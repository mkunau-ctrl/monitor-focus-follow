<#
    Uninstall-Autostart.ps1

    Entfernt den Autostart wieder: die geplante Aufgabe "MonitorFocusFollow"
    und - falls von einer aelteren Version noch vorhanden - die Verknuepfung
    im Autostart-Ordner.

    Ein bereits laufender Prozess wird dadurch NICHT beendet - dafuer den
    Task-Manager benutzen (Details -> powershell.exe mit 'MonitorFocusFollow.ps1').
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'MonitorFocusFollow'

# 1. Geplante Aufgabe entfernen.
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Geplante Aufgabe entfernt: $taskName"
}
else {
    Write-Host "Keine geplante Aufgabe '$taskName' gefunden."
}

# 2. Alte Autostart-Verknuepfung entfernen (falls noch da).
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'MonitorFocusFollow.lnk'
if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Host "Alte Autostart-Verknuepfung entfernt: $lnk"
}

Write-Host ""
Write-Host "Hinweis: Ein bereits laufendes monitor-focus-follow wird hierdurch"
Write-Host "nicht beendet. Zum Beenden den Task-Manager verwenden:"
Write-Host "  Details -> powershell.exe mit 'MonitorFocusFollow.ps1' -> Task beenden."
