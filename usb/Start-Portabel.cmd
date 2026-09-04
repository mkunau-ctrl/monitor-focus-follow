@echo off
rem Variante B: monitor-focus-follow direkt vom Stick starten (nichts wird installiert).
rem Laeuft, bis der Stick abgezogen wird oder das Programm im Task-Manager beendet wird.
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0MonitorFocusFollow.ps1"
echo.
echo monitor-focus-follow laeuft jetzt portabel vom Stick.
echo Nicht den Stick abziehen, solange es laufen soll.
echo.
echo Beenden: Task-Manager -^> Details -^> powershell.exe mit "MonitorFocusFollow.ps1".
echo Pausieren: Strg+Alt+Pause.
echo.
pause
