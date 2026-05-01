# ==============================================================================
# MantenimientoSemanal.ps1
# Script PowerShell 7 — Limpieza + Actualización Chocolatey + Telegram
# Windows 10/11 | Requiere ejecución como Administrador
# Log: C:\Users\Public\Documents\AutoTemp\
# Modificado: 03/04/2026 21 hs
# ------------------------------------------------------------------------------
# Versión : 4.1
# Cambios : - Fix: $script:AvisoVencimiento se inicializa ANTES del bloque de
#             vencimiento para que no sea pisada por la asignacion global.
#           - Fix: powershell-core excluido de choco upgrade (igual que rustdesk)
#             para evitar que el instalador MSI mate el proceso pwsh en ejecucion.
#           - Nuevo Modulo 7: actualiza powershell-core y rustdesk al FINAL del
#             script, cuando ya terminaron todos los modulos. Si falla, no afecta
#             el mantenimiento ni el reporte al cliente.
# ------------------------------------------------------------------------------
# Versión : 4
# Cambios : - Kill switch: lee flag "Activo" de config.json. Si es false,
#             el script termina silenciosamente sin ejecutar ningún módulo.
#           - Vencimiento: lee campo "VenceEl" (formato yyyy-MM-dd) de
#             config.json. Si la fecha actual la supera, el script termina
#             y envía Telegram avisando que el servicio venció en esa PC.
#           - Blindaje NTFS: función Blindar-Config endurece permisos del
#             config.json al finalizar (solo SYSTEM y Administradores pueden
#             leer; usuarios normales sin acceso).
#           - Módulo 5 rediseñado: el .txt se crea directamente en el
#             Escritorio del cliente (sin acceso directo .lnk). Se elimina
#             la creación del acceso directo anterior.
#           - Ventana WinForms con countdown: al finalizar el mantenimiento
#             se muestra el reporte en una ventana flotante con countdown
#             de 18 segundos y botón para cerrar antes. No bloquea el script.
# ------------------------------------------------------------------------------
# Versión : 3
# Cambios : - Nueva función Gestionar-Estadisticas: acumulador anual de bytes
#             liberados en estadisticas-anuales.json. Resetea automáticamente
#             al completar 52 semanas.
#           - Enviar-Resumen-Telegram: agrega bloque de acumulado anual
#             (semana N de 52, total acumulado, equivalencias fotos/canciones).
#           - Crear-LogCliente: agrega sección de acumulado anual al .txt
#             del Escritorio del cliente (argumento de venta de suscripción).
# ------------------------------------------------------------------------------
# Versión : 2
# Cambios : - Fix Bug: ExitCode de Start-Process capturado con try/catch para
#             evitar error de assembly System.Collections.NonGeneric en .NET 9/10
#           - Fix Bug: Get-CimInstance envuelto en try/catch para que caida al
#             fallback de C:\Users si CimCmdlets no carga en PS7 Core
# ==============================================================================

#Requires -Version 7.0
#Requires -RunAsAdministrator

# ------------------------------------------------------------------------------
# CONFIGURACIÓN GENERAL
# ------------------------------------------------------------------------------
$logDir      = "C:\Users\Public\Documents\AutoTemp"
$logFile     = "$logDir\MantenimientoSemanal_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$fechaInicio = Get-Date

# --- TELEGRAM ---
$ConfigPath = "C:\Users\Public\Documents\Automatico\config.json"
$Config = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
$TelegramToken  = $Config.TelegramToken
$TelegramChatID = $Config.TelegramChatID

# ------------------------------------------------------------------------------
# SECCIÓN 1 — KILL SWITCH Y CONTROL DE VENCIMIENTO
# ------------------------------------------------------------------------------

# Kill switch: si "Activo" es false, terminar silenciosamente

$script:AvisoVencimiento = "" # Movido por recomendacion del Otro Yo de Claude el 09/04/2026 15.47 hs - Se llena si faltan 14 dias o menos para vencer.
if ($Config.PSObject.Properties.Name -contains 'Activo') {
    if ($Config.Activo -eq $false) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts [INFO] Servicio inactivo (Activo=false en config.json). Mantenimiento cancelado." |
            Out-File -FilePath $logFile -Append
        exit 0
    }
}

# Control de vencimiento: si "VenceEl" existe, evaluar vencido o proximo a vencer
if ($Config.PSObject.Properties.Name -contains 'VenceEl') {
    try {
        # Parseo robusto: split manual para evitar dependencia de cultura regional
        $partes = $Config.VenceEl -split "-"
        $fechaVence = [datetime]::new([int]$partes[0], [int]$partes[1], [int]$partes[2])
        $diasRestantes  = ([math]::Floor(($fechaVence - (Get-Date)).TotalDays))
        $fechaVenceTxt  = $fechaVence.ToString("dd/MM/yyyy")

        if ((Get-Date) -gt $fechaVence) {
            # --- VENCIDO: avisar al cliente y a TuPcVeloz, luego salir ---
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$ts [WARN] Servicio vencido el $($Config.VenceEl) en equipo $env:COMPUTERNAME." |
                Out-File -FilePath $logFile -Append

            # Aviso Telegram a TuPcVeloz
            $uriV  = "https://api.telegram.org/bot$TelegramToken/sendMessage"
            $msgV  = "Servicio TuPcVeloz VENCIDO`n`nEquipo: $env:COMPUTERNAME`nVencio el: $fechaVenceTxt`nFecha actual: $(Get-Date -Format 'dd/MM/yyyy')`n`nRenovar o desactivar el servicio NSSM."
            $bodyV = @{ chat_id = $TelegramChatID; text = $msgV } | ConvertTo-Json -Compress
            try {
                Invoke-RestMethod -Uri $uriV -Method Post `
                    -ContentType "application/json; charset=utf-8" `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyV)) `
                    -ErrorAction Stop | Out-Null
            } catch { }

            # Aviso al cliente: .txt en Escritorio
            try {
                $usuarioVenc = $null
                try { $usuarioVenc = (Get-CimInstance -Class Win32_ComputerSystem -ErrorAction Stop).UserName } catch { }
                if ($usuarioVenc -and $usuarioVenc -match '\\') { $usuarioVenc = $usuarioVenc.Split('\')[1] }
                if (-not $usuarioVenc -or $usuarioVenc -match '\$$' -or $usuarioVenc -eq 'SYSTEM') {
                    $usuarioVenc = Get-ChildItem "C:\Users" -Directory |
                        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') -and $_.Name -notmatch '\$$' } |
                        Select-Object -First 1 -ExpandProperty Name
                }
                $escritorioVenc  = "C:\Users\$usuarioVenc\Desktop"
                $archivoVenc     = "$escritorioVenc\TuPcVeloz-SERVICIO-VENCIDO.txt"
                $contenidoVenc   = @"
============================================================
  TuPcVeloz - Aviso de servicio
============================================================

El servicio de mantenimiento automatico TuPcVeloz
vencio el $fechaVenceTxt.

Tu PC ya NO esta siendo mantenida automaticamente.

Para renovar el servicio contactanos en:
  tupcveloz.com

============================================================
  Servicio brindado por TuPcVeloz - tupcveloz.com
============================================================
"@
                if (-not (Test-Path $escritorioVenc)) {
                    New-Item -Path $escritorioVenc -ItemType Directory -Force | Out-Null
                }
                $contenidoVenc | Out-File -FilePath $archivoVenc -Encoding UTF8 -Force
                "$ts [OK] Aviso de vencimiento escrito en Escritorio del cliente: $archivoVenc" |
                    Out-File -FilePath $logFile -Append
            } catch {
                "$ts [WARN] No se pudo escribir aviso de vencimiento en Escritorio: $_" |
                    Out-File -FilePath $logFile -Append
            }

            # Aviso al cliente: ventana WinForms roja sin countdown via schtasks
            # (Mostrar-VentanaReporte aun no esta definida aqui, usamos llamada
            #  diferida via Start-Job para que se defina antes de ejecutarse)
            try {
                $contenidoVencWin = @"
============================================================
  TuPcVeloz - Aviso de servicio
============================================================

El servicio de mantenimiento automatico TuPcVeloz
vencio el $fechaVenceTxt.

Tu PC ya NO esta siendo mantenida automaticamente.

Para renovar el servicio contactanos en:
  tupcveloz.com

============================================================
"@
                # Lanzar ventana roja sin countdown (Countdown=0)
                # La funcion Mostrar-VentanaReporte se llama desde un job
                # para no depender del orden de definicion en el script
                $auxRojo = $contenidoVencWin -replace "'", "''"
                $auxPathRojo = "$logDir\TuPcVeloz-Vencido-Aux.ps1"
                $auxScriptRojo = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'TuPcVeloz - Servicio vencido'
`$form.Size = New-Object System.Drawing.Size(560, 560)
`$form.StartPosition = 'CenterScreen'
`$form.FormBorderStyle = 'FixedDialog'
`$form.MaximizeBox = `$false
`$form.TopMost = `$true
`$form.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)
`$banner = New-Object System.Windows.Forms.Panel
`$banner.Dock = 'Top'; `$banner.Height = 48
`$banner.BackColor = [System.Drawing.Color]::FromArgb(200,50,50)
`$form.Controls.Add(`$banner)
`$lblT = New-Object System.Windows.Forms.Label
`$lblT.Text = '  TuPcVeloz - Aviso de servicio'
`$lblT.Dock = 'Fill'
`$lblT.Font = New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
`$lblT.ForeColor = [System.Drawing.Color]::White
`$lblT.TextAlign = 'MiddleLeft'
`$banner.Controls.Add(`$lblT)
`$txt = New-Object System.Windows.Forms.TextBox
`$txt.Multiline = `$true; `$txt.ScrollBars = 'Vertical'; `$txt.ReadOnly = `$true
`$txt.Font = New-Object System.Drawing.Font('Courier New',9)
`$txt.BackColor = [System.Drawing.Color]::White
`$txt.ForeColor = [System.Drawing.Color]::FromArgb(30,30,30)
`$txt.Location = New-Object System.Drawing.Point(10,58)
`$txt.Size = New-Object System.Drawing.Size(524,400)
`$txt.Text = '$auxRojo'
`$form.Controls.Add(`$txt)
`$lblC = New-Object System.Windows.Forms.Label
`$lblC.Text = 'Hace clic en Cerrar cuando termines de leer.'
`$lblC.Location = New-Object System.Drawing.Point(10,468)
`$lblC.Size = New-Object System.Drawing.Size(340,24)
`$lblC.Font = New-Object System.Drawing.Font('Segoe UI',9)
`$lblC.ForeColor = [System.Drawing.Color]::FromArgb(100,100,100)
`$form.Controls.Add(`$lblC)
`$btn = New-Object System.Windows.Forms.Button
`$btn.Text = 'Cerrar'
`$btn.Location = New-Object System.Drawing.Point(430,462)
`$btn.Size = New-Object System.Drawing.Size(104,32)
`$btn.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
`$btn.BackColor = [System.Drawing.Color]::FromArgb(200,50,50)
`$btn.ForeColor = [System.Drawing.Color]::White
`$btn.FlatStyle = 'Flat'; `$btn.FlatAppearance.BorderSize = 0
`$btn.Add_Click({ `$form.Close() })
`$form.Controls.Add(`$btn)
[System.Windows.Forms.Application]::Run(`$form)
"@
                [System.IO.File]::WriteAllText($auxPathRojo, $auxScriptRojo, [System.Text.UTF8Encoding]::new($false))

                # Detectar usuario activo
                $usuVenc = $null
                $quser = & quser 2>$null
                if ($quser) {
                    $linea = $quser | Where-Object { $_ -match 'Activ|Active' } | Select-Object -First 1
                    if (-not $linea) { $linea = $quser | Select-Object -Skip 1 -First 1 }
                    if ($linea -match '^\s*>?\s*(\S+)') { $usuVenc = $Matches[1].TrimStart('>') }
                }
                if (-not $usuVenc) {
                    $usuVenc = Get-ChildItem "C:\Users" -Directory |
                        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') -and $_.Name -notmatch '\$$' } |
                        Select-Object -First 1 -ExpandProperty Name
                }

                if ($usuVenc) {
                    $tnRojo  = "TuPcVeloz-Vencido-$(Get-Date -Format 'HHmmss')"
                    $horaR   = (Get-Date).AddMinutes(1).ToString("HH:mm")
                    $argRojo = "/C schtasks /Create /TN `"$tnRojo`" /TR `"pwsh -WindowStyle Hidden -NonInteractive -File '$auxPathRojo'`" /SC ONCE /ST $horaR /RU `"$usuVenc`" /F /RL LIMITED"
                    $pr = Start-Process "cmd.exe" -ArgumentList $argRojo -Wait -PassThru -NoNewWindow
                    if ($pr.ExitCode -eq 0) {
                        Start-Sleep -Seconds 2
                        schtasks /Run /TN $tnRojo 2>$null | Out-Null
                        Start-Job -ScriptBlock { param($tn); Start-Sleep 300; schtasks /Delete /TN $tn /F 2>$null } -ArgumentList $tnRojo | Out-Null
                        "$ts [OK] Ventana WinForms de vencimiento lanzada como '$usuVenc'." | Out-File -FilePath $logFile -Append
                    }
                }
            } catch {
                "$ts [WARN] No se pudo lanzar ventana de vencimiento: $_" | Out-File -FilePath $logFile -Append
            }

            Start-Sleep -Seconds 3
            exit 0

        } elseif ($diasRestantes -le 14) {
            # --- PROXIMO A VENCER: setear aviso para inyectar en reporte ---
            $script:AvisoVencimiento = "AVISO: El servicio TuPcVeloz vence el $fechaVenceTxt (faltan $diasRestantes dias). Contactanos en tupcveloz.com para renovar."
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			"$ts [WARN] Servicio proximo a vencer: $diasRestantes dias restantes." | Out-File -FilePath $logFile -Append
        }

    } catch {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts [WARN] No se pudo parsear VenceEl='$($Config.VenceEl)'. Formato esperado: yyyy-MM-dd. Continuando." |
            Out-File -FilePath $logFile -Append
    }
}
# ------------------------------------------------------------------------------
# Contador global de espacio liberado (en bytes)
$script:BytesLiberados   = 0
$script:ChocoResumen     = "sin cambios"

# Ruta del JSON de estadísticas anuales acumuladas
$estadisticasFile = "$logDir\estadisticas-anuales.json"

# Crear directorio de log si no existe
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# ------------------------------------------------------------------------------
# FUNCIONES BASE
# ------------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Mensaje,
        [ValidateSet("INFO","WARN","ERROR","OK")][string]$Nivel = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "$timestamp [$Nivel] $Mensaje"
    $linea | Out-File -FilePath $logFile -Append
    switch ($Nivel) {
        "ERROR" { Write-Host $linea -ForegroundColor Red }
        "WARN"  { Write-Host $linea -ForegroundColor Yellow }
        "OK"    { Write-Host $linea -ForegroundColor Green }
        default { Write-Host $linea }
    }
}

function Write-Separador {
    param([string]$Titulo)
    $linea = "=" * 60
    Write-Log "$linea" "INFO"
    Write-Log "  $Titulo" "INFO"
    Write-Log "$linea" "INFO"
}

# Desbloquear script si es necesario
try {
    Unblock-File -Path $PSCommandPath -ErrorAction Stop
    Write-Log "Script desbloqueado correctamente." "OK"
} catch {
    Write-Log "No se pudo desbloquear el script: $_" "WARN"
}

# ------------------------------------------------------------------------------
# FUNCIONES DE LIMPIEZA
# ------------------------------------------------------------------------------

function Limpiar-Archivos {
    param([string]$Ruta, [string]$Descripcion)
    try {
        if (Test-Path $Ruta) {
            $archivos = Get-ChildItem -Path $Ruta -Recurse -Force -ErrorAction SilentlyContinue
            $count = 0
            foreach ($archivo in $archivos) {
                try {
                    $script:BytesLiberados += $archivo.Length
                    Remove-Item -Path $archivo.FullName -Force -Recurse -ErrorAction Stop
                    $count++
                } catch {
                    Write-Log "No se pudo eliminar: $($archivo.FullName) — $_" "WARN"
                }
            }
            Write-Log "$Descripcion limpiado ($count elementos). Ruta: $Ruta" "OK"
        } else {
            Write-Log "$Descripcion no encontrado en: $Ruta" "INFO"
        }
    } catch {
        Write-Log "Error limpiando $Descripcion en $Ruta`: $_" "ERROR"
    }
}

function Limpiar-DeepScanTmp {
    param([string[]]$Rutas, [string]$Descripcion)
    foreach ($Ruta in $Rutas) {
        try {
            if (Test-Path $Ruta) {
                $archivos = Get-ChildItem -Path $Ruta -Include *.tmp,*.temp -Recurse -File -ErrorAction SilentlyContinue
                $count = 0
                foreach ($archivo in $archivos) {
                    try {
                        $script:BytesLiberados += $archivo.Length
                        Remove-Item -Path $archivo.FullName -Force -ErrorAction Stop
                        $count++
                    } catch {
                        Write-Log "No se pudo eliminar temporal: $($archivo.FullName)" "WARN"
                    }
                }
                Write-Log "$Descripcion completado en $Ruta ($count archivos .tmp/.temp)" "OK"
            } else {
                Write-Log "$Descripcion — ruta no encontrada: $Ruta" "INFO"
            }
        } catch {
            Write-Log "Error durante $Descripcion en $Ruta`: $_" "ERROR"
        }
    }
}

function Limpiar-Prefetch {
    param([string]$Ruta, [string]$Descripcion)
    try {
        if (Test-Path $Ruta) {
            $fechaLimite = (Get-Date).AddDays(-30)
            $archivos = Get-ChildItem -Path $Ruta -Filter *.pf -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $fechaLimite }
            $count = 0
            foreach ($archivo in $archivos) {
                try {
                    $script:BytesLiberados += $archivo.Length
                    Remove-Item -Path $archivo.FullName -Force -ErrorAction Stop
                    $count++
                } catch {
                    Write-Log "No se pudo eliminar Prefetch: $($archivo.FullName)" "WARN"
                }
            }
            Write-Log "$Descripcion completado ($count archivos .pf con mas de 30 dias)" "OK"
        } else {
            Write-Log "$Descripcion — ruta no encontrada: $Ruta" "INFO"
        }
    } catch {
        Write-Log "Error en $Descripcion`: $_" "ERROR"
    }
}

function Limpiar-TareasProgramadas {
    param([string]$Ruta, [string]$Patron, [string]$Descripcion)
    try {
        if (Test-Path $Ruta) {
            $tareas = Get-ChildItem -Path $Ruta -Filter $Patron -Recurse -ErrorAction SilentlyContinue
            $count = 0
            foreach ($tarea in $tareas) {
                try {
                    Remove-Item -Path $tarea.FullName -Force -ErrorAction Stop
                    $count++
                } catch {
                    Write-Log "No se pudo eliminar tarea: $($tarea.FullName)" "WARN"
                }
            }
            Write-Log "$Descripcion limpiado ($count tareas eliminadas)" "OK"
        } else {
            Write-Log "$Descripcion — ruta no encontrada: $Ruta" "INFO"
        }
    } catch {
        Write-Log "Error en $Descripcion`: $_" "ERROR"
    }
}

function Deshabilitar-Servicio {
    param([string]$Nombre, [string]$Descripcion)
    try {
        $servicio = Get-Service -Name $Nombre -ErrorAction Stop
        if ($servicio.Status -ne 'Stopped') {
            Stop-Service -Name $Nombre -Force -ErrorAction Stop
            Write-Log "Servicio '$Descripcion' detenido" "OK"
        }
        Set-Service -Name $Nombre -StartupType Disabled -ErrorAction Stop
        Write-Log "Servicio '$Descripcion' deshabilitado" "OK"
    } catch {
        Write-Log "No se pudo deshabilitar '$Descripcion': $_" "WARN"
    }
}

function Eliminar-TareasInvasivas {
    $blacklist = @(
        "Dropbox","IObit","IOb","ASC_","AdvancedSystemCare","Advanced SystemCare",
        "Avast","AVG","McAfee","Norton","Symantec","CCleaner",
        "Driver Booster","DriverBooster","Driver Easy","DriverEasy",
        "Glary","PCOptimizer","WinOptimizer","Auslogics","Malwarebytes",
        "Babylon","Conduit","OpenCandy","Reimage","SpeedUpMyPC",
        "iSkysoft","Wondershare",
        "Core Temp","CoreTemp","Core Temp Autostart",
        "PDFXChange","PDFXChangeAutoUpdate","TrackerUpdate"
    )

    Write-Log "Buscando tareas programadas de software invasivo..." "INFO"
    $eliminadas = 0
    $errores    = 0

    try {
        $todasLasTareas = Get-ScheduledTask -ErrorAction Stop
        foreach ($tarea in $todasLasTareas) {
            $nombreTarea = $tarea.TaskName
            $coincide = $blacklist | Where-Object { $nombreTarea -like "*$_*" }
            if ($coincide) {
                try {
                    Unregister-ScheduledTask -TaskName $nombreTarea -TaskPath $tarea.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Log "Tarea eliminada: '$nombreTarea' (coincide con: $($coincide -join ', '))" "OK"
                    $eliminadas++
                } catch {
                    Write-Log "No se pudo eliminar tarea '$nombreTarea': $_" "WARN"
                    $errores++
                }
            }
        }
    } catch {
        Write-Log "Error al obtener lista de tareas programadas: $_" "ERROR"
        return
    }

    if ($eliminadas -eq 0 -and $errores -eq 0) {
        Write-Log "No se encontraron tareas de software invasivo." "INFO"
    } else {
        Write-Log "Tareas invasivas: $eliminadas eliminadas, $errores con error." "OK"
    }
}

# ------------------------------------------------------------------------------
# FUNCIÓN: ESTADÍSTICAS ANUALES ACUMULADAS
# ------------------------------------------------------------------------------

function Gestionar-Estadisticas {
    param([long]$BytesEstaSemana)

    $hoy          = Get-Date -Format "yyyy-MM-dd"
    $semanas_max  = 52

    # Leer JSON existente o crear estructura nueva
    if (Test-Path $estadisticasFile) {
        try {
            $stats = Get-Content $estadisticasFile -Raw | ConvertFrom-Json
            Write-Log "Estadisticas anuales cargadas ($($stats.semanas_registradas) semanas previas)." "INFO"
        } catch {
            Write-Log "No se pudo leer estadisticas-anuales.json, se reinicia el ciclo: $_" "WARN"
            $stats = $null
        }
    } else {
        $stats = $null
    }

    if (-not $stats) {
        $stats = [PSCustomObject]@{
            inicio_ciclo       = $hoy
            semanas_registradas = 0
            bytes_acumulados   = [long]0
            ultima_ejecucion   = $hoy
        }
        Write-Log "Nuevo ciclo anual iniciado el $hoy." "OK"
    }

    # Sumar bytes de esta semana
    $stats.bytes_acumulados    = [long]$stats.bytes_acumulados + $BytesEstaSemana
    $stats.semanas_registradas = [int]$stats.semanas_registradas + 1
    $stats.ultima_ejecucion    = $hoy

    # Guardar antes de verificar reset (para no perder la semana actual)
    try {
        $stats | ConvertTo-Json | Out-File -FilePath $estadisticasFile -Encoding UTF8 -Force
        Write-Log "Estadisticas anuales guardadas. Semana $($stats.semanas_registradas) de $semanas_max." "OK"
    } catch {
        Write-Log "No se pudo guardar estadisticas-anuales.json: $_" "WARN"
    }

    # Si se completaron 52 semanas, resetear para el próximo ciclo
    if ($stats.semanas_registradas -ge $semanas_max) {
        Write-Log "Ciclo anual completado (52 semanas). Reseteando estadisticas para el proximo ciclo." "OK"
        $statsNuevo = [PSCustomObject]@{
            inicio_ciclo        = $hoy
            semanas_registradas = 0
            bytes_acumulados    = [long]0
            ultima_ejecucion    = $hoy
        }
        try {
            $statsNuevo | ConvertTo-Json | Out-File -FilePath $estadisticasFile -Encoding UTF8 -Force
        } catch {
            Write-Log "No se pudo resetear estadisticas-anuales.json: $_" "WARN"
        }
    }

    return $stats
}

# ------------------------------------------------------------------------------
# MÓDULO 1 — LIMPIEZA DE TEMPORALES Y CACHÉS
# ------------------------------------------------------------------------------

function Iniciar-Limpieza {
    Write-Separador "MODULO 1: LIMPIEZA DE TEMPORALES Y CACHES"

    $tareas = @(
        # --- NAVEGADORES ---
        @{Tipo="Cache"; Nombre="brave.cache";            Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache" "Cache de Brave" }},
        @{Tipo="Cache"; Nombre="chromium.cache";         Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Chromium\User Data\Default\Cache" "Cache de Chromium" }},
        @{Tipo="Cache"; Nombre="firefox.cache";          Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Mozilla\Firefox\Profiles\*\cache*" "Cache de Firefox" }},
        @{Tipo="Cache"; Nombre="google_chrome.cache";    Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Cache" "Cache de Google Chrome" }},
        @{Tipo="Cache"; Nombre="microsoft_edge.cache";   Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Cache" "Cache de Microsoft Edge" }},
        @{Tipo="Cache"; Nombre="opera.cache";            Accion={ Limpiar-Archivos "C:\Users\*\AppData\Roaming\Opera Software\Opera Stable\Cache" "Cache de Opera" }},
        @{Tipo="Cache"; Nombre="palemoon.cache";         Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Moonchild Productions\Pale Moon\Profiles\*\cache*" "Cache de Pale Moon" }},
        @{Tipo="Cache"; Nombre="safari.cache";           Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Apple Computer\Safari\Cache" "Cache de Safari" }},
        @{Tipo="Cache"; Nombre="seamonkey.cache";        Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Mozilla\SeaMonkey\Profiles\*\cache*" "Cache de SeaMonkey" }},
        @{Tipo="Cache"; Nombre="thunderbird.cache";      Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Thunderbird\Profiles\*\cache*" "Cache de Thunderbird" }},
        @{Tipo="Cache"; Nombre="waterfox.cache";         Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Waterfox\Profiles\*\cache*" "Cache de Waterfox" }},
        @{Tipo="Cache"; Nombre="internet_explorer.cache";Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache" "Cache de Internet Explorer" }},
        # --- APLICACIONES ---
        @{Tipo="Cache"; Nombre="adobe_reader.cache";     Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Adobe\Acrobat\*\Cache" "Cache de Adobe Reader" }},
        @{Tipo="Cache"; Nombre="adobe_reader.tmp";       Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Adobe\Acrobat\*\Temp" "Temporales de Adobe Reader" }},
        @{Tipo="Cache"; Nombre="discord.cache";          Accion={ Limpiar-Archivos "C:\Users\*\AppData\Roaming\discord\Cache" "Cache de Discord" }},
        @{Tipo="Cache"; Nombre="flash.cache";            Accion={ Limpiar-Archivos "C:\Users\*\AppData\Roaming\Macromedia\Flash Player\*" "Cache de Flash" }},
        @{Tipo="Cache"; Nombre="gimp.tmp";               Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\GIMP\*\tmp" "Temporales de GIMP" }},
        @{Tipo="Cache"; Nombre="java.cache";             Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Sun\Java\Deployment\cache" "Cache de Java" }},
        @{Tipo="Cache"; Nombre="windows_media_player";   Accion={ Limpiar-Archivos "C:\Users\*\AppData\Local\Microsoft\Media Player\*" "Cache de Windows Media Player" }},
        @{Tipo="Cache"; Nombre="winrar.temp";            Accion={ Limpiar-Archivos "C:\Users\*\AppData\Roaming\WinRAR\*" "Temporales de WinRAR" }},
        @{Tipo="Cache"; Nombre="zoom.cache";             Accion={ Limpiar-Archivos "C:\Users\*\AppData\Roaming\Zoom\data\cache" "Cache de Zoom" }},
        # --- SISTEMA ---
        @{Tipo="Sistema"; Nombre="windows_temp";         Accion={
            Limpiar-Archivos "C:\Windows\Temp" "Temporales de Windows (System)"
            Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $userTempPath = Join-Path $_.FullName "AppData\Local\Temp"
                Limpiar-Archivos $userTempPath "Temporales de usuario [$($_.Name)]"
            }
        }},
        @{Tipo="Sistema"; Nombre="deepscan.tmp";         Accion={
            $rutasTemp = @("C:\Windows\Temp") + (
                Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName "AppData\Local\Temp" }
            )
            Limpiar-DeepScanTmp -Rutas $rutasTemp -Descripcion "DeepScan *.tmp / *.temp"
        }},
        @{Tipo="Sistema"; Nombre="recycle_bin";          Accion={
            try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log "Papelera de reciclaje vaciada" "OK" }
            catch { Write-Log "Error al vaciar papelera: $_" "WARN" }
        }},
        @{Tipo="Sistema"; Nombre="prefetch";             Accion={ Limpiar-Prefetch "C:\Windows\Prefetch" "Prefetch (archivos .pf > 30 dias)" }},
        # --- TAREAS PROGRAMADAS NO DESEADAS ---
        @{Tipo="Tareas"; Nombre="edge_tasks";    Accion={ Limpiar-TareasProgramadas "C:\Windows\System32\Tasks" "MicrosoftEdgeUpdateTask*" "Tareas de Edge Update" }},
        @{Tipo="Tareas"; Nombre="defrag_tasks";  Accion={ Limpiar-TareasProgramadas "C:\Windows\System32\Tasks\Microsoft\Windows\Defrag" "*" "Tareas de Defrag" }},
        @{Tipo="Tareas"; Nombre="invasivas_blacklist"; Accion={ Eliminar-TareasInvasivas }},
        # --- SERVICIOS EDGE (OPCIONALES) ---
        @{Tipo="Servicio"; Nombre="edge_elevation"; Accion={ Deshabilitar-Servicio "MicrosoftEdgeElevationService" "Edge Elevation Service" }},
        @{Tipo="Servicio"; Nombre="edge_update";    Accion={ Deshabilitar-Servicio "edgeupdate" "Edge Update" }},
        @{Tipo="Servicio"; Nombre="edge_updatem";   Accion={ Deshabilitar-Servicio "edgeupdatem" "Edge Update Manager" }}
    )

    $total  = $tareas.Count
    $actual = 0

    foreach ($tarea in $tareas) {
        $actual++
        $pct = [math]::Round(($actual / $total) * 100)
        Write-Progress -Activity "Limpieza en progreso" `
                       -Status "[$($tarea.Tipo)] $($tarea.Nombre) ($actual/$total)" `
                       -PercentComplete $pct
        try {
            & $tarea.Accion
        } catch {
            Write-Log "Error inesperado en tarea '$($tarea.Nombre)': $_" "ERROR"
        }
    }

    Write-Progress -Activity "Limpieza en progreso" -Status "Completado" -Completed

    Write-Log "Limpieza directa de refuerzo en C:\Windows\Temp y TEMP de usuario..." "INFO"
    try {
        Get-ChildItem -Path "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Get-ChildItem -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "Limpieza de refuerzo completada." "OK"
    } catch {
        Write-Log "Error en limpieza de refuerzo: $_" "WARN"
    }

    Write-Log "MODULO 1 FINALIZADO." "OK"
}

# ------------------------------------------------------------------------------
# MÓDULO 2 — ACTUALIZACIÓN CHOCOLATEY
# ------------------------------------------------------------------------------

function Iniciar-Chocolatey {
    Write-Separador "MODULO 2: ACTUALIZACION CHOCOLATEY"

    $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $chocoPath) {
        Write-Log "Chocolatey NO esta instalado o no esta en el PATH. Saltando modulo." "WARN"
        return
    }

    Write-Log "Chocolatey encontrado en: $($chocoPath.Source)" "OK"
    Write-Log "Ejecutando: choco upgrade all -y --no-progress" "INFO"

    # Medir espacio antes de Chocolatey
    $espacioAntes = (Get-PSDrive C).Free

    # Archivos temporales para capturar salida de choco
    $tempOut = "$logDir\choco_output.tmp"
    $tempErr = "$logDir\choco_error.tmp"

    try {
        # --- Intento 1: choco upgrade normal ---
        $proc = Start-Process -FilePath "choco" `
                              -ArgumentList "upgrade all -y --no-progress --except=""rustdesk.install,powershell-core""" `
                              -RedirectStandardOutput $tempOut `
                              -RedirectStandardError  $tempErr `
                              -NoNewWindow -PassThru -Wait

        if (Test-Path $tempOut) {
            $salida1 = Get-Content $tempOut
            $salida1 | ForEach-Object { Write-Log $_ "INFO" }
            Remove-Item $tempOut -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempErr) {
            Get-Content $tempErr | ForEach-Object { Write-Log $_ "WARN" }
            Remove-Item $tempErr -Force -ErrorAction SilentlyContinue
        }

        $salida2      = $null
        $lineaResumen = $null

        # Leer ExitCode con try/catch para evitar error de assembly en .NET 9/10
        $exitCode1 = 0
        try { $exitCode1 = $proc.ExitCode } catch { $exitCode1 = -1 }

        if ($exitCode1 -ne 0) {
            Write-Log "choco upgrade all termino con codigo $exitCode1. Reintentando con --ignore-checksums..." "WARN"

            # --- Intento 2: choco upgrade con --ignore-checksums ---
            $proc2 = Start-Process -FilePath "choco" `
                                   -ArgumentList "upgrade all --ignore-checksums -y --no-progress --except=""rustdesk.install,powershell-core""" `
                                   -RedirectStandardOutput $tempOut `
                                   -RedirectStandardError  $tempErr `
                                   -NoNewWindow -PassThru -Wait

            if (Test-Path $tempOut) {
                $salida2 = Get-Content $tempOut
                $salida2 | ForEach-Object { Write-Log $_ "INFO" }
                Remove-Item $tempOut -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $tempErr) {
                Get-Content $tempErr | ForEach-Object { Write-Log $_ "WARN" }
                Remove-Item $tempErr -Force -ErrorAction SilentlyContinue
            }

            # Leer ExitCode del intento 2 también con try/catch
            $exitCode2 = 0
            try { $exitCode2 = $proc2.ExitCode } catch { $exitCode2 = -1 }

            if ($exitCode2 -ne 0) {
                Write-Log "choco upgrade --ignore-checksums termino con errores (codigo $exitCode2). Revisa el log." "ERROR"
            } else {
                Write-Log "Actualizacion con --ignore-checksums completada exitosamente." "OK"
            }

            $lineaResumen = $salida2 | Where-Object { $_ -match "upgraded \d+/\d+ packages" } | Select-Object -Last 1

        } else {
            Write-Log "Actualizacion Chocolatey completada exitosamente." "OK"
            $lineaResumen = $salida1 | Where-Object { $_ -match "upgraded \d+/\d+ packages" } | Select-Object -Last 1
        }

        # Capturar resumen de actualizaciones
        $script:ChocoResumen = "sin cambios"
        if ($lineaResumen -match "upgraded (\d+)/(\d+) packages") {
            $script:ChocoResumen = "$($Matches[1]) de $($Matches[2]) apps actualizadas"
        }

        # Acumular espacio liberado por Chocolatey
        $espacioDespues = (Get-PSDrive C).Free
        $bytesChoco = $espacioDespues - $espacioAntes
        if ($bytesChoco -gt 0) { $script:BytesLiberados += $bytesChoco }

    } catch {
        Write-Log "Excepcion durante choco upgrade: $_" "ERROR"
    }

    Write-Log "MODULO 2 FINALIZADO." "OK"
}

# ------------------------------------------------------------------------------
# MÓDULO 3 — NOTIFICACIÓN TELEGRAM
# ------------------------------------------------------------------------------

function Enviar-Telegram {
    param([string]$Mensaje)

    $uri  = "https://api.telegram.org/bot$TelegramToken/sendMessage"
    $body = @{
        chat_id    = $TelegramChatID
        text       = $Mensaje
        parse_mode = "HTML"
    } | ConvertTo-Json -Compress

    try {
        $respuesta = Invoke-RestMethod -Uri $uri `
                                       -Method Post `
                                       -ContentType "application/json; charset=utf-8" `
                                       -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                                       -ErrorAction Stop
        if ($respuesta.ok) {
            Write-Log "Notificacion Telegram enviada correctamente." "OK"
        } else {
            Write-Log "Telegram respondio con error: $($respuesta | ConvertTo-Json)" "WARN"
        }
    } catch {
        Write-Log "No se pudo enviar notificacion Telegram: $_" "WARN"
    }
}

function Enviar-Resumen-Telegram {
    param(
        [timespan]$Duracion,
        [PSCustomObject]$Stats
    )

    $fecha   = Get-Date -Format "dd/MM/yyyy HH:mm"
    $equipo  = $env:COMPUTERNAME
    $usuario = $env:USERNAME
    $mins    = [math]::Round($Duracion.TotalMinutes, 1)

    # Contar errores y warnings reales (excluir "cannot find path" — son normales)
    $errores  = (Get-Content $logFile -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match "\[ERROR\]" }).Count
    $warnings = (Get-Content $logFile -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match "\[WARN\]" -and $_ -notmatch "cannot find path" -and $_ -notmatch "Cannot find path" }).Count

    $estado = if ($errores -gt 0) { "con $errores error(es)" } elseif ($warnings -gt 0) { "con $warnings aviso(s)" } else { "sin errores" }

    # Formatear espacio liberado esta semana
    $mb = [math]::Round($script:BytesLiberados / 1MB, 1)
    $espacioTexto = if ($mb -ge 1024) { "$([math]::Round($mb/1024, 2)) GB" } else { "$mb MB" }

    # Formatear acumulado anual con equivalencias
    $semana      = if ($Stats) { $Stats.semanas_registradas } else { 1 }
    $bytesAnio   = if ($Stats) { [long]$Stats.bytes_acumulados } else { $script:BytesLiberados }
    $mbAnio      = [math]::Round($bytesAnio / 1MB, 1)
    $acumTexto   = if ($mbAnio -ge 1024) { "$([math]::Round($mbAnio/1024, 2)) GB" } else { "$mbAnio MB" }
    $fotos       = [math]::Round($bytesAnio / 5MB)
    $canciones   = [math]::Round($bytesAnio / 4MB)

    $msg = @"
<b>TuPcVeloz - Mantenimiento Semanal</b>

<b>Equipo:</b> $equipo
<b>Usuario:</b> $usuario
<b>Fecha:</b> $fecha
<b>Duracion:</b> $mins minutos
<b>Espacio liberado:</b> $espacioTexto
<b>Apps actualizadas:</b> $($script:ChocoResumen)
<b>Estado:</b> $estado

<b>Acumulado anual (semana $semana de 52):</b>
  Total liberado: $acumTexto
  Equivale a: ~$fotos fotos de 5MB
              ~$canciones canciones de 4MB

<b>Modulos ejecutados:</b>
- Modulo 1: Limpieza de temporales y caches
- Modulo 2: Actualizacion Chocolatey
- Modulo 3: Log generado en Escritorio del cliente

<b>Log completo:</b> $logFile
"@

    Enviar-Telegram -Mensaje $msg
}

# ------------------------------------------------------------------------------
# MÓDULO 5 — LOG LEGIBLE PARA EL CLIENTE (ESCRITORIO)
# ------------------------------------------------------------------------------

function Crear-LogCliente {
    param(
        [timespan]$Duracion,
        [PSCustomObject]$Stats
    )

    $fecha  = Get-Date -Format "dd/MM/yyyy 'a las' HH:mm"
    $equipo = $env:COMPUTERNAME
    $mins   = [math]::Round($Duracion.TotalMinutes, 1)

    # Detectar usuario humano real (no SYSTEM ni cuenta de maquina NombrePC$)
    # Try/catch por si CimCmdlets no carga en PS7 Core (ej: Windows IoT LTSC)
    $usuarioReal = $null
    try {
        $usuarioReal = (Get-CimInstance -Class Win32_ComputerSystem -ErrorAction Stop).UserName
    } catch {
        Write-Log "Get-CimInstance no disponible, usando fallback de C:\Users" "WARN"
    }
    if ($usuarioReal -and $usuarioReal -match '\\') {
        $usuarioReal = $usuarioReal.Split('\')[1]
    }
    # Fallback: buscar primer usuario humano en C:\Users excluyendo cuentas del sistema
    if (-not $usuarioReal -or $usuarioReal -match '\$$' -or $usuarioReal -eq 'SYSTEM') {
        $usuarioReal = Get-ChildItem "C:\Users" -Directory |
                       Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') -and $_.Name -notmatch '\$$' } |
                       Select-Object -First 1 -ExpandProperty Name
    }

    $usuario        = $usuarioReal
    $escritorio     = "C:\Users\$usuario\Desktop"
    $archivoCliente = "$escritorio\TuPcVeloz-Ultimo-Mantenimiento.txt"

    $mb = [math]::Round($script:BytesLiberados / 1MB, 1)
    $espacioTexto = if ($mb -ge 1024) { "$([math]::Round($mb/1024, 2)) GB" } else { "$mb MB" }

    # Acumulado anual para el cliente
    $semana    = if ($Stats) { $Stats.semanas_registradas } else { 1 }
    $bytesAnio = if ($Stats) { [long]$Stats.bytes_acumulados } else { $script:BytesLiberados }
    $mbAnio    = [math]::Round($bytesAnio / 1MB, 1)
    $acumTexto = if ($mbAnio -ge 1024) { "$([math]::Round($mbAnio/1024, 2)) GB" } else { "$mbAnio MB" }
    $fotos     = [math]::Round($bytesAnio / 5MB)
    $canciones = [math]::Round($bytesAnio / 4MB)
    $inicioCiclo = if ($Stats) { $Stats.inicio_ciclo } else { (Get-Date -Format "yyyy-MM-dd") }

    $contenido = @"
============================================================
  TuPcVeloz - Servicio de Mantenimiento Semanal
============================================================

Tu PC fue revisada y optimizada el $fecha.

Equipo : $equipo
Usuario: $usuario
Duracion: $mins minutos
Espacio liberado esta semana: $espacioTexto
Apps actualizadas: $($script:ChocoResumen)

LO QUE SE HIZO EN ESTA SESION:

  [OK] Limpieza de archivos temporales y caches
       - Temporales de Windows y usuarios
       - Cache de navegadores (Chrome, Firefox, Edge, etc.)
       - Papelera de reciclaje vaciada
       - Archivos Prefetch antiguos eliminados
       - Tareas programadas no deseadas eliminadas

  [OK] Actualizacion de programas instalados
       - Se actualizaron automaticamente todos los programas
         gestionados por Chocolatey

============================================================
  RESUMEN ANUAL ACUMULADO (semana $semana de 52)
  Desde: $inicioCiclo
============================================================

  Total liberado en el año : $acumTexto
  Equivale aproximadamente a: $fotos fotos de 5MB
                               $canciones canciones de 4MB

  Sin el servicio TuPcVeloz, toda esa basura digital
  seguiria frenando tu PC semana a semana.

============================================================
  Tu PC esta optimizada y lista para usar.
  Servicio brindado por TuPcVeloz - tupcveloz.com
============================================================
"@

    # Inyectar aviso de vencimiento si corresponde (faltan 14 dias o menos)
    if ($script:AvisoVencimiento) {
        $contenido += "`r`n`r`n*** $($script:AvisoVencimiento) ***"
    }

    # Crear el .txt directamente en el Escritorio del cliente
    try {
        if (-not (Test-Path $escritorio)) {
            New-Item -Path $escritorio -ItemType Directory -Force | Out-Null
        }
        $contenido | Out-File -FilePath $archivoCliente -Encoding UTF8 -Force
        Write-Log "Log para el cliente generado en: $archivoCliente" "OK"
    } catch {
        Write-Log "No se pudo crear el log para el cliente: $_" "WARN"
        return
    }

    # Devolver el contenido y la ruta para que Mostrar-VentanaReporte los use
    return [PSCustomObject]@{
        Contenido = $contenido
        Ruta      = $archivoCliente
    }
}

# ------------------------------------------------------------------------------
# MÓDULO 6 — VENTANA WINFORMS CON COUNTDOWN
# ------------------------------------------------------------------------------

function Mostrar-VentanaReporte {
    param(
        [string]$Contenido,
        [string]$RutaTxt,
        [string]$BannerColor = "30,120,200",   # RGB azul normal
        [string]$BannerTitulo = "TuPcVeloz - Mantenimiento Semanal",
        [int]$Countdown = 18                    # 0 = sin countdown (ventana de vencimiento)
    )

    # El servicio NSSM corre en Session 0 (aislada del escritorio del usuario).
    # Las ventanas creadas desde Session 0 son invisibles para el usuario.
    # Solucion: escribir un .ps1 auxiliar en Public\Documents\AutoTemp y
    # lanzarlo via schtasks como el usuario activo (Session 1), que si
    # tiene acceso al escritorio. La tarea se autoeliminara al terminar.

    # Escapar el contenido para embeber en here-string dentro del .ps1 auxiliar
    $contenidoEscapado = $Contenido -replace "'", "''"

    $auxScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$segundos = $Countdown
`$rgb      = '$BannerColor' -split ','

`$form                 = New-Object System.Windows.Forms.Form
`$form.Text            = 'TuPcVeloz'
`$form.Size            = New-Object System.Drawing.Size(560, 560)
`$form.StartPosition   = 'CenterScreen'
`$form.FormBorderStyle = 'FixedDialog'
`$form.MaximizeBox     = `$false
`$form.TopMost         = `$true
`$form.BackColor       = [System.Drawing.Color]::FromArgb(245, 245, 245)

`$banner               = New-Object System.Windows.Forms.Panel
`$banner.Dock          = 'Top'
`$banner.Height        = 48
`$banner.BackColor     = [System.Drawing.Color]::FromArgb([int]`$rgb[0], [int]`$rgb[1], [int]`$rgb[2])
`$form.Controls.Add(`$banner)

`$lblT                 = New-Object System.Windows.Forms.Label
`$lblT.Text            = '  $BannerTitulo'
`$lblT.Dock            = 'Fill'
`$lblT.Font            = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
`$lblT.ForeColor       = [System.Drawing.Color]::White
`$lblT.TextAlign       = 'MiddleLeft'
`$banner.Controls.Add(`$lblT)

`$txt                  = New-Object System.Windows.Forms.TextBox
`$txt.Multiline        = `$true
`$txt.ScrollBars       = 'Vertical'
`$txt.ReadOnly         = `$true
`$txt.Font             = New-Object System.Drawing.Font('Courier New', 9)
`$txt.BackColor        = [System.Drawing.Color]::White
`$txt.ForeColor        = [System.Drawing.Color]::FromArgb(30, 30, 30)
`$txt.Location         = New-Object System.Drawing.Point(10, 58)
`$txt.Size             = New-Object System.Drawing.Size(524, 400)
`$txt.Text             = '$contenidoEscapado'
`$form.Controls.Add(`$txt)

`$lblCuenta            = New-Object System.Windows.Forms.Label
`$lblCuenta.Location   = New-Object System.Drawing.Point(10, 468)
`$lblCuenta.Size       = New-Object System.Drawing.Size(340, 24)
`$lblCuenta.Font       = New-Object System.Drawing.Font('Segoe UI', 9)
`$lblCuenta.ForeColor  = [System.Drawing.Color]::FromArgb(100, 100, 100)
`$form.Controls.Add(`$lblCuenta)

`$btn                  = New-Object System.Windows.Forms.Button
`$btn.Text             = 'Cerrar'
`$btn.Location         = New-Object System.Drawing.Point(430, 462)
`$btn.Size             = New-Object System.Drawing.Size(104, 32)
`$btn.Font             = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
`$btn.BackColor        = [System.Drawing.Color]::FromArgb([int]`$rgb[0], [int]`$rgb[1], [int]`$rgb[2])
`$btn.ForeColor        = [System.Drawing.Color]::White
`$btn.FlatStyle        = 'Flat'
`$btn.FlatAppearance.BorderSize = 0
`$btn.Add_Click({ `$form.Close() })
`$form.Controls.Add(`$btn)

if (`$segundos -gt 0) {
    `$lblCuenta.Text = "Cerrando en `$segundos segundos..."
    `$restantes = `$segundos
    `$timer = New-Object System.Windows.Forms.Timer
    `$timer.Interval = 1000
    `$timer.Add_Tick({
        `$script:restantes--
        if (`$script:restantes -le 0) { `$timer.Stop(); `$form.Close() }
        else { `$lblCuenta.Text = "Cerrando en `$script:restantes segundos..." }
    })
    `$timer.Start()
} else {
    `$lblCuenta.Text = 'Hace clic en Cerrar cuando termines de leer.'
}

[System.Windows.Forms.Application]::Run(`$form)
"@

    # Escribir el .ps1 auxiliar sin BOM en AutoTemp
    $auxPath = "$logDir\TuPcVeloz-Reporte-Aux.ps1"
    try {
        [System.IO.File]::WriteAllText($auxPath, $auxScript, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Log "No se pudo escribir script auxiliar WinForms: $_" "WARN"
        return
    }

    # Detectar usuario activo (el que tiene sesion en el escritorio)
    $usuarioActivo = $null
    try {
        $quser = & quser 2>$null
        if ($quser) {
            $lineaActiva = $quser | Where-Object { $_ -match 'Activ|Active' } | Select-Object -First 1
            if (-not $lineaActiva) { $lineaActiva = $quser | Select-Object -Skip 1 -First 1 }
            if ($lineaActiva -match '^\s*>?\s*(\S+)') {
                $usuarioActivo = $Matches[1].TrimStart('>')
            }
        }
    } catch { }

    if (-not $usuarioActivo) {
        # Fallback: primer usuario humano de C:\Users
        $usuarioActivo = Get-ChildItem "C:\Users" -Directory |
            Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') -and $_.Name -notmatch '\$$' } |
            Select-Object -First 1 -ExpandProperty Name
    }

    if (-not $usuarioActivo) {
        Write-Log "No se pudo detectar usuario activo para lanzar ventana WinForms." "WARN"
        return
    }

    # Nombre unico para la tarea (evita colisiones si corre dos veces seguidas)
    $taskName = "TuPcVeloz-Reporte-$(Get-Date -Format 'HHmmss')"

    # Crear tarea programada que corre como el usuario activo, una sola vez, ahora
    # /ST con hora actual + 1 min para que schtasks la acepte; /RU sin password
    $horaEjecucion = (Get-Date).AddMinutes(1).ToString("HH:mm")
    $argCmd = "/C schtasks /Create /TN `"$taskName`" /TR `"pwsh -WindowStyle Hidden -NonInteractive -File '$auxPath'`" /SC ONCE /ST $horaEjecucion /RU `"$usuarioActivo`" /F /RL LIMITED"

    try {
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $argCmd -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            # Ejecutar la tarea inmediatamente sin esperar la hora programada
            Start-Sleep -Seconds 2
            schtasks /Run /TN $taskName 2>$null | Out-Null
            # Programar eliminacion de la tarea auxiliar tras 5 minutos
            Start-Job -ScriptBlock {
                param($tn)
                Start-Sleep -Seconds 300
                schtasks /Delete /TN $tn /F 2>$null | Out-Null
            } -ArgumentList $taskName | Out-Null
            Write-Log "Ventana WinForms lanzada como usuario '$usuarioActivo' via schtasks ($taskName)." "OK"
        } else {
            Write-Log "schtasks devolvio codigo $($proc.ExitCode) al crear tarea WinForms." "WARN"
        }
    } catch {
        Write-Log "No se pudo lanzar ventana WinForms via schtasks: $_" "WARN"
    }
}

# ------------------------------------------------------------------------------
# MÓDULO 7 — ACTUALIZACIÓN SEGURA DE PAQUETES POSTERGADOS
# ------------------------------------------------------------------------------
# powershell-core: su instalador MSI reemplaza el ejecutable en uso. Si corre
#   durante el script mata el proceso pwsh padre. Se actualiza al final.
# rustdesk: su instalador reinicia el servicio RustDesk, lo que puede cortar
#   sesiones remotas activas en medio del mantenimiento. Al final es seguro.
# ------------------------------------------------------------------------------

function Actualizar-PaquetesPostergados {
    Write-Separador "MODULO 7: ACTUALIZACION DE PAQUETES POSTERGADOS"

    $paquetes = @("powershell-core", "rustdesk.install")
    $tempOut7  = "$logDir\choco_post_output.tmp"
    $tempErr7  = "$logDir\choco_post_error.tmp"

    foreach ($pkg in $paquetes) {
        Write-Log "Actualizando paquete postergado: $pkg" "INFO"
        try {
            $p = Start-Process -FilePath "choco" `
                               -ArgumentList "upgrade $pkg -y --no-progress" `
                               -RedirectStandardOutput $tempOut7 `
                               -RedirectStandardError  $tempErr7 `
                               -NoNewWindow -PassThru -Wait

            if (Test-Path $tempOut7) {
                Get-Content $tempOut7 | ForEach-Object { Write-Log $_ "INFO" }
                Remove-Item $tempOut7 -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $tempErr7) {
                Get-Content $tempErr7 | ForEach-Object { Write-Log $_ "WARN" }
                Remove-Item $tempErr7 -Force -ErrorAction SilentlyContinue
            }

            $exitCode7 = 0
            try { $exitCode7 = $p.ExitCode } catch { $exitCode7 = -1 }

            if ($exitCode7 -eq 0) {
                Write-Log "Paquete '$pkg' actualizado correctamente." "OK"
            } else {
                Write-Log "choco upgrade $pkg termino con codigo $exitCode7." "WARN"
            }
        } catch {
            Write-Log "Error al actualizar '$pkg': $_" "WARN"
        }
    }

    Write-Log "MODULO 7 FINALIZADO." "OK"
}

# ------------------------------------------------------------------------------
# FUNCIÓN: BLINDAJE NTFS DE CONFIG.JSON
# ------------------------------------------------------------------------------

function Blindar-Config {
    param([string]$Ruta)
    try {
        # Deshabilitar herencia y quitar permisos heredados
        & icacls $Ruta /inheritance:d /T /Q 2>&1 | Out-Null
        # Quitar acceso a usuarios normales
        & icacls $Ruta /remove "BUILTIN\Users" /T /Q 2>&1 | Out-Null
        & icacls $Ruta /remove "NT AUTHORITY\Authenticated Users" /T /Q 2>&1 | Out-Null
        # Asegurar que SYSTEM y Administradores conservan lectura
        & icacls $Ruta /grant "NT AUTHORITY\SYSTEM:(R)" /Q 2>&1 | Out-Null
        & icacls $Ruta /grant "BUILTIN\Administrators:(R)" /Q 2>&1 | Out-Null
        Write-Log "config.json blindado con permisos NTFS restringidos." "OK"
    } catch {
        Write-Log "No se pudo blindar config.json: $_" "WARN"
    }
}

# ------------------------------------------------------------------------------
# EJECUCIÓN PRINCIPAL
# ------------------------------------------------------------------------------

Write-Log "======================================================" "INFO"
Write-Log "  INICIO DE MANTENIMIENTO SEMANAL" "INFO"
Write-Log "  Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
Write-Log "  Usuario: $env:USERNAME | Equipo: $env:COMPUTERNAME" "INFO"
Write-Log "======================================================" "INFO"

try {
    Iniciar-Limpieza
} catch {
    Write-Log "Error fatal en MODULO 1: $_" "ERROR"
}

try {
    Iniciar-Chocolatey
} catch {
    Write-Log "Error fatal en MODULO 2: $_" "ERROR"
}

# Calcular duracion final
$duracion = (Get-Date) - $fechaInicio

# Gestionar estadísticas anuales acumuladas
$stats = $null
try {
    $stats = Gestionar-Estadisticas -BytesEstaSemana $script:BytesLiberados
} catch {
    Write-Log "Error en Gestionar-Estadisticas: $_" "WARN"
}

# Resumen en log tecnico
Write-Log "======================================================" "INFO"
Write-Log "  MANTENIMIENTO COMPLETADO" "OK"
Write-Log "  Duracion total: $([math]::Round($duracion.TotalMinutes, 1)) minutos" "INFO"
Write-Log "  Log guardado en: $logFile" "INFO"
Write-Log "======================================================" "INFO"

# Modulo 4 — Notificacion Telegram
try {
    Enviar-Resumen-Telegram -Duracion $duracion -Stats $stats
} catch {
    Write-Log "Error fatal en MODULO 4 (Telegram): $_" "ERROR"
}

# Modulo 5 — Log para el cliente en el Escritorio + ventana WinForms
$resultadoLog = $null
try {
    $resultadoLog = Crear-LogCliente -Duracion $duracion -Stats $stats
} catch {
    Write-Log "Error fatal en MODULO 5 (Log cliente): $_" "ERROR"
}

# Modulo 6 — Ventana WinForms con countdown
if ($resultadoLog -and $resultadoLog.Contenido) {
    try {
        Mostrar-VentanaReporte -Contenido $resultadoLog.Contenido -RutaTxt $resultadoLog.Ruta
    } catch {
        Write-Log "Error al lanzar ventana WinForms: $_" "WARN"
    }
}

# Modulo 7 — Actualizacion segura de paquetes postergados (pwsh-core, rustdesk)
# Se ejecuta AL FINAL, cuando ya terminaron todos los modulos y el reporte fue
# generado. Si el instalador mata el proceso pwsh (caso powershell-core), no
# afecta nada de lo anterior. rustdesk se excluye del choco normal porque su
# instalador reinicia el servicio y puede interferir con conexiones activas.
try {
    Actualizar-PaquetesPostergados
} catch {
    Write-Log "Error en Modulo 7 (paquetes postergados): $_" "WARN"
}

# Blindaje NTFS del config.json (idempotente, corre siempre al final)
try {
    Blindar-Config -Ruta $ConfigPath
} catch {
    Write-Log "Error en Blindar-Config: $_" "WARN"
}
