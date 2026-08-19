# AW2 Playbook → SMB Virtual IT Department fit analysis

**Question:** Can we realistically leverage the AW2ANSIBUILDP01 playbooks for AutomationAI’s AI Automated IT Department for small businesses?

**Short answer:** **Yes for a strong core set. Partial for build/scheduler (need SMB rewrite). No for corporate proxy/agent stacks as defaults.**

---

## Verdict summary

| Tier | Meaning | Count |
|------|---------|-------|
| **A — Ship now** | Use in vITD with light vars only | 14 |
| **B — Ship with guardrails** | Useful but interactive or client-specific tooling | 8 |
| **C — Rewrite before sell** | Valuable IP; not client-safe as-is | 6 |
| **D — Do not productize** | Lab toys or corp-only | rest (raw only) |

---

## Tier A — Ship now (core vITD Linux)

These map cleanly to monthly recurring SMB work.

| Playbook | SMB use | vITD module | Notes |
|----------|---------|-------------|--------|
| `patch_and_verify.yml` | **Flagship** Linux patch + evidence zip | M-PATCH-L | Already core. Keep kernel exclude default. |
| `host_inventory_report.yml` | Owner/insurer asset spreadsheet | M-OBS | Excel on control node. |
| `collect_system_metrics.yml` | Capacity CSV (Grafana-ready) | M-OBS | Fix inventory group `hosts` → `linux` in SMB wrapper. |
| `check-ram-cpu.yml` / `check-ram-cpu2.yml` | Quick health on ticket | M-OBS / IT Copilot | Harmless, fast. |
| `list-package.yaml` / `list-package-new.yaml` | “Is agent X installed?” | M-PATCH support | Change default `pkg_name` from `hp-ams` to client agent. |
| `secure_boot_status.yaml` | Security posture check | M-OBS / hardening report | Good quarterly add-on. |
| `search-user.yaml` / `search-name-return-userid.yml` | Find local accounts | Identity ops / IT desk | Great for offboarding audits. |
| `user-exist-unix.yaml` / `user-exist-with_name.yaml` | Account existence checks | Identity | |
| `user-password-expiration.yaml` | Password aging report | M-PW | Pair with monthly scorecard. |

**Why realistic for SMB:** No Cylance/BigFix dependency, no corp mail, produces evidence owners understand, runs on RHEL/OL/Ubuntu-class boxes SMBs actually have (app servers, NVRs, web).

---

## Tier B — Ship with guardrails

| Playbook | SMB use | Guardrails |
|----------|---------|------------|
| `ad-join-linux.yaml` | Join Linux to customer AD | Many SMBs have AD; use Ansible Vault not long-lived prompts in automation; test on one host; document DNS/NTP prerequisites. |
| `add_user.yaml` / `add_priviledge_user.yaml` | Break-glass / admin users | Prefer AD join long-term; local users only when needed; vault passwords. |
| `change_user_passwd.yml` | Rotate local passwords | M-PW; never log plaintext; `vars_prompt` is OK for attended runs. |
| `setup_passwordless_sudo.yml` | Bootstrap automation user | Only onboarding; high risk if mis-scoped. |
| `user-deletion.yaml` | Offboard local user | Confirm change ticket; no bulk unattended without allowlist. |
| `zabbix_maintenance.yml` | Silence alerts during patch | **Only if client runs Zabbix.** Else skip. |
| `deploy_change_user_passwd.yml` | Scripted multi-user rotate | Needs `change_user_passwd.sh` beside playbook (copied into smb-modules/files). Hard-coded remote path fixed in wrapper. |

---

## Tier C — Rewrite before you sell (keep as IP)

### 1) Server build factory (`OL8/OL9/New_server_config.yaml`)
**Valuable pattern** (hostname, hosts file, users, agents, logging) but **not SMB-ready**:
- Expects `/etc/ansible/FILES/oraclelinux/N/` package farm
- Hardcodes **Cylance + BigFix + Zabbix** agent patterns
- Still contains employer-style admin account names in loops (even after partial sanitize)
- Weak sample password hash pattern must be vault-only

**SMB product approach:** Publish a **thin** `smb_server_baseline.yml` (hostname, chrony, users from vars, optional AD join, optional agent list as variables). Treat OL8/OL9 playbooks as **reference**, not customer default.

### 2) Patch calendar + scheduler stack (`patch_calendar.yaml` + `scripts/*`)
**Excellent enterprise scheduler** (materialize month, notify, zabbix maint, run patch_and_verify).  
**Not SMB-ready as-is:**
- Contacts still reference jackinthebox.com addresses (sanitize incomplete on nested YAML values)
- Zabbix hostnames, testing job `ebstest_process_test`
- Paths `/etc/ansible/hosts`, America/Los_Angeles bias
- Needs `zabbix_api.env` secrets pattern

**SMB product approach:** Ship `smb_patch_calendar.example.yaml` + keep AW2 scripts under `reference/patch-scheduler-aw2/` for you to adapt when a client has >10 Linux hosts and wants calendar automation. Phase-2 product: “Patch Calendar Pro.”

### 3) Timekeeping start/stop/ping
Looks like a **specialized app stack** control, not generic SMB IT.  
**Do not** put in Starter/Growth tiers. Optional only if a client has the same stack.

---

## Tier D — Do not productize as SMB defaults

| Item | Why |
|------|-----|
| falcon-proxy, set-proxy, key.yaml | Corporate security stack / network assumptions |
| reset-sunos-password | Legacy Unix niche (separate Legacy Unix SKU only) |
| hello-world, ping, 2task, copy*, installappache, install-abc, ss, filepermissions | Lab / training |
| passwd_change.yml (world-writable history on server) | Prefer change_user_passwd.yml |
| Raw `_from_aw2ansibuildp01_raw/` | Internal only — may contain residual employer strings |

---

## How this maps to money (vITD)

| Customer pays for | Playbooks you run |
|-------------------|-------------------|
| Growth tier Linux | Tier A monthly: patch_and_verify + inventory + metrics + password expiration report |
| Identity pack | ad-join + user exist/search + controlled add/delete |
| Password hygiene pack | change_user_passwd + expiration report + evidence |
| Build project (fixed fee) | **Only after** SMB baseline rewrite — not stock OL8 playbook |
| Patch calendar add-on | Scheduler reference + SMB calendar template when fleet ≥10 |
| Zabbix clients | zabbix_maintenance around patch windows |

---

## Gaps still needed for full “AI IT department” (not in AW2 set)

These stay in other folders of the project:
- Windows patch (`automation/windows-patch`)
- SQL customer export (`automation/sql-export`)
- Backup freshness (`automation/backup`)
- Growth/sales agents (`agents/`)
- IT Copilot report digests (`agents/it-copilot`)

AW2 set is **Linux ops backbone**, not the whole product.

---

## Risks if you ship enterprise playbooks unchanged

1. **Wrong agents** (Cylance/BigFix) break SMB builds or look unprofessional  
2. **Leaked contact/domain strings** in calendar YAML damage trust  
3. **Interactive vars_prompt** does not scale for unattended MRR automation  
4. **Inventory group names** (`hosts` vs `linux` vs `all`) cause empty runs  
5. **File path coupling** to `/etc/ansible/playbook` on AW2 only  

SMB wrappers in `smb-modules/` address (3)–(5) for Tier A/B.

---

## Recommendation (decision)

**Incorporate Tier A + B into the product runtime path now.**  
**Keep Tier C as reference + Phase-2 roadmap.**  
**Leave Tier D in raw only.**

That is enough Linux substance to honestly sell:
- Managed Linux patch & verify  
- Inventory + metrics scorecards  
- AD join / identity hygiene  
- Password rotation ops  

…and still need Windows/SQL/backup/AI desk from the rest of the project for full vITD.
