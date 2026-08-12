# Lab Notes — psPAS PAM Automation

> Running log, newest first.

## Known traps (pre-seeded)

### psPAS Gallery version leads the GitHub Releases page

Install from the PowerShell Gallery (`Install-Module psPAS`) — v8.x — not by cloning
the repo, whose Releases page lags. Note the exact version you used; the API surface
differs across major versions.

### Ordering: safe → member → account

The REST API enforces dependency order. Creating an account before its safe exists,
or granting a member before the safe is created, fails. The reconciliation runbook
processes safes first for this reason. Hitting the ordering error once teaches it
better than reading it.

### Auth type must match the tenant

`New-PASSession -type` is CyberArk / LDAP / RADIUS. Wrong type gives an auth failure
that looks like bad credentials. Confirm how your lab tenant authenticates.

### Idira naming

Some cmdlet help and error strings now say "Idira." Same API. Worth a sentence in
the write-up that you're current on the rebrand.

## YYYY-MM-DD — <first real entry>

**Goal:** · **What happened:** · **Why:** · **Fix:** · **Time lost:**

## Open questions
- [ ] Should reconciliation auto-remove UNEXPECTED members, or only report them?
      (Deleting access automatically is risky — argue your choice.)
- [ ] How does psPAS handle rate limits on a bulk onboard?
