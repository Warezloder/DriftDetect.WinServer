#Requires -Version 7.0

<#
.SYNOPSIS
    DriftDetect.WinServer - Windows Server 2022/2025 configuration drift detection module.

.DESCRIPTION
    Root module file that loads all classes, private functions, and public functions.
    This module provides comprehensive drift detection for Windows Server environments
    using hash-based change tracking and severity scoring.
    
    Supports both local and remote collection via PowerShell Remoting.
#>

$ErrorActionPreference = 'Stop'

# Get module root path
$ModuleRoot = $PSScriptRoot

# Load Classes (order matters - base classes first)
$classLoadOrder = @(
    'EntityBase.ps1'
    'CollectorBase.ps1'
    'SystemCollector.ps1'
    'ServiceCollector.ps1'
    'FeatureCollector.ps1'
    'NetworkCollector.ps1'
    'StorageCollector.ps1'
    'FirewallCollector.ps1'
    'ScheduledTaskCollector.ps1'
    'LocalUserGroupCollector.ps1'
    'GroupPolicyCollector.ps1'
    'RegistryCollector.ps1'
    'DomainCollector.ps1'
    'Snapshot.ps1'
    'DriftEngine.ps1'
)

Write-Verbose "Loading DriftDetect.WinServer classes..."
foreach ($className in $classLoadOrder) {
    $classPath = Join-Path $ModuleRoot "Classes\$className"
    if (Test-Path $classPath) {
        . $classPath
        Write-Verbose "  Loaded: $className"
    }
    else {
        Write-Warning "Class file not found: $classPath"
    }
}

# Load Private functions
Write-Verbose "Loading private functions..."
$privatePath = Join-Path $ModuleRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "  Loaded: $($_.Name)"
        }
        catch {
            Write-Warning "Failed to load private function $($_.Name): $_"
        }
    }
}

# Load Public functions
Write-Verbose "Loading public functions..."
$publicPath = Join-Path $ModuleRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "  Loaded: $($_.Name)"
        }
        catch {
            Write-Warning "Failed to load public function $($_.Name): $_"
        }
    }
}

# Export public functions
Export-ModuleMember -Function 'New-WSSnapshot', 'Compare-WSSnapshot', 'Export-WSDriftReport', 'Get-WSSnapshot'

Write-Verbose "DriftDetect.WinServer module loaded successfully"
