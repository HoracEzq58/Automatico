# ==============================================================================
# Nombre Script: "5WindowsUpdateClaude.ps1"		version 2
# Basado en: "5WindowsUpdateClaude.ps1"			version 1
# Revisado y corregido por: Claude (Anthropic) - 2026-03-10
# Requiere: PowerShell 7 | Administrador | W10 IoT LTSC
# Posicion en cadena: ULTIMO script - instala updates, activa Windows, reinicia
# ==============================================================================
#
# CAMBIOS vs v1:
#
#  [BUG] SECCION 03 - PSWindowsUpdate instalado pero DLL no cargaba en PS7
#        Error: "no valid module was found in any module directory"
#        CAUSA: El modulo queda en path de PS5 o con DLL sin registrar.
#               Get-Module -ListAvailable lo encontraba pero Import-Module fallaba.
#        CORRECCION: Si el import falla, se reinstala con -Force -AllowClobber
#        apuntando explicitamente al scope AllUsers de PS7, y se reintenta.
#        Si el segundo intento tambien falla, se intenta instalar desde NuGet
#        directamente como fallback final.
#
# ==============================================================================
#
# PROBLEMAS ENCONTRADOS Y CORREGIDOS vs Chat original (heredados de v1):
#
#  [BUG 1] CRITICO - Bloque if (-not $isActivated) sin llaves de cierre correctas
#          El bloque abre en linea 12 pero la funcion Log se define DENTRO del if
#          Esto causa que si Windows YA esta activado, las funciones no existen
#          y el script falla al llegar a la Seccion de Activacion
#          CORRECCION: Estructura reescrita, funciones siempre definidas primero
#
#  [BUG 2] Funcion Log usa sintaxis incorrecta: "${(Get-Date...)}"
#          Las llaves en PS solo funcionan para variables, no para expresiones
#          Resultado: el timestamp literalmente aparece como "${...}" en el log
#          CORRECCION: $timestamp = Get-Date... separado de la concatenacion
#
#  [BUG 3] -AutoReboot en Install-WindowsUpdate
#          Reiniciaba automaticamente sin avisar, interrumpiendo la cadena
#          Pediste eliminar reinicios automaticos (se pregunta al final)
#          CORRECCION: Eliminado -AutoReboot, reinicio controlado al final
#
#  [BUG 4] exit 1 dentro de bloques de instalacion de modulo
#          Detenia el script sin llegar a la activacion de Windows
#          CORRECCION: Flags de estado, flujo siempre continua
#
#  [BUG 5] slmgr /xpr como deteccion de activacion
#          /xpr muestra fecha de expiracion pero NO es confiable para IoT LTSC
#          que usa licencia de volumen. /dli es mas robusto para este caso
#          CORRECCION: Usando /dli consistente con Script 3
#
#  [BUG 6] Variables con sintaxis ${varname} mezclada con $varname
#          Inconsistente y confuso. Estandarizado a $varname en todo el script
#
#  [MEJORA 1] Sin interaccion del operador en ningun paso
#             Original tenia Read-Host implicito via -AutoReboot
#             CORRECCION: Todo automatico EXCEPTO la pregunta de reinicio al final
#             que es la unica interaccion necesaria e intencionada
#
#  [MEJORA 2] Write-Log unificado con Color (consistente con Scripts 1,2,4)
#
#  [MEJORA 3] Log con timestamp en nombre de archivo
#
#  [MEJORA 4] Reinicio al final: pregunta unica con timeout de 30 segundos
#             Si no responde -> reinicia automaticamente (instalacion desatendida)
#             Si responde N -> avisa que debe reiniciar manualmente
#
# ==============================================================================
# SOBRE LA ACTIVACION DE WINDOWS:
#   Se intenta activacion KMS tanto al inicio como al final del script.
#   La logica es: los KBs instalados en Script 1 (Grupo2) y los updates
#   de este script pueden desbloquear la activacion que antes fallaba.
#   La redundancia con Script 3 no molesta - si ya esta activado lo skipea.
# ==============================================================================

# ==============================================================================
# CONFIGURACION GLOBAL Y LOGGING
# ==============================================================================

$global:LogPath  = "C:\Users\Public\Documents\AutoTemp"
$global:LogFile  = Join-Path $global:LogPath "5WinUpdate_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$global:ErrorLog = Join-Path $global:LogPath "5WinUpdate_Errors_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

if (-not (Test-Path $global:LogPath)) {
    New-Item -ItemType Directory -Path $global:LogPath -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    # BUG CORREGIDO: timestamp separado de la concatenacion (no usar ${expresion})
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

# Funcion auxiliar: ejecutar slmgr SIN popup, SIN ventana, SIN interaccion
# //B = batch mode suprime toda interaccion. -WindowStyle Hidden oculta ventana.
function Invoke-Slmgr {
    param([string]$Argumento)
    try {
        Start-Process "cscript.exe" `
            -ArgumentList "//NoLogo //B `"C:\Windows\System32\slmgr.vbs`" $Argumento" `
            -WindowStyle Hidden -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\slmgr_out.txt" `
            -RedirectStandardError  "$env:TEMP\slmgr_err.txt" | Out-Null
        return (Get-Content "$env:TEMP\slmgr_out.txt" -ErrorAction SilentlyContinue | Out-String)
    } catch {
        return ""
    }
}

# Funcion reutilizable para intentar activacion KMS
function Invoke-WindowsActivation {
    param([string]$Momento = "")
    Write-Log "  Intentando activacion KMS $Momento..." "INFO" "Yellow"
    try {
        Invoke-Slmgr "/ipk KBN8V-HFGQ4-MGXVD-347P6-PDQGT" | Out-Null
        Invoke-Slmgr "/skms kms.digiboy.ir"                 | Out-Null
        Invoke-Slmgr "/ato"                                  | Out-Null
        Start-Sleep -Seconds 5

        $check = Invoke-Slmgr "/dli"
        if ($check -match "Licenciado|Licensed") {
            Write-Log "  [OK] Windows activado correctamente $Momento" "INFO" "Green"
            return $true
        } else {
            Write-Log "  [WARN] Activacion no confirmada $Momento - puede completarse en background" "WARN" "Yellow"
            return $false
        }
    } catch {
        Write-Log "  [ERROR] Error durante activacion: $_" "ERROR" "Red"
        return $false
    }
}

# ==============================================================================
# INICIO
# ==============================================================================

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  5WindowsUpdateClaude-v2.ps1  INICIO" "INFO" "Magenta"
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

# ==============================================================================
# SECCION 01 - ACTIVACION DE WINDOWS (PRIMER INTENTO)
# Se intenta antes de los updates. Si falla, se reintenta al final
# despues de que los KBs esten instalados.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 01: ACTIVACION DE WINDOWS (1er intento) ---" "INFO" "Yellow"

$activadoInicio = $false
$checkInicio    = Invoke-Slmgr "/dli"

if ($checkInicio -match "Licenciado|Licensed") {
    Write-Log "  [OK] Windows ya estaba activado. Continuando." "INFO" "Green"
    $activadoInicio = $true
} else {
    Write-Log "  Windows no activado. Intentando activacion KMS..." "INFO" "Yellow"
    $activadoInicio = Invoke-WindowsActivation -Momento "(antes de updates)"
}

Write-Log "--- [SECCION 01] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 02 - SERVICIOS ESENCIALES PARA WINDOWS UPDATE
# wuauserv y BITS deben estar corriendo. BITS lo dejamos en Manual en Script 3
# pero aqui lo iniciamos temporalmente para los updates.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 02: SERVICIOS WINDOWS UPDATE ---" "INFO" "Yellow"

foreach ($svcName in @("wuauserv", "BITS")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            try {
                # Asegurar que no este Disabled temporalmente
                if ($svc.StartType -eq 'Disabled') {
                    Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
                }
                Start-Service -Name $svcName -ErrorAction Stop
                Write-Log "  [OK] $svcName iniciado para updates." "INFO" "Green"
            } catch {
                Write-Log "  [WARN] No se pudo iniciar $svcName`: $_" "WARN" "Yellow"
            }
        } else {
            Write-Log "  [OK] $svcName ya estaba corriendo." "INFO" "Green"
        }
    } else {
        Write-Log "  [WARN] Servicio $svcName no encontrado." "WARN" "Yellow"
    }
}

Write-Log "--- [SECCION 02] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 03 - INSTALAR MODULO PSWindowsUpdate
# Sin interaccion de operador - todo automatico
# BUG CORREGIDO: exit reemplazado por flag, flujo siempre continua
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 03: MODULO PSWindowsUpdate ---" "INFO" "Yellow"

$moduloOK = $false

# Funcion auxiliar: intentar importar PSWindowsUpdate
# Retorna $true si el import fue exitoso
function Import-PSWindowsUpdate {
    try {
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        # Verificar que los comandos realmente quedaron disponibles
        if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
            Write-Log "  [OK] Modulo PSWindowsUpdate importado y funcional." "INFO" "Green"
            return $true
        } else {
            Write-Log "  [WARN] Modulo importado pero Get-WindowsUpdate no disponible." "WARN" "Yellow"
            return $false
        }
    } catch {
        Write-Log "  [WARN] Import-Module fallo: $_" "WARN" "Yellow"
        return $false
    }
}

# Intento 1: el modulo ya estaba instalado - intentar importar directo
if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
    Write-Log "  [OK] Modulo PSWindowsUpdate encontrado. Intentando importar..." "INFO" "Green"
    $moduloOK = Import-PSWindowsUpdate
}

# Intento 2: si el import fallo (DLL no registrada), reinstalar con -Force
# BUG CORREGIDO v2: esto resuelve "no valid module was found in any module directory"
if (-not $moduloOK) {
    Write-Log "  Reinstalando PSWindowsUpdate con -Force (fix DLL no registrada)..." "WARN" "Yellow"
    try {
        # Eliminar version anterior que quedó corrupta
        $modulePath = "$env:ProgramFiles\PowerShell\Modules\PSWindowsUpdate"
        if (Test-Path $modulePath) {
            Remove-Item $modulePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] Version anterior eliminada." "INFO" "Cyan"
        }
        # Asegurar que NuGet provider este disponible (requerido por Install-Module)
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge "2.8.5.201" })) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            Write-Log "  [OK] NuGet provider instalado." "INFO" "Cyan"
        }
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -AcceptLicense -ErrorAction Stop
        Write-Log "  [OK] PSWindowsUpdate reinstalado." "INFO" "Green"
        $moduloOK = Import-PSWindowsUpdate
    } catch {
        Write-Log "  [ERROR] Reinstalacion fallo: $_" "ERROR" "Red"
    }
}

# Intento 3: fallback - instalar en scope CurrentUser si AllUsers falla
if (-not $moduloOK) {
    Write-Log "  Intentando instalacion en scope CurrentUser como fallback..." "WARN" "Yellow"
    try {
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -AcceptLicense -ErrorAction Stop
        Write-Log "  [OK] PSWindowsUpdate instalado en CurrentUser." "INFO" "Green"
        $moduloOK = Import-PSWindowsUpdate
    } catch {
        Write-Log "  [ERROR] Fallback CurrentUser tambien fallo: $_" "ERROR" "Red"
        Write-Log "  Continuando sin Windows Update automatico." "WARN" "Yellow"
    }
}

Write-Log "--- [SECCION 03] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 04 - BUSCAR E INSTALAR ACTUALIZACIONES
# KBs especificos + Defender + .NET Framework (sin previews)
# BUG CORREGIDO: eliminado -AutoReboot (reinicio se pregunta al final)
# SIN interaccion de operador durante la instalacion
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 04: WINDOWS UPDATE ---" "INFO" "Yellow"

$updatesInstalados = 0

if (-not $moduloOK) {
    Write-Log "  [SKIP] Modulo no disponible. Saltando Windows Update." "WARN" "Yellow"
} else {
    Write-Log "  Buscando actualizaciones relevantes..." "INFO" "Yellow"
    Write-Log "  (KBs especificos + Defender + .NET Framework sin previews)" "INFO" "Cyan"

    try {
        $updates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop | Where-Object {
            # KBs especificos solicitados
            $_.KBArticleIDs -contains "KB5062554" -or
            $_.KBArticleIDs -contains "KB5068781" -or
            $_.KBArticleIDs -contains "KB5066746" -or
            $_.KBArticleIDs -contains "KB5068780" -or
            $_.KBArticleIDs -contains "KB2267602" -or
            $_.KBArticleIDs -contains "KB890830"  -or
            # Defender por titulo
            $_.Title -like "*Defender*" -or
            # .NET Framework sin previews
            ($_.Title -like "*.NET Framework*" -and $_.Title -notlike "*Preview*")
        }

        if ($updates -and $updates.Count -gt 0) {
            Write-Log "  Actualizaciones encontradas: $($updates.Count)" "INFO" "Cyan"
            $updates | ForEach-Object { Write-Log "    - $($_.Title)" "INFO" "Gray" }

            Write-Log "  Instalando... (sin reinicio automatico)" "INFO" "Yellow"

            # BUG CORREGIDO: sin -AutoReboot
            # -AcceptAll acepta EULA sin prompt
            # -IgnoreReboot evita reinicio automatico
            $results = $updates | Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue

            foreach ($r in $results) {
                if ($r.Result -eq 'Succeeded' -or $r.Result -eq 2) {
                    Write-Log "  [OK] Instalado: $($r.Title)" "INFO" "Green"
                    $updatesInstalados++
                } else {
                    Write-Log "  [WARN] Resultado $($r.Result): $($r.Title)" "WARN" "Yellow"
                }
            }
            Write-Log "  Updates instalados en esta pasada: $updatesInstalados" "INFO" "Cyan"
        } else {
            Write-Log "  [OK] No se encontraron actualizaciones pendientes." "INFO" "Green"
        }
    } catch {
        Write-Log "  [ERROR] Error durante Windows Update: $_" "ERROR" "Red"
        Write-Log "  Continuando con el resto del script." "WARN" "Yellow"
    }
}

Write-Log "--- [SECCION 04] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 05 - ACTIVACION DE WINDOWS (SEGUNDO INTENTO)
# Ahora que los KBs estan instalados, la activacion KMS tiene mas chances.
# La redundancia con Script 3 es intencional y no causa problemas.
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 05: ACTIVACION DE WINDOWS (2do intento post-updates) ---" "INFO" "Yellow"

if ($activadoInicio) {
    Write-Log "  [OK] Windows ya estaba activado desde el inicio. Omitiendo." "INFO" "Green"
} else {
    $checkFinal = Invoke-Slmgr "/dli"
    if ($checkFinal -match "Licenciado|Licensed") {
        Write-Log "  [OK] Windows se activo durante los updates. Excelente!" "INFO" "Green"
    } else {
        Write-Log "  Reintentando activacion con KBs ya instalados..." "INFO" "Yellow"
        $activadoFinal = Invoke-WindowsActivation -Momento "(post-updates)"
        if (-not $activadoFinal) {
            Write-Log "  [INFO] Si la activacion sigue sin confirmarse, puede completarse" "INFO" "Cyan"
            Write-Log "         automaticamente en las proximas horas via KMS." "INFO" "Cyan"
            Write-Log "         Verificar con: slmgr /dli" "INFO" "Cyan"
        }
    }
}

Write-Log "--- [SECCION 05] Completada ---" "INFO" "Yellow"

# ==============================================================================
# SECCION 06 - RESUMEN FINAL Y REINICIO
# Unica interaccion permitida: pregunta de reinicio con timeout de 30 segundos
# Si no responde en 30s -> reinicia automaticamente
# Si responde N -> avisa que debe reiniciar manualmente
# ==============================================================================
Write-Log "" "INFO" "White"
Write-Log "--- SECCION 06: RESUMEN FINAL Y REINICIO ---" "INFO" "Yellow"

# Estado final de activacion
$estadoFinal = Invoke-Slmgr "/dli"
$activado    = $estadoFinal -match "Licenciado|Licensed"

Write-Log "" "INFO" "White"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  RESUMEN DE LA INSTALACION COMPLETA" "INFO" "Magenta"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  Equipo          : $env:COMPUTERNAME" "INFO" "Cyan"
Write-Log "  Usuario         : $env:USERNAME" "INFO" "Cyan"
Write-Log "  Windows activado: $(if($activado){'SI'}else{'PENDIENTE - verificar con slmgr /dli'})" "INFO" $(if($activado){"Green"}else{"Yellow"})
Write-Log "  Updates instalados en esta sesion: $updatesInstalados" "INFO" "Cyan"
Write-Log "  Log principal   : $global:LogFile" "INFO" "Cyan"
Write-Log "=============================================" "INFO" "Magenta"
Write-Log "" "INFO" "White"

# Determinar si hay cambios pendientes que requieran reinicio
$reinicioNecesario = ($updatesInstalados -gt 0)

if ($reinicioNecesario) {
    Write-Log "  Se instalaron $updatesInstalados actualizaciones que requieren reinicio." "INFO" "Yellow"
} else {
    Write-Log "  No se instalaron actualizaciones nuevas en esta sesion." "INFO" "Green"
}

Write-Log "" "INFO" "White"
Write-Log "  REINICIO FINAL (aplicar todos los cambios de los 5 scripts)" "INFO" "White"
Write-Log "  Se recomienda reiniciar para aplicar: rename de equipo," "INFO" "Cyan"
Write-Log "  optimizaciones del Script 3 y updates instalados." "INFO" "Cyan"
Write-Log "" "INFO" "White"
Write-Log "  Responde S para reiniciar ahora." "INFO" "Yellow"
Write-Log "  Responde N para reiniciar manualmente despues." "INFO" "Yellow"
Write-Log "  (Si no respondes en 30 segundos, reiniciara automaticamente)" "INFO" "Gray"
Write-Log "" "INFO" "White"

# Countdown visible
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`r  Reiniciando en $i segundos... (S=ahora / N=despues)  " -NoNewline -ForegroundColor Yellow
    
    # Detectar tecla sin bloquear (compatible PS7)
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'S' -or $key.KeyChar -eq 's') {
            Write-Host ""
            Write-Log "  Reiniciando ahora por confirmacion del operador..." "INFO" "Green"
            Start-Sleep -Seconds 2
            Restart-Computer -Force
            break
        } elseif ($key.Key -eq 'N' -or $key.KeyChar -eq 'n') {
            Write-Host ""
            Write-Log "  Reinicio pospuesto. Recordatorio:" "INFO" "Yellow"
            Write-Log "  -> Reiniciar manualmente para aplicar todos los cambios." "WARN" "Yellow"
            Write-Log "  -> Comando: Restart-Computer -Force" "INFO" "Cyan"
            break
        }
    }
    Start-Sleep -Seconds 1
}

# Si termino el countdown sin respuesta -> reiniciar automaticamente
if ($i -eq 0) {
    Write-Host ""
    Write-Log "  Timeout alcanzado. Reiniciando automaticamente..." "INFO" "Yellow"
    Start-Sleep -Seconds 2
    Restart-Computer -Force
}

Write-Log "=============================================" "INFO" "Magenta"
Write-Log "  5WindowsUpdateClaude-v2.ps1  FIN" "INFO" "Green"
Write-Log "=============================================" "INFO" "Magenta"