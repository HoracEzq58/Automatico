# =================================================================
# nombre archivo: "AplicaEspArgReinicio.ps1" GROK - 11/09/2026
# Script definitivo - Forzar Español (Argentina) + Reinicio
# Ejecutar DESPUÉS de la macro TinyTask InstallPackEspArg.rec o exe  ===================================================================

Write-Host "`n[1/4] Forzando idioma de interfaz a es-AR por registro..." -ForegroundColor Cyan

# PreferredUILanguages
New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "PreferredUILanguages" -Value "es-AR" -PropertyType MultiString -Force | Out-Null

# MachinePreferredUILanguages
New-ItemProperty -Path "HKCU:\Control Panel\Desktop\MuiCached" -Name "MachinePreferredUILanguages" -Value "es-AR" -PropertyType MultiString -Force -ErrorAction SilentlyContinue | Out-Null

# SystemPreferredUILanguages
New-ItemProperty -Path "HKCU:\Control Panel\Desktop\MuiCached" -Name "SystemPreferredUILanguages" -Value "es-AR" -PropertyType MultiString -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "[OK] Valores de registro escritos" -ForegroundColor Green

# ------------------------------------------------------------
Write-Host "`n[2/4] Reforzando System Locale y Culture..." -ForegroundColor Cyan

try { Set-WinSystemLocale -SystemLocale es-AR -ErrorAction Stop; Write-Host "[OK] SystemLocale → es-AR" -ForegroundColor Green } catch { Write-Host "[!] SystemLocale: $_" -ForegroundColor Yellow }
try { Set-Culture es-AR -ErrorAction Stop; Write-Host "[OK] Culture → es-AR" -ForegroundColor Green } catch { Write-Host "[!] Culture: $_" -ForegroundColor Yellow }

# ------------------------------------------------------------
Write-Host "`n[3/4] Verificación final..." -ForegroundColor Cyan

$pref = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "PreferredUILanguages" -ErrorAction SilentlyContinue).PreferredUILanguages
$mach = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop\MuiCached" -ErrorAction SilentlyContinue).MachinePreferredUILanguages

Write-Host "PreferredUILanguages      : $pref"
Write-Host "MachinePreferredUILanguages: $mach"

if ($pref -eq "es-AR" -or $pref -contains "es-AR") {
    Write-Host "`n[OK] Idioma configurado correctamente → se aplicará al reiniciar" -ForegroundColor Green
} else {
    Write-Host "`n[ALERTA] No se pudo confirmar es-AR en el registro" -ForegroundColor Red
}

# ------------------------------------------------------------
Write-Host "`n[4/4] Reiniciando en 3 segundos..." -ForegroundColor Yellow
Write-Host "Presioná Ctrl+C si querés cancelar el reinicio`n"

Start-Sleep -Seconds 3
Restart-Computer -Force