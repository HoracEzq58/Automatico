# "ErradicaWindowsMediaPlayer-Modo.ps1"
# --- Script para erradicar Windows Media Player en Win 10 IoT LTSC ---
Write-Host "Iniciando proceso de erradicación..." -ForegroundColor Cyan

# 1. Matar procesos activos para evitar bloqueos de archivos
Write-Host "Deteniendo procesos y servicios..."
Stop-Process -Name "wmplayer", "wmpnetwk", "wmlaunch" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "WMPNetworkSvc" -ErrorAction SilentlyContinue

# 2. Eliminar como "Capacidad de Windows" (Método oficial LTSC)
$wmp = Get-WindowsCapability -Online | Where-Object { $_.Name -like "*WindowsMediaPlayer*" }
if ($wmp) {
    Write-Host "Eliminando capacidad: $($wmp.Name)"
    Remove-WindowsCapability -Online -Name $wmp.Name | Out-Null
}

# 3. Intentar remover vía DISM (Parámetro /Remove borra el payload)
Write-Host "Ejecutando limpieza profunda con DISM..."
dism /online /disable-feature /featurename:WindowsMediaPlayer /remove /norestart /quiet

# 4. Forzar toma de posesión y borrado de archivos físicos
$paths = @("${env:ProgramFiles(x86)}\Windows Media Player", "${env:ProgramFiles}\Windows Media Player")

foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "Atacando carpeta: $path"
        # takeown en español usa /d s (Sí)
        takeown /f $path /r /d s | Out-Null
        # Usamos el SID *S-1-5-32-544 (Administradores) para que funcione en cualquier idioma
        icacls $path /grant "*S-1-5-32-544:F" /t /inheritance:e /q
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 5. Limpieza de accesos directos en el Menú Inicio
$shortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Media Player.lnk"
if (Test-Path $shortcut) { Remove-Item $shortcut -Force }

Write-Host "Proceso completado. Se recomienda reiniciar para purgar el registro." -ForegroundColor Green
