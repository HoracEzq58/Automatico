# ==============================================================================
# Nombre Script: "4ExtraeNew-InstallAppsDesktop-Claude.ps1"		version 2
# Basado en: "4ExtraeNew-InstallAppsDesktop-Claude.ps1"			version 1
# Revisado y corregido por: Claude (Anthropic) - 2026-03-10
# Actualizado por: Claude (Anthropic) - 2026-03-16
# Requiere: PowerShell 7 | Administrador | Chocolatey instalado
# Flujo: 1)Instalar -> 1.5)ConfigEverything -> 2)Verificar faltantes ->
#        3)Limpiar sobrantes -> 3.5)Actualizar -> 4)Renombrar SSD -> llamar Script 5
# ==============================================================================
#
# CAMBIOS vs v1:
#
#  [CAMBIO 1] PASO 4 eliminado (backup + sobreescritura del config)
#             El config del pendrive ya NO tiene versiones fijas -> instala
#             siempre la ultima version disponible. No tiene sentido pisarlo
#             con lo que quedo instalado (ese flujo causaba config truncado
#             si algun paquete no se instalo correctamente en el Paso 1).
#             El antiguo Paso 5 (Renombrar SSD) pasa a ser Paso 4.
#
#  [CAMBIO 2] Markdown eliminado (ya no se genera packages-list.md)
#             Al eliminar el Paso 4, el markdown pierde su razon de ser.
#
#  [CAMBIO 3] Nombre del config corregido a "InstallAppsDesktop-Automatico.config"
#             (Desktop con D minuscula, consistente con el pendrive)
#
#  [CAMBIO 4] Reintentos progresivos en Paso 1 (instalacion inicial):
#             - Intento 1: choco install normal
#             - Intento 2: + --ignore-checksums
#             - Intento 3: + --ignore-checksums --force
#             El error mas comun de choco en instalaciones limpias es checksum.
#
#  [CAMBIO 5] Reintentos progresivos en Paso 2 (reinstalacion de faltantes):
#             Misma logica: normal -> --ignore-checksums -> --ignore-checksums --force
#
# CAMBIOS 2026-03-16 (manteniendo v2):
#
#  [PASO 1.5] ConfigEverything agregado entre Paso 1 y Paso 2:
#             - Chocolatey acaba de instalar Everything en Paso 1, momento correcto
#             - Configura hide_empty_search_results=1 en Everything.ini
#             - Clave confirmada en instalacion real (2026-03-16)
#             - Pantalla en blanco al abrir Everything hasta que el usuario escriba
#
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "4ExtInstall_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "4ExtInstall_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

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
        Add-Content -Path $global:LogFile  -Value $entry -Encoding UTF8
        if ($Level -eq "ERROR") {
            Add-Content -Path $global:ErrorLog -Value $entry -Encoding UTF8
        }
    } catch {
        Write-Host "  [!] Error escribiendo log: $_" -ForegroundColor DarkRed
    }
}

# Funcion auxiliar: obtener lista de paquetes instalados en choco
# Compatible con choco v1 (--local-only) y v2 (comportamiento default)
function Get-ChocoInstalled {
    $raw = choco list --limit-output 2>$null | Where-Object { $_ -and $_.Trim() -ne "" }
    if (-not $raw) {
        # Fallback choco v1
        $raw = choco list --local-only --limit-output 2>$null | Where-Object { $_ -and $_.Trim() -ne "" }
    }
    return $raw
}

# Funcion: instalar un paquete con reintentos progresivos
# Intento 1: normal | Intento 2: --ignore-checksums | Intento 3: --ignore-checksums --force
function Install-ChocoConReintentos {
    param(
        [string]$PackageId,
        [int]$EsperaSegundos = 5
    )

    $intentos = @(
        @{ Flags = "";                                    Desc = "normal"                        }
        @{ Flags = "--ignore-checksums";                  Desc = "--ignore-checksums"             }
        @{ Flags = "--ignore-checksums --force";          Desc = "--ignore-checksums --force"     }
    )

    for ($i = 0; $i -lt $intentos.Count; $i++) {
        $n    = $i + 1
        $desc = $intentos[$i].Desc
        $flags = $intentos[$i].Flags

        Write-Log "    [${n}/3] Instalando: $PackageId ($desc)" "INFO" "Yellow"
        try {
            if ($flags -eq "") {
                choco install $PackageId --limit-output --no-progress -y 2>&1 | Out-Null
            } else {
                $cmd = "choco install $PackageId $flags --limit-output --no-progress -y"
                Invoke-Expression "$cmd 2>&1" | Out-Null
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Log "    [OK] $PackageId instalado (intento $n)." "INFO" "Green"
                return $true
            } else {
                Write-Log "    [WARN] Intento $n fallo para $PackageId (ExitCode: $LASTEXITCODE)" "WARN" "DarkYellow"
                if ($n -lt $intentos.Count) { Start-Sleep -Seconds $EsperaSegundos }
            }
        } catch {
            Write-Log "    [ERROR] Intento $n - $PackageId : $($_.Exception.Message)" "ERROR" "Red"
            if ($n -lt $intentos.Count) { Start-Sleep -Seconds $EsperaSegundos }
        }
    }

    Write-Log "    [FAIL] $PackageId no se pudo instalar tras 3 intentos." "ERROR" "Red"
    return $false
}

# ==============================================================================
# INICIO
# ==============================================================================

# ==============================================================================
# INTERRUPTORES - Modificar segun necesidad antes de ejecutar
# ==============================================================================
$LlamarScript5 = $true    # $true  = llama al Script 5 al finalizar (normal)
                           # $false = termina sin llamar al Script 5 (debug)
# ==============================================================================

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  4ExtraeNew-InstallAppsDesktop-Claude-v2.ps1  INICIO" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Usuario   : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Log       : $global:LogFile" "INFO" "Cyan"

# Verificar PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log "ERROR: Requiere PowerShell 7+. Version actual: $($PSVersionTable.PSVersion)" "ERROR" "Red"
    exit 1
}

# Verificar Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: Requiere permisos de Administrador." "ERROR" "Red"
    exit 1
}

# Verificar Chocolatey
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: Chocolatey no esta disponible. Verificar que el Script 1 lo haya instalado." "ERROR" "Red"
    exit 1
}
$chocoVer = choco --version 2>$null
Write-Log "Chocolatey: OK (v$chocoVer)" "INFO" "Green"

$automaticoPath = "C:\Users\Public\Documents\Automatico"
Set-Location $automaticoPath -ErrorAction SilentlyContinue

# ==============================================================================
# PASO 1 - INSTALAR DESDE ARCHIVO MAESTRO
# Reintentos progresivos: normal -> --ignore-checksums -> --ignore-checksums --force
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 1: INSTALAR DESDE ARCHIVO MAESTRO ---" "INFO" "Yellow"

# CAMBIO v2: nombre con Desktop (D minuscula) - consistente con el pendrive
$masterConfig     = Join-Path $automaticoPath "InstallAppsDesktop-Automatico.config"
$paso1OK          = $false
$expectedPackages = @()

if (-not (Test-Path $masterConfig)) {
    Write-Log "  [ERROR] Archivo maestro no encontrado: $masterConfig" "ERROR" "Red"
    Write-Log "  Verificar que el pendrive haya sido copiado correctamente en Script 1." "WARN" "Yellow"
} else {
    Write-Log "  [OK] Archivo maestro encontrado: $masterConfig" "INFO" "Green"

    # Parsear lista esperada del XML maestro
    try {
        [xml]$masterXml   = Get-Content $masterConfig -Encoding UTF8
        $expectedPackages = $masterXml.packages.package | ForEach-Object { $_.id }
        Write-Log "  Paquetes en maestro: $($expectedPackages.Count)" "INFO" "Cyan"
    } catch {
        Write-Log "  [ERROR] No se pudo parsear el XML maestro: $_" "ERROR" "Red"
    }

    # Intento 1: instalacion normal del config completo
    Write-Log "  [1/3] choco install config (normal)..." "INFO" "Yellow"
    try {
        choco install $masterConfig --limit-output --no-progress -y
        if ($LASTEXITCODE -eq 0) {
            Write-Log "  [OK] Instalacion inicial completada (intento 1)." "INFO" "Green"
            $paso1OK = $true
        } else {
            Write-Log "  [WARN] Intento 1 fallo (ExitCode: $LASTEXITCODE). Reintentando con --ignore-checksums..." "WARN" "Yellow"
            Start-Sleep -Seconds 5
        }
    } catch {
        Write-Log "  [WARN] Intento 1 - excepcion: $_. Reintentando..." "WARN" "Yellow"
        Start-Sleep -Seconds 5
    }

    # Intento 2: con --ignore-checksums
    if (-not $paso1OK) {
        Write-Log "  [2/3] choco install config (--ignore-checksums)..." "INFO" "Yellow"
        try {
            choco install $masterConfig --ignore-checksums --limit-output --no-progress -y
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] Instalacion completada (intento 2, --ignore-checksums)." "INFO" "Green"
                $paso1OK = $true
            } else {
                Write-Log "  [WARN] Intento 2 fallo (ExitCode: $LASTEXITCODE). Reintentando con --force..." "WARN" "Yellow"
                Start-Sleep -Seconds 5
            }
        } catch {
            Write-Log "  [WARN] Intento 2 - excepcion: $_. Reintentando..." "WARN" "Yellow"
            Start-Sleep -Seconds 5
        }
    }

    # Intento 3: con --ignore-checksums --force
    if (-not $paso1OK) {
        Write-Log "  [3/3] choco install config (--ignore-checksums --force)..." "INFO" "Yellow"
        try {
            choco install $masterConfig --ignore-checksums --force --limit-output --no-progress -y
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] Instalacion completada (intento 3, --ignore-checksums --force)." "INFO" "Green"
                $paso1OK = $true
            } else {
                Write-Log "  [ERROR] Los 3 intentos fallaron para la instalacion del config (ExitCode: $LASTEXITCODE)" "ERROR" "Red"
                Write-Log "  El Paso 2 intentara recuperar los paquetes faltantes individualmente." "WARN" "Yellow"
            }
        } catch {
            Write-Log "  [ERROR] Intento 3 - excepcion: $_" "ERROR" "Red"
            Write-Log "  El Paso 2 intentara recuperar los paquetes faltantes individualmente." "WARN" "Yellow"
        }
    }
}

Write-Log "--- [PASO 1] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 1.5 - CONFIGURAR EVERYTHING
# Se ejecuta aqui porque Chocolatey acaba de instalarlo en el Paso 1.
# Configura pantalla en blanco hasta que el usuario escriba en la barra.
# Instala el servicio Everything para indexar NTFS sin UAC (compatible con
# la desindexacion de disco C: que se aplica en las instalaciones).
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 1.5: CONFIGURAR EVERYTHING ---" "INFO" "Yellow"

# Everything debe estar cerrado para poder escribir el ini
Stop-Process -Name "Everything" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$everythingIni = "$env:APPDATA\Everything\Everything.ini"
if (-not (Test-Path $everythingIni)) {
    $everythingIni = "C:\Program Files\Everything\Everything.ini"
}

if (Test-Path $everythingIni) {
    try {
        $key   = "hide_empty_search_results"
        $value = "1"

        $iniContent = Get-Content $everythingIni

        if ($iniContent -match "^$key=") {
            $iniContent = $iniContent | ForEach-Object {
                if ($_ -match "^$key=") { "$key=$value" } else { $_ }
            }
            Write-Log "  [OK] Clave '$key' actualizada a $value en Everything.ini." "INFO" "Green"
        } else {
            $iniContent += "$key=$value"
            Write-Log "  [OK] Clave '$key' agregada con valor $value en Everything.ini." "INFO" "Green"
        }

        $iniContent | Set-Content $everythingIni -Encoding utf8NoBOM
        Write-Log "  Everything configurado: pantalla en blanco hasta que el usuario escriba." "INFO" "Green"
    } catch {
        Write-Log "  [ERROR] Error configurando Everything.ini: $_" "ERROR" "Red"
    }
} else {
    Write-Log "  [WARN] Everything.ini no encontrado. Puede que no haya instalado correctamente en Paso 1." "WARN" "Yellow"
}

# Instalar servicio Everything para indexar NTFS sin requerir UAC.
# Necesario cuando la indexacion del disco C: esta desactivada (Chris Titus).
$everythingExe = "C:\Program Files\Everything\Everything.exe"
if (Test-Path $everythingExe) {
    try {
        & $everythingExe -install-service
        Start-Sleep -Seconds 3
        Write-Log "  [OK] Servicio Everything instalado. Indexacion NTFS sin UAC." "INFO" "Green"
    } catch {
        Write-Log "  [WARN] No se pudo instalar el servicio Everything: $_" "WARN" "Yellow"
    }
} else {
    Write-Log "  [WARN] Everything.exe no encontrado en ruta esperada." "WARN" "Yellow"
}

Write-Log "--- [PASO 1.5] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 2 - VERIFICAR FALTANTES Y REINSTALAR (uno por uno con reintentos)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 2: VERIFICAR PAQUETES FALTANTES ---" "INFO" "Yellow"

if ($expectedPackages.Count -eq 0) {
    Write-Log "  [SKIP] Sin lista de paquetes esperados. Saltando verificacion." "WARN" "Yellow"
} else {
    $installedRaw      = Get-ChocoInstalled
    $installedPackages = $installedRaw | ForEach-Object { ($_ -split '\|')[0].Trim() }
    $missing           = $expectedPackages | Where-Object { $_ -notin $installedPackages }

    if ($missing.Count -gt 0) {
        Write-Log "  [WARN] Paquetes faltantes: $($missing.Count)" "WARN" "Yellow"
        $missing | ForEach-Object { Write-Log "    - $_" "WARN" "Yellow" }
        Write-Log "  Reinstalando individualmente con reintentos progresivos..." "INFO" "Yellow"

        $recuperados  = 0
        $aunFallan    = @()

        foreach ($pkg in $missing) {
            $ok = Install-ChocoConReintentos -PackageId $pkg -EsperaSegundos 5
            if ($ok) { $recuperados++ } else { $aunFallan += $pkg }
        }

        Write-Log "  Recuperados: $recuperados / $($missing.Count)" "INFO" "Cyan"

        if ($aunFallan.Count -gt 0) {
            Write-Log "  [WARN] Paquetes que requieren atencion manual:" "WARN" "Yellow"
            $aunFallan | ForEach-Object { Write-Log "    - $_" "WARN" "Red" }
        } else {
            Write-Log "  [OK] Todos los faltantes fueron recuperados." "INFO" "Green"
        }
    } else {
        Write-Log "  [OK] Todos los paquetes esperados estan instalados." "INFO" "Green"
    }
}

Write-Log "--- [PASO 2] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 3 - REVISAR SOBRANTES Y LIMPIAR (interactivo)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 3: REVISAR PAQUETES SOBRANTES ---" "INFO" "Yellow"

if ($expectedPackages.Count -eq 0) {
    Write-Log "  [SKIP] Sin lista de referencia. Saltando limpieza." "WARN" "Yellow"
} else {
    $installedRaw      = Get-ChocoInstalled
    $installedPackages = $installedRaw | ForEach-Object { ($_ -split '\|')[0].Trim() }
    $extras            = $installedPackages | Where-Object { $_ -notin $expectedPackages }

    if ($extras.Count -gt 0) {
        Write-Log "  Paquetes extras/dependencias detectados: $($extras.Count)" "INFO" "Cyan"
        $extras | ForEach-Object { Write-Log "    - $_" "INFO" "Cyan" }

        Write-Log "  Revisando uno por uno (Enter = mantener)..." "INFO" "Yellow"
        foreach ($pkg in $extras) {
            $resp = Read-Host "  Desinstalar '$pkg'? (s/n)"
            if ($resp -eq 's' -or $resp -eq 'S') {
                try {
                    choco uninstall $pkg -y
                    Write-Log "    [OK] Desinstalado: $pkg" "INFO" "Yellow"
                } catch {
                    Write-Log "    [ERROR] No se pudo desinstalar: $pkg - $_" "ERROR" "Red"
                }
            } else {
                Write-Log "    [OK] Mantenido: $pkg" "INFO" "Gray"
            }
        }
        Write-Log "  [OK] Proceso de limpieza completado." "INFO" "Green"
    } else {
        Write-Log "  [OK] No hay paquetes extras para revisar." "INFO" "Green"
    }
}

Write-Log "--- [PASO 3] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 3.5 - ACTUALIZAR TODOS LOS PAQUETES
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 3.5: ACTUALIZAR TODOS LOS PAQUETES ---" "INFO" "Yellow"
try {
    choco upgrade all --limit-output --no-progress -y
    Write-Log "  [OK] Actualizacion completada." "INFO" "Green"
} catch {
    Write-Log "  [WARN] Error durante actualizacion: $_" "WARN" "Yellow"
}
Write-Log "--- [PASO 3.5] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 4 - RENOMBRAR VOLUMEN C: CON MARCA Y CAPACIDAD DEL SSD
# (era Paso 5 en v1 - renumerado al eliminar el antiguo Paso 4)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 4: RENOMBRAR VOLUMEN C: (SSD) ---" "INFO" "Yellow"

try {
    $partition = Get-Partition -DriveLetter 'C' -ErrorAction Stop
    $disk      = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $partition.DiskNumber }

    if ($null -eq $disk) {
        Write-Log "  [WARN] No se pudo detectar el disco fisico de C:. Saltando renombrado." "WARN" "Yellow"
    } else {
        # Limpiar nombre de marca
        $brand = $disk.FriendlyName
        $brand = ($brand -replace '\d+GB', '' -replace 'SSD', '' -replace '\s+', ' ').Trim()

        # Mapear capacidad real a nominal estandar
        $rawGB      = $disk.Size / 1GB
        $capacityGB = switch ($rawGB) {
            { $_ -le 135  } { 128;  break }
            { $_ -le 260  } { 240;  break }
            { $_ -le 520  } { 500;  break }
            { $_ -le 1050 } { 1000; break }
            { $_ -le 2100 } { 2000; break }
            default          { [math]::Round($_); break }
        }

        $newLabel = "SSD $brand ${capacityGB}gb"

        # NTFS admite hasta 32 chars en label
        if ($newLabel.Length -gt 32) {
            Write-Log "  [WARN] Nombre demasiado largo, truncando a 32 chars: $newLabel" "WARN" "Yellow"
            $newLabel = $newLabel.Substring(0, 32)
        }

        Set-Volume -DriveLetter 'C' -NewFileSystemLabel $newLabel -ErrorAction Stop
        Write-Log "  [OK] Volumen C: renombrado a: '$newLabel'" "INFO" "Green"
    }
} catch {
    Write-Log "  [WARN] Error al renombrar volumen C:: $_" "WARN" "Yellow"
    Write-Log "  Continuando sin renombrar." "INFO" "Gray"
}

Write-Log "--- [PASO 4] Completado ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  4ExtraeNew-InstallAppsDesktop-Claude-v2.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Log       : $global:LogFile" "INFO" "Cyan"
Write-Log "" "INFO" "White"
Write-Log "SIGUIENTE PASO: Script 5 - 5WindowsUpdateClaude.ps1" "INFO" "White"
Write-Log "Iniciando en 6 segundos..." "INFO" "Yellow"

Start-Sleep -Seconds 6

# Llamado al Script 5
$script5 = Join-Path $automaticoPath "5WindowsUpdateClaude.ps1"
if (-not $LlamarScript5) {
    Write-Log "  [i] Llamado al Script 5 desactivado (LlamarScript5 = false)" "INFO" "Gray"
} elseif (Test-Path $script5) {
    Write-Log "Ejecutando Script 5: $script5" "INFO" "Cyan"
    & $script5
} else {
    Write-Log "  [WARN] Script 5 no encontrado en: $script5" "WARN" "Yellow"
    Write-Log "  Ejecutalo manualmente cuando estes listo." "INFO" "White"
}