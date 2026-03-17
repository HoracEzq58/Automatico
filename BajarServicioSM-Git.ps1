# BajarServicioSM-Git.ps1
$destino = "C:\Users\Public\Documents\Automatico"
New-Item -ItemType Directory -Force -Path $destino
$base = "https://raw.githubusercontent.com/HoracEzq58/Automatico/main"
$archivos = @(
    "MantenimientoSemanal.ps1",
    "Vigilante.ps1",
    "Instalar_ServicioMS.bat",
    "Desinstalar_ServicioMS.bat"
)
foreach ($archivo in $archivos) {
    Invoke-WebRequest "$base/$archivo" -OutFile "$destino\$archivo"
    Write-Host "Descargado: $archivo" -ForegroundColor Green
}