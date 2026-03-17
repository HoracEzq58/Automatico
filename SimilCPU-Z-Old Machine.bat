@echo off
REM === Auto-relanzar dentro de cmd /k para que la ventana no se cierre ===
if "%~1"=="RELAUNCHED" goto :main
cmd /k "%~f0" RELAUNCHED
exit

:main
title Reporte de Hardware - Taller
setlocal EnableDelayedExpansion
chcp 1252 >nul

set "pcname=%COMPUTERNAME%"
set "outfile=%~dp0Reporte_%pcname%.txt"

echo Generando reporte, aguarde...
echo.

REM ============================================================
REM  ENCABEZADO
REM ============================================================
(
echo ==============================================
echo   REPORTE DE HARDWARE - TALLER
echo ==============================================
echo Equipo  : %pcname%
echo Usuario : %USERNAME%
echo Fecha   : %date%   Hora: %time%
echo ==============================================
echo.
) > "!outfile!"

REM ============================================================
REM  CPU
REM ============================================================
echo [CPU] >> "!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic cpu get Name /format:value 2^>nul ^| findstr "="') do (
    echo Modelo    : %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfCores /format:value 2^>nul ^| findstr "="') do (
    echo Nucleos   : %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfLogicalProcessors /format:value 2^>nul ^| findstr "="') do (
    echo Logicos   : %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get MaxClockSpeed /format:value 2^>nul ^| findstr "="') do (
    echo Velocidad : %%a MHz >> "!outfile!"
)
echo. >> "!outfile!"

REM ============================================================
REM  RAM
REM ============================================================
echo [MEMORIA RAM] >> "!outfile!"

REM --- Tipo DDR ---
set "tipoRAM=Desconocido"
for /f "tokens=2 delims==" %%a in ('wmic memorychip get SMBIOSMemoryType /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    if "%%a"=="20" set "tipoRAM=DDR1"
    if "%%a"=="21" set "tipoRAM=DDR2"
    if "%%a"=="22" set "tipoRAM=DDR2 FB-DIMM"
    if "%%a"=="24" set "tipoRAM=DDR3"
    if "%%a"=="26" set "tipoRAM=DDR4"
    if "%%a"=="34" set "tipoRAM=DDR5"
)
echo Tipo      : !tipoRAM! >> "!outfile!"

REM --- Velocidad ---
set "ramSpeed="
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Speed /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    if not defined ramSpeed set "ramSpeed=%%a"
)
if defined ramSpeed (
    echo Velocidad : !ramSpeed! MHz >> "!outfile!"
) else (
    echo Velocidad : No detectada >> "!outfile!"
)

REM --- Total GB via PowerShell (evita overflow de 32bit) ---
set "ramGB="
for /f %%m in ('powershell -NoProfile -Command "[math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB)" 2^>nul') do (
    set "ramGB=%%m"
)
if defined ramGB (
    echo Total     : !ramGB! GB >> "!outfile!"
) else (
    echo Total     : No detectado >> "!outfile!"
)

REM --- Slots usados ---
set "slots=0"
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Capacity /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    set /a slots+=1
)
echo Slots en uso: !slots! >> "!outfile!"
echo. >> "!outfile!"

REM ============================================================
REM  DISCO
REM ============================================================
echo [DISCO] >> "!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get Model /format:value 2^>nul ^| findstr "="') do (
    echo Modelo    : %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get InterfaceType /format:value 2^>nul ^| findstr "="') do (
    echo Interfaz  : %%a >> "!outfile!"
)
for /f %%s in ('powershell -NoProfile -Command "[math]::Round((Get-WmiObject Win32_DiskDrive | Select-Object -First 1).Size/1GB)" 2^>nul') do (
    echo Tamanio   : %%s GB >> "!outfile!"
)
for /f "usebackq tokens=*" %%t in (`powershell -NoProfile -Command "try { (Get-PhysicalDisk | Select-Object -First 1).MediaType } catch { 'No detectado' }" 2^>nul`) do (
    echo Tipo      : %%t >> "!outfile!"
)
echo. >> "!outfile!"

REM ============================================================
REM  MOTHERBOARD
REM ============================================================
echo [MOTHERBOARD] >> "!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Manufacturer /format:value 2^>nul ^| findstr "="') do (
    echo Fabricante: %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Product /format:value 2^>nul ^| findstr "="') do (
    echo Modelo    : %%a >> "!outfile!"
)
echo. >> "!outfile!"

REM ============================================================
REM  BIOS
REM ============================================================
echo [BIOS] >> "!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic bios get Manufacturer /format:value 2^>nul ^| findstr "="') do (
    echo Fabricante: %%a >> "!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic bios get SMBIOSBIOSVersion /format:value 2^>nul ^| findstr "="') do (
    echo Version   : %%a >> "!outfile!"
)
echo. >> "!outfile!"

REM ============================================================
REM  VIDEO
REM ============================================================
echo [VIDEO] >> "!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic path win32_VideoController get Name /format:value 2^>nul ^| findstr "="') do (
    echo Modelo    : %%a >> "!outfile!"
)
for /f %%v in ('powershell -NoProfile -Command "try { [math]::Round((Get-WmiObject Win32_VideoController | Select-Object -First 1).AdapterRAM/1MB) } catch { 0 }" 2^>nul') do (
    if %%v GTR 0 echo VRAM      : %%v MB >> "!outfile!"
)
echo. >> "!outfile!"

REM ============================================================
REM  MOSTRAR RESULTADO
REM ============================================================
cls
type "!outfile!"
echo.
echo ==============================================
echo  Reporte guardado en: !outfile!
echo ==============================================
echo.
echo Presione cualquier tecla para salir...
pause >nul
