# Utter Relay

[Utter](https://github.com/Sue103/Vapp)(iOS版オンデバイス音声入力アプリ)のクリップボード同期機能のための、
Mac・Windows用の常駐リレーアプリです。外部サーバーを使わず、同じWi-Fi内の
あなたの機器同士だけをつなぎます。

配布ページ: ダウンロードや使い方は Releases を参照してください。

## 構成

- `Sources/VoiceQuickRelay/` — Mac版(SwiftUI, メニューバー常駐)。依存ライブラリなし、Network.frameworkのみで実装。
- `build_app.sh` — Mac版を `.app` に組み立てるビルドスクリプト。
- `voicequick_clipboard.py` — リレーサーバー + デスクトップエージェントの中核ロジック(Mac/Windows共通)。
- `voicequick_tray.py` — Windows用のシステムトレイUI(`voicequick_clipboard.py`のDesktopAgentをラップ)。
- `build_windows.bat` / `requirements-tray.txt` — Windows実機での`.exe`ビルド手順。

## 注意

このリポジトリは配布用です。開発は別の非公開リポジトリで行っており、
`voicequick_clipboard.py` の変更はそちらが正になります。ここへは
リリースのタイミングで反映します。
