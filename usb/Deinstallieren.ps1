<#
    Deinstallieren.ps1

    Entfernt monitor-focus-follow von diesem PC:
      - beendet eine laufende Instanz,
      - loescht die geplante Autostart-Aufgabe (und eine evtl. alte Verknuepfung),
      - loescht den Programmordner %LOCALAPPDATA%\monitor-focus-follow.

    Betrifft nur die installierte Variante (Setup.cmd). Eine portabel vom
    Stick gestartete Instanz wird ebenfalls beendet, aber auf dem Stick
    liegt naturgemaess nichts zum Loeschen.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path $env:LOCALAPPDATA 'monitor-focus-follow'
$lnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'MonitorFocusFollow.lnk'

Write-Host "monitor-focus-follow entfernen"
Write-Host ""

# 1. Laufende Instanz(en) beenden.
$procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*MonitorFocusFollow.ps1*' }
if ($procs) {
    foreach ($p in $procs) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "Instanz beendet (PID $($p.ProcessId))" } catch { }
    }
    Start-Sleep -Milliseconds 500
}
else {
    Write-Host "keine laufende Instanz gefunden"
}

# 2. Autostart entfernen: geplante Aufgabe + alte Verknuepfung.
$task = Get-ScheduledTask -TaskName 'MonitorFocusFollow' -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName 'MonitorFocusFollow' -Confirm:$false
    Write-Host "geplante Aufgabe entfernt"
}
if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Host "alte Autostart-Verknuepfung entfernt"
}
if (-not $task -and -not (Test-Path -LiteralPath $lnk)) {
    Write-Host "kein Autostart-Eintrag vorhanden"
}

# 3. Programmordner loeschen.
if (Test-Path -LiteralPath $target) {
    try {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Host "Programmordner geloescht: $target"
    }
    catch {
        Write-Host "Programmordner konnte nicht geloescht werden ($($_.Exception.Message))."
        Write-Host "Bitte manuell loeschen: $target"
    }
}
else {
    Write-Host "kein Programmordner vorhanden (war evtl. nur portabel gestartet)"
}

Write-Host ""
Write-Host "Fertig."
