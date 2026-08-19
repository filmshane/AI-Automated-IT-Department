# Ansible patch scheduler

**Status: TESTING MODE** — only `ebstest_process_test` (EBSTEST 2026-07-23 19:00) is live.
Do not set `mode.testing: false` until the owner says so.

## Full documentation
→ **[HOWTO-patch-scheduler.md](./HOWTO-patch-scheduler.md)**

## One-line ops
```bash
vi /etc/ansible/playbook/scripts/patch_calendar.yaml
python3 /etc/ansible/playbook/scripts/patch_materialize_month.py --also-next
grep '|yes|' /etc/ansible/playbook/scripts/schedule/active_jobs.conf
```
