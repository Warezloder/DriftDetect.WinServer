BeforeAll {
    $moduleRoot=Split-Path $PSScriptRoot
    $env:PSModulePath=(Split-Path $moduleRoot)+';'+$env:PSModulePath
    Import-Module DriftDetect.Core -ErrorAction Stop
    . (Join-Path $moduleRoot 'Private/Transport.ps1')
    . (Join-Path $moduleRoot 'Collectors/Windows.ps1')
    . (Join-Path $moduleRoot 'Public/Compare-WSSnapshot.ps1')
    $script:WinRules=Import-DDRuleSet -Path (Join-Path $moduleRoot 'Config/Rules.json')
    function Get-ScheduledTask { }
    function Export-ScheduledTask { }
    function Get-ScheduledTaskInfo { }
    function Get-NetAdapter { }
    function Get-NetIPAddress { }
    function Get-DnsClientServerAddress { }
    function Get-NetIPInterface { }
    function Get-NetRoute { }
    function Get-Volume { }
    function New-ProviderFixtureSnapshot($Envelope,$Unit,$Scope=@{}) {
        $entities=@(foreach($record in $Envelope.Entities){New-DDEntity -EntityType $record.EntityType -Id $record.Id -Name $record.Name -CollectionId $Unit -Properties $record.Properties -Observations $record.Observations})
        $collection=New-DDCollection -Id $Unit -Status $Envelope.Status -Scope $Scope -Entities $entities
        New-DDSnapshot -Technology WinServer -Target @{Id='fixture-target';Name='server';Version='10';Build='1';IdentitySource='Fixture'} -Collections @($collection) -RuleSet $script:WinRules
    }
    function Set-TaskFixture([string]$Argument='first',[string]$User='S-1-5-18',[string]$Boundary='2026-01-01T00:00:00') {
        $script:FixtureXml='<Task><Triggers><TimeTrigger><StartBoundary>'+$Boundary+'</StartBoundary></TimeTrigger></Triggers><Principals><Principal><UserId>'+$User+'</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><Enabled>false</Enabled></Settings><Actions><Exec><Command>tool.exe</Command><Arguments>'+$Argument+'</Arguments></Exec></Actions></Task>'
    }
}
Describe 'Normalized Windows provider data compared by real Core' {
    BeforeEach {
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Reviewed';TaskPath='\Ops\'} }
        Mock Export-ScheduledTask { $script:FixtureXml }
        Mock Get-ScheduledTaskInfo { [pscustomobject]@{LastTaskResult=0} }
    }
    It 'detects allowlisted argument changes in ordered execution actions' {
        Set-TaskFixture -Argument 'first'
        $a=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{TaskArgumentAllowList=@('\Ops\Reviewed')}) 'ScheduledTasks.Tasks'
        Set-TaskFixture -Argument 'changed'
        $b=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{TaskArgumentAllowList=@('\Ops\Reviewed')}) 'ScheduledTasks.Tasks'
        $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b
        $result.TotalChanges | Should -Be 1
        $result.Changes[0].PropertyPath | Should -Be '/OrderedActions'
    }
    It 'never persists or compares omitted arguments including unrecognized values' {
        Set-TaskFixture -Argument 'first-private-value'
        $a=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}) 'ScheduledTasks.Tasks'
        Set-TaskFixture -Argument 'other-private-value'
        $b=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}) 'ScheduledTasks.Tasks'
        (Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b).TotalChanges | Should -Be 0
        ($a,$b | ConvertTo-Json -Depth 100) | Should -Not -Match 'first-private-value|other-private-value'
    }
    It 'detects trigger and principal changes on disabled tasks' {
        Set-TaskFixture
        $a=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}) 'ScheduledTasks.Tasks'
        Set-TaskFixture -User 'S-1-5-19' -Boundary '2026-01-01T01:00:00'
        $b=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'ScheduledTasks.Tasks' -Options @{}) 'ScheduledTasks.Tasks'
        $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b
        $result.TotalChanges | Should -Be 2
        $result.Changes.PropertyPath | Should -Contain '/Principals/Principal/UserId'
        $result.Changes.PropertyPath | Should -Contain '/Triggers/TimeTrigger/StartBoundary'
    }
    It 'detects ordered per-interface DNS reversal and keeps routes as configuration' {
        Mock Get-NetAdapter { [pscustomobject]@{Name='LAN';InterfaceGuid='adapter-guid';ifIndex=1;Status='Up'} }
        Mock Get-NetIPAddress { [pscustomobject]@{IPAddress='10.0.0.2';PrefixLength=24;AddressFamily='IPv4'} }
        Mock Get-NetIPInterface { [pscustomobject]@{AddressFamily='IPv4';Dhcp='Disabled'} }
        Mock Get-NetRoute { [pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='10.0.0.1';RouteMetric=25} }
        Mock Get-DnsClientServerAddress { [pscustomobject]@{AddressFamily=2;ServerAddresses=@('10.0.0.10','10.0.0.11')} }
        $a=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'Network.Adapters' -Options @{}) 'Network.Adapters'
        Mock Get-DnsClientServerAddress { [pscustomobject]@{AddressFamily=2;ServerAddresses=@('10.0.0.11','10.0.0.10')} }
        $b=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'Network.Adapters' -Options @{}) 'Network.Adapters'
        $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b
        $result.TotalChanges | Should -Be 1
        $result.Changes.PropertyPath | Should -Be '/Dns'
        $a.Entities.NetworkAdapter[0].Properties.Routes[0].NextHop | Should -Be '10.0.0.1'
    }
    It 'uses SID membership as a set and reports security entity additions' {
        $a=New-ProviderFixtureSnapshot @{Status='Success';Entities=@(@{EntityType='LocalGroup';Id='S-1-5-32-544';Name='Administrators';Properties=@{Members=@('sid-a','sid-b')};Observations=@{}})} 'Accounts.Groups'
        $b=New-ProviderFixtureSnapshot @{Status='Success';Entities=@(@{EntityType='LocalGroup';Id='S-1-5-32-544';Name='Administrators';Properties=@{Members=@('sid-b','sid-a')};Observations=@{}})} 'Accounts.Groups'
        (Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b).TotalChanges | Should -Be 0
        $empty=New-ProviderFixtureSnapshot @{Status='Success';Entities=@()} 'Accounts.Groups'
        $result=Compare-WSSnapshot -BaselineSnapshot $empty -CurrentSnapshot $a
        $result.TotalChanges | Should -Be 1
        $result.NewEntities[0].Severity | Should -Be 'High'
    }
    It 'recursively detects trust direction changes under the keyed provider policy' {
        $a=New-ProviderFixtureSnapshot @{Status='Success';Entities=@(@{EntityType='DomainTrusts';Id='trusts';Name='Trusts';Properties=@{Trusts=@(@{TrustedDomain='partner.test';TrustDirection=1})};Observations=@{}})} 'Domain.Trusts'
        $b=New-ProviderFixtureSnapshot @{Status='Success';Entities=@(@{EntityType='DomainTrusts';Id='trusts';Name='Trusts';Properties=@{Trusts=@(@{TrustedDomain='partner.test';TrustDirection=3})};Observations=@{}})} 'Domain.Trusts'
        $result=Compare-WSSnapshot -BaselineSnapshot $a -CurrentSnapshot $b
        $result.TotalChanges | Should -Be 1
        $result.Changes[0].PropertyPath | Should -Match 'TrustDirection$'
        $result.Changes[0].Severity | Should -Be 'High'
    }
    It 'projects CIM character drive letters into the plain snapshot contract' {
        Mock Get-Volume { [pscustomobject]@{UniqueId='volume-id';Path='volume-path';DriveLetter=[char]'C';Size=100;SizeRemaining=50} }
        $snapshot=New-ProviderFixtureSnapshot (Invoke-WSQuery -Unit 'Storage.Volumes' -Options @{}) 'Storage.Volumes'
        $snapshot.Entities.Volume[0].Properties.DriveLetter | Should -BeOfType string
        $snapshot.Entities.Volume[0].Properties.DriveLetter | Should -Be 'C'
    }
}
