# Privileged-Account Onboarding Runbook (psPAS)

> The deliverable of Lab 11, write this up as if handing it to a teammate. Fill the
> bracketed sections from your own run against the lab/trial tenant.

## Purpose

Automate the privileged-account lifecycle against CyberArk/Idira as idempotent,
source-controlled runbooks instead of PVWA clicks, with `intended-state.yml` as the
single source of truth.

## Prerequisites

- psPAS v8.x from the PowerShell Gallery
- `powershell-yaml`
- A lab/trial Idira tenant and an account permitted to manage safes

## Workflow

1. **Connect**, `./Connect-Lab.ps1 -BaseUri <tenant>` (credentials prompted, never stored)
2. **Provision safes**, `./New-LabSafe.ps1` (idempotent; skips existing)
3. **Onboard accounts**, `./Import-Accounts.ps1`
4. **Reconcile**, `./Test-Reconciliation.ps1` (read-only drift report)
5. **Disconnect**, `./Disconnect-Lab.ps1`

## Idempotency guarantees

- Safes: created only if absent; members added only if missing.
- Accounts: matched on address + username before creation.
- Reconciliation never auto-deletes, `UNEXPECTED` members are reported for a human.

## Ordering

The REST API enforces safe → member → account. The runbooks follow that order; see
LAB-NOTES for the error you get when you don't.

## Reflection (fill in)

- What did psPAS make trivial that the PVWA makes tedious? [___]
- Where did the API force explicit ordering you'd normally not think about? [___]
- Would you let reconciliation auto-remove unexpected members? Argue your choice. [___]
- Idira rebrand: which cmdlet help/error strings changed, and did anything break? [___]
