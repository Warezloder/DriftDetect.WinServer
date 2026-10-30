BeforeAll {
    $moduleRoot=Split-Path $PSScriptRoot
    $manifest=Import-PowerShellDataFile (Join-Path $moduleRoot 'DriftDetect.WinServer.psd1')
}
Describe 'Windows package contract' {
    It 'requires Core 1 while keeping platform and report modules lazy' {
        $manifest.ModuleVersion | Should -Be '2.0.1'
        $manifest.RequiredModules.ModuleName | Should -Contain 'DriftDetect.Core'
        $manifest.RequiredModules.ModuleName | Should -Not -Contain 'PSWriteHTML'
        $manifest.FunctionsToExport | Should -Contain 'Export-WSConfigurationReport'
    }
    It 'retains capture parameters and adds explicit coverage switches' {
        $errors=$null;$tokens=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $moduleRoot 'Public/New-WSSnapshot.ps1'),[ref]$tokens,[ref]$errors)
        $parameters=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true).Body.ParamBlock.Parameters.Name.VariablePath.UserPath
        foreach($name in 'ComputerName','Credential','IncludeRegistry','IncludeScheduledTasks','IncludeGroupPolicy','OutputPath','IncludeAll','Strict','TaskArgumentAllowList') { $parameters | Should -Contain $name }
    }
    It 'loads functions without legacy classes' {
        $text=Get-Content (Join-Path $moduleRoot 'DriftDetect.WinServer.psm1') -Raw
        $text | Should -Not -Match 'classLoadOrder|Classes\\'
    }
}
