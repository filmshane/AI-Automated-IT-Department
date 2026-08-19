# Linux Ansible for AutomationAI vITD

## Where to run things (SMB)

**Start here:** [`smb-modules/README.md`](smb-modules/README.md)

| Path | Role |
|------|------|
| `smb-modules/` | **Customer product runtime** (Tier A/B playbooks + wrappers) |
| `playbooks/` | Core copies + schedule hints |
| `playbooks/from-aw2ansibuildp01/` | Full sanitized AW2 set |
| `reference/patch-scheduler-aw2/` | Enterprise scheduler engine (rewrite calendar before client use) |
| `_from_aw2ansibuildp01_raw/` | Internal raw pull — do not give to customers |
| `FROM-AW2ANSIBUILDP01.md` | Pull manifest |
| `../../docs/05-AW2-PLAYBOOK-SMB-FIT.md` | Fit analysis |

## Monthly customer command

```bash
ansible-playbook -i inventory/hosts.ini smb-modules/wrappers/site_monthly_linux.yml --limit customer_alpha_linux
```
