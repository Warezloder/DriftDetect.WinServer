#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Server roles and features.
#>

class FeatureCollector : WSCollectorBase {
    FeatureCollector() : base('Feature') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        try {
            $features = $this.Invoke({
                Get-WindowsFeature | Where-Object {$_.Installed -eq $true} | ForEach-Object {
                    @{
                        Name = $_.Name
                        DisplayName = $_.DisplayName
                        FeatureType = $_.FeatureType.ToString()
                        Path = $_.Path
                        Depth = $_.Depth
                        Installed = $_.Installed
                    }
                }
            })

            foreach ($feature in $features) {
                $props = @{
                    Name = $feature.Name
                    DisplayName = $feature.DisplayName
                    FeatureType = $feature.FeatureType
                    Path = $feature.Path
                    Depth = $feature.Depth
                    Installed = $feature.Installed
                }

                $entity = [WSEntity]::new('Feature', $feature.Name, "Feature/$($feature.Name)", $props)
                $entities.Add($entity) | Out-Null
            }
        }
        catch {
            Write-Verbose "Failed to get Windows Features: $_"
        }

        return $entities.ToArray()
    }
}
