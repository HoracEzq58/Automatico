# "MigrateToChocoClaude.ps1" nombre del archivo 
# Migra aplicaciones instaladas a Chocolatey usando base de datos local JSON
# v2   - Reemplaza API online por lookup local, matching regex, sin duplicados
# v2.1 - Fix desinstalacion: parseo correcto de EXE y argumentos del UninstallString
# v3   - Verificacion previa en Choco antes de desinstalar, DryRun, confirmacion,
#        upgrade si ya esta en Choco, lista de sin-mapping al final
# v3.1 - Navegadores al final de desinstalacion, Chrome el ultimo de todos
# v3.2 - Chocolatey se instala PRIMERO antes de cualquier verificacion
# v3.3 - ExcluirMigracion + MotivoExclusion en JSON: apps con plugins/librerias/config en AppData quedan intactas; PATH refresh antes de choco search; codigo 1 aceptado en 7-Zip
#
#Requires -Version 7.0
#Requires -RunAsAdministrator

param(
    [switch]$DryRun  # Simula todo sin tocar nada. Uso: .\okMigratetoChoco.ps1 -DryRun
)

# ============================================================
# CONFIGURACION
# ============================================================
$script:JsonMappingPath = Join-Path $PSScriptRoot "okchoco_mapping_db.json"

$script:ExcluirSiempre = @(
    "whatsapp",
    "rustdesk",
    "powershell-core"
)

# Red de seguridad hardcoded: apps con plugins/librerias/config en AppData
# Actua aunque el campo ExcluirMigracion no este en el JSON
$script:ExcluirPorSeguridad = @{
    "vscode"          = "Extensions y settings.json - el usuario las gestiona manualmente"
    "vscode.install"  = "Extensions y settings.json - el usuario las gestiona manualmente"
    "audacity"        = "Plugins Nyquist/LADSPA y macros - el usuario las gestiona manualmente"
    "reaper"          = "Plugins VST y proyectos - el usuario los gestiona manualmente"
    "obs-studio"      = "Escenas y plugins - el usuario los gestiona manualmente"
    "gimp"            = "Scripts, brushes y plugins - el usuario los gestiona manualmente"
    "inkscape"        = "Extensions y paletas custom - el usuario las gestiona manualmente"
    "python"          = "Entornos virtuales y paquetes pip - el usuario los gestiona manualmente"
    "nodejs"          = "Paquetes globales npm - el usuario los gestiona manualmente"
    "nodejs.install"  = "Paquetes globales npm - el usuario los gestiona manualmente"
    "virtualbox"      = "Config de red bridging - el usuario la gestiona manualmente"
    "krita"           = "Brushes y recursos custom - el usuario los gestiona manualmente"
    "blender"         = "Add-ons y configuracion - el usuario los gestiona manualmente"
}

# ============================================================
# LOGGING
# ============================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARNING","ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($DryRun) { "[DRYRUN] " } else { "" }
    $logMessage = "[$timestamp] [$Level] $prefix$Message"
    $color = switch ($Level) {
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
    $logMessage | Out-File -FilePath "$PSScriptRoot\ChocolateyMigration.log" -Append -Encoding utf8
}

# ============================================================
# CARGAR JSON
# ============================================================
function Get-MappingDB {
    if (-not (Test-Path $script:JsonMappingPath)) {
        Write-Log "No se encontro: $script:JsonMappingPath" -Level "ERROR"
        return $null
    }
    try {
        $db = Get-Content -Path $script:JsonMappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log "Base de datos cargada: $($db.Count) entradas"

        $seen = @{}
        $dbLimpia = @()
        foreach ($entry in $db) {
            $key = $entry.NombreOriginal.ToLower()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $dbLimpia += $entry
            } else {
                Write-Log "Duplicado ignorado: '$($entry.NombreOriginal)' -> '$($entry.NombreChoco)'" -Level "WARNING"
            }
        }
        Write-Log "Entradas unicas: $($dbLimpia.Count)"
        return $dbLimpia
    } catch {
        Write-Log "Error leyendo JSON: $_" -Level "ERROR"
        return $null
    }
}

# ============================================================
# BUSCAR EN JSON
# ============================================================
function Find-InMappingDB {
    param([string]$DisplayName, [array]$MappingDB)

    foreach ($entry in $MappingDB) {
        if ($entry.Excluir -eq $true) { continue }
        if ([string]::IsNullOrWhiteSpace($entry.NombreChoco)) { continue }
        if ($script:ExcluirSiempre -contains $entry.NombreChoco.ToLower()) { continue }
        # Excluir apps con plugins/librerias/config en AppData (campo JSON v3.3)
        if ($entry.PSObject.Properties["ExcluirMigracion"] -and $entry.ExcluirMigracion -eq $true) { continue }
        # Red de seguridad hardcoded por si falta el campo en el JSON
        if ($script:ExcluirPorSeguridad.ContainsKey($entry.NombreChoco.ToLower())) { continue }
        try {
            if ($DisplayName -match "(?i)^$($entry.NombreOriginal)$") { return $entry }
        } catch {
            if ($DisplayName -ieq $entry.NombreOriginal) { return $entry }
        }
    }
    return $null
}

# ============================================================
# VERIFICAR QUE EL PAQUETE EXISTE EN CHOCO (ONLINE)
# ============================================================
function Test-ChocoPackageExists {
    param([string]$PackageId)

    try {
        # Asegurar que choco este en el PATH de esta sesion PS7
        $chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
        if (-not (Get-Command choco -ErrorAction SilentlyContinue) -and (Test-Path $chocoExe)) {
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
        }
        $resultado = & choco search $PackageId --exact --limit-output 2>&1
        if ($LASTEXITCODE -eq 0 -and $resultado -match "^$PackageId\|") {
            return $true
        }
        return $false
    } catch {
        Write-Log "Error verificando '$PackageId' en Choco: $_" -Level "WARNING"
        return $false
    }
}

# ============================================================
# VERIFICAR SI YA ESTA INSTALADO POR CHOCO
# ============================================================
function Test-ChocoAlreadyInstalled {
    param([string]$PackageId)

    try {
        $resultado = & choco list $PackageId --exact --limit-output 2>&1
        return ($LASTEXITCODE -eq 0 -and $resultado -match "^$PackageId\|")
    } catch {
        return $false
    }
}

# ============================================================
# APPS INSTALADAS DEL REGISTRO
# ============================================================
function Get-InstalledApps {
    Write-Log "Relevando aplicaciones instaladas en el registro..."

    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $filtrosSistema = @(
        "*Microsoft Visual C++*","*Windows *","*Update for*","*.NET*",
        "*Driver*","*Redistributable*","*Runtime*","*Security Update*","*Hotfix*"
    )

    $installedApps = @()
    $nombresVistos = @{}

    foreach ($path in $regPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.UninstallString -and -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
                Select-Object DisplayName, DisplayVersion, UninstallString

            foreach ($app in $apps) {
                $key = $app.DisplayName.ToLower()
                if ($nombresVistos.ContainsKey($key)) { continue }
                $esSistema = $false
                foreach ($filtro in $filtrosSistema) {
                    if ($app.DisplayName -like $filtro) { $esSistema = $true; break }
                }
                if ($esSistema) { continue }
                $nombresVistos[$key] = $true
                $installedApps += $app
            }
        } catch {
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
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        return $true
    }
    if ($DryRun) { Write-Log "[DRYRUN] Se instalaria Chocolatey aqui"; return $true }
    try {
        Write-Log "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        if (Test-Path $chocoExe) {
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Log "Chocolatey instalado correctamente"
            return $true
        }
        Write-Log "No se pudo instalar Chocolatey" -Level "ERROR"
        return $false
    } catch {
        Write-Log "Excepcion instalando Chocolatey: $_" -Level "ERROR"
        return $false
    }
}

# ============================================================
# DESINSTALAR APP
# ============================================================
function Uninstall-Application {
    param([string]$DisplayName, [string]$UninstallString)

    Write-Log "Desinstalando: $DisplayName"
    Write-Log "UninstallString: $UninstallString"

    if ($DryRun) { Write-Log "[DRYRUN] Se desinstalaria: $DisplayName"; return $true }

    try {
        if ($UninstallString -imatch "msiexec") {
            $guid = [regex]::Match($UninstallString, '\{[A-F0-9\-]+\}', 'IgnoreCase').Value
            if ($guid) {
                Write-Log "MSI GUID: $guid"
                $exitCode = (Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru -NoNewWindow).ExitCode
            } else {
                Write-Log "No se pudo extraer GUID de: $UninstallString" -Level "WARNING"
                return $false
            }
        } else {
            if ($UninstallString -match '^"([^"]+)"\s*(.*)$') {
                $exe  = $matches[1]
                $args = $matches[2].Trim()
            } elseif ($UninstallString -match '^(\S+)\s*(.*)$') {
                $exe  = $matches[1]
                $args = $matches[2].Trim()
            } else {
                $exe  = $UninstallString
                $args = ""
            }

            Write-Log "EXE: $exe"
            Write-Log "Args: $args"

            if (-not (Test-Path $exe)) {
                Write-Log "EXE no encontrado: $exe" -Level "ERROR"
                return $false
            }

            if ([string]::IsNullOrWhiteSpace($args)) {
                $args = "/S"
                Write-Log "Sin argumentos propios, usando /S"
            }

            $exitCode = (Start-Process $exe -ArgumentList $args -Wait -PassThru -NoNewWindow).ExitCode
        }

        # 0=OK, 3010=OK reinicio pendiente, 1605=ya no estaba, 19=Chrome/Edge reboot
        if ($exitCode -in @(0, 1, 3010, 1605, 19)) {  # 1=7-Zip exito, 19=Chrome/Edge reboot
            Write-Log "Desinstalacion exitosa: $DisplayName (codigo: $exitCode)"
            return $true
        } else {
            Write-Log "Codigo inesperado: $DisplayName (codigo: $exitCode)" -Level "WARNING"
            return $false
        }
    } catch {
        Write-Log "Excepcion desinstalando '$DisplayName': $_" -Level "ERROR"
        return $false
    }
}

# ============================================================
# INSTALAR O ACTUALIZAR DESDE CHOCO
# ============================================================
function Install-ChocoPackage {
    param([string]$PackageId, [bool]$YaInstalado = $false, [int]$MaxRetries = 3)

    $accion = if ($YaInstalado) { "upgrade" } else { "install" }
    Write-Log "Choco $accion`: $PackageId"

    if ($DryRun) { Write-Log "[DRYRUN] Se ejecutaria: choco $accion $PackageId -y"; return $true }

    for ($intento = 1; $intento -le $MaxRetries; $intento++) {
        try {
            switch ($intento) {
                1 { & choco $accion $PackageId -y --no-progress 2>&1 | Out-Null }
                2 { & choco $accion $PackageId -y --no-progress --ignore-checksums 2>&1 | Out-Null }
                3 { & choco $accion $PackageId -y --no-progress --force 2>&1 | Out-Null }
            }
            if ($LASTEXITCODE -eq 0) {
                Write-Log "OK: $PackageId"
                return $true
            } else {
                Write-Log "Intento $intento fallido para '$PackageId' (exit: $LASTEXITCODE)" -Level "WARNING"
                if ($intento -lt $MaxRetries) { Start-Sleep -Seconds 3 }
            }
        } catch {
            Write-Log "Excepcion intento $intento '$PackageId': $_" -Level "ERROR"
            if ($intento -lt $MaxRetries) { Start-Sleep -Seconds 3 }
        }
    }
    Write-Log "FALLO tras $MaxRetries intentos: $PackageId" -Level "ERROR"
    return $false
}

# ============================================================
# FUNCION PRINCIPAL
# ============================================================
function Start-ChocolateyMigration {
    $startTime = Get-Date

    if ($DryRun) {
        Write-Log "========================================================"
        Write-Log "=== MODO SIMULACION (DryRun) - NO SE TOCA NADA ==="
        Write-Log "========================================================"
    }

    Write-Log "========================================================"
    Write-Log "=== MIGRACION A CHOCOLATEY v3 - $(Get-Date -Format 'dd/MM/yyyy HH:mm') ==="
    Write-Log "========================================================"

    # 1. INSTALAR CHOCOLATEY PRIMERO - siempre, el cliente casi nunca lo tiene
    Write-Log "========================================================"
    Write-Log "=== PASO PREVIO: INSTALANDO/VERIFICANDO CHOCOLATEY ==="
    Write-Log "========================================================"
    if (-not (Install-Chocolatey)) {
        Write-Log "CRITICO: No se pudo instalar Chocolatey. Abortando." -Level "ERROR"
        return
    }

    # 2. Cargar JSON
    $mappingDB = Get-MappingDB
    if ($null -eq $mappingDB) { return }

    # 3. Obtener apps instaladas
    $installedApps = Get-InstalledApps
    if ($installedApps.Count -eq 0) {
        Write-Log "No se encontraron apps instaladas." -Level "WARNING"
        return
    }

    # 4. Cruzar con JSON
    Write-Log "--- Analizando apps contra base de datos ---"
    $candidatos         = @()
    $noEncontradas      = @()
    $excluidasRiesgo    = @()  # Apps con ExcluirMigracion=true o en lista hardcoded

    foreach ($app in $installedApps) {
        # Chequear exclusion por seguridad ANTES del match
        $entradaDB = $mappingDB | Where-Object {
            try { $app.DisplayName -match "(?i)^$($_.NombreOriginal)$" } catch { $false }
        } | Select-Object -First 1

        if ($entradaDB) {
            $chocoIdCheck = ($entradaDB.NombreChoco ?? "").ToLower()
            $motivoJSON   = if ($entradaDB.PSObject.Properties["ExcluirMigracion"] -and $entradaDB.ExcluirMigracion) { $entradaDB.MotivoExclusion } else { $null }
            $motivoLista  = if ($script:ExcluirPorSeguridad.ContainsKey($chocoIdCheck)) { $script:ExcluirPorSeguridad[$chocoIdCheck] } else { $null }
            $motivo       = $motivoJSON ?? $motivoLista
            if ($motivo) {
                Write-Log "EXCLUIDA (riesgo): '$($app.DisplayName)' - $motivo" -Level "WARNING"
                $excluidasRiesgo += "$($app.DisplayName): $motivo"
                continue
            }
        }

        $match = Find-InMappingDB -DisplayName $app.DisplayName -MappingDB $mappingDB
        if ($match) {
            Write-Log "CANDIDATO: '$($app.DisplayName)' -> choco: '$($match.NombreChoco)'"
            $candidatos += [PSCustomObject]@{
                DisplayName     = $app.DisplayName
                Version         = $app.DisplayVersion
                ChocolateyId    = $match.NombreChoco
                UninstallString = $app.UninstallString
                EsBloatware     = $match.EsBloatware
                Categoria       = $match.Categoria
            }
        } else {
            $noEncontradas += $app.DisplayName
        }
    }

    Write-Log "Candidatos con mapping: $($candidatos.Count)"
    Write-Log "Sin mapping: $($noEncontradas.Count)"

    if ($candidatos.Count -eq 0) {
        Write-Log "Ninguna app tiene mapping. Nada que migrar." -Level "WARNING"
        return
    }

    # 5. VERIFICAR QUE EXISTEN EN CHOCO ANTES DE DESINSTALAR
    Write-Log "========================================================"
    Write-Log "=== PASO 0: VERIFICANDO PAQUETES EN CHOCO (ONLINE) ==="
    Write-Log "========================================================"

    $verificados  = @()
    $noEnChoco    = @()

    foreach ($c in $candidatos) {
        Write-Log "Verificando en Choco: $($c.ChocolateyId) ..."
        if ($DryRun) {
            Write-Log "[DRYRUN] Se verificaria: $($c.ChocolateyId)"
            $verificados += $c
            continue
        }

        $existeEnChoco   = Test-ChocoPackageExists  -PackageId $c.ChocolateyId
        $yaEnChoco       = Test-ChocoAlreadyInstalled -PackageId $c.ChocolateyId

        if ($existeEnChoco) {
            $c | Add-Member -NotePropertyName "YaEnChoco" -NotePropertyValue $yaEnChoco -Force
            $verificados += $c
            $estado = if ($yaEnChoco) { "ya instalado por Choco -> se hara upgrade" } else { "OK en repo" }
            Write-Log "  VERIFICADO: $($c.ChocolateyId) ($estado)"
        } else {
            $noEnChoco += $c.DisplayName
            Write-Log "  NO ENCONTRADO EN CHOCO: $($c.ChocolateyId) -> '$($c.DisplayName)' se omite" -Level "WARNING"
        }
    }

    Write-Log "Verificados OK: $($verificados.Count) / $($candidatos.Count)"
    if ($noEnChoco.Count -gt 0) {
        Write-Log "Omitidos (no estan en Choco, no se tocan):" -Level "WARNING"
        foreach ($n in $noEnChoco) { Write-Log "  - $n" -Level "WARNING" }
    }

    if ($verificados.Count -eq 0) {
        Write-Log "Ninguna app verificada en Choco. Abortando." -Level "WARNING"
        return
    }

    # 6. CONFIRMACION ANTES DE PROCEDER
    Write-Log "========================================================"
    Write-Log "=== Apps que seran migradas (verificadas en Choco) ==="
    Write-Log "========================================================"
    foreach ($c in $verificados) {
        $extra = @()
        if ($c.EsBloatware) { $extra += "BLOATWARE" }
        if ($c.YaEnChoco)   { $extra += "upgrade" } else { $extra += "install" }
        $tag = if ($extra) { " [" + ($extra -join ", ") + "]" } else { "" }
        Write-Log "  $($c.DisplayName) -> $($c.ChocolateyId)$tag"
    }

    if (-not $DryRun) {
        Write-Host ""
        Write-Host "==> Continuar con la migracion de $($verificados.Count) apps? (S/N): " -ForegroundColor Cyan -NoNewline
        $confirmacion = Read-Host
        if ($confirmacion -notmatch "^[Ss]$") {
            Write-Log "Operacion cancelada por el usuario."
            return
        }
    }

    # 7. DESINSTALAR (solo las que NO estan ya en Choco)
    # ORDEN: primero todo, luego navegadores secundarios, Chrome al ultimo
    # Asi la PC nunca queda sin browser durante el proceso
    Write-Log "========================================================"
    Write-Log "=== PASO 1: DESINSTALANDO APPS ORIGINALES ==="
    Write-Log "========================================================"
    $desinstalacionesOK = 0
    $paraReinstalar     = @()

    $noNavegadores = $verificados | Where-Object {
        $_.ChocolateyId -notmatch 'googlechrome|firefox|microsoft-edge|opera|brave|tor-browser'
    }
    $navegadores = $verificados | Where-Object {
        $_.ChocolateyId -match 'firefox|microsoft-edge|opera|brave|tor-browser'
    }
    $chrome = $verificados | Where-Object { $_.ChocolateyId -eq 'googlechrome' }

    Write-Log "Orden de desinstalacion: apps normales -> navegadores secundarios -> Chrome al ultimo"
    $ordenDesinstalacion = @() + $noNavegadores + $navegadores + $chrome

    foreach ($c in $ordenDesinstalacion) {
        if ($c.YaEnChoco) {
            Write-Log "Saltando desinstalacion de '$($c.DisplayName)' - ya esta en Choco, se hara upgrade"
            $paraReinstalar += $c
            continue
        }
        if (Uninstall-Application -DisplayName $c.DisplayName -UninstallString $c.UninstallString) {
            $desinstalacionesOK++
            $paraReinstalar += $c
        } else {
            Write-Log "Se omite reinstalacion de '$($c.DisplayName)' por fallo en desinstalacion" -Level "WARNING"
        }
    }

    Write-Log "Desinstaladas: $desinstalacionesOK / $($verificados.Where({-not $_.YaEnChoco}).Count)"

    # 8. Chocolatey ya instalado al principio, nada que hacer aqui

    # 9. INSTALAR / UPGRADE DESDE CHOCO
    Write-Log "========================================================"
    Write-Log "=== PASO 3: INSTALANDO/ACTUALIZANDO DESDE CHOCOLATEY ==="
    Write-Log "========================================================"
    $instalacionesOK = 0
    $fallos = @()

    foreach ($c in $paraReinstalar) {
        $yaEnChoco = if ($null -ne $c.YaEnChoco) { $c.YaEnChoco } else { $false }
        if (Install-ChocoPackage -PackageId $c.ChocolateyId -YaInstalado $yaEnChoco) {
            $instalacionesOK++
        } else {
            $fallos += "$($c.DisplayName) -> $($c.ChocolateyId)"
        }
    }

    # 10. GENERAR XML DE REFERENCIA
    $configDir = Join-Path $PSScriptRoot "Config"
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    $xmlPath = Join-Path $configDir "AppsInstaladas-Choco.config"
    $xmlContent = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<packages>`r`n"
    foreach ($c in ($paraReinstalar | Where-Object { $fallos -notcontains "$($_.DisplayName) -> $($_.ChocolateyId)" })) {
        $xmlContent += "  <package id=`"$($c.ChocolateyId)`" />`r`n"
    }
    $xmlContent += "</packages>"
    $xmlContent | Out-File -FilePath $xmlPath -Encoding utf8
    Write-Log "XML guardado en: $xmlPath"

    # 11. RESUMEN FINAL
    $duracion = (Get-Date) - $startTime
    Write-Log "========================================================"
    Write-Log "=== RESUMEN FINAL ==="
    Write-Log "========================================================"
    Write-Log "Apps analizadas:                   $($installedApps.Count)"
    Write-Log "Con mapping en DB:                 $($candidatos.Count)"
    Write-Log "Verificadas OK en Choco:           $($verificados.Count)"
    Write-Log "Omitidas (no estan en Choco):      $($noEnChoco.Count)"
    Write-Log "Excluidas por seguridad:           $($excluidasRiesgo.Count)"
    Write-Log "Desinstalaciones exitosas:         $desinstalacionesOK"
    Write-Log "Instalaciones/upgrades exitosos:   $instalacionesOK / $($paraReinstalar.Count)"
    Write-Log "Tiempo total:                      $($duracion.ToString('hh\:mm\:ss'))"

    if ($fallos.Count -gt 0) {
        Write-Log "--- FALLOS en instalacion ---" -Level "WARNING"
        foreach ($f in $fallos) { Write-Log "  FALLO: $f" -Level "WARNING" }
    }

    if ($excluidasRiesgo.Count -gt 0) {
        Write-Log "--- Apps EXCLUIDAS (plugins/librerias/config - actualizar manualmente) ---" -Level "WARNING"
        foreach ($e in $excluidasRiesgo) { Write-Log "  EXCLUIDA: $e" -Level "WARNING" }
        Write-Log "Estas apps NO fueron tocadas. El usuario las actualiza manualmente." -Level "WARNING"
    }

    if ($noEncontradas.Count -gt 0) {
        Write-Log "--- Apps SIN MAPPING (agregar al JSON si tienen paquete en Choco) ---" -Level "WARNING"
        foreach ($n in ($noEncontradas | Sort-Object)) {
            Write-Log "  SIN MAPPING: $n" -Level "WARNING"
        }
    }

    if ($fallos.Count -eq 0) {
        Write-Log "EXITO TOTAL: Todas las apps procesadas correctamente."
    }
    Write-Log "========================================================"
}

Start-ChocolateyMigration