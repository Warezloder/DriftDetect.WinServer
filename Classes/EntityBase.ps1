#Requires -Version 7.0

<#
.SYNOPSIS
    Base class for all Windows Server configuration entities tracked for drift detection.
#>

class WSEntity {
    [string]$EntityType
    [string]$Name
    [string]$Path
    [hashtable]$Properties
    [string]$Hash
    [datetime]$CapturedAt

    WSEntity([string]$type, [string]$name, [string]$path, [hashtable]$props) {
        $this.EntityType = $type
        $this.Name = $name
        $this.Path = $path
        $this.Properties = $props
        $this.CapturedAt = [datetime]::UtcNow
        $this.Hash = $this.ComputeHash()
    }

    # Compute SHA256 hash of the entity's configuration
    [string] ComputeHash() {
        $json = $this.Properties | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($bytes)
        return [System.BitConverter]::ToString($hashBytes) -replace '-'
    }

    # Compare this entity to another, returning drift items
    [object[]] CompareTo([WSEntity]$other) {
        if ($this.Hash -eq $other.Hash) {
            return @() # No changes
        }

        $drifts = [System.Collections.ArrayList]::new()
        $allKeys = ($this.Properties.Keys + $other.Properties.Keys) | Sort-Object -Unique

        foreach ($key in $allKeys) {
            $oldVal = $this.Properties[$key]
            $newVal = $other.Properties[$key]

            if ($null -eq $oldVal -and $null -ne $newVal) {
                $drifts.Add([PSCustomObject]@{
                    EntityType = $this.EntityType
                    EntityName = $this.Name
                    EntityPath = $this.Path
                    Property = $key
                    ChangeType = 'Added'
                    OldValue = $null
                    NewValue = $newVal
                    OldHash = $this.Hash
                    NewHash = $other.Hash
                }) | Out-Null
            }
            elseif ($null -ne $oldVal -and $null -eq $newVal) {
                $drifts.Add([PSCustomObject]@{
                    EntityType = $this.EntityType
                    EntityName = $this.Name
                    EntityPath = $this.Path
                    Property = $key
                    ChangeType = 'Removed'
                    OldValue = $oldVal
                    NewValue = $null
                    OldHash = $this.Hash
                    NewHash = $other.Hash
                }) | Out-Null
            }
            elseif ($oldVal -is [array] -and $newVal -is [array]) {
                # Array comparison
                $oldSorted = ($oldVal | Sort-Object) -join ','
                $newSorted = ($newVal | Sort-Object) -join ','
                if ($oldSorted -ne $newSorted) {
                    $drifts.Add([PSCustomObject]@{
                        EntityType = $this.EntityType
                        EntityName = $this.Name
                        EntityPath = $this.Path
                        Property = $key
                        ChangeType = 'Modified'
                        OldValue = $oldVal -join ', '
                        NewValue = $newVal -join ', '
                        OldHash = $this.Hash
                        NewHash = $other.Hash
                    }) | Out-Null
                }
            }
            elseif ($oldVal -ne $newVal) {
                $drifts.Add([PSCustomObject]@{
                    EntityType = $this.EntityType
                    EntityName = $this.Name
                    EntityPath = $this.Path
                    Property = $key
                    ChangeType = 'Modified'
                    OldValue = $oldVal
                    NewValue = $newVal
                    OldHash = $this.Hash
                    NewHash = $other.Hash
                }) | Out-Null
            }
        }

        return $drifts.ToArray()
    }
}
