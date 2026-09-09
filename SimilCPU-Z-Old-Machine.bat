@echo off
REM ============================================================
REM nombre archivo "SimilCPU-Z-Old-Machine.bat"
REM Version 5 - 08/09/2026 -12.30hs - Grok
REM DDR2 / DDR3 / DDR4 / DDR5 + Fabricante + Part Number
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
for /f "tokens=2 delims==" %%a in ('wmic cpu get Name /format:value 2^>nul ^| findstr "="') do (
    set "cpuName=%%a"
    for /f "tokens=* delims= " %%x in ("!cpuName!") do set "cpuName=%%x"
    >>"!outfile!" echo Modelo    : !cpuName!
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfCores /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Nucleos   : %%x
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfLogicalProcessors /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Logicos   : %%x
)
for /f "tokens=2 delims==" %%a in ('wmic cpu get MaxClockSpeed /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Velocidad : %%x MHz
)
>>"!outfile!" echo.

REM ============================================================
REM MEMORIA RAM
REM ============================================================
>>"!outfile!" echo [MEMORIA RAM]
set "tipoRAM=Desconocido"

REM --- Detectar tipo ---
REM 1) SMBIOSMemoryType via PowerShell
powershell -NoProfile -Command "try{$r=Get-CimInstance Win32_PhysicalMemory -EA Stop|Select -Expand SMBIOSMemoryType -First 1; if($r){$r}else{''}}catch{try{$r=Get-WmiObject Win32_PhysicalMemory|Select -Expand SMBIOSMemoryType -First 1; if($r){$r}else{''}}catch{''}}" >"!tmpfile!" 2>nul
set /p rawType=<"!tmpfile!"
if defined rawType (
    for /f "tokens=* delims= " %%x in ("!rawType!") do set "rawType=%%x"
    if "!rawType!"=="19" set "tipoRAM=DDR2"
    if "!rawType!"=="20" set "tipoRAM=DDR2 FB-DIMM"
    if "!rawType!"=="24" set "tipoRAM=DDR3"
    if "!rawType!"=="26" set "tipoRAM=DDR4"
    if "!rawType!"=="34" set "tipoRAM=DDR5"
)

REM 2) Fallback WMIC SMBIOSMemoryType
if "!tipoRAM!"=="Desconocido" (
    for /f "tokens=2 delims==" %%a in ('wmic memorychip get SMBIOSMemoryType /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
        set "v=%%a"
        for /f "tokens=* delims= " %%x in ("!v!") do (
            if "%%x"=="19" set "tipoRAM=DDR2"
            if "%%x"=="20" set "tipoRAM=DDR2 FB-DIMM"
            if "%%x"=="24" set "tipoRAM=DDR3"
            if "%%x"=="26" set "tipoRAM=DDR4"
            if "%%x"=="34" set "tipoRAM=DDR5"
        )
    )
)

REM 3) Fallback MemoryType (CIM)
if "!tipoRAM!"=="Desconocido" (
    for /f "tokens=2 delims==" %%a in ('wmic memorychip get MemoryType /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
        set "v=%%a"
        for /f "tokens=* delims= " %%x in ("!v!") do (
            if "%%x"=="20" set "tipoRAM=DDR"
            if "%%x"=="21" set "tipoRAM=DDR2"
            if "%%x"=="22" set "tipoRAM=DDR2 FB-DIMM"
            if "%%x"=="24" set "tipoRAM=DDR3"
            if "%%x"=="25" set "tipoRAM=FBD2"
            if "%%x"=="26" set "tipoRAM=DDR4"
        )
    )
)

REM 4) Ultimo recurso PowerShell MemoryType
if "!tipoRAM!"=="Desconocido" (
    powershell -NoProfile -Command "try{$r=Get-CimInstance Win32_PhysicalMemory -EA Stop|Select -Expand MemoryType -First 1; if($r){$r}else{''}}catch{try{$r=Get-WmiObject Win32_PhysicalMemory|Select -Expand MemoryType -First 1; if($r){$r}else{''}}catch{''}}" >"!tmpfile!" 2>nul
    set /p rawType=<"!tmpfile!"
    if defined rawType (
        for /f "tokens=* delims= " %%x in ("!rawType!") do set "rawType=%%x"
        if "!rawType!"=="20" set "tipoRAM=DDR"
        if "!rawType!"=="21" set "tipoRAM=DDR2"
        if "!rawType!"=="22" set "tipoRAM=DDR2 FB-DIMM"
        if "!rawType!"=="24" set "tipoRAM=DDR3"
        if "!rawType!"=="25" set "tipoRAM=FBD2"
        if "!rawType!"=="26" set "tipoRAM=DDR4"
    )
)

>>"!outfile!" echo Tipo      : !tipoRAM!

REM Velocidad
set "ramSpeed="
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Speed /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
    if not defined ramSpeed (
        set "v=%%a"
        for /f "tokens=* delims= " %%x in ("!v!") do set "ramSpeed=%%x"
    )
)
if defined ramSpeed (
    >>"!outfile!" echo Velocidad : !ramSpeed! MHz
) else (
    >>"!outfile!" echo Velocidad : No detectada
)

REM Total RAM
powershell -NoProfile -Command "try{[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)}catch{[math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB)}" >"!tmpfile!" 2>nul
set "ramGB="
set /p ramGB=<"!tmpfile!"
if defined ramGB (
    for /f "tokens=* delims= " %%x in ("!ramGB!") do >>"!outfile!" echo Total     : %%x GB
) else (
    >>"!outfile!" echo Total     : No detectado
)

REM Contar slots en uso
set "slots=0"
for /f "tokens=2 delims==" %%a in ('wmic memorychip get Capacity /format:value 2^>nul ^| findstr /R "=[0-9]"') do set /a slots+=1
>>"!outfile!" echo Slots en uso: !slots!

REM Canal
set "canal=No detectado"
if !slots! EQU 1 set "canal=Single Channel (1 modulo)"
if !slots! EQU 2 (
    set "tam1=" & set "tam2=" & set "count=0"
    for /f "tokens=2 delims==" %%a in ('wmic memorychip get Capacity /format:value 2^>nul ^| findstr /R "=[0-9]"') do (
        set /a count+=1
        set "v=%%a"
        for /f "tokens=* delims= " %%x in ("!v!") do (
            if !count! EQU 1 set "tam1=%%x"
            if !count! EQU 2 set "tam2=%%x"
        )
    )
    if "!tam1!"=="!tam2!" (set "canal=Dual Channel probable (2 modulos iguales)") else (set "canal=Single/Flex Channel posible (2 modulos distintos)")
)
if !slots! GTR 2 set "canal=Multi Channel posible (!slots! modulos)"
>>"!outfile!" echo Canal     : !canal!
>>"!outfile!" echo.

REM ============================================================
REM DETALLE DE MODULOS (PowerShell - mas confiable)
REM ============================================================
>>"!outfile!" echo --- Detalle de modulos ---

powershell -NoProfile -Command "try{$m=Get-CimInstance Win32_PhysicalMemory -EA Stop}catch{$m=Get-WmiObject Win32_PhysicalMemory}; $i=0; foreach($x in $m){$i++; $manu=($x.Manufacturer -replace '^\s+|\s+$',''); $part=($x.PartNumber -replace '^\s+|\s+$',''); if(-not $manu){$manu='?'}; if(-not $part){$part='?'}; Write-Output ('Modulo ' + $i + '  : ' + $manu + '  ' + $part)}" >"!tmpfile!" 2>nul

set "modulosOK=0"
for /f "usebackq delims=" %%L in ("!tmpfile!") do (
    if not "%%L"=="" (
        set /a modulosOK+=1
        >>"!outfile!" echo %%L
    )
)

if !modulosOK! EQU 0 (
    >>"!outfile!" echo No se pudo obtener detalle de modulos
)
>>"!outfile!" echo.

REM ============================================================
REM DISCO
REM ============================================================
>>"!outfile!" echo [DISCO]
set "diskcount=0"
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get Model /format:value 2^>nul ^| findstr "="') do (
    set /a diskcount+=1
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Modelo    : %%x
)
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get InterfaceType /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Interfaz  : %%x
)

powershell -NoProfile -Command "try{Get-CimInstance Win32_DiskDrive|%%{[math]::Round($_.Size/1GB)}}catch{Get-WmiObject Win32_DiskDrive|%%{[math]::Round($_.Size/1GB)}}" >"!tmpfile!" 2>nul
for /f "usebackq tokens=*" %%a in ("!tmpfile!") do (
    if not "%%a"=="" (
        for /f "tokens=* delims= " %%x in ("%%a") do >>"!outfile!" echo Tamanio   : %%x GB
    )
)

if !diskcount! EQU 0 (
    >>"!outfile!" echo Modelo    : No detectado
    >>"!outfile!" echo Interfaz  : No detectada
    >>"!outfile!" echo Tamanio   : No detectado
)
>>"!outfile!" echo.

REM ============================================================
REM MOTHERBOARD + SOCKET
REM ============================================================
>>"!outfile!" echo [MOTHERBOARD]
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Manufacturer /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Fabricante: %%x
)
for /f "tokens=2 delims==" %%a in ('wmic baseboard get Product /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Modelo    : %%x
)
set "socket=No detectado"
for /f "tokens=2 delims==" %%a in ('wmic cpu get SocketDesignation /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do set "socket=%%x"
)
>>"!outfile!" echo Socket    : !socket!
>>"!outfile!" echo.

REM ============================================================
REM BIOS
REM ============================================================
>>"!outfile!" echo [BIOS]
for /f "tokens=2 delims==" %%a in ('wmic bios get Manufacturer /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Fabricante: %%x
)
for /f "tokens=2 delims==" %%a in ('wmic bios get SMBIOSBIOSVersion /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Version   : %%x
)
>>"!outfile!" echo.

REM ============================================================
REM VIDEO
REM ============================================================
>>"!outfile!" echo [VIDEO]
for /f "tokens=2 delims==" %%a in ('wmic path win32_VideoController get Name /format:value 2^>nul ^| findstr "="') do (
    set "v=%%a"
    for /f "tokens=* delims= " %%x in ("!v!") do >>"!outfile!" echo Modelo    : %%x
)

powershell -NoProfile -Command "try{[math]::Round((Get-CimInstance Win32_VideoController|Select -First 1).AdapterRAM/1MB)}catch{try{[math]::Round((Get-WmiObject Win32_VideoController|Select -First 1).AdapterRAM/1MB)}catch{0}}" >"!tmpfile!" 2>nul
set "vram="
set /p vram=<"!tmpfile!"
if defined vram (
    for /f "tokens=* delims= " %%x in ("!vram!") do set "vram=%%x"
    if not "!vram!"=="0" if not "!vram!"=="" (
        >>"!outfile!" echo VRAM      : !vram! MB
    )
)
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