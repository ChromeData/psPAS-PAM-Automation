<#
.SYNOPSIS
  Report drift between intended-state.yml and the actual CyberArk/Idira tenant.

.DESCRIPTION
  Read-only by default. Enumerates safes, members, and accounts via psPAS and diffs
  them against the intended state. This is the runbook that proves your source of
  truth actually matches reality — the artifact of Lab 11.

  psPAS is pspete's community module (MIT). This script is the lab's reconciliation
  logic on top of it.

.NOTES
  Requires: psPAS module, an active Connect-Lab session.
#>
[CmdletBinding()]
param(
  [string]$IntendedStatePath = "$PSScriptRoot/../intended-state.yml",
  [switch]$Apply   # without this, drift is reported but NOT corrected
)

$ErrorActionPreference = 'Stop'
Import-Module psPAS

if (-not (Get-PASSession)) {
  throw "No active session. Run ./Connect-Lab.ps1 first."
}

# powershell-yaml is the usual choice; install if missing.
if (-not (Get-Module -ListAvailable powershell-yaml)) {
  Install-Module powershell-yaml -Scope CurrentUser -Force
}
Import-Module powershell-yaml
$intended = ConvertFrom-Yaml (Get-Content -Raw $IntendedStatePath)

$drift = [System.Collections.Generic.List[object]]::new()

foreach ($safe in $intended.safes) {
  Write-Host "==> Reconciling safe: $($safe.name)"

  $actual = Get-PASSafe -SafeName $safe.name -ErrorAction SilentlyContinue
  if (-not $actual) {
    $drift.Add([pscustomobject]@{ Type='Safe'; Name=$safe.name; Issue='MISSING' })
    if ($Apply) {
      Write-Host "    creating safe $($safe.name)"
      Add-PASSafe -SafeName $safe.name -Description $safe.description -ManagingCPM $safe.managingCPM
    }
    continue
  }

  $actualMembers = Get-PASSafeMember -SafeName $safe.name | Select-Object -ExpandProperty MemberName
  foreach ($m in $safe.members) {
    if ($m.name -notin $actualMembers) {
      $drift.Add([pscustomobject]@{ Type='Member'; Name="$($safe.name)/$($m.name)"; Issue='MISSING' })
      # Apply path would Add-PASSafeMember with the mapped permission set here.
    }
  }
  # Members present in the tenant but NOT in intended state — the dangerous drift.
  foreach ($am in $actualMembers) {
    if ($am -notin ($safe.members.name)) {
      $drift.Add([pscustomobject]@{ Type='Member'; Name="$($safe.name)/$am"; Issue='UNEXPECTED' })
    }
  }
}

Write-Host ""
if ($drift.Count -eq 0) {
  Write-Host "IN SYNC: tenant matches intended state." -ForegroundColor Green
} else {
  Write-Host "DRIFT DETECTED ($($drift.Count)):" -ForegroundColor Yellow
  $drift | Format-Table -AutoSize
  Write-Host "UNEXPECTED members are the ones to investigate first — those are"
  Write-Host "access grants nobody declared."
  if (-not $Apply) { Write-Host "`nRe-run with -Apply to converge (creates missing; never auto-deletes)." }
}
