<#
.SYNOPSIS
  Maps the three role names used in intended-state.yml to CyberArk safe permissions.

.DESCRIPTION
  CyberArk safe membership is ~22 independent booleans. Handing that surface to
  whoever edits the state file guarantees drift: two people who both mean
  "auditor" will tick different boxes, and six months later nobody can say which
  set was intended.

  So the state file speaks in three roles, and this module is the only place the
  translation lives. Change a role's meaning here and every safe converges on the
  next reconciliation run.

  The three roles map to the separation any PAM review expects:

    audit  - can see that an account exists and read the log. Cannot retrieve
             a credential. This is the set people most often get wrong, because
             ListAccounts feels harmless and RetrieveAccounts is the actual
             boundary between "oversight" and "access".

    use    - can retrieve and connect. Cannot change membership or delete.
             The incident-responder set.

    full   - can administer the safe and its membership. Deliberately does NOT
             include the dual-control request authorizations; approving your own
             access request is not an administrative convenience.
#>

$script:RoleDefinitions = @{

    audit = @{
        ListAccounts    = $true
        ViewAuditLog    = $true
        ViewSafeMembers = $true
    }

    use = @{
        UseAccounts                            = $true
        RetrieveAccounts                       = $true
        ListAccounts                           = $true
        ViewAuditLog                           = $true
        ViewSafeMembers                        = $true
        InitiateCPMAccountManagementOperations  = $true
    }

    full = @{
        UseAccounts                            = $true
        RetrieveAccounts                       = $true
        ListAccounts                           = $true
        AddAccounts                            = $true
        UpdateAccountContent                   = $true
        UpdateAccountProperties                = $true
        InitiateCPMAccountManagementOperations  = $true
        SpecifyNextAccountContent              = $true
        RenameAccounts                         = $true
        DeleteAccounts                         = $true
        UnlockAccounts                         = $true
        ManageSafe                             = $true
        ManageSafeMembers                      = $true
        BackupSafe                             = $true
        ViewAuditLog                           = $true
        ViewSafeMembers                        = $true
        AccessWithoutConfirmation              = $true
    }
}

function Get-LabRoleNames {
    <#
    .SYNOPSIS
      The valid role names. Used to validate the state file before any writes.
    #>
    [CmdletBinding()]
    param()
    return $script:RoleDefinitions.Keys | Sort-Object
}

function Get-LabRolePermission {
    <#
    .SYNOPSIS
      Returns the permission hashtable for a role, ready to splat into
      Add-PASSafeMember or Set-PASSafeMember.

    .EXAMPLE
      Add-PASSafeMember -SafeName LAB-Linux-Root -MemberName lab-auditors @(Get-LabRolePermission audit)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role
    )

    if (-not $script:RoleDefinitions.ContainsKey($Role)) {
        throw "Unknown role '$Role'. Valid roles: $((Get-LabRoleNames) -join ', ')"
    }

    # Return a copy so a caller cannot mutate the definition for everyone else.
    return $script:RoleDefinitions[$Role].Clone()
}

function Compare-LabRolePermission {
    <#
    .SYNOPSIS
      Compares a live safe member's permissions against what their role should grant.

    .DESCRIPTION
      Returns objects describing each mismatch. Two kinds matter, and they are
      not equally urgent:

        Extra   - the member holds a permission the role does not grant. This is
                  privilege creep and it is the finding that matters.
        Missing - the role grants it, the member lacks it. Usually a broken
                  workflow, not a security problem.

    .OUTPUTS
      PSCustomObject[] with Permission, Expected, Actual, Kind
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter(Mandatory)]
        [AllowNull()]
        $ActualPermissions
    )

    $expected = Get-LabRolePermission -Role $Role
    $results  = [System.Collections.Generic.List[object]]::new()

    # psPAS returns permissions as a nested object; normalise to a hashtable of
    # name -> bool so the comparison below does not care about shape.
    $actual = @{}
    if ($null -ne $ActualPermissions) {
        foreach ($p in $ActualPermissions.PSObject.Properties) {
            if ($p.Value -is [bool]) { $actual[$p.Name] = $p.Value }
        }
    }

    # Every permission the role grants must be present and true.
    foreach ($name in $expected.Keys) {
        $has = $actual.ContainsKey($name) -and $actual[$name]
        if (-not $has) {
            $results.Add([pscustomobject]@{
                Permission = $name
                Expected   = $true
                Actual     = $false
                Kind       = 'Missing'
            })
        }
    }

    # Anything true that the role does not grant is privilege creep.
    foreach ($name in $actual.Keys) {
        if ($actual[$name] -and -not $expected.ContainsKey($name)) {
            $results.Add([pscustomobject]@{
                Permission = $name
                Expected   = $false
                Actual     = $true
                Kind       = 'Extra'
            })
        }
    }

    return $results
}

Export-ModuleMember -Function Get-LabRoleNames, Get-LabRolePermission, Compare-LabRolePermission
