# ================================================================================
# Nombre Script: "4InstallAppsDesktop-Claude.ps1" version 6 (unificada) 12/09/2026
# Basado en: "4ExtraeNew-InstallAppsDesktop-Claude.ps1"			version 3
# Reescrito por: Claude (Anthropic) - 2026-09-12
# Requiere: PowerShell 7 | Administrador | Chocolatey instalado
# Flujo: 1)Instalar -> 1.5)ConfigEverything -> 2)Verificar faltantes ->
#        3)Renombrar SSD -> 3.5)EmptyStandbyList -> FIN (sin Script 5)
# ================================================================================
#
# CAMBIOS v4 (2026-09-12):
#
#  [PASO 1] Bajado de 3 a 2 intentos para el config completo: normal y
#           --ignore-checksums. Se saca el 3er intento con --force a nivel
#           config completo (mas riesgo que beneficio real segun experiencia
#           de campo). El Paso 2 sigue haciendo de control: compara maestro
#           vs instalado y reintenta individualmente los que falten, ahi si
#           con --force como ultimo recurso (Install-ChocoConReintentos,
#           sin cambios) porque ahi el riesgo es acotado a un solo paquete.
#
#  [PASO 1.5] BUG REAL CORREGIDO: la clave usada para Everything.ini era
#           "hide_empty_search_results", que no existe. La clave real,
#           documentada por voidtools, es "hide_results_when_search_is_empty"
#           (asi lo tenia bien el script suelto ConfigEverything.ps1). Se
#           suman ademas las mismas configuraciones extra de ese script:
#           exclude_system_files, exclude_hidden_files, show_status_bar=0,
#           match_path=0. Al final se reinicia Everything.exe.
#
#  [PASO 3 Y 3.5 ELIMINADOS] (antes "revisar sobrantes" y "actualizar todos
#           los paquetes"). En una instalacion limpia con el config maestro
#           homologado no tienen nada que hacer: no hay sobrantes ni nada
#           para actualizar (el config sin versiones fijas ya instalo la
#           ultima version disponible en el Paso 1). Ademas duplican lo que
#           ya hace MantenimientoSemanal semanalmente en cada cliente
#           (incluyendo la misma exclusion de rustdesk.install del upgrade).
#           Sacarlos deja este script SIN NINGUN Read-Host: el ultimo que
#           quedaba era el "Desinstalar 'x'? (s/n)" del viejo Paso 3.
#           Los antiguos Paso 4 y Paso 4.5 se renumeran a Paso 3 y Paso 3.5.
#
#  [FIN DE SCRIPT] Se elimina el bloque completo de llamado al Script 5
#           (no solo el flag $LlamarScript5) porque S5 quedo descartado.
#
# ==============================================================================
# CAMBIOS HEREDADOS DE v3 (se mantienen):
#
#  - Reintentos progresivos en el Paso 2 (recuperacion de faltantes):
#    normal -> --ignore-checksums -> --ignore-checksums --force
#  - Deteccion de tipo de disco (SSD/HDD/Unspecified) con diccionario de
#    marcas (brandMap) para nombres limpios sin redundancia de capacidad
#  - EmptyStandbyList.exe: descarga idempotente desde GitHub, requerido por
#    AutoRAM-Monitor en equipos con poca RAM
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
        $raw = choco list --local-only --limit-output 2>$null | Where-Object { $_ -and $_.Trim() -ne "" }
    }
    return $raw
}

# Funcion: instalar un paquete con reintentos progresivos
# Intento 1: normal | Intento 2: --ignore-checksums | Intento 3: --ignore-checksums --force
# Usada solo por el Paso 2 (recuperacion individual de faltantes) - aca el
# --force es de bajo riesgo porque afecta a un unico paquete, no a todo el config.
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
        $n     = $i + 1
        $desc  = $intentos[$i].Desc
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

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  4ExtraeNew-InstallAppsDesktop-Claude-v4.ps1  INICIO" "INFO" "Magenta"
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
# PASO 1 - INSTALAR DESDE ARCHIVO MAESTRO (unico config, sin versiones fijas)
# 2 intentos para todo el config: normal -> --ignore-checksums.
# El Paso 2 hace de control: compara maestro vs instalado y resuelve
# individualmente lo que estos 2 intentos no hayan podido resolver.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 1: INSTALAR DESDE ARCHIVO MAESTRO ---" "INFO" "Yellow"

$masterConfig     = Join-Path $automaticoPath "InstallAppsDesktop-Automatico.config"
$paso1OK          = $false
$expectedPackages = @()

if (-not (Test-Path $masterConfig)) {
    Write-Log "  [ERROR] Archivo maestro no encontrado: $masterConfig" "ERROR" "Red"
    Write-Log "  Verificar que el pendrive haya sido copiado correctamente en Script 1." "WARN" "Yellow"
} else {
    Write-Log "  [OK] Archivo maestro encontrado: $masterConfig" "INFO" "Green"

    try {
        [xml]$masterXml   = Get-Content $masterConfig -Encoding UTF8
        $expectedPackages = $masterXml.packages.package | ForEach-Object { $_.id }
        Write-Log "  Paquetes en maestro: $($expectedPackages.Count)" "INFO" "Cyan"
    } catch {
        Write-Log "  [ERROR] No se pudo parsear el XML maestro: $_" "ERROR" "Red"
    }

    # Intento 1: instalacion normal del config completo
    Write-Log "  [1/2] choco install config (normal)..." "INFO" "Yellow"
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

    # Intento 2: con --ignore-checksums (resuelve la gran mayoria de los casos)
    if (-not $paso1OK) {
        Write-Log "  [2/2] choco install config (--ignore-checksums)..." "INFO" "Yellow"
        try {
            choco install $masterConfig --ignore-checksums --limit-output --no-progress -y
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] Instalacion completada (intento 2, --ignore-checksums)." "INFO" "Green"
                $paso1OK = $true
            } else {
                Write-Log "  [WARN] Los 2 intentos del config completo fallaron (ExitCode: $LASTEXITCODE)." "WARN" "Yellow"
                Write-Log "  El Paso 2 intentara recuperar los paquetes faltantes individualmente." "WARN" "Yellow"
            }
        } catch {
            Write-Log "  [WARN] Intento 2 - excepcion: $_" "WARN" "Yellow"
            Write-Log "  El Paso 2 intentara recuperar los paquetes faltantes individualmente." "WARN" "Yellow"
        }
    }
}

Write-Log "--- [PASO 1] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 1.5 - CONFIGURAR EVERYTHING
# Se ejecuta aqui porque Chocolatey acaba de instalarlo en el Paso 1.
# BUG CORREGIDO: la clave "hide_empty_search_results" no existe en Everything;
# la clave real es "hide_results_when_search_is_empty". Se agregan ademas
# las mismas configuraciones extra de ConfigEverything.ps1.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 1.5: CONFIGURAR EVERYTHING ---" "INFO" "Yellow"

Stop-Process -Name "Everything" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$everythingIni = "$env:APPDATA\Everything\Everything.ini"
if (-not (Test-Path $everythingIni)) {
    $everythingIni = "C:\Program Files\Everything\Everything.ini"
}

if (Test-Path $everythingIni) {
    try {
        $settings = @{
            "hide_results_when_search_is_empty" = 1   # pantalla en blanco hasta que el usuario escriba
            "exclude_system_files"              = 1   # ocultar archivos de sistema
            "exclude_hidden_files"               = 1   # ocultar carpetas ocultas
            "show_status_bar"                    = 0   # vista mas limpia sin barra de estado
            "match_path"                         = 0
        }

        $iniContent = Get-Content $everythingIni
        foreach ($key in $settings.Keys) {
            $value = $settings[$key]
            if ($iniContent -match "^$key=") {
                $iniContent = $iniContent | ForEach-Object {
                    if ($_ -match "^$key=") { "$key=$value" } else { $_ }
                }
                Write-Log "  [OK] Clave '$key' actualizada a $value en Everything.ini." "INFO" "Green"
            } else {
                $iniContent += "$key=$value"
                Write-Log "  [OK] Clave '$key' agregada con valor $value en Everything.ini." "INFO" "Green"
            }
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
$everythingExe = "C:\Program Files\Everything\Everything.exe"
if (Test-Path $everythingExe) {
    try {
        & $everythingExe -install-service
        Start-Sleep -Seconds 3
        Write-Log "  [OK] Servicio Everything instalado. Indexacion NTFS sin UAC." "INFO" "Green"
    } catch {
        Write-Log "  [WARN] No se pudo instalar el servicio Everything: $_" "WARN" "Yellow"
    }

    # Reiniciar Everything para que tome la config nueva (ConfigEverything.ps1 lo hacia asi)
    try {
        Start-Process $everythingExe
        Write-Log "  [OK] Everything reiniciado con la configuracion nueva." "INFO" "Green"
    } catch {
        Write-Log "  [WARN] No se pudo reiniciar Everything: $_" "WARN" "Yellow"
    }
} else {
    Write-Log "  [WARN] Everything.exe no encontrado en ruta esperada." "WARN" "Yellow"
}

Write-Log "--- [PASO 1.5] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 2 - VERIFICAR FALTANTES Y REINSTALAR (uno por uno con reintentos)
# Este es el "control" que compara el config maestro contra lo efectivamente
# instalado, y resuelve individualmente lo que el Paso 1 no haya logrado.
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

        $recuperados = 0
        $aunFallan   = @()

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
# PASO 3 - RENOMBRAR VOLUMEN C: CON MARCA Y CAPACIDAD DEL SSD
# (era Paso 4 en v3 - renumerado al eliminar los antiguos Paso 3 y 3.5)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 3: RENOMBRAR VOLUMEN C: (SSD) ---" "INFO" "Yellow"

try {
    $partition = Get-Partition -DriveLetter 'C' -ErrorAction Stop
    $disk      = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $partition.DiskNumber }

    if ($null -eq $disk) {
        Write-Log "  [WARN] No se pudo detectar el disco fisico de C:. Saltando renombrado." "WARN" "Yellow"
    } else {
        $brandMap = @(
            @{ Pattern = 'Hicksemi|HS-SSD-WAVE|HS--WAVE|HSWAVE|HS-WAVE'; Name = 'Hicksemi'  }
            @{ Pattern = 'Kingston|KINGSTON|SA400';           Name = 'Kingston'  }
            @{ Pattern = 'Samsung|SAMSUNG';                   Name = 'Samsung'   }
            @{ Pattern = 'WD|Western.?Digital';               Name = 'WD'        }
            @{ Pattern = 'Crucial|CT\d+';                     Name = 'Crucial'   }
            @{ Pattern = 'SanDisk|SANDISK';                   Name = 'SanDisk'   }
            @{ Pattern = 'Patriot';                           Name = 'Patriot'   }
            @{ Pattern = 'PNY';                               Name = 'PNY'       }
            @{ Pattern = 'A-?DATA|ADATA';                     Name = 'ADATA'     }
            @{ Pattern = 'Toshiba|TOSHIBA';                   Name = 'Toshiba'   }
            @{ Pattern = 'Intel';                             Name = 'Intel'     }
            @{ Pattern = 'Seagate';                           Name = 'Seagate'   }
            @{ Pattern = 'Lexar';                             Name = 'Lexar'     }
            @{ Pattern = 'Silicon.?Power|SP\d+';              Name = 'SiliconPwr'}
            @{ Pattern = 'Team.?Group|T-?Force';              Name = 'TeamGroup' }
        )

        $rawBrand    = $disk.FriendlyName
        $matchedName = $null
        foreach ($entry in $brandMap) {
            if ($rawBrand -match $entry.Pattern) {
                $matchedName = $entry.Name
                break
            }
        }

        if ($matchedName) {
            $brand = $matchedName
            Write-Log "  Marca identificada: '$rawBrand' -> '$brand'" "INFO" "Cyan"
        } else {
            $brand = ($rawBrand -replace '\d+\s*G\b', '' -replace '\d+GB', '' -replace 'SSD', '' -replace '\s+', ' ').Trim()
            Write-Log "  Marca no mapeada, limpieza generica: '$rawBrand' -> '$brand'" "WARN" "Yellow"
        }

        $mediaType = $disk.MediaType
        $rawGB     = $disk.Size / 1GB

        if ($mediaType -eq "SSD") {
            $diskPrefix = "SSD"
            $capacityGB = switch ($rawGB) {
                { $_ -le 135  } { 128;  break }
                { $_ -le 260  } { 240;  break }
                { $_ -le 520  } { 500;  break }
                { $_ -le 1050 } { 1000; break }
                { $_ -le 2100 } { 2000; break }
                default          { [math]::Round($_); break }
            }
            Write-Log "  Tipo detectado: SSD" "INFO" "Cyan"
        } else {
            $diskPrefix = "HDD"
            $capacityGB = [math]::Round($rawGB)
            Write-Log "  Tipo detectado: $($mediaType ? $mediaType : 'Unspecified') -> tratado como HDD" "WARN" "Yellow"
        }

        $newLabel = "$diskPrefix $brand ${capacityGB}gb"

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

Write-Log "--- [PASO 3] Completado ---" "INFO" "Yellow"

# ==============================================================================
# PASO 3.5 - DESCARGAR EmptyStandbyList.exe (requerido por AutoRAM-Monitor)
# (era Paso 4.5 en v3)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- PASO 3.5: EmptyStandbyList.exe para AutoRAM ---" "INFO" "Yellow"

$rutaTools = Join-Path $automaticoPath "Tools"
$destino   = Join-Path $rutaTools "EmptyStandbyList.exe"

if (-not (Test-Path $destino)) {
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stefanpejcic/EmptyStandbyList/master/EmptyStandbyList.exe" -OutFile $destino -UseBasicParsing
        if (Test-Path $destino) {
            Write-Log "  [OK] EmptyStandbyList.exe disponible en Tools\" "INFO" "Green"
        } else {
            Write-Log "  [WARN] No se pudo descargar EmptyStandbyList.exe." "WARN" "Yellow"
        }
    } catch {
        Write-Log "  [ERROR] No se pudo descargar EmptyStandbyList.exe: $($_.Exception.Message)" "ERROR" "Red"
    }
} else {
    Write-Log "  [i] EmptyStandbyList.exe ya presente en Tools\ - sin cambios." "INFO" "Gray"
}

Write-Log "--- [PASO 3.5] Completado ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# S5 queda descartado (ver Script 1) - no hay llamado a ningun script mas.
# Reinicio automatico: el rename de equipo (S2) y los cambios de DISM /
# Memory Compression (S3) necesitan un reboot para terminar de aplicarse.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  4ExtraeNew-InstallAppsDesktop-Claude-v4.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Log       : $global:LogFile" "INFO" "Cyan"
Write-Log "" "INFO" "White"
Write-Log "DESPLIEGUE COMPLETO. Reiniciando equipo en 5 segundos..." "INFO" "Green"
Write-Log "(rename de equipo, DISM y Memory Compression necesitan este reinicio)" "INFO" "Gray"
Write-Log "" "INFO" "White"

Start-Sleep -Seconds 5
Restart-Computer -Force
