# AutoRAM-Monitor.ps1
# Servicio NSSM de gestion inteligente de RAM
# TuPcVeloz - v1.0
# Se instala solo en equipos con menos de 8 GB RAM
# El perfil (moderado/agresivo) lo define autoram-config.json

$ConfigPath = "C:\Users\Public\Documents\Automatico\autoram-config.json"
$LogPath    = "C:\Users\Public\Documents\AutoTemp\AutoRAM.log"
$ToolPath   = "C:\Users\Public\Documents\Automatico\Tools\EmptyStandbyList.exe"
$ServiceName = "AutoRAM-TuPcVeloz"

New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

# ------------------------------------
# FUNCIONES
# ------------------------------------

function Write-AutoRamLog($msg) {
    $linea = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $LogPath -Value $linea
    Write-Host $linea
}

function Uninstall-SelfService {
    # 22/09/2026: self-heal. Si el Monitor no puede arrancar (config ausente o
    # invalido) es porque quedo huerfano - la Seccion 19 ya decidio que este
    # equipo no necesita AutoRAM (o el config esta corrupto y no hay forma de
    # auto-repararlo). En vez de solo loguear y salir con exit 1 -lo que hace
    # que nssm lo relance en loop para siempre, como paso 11 dias en
    # DESKTOP-ROMAN con ~30.000 reinicios- se programa la desinstalacion.
    #
    # IMPORTANTE: no se llama "nssm stop" directamente desde este script.
    # nssm agrupa el proceso del servicio (este mismo pwsh.exe) en un job
    # object y al detenerlo mata todo el arbol de procesos, incluidos los
    # hijos que este mismo script lance - el "nssm remove" posterior nunca
    # llegaria a ejecutarse. Por eso se delega en una tarea programada de
    # Windows (fuera del job object de nssm) que corre unos segundos despues,
    # cuando este proceso ya termino por su cuenta via exit 1.
	
    Write-AutoRamLog "  [SELF-HEAL] Programando desinstalacion de servicio huerfano $ServiceName..."
    try {
        $nssmPath = (Get-Command nssm -ErrorAction SilentlyContinue).Source
        if (-not $nssmPath) {
            Write-AutoRamLog "  [SELF-HEAL][WARN] nssm no encontrado en PATH - no se pudo programar la autodesinstalacion."
            return
        }
        $taskName = "AutoRAM-SelfHeal-Uninstall"
        $horaTarea = (Get-Date).AddSeconds(10).ToString("HH:mm:ss")
        $cmdLine = "/c timeout /t 5 /nobreak >nul & `"$nssmPath`" stop $ServiceName & `"$nssmPath`" remove $ServiceName confirm & schtasks /Delete /TN `"$taskName`" /F"
        & schtasks /Create /TN $taskName /TR "cmd.exe $cmdLine" /SC ONCE /ST $horaTarea /F | Out-Null
        Write-AutoRamLog "  [SELF-HEAL] Tarea programada OK - $ServiceName se desinstalara en unos segundos, fuera del arbol de procesos de nssm."
    }
    catch {
        Write-AutoRamLog "  [SELF-HEAL][WARN] Fallo al programar autodesinstalacion: $_"
    }
}

function Get-RAM {
    $os = Get-CimInstance Win32_OperatingSystem
    $total = $os.TotalVisibleMemorySize
    $libre = $os.FreePhysicalMemory
    $usada = $total - $libre
    $pct   = [math]::Round(($usada / $total) * 100, 1)
    return [PSCustomObject]@{
        TotalMB  = [math]::Round($total / 1024, 0)
        LibreMB  = [math]::Round($libre / 1024, 0)
        UsadaPct = $pct
    }
}

function Limpiar-RAM {
    param($cfg)

    Write-AutoRamLog "  Limpieza iniciada"

    # GC .NET del proceso PowerShell (marginal pero inocuo)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    # Standby List - la accion que realmente libera RAM visible
    if (Test-Path $ToolPath) {
        Start-Process $ToolPath -ArgumentList "standbylist" -NoNewWindow -Wait
        Write-AutoRamLog "  [OK] Standby list limpiada"
    }
    else {
        Write-AutoRamLog "  [WARN] EmptyStandbyList.exe no encontrado en $ToolPath - saltando"
    }

    # SMB cache - solo si esta habilitado en config
    if ($cfg.SmbTuning -eq $true) {
        try {
            Set-SmbClientConfiguration `
                -DirectoryCacheLifetime 0 `
                -FileInfoCacheLifetime 0 `
                -FileNotFoundCacheLifetime 0 `
                -Confirm:$false | Out-Null
            Write-AutoRamLog "  [OK] SMB cache reducido"
        }
        catch {
            Write-AutoRamLog "  [WARN] No se pudo ajustar SMB: $_"
        }
    }
}

# ------------------------------------
# INICIO
# ------------------------------------

Write-AutoRamLog "===== AutoRAM-Monitor iniciado ====="

# Leer config
if (-not (Test-Path $ConfigPath)) {
    Write-AutoRamLog "[ERROR] No se encontro autoram-config.json en $ConfigPath - deteniendo servicio"
	Uninstall-SelfService
    exit 1
}

try {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-AutoRamLog "[ERROR] autoram-config.json corrupto o invalido: $_ - deteniendo servicio"
	Uninstall-SelfService
    exit 1
}

Write-AutoRamLog "  Perfil cargado  : $($cfg.Perfil)"
Write-AutoRamLog "  Umbral RAM      : $($cfg.UmbralPct)%"
Write-AutoRamLog "  Intervalo       : $($cfg.IntervaloSeg) seg"
Write-AutoRamLog "  Cooldown        : $($cfg.CooldownSeg) seg"
Write-AutoRamLog "  SMB tuning      : $($cfg.SmbTuning)"

$ultimaLimpieza = Get-Date "2000-01-01"

# ------------------------------------
# LOOP PRINCIPAL
# ------------------------------------

while ($true) {

    $ram  = Get-RAM
    $ahora = Get-Date
    $desdeUltima = ($ahora - $ultimaLimpieza).TotalSeconds

    Write-AutoRamLog "RAM: $($ram.UsadaPct)% usada | Libre: $($ram.LibreMB) MB / $($ram.TotalMB) MB"

    if ($ram.UsadaPct -ge $cfg.UmbralPct -and $desdeUltima -ge $cfg.CooldownSeg) {
        Write-AutoRamLog "  [ALERTA] Umbral superado ($($ram.UsadaPct)% >= $($cfg.UmbralPct)%)"
        Limpiar-RAM -cfg $cfg
        $ultimaLimpieza = Get-Date

        # Log post-limpieza
        Start-Sleep -Seconds 3
        $ramPost = Get-RAM
        Write-AutoRamLog "  Post-limpieza   : $($ramPost.UsadaPct)% usada | Libre: $($ramPost.LibreMB) MB"
    }

    Start-Sleep -Seconds $cfg.IntervaloSeg
}