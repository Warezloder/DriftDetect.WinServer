function Export-WSDriftReport {
    <# .SYNOPSIS
    Exports a Windows drift report through the shared Core HTML renderer.
    #>
    [CmdletBinding(DefaultParameterSetName='Object')]
    param(
        [Parameter(Mandatory,ParameterSetName='Object',ValueFromPipeline)]$DriftResult,
        [Parameter(Mandatory,ParameterSetName='Path')][string]$DriftResultPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Title='Windows Server Configuration Drift Report'
    )
    process {
        $arguments=@{OutputPath=$OutputPath;Title=$Title}
        if($PSCmdlet.ParameterSetName -eq 'Path'){$arguments.DriftResultPath=$DriftResultPath}else{$arguments.DriftResult=$DriftResult}
        Export-DDDriftReport @arguments
    }
}
