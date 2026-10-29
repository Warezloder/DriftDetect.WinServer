#Requires -Version 7.0
$ErrorActionPreference='Stop'
$core=Get-Module DriftDetect.Core | Sort-Object Version -Descending | Select-Object -First 1
if (-not $core -or $core.Version.Major -ne 1) { throw 'DriftDetect.WinServer 2.x requires DriftDetect.Core 1.x. Install or supply a compatible Core through PSModulePath.' }
foreach ($folder in 'Private','Collectors','Public') {
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Filter *.ps1 | Sort-Object Name)) { . $file.FullName }
}
Export-ModuleMember -Function New-WSSnapshot,Get-WSSnapshot,Compare-WSSnapshot,Export-WSDriftReport,Export-WSConfigurationReport
