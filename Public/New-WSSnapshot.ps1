function New-WSSnapshot {
    <#
    .SYNOPSIS
        Captures Windows Server configuration with explicit collection coverage.
    .DESCRIPTION
        IncludeAll enables Registry, ScheduledTasks and GroupPolicy. Strict rejects
        any requested applicable unit that does not succeed. Task arguments are
        omitted unless the exact full task path is explicitly allowlisted.
    .EXAMPLE
        New-WSSnapshot -ComputerName SERVER01 -IncludeAll -OutputPath baseline.json
    .EXAMPLE
        New-WSSnapshot -IncludeScheduledTasks -TaskArgumentAllowList '\Ops\Reviewed task'
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string]$ComputerName='localhost',
        [PSCredential]$Credential,
        [switch]$IncludeRegistry,
        [switch]$IncludeScheduledTasks,
        [switch]$IncludeGroupPolicy,
        [string]$OutputPath,
        [switch]$IncludeAll,
        [switch]$Strict,
        [string[]]$TaskArgumentAllowList=@()
    )
    $session=$null
    $argumentCoverage='Task arguments are omitted unless the exact full task path is allowlisted; omitted argument drift is not assessed.'
    $registryCoverage='Known credential-bearing registry values are excluded by exact value names; their drift is not assessed. This policy does not identify arbitrary secrets.'
    $allow=@($TaskArgumentAllowList | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or -not $_.StartsWith('\') -or $_.EndsWith('\') -or $_ -match '[*?]') { throw 'TaskArgumentAllowList requires exact full task paths beginning with a backslash; wildcards and folder-only paths are invalid.' }
        $_.ToLowerInvariant()
    } | Sort-Object -Unique)
    $options=@{
        IncludeRegistry=([bool]$IncludeRegistry -or [bool]$IncludeAll)
        IncludeScheduledTasks=([bool]$IncludeScheduledTasks -or [bool]$IncludeAll)
        IncludeGroupPolicy=([bool]$IncludeGroupPolicy -or [bool]$IncludeAll)
        TaskArgumentAllowList=$allow
        RegistryPaths=@(Get-WSRegistryPaths)
        Recurse=$true
    }
    try {
        if ($ComputerName -notin 'localhost','.', $env:COMPUTERNAME) {
            $connect=@{ComputerName=$ComputerName;ErrorAction='Stop'}
            if ($Credential) { $connect.Credential=$Credential }
            try { $session=New-PSSession @connect } catch { throw 'Unable to establish the requested Windows remoting session. Check connectivity and credentials.' }
        }
        try { $identity=Invoke-WSQuery -Unit Target -Options @{} -Session $session } catch { throw 'Unable to establish trustworthy Windows target identity. Check CIM and registry access.' }
        if ([string]::IsNullOrWhiteSpace([string]$identity.Id)) { throw 'Trustworthy Windows target identity is unavailable.' }
        $target=@{Id=$identity.Id;Name=$identity.Name;IdentitySource=$identity.IdentitySource;Version=$identity.Version;Build=$identity.Build}
        $options.DomainRole=[int]$identity.DomainRole
        $options.PartOfDomain=[bool]$identity.PartOfDomain
        $collections=[System.Collections.Generic.List[object]]::new()
        foreach ($unit in Get-WSUnitDefinitions) {
            $scope=@{};foreach($key in $unit.Scope.Keys){$scope[$key]=$unit.Scope[$key]}
            if ($unit.Id -eq 'ScheduledTasks.Tasks') { $scope.TaskArgumentAllowList=$allow; $scope.ArgumentCoverage=$argumentCoverage; $scope.Exclusions=@($argumentCoverage) }
            if ($unit.Id -eq 'Registry.Values') { $scope.RegistryPaths=$options.RegistryPaths }
            if ($unit.Option -and -not $options[$unit.Option]) {
                $collections.Add((New-DDCollection -Id $unit.Id -Status Skipped -Scope $scope -Reason 'Not requested by capture options.'))
                continue
            }
            $started=[datetime]::UtcNow.ToString('o')
            try {
                $data=Invoke-WSQuery -Unit $unit.Id -Options $options -Session $session
                if ($data.Status -notin 'Success','Partial','Failed','Unsupported','NotApplicable') { throw 'Invalid Windows provider response.' }
                $entities=@(foreach($record in @($data.Entities)) {
                    $properties=ConvertTo-WSMap $record.Properties
                    $observations=ConvertTo-WSMap $record.Observations
                    New-DDEntity -EntityType $record.EntityType -Id $record.Id -Name $record.Name -Path $record.Path -CollectionId $unit.Id -Properties $properties -Observations $observations
                })
                $collections.Add((New-DDCollection -Id $unit.Id -Status $data.Status -Entities $entities -Scope $scope -Reason ([string]$data.Reason)))
            } catch {
                # Never persist an exception message: it may contain task arguments,
                # registry values, credential details or raw native command output.
                $collections.Add((New-DDCollection -Id $unit.Id -Status Failed -Scope $scope -Reason 'Windows provider query failed.' -Diagnostics @(@{Code='WindowsQueryFailed';Message='Collection failed. Verify target capability and access; no raw error content was retained.'})))
            }
            $collections[$collections.Count-1].StartedAt=$started
            $collections[$collections.Count-1].CompletedAt=[datetime]::UtcNow.ToString('o')
        }
        $incomplete=@($collections | Where-Object Status -in 'Partial','Failed','Unsupported')
        if ($Strict -and $incomplete.Count -gt 0) { throw ('Strict capture requires successful requested applicable units. Incomplete: '+($incomplete.Id -join ', ')) }
        if ($incomplete.Count -gt 0) { Write-Warning ('Snapshot coverage is incomplete: '+($incomplete.Id -join ', ')) }
        $profile=@{RequestedCollectors=@($collections | Where-Object Status -ne 'Skipped' | ForEach-Object Id);IncludeRegistry=$options.IncludeRegistry;IncludeScheduledTasks=$options.IncludeScheduledTasks;IncludeGroupPolicy=$options.IncludeGroupPolicy;TaskArgumentAllowList=$allow;RegistryPaths=$options.RegistryPaths;RegistryRecurse=$true}
        $profile.ArgumentCoverage=$argumentCoverage
        $profile.RegistryExclusionCoverage=$registryCoverage
        $profile.Exclusions=@($argumentCoverage,$registryCoverage)
        $rules=Import-DDRuleSet -Path (Join-Path $PSScriptRoot '../Config/Rules.json')
        $snapshot=New-DDSnapshot -Technology WinServer -Target $target -Collections @($collections.ToArray()) -CollectionProfile $profile -RuleSet $rules -ProviderVersion '2.0.0'
        if ($OutputPath) { $null=Export-DDSnapshot -Snapshot $snapshot -Path $OutputPath }
        return $snapshot
    } finally {
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    }
}
