BeforeDiscovery {
    $env:PSModulePath=(Split-Path (Split-Path $PSScriptRoot))+';'+$env:PSModulePath
    Import-Module (Join-Path (Split-Path $PSScriptRoot) 'DriftDetect.WinServer.psd1') -ErrorAction Stop
}
Describe 'Windows capture and Core integration' {
    InModuleScope DriftDetect.WinServer {
        BeforeEach {
            Mock Invoke-WSQuery {
                if ($Unit -eq 'Target') { return @{Id='11111111-2222-3333-4444-555555555555';Name='SERVER01';IdentitySource='SMBIOS.UUID';Version='10.0';Build='20348';DomainRole=3;PartOfDomain=$false} }
                return @{Status='Success';Entities=@();Reason=''}
            }
        }
        It 'records all sixteen collection units including explicit optional skips' {
            $snapshot=New-WSSnapshot
            $snapshot.Collections.Count | Should -Be 16
            @($snapshot.Collections | Where-Object Status -eq 'Skipped').Count | Should -Be 3
            $snapshot.ComputerName | Should -Be 'SERVER01'
            $snapshot.SchemaVersion | Should -Be '2.0'
        }
        It 'IncludeAll enables optional units and normalizes allowlist scope' {
            $snapshot=New-WSSnapshot -IncludeAll -TaskArgumentAllowList '\Ops\Reviewed','\ops\reviewed'
            @($snapshot.Collections | Where-Object Status -eq 'Skipped').Count | Should -Be 0
            $snapshot.CollectionProfile.TaskArgumentAllowList.Count | Should -Be 1
            $snapshot.CollectionProfile.TaskArgumentAllowList[0] | Should -Be '\ops\reviewed'
        }
        It 'retains readable exclusion coverage even when task and registry units contain zero entities' {
            $snapshot=New-WSSnapshot -IncludeAll
            $tasks=$snapshot.Collections | Where-Object Id -eq 'ScheduledTasks.Tasks'
            $registry=$snapshot.Collections | Where-Object Id -eq 'Registry.Values'
            $tasks.EntityCount | Should -Be 0
            $tasks.Scope.ArgumentCoverage | Should -Match 'argument drift.*not assessed'
            ($tasks.Scope.Exclusions -join ' ') | Should -Match 'argument'
            ($registry.Scope.Exclusions -join ' ') | Should -Match 'registry.*excluded'
            $registry.Scope.ExcludedValueNames | Should -Contain 'DefaultPassword'
            $registry.Scope.Contains('ExcludedNamePattern') | Should -BeFalse
            $snapshot.CollectionProfile.ArgumentCoverage | Should -Match 'argument drift.*not assessed'
            $snapshot.CollectionProfile.RegistryExclusionCoverage | Should -Match 'exact.*value names'
            ($snapshot.CollectionProfile.Exclusions -join ' ') | Should -Match 'argument.*registry'
        }
        It 'persists failed unit status without raw exception values' {
            Mock Invoke-WSQuery { throw 'unrecognized-private-value' } -ParameterFilter { $Unit -eq 'Accounts.Groups' }
            $snapshot=New-WSSnapshot -WarningAction SilentlyContinue
            ($snapshot.Collections | Where-Object Id -eq 'Accounts.Groups').Status | Should -Be 'Failed'
            ($snapshot | ConvertTo-Json -Depth 100) | Should -Not -Match 'unrecognized-private-value'
        }
        It 'Strict terminates on an incomplete requested unit' {
            Mock Invoke-WSQuery { throw 'private-value' } -ParameterFilter { $Unit -eq 'Storage.Disks' }
            { New-WSSnapshot -Strict } | Should -Throw '*Storage.Disks*'
        }
        It 'does not mix unrelated optional options into successful unit scope' {
            $a=New-WSSnapshot
            $b=New-WSSnapshot -IncludeRegistry
            $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b -AllowPartial
            $result.IsComplete | Should -BeFalse
            $result.TotalChanges | Should -Be 0
        }
        It 'rejects broad argument allowlists' {
            { New-WSSnapshot -IncludeScheduledTasks -TaskArgumentAllowList '\Ops\*' } | Should -Throw '*exact full*'
        }
        It 'closes its remote session after strict failure' {
            Mock New-PSSession { 'owned-test-session' }
            Mock Remove-PSSession { } -RemoveParameterType Session
            Mock Invoke-WSQuery { throw 'failed query' } -ParameterFilter { $Unit -eq 'Storage.Disks' }
            { New-WSSnapshot -ComputerName remote-test -Strict } | Should -Throw '*Storage.Disks*'
            Should -Invoke Remove-PSSession -Times 1 -Exactly
        }
        It 'never falls back to display name when identity capture fails' {
            Mock Invoke-WSQuery { throw 'identity failure' } -ParameterFilter { $Unit -eq 'Target' }
            { New-WSSnapshot } | Should -Throw '*trustworthy Windows target identity*'
        }
        It 'round trips local JSON paths containing brackets and compares offline' {
            $path=Join-Path $TestDrive 'baseline [one].json'
            $a=New-WSSnapshot -OutputPath $path
            $b=Get-WSSnapshot -Path $path
            $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b
            $result.IsComplete | Should -BeTrue
            $result.TotalChanges | Should -Be 0
        }
    }
}


