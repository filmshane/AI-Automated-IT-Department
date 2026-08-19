#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path

def summarize_file(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = []
    keys = ("RESULT:", "REBOOT:", "Pending reboot", "STALE", "SUCCESS", "REVIEW", "WHATIF", "NO_UPDATES")
    for key in keys:
        for line in text.splitlines():
            if key.lower() in line.lower():
                lines.append(f"{path.name}: {line.strip()}")
    if not lines:
        lines.append(f"{path.name}: (no RESULT markers — human review)")
    return lines

def main() -> None:
    ap = argparse.ArgumentParser(); ap.add_argument("report_dir", type=Path)
    args = ap.parse_args()
    print(f"IT Copilot digest for {args.report_dir}")
    print("=" * 60)
    paths = list(args.report_dir.rglob("*"))
    files = [p for p in paths if p.is_file()]
    if not files:
        print("No reports found."); return
    for p in sorted(files):
        if p.suffix.lower() == ".csv":
            print(f"- {p.name}: CSV evidence ({p.stat().st_size} bytes)"); continue
        if p.suffix.lower() in {".txt", ".log"} or "summary" in p.name.lower() or "comparison" in p.name.lower():
            for line in summarize_file(p):
                print(f"- {line}")

if __name__ == "__main__":
    main()
