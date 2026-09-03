<#
    FocusLogic.psm1 - reine Entscheidungslogik fuer monitor-focus-follow.

    Dieses Modul ruft KEINE Windows-API auf. Alles hier ist mit Pester
    testbar. Die eigentlichen API-Aufrufe stecken in src/Native.cs.
#>

function Get-MonitorIndexForPoint {
    <#
        Liefert den Index des ersten Monitors, der den Punkt (X, Y) enthaelt.
        Monitore: Array von Objekten mit .Left .Top .Right .Bottom (Ganzzahlen).
        Right/Bottom sind exklusiv -> linke/obere Kante gehoert zum Monitor,
        rechte/untere nicht. Kein Treffer -> -1.
    #>
    param(
        [int]$X,
        [int]$Y,
        [object[]]$Monitors
    )

    for ($i = 0; $i -lt $Monitors.Count; $i++) {
        $m = $Monitors[$i]
        if ($X -ge $m.Left -and $X -lt $m.Right -and $Y -ge $m.Top -and $Y -lt $m.Bottom) {
            return $i
        }
    }
    return -1
}

function Test-ShouldSwitch {
    <#
        Entscheidet, ob jetzt ein Fokuswechsel ausgeloest werden soll.
        True nur wenn: aktueller Monitor gueltig (>= 0), verschieden vom
        letzten, und seit Beginn des Wechsels sind mindestens DebounceMs
        vergangen.
    #>
    param(
        [int]$LastIndex,
        [int]$CurrentIndex,
        [datetime]$ChangeStartedUtc,
        [datetime]$NowUtc,
        [int]$DebounceMs
    )

    if ($CurrentIndex -lt 0) { return $false }
    if ($CurrentIndex -eq $LastIndex) { return $false }
    return ((($NowUtc - $ChangeStartedUtc).TotalMilliseconds) -ge $DebounceMs)
}

function Test-IsFocusableWindow {
    <#
        Filtert Fenster, die keinen Fokus bekommen sollen: Desktop,
        Taskleiste, unsichtbare/Nicht-Top-Level-Fenster und Prozesse aus
        der Ausschlussliste.
    #>
    param(
        [string]$ClassName,
        [string]$ProcessName,
        [bool]$IsVisibleTopLevel,
        [string[]]$ExcludeProcesses
    )

    if (-not $IsVisibleTopLevel) { return $false }

    $blockedClasses = @('WorkerW', 'Progman', 'Shell_TrayWnd', 'Windows.UI.Core.CoreWindow')
    if ($blockedClasses -contains $ClassName) { return $false }

    $pn = ($ProcessName -replace '\.exe$', '').ToLowerInvariant()
    foreach ($ex in $ExcludeProcesses) {
        if (($ex -replace '\.exe$', '').ToLowerInvariant() -eq $pn) { return $false }
    }
    return $true
}

Export-ModuleMember -Function Get-MonitorIndexForPoint, Test-ShouldSwitch, Test-IsFocusableWindow
