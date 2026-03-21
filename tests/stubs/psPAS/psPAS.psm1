<#
  A stub tenant, standing in for psPAS.

  Test-Reconciliation.ps1 is the largest piece of logic in this lab and none of
  it was tested. RoleMap.Tests.ps1 covers the permission mapping, which is pure
  and easy; the reconciliation itself, the part that decides what counts as
  drift and what gets written back, only ran against a live CyberArk tenant.
  There is no free self-hosted EPV, so in practice it never ran at all.

  This module is named psPAS on purpose. Placed earlier on PSModulePath it
  shadows the real module, so `Import-Module psPAS` inside the script resolves
  here and the script under test needs no modification whatsoever. That matters:
  a test that requires editing the thing it tests is testing something else.

  The tenant is described by a JSON file at $env:STUB_TENANT. Every write is
  appended to $env:STUB_WRITES so tests can assert on what the script tried to
  change, including asserting that it tried to change nothing.

  WHAT THIS PROVES
    The drift classification, the ordering of checks, the state-file validation,
    the JSON report shape, the exit codes, and that -Apply writes what it should
    and only what it should.

  WHAT IT DOES NOT PROVE
    Anything about CyberArk. Real psPAS cmdlets have richer objects, different
    error modes, paging, and version-dependent behaviour. These are contract
    tests against the shapes this script consumes, not evidence that it works
    against an EPV.
#>

function script:Get-Tenant {
    if (-not $env:STUB_TENANT -or -not (Test-Path $env:STUB_TENANT)) {
        return @{ safes = @(); members = @{}; accounts = @() }
    }
    Get-Content -Raw $env:STUB_TENANT | ConvertFrom-Json
}

function script:Record-Write {
    param([string]$Cmdlet, [hashtable]$Params)
    if (-not $env:STUB_WRITES) { return }
    $entry = [pscustomobject]@{ cmdlet = $Cmdlet; params = $Params }
    Add-Content -Path $env:STUB_WRITES -Value ($entry | ConvertTo-Json -Compress -Depth 6)
}

function Get-PASSession {
    # The script throws unless this returns something truthy.
    [pscustomobject]@{ User = 'stub'; BaseURI = 'https://stub.invalid' }
}

function Get-PASSafe {
    param([string]$SafeName)
    $t = Get-Tenant
    $t.safes | Where-Object { $_.safeName -eq $SafeName }
}

function Get-PASSafeMember {
    param([string]$SafeName)
    $t = Get-Tenant
    if ($t.members.PSObject.Properties.Name -contains $SafeName) {
        return $t.members.$SafeName
    }
    @()
}

function Get-PASAccount {
    param([string]$safeName, [string]$search)
    $t = Get-Tenant
    $t.accounts | Where-Object { $_.safeName -eq $safeName }
}

function Add-PASSafe {
    param([string]$SafeName, [string]$Description, [string]$ManagingCPM)
    Record-Write 'Add-PASSafe' @{ SafeName = $SafeName }
}

function Add-PASSafeMember {
    param(
        [string]$SafeName, [string]$MemberName,
        [switch]$UseAccounts, [switch]$RetrieveAccounts, [switch]$ListAccounts,
        [switch]$AddAccounts, [switch]$UpdateAccountContent, [switch]$UpdateAccountProperties,
        [switch]$DeleteAccounts, [switch]$ManageSafe, [switch]$ManageSafeMembers,
        [switch]$ViewAuditLog, [switch]$ViewSafeMembers, [switch]$AccessWithoutConfirmation,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    Record-Write 'Add-PASSafeMember' @{ SafeName = $SafeName; MemberName = $MemberName }
}

function Set-PASSafeMember {
    param(
        [string]$SafeName, [string]$MemberName,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    Record-Write 'Set-PASSafeMember' @{ SafeName = $SafeName; MemberName = $MemberName }
}

function Add-PASAccount {
    param(
        [string]$safeName, [string]$platformID, [string]$address,
        [string]$userName, [string]$secretType,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    Record-Write 'Add-PASAccount' @{ safeName = $safeName; userName = $userName }
}

# Deliberately NOT exported, because the script must never call them:
# Remove-PASSafe, Remove-PASSafeMember, Remove-PASAccount.
# If the script ever gains a deletion path, it will fail here with
# "term not recognized" rather than silently revoking access in a test.

Export-ModuleMember -Function Get-PASSession, Get-PASSafe, Get-PASSafeMember,
Get-PASAccount, Add-PASSafe, Add-PASSafeMember, Set-PASSafeMember, Add-PASAccount
