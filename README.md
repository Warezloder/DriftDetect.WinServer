# DriftDetect.WinServer v1.0

**Configuration drift detection for Windows Server 2022/2025**

## Overview

DriftDetect.WinServer provides comprehensive drift detection for Windows Server 2022/2025 infrastructure. Built with PowerShell 7 classes and hash-based change tracking, it quickly identifies configuration changes across system, services, features, network, storage, security, and domain settings.

**Supports both local and remote collection** via PowerShell Remoting, making it ideal for monitoring multiple servers from a central management station.

## Key Features

- **Hash-Based Change Detection** - Fast comparison using SHA256 hashing
- **Comprehensive Coverage** - 11 entity collectors covering all major configuration areas
- **Local & Remote Collection** - Collect from localhost or remote servers via PSRemoting
- **Entity Lifecycle Tracking** - Detects new, modified, and deleted components
- **Configurable Severity Scoring** - Critical, High, Medium, Low classifications
- **Rich HTML Reports** - Interactive tables with filtering and severity highlighting
- **PowerShell 7 Optimized** - Modern syntax, classes, and performance
- **Domain-Aware** - Tracks domain membership, Group Policy, and trust relationships

## Entity Types Collected

| Category | Entities | Details |
|----------|----------|---------|
| **System** | Host Configuration | Hostname, Domain, OS version/build, DNS, timezone, memory, processors |
| **Service** | Windows Services | All non-disabled services with startup type and running state |
| **Feature** | Roles & Features | Installed Windows features (IIS, Hyper-V, AD DS, File Server, etc.) |
| **Network** | Adapters & Teaming | Network adapters, IP configuration, NIC teaming settings |
| **Storage** | Disks & Volumes | Physical disks, volumes, health status, capacity |
| **Firewall** | Profiles & Rules | Firewall profiles, enabled rules (ports, protocols, direction) |
| **ScheduledTask** | Scheduled Tasks | Non-disabled tasks with triggers and actions (optional) |
| **LocalAccount** | Users & Groups | Local users, groups, and group membership |
| **GroupPolicy** | Applied GPOs | Applied Group Policies and filtered GPOs with reasons (optional) |
| **Registry** | Important Keys | Security and configuration registry settings (optional) |
| **Domain** | Domain Membership | Domain/workgroup status, DC, trust relationships |

## Installation

```powershell
# Prerequisites
Install-Module PSWriteHTML -MinimumVersion 0.0.170

# Import module
Import-Module .\DriftDetect.WinServer.psd1
```

## Quick Start

### Local Server Monitoring
```powershell
# 1. Capture baseline snapshot (local server)
New-WSSnapshot -ComputerName localhost -OutputPath "baseline.json" `
    -IncludeRegistry -IncludeGroupPolicy -IncludeScheduledTasks

# 2. Make changes to the server...
# (Install feature, change service, modify firewall, etc.)

# 3. Capture current state
$current = New-WSSnapshot -ComputerName localhost `
    -IncludeRegistry -IncludeGroupPolicy -IncludeScheduledTasks

# 4. Compare and detect drift
$drift = Compare-WSSnapshot -BaselinePath baseline.json -CurrentSnapshot $current

# 5. Generate HTML report
Export-WSDriftReport -DriftResult $drift -OutputPath "drift-report.html"
Start-Process "drift-report.html"
```

### Remote Server Monitoring
```powershell
# Enable PowerShell Remoting on target server first:
# Enable-PSRemoting -Force

# Capture from remote server
$cred = Get-Credential Administrator
New-WSSnapshot -ComputerName SERVER01 -Credential $cred `
    -OutputPath "SERVER01-baseline.json" `
    -IncludeRegistry -IncludeGroupPolicy
```

## Usage Examples

### Minimal Snapshot (Fast)
```powershell
# Core entities only (System, Services, Features, Network, Storage, Firewall, Users, Domain)
$snapshot = New-WSSnapshot -ComputerName localhost -OutputPath "quick-snapshot.json"
```

### Comprehensive Snapshot
```powershell
# Everything including optional collectors
New-WSSnapshot -ComputerName localhost -OutputPath "full-snapshot.json" `
    -IncludeRegistry -IncludeGroupPolicy -IncludeScheduledTasks -Verbose
```

### Compare Snapshots
```powershell
# Using file paths
$drift = Compare-WSSnapshot -BaselinePath baseline.json -CurrentPath current.json

# Using objects
$baseline = Get-WSSnapshot -Path baseline.json
$current = New-WSSnapshot -ComputerName localhost -IncludeRegistry
$drift = Compare-WSSnapshot -BaselineSnapshot $baseline -CurrentSnapshot $current

# Save comparison results
Compare-WSSnapshot -BaselinePath baseline.json -CurrentPath current.json `
    -OutputPath "drift-results.json"
```

### Generate Reports
```powershell
# Basic report
Export-WSDriftReport -DriftResult $drift -OutputPath "report.html"

# Custom title
Export-WSDriftReport -DriftResult $drift -OutputPath "report.html" `
    -Title "SERVER01 Weekly Drift Report"

# From saved drift results
Export-WSDriftReport -DriftResultPath "drift-results.json" `
    -OutputPath "report.html"
```

### Inspect Snapshots
```powershell
# Load and inspect
$snapshot = Get-WSSnapshot -Path "snapshot.json"

# View metadata
$snapshot.ComputerName
$snapshot.OSVersion
$snapshot.CapturedAt
$snapshot.Entities.Keys

# Count entities by type
$snapshot.Entities.System.Count
$snapshot.Entities.Service.Count
$snapshot.Entities.Feature.Count

# Find specific entity
$mgmtAdapter = $snapshot.GetEntity('Network', 'Network/Adapter/Ethernet')
$mgmtAdapter.Properties
```

## Scheduled Monitoring

### Monitor Multiple Servers
```powershell
# Save as C:\Scripts\WinServer-DriftMonitor.ps1
param(
    [Parameter(Mandatory)]
    [string[]]$ServerNames,
    
    [Parameter(Mandatory)]
    [PSCredential]$Credential
)

Import-Module DriftDetect.WinServer

$date = Get-Date -Format "yyyy-MM-dd_HHmm"

foreach ($server in $ServerNames) {
    try {
        Write-Host "Processing $server..." -ForegroundColor Cyan
        
        # Capture current snapshot
        $current = New-WSSnapshot -ComputerName $server -Credential $Credential `
            -OutputPath "C:\Snapshots\$server\$date.json" `
            -IncludeRegistry -IncludeGroupPolicy
        
        # Compare to baseline
        $baselinePath = "C:\Snapshots\$server\baseline.json"
        if (Test-Path $baselinePath) {
            $baseline = Get-WSSnapshot -Path $baselinePath
            $drift = Compare-WSSnapshot -BaselineSnapshot $baseline -CurrentSnapshot $current
            
            # Generate report if changes detected
            if ($drift.TotalChanges -gt 0) {
                $reportPath = "C:\Reports\$server\drift_$date.html"
                Export-WSDriftReport -DriftResult $drift -OutputPath $reportPath
                
                # Alert on critical changes
                if ($drift.SeveritySummary.Critical -gt 0) {
                    Send-MailMessage -To "admin@domain.local" `
                        -Subject "CRITICAL: $server Drift Detected" `
                        -Body "$($drift.SeveritySummary.Critical) critical changes detected on $server" `
                        -Attachments $reportPath `
                        -SmtpServer "smtp.domain.local"
                }
            }
        }
    }
    catch {
        Write-Error "Failed to process $server : $_"
    }
}
```

Schedule it:
```powershell
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
$cred = Get-Credential
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-File C:\Scripts\WinServer-DriftMonitor.ps1 -ServerNames @('SERVER01','SERVER02','SERVER03')"

Register-ScheduledTask -TaskName "Windows Server Drift Monitor" `
    -Trigger $trigger -Action $action
```

## Custom Severity Rules

Edit `Config\SeverityRules.json`:

```json
{
  "Rules": [
    {"EntityType": "System", "Property": "PartOfDomain", "Severity": "Critical"},
    {"EntityType": "Service", "Property": "Status", "Severity": "Medium"},
    {"EntityType": "Feature", "Property": "*", "Severity": "High"},
    {"EntityType": "Firewall", "Property": "Enabled", "Severity": "Critical"},
    {"EntityType": "GroupPolicy", "Property": "AppliedGPOs", "Severity": "High"},
    {"EntityType": "LocalAccount", "Property": "Members", "Severity": "High"}
  ]
}
```

## Advanced Configuration

### Custom Registry Paths
```powershell
# Add custom registry paths to monitor
$collector = [RegistryCollector]::new()
$collector.AddRegistryPath('HKLM:\SOFTWARE\MyCompany\Settings')
# Then use in custom snapshot capture
```

### Remote Collection Best Practices
```powershell
# Use CredSSP for multi-hop scenarios (e.g., querying domain resources)
$session = New-PSSession -ComputerName SERVER01 -Credential $cred `
    -Authentication CredSSP

# Pass session to snapshot capture
$snapshot = New-WSSnapshot -ComputerName SERVER01 -Credential $cred
```

## Performance Tips

- **Minimal snapshots** - Omit optional collectors for faster captures
- **Hash comparison** - Only changed entities are deeply compared
- **Remote collection** - Runs natively on target server (minimal network traffic)
- **Scheduled off-hours** - Run monitoring during low-activity periods

## Troubleshooting

### PowerShell Remoting Issues
```powershell
# Test remoting
Test-WSMan -ComputerName SERVER01

# Enable remoting on target server
Enable-PSRemoting -Force

# Configure firewall (if needed)
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -Enabled True
```

### Permission Issues
```powershell
# Ensure account has:
# - Local Administrator on target server
# - Permissions to read: Services, Features, Registry, Group Policy
# - Domain user for domain/trust enumeration
```

### Large Snapshot Files
```powershell
# Reduce snapshot size by excluding optional collectors
New-WSSnapshot -ComputerName localhost -OutputPath "snapshot.json"
# Don't use -IncludeScheduledTasks unless needed
```

## Comparison with Other Modules

| Feature | DriftDetect.WinServer | DriftDetect.ESXi | DriftDetect.VMware |
|---------|----------------------|------------------|--------------------|
| **Target** | Windows Server 2022/2025 | Standalone ESXi hosts | vCenter infrastructure |
| **Scope** | Single server config | Single ESXi host | Multiple hosts/clusters/VMs |
| **Collection** | Local or PSRemoting | Direct to ESXi | vCenter API |
| **Entity Types** | 11 types | 7 types | 5 types |
| **Use Case** | Server config management | Edge ESXi monitoring | Datacenter with vCenter |

## Module Structure

```
DriftDetect.WinServer/
├── DriftDetect.WinServer.psd1            # Module manifest
├── DriftDetect.WinServer.psm1            # Root module
├── Classes/                              # Entity and collector classes
│   ├── EntityBase.ps1                    # Base entity class
│   ├── CollectorBase.ps1                 # Base collector
│   ├── SystemCollector.ps1               # System configuration
│   ├── ServiceCollector.ps1              # Windows services
│   ├── FeatureCollector.ps1              # Roles & features
│   ├── NetworkCollector.ps1              # Network & teaming
│   ├── StorageCollector.ps1              # Disks & volumes
│   ├── FirewallCollector.ps1             # Firewall rules
│   ├── ScheduledTaskCollector.ps1        # Scheduled tasks
│   ├── LocalUserGroupCollector.ps1       # Local users/groups
│   ├── GroupPolicyCollector.ps1          # Group Policy
│   ├── RegistryCollector.ps1             # Registry settings
│   ├── DomainCollector.ps1               # Domain membership
│   ├── Snapshot.ps1                      # Snapshot container
│   └── DriftEngine.ps1                   # Comparison engine
├── Public/                               # Exported functions
│   ├── New-WSSnapshot.ps1
│   ├── Compare-WSSnapshot.ps1
│   ├── Export-WSDriftReport.ps1
│   └── Get-WSSnapshot.ps1
└── Config/                               # Configuration
    └── SeverityRules.json                # Severity scoring rules
```

## Requirements

- **PowerShell:** 7.0 or higher
- **PSWriteHTML:** 0.0.170 or higher
- **Windows Server:** 2022 or 2025 (2019 may work but untested)
- **Permissions:** Local Administrator for full collection
- **PowerShell Remoting:** Enabled for remote collection

## Use Cases

- **Change Control** - Track configuration changes during maintenance windows
- **Compliance Auditing** - Ensure servers maintain required configurations
- **Security Hardening** - Monitor firewall, users, group policy, registry
- **Troubleshooting** - Identify unexpected changes after issues
- **Multi-Server Management** - Monitor entire server fleet from central location
- **Pre/Post Patching** - Verify patch installations didn't introduce drift

## License

MIT License - see LICENSE file

## Contributing

Issues and pull requests welcome at: https://github.com/Warezloder/DriftDetect.WinServer

## Related Projects

- **DriftDetect.VMware** - For vCenter-managed environments
- **DriftDetect.ESXi** - For standalone ESXi hosts

## Author

**Warezloder**  
https://github.com/Warezloder
