<#
    MonitorFocusFollow.ps1

    Setzt den Fokus beim Ueberqueren der Monitorgrenze auf das Fenster
    direkt unter dem Mauszeiger. Bewegungen innerhalb eines Monitors
    aendern nichts.

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
    PollIntervalMs    = 100
    DebounceMs        = 120
    RaiseWindow       = $false
    PauseOnFullscreen = $true
    ExcludeProcesses  = @()
    LogToFile         = $false
    LogPath           = 'focus.log'
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
Add-Type -AssemblyName System.Windows.Forms

[MFF.Native]::MakeDpiAware()

# ---------------------------------------------------------------------------
# Monitor-Rechtecke aus dem aktuellen Bildschirmzustand
# ---------------------------------------------------------------------------
function Get-MonitorRects {
    [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
        [pscustomobject]@{
            Left   = $_.Bounds.Left
            Top    = $_.Bounds.Top
            Right  = $_.Bounds.Right
            Bottom = $_.Bounds.Bottom
        }
    }
}

# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------
$lastIndex       = -1
$pendingIndex    = -1
$changeStartedUtc = [datetime]::UtcNow

Write-FocusLog "gestartet (PollIntervalMs=$($cfg.PollIntervalMs), DebounceMs=$($cfg.DebounceMs), RaiseWindow=$($cfg.RaiseWindow), PauseOnFullscreen=$($cfg.PauseOnFullscreen))"

try {
    while ($true) {
        try {
            $mons = Get-MonitorRects
            $p = [MFF.Native]::GetCursorPos()
            $idx = Get-MonitorIndexForPoint $p[0] $p[1] $mons

            if ($idx -ge 0 -and $idx -ne $lastIndex -and $idx -ne $pendingIndex) {
                $pendingIndex = $idx
                $changeStartedUtc = [datetime]::UtcNow
            }

            if ($pendingIndex -ge 0 -and
                (Test-ShouldSwitch $lastIndex $pendingIndex $changeStartedUtc ([datetime]::UtcNow) $cfg.DebounceMs)) {

                $p2 = [MFF.Native]::GetCursorPos()
                $nowIdx = Get-MonitorIndexForPoint $p2[0] $p2[1] $mons

                if ($nowIdx -eq $pendingIndex) {
                    $blockedByFullscreen = $cfg.PauseOnFullscreen -and [MFF.Native]::IsForegroundFullscreen()
                    if (-not $blockedByFullscreen) {
                        $h = [MFF.Native]::GetRootWindowAt($p2[0], $p2[1])
                        if ($h -ne [IntPtr]::Zero -and $h -ne [MFF.Native]::GetForeground()) {
                            $cls  = [MFF.Native]::GetClassNameOf($h)
                            $proc = [MFF.Native]::GetProcessNameOf($h)
                            $vis  = [MFF.Native]::IsVisibleTopLevel($h)
                            if (Test-IsFocusableWindow $cls $proc $vis $cfg.ExcludeProcesses) {
                                [MFF.Native]::SetForegroundForced($h, [bool]$cfg.RaiseWindow)
                                Write-FocusLog ("Fokus -> Monitor {0}, Prozess {1}" -f $pendingIndex, $proc)
                            }
                        }
                    }
                    $lastIndex = $pendingIndex
                }
                $pendingIndex = -1
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
