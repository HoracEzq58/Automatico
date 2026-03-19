# ==============================================================================
# Nombre Script: "1Fi-2601-AutomaticoClaude.ps1"
# Basado en: "1Fi-2601_AutomaticoClaude-v1.ps1"
# Revisado y modularizado por: Claude (Anthropic) - 2026-03-09
# Actualizado por: Claude (Anthropic) - 2026-03-18
# Requiere: PowerShell 5 (compatible con W10 IoT LTSC recien instalado)
# Ejecutar como: Administrador
# SET-EXECUTIONPOLICY -EXECUTIONPOLICY UNRESTRICTED -SCOPE LocalMachine
# ==============================================================================
#
# CAMBIOS vs v1/v2:
#
#  [CAMBIO] SECCION 01 - Reemplazado copiado desde pendrive por descarga desde GitHub
#           ANTES: buscaba pendrive "Automatico K" o "Automatico SD" y copiaba carpetas
#           AHORA: descarga ZIP del repo publico HoracEzq58/Automatico desde GitHub,
#                  extrae las carpetas Fi-2601 y Automatico, las copia a sus destinos.
#           MOTIVO: archivos siempre actualizados en Git, sin depender del pendrive.
#           COMPATIBLE PS5: usa Invoke-WebRequest y System.IO.Compression, sin Git.
#
# ==============================================================================
#
# PROBLEMAS ENCONTRADOS Y CORREGIDOS vs GROKv2 (heredados de v1):
#
#  [BUG 1] Sec.04 - choco install usaba --version=latest literalmente
#          "choco install pkg --version=latest" es un error en choco, 
#          si no hay version en el XML pasa "latest" como string al comando
#          CORRECCION: Si version es "latest" o vacia, se omite --version
#
#  [BUG 2] Sec.04 - choco list usa --local-only (obsoleto en choco v2+)
#          En choco v2 el flag correcto es --local-only-packages o simplemente
#          omitirlo con "choco list --exact" que por defecto es local
#          CORRECCION: Se usa "choco list --local-only --exact" con fallback
#
#  [BUG 3] Sec.04 - Las funciones se definen DESPUES del bloque que las usa
#          PowerShell 5 requiere que las funciones esten definidas antes de
#          ser llamadas cuando estan fuera de un scriptblock
#          CORRECCION: Funciones movidas al inicio, antes de las secciones
#
#  [BUG 4] Sec.04 - $aunFallanSegundaPasada usada en el resumen final pero
#          solo existe dentro del bloque if ($paquetesFallidos.Count -gt 0)
#          Si no hay fallidos, la variable no existe y el script da error
#          CORRECCION: Inicializada como @() antes del loop de grupos
#
#  [MEJORA 1] Sec.01 - WMI alternativo busca DriveType 2 (removible) Y 3 (fijo)
#             DriveType 3 son discos fijos, no pendrives. Solo deberia ser 2
#             CORRECCION: Solo DriveType 2 en metodo alternativo
#
#  [MEJORA 2] Sec.04 - XML config con versiones: si el XML tiene version, 
#             se usa; si no tiene atributo version, se instala latest (sin flag)
#             Esto es consistente con lo que aprendiste sobre choco y versiones
#
#  [MEJORA 3] General - Modularizado: cada seccion es autocontenida con su
#             propio try/catch, header y footer de log
#
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath    = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile    = Join-Path $global:LogPath "Fi-2601_Install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog   = Join-Path $global:LogPath "Fi-2601_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Crear carpeta de logs si no existe
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
    $entry = "[$timestamp] [$Level] $Message"
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
# FUNCIONES CHOCOLATEY
# Definidas al inicio para que PS5 las encuentre en todas las secciones
# ==============================================================================

function Test-ChocoPackageExists {
    # Verifica si un paquete existe en el repositorio de Chocolatey
    param([string]$PackageId)
    try {
        $result = choco search --exact $PackageId --limit-output 2>$null
        return ($result -and ($result | Out-String).Contains($PackageId))
    } catch {
        return $false
    }
}

function Test-ChocoPackageInstalled {
    # Verifica si un paquete ya esta instalado localmente
    param([string]$PackageId)
    try {
        # --local-only funciona en choco v1; en v2 es el comportamiento por defecto
        $result = choco list --exact --local-only $PackageId --limit-output 2>$null
        if (-not $result) {
            # Fallback para choco v2
            $result = choco list --exact $PackageId --limit-output 2>$null
        }
        return ($result -and ($result | Out-String).Contains($PackageId))
    } catch {
        return $false
    }
}

function Install-ChocoPackage {
    # Instala un paquete con reintentos. Version es opcional.
    # Si no se pasa version (o es "latest"/vacia), instala la ultima disponible
    param(
        [string]$PackageId,
        [string]$PackageVersion = "",   # Vacio = instala latest (sin flag --version)
        [int]$MaxReintentos    = 3,
        [int]$EsperaSegundos   = 5
    )

    # Verificar existencia en repositorio
    if (-not (Test-ChocoPackageExists -PackageId $PackageId)) {
        Write-Log "  [SKIP] $PackageId no existe en Chocolatey." "WARN" "Yellow"
        return $false
    }

    # Verificar si ya esta instalado
    if (Test-ChocoPackageInstalled -PackageId $PackageId) {
        Write-Log "  [YA OK] $PackageId ya instalado." "INFO" "Blue"
        return $true
    }

    # Determinar si usar --version o no
    # BUG CORREGIDO: nunca pasar "latest" como string a --version
    $useVersion = ($PackageVersion -and $PackageVersion -ne "latest" -and $PackageVersion -ne "")

    for ($i = 1; $i -le $MaxReintentos; $i++) {
        try {
            if ($useVersion) {
                Write-Log "  [${i}/${MaxReintentos}] Instalando: ${PackageId} v${PackageVersion}" "INFO" "Yellow"
                $output = choco install $PackageId --version=$PackageVersion --limit-output --no-progress -y 2>&1
            } else {
                Write-Log "  [${i}/${MaxReintentos}] Instalando: ${PackageId} (ultima version)" "INFO" "Yellow"
                $output = choco install $PackageId --limit-output --no-progress -y 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] $PackageId instalado correctamente." "INFO" "Green"
                return $true
            } else {
                Write-Log "  [WARN] Intento $i fallo para $PackageId (ExitCode: $LASTEXITCODE)" "WARN" "DarkYellow"
                Write-Log "  Output: $($output | Out-String)" "WARN" "Gray"
                if ($i -lt $MaxReintentos) { Start-Sleep -Seconds $EsperaSegundos }
            }
        } catch {
            Write-Log "  [ERROR] Intento $i - $PackageId : $($_.Exception.Message)" "ERROR" "Red"
            if ($i -lt $MaxReintentos) { Start-Sleep -Seconds $EsperaSegundos }
        }
    }

    Write-Log "  [FAIL] $PackageId no se pudo instalar tras $MaxReintentos intentos." "ERROR" "Red"
    return $false
}

# ==============================================================================
# INICIO
# ==============================================================================

# ==============================================================================
# INTERRUPTORES - Modificar segun necesidad antes de ejecutar
# ==============================================================================
$LlamarScript2 = $true    # $true  = llama al Script 2 al finalizar (normal)
                           # $false = termina sin llamar al Script 2 (debug)
# ==============================================================================

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  1Fi-2601_AutomaticoClaude.ps1  INICIO" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Usuario  : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Fecha    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO" "Cyan"
Write-Log "Log      : $global:LogFile" "INFO" "Cyan"

# Verificar permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: Requiere permisos de Administrador. Abri PowerShell como Admin." "ERROR" "Red"
    exit 1
}
Write-Log "Permisos de Administrador: OK" "INFO" "Green"

# ==============================================================================
# SECCION 01 - DESCARGAR ARCHIVOS DESDE GITHUB
# Descarga el ZIP del repo publico, extrae Fi-2603 y Automatico,
# los copia a sus destinos. Sin Git, sin pendrive. Compatible PS5.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 01: DESCARGAR ARCHIVOS DESDE GITHUB ---" "INFO" "Yellow"

$GitHubUser   = "HoracEzq58"
$GitHubRepo   = "Automatico"
$GitHubBranch = "main"
$ZipUrl       = "https://github.com/$GitHubUser/$GitHubRepo/archive/refs/heads/$GitHubBranch.zip"
$ZipLocal     = "$env:TEMP\Automatico-github.zip"
$ExtractPath  = "$env:TEMP\Automatico-github"
$RepoFolder   = "$ExtractPath\$GitHubRepo-$GitHubBranch"  # nombre que genera GitHub al extraer
$DestImagenes    = "C:\Users\Public\Pictures"
$DestDocumentos  = "C:\Users\Public\Documents"

$seccion01OK = $false

try {
    # Paso 1: Descargar ZIP
    Write-Log "  Descargando repo desde: $ZipUrl" "INFO" "Yellow"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    # Limpiar descarga anterior si existe
    if (Test-Path $ZipLocal)    { Remove-Item $ZipLocal    -Force }
    if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }

    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ZipUrl, $ZipLocal)
    Write-Log "  [OK] ZIP descargado: $ZipLocal ($([math]::Round((Get-Item $ZipLocal).Length/1KB,1)) KB)" "INFO" "Green"

    # Paso 2: Extraer ZIP - compatible PS5 via .NET
    Write-Log "  Extrayendo ZIP..." "INFO" "Yellow"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipLocal, $ExtractPath)
    Write-Log "  [OK] ZIP extraido en: $ExtractPath" "INFO" "Green"

    # Paso 3: Verificar que las carpetas existen en el repo
    $Carpeta1 = Join-Path $RepoFolder "Fi-2603"
    $Carpeta2 = Join-Path $RepoFolder "Automatico"

    foreach ($carpeta in @($Carpeta1, $Carpeta2)) {
        if (Test-Path $carpeta) {
            Write-Log "  [OK] Carpeta encontrada en repo: $carpeta" "INFO" "Green"
        } else {
            Write-Log "  [WARN] Carpeta NO encontrada en repo: $carpeta" "WARN" "Yellow"
        }
    }

    # Paso 4: Limpiar destinos anteriores
    foreach ($destino in @("$DestImagenes\Fi-2603", "$DestDocumentos\Automatico")) {
        if (Test-Path $destino) {
            try {
                Remove-Item $destino -Recurse -Force
                Write-Log "  [OK] Limpiado destino anterior: $destino" "INFO" "Yellow"
            } catch {
                Write-Log "  [ERROR] No se pudo limpiar: $destino - $_" "ERROR" "Red"
            }
        }
    }

    # Paso 5: Copiar carpetas a sus destinos
    if (Test-Path $Carpeta1) {
        try {
            Copy-Item $Carpeta1 -Destination $DestImagenes -Recurse -Force
            Write-Log "  [OK] Copiado: Fi-2603 -> $DestImagenes" "INFO" "Green"
            $seccion01OK = $true
        } catch {
            Write-Log "  [ERROR] Copia fallida Fi-2603: $_" "ERROR" "Red"
        }
    }
    if (Test-Path $Carpeta2) {
        try {
            Copy-Item $Carpeta2 -Destination $DestDocumentos -Recurse -Force
            Write-Log "  [OK] Copiado: Automatico -> $DestDocumentos" "INFO" "Green"
            $seccion01OK = $true
        } catch {
            Write-Log "  [ERROR] Copia fallida Automatico: $_" "ERROR" "Red"
        }
    }

    # Paso 6: Limpiar temporales
    Remove-Item $ZipLocal    -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  [OK] Temporales de descarga eliminados." "INFO" "Gray"

} catch {
    Write-Log "  [ERROR] Fallo la descarga desde GitHub: $_" "ERROR" "Red"
    Write-Log "  Verificar conexion a internet y que el repo sea publico." "WARN" "Yellow"
    # Crear estructura minima para que el resto del script no falle
    $dirBase = "C:\Users\Public\Documents\Automatico"
    if (-not (Test-Path $dirBase)) {
        New-Item -ItemType Directory -Path $dirBase -Force | Out-Null
        Write-Log "  [OK] Directorio minimo creado: $dirBase" "INFO" "Yellow"
    }
}

Write-Log "  Descarga OK: $seccion01OK" "INFO" "Cyan"
Write-Log "--- [SECCION 01] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 02 - LIMPIAR CACHE DNS
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 02: LIMPIAR CACHE DNS ---" "INFO" "Yellow"
try {
    Clear-DnsClientCache
    Write-Log "  [OK] Cache DNS limpiado." "INFO" "Green"
} catch {
    Write-Log "  [WARN] No se pudo limpiar cache DNS: $_" "WARN" "Yellow"
}
Write-Log "--- [SECCION 02] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 03 - INSTALAR CHOCOLATEY
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 03: INSTALAR CHOCOLATEY ---" "INFO" "Yellow"
try {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $chocoVer = choco --version 2>$null
        Write-Log "  [OK] Chocolatey ya instalado. Version: $chocoVer" "INFO" "Green"
    } else {
        Write-Log "  Instalando Chocolatey..." "INFO" "Yellow"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "  [OK] Chocolatey instalado correctamente." "INFO" "Green"
        } else {
            Write-Log "  [ERROR] Chocolatey no quedo disponible tras la instalacion." "ERROR" "Red"
        }
    }
} catch {
    Write-Log "  [ERROR] Fallo al instalar Chocolatey: $_" "ERROR" "Red"
    Write-Log "  Continuando - la Seccion 04 sera omitida." "WARN" "Yellow"
}
Write-Log "--- [SECCION 03] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 04 - INSTALACION DE APLICACIONES CON CHOCOLATEY
# Grupos por prioridad con reintentos y segunda pasada para fallidos
#
# SOBRE EL XML DE CONFIG:
#   Si el XML tiene <package id="vlc" version="3.0.20" /> se usa esa version
#   Si el XML tiene <package id="vlc" /> (sin version) se instala la ultima
#   Si el paquete no esta en el XML pero si en los grupos, se instala la ultima
#   NUNCA se pasa "latest" como string al flag --version (bug del original)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 04: INSTALACION DE APLICACIONES ---" "INFO" "Magenta"

$automaticoPath = "C:\Users\Public\Documents\Automatico"
$configPath     = "$automaticoPath\InstallAppsDESKTOP-Automatico0.config"

# Grupos de instalacion por prioridad (nombre alfabetico = orden de ejecucion)
$gruposPrioridad = @{
    "Grupo1_Base" = @{
        Descripcion        = "Chocolatey Core y Extensiones"
        Paquetes           = @(
            "chocolatey",
            "chocolatey-core.extension",
            "chocolatey-compatibility.extension",
            "chocolatey-dotnetfx.extension",
            "chocolatey-windowsupdate.extension"
        )
        MaxReintentos      = 2
        EsperaEntreReintentos = 3
    }
    "Grupo2_Windows" = @{
        Descripcion        = "Windows Updates y KBs"
        Paquetes           = @(
            "KB2919355", "KB2919442", "KB2999226",
            "KB3033929", "KB3035131", "KB3118401"
            # KB5066188 se maneja en Script 2 (Windows Update)
        )
        MaxReintentos      = 3
        EsperaEntreReintentos = 5
    }
    "Grupo3_Runtime" = @{
        Descripcion        = ".NET Framework y Visual C++ Redistributables"
        Paquetes           = @(
            "dotnetfx",
            "vcredist2015",
            "vcredist2017",
            "vcredist140"
        )
        MaxReintentos      = 3
        EsperaEntreReintentos = 5
    }
    "Grupo4_DotNet" = @{
        Descripcion        = ".NET Runtime y Desktop Runtime"
        Paquetes           = @(
            "dotnet-8.0-runtime",
            "dotnet-8.0-desktopruntime",
            "dotnet-9.0-runtime",
            "dotnet-runtime",
            "dotnet"
        )
        MaxReintentos      = 3
        EsperaEntreReintentos = 5
    }
    "Grupo5_PowerShell" = @{
        Descripcion        = "PowerShell 7 (para los scripts 2 al 5)"
        Paquetes           = @("powershell-core")
        MaxReintentos      = 2
        EsperaEntreReintentos = 5
    }
    "Grupo6_Apps" = @{
        Descripcion        = "Aplicaciones de trabajo"
        Paquetes           = @(
            "notepadplusplus.install",
            "rustdesk.install",
            "kdeconnect-kde"
        )
        MaxReintentos      = 3
        EsperaEntreReintentos = 5
    }
}

# Solo continuar si choco esta disponible
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "  [SKIP] Chocolatey no disponible. Saltando Seccion 04." "WARN" "Yellow"
} else {

    if (Test-Path $automaticoPath) { Set-Location $automaticoPath }

    # Parsear XML de config (versiones opcionales)
    $versionesXml = @{}
    if (Test-Path $configPath) {
        try {
            [xml]$xml = Get-Content $configPath -Encoding UTF8
            foreach ($pkg in $xml.packages.package) {
                # Solo guardar version si el atributo existe y no esta vacio
                if ($pkg.version -and $pkg.version -ne "") {
                    $versionesXml[$pkg.id] = $pkg.version
                }
                # Si no tiene version, no se agrega al hash -> se instalara latest
            }
            Write-Log "  [OK] XML config cargado. Paquetes con version especifica: $($versionesXml.Count)" "INFO" "Green"
        } catch {
            Write-Log "  [ERROR] No se pudo parsear el XML config: $_" "ERROR" "Red"
        }
    } else {
        Write-Log "  [INFO] XML config no encontrado ($configPath). Se instalara la ultima version de todo." "INFO" "Yellow"
    }

    # Estadisticas globales
    $stats = @{ Exitosos = 0; Fallidos = 0; Total = 0; GruposOK = 0; GruposFail = 0 }

    # BUG CORREGIDO: inicializar antes del loop para evitar error si no hay fallidos
    $fallidos          = @()
    $aunFallan         = @()

    # Loop principal por grupos
    foreach ($grupoNombre in ($gruposPrioridad.Keys | Sort-Object)) {
        $grupo    = $gruposPrioridad[$grupoNombre]
        $paquetes = $grupo.Paquetes

        Write-Log "" "INFO" "White"
        Write-Log "  [GROUP] $grupoNombre - $($grupo.Descripcion)" "INFO" "Magenta"
        Write-Log "  Paquetes: $($paquetes.Count) | Reintentos max: $($grupo.MaxReintentos)" "INFO" "Cyan"

        $okGrupo   = 0
        $failGrupo = 0

        foreach ($pkgId in $paquetes) {
            # Obtener version: del XML si existe, sino instala latest (string vacio)
            $ver = if ($versionesXml.ContainsKey($pkgId)) { $versionesXml[$pkgId] } else { "" }

            $ok = Install-ChocoPackage -PackageId $pkgId -PackageVersion $ver `
                                       -MaxReintentos $grupo.MaxReintentos `
                                       -EsperaSegundos $grupo.EsperaEntreReintentos
            $stats.Total++
            if ($ok) { $okGrupo++;   $stats.Exitosos++ }
            else      { $failGrupo++; $stats.Fallidos++; $fallidos += @{ Id = $pkgId; Version = $ver; Grupo = $grupoNombre } }
        }

        if ($failGrupo -eq 0) {
            Write-Log "  [OK] ${grupoNombre}: ${okGrupo}/$($paquetes.Count) exitosos" "INFO" "Green"
            $stats.GruposOK++
        } else {
            Write-Log "  [PARCIAL] ${grupoNombre}: ${okGrupo} ok, ${failGrupo} fallidos" "WARN" "Yellow"
            $stats.GruposFail++
        }

        # Pausa entre grupos (excepto el ultimo)
        if ($grupoNombre -ne ($gruposPrioridad.Keys | Sort-Object | Select-Object -Last 1)) {
            Start-Sleep -Seconds 3
        }
    }

    # Segunda pasada para fallidos
    if ($fallidos.Count -gt 0) {
        Write-Log "" "INFO" "White"
        Write-Log "  [RETRY] SEGUNDA PASADA - $($fallidos.Count) paquetes fallidos" "INFO" "Magenta"

        $recuperados = 0
        foreach ($pkg in $fallidos) {
            $ok = Install-ChocoPackage -PackageId $pkg.Id -PackageVersion $pkg.Version -MaxReintentos 2 -EsperaSegundos 5
            if ($ok) {
                $recuperados++
                $stats.Exitosos++
                $stats.Fallidos--
                Write-Log "  [RECOVERED] $($pkg.Id) recuperado en segunda pasada." "INFO" "Green"
            } else {
                $aunFallan += $pkg
            }
        }
        Write-Log "  Segunda pasada: $recuperados recuperados, $($aunFallan.Count) aun fallan." "INFO" "Cyan"
    }

    # Resumen final
    Write-Log "" "INFO" "White"
    Write-Log "  =========== RESUMEN INSTALACION ===========" "INFO" "Magenta"
    Write-Log "  Total procesados : $($stats.Total)"    "INFO" "White"
    Write-Log "  Exitosos         : $($stats.Exitosos)" "INFO" "Green"
    Write-Log "  Fallidos         : $($stats.Fallidos)" "INFO" "Red"
    Write-Log "  Tasa de exito    : $(if($stats.Total -gt 0){[math]::Round($stats.Exitosos/$stats.Total*100,1)}else{0})%" "INFO" "Cyan"

    if ($aunFallan.Count -gt 0) {
        Write-Log "  PAQUETES CON ATENCION MANUAL REQUERIDA:" "WARN" "Yellow"
        foreach ($pkg in $aunFallan) {
            Write-Log "    - $($pkg.Id) [$($pkg.Grupo)]" "WARN" "White"
        }
    } else {
        Write-Log "  TODOS LOS PAQUETES INSTALADOS CORRECTAMENTE" "INFO" "Green"
    }
}

Write-Log "--- [SECCION 04] Completada ---" "INFO" "Magenta"

# ==============================================================================
# SECCION 05 - COPIAR ARCHIVO ESPAÑOL PARA NOTEPAD++
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 05: ARCHIVO ESPAÑOL NOTEPAD++ ---" "INFO" "Yellow"

$nppSpanishOrigen = "C:\Users\Public\Documents\Automatico\Tu-pc-va-a-volar\spanish.xml"
$nppDir           = "C:\Program Files\Notepad++"
$nppLocalization  = "$nppDir\localization"

if (-not (Test-Path $nppSpanishOrigen)) {
    Write-Log "  [WARN] spanish.xml no encontrado en: $nppSpanishOrigen" "WARN" "Yellow"
} elseif (-not (Test-Path $nppDir)) {
    Write-Log "  [WARN] Notepad++ no esta instalado. Saltando copia de spanish.xml." "WARN" "Yellow"
} else {
    try {
        if (-not (Test-Path $nppLocalization)) {
            New-Item -ItemType Directory -Path $nppLocalization -Force | Out-Null
        }
        Copy-Item $nppSpanishOrigen -Destination $nppLocalization -Force
        Write-Log "  [OK] spanish.xml copiado a: $nppLocalization" "INFO" "Green"
    } catch {
        Write-Log "  [ERROR] No se pudo copiar spanish.xml: $_" "ERROR" "Red"
    }
}

Write-Log "--- [SECCION 05] Completada ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  1Fi-2601_AutomaticoClaude.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Log guardado en : $global:LogFile" "INFO" "Cyan"
Write-Log "Errores en      : $global:ErrorLog" "INFO" "Cyan"
Write-Log "" "INFO" "White"
Write-Log "SIGUIENTE PASO: Script 2 - 2RenameLaptop-Desktop-Claude.ps1" "INFO" "White"
Write-Log "Iniciando en 6 segundos en PowerShell 7..." "INFO" "Yellow"

Start-Sleep -Seconds 6

# Llamado al Script 2 desde PS5 -> PS7
# IMPORTANTE: pwsh.exe recien instalado en este mismo script NO esta en PATH
# todavia (requeriria nueva sesion). Usamos la ruta fija de instalacion de PS7.
$pwsh7Paths = @(
    "$env:ProgramFiles\PowerShell\7\pwsh.exe",
    "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
)
$pwsh7 = $pwsh7Paths | Where-Object { Test-Path $_ } | Select-Object -First 1

$script2 = "C:\Users\Public\Documents\Automatico\2RenameLaptop-Desktop-Claude.ps1"

if (-not $LlamarScript2) {
    Write-Log "  [i] Llamado al Script 2 desactivado (LlamarScript2 = false)" "INFO" "Gray"
} elseif (-not $pwsh7) {
    Write-Log "  [WARN] pwsh.exe (PS7) no encontrado en rutas conocidas." "WARN" "Yellow"
    Write-Log "  Puede que requiera cerrar y reabrir sesion para que quede en PATH." "WARN" "Yellow"
    Write-Log "  Ejecuta manualmente en PS7: $script2" "INFO" "White"
} elseif (-not (Test-Path $script2)) {
    Write-Log "  [WARN] Script 2 no encontrado en: $script2" "WARN" "Yellow"
    Write-Log "  Ejecutalo manualmente en PowerShell 7 cuando estes listo." "INFO" "White"
} else {
    Write-Log "Lanzando Script 2 en PowerShell 7: $pwsh7" "INFO" "Cyan"
    Start-Process $pwsh7 `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$script2`"" `
        -Verb RunAs `
        -Wait
}
Write-Log "" "INFO" "White"