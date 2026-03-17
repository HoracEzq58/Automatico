# Script para deshabilitar y finalizar la tarea "ScheduledDefrag"
# Nombre de la tarea a deshabilitar y finalizar
$taskPath = "\Microsoft\Windows\Defrag"
$taskName = "ScheduledDefrag"

try {
    # Verificar si la tarea existe
    $taskExists = Get-ScheduledTask | Where-Object { $_.TaskPath -eq $taskPath + "\" -and $_.TaskName -eq $taskName }

    if ($taskExists) {
        Write-Host "La tarea '$taskName' existe. Procediendo a finalizar y deshabilitar..." -ForegroundColor Green
        
        # Finalizar la tarea si está en ejecución
        Stop-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        Write-Host "Tarea '$taskName' finalizada." -ForegroundColor Yellow

        # Deshabilitar la tarea
        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName
        Write-Host "Tarea '$taskName' deshabilitada." -ForegroundColor Green
    } else {
        Write-Host "La tarea '$taskName' no existe o ya está deshabilitada." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Ocurrió un error: $_" -ForegroundColor Red
}
# Lista de servicios a deshabilitar
$services = @(
    "XblAuthManager",           # Administración de Autenticación de Xbox Live
    "WpcMonSvc",                # Control Parental
    "DiagTrack",                # Experiencia del usuario y Telemetría
	"MicrosoftEdgeElevationService", # Microsoft Edge Elevation Service
    "edgeupdate",               # Microsoft Edge Update Service
    "edgeupdatem",              # Microsoft Edge Update Service (modo máquina)
    "Fax",                      # Fax
    "vmicguestinterface",       # Interfaz de servicio invitado de Hyper-V
    "vmicshutdown",             # Servicio de Cierre de invitado de Hyper-V
    "vmickvpexchange",          # Servicio de Intercambio de Datos de Hyper-V
    "vmicheartbeat",            # Servicio de latido de Hyper-V
    "vmictimesync",             # Servicio de sincronización de Hora de Hyper-V
    "vmicrdv",                  # Serv de virt de escritorio remoto de Hyper-V
    "vmicvmsession",            # Servicio PowerShell Direct de Hyper-V
    "XblGameSave",              # Partida guardada en Xbox live
    "WbioSrvc",                 # Servicio Biométrico de Windows
    "bthserv",                  # Servicio de Compatibilidad con BlueTooth
    "lfsvc",                    # Servicio de Geolocalización
    "XboxNetApiSvc",            # Servicio de Red de Xbox live
    "wisvc",                    # Servicio de Windows Insider
    "PhoneSvc",                 # Servicio Telefónico
    "SysMain",                  # SysMain (Superfetch)
    "TapiSrv",                  # Telefonía
    "XboxGipSvc",               # Xbox accesory mag service
    "XboxLiveAuthManager"       # Xbox live
)

# Función para deshabilitar un servicio
function Disable-Service {
    param (
        [string]$ServiceName
    )
    try {
        # Detener el servicio si está en ejecución
        Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
        # Configurar el inicio en deshabilitado
        Set-Service -Name $ServiceName -StartupType Disabled
        Write-Host "Servicio '$ServiceName' deshabilitado exitosamente." -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo deshabilitar el servicio '$ServiceName'. Verifica si el nombre es correcto o si tienes los permisos necesarios."
    }
}

# Deshabilitar los servicios
foreach ($service in $services) {
    Disable-Service -ServiceName $service
}

Write-Host "Todos los servicios especificados han sido procesados." -ForegroundColor Cyan

# Lista de servicios a configurar
$servicesToConfigure = @(
    @{Name = "HomeGroupListener"; StartupType = "Manual"},
    @{Name = "HomeGroupProvider"; StartupType = "Manual"},
    @{Name = "AJRouter"; StartupType = "Disabled"},
    @{Name = "ALG"; StartupType = "Manual"},
    @{Name = "AppIDSvc"; StartupType = "Manual"},
    @{Name = "AppMgmt"; StartupType = "Manual"},
    @{Name = "AppReadiness"; StartupType = "Manual"},
    @{Name = "AppVClient"; StartupType = "Disabled"},
    @{Name = "AppXSvc"; StartupType = "Manual"},
    @{Name = "Appinfo"; StartupType = "Manual"},
    @{Name = "AssignedAccessManagerSvc"; StartupType = "Disabled"},
    @{Name = "AudioEndpointBuilder"; StartupType = "Automatic"},
    @{Name = "AudioSrv"; StartupType = "Automatic"},
    @{Name = "Audiosrv"; StartupType = "Automatic"},
    @{Name = "AxInstSV"; StartupType = "Manual"},
    @{Name = "BDESVC"; StartupType = "Manual"},
    @{Name = "BFE"; StartupType = "Automatic"},
    @{Name = "BITS"; StartupType = "Automatic"},
    @{Name = "BTAGService"; StartupType = "Manual"},
    @{Name = "BcastDVRUserService_*"; StartupType = "Manual"},
    @{Name = "BluetoothUserService_*"; StartupType = "Manual"},
    @{Name = "BrokerInfrastructure"; StartupType = "Automatic"},
    @{Name = "Browser"; StartupType = "Manual"},
    @{Name = "BthHFSrv"; StartupType = "Automatic"},
    @{Name = "CDPSvc"; StartupType = "Manual"},
    @{Name = "CDPUserSvc_*"; StartupType = "Automatic"},
    @{Name = "COMSysApp"; StartupType = "Manual"},
    @{Name = "CaptureService_*"; StartupType = "Manual"},
    @{Name = "ClipSVC"; StartupType = "Manual"},
    @{Name = "ConsentUxUserSvc_*"; StartupType = "Manual"},
    @{Name = "CoreMessagingRegistrar"; StartupType = "Automatic"},
    @{Name = "CredentialEnrollmentManagerUserSvc_*"; StartupType = "Manual"},
    @{Name = "CryptSvc"; StartupType = "Automatic"},
    @{Name = "CscService"; StartupType = "Manual"},
    @{Name = "DPS"; StartupType = "Automatic"},
    @{Name = "DcomLaunch"; StartupType = "Automatic"},
    @{Name = "DcpSvc"; StartupType = "Manual"},
    @{Name = "DevQueryBroker"; StartupType = "Manual"},
    @{Name = "DeviceAssociationBrokerSvc_*"; StartupType = "Manual"},
    @{Name = "DeviceAssociationService"; StartupType = "Manual"},
    @{Name = "DeviceInstall"; StartupType = "Manual"},
    @{Name = "DevicePickerUserSvc_*"; StartupType = "Manual"},
    @{Name = "DevicesFlowUserSvc_*"; StartupType = "Manual"},
    @{Name = "Dhcp"; StartupType = "Automatic"},
    @{Name = "DialogBlockingService"; StartupType = "Disabled"},
    @{Name = "DispBrokerDesktopSvc"; StartupType = "Automatic"},
    @{Name = "DisplayEnhancementService"; StartupType = "Manual"},
    @{Name = "DmEnrollmentSvc"; StartupType = "Manual"},
    @{Name = "Dnscache"; StartupType = "Automatic"},
    @{Name = "DsSvc"; StartupType = "Manual"},
    @{Name = "DsmSvc"; StartupType = "Manual"},
    @{Name = "DusmSvc"; StartupType = "Automatic"},
    @{Name = "EFS"; StartupType = "Manual"},
    @{Name = "EapHost"; StartupType = "Manual"},
    @{Name = "EntAppSvc"; StartupType = "Manual"},
    @{Name = "EventLog"; StartupType = "Automatic"},
    @{Name = "EventSystem"; StartupType = "Automatic"},
    @{Name = "FDResPub"; StartupType = "Manual"},
    @{Name = "FontCache"; StartupType = "Automatic"},
    @{Name = "FrameServer"; StartupType = "Manual"},
    @{Name = "FrameServerMonitor"; StartupType = "Manual"},
    @{Name = "GraphicsPerfSvc"; StartupType = "Manual"},
    @{Name = "HvHost"; StartupType = "Manual"},
    @{Name = "IEEtwCollectorService"; StartupType = "Manual"},
    @{Name = "IKEEXT"; StartupType = "Manual"},
    @{Name = "InstallService"; StartupType = "Manual"},
    @{Name = "InventorySvc"; StartupType = "Manual"},
    @{Name = "IpxlatCfgSvc"; StartupType = "Manual"},
    @{Name = "KtmRm"; StartupType = "Manual"},
    @{Name = "LSM"; StartupType = "Automatic"},
    @{Name = "LanmanServer"; StartupType = "Automatic"},
    @{Name = "LanmanWorkstation"; StartupType = "Automatic"},
    @{Name = "LicenseManager"; StartupType = "Manual"},
    @{Name = "LxpSvc"; StartupType = "Manual"},
    @{Name = "MSDTC"; StartupType = "Manual"},
    @{Name = "MapsBroker"; StartupType = "AutomaticDelayedStart"},
    @{Name = "McpManagementService"; StartupType = "Manual"},
    @{Name = "MessagingService_*"; StartupType = "Manual"},
    @{Name = "MixedRealityOpenXRSvc"; StartupType = "Manual"},
    @{Name = "MpsSvc"; StartupType = "Automatic"},
    @{Name = "MsKeyboardFilter"; StartupType = "Manual"},
    @{Name = "NPSMSvc_*"; StartupType = "Manual"},
    @{Name = "NaturalAuthentication"; StartupType = "Manual"},
    @{Name = "NcaSvc"; StartupType = "Manual"},
    @{Name = "NcbService"; StartupType = "Manual"},
    @{Name = "NcdAutoSetup"; StartupType = "Manual"},
    @{Name = "NetSetupSvc"; StartupType = "Manual"},
    @{Name = "NetTcpPortSharing"; StartupType = "Disabled"},
    @{Name = "Netman"; StartupType = "Manual"},
    @{Name = "NgcCtnrSvc"; StartupType = "Manual"},
    @{Name = "NgcSvc"; StartupType = "Manual"},
    @{Name = "OneSyncSvc_*"; StartupType = "Automatic"},
    @{Name = "P9RdrService_*"; StartupType = "Manual"},
    @{Name = "PNRPAutoReg"; StartupType = "Manual"},
    @{Name = "PNRPsvc"; StartupType = "Manual"},
    @{Name = "PenService_*"; StartupType = "Manual"},
    @{Name = "PerfHost"; StartupType = "Manual"},
    @{Name = "PimIndexMaintenanceSvc_*"; StartupType = "Manual"},
    @{Name = "PlugPlay"; StartupType = "Manual"},
    @{Name = "PolicyAgent"; StartupType = "Manual"},
    @{Name = "Power"; StartupType = "Automatic"},
    @{Name = "PrintNotify"; StartupType = "Manual"},
    @{Name = "PrintWorkflowUserSvc_*"; StartupType = "Manual"},
    @{Name = "ProfSvc"; StartupType = "Automatic"},
    @{Name = "PushToInstall"; StartupType = "Manual"},
    @{Name = "QWAVE"; StartupType = "Manual"},
    @{Name = "RasAuto"; StartupType = "Manual"},
    @{Name = "RemoteAccess"; StartupType = "Disabled"},
    @{Name = "RemoteRegistry"; StartupType = "Disabled"},
    @{Name = "RetailDemo"; StartupType = "Manual"},
    @{Name = "RmSvc"; StartupType = "Manual"},
    @{Name = "RpcEptMapper"; StartupType = "Automatic"},
    @{Name = "RpcLocator"; StartupType = "Manual"},
    @{Name = "RpcSs"; StartupType = "Automatic"},
    @{Name = "SCPolicySvc"; StartupType = "Manual"},
    @{Name = "SCardSvr"; StartupType = "Manual"},
    @{Name = "SDRSVC"; StartupType = "Manual"},
    @{Name = "SEMgrSvc"; StartupType = "Manual"},
    @{Name = "SENS"; StartupType = "Automatic"},
    @{Name = "SSDPSRV"; StartupType = "Manual"},
    @{Name = "SamSs"; StartupType = "Automatic"},
    @{Name = "ScDeviceEnum"; StartupType = "Manual"},
    @{Name = "Schedule"; StartupType = "Automatic"},
    @{Name = "SecurityHealthService"; StartupType = "Manual"},
    @{Name = "Sense"; StartupType = "Manual"},
    @{Name = "SensorDataService"; StartupType = "Manual"},
    @{Name = "SensorService"; StartupType = "Manual"},
    @{Name = "SensrSvc"; StartupType = "Manual"},
    @{Name = "SessionEnv"; StartupType = "Manual"},
    @{Name = "SgrmBroker"; StartupType = "Automatic"},
    @{Name = "SharedAccess"; StartupType = "Manual"},
    @{Name = "SharedRealitySvc"; StartupType = "Manual"},
    @{Name = "ShellHWDetection"; StartupType = "Automatic"},
    @{Name = "SmsRouter"; StartupType = "Manual"},
    @{Name = "Spooler"; StartupType = "Automatic"},
    @{Name = "SstpSvc"; StartupType = "Manual"},
    @{Name = "StiSvc"; StartupType = "Manual"},
    @{Name = "StorSvc"; StartupType = "Manual"},
    @{Name = "SystemEventsBroker"; StartupType = "Automatic"},
    @{Name = "TabletInputService"; StartupType = "Manual"},
    @{Name = "TextInputManagementService"; StartupType = "Manual"},
    @{Name = "Themes"; StartupType = "Automatic"},
    @{Name = "TieringEngineService"; StartupType = "Manual"},
    @{Name = "TimeBroker"; StartupType = "Manual"},
    @{Name = "TimeBrokerSvc"; StartupType = "Manual"},
    @{Name = "TokenBroker"; StartupType = "Manual"},
    @{Name = "TrkWks"; StartupType = "Automatic"},
    @{Name = "TroubleshootingSvc"; StartupType = "Manual"},
    @{Name = "TrustedInstaller"; StartupType = "Manual"},
    @{Name = "UI0Detect"; StartupType = "Manual"},
    @{Name = "UdkUserSvc_*"; StartupType = "Manual"},
    @{Name = "UevAgentService"; StartupType = "Disabled"},
    @{Name = "UmRdpService"; StartupType = "Manual"},
    @{Name = "UnistoreSvc_*"; StartupType = "Manual"},
    @{Name = "UserDataSvc_*"; StartupType = "Manual"},
    @{Name = "UserManager"; StartupType = "Automatic"},
    @{Name = "UsoSvc"; StartupType = "Manual"},
    @{Name = "VGAuthService"; StartupType = "Automatic"},
    @{Name = "VMTools"; StartupType = "Automatic"},
    @{Name = "VSS"; StartupType = "Manual"},
    @{Name = "VacSvc"; StartupType = "Manual"},
    @{Name = "W32Time"; StartupType = "Manual"},
    @{Name = "WEPHOSTSVC"; StartupType = "Manual"},
    @{Name = "WFDSConMgrSvc"; StartupType = "Manual"},
    @{Name = "WMPNetworkSvc"; StartupType = "Manual"},
    @{Name = "WManSvc"; StartupType = "Manual"},
    @{Name = "WPDBusEnum"; StartupType = "Manual"},
    @{Name = "WSService"; StartupType = "Manual"},
    @{Name = "WaaSMedicSvc"; StartupType = "Manual"},
    @{Name = "WalletService"; StartupType = "Manual"},
    @{Name = "WarpJITSvc"; StartupType = "Manual"},
    @{Name = "Wcmsvc"; StartupType = "Automatic"},
    @{Name = "WcsPlugInService"; StartupType = "Manual"},
    @{Name = "WdNisSvc"; StartupType = "Manual"},
    @{Name = "WdiServiceHost"; StartupType = "Manual"},
    @{Name = "WdiSystemHost"; StartupType = "Manual"},
    @{Name = "WebClient"; StartupType = "Manual"},
    @{Name = "Wecsvc"; StartupType = "Manual"},
    @{Name = "WerSvc"; StartupType = "Manual"},
    @{Name = "WiaRpc"; StartupType = "Manual"},
    @{Name = "WinDefend"; StartupType = "Automatic"},
    @{Name = "WinHttpAutoProxySvc"; StartupType = "Manual"},
    @{Name = "WinRM"; StartupType = "Manual"},
    @{Name = "Winmgmt"; StartupType = "Automatic"},
    @{Name = "WlanSvc"; StartupType = "Automatic"},
    @{Name = "WpnService"; StartupType = "Manual"},
    @{Name = "WpnUserService_*"; StartupType = "Automatic"},
    @{Name = "autotimesvc"; StartupType = "Manual"},
    @{Name = "camsvc"; StartupType = "Manual"},
    @{Name = "cloudidsvc"; StartupType = "Manual"},
    @{Name = "dcsvc"; StartupType = "Manual"},
    @{Name = "defragsvc"; StartupType = "Manual"},
    @{Name = "diagnosticshub.standardcollector.service"; StartupType = "Manual"},
    @{Name = "diagsvc"; StartupType = "Manual"},
    @{Name = "dmwappushservice"; StartupType = "Manual"},
    @{Name = "dot3svc"; StartupType = "Manual"},
    @{Name = "edgeupdate"; StartupType = "Manual"},
    @{Name = "edgeupdatem"; StartupType = "Manual"},
    @{Name = "embeddedmode"; StartupType = "Manual"},
    @{Name = "fdPHost"; StartupType = "Manual"},
    @{Name = "fhsvc"; StartupType = "Manual"},
    @{Name = "gpsvc"; StartupType = "Automatic"},
    @{Name = "hidserv"; StartupType = "Manual"},
    @{Name = "icssvc"; StartupType = "Manual"},
    @{Name = "iphlpsvc"; StartupType = "Automatic"},
    @{Name = "lltdsvc"; StartupType = "Manual"},
    @{Name = "lmhosts"; StartupType = "Manual"},
    @{Name = "mpssvc"; StartupType = "Automatic"},
    @{Name = "msiserver"; StartupType = "Manual"},
    @{Name = "netprofm"; StartupType = "Manual"},
    @{Name = "nsi"; StartupType = "Automatic"},
    @{Name = "p2pimsvc"; StartupType = "Manual"},
    @{Name = "p2psvc"; StartupType = "Manual"},
    @{Name = "perceptionsimulation"; StartupType = "Manual"},
    @{Name = "pla"; StartupType = "Manual"},
    @{Name = "seclogon"; StartupType = "Manual"},
    @{Name = "shpamsvc"; StartupType = "Disabled"},
    @{Name = "smphost"; StartupType = "Manual"},
    @{Name = "spectrum"; StartupType = "Manual"},
    @{Name = "sppsvc"; StartupType = "AutomaticDelayedStart"},
    @{Name = "ssh-agent"; StartupType = "Disabled"},
    @{Name = "svsvc"; StartupType = "Manual"},
    @{Name = "swprv"; StartupType = "Manual"},
    @{Name = "tiledatamodelsvc"; StartupType = "Automatic"},
    @{Name = "tzautoupdate"; StartupType = "Disabled"},
    @{Name = "uhssvc"; StartupType = "Disabled"},
    @{Name = "upnphost"; StartupType = "Manual"},
    @{Name = "vds"; StartupType = "Manual"},
    @{Name = "vm3dservice"; StartupType = "Manual"},
    @{Name = "vmicvss"; StartupType = "Manual"},
    @{Name = "vmvss"; StartupType = "Manual"},
    @{Name = "wbengine"; StartupType = "Manual"},
    @{Name = "wcncsvc"; StartupType = "Manual"},
    @{Name = "webthreatdefsvc"; StartupType = "Manual"},
    @{Name = "webthreatdefusersvc_*"; StartupType = "Automatic"},
    @{Name = "wercplsupport"; StartupType = "Manual"},
    @{Name = "wlidsvc"; StartupType = "Manual"},
    @{Name = "wlpasvc"; StartupType = "Manual"},
    @{Name = "wmiApSrv"; StartupType = "Manual"},
    @{Name = "workfolderssvc"; StartupType = "Manual"},
    @{Name = "wscsvc"; StartupType = "AutomaticDelayedStart"},
    @{Name = "wuauserv"; StartupType = "Manual"},
    @{Name = "wudfsvc"; StartupType = "Manual"}
)
# Configurar servicios
foreach ($service in $servicesToConfigure) {
    try {
        $serviceName = $service.Name
        $startupType = $service.StartupType
        Write-Host "Configurando el servicio $serviceName con el tipo de inicio $startupType..."
        Set-Service -Name $serviceName -StartupType $startupType -ErrorAction Stop
        Write-Host "Servicio $serviceName configurado correctamente."
    } catch {
        Write-Host "No se pudo configurar el servicio $serviceName $($_.Exception.Message)"
    }
}
