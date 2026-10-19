# Nombre Archivo: "AnclarBarraTareas.ps1"
# Claude 16/10/2026
$progs = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
$xml   = "C:\Users\Public\Documents\AutoTemp\TaskbarLayout.xml"

# 1) Panel de control no tiene acceso directo por defecto: se crea
$ws = New-Object -ComObject WScript.Shell
$s  = $ws.CreateShortcut((Join-Path $progs "Panel de control.lnk"))
$s.TargetPath = "$env:windir\System32\control.exe"
$s.Save()

# 2) Armar la lista (solo lo que existe)
$items = @('<taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />')
foreach ($n in 'Google Chrome','Panel de control','Excel','Word') {
    $p = Join-Path $progs "$n.lnk"
    if (Test-Path $p) { $items += "<taskbar:DesktopApp DesktopApplicationLinkPath=`"$p`" />" }
    else { Write-Host "No existe $p - se omite" -ForegroundColor Yellow }
}

@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        $($items -join "`r`n        ")
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@ | Set-Content -Path $xml -Encoding UTF8

# 3) Aplicar: politica de layout + reiniciar explorer
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
New-Item $key -Force | Out-Null
Set-ItemProperty $key -Name LockedStartLayout -Value 1 -Type DWord
Set-ItemProperty $key -Name StartLayoutFile  -Value $xml -Type ExpandString
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 10

# 4) Destrabar para que el usuario pueda modificar la barra despues
Set-ItemProperty $key -Name LockedStartLayout -Value 0
Remove-ItemProperty $key -Name StartLayoutFile -ErrorAction SilentlyContinue

# 5) Quitar el tilde de "Bloquear la barra de tareas"
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty $adv -Name TaskbarSizeMove -Value 1 -Type DWord

Stop-Process -Name explorer -Force
