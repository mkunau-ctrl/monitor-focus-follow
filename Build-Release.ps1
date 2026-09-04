<#
    Build-Release.ps1

    Baut das Verteilpaket dist\monitor-focus-follow-usb.zip.
    Inhalt: das Programm + src\ + Config + die USB-Skripte (usb\) +
    Kurzanleitung. Ohne Tests, Doku, .git.

    Das ZIP auf einen USB-Stick entpacken - fertig.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root    = $PSScriptRoot
$dist    = Join-Path $root 'dist'
$stage   = Join-Path $dist '_stage'
# Der Ordnername beginnt mit '!', damit er im Explorer ganz oben steht.
$appDir  = Join-Path $stage '!monitor-focus-follow'
$zip     = Join-Path $dist 'monitor-focus-follow-usb.zip'

# Sauber starten.
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zip)   { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path (Join-Path $appDir 'src') -Force | Out-Null

# Programmdateien.
$programFiles = @(
    'MonitorFocusFollow.ps1',
    'config.psd1',
    'Install-Autostart.ps1',
    'Uninstall-Autostart.ps1',
    'src\Native.cs',
    'src\FocusLogic.psm1'
)
foreach ($f in $programFiles) {
    Copy-Item -LiteralPath (Join-Path $root $f) -Destination (Join-Path $appDir $f) -Force
}

# USB-Skripte + Anleitung (aus usb\ in den App-Ordner).
Get-ChildItem -LiteralPath (Join-Path $root 'usb') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $appDir $_.Name) -Force
}

# Wegweiser-Datei neben den Ordner (landet nach dem Entpacken im Stammverzeichnis).
$signpost = @"
========================================
  monitor-focus-follow
========================================

Der Ordner liegt hier:  !monitor-focus-follow
(steht ganz oben, weil der Name mit ! beginnt)

Darin:
  Setup.cmd          -> auf diesem PC installieren
  Start-Portabel.cmd -> nur vom Stick starten (ohne Installation)
  Deinstallieren.cmd -> wieder entfernen
  LIESMICH.txt       -> ausfuehrliche Anleitung
"@
[System.IO.File]::WriteAllText(
    (Join-Path $stage '!!! monitor-focus-follow - HIER LESEN.txt'),
    $signpost, [System.Text.UTF8Encoding]::new($false))

# ZIP: Inhalt von _stage (also der !-Ordner + die Wegweiser-Datei) landet
# direkt im Zielverzeichnis beim Entpacken.
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

$size = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Write-Host "Paket gebaut:"
Write-Host "  $zip  ($size KB)"
Write-Host ""
Write-Host "Inhalt:"
Get-ChildItem -LiteralPath $stage -Recurse -File |
    ForEach-Object { "  " + $_.FullName.Substring($stage.Length + 1) } |
    Sort-Object
Write-Host ""
Write-Host "Auf einen USB-Stick entpacken. Dann im Ordner '!monitor-focus-follow'"
Write-Host "Setup.cmd (installieren) oder Start-Portabel.cmd (nur vom Stick) doppelklicken."
