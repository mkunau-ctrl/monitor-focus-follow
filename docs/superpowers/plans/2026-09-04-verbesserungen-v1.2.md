# Verbesserungen v1.2 – Implementierungsplan

**Spec:** `docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md`
(Abschnitt „Änderung v1.1" + dieser Plan)

**Ziel:** Fünf kleine, unabhängige Verbesserungen an der laufenden v1.1.

## Global Constraints

- Windows PowerShell 5.1, keine PS-7-Syntax.
- `Add-Type` für `src/Native.cs`: `-ReferencedAssemblies System.Windows.Forms, System.Drawing`.
- Alle sichtbaren Texte / Doku auf Deutsch.
- Kein Netzwerk, kein Tastatur-Mitschnitt. Der Hotkey liest nur den
  Tastenzustand von Ctrl/Alt/Umschalttaste + einer Funktionstaste, kein
  Logging von Eingaben.
- Nach Umsetzung: `docs/PROJEKT-LOG.md` und `README.md` aktualisieren.

---

## Task 1: Einmal-Instanz-Sperre (Mutex)

**Datei:** `MonitorFocusFollow.ps1`

Ganz am Anfang (nach `param`): benannten Mutex `MonitorFocusFollow_SingleInstance`
anlegen. `WaitOne(0)` – wenn `$false`, läuft schon eine Instanz →
`Write-FocusLog "bereits aktiv – diese Instanz beendet sich"` und `exit 0`.
Mutex-Referenz in einer Skriptvariablen halten, im `finally` `ReleaseMutex()`
+ `Dispose()`.

**Test:** zweimal `-Once` hintereinander startet normal; zwei Dauerläufe
gleichzeitig → der zweite beendet sich sofort (im Log sichtbar).

---

## Task 2: Bessere Fensterfilter

**Dateien:** `src/Native.cs`, `src/FocusLogic.psm1`, `tests/FocusLogic.Tests.ps1`, `MonitorFocusFollow.ps1`

**Native.cs:** neue Methode
`static bool HasAcceptableExStyle(IntPtr h)` – liest `GetWindowLong(h, GWL_EXSTYLE)`;
`$false`, wenn `WS_EX_TOOLWINDOW (0x80)` oder `WS_EX_NOACTIVATE (0x08000000)`
gesetzt ist. Bei Fehler `$true` (nicht fälschlich blockieren).

**FocusLogic.psm1:** `Test-IsFocusableWindow` bekommt Parameter
`[bool]$HasAcceptableExStyle` (nach `$IsVisibleTopLevel`). `$false` →
nicht fokussierbar. Die Liste `$blockedClasses` erweitern um:
`'Shell_SecondaryTrayWnd'` (Taskleiste auf dem 2. Monitor!),
`'XamlExplorerHostIslandWindow'`, `'ForegroundStaging'`,
`'MultitaskingViewFrame'`, `'TaskListThumbnailWnd'`,
`'NotifyIconOverflowWindow'`, `'TopLevelWindowForOverflowXamlIsland'`,
`'Windows.UI.Composition.DesktopWindowContentBridge'`.

**MonitorFocusFollow.ps1:** in der Schleife `[MFF.Native]::HasAcceptableExStyle($h2ptr)`
ermitteln und an `Test-IsFocusableWindow` übergeben.

**Tests:** je ein Fall für `Shell_SecondaryTrayWnd` → `$false` und für
`HasAcceptableExStyle = $false` → `$false`; bestehende Fälle um das neue
Argument `$true` ergänzen.

---

## Task 3: Absturz-Log beim Start

**Datei:** `MonitorFocusFollow.ps1`

`function Write-CrashLog([string]$msg)` – schreibt **immer** (unabhängig von
`LogToFile`) mit Zeitstempel nach `"$PSScriptRoot\crash.log"`.

Den Startteil (Config laden, `Add-Type`, `Import-Module`, `MakeDpiAware`) in
ein `try`/`catch` fassen; im `catch` `Write-CrashLog` mit voller
Fehlermeldung + StackTrace, dann `exit 1`. Zusätzlich die gesamte
Hauptschleife in `try`/`catch`, dessen `catch` (unerwarteter Abbruch des
ganzen Skripts, nicht die schon vorhandene Pro-Runde-Behandlung) ebenfalls
`Write-CrashLog` aufruft. `crash.log` in `.gitignore` aufnehmen.

**Test:** Skript mit absichtlich kaputtem `-ConfigPath` auf eine
nicht-`.psd1`-Datei, die ungültiges PowerShell enthält → Programm läuft mit
Defaults weiter (kein Crash). `Add-Type`-Fehler lässt sich schwer erzwingen;
stattdessen manuell prüfen, dass `Write-CrashLog` eine Datei anlegt (kurzer
Direktaufruf).

---

## Task 4: Pause-Hotkey (Ctrl+Alt+<Taste>)

**Dateien:** `src/Native.cs`, `MonitorFocusFollow.ps1`, `config.psd1`

**Native.cs:** `static bool IsKeyDown(int vk)` – `(GetAsyncKeyState(vk) & 0x8000) != 0`.

**config.psd1:** neu
`EnableToggleHotkey = $true` und `ToggleKey = 'Pause'`
(erlaubte Werte: `Pause`, `ScrollLock`, `F9`, `F10`, `F11`, `F12`).

**MonitorFocusFollow.ps1:**
- Map Name→VK: `Pause=0x13, ScrollLock=0x91, F9=0x78, F10=0x79, F11=0x7A, F12=0x7B`.
  Unbekannter Wert → Warnung + `Pause`.
- Modifikatoren fest: `VK_CONTROL=0x11`, `VK_MENU=0x12` (Alt).
- Zustandsvariablen `$paused = $false`, `$hotkeyWasDown = $false`.
- In der Schleife, vor der Fokus-Logik: wenn `EnableToggleHotkey` und
  Ctrl **und** Alt **und** ToggleKey gedrückt → Flankenerkennung
  (`-not $hotkeyWasDown`) → `$paused = -not $paused`,
  `Write-FocusLog ("Hotkey: " + $(if($paused){'pausiert'}else{'aktiv'}))`.
  `$hotkeyWasDown` aktualisieren.
- Wenn `$paused` → Rest der Fokus-Logik in dieser Runde überspringen
  (Schleife läuft weiter, damit man wieder aktivieren kann).

**Test:** Logik der Flankenerkennung ist im Skript, nicht im Modul – manuell:
Programm mit `-Log` starten, Ctrl+Alt+Pause → „pausiert", nochmal → „aktiv".

---

## Task 5 (= Idee 7): Zuverlässigere Vollbild-Erkennung

**Datei:** `src/Native.cs`

In `IsForegroundFullscreen()` zusätzlich `SHQueryUserNotificationState`
(shell32) abfragen. Rückgabe `QUNS_BUSY (2)`, `QUNS_RUNNING_D3D_FULL_SCREEN (3)`
oder `QUNS_PRESENTATION_MODE (4)` → `true`. Ergebnis ist `true`, wenn die
Shell-Abfrage **oder** der bisherige Rechteck-Vergleich zutrifft. Bei Fehler
der Shell-Abfrage nur den Rechteck-Vergleich verwenden.

**Test:** manuell – Vollbild-Video (YouTube F) auf einem Monitor, Maus kurz
rüber → kein Fokuswechsel; Log zeigt keinen „Fokus ->"-Eintrag.

---

## Self-Review

- Idee 1 → Task 1. Idee 2 → Task 2. Idee 3 → Task 3. Idee 4 → Task 4.
  Idee 7 → Task 5. ✓
- Keine Platzhalter; alle VK-Codes und Klassennamen konkret genannt. ✓
- `Test-IsFocusableWindow`-Signatur in Task 2 (Modul), Task 2
  (Aufruf im Skript) und den Tests konsistent:
  `(ClassName, ProcessName, IsVisibleTopLevel, HasAcceptableExStyle, ExcludeProcesses)`. ✓
