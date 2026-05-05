# AutoRAM-Monitor.ps1
# Servicio NSSM de gestion inteligente de RAM
# TuPcVeloz - v1.0
# Se instala solo en equipos con menos de 8 GB RAM
# El perfil (moderado/agresivo) lo define autoram-config.json

$ConfigPath = "C:\Users\Public\Documents\Automatico\autoram-config.json"
$LogPath    = "C:\Users\Public\Documents\AutoTemp\AutoRAM.log"
$ToolPath   = "C:\Users\Public\Documents\Automatico\Tools\EmptyStandbyList.exe"

New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

# ------------------------------------
# FUNCIONES
# ------------------------------------

function Write-AutoRamLog($msg) {
    $linea = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $LogPath -Value $linea
    Write-Host $linea
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
    exit 1
}

try {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-AutoRamLog "[ERROR] autoram-config.json corrupto o invalido: $_ - deteniendo servicio"
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