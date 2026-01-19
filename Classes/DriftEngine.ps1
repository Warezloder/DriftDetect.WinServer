#Requires -Version 7.0

<#
.SYNOPSIS
    Engine for comparing Windows Server snapshots and detecting drift.
#>

class WSDriftEngine {
    [hashtable]$SeverityRules
    
    WSDriftEngine() {
        $this.SeverityRules = @{}
    }

    # Load severity rules from config
    [void] LoadSeverityRules([string]$configPath) {
        if (Test-Path $configPath) {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            foreach ($rule in $config.Rules) {
                $key = "$($rule.EntityType):$($rule.Property)"
                $this.SeverityRules[$key] = $rule.Severity
            }
        }
    }

    # Determine severity of a change
    [string] GetSeverity([string]$entityType, [string]$property) {
        # Exact match
        $key = "${entityType}:${property}"
        if ($this.SeverityRules.ContainsKey($key)) {
            return $this.SeverityRules[$key]
        }

        # Wildcard entity match
        $key = "*:${property}"
        if ($this.SeverityRules.ContainsKey($key)) {
            return $this.SeverityRules[$key]
        }

        # Wildcard property match
        $key = "${entityType}:*"
        if ($this.SeverityRules.ContainsKey($key)) {
            return $this.SeverityRules[$key]
        }

        # Default
        return 'Low'
    }

    # Compare two snapshots and return drift results
    [PSCustomObject] Compare([WSSnapshot]$baseline, [WSSnapshot]$current) {
        $changes = [System.Collections.ArrayList]::new()
        $newEntities = [System.Collections.ArrayList]::new()
        $deletedEntities = [System.Collections.ArrayList]::new()
        
        # Get all entity types from both snapshots
        $allTypes = ($baseline.Entities.Keys + $current.Entities.Keys) | Sort-Object -Unique

        foreach ($type in $allTypes) {
            $baselineEntities = $baseline.GetEntitiesByType($type)
            $currentEntities = $current.GetEntitiesByType($type)

            # Index by Path for faster lookup
            $baselineMap = @{}
            foreach ($e in $baselineEntities) {
                $baselineMap[$e.Path] = $e
            }

            $currentMap = @{}
            foreach ($e in $currentEntities) {
                $currentMap[$e.Path] = $e
            }

            # Find deleted entities
            foreach ($path in $baselineMap.Keys) {
                if (-not $currentMap.ContainsKey($path)) {
                    $e = $baselineMap[$path]
                    $deletedEntities.Add([PSCustomObject]@{
                        EntityType = $e.EntityType
                        EntityName = $e.Name
                        EntityPath = $e.Path
                        Hash = $e.Hash
                    }) | Out-Null
                }
            }

            # Find new entities
            foreach ($path in $currentMap.Keys) {
                if (-not $baselineMap.ContainsKey($path)) {
                    $e = $currentMap[$path]
                    $newEntities.Add([PSCustomObject]@{
                        EntityType = $e.EntityType
                        EntityName = $e.Name
                        EntityPath = $e.Path
                        Hash = $e.Hash
                    }) | Out-Null
                }
            }

            # Compare existing entities
            foreach ($path in $currentMap.Keys) {
                if ($baselineMap.ContainsKey($path)) {
                    $baseEntity = $baselineMap[$path]
                    $currEntity = $currentMap[$path]
                    
                    # Quick hash comparison first
                    if ($baseEntity.Hash -ne $currEntity.Hash) {
                        $drifts = $baseEntity.CompareTo($currEntity)
                        foreach ($drift in $drifts) {
                            # Add severity
                            $drift | Add-Member -NotePropertyName 'Severity' -NotePropertyValue ($this.GetSeverity($drift.EntityType, $drift.Property))
                            $changes.Add($drift) | Out-Null
                        }
                    }
                }
            }
        }

        # Build result object
        $result = [PSCustomObject]@{
            BaselineSnapshot = $baseline.SnapshotId
            CurrentSnapshot = $current.SnapshotId
            BaselineCapturedAt = $baseline.CapturedAt
            CurrentCapturedAt = $current.CapturedAt
            ComputerName = $current.ComputerName
            Changes = $changes.ToArray()
            NewEntities = $newEntities.ToArray()
            DeletedEntities = $deletedEntities.ToArray()
            TotalChanges = $changes.Count
            TotalNew = $newEntities.Count
            TotalDeleted = $deletedEntities.Count
            SeveritySummary = @{
                Critical = ($changes | Where-Object Severity -eq 'Critical').Count
                High = ($changes | Where-Object Severity -eq 'High').Count
                Medium = ($changes | Where-Object Severity -eq 'Medium').Count
                Low = ($changes | Where-Object Severity -eq 'Low').Count
            }
        }

        return $result
    }
}
