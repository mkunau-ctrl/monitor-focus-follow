# CLAUDE.md – Einstieg für die nächste Session

## Zweck

`monitor-focus-follow` setzt den Tastaturfokus automatisch auf das Fenster
unter dem Mauszeiger, sobald sich dieses Fenster ändert – beim Wechsel
zwischen zwei Monitoren **und** im Splitscreen auf einem Monitor. Ohne Klick.
Windows/PowerShell, läuft versteckt per Autostart.

## Wo weiterlesen (statt Code lesen)

- **`docs/PROJEKT-LOG.md`** – chronologischer Verlauf + Abschnitt „Aktueller
  Stand" ganz oben (Version, was läuft, offene Punkte). **Zuerst hier lesen.**
- `docs/DATEIEN.md` – welche Datei für was zuständig ist.
- `docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md` – das
  Design im Detail (inkl. Änderungen v1.1 / v1.2).
- `docs/superpowers/plans/` – die Umsetzungspläne pro Version.

## Aufbau

| Datei | Wofür |
|---|---|
| `MonitorFocusFollow.ps1` | Einstieg + Hauptschleife: Mausposition abfragen, Fensterwechsel erkennen, Fokus setzen |
| `src/FocusLogic.psm1` | reine Entscheidungslogik (Wechsel ja/nein, Fensterfilter) – keine Windows-API, mit Pester getestet |
| `src/Native.cs` | eingebetteter C#-Helfer: alle Windows-API-Aufrufe (Cursor, Fenster, Fokus setzen, Maustasten, DPI) |
| `config.psd1` | Einstellungen (Entprellung, Vollbild-/Maustaste-Pause, Ausschlussliste, Logdatei) |
| `tests/FocusLogic.Tests.ps1` | Pester-Tests für `FocusLogic.psm1` |
| `Install-Autostart.ps1` / `Uninstall-Autostart.ps1` | versteckte Autostart-Verknüpfung an/aus |
| `Build-Release.ps1` | baut `dist/monitor-focus-follow-usb.zip` für die Verteilung |
| `usb/` | Doppelklick-Skripte fürs Verteilpaket: `Setup.cmd` (installieren), `Start-Portabel.cmd` (vom Stick), `Deinstallieren.cmd`, `LIESMICH.txt` |
| `README.md` | Anleitung für Endnutzer |

## Starten / Testen

```powershell
# Tests
Invoke-Pester .\tests\FocusLogic.Tests.ps1

# Manuell mit Log-Ausgabe (zum Debuggen), Strg+C beendet
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Log

# Nur ein Durchlauf (Selbsttest)
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Once -Log

# Autostart einrichten
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1

# Verteilpaket bauen -> dist\monitor-focus-follow-usb.zip
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```

Im Normalbetrieb läuft es versteckt; **Beenden nur über den Task-Manager**
(Details → `powershell.exe` mit `MonitorFocusFollow.ps1` → Task beenden).

## Arbeitsweise

Dieses Projekt folgt dem Skill **`projekt-workflow`**: erst planen (Design im
Chat oder Spec-Datei), Zustimmung abwarten, dann bauen (TDD wo möglich),
danach `docs/PROJEKT-LOG.md` und diese Datei aktualisieren. Antworten und
Doku auf Deutsch. Datenschutz beachten.

## Konventionen / Fallstricke

- **Windows PowerShell 5.1** (`powershell.exe`), keine PS-7-only-Syntax.
- `Add-Type` für `src/Native.cs` braucht `-ReferencedAssemblies
  System.Windows.Forms, System.Drawing`.
- Pester 5+ nötig (auf dem Entwicklungsrechner ist Pester 6 installiert).
- **`git push` durch Claude wird vom Auto-Classifier blockiert.** Der Nutzer
  pusht selbst: `!powershell -Command "cd <repo>; git push"`.
- GitHub-Remote: `https://github.com/mkunau-ctrl/monitor-focus-follow`
  (öffentlich, Branch `main`). Der GitHub-MCP-Server war zeitweise kaputt;
  Repo-Operationen laufen über die `gh` CLI.
- Datenschutz: Tool liest nur die Mausposition und Fenster-/Prozessnamen,
  **keine Tastatureingaben**, kein Netzwerk. Logdatei standardmäßig aus; wenn
  an, nur Zeitstempel + Prozessname, keine Fenstertitel.
