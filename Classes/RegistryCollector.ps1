#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for important Windows Registry settings.
#>

class RegistryCollector : WSCollectorBase {
    [string[]]$ImportantPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'
        'HKLM:\SOFTWARE\Policies\Microsoft'
        'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
        'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    )

    RegistryCollector() : base('Registry') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Collect all registry paths in one remote call
        $allRegData = $this.Invoke({
            param($paths)
            
            $results = @()
            foreach ($path in $paths) {
                try {
                    if (Test-Path $path) {
                        $item = Get-Item -Path $path -ErrorAction Stop
                        
                        $result = @{
                            Path = $path
                            Exists = $true
                            Values = @{}
                        }
                        
                        foreach ($valueName in $item.Property) {
                            try {
                                $value = $item.GetValue($valueName)
                                $result.Values[$valueName] = $value
                            }
                            catch {
                                $result.Values[$valueName] = "Error reading value"
                            }
                        }
                        
                        $results += $result
                    }
                }
                catch {
                    # Skip paths that fail
                }
            }
            
            return $results
        }.GetNewClosure()).Invoke(@(,$this.ImportantPaths))

        foreach ($regData in $allRegData) {
            if ($regData.Exists) {
                $props = @{
                    Path = $regData.Path
                    Exists = $regData.Exists
                    ValueCount = $regData.Values.Count
                    Values = $regData.Values
                }

                $pathName = $regData.Path -replace '[:\\]', '_'
                $entity = [WSEntity]::new('Registry', $pathName, "Registry/$pathName", $props)
                $entities.Add($entity) | Out-Null
            }
        }

        return $entities.ToArray()
    }

    # Method to add custom registry paths
    [void] AddRegistryPath([string]$path) {
        $this.ImportantPaths += $path
    }
}
