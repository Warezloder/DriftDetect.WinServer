function Export-WSConfigurationReport {
    <# .SYNOPSIS
    Exports all captured Windows configuration with explicit coverage.
    #>
    [CmdletBinding(DefaultParameterSetName='Object')]
    param(
        [Parameter(Mandatory,ParameterSetName='Object',ValueFromPipeline)]$Snapshot,
        [Parameter(Mandatory,ParameterSetName='Path')][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Title='Windows Server Configuration Report'
    )
    process {
        $arguments=@{OutputPath=$OutputPath;Title=$Title}
        if($PSCmdlet.ParameterSetName -eq 'Path'){$arguments.SnapshotPath=$SnapshotPath}else{$arguments.Snapshot=$Snapshot}
        Export-DDConfigurationReport @arguments
    }
}
