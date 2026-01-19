#Requires -Version 7.0

function Export-WSDriftReport {
    <#
    .SYNOPSIS
        Generates an HTML drift report from Windows Server comparison results.
    
    .DESCRIPTION
        Creates a professional HTML report showing configuration drift with severity
        highlighting, change summaries, and detailed change tables. Uses PSWriteHTML
        for rich formatting.
    
    .PARAMETER DriftResult
        The drift comparison result object from Compare-WSSnapshot.
    
    .PARAMETER DriftResultPath
        Path to drift comparison JSON file (alternative to DriftResult parameter).
    
    .PARAMETER OutputPath
        Path where the HTML report will be saved.
    
    .PARAMETER Title
        Custom title for the report. Default: "Windows Server Configuration Drift Report"
    
    .EXAMPLE
        PS> $drift = Compare-WSSnapshot -BaselinePath baseline.json -CurrentPath current.json
        PS> Export-WSDriftReport -DriftResult $drift -OutputPath report.html
        Generates HTML report from drift object.
    
    .EXAMPLE
        PS> Export-WSDriftReport -DriftResultPath drift.json -OutputPath report.html
        Generates HTML report from saved drift JSON.
    
    .NOTES
        Requires PSWriteHTML module.
    #>
    [CmdletBinding(DefaultParameterSetName='Object')]
    param(
        [Parameter(Mandatory, ParameterSetName='Object', ValueFromPipeline)]
        [PSCustomObject]$DriftResult,

        [Parameter(Mandatory, ParameterSetName='Path')]
        [ValidateScript({ Test-Path $_ })]
        [string]$DriftResultPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$Title = "Windows Server Configuration Drift Report"
    )

    begin {
        # Ensure PSWriteHTML is available
        if (-not (Get-Module -ListAvailable -Name PSWriteHTML)) {
            throw "PSWriteHTML module is required. Install with: Install-Module PSWriteHTML"
        }

        Import-Module PSWriteHTML -ErrorAction Stop
    }

    process {
        try {
            # Load drift result if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                Write-Verbose "Loading drift result from $DriftResultPath"
                $DriftResult = Get-Content $DriftResultPath -Raw | ConvertFrom-Json
            }

            Write-Verbose "Generating HTML report..."

            # Create HTML report
            New-HTML -Title $Title -FilePath $OutputPath -ShowHTML:$false {
                # Header section
                New-HTMLSection -HeaderText $Title {
                    New-HTMLPanel {
                        New-HTMLText -Text "Server: $($DriftResult.ComputerName)" -FontSize 16 -FontWeight bold
                        New-HTMLText -Text "Baseline Snapshot: $($DriftResult.BaselineSnapshot)" -FontSize 12
                        New-HTMLText -Text "Baseline Captured: $($DriftResult.BaselineCapturedAt)" -FontSize 12
                        New-HTMLText -Text "Current Snapshot: $($DriftResult.CurrentSnapshot)" -FontSize 12
                        New-HTMLText -Text "Current Captured: $($DriftResult.CurrentCapturedAt)" -FontSize 12
                    }
                }

                # Summary section
                New-HTMLSection -HeaderText "Drift Summary" {
                    New-HTMLPanel {
                        New-HTMLChart -Title "Changes by Severity" {
                            New-ChartPie -Name 'Critical' -Value $DriftResult.SeveritySummary.Critical -Color Red
                            New-ChartPie -Name 'High' -Value $DriftResult.SeveritySummary.High -Color Orange
                            New-ChartPie -Name 'Medium' -Value $DriftResult.SeveritySummary.Medium -Color Yellow
                            New-ChartPie -Name 'Low' -Value $DriftResult.SeveritySummary.Low -Color Green
                        }
                    }
                    New-HTMLPanel {
                        New-HTMLText -Text "Total Changes: $($DriftResult.TotalChanges)" -FontSize 18 -Color Blue
                        New-HTMLText -Text "New Entities: $($DriftResult.TotalNew)" -FontSize 18 -Color Green
                        New-HTMLText -Text "Deleted Entities: $($DriftResult.TotalDeleted)" -FontSize 18 -Color Red
                    }
                }

                # Changes table
                if ($DriftResult.Changes.Count -gt 0) {
                    New-HTMLSection -HeaderText "Configuration Changes" -CanCollapse {
                        New-HTMLTable -DataTable $DriftResult.Changes {
                            New-TableCondition -Name 'Severity' -Value 'Critical' -BackgroundColor Red -Color White
                            New-TableCondition -Name 'Severity' -Value 'High' -BackgroundColor Orange -Color White
                            New-TableCondition -Name 'Severity' -Value 'Medium' -BackgroundColor Yellow
                            New-TableCondition -Name 'Severity' -Value 'Low' -BackgroundColor LightGreen
                        } -Filtering -PagingLength 25
                    }
                }

                # New entities table
                if ($DriftResult.NewEntities.Count -gt 0) {
                    New-HTMLSection -HeaderText "New Entities" -CanCollapse -Collapsed {
                        New-HTMLTable -DataTable $DriftResult.NewEntities -Filtering
                    }
                }

                # Deleted entities table
                if ($DriftResult.DeletedEntities.Count -gt 0) {
                    New-HTMLSection -HeaderText "Deleted Entities" -CanCollapse -Collapsed {
                        New-HTMLTable -DataTable $DriftResult.DeletedEntities -Filtering
                    }
                }

                # Footer
                New-HTMLSection {
                    New-HTMLText -Text "Report generated: $(Get-Date)" -FontSize 10 -Color Gray
                    New-HTMLText -Text "DriftDetect.WinServer v1.0" -FontSize 10 -Color Gray
                }
            }

            Write-Verbose "Report saved to: $OutputPath"
            return $OutputPath
        }
        catch {
            Write-Error "Failed to generate report: $_"
            throw
        }
    }
}
