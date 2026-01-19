#Requires -Version 7.0

<#
.SYNOPSIS
    Base class for Windows Server configuration collectors.
    Supports both local and remote collection via PowerShell Remoting.
#>

class WSCollectorBase {
    [string]$EntityType
    [bool]$Enabled = $true
    [string]$ComputerName
    [System.Management.Automation.Runspaces.PSSession]$Session

    WSCollectorBase([string]$type) {
        $this.EntityType = $type
    }

    # Override in derived classes
    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        throw "Collect() must be implemented in derived class"
    }

    # Helper to safely get property value
    [object] GetProperty([object]$obj, [string]$property, [object]$default = $null) {
        try {
            $val = $obj.$property
            return $null -eq $val ? $default : $val
        }
        catch {
            return $default
        }
    }

    # Helper to get nested property (e.g. "Config.Network.DNSServers")
    [object] GetNestedProperty([object]$obj, [string]$propertyPath, [object]$default = $null) {
        try {
            $current = $obj
            foreach ($prop in $propertyPath -split '\.') {
                $current = $current.$prop
                if ($null -eq $current) { return $default }
            }
            return $current
        }
        catch {
            return $default
        }
    }

    # Execute scriptblock locally or remotely
    [object] Invoke([scriptblock]$scriptBlock) {
        if ($this.Session) {
            return Invoke-Command -Session $this.Session -ScriptBlock $scriptBlock
        }
        else {
            return & $scriptBlock
        }
    }
}
