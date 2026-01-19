#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Server services and their startup configurations.
#>

class ServiceCollector : WSCollectorBase {
    ServiceCollector() : base('Service') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        $services = $this.Invoke({
            Get-Service | Where-Object {$_.StartType -ne 'Disabled' -or $_.Status -eq 'Running'} | ForEach-Object {
                @{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    Status = $_.Status.ToString()
                    StartType = $_.StartType.ToString()
                    ServiceType = $_.ServiceType.ToString()
                    CanStop = $_.CanStop
                    CanPauseAndContinue = $_.CanPauseAndContinue
                }
            }
        })

        foreach ($svc in $services) {
            $props = @{
                Name = $svc.Name
                DisplayName = $svc.DisplayName
                Status = $svc.Status
                StartType = $svc.StartType
                ServiceType = $svc.ServiceType
                CanStop = $svc.CanStop
                CanPauseAndContinue = $svc.CanPauseAndContinue
            }

            $entity = [WSEntity]::new('Service', $svc.Name, "Service/$($svc.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
