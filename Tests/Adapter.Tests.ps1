BeforeAll {
    $root = Split-Path $PSScriptRoot
    foreach ($folder in 'Private','Collectors') {
        Get-ChildItem (Join-Path $root $folder) -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
    }
    function Get-ScheduledTask { }
    function Export-ScheduledTask { }
    function Get-ScheduledTaskInfo { }
    function Get-Volume { }
    function Get-Disk { }
    function Get-LocalGroup { }
    function Get-LocalGroupMember { }
    function Get-NetLbfoTeam { }
    function Get-WindowsFeature { }
    function Get-NetFirewallRule { }
    function Get-NetFirewallAddressFilter { }
    function Get-NetFirewallApplicationFilter { }
    function Get-NetFirewallServiceFilter { }
    function Get-NetFirewallPortFilter { }
    function Get-NetFirewallInterfaceFilter { }
    function Get-NetFirewallInterfaceTypeFilter { }
    function Get-NetFirewallSecurityFilter { }
    function gpresult.exe { }
    $script:TaskXml = '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><CalendarTrigger><StartBoundary>2026-01-01T12:00:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers><Principals><Principal id="Author"><UserId>S-1-5-18</UserId><LogonType>ServiceAccount</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><Enabled>false</Enabled><ExecutionTimeLimit>PT72H</ExecutionTimeLimit></Settings><Actions Context="Author"><Exec><Command>tool.exe</Command><Arguments>unrecognized-private-value</Arguments><WorkingDirectory>C:\Tools</WorkingDirectory></Exec><Exec><Command>second.exe</Command></Exec></Actions></Task>'
}
Describe 'Windows transport and normalization' {
    It 'preserves an array as one local invocation argument' {
        $actual = Invoke-WSCommand -ScriptBlock { param($paths,$flag) @{ Paths=@($paths); Flag=$flag } } -ArgumentList @(@('a','b'),$true)
        $actual.Paths.Count | Should -Be 2
        $actual.Flag | Should -BeTrue
    }
    It 'returns disabled task configuration but excludes arguments before data leaves provider' {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Daily';TaskPath='\Ops\'} }
        Mock Export-ScheduledTask { $script:TaskXml }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastTaskResult=0;LastRunTime=[datetime]'2026-01-01';NextRunTime=[datetime]'2026-01-02'} }
        $result=Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{ TaskArgumentAllowList=@() }
        $result.Status | Should -Be 'Success'
        $json=$result | ConvertTo-Json -Depth 40
        $json | Should -Not -Match 'unrecognized-private-value'
        $json | Should -Match 'ArgumentsExcluded'
        $result.Entities[0].Properties.Settings.Enabled | Should -Be 'false'
        $result.Entities[0].Properties.OrderedActions.Count | Should -Be 2
    }
    It 'captures arguments only for the exact full allowlisted task path' {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Daily';TaskPath='\Ops\'} }
        Mock Export-ScheduledTask { $script:TaskXml }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastTaskResult=0} }
        $allowed=Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{TaskArgumentAllowList=@('\Ops\Daily')}
        ($allowed | ConvertTo-Json -Depth 40) | Should -Match 'unrecognized-private-value'
        $other=Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{TaskArgumentAllowList=@('\Ops\*')}
        ($other | ConvertTo-Json -Depth 40) | Should -Not -Match 'unrecognized-private-value'
    }
    It 'uses stable volume identity even without a drive letter and keeps free space in observations' {
        Mock Get-Volume { [pscustomobject]@{UniqueId='volume-42';Path='\\?\Volume{42}\';DriveLetter=$null;FileSystem='NTFS';FileSystemLabel='Data';Size=100;SizeRemaining=50;HealthStatus='Healthy';OperationalStatus='OK'} }
        $result=Invoke-WSQuery -Unit 'Storage.Volumes' -Options @{}
        $result.Entities[0].Id | Should -Be 'volume-42'
        $result.Entities[0].Properties.ContainsKey('SizeRemaining') | Should -BeFalse
        $result.Entities[0].Observations.SizeRemaining | Should -Be 50
    }
    It 'rejects duplicate or absent stable storage identities' {
        Mock Get-Volume { [pscustomobject]@{UniqueId='';Path='';DriveLetter='C'} }
        { Invoke-WSQuery -Unit 'Storage.Volumes' -Options @{} } | Should -Throw '*identity*'
        Mock Get-Volume { @([pscustomobject]@{UniqueId='same';Path='a'},[pscustomobject]@{UniqueId='same';Path='b'}) }
        { Invoke-WSQuery -Unit 'Storage.Volumes' -Options @{} } | Should -Throw '*identity*'
    }
    It 'does not turn failed membership enumeration into an empty group' {
        Mock Get-LocalGroup { [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-32-544'};Name='Administrators'} }
        Mock Get-LocalGroupMember { throw 'access denied private-value' }
        { Invoke-WSQuery -Unit 'Accounts.Groups' -Options @{DomainRole=3} } | Should -Throw '*access denied*'
    }
    It 'positively excludes local SAM on domain controllers' {
        (Invoke-WSQuery -Unit 'Accounts.Groups' -Options @{DomainRole=5}).Status | Should -Be 'NotApplicable'
    }
    It 'distinguishes successful empty teaming query' {
        Mock Get-NetLbfoTeam { @() }
        (Invoke-WSQuery -Unit 'Network.Teams' -Options @{}).Status | Should -Be 'Success'
    }
    It 'fails feature collection when the provider query fails' {
        Mock Get-WindowsFeature { throw 'feature provider unavailable' }
        { Invoke-WSQuery -Unit 'Features.Installed' -Options @{} } | Should -Throw '*feature provider*'
    }
    It 'preserves mixed action execution order' {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Daily';TaskPath='\Ops\'} }
        Mock Export-ScheduledTask { '<Task><Actions><Exec><Command>one</Command></Exec><ComHandler><ClassId>abc</ClassId></ComHandler><Exec><Command>three</Command></Exec></Actions></Task>' }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastTaskResult=0} }
        $result=Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}
        $result.Entities[0].Properties.OrderedActions.Type -join ',' | Should -Be 'Exec,ComHandler,Exec'
    }
    It 'retains named values and attributes inside complete trigger XML' {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Daily';TaskPath='\Ops\'} }
        Mock Export-ScheduledTask { '<Task><Triggers><EventTrigger><Subscription>event query</Subscription><ValueQueries><Value name="Account">Event/EventData/Data</Value></ValueQueries></EventTrigger></Triggers><Actions><Exec><Command>tool.exe</Command></Exec></Actions></Task>' }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastTaskResult=0} }
        $result=Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}
        $result.Entities[0].Properties.Triggers.EventTrigger.ValueQueries.Value.'@name' | Should -Be 'Account'
        $result.Entities[0].Properties.Triggers.EventTrigger.ValueQueries.Value.'#text' | Should -Be 'Event/EventData/Data'
    }
    It 'collects disabled firewall rules with all associated filters' {
        Mock Get-NetFirewallRule { [pscustomobject]@{Name='rule';DisplayName='Rule';Enabled='False'} }
        Mock Get-NetFirewallAddressFilter { [pscustomobject]@{LocalAddress=@('Any');RemoteAddress=@('10.0.0.0/8')} }
        Mock Get-NetFirewallApplicationFilter { [pscustomobject]@{Program='C:\app.exe';Package='Any'} }
        Mock Get-NetFirewallServiceFilter { [pscustomobject]@{Service='Any'} }
        Mock Get-NetFirewallPortFilter { [pscustomobject]@{Protocol='TCP';LocalPort='443'} }
        Mock Get-NetFirewallInterfaceFilter { [pscustomobject]@{InterfaceAlias=@('Any')} }
        Mock Get-NetFirewallInterfaceTypeFilter { [pscustomobject]@{InterfaceType='Any'} }
        Mock Get-NetFirewallSecurityFilter { [pscustomobject]@{Authentication='NotRequired'} }
        $result=Invoke-WSQuery -Unit 'Firewall.Rules' -Options @{}
        $result.Entities[0].Properties.Enabled | Should -Be 'False'
        $result.Entities[0].Properties.Address[0].RemoteAddress[0] | Should -Be '10.0.0.0/8'
        $result.Entities[0].Properties.Application[0].Program | Should -Be 'C:\app.exe'
    }
    It 'does not turn failed firewall filter collection into success' {
        Mock Get-NetFirewallRule { [pscustomobject]@{Name='rule';DisplayName='Rule';Enabled='False'} }
        Mock Get-NetFirewallAddressFilter { throw 'filter access denied' }
        { Invoke-WSQuery -Unit 'Firewall.Rules' -Options @{} } | Should -Throw '*filter access denied*'
    }
    It 'passes registry scope locally and observes missing selected keys' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'HKLM:\Missing' }
        $result=Invoke-WSQuery -Unit 'Registry.Values' -Options @{RegistryPaths=@('HKLM:\Missing');Recurse=$true}
        $result.Entities[0].Properties.Exists | Should -BeFalse
        $result.Entities[0].Id | Should -Be 'hkey_local_machine\missing'
    }
    It 'omits secret registry values without reading them and records value kinds' {
        $key=[pscustomobject]@{Name='HKEY_LOCAL_MACHINE\Test'}
        $key | Add-Member ScriptMethod GetValueNames { @('DefaultPassword','Value') }
        $key | Add-Member ScriptMethod GetValue { param($name,$default,$options) if($name -eq 'DefaultPassword'){throw 'secret was read'}; 'configured' }
        $key | Add-Member ScriptMethod GetValueKind { param($name) 'String' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        Mock Get-Item { $key } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        $result=Invoke-WSQuery -Unit 'Registry.Values' -Options @{RegistryPaths=@('HKLM:\Test');Recurse=$true}
        $result.Entities[0].Properties.Values.Value.Kind | Should -Be 'String'
        $result.Entities[0].Properties.Values.ContainsKey('DefaultPassword') | Should -BeFalse
        $result.Entities[0].Properties.ExcludedValueNames | Should -Contain 'DefaultPassword'
    }
    It 'retains password and credential policy settings while excluding exact secret value names' {
        $key=[pscustomobject]@{Name='HKEY_LOCAL_MACHINE\Test'}
        $key | Add-Member ScriptMethod GetValueNames { @('DefaultPassword','DefaultPin','AltDefaultPassword','AutoLogonPassword','PasswordComplexity','PasswordHistorySize','MaximumPasswordAge','DisablePasswordChange','AutoLogonCount','CredentialGuard','PrivateKeyArchive','SecretPolicy') }
        $key | Add-Member ScriptMethod GetValue { param($name,$default,$options) if($name -in 'DefaultPassword','DefaultPin','AltDefaultPassword','AutoLogonPassword'){throw 'secret was read'}; 1 }
        $key | Add-Member ScriptMethod GetValueKind { param($name) 'DWord' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        Mock Get-Item { $key } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -eq 'HKLM:\Test' }
        $result=Invoke-WSQuery -Unit 'Registry.Values' -Options @{RegistryPaths=@('HKLM:\Test');Recurse=$true}
        foreach($name in 'PasswordComplexity','PasswordHistorySize','MaximumPasswordAge','DisablePasswordChange','AutoLogonCount','CredentialGuard','PrivateKeyArchive','SecretPolicy') {
            $result.Entities[0].Properties.Values.ContainsKey($name) | Should -BeTrue
            $result.Entities[0].Properties.Values[$name].Value | Should -Be 1
        }
        $result.Entities[0].Properties.ExcludedValueNames.Count | Should -Be 4
    }
    It 'preserves argument cardinality through the remote invocation boundary' {
        Mock Invoke-Command {
            $output=& $ScriptBlock @ArgumentList
            [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($output))
        } -RemoveParameterType Session
        $result=Invoke-WSCommand -Session 'synthetic-session' -ScriptBlock { param($paths,$flag) @{Paths=@($paths);Flag=$flag} } -ArgumentList @(@('first','second'),$true)
        $result.Paths.Count | Should -Be 2
        $result.Flag | Should -BeTrue
    }
    It 'falls back to MachineGuid when SMBIOS identity cannot be queried' {
        Mock Get-CimInstance {
            if($ClassName -eq 'Win32_ComputerSystemProduct'){throw 'SMBIOS unavailable'}
            if($ClassName -eq 'Win32_ComputerSystem'){return [pscustomobject]@{Name='server';DomainRole=3;PartOfDomain=$false}}
            [pscustomobject]@{Version='10.0';BuildNumber='20348'}
        }
        Mock Get-ItemProperty { [pscustomobject]@{MachineGuid='11111111-2222-3333-4444-555555555555'} }
        $result=Invoke-WSQuery -Unit Target -Options @{}
        $result.IdentitySource | Should -Be 'Registry.MachineGuid'
        $result.Id | Should -Be '11111111-2222-3333-4444-555555555555'
    }
}
Describe 'Group Policy structured output' {
    It 'extracts stable GPO identity and omits refresh timestamps' {
        $xml=Get-Content (Join-Path $PSScriptRoot 'Fixtures/gpresult.xml') -Raw
        $first=ConvertFrom-WSGroupPolicyXml -Xml $xml
        @($first).Count | Should -Be 1
        $first[0].Id | Should -Be '{01234567-89AB-CDEF-0123-456789ABCDEF}'
        ($first | ConvertTo-Json -Depth 30) | Should -Not -Match 'LastRefresh|2026-10-28'
    }
    It 'rejects unsuccessful native capture even if XML exists' {
        { ConvertFrom-WSGroupPolicyXml -Xml '<Rsop />' -ExitCode 5 } | Should -Throw '*exit*'
    }
    It 'rejects malformed or unrelated XML' {
        { ConvertFrom-WSGroupPolicyXml -Xml '<html />' } | Should -Throw
    }
    It 'checks gpresult process exit before reading its output' {
        Mock gpresult.exe { $global:LASTEXITCODE=5 }
        { Invoke-WSQuery -Unit 'GroupPolicy.Applied' -Options @{} } | Should -Throw '*exit code*'
    }
    It 'ignores nested GPO references inside per-setting ExtensionData' {
        $xml=Get-Content (Join-Path $PSScriptRoot 'Fixtures/gpresult.xml') -Raw
        $xml=$xml.Replace('</ComputerResults>','<ExtensionData><Extension><Account><GPO><Identifier>{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}</Identifier><Domain>example.test</Domain></GPO></Account></Extension></ExtensionData></ComputerResults>')
        $gpos=ConvertFrom-WSGroupPolicyXml -Xml $xml
        $gpos.Count | Should -Be 1
        $gpos[0].Id | Should -Be '{01234567-89AB-CDEF-0123-456789ABCDEF}'
    }
}
