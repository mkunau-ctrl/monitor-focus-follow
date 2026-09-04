# Projekt-Logbuch – monitor-focus-follow

Chronologischer Verlauf, neueste Änderung oben. Prosa, kein Code-Dump.
Wer das Projekt fortsetzt, soll hier verstehen können, *was*, *warum* und
*wie weit* – ohne den Quellcode zu lesen.

---

## 2026-09-04 – Verbesserungen 1–4 + 7 (v1.2) – IN ARBEIT

**Was:** Geplant sind fünf kleine Verbesserungen:
1. Einmal-Instanz-Sperre (Mutex), damit nie mehrere Kopien gleichzeitig laufen.
2. Bessere Fensterfilter (Tool-Fenster, nicht-aktivierbare Fenster, Startmenü,
   Task-Ansicht, Benachrichtigungs-Popups ausschließen).
3. Absturz-Log beim Start (`crash.log`), weil das Programm versteckt läuft und
   ein Startfehler sonst unsichtbar bleibt.
4. Pause-Hotkey zum schnellen An/Aus ohne Task-Manager.
7. Zuverlässigere Vollbild-Erkennung über `SHQueryUserNotificationState` statt
   nur "Fensterrechteck = Monitorgröße".

**Warum:** Nutzer hat v1.1 als "funktioniert perfekt" bestätigt und nach
sinnvollen nächsten Schritten gefragt. Punkte 5 (GitHub Actions) und 6
(Config-Hot-Reload) wurden zurückgestellt.

**Stand:** Noch nicht umgesetzt. Plan wird als
`docs/superpowers/plans/2026-09-04-verbesserungen-v1.2.md` geschrieben.

**Offene Punkte:** siehe oben; nach Umsetzung 5 und 6 bei Bedarf.

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
