<#
  Contract tests for Test-Reconciliation.ps1.

  The script runs UNMODIFIED. tests/stubs is prepended to PSModulePath so its
  `Import-Module psPAS` resolves to the stub tenant instead of the real module.
  A test that requires editing the thing under test is testing something else.

  Each case builds a tenant, runs the script in a child pwsh (it calls exit, so
  it cannot run in-process), and asserts on the JSON drift report and the exit
  code. Writes are captured so -Apply can be checked for what it did AND for
  what it did not do.

  These are contract tests against the shapes this script consumes. They are not
  evidence it works against a real EPV; there is no free self-hosted CyberArk to
  run it on. What they do cover is every line of drift classification, which
  previously ran nowhere at all.
#>

BeforeAll {
    $script:LabRoot = Split-Path -Parent $PSScriptRoot
    $script:Script = Join-Path $LabRoot 'scripts/Test-Reconciliation.ps1'
    $script:Stubs = Join-Path $PSScriptRoot 'stubs'

    # Build the "live" permission objects from RoleMap itself rather than
    # hand-writing them here. Hand-written copies drift from the definition and
    # then the tests pass while describing a permission set that no longer
    # exists, which is the failure mode this whole repo keeps running into.
    Import-Module (Join-Path $LabRoot 'scripts/RoleMap.psm1') -Force

    function Get-RolePerm {
        param([string]$Role)
        # psPAS returns permissions as an object with boolean properties; the
        # role map returns a hashtable. Convert so the stub hands the script the
        # shape Compare-LabRolePermission actually walks.
        [pscustomobject](Get-LabRolePermission -Role $Role)
    }

    function Get-FullPerm { Get-RolePerm -Role 'full' }
    function Get-AuditPerm { Get-RolePerm -Role 'audit' }

    function New-StateFile {
        param([string]$Yaml)
        $p = Join-Path ([System.IO.Path]::GetTempPath()) "state-$([guid]::NewGuid()).yml"
        Set-Content -Path $p -Value $Yaml -Encoding utf8
        $p
    }

    function New-TenantFile {
        param([hashtable]$Tenant)
        $p = Join-Path ([System.IO.Path]::GetTempPath()) "tenant-$([guid]::NewGuid()).json"
        $Tenant | ConvertTo-Json -Depth 8 | Set-Content -Path $p -Encoding utf8
        $p
    }

    function Invoke-Reconcile {
        param([string]$StatePath, [string]$TenantPath, [switch]$Apply)

        $json = Join-Path ([System.IO.Path]::GetTempPath()) "drift-$([guid]::NewGuid()).json"
        $writes = Join-Path ([System.IO.Path]::GetTempPath()) "writes-$([guid]::NewGuid()).jsonl"
        New-Item -ItemType File -Path $writes -Force | Out-Null

        $applyArg = if ($Apply) { '-Apply' } else { '' }
        $cmd = @"
`$env:PSModulePath = '$Stubs' + [IO.Path]::PathSeparator + `$env:PSModulePath
`$env:STUB_TENANT = '$TenantPath'
`$env:STUB_WRITES = '$writes'
& '$Script' -IntendedStatePath '$StatePath' -JsonPath '$json' $applyArg
exit `$LASTEXITCODE
"@
        $out = pwsh -NoProfile -Command $cmd 2>&1
        $code = $LASTEXITCODE

        [pscustomobject]@{
            ExitCode = $code
            Output   = ($out -join "`n")
            Report   = if (Test-Path $json) { Get-Content -Raw $json | ConvertFrom-Json } else { $null }
            Writes   = @(Get-Content $writes -ErrorAction SilentlyContinue |
                Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
        }
    }

    # A state file with one safe, two members, one account.
    $script:BaseState = @'
safes:
  - name: LAB-Linux-Root
    description: Root credentials for lab Linux hosts
    managingCPM: PasswordManager
    members:
      - name: lab-pam-admins
        role: full
      - name: lab-auditors
        role: audit
accounts:
  - safe: LAB-Linux-Root
    platformId: UnixSSH
    address: host1.lab
    userName: root
'@
}

Describe 'Reconciliation drift classification' {

    It 'reports no drift when the tenant matches the state file' {
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{
            safes   = @(@{ safeName = 'LAB-Linux-Root' })
            members = @{
                'LAB-Linux-Root' = @(
                    @{ MemberName = 'lab-pam-admins'; Permissions = (Get-FullPerm) },
                    @{ MemberName = 'lab-auditors'; Permissions = (Get-AuditPerm) }
                )
            }
            accounts = @(@{ safeName = 'LAB-Linux-Root'; userName = 'root'; address = 'host1.lab'; platformId = 'UnixSSH' })
        }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        $r.Report.driftCount | Should -Be 0
        $r.ExitCode | Should -Be 0
    }

    It 'flags a member nobody declared as UNEXPECTED' {
        # The finding that matters: access no document explains.
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{
            safes   = @(@{ safeName = 'LAB-Linux-Root' })
            members = @{
                'LAB-Linux-Root' = @(
                    @{ MemberName = 'lab-pam-admins'; Permissions = (Get-FullPerm) },
                    @{ MemberName = 'lab-auditors'; Permissions = (Get-AuditPerm) },
                    @{ MemberName = 'mystery-contractor'; Permissions = (Get-FullPerm) }
                )
            }
            accounts = @(@{ safeName = 'LAB-Linux-Root'; userName = 'root'; address = 'host1.lab'; platformId = 'UnixSSH' })
        }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        $unexpected = @($r.Report.drift | Where-Object Issue -eq 'UNEXPECTED')
        $unexpected.Count | Should -Be 1
        $unexpected[0].Name | Should -BeLike '*mystery-contractor'
        $r.ExitCode | Should -Be 1
    }

    It 'flags a declared member holding more than their role as EXTRA_PERM' {
        # Privilege creep: granted "temporarily" during an incident, never removed.
        $state = New-StateFile $BaseState
        # The auditor with ManageSafeMembers bolted on. Add-Member rather than
        # assignment: the audit role does not define the property at all, which
        # is precisely why holding it is privilege creep.
        $over = Get-AuditPerm
        $over | Add-Member -NotePropertyName 'ManageSafeMembers' -NotePropertyValue $true
        $tenant = New-TenantFile @{
            safes   = @(@{ safeName = 'LAB-Linux-Root' })
            members = @{
                'LAB-Linux-Root' = @(
                    @{ MemberName = 'lab-pam-admins'; Permissions = (Get-FullPerm) },
                    @{ MemberName = 'lab-auditors'; Permissions = $over }
                )
            }
            accounts = @(@{ safeName = 'LAB-Linux-Root'; userName = 'root'; address = 'host1.lab'; platformId = 'UnixSSH' })
        }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        @($r.Report.drift | Where-Object Issue -eq 'EXTRA_PERM').Count | Should -BeGreaterThan 0
        $r.ExitCode | Should -Be 1
    }

    It 'flags a missing safe and does not then evaluate its members' {
        # Nothing about a safe can be checked until it exists; the script must
        # not emit a cascade of member findings for a safe that is not there.
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{ safes = @(); members = @{}; accounts = @() }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        $safeDrift = @($r.Report.drift | Where-Object { $_.Type -eq 'Safe' -and $_.Issue -eq 'MISSING' })
        $safeDrift.Count | Should -Be 1
        @($r.Report.drift | Where-Object Type -eq 'Permission').Count | Should -Be 0
    }

    It 'flags an account on the wrong platform' {
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{
            safes   = @(@{ safeName = 'LAB-Linux-Root' })
            members = @{
                'LAB-Linux-Root' = @(
                    @{ MemberName = 'lab-pam-admins'; Permissions = (Get-FullPerm) },
                    @{ MemberName = 'lab-auditors'; Permissions = (Get-AuditPerm) }
                )
            }
            accounts = @(@{ safeName = 'LAB-Linux-Root'; userName = 'root'; address = 'host1.lab'; platformId = 'WinDomain' })
        }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        @($r.Report.drift | Where-Object Issue -eq 'WRONG_PLATFORM').Count | Should -Be 1
    }
}

Describe 'State file validation happens before the tenant is touched' {

    It 'refuses an unknown role rather than granting an empty permission set' {
        # An unknown role reaching the apply path would add a member who can do
        # nothing, and it would look like success.
        $state = New-StateFile @'
safes:
  - name: LAB-Linux-Root
    description: x
    managingCPM: PasswordManager
    members:
      - name: someone
        role: superuser
'@
        $tenant = New-TenantFile @{ safes = @(); members = @{}; accounts = @() }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant -Apply
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match 'unknown role'
        # And critically: nothing was written despite -Apply.
        $r.Writes.Count | Should -Be 0
    }
}

Describe 'Apply writes what it should, and nothing else' {

    It 'creates a missing safe and adds its declared members' {
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{ safes = @(); members = @{}; accounts = @() }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant -Apply
        @($r.Writes | Where-Object cmdlet -eq 'Add-PASSafe').Count | Should -Be 1
    }

    It 'never deletes anything, even when the tenant has undeclared members' {
        # The stub does not export any Remove-* cmdlet. If the script ever grows
        # a deletion path this fails loudly with "term not recognized", which is
        # the point: a reconciler that revokes access on a bad state file will
        # do it during an incident.
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{
            safes   = @(@{ safeName = 'LAB-Linux-Root' })
            members = @{
                'LAB-Linux-Root' = @(
                    @{ MemberName = 'lab-pam-admins'; Permissions = (Get-FullPerm) },
                    @{ MemberName = 'lab-auditors'; Permissions = (Get-AuditPerm) },
                    @{ MemberName = 'mystery-contractor'; Permissions = (Get-FullPerm) }
                )
            }
            accounts = @(@{ safeName = 'LAB-Linux-Root'; userName = 'root'; address = 'host1.lab'; platformId = 'UnixSSH' })
        }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant -Apply
        @($r.Writes | Where-Object { $_.cmdlet -like 'Remove-*' }).Count | Should -Be 0
        $r.Output | Should -Not -Match 'not recognized'
    }

    It 'writes nothing at all without -Apply' {
        $state = New-StateFile $BaseState
        $tenant = New-TenantFile @{ safes = @(); members = @{}; accounts = @() }
        $r = Invoke-Reconcile -StatePath $state -TenantPath $tenant
        $r.Writes.Count | Should -Be 0
    }
}
