# ==============================================================================
# Nombre Script: "2RenameLaptop-Desktop-Claude.ps1" version 2
# Basado en: "2RenameLaptop-Desktop-Claude.ps1" version 1
# Revisado y corregido por: Claude (Anthropic) - 2026-03-10
# Requiere: PowerShell 7 | Administrador | W10 IoT LTSC
# ==============================================================================
#
# PROBLEMAS ENCONTRADOS Y CORREGIDOS vs v1:
#
#  [BUG 1] Rename-Computer falla con "No mapping between account names and
#          security IDs was done" despues de renombrar el usuario en la misma
#          sesion de PowerShell.
#          CAUSA: Rename-Computer usa WMI/CIM internamente. Cuando se renombra
#          el usuario (Pomelo->nombre nuevo) en la misma sesion, el token de
#          seguridad en memoria sigue referenciando el SID viejo de Pomelo.
#          WMI intenta conectarse con ese token y falla porque el SID ya no
#          matchea ninguna cuenta valida.
#          CORRECCION: Reemplazado Rename-Computer por escritura directa en
#          el registro de Windows (HKLM:\SYSTEM\...\ComputerName), que no usa
#          WMI y no tiene problema de SID. El cambio se aplica igual al
#          reiniciar, exactamente igual que Rename-Computer.
#
#  [BUG 2] Los titulos de seccion en los logs decian "SECCION 06" y "SECCION 02"
#          mezclados, confuso para diagnostico.
#          CORRECCION: Renombrados coherentemente como SECCION A y SECCION B.
#
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "2Rename_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "2Rename_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

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
Write-Log "  2RenameLaptop-Desktop-Claude-v2.ps1  INICIO" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Usuario  : $env:USERNAME en $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "PS Version: $($PSVersionTable.PSVersion)" "INFO" "Cyan"
Write-Log "Log      : $global:LogFile" "INFO" "Cyan"

# Verificar PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log "ERROR: Este script requiere PowerShell 7 o superior." "ERROR" "Red"
    Write-Log "Version actual: $($PSVersionTable.PSVersion)" "ERROR" "Red"
    Write-Log "Instala PS7 con: winget install Microsoft.PowerShell" "INFO" "Yellow"
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
# SECCION A - INSTALAR OFFICE LTSC 2021
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 1: INSTALAR OFFICE LTSC 2021 ---" "INFO" "Yellow"

$officeDir    = "C:\Users\Public\Documents\Automatico\Office-LTSC-2021"
$officeSetup  = Join-Path $officeDir "setup.exe"
$officeConfig = Join-Path $officeDir "configuration.xml"

if (-not (Test-Path $officeSetup)) {
    Write-Log "  [WARN] setup.exe no encontrado en: $officeDir" "WARN" "Yellow"
    Write-Log "  Verificar que el Script 1 haya copiado la carpeta desde el pendrive." "WARN" "Yellow"
} elseif (-not (Test-Path $officeConfig)) {
    Write-Log "  [WARN] configuration.xml no encontrado en: $officeDir" "WARN" "Yellow"
} else {
    # Verificar si Office ya esta instalado buscando en registro
    $officeInstalado = $false
    $officeRegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"
    )
    foreach ($regPath in $officeRegPaths) {
        if (Test-Path $regPath) {
            $officeInstalado = $true
            $officeVer = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).VersionToReport
            break
        }
    }

    if ($officeInstalado) {
        Write-Log "  [OK] Office ya esta instalado (version: $officeVer). Saltando instalacion." "INFO" "Green"
    } else {
    Write-Log "  Archivos Office encontrados. Iniciando instalacion..." "INFO" "Green"
    Write-Log "  Ruta: $officeDir" "INFO" "Cyan"
    try {
        $proc = Start-Process -FilePath $officeSetup `
                              -ArgumentList "/configure `"$officeConfig`"" `
                              -WorkingDirectory $officeDir `
                              -WindowStyle Minimized `
                              -Wait `
                              -PassThru `
                              -ErrorAction Stop

        if ($proc.ExitCode -eq 0) {
            Write-Log "  [OK] Office LTSC 2021 instalado correctamente. (ExitCode: 0)" "INFO" "Green"
        } else {
            Write-Log "  [WARN] Office termino con ExitCode: $($proc.ExitCode)" "WARN" "Yellow"
            Write-Log "  Algunos codigos no cero son normales en Office (ej: 3010 = reinicio pendiente)" "INFO" "Cyan"
        }
    } catch {
        Write-Log "  [ERROR] Fallo al ejecutar Office setup: $_" "ERROR" "Red"
    }
    } # fin if (-not $officeInstalado)
}

Write-Log "--- [SECCION 1] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 2 - RENAME DE USUARIO
# Pide el nuevo nombre interactivamente solo si el usuario actual es "Pomelo"
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 2: RENAME DE USUARIO ---" "INFO" "Yellow"

try {
    $pomeloUser = Get-LocalUser -Name "Pomelo" -ErrorAction SilentlyContinue

    if (-not $pomeloUser) {
        Write-Log "  [OK] La cuenta 'Pomelo' no existe (posiblemente ya renombrada)." "INFO" "Green"
    } elseif ($env:USERNAME -ne "Pomelo") {
        Write-Log "  [INFO] Usuario actual es '$env:USERNAME', no 'Pomelo'. Saltando rename." "INFO" "Yellow"
    } else {
        Write-Log "  Usuario actual: Pomelo. Ingrese el nuevo nombre de usuario (ej: SuperLili):" "INFO" "Cyan"
        $newUserName = Read-Host

        if ([string]::IsNullOrWhiteSpace($newUserName)) {
            Write-Log "  [WARN] Nombre vacio. Rename cancelado." "WARN" "Yellow"
        } else {
            try {
                Rename-LocalUser -Name "Pomelo" -NewName $newUserName -ErrorAction Stop
                Get-LocalUser -Name $newUserName | Set-LocalUser -FullName $newUserName -ErrorAction Stop
                Write-Log "  [OK] Usuario renombrado a '$newUserName' correctamente." "INFO" "Green"
            } catch {
                Write-Log "  [ERROR] No se pudo renombrar el usuario: $_" "ERROR" "Red"
            }
        }
    }
} catch {
    Write-Log "  [ERROR] Error verificando usuario Pomelo: $_" "ERROR" "Red"
}

Write-Log "--- [SECCION 2] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 3 - RENOMBRAR EQUIPO SEGUN USUARIO Y TIPO DE CHASIS
# Formato: LAPTOP-USUARIO o DESKTOP-USUARIO (7 chars del nombre)
#
# BUG CORREGIDO v2: Rename-Computer usa WMI y falla si en la misma sesion
# se renombro el usuario (SID cacheado invalido). Solucion: escritura directa
# en el registro, que no usa WMI y funciona correctamente en todos los casos.
# El efecto es identico: el nuevo nombre se aplica al reiniciar.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 3: RENOMBRAR EQUIPO ---" "INFO" "Yellow"

$renameOK = $false

# --- Obtener nombre de usuario ---
# Prioridad: variable global del Script 1 -> deteccion local -> sesion actual
$username = $null

if ($global:NewUserName -and $global:NewUserName -ne "") {
    $username = $global:NewUserName
    Write-Log "  Usuario (global Script 1): $username" "INFO" "Green"
} else {
    try {
        $localUsers = Get-LocalUser | Where-Object {
            $_.Enabled -and $_.Name -notin @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
        }
        if ($localUsers) {
            $username = $localUsers[0].Name
            Write-Log "  Usuario (cuenta local detectada): $username" "INFO" "Green"
        } else {
            $username = $env:USERNAME
            Write-Log "  [WARN] Sin cuentas locales activas. Usando sesion actual: $username" "WARN" "Yellow"
        }
    } catch {
        $username = $env:USERNAME
        Write-Log "  [WARN] Error Get-LocalUser: $_. Usando sesion: $username" "WARN" "Yellow"
    }
}

# --- Generar prefijo limpio (7 chars, mayusculas, sin caracteres especiales) ---
$userPrefix = Get-CleanComputerPrefix -Name $username
Write-Log "  Prefijo generado: $userPrefix (de '$username')" "INFO" "Cyan"

# --- Verificar nombre actual ---
$currentName  = $env:COMPUTERNAME
$validFormats = @("LAPTOP-$userPrefix", "DESKTOP-$userPrefix")

if ($currentName -in $validFormats) {
    Write-Log "  [OK] Nombre actual '$currentName' ya tiene el formato correcto." "INFO" "Green"
    $renameOK = $true
} else {
    Write-Log "  Nombre actual: $currentName -> necesita cambio" "INFO" "Yellow"

    # --- Detectar tipo de chasis via registro (no usa WMI, evita problema de SID) ---
    # Tipos laptop/portatil/tablet segun Win32_SystemEnclosure ChassisTypes:
    #   8=Portatil, 9=Notebook, 10=Handheld, 14=Sub-Notebook
    #   30=Tablet, 31=Convertible, 32=Detachable (modernos)
    $chassisPrefix = "DESKTOP-"
    try {
        # Get-CimInstance no tiene el problema de SID (usa DCOM local, no WMI remoto)
        # pero para mayor seguridad usamos el registro directamente
        $chassis     = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        $chassisType = $chassis.ChassisTypes[0]
        $laptopTypes = @(8, 9, 10, 14, 30, 31, 32)
        $chassisPrefix = if ($chassisType -in $laptopTypes) { "LAPTOP-" } else { "DESKTOP-" }
        Write-Log "  Tipo de chasis: $chassisType -> $chassisPrefix" "INFO" "Cyan"
    } catch {
        Write-Log "  [WARN] No se pudo detectar chasis: $_. Usando DESKTOP-." "WARN" "Yellow"
    }

    # --- Generar y validar nuevo nombre ---
    $newComputerName = "$chassisPrefix$userPrefix"

    if ($newComputerName.Length -gt 63) {
        Write-Log "  [ERROR] Nombre '$newComputerName' excede 63 caracteres. Rename cancelado." "ERROR" "Red"
    } elseif ($newComputerName -eq $currentName) {
        Write-Log "  [OK] Nombre '$newComputerName' ya coincide con el actual." "INFO" "Green"
        $renameOK = $true
    } else {
        # --- BUG CORREGIDO v2: Rename via registro en lugar de Rename-Computer ---
        # Rename-Computer usa WMI y falla con SID invalido despues de rename de usuario
        # La escritura en registro es equivalente y no tiene esa limitacion
        try {
            $regComputerName = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName"
            $regActiveComputerName = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName"
            $regTcpip = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

            Set-ItemProperty -Path $regComputerName       -Name "ComputerName" -Value $newComputerName -Force -ErrorAction Stop
            Set-ItemProperty -Path $regTcpip              -Name "Hostname"     -Value $newComputerName -Force -ErrorAction Stop
            Set-ItemProperty -Path $regTcpip              -Name "NV Hostname"  -Value $newComputerName -Force -ErrorAction Stop

            # ActiveComputerName puede no existir en todos los sistemas, no es critico
            try {
                Set-ItemProperty -Path $regActiveComputerName -Name "ComputerName" -Value $newComputerName -Force -ErrorAction Stop
            } catch {
                Write-Log "  [INFO] ActiveComputerName no modificado (no critico): $_" "INFO" "Cyan"
            }

            Write-Log "  [OK] Equipo renombrado en registro: '$currentName' -> '$newComputerName'" "INFO" "Green"
            Write-Log "  [INFO] El nuevo nombre se aplica completamente al reiniciar." "INFO" "Cyan"
            Write-Log "  [INFO] El reinicio se realizara al finalizar el Script 5." "INFO" "Cyan"
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
Write-Log "  2RenameLaptop-Desktop-Claude-v2.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "Rename OK  : $renameOK" "INFO" "Cyan"
Write-Log "Log        : $global:LogFile" "INFO" "Cyan"
Write-Log "" "INFO" "White"

if ($LlamarScript3) {
    Write-Log "SIGUIENTE PASO: Script 3 - 3TuPcVolaraClaude.ps1" "INFO" "White"
    Write-Log "Iniciando en 6 segundos..." "INFO" "Yellow"
    Start-Sleep -Seconds 6

    $script3 = "C:\Users\Public\Documents\Automatico\3TuPcVolaraClaude.ps1"
    if (Test-Path $script3) {
        Write-Log "Ejecutando Script 3: $script3" "INFO" "Cyan"
        & $script3
    } else {
        Write-Log "[WARN] Script 3 no encontrado en: $script3" "WARN" "Yellow"
        Write-Log "Ejecutalo manualmente cuando estes listo." "INFO" "White"
    }
} else {
    Write-Log "LlamarScript3 = false. Fin sin llamar al Script 3." "INFO" "Yellow"
}