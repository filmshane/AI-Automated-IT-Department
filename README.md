# AutomationAI — AI Automated IT Department for Small Business

**Owner:** Shane A. Miller | Cleveland, TN (Chattanooga MSA)  
**Contact:** (424) 279-0225 | shane.a.miller@live.com  
**Goal:** $200K–$500K/year productized IT + AI ops for SMBs who cannot staff a full IT department.

## Start here

0. **`WHOLE-PLAN-AND-DIRECTORY-MAP.md`** — full plan + every directory explained

1. Read **`docs/00-MASTER-PLAN-200K-500K.md`** (business, packaging, funnel, roadmap)
2. Read **`docs/01-PRODUCT-CATALOG.md`** (what you sell)
3. Deploy tech from **`automation/`** (Linux Ansible, Windows patch, SQL export, backups)
4. Build agents from **`agents/`** (6 growth agents + IT copilot)
5. Use **`sales/`** scripts and scoreboards weekly

## Important

- **Sanitize before client use.** Playbooks here are customer-ready templates derived from your personal automation patterns. Never copy employer secrets, inventories, or proprietary configs.
- Confirm **moonlighting / IP** policy before selling while employed.
- Do **not** claim JITB/Disney/etc. as AutomationAI clients.

## Folder map

```
AI-Automated-IT-Department/
  README.md
  docs/           Master plan, catalog, architecture, legal
  automation/     Real deployable code (Ansible, PS1, SQL, backup)
  agents/         Specs + starter code for AI employees
  sales/          Funnel, scripts, pricing, scoreboard
  templates/      SOW, MSA outline, monthly report
  runbooks/       Delivery SOPs
```

## Companion docs (already on your machine)

- `Documents/Projects/Local-Business-AI-and-IT-Action-Plan-Shane-Miller.md`
- `Downloads/AIBUS/PRODUCTS-PITCHES-AND-200K-PLAN.md`
- Source Linux playbooks: `Desktop/Ansible Ruby Files/patch_and_verify.yml`


## AW2ANSIBUILDP01 playbooks (incorporated)

Live pull from `AW2ANSIBUILDP01:/etc/ansible/playbook` is documented in:

`automation/linux-ansible/FROM-AW2ANSIBUILDP01.md`

- Raw internal copy: `automation/linux-ansible/_from_aw2ansibuildp01_raw/`
- Sanitized product copies: `automation/linux-ansible/playbooks/from-aw2ansibuildp01/`
- Core promoted: `patch_and_verify.yml`, `host_inventory_report.yml`, `collect_system_metrics.yml`, `ad-join-linux.yaml`, `patch_calendar.yaml`


## SMB Linux runtime

Use `automation/linux-ansible/smb-modules/` after fit analysis in `docs/05-AW2-PLAYBOOK-SMB-FIT.md`.


## Windows patching (real tool)

Source: `C:\Users\millersh\bin\` (`winupdate.cmd`, `winupdate-main.ps1`).

Product path: `automation/windows-patch/`

| Mode | Entry |
|------|--------|
| Interactive | `winupdate.cmd` / `winupdate-main.ps1` |
| Unattended MRR | `Invoke-AAIWinUpdateUnattended.ps1` |
| Schedule | `Register-AAIWinUpdateTask.ps1` |

See `automation/windows-patch/README.md`.
