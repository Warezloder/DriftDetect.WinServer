function Compare-WSSnapshot {
    <# .SYNOPSIS
    Compares Windows snapshots with strict coverage or explicit AllowPartial.
    #>
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory,ParameterSetName='Path')][string]$BaselinePath,
        [Parameter(Mandatory,ParameterSetName='Path')][string]$CurrentPath,
        [Parameter(Mandatory,ParameterSetName='Object')]$BaselineSnapshot,
        [Parameter(Mandatory,ParameterSetName='Object')]$CurrentSnapshot,
        [string]$SeverityConfigPath,
        [string]$OutputPath,
        [switch]$AllowPartial
    )
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $BaselineSnapshot=Get-WSSnapshot -Path $BaselinePath
        $CurrentSnapshot=Get-WSSnapshot -Path $CurrentPath
    }
    if ($BaselineSnapshot.Technology -ne 'WinServer' -or $CurrentSnapshot.Technology -ne 'WinServer') { throw 'Compare-WSSnapshot requires Windows Server snapshots.' }
    $compare=@{BaselineSnapshot=$BaselineSnapshot;CurrentSnapshot=$CurrentSnapshot;AllowPartial=$AllowPartial}
    if ($SeverityConfigPath) { $compare.RuleSet=Import-DDRuleSet -Path $SeverityConfigPath }
    $result=Compare-DDSnapshot @compare
    if ($OutputPath) { $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8 -ErrorAction Stop }
    return $result
}
