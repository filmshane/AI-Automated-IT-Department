#!/bin/bash
# Daily/generic cron entrypoint.
# Actions:
#   morning       — 08:00 day-of notice for every job scheduled today
#   reminder      — 17:00 reminder for every job scheduled today
#   zabbix_maint  — T-10m put hosts in Zabbix maintenance (smczabbixp01p)
#   run           — execute playbook for jobs whose patch_time matches now (± window)
#
# Schedule source: schedule/active_jobs.conf (from patch_materialize_month.py)
# Format: group|patch_date|patch_time|recipients|enabled|job_id|name
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${LOG_DIR:-/etc/ansible/playbook/logs}"
STATE_DIR="${LOG_DIR}/schedule_state"
ACTIVE="${ACTIVE_JOBS:-${SCRIPT_DIR}/schedule/active_jobs.conf}"
mkdir -p "$LOG_DIR" "$STATE_DIR"

ACTION="${1:-}"
shift || true
FORCE_GROUP=""
FORCE_ALL_TODAY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-group) FORCE_GROUP="${2:-}"; shift 2 ;;
    --force-today) FORCE_ALL_TODAY=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! "$ACTION" =~ ^(morning|reminder|run|zabbix_maint)$ ]]; then
  echo "Usage: $0 morning|reminder|run|zabbix_maint [--force-group G] [--force-today]" >&2
  exit 2
fi

TODAY="$(date '+%Y-%m-%d')"
NOW_HM="$(date '+%H:%M')"
NOW_EPOCH="$(date '+%s')"
LOG="${LOG_DIR}/schedule_runner_${ACTION}_$(date '+%Y%m%d').log"

log() { echo "[$(date '+%F %T %Z')] $*" | tee -a "$LOG"; }

log "BEGIN action=${ACTION} today=${TODAY} now=${NOW_HM}"

if [[ ! -f "$ACTIVE" ]]; then
  log "ERROR missing ${ACTIVE} — run patch_materialize_month.py --also-next"
  exit 1
fi

rc=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  IFS='|' read -r group patch_date patch_time recipients enabled job_id name notify_only <<<"$line"
  group="$(echo "$group" | xargs)"
  patch_date="$(echo "$patch_date" | xargs)"
  patch_time="$(echo "$patch_time" | xargs)"
  recipients="$(echo "$recipients" | xargs)"
  enabled="$(echo "${enabled:-yes}" | xargs | tr '[:upper:]' '[:lower:]')"
  job_id="$(echo "${job_id:-}" | xargs)"
  name="$(echo "${name:-$group}" | xargs)"
  notify_only="$(echo "${notify_only:-no}" | xargs | tr '[:upper:]' '[:lower:]')"

  [[ -n "$FORCE_GROUP" && "$group" != "$FORCE_GROUP" && "$job_id" != "$FORCE_GROUP" ]] && continue
  [[ "$enabled" =~ ^(y|yes|true|1)$ ]] || { log "SKIP disabled ${job_id:-$group}"; continue; }
  [[ "$patch_date" == "$TODAY" ]] || { log "SKIP ${job_id}: date ${patch_date}"; continue; }
  [[ -n "$recipients" ]] || { log "SKIP ${job_id}: no recipients"; continue; }

  state_file="${STATE_DIR}/${job_id:-$group}_${patch_date}_${ACTION}.done"
  if [[ -f "$state_file" && -z "$FORCE_GROUP" && "$FORCE_ALL_TODAY" -eq 0 ]]; then
    log "SKIP already done ${ACTION} ${job_id}"
    continue
  fi

  case "$ACTION" in
    morning|reminder)
      log "NOTIFY ${ACTION} job=${job_id} group=${group} time=${patch_time} to=${recipients}"
      if python3 "${SCRIPT_DIR}/patch_notify.py" \
          --group "$group" \
          --type "$ACTION" \
          --patch-date "$patch_date" \
          --patch-time "$patch_time" \
          --to "$recipients" \
          --app-name "$name" \
          --job-id "$job_id"; then
        touch "$state_file"
        log "OK notify ${job_id}"
      else
        log "FAIL notify ${job_id}"
        rc=1
      fi
      ;;
    zabbix_maint)
      # Fire once in the window from (patch_time - 10m) through ~T+5m
      patch_epoch="$(date -d "${patch_date} ${patch_time}:00" '+%s')"
      maint_epoch=$(( patch_epoch - 600 ))
      delta=$(( NOW_EPOCH - maint_epoch ))
      if [[ -z "$FORCE_GROUP" && "$FORCE_ALL_TODAY" -eq 0 ]]; then
        if (( delta < 0 || delta > 900 )); then
          log "SKIP zabbix_maint ${job_id}: outside pre-patch window delta=${delta}s (want 0..900 from T-10m)"
          continue
        fi
      fi
      log "ZABBIX MAINT present job=${job_id} group=${group} (10 min before ${patch_time})"
      MINS="${ZABBIX_MAINT_MINUTES:-360}"
      if "${SCRIPT_DIR}/patch_zabbix_maint.sh" present "$group" "$job_id" "$patch_date" "$patch_time" "$MINS"; then
        touch "$state_file"
        log "OK zabbix_maint ${job_id}"
      else
        log "FAIL zabbix_maint ${job_id}"
        rc=1
      fi
      ;;
    run)
      if [[ "$notify_only" =~ ^(y|yes|true|1)$ ]]; then
        log "SKIP run ${job_id}: notify_only=yes (testing/safe mode)"
        continue
      fi
      # Match patch window: from patch_time to +20 minutes (cron fires at :00 of that hour)
      patch_epoch="$(date -d "${patch_date} ${patch_time}:00" '+%s')"
      delta=$(( NOW_EPOCH - patch_epoch ))
      if [[ -z "$FORCE_GROUP" && "$FORCE_ALL_TODAY" -eq 0 ]]; then
        if (( delta < 0 || delta > 1200 )); then
          log "SKIP run ${job_id}: outside window delta=${delta}s (want 0..1200)"
          continue
        fi
      fi

      # Zabbix lifecycle:
      #   1) ensure maintenance is active (normally created at T-10m by zabbix_maint)
      #   2) run patching
      #   3) wait 10 minutes after patching finishes
      #   4) remove maintenance window
      MINS="${ZABBIX_MAINT_MINUTES:-360}"
      POST_WAIT="${ZABBIX_POST_PATCH_WAIT_SEC:-600}"

      log "ZABBIX MAINT ensure-present before patch job=${job_id} group=${group} minutes=${MINS}"
      if ! "${SCRIPT_DIR}/patch_zabbix_maint.sh" present "$group" "$job_id" "$patch_date" "$patch_time" "$MINS"; then
        log "WARN zabbix maint present failed for ${job_id} — continuing with patch anyway"
      fi

      log "RUN job=${job_id} group=${group}"
      set +e
      "${SCRIPT_DIR}/patch_run.sh" "$group"
      patch_rc=$?
      set -e
      if [[ $patch_rc -eq 0 ]]; then
        log "OK run ${job_id} patch_rc=0"
      else
        log "FAIL run ${job_id} patch_rc=${patch_rc}"
        rc=1
      fi

      log "WAIT ${POST_WAIT}s after patch before removing Zabbix maintenance (job=${job_id})"
      sleep "${POST_WAIT}"

      log "ZABBIX MAINT remove after post-wait job=${job_id} group=${group}"
      if "${SCRIPT_DIR}/patch_zabbix_maint.sh" absent "$group" "$job_id" "$patch_date" "$patch_time"; then
        log "OK zabbix maint removed ${job_id}"
      else
        log "FAIL zabbix maint remove ${job_id}"
        rc=1
      fi

      touch "$state_file"
      log "DONE run+maint lifecycle job=${job_id} patch_rc=${patch_rc}"
      ;;
  esac
done < "$ACTIVE"

log "END action=${ACTION} rc=${rc}"
exit "$rc"
