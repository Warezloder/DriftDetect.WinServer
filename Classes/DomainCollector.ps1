#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for domain membership and trust relationships.
#>

class DomainCollector : WSCollectorBase {
    DomainCollector() : base('Domain') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        $domainInfo = $this.Invoke({
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            
            $result = @{
                PartOfDomain = $cs.PartOfDomain
                Domain = $cs.Domain
                Workgroup = $cs.Workgroup
            }
            
            # If domain-joined, get more details
            if ($cs.PartOfDomain) {
                try {
                    # Get domain controller info
                    $dc = Get-CimInstance -ClassName Win32_NTDomain | Select-Object -First 1
                    $result['DomainControllerName'] = $dc.DomainControllerName
                    $result['DomainName'] = $dc.DomainName
                    
                    # Get trust relationships (requires elevated permissions)
                    try {
                        $trusts = Get-CimInstance -Namespace root\MicrosoftActiveDirectory -ClassName Microsoft_DomainTrustStatus -ErrorAction SilentlyContinue
                        $result['Trusts'] = @($trusts | ForEach-Object {
                            @{
                                TrustedDomain = $_.TrustedDomain
                                TrustDirection = $_.TrustDirection
                                TrustType = $_.TrustType
                                TrustAttributes = $_.TrustAttributes
                            }
                        })
                    }
                    catch {
                        $result['Trusts'] = @()
                        $result['TrustsError'] = "Unable to enumerate trusts (may require elevated permissions)"
                    }
                }
                catch {
                    $result['DomainError'] = $_.Exception.Message
                }
            }
            
            $result
        })

        $props = @{
            PartOfDomain = $domainInfo.PartOfDomain
            Domain = $domainInfo.Domain
            Workgroup = $domainInfo.Workgroup
        }

        if ($domainInfo.PartOfDomain) {
            $props['DomainControllerName'] = $domainInfo.DomainControllerName
            $props['DomainName'] = $domainInfo.DomainName
            $props['Trusts'] = $domainInfo.Trusts
            $props['TrustCount'] = $domainInfo.Trusts.Count
            
            if ($domainInfo.TrustsError) {
                $props['TrustsError'] = $domainInfo.TrustsError
            }
            if ($domainInfo.DomainError) {
                $props['DomainError'] = $domainInfo.DomainError
            }
        }

        $name = if ($domainInfo.PartOfDomain) { $domainInfo.Domain } else { $domainInfo.Workgroup }
        $entity = [WSEntity]::new('Domain', $name, 'Domain/Membership', $props)
        $entities.Add($entity) | Out-Null

        return $entities.ToArray()
    }
}
