# ==================================================================
# DetectaPersistenciaAppsInvasivas.ps1
# DETECTOR DE PERSISTENCIA DE APPS INVASIVAS
# Corre como Administrador en pwsh (PowerShell 7+)
# creacion 2026/04/03 20.00 hs ultima modificacion 2026/04/03 2103 hs
# - Fix PS7: Get-WmiObject -> Get-CimInstance
# - Fix registro vacio: Get-Member con guard
# ==================================================================

$invasivos = @(
    "Dropbox","IObit","ASC","AdvancedSystemCare","Avast","AVG","McAfee",
    "Norton","Symantec","CCleaner","DriverBooster","DriverEasy","Glary",
    "PCOptimizer","Auslogics","Malwarebytes","Babylon","Conduit","Reimage",
    "SpeedUpMyPC","Wondershare","iSkysoft","CoreTemp","PDFXChange",
    "OpenCandy","Coupon","Toolbar","SearchProtect","MySearch","Delta"
)

$resultados = [System.Collections.Generic.List[PSCustomObject]]::new()

function Chequear {
    param($Lugar, $Nombre, $Valor)
    foreach ($inv in $invasivos) {
        if ($Nombre -like "*$inv*" -or $Valor -like "*$inv*") {
            $script:resultados.Add([PSCustomObject]@{
                Lugar  = $Lugar
                Nombre = $Nombre
                Valor  = $Valor
            })
            break
        }
    }
}

# --- 1. Registro: Run / RunOnce ---
$regRuns = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($ruta in $regRuns) {
    if (Test-Path $ruta) {
        $props = Get-ItemProperty $ruta -ErrorAction SilentlyContinue
        if ($props) {
            $props | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                $val = $props.$($_.Name)
                Chequear "Registro Run [$ruta]" $_.Name "$val"
            }
        }
    }
}

# --- 2. Tareas programadas ---
# Excluir rutas de Windows que generan falsos positivos
$rutasBlancas = @(
    "\Microsoft\Windows\TPM\",
    "\Microsoft\Windows\UpdateOrchestrator\",
    "\Microsoft\Windows\WindowsUpdate\",
    "\Microsoft\Windows\Defrag\",
    "\Microsoft\Windows\DiskCleanup\"
)
Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
    $taskPath = $_.TaskPath
    $esBlanca = $rutasBlancas | Where-Object { $taskPath -like "*$_*" }
    if (-not $esBlanca) {
        $accion = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " "
        Chequear "Tarea programada [$taskPath]" $_.TaskName $accion
    }
}

# --- 3. Servicios de Windows (Get-CimInstance en lugar de Get-WmiObject) ---
Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($_.Name)'" -ErrorAction SilentlyContinue
    $bin = if ($svc) { $svc.PathName } else { "" }
    Chequear "Servicio Windows" $_.Name "$bin"
}

# --- 4. Carpetas de Inicio (Startup) ---
$startups = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)
foreach ($ruta in $startups) {
    if (Test-Path $ruta) {
        Get-ChildItem $ruta -ErrorAction SilentlyContinue | ForEach-Object {
            Chequear "Carpeta Startup" $_.Name $_.FullName
        }
    }
}

# --- 5. Extensiones de navegadores (Chrome y Edge) ---
$perfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

foreach ($usuario in $perfiles) {
    $extPaths = @(
        "$($usuario.FullName)\AppData\Local\Google\Chrome\User Data\Default\Extensions",
        "$($usuario.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Extensions"
    )
    foreach ($extPath in $extPaths) {
        if (Test-Path $extPath) {
            Get-ChildItem $extPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $manifestFile = Get-ChildItem "$($_.FullName)" -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                if ($manifestFile) {
                    $contenido = Get-Content $manifestFile.FullName -Raw -ErrorAction SilentlyContinue
                    Chequear "Extension navegador [$($usuario.Name)]" $_.Name $contenido
                }
            }
        }
    }
}

# --- 6. WMI Subscriptions (persistencia avanzada) ---
Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction SilentlyContinue | ForEach-Object {
    Chequear "WMI Subscription" $_.Name $_.Query
}

# --- RESULTADO ---
if ($resultados.Count -eq 0) {
    Write-Host "`nNada sospechoso encontrado." -ForegroundColor Green
} else {
    Write-Host "`n=== APPS INVASIVAS DETECTADAS: $($resultados.Count) ===" -ForegroundColor Red
    $resultados | Format-Table -AutoSize -Wrap
}