@echo off
setlocal enabledelayedexpansion
:: ==============================================================================
:: Instalar_ServicioMS.bat
:: Instala el servicio MantenimientoSemanal via NSSM
:: Ejecutar como ADMINISTRADOR
:: ==============================================================================

title Instalador Servicio Mantenimiento Semanal
color 0A

echo.
echo  =====================================================
echo   INSTALADOR - Servicio MantenimientoSemanal
echo  =====================================================
echo.

:: --- Verificar que se ejecuta como administrador ---
net session >nul 2>&1
if !errorlevel! NEQ 0 (
    echo  [ERROR] Este script debe ejecutarse como Administrador.
    echo  Clic derecho -^> Ejecutar como administrador
    pause
    exit /b 1
)
echo  [OK] Privilegios de administrador confirmados.

:: --- Rutas ---
set SCRIPTS_DIR=C:\Users\Public\Documents\Automatico
set LOG_DIR=C:\Users\Public\Documents\AutoTemp
set VIGILANTE=%SCRIPTS_DIR%\Vigilante.ps1
set INSTALL_LOG=%LOG_DIR%\Instalar_Servicio.log

:: --- Crear carpetas si no existen ---
if not exist "%SCRIPTS_DIR%" (
    mkdir "%SCRIPTS_DIR%"
    echo  [OK] Carpeta Automatico creada.
)
if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%"
    echo  [OK] Carpeta AutoTemp creada.
)

:: --- Log de instalacion ---
echo. >> "%INSTALL_LOG%"
echo ======================================================= >> "%INSTALL_LOG%"
echo  Instalacion iniciada: %DATE% %TIME% >> "%INSTALL_LOG%"
echo ======================================================= >> "%INSTALL_LOG%"

:: --- Verificar que NSSM esta disponible ---
where nssm >nul 2>&1
if !errorlevel! NEQ 0 (
    echo  [INFO] NSSM no encontrado. Instalando via Chocolatey...
    choco install nssm -y
    if !errorlevel! NEQ 0 (
        echo  [ERROR] No se pudo instalar NSSM. Asegurate de tener Chocolatey instalado.
        echo  [ERROR] Fallo instalacion NSSM >> "%INSTALL_LOG%"
        pause
        exit /b 1
    )
    echo  [OK] NSSM instalado via Chocolatey.
    echo  [OK] NSSM instalado via Chocolatey >> "%INSTALL_LOG%"
) else (
    echo  [OK] NSSM encontrado en PATH.
)

:: --- Verificar que pwsh.exe existe ---
if not exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    echo  [ERROR] PowerShell 7 no encontrado en %ProgramFiles%\PowerShell\7\pwsh.exe
    echo  [ERROR] Instala PowerShell 7 antes de continuar.
    echo  [ERROR] pwsh.exe no encontrado >> "%INSTALL_LOG%"
    pause
    exit /b 1
)
echo  [OK] PowerShell 7 encontrado.

:: --- Copiar scripts a Automatico ---
echo  [INFO] Copiando scripts a %SCRIPTS_DIR%...

if not exist "%~dp0Vigilante.ps1" (
    echo  [ERROR] No se encontro Vigilante.ps1 junto al bat.
    echo  [ERROR] Vigilante.ps1 no encontrado en origen >> "%INSTALL_LOG%"
    pause
    exit /b 1
)
if not exist "%~dp0MantenimientoSemanal.ps1" (
    echo  [ERROR] No se encontro MantenimientoSemanal.ps1 junto al bat.
    echo  [ERROR] MantenimientoSemanal.ps1 no encontrado en origen >> "%INSTALL_LOG%"
    pause
    exit /b 1
)

copy /Y "%~dp0Vigilante.ps1" "%SCRIPTS_DIR%\Vigilante.ps1" >nul
copy /Y "%~dp0MantenimientoSemanal.ps1" "%SCRIPTS_DIR%\MantenimientoSemanal.ps1" >nul
echo  [OK] Scripts copiados.
echo  [OK] Scripts copiados >> "%INSTALL_LOG%"

:: --- Eliminar servicio si ya existia (reinstalacion limpia) ---
:: Usamos sc query que es mas confiable que nssm status para detectar existencia
sc query MantenimientoSemanal >nul 2>&1
if !errorlevel! EQU 0 (
    echo  [INFO] Servicio ya existe. Eliminando para reinstalar...
    nssm stop MantenimientoSemanal >nul 2>&1
    timeout /t 2 /nobreak >nul
    nssm remove MantenimientoSemanal confirm
    if !errorlevel! NEQ 0 (
        echo  [ERROR] No se pudo eliminar el servicio existente.
        echo  [ERROR] Fallo nssm remove >> "%INSTALL_LOG%"
        pause
        exit /b 1
    )
    echo  [OK] Servicio anterior eliminado.
    echo  [OK] Servicio anterior eliminado >> "%INSTALL_LOG%"
    timeout /t 2 /nobreak >nul
)

:: --- Instalar servicio con NSSM ---
echo  [INFO] Instalando servicio con NSSM...
nssm install MantenimientoSemanal "%ProgramFiles%\PowerShell\7\pwsh.exe" "-NonInteractive -WindowStyle Hidden -File \"%VIGILANTE%\""
if !errorlevel! NEQ 0 (
    echo  [ERROR] Fallo nssm install.
    echo  [ERROR] Fallo nssm install >> "%INSTALL_LOG%"
    pause
    exit /b 1
)
echo  [OK] Servicio creado.

:: --- Configurar el servicio ---
echo  [INFO] Configurando parametros del servicio...

nssm set MantenimientoSemanal DisplayName "Mantenimiento Semanal (Limpieza + Chocolatey)"
nssm set MantenimientoSemanal Description "Ejecuta limpieza de temporales y actualizacion Chocolatey cada 7 dias. Sin ventanas."
nssm set MantenimientoSemanal Start SERVICE_AUTO_START
nssm set MantenimientoSemanal AppStdout "%LOG_DIR%\nssm_stdout.log"
nssm set MantenimientoSemanal AppStderr "%LOG_DIR%\nssm_stderr.log"
nssm set MantenimientoSemanal AppRotateFiles 1
nssm set MantenimientoSemanal AppRotateSeconds 604800
nssm set MantenimientoSemanal AppRotateBytes 1048576
nssm set MantenimientoSemanal AppExit Default Restart
nssm set MantenimientoSemanal AppRestartDelay 60000

echo  [OK] Parametros configurados.
echo  [OK] Parametros configurados >> "%INSTALL_LOG%"

:: --- Arrancar el servicio ---
echo  [INFO] Iniciando servicio...
nssm start MantenimientoSemanal
if !errorlevel! NEQ 0 (
    echo  [WARN] nssm start devolvio un error. Verificando estado real...
    echo  [WARN] nssm start con error - verificando >> "%INSTALL_LOG%"
)

:: --- Verificar estado final ---
timeout /t 3 /nobreak >nul
echo  [INFO] Estado del servicio:
sc query MantenimientoSemanal | findstr /I "STATE"

sc query MantenimientoSemanal | findstr /I "RUNNING" >nul 2>&1
if !errorlevel! EQU 0 (
    echo  [OK] Servicio corriendo correctamente.
    echo  [OK] Servicio RUNNING al finalizar instalacion >> "%INSTALL_LOG%"
) else (
    echo  [WARN] El servicio no figura como RUNNING. Revisar logs en %LOG_DIR%
    echo  [WARN] Servicio no RUNNING al finalizar >> "%INSTALL_LOG%"
)

echo  Instalacion finalizada: %DATE% %TIME% >> "%INSTALL_LOG%"

echo.
echo  =====================================================
echo   INSTALACION COMPLETADA
echo   Logs en: %LOG_DIR%
echo   - Instalar_Servicio.log       ^<- este proceso
echo   - Vigilante.log               ^<- actividad del watchdog
echo   - nssm_stdout.log / nssm_stderr.log
echo  =====================================================
echo.
echo  Para desinstalar ejecuta: Desinstalar_ServicioMS.bat
echo.
pause
endlocal