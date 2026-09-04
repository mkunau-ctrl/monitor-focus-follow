# Dateiübersicht – welche Datei ist für was zuständig

Kurzer Wegweiser durch das Projekt. Details zur Funktionsweise stehen in
`docs/superpowers/specs/`, der Verlauf in `docs/PROJEKT-LOG.md`.

## Das eigentliche Programm

| Datei | Zuständig für |
|---|---|
| `MonitorFocusFollow.ps1` | Hauptprogramm. Endlosschleife: Mausposition abfragen → prüfen, ob ein anderes Fenster darunter liegt → nach kurzer Wartezeit (Entprellung) den Tastaturfokus dorthin setzen. Lädt die Config, kompiliert den C#-Helfer, verarbeitet den Pause-Hotkey, schreibt Logs, sorgt für die Einmal-Instanz-Sperre und das Absturz-Log. |
| `src/FocusLogic.psm1` | Reine Entscheidungslogik **ohne** Windows-Aufrufe: `Test-ShouldSwitchWindow` (anderes Fenster? Entprellzeit um? Maustaste gedrückt?) und `Test-IsFocusableWindow` (darf dieses Fenster Fokus bekommen – kein Desktop, keine Taskleiste, kein Tool-Fenster …). Ausgelagert, damit es mit Pester testbar ist. |
| `src/Native.cs` | Alle echten Windows-API-Aufrufe (C#, wird beim Start per `Add-Type` kompiliert): Mausposition, Fenster unter dem Zeiger, Fenster aktivieren (inkl. Umgehung der Vordergrund-Sperre), Maustasten-/Tastenzustand, Vollbild-Erkennung, DPI-Awareness. Enthält keine Entscheidungslogik. |
| `config.psd1` | Einstellungen: `PollIntervalMs`, `DebounceMs`, `RaiseWindow`, `PauseOnFullscreen`, `PauseWhileMouseDown`, `EnableToggleHotkey`, `ToggleKey`, `ExcludeProcesses`, `LogToFile`, `LogPath`. |

## Installation & Autostart (auf einem PC)

| Datei | Zuständig für |
|---|---|
| `Install-Autostart.ps1` | Legt die versteckte Autostart-Verknüpfung im Startup-Ordner an. |
| `Uninstall-Autostart.ps1` | Entfernt diese Verknüpfung wieder. |

## Verteilung / USB-Stick

| Datei | Zuständig für |
|---|---|
| `Build-Release.ps1` | Baut `dist/monitor-focus-follow-usb.zip`: Programm + `src/` + Config + die USB-Skripte, verpackt im Ordner `!monitor-focus-follow` (führendes `!` = ganz oben im Explorer) plus eine Wegweiser-Textdatei fürs Stammverzeichnis. |
| `usb/Setup.cmd` + `usb/Setup.ps1` | **Variante A:** kopiert das Programm vom Stick nach `%LOCALAPPDATA%\monitor-focus-follow`, richtet Autostart ein, startet sofort. `.cmd` = Doppelklick-Starter, `.ps1` = die eigentliche Arbeit. Kein Admin nötig. |
| `usb/Start-Portabel.cmd` | **Variante B:** startet das Programm direkt vom Stick, ohne Installation. Läuft, solange der Stick steckt. |
| `usb/Deinstallieren.cmd` + `usb/Deinstallieren.ps1` | Beendet die laufende Instanz, entfernt die Autostart-Verknüpfung und den Programmordner vom PC. |
| `usb/LIESMICH.txt` | Anleitung, die mit ins Paket kommt. |

## Doku & Tests

| Datei | Zuständig für |
|---|---|
| `tests/FocusLogic.Tests.ps1` | Automatische Tests für `src/FocusLogic.psm1` (Pester 5+). |
| `CLAUDE.md` | Einstieg für die nächste Session (Mensch oder KI): Zweck, Aufbau, Befehle, Arbeitsweise, Fallstricke. |
| `docs/PROJEKT-LOG.md` | Chronologisches Logbuch: was wann warum gebaut wurde, aktueller Stand, offene Punkte. **Wichtigste Doku-Datei.** |
| `docs/DATEIEN.md` | Diese Übersicht. |
| `docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md` | Design im Detail (inkl. Änderungen v1.1 / v1.2). |
| `docs/superpowers/plans/` | Umsetzungspläne pro Version. |
| `README.md` | Anleitung für Endnutzer. |
| `.gitignore` | Was **nicht** ins Repo kommt: Logs (`focus.log`, `crash.log`), `dist/`. |

## Wird zur Laufzeit erzeugt (nicht im Repo)

| Datei | Bedeutung |
|---|---|
| `focus.log` | nur wenn `LogToFile = $true`: Ereignisprotokoll (Zeitstempel, Prozessname – keine Fenstertitel). |
| `crash.log` | wird immer geschrieben, falls das Programm beim Start oder unerwartet abbricht. |
| `dist/monitor-focus-follow-usb.zip` | das gebaute Verteilpaket. |
