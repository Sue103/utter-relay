#!/usr/bin/env python3
"""VoiceQuick Relay - Windows/macOS system tray wrapper.

voicequick_clipboard.py の DesktopAgent(既に動作確認済みの同期ロジック、
LOCAL_CHANGE_GRACE_SECONDSの修正込み)をそのまま使い、その上に
トレイアイコン+設定ウィンドウをかぶせるだけのラッパー。
ロジックを二重管理しないよう、同期処理そのものはvoicequick_clipboard.pyに一本化している。

配布用の単体exe化にはPyInstallerを使う想定(build_windows.batを参照)。
"""
from __future__ import annotations

import json
import platform
import threading
from pathlib import Path
from tkinter import Tk, Label, Entry, Button, StringVar, messagebox

import pystray
from PIL import Image, ImageDraw

import voicequick_clipboard as core

CONFIG_DIR = Path.home() / ".voicequick"
CONFIG_PATH = CONFIG_DIR / "tray_config.json"

DEFAULT_CONFIG = {
    "relay_url": "http://192.168.1.13:7210",
    "token": "",
    "device_id": f"{platform.system().lower()}-{platform.node()}",
    "interval": 0.6,
    "auto_start": True,
}


def load_config() -> dict:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if CONFIG_PATH.exists():
        try:
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            return {**DEFAULT_CONFIG, **data}
        except (json.JSONDecodeError, OSError):
            pass
    return dict(DEFAULT_CONFIG)


def save_config(config: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")


class TrayApp:
    def __init__(self):
        self.config = load_config()
        self.agent: core.DesktopAgent | None = None
        self.agent_thread: threading.Thread | None = None
        self.running = False
        self.icon = pystray.Icon(
            "voicequick-relay",
            icon=self._make_icon(active=False),
            title="VoiceQuick Relay",
            menu=self._build_menu(),
        )

    def _make_icon(self, active: bool) -> Image.Image:
        size = 64
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        color = (52, 199, 89, 255) if active else (142, 142, 147, 255)
        draw.ellipse((8, 8, size - 8, size - 8), fill=color)
        return image

    def _build_menu(self) -> pystray.Menu:
        return pystray.Menu(
            pystray.MenuItem(self._toggle_label, self.toggle),
            pystray.MenuItem("設定...", self.open_settings),
            pystray.MenuItem(self._status_text, None, enabled=False),
            pystray.MenuItem("終了", self.quit_app),
        )

    def _toggle_label(self, item=None) -> str:
        return "停止" if self.running else "開始"

    def _status_text(self, item=None) -> str:
        state = "実行中" if self.running else "停止中"
        return f"状態: {state} -> {self.config['relay_url']}"

    def toggle(self, icon=None, item=None):
        self.stop() if self.running else self.start()

    def start(self):
        if self.running:
            return
        try:
            self.agent = core.DesktopAgent(
                relay_url=self.config["relay_url"],
                token=self.config["token"],
                device_id=self.config["device_id"],
                interval=float(self.config["interval"]),
            )
        except RuntimeError as error:
            self._notify(f"起動できません: {error}")
            return
        self.agent_thread = threading.Thread(target=self.agent.run, daemon=True)
        self.agent_thread.start()
        self.running = True
        self._refresh_icon()

    def stop(self):
        if self.agent:
            self.agent.stop()
        self.running = False
        self.agent = None
        self.agent_thread = None
        self._refresh_icon()

    def _refresh_icon(self):
        self.icon.icon = self._make_icon(active=self.running)
        self.icon.menu = self._build_menu()

    def _notify(self, message: str):
        try:
            self.icon.notify(message, title="VoiceQuick Relay")
        except Exception:
            print(f"[tray] {message}")

    def open_settings(self, icon=None, item=None):
        threading.Thread(target=self._settings_window, daemon=True).start()

    def _settings_window(self):
        root = Tk()
        root.title("VoiceQuick Relay 設定")
        root.attributes("-topmost", True)
        root.resizable(False, False)

        relay_var = StringVar(value=self.config["relay_url"])
        token_var = StringVar(value=self.config["token"])
        device_var = StringVar(value=self.config["device_id"])

        Label(root, text="Relay URL(Macで動いているVoiceQuick Relayのアドレス)").pack(anchor="w", padx=12, pady=(12, 0))
        Entry(root, textvariable=relay_var, width=42).pack(padx=12)

        Label(root, text="ペアリングトークン(Mac側と一致させる。空でも可)").pack(anchor="w", padx=12, pady=(10, 0))
        Entry(root, textvariable=token_var, width=42, show="*").pack(padx=12)

        Label(root, text="デバイスID").pack(anchor="w", padx=12, pady=(10, 0))
        Entry(root, textvariable=device_var, width=42).pack(padx=12)

        def on_save():
            relay_url = relay_var.get().strip()
            if not relay_url:
                messagebox.showerror("VoiceQuick Relay", "Relay URLを入力してください")
                return
            self.config["relay_url"] = relay_url
            self.config["token"] = token_var.get().strip()
            self.config["device_id"] = device_var.get().strip() or self.config["device_id"]
            save_config(self.config)
            if self.running:
                self.stop()
                self.start()
            else:
                self._refresh_icon()
            root.destroy()

        Button(root, text="保存", command=on_save).pack(pady=14)
        root.mainloop()

    def quit_app(self, icon=None, item=None):
        self.stop()
        self.icon.stop()

    def run(self):
        if self.config.get("auto_start", True):
            self.start()
        self.icon.run()


def main():
    TrayApp().run()


if __name__ == "__main__":
    main()
