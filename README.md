# monitor-focus-follow

Setzt den Tastaturfokus automatisch auf das Fenster unter dem Mauszeiger,
**sobald sich dieses Fenster ändert** – egal ob durch Monitorwechsel oder
durch ein anderes Fenster im Splitscreen daneben (z. B. Browser links,
WhatsApp rechts). Kein Klick nötig. Bewegungen innerhalb desselben Fensters
ändern nichts. Solange eine Maustaste gedrückt ist (Markieren, Ziehen),
bleibt der Fokus stehen.

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

> **Für Entwickler / zum Weiterarbeiten:** `docs/DATEIEN.md` erklärt jede
> Datei, `docs/PROJEKT-LOG.md` den Verlauf und aktuellen Stand.

## Beenden

**Kurz pausieren statt beenden:** `Strg`+`Alt`+`Pause` schaltet das
Fokus-Folgen aus und wieder an (Taste änderbar über `ToggleKey`).

So beendest du es ganz:

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
| `DebounceMs` | `120` | Wartezeit über dem neuen Fenster, bevor der Fokus gesetzt wird |
| `RaiseWindow` | `$false` | Fenster zusätzlich in der Z-Reihenfolge nach vorne holen |
| `PauseOnFullscreen` | `$true` | kein Fokuswechsel, solange vorne eine Vollbild-App läuft |
| `PauseWhileMouseDown` | `$true` | kein Fokuswechsel, solange eine Maustaste gedrückt ist |
| `EnableToggleHotkey` | `$true` | Pause-Hotkey `Strg`+`Alt`+`<ToggleKey>` aktiv |
| `ToggleKey` | `Pause` | Taste für den Hotkey: `Pause`, `ScrollLock`, `F9`–`F12` |
| `ExcludeProcesses` | `@()` | Prozessnamen (ohne `.exe`), die nie fokussiert werden |
| `LogToFile` | `$false` | Ereignisse zusätzlich in eine Datei schreiben |
| `LogPath` | `focus.log` | Pfad der Logdatei (relativ zum Projektordner) |

Nach einer Änderung das Programm neu starten (Task-Manager → beenden, dann
über die Verknüpfung oder den `Start-Process`-Befehl neu starten).

## Auf mehreren PCs / USB-Stick

Verteilpaket bauen:
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```
Das erzeugt `dist/monitor-focus-follow-usb.zip`. Inhalt auf einen USB-Stick
entpacken – es entsteht der Ordner **`!monitor-focus-follow`** (führendes
`!`, damit er im Explorer ganz oben steht) plus eine Wegweiser-Textdatei im
Stammverzeichnis. Im Ordner:

| Datei | Funktion |
|---|---|
| `Setup.cmd` | **Installieren:** kopiert das Programm nach `%LOCALAPPDATA%\monitor-focus-follow`, richtet Autostart ein, startet sofort. Kein Admin nötig, Stick kann danach raus. |
| `Start-Portabel.cmd` | **Ohne Installation:** startet direkt vom Stick. Läuft, solange der Stick steckt. |
| `Deinstallieren.cmd` | entfernt Autostart + Programmordner vom PC, beendet die laufende Instanz. |
| `LIESMICH.txt` | Kurzanleitung. |

Eine vorhandene `config.psd1` auf dem Ziel-PC wird **nicht** überschrieben
(die neue Vorlage kommt als `config.psd1.neu` daneben). Ein echtes
„automatisch beim Einstecken" gibt es nicht – Windows blockiert AutoRun von
USB-Sticks; ein Doppelklick auf `Setup.cmd` ist nötig.

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
(Fensterwechsel-Erkennung, Entprellung, „Maustaste gedrückt → kein
Wechsel", Fensterfilter). Der Windows-API-Teil (`src/Native.cs`) wird über
die manuelle Checkliste unten geprüft.

## Datenschutz

- Läuft komplett lokal. **Keine Netzwerkverbindung, keine Telemetrie.**
- Das Programm liest **keine Tastatureingaben** mit. Es reagiert nur auf die
  Mausposition und aktiviert Fenster. Für den Pause-Hotkey wird lediglich
  abgefragt, ob `Strg`, `Alt` und die eine Hotkey-Taste *gerade gedrückt*
  sind – nichts davon wird gespeichert.
- Standardmäßig wird **keine Logdatei** geschrieben. Die Konsolenausgabe gibt
  es nur beim manuellen Start mit `-Log`.
- Wenn `LogToFile = $true` gesetzt ist, enthält die Datei nur Zeitstempel
  und den Prozessnamen des fokussierten Fensters – **niemals Fenstertitel,
  Fensterinhalte oder Eingaben.**

## Manuelle Testcheckliste

1. Maus über die Monitorgrenze bewegen → Fenster auf dem anderen Monitor
   wird aktiv, ohne Klick.
2. Splitscreen auf einem Monitor (z. B. Browser + WhatsApp): Maus vom einen
   zum anderen Fenster bewegen, nicht klicken → Tippen landet im Fenster
   unter der Maus.
3. Maus innerhalb desselben Fensters bewegen → Fokus bleibt.
4. In einem Fenster Text mit gedrückter Maustaste über die Fensterkante
   hinaus markieren → Fokus springt nicht weg.
5. Vollbild-Spiel/-Video, Maus kurz rüber und zurück → kein Fokuswechsel
   (bei `PauseOnFullscreen = $true`).
6. `Strg`+`Alt`+`Pause` → Log zeigt „pausiert", Fokus folgt nicht mehr;
   nochmal → „aktiv".
7. Zweite Kopie starten, während eine läuft → die zweite beendet sich sofort
   („bereits aktiv").
8. `Strg`+`C` im Konsolenbetrieb → Ausgabe „beendet".
9. Nach `Install-Autostart.ps1` und Neuanmeldung → Programm läuft, im
   Task-Manager beendbar.

## Zukunftsideen (nicht enthalten)

- **Fokus auf einzelne Eingabefelder innerhalb einer Seite** (z. B. zwei
  Suchfelder auf einer Webseite). Windows sieht dort nur ein Fenster;
  sauber wäre nur ein simulierter Klick an der Mausposition – riskant,
  weil das ungewollt Buttons/Links auslösen kann.
- **Zwei Mäuse + zwei Tastaturen**, jede fest einem Monitor zugeordnet
  (Multi-Seat). Auf Windows mit Bordmitteln nicht möglich (nur ein
  Systemcursor) – ein eigenes, größeres Projekt.

Details in `docs/superpowers/specs/2026-09-03-monitor-focus-follow-design.md`.
