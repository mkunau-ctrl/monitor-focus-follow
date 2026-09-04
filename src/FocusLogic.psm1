<#
    FocusLogic.psm1 - reine Entscheidungslogik fuer monitor-focus-follow.

    Dieses Modul ruft KEINE Windows-API auf. Alles hier ist mit Pester
    testbar. Die eigentlichen API-Aufrufe stecken in src/Native.cs.
#>

function Test-ShouldSwitchWindow {
    <#
        Entscheidet, ob jetzt ein Fokuswechsel ausgeloest werden soll.

        True nur wenn ALLE Bedingungen erfuellt sind:
          - keine Maustaste gedrueckt (kein Markieren/Ziehen im Gange),
          - aktuelles Fenster-Handle gueltig (nicht 0),
          - aktuelles Fenster verschieden vom zuletzt fokussierten,
          - seit Beginn des Wechsels sind mindestens DebounceMs vergangen.

        Handles werden als [long] uebergeben (in der Schleife per
        IntPtr.ToInt64()).
    #>
    param(
        [long]$LastHwnd,
        [long]$CurrentHwnd,
        [datetime]$ChangeStartedUtc,
        [datetime]$NowUtc,
        [int]$DebounceMs,
        [bool]$MouseButtonDown
    )

    if ($MouseButtonDown) { return $false }
    if ($CurrentHwnd -eq 0) { return $false }
    if ($CurrentHwnd -eq $LastHwnd) { return $false }
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

Export-ModuleMember -Function Test-ShouldSwitchWindow, Test-IsFocusableWindow
