# Playbooks from AW2ANSIBUILDP01:/etc/ansible/playbook

Pulled live from control node and incorporated into this product pack.

## Host
- AW2ANSIBUILDP01.corp.jitb.net (10.4.151.93)
- Remote dir: `/etc/ansible/playbook`
- Raw download (private working copy): `automation/linux-ansible/_from_aw2ansibuildp01_raw/`
- Sanitized product copies: `automation/linux-ansible/playbooks/from-aw2ansibuildp01/`
- Core promoted to: `automation/linux-ansible/playbooks/`

## IMPORTANT
- Sanitized copies replace JITB domains with `example.customer.local` and vault password placeholders.
- **Do not** re-upload sanitized marketing copies back over production JITB playbooks without review.
- Raw folder may still contain employer-specific strings — treat as internal only.
- Falcon proxy / corporate proxy playbooks were **not** promoted as SMB product defaults.

## Inventory mapping (promoted)

| File | Product module | Size raw→sanitized | Sanitize notes |
|------|----------------|--------------------|----------------|
| `New_server_config.yaml` | M-BUILD generic | 10793->11416 | replaced corp\.jitb\.net; replaced \bJITB\b; replaced millershuxadmin; redacted password-like assignment |
| `OL8-New_server_config.from-Downloads-bin.yaml` | M-BUILD OL8 alt (review) | 9774->10124 | replaced corp\.jitb\.net; replaced \bJITB\b; replaced millershuxadmin; redacted password-like assignment |
| `OL8-New_server_config.yaml` | M-BUILD OL8 | 9770->10097 | replaced corp\.jitb\.net; replaced \bJITB\b; replaced millershuxadmin; redacted password-like assignment |
| `OL9-New_server_config.yaml` | M-BUILD OL9 | 9466->10099 | replaced corp\.jitb\.net; replaced \bJITB\b; replaced millershuxadmin; redacted password-like assignment |
| `ad-join-linux.yaml` | M-AD identity | 4573->4967 | replaced corp\.jitb\.net |
| `add_priviledge_user.yaml` | identity support | 1558->1837 | redacted password-like assignment |
| `add_user.yaml` | identity support | 1205->1463 | redacted password-like assignment |
| `change_user_passwd.yml` | M-PW support | 2027->2303 | redacted password-like assignment |
| `check-ram-cpu.yml` | M-OBS quick | 502->745 | clean |
| `check-ram-cpu2.yml` | M-OBS quick | 879->1135 | clean |
| `collect_system_metrics.yml` | M-OBS metrics | 2857->3093 | clean |
| `deploy_change_user_passwd.yml` | M-PW support | 1151->1426 | replaced millershuxadmin |
| `host_inventory_report.yml` | M-OBS inventory | 4454->4804 | clean |
| `list-package-new.yaml` | patch support | 1199->1475 | clean |
| `list-package.yaml` | patch support | 529->779 | clean |
| `patch_and_verify.yml` | M-PATCH-L core | 13174->13740 | replaced corp\.jitb\.net |
| `patch_patch_calendar.yaml` | M-PATCH scheduler | 7815->8317 | replaced corp\.jitb\.net; replaced millersh |
| `search-name-return-userid.yml` | ops user search | 1580->1866 | clean |
| `search-user.yaml` | ops user search | 4106->4332 | clean |
| `secure_boot_status.yaml` | security check | 632->888 | clean |
| `setup_passwordless_sudo.yml` | build support | 2374->2685 | clean |
| `timekeeping_ping_timekeeping.yml` | optional module | 1163->1445 | clean |
| `timekeeping_start_timekeeping.yml` | optional module | 9543->10081 | clean |
| `timekeeping_stop_timekeeping.yml` | optional module | 11596->12174 | clean |
| `user-deletion.yaml` | identity support | 1078->1342 | clean |
| `user-exist-unix.yaml` | identity support | 1066->1331 | clean |
| `user-exist-with_name.yaml` | identity support | 1066->1338 | clean |
| `user-password-expiration.yaml` | M-PW support | 1131->1401 | clean |
| `zabbix_maintenance.yml` | ops maintenance window | 1898->2164 | replaced corp\.jitb\.net; replaced millersh; redacted password-like assignment |

## Also present on control node but not promoted as core product

- `2task.yaml` (lab/corp-specific/utility — still in raw download)
- `copy-file.yaml` (lab/corp-specific/utility — still in raw download)
- `copy.yaml` (lab/corp-specific/utility — still in raw download)
- `falcon-proxy.yaml` (lab/corp-specific/utility — still in raw download)
- `falcon-proxy.yml` (lab/corp-specific/utility — still in raw download)
- `filepermissions.yaml` (lab/corp-specific/utility — still in raw download)
- `hello-world.yaml` (lab/corp-specific/utility — still in raw download)
- `install-abc.yaml` (lab/corp-specific/utility — still in raw download)
- `installappache.yaml` (lab/corp-specific/utility — still in raw download)
- `key.yaml` (lab/corp-specific/utility — still in raw download)
- `passwd_change.yml` (lab/corp-specific/utility — still in raw download)
- `ping.yaml` (lab/corp-specific/utility — still in raw download)
- `reset-sunos-password.yaml` (lab/corp-specific/utility — still in raw download)
- `set-proxy.yml` (lab/corp-specific/utility — still in raw download)
- `ss.yaml` (lab/corp-specific/utility — still in raw download)

## Product wiring

| vITD / module | Playbooks to use |
|---------------|------------------|
| Linux Patch Factory | `patch_and_verify.yml`, `patch_calendar.yaml`, `list-package*.yaml` |
| Inventory / Observability | `host_inventory_report.yml`, `collect_system_metrics.yml`, `check-ram-cpu*.yml` |
| Server Build Factory | `OL8-New_server_config.yaml`, `OL9-New_server_config.yaml`, `New_server_config.yaml` |
| AD Join / Identity | `ad-join-linux.yaml`, `add_user.yaml`, `add_priviledge_user.yaml`, `setup_passwordless_sudo.yml` |
| Password hygiene | `change_user_passwd.yml`, `deploy_change_user_passwd.yml`, `user-password-expiration.yaml` |
| Ops helpers | `search-user.yaml`, `search-name-return-userid.yml`, `zabbix_maintenance.yml` |
| Timekeeping (optional) | `timekeeping_*.yml` |

## Next steps
1. Diff sanitized build playbooks vs client needs; move all passwords to Ansible Vault.
2. Replace `example.customer.local` with client realm/DNS at install time.
3. Keep raw folder out of any customer repo / git public.
4. Update master plan product catalog references to these filenames.

## SMB fit analysis (authoritative)

See **`docs/05-AW2-PLAYBOOK-SMB-FIT.md`** for Tier A/B/C/D decisions.

**Runtime path for small business product:** `smb-modules/`  
**Reference only:** `reference/patch-scheduler-aw2/`, OL8/OL9/New_server_config builds  
**Internal only:** `_from_aw2ansibuildp01_raw/`
