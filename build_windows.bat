@echo off
REM Builds VoiceQuickRelay.exe. Run this on a real Windows machine.
REM First: pip install -r requirements-tray.txt

pyinstaller --onefile --windowed --name VoiceQuickRelay voicequick_tray.py

echo.
echo ==^> Done. Check dist\VoiceQuickRelay.exe
pause
