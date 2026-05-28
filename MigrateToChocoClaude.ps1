# "MigratetoChocoClaude.ps1" v2 dejamos las versiones fuera del nombre porfa ! 
# Migra aplicaciones instaladas a Chocolatey usando base de datos local JSON
# v2   - Reemplaza API online por lookup local, matching regex, sin duplicados
# v2.1 - Fix desinstalacion: parseo correcto de EXE y argumentos del UninstallString
# v2.2 - Fix codigo 19 (MUST_REBOOT_TO_UNINSTALL) aceptado como exito; JSON: 7-Zip.*, Core Temp.*, LocalSend, PowerShell excluido
# v2.3 - Fix codigo 1 (7-Zip uninstaller); PWSH7 tratamiento especial: Choco install + tarea programada para desinstalar MSI viejo al proximo login
#
#Requires -Version 7.0
#Requires -RunAsAdministrator

# ============================================================
# CONFIGURACION
# ============================================================

# Ruta al JSON de mapping - debe estar en la misma carpeta que el script
$script:JsonMappingPath = Join-Path $PSScriptRoot "okchoco_mapping_db.json"

# Apps que nunca se tocan independientemente de lo que diga el JSON
$script:ExcluirSiempre = @(
    "whatsapp",           # paquete unlisted en Choco, no se actualiza bien
    "rustdesk",           # nunca tocar en clientes remotos
    "powershell-core"     # no tocar durante ejecucion
)

# Patrones regex que identifican PowerShell 7 instalado via MSI (no via Choco)
# Se detecta separado para tratamiento especial: instala por Choco + tarea post-login desinstala el MSI
$script:PwshMsiPatterns = @(
    "^PowerShell 7.*$",
    "^PowerShell-.*-win-x64$"
)

# ============================================================
# LOGGING
# ============================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    $logMessage | Out-File -FilePath "$PSScriptRoot\ChocolateyMigration.log" -Append -Encoding utf8
}

# ============================================================
# CARGAR JSON DE MAPPING
# ============================================================

function Get-MappingDB {
    if (-not (Test-Path $script:JsonMappingPath)) {
        Write-Log "ERROR: No se encontro el archivo de mapping en: $script:JsonMappingPath" -Level "ERROR"
        Write-Log "Coloca okchoco_mapping_db.json en la misma carpeta que el script." -Level "ERROR"
        return $null
    }

    try {
        $db = Get-Content -Path $script:JsonMappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log "Base de datos cargada: $($db.Count) entradas"

        # Eliminar duplicados: quedarse con la primera entrada por NombreOriginal
        $seen = @{}
        $dbLimpia = @()
        foreach ($entry in $db) {
            $key = $entry.NombreOriginal.ToLower()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $dbLimpia += $entry
            }
            else {
                Write-Log "Duplicado ignorado en JSON: '$($entry.NombreOriginal)' -> '$($entry.NombreChoco)'" -Level "WARNING"
            }
        }

        Write-Log "Entradas unicas en DB: $($dbLimpia.Count)"
        return $dbLimpia
    }
    catch {
        Write-Log "Error leyendo el JSON de mapping: $_" -Level "ERROR"
        return $null
    }
}

# ============================================================
# BUSCAR APP EN EL JSON
# Devuelve el objeto de mapping o $null si no se encuentra o esta excluida
# ============================================================

function Find-InMappingDB {
    param (
        [string]$DisplayName,
        [array]$MappingDB
    )

    foreach ($entry in $MappingDB) {
        # Saltar entradas excluidas en el JSON
        if ($entry.Excluir -eq $true) { continue }

        # Saltar si NombreChoco esta vacio
        if ([string]::IsNullOrWhiteSpace($entry.NombreChoco)) { continue }

        # Saltar si el ID de choco esta en la lista de exclusion permanente
        if ($script:ExcluirSiempre -contains $entry.NombreChoco.ToLower()) { continue }

        # Matching: usar -match (regex) para aprovechar patrones como "Mozilla Firefox.*"
        try {
            if ($DisplayName -match "(?i)^$($entry.NombreOriginal)$") {
                return $entry
            }
        }
        catch {
            # Si el patron regex es invalido, caer a comparacion exacta
            if ($DisplayName -ieq $entry.NombreOriginal) {
                return $entry
            }
        }
    }

    return $null
}

# ============================================================
# OBTENER APPS INSTALADAS DESDE EL REGISTRO
# ============================================================

function Get-InstalledApps {
    Write-Log "Relevando aplicaciones instaladas en el registro..."

    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    # Filtros de sistema - no tocar estas
    $filtrosSistema = @(
        "*Microsoft Visual C++*",
        "*Windows *",
        "*Update for*",
        "*.NET*",
        "*Driver*",
        "*Redistributable*",
        "*Runtime*",
        "*Security Update*",
        "*Hotfix*"
    )

    $installedApps = @()
    $nombresVistos = @{}

    foreach ($path in $regPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and
                    $_.UninstallString -and
                    -not [string]::IsNullOrWhiteSpace($_.DisplayName)
                } |
                Select-Object DisplayName, DisplayVersion, Publisher, UninstallString

            foreach ($app in $apps) {
                # Saltar duplicados por nombre (pueden aparecer en varios paths del registro)
                $key = $app.DisplayName.ToLower()
                if ($nombresVistos.ContainsKey($key)) { continue }

                # Saltar apps de sistema
                $esSistema = $false
                foreach ($filtro in $filtrosSistema) {
                    if ($app.DisplayName -like $filtro) {
                        $esSistema = $true
                        break
                    }
                }
                if ($esSistema) { continue }

                $nombresVistos[$key] = $true
                $installedApps += $app
            }
        }
        catch {
            Write-Log "Error accediendo a: $path - $_" -Level "ERROR"
        }
    }

    Write-Log "Apps encontradas (sin duplicados de sistema): $($installedApps.Count)"
    return $installedApps
}

# ============================================================
# INSTALAR CHOCOLATEY
# ============================================================

function Install-Chocolatey {
    $chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"

    if (Test-Path $chocoExe) {
        Write-Log "Chocolatey ya esta instalado"
        # Refrescar PATH por si acaso
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        return $true
    }

    Write-Log "Instalando Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        if (Test-Path $chocoExe) {
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Log "Chocolatey instalado correctamente"
            return $true
        }
        else {
            Write-Log "Chocolatey no se pudo instalar" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Excepcion instalando Chocolatey: $_" -Level "ERROR"
        return $false
    }
}

# ============================================================
# DESINSTALAR UNA APP
# ============================================================

function Uninstall-Application {
    param (
        [string]$DisplayName,
        [string]$UninstallString
    )

    Write-Log "Desinstalando: $DisplayName"
    Write-Log "UninstallString: $UninstallString"

    try {
        if ($UninstallString -imatch "msiexec") {
            # --- CASO MSI ---
            $guid = [regex]::Match($UninstallString, '\{[A-F0-9\-]+\}', 'IgnoreCase').Value
            if ($guid) {
                Write-Log "MSI detectado, GUID: $guid"
                $exitCode = (Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru -NoNewWindow).ExitCode
            }
            else {
                Write-Log "No se pudo extraer GUID de: $UninstallString" -Level "WARNING"
                return $false
            }
        }
        else {
            # --- CASO EXE ---
            # Parsear correctamente: separar EXE entre comillas de los argumentos que siguen
            if ($UninstallString -match '^"([^"]+)"\s*(.*)$') {
                # Formato: "C:\ruta\setup.exe" --flag1 --flag2
                $exe  = $matches[1]
                $args = $matches[2].Trim()
            }
            elseif ($UninstallString -match '^(\S+)\s*(.*)$') {
                # Formato sin comillas: C:\ruta\setup.exe --flag1
                $exe  = $matches[1]
                $args = $matches[2].Trim()
            }
            else {
                $exe  = $UninstallString
                $args = ""
            }

            Write-Log "EXE: $exe"
            Write-Log "Args: $args"

            # Si el UninstallString ya trae sus propios argumentos los usamos tal cual
            # Si no trae ninguno, agregamos los silenciosos genéricos
            if ([string]::IsNullOrWhiteSpace($args)) {
                $args = "/S /silent /quiet /uninstall"
                Write-Log "Sin argumentos propios, usando silenciosos genericos"
            }

            if (-not (Test-Path $exe)) {
                Write-Log "EXE no encontrado en disco: $exe" -Level "ERROR"
                return $false
            }

            $exitCode = (Start-Process $exe -ArgumentList $args -Wait -PassThru -NoNewWindow).ExitCode
        }

        # Codigos de exito: 0=OK, 1=OK (7-Zip/InnoSetup), 3010=OK con reinicio pendiente, 1605=ya no estaba instalado, 19=requiere reinicio para completar desinstalacion
        if ($exitCode -in @(0, 1, 3010, 1605, 19)) {
            Write-Log "Desinstalacion exitosa: $DisplayName (codigo: $exitCode)"
            return $true
        }
        else {
            Write-Log "Desinstalacion con codigo inesperado: $DisplayName (codigo: $exitCode)" -Level "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Excepcion desinstalando '$DisplayName': $_" -Level "ERROR"
        return $false
    }
}

# ============================================================
# INSTALAR PAQUETE DESDE CHOCOLATEY
# ============================================================

function Install-ChocoPackage {
    param (
        [string]$PackageId,
        [int]$MaxRetries = 3
    )

    Write-Log "Instalando desde Choco: $PackageId"

    for ($intento = 1; $intento -le $MaxRetries; $intento++) {
        try {
            switch ($intento) {
                1 { & choco install $PackageId -y --no-progress 2>&1 | Out-Null }
                2 { & choco install $PackageId -y --no-progress --ignore-checksums 2>&1 | Out-Null }
                3 { & choco install $PackageId -y --no-progress --force 2>&1 | Out-Null }
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Instalado OK: $PackageId"
                return $true
            }
            else {
                Write-Log "Intento $intento fallido para '$PackageId' (exit: $LASTEXITCODE)" -Level "WARNING"
                if ($intento -lt $MaxRetries) { Start-Sleep -Seconds 3 }
            }
        }
        catch {
            Write-Log "Excepcion intento $intento para '$PackageId': $_" -Level "ERROR"
            if ($intento -lt $MaxRetries) { Start-Sleep -Seconds 3 }
        }
    }

    Write-Log "FALLO tras $MaxRetries intentos: $PackageId" -Level "ERROR"
    return $false
}

# ============================================================
# MIGRACION ESPECIAL POWERSHELL 7 MSI -> CHOCOLATEY
# Instala powershell-core via Choco y registra tarea programada
# para que al proximo login se desinstale el MSI viejo y la tarea se autoelimine
# ============================================================

function Register-DesinstalarPwshMsi {
    $nombreTarea = "TuPcVeloz-DesinstalarPwshMsi"

    $scriptBloque = @'
$rutas = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($ruta in $rutas) {
    Get-ItemProperty $ruta -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "^PowerShell 7" } |
    ForEach-Object {
        $us = if ($_.QuietUninstallString) { $_.QuietUninstallString } else { $_.UninstallString }
        if ($us) {
            if ($us -match '^"([^"]+)"(.*)$') { $exe = $Matches[1]; $arg = $Matches[2].Trim() }
            else { $exe = $us; $arg = "" }
            Start-Process -FilePath $exe -ArgumentList "$arg /quiet /norestart" -Wait -ErrorAction SilentlyContinue
        }
    }
}
Unregister-ScheduledTask -TaskName "TuPcVeloz-DesinstalarPwshMsi" -Confirm:$false -ErrorAction SilentlyContinue
'@

    $encoded  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBloque))
    $accion   = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NonInteractive -EncodedCommand $encoded"
    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 1)

    try {
        Register-ScheduledTask -TaskName $nombreTarea -Action $accion -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Write-Log "Tarea programada '$nombreTarea' registrada: desinstalara MSI de PWSH7 al proximo login"
        return $true
    }
    catch {
        Write-Log "No se pudo registrar tarea para desinstalar MSI de PWSH7: $_" -Level "WARNING"
        return $false
    }
}

# ============================================================
# FUNCION PRINCIPAL
# ============================================================

function Start-ChocolateyMigration {
    $startTime = Get-Date
    Write-Log "========================================================"
    Write-Log "=== MIGRACION A CHOCOLATEY v2 - $(Get-Date -Format 'dd/MM/yyyy HH:mm') ==="
    Write-Log "========================================================"

    # 1. Cargar base de datos JSON
    $mappingDB = Get-MappingDB
    if ($null -eq $mappingDB) {
        Write-Log "No se puede continuar sin la base de datos de mapping." -Level "ERROR"
        return
    }

    # 2. Obtener apps instaladas
    $installedApps = Get-InstalledApps
    if ($installedApps.Count -eq 0) {
        Write-Log "No se encontraron aplicaciones instaladas. Abortando." -Level "WARNING"
        return
    }

    # 3. Cruzar apps instaladas contra el JSON
    Write-Log "--- Analizando apps contra base de datos ---"
    $candidatos    = @()
    $noEncontradas = @()
    $pwshMsiInfo   = $null   # PWSH7 MSI detectado para tratamiento especial

    foreach ($app in $installedApps) {

        # Detectar PWSH7 instalado via MSI antes del lookup normal
        $esPwshMsi = $false
        foreach ($patron in $script:PwshMsiPatterns) {
            if ($app.DisplayName -match $patron) { $esPwshMsi = $true; break }
        }
        if ($esPwshMsi) {
            Write-Log "PWSH7-MSI detectado: '$($app.DisplayName)' -> tratamiento especial (instala Choco + tarea post-login)"
            $pwshMsiInfo = $app
            continue
        }

        $match = Find-InMappingDB -DisplayName $app.DisplayName -MappingDB $mappingDB

        if ($match) {
            Write-Log "CANDIDATO: '$($app.DisplayName)' -> choco: '$($match.NombreChoco)'"
            $candidatos += [PSCustomObject]@{
                DisplayName    = $app.DisplayName
                Version        = $app.DisplayVersion
                ChocolateyId   = $match.NombreChoco
                UninstallString = $app.UninstallString
                EsBloatware    = $match.EsBloatware
            }
        }
        else {
            $noEncontradas += $app.DisplayName
        }
    }

    Write-Log "Apps para migrar: $($candidatos.Count)"
    Write-Log "Apps sin mapping (se dejan como estan): $($noEncontradas.Count)"
    if ($pwshMsiInfo) {
        Write-Log "PowerShell 7 MSI: detectado, se migrara al final via Choco + tarea post-login"
    }

    if ($candidatos.Count -eq 0) {
        Write-Log "Ninguna app instalada tiene mapping en la DB. Nada que migrar." -Level "WARNING"
        return
    }

    # Mostrar resumen antes de proceder
    Write-Log "--- Apps que seran migradas ---"
    foreach ($c in $candidatos) {
        $bloat = if ($c.EsBloatware) { " [BLOATWARE]" } else { "" }
        Write-Log "  $($c.DisplayName) -> $($c.ChocolateyId)$bloat"
    }

    # 4. Desinstalar apps originales
    Write-Log "========================================================"
    Write-Log "=== PASO 1: DESINSTALANDO APPS ORIGINALES ==="
    Write-Log "========================================================"
    $desinstalacionesOK = 0

    foreach ($c in $candidatos) {
        if (Uninstall-Application -DisplayName $c.DisplayName -UninstallString $c.UninstallString) {
            $desinstalacionesOK++
        }
    }

    Write-Log "Desinstaladas: $desinstalacionesOK / $($candidatos.Count)"

    # 5. Instalar Chocolatey
    Write-Log "========================================================"
    Write-Log "=== PASO 2: INSTALANDO CHOCOLATEY ==="
    Write-Log "========================================================"
    if (-not (Install-Chocolatey)) {
        Write-Log "CRITICO: No se pudo instalar Chocolatey. Las apps fueron desinstaladas pero no se reinstalaran." -Level "ERROR"
        Write-Log "Instala Chocolatey manualmente y ejecuta el paso 3 por separado." -Level "ERROR"
        return
    }

    # 6. Reinstalar todo desde Chocolatey
    Write-Log "========================================================"
    Write-Log "=== PASO 3: REINSTALANDO DESDE CHOCOLATEY ==="
    Write-Log "========================================================"
    $instalacionesOK = 0
    $fallos = @()

    foreach ($c in $candidatos) {
        if (Install-ChocoPackage -PackageId $c.ChocolateyId) {
            $instalacionesOK++
        }
        else {
            $fallos += "$($c.DisplayName) -> $($c.ChocolateyId)"
        }
    }

    # 6b. PWSH7 tratamiento especial: instalar via Choco, desinstalar MSI viejo al proximo login
    $pwshChocoOK = $false
    if ($pwshMsiInfo) {
        Write-Log "========================================================"
        Write-Log "=== PASO 3b: MIGRANDO POWERSHELL 7 (tratamiento especial) ==="
        Write-Log "========================================================"
        Write-Log "Instalando powershell-core via Choco (MSI viejo sigue activo hasta el proximo login)..."
        $pwshChocoOK = Install-ChocoPackage -PackageId "powershell-core"
        if ($pwshChocoOK) {
            $instalacionesOK++
            Register-DesinstalarPwshMsi | Out-Null
        }
        else {
            $fallos += "$($pwshMsiInfo.DisplayName) -> powershell-core"
            Write-Log "No se pudo instalar powershell-core via Choco. MSI original sin cambios." -Level "WARNING"
        }
    }

    # 7. Generar XML para referencia futura
    $configDir = Join-Path $PSScriptRoot "Config"
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    $xmlPath = Join-Path $configDir "AppsInstaladas-Choco.config"

    # Armar lista de paquetes exitosos (candidatos normales + pwsh-core si OK)
    $exitosos = $candidatos | Where-Object { $fallos -notcontains "$($_.DisplayName) -> $($_.ChocolateyId)" }
    $xmlContent = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<packages>`r`n"
    foreach ($c in $exitosos) {
        $xmlContent += "  <package id=`"$($c.ChocolateyId)`" />`r`n"
    }
    if ($pwshChocoOK) {
        $xmlContent += "  <package id=`"powershell-core`" />`r`n"
    }
    $xmlContent += "</packages>"
    $xmlContent | Out-File -FilePath $xmlPath -Encoding utf8
    Write-Log "XML de referencia guardado en: $xmlPath"

    # 8. Resumen final
    $totalEsperado = $candidatos.Count + $(if ($pwshMsiInfo) { 1 } else { 0 })
    $duracion = (Get-Date) - $startTime
    Write-Log "========================================================"
    Write-Log "=== RESUMEN FINAL ==="
    Write-Log "========================================================"
    Write-Log "Apps analizadas del registro:      $($installedApps.Count)"
    Write-Log "Apps con mapping en DB:            $($candidatos.Count)"
    Write-Log "Apps sin mapping (sin cambios):    $($noEncontradas.Count)"
    Write-Log "Desinstalaciones exitosas:         $desinstalacionesOK / $($candidatos.Count)"
    Write-Log "Instalaciones Choco exitosas:      $instalacionesOK / $totalEsperado"
    if ($pwshMsiInfo) {
        if ($pwshChocoOK) {
            Write-Log "PowerShell 7:                      OK - Choco instalado, MSI viejo se limpia al proximo login"
        }
        else {
            Write-Log "PowerShell 7:                      FALLO migracion a Choco - MSI original sin cambios" -Level "WARNING"
        }
    }
    Write-Log "Tiempo total:                      $($duracion.ToString('hh\:mm\:ss'))"

    if ($fallos.Count -gt 0) {
        Write-Log "--- Apps que FALLARON la instalacion ---" -Level "WARNING"
        foreach ($f in $fallos) {
            Write-Log "  FALLO: $f" -Level "WARNING"
        }
        Write-Log "Estas apps deben instalarse manualmente." -Level "WARNING"
    }
    else {
        Write-Log "EXITO TOTAL: Todas las apps migradas correctamente a Chocolatey."
    }
    Write-Log "========================================================"
}

# ============================================================
# ARRANQUE
# ============================================================
Start-ChocolateyMigration