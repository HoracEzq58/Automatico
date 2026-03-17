# ======================================================
# Seccion xx ConfigEverything.ps1 
# ======================================================

# 1. Aseguramos que Everything esté cerrado para escribir en el archivo de config
Stop-Process -Name "Everything" -ErrorAction SilentlyContinue

$iniPath = "$env:APPDATA\Everything\Everything.ini"

# Si el archivo no existe en AppData, probamos en la carpeta de instalación (portable)
if (-not (Test-Path $iniPath)) {
    $iniPath = "C:\Program Files\Everything\Everything.ini"
}

if (Test-Path $iniPath) {
    Write-Host "Configurando Everything para usuarios 'normalitos'..." -ForegroundColor Cyan

    # Definimos los cambios (1 = Activado, 0 = Desactivado)
    $settings = @{
        "hide_results_when_search_is_empty" = 1  # No mostrar nada al abrir
        "exclude_system_files"              = 1  # Ocultar archivos raros de sistema
        "exclude_hidden_files"              = 1  # Ocultar carpetas ocultas
        "show_status_bar"                   = 0  # Vista más limpia sin barra de estado
        "match_path"                        = 0  
    }

    $content = Get-Content $iniPath

    foreach ($key in $settings.Keys) {
        $value = $settings[$key]
        if ($content -match "^$key=") {
            $content = $content -replace "^$key=.*", "$key=$value"
        } else {
            $content += "$key=$value"
        }
    }

    $content | Set-Content $iniPath -Encoding UTF8
    Write-Host "¡Configuración aplicada con éxito!" -ForegroundColor Green
    
    # Reiniciamos el proceso
    Start-Process "Everything.exe"
} else {
    Write-Error "No se encontró el archivo Everything.ini. ¿Está instalado?"
}