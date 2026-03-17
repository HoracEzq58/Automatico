@echo off
:: ==============================================================================
:: Desinstalar_Servicio.bat
:: Elimina el servicio MantenimientoSemanal de NSSM
:: Ejecutar como ADMINISTRADOR
:: ==============================================================================

title Desinstalar Servicio Mantenimiento Semanal
color 0C

echo.
echo  =====================================================
echo   DESINSTALADOR - Servicio MantenimientoSemanal
echo  =====================================================
echo.

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo  [ERROR] Ejecutar como Administrador.
    pause
    exit /b 1
)

echo  [INFO] Deteniendo y eliminando servicio...
nssm stop MantenimientoSemanal >nul 2>&1
nssm remove MantenimientoSemanal confirm

echo.
echo  [OK] Servicio eliminado.
echo  Los scripts en C:\Scripts y los logs NO se eliminaron.
echo.
pause
