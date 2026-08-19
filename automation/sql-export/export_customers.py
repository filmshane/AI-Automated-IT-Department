#!/usr/bin/env python3
"""Allow-listed SQL export for SMB customer engagement."""
from __future__ import annotations
import argparse, csv, datetime as dt, os, re, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    raise SystemExit("pip install pyyaml pyodbc")
SAFE_NAME = re.compile(r"^[a-zA-Z0-9_\-]+$")

def load_config(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)

def read_allowlisted_sql(allowlist_dir: Path, name: str) -> str:
    if not SAFE_NAME.match(name):
        raise ValueError("invalid query name")
    path = allowlist_dir / f"{name}.sql"
    if not path.is_file():
        raise FileNotFoundError(f"not in allowlist: {path}")
    sql = path.read_text(encoding="utf-8")
    lowered = re.sub(r"--.*?$", "", sql, flags=re.M).lower()
    for bad in (" insert ", " update ", " delete ", " drop ", " alter ", " truncate ", " merge ", " exec ", " xp_"):
        if bad in f" {lowered} ":
            raise ValueError(f"forbidden keyword detected: {bad.strip()}")
    if "select" not in lowered:
        raise ValueError("only SELECT allowlisted queries permitted")
    return sql

def connect(cfg: dict):
    engine = (cfg.get("engine") or "mssql").lower()
    user = os.environ.get("AAI_SQL_USER"); pwd = os.environ.get("AAI_SQL_PASSWORD")
    if engine == "mssql":
        import pyodbc
        dsn = cfg["conn"]["dsn"]
        if user and pwd:
            dsn = dsn + f";UID={user};PWD={pwd}"
        return pyodbc.connect(dsn)
    if engine == "mysql":
        import pymysql
        c = cfg["conn"]
        return pymysql.connect(host=c.get("host","localhost"), user=user or c.get("user"),
            password=pwd or c.get("password"), database=c.get("database"))
    if engine == "postgres":
        import psycopg2
        c = cfg["conn"]
        return psycopg2.connect(host=c.get("host","localhost"), user=user or c.get("user"),
            password=pwd or c.get("password"), dbname=c.get("database"))
    raise SystemExit(f"unsupported engine {engine}")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("-c","--config", default="config.yaml"); ap.add_argument("-q","--query", required=True)
    args = ap.parse_args(); cfg = load_config(Path(args.config))
    allowlist_dir = Path(cfg.get("allowlist_dir", "./allowlist")); out_dir = Path(cfg.get("output_dir", "./out")); out_dir.mkdir(parents=True, exist_ok=True)
    sql = read_allowlisted_sql(allowlist_dir, args.query)
    customer = cfg.get("customer_code", "customer"); ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_csv = out_dir / f"{customer}-{args.query}-{ts}.csv"; log_path = out_dir / f"{customer}-export.log"
    conn = connect(cfg)
    try:
        cur = conn.cursor(); cur.execute(sql); rows = cur.fetchall()
        cols = [d[0] for d in cur.description] if cur.description else []
        with out_csv.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f); w.writerow(cols)
            for r in rows: w.writerow(list(r))
        log_path.open("a", encoding="utf-8").write(f"{dt.datetime.now().isoformat()} query={args.query} rows={len(rows)} file={out_csv}\n")
        print(out_csv); print(f"rows={len(rows)}")
    finally:
        conn.close()
    return 0
if __name__ == "__main__":
    sys.exit(main())
