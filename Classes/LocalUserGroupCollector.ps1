#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for local users and groups.
#>

class LocalUserGroupCollector : WSCollectorBase {
    LocalUserGroupCollector() : base('LocalAccount') {}

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
                    Enabled = $_.Enabled
                    PasswordRequired = $_.PasswordRequired
                    PasswordChangeableDate = $_.PasswordChangeableDate
                    PasswordExpires = $_.PasswordExpires
                    UserMayChangePassword = $_.UserMayChangePassword
                    PasswordLastSet = $_.PasswordLastSet
                    LastLogon = $_.LastLogon
                    Description = $_.Description
                }
            }
        })

        foreach ($user in $users) {
            $props = @{
                Name = $user.Name
                SID = $user.SID
                Enabled = $user.Enabled
                PasswordRequired = $user.PasswordRequired
                PasswordChangeableDate = $user.PasswordChangeableDate
                PasswordExpires = $user.PasswordExpires
                UserMayChangePassword = $user.UserMayChangePassword
                PasswordLastSet = $user.PasswordLastSet
                LastLogon = $user.LastLogon
                Description = $user.Description
            }

            $entity = [WSEntity]::new('LocalAccount', "User-$($user.Name)", "LocalAccount/User/$($user.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        # Local Groups
        $groups = $this.Invoke({
            Get-LocalGroup | ForEach-Object {
                $members = Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
                @{
                    Name = $_.Name
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

            $entity = [WSEntity]::new('LocalAccount', "Group-$($group.Name)", "LocalAccount/Group/$($group.Name)", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
