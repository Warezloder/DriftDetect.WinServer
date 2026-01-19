#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows Server storage configuration (disks, volumes, mount points).
#>

class StorageCollector : WSCollectorBase {
    StorageCollector() : base('Storage') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Physical Disks
        $disks = $this.Invoke({
            Get-Disk | ForEach-Object {
                @{
                    Number = $_.Number
                    FriendlyName = $_.FriendlyName
                    SerialNumber = $_.SerialNumber
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    PartitionStyle = $_.PartitionStyle.ToString()
                    OperationalStatus = $_.OperationalStatus.ToString()
                    HealthStatus = $_.HealthStatus.ToString()
                    BusType = $_.BusType.ToString()
                }
            }
        })

        foreach ($disk in $disks) {
            $props = @{
                Number = $disk.Number
                FriendlyName = $disk.FriendlyName
                SerialNumber = $disk.SerialNumber
                SizeGB = $disk.SizeGB
                PartitionStyle = $disk.PartitionStyle
                OperationalStatus = $disk.OperationalStatus
                HealthStatus = $disk.HealthStatus
                BusType = $disk.BusType
            }

            $entity = [WSEntity]::new('Storage', "Disk$($disk.Number)", "Storage/Disk/$($disk.Number)", $props)
            $entities.Add($entity) | Out-Null
        }

        # Volumes
        $volumes = $this.Invoke({
            Get-Volume | Where-Object {$_.DriveType -eq 'Fixed'} | ForEach-Object {
                @{
                    DriveLetter = $_.DriveLetter
                    FileSystemLabel = $_.FileSystemLabel
                    FileSystem = $_.FileSystem
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    SizeRemainingGB = [math]::Round($_.SizeRemaining / 1GB, 2)
                    HealthStatus = $_.HealthStatus.ToString()
                    OperationalStatus = $_.OperationalStatus.ToString()
                }
            }
        })

        foreach ($vol in $volumes) {
            $driveLetter = if ($vol.DriveLetter) { $vol.DriveLetter } else { 'NoLetter' }
            $props = @{
                DriveLetter = $vol.DriveLetter
                FileSystemLabel = $vol.FileSystemLabel
                FileSystem = $vol.FileSystem
                SizeGB = $vol.SizeGB
                SizeRemainingGB = $vol.SizeRemainingGB
                HealthStatus = $vol.HealthStatus
                OperationalStatus = $vol.OperationalStatus
            }

            $entity = [WSEntity]::new('Storage', "${driveLetter}:$($vol.FileSystemLabel)", "Storage/Volume/$driveLetter", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
