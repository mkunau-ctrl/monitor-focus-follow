# monitor-focus-follow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein verstecktes PowerShell-Hintergrundprogramm, das den Tastaturfokus beim Überqueren der Monitorgrenze auf das Fenster unter dem Mauszeiger setzt.

**Architecture:** PowerShell-Hauptschleife (`MonitorFocusFollow.ps1`) lädt `config.psd1`, kompiliert einen eingebetteten C#-Helfer (`src/Native.cs`, Klasse `MFF.Native`) per `Add-Type` und importiert reine Logik aus `src/FocusLogic.psm1`. Die Schleife pollt die Mausposition, erkennt Monitorwechsel (mit Entprellung) und ruft `SetForegroundWindowForced` auf. Logik ist von der Windows-API getrennt und mit Pester getestet.

**Tech Stack:** Windows PowerShell 5.1, `Add-Type` (C# inline), `System.Windows.Forms.Screen`, P/Invoke (user32), Pester 5.

**Spec:** `docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md`

## Global Constraints

- Zielplattform: Windows 11, Windows PowerShell 5.1 (`powershell.exe`). Keine PowerShell-7-only-Syntax.
- Keine Netzwerkzugriffe, keine Telemetrie, kein Mitlesen von Tastatureingaben.
- Standardmäßig keine Logdatei; Logdatei (wenn aktiviert) enthält nur Zeitstempel, Monitor-Index, Prozessname — nie Fenstertitel.
- Alle benutzersichtbaren Texte (README, Log, Meldungen) auf Deutsch.
- Betrieb: versteckter Autostart; Beenden nur über Task-Manager. Konsolenstart nur zum Testen (`-Verbose`).
- Config-Defaults: `PollIntervalMs=100`, `DebounceMs=120`, `RaiseWindow=$false`, `PauseOnFullscreen=$true`, `ExcludeProcesses=@()`, `LogToFile=$false`.
- Häufige Commits, jeweils nach grüner Teststufe.

---

## File Structure

- `src/FocusLogic.psm1` — reine Funktionen: `Get-MonitorIndexForPoint`, `Test-ShouldSwitch`, `Test-IsFocusableWindow`. Keine Windows-API.
- `src/Native.cs` — C#-Klasse `MFF.Native`, dünne P/Invoke-Wrapper. Keine Entscheidungslogik.
- `config.psd1` — Einstellungen als PowerShell-Data-Datei.
- `MonitorFocusFollow.ps1` — Einstieg: Args (`-Verbose`, `-Once`, `-ConfigPath`), Config laden + validieren, `Add-Type`, Modulimport, Hauptschleife, sauberes Beenden.
- `tests/FocusLogic.Tests.ps1` — Pester-Tests für `FocusLogic.psm1`.
- `Install-Autostart.ps1` / `Uninstall-Autostart.ps1` — Verknüpfung in `shell:startup` anlegen/entfernen.
- `README.md` — Installation, Nutzung, Beenden, Datenschutz, manuelle Testcheckliste.

---

## Task 1: Reine Logik `FocusLogic.psm1`

**Files:**
- Create: `src/FocusLogic.psm1`
- Test: `tests/FocusLogic.Tests.ps1`

**Interfaces:**
- Consumes: nichts.
- Produces:
  - `Get-MonitorIndexForPoint([int]$X, [int]$Y, [object[]]$Monitors) -> [int]` — `$Monitors` ist Array von Objekten mit `.Left,.Top,.Right,.Bottom` (Ganzzahlen; `Right`/`Bottom` exklusiv). Rückgabe: Index des ersten enthaltenden Monitors, sonst `-1`. Kante: linker/oberer Rand gehört zum Monitor, rechter/unterer nicht.
  - `Test-ShouldSwitch([int]$LastIndex, [int]$CurrentIndex, [datetime]$ChangeStartedUtc, [datetime]$NowUtc, [int]$DebounceMs) -> [bool]` — `$true` nur wenn `CurrentIndex -ge 0`, `CurrentIndex -ne LastIndex` und `(NowUtc - ChangeStartedUtc).TotalMilliseconds -ge DebounceMs`.
  - `Test-IsFocusableWindow([string]$ClassName, [string]$ProcessName, [bool]$IsVisibleTopLevel, [string[]]$ExcludeProcesses) -> [bool]` — `$false` wenn nicht sichtbar/Top-Level, wenn `ClassName` in `@('WorkerW','Progman','Shell_TrayWnd','Windows.UI.Core.CoreWindow')`, oder wenn `ProcessName` (case-insensitive, ohne `.exe`) in `ExcludeProcesses`. Sonst `$true`.

- [ ] **Step 1: Failing test schreiben** — `tests/FocusLogic.Tests.ps1`:

```powershell
BeforeAll { Import-Module "$PSScriptRoot/../src/FocusLogic.psm1" -Force }

Describe 'Get-MonitorIndexForPoint' {
    $mons = @(
        [pscustomobject]@{ Left=0;     Top=0; Right=1920; Bottom=1080 }
        [pscustomobject]@{ Left=-1920; Top=0; Right=0;    Bottom=1080 }
    )
    It 'findet Hauptmonitor' { Get-MonitorIndexForPoint 100 100 $mons | Should -Be 0 }
    It 'findet linken Monitor bei negativem X' { Get-MonitorIndexForPoint -50 100 $mons | Should -Be 1 }
    It 'linke Kante gehoert zum Monitor' { Get-MonitorIndexForPoint 0 0 $mons | Should -Be 0 }
    It 'rechte Kante ist exklusiv' { Get-MonitorIndexForPoint 1920 100 $mons | Should -Be -1 }
    It 'ausserhalb -> -1' { Get-MonitorIndexForPoint 5000 5000 $mons | Should -Be -1 }
}

Describe 'Test-ShouldSwitch' {
    $t0 = [datetime]::UtcNow
    It 'gleicher Index -> false' { Test-ShouldSwitch 0 0 $t0 $t0.AddMilliseconds(500) 120 | Should -BeFalse }
    It 'Entprellung nicht abgelaufen -> false' { Test-ShouldSwitch 0 1 $t0 $t0.AddMilliseconds(50) 120 | Should -BeFalse }
    It 'Entprellung abgelaufen -> true' { Test-ShouldSwitch 0 1 $t0 $t0.AddMilliseconds(200) 120 | Should -BeTrue }
    It 'ungueltiger Index -> false' { Test-ShouldSwitch 0 -1 $t0 $t0.AddMilliseconds(200) 120 | Should -BeFalse }
}

Describe 'Test-IsFocusableWindow' {
    It 'Desktop -> false' { Test-IsFocusableWindow 'WorkerW' 'explorer' $true @() | Should -BeFalse }
    It 'Taskleiste -> false' { Test-IsFocusableWindow 'Shell_TrayWnd' 'explorer' $true @() | Should -BeFalse }
    It 'unsichtbar -> false' { Test-IsFocusableWindow 'Chrome_WidgetWin_1' 'chrome' $false @() | Should -BeFalse }
    It 'ausgeschlossener Prozess -> false' { Test-IsFocusableWindow 'X' 'game' $true @('game') | Should -BeFalse }
    It 'normales Fenster -> true' { Test-IsFocusableWindow 'Chrome_WidgetWin_1' 'chrome' $true @() | Should -BeTrue }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag prüfen** — `Invoke-Pester tests/FocusLogic.Tests.ps1` → FAIL (Modul/Funktionen fehlen).

- [ ] **Step 3: `src/FocusLogic.psm1` implementieren:**

```powershell
function Get-MonitorIndexForPoint {
    param([int]$X, [int]$Y, [object[]]$Monitors)
    for ($i = 0; $i -lt $Monitors.Count; $i++) {
        $m = $Monitors[$i]
        if ($X -ge $m.Left -and $X -lt $m.Right -and $Y -ge $m.Top -and $Y -lt $m.Bottom) { return $i }
    }
    return -1
}

function Test-ShouldSwitch {
    param([int]$LastIndex, [int]$CurrentIndex, [datetime]$ChangeStartedUtc, [datetime]$NowUtc, [int]$DebounceMs)
    if ($CurrentIndex -lt 0) { return $false }
    if ($CurrentIndex -eq $LastIndex) { return $false }
    return (($NowUtc - $ChangeStartedUtc).TotalMilliseconds -ge $DebounceMs)
}

function Test-IsFocusableWindow {
    param([string]$ClassName, [string]$ProcessName, [bool]$IsVisibleTopLevel, [string[]]$ExcludeProcesses)
    if (-not $IsVisibleTopLevel) { return $false }
    $blockedClasses = @('WorkerW','Progman','Shell_TrayWnd','Windows.UI.Core.CoreWindow')
    if ($blockedClasses -contains $ClassName) { return $false }
    $pn = ($ProcessName -replace '\.exe$','').ToLowerInvariant()
    foreach ($ex in $ExcludeProcesses) {
        if (($ex -replace '\.exe$','').ToLowerInvariant() -eq $pn) { return $false }
    }
    return $true
}

Export-ModuleMember -Function Get-MonitorIndexForPoint, Test-ShouldSwitch, Test-IsFocusableWindow
```

- [ ] **Step 4: Tests ausführen, grün prüfen** — `Invoke-Pester tests/FocusLogic.Tests.ps1` → alle PASS.

- [ ] **Step 5: Commit** — `git add src/FocusLogic.psm1 tests/FocusLogic.Tests.ps1 && git commit -m "feat: reine Fokus-Logik mit Pester-Tests"`

---

## Task 2: Native-Helfer `src/Native.cs`

**Files:**
- Create: `src/Native.cs`

**Interfaces:**
- Consumes: nichts.
- Produces: C#-Klasse `MFF.Native` (Namespace `MFF`), statische Methoden, geladen via `Add-Type -TypeDefinition (Get-Content src/Native.cs -Raw) -ReferencedAssemblies System.Windows.Forms`:
  - `static int[] GetCursorPos()` -> `{x, y}` in virtuellen Bildschirmkoordinaten.
  - `static IntPtr GetRootWindowAt(int x, int y)` -> `WindowFromPoint` + `GetAncestor(GA_ROOT)`.
  - `static IntPtr GetForeground()` -> `GetForegroundWindow()`.
  - `static string GetClassNameOf(IntPtr h)` (max 256).
  - `static string GetProcessNameOf(IntPtr h)` -> Prozessname ohne Endung, `""` bei Fehler.
  - `static bool IsVisibleTopLevel(IntPtr h)` -> `IsWindow && IsWindowVisible && GetAncestor(GA_ROOT)==h`.
  - `static bool IsForegroundFullscreen()` -> Vordergrundfenster-Rect deckt seinen Monitor komplett und Klasse ist nicht `WorkerW`/`Progman`.
  - `static void SetForegroundForced(IntPtr h, bool raise)` -> `SPI_SETFOREGROUNDLOCKTIMEOUT=0`, `AttachThreadInput`-Trick, `SetForegroundWindow`; wenn `raise` zusätzlich `SetWindowPos(HWND_TOP, SWP_NOMOVE|SWP_NOSIZE)`.
  - `static void MakeDpiAware()` -> `SetProcessDpiAwarenessContext(-4)` mit Fallback `SetProcessDPIAware()`.

- [ ] **Step 1: `src/Native.cs` schreiben** — vollständige C#-Klasse mit den obigen Signaturen, `using System; using System.Text; using System.Runtime.InteropServices; using System.Diagnostics; using System.Windows.Forms;`. P/Invoke: `GetCursorPos`, `WindowFromPoint`, `GetAncestor`, `GetForegroundWindow`, `GetClassName`, `GetWindowThreadProcessId`, `IsWindow`, `IsWindowVisible`, `GetWindowRect`, `SystemParametersInfo`, `AttachThreadInput`, `SetForegroundWindow`, `SetWindowPos`, `SetProcessDpiAwarenessContext`, `SetProcessDPIAware`. `POINT`/`RECT`-Structs. `SetForegroundForced`: aktuellen Vordergrund-Thread und Ziel-Thread via `AttachThreadInput` verbinden, `SetForegroundWindow`, wieder trennen; alles in try/catch, Fehler schlucken.

- [ ] **Step 2: Kompilierung prüfen (manuell)** — Konsole: `Add-Type -TypeDefinition (Get-Content src/Native.cs -Raw) -ReferencedAssemblies System.Windows.Forms; [MFF.Native]::GetCursorPos()` → gibt zwei Zahlen zurück. `[MFF.Native]::GetProcessNameOf([MFF.Native]::GetForeground())` → Prozessname.

- [ ] **Step 3: Commit** — `git add src/Native.cs && git commit -m "feat: C#-Helfer fuer Windows-API (Cursor, Fenster, Fokus)"`

---

## Task 3: Konfiguration `config.psd1`

**Files:**
- Create: `config.psd1`

**Interfaces:**
- Produces: `config.psd1`, ladbar via `Import-PowerShellDataFile`. Schlüssel siehe Global Constraints.

- [ ] **Step 1: `config.psd1` schreiben:**

```powershell
@{
    PollIntervalMs    = 100
    DebounceMs        = 120
    RaiseWindow       = $false
    PauseOnFullscreen = $true
    ExcludeProcesses  = @()
    LogToFile         = $false
    LogPath           = 'focus.log'
}
```

- [ ] **Step 2: Laden prüfen** — Konsole: `Import-PowerShellDataFile ./config.psd1` → Hashtable mit 7 Schlüsseln.

- [ ] **Step 3: Commit** — `git add config.psd1 && git commit -m "feat: Standardkonfiguration"`

---

## Task 4: Einstieg + Hauptschleife `MonitorFocusFollow.ps1`

**Files:**
- Create: `MonitorFocusFollow.ps1`

**Interfaces:**
- Consumes: `FocusLogic.psm1` (Task 1), `MFF.Native` (Task 2), `config.psd1` (Task 3).
- Produces: ausführbares Skript. Parameter: `[switch]$Verbose` (Standard-Common-Parameter reicht — stattdessen `-Log` als eigener Switch), `[switch]$Once` (eine Iteration, für Test), `[string]$ConfigPath = "$PSScriptRoot\config.psd1"`.

- [ ] **Step 1: Skript schreiben** mit dieser Struktur:
  - `param([switch]$Log, [switch]$Once, [string]$ConfigPath = "$PSScriptRoot\config.psd1")`
  - `$defaults` Hashtable (wie config.psd1). Config laden: wenn Datei existiert `Import-PowerShellDataFile`, sonst Warnung; fehlende/falsch-typige Schlüssel aus `$defaults` ergänzen. Ergebnis `$cfg`.
  - `function Write-FocusLog([string]$msg)` — schreibt `"{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg`; auf Konsole wenn `$Log`, in Datei wenn `$cfg.LogToFile` (Pfad relativ zu `$PSScriptRoot`).
  - `Add-Type -TypeDefinition (Get-Content "$PSScriptRoot\src\Native.cs" -Raw) -ReferencedAssemblies System.Windows.Forms` in try/catch → bei Fehler `Write-FocusLog`, `exit 1`.
  - `Import-Module "$PSScriptRoot\src\FocusLogic.psm1" -Force`
  - `[MFF.Native]::MakeDpiAware()`
  - `Add-Type -AssemblyName System.Windows.Forms`
  - `function Get-MonitorRects` → `[System.Windows.Forms.Screen]::AllScreens | % { [pscustomobject]@{ Left=$_.Bounds.Left; Top=$_.Bounds.Top; Right=$_.Bounds.Right; Bottom=$_.Bounds.Bottom } }`
  - Zustand: `$lastIndex = -1`, `$changeStartedUtc = [datetime]::UtcNow`, `$pendingIndex = -1`.
  - `try { while ($true) { ... ; if ($Once) { break }; Start-Sleep -Milliseconds $cfg.PollIntervalMs } } finally { Write-FocusLog 'beendet' }`
  - Schleifenkörper:
    ```powershell
    $mons = Get-MonitorRects
    $p = [MFF.Native]::GetCursorPos()
    $idx = Get-MonitorIndexForPoint $p[0] $p[1] $mons
    if ($idx -ge 0 -and $idx -ne $lastIndex -and $idx -ne $pendingIndex) {
        $pendingIndex = $idx; $changeStartedUtc = [datetime]::UtcNow
    }
    if ($pendingIndex -ge 0 -and (Test-ShouldSwitch $lastIndex $pendingIndex $changeStartedUtc ([datetime]::UtcNow) $cfg.DebounceMs)) {
        $p2 = [MFF.Native]::GetCursorPos()
        $nowIdx = Get-MonitorIndexForPoint $p2[0] $p2[1] $mons
        if ($nowIdx -eq $pendingIndex) {
            if (-not ($cfg.PauseOnFullscreen -and [MFF.Native]::IsForegroundFullscreen())) {
                $h = [MFF.Native]::GetRootWindowAt($p2[0], $p2[1])
                if ($h -ne [IntPtr]::Zero -and $h -ne [MFF.Native]::GetForeground()) {
                    $cls = [MFF.Native]::GetClassNameOf($h)
                    $proc = [MFF.Native]::GetProcessNameOf($h)
                    $vis = [MFF.Native]::IsVisibleTopLevel($h)
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
    ```
  - Ganzer Körper in `try/catch { Write-FocusLog ("Fehler: " + $_.Exception.Message) }` damit die Schleife weiterläuft.

- [ ] **Step 2: `-Once` manuell testen** — `powershell -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Once -Log` → läuft eine Iteration ohne Fehler, gibt ggf. Log aus.

- [ ] **Step 3: Dauerbetrieb manuell testen** — ohne `-Once` starten, Maus über die Monitorgrenze bewegen → Fenster drüben wird aktiv; Bewegung innerhalb eines Monitors → nichts. `Strg+C` → "beendet".

- [ ] **Step 4: Commit** — `git add MonitorFocusFollow.ps1 && git commit -m "feat: Hauptschleife mit Monitorwechsel-Erkennung"`

---

## Task 5: Autostart-Skripte

**Files:**
- Create: `Install-Autostart.ps1`, `Uninstall-Autostart.ps1`

**Interfaces:**
- Consumes: `MonitorFocusFollow.ps1`.
- Produces: Verknüpfung `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\MonitorFocusFollow.lnk`.

- [ ] **Step 1: `Install-Autostart.ps1` schreiben:**

```powershell
$ErrorActionPreference = 'Stop'
$script  = Join-Path $PSScriptRoot 'MonitorFocusFollow.ps1'
$startup = [Environment]::GetFolderPath('Startup')
$lnk     = Join-Path $startup 'MonitorFocusFollow.lnk'
$w = New-Object -ComObject WScript.Shell
$s = $w.CreateShortcut($lnk)
$s.TargetPath = (Get-Command powershell.exe).Source
$s.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle = 7
$s.Description  = 'monitor-focus-follow: Fokus folgt der Maus beim Monitorwechsel'
$s.Save()
Write-Host "Autostart eingerichtet: $lnk"
Write-Host "Startet beim naechsten Anmelden. Jetzt starten:"
Write-Host "  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-ExecutionPolicy Bypass -File `"$script`"'"
```

- [ ] **Step 2: `Uninstall-Autostart.ps1` schreiben** — `$lnk` wie oben; wenn vorhanden `Remove-Item $lnk`, Meldung "Autostart entfernt" bzw. "war nicht eingerichtet". Hinweis ausgeben, dass ein bereits laufender Prozess über den Task-Manager beendet werden muss.

- [ ] **Step 3: Manuell testen** — `Install-Autostart.ps1` ausführen → `.lnk` existiert im Startup-Ordner. `Uninstall-Autostart.ps1` → weg.

- [ ] **Step 4: Commit** — `git add Install-Autostart.ps1 Uninstall-Autostart.ps1 && git commit -m "feat: Autostart einrichten/entfernen"`

---

## Task 6: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: `README.md` schreiben** (Deutsch) mit Abschnitten:
  - **Was es macht** — 2 Sätze.
  - **Voraussetzungen** — Windows, PowerShell 5.1, für Tests Pester 5 (`Install-Module Pester`).
  - **Installation** — Repo-Ordner ablegen, `powershell -ExecutionPolicy Bypass -File .\Install-Autostart.ps1`, ab-/anmelden oder den ausgegebenen `Start-Process`-Befehl nutzen.
  - **Beenden** — Task-Manager → Reiter „Details" → Spalte „Befehlszeile" einblenden → `powershell.exe`-Eintrag mit `MonitorFocusFollow.ps1` → „Task beenden". Autostart dauerhaft weg: `Uninstall-Autostart.ps1`.
  - **Konfiguration** — Tabelle der `config.psd1`-Schlüssel (aus der Spec).
  - **Zum Testen/Debuggen** — `powershell -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Log`.
  - **Tests** — `Invoke-Pester .\tests\FocusLogic.Tests.ps1`.
  - **Datenschutz** — aus der Spec: alles lokal, kein Netzwerk, kein Tastatur-Mitschnitt, standardmäßig keine Logdatei; Logdatei enthält nur Zeit/Monitor/Prozessname.
  - **Manuelle Testcheckliste** — die 5 Punkte aus der Spec.
  - **Zukunftsidee** — Multi-Seat (2 Mäuse/Tastaturen), nicht in v1; Verweis auf die Spec.

- [ ] **Step 2: Commit** — `git add README.md && git commit -m "docs: README mit Installation, Beenden, Datenschutz"`

---

## Self-Review

**Spec coverage:**
- Verhalten (Poll, Monitorwechsel, Entprellung, Filter, Fullscreen-Pause, Raise) → Task 1 + Task 4. ✓
- Native-Aufrufe inkl. Foreground-Lock + DPI → Task 2. ✓
- Config + Defaults + Fallback → Task 3 + Task 4 Step 1. ✓
- Fehlerbehandlung (Add-Type-Fail → exit 1; API-Fehler → weiterlaufen; Ctrl+C → finally) → Task 4. ✓
- Datenschutz (kein Netz, kein Keylog, keine Titel im Log) → Task 4 (Write-FocusLog loggt nur Prozessname) + Task 6. ✓
- Autostart versteckt / Beenden per Task-Manager → Task 5 + Task 6. ✓
- Pester-Tests (Monitorindex inkl. negativer Koords, Entprellung, Filter) → Task 1. ✓
- Multi-Seat als Nicht-Ziel dokumentiert → Task 6 + Spec. ✓

**Placeholder scan:** keine TBD/TODO; alle Code-Schritte enthalten echten Code. ✓

**Type consistency:** `Get-MonitorIndexForPoint`, `Test-ShouldSwitch`, `Test-IsFocusableWindow` identisch in Task 1 und Task 4. `MFF.Native`-Methoden in Task 2 und Task 4 identisch benannt (`GetCursorPos`, `GetRootWindowAt`, `GetForeground`, `GetClassNameOf`, `GetProcessNameOf`, `IsVisibleTopLevel`, `IsForegroundFullscreen`, `SetForegroundForced`, `MakeDpiAware`). ✓
