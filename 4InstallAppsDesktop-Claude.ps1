# ================================================================================
# Nombre Script: "4InstallAppsDesktop-Claude.ps1"  version 7  12/10/2026
# Basado en: version 6 (unificada) 12/09/2026
# Reescrito por: Claude (Anthropic) - 2026-10-12
# Requiere: PowerShell 7 | Administrador | Chocolatey instalado
# Flujo: 1)Instalar -> 1.5)ConfigEverything -> 2)Verificar faltantes ->
#        2.5)Asegurar Chrome -> 3)Renombrar SSD -> 3.5)EmptyStandbyList ->
#        4)Macros TinyTask -> reinicio (solo si se corre completo)
# ================================================================================
#
# USO:
#   Completo (como siempre):   pwsh -File .\4InstallAppsDesktop-Claude.ps1
#   Solo algunos pasos:        pwsh -File .\4InstallAppsDesktop-Claude.ps1 -Solo 2.5,4
#                              (desde una consola pwsh ya abierta conviene usar
#                               comillas:  .\4InstallAppsDesktop-Claude.ps1 -Solo '2.5','4' )
#   Pasos validos: 1, 1.5, 2, 2.5, 3, 3.5, 4
#   Con -Solo NO se reinicia el equipo al final.
#
# CAMBIOS v7 (2026-10-12):
#
#  [PARAMETRO -Solo] Cada paso es independiente: se puede ejecutar uno solo
#           si fallo. Sin -Solo corre todo y reinicia como antes.
#
#  [CODIGOS 1641 y 3010] Son EXITO en Chocolatey (reinicio pendiente). Antes
#           solo se aceptaba 0 y un Chrome bien instalado podia contarse como
#           fallo y gatillar reintentos innecesarios.
#
#  [PASO 2] Si se corre solo, carga por su cuenta la lista del config maestro.
#
#  [PASO 2.5 NUEVO] Asegura Google Chrome verificando chrome.exe real (no solo
#           "choco list"). Si choco cree que esta instalado pero falta el exe,
#           un "choco install" normal responde "ya instalado" con codigo 0 sin
#           hacer nada: por eso reinstala directo con --force.
#
#  [PASO 3.6 NUEVO] Mudado del S1, Notepad++ ahora se instala desde este S4
#
#        4)	Anclar barra de tareas (layout XML) -> reinicio (solo si se corre completo)
#			- Anclado por layout XML (ya no hay macros TinyTask)
#           - Sin exit ni ErrorActionPreference Stop: si falla, loguea y sigue.
#           - WaitForExit en vez de Wait-Process (evita falso timeout cuando
#             la macro termina antes de llegar a esperar).
#           - Sin Office se omiten solo Excel y Word; sin Chrome, solo Google.
#           - Registro de macros ya hechas (Tools\TiniTask\MacrosHechas.txt):
#             al repetir -Solo 4 no vuelve a correr las que ya funcionaron
#             (anclar de nuevo podria desanclar). Para repetir todo, borrar
#             ese archivo.
#           - Cuenta regresiva de 10 s: NO tocar mouse ni teclado.
#
#  [REINICIO] Solo se reinicia si se corrio completo (sin -Solo).
#
# CAMBIOS v6 / v4 (se mantienen):
#  - Paso 1 con 2 intentos para el config completo (normal e --ignore-checksums).
#  - Paso 1.5: clave correcta hide_results_when_search_is_empty + extras.
#  - Sin ningun Read-Host. S5 descartado.
#  - Reintentos progresivos en la recuperacion individual de faltantes (Paso 2):
#    normal -> --ignore-checksums -> --ignore-checksums --force
#  - Deteccion de tipo de disco (SSD/HDD) con brandMap para el nombre del volumen
#  - EmptyStandbyList.exe: descarga idempotente, requerido por AutoRAM-Monitor
# ==============================================================================

param([string[]]$Solo)

# Acepta -Solo 2.5,4 tanto desde pwsh interactivo como desde -File
$Solo = @($Solo | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
function Test-Paso { param([string]$Id) return (($Solo.Count -eq 0) -or ($Id -in $Solo)) }

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

# Funcion: detectar Google Chrome real (chrome.exe). Sin fallback a registro
# (BLBeacon): queda huerfano tras un desinstalado a medias y da falso "instalado".
function Test-GoogleChrome {
    $rutas = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($r in $rutas) {
        if (Test-Path -LiteralPath $r -PathType Leaf) { return $true }
    }
    return $false
}

# Funcion: detectar Office 2021 / LTSC (ClickToRun o lista de desinstalacion)
function Test-Office2021 {
    foreach ($ruta in @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration')) {
        if (Test-Path -LiteralPath $ruta) {
            $ids = [string](Get-ItemProperty -LiteralPath $ruta -ErrorAction SilentlyContinue).ProductReleaseIds
            if ($ids -match '(?i)(ProPlus|Standard|Professional|HomeBusiness|ProjectPro|VisioPro).*2021|2021.*(ProPlus|Standard|Professional|HomeBusiness|ProjectPro|VisioPro)') { return $true }
        }
    }
    foreach ($ruta in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $apps = Get-ItemProperty -Path $ruta -ErrorAction SilentlyContinue
        if ($apps | Where-Object { $_.DisplayName -match '(?i)Office.*(LTSC|2021)|(LTSC|2021).*Office' }) { return $true }
    }
    return $false
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

            if ($LASTEXITCODE -in 0, 1641, 3010) {
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
Write-Log "  4InstallAppsDesktop-Claude.ps1 (v7)  INICIO" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Usuario   : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Log       : $global:LogFile" "INFO" "Cyan"
if ($Solo.Count -gt 0) {
    Write-Log "Modo -Solo: pasos $($Solo -join ', ')" "INFO" "Cyan"
}

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

# Variables compartidas entre pasos (el Paso 1 las llena; el Paso 2 las recarga si hace falta)
$masterConfig     = Join-Path $automaticoPath "InstallAppsDesktop-Automatico.config"
$paso1OK          = $false
$expectedPackages = @()

# ==============================================================================
# PASO 1 - INSTALAR DESDE ARCHIVO MAESTRO (unico config, sin versiones fijas)
# 2 intentos para todo el config: normal -> --ignore-checksums.
# El Paso 2 hace de control: compara maestro vs instalado y resuelve
# individualmente lo que estos 2 intentos no hayan podido resolver.
# ==============================================================================
if (Test-Paso '1') {
Write-Log "" "INFO" "White"
Write-Log "--- PASO 1: INSTALAR DESDE ARCHIVO MAESTRO ---" "INFO" "Yellow"

if (-not (Test-Path $masterConfig)) {
    Write-Log "  [ERROR] Archivo maestro no encontrado: $masterConfig" "ERROR" "Red"
    Write-Log "  Verificar que el pendrive haya sido copiado correctamente en Script 1." "WARN" "Yellow"
} else {
    Write-Log "  [OK] Archivo maestro encontrado: $masterConfig" "INFO" "Green"

    try {
        [xml]$masterXml   = Get-Content $masterConfig -Encoding UTF8
        $expectedPackages = @($masterXml.packages.package | ForEach-Object { $_.id })
        Write-Log "  Paquetes en maestro: $($expectedPackages.Count)" "INFO" "Cyan"
    } catch {
        Write-Log "  [ERROR] No se pudo parsear el XML maestro: $_" "ERROR" "Red"
    }

    # Intento 1: instalacion normal del config completo
    Write-Log "  [1/2] choco install config (normal)..." "INFO" "Yellow"
    try {
        choco install $masterConfig --limit-output --no-progress -y
        if ($LASTEXITCODE -in 0, 1641, 3010) {
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
            if ($LASTEXITCODE -in 0, 1641, 3010) {
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
}

# ==============================================================================
# PASO 1.5 - CONFIGURAR EVERYTHING
# Se ejecuta aqui porque Chocolatey acaba de instalarlo en el Paso 1.
# Clave correcta: "hide_results_when_search_is_empty" (la vieja
# "hide_empty_search_results" no existe en Everything).
# ==============================================================================
if (Test-Paso '1.5') {
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
            "exclude_hidden_files"              = 1   # ocultar carpetas ocultas
            "show_status_bar"                   = 0   # vista mas limpia sin barra de estado
            "match_path"                        = 0
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

    # Reiniciar Everything para que tome la config nueva
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
}

# ==============================================================================
# PASO 2 - VERIFICAR FALTANTES Y REINSTALAR (uno por uno con reintentos)
# Este es el "control" que compara el config maestro contra lo efectivamente
# instalado, y resuelve individualmente lo que el Paso 1 no haya logrado.
# Si se corre solo (-Solo 2), recarga la lista del config maestro por su cuenta.
# ==============================================================================
if (Test-Paso '2') {
Write-Log "" "INFO" "White"
Write-Log "--- PASO 2: VERIFICAR PAQUETES FALTANTES ---" "INFO" "Yellow"

if (@($expectedPackages).Count -eq 0) {
    if (Test-Path $masterConfig) {
        try {
            [xml]$masterXml   = Get-Content $masterConfig -Encoding UTF8
            $expectedPackages = @($masterXml.packages.package | ForEach-Object { $_.id })
        } catch {
            Write-Log "  [ERROR] No se pudo parsear el XML maestro: $_" "ERROR" "Red"
        }
    }
}

if ($expectedPackages.Count -eq 0) {
    Write-Log "  [SKIP] Sin lista de paquetes esperados. Saltando verificacion." "WARN" "Yellow"
} else {
    $installedRaw      = Get-ChocoInstalled
    $installedPackages = $installedRaw | ForEach-Object { ($_ -split '\|')[0].Trim() }
    $missing           = @($expectedPackages | Where-Object { $_ -notin $installedPackages })

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
}

# ==============================================================================
# PASO 2.5 - ASEGURAR GOOGLE CHROME (verifica chrome.exe, no solo choco list)
# Si choco cree que esta instalado pero falta el exe, un install normal
# responde "ya instalado" (codigo 0) sin hacer nada: por eso va directo con --force.
# ==============================================================================
if (Test-Paso '2.5') {
Write-Log "" "INFO" "White"
Write-Log "--- PASO 2.5: ASEGURAR GOOGLE CHROME ---" "INFO" "Yellow"

if (Test-GoogleChrome) {
    Write-Log "  [OK] chrome.exe presente." "INFO" "Green"
} else {
    Write-Log "  [WARN] chrome.exe no existe (aunque choco lo liste). Reinstalando con --force..." "WARN" "Yellow"
    $chromeOK = $false
    foreach ($flags in @(@('--force'), @('--ignore-checksums', '--force'))) {
        Write-Log "    choco install googlechrome $($flags -join ' ')" "INFO" "Yellow"
        choco install googlechrome @flags --limit-output --no-progress -y 2>&1 | Out-Null
        $codigo = $LASTEXITCODE
        Start-Sleep -Seconds 3
        if (($codigo -in 0, 1641, 3010) -and (Test-GoogleChrome)) {
            Write-Log "  [OK] Chrome instalado y verificado." "INFO" "Green"
            $chromeOK = $true
            break
        }
        Write-Log "    [WARN] Intento fallido (ExitCode: $codigo)." "WARN" "DarkYellow"
    }
    if (-not $chromeOK) {
        Write-Log "  [ERROR] Chrome no quedo instalado. Requiere atencion manual." "ERROR" "Red"
    }
}

Write-Log "--- [PASO 2.5] Completado ---" "INFO" "Yellow"
}

# ==============================================================================
# PASO 3 - RENOMBRAR VOLUMEN C: CON MARCA Y CAPACIDAD DEL SSD
# ==============================================================================
if (Test-Paso '3') {
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
}

# ==============================================================================
# PASO 3.5 - DESCARGAR EmptyStandbyList.exe (requerido por AutoRAM-Monitor)
# ==============================================================================
if (Test-Paso '3.5') {
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
}
# ==============================================================================
# PASO 3.6 - ARCHIVO ESPANOL PARA NOTEPAD++ (movido desde el Script 1)
# En el S1 Notepad++ todavia no esta instalado; lo instala el Paso 1 de este script.
# ==============================================================================
if (Test-Paso '3.6') {
Write-Log "" "INFO" "White"
Write-Log "--- PASO 3.6: ESPANOL NOTEPAD++ ---" "INFO" "Yellow"

$nppSpanishOrigen = Join-Path $automaticoPath "Tools\spanish.xml"
$nppDir           = "C:\Program Files\Notepad++"
$nppLocalization  = Join-Path $nppDir "localization"

if (-not (Test-Path $nppSpanishOrigen)) {
    Write-Log "  [WARN] spanish.xml no encontrado en: $nppSpanishOrigen" "WARN" "Yellow"
} elseif (-not (Test-Path $nppDir)) {
    Write-Log "  [WARN] Notepad++ no esta instalado. Saltando copia de spanish.xml." "WARN" "Yellow"
} else {
    try {
        Stop-Process -Name "notepad++" -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $nppLocalization)) { New-Item -ItemType Directory -Path $nppLocalization -Force | Out-Null }
        Copy-Item $nppSpanishOrigen -Destination $nppLocalization -Force
        Write-Log "  [OK] spanish.xml copiado a: $nppLocalization" "INFO" "Green"
    } catch {
        Write-Log "  [ERROR] No se pudo copiar spanish.xml: $_" "ERROR" "Red"
    }
}

Write-Log "--- [PASO 3.6] Completado ---" "INFO" "Yellow"
}

# ==============================================================================
# PASO 4 - ANCLAR BARRA DE TAREAS (layout XML, sin macros ni GUI)
# Orden: Explorador, Chrome, Panel de control, Excel, Word. Desancla todo lo demas.
# Cada app se ancla SOLO si esta realmente instalada (chrome.exe / Office 2021).
# ==============================================================================
if (Test-Paso '4') {
Write-Log "" "INFO" "White"
Write-Log "--- PASO 4: ANCLAR BARRA DE TAREAS ---" "INFO" "Yellow"

$progs  = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
$xml    = Join-Path $global:LogPath "TaskbarLayout.xml"
$polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$items  = @('<taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />')
$ws     = New-Object -ComObject WScript.Shell

try {
    # --- Chrome: solo si chrome.exe existe; si falta el .lnk, se crea ---
    $chromeExe = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if ($chromeExe) {
        $lnk = Join-Path $progs "Google Chrome.lnk"
        if (-not (Test-Path $lnk)) {
            $s = $ws.CreateShortcut($lnk); $s.TargetPath = $chromeExe; $s.Save()
        }
        $items += "<taskbar:DesktopApp DesktopApplicationLinkPath=`"$lnk`" />"
        Write-Log "  [OK] Chrome se ancla." "INFO" "Green"
    } else {
        Write-Log "  [WARN] Chrome no esta instalado: no se ancla." "WARN" "Yellow"
    }

    # --- Panel de control: siempre (el .lnk se crea) ---
    $lnk = Join-Path $progs "Panel de control.lnk"
    $s = $ws.CreateShortcut($lnk); $s.TargetPath = "$env:windir\System32\control.exe"; $s.Save()
    $items += "<taskbar:DesktopApp DesktopApplicationLinkPath=`"$lnk`" />"

    # --- Excel y Word: solo si hay Office 2021 y existe el .lnk ---
    if (Test-Office2021) {
        foreach ($n in 'Excel','Word') {
            $lnk = Join-Path $progs "$n.lnk"
            if (Test-Path $lnk) {
                $items += "<taskbar:DesktopApp DesktopApplicationLinkPath=`"$lnk`" />"
                Write-Log "  [OK] $n se ancla." "INFO" "Green"
            } else {
                Write-Log "  [WARN] No existe $lnk: $n no se ancla." "WARN" "Yellow"
            }
        }
    } else {
        Write-Log "  [WARN] Office 2021 no detectado: Excel y Word no se anclan." "WARN" "Yellow"
    }

    # --- XML ---
@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        $($items -join "`r`n        ")
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@ | Set-Content -Path $xml -Encoding UTF8

    # --- Aplicar politica + reiniciar explorer ---
    New-Item $polKey -Force | Out-Null
    Set-ItemProperty $polKey -Name LockedStartLayout -Value 1 -Type DWord
    Set-ItemProperty $polKey -Name StartLayoutFile  -Value $xml -Type ExpandString
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
} catch {
    Write-Log "  [ERROR] Fallo armando el layout de la barra: $($_.Exception.Message)" "ERROR" "Red"
} finally {
    # Siempre destrabar, aunque haya fallado algo
    Set-ItemProperty $polKey -Name LockedStartLayout -Value 0 -ErrorAction SilentlyContinue
    Remove-ItemProperty $polKey -Name StartLayoutFile -ErrorAction SilentlyContinue
    # Sacar el tilde de "Bloquear la barra de tareas"
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarSizeMove -Value 1 -Type DWord -ErrorAction SilentlyContinue
}

# Segundo reinicio de explorer + asegurar que vuelva (evita la pantalla negra)
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

Write-Log "--- [PASO 4] Completado ---" "INFO" "Yellow"
}

# ==============================================================================
# FIN DEL SCRIPT
# S5 queda descartado (ver Script 1) - no hay llamado a ningun script mas.
# Reinicio automatico solo en corrida completa: el rename de equipo (S2) y los
# cambios de DISM / Memory Compression (S3) necesitan un reboot para aplicarse.
# Con -Solo no se reinicia.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  4InstallAppsDesktop-Claude.ps1 (v7)  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Log       : $global:LogFile" "INFO" "Cyan"
Write-Log "" "INFO" "White"

if ($Solo.Count -eq 0) {
    Write-Log "DESPLIEGUE COMPLETO. Reiniciando equipo en 5 segundos..." "INFO" "Green"
    Write-Log "(rename de equipo, DISM y Memory Compression necesitan este reinicio)" "INFO" "Gray"
    Write-Log "" "INFO" "White"
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Log "Modo -Solo ($($Solo -join ', ')): sin reinicio automatico." "INFO" "Cyan"
}