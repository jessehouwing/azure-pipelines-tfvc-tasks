$repositoryKind = Get-VstsTaskVariable -Name "Build.Repository.Provider"

function get-runs
{
    [cmdletbinding()]
    param(
        $top
    )
    Write-VstsTaskDebug  ("Entering: get-runs")
    return Invoke-RestMethod -Uri "$org$teamProject/_apis/build/Builds?statusFilter=inProgress&`$top=$top" -Method Get -ContentType "application/json" -Headers $header
}

function get-timeline 
{
    [cmdletbinding()]
    param(
        $runId
    )
    Write-VstsTaskDebug  ("Entering: get-timeline")
    $url = "$org$teamProject/_apis/build/builds/$runId/Timeline"
    return Invoke-RestMethod -Uri $url -Method Get -ContentType "application/json" -Headers $header 
}

function get-inprogressjobs 
{
    [cmdletbinding()]
    param(
        $timeline
    )
    Write-VstsTaskDebug  ("Entering: get-jobs")
    return $timeline.records | ?{ ($_.type -eq "Job") -and ($_.state -eq "inProgress") }
}

function get-self
{
    [cmdletbinding()]
    param(
        $timeline
    )
    Write-VstsTaskDebug  ("Entering: get-self")
    return @($timeline.records | ?{ ($_.type -eq "Job") -and ($_.state -eq "inProgress") -and ($_.id -eq $jobId) })[0]
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

            return @{ 
                AgentMachineName = (($log | Select-string -Pattern "(?<=Agent.MachineName:)[^\r\n]*").Matches[0].Value)
                AgentAgentId = (($log | Select-string -Pattern "(?<=Agent.AgentId:)[^\r\n]*").Matches[0].Value)
                SystemServerType = (($log | Select-string -Pattern "(?<=System.ServerType:)[^\r\n]*").Matches[0].Value)
                BuildRepositoryTfvcWorkspace = (($log | Select-string -Pattern "(?<=Build.Repository.Tfvc.Workspace:)[^\r\n]*").Matches[0].Value)
            }
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
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($null -eq $_.task) })
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
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($null -eq $_.task) -and ($_.state  -eq "completed") })
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
    $tasks = @($timeline.records | ?{ ($_.parentId -eq $job.id) -and ($_.type -eq "Task") -and ($_.name -like "Checkout *") -and ($null -eq $_.task) -and ($_.state  -eq "inProgress") })
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

    if (-not $self)
    {
        $ownTimeline = get-timeline -run $buildId
        $self = get-self -timeline $ownTimeline
    }

    foreach ($run in $runs)
    {
        if (-not (is-tfvcbuild -run $run))
        {
            return $false;
        }

        $timeline = get-timeline -run $run.id
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
                    Write-VstsTaskDebug "Their Hostname: '$hostname', mine: '$currentHostname'"

                    $hostnameConflict = $hostname -eq $currentHostname
                    $workspaceConflict = $metadata.BuildRepositoryTfvcWorkspace -eq $desiredWorkspace
                    Write-VstsTaskDebug "Their Workspace: '$($metadata.BuildRepositoryTfvcWorkspace)', mine: '$desiredWorkspace'"

                    if ($hostnameConflict -or $workspaceConflict)
                    {
                        $finishedCheckout = hasfinished-checkout -timeline $timeline -job $job
                        Write-VstsTaskDebug "Finished Checkout: $finishedCheckout"
                        
                        if (-not $finishedCheckout)
                        {
                            $isCheckingOut = is-checkingout -timeline $timeline -job $job
                            Write-VstsTaskDebug "Is checking out: $isCheckingOut"

                            Write-VstsTaskDebug "Their StartTime: '$($job.startTime)', mine: '$($self.startTime)'"
                            Write-VstsTaskDebug "Their BuildId: '$($run.id)', mine: '$buildId'"
                            Write-VstsTaskDebug "Their Job Order: '$($self.order)', mine: '$($job.order)'"

                            Write-VstsTaskDebug "Their: $($job | ConvertTo-Json)"
                            Write-VstsTaskDebug "Mine:  $($self | ConvertTo-Json)"
                            
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
                                Start-Sleep -seconds 20
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
            Start-Sleep -seconds 10
        }        
    } until (-not $mustyield)
}

if ($repositoryKind -eq "TfsVersionControl")
{
    $self = $null
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
    $agentHomeDirectory = Get-VstsTaskVariable -Name "Agent.HomeDirectory" -Require

    wait-whenyielding
    start-sleep 10
    wait-whenyielding

    if ((Get-VstsTaskVariable -Name "TryTfCleanUp") -eq "true")
    {
        Write-Host "Cleaning up workspaces..."
        $tf = [System.IO.Path]::Combine($agentHomeDirectory, "externals", "tf", "tf.exe")
        [xml] $workspaces = & $tf vc workspaces $desiredWorkspace /computer:* /format:xml /collection:$org /loginType:OAuth /login:.,$vssCredential /noprompt

        foreach ($workspace in @($workspaces.Workspaces))
        {
            if (-not [System.String]::IsNullOrWhiteSpace($workspace)){
                Write-Host "Deleting: $desiredWorkspace;$($workspace.ownerid)"
                & $tf vc workspace /delete "$desiredWorkspace;$($workspace.ownerid)" /collection:$org /loginType:OAuth /login:.,$vssCredential /noprompt
            }
        }
    }
}

Write-Host "##vso[task.complete result=Succeeded;]"
