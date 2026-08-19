#!/usr/bin/env python3
"""Send patch window notification emails for an inventory group."""
from __future__ import annotations

import argparse
import smtplib
import subprocess
import sys
from datetime import datetime
from email.mime.text import MIMEText
from pathlib import Path
from zoneinfo import ZoneInfo

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from patch_calendar_lib import list_hosts, load_calendar, inventories_from_cal  # noqa: E402

TZ = ZoneInfo("America/Los_Angeles")
CAL_PATH = SCRIPT_DIR / "patch_calendar.yaml"


def format_when(patch_date: str, patch_time: str) -> str:
    dt = datetime.strptime(f"{patch_date} {patch_time}", "%Y-%m-%d %H:%M").replace(tzinfo=TZ)
    return dt.strftime("%A, %B %d, %Y at %I:%M %p %Z").replace(" 0", " ")


def format_time_only(patch_time: str) -> str:
    hh, mm = patch_time.split(":")
    h = int(hh)
    ampm = "AM" if h < 12 else "PM"
    h12 = h % 12 or 12
    return f"{h12}:{mm} {ampm} PT"


def build(
    notify_type: str,
    group: str,
    hosts: list[str],
    human_when: str,
    patch_date: str,
    patch_time: str,
    app_name: str = "",
    window: str = "",
    owners: str = "",
    job_id: str = "",
) -> tuple[str, str]:
    """Build a concise, business-professional notification."""
    label = app_name or group
    count = len(hosts)
    host_block = "\n".join(f"  • {h}" for h in hosts) or "  • (no hosts found in inventory)"
    time_short = format_time_only(patch_time)
    window_line = window.strip() if window and window.strip() and "NEED TO CONFIRM" not in window.upper() else ""

    if notify_type == "morning":
        subject = f"Scheduled Maintenance Notice — {label} — {patch_date} {time_short}"
        purpose = (
            f"As part of our scheduled maintenance program, operating system patches "
            f"will be applied today to the hosts listed below."
        )
        when_blurb = f"Maintenance is scheduled to begin at {time_short} on {human_when.split(' at ')[0]}."
    elif notify_type == "reminder":
        subject = f"Reminder: Maintenance This Evening — {label} — {time_short}"
        purpose = (
            f"This is a reminder that scheduled operating system patching for "
            f"{label} will take place today."
        )
        when_blurb = f"Maintenance will begin at {time_short}."
    else:
        subject = f"Scheduled Maintenance — {label} — {patch_date} {time_short}"
        purpose = (
            f"As part of our scheduled maintenance program, operating system patches "
            f"will be applied to the hosts listed below."
        )
        when_blurb = f"Maintenance is scheduled for {human_when}."

    window_section = f"\nChange window:  {window_line}" if window_line else ""

    body = f"""Hi Team,

{purpose}

{when_blurb}

Details
-------
Environment:   {label}
Inventory:     {group}
Start time:    {human_when}{window_section}
Host count:    {count}

Hosts to be patched
-------------------
{host_block}

Impact
------
Please plan accordingly. Brief service impact may occur while packages are updated.
Kernel packages are excluded from this process, and hosts are not rebooted automatically
unless separately communicated.

If you have questions or concerns about this maintenance window, please contact
SysOps-UNIX or the application owner before the start time.

Regards,
SysOps-UNIX
Linux Patch Automation
"""
    return subject, body


def send_mail(
    subject: str,
    body: str,
    mail_from: str,
    recipients: list[str],
    smtp_host: str,
    smtp_port: int,
) -> None:
    msg = MIMEText(body, _charset="utf-8")
    msg["Subject"] = subject
    msg["From"] = mail_from
    msg["To"] = ", ".join(recipients)
    msg["X-Ansible-Patch-Notify"] = "true"
    with smtplib.SMTP(smtp_host, smtp_port, timeout=60) as s:
        s.ehlo()
        s.sendmail(mail_from, recipients, msg.as_string())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--group", required=True)
    ap.add_argument("--type", required=True, choices=["morning", "reminder", "custom"])
    ap.add_argument("--patch-date", required=True)
    ap.add_argument("--patch-time", required=True)
    ap.add_argument("--to", required=True, help="comma-separated emails")
    ap.add_argument("--app-name", default="")
    ap.add_argument("--window", default="")
    ap.add_argument("--owners", default="")
    ap.add_argument("--job-id", default="")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--calendar", default=str(CAL_PATH))
    args = ap.parse_args()

    recipients = [x.strip() for x in args.to.split(",") if x.strip()]
    if not recipients:
        print("ERROR: no recipients", file=sys.stderr)
        return 2

    cal = load_calendar(args.calendar)
    mail = cal.get("mail") or {}
    invs = inventories_from_cal(cal)
    hosts = list_hosts(args.group, invs)
    human = format_when(args.patch_date, args.patch_time)
    subject, body = build(
        args.type,
        args.group,
        hosts,
        human,
        args.patch_date,
        args.patch_time,
        app_name=args.app_name,
        window=args.window,
        owners=args.owners,
        job_id=args.job_id,
    )
    print(f"group={args.group} type={args.type} hosts={len(hosts)} to={recipients}")
    print(f"subject={subject}")
    if args.dry_run:
        print(body)
        return 0

    send_mail(
        subject,
        body,
        mail.get("from") or "ansible@corp.jitb.net",
        recipients,
        mail.get("smtp_host") or "mail.jackinthebox.com",
        int(mail.get("smtp_port") or 25),
    )
    print("SENT OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
