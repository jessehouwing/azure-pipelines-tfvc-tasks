$repositoryKind = Get-VstsTaskVariable -Name "Build.Repository.Provider"

function get-runs
{
    [cmdletbinding()]
    param(
        $top
    )
    Write-VstsTaskDebug  ("Entering: get-runs")
    $runs = Invoke-RestMethod -Uri "$org$teamProject/_apis/build/Builds?statusFilter=inProgress&`$top=$top" -Method Get -ContentType "application/json" -Headers $header
    return $runs
}

function get-timeline 
{
    [cmdletbinding()]
    param(
        $run
    )
    Write-VstsTaskDebug  ("Entering: get-timeline")
    $runId = $run.Id
    $url = "$org$teamProject/_apis/build/builds/$runId/Timeline"
    $timeline = Invoke-RestMethod -Uri $url -Method Get -ContentType "application/json" -Headers $header 
    return $timeline
}

function get-inprogressjobs 
{
    [cmdletbinding()]
    param(
        $timeline
    )
    Write-VstsTaskDebug  ("Entering: get-jobs")
    $jobs = $timeline.records | ?{ ($_.type -eq "Job") -and ($_.state -eq "inProgress") }
    return $jobs
}

function get-self
{
    [cmdletbinding()]
    param(
        $timeline
    )
    Write-VstsTaskDebug  ("Entering: get-self")
    $job = @($timeline.records | ?{ ($_.type -eq "Job") -and ($_.state -eq "inProgress") -and ($_.id -eq $jobId) })
    return $job[0]
}

function get-additionalmetadata
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )
    Write-VstsTaskDebug  ("Entering: get-additionalmetadata")
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -eq "Pre-job: Fix parallel execution on hosted agent 1/2.") -and ($_.state -eq "completed") })
    
    if ($tasks.Length -gt 0)
    {
        $url = $tasks[0].log.url
        if (-not "$url" -eq "")
        {
            $log = (Invoke-WebRequest -Uri $url -Headers $header -UseBasicParsing).Content

            $metadata = @{ 
                AgentMachineName = (($log | Select-string -Pattern "(?<=Agent.MachineName:)[^\r\n]*").Matches[0].Value)
                AgentAgentId = (($log | Select-string -Pattern "(?<=Agent.AgentId:)[^\r\n]*").Matches[0].Value)
                SystemServerType = (($log | Select-string -Pattern "(?<=System.ServerType:)[^\r\n]*").Matches[0].Value)
                BuildRepositoryTfvcWorkspace = (($log | Select-string -Pattern "(?<=Build.Repository.Tfvc.Workspace:)[^\r\n]*").Matches[0].Value)
            }

            return $metadata
        }
    }
    return $null
}

function is-tfvcbuild
{
    [cmdletbinding()]
    param(
        $run
    )
    Write-VstsTaskDebug  ("Entering: is-tfvcbuild")
    return ($run.repository.type -eq "TfsVersionControl")
}

function has-checkout 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )
    Write-VstsTaskDebug  ("Entering: has-checkout")
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($_.task -eq $null) })
    if ($tasks.Length -gt 0)
    {
        return $true;
    }
    return $false
}

function hasfinished-checkout 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )
    Write-VstsTaskDebug  ("Entering: hasfinished-checkout")
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($_.task -eq $null) -and ($_.state  -eq "completed") })
    if ($tasks.Length -gt 0)
    {
        return $true;
    }
    return $false
}

function is-checkingout 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )
    Write-VstsTaskDebug  ("Entering: is-checkingout")
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($_.task -eq $null) -and ($_.state  -eq "inProgress") })
    if ($tasks.Length -gt 0)
    {
        return $true;
    }
    return $false
}

function is-jobtypeunknown
{
    [cmdletbinding()]
    param(
        $job
    )
    Write-VstsTaskDebug  ("Entering: is-jobtypeunknown")
    $workername = $job.workerName
    if ("$workername" -eq "")
    {
        return $true
    }
    return $false
}

function must-yield
{
    $runs = (get-runs -top 100).Value

    foreach ($run in $runs)
    {
        if (-not (is-tfvcbuild -run $run))
        {
            return $false;
        }

        $timeline = get-timeline -run $run
        $self = get-self -timeline $timeline
        $jobs = get-inprogressjobs -timeline $timeline

        foreach ($job in $jobs)
        {
            Write-VstsTaskDebug "$($run._links.web.href)&view=logs&j=$($job.id)"

            if (-not ($job.id -eq $self.id))
            {
                $isJobTypeUnknown = is-jobtypeunknown -job $job
                if ($isJobTypeUnknown)
                {
                    # in case we're uncertain, it's better to wait.
                    Write-VstsTaskDebug "Job with an undetermined agent pool..."
                    return $true
                }
                
                $metadata = get-additionalmetadata -job $job -timeline $timeline
                if (-not $metadata)
                {
                    # in case we're uncertain, it's better to wait.
                    Write-VstsTaskDebug "Waiting for job metadata..."
                    return $true
                }

                $isHosted = $metadata.SystemServerType -eq "Hosted"
                
                Write-VstsTaskDebug "IsHosted: $isHosted"
                if ($isHosted)
                {
                    $hostname = $metadata.AgentMachineName
                    Write-VstsTaskDebug "Hostname: $hostname"

                    $hostnameConflict = $hostname -eq $currentHostname
                    $workspaceConflict = $metadata.BuildRepositoryTfvcWorkspace -eq $desiredWorkspace

                    if ($hostnameConflict -or $workspaceConflict)
                    {
                        $finishedCheckout = hasfinished-checkout -timeline $timeline -job $job
                        Write-VstsTaskDebug "Finished Checkout: $finishedCheckout"
                        
                        if (-not $finishedCheckout)
                        {
                            $isCheckingOut = is-checkingout -timeline $timeline -job $job
                            Write-VstsTaskDebug "Is checking out: $isCheckingOut"

                            Write-Host "This job: IsCheckingOut: false, Start: $($self.startTime), BuildId: $buildId, JobOrder: $($self.order)."
                            Write-VstsTaskDebug ($self | ConvertTo-Json)
                            Write-Host "That job: IsCheckingOut: $isCheckingOut, Start: $($job.startTime), BuildId: $($run.id), JobOrder: $($job.order)."
                            Write-VstsTaskDebug ($job | ConvertTo-Json)

                            if (
                                    $isCheckingOut -or 
                                    ($job.startTime -lt $self.startTime) -or 
                                    ($job.startTime -eq $self.startTime -and $run.id -lt $buildId) -or
                                    ($job.startTime -eq $self.startTime -and $run.id -eq $buildId -and $job.order -lt $self.order)
                               )
                            {

                                if ($hostnameConflict) { Write-VstsTaskWarning "Another job running is on host: '$currentHostname'..." }
                                if ($workspaceConflict) { Write-VstsTaskWarning "Another job running is on workspace '$desiredWorkspace'..." }

                                Write-Host "Waiting for: $($run._links.web.href)&view=logs&j=$($job.id)"
                                return $true
                            }
                            else {
                                Write-Host "Cutting in front of: $($run._links.web.href)&view=logs&j=$($job.id)"
                            }
                        }
                    }
                }
            }
        }
    }
    Write-Host "Found no conflicting builds..."
    return $false
}

function wait-whenyielding
{
    do {
        try {
            $mustyield = must-yield
        }
        catch {
            Write-VstsTaskWarning "Error occurred checking for other jobs..."
            $mustyield = $true
        }
        if ($mustyield)
        {
            Start-Sleep -seconds 15
        }        
    } until (-not $mustyield)
}

if ($repositoryKind -eq "TfsVersionControl")
{
    $endpoint = (Get-VstsEndpoint -Name SystemVssConnection -Require)
    $vssCredential = [string]$endpoint.auth.parameters.AccessToken
    $org = Get-VstsTaskVariable -Name "System.TeamFoundationCollectionUri" -Require
    $currentHostname = Get-VstsTaskVariable -Name "Agent.MachineName" -Require
    $buildId = Get-VstsTaskVariable -Name "Build.BuildId" -Require
    $jobId = Get-VstsTaskVariable -Name "System.JobId" -Require
    $teamProject = Get-VstsTaskVariable -Name "System.TeamProject" -Require
    $agentBuildDirectory = Get-VstsTaskVariable -Name "Agent.BuildDirectory" -Require
    $agentId = Get-VstsTaskVariable -Name "Agent.Id" -Require
    $desiredWorkspace = "ws_$(Split-Path $agentBuildDirectory -leaf)_$agentId"
    $header = @{authorization = "Bearer $vssCredential"}

    wait-whenyielding
    start-sleep 10
    wait-whenyielding
}

Write-Host "##vso[task.complete result=Succeeded;]"
