# Windows Patch Factory — AutomationAI

## Source of truth (your laptop)

All autopatch tools live at:

`C:\Users\millersh\bin\`

| File | Role |
|------|------|
| `winupdate.cmd` | Launcher (CMD / Run / PATH) |
| `winupdate-main.ps1` | Full interactive engine |
| `winupdate-*.log` | Per-run logs (next to script) |

These are **copied into this project** so the vITD product pack is complete.

---

## What the real tool does (`winupdate-main.ps1`)

Proven on your box (log `winupdate-20260722-200241.log`):

1. Self-elevates to Administrator  
2. **COM** `Microsoft.Update.Session` (no PSWindowsUpdate module required)  
3. Search `IsInstalled=0 and IsHidden=0`  
4. Accept EULAs, download all, install all  
5. Per-update Succeeded/Failed + HRESULT  
6. Optional **winget** software upgrades (interactive Y/N)  
7. Reboot pending detection + optional reboot  
8. AFK-safe: window stays open until keypress  
9. Log file beside the script  

**Interactive desktop / break-fix use this.**

```bat
:: If C:\Users\millersh\bin is on PATH:
winupdate

:: Or from this project folder:
winupdate.cmd
winupdate.cmd -SkipSoftware
winupdate.cmd -WhatIf
winupdate.cmd -NoRebootPrompt
```

---

## Product layout in this repo

| Path | Use |
|------|-----|
| `winupdate.cmd` / `winupdate-main.ps1` | **Primary interactive** (copy of bin) |
| `from-bin\` | Frozen snapshot of bin sources |
| `Invoke-AAIWinUpdateUnattended.ps1` | **MRR / Scheduled Task / RMM** — same COM engine, evidence pack, no prompts |
| `Register-AAIWinUpdateTask.ps1` | Registers weekly SYSTEM task |
| `Get-AAIWindowsInventory.ps1` | Light inventory CSV |
| `Invoke-AAIWindowsPatch.ps1` | **Legacy alternate** (PSWindowsUpdate module) — optional only |
| `Install-AAIPatchPrereqs.ps1` | Only needed for legacy PSWindowsUpdate path |

---

## Unattended (SMB Virtual IT Department)

```powershell
# Admin PowerShell — preview
.\Invoke-AAIWinUpdateUnattended.ps1 -CustomerCode acme -WhatIf

# Apply OS patches, no reboot, no winget (typical server)
.\Invoke-AAIWinUpdateUnattended.ps1 -CustomerCode acme -Reboot Never

# Apply + reboot if needed (maintenance window)
.\Invoke-AAIWinUpdateUnattended.ps1 -CustomerCode acme -Reboot Prefer

# Also winget apps (workstations)
.\Invoke-AAIWinUpdateUnattended.ps1 -CustomerCode acme -InstallSoftware -Reboot Never

# Schedule Tuesday 22:00
.\Register-AAIWinUpdateTask.ps1 -CustomerCode acme -DayOfWeek Tuesday -Time 22:00 -Reboot Never
```

### Evidence (monthly scorecard / IT Copilot)

```
C:\ProgramData\AutomationAI\reports\
  {customer}-{host}-{date}-wu-updates.csv
  {customer}-{host}-{date}-wu-summary.txt
C:\ProgramData\AutomationAI\logs\
  winupdate-{customer}-{host}-{date}-{ts}.log
```

Feed summary files to `agents/it-copilot/summarize_reports.py`.

---

## Interactive vs unattended

| Feature | `winupdate-main.ps1` | `Invoke-AAIWinUpdateUnattended.ps1` |
|---------|----------------------|-------------------------------------|
| Engine | WU COM | Same WU COM |
| Prompts | Yes (winget, reboot, key) | No |
| Customer evidence pack | Log in bin\ | ProgramData reports + CSV |
| Scheduled Task | Manual | `Register-AAIWinUpdateTask.ps1` |
| Best for | Your PC / on-site | Client MRR fleet |

---

## Deploy to a client PC

1. Copy folder `windows-patch\` to e.g. `C:\ProgramData\AutomationAI\windows-patch\`  
2. Run once interactively or unattended WhatIf  
3. Register task with agreed window  
4. Collect `ProgramData\AutomationAI\reports\` monthly  

Keep `C:\Users\millersh\bin` as your personal PATH launcher; sync changes back into this repo when you improve the script.

---

## vITD catalog mapping

| Sell | Deliver |
|------|---------|
| Windows Patch Factory | Unattended task + monthly evidence |
| Workstation tune-up (on-site) | Interactive `winupdate` + optional winget |
| Scorecard line item | `*-wu-summary.txt` RESULT + installed/failed counts |

---

## Notes from your real run

- 36 updates found; long download/install window (hours possible on first catch-up)  
- Drivers + feature updates included in default criteria (same as interactive tool)  
- Some driver fails (`0x8024200B`) still left overall reboot required — scorecard = **REVIEW**  
- winget may be **GPO-disabled** on corp images — unattended defaults SkipSoftware  

For stricter SMB servers later: add a filter to exclude drivers (`Type eq 'Software'` style criteria) in a future flag `-SoftwareOnly`.
