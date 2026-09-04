<#
    Build-Release.ps1

    Baut das Verteilpaket dist\monitor-focus-follow-usb.zip.
    Inhalt: das Programm + src\ + Config + die USB-Skripte (usb\) +
    Kurzanleitung. Ohne Tests, Doku, .git.

    Das ZIP auf einen USB-Stick entpacken - fertig.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root  = $PSScriptRoot
$dist  = Join-Path $root 'dist'
$stage = Join-Path $dist 'monitor-focus-follow'
$zip   = Join-Path $dist 'monitor-focus-follow-usb.zip'

# Sauber starten.
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zip)   { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path (Join-Path $stage 'src') -Force | Out-Null

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
    Copy-Item -LiteralPath (Join-Path $root $f) -Destination (Join-Path $stage $f) -Force
}

# USB-Skripte + Anleitung (aus usb\ in den Paketstamm).
Get-ChildItem -LiteralPath (Join-Path $root 'usb') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage $_.Name) -Force
}

# ZIP mit oberstem Ordner "monitor-focus-follow\".
Compress-Archive -Path $stage -DestinationPath $zip -Force

$size = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Write-Host "Paket gebaut:"
Write-Host "  $zip  ($size KB)"
Write-Host ""
Write-Host "Inhalt:"
Get-ChildItem -LiteralPath $stage -Recurse -File |
    ForEach-Object { "  " + $_.FullName.Substring($stage.Length + 1) } |
    Sort-Object
Write-Host ""
Write-Host "Auf einen USB-Stick entpacken. Dann dort Setup.cmd (installieren)"
Write-Host "oder Start-Portabel.cmd (nur vom Stick) doppelklicken."
