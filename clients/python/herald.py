#!/usr/bin/env python3
"""Herald client (stdlib only).

Talks to the Herald.app loopback API, reading the port and bearer token from
``~/Library/Application Support/Herald/{port,token}``.

Examples::

    from herald import Herald, HeraldUnavailable

    h = Herald()
    if h.is_available():
        h.register("example.bidbot", appName="BidBot", callbackURL="http://127.0.0.1:5123/herald")
        h.notify("example.bidbot", "Bid accepted", body="Won the Acme RFP",
                 id="bid-42", url="https://example.com/bids/42", sound="Glass",
                 buttons=[{"label": "Open", "url": "https://example.com/bids/42"}],
                 snooze=True)
        print(h.history("example.bidbot", limit=5))
        h.dismiss("example.bidbot", "bid-42")

    try:
        Herald().notify("example.bidbot", "hello")
    except HeraldUnavailable:
        pass  # Herald is not running
"""
from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional

__all__ = ["Herald", "HeraldError", "HeraldUnavailable"]

SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "Herald"
DEFAULT_PORT = 48617


class HeraldError(Exception):
    """The service answered with an error status."""

    def __init__(self, status: int, message: str):
        super().__init__(f"Herald error {status}: {message}")
        self.status = status
        self.message = message


class HeraldUnavailable(HeraldError):
    """Herald is not running (connection refused / timed out)."""

    def __init__(self, message: str = "Herald is not running. Launch Herald.app first."):
        Exception.__init__(self, message)
        self.status = 0
        self.message = message


def _read(name: str) -> Optional[str]:
    try:
        text = (SUPPORT_DIR / name).read_text().strip()
        return text or None
    except OSError:
        return None


class Herald:
    """Client for the Herald notification service."""

    def __init__(self, port: Optional[int] = None, token: Optional[str] = None, timeout: float = 10.0):
        port_file = _read("port")
        self.port: int = port or (int(port_file) if port_file and port_file.isdigit() else DEFAULT_PORT)
        self._token = token
        self.timeout = timeout

    @property
    def token(self) -> Optional[str]:
        # Re-read each time so a regenerated token is picked up.
        return self._token or _read("token")

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def _request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None,
                 query: Optional[Dict[str, Any]] = None, auth: bool = True) -> Any:
        url = self.base_url + path
        if query:
            url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        token = self.token if auth else None
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                msg = json.loads(raw).get("error", raw.decode(errors="replace"))
            except ValueError:
                msg = raw.decode(errors="replace")
            raise HeraldError(e.code, str(msg)) from None
        except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as e:
            raise HeraldUnavailable() from e
        return json.loads(raw) if raw else {}

    def is_available(self) -> bool:
        """True if Herald answers its health endpoint."""
        try:
            return bool(self._request("GET", "/v1/health", auth=False).get("ok"))
        except HeraldError:
            return False

    def health(self) -> Dict[str, Any]:
        return self._request("GET", "/v1/health", auth=False)

    def notify(self, app: str, title: str, **fields: Any) -> str:
        """Send a notification; returns its id.

        ``fields``: id, subtitle, body, image, url, sound, persistent, timeout,
        priority, buttons, snooze, reminder, metadata (see DESIGN.md section 2).
        """
        payload = {"app": app, "title": title, **{k: v for k, v in fields.items() if v is not None}}
        reply = self._request("POST", "/v1/notify", payload)
        return reply.get("id", fields.get("id", ""))

    def register(self, app: str, **fields: Any) -> Dict[str, Any]:
        """Register/update an app: appName, icon, bundleId, callbackURL, allowCommands, defaults."""
        payload = {"app": app, **{k: v for k, v in fields.items() if v is not None}}
        return self._request("POST", "/v1/register", payload)

    def dismiss(self, app: str, id: str) -> Dict[str, Any]:
        return self._request("POST", "/v1/dismiss", {"app": app, "id": id})

    def dismiss_all(self, app: str) -> Dict[str, Any]:
        return self._request("POST", "/v1/dismissAll", {"app": app})

    def history(self, app: str, limit: int = 50) -> list:
        return self._request("GET", "/v1/history", query={"app": app, "limit": limit}).get("items", [])

    def clear_history(self, app: str) -> Dict[str, Any]:
        return self._request("DELETE", "/v1/history", query={"app": app})

    def apps(self) -> Any:
        return self._request("GET", "/v1/apps")


if __name__ == "__main__":
    import sys

    h = Herald()
    try:
        nid = h.notify("herald-demo", "Hello from Python", body="Herald client demo. [Docs](https://example.com)",
                       sound="Glass", snooze=True,
                       buttons=[{"label": "Open", "url": "https://example.com"}])
        print("sent", nid)
    except HeraldUnavailable as e:
        print(e, file=sys.stderr)
        sys.exit(2)
    except HeraldError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
