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
$vssCredential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($vssCredential)"))
$header = @{authorization = "Bearer $vssCredential"}

function get-timeline 
{
    [cmdletbinding()]
    param(
        $run
    )


}

function get-jobs 
{
    [cmdletbinding()]
    param(
        $timeline
    )


}

function get-hostname 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )

    return $currentHostname
}

function hasfinished-checkout 
{
    [cmdletbinding()]
    param(
        $timeline,
        $job
    )

    return true;
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
    return $false
}

while (must-yield)
{
    Write-Message "Waiting 15 seconds..."
    Start-Sleep -seconds 15
}
