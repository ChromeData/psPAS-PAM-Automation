# Lab 11 — CyberArk/Idira PAM Automation with psPAS

[![tests](https://github.com/ChromeData/psPAS-PAM-Automation/actions/workflows/tests.yml/badge.svg)](https://github.com/ChromeData/psPAS-PAM-Automation/actions/workflows/tests.yml)

**Most CyberArk work is done by clicking through the PVWA. This does it from a
file: safes, membership, and accounts declared once, then a script that finds
every difference between that file and the live tenant.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · PowerShell |
| **Built on** | [pspete/psPAS](https://github.com/pspete/psPAS) (MIT) · [cyberark/epv-api-scripts](https://github.com/cyberark/epv-api-scripts) (Apache-2.0) |
| **Cost** | $0 against a trial or lab tenant · **Runtime** ~3 hours |
| **Status** | 🟡 Built and unit-tested · not yet run against a live tenant |

---

## The point

Clicking doesn't scale and it doesn't leave evidence. Onboard fifty accounts by
hand and you get fifty chances to fumble one checkbox, with no record of what
you meant to do.

This is the same job as source control: **declare the state, then continuously
prove reality matches.** The proving half is the part that's actually rare.

## The idea worth stealing

CyberArk safe membership is about 22 independent checkboxes. Hand that to whoever
edits the config and you get drift by lunchtime — two people who both mean
"auditor" will tick different boxes, and six months later nobody can say which
set was intended.

So the state file speaks in **three roles**, and
[`scripts/RoleMap.psm1`](./scripts/RoleMap.psm1) is the only place they're
translated:

| Role | Can | Cannot |
|---|---|---|
| `audit` | list accounts, read the log | **retrieve a credential** |
| `use` | retrieve, connect, trigger CPM | manage the safe or membership |
| `full` | administer the safe and its members | self-approve dual-control requests |

The `audit` boundary is the one people get wrong. `ListAccounts` feels harmless
and `RetrieveAccounts` is the actual line between oversight and access — they get
granted together constantly. Here that's a test, not a convention.

## What it finds

Four kinds of drift, ordered by how much they should worry you:

| Issue | Meaning |
|---|---|
| `UNEXPECTED` | a safe member nobody declared — **access no document explains** |
| `EXTRA_PERM` | a declared member above their role — privilege creep, usually granted "temporarily" during an incident |
| `MISSING` | declared but absent — broken onboarding, not a security problem |
| `MISSING_PERM` | member below their role — broken workflow |

## It won't delete anything

`-Apply` creates what's missing and resets permissions down to the declared role.
It never removes a member or drops a safe.

That's deliberate. A reconciliation script with delete rights will, the first
time the state file is wrong, revoke access during an incident. Removals get
reported and done by a human. Say that out loud in an interview — knowing what
*not* to automate reads as experience.

## Tested without a tenant

20 Pester tests cover the role model, and they run on a laptop with no CyberArk,
no network, no credentials. That's why the role map is its own module: the part
that decides who gets what is the part you most need certainty about.

```bash
Invoke-Pester ./tests -Output Detailed
```

CI runs them on every push, plus PSScriptAnalyzer over `scripts/`.

## What I didn't build

psPAS is pspete's module — every REST call goes through it. The role model, the
reconciliation and drift classification, the tests, and the safety decisions
are mine.

---

## Running it

```powershell
./scripts/Connect-Lab.ps1                              # auth to the tenant
./scripts/Test-Reconciliation.ps1                      # report only, writes nothing
./scripts/Test-Reconciliation.ps1 -JsonPath ../findings/drift.json
./scripts/Test-Reconciliation.ps1 -Apply -WhatIf       # show what would change
./scripts/Test-Reconciliation.ps1 -Apply               # converge
./scripts/Disconnect-Lab.ps1
```

Exits non-zero on drift, so it drops into a pipeline unchanged.

Needs PowerShell 7+, `psPAS`, `powershell-yaml`, and a CyberArk/Idira tenant
(the trial works).

## On the name

Palo Alto Networks acquired CyberArk and rebranded the platform **Idira**. psPAS
already carries the new naming. Docs across the ecosystem are mid-migration, so
this lab uses whichever name the tooling uses at the pinned version.

## Findings

`findings/` fills in on the first live run. [LAB-NOTES.md](./LAB-NOTES.md) is the
log.

## License

Lab code: MIT ([LICENSE](./LICENSE)). psPAS stays MIT, epv-api-scripts Apache-2.0.
