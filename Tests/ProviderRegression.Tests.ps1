BeforeAll {
    . (Join-Path $PSScriptRoot '../Private/Transport.ps1')
    . (Join-Path $PSScriptRoot '../Collectors/Windows.ps1')
    function Get-LocalUser { [CmdletBinding()]param() }
    function Get-CimInstance { [CmdletBinding()]param($ClassName,$Filter) }
    function Get-NetAdapter { [CmdletBinding()]param([switch]$IncludeHidden) }
    function Get-NetIPAddress { [CmdletBinding()]param($InterfaceIndex) }
    function Get-DnsClientServerAddress { [CmdletBinding()]param($InterfaceIndex) }
    function Get-NetIPInterface { [CmdletBinding()]param($InterfaceIndex) }
    function Get-NetRoute { [CmdletBinding()]param($InterfaceIndex) }
}
Describe 'Local account expiration policy regression' {
    BeforeEach {
        # Real LocalUser exposes an expiry timestamp, not a PasswordNeverExpires flag.
        Mock Get-LocalUser { [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-21-1-1001'};Name='fixture';Enabled=$true;PasswordExpires=[datetime]'2026-12-01T00:00:00Z'} }
        Mock Get-CimInstance {
            @([pscustomobject]@{SID='S-1-5-21-1-999';PasswordExpires=$false},[pscustomobject]@{SID='S-1-5-21-1-1001';PasswordExpires=$true})
        }
    }
    It 'joins the boolean policy by SID and retains the timestamp as observation' {
        $result=Invoke-WSQuery -Unit Accounts.Users -Options @{DomainRole=3}
        $result.Entities[0].Properties.PasswordNeverExpires | Should -BeOfType bool
        $result.Entities[0].Properties.PasswordNeverExpires | Should -BeFalse
        $result.Entities[0].Observations.PasswordExpires | Should -Not -BeNullOrEmpty
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_UserAccount' -and $Filter -eq 'LocalAccount=True' }
    }
    It 'captures the never-expires flag when the timestamp is null' {
        Mock Get-LocalUser { [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-21-1-1001'};Name='fixture';PasswordExpires=$null} }
        Mock Get-CimInstance { [pscustomobject]@{SID='S-1-5-21-1-1001';PasswordExpires=$false} }
        $result=Invoke-WSQuery -Unit Accounts.Users -Options @{DomainRole=3}
        $result.Entities[0].Properties.PasswordNeverExpires | Should -BeTrue
    }
    It 'fails instead of inventing a policy when the query fails' {
        Mock Get-CimInstance { throw 'Synthetic access failure' }
        {Invoke-WSQuery -Unit Accounts.Users -Options @{DomainRole=3}} | Should -Throw '*access failure*'
    }
    It 'fails on a missing or non-boolean policy for the matched SID' -ForEach @(@{Policy='Missing'},@{Policy='Null'},@{Policy='String'}) {
        Mock Get-CimInstance {
            if($Policy -eq 'Missing'){return @()}
            [pscustomobject]@{SID='S-1-5-21-1-1001';PasswordExpires=$(if($Policy -eq 'Null'){$null}else{'false'})}
        }
        {Invoke-WSQuery -Unit Accounts.Users -Options @{DomainRole=3}} | Should -Throw '*expiration policy*'
    }
    It 'does not query local account policies on domain controllers' {
        (Invoke-WSQuery -Unit Accounts.Users -Options @{DomainRole=5}).Status | Should -Be NotApplicable
        Should -Invoke Get-CimInstance -Times 0
    }
}
Describe 'Network inventories joined by interface index' {
    BeforeEach {
        Mock Get-NetAdapter {
            @([pscustomobject]@{Name='LAN';InterfaceGuid='bound-guid';ifIndex=10},[pscustomobject]@{Name='Hidden';InterfaceGuid='hidden-guid';ifIndex=20})
        }
        Mock Get-NetIPAddress {
            if($InterfaceIndex -eq 20){throw 'No matching interface'}
            [pscustomobject]@{InterfaceIndex=10;IPAddress='192.0.2.10';PrefixLength=24;AddressFamily='IPv4'}
        }
        Mock Get-DnsClientServerAddress {
            if($InterfaceIndex -eq 20){throw 'No matching interface'}
            [pscustomobject]@{InterfaceIndex=10;AddressFamily=2;ServerAddresses=@('192.0.2.1','192.0.2.2')}
        }
        Mock Get-NetIPInterface {
            if($InterfaceIndex -eq 20){throw 'No matching interface'}
            [pscustomobject]@{InterfaceIndex=10;AddressFamily='IPv4';Dhcp='Disabled'}
        }
        Mock Get-NetRoute {
            if($InterfaceIndex -eq 20){throw 'No matching interface'}
            [pscustomobject]@{InterfaceIndex=10;DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.1'}
        }
    }
    It 'keeps an unbound hidden adapter without losing the bound adapter' {
        $result=Invoke-WSQuery -Unit Network.Adapters -Options @{}
        $result.Status | Should -Be Success
        $result.Entities.Count | Should -Be 2
        $bound=$result.Entities | Where-Object Id -eq 'bound-guid'
        $hidden=$result.Entities | Where-Object Id -eq 'hidden-guid'
        $bound.Properties.IPAddresses[0].IPAddress | Should -Be '192.0.2.10'
        $bound.Properties.Dns[0].ServerAddresses -join ',' | Should -Be '192.0.2.1,192.0.2.2'
        foreach($field in 'IPAddresses','Dns','IPInterfaces','Routes'){$hidden.Properties[$field].Count | Should -Be 0}
        foreach($query in 'Get-NetIPAddress','Get-DnsClientServerAddress','Get-NetIPInterface','Get-NetRoute'){
            Should -Invoke $query -Times 1 -Exactly -ParameterFilter { $null -eq $InterfaceIndex }
        }
    }
    It 'preserves genuine inventory query errors' -ForEach @(
        @{Query='Get-NetIPAddress'},@{Query='Get-DnsClientServerAddress'},@{Query='Get-NetIPInterface'},@{Query='Get-NetRoute'}
    ) {
        Mock $Query { throw 'Synthetic provider failure' }
        {Invoke-WSQuery -Unit Network.Adapters -Options @{}} | Should -Throw '*provider failure*'
    }
    It 'treats successful empty inventories as empty configuration' {
        foreach($query in 'Get-NetIPAddress','Get-DnsClientServerAddress','Get-NetIPInterface','Get-NetRoute'){Mock $query { @() }}
        $result=Invoke-WSQuery -Unit Network.Adapters -Options @{}
        $result.Status | Should -Be Success
        $result.Entities.Count | Should -Be 2
        foreach($entity in $result.Entities){$entity.Properties.IPAddresses.Count | Should -Be 0}
    }
}
