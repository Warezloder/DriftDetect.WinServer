#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Group Policy applied settings and RSoP (Resultant Set of Policy).
#>

class GroupPolicyCollector : WSCollectorBase {
    GroupPolicyCollector() : base('GroupPolicy') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        # Applied GPOs
        $gpos = $this.Invoke({
            try {
                $rsop = gpresult /Scope Computer /R /Z | Out-String
                
                # Parse applied GPOs from gpresult output
                $gpoPattern = 'Applied Group Policy Objects\s+\-+\s+(.*?)(?=\r?\n\s*\r?\n|\Z)'
                $matches = [regex]::Matches($rsop, $gpoPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                
                $appliedGPOs = @()
                if ($matches.Count -gt 0) {
                    $gpoList = $matches[0].Groups[1].Value
                    $appliedGPOs = $gpoList -split '\r?\n' | Where-Object {$_ -match '\S'} | ForEach-Object {$_.Trim()}
                }
                
                # Parse filtered GPOs
                $filteredPattern = 'The following GPOs were not applied.*?\r?\n\s+(.*?)(?=\r?\n\s*\r?\n|\Z)'
                $filteredMatches = [regex]::Matches($rsop, $filteredPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                
                $filteredGPOs = @()
                if ($filteredMatches.Count -gt 0) {
                    $filteredList = $filteredMatches[0].Groups[1].Value
                    $filteredGPOs = $filteredList -split '\r?\n' | Where-Object {$_ -match '\S'} | ForEach-Object {
                        if ($_ -match '(.+?)\s+Filtering:\s+(.+)') {
                            @{
                                Name = $matches[1].Trim()
                                Reason = $matches[2].Trim()
                            }
                        }
                    }
                }
                
                @{
                    AppliedGPOs = $appliedGPOs
                    FilteredGPOs = $filteredGPOs
                    LastRefresh = Get-Date
                }
            }
            catch {
                @{
                    AppliedGPOs = @()
                    FilteredGPOs = @()
                    Error = $_.Exception.Message
                }
            }
        })

        # Create entity for applied GPOs
        $props = @{
            AppliedGPOs = $gpos.AppliedGPOs
            AppliedGPOCount = $gpos.AppliedGPOs.Count
            FilteredGPOs = @($gpos.FilteredGPOs | ForEach-Object { "$($_.Name) - $($_.Reason)" })
            FilteredGPOCount = $gpos.FilteredGPOs.Count
            LastRefresh = $gpos.LastRefresh
        }

        if ($gpos.Error) {
            $props['Error'] = $gpos.Error
        }

        $entity = [WSEntity]::new('GroupPolicy', 'ComputerPolicy', 'GroupPolicy/Computer', $props)
        $entities.Add($entity) | Out-Null

        return $entities.ToArray()
    }
}
