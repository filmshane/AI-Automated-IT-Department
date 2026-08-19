# Architecture
Control: Ansible node, n8n/GHL, vault, evidence store.
Customer: Win tasks/WinRM, Linux SSH, customer backups monitored, SQL RO.
Engagement: DB RO -> allowlist SQL -> CSV -> reactivation SMS -> bookings.
