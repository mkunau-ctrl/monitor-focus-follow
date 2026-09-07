# Projekt-Logbuch – monitor-focus-follow

Chronologischer Verlauf, neueste Änderung oben. Prosa, kein Code-Dump.
Wer das Projekt fortsetzt, soll hier verstehen können, *was*, *warum* und
*wie weit* – ohne den Quellcode zu lesen.

---

## Aktueller Stand (2026-09-08)

**Funktioniert und im Einsatz.** Der Tastaturfokus folgt der Maus – beim
Monitorwechsel und im Splitscreen –, ohne Fokusklau beim Markieren/Ziehen.
Läuft auf dem Rechner des Nutzers versteckt, gestartet über eine **geplante
Aufgabe** (`MonitorFocusFollow`, Auslöser „bei Anmeldung", 15 s Verzögerung).

- **Version im Repo:** v1.3 (USB-Verteilpaket). Laufzeitverhalten = v1.2
  (Single-Instance, erweiterte Filter, crash.log, Pause-Hotkey Strg+Alt+Pause,
  bessere Vollbild-Erkennung) + v1.4-Autostart (geplante Aufgabe statt
  Autostart-Ordner, Konsolenfenster wird sofort versteckt).
- **Tests:** 14 Pester-Tests grün (`Invoke-Pester .\tests\FocusLogic.Tests.ps1`).
- **GitHub:** `https://github.com/mkunau-ctrl/monitor-focus-follow` (öffentlich,
  Branch `main`).
- **USB-Stick des Nutzers:** Ordner `!monitor-focus-follow` entpackt,
  an den Schnellzugriff angepinnt, Wegweiser-Datei im Stammverzeichnis.
- **Dateiübersicht:** siehe `docs/DATEIEN.md`.

### Offene Punkte

- **Push:** Commits ab `b41fae3` (v1.2, v1.3, Doku) waren beim letzten
  Sitzungsende noch nicht auf GitHub – prüfen mit
  `git log origin/main..HEAD` und ggf. `git push`.
  *(Push durch Claude wird vom Auto-Classifier blockiert; der Nutzer pusht
  selbst mit `!git push`.)*
- **Idee 5:** GitHub Actions, die die Pester-Tests bei jedem Push laufen lassen.
- **Idee 6:** `config.psd1` ohne Neustart neu einlesen.
- **Optional:** GitHub-Release mit angehängtem `monitor-focus-follow-usb.zip`.
- **Pause-Hotkey** live vom Nutzer noch nicht ausdrücklich bestätigt
  (Logik getestet, echter Tastendruck nur manuell prüfbar).

### Zukunftsideen (bewusst nicht umgesetzt)

- **Fokus auf einzelne Eingabefelder innerhalb einer Seite** – ginge nur mit
  simuliertem Klick, zu riskant. Details im v1.1-Eintrag.
- **Multi-Seat** (2 Mäuse + 2 Tastaturen, je ein Monitor) – auf Windows nicht
  mit Bordmitteln möglich, eigenes Projekt. Details im v1-Eintrag und in der
  Spec.

---

## 2026-09-08 – Autostart als geplante Aufgabe (v1.4)

**Was:** Der Autostart läuft nicht mehr über eine Verknüpfung im
Windows-Autostart-Ordner, sondern über eine **geplante Aufgabe** namens
`MonitorFocusFollow` (Auslöser „bei Anmeldung", 15 Sekunden Verzögerung,
versteckt, kein Zeitlimit, Neustart bis zu 3× nach einem Absturz, läuft auch
im Akkubetrieb weiter). `Install-Autostart.ps1` legt diese Aufgabe an,
entfernt dabei die alte `.lnk` samt übrig gebliebenem Registry-Eintrag und
startet das Programm sofort mit. `Uninstall-Autostart.ps1` und
`usb/Deinstallieren.ps1` entfernen die Aufgabe wieder.

Zusätzlich: neue Methode `HideConsoleWindow()` in `src/Native.cs`, die das
Hauptskript im Normalbetrieb (nicht bei `-Log`) direkt nach dem Kompilieren
aufruft – gegen ein kurzes Aufblitzen eines Fensters.

**Warum:** Das Tool lief plötzlich nicht mehr. Ursache: der
Autostart-Ordner-Eintrag war in Windows deaktiviert worden (Registry
`StartupApproved\StartupFolder`, erstes Byte `3` statt `2`, Zeitstempel
05.09.2026 01:28) – sehr wahrscheinlich durch eins der „Aufräum-"/Optimizer-
Programme auf dem PC (Lavasoft Web Companion, Avast Browser, Opera GX).
Solche Tools können Autostart-Ordner-Einträge per Häkchen abschalten, eine
geplante Aufgabe nicht.

**Entscheidungen:**
- **Geplante Aufgabe statt `Run`-Registry-Schlüssel:** die Aufgabe kann eine
  Startverzögerung und automatischen Neustart, ein `Run`-Eintrag nicht.
- **„Nur wenn Benutzer angemeldet ist", RunLevel `Limited`:** so wird **kein
  Administrator** und **kein gespeichertes Passwort** gebraucht. Das Tool
  braucht ohnehin die interaktive Sitzung (Maus/Fenster).
- **15 s Verzögerung:** das Tool drängelt sich nicht in den Anmelde-Ansturm.
- **Alte `.lnk` wird beim Einrichten gelöscht**, damit es nicht zwei
  Autostarts gibt.
- **Bewusst nicht gemacht:** die Aufgabe als „unabhängig von der Anmeldung"
  laufen zu lassen (bräuchte Passwort/Admin) und den Startvorgang per
  VBScript/`conhost --headless` komplett flackerfrei zu machen (unnötig, mit
  `-WindowStyle Hidden` + `HideConsoleWindow()` sieht man praktisch nichts).

**Stand danach:** Aufgabe ist eingerichtet und läuft (`Get-ScheduledTask
MonitorFocusFollow` → *Running*), Prozess bestätigt aktiv, alte `.lnk` und
Registry-Eintrag entfernt, 14 Pester-Tests grün, `Native.cs` kompiliert
sauber. Beim nächsten Login startet es automatisch mit.

**Offene Punkte / Nächste Schritte:**
- Nach dem nächsten echten Neustart einmal prüfen, dass es ohne Zutun kommt.
- Commit auf GitHub pushen (Nutzer, mit `!git push`).

---

## 2026-09-04 – Verteilpaket für USB-Stick (v1.3)

**Was:** Ein Weg, das Tool auf beliebige Windows-PCs zu bringen.
`Build-Release.ps1` packt Programm + `src/` + Config + vier Doppelklick-
Skripte in `dist/monitor-focus-follow-usb.zip`. Das ZIP wird auf einen
USB-Stick entpackt. Auf dem Stick:
- `Setup.cmd` (Variante A) – kopiert nach `%LOCALAPPDATA%\monitor-focus-follow`,
  richtet Autostart ein, startet sofort. Kein Admin nötig. Stick kann raus.
- `Start-Portabel.cmd` (Variante B) – startet direkt vom Stick, ohne
  Installation. Läuft, solange der Stick steckt.
- `Deinstallieren.cmd` – beendet Instanz, entfernt Autostart + Programmordner.
- `LIESMICH.txt` – Anleitung.

**Warum:** Nutzer möchte das Tool ohne Git/Entwicklungsumgebung auf mehrere
Rechner bringen.

**Entscheidungen:**
- **Kein echtes AutoRun beim Einstecken** – Windows blockiert das seit
  Windows 7 aus Sicherheitsgründen. Ein Doppelklick auf `Setup.cmd` ist das
  Minimum. Dem Nutzer so erklärt.
- Die `.cmd`-Dateien sind nur dünne Starter (`powershell -ExecutionPolicy
  Bypass -File "%~dp0…"`), damit Doppelklick von jedem Laufwerksbuchstaben
  funktioniert. Jedes Fenster endet mit `pause`.
- **Vorhandene `config.psd1` auf dem Ziel-PC wird nicht überschrieben** – die
  neue Vorlage landet als `config.psd1.neu` daneben.
- Installationsziel `%LOCALAPPDATA%` (kein Admin, pro Benutzer).
- `dist/` ist in `.gitignore` – das ZIP wird bei Bedarf neu gebaut, nicht
  eingecheckt.

**Stand danach:** `Build-Release.ps1` und die vier USB-Skripte umgesetzt.
End-to-End getestet: ZIP bauen → entpacken → `Setup.ps1` (mit umgeleitetem
`%LOCALAPPDATA%`) kopiert alles + legt Autostart an + startet; zweiter
Setup-Lauf schützt die Config; `Deinstallieren.ps1` räumt sauber auf.

**Nachtrag (gleicher Tag):** Der Ordner im Paket heißt jetzt
`!monitor-focus-follow` – das führende `!` sorgt dafür, dass er im
Datei-Explorer **ganz oben** einsortiert wird (der Nutzer hatte den Ordner
zwischen ~150 anderen Dateien auf dem Stick nicht gefunden). Zusätzlich
legt `Build-Release.ps1` eine Wegweiser-Datei
`!!! monitor-focus-follow - HIER LESEN.txt` neben den Ordner (landet beim
Entpacken im Stammverzeichnis des Sticks). Auf dem Stick des Nutzers wurde
der Ordner außerdem an den Windows-Schnellzugriff angepinnt (gilt nur für
diesen PC).

**Offene Punkte:** GitHub-Release mit angehängtem ZIP (optional). Ideen 5
(GitHub Actions) und 6 (Config-Hot-Reload) weiterhin offen.

---

## 2026-09-04 – Verbesserungen 1–4 + 7 (v1.2)

**Was:** Fünf kleine, unabhängige Verbesserungen an v1.1:
1. **Einmal-Instanz-Sperre** (benannter Mutex): eine zweite gestartete Kopie
   beendet sich sofort. Verhindert das Chaos mit mehreren laufenden Kopien.
2. **Bessere Fensterfilter:** zusätzlich ausgeschlossen sind jetzt die
   Taskleiste auf dem 2. Monitor (`Shell_SecondaryTrayWnd`), Task-Ansicht/
   Alt-Tab, Benachrichtigungs- und Overlay-Fenster sowie Fenster mit
   `WS_EX_TOOLWINDOW` / `WS_EX_NOACTIVATE` (Widgets, manche Overlays).
3. **Absturz-Log** `crash.log` neben dem Skript – wird immer geschrieben,
   auch wenn Logging in der Config aus ist. Fängt Startfehler ab (z. B.
   `Add-Type` schlägt fehl), die sonst unsichtbar wären, weil das Programm
   versteckt läuft.
4. **Pause-Hotkey** `Strg+Alt+Pause` (Taste per `config.psd1` änderbar:
   Pause, ScrollLock, F9–F12): schaltet das Fokus-Folgen an/aus, ohne den
   Task-Manager. Umgesetzt über Tastenzustand-Abfrage in der Schleife mit
   Flankenerkennung – kein Message-Loop nötig.
7. **Zuverlässigere Vollbild-Erkennung:** zusätzlich zur bisherigen
   „Fenster = Monitorgröße"-Prüfung wird jetzt `SHQueryUserNotificationState`
   der Shell abgefragt (erkennt echte D3D-Vollbild-Spiele und
   Präsentationsmodus sauber).

**Warum:** Nutzer hat v1.1 als „funktioniert perfekt" bestätigt und nach
sinnvollen nächsten Schritten gefragt.

**Entscheidungen:**
- Ideen **5** (GitHub Actions für die Tests) und **6** (Config ohne Neustart
  neu laden) zurückgestellt – bei Bedarf einzeln.
- Hotkey-Modifikatoren fest auf Strg+Alt, nur die Haupttaste konfigurierbar
  (spart das Parsen beliebiger Hotkey-Strings, deckt die sinnvollen Fälle ab).
- Mutex-Name ohne `Global\`-Präfix (pro Benutzersitzung reicht, keine
  Rechteprobleme).

**Stand danach:** Umgesetzt, 14 Pester-Tests grün. Single-Instance,
crash.log und unbekannte-ToggleKey-Warnung manuell verifiziert.
Plan: `docs/superpowers/plans/2026-09-04-verbesserungen-v1.2.md`.

**Offene Punkte:** Ideen 5 und 6. Hotkey-Umschaltung live noch nicht vom
Nutzer bestätigt (Flankenerkennung getestet, Tastendruck nur manuell prüfbar).

---

## 2026-09-04 – Fokus folgt dem Fenster, nicht nur dem Monitor (v1.1)

**Was:** Der Auslöser für den Fokuswechsel wurde geändert. Vorher: "der
Mauszeiger hat die Monitorgrenze überquert". Jetzt: "das oberste Fenster
unter dem Mauszeiger hat sich geändert". Damit folgt der Fokus der Maus auch
im Splitscreen auf **einem** Monitor (z. B. Browser links, WhatsApp rechts)
und beim App-Wechsel im Splitscreen. Zusätzlich: solange eine Maustaste
gedrückt ist (Text markieren durch Ziehen, Fenster verschieben), wird kein
Fokuswechsel ausgelöst.

**Warum:** Der Nutzer arbeitet oft im Splitscreen und wollte, dass die
Tastatureingabe dorthin geht, wo die Maus ist – nicht nur beim
Monitorwechsel.

**Entscheidungen:**
- Wunsch "in genau das Suchfeld schreiben, das näher an der Maus ist"
  (mehrere Felder auf *einer* Webseite) wurde **bewusst weggelassen**.
  Windows sieht dort nur ein Fensterhandle; das saubere Setzen des
  Feld-Fokus bräuchte einen simulierten Mausklick an der Zeigerposition –
  riskant, weil das ungewollt Buttons/Links auslöst. Als Zukunftsidee in
  Spec und README notiert.
- Schutz "kein Wechsel bei gedrückter Maustaste" als eigene, abschaltbare
  Option `PauseWhileMouseDown` (Standard an).
- Die Monitor-Logik (`Get-MonitorIndexForPoint`) wurde ersatzlos entfernt,
  da der Fenstervergleich den Monitorwechsel automatisch mit abdeckt.

**Stand danach:** Umgesetzt, 11 Pester-Tests grün, manuell im Splitscreen
bestätigt ("funktioniert perfekt"). Läuft als Autostart, auf GitHub
gepusht (Commit `6ec7288`).

**Offene Punkte:** keine für dieses Feature.

---

## 2026-09-03 – Erste Version (v1)

**Was:** Grundgerüst und lauffähige erste Version. Ein verstecktes
PowerShell-Skript pollt ~alle 100 ms die Mausposition, erkennt den
Monitorwechsel (mit 120 ms Entprellung) und aktiviert das Fenster unter dem
Mauszeiger. Reine Entscheidungslogik in einem eigenen Modul mit Pester-Tests,
die Windows-API-Aufrufe in einem eingebetteten C#-Helfer. Autostart über eine
versteckte Verknüpfung im Startup-Ordner; Beenden nur über den Task-Manager
(so vom Nutzer gewünscht).

**Warum:** Bei zwei Monitoren wechselt Windows den Tastaturfokus erst nach
einem Klick auf dem anderen Bildschirm. Die eingebaute Windows-Funktion
(*active window tracking*) ist zu aggressiv – sie reißt bei *jeder*
Mausbewegung den Fokus an sich, auch auf demselben Monitor.

**Entscheidungen:**
- **Ansatz B** gewählt: PowerShell für Schleife/Config/Logs, kleiner
  eingebetteter C#-Helfer für die heiklen API-Aufrufe (v. a.
  `SetForegroundWindow` inkl. Umgehung der Vordergrund-Sperre). Kein
  .NET-SDK nötig. Ansatz A (reines PowerShell) verworfen wegen fragiler
  Fokus-Umschaltung, Ansatz C (eigene .exe) wegen Build-Aufwand.
- Nur Monitorwechsel als Auslöser, nicht jede Mausbewegung – bewusst
  konservativer als die Windows-Funktion.
- `RaiseWindow` standardmäßig aus (Fenster wird aktiviert, aber nicht in
  der Z-Reihenfolge nach vorne geholt).
- Kein Tray-Icon, keine GUI – vom Nutzer so gewünscht.
- Multi-Seat (2 Mäuse + 2 Tastaturen, je ein Monitor) als Zukunftsidee
  dokumentiert, nicht Teil von v1 (auf Windows nur mit erheblichem Aufwand
  möglich, da nur ein Systemcursor).

**Stand danach:** Lauffähig, 15 Pester-Tests grün, Autostart eingerichtet,
Repo `mkunau-ctrl/monitor-focus-follow` auf GitHub (öffentlich).

**Offene Punkte:** Verhalten im Splitscreen (führte zu v1.1).
