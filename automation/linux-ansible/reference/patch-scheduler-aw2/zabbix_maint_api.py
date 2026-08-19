#!/usr/bin/env python3
"""Create/delete Zabbix maintenance windows for inventory hosts via JSON-RPC API."""
from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_URL = "https://smczabbixp01p.corp.jitb.net/api_jsonrpc.php"


def load_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


class Zabbix:
    def __init__(self, url: str, user: str, password: str, verify: bool = False):
        self.url = url
        self.user = user
        self.password = password
        self.ctx = ssl.create_default_context() if verify else ssl._create_unverified_context()
        self.auth = None

    def rpc(self, method: str, params, auth_required: bool = True):
        payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
        if auth_required and self.auth:
            payload["auth"] = self.auth
        req = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json-rpc"},
        )
        with urllib.request.urlopen(req, context=self.ctx, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        if "error" in data:
            err = data["error"]
            raise RuntimeError(f"Zabbix API error {err.get('code')}: {err.get('message')} — {err.get('data')}")
        return data.get("result")

    def login(self):
        self.auth = self.rpc("user.login", {"username": self.user, "password": self.password}, auth_required=False)

    def logout(self):
        if self.auth:
            try:
                self.rpc("user.logout", [])
            except Exception:
                pass
            self.auth = None


def resolve_hosts(zbx: Zabbix, names: list[str]) -> tuple[list[dict], list[str]]:
    """Return (found host dicts, missing inventory names). Match FQDN then short name."""
    found: list[dict] = []
    missing: list[str] = []
    seen_ids: set[str] = set()

    for name in names:
        candidates: list[dict] = []
        # technical name exact
        candidates.extend(
            zbx.rpc("host.get", {"filter": {"host": [name]}, "output": ["hostid", "host", "name", "status"]}) or []
        )
        # visible name exact
        if not candidates:
            candidates.extend(
                zbx.rpc("host.get", {"filter": {"name": [name]}, "output": ["hostid", "host", "name", "status"]}) or []
            )
        short = name.split(".")[0]
        if not candidates and short != name:
            candidates.extend(
                zbx.rpc("host.get", {"filter": {"host": [short]}, "output": ["hostid", "host", "name", "status"]}) or []
            )
            if not candidates:
                candidates.extend(
                    zbx.rpc("host.get", {"filter": {"name": [short]}, "output": ["hostid", "host", "name", "status"]}) or []
                )
        if not candidates:
            missing.append(name)
            continue
        h = candidates[0]
        if h["hostid"] not in seen_ids:
            seen_ids.add(h["hostid"])
            found.append(h)
    return found, missing


def maintenance_by_name(zbx: Zabbix, name: str):
    res = zbx.rpc(
        "maintenance.get",
        {"filter": {"name": [name]}, "output": ["maintenanceid", "name"], "selectHosts": ["hostid", "host"]},
    )
    return res[0] if res else None


def create_or_update(zbx: Zabbix, name: str, desc: str, hostids: list[str], minutes: int) -> str:
    now = int(time.time())
    until = now + minutes * 60
    existing = maintenance_by_name(zbx, name)
    params = {
        "name": name,
        "active_since": str(now),
        "active_till": str(until),
        "hostids": hostids,
        "timeperiods": [
            {
                "timeperiod_type": 0,  # one-time
                "start_date": str(now),
                "period": str(minutes * 60),
            }
        ],
        "description": desc,
        "maintenance_type": 0,  # with data collection
    }
    if existing:
        params["maintenanceid"] = existing["maintenanceid"]
        zbx.rpc("maintenance.update", params)
        return f"updated id={existing['maintenanceid']}"
    result = zbx.rpc("maintenance.create", params)
    mid = (result or {}).get("maintenanceids", ["?"])[0]
    return f"created id={mid}"


def delete_maint(zbx: Zabbix, name: str) -> str:
    existing = maintenance_by_name(zbx, name)
    if not existing:
        return "absent (not found)"
    zbx.rpc("maintenance.delete", [existing["maintenanceid"]])
    return f"deleted id={existing['maintenanceid']}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("state", choices=["present", "absent"])
    ap.add_argument("--name", required=True, help="Maintenance window name")
    ap.add_argument("--hosts", required=True, help="JSON list of inventory hostnames")
    ap.add_argument("--minutes", type=int, default=240)
    ap.add_argument("--desc", default="Scheduled Linux OS patching via Ansible")
    ap.add_argument("--env-file", default=str(Path(__file__).resolve().parent / "zabbix_api.env"))
    args = ap.parse_args()

    env = load_env(Path(args.env_file))
    user = env.get("ZABBIX_USERNAME") or os.environ.get("ZABBIX_USERNAME") or "millersh"
    password = env.get("ZABBIX_PASSWORD") or os.environ.get("ZABBIX_PASSWORD") or ""
    server = env.get("ZABBIX_SERVER") or os.environ.get("ZABBIX_SERVER") or "https://smczabbixp01p.corp.jitb.net"
    url = server.rstrip("/") + "/api_jsonrpc.php" if not server.endswith("api_jsonrpc.php") else server
    verify = str(env.get("ZABBIX_VALIDATE_CERTS", "False")).lower() in ("1", "true", "yes")

    if not password or password == "CHANGE_ME":
        print("ERROR: ZABBIX_PASSWORD not set", file=sys.stderr)
        return 2

    hosts = json.loads(args.hosts)
    zbx = Zabbix(url, user, password, verify=verify)
    try:
        zbx.login()
        print(f"LOGIN OK user={user}")
        if args.state == "absent":
            print(delete_maint(zbx, args.name))
            return 0

        found, missing = resolve_hosts(zbx, hosts)
        print(f"RESOLVED {len(found)}/{len(hosts)} hosts")
        for h in found:
            status = "enabled" if h.get("status") == "0" else "disabled"
            print(f"  + {h['host']} (visible={h.get('name')}, {status})")
        for m in missing:
            print(f"  - MISSING in Zabbix: {m}")

        if not found:
            print("ERROR: no matching Zabbix hosts", file=sys.stderr)
            return 1

        hostids = [h["hostid"] for h in found]
        result = create_or_update(zbx, args.name, args.desc, hostids, args.minutes)
        print(f"MAINTENANCE {result} name={args.name} minutes={args.minutes}")
        if missing:
            print(f"WARNING: {len(missing)} inventory host(s) not found in Zabbix")
            return 0  # still success if some hosts covered
        return 0
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    finally:
        zbx.logout()


if __name__ == "__main__":
    raise SystemExit(main())
