[cmdletbinding()]
param()

$endpoint = (Get-VstsEndpoint -Name SystemVssConnection -Require)
$vssCredential = [string]$endpoint.auth.parameters.AccessToken
$org = Get-VstsTaskVariable -Name "System.TeamFoundationCollectionUri" -Require
$currentHostname = Get-VstsTaskVariable -Name "Agent.MachineName" -Require
$buildId = Get-VstsTaskVariable -Name "Build.BuildId" -Require
$jobId = Get-VstsTaskVariable -Name "System.JobId" -Require
$jobAttempt = Get-VstsTaskVariable -Name "System.JobAttempt" -Require
$agentId = Get-VstsTaskVariable -Name "Agent.Id" -Require
$teamProject = Get-VstsTaskVariable -Name "System.TeamProject" -Require

#& az config set extension.use_dynamic_install=yes_without_prompt
#& az extension add --name azure-devops
#& az devops configure --defaults organization=$org project=$teamProject
$vssCredential | &  az devops login --org $org

# Create header with PAT
#$vssCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($vssCredential)"))
$header = @{authorization = "Bearer $vssCredential"}

function get-timeline 
{
    [cmdletbinding()]
    param(
        $run
    )

    $build = Invoke-RestMethod -Uri $run.url -Method Get -ContentType "application/json" -Headers $header
    $url = $build._links.timeline.href
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
    $runsRaw = & az pipelines runs list --org $org --status inProgress --project $teamProject --top 50
    $runs = $runsRaw | ConvertFrom-Json 

    foreach ($run in $runs)
    {
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

while (must-yield)
{
    Start-Sleep -seconds 15
}
