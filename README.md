# monitor-focus-follow

Setzt bei zwei Monitoren den Tastaturfokus automatisch auf das Fenster unter
dem Mauszeiger, **sobald die Maus die Monitorgrenze überquert** – ohne dass
man erst klicken muss. Bewegungen innerhalb eines Monitors ändern nichts.

## Voraussetzungen

- Windows 10/11
- Windows PowerShell 5.1 (vorinstalliert)
- Nur für die Tests: Pester 5 oder neuer
  (`Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`)

## Installation

1. Diesen Projektordner an einen festen Ort legen (z. B.
   `C:\Users\<Name>\monitor-focus-follow`).
2. Autostart einrichten:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1
   ```
3. Entweder neu anmelden – oder sofort starten mit dem Befehl, den das
   Installationsskript ausgibt:
   ```
   Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "<Pfad>\MonitorFocusFollow.ps1"'
   ```

Das Programm läuft danach unsichtbar im Hintergrund (kein Fenster, kein
Symbol).

## Beenden

Es gibt bewusst keinen Beenden-Knopf. So beendest du es:

1. Task-Manager öffnen (`Strg`+`Umschalt`+`Esc`).
2. Reiter **Details**.
3. Mit Rechtsklick auf eine Spaltenüberschrift **Spalten auswählen** →
   Haken bei **Befehlszeile** setzen.
4. Den Eintrag `powershell.exe` suchen, dessen Befehlszeile
   `MonitorFocusFollow.ps1` enthält.
5. Rechtsklick → **Task beenden**.

Autostart dauerhaft entfernen:
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autostart.ps1
```
(Beendet einen laufenden Prozess nicht – dafür den Task-Manager benutzen.)

## Konfiguration

Einstellungen in `config.psd1` (wird beim Start gelesen; fehlt ein Wert,
gilt der Standard):

| Schlüssel | Standard | Zweck |
|---|---|---|
| `PollIntervalMs` | `100` | Abfragetakt der Schleife in Millisekunden |
| `DebounceMs` | `120` | Wartezeit nach Grenzübertritt, bevor der Fokus gesetzt wird |
| `RaiseWindow` | `$false` | Fenster zusätzlich in der Z-Reihenfolge nach vorne holen |
| `PauseOnFullscreen` | `$true` | kein Fokuswechsel, solange vorne eine Vollbild-App läuft |
| `ExcludeProcesses` | `@()` | Prozessnamen (ohne `.exe`), die nie fokussiert werden |
| `LogToFile` | `$false` | Ereignisse zusätzlich in eine Datei schreiben |
| `LogPath` | `focus.log` | Pfad der Logdatei (relativ zum Projektordner) |

Nach einer Änderung das Programm neu starten (Task-Manager → beenden, dann
über die Verknüpfung oder den `Start-Process`-Befehl neu starten).

## Zum Testen / Debuggen

Im Vordergrund mit Log-Ausgaben starten:
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Log
```
Nur eine Schleifeniteration (Selbsttest):
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorFocusFollow.ps1 -Once -Log
```
Beenden im Konsolenbetrieb mit `Strg`+`C`.

## Automatisierte Tests

```
Invoke-Pester .\tests\FocusLogic.Tests.ps1
```
Getestet wird die reine Entscheidungslogik in `src/FocusLogic.psm1`
(Monitorzuordnung inkl. negativer Koordinaten, Entprellung, Fensterfilter).
Der Windows-API-Teil (`src/Native.cs`) wird über die manuelle Checkliste
unten geprüft.

## Datenschutz

- Läuft komplett lokal. **Keine Netzwerkverbindung, keine Telemetrie.**
- Das Programm liest **keine Tastatureingaben** mit. Es reagiert nur auf die
  Mausposition und aktiviert Fenster.
- Standardmäßig wird **keine Logdatei** geschrieben. Die Konsolenausgabe gibt
  es nur beim manuellen Start mit `-Log`.
- Wenn `LogToFile = $true` gesetzt ist, enthält die Datei nur Zeitstempel,
  Monitor-Index und den Prozessnamen des fokussierten Fensters – **niemals
  Fenstertitel, Fensterinhalte oder Eingaben.**

## Manuelle Testcheckliste

1. Maus langsam über die Monitorgrenze bewegen → Fenster auf dem Zielmonitor
   wird aktiv, ohne Klick.
2. Maus innerhalb eines Monitors zwischen Fenstern bewegen → Fokus bleibt.
3. Vollbild-Spiel/-Video auf einem Monitor, Maus kurz rüber und zurück →
   kein Fokuswechsel (bei `PauseOnFullscreen = $true`).
4. `Strg`+`C` im Konsolenbetrieb → Ausgabe „beendet".
5. Nach `Install-Autostart.ps1` und Neuanmeldung → Programm läuft, im
   Task-Manager beendbar.

## Zukunftsidee (nicht in Version 1)

Zwei Mäuse + zwei Tastaturen, jede fest einem Monitor zugeordnet
(Multi-Seat). Auf Windows mit Bordmitteln nicht möglich (nur ein
Systemcursor) – das wäre ein eigenes, größeres Projekt. Details in
`docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md`.
