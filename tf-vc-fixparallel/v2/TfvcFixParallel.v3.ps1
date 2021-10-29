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

function get-jobs 
{
    [cmdletbinding()]
    param(
        $timeline
    )
    Write-VstsTaskDebug  ("Entering: get-jobs")
    $jobs = $timeline.records | ?{ $_.type -eq "Job" }
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
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -eq "Initialize job") -and ($_.state  -eq "completed") })
    
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
    $runs = (get-runs -top 50).Value

    foreach ($run in $runs)
    {
        if (-not (is-tfvcbuild -run $run))
        {
            return $false;
        }

        $timeline = get-timeline -run $run
        $jobs = get-jobs -timeline $timeline

        foreach ($job in $jobs)
        {
            $isHosted = is-hostedjob $job
            Write-VstsTaskDebug "IsHosted: $isHosted"
            if ($isHosted)
            {
                $hasCheckout = has-checkout -job $job -timeline $timeline
                Write-VstsTaskDebug "HasCheckout: $hasCheckout"

                if ((-not ($run.Id -eq $buildId -and $job.id -eq $jobId)) -and $hasCheckout)
                {
                    $hostname = get-hostname -timeline $timeline -job $job
                    Write-VstsTaskDebug "Hostname: $hostname"
                    if ($hostname -eq "")
                    {
                        # in case we're uncertain, it's better to wait.
                        Write-VstsTaskWarning "Job with an undetermined hostname. Waiting 15 seconds..."
                        return $true
                    }

                    if ($hostname -eq $currentHostname)
                    {
                        $finishedCheckout = hasfinished-checkout -timeline $timeline -job $job
                        Write-VstsTaskDebug "Finished Checkout: $finishedCheckout"
                        if (-not $finishedCheckout)
                        {
                            if ($run.Id -lt $buildId -or ($run.Id -eq $buildId -and $job.id -lt $jobId))
                            {
                                Write-VstsTaskWarning "Two agents with the same hostname detected. Waiting 15 seconds..."
                                return $true
                            }
                        }
                    }
                }
            }
        }
    }
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
    $jobAttempt = Get-VstsTaskVariable -Name "System.JobAttempt" -Require
    $agentId = Get-VstsTaskVariable -Name "Agent.Id" -Require
    $teamProject = Get-VstsTaskVariable -Name "System.TeamProject" -Require
    $header = @{authorization = "Bearer $vssCredential"}

    while (must-yield)
    {
        Start-Sleep -seconds 15
    }
}

Write-Host "##vso[task.complete result=Succeeded;]"