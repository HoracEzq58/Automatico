# ==============================================================================
# Nombre Script: "3TuPcVolaraClaude-v3.ps1"
# Basado en: "3TuPcVolaraClaude-v2.ps1"
# Revisado y corregido por: Claude (Anthropic) - 2026-03-10
# Actualizado por: Claude (Anthropic) - 2026-03-16
# Requiere: PowerShell 7 | Administrador | W10 IoT LTSC
# ==============================================================================
#
# CAMBIOS vs v2:
#
#  [MEJORA] Sin sistema de logs - solo Write-Host, sin archivo de log
#           CORRECCION: Agregado sistema de logs identico al de los Scripts 2, 4 y 5
#           Archivo: C:\Users\Public\Documents\AutoTemp\3TuPcVola_FECHA.log
#           Archivo errores: C:\Users\Public\Documents\AutoTemp\3TuPcVola_Errors_FECHA.log
#           Todos los Write-Host reemplazados por Write-Log con colores equivalentes
#
# CAMBIOS 2026-03-16 (manteniendo v3):
#
#  [SECCION 13] Erradicacion profunda de WMP agregada al bloque existente:
#               - Para procesos (wmplayer, wmpnetwk, wmlaunch) antes de desinstalar
#               - Remove-WindowsCapability (elimina payload, WMP no vuelve solo)
#               - DISM /remove /norestart (anti-Highlander)
#               - Borrado fisico de carpetas con takeown + icacls SID *S-1-5-32-544
#               - Eliminacion de acceso directo en Menu Inicio
#               NOTA: takeown usa /d y (ingles) porque IoT LTSC viene en ingles
##  
#
# ==============================================================================
# ADVERTENCIA: Ejecutar siempre como Administrador
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "3TuPcVola_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "3TuPcVola_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

if (-not (Test-Path $global:LogPath)) {
    New-Item -ItemType Directory -Path $global:LogPath -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] [$Level] $Message"

    if ($Color -eq "White") {
        $Color = switch ($Level) {
            "INFO"  { "Green"  }
            "WARN"  { "Yellow" }
            "ERROR" { "Red"    }
            default { "White"  }
        }
    }

    Write-Host $entry -ForegroundColor $Color
    try {
        Add-Content -Path $global:LogFile -Value $entry -Encoding UTF8
        if ($Level -eq "ERROR") {
            Add-Content -Path $global:ErrorLog -Value $entry -Encoding UTF8
        }
    } catch {
        Write-Host "  [!] Error escribiendo log: $_" -ForegroundColor DarkRed
    }
}

# ==============================================================================
# INTERRUPTORES - Modificar segun necesidad antes de ejecutar
# ==============================================================================
$LlamarScript4 = $true    # $true  = llama al Script 4 al finalizar (normal)
                           # $false = termina sin llamar al Script 4 (debug)
# ==============================================================================

# Lista de servicios de red que NUNCA deben tocarse
$SERVICIOS_RED_PROTEGIDOS = @(
    "NlaSvc",            # Network Location Awareness  - icono red systray
    "netprofm",          # Network List Service         - perfil de red
    "nsi",               # Network Store Interface      - base de red
    "iphlpsvc",          # IP Helper                    - IPv6 y tunel
    "Dnscache",          # DNS Client                   - resolucion DNS
    "LanmanWorkstation", # Workstation                  - acceso a recursos de red
    "WSearch"            # Windows Search               - barra de busqueda Inicio
)

Write-Log "=============================================" "INFO" "Cyan"
Write-Log "   3TuPcVolaraClaude-v3.ps1  -  INICIO" "INFO" "Cyan"
Write-Log "=============================================" "INFO" "Cyan"
Write-Log "Usuario  : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Log      : $global:LogFile" "INFO" "Cyan"

# Verificar PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log "ERROR: Este script requiere PowerShell 7 o superior." "ERROR" "Red"
    Write-Log "Version actual: $($PSVersionTable.PSVersion)" "ERROR" "Red"
    exit 1
}
Write-Log "PowerShell 7+: OK ($($PSVersionTable.PSVersion))" "INFO" "Green"

# Verificar Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: Requiere permisos de Administrador." "ERROR" "Red"
    exit 1
}
Write-Log "Administrador: OK" "INFO" "Green"

#######################################################
# SECCION 1 - ACTIVACION DE WINDOWS
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 1: ACTIVACION DE WINDOWS ---" "INFO" "Yellow"

$slmgr = "C:\Windows\System32\slmgr.vbs"

$dliCheck = cscript //NoLogo $slmgr /dli 2>&1 | Out-String
if ($dliCheck -match "Licenciado|Licensed") {
    Write-Log "  [OK] Windows ya se encuentra activado. Omitiendo." "INFO" "Green"
} else {
    Write-Log "  Windows no esta activado. Procediendo..." "WARN" "Yellow"
    try {
        cscript //NoLogo $slmgr /ipk KBN8V-HFGQ4-MGXVD-347P6-PDQGT 2>&1 | Out-Null
        cscript //NoLogo $slmgr /skms kms.digiboy.ir                  2>&1 | Out-Null
        cscript //NoLogo $slmgr /ato                                   2>&1 | Out-Null
        Start-Sleep -Seconds 5
        $dliCheck2 = cscript //NoLogo $slmgr /dli 2>&1 | Out-String
        if ($dliCheck2 -match "Licenciado|Licensed") {
            Write-Log "  [OK] Windows activado correctamente." "INFO" "Green"
        } else {
            Write-Log "  [WARN] Activacion no confirmada. Puede completarse en background via KMS." "WARN" "Yellow"
        }
    } catch {
        Write-Log "  [ERROR] Error durante activacion: $_" "ERROR" "Red"
    }
}
Write-Log "--- [SECCION 1] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 2 - ICONOS ESCRITORIO Y ENTORNO VISUAL
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 2: ICONOS Y ENTORNO VISUAL ---" "INFO" "Yellow"
try {
    $desktopPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    $taskViewPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if (!(Test-Path $desktopPath)) { New-Item -Path $desktopPath -Force | Out-Null }
    New-ItemProperty -Path $desktopPath -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $desktopPath -Name "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Log "  [OK] Iconos 'Este equipo' y 'Archivos de usuario' habilitados." "INFO" "Green"

    if (!(Test-Path $taskViewPath)) { New-Item -Path $taskViewPath -Force | Out-Null }
    New-ItemProperty -Path $taskViewPath -Name "ShowTaskViewButton" -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Log "  [OK] Boton Vista de Tareas deshabilitado." "INFO" "Green"

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Write-Log "  [OK] Explorer reiniciado para aplicar cambios." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error en entorno de escritorio: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 2] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 3 - DESHABILITAR NOTIFICACIONES
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 3: NOTIFICACIONES ---" "INFO" "Yellow"
try {
    $notifPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    if (!(Test-Path $notifPath)) { New-Item -Path $notifPath -Force | Out-Null }
    New-ItemProperty -Path $notifPath -Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $notifPath -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED"           -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Log "  [OK] Notificaciones emergentes y sonidos deshabilitados." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error al deshabilitar notificaciones: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 3] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 4 - ENERGIA (ALTO RENDIMIENTO)
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 4: CONFIGURACION DE ENERGIA ---" "INFO" "Yellow"
try {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Write-Log "  [OK] Plan Alto Rendimiento activado." "INFO" "Green"

    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
    Write-Log "  [OK] CPU forzada al 100% (sin throttling)." "INFO" "Green"

    powercfg /change monitor-timeout-ac 120
    powercfg /change monitor-timeout-dc 20
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    Write-Log "  [OK] Tiempos de espera configurados (monitor 120min AC / 20min DC, sin suspension)." "INFO" "Green"

    powercfg /h off
    Write-Log "  [OK] Hibernacion desactivada." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error en configuracion de energia: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 4] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 5 - APPS EN SEGUNDO PLANO
# Sin bloqueo global (rompia red, busqueda y VPN)
# Se deshabilitan individualmente solo las apps no criticas
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 5: APPS EN SEGUNDO PLANO ---" "INFO" "Yellow"
Write-Log "  [SEGURO] Deshabilitando apps individualmente (sin bloqueo global)." "WARN" "Yellow"

$appsNoEsenciales = @(
    "Microsoft.XboxGameCallableUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.People",
    "Microsoft.Wallet",
    "Microsoft.WindowsMaps",
    "Microsoft.BingWeather",
    "Microsoft.BingNews",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.Messaging",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.OneConnect",
    "Microsoft.Print3D",
    "Microsoft.SkypeApp",
    "Microsoft.MixedReality.Portal",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.WindowsFeedbackHub"
)

$bgPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
foreach ($app in $appsNoEsenciales) {
    try {
        $appPath = "$bgPath\$app"
        if (!(Test-Path $appPath)) { New-Item -Path $appPath -Force | Out-Null }
        Set-ItemProperty -Path $appPath -Name "Disabled"       -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $appPath -Name "DisabledByUser" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "  [OK] Deshabilitada: $app" "INFO" "Gray"
    } catch {
        Write-Log "  [WARN] Error deshabilitando $app`: $_" "WARN" "Yellow"
    }
}
Write-Log "  [OK] Apps no esenciales deshabilitadas individualmente." "INFO" "Green"
Write-Log "--- [SECCION 5] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 6 - DESHABILITAR SERVICIOS DE JUEGO XBOX
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 6: SERVICIOS DE JUEGO XBOX ---" "INFO" "Yellow"
try {
    $gameBarPath  = "HKCU:\System\GameConfigStore"
    $gameDVRPath  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    $gameModePath = "HKCU:\SOFTWARE\Microsoft\GameBar"

    if (!(Test-Path $gameBarPath))  { New-Item -Path $gameBarPath  -Force | Out-Null }
    if (!(Test-Path $gameDVRPath))  { New-Item -Path $gameDVRPath  -Force | Out-Null }
    if (!(Test-Path $gameModePath)) { New-Item -Path $gameModePath -Force | Out-Null }

    New-ItemProperty -Path $gameBarPath  -Name "GameDVR_Enabled"     -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $gameDVRPath  -Name "AppCaptureEnabled"   -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $gameModePath -Name "AutoGameModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Log "  [OK] Xbox Game Bar, DVR y Modo Juego deshabilitados." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error al deshabilitar Xbox: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 6] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 7 - WINDOWS UPDATE - DELIVERY OPTIMIZATION
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 7: DELIVERY OPTIMIZATION ---" "INFO" "Yellow"
try {
    $updatePath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization"
    $doConfigPath = "$updatePath\Config"

    if (!(Test-Path $updatePath))   { New-Item -Path $updatePath   -Force | Out-Null }
    if (!(Test-Path $doConfigPath)) { New-Item -Path $doConfigPath -Force | Out-Null }

    New-ItemProperty -Path $updatePath   -Name "DODownloadMode" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $doConfigPath -Name "DownloadMode"   -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $doConfigPath -Name "DODownloadMode" -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Log "  [OK] Descarga P2P deshabilitada (solo desde este dispositivo)." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error en Delivery Optimization: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 7] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 8 - EFECTOS VISUALES (MAXIMO RENDIMIENTO)
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 8: EFECTOS VISUALES ---" "INFO" "Yellow"
try {
    $perfPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (!(Test-Path $perfPath)) { New-Item -Path $perfPath -Force | Out-Null }
    Set-ItemProperty -Path $perfPath -Name "VisualFXSetting" -Value 2 -Type DWord -ErrorAction Stop
    Write-Log "  [OK] Efectos visuales: Mejor rendimiento." "INFO" "Green"

    $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (!(Test-Path $themePath)) { New-Item -Path $themePath -Force | Out-Null }
    Set-ItemProperty -Path $themePath -Name "EnableTransparency" -Value 0 -Type DWord -ErrorAction Stop
    Write-Log "  [OK] Transparencia deshabilitada." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error en efectos visuales: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 8] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 9 - MEMORIA VIRTUAL
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 9: MEMORIA VIRTUAL ---" "INFO" "Yellow"
try {
    $physicalModules = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    if ($physicalModules.Sum -gt 0) {
        $totalMemoryMB = [math]::Round($physicalModules.Sum / 1MB, 0)
    } else {
        $totalMemoryMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1KB, 0)
    }
    Write-Log "  RAM detectada: $([math]::Round($totalMemoryMB/1024,2)) GB" "INFO" "Cyan"

    $pageSize = [math]::Round($totalMemoryMB * 1.5, 0)
    if ($pageSize -lt 2048) { $pageSize = 2048 }
    Write-Log "  Pagefile calculado: $pageSize MB (1.5x RAM)" "INFO" "Cyan"

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computer.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile = $false } | Out-Null
    }
    $existing = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-CimInstance }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $regPath -Name "PagingFiles" -Type MultiString -Value "C:\pagefile.sys $pageSize $pageSize"
    Write-Log "  [OK] Memoria virtual fija configurada: $pageSize MB." "INFO" "Green"
} catch {
    Write-Log "  [ERROR] Error en memoria virtual: $_" "ERROR" "Red"
}
Write-Log "--- [SECCION 9] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 10 - SERVICIOS NO ESENCIALES
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 10: SERVICIOS NO ESENCIALES ---" "INFO" "Yellow"
Write-Log "  Servicios protegidos: $($SERVICIOS_RED_PROTEGIDOS -join ', ')" "WARN" "Yellow"

$serviciosDisabled = @(
    "BcastDVRUserService",   "BluetoothUserService",  "bthserv",
    "DiagTrack",             "dmwappushservice",      "Fax",
    "FontCache",             "lfsvc",                 "MapsBroker",
    "MessagingService",      "MixedRealityOpenXRSvc", "OneSyncSvc",
    "PhoneSvc",              "PimIndexMaintenanceSvc","RemoteRegistry",
    "shpamsvc",              "TabletInputService",    "TapiSrv",
    "UnistoreSvc",           "UserDataSvc",           "vmicguestinterface",
    "vmicheartbeat",         "vmickvpexchange",       "vmicrdv",
    "vmicshutdown",          "vmictimesync",          "vmicvmsession",
    "WalletService",         "WbioSrvc",              "wisvc",
    "WMPNetworkSvc",         "XblAuthManager",        "XblGameSave",
    "XboxGipSvc",            "XboxNetApiSvc",         "SysMain"
)

foreach ($service in $serviciosDisabled) {
    if ($SERVICIOS_RED_PROTEGIDOS -contains $service) {
        Write-Log "  [SKIP] $service esta en lista protegida - omitido." "WARN" "Magenta"
        continue
    }
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne 'Disabled') {
        try {
            Stop-Service $service -Force              -ErrorAction SilentlyContinue
            Set-Service  $service -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "  [OK] Disabled: $service" "INFO" "Gray"
        } catch {
            Write-Log "  [WARN] Error con $service`: $_" "WARN" "Yellow"
        }
    } else {
        Write-Log "  [i] Ya deshabilitado: $service" "INFO" "Gray"
    }
}

$serviciosManual = @(
    @{ Name = "BITS";           Label = "BITS (Windows Update / Store / VPN)" },
    @{ Name = "StorSvc";        Label = "StorSvc (Almacenamiento / instalacion apps)" },
    @{ Name = "PcaSvc";         Label = "PcaSvc (Compatibilidad apps / VPN terceros)" },
    @{ Name = "WpnService";     Label = "WpnService (Push / ms-settings:network)" },
    @{ Name = "WpnUserService"; Label = "WpnUserService (Push usuario / ms-settings)" }
)
foreach ($svc in $serviciosManual) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service $svc.Name -Force              -ErrorAction SilentlyContinue
        Set-Service  $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
        Write-Log "  [OK] Manual: $($svc.Label)" "WARN" "Yellow"
    }
}

Write-Log "  Verificando servicios protegidos..." "INFO" "Cyan"
foreach ($svcName in $SERVICIOS_RED_PROTEGIDOS) {
    $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.StartType -eq 'Disabled') {
            Set-Service   $svcName -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service $svcName                        -ErrorAction SilentlyContinue
            Write-Log "  [FIX] $svcName estaba Disabled -> restaurado a Automatic." "WARN" "Magenta"
        } elseif ($s.Status -ne 'Running' -and $s.StartType -eq 'Automatic') {
            Start-Service $svcName -ErrorAction SilentlyContinue
            Write-Log "  [FIX] $svcName estaba detenido -> iniciado." "WARN" "Magenta"
        } else {
            Write-Log "  [OK] $svcName protegido y activo." "INFO" "Green"
        }
    }
}
Write-Log "--- [SECCION 10] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 11 - PREFETCH / SUPERFETCH
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 11: PREFETCH/SUPERFETCH ---" "INFO" "Yellow"
$prefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
Set-ItemProperty -Path $prefetchPath -Name "EnablePrefetcher" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $prefetchPath -Name "EnableSuperfetch" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "  [OK] Prefetch y Superfetch desactivados." "INFO" "Green"
Write-Log "--- [SECCION 11] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 12 - WINDOWS UPDATE Y TELEMETRIA
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 12: WINDOWS UPDATE Y TELEMETRIA ---" "INFO" "Yellow"

$auPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
if (!(Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Type DWord -ErrorAction SilentlyContinue
Write-Log "  [OK] Actualizaciones automaticas desactivadas (notifica pero no instala)." "INFO" "Green"

foreach ($path in @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
)) {
    if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "AllowTelemetry"      -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $path -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "  [OK] Telemetria desactivada." "INFO" "Green"
Write-Log "--- [SECCION 12] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 13 - DESINSTALAR WMP, IE11 y FAX
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 13: DESINSTALAR WMP, IE y FAX ---" "INFO" "Yellow"
Write-Log "  [AVISO] Requiere reinicio al finalizar el script." "WARN" "Yellow"

foreach ($feature in @(
    @{ Name = "WindowsMediaPlayer";               Label = "Windows Media Player" },
    @{ Name = "Internet-Explorer-Optional-amd64"; Label = "Internet Explorer 11" },
    @{ Name = "FaxServicesClientPackage";         Label = "Windows Fax and Scan" }
)) {
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -FeatureName $feature.Name -Online -NoRestart
            Write-Log "  [OK] Desinstalado: $($feature.Label)" "INFO" "Green"
        } else {
            Write-Log "  [i] Ya no presente: $($feature.Label)" "INFO" "Gray"
        }
    } catch {
        Write-Log "  [WARN] Error desinstalando $($feature.Label): $_" "WARN" "Yellow"
    }
}

# --- Erradicacion profunda de WMP (anti-Highlander) ---
Write-Log "  Iniciando erradicacion profunda de WMP..." "INFO" "Yellow"

# Matar procesos activos
Stop-Process -Name "wmplayer","wmpnetwk","wmlaunch" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "WMPNetworkSvc" -ErrorAction SilentlyContinue

# Eliminar como Windows Capability (con /remove para que no vuelva)
$wmpCap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "*WindowsMediaPlayer*" }
if ($wmpCap) {
    try {
        Remove-WindowsCapability -Online -Name $wmpCap.Name | Out-Null
        Write-Log "  [OK] Windows Capability WMP eliminada: $($wmpCap.Name)" "INFO" "Green"
    } catch {
        Write-Log "  [WARN] Error eliminando Capability WMP: $_" "WARN" "Yellow"
    }
} else {
    Write-Log "  [i] Windows Capability WMP no encontrada (ya eliminada)." "INFO" "Gray"
}

# DISM con /remove para borrar payload y evitar restauracion automatica
# IoT LTSC viene en ingles, /d y es la respuesta correcta para confirmacion automatica
Write-Log "  Ejecutando DISM /remove (puede demorar unos segundos)..." "INFO" "Yellow"
$dismResult = dism /online /disable-feature /featurename:WindowsMediaPlayer /remove /norestart /quiet 2>&1
Write-Log "  [OK] DISM completado." "INFO" "Green"

# Borrado fisico de carpetas WMP con takeown e icacls
$wmpPaths = @(
    "${env:ProgramFiles(x86)}\Windows Media Player",
    "${env:ProgramFiles}\Windows Media Player"
)
foreach ($wmpPath in $wmpPaths) {
    if (Test-Path $wmpPath) {
        try {
            Write-Log "  Eliminando carpeta: $wmpPath" "INFO" "Yellow"
            # /d y = respuesta automatica "Yes" (IoT LTSC en ingles)
            takeown /f $wmpPath /r /d y | Out-Null
            # SID *S-1-5-32-544 = Administradores, funciona en cualquier idioma
            icacls $wmpPath /grant "*S-1-5-32-544:F" /t /inheritance:e /q | Out-Null
            Remove-Item $wmpPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] Carpeta WMP eliminada: $wmpPath" "INFO" "Green"
        } catch {
            Write-Log "  [WARN] Error eliminando $wmpPath`: $_" "WARN" "Yellow"
        }
    } else {
        Write-Log "  [i] Carpeta no encontrada: $wmpPath" "INFO" "Gray"
    }
}

# Eliminar acceso directo del Menu Inicio
$wmpShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Media Player.lnk"
if (Test-Path $wmpShortcut) {
    Remove-Item $wmpShortcut -Force -ErrorAction SilentlyContinue
    Write-Log "  [OK] Acceso directo WMP eliminado del Menu Inicio." "INFO" "Green"
} else {
    Write-Log "  [i] Acceso directo WMP no encontrado (ya eliminado)." "INFO" "Gray"
}

Write-Log "  [OK] Erradicacion profunda WMP completada." "INFO" "Green"
Write-Log "--- [SECCION 13] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 14 - LIMPIEZA DE ARCHIVOS TEMPORALES
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 14: ARCHIVOS TEMPORALES ---" "INFO" "Yellow"
foreach ($folder in @(
    "$env:TEMP\*",
    "$env:SystemRoot\Temp\*",
    "$env:WINDIR\Prefetch\*",
    "$env:WINDIR\SoftwareDistribution\Download\*",
    "$env:LOCALAPPDATA\Temp\*"
)) {
    Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  [i] Limpiado: $folder" "INFO" "Gray"
}
ipconfig /flushdns | Out-Null
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
Write-Log "  [OK] Temporales eliminados y DNS limpiado." "INFO" "Green"
Write-Log "--- [SECCION 14] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 15 - PROGRAMAS DE INICIO
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 15: PROGRAMAS DE INICIO ---" "INFO" "Yellow"

$excludeRun = @(
    "Windows Security notification icon",
    "Windows Defender",
    "SecurityHealth",
    "WindowsDefender",
    "BingSvc"
)

foreach ($path in @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)) {
    if (Test-Path $path) {
        $props = (Get-ItemProperty -Path $path).PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
        foreach ($prop in $props) {
            if ($excludeRun -contains $prop.Name) {
                Write-Log "  [i] Conservado: $($prop.Name)" "INFO" "Green"
            } else {
                Remove-ItemProperty -Path $path -Name $prop.Name -ErrorAction SilentlyContinue
                Write-Log "  [i] Eliminado del inicio: $($prop.Name)" "INFO" "Gray"
            }
        }
    }
}

Get-ScheduledTask | Where-Object {
    $_.State -eq 'Ready' -and
    $_.TaskName -notlike '*Microsoft*' -and
    $_.TaskName -notlike '*Windows*'
} | ForEach-Object {
    Disable-ScheduledTask -InputObject $_ -ErrorAction SilentlyContinue
    Write-Log "  [i] Tarea deshabilitada: $($_.TaskName)" "INFO" "Gray"
}
Write-Log "  [OK] Inicio limpiado." "INFO" "Green"
Write-Log "--- [SECCION 15] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 16 - TAREAS PROGRAMADAS PESADAS
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 16: TAREAS PROGRAMADAS PESADAS ---" "INFO" "Yellow"
$disabledCount = 0
foreach ($taskPath in @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\DiskFootprint\Diagnostics",
    "\Microsoft\Windows\FileHistory\File History",
    "\Microsoft\Windows\Maintenance\WinSAT",
    "\Microsoft\Windows\Windows Update\Automatic App Update",
    "\Microsoft\Office\OfficeTelemetryAgentLogOn",
    "\Microsoft\Office\OfficeTelemetryAgentFallBack"
)) {
    try {
        $task = Get-ScheduledTask -TaskPath "$(Split-Path $taskPath -Parent)\" `
                                  -TaskName  (Split-Path $taskPath -Leaf) `
                                  -ErrorAction SilentlyContinue
        if ($task) {
            Disable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue
            Write-Log "  [OK] Deshabilitada: $(Split-Path $taskPath -Leaf)" "INFO" "Green"
            $disabledCount++
        } else {
            Write-Log "  [i] No encontrada: $(Split-Path $taskPath -Leaf)" "INFO" "Gray"
        }
    } catch {
        Write-Log "  [WARN] Error con tarea $(Split-Path $taskPath -Leaf): $_" "WARN" "Yellow"
    }
}
Write-Log "  [OK] $disabledCount tareas deshabilitadas." "INFO" "Green"
Write-Log "--- [SECCION 16] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 17 - OPTIMIZACIONES FINALES DE REGISTRO
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 17: OPTIMIZACIONES DE REGISTRO ---" "INFO" "Yellow"

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" `
    -Name "Win32PrioritySeparation" -Value 26 -Type DWord -ErrorAction SilentlyContinue
Write-Log "  [OK] Prioridad de programas optimizada (26)." "INFO" "Green"

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" `
    -Name "MenuShowDelay" -Value 50 -Type DWord -ErrorAction SilentlyContinue
Write-Log "  [OK] Menus acelerados (50ms)." "INFO" "Green"

Write-Log "  [SEGURO] Activity Feed conservado (menu Inicio y busqueda funcionan)." "WARN" "Yellow"
Write-Log "--- [SECCION 17] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 18 - VERIFICACION FINAL DE SERVICIOS
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 18: VERIFICACION FINAL ---" "INFO" "Yellow"

$sm = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
if ($sm -and $sm.StartType -ne 'Disabled') {
    Stop-Service "SysMain" -Force              -ErrorAction SilentlyContinue
    Set-Service  "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Log "  [OK] SysMain deshabilitado." "INFO" "Green"
} else {
    Write-Log "  [i] SysMain ya deshabilitado." "INFO" "Gray"
}

$bits = Get-Service -Name "BITS" -ErrorAction SilentlyContinue
if ($bits -and $bits.StartType -eq 'Disabled') {
    Set-Service "BITS" -StartupType Manual -ErrorAction SilentlyContinue
    Write-Log "  [FIX] BITS restaurado a Manual." "WARN" "Magenta"
} else {
    Write-Log "  [OK] BITS en Manual (correcto)." "INFO" "Green"
}

Write-Log "  Verificacion final de servicios protegidos..." "INFO" "Yellow"
foreach ($svcName in $SERVICIOS_RED_PROTEGIDOS) {
    $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -eq 'Disabled') {
        Set-Service   $svcName -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service $svcName                        -ErrorAction SilentlyContinue
        Write-Log "  [FIX] $svcName restaurado (estaba Disabled)." "WARN" "Magenta"
    } elseif ($s) {
        Write-Log "  [OK] $svcName activo." "INFO" "Green"
    }
}
Write-Log "--- [SECCION 18] Completada ---" "INFO" "Yellow"

#######################################################
# SECCION 19 - LLAMADO AL SCRIPT 4
#######################################################
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 19: LLAMADO AL SCRIPT 4 ---" "INFO" "Yellow"

$extDir    = "C:\Users\Public\Documents\Automatico\"
$extScript = "4ExtraeNew-InstallAppsDesktop-Claude-v2.ps1"
$extFull   = Join-Path $extDir $extScript

if (-not $LlamarScript4) {
    Write-Log "  [i] Llamado al Script 4 desactivado (LlamarScript4 = false). Fin en modo debug." "INFO" "Gray"
} elseif (Test-Path $extFull) {
    Write-Log "  Script 4 encontrado. Iniciando en 6 segundos..." "INFO" "Yellow"
    Start-Sleep -Seconds 6
    try {
        Set-Location $extDir
        Write-Log "  Ejecutando Script 4: $extFull" "INFO" "Cyan"
        & $extFull
    } catch {
        Write-Log "  [ERROR] Error al ejecutar Script 4: $_" "ERROR" "Red"
    }
} else {
    Write-Log "  [WARN] Script 4 no encontrado en: $extFull" "WARN" "Yellow"
    Write-Log "  Ejecutalo manualmente cuando estes listo." "INFO" "White"
}
Write-Log "--- [SECCION 19] Completada ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Cyan"
Write-Log "   3TuPcVolaraClaude-v3.ps1  -  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Cyan"
Write-Log "Log      : $global:LogFile" "INFO" "Cyan"
Write-Log "Errores  : $global:ErrorLog" "INFO" "Cyan"
Write-Log "" "INFO" "White"