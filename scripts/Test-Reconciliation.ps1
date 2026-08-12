<#
.SYNOPSIS
  Report — and optionally correct — drift between intended-state.yml and the
  live CyberArk/Idira tenant.

.DESCRIPTION
  Read-only by default. Enumerates safes, safe members, member permissions, and
  accounts via psPAS, then diffs them against the declared state.

  Four kinds of drift, in descending order of how much they should worry you:

    UNEXPECTED   a safe member nobody declared. Someone has access that no
                 document explains. This is the finding that matters.
    EXTRA_PERM   a declared member holding permissions above their role.
                 Privilege creep - usually granted "temporarily" in an incident.
    MISSING      something declared that does not exist. Usually a broken
                 onboarding, not a security problem.
    MISSING_PERM a declared member below their role. Broken workflow.

  -Apply converges the tenant toward the file. It creates and it downgrades.
  It never deletes a safe and never removes a member - see the note on
  DELETION below.

  psPAS is pspete's community module (MIT). The reconciliation logic, the role
  model, and the drift classification here are this lab's work.

.PARAMETER Apply
  Perform corrections. Without it, nothing is written.

.PARAMETER JsonPath
  Write the drift report as JSON for the findings/ folder and for CI.

.EXAMPLE
  ./Test-Reconciliation.ps1
  ./Test-Reconciliation.ps1 -JsonPath ../findings/drift-2026-08-11.json
  ./Test-Reconciliation.ps1 -Apply

.NOTES
  DELETION is deliberately not automated. A reconciliation script that removes
  safe members will, the first time the state file is wrong, revoke access
  during an incident. Removals are reported and done by a human.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$IntendedStatePath = "$PSScriptRoot/../intended-state.yml",
    [switch]$Apply,
    [string]$JsonPath
)

$ErrorActionPreference = 'Stop'

Import-Module psPAS
Import-Module "$PSScriptRoot/RoleMap.psm1" -Force

if (-not (Get-PASSession)) {
    throw "No active session. Run ./Connect-Lab.ps1 first."
}

if (-not (Get-Module -ListAvailable powershell-yaml)) {
    Install-Module powershell-yaml -Scope CurrentUser -Force
}
Import-Module powershell-yaml

$intended = ConvertFrom-Yaml (Get-Content -Raw $IntendedStatePath)

# ---------------------------------------------------------------------------
# Validate the state file BEFORE touching the tenant.
#
# An unknown role name reaching the apply path would silently grant an empty
# permission set, which looks like success and produces a member who can do
# nothing. Fail loudly here instead.
# ---------------------------------------------------------------------------
$validRoles = Get-LabRoleNames
foreach ($safe in $intended.safes) {
    if (-not $safe.name) { throw "A safe entry has no 'name'." }
    foreach ($m in $safe.members) {
        if ($m.role -notin $validRoles) {
            throw "Safe '$($safe.name)' member '$($m.name)' has unknown role '$($m.role)'. Valid: $($validRoles -join ', ')"
        }
    }
}
Write-Host "State file valid: $($intended.safes.Count) safe(s), $(($intended.safes.members | Measure-Object).Count) membership(s)." -ForegroundColor Cyan

$drift = [System.Collections.Generic.List[object]]::new()

function Add-Drift {
    param($Type, $Name, $Issue, $Detail = '')
    $drift.Add([pscustomobject]@{
        Type   = $Type
        Name   = $Name
        Issue  = $Issue
        Detail = $Detail
    })
}

# ---------------------------------------------------------------------------
# Safes and membership
# ---------------------------------------------------------------------------
foreach ($safe in $intended.safes) {
    Write-Host "==> Safe: $($safe.name)"

    $actualSafe = Get-PASSafe -SafeName $safe.name -ErrorAction SilentlyContinue

    if (-not $actualSafe) {
        Add-Drift 'Safe' $safe.name 'MISSING'
        if ($Apply -and $PSCmdlet.ShouldProcess($safe.name, 'Create safe')) {
            Write-Host "    creating safe" -ForegroundColor Yellow
            Add-PASSafe -SafeName $safe.name `
                        -Description $safe.description `
                        -ManagingCPM $safe.managingCPM
        } else {
            # Nothing else about this safe can be checked until it exists.
            continue
        }
    }

    $actualMembers = @(Get-PASSafeMember -SafeName $safe.name -ErrorAction SilentlyContinue)
    $declaredNames = @($safe.members.name)

    # --- declared members: present? correct permissions? ---
    foreach ($m in $safe.members) {
        $live = $actualMembers | Where-Object { $_.MemberName -eq $m.name }

        if (-not $live) {
            Add-Drift 'Member' "$($safe.name)/$($m.name)" 'MISSING' "role=$($m.role)"

            if ($Apply -and $PSCmdlet.ShouldProcess("$($safe.name)/$($m.name)", "Add member as '$($m.role)'")) {
                Write-Host "    adding $($m.name) as $($m.role)" -ForegroundColor Yellow
                $perms = Get-LabRolePermission -Role $m.role
                Add-PASSafeMember -SafeName $safe.name -MemberName $m.name @perms
            }
            continue
        }

        # Member exists - compare their actual permissions to the role.
        $mismatches = Compare-LabRolePermission -Role $m.role -ActualPermissions $live.Permissions

        foreach ($mm in $mismatches) {
            $issue = if ($mm.Kind -eq 'Extra') { 'EXTRA_PERM' } else { 'MISSING_PERM' }
            Add-Drift 'Permission' "$($safe.name)/$($m.name)" $issue $mm.Permission
        }

        if ($mismatches -and $Apply -and $PSCmdlet.ShouldProcess("$($safe.name)/$($m.name)", "Reset permissions to role '$($m.role)'")) {
            Write-Host "    correcting $($m.name) to exactly '$($m.role)'" -ForegroundColor Yellow
            # Set-PASSafeMember replaces the whole permission set, which is what
            # we want: it removes the extras as well as adding the missing.
            $perms = Get-LabRolePermission -Role $m.role
            Set-PASSafeMember -SafeName $safe.name -MemberName $m.name @perms
        }
    }

    # --- members present in the tenant that nobody declared ---
    foreach ($am in $actualMembers) {
        if ($am.MemberName -notin $declaredNames) {
            Add-Drift 'Member' "$($safe.name)/$($am.MemberName)" 'UNEXPECTED' 'not in intended-state.yml'
        }
    }
}

# ---------------------------------------------------------------------------
# Accounts
#
# The original version of this script stopped at membership. An account sitting
# in the wrong safe is the same class of problem as an undeclared member, so it
# gets reconciled too.
# ---------------------------------------------------------------------------
foreach ($acct in $intended.accounts) {
    $label = "$($acct.safe)/$($acct.userName)@$($acct.address)"
    Write-Host "==> Account: $label"

    $live = Get-PASAccount -safeName $acct.safe -search "$($acct.userName) $($acct.address)" -ErrorAction SilentlyContinue |
            Where-Object { $_.userName -eq $acct.userName -and $_.address -eq $acct.address }

    if (-not $live) {
        Add-Drift 'Account' $label 'MISSING' "platform=$($acct.platformId)"

        if ($Apply -and $PSCmdlet.ShouldProcess($label, 'Onboard account')) {
            Write-Host "    onboarding" -ForegroundColor Yellow
            Add-PASAccount -safeName    $acct.safe `
                           -platformID  $acct.platformId `
                           -address     $acct.address `
                           -userName    $acct.userName `
                           -secretType  password
            # No secret supplied: the CPM reconciles and sets one on first run.
            # Putting a real credential in a state file would defeat the point.
        }
        continue
    }

    if ($live.platformId -ne $acct.platformId) {
        Add-Drift 'Account' $label 'WRONG_PLATFORM' "actual=$($live.platformId) expected=$($acct.platformId)"
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Host ""

if ($JsonPath) {
    $report = [pscustomobject]@{
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        stateFile    = (Resolve-Path $IntendedStatePath).Path
        applied      = [bool]$Apply
        driftCount   = $drift.Count
        drift        = $drift
    }
    $dir = Split-Path -Parent $JsonPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonPath -Encoding utf8
    Write-Host "Report written to $JsonPath" -ForegroundColor Cyan
}

if ($drift.Count -eq 0) {
    Write-Host "IN SYNC: tenant matches intended state." -ForegroundColor Green
    exit 0
}

Write-Host "DRIFT DETECTED ($($drift.Count)):" -ForegroundColor Yellow
$drift | Format-Table -AutoSize

$unexpected = @($drift | Where-Object Issue -eq 'UNEXPECTED')
$extraPerm  = @($drift | Where-Object Issue -eq 'EXTRA_PERM')

if ($unexpected.Count -or $extraPerm.Count) {
    Write-Host ""
    Write-Host "Investigate these first:" -ForegroundColor Red
    Write-Host "  $($unexpected.Count) undeclared member(s)  - access nobody documented"
    Write-Host "  $($extraPerm.Count) excess permission(s)   - privilege creep"
    Write-Host ""
    Write-Host "Removals are not automated. Confirm each is genuinely unauthorised"
    Write-Host "before revoking - a wrong revocation during an incident is worse"
    Write-Host "than the drift."
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Re-run with -Apply to create what is missing and reset permissions"
    Write-Host "to their declared role. Nothing is ever deleted."
}

# Non-zero exit so CI fails on drift.
exit 1
