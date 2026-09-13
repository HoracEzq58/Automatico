# nombre archivo: "AjustarMayorRendimientoMostrarVistas.ps1" Gem - 11/09/2026
# 1. Configurar el modo de efectos visuales a 'Personalizado' (Custom)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -ErrorAction SilentlyContinue

# 2. Modificar la máscara binaria global para destildar todas las opciones en la ventana sysdm.cpl
$HexMask = [byte[]](0x90, 0x12, 0x01, 0x80, 0x10, 0x00, 0x00, 0x00)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value $HexMask -ErrorAction SilentlyContinue

# 3. Desactivar funciones específicas (sombras, animaciones, arrastre de ventanas, suavizado de fuentes)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Value 0 -ErrorAction SilentlyContinue

# 4. Forzar la activación EXCLUSIVA de "Mostrar vistas en miniatura en lugar de iconos"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "IconsOnly" -Value 0 -ErrorAction SilentlyContinue

# 5. Reiniciar el Explorador para aplicar los cambios de entorno sin reiniciar la PC
Stop-Process -Name explorer -Force