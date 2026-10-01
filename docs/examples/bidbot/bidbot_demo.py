#!/usr/bin/env python3
"""BidBot: a worked example of an app that talks to Herald (issues #32, DESIGN section 7).

Run it with Herald running:

    python3 docs/examples/bidbot/bidbot_demo.py

What it does, in order (the README next to this file walks through each step):

  1. registers the app "bidbot" (name, icon, default sound);
  2. PUTs a manifest: the fields BidBot can send (bid, amount, client, deadline, url, image) with samples,
     and the two actions it offers;
  3. PUTs a default grid template, "bid-card" (3 rows x 4 columns), that the manifest names as its default,
     with one extra action the USER owns: a Shortcut-ready "Follow up" button;
  4. sends three events (bid accepted, bid lost, deadline soon), each with a voice line and buttons.

Standard library only. The Herald client is clients/python/herald.py from this repository.

Useful flags:
  --quiet            no chime and no speech (banners only)
  --wait SECONDS     keep a loopback server up so "Mark seen" works, and print the callbacks it receives
  --previews DIR     also render each banner through POST /v1/preview (light and dark) into DIR as PNGs
                     (--scale 1 to 3 sets the pixel scale)
  --cleanup          remove BidBot's banners, manifest, template and history, then exit
  --print NAME       print the manifest or the template JSON and exit (no Herald needed)

To drive a second Herald (a development build) set HERALD_PORT and HERALD_SUPPORT_DIR, as the CLI does.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import threading
import time
import urllib.error
import urllib.request
import zlib
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
# The in-repo client first; an installed or copied herald.py works too.
sys.path.insert(0, str(HERE.parents[2] / "clients" / "python"))
try:
    from herald import Herald, HeraldError, HeraldUnavailable
except ImportError:  # pragma: no cover
    sys.exit("herald.py not found: run this from a checkout of the Herald repository, or copy "
             "clients/python/herald.py next to this script.")

APP = "bidbot"
TEMPLATE_NAME = "bid-card"
SHORTCUT_NAME = "Bid follow-up"
ASSETS = HERE / "assets"


# ---------------------------------------------------------------------------------------------------------
# Pictures. BidBot sends an `image` with each event; to stay dependency-free the script draws four small
# PNGs itself (a check, a cross, a clock and an app icon) with a few lines of anti-aliased geometry.
# ---------------------------------------------------------------------------------------------------------

def _seg(px: float, py: float, a: Tuple[float, float], b: Tuple[float, float]) -> float:
    """Distance from a point to the segment a-b."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _png(size: int, top: Tuple[int, int, int], bottom: Tuple[int, int, int], glyph) -> bytes:
    """A size x size RGBA PNG: a vertical gradient with a white glyph on it. `glyph(x, y)` returns coverage 0...1."""
    rows = bytearray()
    for y in range(size):
        t = y / (size - 1)
        base = [round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)]
        rows.append(0)  # filter type: none
        for x in range(size):
            c = max(0.0, min(1.0, glyph(x + 0.5, y + 0.5)))
            rows += bytes(round(base[i] + (255 - base[i]) * c) for i in range(3)) + b"\xff"

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")


def _stroke(points: List[Tuple[float, float]], width: float):
    def glyph(x: float, y: float) -> float:
        d = min(_seg(x, y, points[i], points[i + 1]) for i in range(len(points) - 1))
        return 0.5 - (d - width / 2)
    return glyph


def _union(*glyphs):
    return lambda x, y: max(g(x, y) for g in glyphs)


def _ring(cx: float, cy: float, radius: float, width: float):
    return lambda x, y: 0.5 - (abs(math.hypot(x - cx, y - cy) - radius) - width / 2)


def make_assets() -> Dict[str, Path]:
    """Writes the pictures next to this script when they are missing; returns name -> path."""
    ASSETS.mkdir(exist_ok=True)
    s = 144
    specs = {
        "won": ((70, 190, 120), (30, 130, 80), _stroke([(40, 76), (62, 99), (106, 49)], 15)),
        "lost": ((226, 98, 90), (178, 44, 44),
                 _union(_stroke([(48, 48), (96, 96)], 15), _stroke([(96, 48), (48, 96)], 15))),
        "deadline": ((250, 178, 60), (226, 130, 24),
                     _union(_ring(72, 72, 38, 10), _stroke([(72, 72), (72, 47)], 9), _stroke([(72, 72), (91, 83)], 9))),
        "icon": ((88, 130, 250), (52, 88, 220),
                 _union(_stroke([(40, 78), (72, 44), (104, 78)], 14), _stroke([(72, 44), (72, 104)], 14))),
    }
    out: Dict[str, Path] = {}
    for name, (top, bottom, glyph) in specs.items():
        path = ASSETS / f"{name}.png"
        if not path.exists():
            path.write_bytes(_png(s, top, bottom, glyph))
        out[name] = path
    return out


# ---------------------------------------------------------------------------------------------------------
# The manifest: what BidBot can send and what the user can press.
# ---------------------------------------------------------------------------------------------------------

def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_manifest(assets: Dict[str, Path]) -> Dict[str, Any]:
    return {
        "app": APP,
        "appName": "BidBot",
        "icon": str(assets["icon"]),
        "version": 1,
        # The tokens a template can bind as {bid}, {amount}, ... A notification sends them as top-level keys.
        # `sample` values are what the Designer and POST /v1/preview ("data": "sample") draw.
        "fields": [
            {"key": "title", "type": "text", "required": True, "sample": "Bid accepted"},
            {"key": "bid", "type": "text", "sample": "BID-4021 · Brand refresh"},
            {"key": "amount", "type": "text", "sample": "$4,200"},
            {"key": "client", "type": "text", "sample": "Acme Corp"},
            {"key": "deadline", "type": "date", "sample": iso(datetime.now(timezone.utc) + timedelta(hours=2, minutes=1))},
            {"key": "url", "type": "url", "sample": "https://example.com/bids/4021"},
            {"key": "image", "type": "image", "sample": str(assets["won"])},
        ],
        # BidBot's own buttons. A notification names them with "buttons"; a template may relabel, restyle,
        # reorder or hide them by id (see actionRules in the template).
        "actions": [
            {"id": "open", "label": "Open bid", "kind": "url", "url": "{url}"},
            {"id": "seen", "label": "Mark seen", "kind": "callback"},
        ],
        # Used whenever a notification names no template.
        "defaultTemplate": TEMPLATE_NAME,
    }


# ---------------------------------------------------------------------------------------------------------
# The default template: a 3 x 4 grid.
#
#            col 0 (72 pt)   col 1 (fill)        col 2 (fill)        col 3 (auto)
#   row 0    image  (spans   title (spans cols 1-2)                  amount badge
#   row 1    rows 0-1)       "client . bid" (spans cols 1-2)         deadline, relative
#   row 2    actions: BidBot's buttons + the template's "Follow up" Shortcut + Snooze (spans all 4 columns)
#
# collapseEmpty is on: with no deadline (accepted and lost events) the timestamp cell disappears.
# ---------------------------------------------------------------------------------------------------------

def build_template() -> Dict[str, Any]:
    return {
        "name": TEMPLATE_NAME,
        "app": APP,
        "layoutVersion": 2,
        "collapseEmpty": True,
        "grid": {"rows": 3, "cols": 4, "rowSizes": ["auto", "auto", "auto"],
                 "colSizes": ["72", "fill", "fill", "auto"], "gap": 8, "padding": 14, "width": 400},
        "cells": [
            {"id": "img", "row": 0, "col": 0, "rowSpan": 2, "align": "topLeading",
             "component": {"type": "image", "binding": "{image}", "fit": "cover", "cornerRadius": 10, "aspectRatio": 1}},
            {"id": "title", "row": 0, "col": 1, "colSpan": 2, "align": "topLeading",
             "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
            {"id": "amount", "row": 0, "col": 3, "align": "topTrailing",
             "component": {"type": "badge", "binding": "{amount}", "color": "#3B6EF5"}},
            {"id": "who", "row": 1, "col": 1, "colSpan": 2, "align": "topLeading",
             "component": {"type": "text", "binding": "{client} · {bid}", "style": "subtitle", "maxLines": 2}},
            {"id": "due", "row": 1, "col": 3, "align": "topTrailing",
             "component": {"type": "timestamp", "binding": "{deadline}", "relative": True, "style": "caption"}},
            {"id": "acts", "row": 2, "col": 0, "colSpan": 4,
             "component": {"type": "actions", "source": "merged", "layout": "row", "maxVisible": 4}},
        ],
        # The template's own action, owned by the user, not by BidBot. It hands a line of text to the
        # Shortcut named below; Herald asks once before the first run (see the README).
        "actionRules": [
            {"add": {"id": "followup", "label": "Follow up", "kind": "shortcut", "shortcut": SHORTCUT_NAME,
                     "input": "{client}: {bid} ({amount})\n{url}"}},
        ],
        "snooze": True,
        "persistent": True,
    }


# ---------------------------------------------------------------------------------------------------------
# The events.
# ---------------------------------------------------------------------------------------------------------

def build_events(assets: Dict[str, Path], now: datetime) -> List[Dict[str, Any]]:
    return [
        {"key": "accepted", "id": "bid-4021", "title": "Bid accepted", "bid": "BID-4021 · Brand refresh",
         "amount": "$4,200", "client": "Acme Corp", "image": assets["won"], "sound": "Glass", "priority": "high",
         "url": "https://example.com/bids/4021",
         "say": "Bid accepted. Acme Corp signed off on forty two hundred dollars."},
        {"key": "lost", "id": "bid-4017", "title": "Bid lost", "bid": "BID-4017 · Mobile app",
         "amount": "$9,800", "client": "Globex", "image": assets["lost"], "sound": "Basso", "priority": "normal",
         "url": "https://example.com/bids/4017",
         "say": "Bid lost. Globex went with another vendor."},
        {"key": "deadline", "id": "bid-4023", "title": "Deadline in 2 hours", "bid": "BID-4023 · Data pipeline",
         "amount": "$6,500", "client": "Initech", "image": assets["deadline"], "sound": "Ping", "priority": "high",
         "url": "https://example.com/bids/4023", "deadline": iso(now + timedelta(hours=2, minutes=1)),
         "say": "Heads up. The Initech bid is due in two hours."},
    ]


def event_payload(event: Dict[str, Any], quiet: bool, callbacks: bool) -> Dict[str, Any]:
    """The /v1/notify body for one event. The fields at the top level are the manifest's."""
    buttons = [{"label": "Open bid", "url": event["url"]}]
    if callbacks:
        buttons.append({"label": "Mark seen", "callback": {"payload": {"bid": event["id"]}}})
    payload: Dict[str, Any] = {
        "app": APP,
        "id": event["id"],                      # the same id later replaces this banner in place
        "title": event["title"],
        "bid": event["bid"], "amount": event["amount"], "client": event["client"],
        "url": event["url"],
        "image": str(event["image"]),
        "priority": event["priority"],
        "buttons": buttons,
        "sound": "none" if quiet else event["sound"],
    }
    if "deadline" in event:
        payload["deadline"] = event["deadline"]
    if not quiet:
        payload["speak"] = {"text": event["say"], "speed": 1.05}
    return payload


# ---------------------------------------------------------------------------------------------------------
# Talking to Herald. herald.py (1.1) covers register / notify / dismiss; manifests, templates, shortcuts and
# previews are plain requests, so a small subclass adds them.
# ---------------------------------------------------------------------------------------------------------

class BidBotHerald(Herald):
    def put_manifest(self, manifest: Dict[str, Any]) -> Any:
        return self._request("PUT", "/v1/manifest", manifest)

    def put_template(self, template: Dict[str, Any]) -> Any:
        return self._request("PUT", "/v1/templates", template)

    def delete_manifest(self, app: str) -> Any:
        return self._request("DELETE", "/v1/manifest", query={"app": app})

    def delete_template(self, app: str, name: str) -> Any:
        return self._request("DELETE", "/v1/templates", query={"app": app, "name": name})

    def shortcuts(self) -> List[str]:
        return self._request("GET", "/v1/shortcuts").get("items", [])

    def preview(self, template: str, data: Dict[str, Any], appearance: str, scale: float = 2) -> bytes:
        """POST /v1/preview answers with PNG bytes, not JSON."""
        body = json.dumps({"template": template, "app": APP, "data": data,
                           "appearance": appearance, "scale": scale}).encode()
        req = urllib.request.Request(self.base_url + "/v1/preview", data=body, method="POST", headers={
            "Content-Type": "application/json", "Authorization": f"Bearer {self.token}"})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            raise HeraldError(e.code, e.read().decode(errors="replace")) from None
        except OSError as e:
            raise HeraldUnavailable() from e


def connect() -> BidBotHerald:
    """The local Herald, or the one HERALD_PORT / HERALD_SUPPORT_DIR point at (a development build)."""
    support = os.environ.get("HERALD_SUPPORT_DIR")
    token: Optional[str] = None
    port: Optional[int] = None
    if support:
        folder = Path(support).expanduser()
        try:
            token = (folder / "token").read_text().strip() or None
            port_text = (folder / "port").read_text().strip()
            port = int(port_text) if port_text.isdigit() else None
        except OSError:
            pass
    if os.environ.get("HERALD_PORT", "").isdigit():
        port = int(os.environ["HERALD_PORT"])
    return BidBotHerald(port=port, token=token)


class CallbackServer:
    """A loopback server for the "Mark seen" button: Herald POSTs {notificationId, app, action, payload} to
    the callbackURL given at registration; any 2xx answer tells Herald the action happened (it then dismisses
    the banner)."""

    def __init__(self) -> None:
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802 (http.server naming)
                size = int(self.headers.get("Content-Length") or 0)
                try:
                    event = json.loads(self.rfile.read(size) or b"{}")
                except ValueError:
                    event = {}
                outer.received.append(event)
                print(f"  callback: {event.get('action')!r} on {event.get('notificationId')} "
                      f"payload={json.dumps(event.get('payload'))}")
                reply = b'{"ok":true}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(reply)))
                self.end_headers()
                self.wfile.write(reply)

            def log_message(self, *args: Any) -> None:  # keep the console to our own lines
                pass

        self.received: List[Dict[str, Any]] = []
        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.server.server_address[1]}/herald"

    def close(self) -> None:
        self.server.shutdown()


# ---------------------------------------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="BidBot: a worked Herald example.", formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--quiet", action="store_true", help="no chime and no speech")
    parser.add_argument("--wait", type=float, default=0.0, metavar="SECONDS",
                        help="serve the 'Mark seen' callback for this long after sending")
    parser.add_argument("--delay", type=float, default=1.5, metavar="SECONDS", help="pause between events (default 1.5)")
    parser.add_argument("--previews", type=Path, metavar="DIR", help="render each banner via /v1/preview into DIR")
    parser.add_argument("--scale", type=float, default=2.0, help="pixel scale of --previews, 1 to 3 (default 2)")
    parser.add_argument("--cleanup", action="store_true", help="remove BidBot's banners, manifest, template and history")
    parser.add_argument("--print", dest="print_what", choices=["manifest", "template"], help="print that JSON and exit")
    args = parser.parse_args()

    assets = make_assets()
    if args.print_what:
        doc = build_manifest(assets) if args.print_what == "manifest" else build_template()
        print(json.dumps(doc, indent=2, ensure_ascii=False))
        return 0

    h = connect()
    try:
        info = h.health()
    except HeraldError as e:
        print(f"{e}\nStart Herald.app (or a Debug build with HERALD_PORT / HERALD_SUPPORT_DIR) and run this again.",
              file=sys.stderr)
        return 2
    print(f"Herald {info.get('version')} answers on port {h.port}")

    try:
        if args.cleanup:
            h.dismiss_all(APP)
            for call in (lambda: h.delete_manifest(APP), lambda: h.delete_template(APP, TEMPLATE_NAME), lambda: h.clear_history(APP)):
                try:
                    call()
                except HeraldError:
                    pass  # already gone
            print("BidBot removed: banners, manifest, template, history")
            return 0
        return run(h, args, assets)
    except HeraldError as e:
        print(f"Herald refused a request: {e}", file=sys.stderr)
        return 1


def run(h: BidBotHerald, args: argparse.Namespace, assets: Dict[str, Path]) -> int:
    listener = CallbackServer() if args.wait > 0 else None

    # 1. Register the app. The callback URL is only given while this script is listening for it.
    registration: Dict[str, Any] = {"appName": "BidBot", "icon": str(assets["icon"]),
                                    "defaults": {"sound": "none" if args.quiet else "Glass", "persistent": True}}
    if listener:
        registration["callbackURL"] = listener.url
    h.register(APP, **registration)
    print(f"1. registered '{APP}'" + (f" (callbacks to {listener.url})" if listener else ""))

    # 2. The manifest: fields with samples, and the two actions BidBot offers.
    h.put_manifest(build_manifest(assets))
    print("2. manifest saved: fields bid, amount, client, deadline, url, image")

    # 3. The default template. The manifest names it, so a notification does not have to.
    h.put_template(build_template())
    print(f"3. template '{TEMPLATE_NAME}' saved (3 x 4 grid, default for {APP})")
    try:
        if SHORTCUT_NAME not in h.shortcuts():
            print(f"   note: no Shortcut named '{SHORTCUT_NAME}' yet; the Follow up button is wired and will work "
                  f"once you create one (README, \"The Shortcut\").")
    except HeraldError:
        pass

    now = datetime.now(timezone.utc)
    events = build_events(assets, now)

    # 4. Previews, if asked: the same GridBannerView, drawn offscreen, in both appearances.
    if args.previews:
        args.previews.mkdir(parents=True, exist_ok=True)
        for ev in events:
            data = event_payload(ev, quiet=True, callbacks=True)
            for appearance in ("light", "dark"):
                path = args.previews / f"{ev['key']}-{appearance}.png"
                path.write_bytes(h.preview(TEMPLATE_NAME, data, appearance, args.scale))
        print(f"   previews written to {args.previews}")

    # 5. The events. The fields ride at the top level; Herald binds them to the template's cells.
    for i, ev in enumerate(events):
        if i:
            time.sleep(args.delay)
        nid = h.notify(APP, ev["title"], **{k: v for k, v in event_payload(ev, args.quiet, bool(listener)).items()
                                            if k not in ("app", "title")})
        print(f"4. sent {ev['key']:<8} -> {nid}")

    if listener:
        print(f"Waiting {args.wait:g} s for button presses (press 'Mark seen' on a banner)...")
        time.sleep(args.wait)
        listener.close()
        print(f"{len(listener.received)} callback(s) received")
    print("Done. History: Herald menu > History > BidBot. Remove everything with --cleanup.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
