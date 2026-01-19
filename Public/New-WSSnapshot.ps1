#Requires -Version 7.0

function New-WSSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of Windows Server configuration.
    
    .DESCRIPTION
        Collects detailed configuration data from a Windows Server 2022/2025 system including
        system settings, services, features, network, storage, firewall, scheduled tasks,
        local users/groups, group policy, registry settings, and domain membership.
        
        Supports both local and remote collection via PowerShell Remoting.
    
    .PARAMETER ComputerName
        The computer name to capture snapshot from. Use localhost or omit for local machine.
        For remote servers, PowerShell Remoting must be enabled.
    
    .PARAMETER Credential
        Credentials for remote connection (if needed).
    
    .PARAMETER IncludeRegistry
        Include important registry settings in snapshot.
    
    .PARAMETER IncludeScheduledTasks
        Include scheduled tasks in snapshot.
    
    .PARAMETER IncludeGroupPolicy
        Include applied Group Policy settings and RSoP data.
    
    .PARAMETER OutputPath
        Path to export the snapshot JSON file. If not specified, returns snapshot object only.
    
    .EXAMPLE
        PS> $snapshot = New-WSSnapshot -ComputerName localhost -OutputPath "baseline.json"
        Captures a basic snapshot of the local server.
    
    .EXAMPLE
        PS> New-WSSnapshot -ComputerName SERVER01 -IncludeRegistry -IncludeGroupPolicy -IncludeScheduledTasks
        Captures a comprehensive snapshot of remote server SERVER01.
    
    .NOTES
        Requires PowerShell 7.0+.
        For remote servers, requires PowerShell Remoting enabled.
        Some collectors require elevated (Administrator) permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ComputerName = 'localhost',

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [switch]$IncludeRegistry,

        [Parameter()]
        [switch]$IncludeScheduledTasks,

        [Parameter()]
        [switch]$IncludeGroupPolicy,

        [Parameter()]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting snapshot capture from $ComputerName"
        
        # Establish session if remote
        $session = $null
        if ($ComputerName -ne 'localhost' -and $ComputerName -ne $env:COMPUTERNAME) {
            try {
                $sessionParams = @{
                    ComputerName = $ComputerName
                }
                if ($Credential) {
                    $sessionParams['Credential'] = $Credential
                }
                
                $session = New-PSSession @sessionParams -ErrorAction Stop
                Write-Verbose "Established remote session to $ComputerName"
            }
            catch {
                throw "Failed to establish remote session: $_"
            }
        }
    }

    process {
        try {
            # Create snapshot object
            $snapshot = [WSSnapshot]::new()

            # Always collect System configuration
            Write-Verbose "Collecting system configuration..."
            $systemCollector = [SystemCollector]::new()
            $systemEntities = $systemCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($systemEntities)
            
            # Set snapshot metadata from system info
            $sysProps = $systemEntities[0].Properties
            $snapshot.ComputerName = $sysProps.ComputerName
            $snapshot.OSVersion = $sysProps.OSVersion
            $snapshot.OSBuild = $sysProps.OSBuild
            Write-Verbose "Collected $($systemEntities.Count) system entities"

            # Always collect Services
            Write-Verbose "Collecting services..."
            $serviceCollector = [ServiceCollector]::new()
            $serviceEntities = $serviceCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($serviceEntities)
            Write-Verbose "Collected $($serviceEntities.Count) service entities"

            # Always collect Features
            Write-Verbose "Collecting Windows features..."
            $featureCollector = [FeatureCollector]::new()
            $featureEntities = $featureCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($featureEntities)
            Write-Verbose "Collected $($featureEntities.Count) feature entities"

            # Always collect Network
            Write-Verbose "Collecting network configuration..."
            $networkCollector = [NetworkCollector]::new()
            $networkEntities = $networkCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($networkEntities)
            Write-Verbose "Collected $($networkEntities.Count) network entities"

            # Always collect Storage
            Write-Verbose "Collecting storage configuration..."
            $storageCollector = [StorageCollector]::new()
            $storageEntities = $storageCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($storageEntities)
            Write-Verbose "Collected $($storageEntities.Count) storage entities"

            # Always collect Firewall
            Write-Verbose "Collecting firewall configuration..."
            $firewallCollector = [FirewallCollector]::new()
            $firewallEntities = $firewallCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($firewallEntities)
            Write-Verbose "Collected $($firewallEntities.Count) firewall entities"

            # Always collect Local Users/Groups
            Write-Verbose "Collecting local users and groups..."
            $localCollector = [LocalUserGroupCollector]::new()
            $localEntities = $localCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($localEntities)
            Write-Verbose "Collected $($localEntities.Count) local account entities"

            # Always collect Domain information
            Write-Verbose "Collecting domain membership..."
            $domainCollector = [DomainCollector]::new()
            $domainEntities = $domainCollector.Collect($ComputerName, $session)
            $snapshot.AddEntities($domainEntities)
            Write-Verbose "Collected $($domainEntities.Count) domain entities"

            # Optional: Scheduled Tasks
            if ($IncludeScheduledTasks) {
                Write-Verbose "Collecting scheduled tasks..."
                $taskCollector = [ScheduledTaskCollector]::new()
                $taskEntities = $taskCollector.Collect($ComputerName, $session)
                $snapshot.AddEntities($taskEntities)
                Write-Verbose "Collected $($taskEntities.Count) scheduled task entities"
            }

            # Optional: Group Policy
            if ($IncludeGroupPolicy) {
                Write-Verbose "Collecting group policy settings..."
                $gpCollector = [GroupPolicyCollector]::new()
                $gpEntities = $gpCollector.Collect($ComputerName, $session)
                $snapshot.AddEntities($gpEntities)
                Write-Verbose "Collected $($gpEntities.Count) group policy entities"
            }

            # Optional: Registry
            if ($IncludeRegistry) {
                Write-Verbose "Collecting registry settings..."
                $regCollector = [RegistryCollector]::new()
                $regEntities = $regCollector.Collect($ComputerName, $session)
                $snapshot.AddEntities($regEntities)
                Write-Verbose "Collected $($regEntities.Count) registry entities"
            }

            # Add metadata
            $snapshot.Metadata['CaptureParameters'] = @{
                IncludeRegistry = $IncludeRegistry.IsPresent
                IncludeScheduledTasks = $IncludeScheduledTasks.IsPresent
                IncludeGroupPolicy = $IncludeGroupPolicy.IsPresent
            }

            # Export if path specified
            if ($OutputPath) {
                $snapshot.Export($OutputPath)
                Write-Verbose "Snapshot exported to $OutputPath"
            }

            return $snapshot
        }
        catch {
            Write-Error "Failed to capture snapshot: $_"
            throw
        }
        finally {
            if ($session) {
                Remove-PSSession -Session $session
                Write-Verbose "Closed remote session"
            }
        }
    }
}
