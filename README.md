# Lab 11 — CyberArk/Idira PAM Automation with psPAS

**Automate the privileged-account lifecycle against CyberArk/Idira's REST API with
the psPAS PowerShell module — safe creation, account onboarding, access grants, and
reconciliation — as idempotent, source-controlled runbooks instead of clicks.**

| | |
|---|---|
| **Domains** | CyberArk/Idira · Linux/PowerShell |
| **Built on** | [pspete/psPAS](https://github.com/pspete/psPAS) (MIT) · [cyberark/epv-api-scripts](https://github.com/cyberark/epv-api-scripts) (Apache-2.0) |
| **Runtime** | ~3 hours · $0 (against a CyberArk/Idira trial or lab tenant) |
| **Status** | 🟡 In progress |

---

## Why this lab exists

This is the one lab that's purely your domain — no cloud provider, just PAM done
properly as code. Most CyberArk work is done by hand in the PVWA. Doing it through
psPAS as idempotent runbooks is what separates an operator from an engineer: onboard
fifty accounts reproducibly, prove a safe's membership matches intended state, and
reconcile drift automatically. It also demonstrates you're current on the Idira
rebrand, since psPAS already carries the new naming.

## What I built

- **Idempotent runbooks** (`scripts/`) for: creating a safe with intended
  membership, onboarding accounts into it, granting/revoking access by role, and a
  reconciliation check that reports drift between intended and actual state.
- A **declarative intended-state file** (`intended-state.yml`) — the runbooks
  converge the tenant toward it, so the repo *is* the source of truth.
- A **read-only audit runbook** that exports current safe/account/member state for
  comparison, adapted from the patterns in cyberark/epv-api-scripts.

## What I did not build

psPAS and epv-api-scripts are community/CyberArk tools. My work is the runbook
design, the intended-state model, the reconciliation logic, and the write-up of how
this maps to a real onboarding workflow.

---

## Running it

```powershell
# Against a CyberArk/Idira trial or lab tenant — never production.
./scripts/Connect-Lab.ps1                 # authenticate (creds prompted, never stored)
./scripts/New-LabSafe.ps1                 # create safe + intended membership
./scripts/Import-Accounts.ps1             # onboard accounts from intended-state.yml
./scripts/Test-Reconciliation.ps1         # report drift: intended vs actual
./scripts/Disconnect-Lab.ps1
```

## The deliverable

`docs/onboarding-runbook.md` — the runbook written up as you'd hand it to a team:
the workflow, the idempotency guarantees, and the reconciliation output showing
intended state matching actual. Plus the reflection: what psPAS makes easy that the
PVWA makes tedious, and where the API forces you to think about ordering (safe
before member before account).

## Safety

- Lab/trial tenant only. Credentials are prompted at runtime and never written to
  disk or committed.
- The reconciliation runbook is read-only by default; the converge step requires an
  explicit `-Apply` switch so a dry run can't mutate the tenant by accident.

## What broke

See [LAB-NOTES.md](./LAB-NOTES.md).
