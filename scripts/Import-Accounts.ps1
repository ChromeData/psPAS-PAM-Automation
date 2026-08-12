<#
.SYNOPSIS
  Onboard the accounts listed in intended-state.yml into their safes.
.DESCRIPTION
  Idempotent-ish: checks for an existing account at the same address+username in
  the safe before adding. Passwords are NOT in the state file — the CPM reconciles
  or you set them interactively; never commit credential values.
#>
[CmdletBinding()]
param([string]$IntendedStatePath = "$PSScriptRoot/../intended-state.yml")

$ErrorActionPreference = 'Stop'
Import-Module psPAS
if (-not (Get-PASSession)) { throw "No active session. Run ./Connect-Lab.ps1 first." }
Import-Module powershell-yaml
$intended = ConvertFrom-Yaml (Get-Content -Raw $IntendedStatePath)

foreach ($acct in $intended.accounts) {
  $existing = Get-PASAccount -safeName $acct.safe -search "$($acct.userName) $($acct.address)" -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "account exists: $($acct.userName)@$($acct.address) in $($acct.safe)"
    continue
  }
  Write-Host "onboarding: $($acct.userName)@$($acct.address) -> $($acct.safe)" -ForegroundColor Green
  Add-PASAccount -SafeName $acct.safe -PlatformID $acct.platformId `
                 -Address $acct.address -UserName $acct.userName
  # No -secret passed: let the CPM reconcile, or set-secret interactively later.
}
Write-Host "Accounts onboarded. Verify with ./Test-Reconciliation.ps1"
