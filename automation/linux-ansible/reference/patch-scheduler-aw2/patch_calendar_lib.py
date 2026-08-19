#!/usr/bin/env python3
"""Patch calendar helpers: load YAML, resolve dates, expand contacts, list hosts."""
from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


WEEKDAY = {
    "mon": 0, "monday": 0,
    "tue": 1, "tues": 1, "tuesday": 1,
    "wed": 2, "wednesday": 2,
    "thu": 3, "thur": 3, "thurs": 3, "thursday": 3,
    "fri": 4, "friday": 4,
    "sat": 5, "saturday": 5,
    "sun": 6, "sunday": 6,
}


def load_calendar(path: str | Path) -> dict[str, Any]:
    path = Path(path)
    text = path.read_text()
    if yaml is not None:
        return yaml.safe_load(text)
    # minimal fallback parser not ideal — require pyyaml
    raise RuntimeError("PyYAML is required. Install with: pip install --user pyyaml")


def expand_recipients(entries: list[str], contacts: dict[str, str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for e in entries or []:
        e = (e or "").strip()
        if not e:
            continue
        if "@" in e:
            addr = e
        else:
            addr = contacts.get(e) or contacts.get(e.lower())
            if not addr:
                continue
        if addr not in seen:
            seen.add(addr)
            out.append(addr)
    return out


def first_weekday_of_month(year: int, month: int, wd: int) -> date:
    d = date(year, month, 1)
    delta = (wd - d.weekday()) % 7
    return d + timedelta(days=delta)


def last_weekday_of_month(year: int, month: int, wd: int) -> date:
    # last day of month
    if month == 12:
        d = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        d = date(year, month + 1, 1) - timedelta(days=1)
    delta = (d.weekday() - wd) % 7
    return d - timedelta(days=delta)


def resolve_rule_date(year: int, month: int, week: str, weekday: str) -> date:
    wd = WEEKDAY[weekday.lower()]
    week = week.lower()
    if week == "first":
        return first_weekday_of_month(year, month, wd)
    if week == "last":
        return last_weekday_of_month(year, month, wd)
    raise ValueError(f"Unsupported week={week!r}")


@dataclass
class Job:
    id: str
    name: str
    inventory_group: str
    patch_date: date
    patch_time: str  # HH:MM
    window: str
    recipients: list[str]
    owners_text: str
    tier: str = ""
    enabled: bool = True
    notes: str = ""
    source: str = "calendar"  # calendar|override

    @property
    def patch_time_display(self) -> str:
        hh, mm = self.patch_time.split(":")
        h = int(hh)
        ampm = "AM" if h < 12 else "PM"
        h12 = h % 12 or 12
        return f"{h12}:{mm} {ampm}"


def materialize_jobs(cal: dict[str, Any], year: int, month: int) -> list[Job]:
    contacts = cal.get("contacts") or {}
    jobs: list[Job] = []

    for app in cal.get("applications") or []:
        if not app.get("enabled", True):
            continue
        try:
            d = resolve_rule_date(year, month, app["week"], app["weekday"])
        except Exception as e:
            print(f"WARN skip {app.get('id')}: {e}")
            continue
        jobs.append(
            Job(
                id=app["id"],
                name=app.get("name") or app["id"],
                inventory_group=app["inventory_group"],
                patch_date=d,
                patch_time=str(app["patch_time"]),
                window=app.get("window") or "",
                recipients=expand_recipients(app.get("recipients") or [], contacts),
                owners_text=app.get("owners_text") or "",
                tier=app.get("tier") or "",
                enabled=True,
                notes=app.get("notes") or "",
                source="calendar",
            )
        )

    for ov in cal.get("overrides") or []:
        if not ov.get("enabled", True):
            continue
        d = date.fromisoformat(str(ov["patch_date"]))
        if d.year != year or d.month != month:
            continue
        rcpt = ov.get("recipients") or []
        # overrides may use raw emails
        expanded = expand_recipients(rcpt, contacts) if any("@" not in str(x) for x in rcpt) else list(rcpt)
        # if mix
        expanded = expand_recipients(
            [str(x) for x in rcpt], contacts
        )
        jobs.append(
            Job(
                id=ov["id"],
                name=ov.get("name") or ov["id"],
                inventory_group=ov["inventory_group"],
                patch_date=d,
                patch_time=str(ov["patch_time"]),
                window=ov.get("window") or "",
                recipients=expanded,
                owners_text=ov.get("owners_text") or "",
                tier=ov.get("tier") or "override",
                enabled=True,
                notes=ov.get("notes") or "",
                source="override",
            )
        )

    jobs.sort(key=lambda j: (j.patch_date, j.patch_time, j.inventory_group))
    return jobs


def list_hosts(group: str, inventories: list[str]) -> list[str]:
    hosts: list[str] = []
    for inv in inventories:
        try:
            out = subprocess.check_output(
                ["ansible-inventory", "-i", inv, "--list"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            data = json.loads(out)
        except Exception:
            continue
        g = data.get(group) or {}
        h = list(g.get("hosts") or [])
        if not h:
            for child in g.get("children") or []:
                h.extend((data.get(child) or {}).get("hosts") or [])
        hosts.extend(h)
    # unique
    seen, uniq = set(), []
    for h in hosts:
        if h not in seen:
            seen.add(h)
            uniq.append(h)
    return uniq


def inventories_from_cal(cal: dict[str, Any]) -> list[str]:
    invs = [cal.get("inventory") or "/etc/ansible/hosts"]
    for e in cal.get("extra_inventories") or []:
        if e not in invs:
            invs.append(e)
    return invs
