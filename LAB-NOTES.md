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

### 2026-08-11 — first version put raw permissions in the state file

The original `intended-state.yml` listed CyberArk permission booleans directly. It
worked and it was unusable: 22 flags per member, a diff nobody could review, and
nothing stopping two entries that both mean "auditor" from differing.

Collapsed to three roles with the translation in one module. The state file became
reviewable and the permission model became testable, which is the real win — the part
of a PAM automation you most need certainty about is the part that decides who gets
what, and now it runs on a laptop with no tenant.

The `audit` boundary is the one I was most careful with. `ListAccounts` feels harmless
and `RetrieveAccounts` is the actual line between oversight and access, and they get
granted together constantly in real safes. Here it's a test, not a convention.

Final run: **20 passed** (`findings/test-run.txt`).

---

### 2026-08-11 — talked myself out of automating deletion

Considered full convergence, including removing undeclared members. Decided against
it, and this is the decision I'd most want to defend out loud.

A reconciler with delete rights will, the first time the state file is stale, revoke
access during an incident. The blast radius of "wrong revocation at 3am" is worse than
the drift it fixes. So `-Apply` creates what's missing and resets permissions down to
the declared role, and removals are reported for a human.

Used `Set-PASSafeMember` rather than adding missing permissions, though: replacing the
whole set converges in *both* directions, so privilege creep actually gets removed.
Adding-only would report creep forever and never fix it.

**Biggest risk on the first live run:** the shape of `Get-PASSafeMember`'s permission
object. The comparer normalises whatever psPAS returns down to name -> bool. If the
real tenant nests it one level deeper than expected, the normaliser silently sees zero
permissions and every member reports as `MISSING_PERM`. That failure looks like drift
rather than a bug, which makes it nasty. Check one member by hand before trusting the
first report.
