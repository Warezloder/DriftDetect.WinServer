#Requires -Version 7.0

<#
.SYNOPSIS
    Snapshot of Windows Server configuration at a point in time.
#>

class WSSnapshot {
    [string]$SnapshotId
    [datetime]$CapturedAt
    [string]$ComputerName
    [string]$OSVersion
    [string]$OSBuild
    [hashtable]$Entities
    [string]$SchemaVersion = '1.0'
    [hashtable]$Metadata

    WSSnapshot() {
        $this.SnapshotId = [guid]::NewGuid().ToString()
        $this.CapturedAt = [datetime]::UtcNow
        $this.Entities = @{}
        $this.Metadata = @{}
    }

    # Add entities from a collector
    [void] AddEntities([WSEntity[]]$entities) {
        foreach ($e in $entities) {
            if (-not $this.Entities.ContainsKey($e.EntityType)) {
                $this.Entities[$e.EntityType] = [System.Collections.ArrayList]::new()
            }
            $this.Entities[$e.EntityType].Add($e) | Out-Null
        }
    }

    # Get entity by type and path
    [WSEntity] GetEntity([string]$type, [string]$path) {
        if (-not $this.Entities.ContainsKey($type)) {
            return $null
        }
        return $this.Entities[$type] | Where-Object { $_.Path -eq $path } | Select-Object -First 1
    }

    # Get all entities of a type
    [WSEntity[]] GetEntitiesByType([string]$type) {
        if (-not $this.Entities.ContainsKey($type)) {
            return @()
        }
        return $this.Entities[$type]
    }

    # Export to file
    [void] Export([string]$path) {
        $export = @{
            SnapshotId = $this.SnapshotId
            CapturedAt = $this.CapturedAt.ToString('o')
            ComputerName = $this.ComputerName
            OSVersion = $this.OSVersion
            OSBuild = $this.OSBuild
            SchemaVersion = $this.SchemaVersion
            Metadata = $this.Metadata
            Entities = @{}
        }

        foreach ($type in $this.Entities.Keys) {
            $export.Entities[$type] = @($this.Entities[$type] | ForEach-Object {
                @{
                    EntityType = $_.EntityType
                    Name = $_.Name
                    Path = $_.Path
                    Hash = $_.Hash
                    CapturedAt = $_.CapturedAt.ToString('o')
                    Properties = $_.Properties
                }
            })
        }

        $export | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding UTF8
    }

    # Helper method to convert PSCustomObject to Hashtable
    static [hashtable] ConvertToHashtable([object]$obj) {
        if ($null -eq $obj) {
            return @{}
        }
        
        if ($obj -is [hashtable]) {
            return $obj
        }
        
        $hash = @{}
        if ($obj -is [PSCustomObject]) {
            foreach ($prop in $obj.PSObject.Properties) {
                $value = $prop.Value
                # Recursively convert nested PSCustomObjects
                if ($value -is [PSCustomObject]) {
                    $hash[$prop.Name] = [WSSnapshot]::ConvertToHashtable($value)
                }
                else {
                    $hash[$prop.Name] = $value
                }
            }
        }
        return $hash
    }

    # Import from file
    static [WSSnapshot] Import([string]$path) {
        $data = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 20

        $snapshot = [WSSnapshot]::new()
        $snapshot.SnapshotId = $data.SnapshotId
        $snapshot.CapturedAt = [datetime]::Parse($data.CapturedAt)
        $snapshot.ComputerName = $data.ComputerName
        $snapshot.OSVersion = $data.OSVersion
        $snapshot.OSBuild = $data.OSBuild
        $snapshot.SchemaVersion = $data.SchemaVersion
        
        # Convert Metadata from PSCustomObject to Hashtable
        $snapshot.Metadata = [WSSnapshot]::ConvertToHashtable($data.Metadata)

        foreach ($type in $data.Entities.PSObject.Properties.Name) {
            $snapshot.Entities[$type] = [System.Collections.ArrayList]::new()
            foreach ($e in $data.Entities.$type) {
                # Convert Properties from PSCustomObject to Hashtable
                $props = [WSSnapshot]::ConvertToHashtable($e.Properties)
                $entity = [WSEntity]::new($e.EntityType, $e.Name, $e.Path, $props)
                $entity.Hash = $e.Hash
                $entity.CapturedAt = [datetime]::Parse($e.CapturedAt)
                $snapshot.Entities[$type].Add($entity) | Out-Null
            }
        }

        return $snapshot
    }
}
