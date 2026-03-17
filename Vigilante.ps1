# ==============================================================================
# Vigilante.ps1
# Servicio watchdog para MantenimientoSemanal.ps1
# Corre como servicio Windows via NSSM — SIN ventanas, en segundo plano
# ==============================================================================

#Requires -Version 7.0

# ------------------------------------------------------------------------------
# CONFIGURACIÓN — ajusta estas rutas si cambiaste la ubicación del script
# ------------------------------------------------------------------------------
$scriptMantenimiento = "C:\Users\Public\Documents\Automatico\MantenimientoSemanal.ps1"
$logDir              = "C:\Users\Public\Documents\AutoTemp"
$archivoUltimaVez    = "$logDir\ultima_ejecucion.txt"
$logVigilante        = "$logDir\Vigilante.log"
$diasEntreCorridas   = 7          # Cada cuántos días ejecutar
$horasEntreChecks    = 6          # Cada cuántas horas re-comprobar si el PC sigue encendido

# ------------------------------------------------------------------------------
# FUNCIÓN DE LOG (sin consola, solo archivo — es un servicio)
# ------------------------------------------------------------------------------
function Write-LogV {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Nivel] $Mensaje" | Out-File -FilePath $logVigilante -Append
}

# Crear carpeta de logs si no existe
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

Write-LogV "======================================================="
Write-LogV "  Servicio Vigilante iniciado"
Write-LogV "  Script a vigilar: $scriptMantenimiento"
Write-LogV "  Intervalo mínimo: $diasEntreCorridas días"
Write-LogV "  Re-check cada:    $horasEntreChecks horas"
Write-LogV "======================================================="

# ------------------------------------------------------------------------------
# FUNCIÓN: leer fecha de última ejecución
# ------------------------------------------------------------------------------
function Get-UltimaEjecucion {
    if (Test-Path $archivoUltimaVez) {
        try {
            $contenido = Get-Content $archivoUltimaVez -Raw
            return [datetime]::Parse($contenido.Trim())
        } catch {
            Write-LogV "No se pudo leer la fecha de última ejecución. Se asume nunca." "WARN"
            return [datetime]::MinValue
        }
    }
    return [datetime]::MinValue   # Nunca se ejecutó → ejecutar ya
}

# ------------------------------------------------------------------------------
# FUNCIÓN: guardar fecha de última ejecución
# ------------------------------------------------------------------------------
function Set-UltimaEjecucion {
    (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $archivoUltimaVez -Force
}

# ------------------------------------------------------------------------------
# FUNCIÓN: lanzar mantenimiento SIN ventana visible (segundo plano real)
# ------------------------------------------------------------------------------
function Lanzar-Mantenimiento {
    Write-LogV "Lanzando MantenimientoSemanal.ps1 en segundo plano..." "INFO"

    try {
        # Start-Process con WindowStyle Hidden = sin ventana visible para el usuario
        $proceso = Start-Process -FilePath "pwsh.exe" `
            -ArgumentList "-NonInteractive", "-WindowStyle", "Hidden", "-File", "`"$scriptMantenimiento`"" `
            -Verb RunAs `
            -PassThru `
            -WindowStyle Hidden

        Write-LogV "Proceso lanzado. PID: $($proceso.Id)" "OK"

        # Esperar a que termine y capturar código de salida
        $proceso.WaitForExit()
        $codigoSalida = $proceso.ExitCode
        Write-LogV "Mantenimiento finalizado. Código de salida: $codigoSalida" $(if ($codigoSalida -eq 0) { "OK" } else { "WARN" })

        # Guardar timestamp de esta ejecución
        Set-UltimaEjecucion
        Write-LogV "Fecha de última ejecución actualizada." "OK"

    } catch {
        Write-LogV "Error al lanzar el mantenimiento: $_" "ERROR"
    }
}

# ------------------------------------------------------------------------------
# BUCLE PRINCIPAL DEL SERVICIO
# Corre indefinidamente. NSSM lo reinicia si falla.
# ------------------------------------------------------------------------------
Write-LogV "Entrando en bucle de vigilancia..." "INFO"

while ($true) {

    $ultimaVez    = Get-UltimaEjecucion
    $ahora        = Get-Date
    $diasPasados  = ($ahora - $ultimaVez).TotalDays

    Write-LogV "Comprobando... Última ejecución: $ultimaVez | Días transcurridos: $([math]::Round($diasPasados, 1))"

    if ($diasPasados -ge $diasEntreCorridas) {
        Write-LogV "Han pasado $([math]::Round($diasPasados, 1)) días (>= $diasEntreCorridas). ¡Ejecutando mantenimiento!" "OK"
        Lanzar-Mantenimiento
    } else {
        $diasRestantes = [math]::Round($diasEntreCorridas - $diasPasados, 1)
        Write-LogV "Aún faltan $diasRestantes días para el próximo mantenimiento. Durmiendo $horasEntreChecks horas." "INFO"
    }

    # Dormir X horas antes del próximo check
    # (si el PC se apaga y enciende, NSSM reinicia el servicio y vuelve a comprobar inmediatamente)
    Start-Sleep -Seconds ($horasEntreChecks * 3600)
}
