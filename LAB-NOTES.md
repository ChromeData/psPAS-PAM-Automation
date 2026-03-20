# Lab Notes — 11 psPAS PAM Automation

Running log. Errors, dead ends, fixes, surprises. Dated, newest at the bottom.
This file is the proof the lab was real.

---

## Format

```
### YYYY-MM-DD — what I was trying to do

**Expected:**
**Got:**
**Cause:**
**Fix:**
```

---

## Decisions made while building (and why)

### Roles instead of raw permissions

First pass put CyberArk permission booleans straight in `intended-state.yml`.
It worked and it was unusable — 22 flags per member, no way to review a diff,
and nothing stopping two "auditor" entries from differing. Collapsed to three
roles with the translation in one module. The state file became reviewable and
the permission model became testable.

### Deletion left out of `-Apply`

Considered full convergence including removals. Talked myself out of it: the
first time the state file is stale, an automated revoke pulls access during an
incident, and the blast radius of "wrong revocation at 3am" is worse than the
drift it fixes. Removals get reported.

### `Set-PASSafeMember` rather than adding the missing permissions

Adding only what's missing never removes privilege creep. Replacing the whole
set converges in both directions, which is the entire point of reconciliation.

### The account reconciliation onboards without a secret

`Add-PASAccount` runs with no password so the CPM reconciles and sets one.
Putting a real credential in a YAML file to automate credential management would
be self-defeating.

---

## Known traps (confirm on first live run)

- **`Get-PASSafeMember` permission shape.** The comparison normalises whatever
  psPAS returns down to name → bool. Verify the actual property nesting on a
  real tenant; if it's wrapped one level deeper than expected, the normaliser
  silently sees zero permissions and every member reports as `MISSING_PERM`.
  That failure looks like drift rather than a bug, which makes it nasty.
- **Search matching.** `Get-PASAccount -search` is fuzzy. The result is filtered
  on exact `userName` + `address`, but confirm it doesn't miss accounts whose
  address is stored in a different format (FQDN vs. short name).
- **CPM name.** `managingCPM: PasswordManager` is the default. A tenant with a
  renamed CPM fails at safe creation.
- **Idira naming.** Check whether the tenant's API surface still answers to the
  CyberArk paths psPAS uses at the pinned version.

---

## Open questions to answer while running

- [ ] How long does reconciliation take against a tenant with ~100 safes?
- [ ] Does `-WhatIf` correctly suppress every write path? (Test before trusting it.)
- [ ] What does `Compare-LabRolePermission` report for a member added via the
      PVWA with a custom permission set?
- [ ] Capture a real `UNEXPECTED` finding — deliberately add a member outside
      the state file, confirm it's caught, screenshot for `findings/`.

---

## Log

_(first entry goes here on the first live run)_
