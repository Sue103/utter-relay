@echo off
REM VoiceQuickRelay.exe をビルドする(Windows実機で実行すること)。
REM 事前に: pip install -r requirements-tray.txt

pyinstaller --onefile --windowed --name VoiceQuickRelay voicequick_tray.py

echo.
echo ==^> dist\VoiceQuickRelay.exe ができていれば成功です。
pause
