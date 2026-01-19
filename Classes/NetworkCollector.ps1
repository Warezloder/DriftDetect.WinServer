#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Server network configuration (adapters, IP, routes, teaming).
#>

class NetworkCollector : WSCollectorBase {
    NetworkCollector() : base('Network') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Network Adapters
        $adapters = $this.Invoke({
            Get-NetAdapter | ForEach-Object {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
                @{
                    Name = $_.Name
                    InterfaceDescription = $_.InterfaceDescription
                    Status = $_.Status.ToString()
                    MacAddress = $_.MacAddress
                    LinkSpeed = $_.LinkSpeed
                    MediaType = $_.MediaType
                    IPAddresses = @($ipConfig | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" })
                }
            }
        })

        foreach ($adapter in $adapters) {
            $props = @{
                Name = $adapter.Name
                InterfaceDescription = $adapter.InterfaceDescription
                Status = $adapter.Status
                MacAddress = $adapter.MacAddress
                LinkSpeed = $adapter.LinkSpeed
                MediaType = $adapter.MediaType
                IPAddresses = $adapter.IPAddresses
            }

            $entity = [WSEntity]::new('Network', $adapter.Name, "Network/Adapter/$($adapter.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        # NIC Teaming (if configured)
        try {
            $teams = $this.Invoke({
                Get-NetLbfoTeam -ErrorAction SilentlyContinue | ForEach-Object {
                    @{
                        Name = $_.Name
                        TeamingMode = $_.TeamingMode.ToString()
                        LoadBalancingAlgorithm = $_.LoadBalancingAlgorithm.ToString()
                        Members = @($_.Members)
                        Status = $_.Status.ToString()
                    }
                }
            })

            foreach ($team in $teams) {
                $props = @{
                    Name = $team.Name
                    TeamingMode = $team.TeamingMode
                    LoadBalancingAlgorithm = $team.LoadBalancingAlgorithm
                    Members = $team.Members
                    Status = $team.Status
                }

                $entity = [WSEntity]::new('Network', $team.Name, "Network/Team/$($team.Name)", $props)
                $entities.Add($entity) | Out-Null
            }
        }
        catch {
            Write-Verbose "NIC Teaming not available or configured: $_"
        }

        return $entities.ToArray()
    }
}
