#Requires -Version 7.0

function Get-WSSnapshot {
    <#
    .SYNOPSIS
        Loads a Windows Server snapshot from a JSON file.
    
    .DESCRIPTION
        Imports a previously captured Windows Server snapshot from JSON format. Returns a
        WSSnapshot object that can be used for comparison or inspection.
    
    .PARAMETER Path
        Path to the snapshot JSON file.
    
    .EXAMPLE
        PS> $snapshot = Get-WSSnapshot -Path "C:\Snapshots\baseline.json"
        PS> $snapshot.ComputerName
        Loads a snapshot and displays the computer name.
    
    .EXAMPLE
        PS> $snap = Get-WSSnapshot -Path baseline.json
        PS> $snap.Entities.Keys
        Shows entity types captured in the snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Test-Path $_ })]
        [Alias('FilePath', 'FullName')]
        [string]$Path
    )

    process {
        try {
            Write-Verbose "Loading snapshot from $Path"
            $snapshot = [WSSnapshot]::Import($Path)
            
            Write-Verbose "Snapshot loaded:"
            Write-Verbose "  - Snapshot ID: $($snapshot.SnapshotId)"
            Write-Verbose "  - Computer: $($snapshot.ComputerName)"
            Write-Verbose "  - OS Version: $($snapshot.OSVersion)"
            Write-Verbose "  - OS Build: $($snapshot.OSBuild)"
            Write-Verbose "  - Captured: $($snapshot.CapturedAt)"
            Write-Verbose "  - Entity types: $($snapshot.Entities.Keys -join ', ')"

            return $snapshot
        }
        catch {
            Write-Error "Failed to load snapshot: $_"
            throw
        }
    }
}
