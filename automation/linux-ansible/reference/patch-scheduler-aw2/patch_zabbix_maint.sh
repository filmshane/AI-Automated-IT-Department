#!/bin/bash
# Put inventory group hosts into Zabbix maintenance mode (API on smczabbixp01p).
# Usage:
#   patch_zabbix_maint.sh present <group> <job_id> <patch_date> <patch_time> [minutes]
#   patch_zabbix_maint.sh absent  <group> <job_id> <patch_date> <patch_time>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="${1:-}"; GROUP="${2:-}"; JOB_ID="${3:-}"; PATCH_DATE="${4:-}"; PATCH_TIME="${5:-}"; MINUTES="${6:-240}"

if [[ -z "$STATE" || -z "$GROUP" || -z "$JOB_ID" || -z "$PATCH_DATE" ]]; then
  echo "Usage: $0 present|absent <group> <job_id> <patch_date> <patch_time> [minutes]" >&2
  exit 2
fi

ENV_FILE="${ZABBIX_ENV_FILE:-${SCRIPT_DIR}/zabbix_api.env}"
LOG_DIR="${LOG_DIR:-/etc/ansible/playbook/logs}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/zabbix_maint_${JOB_ID}_$(date +%Y%m%d).log"
INVENTORY="${INVENTORY:-/etc/ansible/hosts}"

log() { echo "[$(date '+%F %T %Z')] $*" | tee -a "$LOG"; }

INV_JSON="$(mktemp)"
trap 'rm -f "$INV_JSON"' EXIT
ansible-inventory -i "$INVENTORY" --list >"$INV_JSON" 2>/dev/null

HOST_JSON=$(python3 - "$GROUP" "$INV_JSON" <<'PY'
import json, sys
g, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
hosts = list((d.get(g) or {}).get("hosts") or [])
if not hosts:
    for c in (d.get(g) or {}).get("children") or []:
        hosts.extend((d.get(c) or {}).get("hosts") or [])
if not hosts:
    raise SystemExit(f"no hosts in group {g}")
print(json.dumps(hosts))
PY
)

MAINT_NAME="Linux-Patch-${JOB_ID}-${PATCH_DATE}"
MAINT_NAME="${MAINT_NAME:0:120}"
DESC="Scheduled Linux OS patching for ${GROUP} (${JOB_ID}) starting ${PATCH_DATE} ${PATCH_TIME} PT — Ansible patch scheduler"

log "Zabbix maintenance state=${STATE} name=${MAINT_NAME} group=${GROUP} minutes=${MINUTES}"
log "Inventory hosts: ${HOST_JSON}"

set +e
python3 "${SCRIPT_DIR}/zabbix_maint_api.py" "$STATE" \
  --name "$MAINT_NAME" \
  --hosts "$HOST_JSON" \
  --minutes "$MINUTES" \
  --desc "$DESC" \
  --env-file "$ENV_FILE" >>"$LOG" 2>&1
rc=$?
set -e

tail -n 30 "$LOG" | sed -E 's/(password|PASSWORD)=[^ ]*/\1=***/g' | while read -r line; do
  [[ "$line" == \[* ]] && continue
  log "  $line"
done

if [[ $rc -eq 0 ]]; then
  log "OK zabbix maintenance ${STATE} rc=0"
else
  log "FAIL zabbix maintenance ${STATE} rc=${rc}"
fi
exit "$rc"
