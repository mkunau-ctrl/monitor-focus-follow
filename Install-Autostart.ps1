<#
    Install-Autostart.ps1

    Legt eine versteckte Autostart-Verknuepfung an, sodass
    MonitorFocusFollow.ps1 bei jeder Anmeldung im Hintergrund startet.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script  = Join-Path $PSScriptRoot 'MonitorFocusFollow.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "MonitorFocusFollow.ps1 nicht gefunden neben diesem Skript."
}

$startup = [Environment]::GetFolderPath('Startup')
$lnk     = Join-Path $startup 'MonitorFocusFollow.lnk'

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath        = (Get-Command powershell.exe).Source
$s.Arguments         = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$s.WorkingDirectory  = $PSScriptRoot
$s.WindowStyle       = 7   # minimiert / versteckt
$s.Description        = 'monitor-focus-follow: Fokus folgt der Maus beim Monitorwechsel'
$s.Save()

Write-Host "Autostart eingerichtet:"
Write-Host "  $lnk"
Write-Host ""
Write-Host "Das Programm startet automatisch bei der naechsten Anmeldung."
Write-Host "Sofort starten (ohne Ab-/Anmelden):"
Write-Host "  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$script`"'"
Write-Host ""
Write-Host "Beenden: Task-Manager -> Details -> powershell.exe mit 'MonitorFocusFollow.ps1' -> Task beenden."
