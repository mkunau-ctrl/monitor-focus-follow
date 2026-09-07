<#
    MonitorFocusFollow.ps1

    Setzt den Tastaturfokus auf das Fenster direkt unter dem Mauszeiger,
    sobald sich dieses Fenster aendert - egal ob durch Monitorwechsel
    oder durch ein anderes Fenster im Splitscreen daneben. Bewegungen
    innerhalb desselben Fensters aendern nichts.

    Normalbetrieb: versteckt per Autostart (siehe Install-Autostart.ps1).
    Beenden: ueber den Task-Manager. Kurz pausieren: Strg+Alt+Pause.

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
# Absturz-Log (immer, unabhaengig von der Konfiguration)
# ---------------------------------------------------------------------------
function Write-CrashLog {
    param([string]$Message)
    try {
        $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
        Add-Content -LiteralPath "$PSScriptRoot\crash.log" -Value $line -Encoding UTF8
    }
    catch { }
}

# ---------------------------------------------------------------------------
# Einmal-Instanz-Sperre
# ---------------------------------------------------------------------------
$script:singleInstanceMutex = $null
try {
    $created = $false
    $script:singleInstanceMutex = New-Object System.Threading.Mutex($true, 'MonitorFocusFollow_SingleInstance', [ref]$created)
    if (-not $created) {
        if (-not $script:singleInstanceMutex.WaitOne(0)) {
            if ($Log) { Write-Host "$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) bereits aktiv - diese Instanz beendet sich" }
            exit 0
        }
    }
}
catch {
    Write-CrashLog "Mutex-Fehler beim Start: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Konfiguration laden (mit Fallback auf eingebaute Standardwerte)
# ---------------------------------------------------------------------------
$defaults = @{
    PollIntervalMs      = 100
    DebounceMs          = 120
    RaiseWindow         = $false
    PauseOnFullscreen   = $true
    PauseWhileMouseDown = $true
    EnableToggleHotkey  = $true
    ToggleKey           = 'Pause'
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

# Toggle-Taste in einen virtuellen Tastencode aufloesen.
$vkMap = @{ 'Pause' = 0x13; 'ScrollLock' = 0x91; 'F9' = 0x78; 'F10' = 0x79; 'F11' = 0x7A; 'F12' = 0x7B }
$toggleKeyName = 'Pause'
if ($vkMap.ContainsKey([string]$cfg.ToggleKey)) {
    $toggleKeyName = [string]$cfg.ToggleKey
}
else {
    $configWarnings.Add("ToggleKey '$($cfg.ToggleKey)' ist unbekannt - 'Pause' wird verwendet.")
}
$toggleVk = $vkMap[$toggleKeyName]
$VK_CONTROL = 0x11
$VK_MENU    = 0x12   # Alt

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
# Native-Helfer kompilieren (Fehler hier ist fatal -> crash.log + Exit 1)
# ---------------------------------------------------------------------------
try {
    $nativeSrc = Get-Content -LiteralPath "$PSScriptRoot\src\Native.cs" -Raw
    Add-Type -TypeDefinition $nativeSrc -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
    Import-Module "$PSScriptRoot\src\FocusLogic.psm1" -Force
    # Im Normalbetrieb (kein -Log) ein evtl. sichtbares Konsolenfenster
    # sofort verstecken - der Autostart soll komplett unsichtbar laufen.
    if (-not $Log) { [MFF.Native]::HideConsoleWindow() }
    [MFF.Native]::MakeDpiAware()
}
catch {
    Write-FocusLog "FEHLER beim Start: $($_.Exception.Message)"
    Write-CrashLog "Startfehler: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    exit 1
}

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
$paused           = $false
$hotkeyWasDown    = $false

Write-FocusLog ("gestartet (PollIntervalMs={0}, DebounceMs={1}, RaiseWindow={2}, PauseOnFullscreen={3}, PauseWhileMouseDown={4}, Hotkey={5})" -f `
    $cfg.PollIntervalMs, $cfg.DebounceMs, $cfg.RaiseWindow, $cfg.PauseOnFullscreen, $cfg.PauseWhileMouseDown, `
    $(if ([bool]$cfg.EnableToggleHotkey) { "Strg+Alt+$toggleKeyName" } else { 'aus' }))

try {
    while ($true) {
        try {
            # --- Pause-Hotkey (Flankenerkennung) ---
            if ([bool]$cfg.EnableToggleHotkey) {
                $hotkeyDown = [MFF.Native]::IsKeyDown($VK_CONTROL) -and `
                              [MFF.Native]::IsKeyDown($VK_MENU) -and `
                              [MFF.Native]::IsKeyDown($toggleVk)
                if ($hotkeyDown -and -not $hotkeyWasDown) {
                    $paused = -not $paused
                    Write-FocusLog ("Hotkey: {0}" -f $(if ($paused) { 'pausiert' } else { 'aktiv' }))
                }
                $hotkeyWasDown = $hotkeyDown
            }

            if (-not $paused) {
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
                                $cls   = [MFF.Native]::GetClassNameOf($h2ptr)
                                $proc  = [MFF.Native]::GetProcessNameOf($h2ptr)
                                $vis   = [MFF.Native]::IsVisibleTopLevel($h2ptr)
                                $exOk  = [MFF.Native]::HasAcceptableExStyle($h2ptr)
                                if (Test-IsFocusableWindow $cls $proc $vis $exOk $cfg.ExcludeProcesses) {
                                    [MFF.Native]::SetForegroundForced($h2ptr, [bool]$cfg.RaiseWindow)
                                    Write-FocusLog ("Fokus -> Prozess {0}" -f $proc)
                                }
                            }
                            # In jedem Fall gilt der Kandidat als abgehandelt.
                            $lastHwnd = $pendingHwnd
                        }
                        $pendingHwnd = 0
                    }
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
catch {
    Write-CrashLog "Unerwarteter Abbruch der Hauptschleife: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    throw
}
finally {
    Write-FocusLog "beendet"
    if ($null -ne $script:singleInstanceMutex) {
        try { $script:singleInstanceMutex.ReleaseMutex() } catch { }
        try { $script:singleInstanceMutex.Dispose() } catch { }
    }
}
