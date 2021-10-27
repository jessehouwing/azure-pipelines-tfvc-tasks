[cmdletbinding()]
param()

$endpoint = (Get-VstsEndpoint -Name SystemVssConnection -Require)
$vssCredential = [string]$endpoint.auth.parameters.AccessToken
$org = Get-VstsTaskVariable -Name "System.TeamFoundationCollectionUri" -Require
$currentHostname = Get-VstsTaskVariable -Name "Agent.MachineName" -Require
$buildId = Get-VstsTaskVariable -Name "Build.BuildId" -Require
$jobId = Get-VstsTaskVariable -Name "System.JobId" -Require
$jobAttempt = Get-VstsTaskVariable -Name "System.JobAttempt" -Require
$teamProject = Get-VstsTaskVariable -Name "System.TeamProject" -Require

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

    $url = $run._links.timeline.href
    $timeline = Invoke-RestMethod -Uri $url -Method Get -ContentType "application/json" -Headers $header | ConvertFrom-Json 
    return $timeline
}

function get-jobs 
{
    [cmdletbinding()]
    param(
        $timeline
    )

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

    $tasks = $timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -eq "Initialize job") -and ($_.state  -eq "completed") }
    
    if ($tasks)
    {
        $url = $tasks[0].log.url
        $log = Invoke-WebRequest -Uri $url -Headers $header

        if ($log.Contains("Agent machine name"))
        {
            $log -match ("(?<=Agent machine name:\s+')[^']*")
            return $Matches[0]
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

    $tasks = $timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($_.task -eq $null) }
    if ($tasks)
    {
        return true;
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

    $initTasks = $timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($_.task -eq $null) -and ($_.state  -eq "completed") }
    if ($initTasks)
    {
        return true;
    }
    return $false
}

function must-yield
{
    $runsRaw = & az pipelines runs list --org $org --status inProgress --project $teamProject --top 25
    $runs = $runsRaw | ConvertFrom-Json 

    foreach ($run in $runs)
    {
        $timeline = get-timeline -run $run
        $jobs = get-jobs -timeline $timeline

        foreach ($job in $jobs)
        {
            if ((-not ($run.Id -eq $buildId -and $job.id -eq $jobId)) -and (has-checkout -job $job -timeline $timeline))
            {
                $hostname = get-hostname -timeline $timeline -job $job
                if ($hostname -eq $currentHostname)
                {
                    $finishedCheckout = hasfinished-checkout -timeline $timeline -job $job

                    if (-not $finishedCheckout)
                    {
                        if ($run.Id -lt $buildId -or ($run.Id -eq $buildId -and $job.id -lt $jobId))
                        {
                            return $true
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
    Write-Message "Waiting 15 seconds..."
    Start-Sleep -seconds 15
}
