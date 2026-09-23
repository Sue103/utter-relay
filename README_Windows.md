# Utter Relay (Windows)

Utterアプリのクリップボード同期を、Windows側で受け取るための常駐ツールです。
Mac版と同じ`voicequick_clipboard.py`のロジック(v1.2.2)を、システムトレイの
`voicequick_tray.py`から利用します。

## 動かし方(開発者向け・そのまま実行)

```powershell
pip install -r requirements-tray.txt
python voicequick_tray.py
```

タスクトレイにアイコンが常駐します。右クリックで:

- 開始 / 停止
- 設定...(Relay URL・トークン・デバイスID)
- 終了

## 配布用exeを作る

Windows実機で実行してください(このリポジトリはMacで作成しているため、
.exeはWindows上でビルドする必要があります)。

```powershell
pip install -r requirements-tray.txt
build_windows.bat
```

成功すると `dist\VoiceQuickRelay.exe` ができます。

## 設定

初回起動時は `http://192.168.1.13:7210` が初期値として入っています。
Macの `Utter Relay.app` を起動した時にメニューバーへ表示される
実際のアドレスに書き換えてください。

設定は `%USERPROFILE%\.voicequick\tray_config.json` に保存されます。
