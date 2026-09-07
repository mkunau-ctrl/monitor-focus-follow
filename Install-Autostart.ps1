<#
    Install-Autostart.ps1

    Richtet den Autostart als GEPLANTE AUFGABE ein ("Bei Anmeldung").
    Vorteile gegenueber einer Verknuepfung im Autostart-Ordner:
      - kann von "Aufraeum-"/Optimizer-Programmen nicht per Haeckchen
        deaktiviert werden,
      - startet zuverlaessig, mit kurzer Verzoegerung nach der Anmeldung,
      - startet das Tool nach einem Absturz automatisch neu.

    Braucht KEINE Administratorrechte (Aufgabe laeuft nur, wenn der
    aktuelle Benutzer angemeldet ist; es wird kein Passwort gespeichert).

    Beenden im Betrieb weiterhin ueber den Task-Manager.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'MonitorFocusFollow'
$script   = Join-Path $PSScriptRoot 'MonitorFocusFollow.ps1'
$psExe    = (Get-Command powershell.exe).Source

if (-not (Test-Path -LiteralPath $script)) {
    throw "MonitorFocusFollow.ps1 nicht gefunden neben diesem Skript."
}

# ---------------------------------------------------------------------------
# 1. Geplante Aufgabe anlegen / aktualisieren
# ---------------------------------------------------------------------------
$action = New-ScheduledTaskAction -Execute $psExe `
    -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script) `
    -WorkingDirectory $PSScriptRoot

$trigger = New-ScheduledTaskTrigger -AtLogOn -User ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
$trigger.Delay = 'PT15S'   # 15 Sekunden nach der Anmeldung starten

$principal = New-ScheduledTaskPrincipal -UserId ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME) `
    -LogonType Interactive -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)   # kein Zeitlimit
$settings.Hidden = $true
$settings.DisallowStartOnRemoteAppSession = $false

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'monitor-focus-follow: Tastaturfokus folgt der Maus beim Monitorwechsel' `
    -Force | Out-Null

Write-Host "Geplante Aufgabe eingerichtet: $taskName (Ausloeser: bei Anmeldung, +15 s)"

# ---------------------------------------------------------------------------
# 2. Alten Autostart-Ordner-Eintrag entfernen (Migration / Doppelstart
#    vermeiden)
# ---------------------------------------------------------------------------
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'MonitorFocusFollow.lnk'
if (Test-Path -LiteralPath $lnk) {
    Remove-Item -LiteralPath $lnk -Force
    Write-Host "Alte Autostart-Verknuepfung entfernt: $lnk"
}
$approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
if (Test-Path -LiteralPath $approvedKey) {
    $prop = Get-ItemProperty -LiteralPath $approvedKey -ErrorAction SilentlyContinue
    if ($prop -and $prop.PSObject.Properties.Name -contains 'MonitorFocusFollow.lnk') {
        Remove-ItemProperty -LiteralPath $approvedKey -Name 'MonitorFocusFollow.lnk' -Force
        Write-Host "Alten Registry-Eintrag (StartupApproved) aufgeraeumt."
    }
}

# ---------------------------------------------------------------------------
# 3. Laufende Instanz neu starten, damit es sofort ohne Ab-/Anmelden laeuft
# ---------------------------------------------------------------------------
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*MonitorFocusFollow.ps1*' } |
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
    }
Start-Sleep -Milliseconds 400
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "Fertig. Das Programm laeuft jetzt und startet ab sofort bei jeder Anmeldung."
Write-Host "Beenden: Task-Manager -> Details -> powershell.exe mit 'MonitorFocusFollow.ps1' -> Task beenden."
Write-Host "Kurz pausieren: Strg+Alt+Pause."
Write-Host "Autostart wieder entfernen: Uninstall-Autostart.ps1"
