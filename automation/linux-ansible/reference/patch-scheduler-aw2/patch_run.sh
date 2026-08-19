#!/bin/bash
# Run patch_and_verify.yml for a target inventory group.
set -euo pipefail
GROUP="${1:-}"
if [[ -z "$GROUP" ]]; then
  echo "Usage: $0 <target_group> [extra ansible-playbook args...]" >&2
  exit 2
fi
shift || true

PLAYBOOK="${PLAYBOOK:-/etc/ansible/playbook/patch_and_verify.yml}"
INVENTORY="${INVENTORY:-/etc/ansible/hosts}"
# Include hosts.ini so Aspera groups resolve when used as -i with multiple is harder;
# ansible-playbook takes one -i; for ASPERA* use INVENTORY=/etc/ansible/hosts.ini
case "$GROUP" in
  ASPERS* | ASPERA*) INVENTORY="${INVENTORY_ASPERA:-/etc/ansible/hosts.ini}" ;;
esac
LOG_DIR="${LOG_DIR:-/etc/ansible/playbook/logs}"
ANSIBLE_PLAYBOOK_BIN="${ANSIBLE_PLAYBOOK_BIN:-/home/ansible/.local/bin/ansible-playbook}"
mkdir -p "$LOG_DIR"
TS="$(date '+%Y%m%d-%H%M%S')"
LOG="${LOG_DIR}/patch_run_${GROUP}_${TS}.log"

{
  echo "[$(date '+%F %T %Z')] START group=${GROUP}"
  echo "playbook=${PLAYBOOK} inventory=${INVENTORY}"
  set +e
  "${ANSIBLE_PLAYBOOK_BIN}" "${PLAYBOOK}" -i "${INVENTORY}" -e "target_group=${GROUP}" "$@"
  rc=$?
  set -e
  echo "[$(date '+%F %T %Z')] END group=${GROUP} rc=${rc}"
  exit "$rc"
} 2>&1 | tee -a "${LOG}"
