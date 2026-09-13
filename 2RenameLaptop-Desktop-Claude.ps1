# ==============================================================================
# Nombre Script: "2RenameLaptop-Desktop-Claude.ps1" version 5
# Basado en: "2RenameLaptop-Desktop-Claude.ps1" version 4
# Reescrito por: Claude (Anthropic) - 2026-09-12
# Requiere: PowerShell 7 | Administrador | W10/W11 IoT LTSC
# ==============================================================================
#
# CAMBIOS v5 (2026-09-12):
#
#  [REDISENO] Sec1 Office: instalacion simplificada a CMD + setup.exe, el
#             chequeo de "ya instalado" bajo de ~25 lineas a 2.
#
#  [REDISENO] Sec2 rename de usuario: la cuenta "Pomelo" NUNCA se renombra
#             (no hay Rename-LocalUser). Lo unico que cambia es el FullName
#             (lo que Windows Hello muestra en pantalla de bienvenida, igual
#             que "Cambiar nombre" en netplwiz). El nombre ya no se pregunta
#             aca: se lee de RespuestasDespliegue.json, escrito por el S1 en
#             su Seccion 00 (con fallback a Read-Host si el archivo no esta,
#             para poder seguir corriendo este script de forma standalone).
#
#  [REDISENO] Sec3 rename de equipo: como la cuenta nunca cambia de nombre
#             (Pomelo -> Pomelo siempre), el hostname ahora se arma con el
#             FullName leido en Sec2, no con el Name de la cuenta local.
#
#  [BUG 3/4 YA NO APLICA] El cacheo del tipo de chasis al inicio del script
#             (ver v4) existia porque Rename-LocalUser invalidaba el token
#             SID de la sesion y rompia Get-CimInstance despues. Como ya no
#             se renombra la cuenta, el token nunca se invalida - se saca el
#             cacheo temprano y la deteccion de chasis se hace directo en
#             Sec3, donde se usa.
#
#  [REDISENO] Fin de script: llama a Script 3 pasando -ModoCadena, para que
#             S3 corra las 20 secciones sin preguntar (el menu de seleccion
#             de secciones queda solo para cuando corres S3 vos solo).
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "2Rename_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "2Rename_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
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

# Funcion auxiliar: limpiar nombre para usar en nombre de equipo
# Solo letras, numeros y guiones - maximo 7 caracteres - mayusculas
function Get-CleanComputerPrefix {
    param([string]$Name)
    $clean = $Name -replace '[^a-zA-Z0-9-]', ''
    $clean = ($clean.Substring(0, [Math]::Min(7, $clean.Length))).ToUpper()
    return $clean
}

# ==============================================================================
# INTERRUPTORES - Modificar segun necesidad antes de ejecutar
# ==============================================================================
$LlamarScript3 = $true    # $true  = llama al Script 3 al finalizar (normal)
                           # $false = termina sin llamar al Script 3 (debug)
# ==============================================================================

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  2RenameLaptop-Desktop-Claude-v5.ps1  INICIO" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Usuario  : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Log      : $global:LogFile" "INFO" "Cyan"

# Verificar PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log "ERROR: Este script requiere PowerShell 7 o superior." "ERROR" "Red"
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

# ==============================================================================
# LEER NOMBRE PARA WINDOWS HELLO (pedido por S1 en su Seccion 00)
# Fallback a Read-Host si el archivo no existe, para poder correr este
# script de forma standalone sin haber pasado por el S1.
# ==============================================================================
$nuevoUsuario = $null
if (Test-Path $global:RespuestasFile) {
    try {
        $respuestas = Get-Content $global:RespuestasFile -Raw | ConvertFrom-Json
        $nuevoUsuario = $respuestas.NuevoUsuario
        Write-Log "Nombre Windows Hello leido de RespuestasDespliegue.json: $nuevoUsuario" "INFO" "Green"
    } catch {
        Write-Log "[WARN] No se pudo leer RespuestasDespliegue.json: $_" "WARN" "Yellow"
    }
}
if ([string]::IsNullOrWhiteSpace($nuevoUsuario)) {
    Write-Log "[WARN] Sin nombre disponible. Preguntando (modo standalone)." "WARN" "Yellow"
    $nuevoUsuario = Read-Host "Nombre para Windows Hello (ej: 'SuperLili')"
}

# ==============================================================================
# SECCION 1 - INSTALAR OFFICE LTSC 2021
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 1: INSTALAR OFFICE LTSC 2021 ---" "INFO" "Yellow"

$officeDir = "C:\Users\Public\Documents\Automatico\Office-LTSC-2021"

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration") {
    Write-Log "  [OK] Office ya instalado. Saltando." "INFO" "Green"
} elseif (-not (Test-Path "$officeDir\setup.exe")) {
    Write-Log "  [WARN] setup.exe no encontrado en: $officeDir" "WARN" "Yellow"
} else {
    Write-Log "  Instalando Office LTSC 2021..." "INFO" "Yellow"
    cmd /c "cd /d `"$officeDir`" && setup.exe /configure configuration.xml"
    Write-Log "  [OK] Office lanzado via CMD (ExitCode: $LASTEXITCODE)." "INFO" "Green"
}

Write-Log "--- [SECCION 1] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 2 - NOMBRE PARA WINDOWS HELLO (FullName, Pomelo se queda como cuenta)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 2: NOMBRE WINDOWS HELLO ---" "INFO" "Yellow"

try {
    $pomeloUser = Get-LocalUser -Name "Pomelo" -ErrorAction SilentlyContinue

    if (-not $pomeloUser) {
        Write-Log "  [WARN] La cuenta 'Pomelo' no existe en este equipo." "WARN" "Yellow"
    } elseif ($pomeloUser.FullName -eq $nuevoUsuario) {
        Write-Log "  [OK] FullName ya es '$nuevoUsuario'. Nada que hacer." "INFO" "Green"
    } else {
        Set-LocalUser -Name "Pomelo" -FullName $nuevoUsuario -ErrorAction Stop
        Write-Log "  [OK] FullName de 'Pomelo' actualizado a '$nuevoUsuario'." "INFO" "Green"
    }
} catch {
    Write-Log "  [ERROR] No se pudo actualizar el FullName: $_" "ERROR" "Red"
}

Write-Log "--- [SECCION 2] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 3 - RENOMBRAR EQUIPO SEGUN NOMBRE Y TIPO DE CHASIS
# Formato: LAPTOP-NOMBRE o DESKTOP-NOMBRE (7 chars del nombre)
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 3: RENOMBRAR EQUIPO ---" "INFO" "Yellow"

$renameOK = $false

# --- Generar prefijo limpio a partir del nombre para Windows Hello ---
$userPrefix = Get-CleanComputerPrefix -Name $nuevoUsuario
Write-Log "  Prefijo generado: $userPrefix (de '$nuevoUsuario')" "INFO" "Cyan"

# --- Verificar nombre actual ---
$currentName  = $env:COMPUTERNAME
$validFormats = @("LAPTOP-$userPrefix", "DESKTOP-$userPrefix")

if ($currentName -in $validFormats) {
    Write-Log "  [OK] Nombre actual '$currentName' ya tiene el formato correcto." "INFO" "Green"
    $renameOK = $true
} else {
    Write-Log "  Nombre actual: $currentName -> necesita cambio" "INFO" "Yellow"

    # --- Tipo de chasis: se detecta aca directo (ya no hace falta cachear ---
    # --- al inicio del script, porque la cuenta nunca se renombra y el   ---
    # --- token SID de la sesion nunca se invalida)                       ---
    $chassisPrefix = "DESKTOP-"
    try {
        $chassisObj   = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        $laptopTypes  = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
        $esLaptop     = $chassisObj.ChassisTypes | Where-Object { $_ -in $laptopTypes }
        $chassisPrefix = if ($esLaptop) { "LAPTOP-" } else { "DESKTOP-" }
        Write-Log "  Tipo de chasis detectado: $($chassisObj.ChassisTypes -join ', ') -> $chassisPrefix" "INFO" "Cyan"
    } catch {
        Write-Log "  [WARN] No se pudo detectar chasis: $_. Se usa DESKTOP- como fallback." "WARN" "Yellow"
    }

    $newComputerName = "$chassisPrefix$userPrefix"

    if ($newComputerName.Length -gt 63) {
        Write-Log "  [ERROR] Nombre '$newComputerName' excede 63 caracteres. Rename cancelado." "ERROR" "Red"
    } elseif ($newComputerName -eq $currentName) {
        Write-Log "  [OK] Nombre '$newComputerName' ya coincide con el actual." "INFO" "Green"
        $renameOK = $true
    } else {
        # Rename via registro (no via Rename-Computer/WMI) - practica ya probada
        try {
            $regComputerName       = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName"
            $regActiveComputerName = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName"
            $regTcpip              = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

            Set-ItemProperty -Path $regComputerName -Name "ComputerName" -Value $newComputerName -Force -ErrorAction Stop
            Set-ItemProperty -Path $regTcpip         -Name "Hostname"     -Value $newComputerName -Force -ErrorAction Stop
            Set-ItemProperty -Path $regTcpip         -Name "NV Hostname"  -Value $newComputerName -Force -ErrorAction Stop

            try {
                Set-ItemProperty -Path $regActiveComputerName -Name "ComputerName" -Value $newComputerName -Force -ErrorAction Stop
            } catch {
                Write-Log "  [INFO] ActiveComputerName no modificado (no critico): $_" "INFO" "Cyan"
            }

            Write-Log "  [OK] Equipo renombrado en registro: '$currentName' -> '$newComputerName'" "INFO" "Green"
            Write-Log "  [INFO] El nuevo nombre se aplica completamente al reiniciar." "INFO" "Cyan"
            $renameOK = $true
        } catch {
            Write-Log "  [ERROR] No se pudo renombrar el equipo en registro: $_" "ERROR" "Red"
        }
    }
}

Write-Log "--- [SECCION 3] Completada ---" "INFO" "Yellow"

# ==============================================================================
# FIN DEL SCRIPT
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  2RenameLaptop-Desktop-Claude-v5.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Rename OK  : $renameOK" "INFO" "Cyan"
Write-Log "Log        : $global:LogFile" "INFO" "Cyan"
Write-Log "" "INFO" "White"

if ($LlamarScript3) {
    Write-Log "SIGUIENTE PASO: Script 3 - 3TuPcVolaraClaude.ps1 (modo cadena, sin preguntar secciones)" "INFO" "White"
    Write-Log "Iniciando en 6 segundos..." "INFO" "Yellow"
    Start-Sleep -Seconds 6

    $script3 = "C:\Users\Public\Documents\Automatico\3TuPcVolaraClaude.ps1"
    if (Test-Path $script3) {
        Write-Log "Ejecutando Script 3 con -ModoCadena: $script3" "INFO" "Cyan"
        & $script3 -ModoCadena
    } else {
        Write-Log "[WARN] Script 3 no encontrado en: $script3" "WARN" "Yellow"
        Write-Log "Ejecutalo manualmente cuando estes listo." "INFO" "White"
    }
} else {
    Write-Log "LlamarScript3 = false. Fin sin llamar al Script 3." "INFO" "Yellow"
}
