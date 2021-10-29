[cmdletbinding()]
param()

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

function get-hostname 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )
    Write-VstsTaskDebug  ("Entering: get-hostname")
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -eq "Initialize job") -and ($_.state -eq "completed") })
    
    if ($tasks.Length -gt 0)
    {
        $url = $tasks[0].log.url
        if (-not "$url" -eq "")
        {
            $log = (Invoke-WebRequest -Uri $url -Headers $header -UseBasicParsing).Content

            if ($log.Contains("Agent machine name: "))
            {
                $machineName = ($log | Select-string -Pattern "(?<=Agent machine name:\s+')[^']*").Matches[0].Value
                return $machineName
            }
        }
    }
    return ""
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

function is-hostedjob
{
    [cmdletbinding()]
    param(
        $job
    )
    Write-VstsTaskDebug  ("Entering: is-hostedjob")

    if ($job.workerName -like "Azure Pipelines*" -or
        $job.workerName -like "Hosted*")
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
        $jobs = get-inprogressjobs -timeline $timeline
        $self = $jobs | ?{ $_.id = $jobId }

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

                $isHosted = is-hostedjob -job $job
                
                Write-VstsTaskDebug "IsHosted: $isHosted"
                if ($isHosted)
                {
                    $hostname = get-hostname -timeline $timeline -job $job
                    Write-VstsTaskDebug "Hostname: $hostname"
                    if ("$hostname" -eq "")
                    {
                        # in case we're uncertain, it's better to wait.
                        Write-VstsTaskDebug "Job with an undetermined hostname..."
                        return $true
                    }

                    if ($hostname -eq $currentHostname)
                    {
                        $finishedCheckout = hasfinished-checkout -timeline $timeline -job $job
                        Write-VstsTaskDebug "Finished Checkout: $finishedCheckout"
                        
                        if (-not $finishedCheckout)
                        {
                            $isCheckingOut = is-checkingout -timeline $timeline -job $job
                            if ($isCheckingOut -or ($run.Id -lt $buildId -or ($run.Id -eq $buildId -and $job.startTime -lt $self.startTime)))
                            {
                                Write-VstsTaskWarning "Another job running is on '$currentHostname'..."
                                return $true
                            }
                        }
                    }
                }
            }
        }
    }
    Write-VstsTaskDebug "Taking right of way..."
    return $false
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
    $header = @{authorization = "Bearer $vssCredential"}

    while (must-yield)
    {
        Start-Sleep -seconds 15
    }
}

Write-Host "##vso[task.complete result=Succeeded;]"
