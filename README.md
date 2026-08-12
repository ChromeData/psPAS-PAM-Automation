# Lab 11: CyberArk/Idira PAM Automation with psPAS

[![tests](https://github.com/ChromeData/psPAS-PAM-Automation/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/psPAS-PAM-Automation/actions/workflows/tests.yml)

**Most CyberArk work is done by clicking through the web console. This does it from a file: safes, membership, and accounts declared once, then a script that finds every difference between that file and the live vault.**

| | |
|---|---|
| **Domains** | CyberArk/Idira, PowerShell |
| **Built on** | [pspete/psPAS](https://github.com/pspete/psPAS), [cyberark/epv-api-scripts](https://github.com/cyberark/epv-api-scripts) |
| **Cost** | $0 against a trial or lab tenant. **Runtime** ~3 hours |
| **Status** | Built and unit tested, not yet run against a live tenant |

## Situation

Clicking does not scale and it leaves no evidence. Onboard fifty accounts by hand and you get fifty chances to fumble a checkbox, with no record of what you meant to do.

## Task

Treat the vault like source control: declare the state once, then continuously prove reality matches. The proving half is the part that is actually rare.

## Action

CyberArk safe membership is about 22 separate checkboxes. Hand that to whoever edits the config and you get drift by lunchtime. So the state file speaks in three roles, and [scripts/RoleMap.psm1](./scripts/RoleMap.psm1) is the only place they are translated:

| Role | Can | Cannot |
|---|---|---|
| audit | list accounts, read the log | retrieve a credential |
| use | retrieve, connect, trigger CPM | manage the safe or membership |
| full | administer the safe and its members | self approve dual control requests |

The audit line is the one people get wrong: listing accounts feels harmless, retrieving is the actual boundary, and they get granted together constantly. Here that is a test, not a convention.

The reconciler reports four kinds of drift in order of how much they should worry you: an undeclared member (access no document explains), privilege creep, something missing, and a member below their role.

## Result

20 offline tests cover the role model, and they run on a laptop with no CyberArk, no network, no credentials. CI runs them plus a linter. That is why the role map is its own module: the part that decides who gets what is the part you most need certainty about.

`-Apply` creates what is missing and resets permissions down to the declared role. It never deletes a member or a safe. A reconciler with delete rights will, the first time the file is wrong, revoke access during an incident. Knowing what not to automate reads as experience.

## What I did not build

psPAS is pspete's module, and every vault call goes through it. The role model, the reconciler and drift classification, the tests, and the safety decisions are mine.

## Run it

```powershell
./scripts/Connect-Lab.ps1
./scripts/Test-Reconciliation.ps1                      # report only, writes nothing
./scripts/Test-Reconciliation.ps1 -Apply -WhatIf       # show what would change
./scripts/Test-Reconciliation.ps1 -Apply               # converge
./scripts/Disconnect-Lab.ps1
```

Needs PowerShell 7+, psPAS, powershell-yaml, and a CyberArk/Idira tenant (the trial works).

## Findings

`findings/` fills in on the first live run. [LAB-NOTES.md](./LAB-NOTES.md) is the log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). psPAS stays MIT, epv-api-scripts Apache 2.0.
