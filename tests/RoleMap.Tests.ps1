<#
  Pester tests for the role model.

  These run with no CyberArk tenant, no network, and no credentials, because
  the role map is pure logic. That is the point of keeping it in its own module:
  the part of a PAM automation you most need to be certain about is the part
  that decides who gets what, and that part should be testable on a laptop.

  Run:  Invoke-Pester ./tests -Output Detailed
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../scripts/RoleMap.psm1" -Force
}

Describe 'Get-LabRoleNames' {

    It 'returns exactly the three roles used by intended-state.yml' {
        Get-LabRoleNames | Should -Be @('audit', 'full', 'use')
    }
}

Describe 'Get-LabRolePermission' {

    It 'throws on an unknown role rather than returning an empty set' {
        # An empty set would silently create a member who can do nothing,
        # which looks like success.
        { Get-LabRolePermission -Role 'administrator' } | Should -Throw '*Unknown role*'
    }

    It 'returns a hashtable that can be splatted into Add-PASSafeMember' {
        $p = Get-LabRolePermission -Role 'use'
        $p | Should -BeOfType [hashtable]
        $p.Keys.Count | Should -BeGreaterThan 0
    }

    It 'returns a copy, so a caller cannot mutate the shared definition' {
        $first = Get-LabRolePermission -Role 'audit'
        $first['ManageSafe'] = $true

        $second = Get-LabRolePermission -Role 'audit'
        $second.ContainsKey('ManageSafe') | Should -BeFalse
    }
}

Describe 'Role boundaries' {

    Context 'audit' {
        BeforeAll { $audit = Get-LabRolePermission -Role 'audit' }

        It 'can list accounts' {
            $audit['ListAccounts'] | Should -BeTrue
        }

        It 'CANNOT retrieve a credential' {
            # This is the boundary between oversight and access, and the
            # single most common misconfiguration in a real safe.
            $audit.ContainsKey('RetrieveAccounts') | Should -BeFalse
        }

        It 'CANNOT use an account' {
            $audit.ContainsKey('UseAccounts') | Should -BeFalse
        }

        It 'CANNOT manage membership' {
            $audit.ContainsKey('ManageSafeMembers') | Should -BeFalse
        }
    }

    Context 'use' {
        BeforeAll { $use = Get-LabRolePermission -Role 'use' }

        It 'can retrieve and connect' {
            $use['RetrieveAccounts'] | Should -BeTrue
            $use['UseAccounts']      | Should -BeTrue
        }

        It 'CANNOT manage the safe or its membership' {
            $use.ContainsKey('ManageSafe')        | Should -BeFalse
            $use.ContainsKey('ManageSafeMembers') | Should -BeFalse
        }

        It 'CANNOT delete accounts' {
            $use.ContainsKey('DeleteAccounts') | Should -BeFalse
        }
    }

    Context 'full' {
        BeforeAll { $full = Get-LabRolePermission -Role 'full' }

        It 'can manage the safe and its membership' {
            $full['ManageSafe']        | Should -BeTrue
            $full['ManageSafeMembers'] | Should -BeTrue
        }

        It 'CANNOT self-approve dual-control requests' {
            # Approving your own access request is not an admin convenience.
            $full.ContainsKey('RequestsAuthorizationLevel1') | Should -BeFalse
            $full.ContainsKey('RequestsAuthorizationLevel2') | Should -BeFalse
        }
    }

    It 'escalates strictly: audit is a subset of use, use is a subset of full' {
        $audit = (Get-LabRolePermission -Role 'audit').Keys
        $use   = (Get-LabRolePermission -Role 'use').Keys
        $full  = (Get-LabRolePermission -Role 'full').Keys

        ($audit | Where-Object { $_ -notin $use })  | Should -BeNullOrEmpty
        ($use   | Where-Object { $_ -notin $full }) | Should -BeNullOrEmpty
    }
}

Describe 'Compare-LabRolePermission' {

    It 'reports no drift when permissions match the role exactly' {
        $actual = [pscustomobject]@{
            ListAccounts    = $true
            ViewAuditLog    = $true
            ViewSafeMembers = $true
        }

        Compare-LabRolePermission -Role 'audit' -ActualPermissions $actual |
            Should -BeNullOrEmpty
    }

    It 'flags privilege creep as Extra' {
        # An auditor who somehow acquired RetrieveAccounts - the finding that matters.
        $actual = [pscustomobject]@{
            ListAccounts     = $true
            ViewAuditLog     = $true
            ViewSafeMembers  = $true
            RetrieveAccounts = $true
        }

        $drift = Compare-LabRolePermission -Role 'audit' -ActualPermissions $actual
        $drift.Count             | Should -Be 1
        $drift[0].Permission     | Should -Be 'RetrieveAccounts'
        $drift[0].Kind           | Should -Be 'Extra'
    }

    It 'flags a missing permission as Missing' {
        $actual = [pscustomobject]@{
            ListAccounts = $true
            ViewAuditLog = $true
        }

        $drift = Compare-LabRolePermission -Role 'audit' -ActualPermissions $actual
        $drift.Kind | Should -Contain 'Missing'
        ($drift | Where-Object Permission -eq 'ViewSafeMembers') | Should -Not -BeNullOrEmpty
    }

    It 'treats a permission explicitly set to false as absent' {
        $actual = [pscustomobject]@{
            ListAccounts    = $true
            ViewAuditLog    = $true
            ViewSafeMembers = $false
        }

        $drift = Compare-LabRolePermission -Role 'audit' -ActualPermissions $actual
        ($drift | Where-Object { $_.Permission -eq 'ViewSafeMembers' -and $_.Kind -eq 'Missing' }) |
            Should -Not -BeNullOrEmpty
    }

    It 'handles a member with no permission object at all' {
        # psPAS can return $null here; the script must not blow up mid-run.
        { Compare-LabRolePermission -Role 'audit' -ActualPermissions $null } | Should -Not -Throw
    }

    It 'ignores non-boolean properties psPAS attaches to the object' {
        $actual = [pscustomobject]@{
            ListAccounts    = $true
            ViewAuditLog    = $true
            ViewSafeMembers = $true
            MemberName      = 'lab-auditors'   # string, not a permission
            MemberId        = 42               # int, not a permission
        }

        Compare-LabRolePermission -Role 'audit' -ActualPermissions $actual |
            Should -BeNullOrEmpty
    }
}
