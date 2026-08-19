# SMB modules (realistic vITD runtime)

Organized from AW2ANSIBUILDP01 playbooks after fit analysis (`docs/05-AW2-PLAYBOOK-SMB-FIT.md`).

## Layout

| Folder | Purpose |
|--------|---------|
| `01-patch` | Linux patch + package checks + SMB calendar example |
| `02-inventory-metrics` | Inventory XLSX + metrics CSV |
| `03-identity` | AD join, users, search, sudo bootstrap |
| `04-password` | Rotate / expiration |
| `05-health` | RAM/CPU + secure boot |
| `wrappers` | Customer-facing entry playbooks |
| `files` | Supporting scripts |

## Quick start

```bash
cd automation/linux-ansible
# inventory group [linux] required for metrics SMB wrapper
ansible-playbook -i inventory/hosts.ini smb-modules/wrappers/site_health_check.yml --limit linux
ansible-playbook -i inventory/hosts.ini smb-modules/wrappers/site_monthly_linux.yml --limit linux -e patch_apply=false
ansible-playbook -i inventory/hosts.ini smb-modules/wrappers/site_monthly_linux.yml --limit linux
```

## Do not run on customers without rewrite

- `playbooks/from-aw2ansibuildp01/OL8-*.yaml` / `OL9-*.yaml` / `New_server_config.yaml` — corp agent farm
- `reference/patch-scheduler-aw2/patch_calendar.yaml` — employer contacts/jobs
- Use `wrappers/smb_server_baseline.yml` + `01-patch/smb_patch_calendar.example.yaml` instead

## Attended vs unattended

| Unattended (cron/MRR) | Attended only |
|-----------------------|---------------|
| patch_and_verify | ad-join-linux |
| host_inventory_report | add_user / add_priviledge |
| collect_system_metrics_smb | change_user_passwd |
| check-ram-cpu*, secure_boot | user-deletion |
| user-password-expiration | setup_passwordless_sudo |
