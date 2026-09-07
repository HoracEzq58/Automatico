@echo off
REM ============================================================
REM SimilCPU-Z - Old Machine
REM Version 4 - 07/09/2026 13.40hs ChatGPT
REM DDR2 / DDR3 / DDR4 / DDR5
REM ============================================================

if "%~1"=="RELAUNCHED" goto main
cmd /k "%~f0" RELAUNCHED
exit /b

:main
title Reporte de Hardware - Taller
setlocal EnableDelayedExpansion
chcp 1252 >nul

set "pcname=%COMPUTERNAME%"
set "outfile=%~dp0%pcname%.txt"
set "tmpfile=%TEMP%\SimilCPUZ_%RANDOM%.tmp"

 echo Generando reporte, aguarde...
echo.

>"!outfile!" echo ==============================================
>>"!outfile!" echo   REPORTE DE HARDWARE - TALLER
>>"!outfile!" echo ==============================================
>>"!outfile!" echo Equipo  : %pcname%
>>"!outfile!" echo Usuario : %USERNAME%
>>"!outfile!" echo Fecha   : %date%   Hora: %time%
>>"!outfile!" echo ==============================================
>>"!outfile!" echo.

REM ============================================================
REM CPU
REM ============================================================
>>"!outfile!" echo [CPU]
for /f "tokens=2 delims==" %%a in ('wmic cpu get Name /format:value 2^>nul ^| findstr "="') do echo Modelo    : %%a>>"!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfCores /format:value 2^>nul ^| findstr "="') do echo Nucleos   : %%a>>"!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfLogicalProcessors /format:value 2^>nul ^| findstr "="') do echo Logicos   : %%a>>"!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic cpu get MaxClockSpeed /format:value 2^>nul ^| findstr "="') do echo Velocidad : %%a MHz>>"!outfile!"
>>"!outfile!" echo.

REM ============================================================
REM MEMORIA RAM - DDR2 en adelante
REM ============================================================
>>"!outfile!" echo [MEMORIA RAM]
set "tipoRAM=Desconocido"

REM --- Deteccion primaria: SMBIOSMemoryType via PowerShell/CIM ---
powershell -NoProfile -Command "Get-CimInstance Win32_PhysicalMemory | Select-Object -ExpandProperty SMBIOSMemoryType" >"!tmpfile!" 2>nul
for /f "usebackq tokens=*" %%a in ("!tmpfile!") do (
    if "%%a"=="21" set "tipoRAM=DDR2"
    if "%%a"=="22" set "tipoRAM=DDR2 FB-DIMM"
    if "%%a"=="24" set "tipoRAM=DDR3"
    if "%%a"=="26" set "tipoRAM=DDR4"
    if "%%a"=="34" set "tipoRAM=DDR5"
)

REM --- Fallback: WMIC SMBIOSMemoryType ---
if not "!tipoRAM!"=="Desconocido" goto ram_type_done
for /f "tokens=2 delims==" %%a in ('wmic memorychip get SMBIOSMemoryType /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    if "%%a"=="21" set "tipoRAM=DDR2"
    if "%%a"=="22" set "tipoRAM=DDR2 FB-DIMM"
    if "%%a"=="24" set "tipoRAM=DDR3"
    if "%%a"=="26" set "tipoRAM=DDR4"
    if "%%a"=="34" set "tipoRAM=DDR5"
)

REM --- Fallback final: MemoryType ---
if not "!tipoRAM!"=="Desconocido" goto ram_type_done
for /f "tokens=2 delims==" %%a in ('wmic memorychip get MemoryType /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    if "%%a"=="21" set "tipoRAM=DDR2"
    if "%%a"=="24" set "tipoRAM=DDR3"
)

:ram_type_done
>>"!outfile!" echo Tipo      : !tipoRAM!

set "ramSpeed="
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Speed /format:value 2^>nul ^| findstr /R "=[0-9]"') do if not defined ramSpeed set "ramSpeed=%%a"
if defined ramSpeed goto ram_speed_ok
>>"!outfile!" echo Velocidad : No detectada
goto ram_speed_done
:ram_speed_ok
>>"!outfile!" echo Velocidad : !ramSpeed! MHz
:ram_speed_done

REM Total RAM: PowerShell se ejecuta fuera de un bloque IF/FOR.
powershell -NoProfile -Command "[math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB)" >"!tmpfile!" 2>nul
set "ramGB="
set /p ramGB=<"!tmpfile!"
if defined ramGB goto ram_total_ok
>>"!outfile!" echo Total     : No detectado
goto ram_total_done
:ram_total_ok
>>"!outfile!" echo Total     : !ramGB! GB
:ram_total_done

set "slots=0"
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Capacity /format:value 2^>nul ^| findstr /R "=[0-9]"') do set /a slots+=1
>>"!outfile!" echo Slots en uso: !slots!

set "canal=No detectado"
if !slots! EQU 1 set "canal=Single Channel (1 modulo)"
if !slots! LSS 2 goto channel_done
if !slots! GTR 2 goto channel_multi

set "tam1="
set "tam2="
set "count=0"
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Capacity /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    set /a count+=1
    if !count! EQU 1 set "tam1=%%a"
    if !count! EQU 2 set "tam2=%%a"
)
if "!tam1!"=="!tam2!" set "canal=Dual Channel probable (2 modulos iguales)"
if not "!tam1!"=="!tam2!" set "canal=Single/Flex Channel posible (2 modulos distintos)"
goto channel_done

:channel_multi
set "canal=Multi Channel posible (!slots! modulos)"

:channel_done
>>"!outfile!" echo Canal     : !canal!
>>"!outfile!" echo.

REM ============================================================
REM DISCO
REM ============================================================
>>"!outfile!" echo [DISCO]
set "diskcount=0"
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get Model /format:value 2^>nul ^| findstr "="') do (
    set /a diskcount+=1
    echo Modelo    : %%a>>"!outfile!"
)
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get InterfaceType /format:value 2^>nul ^| findstr "="') do echo Interfaz  : %%a>>"!outfile!"

REM PowerShell fuera de bloques CMD para evitar conflictos de parentesis.
powershell -NoProfile -Command "Get-WmiObject Win32_DiskDrive ^| ForEach-Object { [math]::Round($_.Size/1GB) }" >"!tmpfile!" 2>nul
for /f "usebackq tokens=*" %%a in ("!tmpfile!") do echo Tamanio   : %%a GB>>"!outfile!"

if !diskcount! NEQ 0 goto disk_done
>>"!outfile!" echo Modelo    : No detectado
>>"!outfile!" echo Interfaz  : No detectada
>>"!outfile!" echo Tamanio   : No detectado
:disk_done
>>"!outfile!" echo.

REM ============================================================
REM MOTHERBOARD + SOCKET
REM ============================================================
>>"!outfile!" echo [MOTHERBOARD]
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Manufacturer /format:value 2^>nul ^| findstr "="') do echo Fabricante: %%a>>"!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Product /format:value 2^>nul ^| findstr "="') do echo Modelo    : %%a>>"!outfile!"
set "socket=No detectado"
for /f "tokens=2 delims==" %%a in ('wmic cpu get SocketDesignation /format:value 2^>nul ^| findstr "="') do set "socket=%%a"
>>"!outfile!" echo Socket    : !socket!
>>"!outfile!" echo.

REM ============================================================
REM BIOS
REM ============================================================
>>"!outfile!" echo [BIOS]
for /f "tokens=2 delims==" %%a in ('wmic bios get Manufacturer /format:value 2^>nul ^| findstr "="') do echo Fabricante: %%a>>"!outfile!"
for /f "tokens=2 delims==" %%a in ('wmic bios get SMBIOSBIOSVersion /format:value 2^>nul ^| findstr "="') do echo Version   : %%a>>"!outfile!"
>>"!outfile!" echo.

REM ============================================================
REM VIDEO
REM ============================================================
>>"!outfile!" echo [VIDEO]
for /f "tokens=2 delims==" %%a in ('wmic path win32_VideoController get Name /format:value 2^>nul ^| findstr "="') do echo Modelo    : %%a>>"!outfile!"

powershell -NoProfile -Command "try { [math]::Round((Get-WmiObject Win32_VideoController ^| Select-Object -First 1).AdapterRAM/1MB) } catch { 0 }" >"!tmpfile!" 2>nul
set "vram="
set /p vram=<"!tmpfile!"
if not defined vram goto video_done
if "!vram!"=="0" goto video_done
>>"!outfile!" echo VRAM      : !vram! MB
:video_done
>>"!outfile!" echo.

REM ============================================================
REM FIN
REM ============================================================
del /q "!tmpfile!" >nul 2>&1
cls
type "!outfile!"
echo.
echo ==============================================
echo  Reporte guardado en:
echo  !outfile!
echo ==============================================
echo.
echo Presione cualquier tecla para salir...
pause >nul

endlocal
exit /b
