# Password module

- `change_user_passwd.yml` — attended password set (1–3 users)
- `user-password-expiration.yaml` — report aging
- `deploy_change_user_passwd.yml` — expects `change_user_passwd.sh`

The AW2 deploy playbook copies from `/etc/ansible/playbook/change_user_passwd.sh`.
For SMB control nodes, run from this directory and either:
1. Edit deploy playbook `src:` to `{{ playbook_dir }}/change_user_passwd.sh`, or
2. Copy `change_user_passwd.sh` to your control node's playbook path.

Script is bundled here: `change_user_passwd.sh`
