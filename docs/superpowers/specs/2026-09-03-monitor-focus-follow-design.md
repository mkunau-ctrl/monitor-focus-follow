# Design: monitor-focus-follow

**Datum:** 2026-09-03
**Status:** Entwurf, vom Auftraggeber freigegeben (Verhalten + Ansatz B)

## Problem

Bei zwei Monitoren wird beim Wechsel mit der Maus auf den anderen Bildschirm
das dortige Fenster erst dann aktiv, wenn man klickt. Das Tippen auf Tastatur
landet bis dahin im Fenster des alten Monitors. Das nervt im Alltag.

Windows hat eine eingebaute Funktion (*active window tracking*,
`SPI_SETACTIVEWINDOWTRACKING`), die aber zu aggressiv ist: **jedes** Fenster
unter dem Mauszeiger bekommt sofort den Fokus, auch auf demselben Monitor.

## Ziel (v1)

Ein kleines Programm, das den Fokus **nur beim Überqueren der Monitorgrenze**
auf das Fenster **direkt unter dem Mauszeiger** setzt. Innerhalb eines
Monitors passiert nichts.

### Nicht-Ziele (v1)

- Kein Tray-Icon, keine GUI.
- Kein Pausieren/Steuern zur Laufzeit außer Beenden.
- **Multi-Seat** (2 Mäuse + 2 Tastaturen, je fest einem Monitor zugeordnet) —
  ausdrücklich Zukunftsidee, siehe unten. Windows hat nur einen Systemcursor;
  das ist ein eigenes, deutlich größeres Projekt.

## Betrieb

- Startet automatisch mit Windows, **versteckt** (kein Fenster).
  Autostart-Verknüpfung in `shell:startup`, gestartet mit
  `powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File <pfad>`.
- **Beenden nur über den Task-Manager** (Prozess `powershell.exe`; im README
  wird beschrieben, wie man den richtigen Prozess über die Befehlszeilen-Spalte
  erkennt).
- Manueller Start in der Konsole ist möglich (`-Verbose` für Log-Ausgaben),
  aber nur zum Testen/Debuggen gedacht — kein ausgebautes Feature.

## Ansatz

**Ansatz B:** PowerShell für Schleife, Konfiguration und Logging; ein kleiner
eingebetteter C#-Helfer (per `Add-Type` beim Start kompiliert) für die
heiklen Windows-API-Aufrufe — vor allem `SetForegroundWindow` inklusive des
Foreground-Lock-Tricks. Kein .NET-SDK nötig, kein Build-Schritt, eine
Projektstruktur zum Lesen und Anpassen.

Verworfen:
- **A (reines PowerShell):** `SetForegroundWindow`-Entsperrung in reinem
  PowerShell ist umständlich und fragil.
- **C (eigenständige .exe):** robuster und besserer Startpunkt für Multi-Seat,
  aber braucht .NET-SDK und mehr Struktur. Wechsel zu C, wenn Multi-Seat
  konkret wird.

## Dateien

```
monitor-focus-follow/
├─ MonitorFocusFollow.ps1        # Einstieg: Args, Config laden, Native kompilieren, Hauptschleife
├─ config.psd1                   # Einstellungen (siehe unten)
├─ src/
│  ├─ Native.cs                  # eingebetteter C#-Helfer (P/Invoke-Wrapper, keine Logik)
│  └─ FocusLogic.psm1            # reine Logik-Funktionen, keine Windows-API → testbar
├─ tests/
│  └─ FocusLogic.Tests.ps1       # Pester-Tests
├─ Install-Autostart.ps1         # legt versteckte Verknüpfung in shell:startup an
├─ Uninstall-Autostart.ps1       # entfernt die Verknüpfung
├─ README.md                     # deutsch: Installation, Nutzung, Beenden, Datenschutz
└─ docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md
```

## Verhalten im Detail

Hauptschleife, Takt `PollIntervalMs` (Standard 100 ms):

1. Mausposition holen (`GetCursorPos`).
2. Monitor-Index für diesen Punkt bestimmen
   (`System.Windows.Forms.Screen` / Rechteck-Vergleich in `FocusLogic`).
3. Vergleich mit „letztem Monitor-Index":
   - gleich → nichts tun.
   - geändert → Zeitstempel merken, Zustand „Wechsel angestoßen".
4. Ist ein Wechsel angestoßen und sind seither `DebounceMs` (Standard 120 ms)
   vergangen:
   - Mausposition erneut holen; liegt sie noch auf dem neuen Monitor?
     Wenn nein → Wechsel verwerfen.
   - Oberstes Fenster unter dem Mauszeiger holen
     (`WindowFromPoint` → `GetAncestor(GA_ROOT)`).
   - Filter `Test-IsFocusableWindow`: kein Desktop
     (`WorkerW`/`Progman`), keine Taskleiste (`Shell_TrayWnd`),
     Prozess nicht in `ExcludeProcesses`, Handle ist ein sichtbares
     Top-Level-Fenster.
   - `PauseOnFullscreen` (Standard an): steht im Vordergrund gerade eine
     Vollbild-App (Fenster-Rechteck == Monitor-Rechteck und nicht Desktop)?
     Dann Wechsel verwerfen.
   - Fenster bereits im Vordergrund? Dann nichts tun.
   - Sonst: `SetForegroundWindowForced(hWnd)` aufrufen.
     `RaiseWindow` (Standard aus): nur wenn `$true` zusätzlich in der
     Z-Reihenfolge nach vorne holen.
   - „letzter Monitor-Index" auf den neuen Wert setzen, Wechselzustand
     zurücksetzen.
5. Log (Konsole, nur bei `-Verbose`; Datei nur wenn `LogToFile`).
6. `Start-Sleep -Milliseconds PollIntervalMs`.

## Datenfluss

```
Autostart / Konsole
  → MonitorFocusFollow.ps1
      → config.psd1 laden (fehlt/ungültig → eingebaute Defaults + Warnung)
      → Add-Type src/Native.cs   (Fehler → Meldung, Exit 1)
      → Import-Module src/FocusLogic.psm1
      → Schleife:
          [Native]::GetCursorPos()                     → Point
          FocusLogic\Get-MonitorIndexForPoint          → int
          FocusLogic\Test-ShouldSwitch (alt,neu,zeit)  → bool
          [Native]::GetRootWindowAt(point)             → IntPtr
          FocusLogic\Test-IsFocusableWindow            → bool
          [Native]::IsForegroundFullscreen()           → bool
          [Native]::SetForegroundWindowForced(hWnd)
```

**Trennung:**
- `FocusLogic.psm1` = reine Funktionen (Punkt-in-Rechteck, Entprell-
  Entscheidung, Fenster-Filter anhand von Klassen-/Prozessname +
  Ausschlussliste). Keine Windows-API. Vollständig mit Pester testbar.
- `Native.cs` = dünne Wrapper, keine Entscheidungslogik.
- `MonitorFocusFollow.ps1` = Verdrahtung, Schleife, Logging, sauberes Beenden.

## Native-Helfer (`src/Native.cs`, Klasse `MFF.Native`)

Statische Methoden:

- `Point GetCursorPos()` — Mausposition (virtuelle Bildschirmkoordinaten).
- `IntPtr GetRootWindowAt(int x, int y)` — `WindowFromPoint` +
  `GetAncestor(GA_ROOT)`.
- `bool IsForegroundFullscreen()` — Vordergrundfenster füllt kompletten
  Monitor und ist nicht die Shell.
- `IntPtr GetForegroundWindow()` — für „schon im Vordergrund?"-Prüfung.
- `uint GetProcessIdOfWindow(IntPtr hWnd)` — für Prozessname-Filter.
- `string GetWindowClassName(IntPtr hWnd)`.
- `bool IsWindowVisibleTopLevel(IntPtr hWnd)`.
- `void SetForegroundWindowForced(IntPtr hWnd)` — Foreground-Lock umgehen:
  `SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0)` bzw.
  `AttachThreadInput`-Trick, dann `SetForegroundWindow`; optional
  `SetWindowPos(HWND_TOP)` wenn `RaiseWindow`.
- Beim Laden: Prozess als DPI-aware markieren
  (`SetProcessDpiAwarenessContext`, Fallback `SetProcessDPIAware`), damit
  Monitorkoordinaten bei skalierten Displays stimmen.

## Konfiguration (`config.psd1`)

| Schlüssel | Standard | Zweck |
|---|---|---|
| `PollIntervalMs` | `100` | Abfragetakt der Schleife |
| `DebounceMs` | `120` | Wartezeit nach Grenzübertritt, bevor der Fokus gesetzt wird |
| `RaiseWindow` | `$false` | Fenster zusätzlich in der Z-Reihenfolge nach vorne holen |
| `PauseOnFullscreen` | `$true` | kein Fokuswechsel, wenn vorne eine Vollbild-App läuft |
| `ExcludeProcesses` | `@()` | Prozessnamen (ohne `.exe`), die nie fokussiert werden |
| `LogToFile` | `$false` | Logdatei schreiben |
| `LogPath` | `"$PSScriptRoot\focus.log"` | Pfad der Logdatei |

Fehlt die Datei oder ist ein Wert ungültig → eingebaute Standardwerte,
Warnung ins Log.

## Fehlerbehandlung

- `Add-Type` schlägt fehl → verständliche Meldung („C#-Helfer konnte nicht
  kompiliert werden"), `exit 1`.
- Einzelne API-Aufrufe in `try/catch` innerhalb der Schleife: Fehler wird
  geloggt (bei `-Verbose`/`LogToFile`), Schleife läuft weiter. Ein
  verschwundenes Fenster-Handle darf das Programm nicht beenden.
- `Ctrl+C` / Prozessende → `finally`-Block, Log „beendet".
- Ungültige/nicht mehr existierende `hWnd` → übersprungen.
- Nur ein Monitor angeschlossen → Programm läuft, tut aber nie etwas
  (kein Grenzübertritt möglich).

## Datenschutz

- Komplett lokal, **keine Netzwerkverbindung**, keine Telemetrie.
- Standardmäßig **keine Logdatei**. Konsolen-Log nur bei manuellem Start
  mit `-Verbose`.
- Bei aktiviertem `LogToFile`: nur Zeitstempel, Monitor-Index und
  Prozessname des fokussierten Fensters — **keine Fenstertitel, keine
  Fensterinhalte, keine Tastatureingaben**.
- Das Programm liest Tastatureingaben *nicht* mit; es reagiert nur auf die
  Mausposition und aktiviert Fenster.
- Wird im README unter „Datenschutz" dokumentiert.

## Testen

**Pester** (`tests/FocusLogic.Tests.ps1`), gegen `FocusLogic.psm1`:

- `Get-MonitorIndexForPoint`:
  - Punkt innerhalb Monitor 0 / Monitor 1.
  - Punkt exakt auf der gemeinsamen Kante (definierte Zuordnung).
  - Negative X-Koordinaten (zweiter Monitor links vom Hauptmonitor).
  - Punkt außerhalb aller Monitore → definierter Rückgabewert (z. B. -1).
- `Test-ShouldSwitch`:
  - gleicher Index → `$false`.
  - geänderter Index, Entprellzeit noch nicht abgelaufen → `$false`.
  - geänderter Index, Entprellzeit abgelaufen → `$true`.
- `Test-IsFocusableWindow`:
  - Desktop-Klassen (`WorkerW`, `Progman`) → `$false`.
  - Taskleiste (`Shell_TrayWnd`) → `$false`.
  - Prozess in `ExcludeProcesses` → `$false`.
  - normales sichtbares Fenster → `$true`.

**Manuelle Checkliste** (im README):

1. Maus langsam über die Monitorgrenze → Fenster auf dem Zielmonitor wird
   aktiv, ohne Klick.
2. Maus innerhalb eines Monitors zwischen Fenstern bewegen → Fokus bleibt.
3. Vollbild-Spiel/-Video auf einem Monitor, Maus kurz rüber und zurück →
   kein Fokusklau (bei `PauseOnFullscreen = $true`).
4. `Ctrl+C` im Konsolenbetrieb → sauberes Beenden.
5. Nach `Install-Autostart.ps1` + Neuanmeldung → Programm läuft, im
   Task-Manager beendbar.

Der Native-Teil (`Native.cs`) wird nicht unit-getestet (dünne Wrapper),
nur über die manuelle Checkliste.

## Aenderung v1.1 (2026-09-04): Fokus folgt dem Fenster, nicht nur dem Monitor

**Anlass:** Im Splitscreen auf einem Monitor (z. B. Browser links, WhatsApp
rechts) und beim App-Wechsel im Splitscreen soll der Fokus ebenfalls der
Maus folgen - nicht nur beim Monitorwechsel.

**Aenderung:** Der Ausloeser ist nicht mehr "Monitor-Index geaendert",
sondern **"oberstes Fenster (GA_ROOT) unter dem Mauszeiger geaendert"**.
Das deckt Splitscreen und Monitorwechsel gemeinsam ab. Bewegung innerhalb
desselben Fensters loest weiterhin nichts aus.

**Neue Schutzregel:** Solange eine Maustaste gedrueckt ist (Markieren per
Ziehen, Fenster verschieben), wird kein Fokuswechsel ausgeloest
(`PauseWhileMouseDown`, Standard an).

**Auswirkungen auf die Bausteine:**

- `src/FocusLogic.psm1`: `Test-ShouldSwitch` (Monitor-basiert) und
  `Get-MonitorIndexForPoint` entfallen. Neu:
  `Test-ShouldSwitchWindow([long]$LastHwnd, [long]$CurrentHwnd,
  [datetime]$ChangeStartedUtc, [datetime]$NowUtc, [int]$DebounceMs,
  [bool]$MouseButtonDown) -> [bool]` - `$true` nur wenn keine Maustaste
  gedrueckt, Handle gueltig (nicht 0), verschieden vom letzten und
  Entprellzeit abgelaufen. `Test-IsFocusableWindow` unveraendert.
- `src/Native.cs`: neu `static bool AnyMouseButtonDown()` (prueft
  VK_LBUTTON/RBUTTON/MBUTTON via `GetAsyncKeyState`). `Screen.FromPoint`
  wird nicht mehr gebraucht, `Screen.FromHandle` (in
  `IsForegroundFullscreen`) bleibt.
- `MonitorFocusFollow.ps1`: Schleife merkt sich `lastHwnd`/`pendingHwnd`
  (als `[long]`) statt Monitor-Indizes. Nach der Entprellung wird
  geprueft, ob der Zeiger noch ueber demselben Fenster steht, dann
  Fullscreen-/Vordergrund-/Fokusfilter wie bisher.
- `config.psd1`: neuer Schluessel `PauseWhileMouseDown = $true`.
- Tests: `Test-ShouldSwitchWindow` (gleiches/anderes Fenster, Entprellung,
  Maustaste gedrueckt -> kein Wechsel, Handle 0 -> kein Wechsel) und
  `Test-IsFocusableWindow` wie bisher. Monitor-Index-Tests entfallen.

**Nicht enthalten (eigenes, groesseres Thema):** Fokus auf einzelne
Eingabefelder *innerhalb* einer Seite (z. B. zwei Suchfelder auf einer
Webseite). Windows sieht dort nur ein Fensterhandle; das saubere Setzen
des Feld-Fokus wuerde einen simulierten Klick an der Mausposition
erfordern (Risiko: loest ungewollt Buttons/Links aus).

## Aenderung v1.2 (2026-09-04): fuenf kleine Verbesserungen

Siehe `docs/superpowers/plans/2026-09-04-verbesserungen-v1.2.md` und
`docs/PROJEKT-LOG.md`. Kurz:

1. **Einmal-Instanz-Sperre** in `MonitorFocusFollow.ps1` (benannter
   `System.Threading.Mutex` `MonitorFocusFollow_SingleInstance`): zweite
   Instanz beendet sich sofort mit Exit 0.
2. **Erweiterte Fensterfilter:** `Test-IsFocusableWindow` bekommt den
   Parameter `[bool]$HasAcceptableExStyle` (aus
   `Native.HasAcceptableExStyle`, prueft `WS_EX_TOOLWINDOW` /
   `WS_EX_NOACTIVATE`). `$blockedClasses` erweitert um
   `Shell_SecondaryTrayWnd`, `XamlExplorerHostIslandWindow`,
   `ForegroundStaging`, `MultitaskingViewFrame`, `TaskListThumbnailWnd`,
   `NotifyIconOverflowWindow`, `TopLevelWindowForOverflowXamlIsland`,
   `Windows.UI.Composition.DesktopWindowContentBridge`.
3. **`crash.log`** neben dem Skript (immer geschrieben): faengt Startfehler
   und unerwarteten Abbruch der Hauptschleife ab.
4. **Pause-Hotkey** `Strg+Alt+<ToggleKey>` (Config `EnableToggleHotkey`,
   `ToggleKey` aus Pause/ScrollLock/F9-F12). `Native.IsKeyDown(vk)` +
   Flankenerkennung in der Schleife; Zustand `$paused` ueberspringt die
   Fokus-Logik.
5. **Vollbild-Erkennung:** `Native.IsForegroundFullscreen()` fragt
   zusaetzlich `SHQueryUserNotificationState` ab (QUNS_BUSY /
   QUNS_RUNNING_D3D_FULL_SCREEN / QUNS_PRESENTATION_MODE).

## Aenderung v1.4 (2026-09-08): Autostart als geplante Aufgabe

Siehe `docs/PROJEKT-LOG.md` (Eintrag 2026-09-08). Kurz:

1. **`Install-Autostart.ps1`** legt statt einer `.lnk` in `shell:startup` eine
   geplante Aufgabe `MonitorFocusFollow` an: Ausloeser „bei Anmeldung" +
   15 s Verzoegerung, `Hidden`, kein Zeitlimit, `RestartCount 3` /
   `RestartInterval 1 min`, `MultipleInstances IgnoreNew`, laeuft im
   Akkubetrieb. Principal: aktueller Benutzer, `LogonType Interactive`,
   `RunLevel Limited` → **kein Admin, kein gespeichertes Passwort**. Das
   Skript entfernt zusaetzlich eine alte `.lnk` samt
   `StartupApproved`-Registry-Wert und startet das Programm sofort.
2. **`Uninstall-Autostart.ps1`** / **`usb/Deinstallieren.ps1`**:
   `Unregister-ScheduledTask` (plus alte `.lnk`, falls vorhanden).
3. **`Native.HideConsoleWindow()`** (neu): `GetConsoleWindow` + `ShowWindow
   SW_HIDE`. `MonitorFocusFollow.ps1` ruft es direkt nach dem Kompilieren
   auf, wenn **nicht** `-Log` gesetzt ist — gegen kurzes Fenster-Aufblitzen.

**Ausloeser:** Autostart-Ordner-Eintraege lassen sich von „Aufraeum-"/
Optimizer-Tools per Haeckchen deaktivieren; genau das war passiert. Eine
geplante Aufgabe ist dagegen geschuetzt.

## Zukunftsidee: Multi-Seat (nicht v1)

Ziel: zwei Mäuse + zwei Tastaturen, jede fest einem Monitor zugeordnet,
sodass zwei Personen unabhängig arbeiten können. Auf Windows nicht mit
Bordmitteln möglich (ein Systemcursor, ein Fokus). Realistische Wege wären
Raw-Input pro Gerät + eigener Fenster-Manager oder Fremdsoftware. Eigenes
Projekt, eigener Design-Prozess — wird gestartet, wenn es konkret wird.
Bis dahin bleibt v1 bewusst schlank.
