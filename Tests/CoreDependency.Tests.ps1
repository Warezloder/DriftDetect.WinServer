BeforeAll {
    $script:AdapterRoot=Split-Path $PSScriptRoot -Parent
    $script:AdapterName=Split-Path $script:AdapterRoot -Leaf
    $script:Technology=if($script:AdapterName -eq 'DriftDetect.WinServer'){'WinServer'}else{'ESXi'}
    $script:Shell=(Get-Command pwsh -ErrorAction Stop).Source
    $script:Runner=Join-Path $TestDrive 'import-check.ps1'
    @'
param($ModulePath,$FixtureRoot,$Scenario,$Technology)
$ErrorActionPreference='Stop'
$env:PSModulePath=$FixtureRoot+[IO.Path]::PathSeparator+(Join-Path $PSHOME Modules)
try {
    if($Scenario -eq 'BothLoaded'){Import-Module (Join-Path $FixtureRoot 'DriftDetect.Core/1.9.0/DriftDetect.Core.psd1')}
    if($Scenario -in @('V2Loaded','BothLoaded')){Import-Module (Join-Path $FixtureRoot 'DriftDetect.Core/2.0.0/DriftDetect.Core.psd1')}
    Import-Module $ModulePath
    $command=if($Technology -eq 'WinServer'){'Get-WSSnapshot'}else{'Get-ESXiSnapshot'}
    $snapshot=& $command -Path $Technology
    [pscustomobject]@{Success=$true;CoreVersion=$snapshot.CoreVersion} | ConvertTo-Json -Compress
}catch{
    [pscustomobject]@{Success=$false;Error=$_.Exception.Message} | ConvertTo-Json -Compress
}
'@ | Set-Content -LiteralPath $script:Runner -Encoding utf8
    function Invoke-DependencyScenario([string]$Scenario) {
        $fixture=Join-Path $TestDrive $Scenario
        foreach($version in $(if($Scenario -eq 'OnlyV2'){@('2.0.0')}else{@('1.0.0','1.9.0','2.0.0')})){
            $folder=Join-Path $fixture ('DriftDetect.Core/'+$version)
            $null=New-Item -ItemType Directory -Path $folder -Force
            $source="function Import-DDSnapshot { param([string]`$Path) [pscustomobject]@{Technology=`$Path;CoreVersion='$version'} }; Export-ModuleMember -Function Import-DDSnapshot"
            Set-Content -LiteralPath (Join-Path $folder DriftDetect.Core.psm1) -Value $source -Encoding utf8
            New-ModuleManifest -Path (Join-Path $folder DriftDetect.Core.psd1) -RootModule DriftDetect.Core.psm1 -ModuleVersion $version -Guid '794eb27b-64d8-429c-94de-5c89ebd78ca2' -FunctionsToExport Import-DDSnapshot -CmdletsToExport @() -VariablesToExport @() -AliasesToExport @()
        }
        $output=& $script:Shell -NoProfile -NonInteractive -File $script:Runner -ModulePath (Join-Path $script:AdapterRoot ($script:AdapterName+'.psd1')) -FixtureRoot $fixture -Scenario $Scenario -Technology $script:Technology
        if($LASTEXITCODE -ne 0){throw 'Import test child process failed.'}
        return ($output -join "`n" | ConvertFrom-Json)
    }
}
Describe 'Supported Core major version selection' {
    It 'loads and uses Core 1.x with scenario <Scenario>' -ForEach @(@{Scenario='BothInstalled'},@{Scenario='V2Loaded'},@{Scenario='BothLoaded'}) {
        $result=Invoke-DependencyScenario $Scenario
        $result.Success | Should -BeTrue -Because $result.Error
        $result.CoreVersion | Should -Be '1.9.0'
    }
    It 'rejects an installation containing only Core 2.x' {
        $result=Invoke-DependencyScenario OnlyV2
        $result.Success | Should -BeFalse
        $result.Error | Should -Match 'DriftDetect.Core'
    }
}
