<#
    Setup.ps1  (Variante A)

    Kopiert monitor-focus-follow vom aktuellen Ordner (z. B. USB-Stick) nach
    %LOCALAPPDATA%\monitor-focus-follow auf diesem PC, richtet den Autostart
    ein und startet das Programm sofort. Kein Administrator noetig.
    Danach kann der USB-Stick abgezogen werden.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'monitor-focus-follow'

Write-Host "monitor-focus-follow installieren"
Write-Host "  von:  $source"
Write-Host "  nach: $target"
Write-Host ""

# Laufende Instanz beenden, damit Dateien nicht gesperrt sind.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*MonitorFocusFollow.ps1*' } |
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Write-Host "laufende Instanz beendet (PID $($_.ProcessId))" } catch { }
    }
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Path $target -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $target 'src') -Force | Out-Null

# Programmdateien kopieren (Config gesondert, s. u.).
$files = @(
    'MonitorFocusFollow.ps1',
    'Install-Autostart.ps1',
    'Uninstall-Autostart.ps1',
    'src\Native.cs',
    'src\FocusLogic.psm1'
)
foreach ($f in $files) {
    $src = Join-Path $source $f
    $dst = Join-Path $target $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Datei fehlt im Paket: $f" }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "kopiert: $f"
}

# Config: vorhandene Einstellungen auf dem PC NICHT ueberschreiben.
$cfgSrc = Join-Path $source 'config.psd1'
$cfgDst = Join-Path $target 'config.psd1'
if (Test-Path -LiteralPath $cfgDst) {
    Copy-Item -LiteralPath $cfgSrc -Destination (Join-Path $target 'config.psd1.neu') -Force
    Write-Host "config.psd1 war schon vorhanden - deine Einstellungen bleiben."
    Write-Host "  (die neue Vorlage liegt als config.psd1.neu daneben)"
}
else {
    Copy-Item -LiteralPath $cfgSrc -Destination $cfgDst -Force
    Write-Host "kopiert: config.psd1"
}

Write-Host ""
Write-Host "Autostart einrichten und Programm starten..."
# Install-Autostart.ps1 legt die geplante Aufgabe an, raeumt alte
# Autostart-Eintraege weg und startet das Programm sofort.
& (Join-Path $target 'Install-Autostart.ps1') | Out-Null

Write-Host ""
Write-Host "Fertig. Das Programm laeuft jetzt und startet ab sofort bei jeder Anmeldung."
Write-Host "Der USB-Stick kann abgezogen werden."
Write-Host ""
Write-Host "Beenden: Task-Manager -> Details -> powershell.exe mit 'MonitorFocusFollow.ps1'."
Write-Host "Kurz pausieren: Strg+Alt+Pause."
Write-Host "Wieder entfernen: Deinstallieren.cmd auf dem Stick."
