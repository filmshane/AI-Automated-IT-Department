#!/bin/bash
INVENTORY="${INVENTORY:-/etc/ansible/hosts}"
PLAYBOOK="${PLAYBOOK:-/etc/ansible/playbook/patch_and_verify.yml}"
LOG_DIR="${LOG_DIR:-/etc/ansible/playbook/logs}"
mkdir -p "$LOG_DIR"
