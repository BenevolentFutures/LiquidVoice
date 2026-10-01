#!/usr/bin/env python3
"""Capture the binding Signal prototype's overlay states as PNGs, for the native comparison.

    python3 scripts/capture_prototype.py [--page signal/round6.html]

Serves design/visual-language/prototypes over 127.0.0.1, opens each state in headless Chromium
(nothing on screen) at 2x, and writes design/visual-language/native-renders/prototype/<theme>-<state>.png
cropped to the overlay (rails and pill, plus an 18 pt margin; the history card included for the
history states) and rects.json with every URL and crop. Needs Python Playwright with Chromium (on this machine: python3.11).
"""
import argparse
import functools
import http.server
import json
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent / "design/visual-language"
OUT = ROOT / "native-renders/prototype"
MARGIN = 18
RAIL = 36

STATES = [
    ("01-listening", "state=listening"),
    ("02-listening-hover", "state=listening&hover=1"),
    ("03-listening-hover-cancel", "state=listening&hoverChip=cancel"),
    ("04-listening-armed", "state=listening&armed=1"),
    ("05-transcribing", "state=transcribing"),
    ("06-pasted", "state=delivered&hold=1"),
    ("07-failed", "state=failed&reason=nofocus"),
    ("08-failed-copied", "state=failed&reason=nofocus&copied=1"),
    ("09-history", "state=history"),
    ("10-history-hover-row", "state=history&hoverRow=2"),
    ("13-countdown", "state=countdown&t=0.9"),
    ("14-countdown-canceled", "state=countdown&t=0.9&canceled=1"),
    ("15-sent", "state=sent&hold=1"),
    ("16-noreturn", "state=listening&armed=1&target=noreturn"),
    ("17-failed-clipboardkept", "state=failed&reason=clipboardkept"),
    ("18-timedout", "state=timedout"),
    ("19-asrback", "state=asrback"),
    ("20-micoff", "state=micoff"),
]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def serve():
    handler = functools.partial(QuietHandler, directory=str(ROOT / "prototypes"))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def rect(page, selector):
    return page.evaluate(
        """(s) => { const e = document.querySelector(s); if (!e || !e.offsetParent && getComputedStyle(e).display === 'none') return null;
                    const r = e.getBoundingClientRect(); return r.width ? {x: r.x, y: r.y, width: r.width, height: r.height} : null; }""",
        selector,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--page", default="signal/round6.html")
    args = parser.parse_args()
    server = serve()
    port = server.server_address[1]
    OUT.mkdir(parents=True, exist_ok=True)
    rects = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1600, "height": 900}, device_scale_factor=2)
        for theme in ("dark", "light"):
            for name, query in STATES:
                url = f"http://127.0.0.1:{port}/{args.page}?theme={theme}&{query}"
                page.goto(url)
                page.wait_for_timeout(900)
                pill = rect(page, ".sg-pill")
                if pill is None:
                    print(f"skip {theme}-{name}: no pill")
                    continue
                left = pill["x"] - RAIL - MARGIN
                top = pill["y"] - MARGIN
                right = pill["x"] + pill["width"] + RAIL + MARGIN
                bottom = pill["y"] + pill["height"] + MARGIN
                hist = rect(page, ".sg-hist.is-open")
                if hist:
                    left = min(left, hist["x"] - MARGIN)
                    top = min(top, hist["y"] - MARGIN)
                    right = max(right, hist["x"] + hist["width"] + MARGIN)
                clip = {"x": left, "y": top, "width": right - left, "height": bottom - top}
                file = f"{theme}-{name}.png"
                page.screenshot(path=str(OUT / file), clip=clip)
                rects[file] = {"url": url.replace(f":{port}", ":PORT"), "cropBoxCssPx": clip, "pill": pill}
                print(file, round(pill["width"]), "x", round(pill["height"]))
        browser.close()
    server.shutdown()
    existing = OUT / "rects.json"
    merged = json.loads(existing.read_text()) if existing.exists() else {}
    merged.update(rects)
    existing.write_text(json.dumps(merged, indent=2) + "\n")


if __name__ == "__main__":
    main()
