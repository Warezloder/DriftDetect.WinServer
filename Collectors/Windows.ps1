# This scriptblock executes on Windows PowerShell 5.1 endpoints. Keep all
# projection code inside the block and send only plain records over remoting.
$script:WSProviderQuery = {
    param([string]$Unit, $Options)
    $ErrorActionPreference='Stop'
    function Select-Fields($Object,[string[]]$Fields) {
        $map=@{}
        foreach ($field in $Fields) {
            $value=$Object.$field
            if ($null -eq $value) { $map[$field]=$null }
            elseif ($value -is [datetime]) { $map[$field]=$value.ToUniversalTime().ToString('o') }
            elseif ($value -is [System.Enum]) { $map[$field]=$value.ToString() }
            elseif ($value -is [array]) { $map[$field]=@($value | ForEach-Object { if ($_ -is [System.Enum]) {$_.ToString()} else {$_} }) }
            else { $map[$field]=$value }
        }
        return $map
    }
    function Record([string]$Type,[string]$Id,[string]$Name,$Properties,$Observations=@{}) {
        if ([string]::IsNullOrWhiteSpace($Id)) { throw 'A stable entity identity is unavailable.' }
        @{EntityType=$Type;Id=$Id;Name=$Name;Path=$Id;Properties=$Properties;Observations=$Observations}
    }
    function Registry-Identity([string]$Path) {
        return ($Path -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\').ToLowerInvariant()
    }
    function Xml-Map($Node) {
        $children=@($Node.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })
        $result=@{}
        foreach ($a in $Node.Attributes) { if ($a.Name -ne 'xmlns') { $result['@'+$a.Name]=[string]$a.Value } }
        if ($children.Count -eq 0) {
            if ($result.Count -eq 0) { return [string]$Node.InnerText }
            $result['#text']=[string]$Node.InnerText
            return $result
        }
        foreach ($group in ($children | Group-Object LocalName)) {
            $values=@($group.Group | ForEach-Object { Xml-Map $_ })
            if ($values.Count -eq 1) { $result[$group.Name]=$values[0] }
            else { $result[$group.Name]=$values }
        }
        return $result
    }
    function Parse-Gpo([string]$Text) {
        $settings=New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null
        $reader=[System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Text),$settings)
        $doc=New-Object System.Xml.XmlDocument
        $doc.XmlResolver=$null
        try { $doc.Load($reader) } finally { $reader.Dispose() }
        if ($doc.DocumentElement.LocalName -ne 'Rsop') { throw 'Invalid gpresult XML root.' }
        $computer=$doc.SelectSingleNode('/*[local-name()="Rsop"]/*[local-name()="ComputerResults"]')
        if ($null -eq $computer) { throw 'gpresult XML has no computer results.' }
        foreach ($node in $computer.SelectNodes('./*[local-name()="GPO"]')) {
            $idNode=$node.SelectSingleNode('./*[local-name()="Identifier"]/*[local-name()="Identifier"]')
            $pathNode=$node.SelectSingleNode('./*[local-name()="Path"]')
            $id=''
            if ($idNode) { $id=$idNode.InnerText }
            if ([string]::IsNullOrWhiteSpace($id) -and $pathNode) { $id=$pathNode.InnerText }
            # Local policy may have no GUID; the exact policy path is its identity.
            $properties=@{}
            foreach ($key in 'Name','Path','Enabled','FilterAllowed','AccessDenied','SOM') {
                $child=$node.SelectSingleNode('./*[local-name()="'+$key+'"]')
                if ($child) { $properties[$key]=$child.InnerText }
            }
            $domain=$node.SelectSingleNode('./*[local-name()="Identifier"]/*[local-name()="Domain"]')
            if ($domain) { $properties.Domain=$domain.InnerText }
            Record 'GroupPolicy' $id $properties.Name $properties
        }
    }
    if ($Unit -eq 'Target') {
        $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $product=$null
        try { $product=Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop } catch { }
        $uuid=[guid]::Empty
        $valid=[guid]::TryParse([string]$product.UUID,[ref]$uuid)
        if ($valid -and $uuid -ne [guid]::Empty -and $uuid.ToString() -ne 'ffffffff-ffff-ffff-ffff-ffffffffffff') {
            $id=$uuid.ToString();$source='SMBIOS.UUID'
        } else {
            $machine=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop
            if (-not [guid]::TryParse([string]$machine.MachineGuid,[ref]$uuid) -or $uuid -eq [guid]::Empty) { throw 'Trustworthy Windows target identity unavailable.' }
            $id=$uuid.ToString();$source='Registry.MachineGuid'
        }
        return @{Id=$id;Name=[string]$cs.Name;IdentitySource=$source;Version=[string]$os.Version;Build=[string]$os.BuildNumber;DomainRole=[int]$cs.DomainRole;PartOfDomain=[bool]$cs.PartOfDomain}
    }
    $entities=@()
    switch ($Unit) {
        'System.Configuration' {
            $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $p=Select-Fields $cs @('Name','Domain','DomainRole','PartOfDomain','Workgroup','TotalPhysicalMemory','NumberOfProcessors','NumberOfLogicalProcessors')
            $p.OS=Select-Fields $os @('Caption','Version','BuildNumber','OSArchitecture','InstallDate')
            $p.TimeZone=(Get-TimeZone -ErrorAction Stop).Id
            $entities=@(Record 'System' 'configuration' $cs.Name $p (Select-Fields $os @('LastBootUpTime')))
        }
        'Services.Configuration' {
            $entities=@(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | ForEach-Object {
                Record 'Service' ([string]$_.Name).ToLowerInvariant() $_.Name (Select-Fields $_ @('Name','DisplayName','Description','StartMode','DelayedAutoStart','StartName','PathName','ServiceType','DesktopInteract')) (Select-Fields $_ @('State','Status','AcceptPause','AcceptStop','ProcessId'))
            })
        }
        'Features.Installed' {
            if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { return @{Status='Unsupported';Entities=@();Reason='Get-WindowsFeature is unavailable; install ServerManager on the target.'} }
            $entities=@(Get-WindowsFeature -ErrorAction Stop | Where-Object Installed | ForEach-Object { Record 'Feature' $_.Name $_.Name (Select-Fields $_ @('Name','DisplayName','FeatureType','InstallState','Parent','Path')) })
        }
        'Network.Adapters' {
            $entities=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | ForEach-Object {
                $adapter=$_
                $p=Select-Fields $adapter @('Name','InterfaceDescription','MacAddress','MediaType','AdminStatus')
                $p.IPAddresses=@(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('IPAddress','PrefixLength','AddressFamily','PrefixOrigin','SuffixOrigin','SkipAsSource') } | Sort-Object { $_.IPAddress })
                $p.Dns=@(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | Sort-Object AddressFamily | ForEach-Object { @{AddressFamily=[string]$_.AddressFamily;ServerAddresses=@($_.ServerAddresses)} })
                $p.IPInterfaces=@(Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | Sort-Object AddressFamily | ForEach-Object { Select-Fields $_ @('AddressFamily','Dhcp','InterfaceMetric','AutomaticMetric','NlMtu','Forwarding') })
                $p.Routes=@(Get-NetRoute -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('DestinationPrefix','NextHop','RouteMetric','Protocol','Publish') } | Sort-Object { $_.DestinationPrefix },{ $_.NextHop })
                Record 'NetworkAdapter' ([string]$adapter.InterfaceGuid).ToLowerInvariant() $adapter.Name $p (Select-Fields $adapter @('Status','LinkSpeed','ifIndex'))
            })
        }
        'Network.Teams' {
            if (-not (Get-Command Get-NetLbfoTeam -ErrorAction SilentlyContinue)) { return @{Status='Unsupported';Entities=@();Reason='NIC teaming provider is unavailable.'} }
            $entities=@(Get-NetLbfoTeam -ErrorAction Stop | ForEach-Object { Record 'NetworkTeam' ([string]$_.Name).ToLowerInvariant() $_.Name @{Name=$_.Name;TeamingMode=[string]$_.TeamingMode;LoadBalancingAlgorithm=[string]$_.LoadBalancingAlgorithm;Members=@($_.Members | Sort-Object)} @{Status=[string]$_.Status} })
        }
        'Storage.Volumes' {
            $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $entities=@(Get-Volume -ErrorAction Stop | ForEach-Object {
                $id=[string]$_.UniqueId
                if ([string]::IsNullOrWhiteSpace($id)) { $id=[string]$_.Path }
                if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw 'Unusable or colliding volume identity.' }
                Record 'Volume' $id $id (Select-Fields $_ @('DriveLetter','Path','FileSystem','FileSystemLabel','Size','AllocationUnitSize','DedupMode')) (Select-Fields $_ @('SizeRemaining','HealthStatus','OperationalStatus'))
            })
        }
        'Storage.Disks' {
            $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $entities=@(Get-Disk -ErrorAction Stop | ForEach-Object {
                $id=[string]$_.UniqueId
                if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw 'Unusable or colliding disk identity.' }
                Record 'Disk' $id $id (Select-Fields $_ @('Number','FriendlyName','SerialNumber','UniqueIdFormat','Size','PartitionStyle','BusType','IsOffline','IsReadOnly','Location')) (Select-Fields $_ @('HealthStatus','OperationalStatus'))
            })
        }
        'Firewall.Profiles' {
            $entities=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | ForEach-Object { Record 'FirewallProfile' $_.Name $_.Name (Select-Fields $_ @('Enabled','DefaultInboundAction','DefaultOutboundAction','AllowInboundRules','AllowLocalFirewallRules','AllowLocalIPsecRules','AllowUnicastResponseToMulticast','NotifyOnListen','LogFileName','LogMaxSizeKilobytes','LogAllowed','LogBlocked','DisabledInterfaceAliases')) })
        }
        'Firewall.Rules' {
            $entities=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop | ForEach-Object {
                $rule=$_
                $p=Select-Fields $rule @('Name','DisplayName','Description','Enabled','Profile','Direction','Action','EdgeTraversalPolicy','LooseSourceMapping','LocalOnlyMapping','Owner','PolicyStoreSource','PolicyStoreSourceType')
                $p.Address=@($rule | Get-NetFirewallAddressFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('LocalAddress','RemoteAddress') })
                $p.Application=@($rule | Get-NetFirewallApplicationFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('Program','Package') })
                $p.Service=@($rule | Get-NetFirewallServiceFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('Service') })
                $p.Port=@($rule | Get-NetFirewallPortFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('Protocol','LocalPort','RemotePort','IcmpType','DynamicTarget') })
                $p.Interface=@($rule | Get-NetFirewallInterfaceFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('InterfaceAlias') })
                $p.InterfaceType=@($rule | Get-NetFirewallInterfaceTypeFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('InterfaceType') })
                $p.Security=@($rule | Get-NetFirewallSecurityFilter -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('Authentication','Encryption','OverrideBlockRules','LocalUser','RemoteUser','RemoteMachine') })
                foreach ($key in 'Address','Application','Service','Port','Interface','InterfaceType','Security') { if ($p[$key].Count -eq 0) { throw 'Required firewall filter was not returned.' } }
                Record 'FirewallRule' ([string]$rule.Name).ToLowerInvariant() $rule.DisplayName $p
            })
        }
        'Accounts.Users' {
            if ([int]$Options.DomainRole -ge 4) { return @{Status='NotApplicable';Entities=@();Reason='Win32_ComputerSystem.DomainRole identifies a domain controller without a local SAM.'} }
            $entities=@(Get-LocalUser -ErrorAction Stop | ForEach-Object { Record 'LocalUser' $_.SID.Value $_.Name (Select-Fields $_ @('Name','FullName','Description','Enabled','AccountExpires','UserMayChangePassword','PasswordRequired','PasswordNeverExpires','PrincipalSource')) (Select-Fields $_ @('LastLogon','PasswordLastSet','PasswordChangeableDate','PasswordExpires')) })
        }
        'Accounts.Groups' {
            if ([int]$Options.DomainRole -ge 4) { return @{Status='NotApplicable';Entities=@();Reason='Win32_ComputerSystem.DomainRole identifies a domain controller without a local SAM.'} }
            $entities=@(Get-LocalGroup -ErrorAction Stop | ForEach-Object {
                $group=$_
                $members=@(Get-LocalGroupMember -SID $group.SID -ErrorAction Stop | ForEach-Object { if (-not $_.SID.Value) { throw 'Member SID unavailable.' };[string]$_.SID.Value })
                Record 'LocalGroup' $group.SID.Value $group.Name @{Name=$group.Name;Description=$group.Description;Members=@($members | Sort-Object -Unique)}
            })
        }
        'Domain.Membership' {
            $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $entities=@(Record 'Domain' 'membership' 'Membership' (Select-Fields $cs @('PartOfDomain','Domain','Workgroup','DomainRole')))
        }
        'Domain.Trusts' {
            if (-not $Options.PartOfDomain) { return @{Status='NotApplicable';Entities=@();Reason='Win32_ComputerSystem.PartOfDomain is false.'} }
            if ([int]$Options.DomainRole -lt 4) { return @{Status='Unsupported';Entities=@();Reason='The Microsoft_DomainTrustStatus provider requires a domain controller; no empty trust list is inferred.'} }
            $trusts=@(Get-CimInstance -Namespace root\MicrosoftActiveDirectory -ClassName Microsoft_DomainTrustStatus -ErrorAction Stop | ForEach-Object { Select-Fields $_ @('TrustedDomain','TrustDirection','TrustType','TrustAttributes') })
            $entities=@(Record 'DomainTrusts' 'trusts' 'Trusts' @{Trusts=$trusts})
        }
        'ScheduledTasks.Tasks' {
            $entities=@(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                $task=$_;$path=[string]$task.TaskPath+[string]$task.TaskName
                [xml]$xml=Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
                $allowed=@($Options.TaskArgumentAllowList | ForEach-Object { ([string]$_).ToLowerInvariant() }) -ccontains $path.ToLowerInvariant()
                if (-not $allowed) { foreach ($arg in @($xml.SelectNodes('//*[local-name()="Arguments"]'))) { $null=$arg.ParentNode.RemoveChild($arg) } }
                $p=@{FullTaskPath=$path;ArgumentsExcluded=(-not $allowed);ArgumentCoverage='Arguments omitted unless exact full task path is allowlisted; omitted argument drift is not assessed.'}
                foreach ($key in 'Triggers','Principals','Settings') {
                    $node=$xml.SelectSingleNode('/*[local-name()="Task"]/*[local-name()="'+$key+'"]')
                    if ($node) { $p[$key]=Xml-Map $node } else { $p[$key]=@{} }
                }
                $actions=$xml.SelectSingleNode('/*[local-name()="Task"]/*[local-name()="Actions"]')
                $p.ActionContext=''
                $p.OrderedActions=@()
                if ($actions) {
                    $p.ActionContext=$actions.GetAttribute('Context')
                    $p.OrderedActions=@($actions.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] } | ForEach-Object { @{Type=$_.LocalName;Configuration=(Xml-Map $_)} })
                }
                $info=Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
                Record 'ScheduledTask' $path.ToLowerInvariant() $path $p (Select-Fields $info @('LastRunTime','NextRunTime','LastTaskResult','NumberOfMissedRuns'))
            })
        }
        'ParseGroupPolicy' { $entities=@(Parse-Gpo $Options.Xml) }
        'GroupPolicy.Applied' {
            if (-not (Get-Command gpresult.exe -ErrorAction SilentlyContinue)) { return @{Status='Unsupported';Entities=@();Reason='gpresult.exe is unavailable.'} }
            $temp=Join-Path ([IO.Path]::GetTempPath()) ('DriftDetect-'+[guid]::NewGuid().ToString('N')+'.xml')
            try {
                $null=& gpresult.exe /scope computer /x $temp /f 2>&1
                if ($LASTEXITCODE -ne 0) { throw 'gpresult returned an unsuccessful exit code.' }
                $entities=@(Parse-Gpo (Get-Content -LiteralPath $temp -Raw -ErrorAction Stop))
            } finally { if (Test-Path -LiteralPath $temp) { [IO.File]::Delete($temp) } }
        }
        'Registry.Values' {
            $entities=@(foreach ($path in @($Options.RegistryPaths)) {
                if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { Record 'Registry' (Registry-Identity $path) $path @{Exists=$false;Values=@{};ExcludedValueNames=@()};continue }
                $keys=@(Get-Item -LiteralPath $path -ErrorAction Stop)
                if ($Options.Recurse) { $keys+=@(Get-ChildItem -LiteralPath $path -Recurse -ErrorAction Stop) }
                foreach ($key in $keys) {
                    $values=@{};$excluded=@()
                    foreach ($name in $key.GetValueNames()) {
                        if ($name -in 'DefaultPassword','DefaultPin','AltDefaultPassword','AutoLogonPassword','Password','Secret','Credential','Credentials','PrivateKey','ClientSecret','AccessToken','RefreshToken','ApiKey') { $excluded+=$name;continue }
                        $value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        $kind=[string]$key.GetValueKind($name)
                        if ($value -is [byte[]]) { $value=@{Encoding='Base64';Data=[Convert]::ToBase64String($value)} }
                        $values[$name]=@{Kind=$kind;Value=$value}
                    }
                    Record 'Registry' (Registry-Identity $key.Name) $key.Name @{Exists=$true;Values=$values;ExcludedValueNames=@($excluded | Sort-Object)}
                }
            })
        }
        default { throw 'Unknown Windows collection unit.' }
    }
    return @{Status='Success';Entities=@($entities);Reason=''}
}

