@{
    RootModule='DriftDetect.WinServer.psm1'
    ModuleVersion='2.0.0'
    GUID='c5d9f2e8-4b1a-4e3d-9f7c-2a8e5d6f3b9c'
    Author='Warezloder'
    CompanyName='Community'
    Copyright='(c) 2025 Warezloder. All rights reserved.'
    Description='Windows Server configuration collection with explicit coverage and shared DriftDetect.Core comparison, JSON persistence and reports.'
    PowerShellVersion='7.0'
    RequiredModules=@(@{ModuleName='DriftDetect.Core';ModuleVersion='1.0.0'})
    FunctionsToExport=@('New-WSSnapshot','Get-WSSnapshot','Compare-WSSnapshot','Export-WSDriftReport','Export-WSConfigurationReport')
    CmdletsToExport=@()
    VariablesToExport=@()
    AliasesToExport=@()
    PrivateData=@{PSData=@{
        Tags=@('Windows','WindowsServer','Configuration','Drift','Detection')
        LicenseUri='https://github.com/Warezloder/DriftDetect.WinServer/blob/main/LICENSE'
        ProjectUri='https://github.com/Warezloder/DriftDetect.WinServer'
        ReleaseNotes='2.0.0: Shared Core 1.x, schema 2.0, explicit collection coverage, task argument privacy, stable identities and configuration reports. Recapture baselines before comparison. Classes are retained as unused legacy source.'
    }}
}
