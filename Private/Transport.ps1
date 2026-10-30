# Client-side transport. ArgumentList is deliberately splatted only once: nested
# arrays remain single positional arguments both locally and over remoting.
function Invoke-WSCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [object[]]$ArgumentList=@(), $Session)
    if ($null -ne $Session) {
        Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    } else {
        & $ScriptBlock @ArgumentList
    }
}

function Invoke-WSQuery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Unit, [System.Collections.IDictionary]$Options=@{}, $Session)
    Invoke-WSCommand -Session $Session -ScriptBlock $script:WSProviderQuery -ArgumentList @($Unit,$Options)
}

function ConvertFrom-WSGroupPolicyXml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Xml,[int]$ExitCode=0)
    if ($ExitCode -ne 0) { throw 'gpresult returned an unsuccessful exit code.' }
    $envelope=Invoke-WSQuery -Unit 'ParseGroupPolicy' -Options @{Xml=$Xml}
    return ,@($envelope.Entities)
}

function ConvertTo-WSMap {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) { return $Value }
    $map=@{}
    foreach ($p in $Value.PSObject.Properties) {
        if ($p.Name -notin 'PSComputerName','RunspaceId','PSShowComputerName') { $map[$p.Name]=$p.Value }
    }
    return $map
}

function Get-WSUnitDefinitions {
    @(
        @{Id='System.Configuration';Option='';Scope=@{}}
        @{Id='Services.Configuration';Option='';Scope=@{IncludeDisabled=$true}}
        @{Id='Features.Installed';Option='';Scope=@{InstalledOnly=$true}}
        @{Id='Network.Adapters';Option='';Scope=@{DnsOrder='Ordered';Routes='All'}}
        @{Id='Network.Teams';Option='';Scope=@{}}
        @{Id='Storage.Volumes';Option='';Scope=@{}}
        @{Id='Storage.Disks';Option='';Scope=@{}}
        @{Id='Firewall.Profiles';Option='';Scope=@{PolicyStore='ActiveStore'}}
        @{Id='Firewall.Rules';Option='';Scope=@{PolicyStore='ActiveStore';IncludeDisabled=$true}}
        @{Id='Accounts.Users';Option='';Scope=@{PasswordExpirationPolicy='Win32_UserAccount.PasswordExpires'}}
        @{Id='Accounts.Groups';Option='';Scope=@{Membership='SID'}}
        @{Id='Domain.Membership';Option='';Scope=@{}}
        @{Id='Domain.Trusts';Option='';Scope=@{Provider='Microsoft_DomainTrustStatus'}}
        @{Id='ScheduledTasks.Tasks';Option='IncludeScheduledTasks';Scope=@{IncludeDisabled=$true;ArgumentPolicy='ExactFullPathAllowList'}}
        @{Id='GroupPolicy.Applied';Option='IncludeGroupPolicy';Scope=@{Coverage='Computer GPO identity and application information only'}}
        @{Id='Registry.Values';Option='IncludeRegistry';Scope=@{Recurse=$true;ExcludedValueNames=@('DefaultPassword','DefaultPin','AltDefaultPassword','AutoLogonPassword','Password','Secret','Credential','Credentials','PrivateKey','ClientSecret','AccessToken','RefreshToken','ApiKey');Exclusions=@('Known credential-bearing registry values are excluded by exact value names; their drift is not assessed.')}}
    )
}

function Get-WSRegistryPaths {
    @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'
        'HKLM:\SOFTWARE\Policies\Microsoft'
        'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
        'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    )
}
