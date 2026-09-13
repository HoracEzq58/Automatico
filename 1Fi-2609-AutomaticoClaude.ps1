# ==============================================================================
# Nombre Script: "1Fi-2609-AutomaticoClaude.ps1" version 6 (unificada) 12/09/2026
# Basado en: "1Fi-2601-AutomaticoClaude.ps1"
# Reescrito por: Claude (Anthropic) - 2026-09-12
# Requiere: PowerShell 5 (compatible con W10 IoT LTSC recien instalado)
# Ejecutar como: Administrador
# ==============================================================================
#
# CAMBIOS vs version anterior (1Fi-2601):
#
#  [REDISENO] Front-loading total: esta es la UNICA seccion de toda la cadena
#             S1-S4 que le pregunta algo al operador. Se agrega la SECCION 00
#             que pide el nombre para Windows Hello (FullName, NO renombra la
#             cuenta "Pomelo") y lo guarda en un archivo compartido para que
#             el S2 lo lea sin volver a preguntar. Motivo: dejar el despliegue
#             corriendo sin supervision (S1 arranca, S1-S4 terminan solos).
#
#  [REDISENO] Repo de imagenes: Fi-2603 -> Fi-2609 (actualizado 2026-09).
#
#  [REDISENO] SECCION 04 (instalacion de apps con grupos de prioridad) y
#             SECCION 05 (copiar spanish.xml de Notepad++) se ELIMINAN de
#             este script. Los paquetes ahora se instalan todos juntos desde
#             un unico config maestro en el S4 (que ya tiene su propio
#             control de faltantes). El spanish.xml no hace falta copiarlo:
#             el paquete de Notepad++ ya trae esa localizacion incluida de
#             fabrica en su carpeta "localization".
#
#  [REDISENO] SECCION 03: en vez de dejar la puerta abierta a instalar apps
#             con Chocolatey aca, se limita a instalar SOLO powershell-core
#             (pwsh7), que es lo unico que el resto de la cadena (S2-S4)
#             necesita para poder ejecutarse. Todo lo demas vive en el config
#             maestro que corre el S4.
#
# ==============================================================================
# PROBLEMAS ENCONTRADOS Y CORREGIDOS (heredados de v1, se mantienen resueltos):
#
#  [MEJORA 1] Sec.01 - WMI alternativo busca solo DriveType 2 (removible)
#  [MEJORA 3] General - Modularizado: cada seccion es autocontenida
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "Fi-2609_Install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "Fi-2609_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Archivo compartido de respuestas: lo escribe S1, lo leen S2 (y en el futuro
# cualquier otro script de la cadena que necesite algo pedido al operador).
$global:RespuestasFile = Join-Path $global:LogPath "RespuestasDespliegue.json"

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
# INTERRUPTORES - Modificar segun necesidad antes de ejecutar
# ==============================================================================
$LlamarScript2 = $true    # $true  = llama al Script 2 al finalizar (normal)
                          # $false = termina sin llamar al Script 2 (debug)
# ==============================================================================

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  1Fi-2609_AutomaticoClaude.ps1  INICIO" "INFO" "Magenta"
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
# SECCION 00 - PREGUNTAS AL OPERADOR (UNICA seccion interactiva de S1-S4)
# Todo lo que el resto de la cadena podria necesitar preguntar se pide ACA,
# al comienzo, para poder dejar el equipo desatendido hasta que termine S4.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 00: DATOS DEL CLIENTE ---" "INFO" "Yellow"

$nuevoUsuario = Read-Host "Nombre para Windows Hello (pantalla de bienvenida, ej: 'Familia Perez')"
while ([string]::IsNullOrWhiteSpace($nuevoUsuario)) {
    Write-Log "  [WARN] El nombre no puede quedar vacio." "WARN" "Yellow"
    $nuevoUsuario = Read-Host "Nombre para Windows Hello"
}

$respuestas = @{
    NuevoUsuario = $nuevoUsuario.Trim()
    FechaPedido  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

try {
    $respuestas | ConvertTo-Json | Set-Content -Path $global:RespuestasFile -Encoding UTF8
    Write-Log "  [OK] Respuestas guardadas en: $global:RespuestasFile" "INFO" "Green"
    Write-Log "  Nombre Windows Hello -> $($respuestas.NuevoUsuario)" "INFO" "Cyan"
} catch {
    Write-Log "  [ERROR] No se pudo guardar el archivo de respuestas: $_" "ERROR" "Red"
    Write-Log "  El S2 va a preguntar el nombre de nuevo si esto fallo." "WARN" "Yellow"
}

Write-Log "--- [SECCION 00] Completada. De aca en mas, el despliegue no pregunta nada mas. ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 01 - DESCARGAR ARCHIVOS DESDE GITHUB
# Descarga DOS repos publicos como ZIP y los copia a sus destinos.
# Sin Git, sin pendrive. Compatible PS5.
#
# REPO 1: HoracEzq58/Automatico -> C:\Users\Public\Documents\Automatico\
# REPO 2: HoracEzq58/Fi-2609    -> C:\Users\Public\Pictures\Fi-2609\
#
# NOTA: GitHub genera el ZIP con una carpeta raiz llamada "NombreRepo-main\"
#       Su contenido ES el destino final, no una subcarpeta dentro de el.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 01: DESCARGAR ARCHIVOS DESDE GITHUB ---" "INFO" "Yellow"

$GitHubUser     = "HoracEzq58"
$GitHubBranch   = "main"
$DestImagenes   = "C:\Users\Public\Pictures"
$DestDocumentos = "C:\Users\Public\Documents"

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Invoke-DescargarRepo {
    param(
        [string]$NombreRepo,
        [string]$DestPadre
    )

    $ZipUrl      = "https://github.com/$GitHubUser/$NombreRepo/archive/refs/heads/$GitHubBranch.zip"
    $ZipLocal    = "$env:TEMP\$NombreRepo-github.zip"
    $ExtractPath = "$env:TEMP\$NombreRepo-github"
    $RepoFolder  = "$ExtractPath\$NombreRepo-$GitHubBranch"
    $Destino     = "$DestPadre\$NombreRepo"

    Write-Log "  [REPO] $NombreRepo -> $Destino" "INFO" "Yellow"

    try {
        if (Test-Path $ZipLocal)    { Remove-Item $ZipLocal    -Force }
        if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }

        Write-Log "    Descargando: $ZipUrl" "INFO" "Yellow"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($ZipUrl, $ZipLocal)
        Write-Log "    [OK] ZIP descargado ($([math]::Round((Get-Item $ZipLocal).Length/1KB,1)) KB)" "INFO" "Green"

        Write-Log "    Extrayendo..." "INFO" "Yellow"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipLocal, $ExtractPath)
        Write-Log "    [OK] ZIP extraido." "INFO" "Green"

        if (-not (Test-Path $RepoFolder)) {
            Write-Log "    [ERROR] Carpeta esperada no encontrada: $RepoFolder" "ERROR" "Red"
            Get-ChildItem $ExtractPath -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Log "      $($_.Name)" "WARN" "Yellow"
            }
            return $false
        }

        if (Test-Path $Destino) {
            Remove-Item $Destino -Recurse -Force
            Write-Log "    [OK] Destino anterior limpiado: $Destino" "INFO" "Yellow"
        }

        Copy-Item $RepoFolder -Destination $Destino -Recurse -Force
        Write-Log "    [OK] Copiado a: $Destino" "INFO" "Green"
        return $true

    } catch {
        Write-Log "    [ERROR] Fallo descarga/copia de $NombreRepo : $_" "ERROR" "Red"
        return $false
    } finally {
        Remove-Item $ZipLocal    -Force -ErrorAction SilentlyContinue
        Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "" "INFO" "White"
Write-Log "  [1/2] Repo Automatico (scripts)" "INFO" "Magenta"
$ok1 = Invoke-DescargarRepo -NombreRepo "Automatico" -DestPadre $DestDocumentos

if (-not $ok1) {
    Write-Log "  [WARN] Repo Automatico fallo. Creando directorio minimo." "WARN" "Yellow"
    $dirBase = "$DestDocumentos\Automatico"
    if (-not (Test-Path $dirBase)) {
        New-Item -ItemType Directory -Path $dirBase -Force | Out-Null
    }
}

Write-Log "" "INFO" "White"
Write-Log "  [2/2] Repo Fi-2609 (imagenes cliente)" "INFO" "Magenta"
$ok2 = Invoke-DescargarRepo -NombreRepo "Fi-2609" -DestPadre $DestImagenes

Write-Log "" "INFO" "White"
Write-Log "  Resultado -> Automatico: $(if($ok1){'OK'}else{'FALLO'}) | Fi-2609: $(if($ok2){'OK'}else{'FALLO'})" "INFO" "Cyan"
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
# SECCION 03 - INSTALAR CHOCOLATEY + POWERSHELL 7
# Unico proposito: dejar disponible pwsh7, que es lo que S2/S3/S4 necesitan
# para poder correr. Nada de apps de cliente aca (eso lo hace el S4 con el
# config maestro unico).
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 03: CHOCOLATEY + POWERSHELL 7 ---" "INFO" "Yellow"
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

    if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
        Write-Log "  [OK] PowerShell 7 ya instalado." "INFO" "Green"
    } else {
        Write-Log "  Instalando powershell-core (pwsh7) via Choco..." "INFO" "Yellow"
        choco install powershell-core -y --no-progress
        if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
            Write-Log "  [OK] PowerShell 7 instalado correctamente." "INFO" "Green"
        } else {
            Write-Log "  [ERROR] pwsh.exe no aparecio tras la instalacion." "ERROR" "Red"
        }
    }
} catch {
    Write-Log "  [ERROR] Fallo instalando Chocolatey/pwsh7: $_" "ERROR" "Red"
    Write-Log "  Sin pwsh7 la cadena no puede continuar. Revisar antes de seguir." "WARN" "Yellow"
}
Write-Log "--- [SECCION 03] Completada ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  1Fi-2609_AutomaticoClaude.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Log guardado en : $global:LogFile" "INFO" "Cyan"
Write-Log "Errores en      : $global:ErrorLog" "INFO" "Cyan"
Write-Log "" "INFO" "White"
Write-Log "SIGUIENTE PASO: Script 2 - 2RenameLaptop-Desktop-Claude.ps1" "INFO" "White"
Write-Log "Iniciando en 6 segundos en PowerShell 7..." "INFO" "Yellow"

Start-Sleep -Seconds 6

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
