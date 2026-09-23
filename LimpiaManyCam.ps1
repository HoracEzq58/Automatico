# Nombre Archivo: "LimpiaManyCam.ps1" 23/09/2026 Modo AI
# Set-ExecutionPolicy Bypass -Scope Process -Force; & "C:\Users\pomelo\Downloads\LimpiaManyCam.ps1"
# 1. Frenar y borrar servicios rebeldes (frenamos ManyCam por si las dudas)
Stop-Service -Name "ManyCam Service" -Force -ErrorAction SilentlyContinue
Remove-Service -Name "ManyCam Service" -ErrorAction SilentlyContinue

# 2. Rutas del sistema donde Chocolatey y Windows metieron las garras
$RutasA_Limpiar = @(
    "$env:ProgramData",
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}",
    "$env:AppData",
    "$env:LocalAppData",
    "C:\ProgramData\chocolatey\.chocolatey",
    "C:\ProgramData\chocolatey\lib",
    "C:\Windows\SystemTemp\ChocolateyScratch"
)

# 3. Lista de palabras clave a eliminar de raíz (ManyCam y AutoHotkey)
$Objetivos = @("*ManyCam*", "*AutoHotkey*")

# 4. El súper barrido masivo de carpetas y archivos
foreach ($Ruta in $RutasA_Limpiar) {
    if (Test-Path $Ruta) {
        foreach ($Objetivo in $Objetivos) {
            # Busca archivos y carpetas que coincidan con los nombres objetivos
            Get-ChildItem -Path $Ruta -Filter $Objetivo -Recurse -ErrorAction SilentlyContinue | 
            ForEach-Object {
                Write-Host "Eliminando residuo: $($_.FullName)" -ForegroundColor Cyan
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Host "`n¡Limpieza completa de ManyCam y AutoHotkey finalizada!" -ForegroundColor Green
