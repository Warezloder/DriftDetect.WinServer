#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for local user accounts and groups.
#>

class UserAccountCollector : WSCollectorBase {
    UserAccountCollector() : base('UserAccount') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Local Users
        $users = $this.Invoke({
            Get-LocalUser | ForEach-Object {
                @{
                    Name = $_.Name
                    SID = $_.SID.Value
                    Description = $_.Description
                    Enabled = $_.Enabled
                    PasswordRequired = $_.PasswordRequired
                    PasswordNeverExpires = $_.PasswordNeverExpires
                    UserMayChangePassword = $_.UserMayChangePassword
                    PasswordLastSet = $_.PasswordLastSet
                    LastLogon = $_.LastLogon
                }
            }
        })

        foreach ($user in $users) {
            $props = @{
                Name = $user.Name
                SID = $user.SID
                Description = $user.Description
                Enabled = $user.Enabled
                PasswordRequired = $user.PasswordRequired
                PasswordNeverExpires = $user.PasswordNeverExpires
                UserMayChangePassword = $user.UserMayChangePassword
                PasswordLastSet = $user.PasswordLastSet
                LastLogon = $user.LastLogon
            }

            $entity = [WSEntity]::new('UserAccount', $user.Name, "UserAccount/User/$($user.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        # Local Groups
        $groups = $this.Invoke({
            Get-LocalGroup | ForEach-Object {
                $groupName = $_.Name
                $members = Get-LocalGroupMember -Group $groupName -ErrorAction SilentlyContinue | 
                    ForEach-Object { $_.Name }
                @{
                    Name = $groupName
                    SID = $_.SID.Value
                    Description = $_.Description
                    Members = @($members)
                }
            }
        })

        foreach ($group in $groups) {
            $props = @{
                Name = $group.Name
                SID = $group.SID
                Description = $group.Description
                Members = $group.Members
            }

            $entity = [WSEntity]::new('UserAccount', "Group-$($group.Name)", "UserAccount/Group/$($group.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
