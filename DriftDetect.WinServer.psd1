@{
    # Module manifest for DriftDetect.WinServer
    
    RootModule        = 'DriftDetect.WinServer.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c5d9f2e8-4b1a-4e3d-9f7c-2a8e5d6f3b9c'
    Author            = 'Warezloder'
    CompanyName       = 'Community'
    Copyright         = '(c) 2025 Warezloder. All rights reserved.'
    
    Description       = @'
DriftDetect.WinServer - Configuration drift detection for Windows Server 2022/2025.

Features:
- Class-based collectors for System, Services, Features, Network, Storage, Firewall, Scheduled Tasks, Users/Groups, Group Policy, Registry, and Domain
- Hash-based change detection for efficient comparison
- Configurable severity scoring (Critical, High, Medium, Low)
- Rich HTML reporting with PSWriteHTML
- PowerShell 7+ optimized
- Tracks new, modified, and deleted configuration entities
- Supports both local and remote collection via PowerShell Remoting
- Baseline + delta comparison model

Perfect for Windows Server 2022/2025 infrastructure monitoring and compliance.
'@

    PowerShellVersion = '7.0'
    
    # Required modules
    RequiredModules   = @(
        @{ModuleName = 'PSWriteHTML'; ModuleVersion = '0.0.170'}
    )

    # Functions to export
    FunctionsToExport = @(
        'New-WSSnapshot'
        'Compare-WSSnapshot'
        'Export-WSDriftReport'
        'Get-WSSnapshot'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @(
                'Windows'
                'WindowsServer'
                'Server2022'
                'Server2025'
                'Configuration'
                'Drift'
                'Detection'
                'Compliance'
                'Infrastructure'
                'Automation'
                'Monitoring'
            )
            
            LicenseUri   = 'https://github.com/Warezloder/DriftDetect.WinServer/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/Warezloder/DriftDetect.WinServer'
            
            ReleaseNotes = @'
## Version 1.0.0 - Initial Release

### Features
- Complete configuration drift detection for Windows Server 2022/2025
- Class-based architecture with PowerShell 7 classes
- Hash-based change detection for fast comparison
- Comprehensive entity coverage:
  * System (hostname, domain, OS, DNS, timezone)
  * Services (all non-disabled services)
  * Features (installed Windows features/roles)
  * Network (adapters, IP config, NIC teaming)
  * Storage (disks, volumes)
  * Firewall (profiles, rules)
  * Scheduled Tasks (non-disabled tasks)
  * Local Users & Groups (with membership)
  * Group Policy (applied GPOs, filtered GPOs, RSoP)
  * Registry (important security/config keys)
  * Domain (membership, trusts)
- Configurable severity rules via JSON
- Rich HTML reports with interactive tables and charts
- Pipeline support for all cmdlets
- Local and remote collection (PowerShell Remoting)

### Requirements
- PowerShell 7.0+
- PSWriteHTML 0.0.170+
- Windows Server 2022/2025 (may work with 2019 but untested)
- PowerShell Remoting enabled for remote collection
- Administrator permissions for full data collection

### Usage
Local collection:
```powershell
New-WSSnapshot -ComputerName localhost -OutputPath baseline.json -IncludeRegistry -IncludeGroupPolicy
```

Remote collection:
```powershell
$cred = Get-Credential
New-WSSnapshot -ComputerName SERVER01 -Credential $cred -IncludeScheduledTasks
```
'@
        }
    }

    HelpInfoURI       = 'https://github.com/Warezloder/DriftDetect.WinServer/wiki'
}
