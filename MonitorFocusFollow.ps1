<#
    MonitorFocusFollow.ps1

    Setzt den Tastaturfokus auf das Fenster direkt unter dem Mauszeiger,
    sobald sich dieses Fenster aendert - egal ob durch Monitorwechsel
    oder durch ein anderes Fenster im Splitscreen daneben. Bewegungen
    innerhalb desselben Fensters aendern nichts.

    Normalbetrieb: versteckt per Autostart (siehe Install-Autostart.ps1).
    Beenden: ueber den Task-Manager.

    Zum Testen:
        powershell -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Log
        powershell -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Once -Log
#>
param(
    [switch]$Log,
    [switch]$Once,
    [string]$ConfigPath = "$PSScriptRoot\config.psd1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Konfiguration laden (mit Fallback auf eingebaute Standardwerte)
# ---------------------------------------------------------------------------
$defaults = @{
    PollIntervalMs      = 100
    DebounceMs          = 120
    RaiseWindow         = $false
    PauseOnFullscreen   = $true
    PauseWhileMouseDown = $true
    ExcludeProcesses    = @()
    LogToFile           = $false
    LogPath             = 'focus.log'
}

$cfg = $defaults.Clone()
$configWarnings = New-Object System.Collections.Generic.List[string]

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Import-PowerShellDataFile -LiteralPath $ConfigPath
        foreach ($key in $defaults.Keys) {
            if ($loaded.ContainsKey($key) -and $null -ne $loaded[$key]) {
                if ($defaults[$key] -is [bool] -and $loaded[$key] -isnot [bool]) {
                    $configWarnings.Add("Schluessel '$key' ist kein Boolescher Wert - Standard wird verwendet.")
                }
                elseif (($defaults[$key] -is [int]) -and -not ($loaded[$key] -as [int])) {
                    $configWarnings.Add("Schluessel '$key' ist keine Zahl - Standard wird verwendet.")
                }
                else {
                    $cfg[$key] = $loaded[$key]
                }
            }
        }
    }
    catch {
        $configWarnings.Add("config.psd1 konnte nicht gelesen werden ($($_.Exception.Message)) - Standardwerte werden verwendet.")
    }
}
else {
    $configWarnings.Add("config.psd1 nicht gefunden unter '$ConfigPath' - Standardwerte werden verwendet.")
}

# LogPath in absoluten Pfad aufloesen (relativ zum Projektordner).
$logPath = $cfg.LogPath
if (-not [System.IO.Path]::IsPathRooted($logPath)) {
    $logPath = Join-Path $PSScriptRoot $logPath
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-FocusLog {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    if ($Log) { Write-Host $line }
    if ($cfg.LogToFile) {
        try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { }
    }
}

foreach ($w in $configWarnings) { Write-FocusLog "WARNUNG: $w" }

# ---------------------------------------------------------------------------
# Native-Helfer kompilieren
# ---------------------------------------------------------------------------
try {
    $nativeSrc = Get-Content -LiteralPath "$PSScriptRoot\src\Native.cs" -Raw
    Add-Type -TypeDefinition $nativeSrc -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
}
catch {
    Write-FocusLog "FEHLER: C#-Helfer konnte nicht kompiliert werden: $($_.Exception.Message)"
    exit 1
}

Import-Module "$PSScriptRoot\src\FocusLogic.psm1" -Force

[MFF.Native]::MakeDpiAware()

# ---------------------------------------------------------------------------
# Hilfsfunktion: Wurzelfenster-Handle unter einem Punkt als [long] (0 = keins)
# ---------------------------------------------------------------------------
function Get-RootWindowLongAt {
    param([int]$X, [int]$Y)
    $h = [MFF.Native]::GetRootWindowAt($X, $Y)
    if ($h -eq [IntPtr]::Zero) { return [long]0 }
    return $h.ToInt64()
}

# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------
$lastHwnd         = [long]0
$pendingHwnd      = [long]0
$changeStartedUtc = [datetime]::UtcNow

Write-FocusLog ("gestartet (PollIntervalMs={0}, DebounceMs={1}, RaiseWindow={2}, PauseOnFullscreen={3}, PauseWhileMouseDown={4})" -f `
    $cfg.PollIntervalMs, $cfg.DebounceMs, $cfg.RaiseWindow, $cfg.PauseOnFullscreen, $cfg.PauseWhileMouseDown)

try {
    while ($true) {
        try {
            $p = [MFF.Native]::GetCursorPos()
            $hwnd = Get-RootWindowLongAt $p[0] $p[1]

            # Neues Fenster unter der Maus? -> als Kandidat merken.
            if ($hwnd -ne 0 -and $hwnd -ne $lastHwnd -and $hwnd -ne $pendingHwnd) {
                $pendingHwnd = $hwnd
                $changeStartedUtc = [datetime]::UtcNow
            }

            if ($pendingHwnd -ne 0) {
                $mouseDown = [bool]$cfg.PauseWhileMouseDown -and [MFF.Native]::AnyMouseButtonDown()

                if (Test-ShouldSwitchWindow $lastHwnd $pendingHwnd $changeStartedUtc ([datetime]::UtcNow) $cfg.DebounceMs $mouseDown) {

                    # Zeiger noch ueber demselben Kandidaten?
                    $p2 = [MFF.Native]::GetCursorPos()
                    $hwnd2 = Get-RootWindowLongAt $p2[0] $p2[1]

                    if ($hwnd2 -eq $pendingHwnd) {
                        $h2ptr = [MFF.Native]::GetRootWindowAt($p2[0], $p2[1])
                        $blockedByFullscreen = [bool]$cfg.PauseOnFullscreen -and [MFF.Native]::IsForegroundFullscreen()
                        $alreadyForeground   = ($h2ptr -eq [MFF.Native]::GetForeground())

                        if (-not $blockedByFullscreen -and -not $alreadyForeground) {
                            $cls  = [MFF.Native]::GetClassNameOf($h2ptr)
                            $proc = [MFF.Native]::GetProcessNameOf($h2ptr)
                            $vis  = [MFF.Native]::IsVisibleTopLevel($h2ptr)
                            if (Test-IsFocusableWindow $cls $proc $vis $cfg.ExcludeProcesses) {
                                [MFF.Native]::SetForegroundForced($h2ptr, [bool]$cfg.RaiseWindow)
                                Write-FocusLog ("Fokus -> Prozess {0}" -f $proc)
                            }
                        }
                        # In jedem Fall gilt der Kandidat als abgehandelt,
                        # damit wir ihn nicht in jeder Runde neu pruefen.
                        $lastHwnd = $pendingHwnd
                    }
                    $pendingHwnd = 0
                }
            }
        }
        catch {
            Write-FocusLog "Fehler in der Schleife: $($_.Exception.Message)"
        }

        if ($Once) { break }
        Start-Sleep -Milliseconds $cfg.PollIntervalMs
    }
}
finally {
    Write-FocusLog "beendet"
}
