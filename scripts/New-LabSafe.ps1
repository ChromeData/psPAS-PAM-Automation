<#
.SYNOPSIS
  Create the safes defined in intended-state.yml with their intended membership.
.DESCRIPTION
  Idempotent: skips safes that already exist, adds only missing members. psPAS is
  pspete's community module (MIT); this is the lab's provisioning logic on top.
#>
[CmdletBinding()]
param([string]$IntendedStatePath = "$PSScriptRoot/../intended-state.yml")

$ErrorActionPreference = 'Stop'
Import-Module psPAS
if (-not (Get-PASSession)) { throw "No active session. Run ./Connect-Lab.ps1 first." }
Import-Module powershell-yaml
$intended = ConvertFrom-Yaml (Get-Content -Raw $IntendedStatePath)

# Map the lab's role names to CyberArk permission sets. Kept explicit so the
# translation from 'intended role' to 'actual permissions' is auditable.
$roleMap = @{
  full  = @{ UseAccounts=$true; RetrieveAccounts=$true; ListAccounts=$true; AddAccounts=$true; ManageSafe=$true }
  use   = @{ UseAccounts=$true; RetrieveAccounts=$true; ListAccounts=$true }
  audit = @{ ListAccounts=$true; ViewAuditLog=$true }
}

foreach ($safe in $intended.safes) {
  if (Get-PASSafe -SafeName $safe.name -ErrorAction SilentlyContinue) {
    Write-Host "safe exists: $($safe.name)"
  } else {
    Write-Host "creating safe: $($safe.name)" -ForegroundColor Green
    Add-PASSafe -SafeName $safe.name -Description $safe.description -ManagingCPM $safe.managingCPM
  }
  $existing = (Get-PASSafeMember -SafeName $safe.name).MemberName
  foreach ($m in $safe.members) {
    if ($m.name -in $existing) { continue }
    Write-Host "  + member $($m.name) [$($m.role)]"
    Add-PASSafeMember -SafeName $safe.name -MemberName $m.name @($roleMap[$m.role])
  }
}
Write-Host "Safes reconciled. Next: ./Import-Accounts.ps1"
