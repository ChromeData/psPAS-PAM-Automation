<#
.SYNOPSIS
  Authenticate to the CyberArk/Idira lab tenant with psPAS.

.DESCRIPTION
  Credentials are prompted interactively and never written to disk or committed.
  Points at a lab/trial tenant only.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$BaseUri,   # e.g. https://lab.privilegecloud.cyberark.cloud
  [string]$AuthType = 'CyberArk'            # or 'LDAP' / 'RADIUS' depending on the tenant
)

$ErrorActionPreference = 'Stop'
Import-Module psPAS

$cred = Get-Credential -Message "CyberArk/Idira lab credentials (never stored)"

New-PASSession -BaseURI $BaseUri -Credential $cred -type $AuthType

Write-Host "Connected to $BaseUri as $($cred.UserName)." -ForegroundColor Green
Write-Host "Run ./New-LabSafe.ps1 or ./Test-Reconciliation.ps1 next."
