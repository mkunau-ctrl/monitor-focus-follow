<#
    Konfiguration fuer monitor-focus-follow.
    Wird beim Start eingelesen. Fehlt ein Schluessel oder hat er den
    falschen Typ, verwendet das Programm den eingebauten Standardwert
    und schreibt eine Warnung ins Log.
#>
@{
    # Abfragetakt der Hauptschleife in Millisekunden.
    PollIntervalMs    = 100

    # Wartezeit nach dem Ueberqueren der Monitorgrenze, bevor der Fokus
    # gesetzt wird (verhindert Zappeln direkt an der Kante).
    DebounceMs        = 120

    # $true = Fenster zusaetzlich in der Z-Reihenfolge nach vorne holen.
    # $false = nur aktivieren (konservativ, Standard).
    RaiseWindow       = $false

    # $true = kein Fokuswechsel, solange vorne eine Vollbild-App laeuft
    # (z. B. Spiel oder Vollbild-Video).
    PauseOnFullscreen = $true

    # $true = kein Fokuswechsel, solange eine Maustaste gedrueckt ist
    # (schuetzt Markieren per Ziehen und das Verschieben von Fenstern).
    PauseWhileMouseDown = $true

    # Pause-Hotkey: Strg + Alt + <ToggleKey> schaltet das Folgen an/aus,
    # ohne den Task-Manager. Erlaubte Werte fuer ToggleKey:
    # 'Pause', 'ScrollLock', 'F9', 'F10', 'F11', 'F12'.
    EnableToggleHotkey = $true
    ToggleKey          = 'Pause'

    # Prozessnamen (ohne ".exe"), die nie den Fokus bekommen sollen.
    # Beispiel: @('vlc', 'mpc-hc')
    ExcludeProcesses  = @()

    # $true = Ereignisse zusaetzlich in eine Datei schreiben.
    # Die Datei enthaelt nur Zeitstempel, Monitor-Index und Prozessname -
    # niemals Fenstertitel oder Eingaben.
    LogToFile         = $false

    # Pfad der Logdatei (relativ zum Projektordner, wenn nicht absolut).
    LogPath           = 'focus.log'
}
