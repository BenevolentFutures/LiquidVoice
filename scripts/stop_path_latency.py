#!/usr/bin/env python3
"""Median and p90 per stage of the dictation stop path, from Liquid Voice's own log.

Every build logs one STOP_SUMMARY line per dictation (see StopPathTrace.swift). This script
reads those lines and prints a table. Nothing is sent anywhere.

    scripts/stop_path_latency.py                      # the installed app's log
    scripts/stop_path_latency.py --dev                # Debug builds and test runs
    scripts/stop_path_latency.py ~/Library/Logs/Fluid/Fluid.log  # builds before the identity change
    scripts/stop_path_latency.py --trigger benchmark  # only the fixture benchmark runs
    scripts/stop_path_latency.py --legacy             # logs from builds before STOP_SUMMARY

--legacy rebuilds the same stages from the older APP_BENCH / ASR_BENCH / TYPING_BENCH lines.
There the trigger is the "Hotkey route ... action=stop" line (toggle mode, wall clock, so +-1 ms),
and the paste stage ends at insert_return, which also includes the terminal paste-consumption
wait: it is an upper bound on "paste posted".
"""

import argparse
import json
import os
import re
import statistics
import sys
from datetime import datetime

STAGES = ["releaseMs", "captureMs", "drainMs", "asrMs", "returnMs", "postMs", "handoffMs", "pasteMs", "totalMs"]
DESCRIPTIONS = {
    "releaseMs": "trigger -> stop pipeline entered",
    "captureMs": "-> mic stopped, stop cue",
    "drainMs": "-> final ASR handed to model",
    "asrMs": "model inference",
    "returnMs": "-> stop() returned",
    "postMs": "-> text final (formatting/AI)",
    "handoffMs": "-> handed to typing",
    "pasteMs": "-> paste posted",
    "totalMs": "trigger -> last stage",
}

FIELD = re.compile(r"(\w+)=(\S+)")
WALL = re.compile(r"^\[(\d\d):(\d\d):(\d\d)\.(\d{3})\]")
BENCH_T = re.compile(r"(APP_BENCH|ASR_BENCH|TYPING_BENCH) t=([0-9.]+) (?:session=\d+ )?(\w+)")


def percentile(values, p):
    ordered = sorted(values)
    if not ordered:
        return float("nan")
    rank = p * (len(ordered) - 1)
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (rank - lower)


def read_lines(paths):
    for path in paths:
        try:
            with open(path, errors="replace") as handle:
                yield from handle
        except FileNotFoundError:
            continue


def parse_summaries(lines, trigger=None):
    rows = []
    for line in lines:
        index = line.find("STOP_SUMMARY ")
        if index < 0:
            continue
        fields = dict(FIELD.findall(line[index:]))
        if trigger and fields.get("trigger") != trigger:
            continue
        rows.append(fields)
    return rows


def wall_seconds(line):
    match = WALL.match(line)
    if not match:
        return None
    hours, minutes, seconds, millis = (int(g) for g in match.groups())
    return hours * 3600 + minutes * 60 + seconds + millis / 1000


def parse_legacy(lines):
    """Rebuilds per-dictation stages from pre-trace benchmark lines (one dictation at a time)."""
    rows = []
    current = None
    wall_offset = None  # uptime - wall clock, from any line carrying both
    pending_trigger = None

    def close():
        if current and "stop_enter" in current:
            rows.append(current)

    for line in lines:
        wall = wall_seconds(line)
        bench = BENCH_T.search(line)
        if bench and wall is not None:
            wall_offset = float(bench.group(2)) - wall
        if "Hotkey route" in line and "action=stop" in line and wall is not None and wall_offset is not None:
            pending_trigger = wall + wall_offset
            continue
        if not bench:
            continue
        uptime = float(bench.group(2))
        event = bench.group(3)
        if event == "stop_path_enter":
            close()
            current = {"stop_enter": uptime}
            if pending_trigger is not None and 0 <= uptime - pending_trigger < 5:
                current["trigger"] = pending_trigger
            pending_trigger = None
            continue
        if current is None:
            continue
        mapping = {
            "audio_capture_prepared": "capture_stopped",
            "stop_ensure_ready": "asr_begin",
            "final_done": "asr_end",
            "asr_stop_return": "asr_return",
            "text_ready": "text_ready",
            "asr_type_request": "handoff",
            "insert_return": "paste_posted",
        }
        stage = mapping.get(event)
        if stage and stage not in current:
            current[stage] = uptime
            if stage == "paste_posted":
                rows.append(current)
                current = None
    close()

    order = [
        ("releaseMs", "stop_enter"),
        ("captureMs", "capture_stopped"),
        ("drainMs", "asr_begin"),
        ("asrMs", "asr_end"),
        ("returnMs", "asr_return"),
        ("postMs", "text_ready"),
        ("handoffMs", "handoff"),
        ("pasteMs", "paste_posted"),
    ]
    summaries = []
    for marks in rows:
        fields = {"trigger": "legacy"}
        previous = marks.get("trigger")
        for name, stage in order:
            if stage in marks and previous is not None:
                fields[name] = f"{(marks[stage] - previous) * 1000:.1f}"
            else:
                fields[name] = "-"
            if stage in marks:
                previous = marks[stage]
        start = marks.get("trigger", marks["stop_enter"])
        last = max(marks.values())
        fields["totalMs"] = f"{(last - start) * 1000:.1f}"
        fields["totalFrom"] = "trigger" if "trigger" in marks else "stop_enter"
        summaries.append(fields)
    return summaries


def table(rows):
    stats = {}
    for stage in STAGES:
        values = []
        for row in rows:
            try:
                values.append(float(row.get(stage, "-")))
            except ValueError:
                pass
        stats[stage] = {
            "n": len(values),
            "median": percentile(values, 0.5),
            "p90": percentile(values, 0.9),
            "mean": statistics.fmean(values) if values else float("nan"),
        }
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="*", help="log files (default: the installed app's log and its rotation)")
    parser.add_argument("--dev", action="store_true", help="read the Debug build log (~/Library/Logs/LiquidVoice-Dev)")
    parser.add_argument("--legacy", action="store_true", help="rebuild stages from pre-trace APP_BENCH lines")
    parser.add_argument("--trigger", help="only this trigger (hold_release, toggle, automatic, ui, benchmark)")
    parser.add_argument("--last", type=int, help="only the last N dictations")
    parser.add_argument("--json", action="store_true", help="print JSON instead of a table")
    args = parser.parse_args()

    folder = os.path.expanduser("~/Library/Logs/LiquidVoice-Dev" if args.dev else "~/Library/Logs/LiquidVoice")
    paths = args.logs or [os.path.join(folder, "Fluid.log.1"), os.path.join(folder, "Fluid.log")]
    lines = list(read_lines(paths))
    rows = parse_legacy(lines) if args.legacy else parse_summaries(lines, args.trigger)
    if args.last:
        rows = rows[-args.last :]
    if not rows:
        print("No dictations found.", file=sys.stderr)
        return 1

    stats = table(rows)
    if args.json:
        print(json.dumps({"dictations": len(rows), "stages": stats}, indent=2))
        return 0
    print(f"{len(rows)} dictations from {', '.join(p for p in paths if os.path.exists(p))}")
    print(f"{'stage':<11} {'meaning':<34} {'n':>4} {'median':>8} {'p90':>8}")
    for stage in STAGES:
        entry = stats[stage]
        if entry["n"] == 0:
            continue
        print(f"{stage:<11} {DESCRIPTIONS[stage]:<34} {entry['n']:>4} {entry['median']:>8.1f} {entry['p90']:>8.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
