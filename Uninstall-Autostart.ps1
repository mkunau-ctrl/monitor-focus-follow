<#
    Uninstall-Autostart.ps1

    Entfernt die Autostart-Verknuepfung. Ein bereits laufender Prozess
    wird dadurch NICHT beendet - dafuer den Task-Manager benutzen.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$startup = [Environment]::GetFolderPath('Startup')
$lnk     = Join-Path $startup 'MonitorFocusFollow.lnk'

if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Host "Autostart entfernt: $lnk"
}
else {
    Write-Host "Autostart war nicht eingerichtet (keine Verknuepfung gefunden)."
}

Write-Host ""
Write-Host "Hinweis: Ein bereits laufendes monitor-focus-follow wird hierdurch"
Write-Host "nicht beendet. Zum Beenden den Task-Manager verwenden:"
Write-Host "  Details -> powershell.exe mit 'MonitorFocusFollow.ps1' -> Task beenden."
