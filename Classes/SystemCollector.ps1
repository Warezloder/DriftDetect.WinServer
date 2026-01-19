#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Server system configuration (hostname, domain, OS, time, DNS, etc.).
#>

class SystemCollector : WSCollectorBase {
    SystemCollector() : base('System') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        $props = $this.Invoke({
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            $tz = Get-TimeZone
            $dns = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.ServerAddresses.Count -gt 0}
            
            @{
                ComputerName = $cs.Name
                Domain = $cs.Domain
                DomainRole = switch ($cs.DomainRole) {
                    0 { 'Standalone Workstation' }
                    1 { 'Member Workstation' }
                    2 { 'Standalone Server' }
                    3 { 'Member Server' }
                    4 { 'Backup Domain Controller' }
                    5 { 'Primary Domain Controller' }
                }
                PartOfDomain = $cs.PartOfDomain
                Workgroup = $cs.Workgroup
                OSName = $os.Caption
                OSVersion = $os.Version
                OSBuild = $os.BuildNumber
                OSArchitecture = $os.OSArchitecture
                InstallDate = $os.InstallDate
                LastBootUpTime = $os.LastBootUpTime
                TimeZone = $tz.Id
                TimeZoneDisplayName = $tz.DisplayName
                DNSServers = @($dns | ForEach-Object { 
                    "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" 
                })
                TotalPhysicalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                NumberOfProcessors = $cs.NumberOfProcessors
                NumberOfLogicalProcessors = $cs.NumberOfLogicalProcessors
            }
        })

        $entity = [WSEntity]::new('System', $props.ComputerName, 'System', $props)
        $entities.Add($entity) | Out-Null

        return $entities.ToArray()
    }
}
