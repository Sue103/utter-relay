#!/usr/bin/env python3
"""VoiceQuick Clipboard Relay + macOS/Windows desktop agent (text MVP)."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Windows専用: pywin32でクリップボードをプロセス内から直接読み書きする。
# 以前はpowershell.exeをsubprocessで毎回起動していたが、DesktopAgentが0.6秒おきに
# 呼ぶため、Windows機のCPUを継続的に食い続け、体感できるレベルの動作遅延
# (ネットワークが悪いように見えるほどの重さ)を引き起こしていた。実測で確認済み。
if platform.system() == "Windows":
    import win32clipboard
    import win32con

MAX_TEXT_BYTES = 256 * 1024
VERSION = "1.3.0"

# Grace period (seconds) after a local clipboard change before we allow a remote
# item to overwrite it. Without this, copying something locally can get immediately
# clobbered by an older item still sitting on the relay.
LOCAL_CHANGE_GRACE_SECONDS = 3.0


def now_iso() -> str:
    # Foundationの.iso8601デコーダーと確実に相互運用できる秒精度。
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class ClipboardStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.Lock()
        with self.connection:
            self.connection.execute(
                """
                CREATE TABLE IF NOT EXISTS clipboard_items (
                    revision INTEGER PRIMARY KEY AUTOINCREMENT,
                    id TEXT NOT NULL UNIQUE,
                    origin_device TEXT NOT NULL,
                    text TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    targets TEXT NOT NULL DEFAULT '["all"]'
                )
                """
            )
            columns = {
                row[1] for row in self.connection.execute("PRAGMA table_info(clipboard_items)")
            }
            if "targets" not in columns:
                self.connection.execute(
                    "ALTER TABLE clipboard_items ADD COLUMN targets TEXT NOT NULL DEFAULT '[\"all\"]'"
                )

    def put(self, item: dict) -> dict:
        with self.lock, self.connection:
            self.connection.execute(
                """INSERT OR IGNORE INTO clipboard_items
                   (id, origin_device, text, content_hash, created_at, targets)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (
                    item["id"],
                    item["originDevice"],
                    item["text"],
                    item["contentHash"],
                    item["createdAt"],
                    json.dumps(item.get("targets", ["all"])),
                ),
            )
            row = self.connection.execute(
                """SELECT revision, id, origin_device, text, content_hash, created_at, targets
                   FROM clipboard_items WHERE id = ?""",
                (item["id"],),
            ).fetchone()
        return self._as_dict(row)

    def latest(self, excluding_device: str, platform_name: str, after_revision: int = 0) -> dict | None:
        with self.lock:
            rows = self.connection.execute(
                """SELECT revision, id, origin_device, text, content_hash, created_at, targets
                   FROM clipboard_items
                   WHERE origin_device != ? AND revision > ?
                   ORDER BY revision DESC LIMIT 100""",
                (excluding_device, after_revision),
            ).fetchall()
        for row in rows:
            targets = json.loads(row[6])
            if "all" in targets or platform_name in targets:
                return self._as_dict(row)
        return None

    @staticmethod
    def _as_dict(row: tuple) -> dict:
        return {
            "revision": row[0],
            "id": row[1],
            "originDevice": row[2],
            "text": row[3],
            "contentHash": row[4],
            "createdAt": row[5],
            "targets": json.loads(row[6]),
        }


class RelayHandler(BaseHTTPRequestHandler):
    server_version = "VoiceQuickClipboard/1.0"

    @property
    def relay(self):
        return self.server  # type: ignore[attr-defined]

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/v1/clipboard/health":
            if not self._authorized():
                return
            self._json(HTTPStatus.OK, {"status": "ok", "service": "voicequick-clipboard"})
            return
        if parsed.path == "/v1/clipboard/latest":
            if not self._authorized():
                return
            query = urllib.parse.parse_qs(parsed.query)
            device = query.get("device_id", [self.headers.get("X-VoiceQuick-Device", "unknown")])[0]
            platform_name = query.get("platform", ["all"])[0]
            try:
                after = int(query.get("after_revision", ["0"])[0])
            except ValueError:
                after = 0
            item = self.relay.store.latest(device, platform_name, after)
            if item is None:
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
            else:
                self._json(HTTPStatus.OK, item)
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path != "/v1/clipboard":
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        if not self._authorized():
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_TEXT_BYTES * 2:
                raise ValueError("invalid_size")
            item = json.loads(self.rfile.read(length))
            text = item["text"]
            if not isinstance(text, str) or not text or len(text.encode("utf-8")) > MAX_TEXT_BYTES:
                raise ValueError("invalid_text")
            normalized = {
                "id": str(item.get("id") or uuid.uuid4()),
                "originDevice": str(item.get("originDevice") or self.headers.get("X-VoiceQuick-Device", "unknown")),
                "text": text,
                "contentHash": str(item.get("contentHash") or text_hash(text)),
                "createdAt": str(item.get("createdAt") or now_iso()),
                "targets": item.get("targets") if isinstance(item.get("targets"), list) else ["all"],
            }
            saved = self.relay.store.put(normalized)
            self._json(HTTPStatus.OK, saved)
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(error)})

    def _authorized(self) -> bool:
        if not self.relay.token:
            return True
        if self.headers.get("Authorization") == f"Bearer {self.relay.token}":
            return True
        self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        return False

    def _json(self, status: HTTPStatus, value: dict):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[relay] {self.address_string()} {fmt % args}")


class RelayServer(ThreadingHTTPServer):
    def __init__(self, address, store: ClipboardStore, token: str):
        super().__init__(address, RelayHandler)
        self.store = store
        self.token = token


class SystemClipboard:
    def __init__(self):
        self.system = platform.system()
        if self.system not in {"Darwin", "Windows"}:
            raise RuntimeError("Desktop agent supports macOS and Windows")

    def read(self) -> str:
        if self.system == "Darwin":
            result = subprocess.run(["pbpaste"], capture_output=True, check=False)
            return result.stdout.decode("utf-8", errors="replace")
        # Windows: プロセスを起動せず、win32clipboardでプロセス内から直接読む。
        win32clipboard.OpenClipboard()
        try:
            if win32clipboard.IsClipboardFormatAvailable(win32con.CF_UNICODETEXT):
                return win32clipboard.GetClipboardData(win32con.CF_UNICODETEXT) or ""
            return ""
        finally:
            win32clipboard.CloseClipboard()

    def write(self, text: str):
        if self.system == "Darwin":
            subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
            return
        win32clipboard.OpenClipboard()
        try:
            win32clipboard.EmptyClipboard()
            win32clipboard.SetClipboardData(win32con.CF_UNICODETEXT, text)
        finally:
            win32clipboard.CloseClipboard()


class DesktopAgent:
    def __init__(self, relay_url: str, token: str, device_id: str, interval: float):
        self.relay_url = relay_url.rstrip("/")
        self.token = token
        self.device_id = device_id
        self.platform_name = "mac" if platform.system() == "Darwin" else "windows"
        self.interval = interval
        self.clipboard = SystemClipboard()
        self.last_local_hash = ""
        self.last_applied_hash = ""
        self.last_revision = 0
        self.last_local_change_at = 0.0
        self._stop_event = threading.Event()

    def stop(self):
        # トレイアプリなど、ループの外から安全に止めたい呼び出し元向け。
        # time.sleep()の代わりにEvent.wait()を使うことで、stop()が呼ばれたら
        # 次のポーリング待ちで即座にループを抜けられる(CLIの--serveのみ利用時は未使用のまま)。
        self._stop_event.set()

    def run(self):
        print(f"[agent] VoiceQuick Clipboard {VERSION}")
        print(f"[agent] {self.device_id} -> {self.relay_url}")
        while not self._stop_event.is_set():
            try:
                local_text = self.clipboard.read()
                local_hash = text_hash(local_text) if local_text else ""
                if local_text and local_hash != self.last_local_hash:
                    self.last_local_hash = local_hash
                    self.last_local_change_at = time.monotonic()
                    if local_hash != self.last_applied_hash:
                        self._send(local_text, local_hash)
                remote = self._latest()
                just_changed_locally = (time.monotonic() - self.last_local_change_at) < LOCAL_CHANGE_GRACE_SECONDS
                if remote and remote["contentHash"] != self.last_local_hash and not just_changed_locally:
                    self.clipboard.write(remote["text"])
                    self.last_revision = int(remote["revision"])
                    self.last_applied_hash = remote["contentHash"]
                    self.last_local_hash = remote["contentHash"]
                    print(f"[agent] received r{self.last_revision} from {remote['originDevice']}")
                elif remote and just_changed_locally:
                    # Skip only; revision is not advanced, so this item is reconsidered next loop.
                    print(f"[agent] deferring r{remote['revision']} (local clipboard changed moments ago)")
            except Exception as error:
                print(f"[agent] retrying after error: {error}")
            self._stop_event.wait(self.interval)
        print("[agent] stopped")

    def _request(self, request: urllib.request.Request):
        request.add_header("X-VoiceQuick-Device", self.device_id)
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        return urllib.request.urlopen(request, timeout=5)

    def _send(self, text: str, content_hash: str):
        if "\ufffd" in text:
            print("[agent] skipped text containing Unicode replacement characters")
            return
        item = {
            "id": str(uuid.uuid4()),
            "originDevice": self.device_id,
            "text": text,
            "contentHash": content_hash,
            "createdAt": now_iso(),
            "targets": ["iphone"],
        }
        data = json.dumps(item).encode("utf-8")
        request = urllib.request.Request(
            f"{self.relay_url}/v1/clipboard", data=data, method="POST",
            headers={"Content-Type": "application/json"},
        )
        with self._request(request) as response:
            saved = json.load(response)
        self.last_revision = max(self.last_revision, int(saved["revision"]))
        print(f"[agent] sent r{saved['revision']}")

    def _latest(self) -> dict | None:
        query = urllib.parse.urlencode({
            "device_id": self.device_id,
            "platform": self.platform_name,
            "after_revision": self.last_revision,
        })
        request = urllib.request.Request(f"{self.relay_url}/v1/clipboard/latest?{query}")
        try:
            with self._request(request) as response:
                return json.load(response) if response.status == 200 else None
        except urllib.error.HTTPError as error:
            if error.code == HTTPStatus.NO_CONTENT:
                return None
            raise


def parse_args():
    parser = argparse.ArgumentParser(description="VoiceQuick Clipboard Relay and desktop agent")
    parser.add_argument("--serve", action="store_true", help="also host the relay API")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=7210)
    parser.add_argument("--relay-url", default="http://127.0.0.1:7210")
    parser.add_argument("--token", default=os.environ.get("VOICEQUICK_CLIPBOARD_TOKEN", ""))
    parser.add_argument("--device-id", default=f"{platform.system().lower()}-{platform.node()}")
    parser.add_argument("--db", type=Path, default=Path.home() / ".voicequick" / "clipboard.sqlite3")
    parser.add_argument("--interval", type=float, default=0.6)
    parser.add_argument("--relay-only", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.serve:
        server = RelayServer((args.host, args.port), ClipboardStore(args.db), args.token)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"[relay] listening on http://{args.host}:{args.port}")
    if args.relay_only:
        if not args.serve:
            raise SystemExit("--relay-only requires --serve")
        while True:
            time.sleep(3600)
    DesktopAgent(args.relay_url, args.token, args.device_id, args.interval).run()


if __name__ == "__main__":
    main()
