#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Firewall rules and profiles.
#>

class FirewallCollector : WSCollectorBase {
    FirewallCollector() : base('Firewall') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Firewall Profiles
        $profiles = $this.Invoke({
            Get-NetFirewallProfile | ForEach-Object {
                @{
                    Name = $_.Name
                    Enabled = $_.Enabled
                    DefaultInboundAction = $_.DefaultInboundAction.ToString()
                    DefaultOutboundAction = $_.DefaultOutboundAction.ToString()
                    AllowInboundRules = $_.AllowInboundRules.ToString()
                    AllowLocalFirewallRules = $_.AllowLocalFirewallRules.ToString()
                    AllowLocalIPsecRules = $_.AllowLocalIPsecRules.ToString()
                    NotifyOnListen = $_.NotifyOnListen
                    LogFileName = $_.LogFileName
                }
            }
        })

        foreach ($profile in $profiles) {
            $props = @{
                Name = $profile.Name
                Enabled = $profile.Enabled
                DefaultInboundAction = $profile.DefaultInboundAction
                DefaultOutboundAction = $profile.DefaultOutboundAction
                AllowInboundRules = $profile.AllowInboundRules
                AllowLocalFirewallRules = $profile.AllowLocalFirewallRules
                AllowLocalIPsecRules = $profile.AllowLocalIPsecRules
                NotifyOnListen = $profile.NotifyOnListen
                LogFileName = $profile.LogFileName
            }

            $entity = [WSEntity]::new('Firewall', "Profile-$($profile.Name)", "Firewall/Profile/$($profile.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        # Firewall Rules (enabled only to reduce noise)
        $rules = $this.Invoke({
            Get-NetFirewallRule | Where-Object {$_.Enabled -eq $true} | ForEach-Object {
                @{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    Enabled = $_.Enabled
                    Direction = $_.Direction.ToString()
                    Action = $_.Action.ToString()
                    Profile = $_.Profile.ToString()
                    LocalPort = ($_ | Get-NetFirewallPortFilter).LocalPort
                    RemotePort = ($_ | Get-NetFirewallPortFilter).RemotePort
                    Protocol = ($_ | Get-NetFirewallPortFilter).Protocol
                }
            }
        })

        foreach ($rule in $rules) {
            $props = @{
                Name = $rule.Name
                DisplayName = $rule.DisplayName
                Enabled = $rule.Enabled
                Direction = $rule.Direction
                Action = $rule.Action
                Profile = $rule.Profile
                LocalPort = $rule.LocalPort
                RemotePort = $rule.RemotePort
                Protocol = $rule.Protocol
            }

            $entity = [WSEntity]::new('Firewall', $rule.Name, "Firewall/Rule/$($rule.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
