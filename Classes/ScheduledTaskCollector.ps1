#Requires -Version 7.0

<#
.SYNOPSIS
    Collector for Windows scheduled tasks.
#>

class ScheduledTaskCollector : WSCollectorBase {
    ScheduledTaskCollector() : base('ScheduledTask') {}

    [WSEntity[]] Collect([string]$computerName, [System.Management.Automation.Runspaces.PSSession]$session) {
        $this.ComputerName = $computerName
        $this.Session = $session
        $entities = [System.Collections.ArrayList]::new()
        
        $tasks = $this.Invoke({
            Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled'} | ForEach-Object {
                $info = $null
                try {
                    $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                }
                catch {
                    # Some tasks may not have info available
                }
                
                @{
                    TaskName = $_.TaskName
                    TaskPath = $_.TaskPath
                    State = $_.State.ToString()
                    LastRunTime = if ($info) { $info.LastRunTime } else { $null }
                    LastTaskResult = if ($info) { $info.LastTaskResult } else { $null }
                    NextRunTime = if ($info) { $info.NextRunTime } else { $null }
                    NumberOfMissedRuns = if ($info) { $info.NumberOfMissedRuns } else { 0 }
                    Author = $_.Author
                    Description = $_.Description
                    Triggers = @($_.Triggers | ForEach-Object { if ($_) { $_.GetType().Name } else { 'Unknown' } })
                    Actions = @($_.Actions | ForEach-Object { 
                        if ($_ -and $_.Execute) { $_.Execute } 
                        elseif ($_) { $_.GetType().Name }
                        else { 'Unknown' }
                    })
                }
            }
        })

        foreach ($task in $tasks) {
            $props = @{
                TaskName = $task.TaskName
                TaskPath = $task.TaskPath
                State = $task.State
                LastRunTime = $task.LastRunTime
                LastTaskResult = $task.LastTaskResult
                NextRunTime = $task.NextRunTime
                NumberOfMissedRuns = $task.NumberOfMissedRuns
                Author = $task.Author
                Description = $task.Description
                Triggers = $task.Triggers
                Actions = $task.Actions
            }

            $entity = [WSEntity]::new('ScheduledTask', $task.TaskName, "ScheduledTask$($task.TaskPath)$($task.TaskName)", $props)
            $entities.Add($entity) | Out-Null
        }

        return $entities.ToArray()
    }
}
