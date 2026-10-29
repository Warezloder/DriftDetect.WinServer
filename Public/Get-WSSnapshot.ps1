function Get-WSSnapshot {
    <# .SYNOPSIS
    Loads Windows snapshot JSON for offline inspection, comparison or reporting.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias('FilePath','FullName')][string]$Path)
    process {
        $snapshot=Import-DDSnapshot -Path $Path
        if ($snapshot.Technology -ne 'WinServer') { throw 'The supplied snapshot is not a Windows Server snapshot.' }
        $snapshot
    }
}
