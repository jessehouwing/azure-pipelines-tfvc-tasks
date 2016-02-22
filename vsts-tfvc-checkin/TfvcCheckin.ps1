[cmdletbinding()]
param(
    [string] $Comment = "",
    [string] $IncludeNoCIComment = $true,
    [string] $Itemspec = "$/*",
    [string] $Recursion = "Full",
    [string] $ConfirmUnderstand = $false,
    [string] $OverridePolicy = $false,
    [string] $OverridePolicyReason = "",
    [string] $Notes = ""
)

if (-not ($ConfirmUnderstand -eq $true))
{
    Write-Error "Checking in sources during build can cause delays in your builds, recursive builds, mismatches between sources and symbols and other issues."
}

Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

function Load-Assembly
{
    [cmdletbinding()]
    param(
        [string] $name,
        [string[]] $ProbingPathsArgs
    )

    $ProbingPaths = New-Object System.Collections.ArrayList $ProbingPathsArgs
    if ($ProbingPaths.Count -eq 0)
    {
        Write-Debug "Setting default assembly locations"

        if ($PSScriptRoot -ne $null )
        {
            $ProbingPaths.Add($PSScriptRoot) 
        }
        if ($env:AGENT_HOMEDIRECTORY -ne $null )
        {
            $ProbingPaths.Add((Join-Path $env:AGENT_HOMEDIRECTORY "\Agent\Worker\"))
        } 
        if ($env:AGENT_SERVEROMDIRECTORY -ne $null)
        {
            $ProbingPaths.Add($env:AGENT_SERVEROMDIRECTORY)
        }

        $VS1454Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1464Path -ne $null)
        {
            $ProbingPaths.Add((Join-Path $VS1464Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\"))
        }

        $VS1432Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1432Path -ne $null)
        {
            $ProbingPaths.Add((Join-Path $VS1432Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\"))
        }
    }

    Write-Debug "Resolving $a"

    foreach($a in [System.AppDomain]::CurrentDomain.GetAssemblies())
    {
        if ($a.Name -eq $Name)
        {
            return $a
        }
    }

    $assemblyToLoad = New-Object System.Reflection.AssemblyName $name
    

    foreach ($path in $ProbingPaths)
    {
        Write-Debug "Checking in $path"

        $path = [System.IO.Path]::Combine($path, "$($assemblyToLoad.Name).dll")
        Write-Debug "Looking for $path"
        if (Test-Path -PathType Leaf -LiteralPath $path)
        {
            Write-Debug "Found assembly: $path"
            if ([System.Reflection.AssemblyName]::GetAssemblyName($path).Name -eq $assemblyToLoad.Name)
            {
                Write-Debug "Loading assembly: $path"
                return [System.Reflection.Assembly]::LoadFrom($path)
            }
            else
            {
                Write-Debug "Name Mismatch: $path"
            }
        }
        else
        {
            Write-Debug "Not found: $Name"
        }
    }

    return $null
}

Load-Assembly "Microsoft.TeamFoundation.Client"
Load-Assembly "Microsoft.TeamFoundation.Common"
Load-Assembly "Microsoft.TeamFoundation.VersionControl.Client"
Load-Assembly "Microsoft.TeamFoundation.WorkItemTracking.Client"
Load-Assembly "Microsoft.TeamFoundation.Diff"

function Get-SourceProvider {
    [cmdletbinding()]
    param()

    $provider = @{
        Name = $env:BUILD_REPOSITORY_PROVIDER
        SourcesRootPath = $env:BUILD_SOURCESDIRECTORY
        TeamProjectId = $env:SYSTEM_TEAMPROJECTID
    }
    $success = $false
    try {
        if ($provider.Name -eq 'TfsVersionControl') {
            $serviceEndpoint = Get-ServiceEndpoint -Context $distributedTaskContext -Name $env:BUILD_REPOSITORY_NAME
            $tfsClientCredentials = Get-TfsClientCredentials -ServiceEndpoint $serviceEndpoint
            
            $provider.TfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
                $serviceEndpoint.Url,
                $tfsClientCredentials)
            $versionControlServer = $provider.TfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
            $provider.VersionControlServer = $versionControlServer;
            $provider.Workspace = $versionControlServer.TryGetWorkspace($provider.SourcesRootPath)
            if (!$provider.Workspace) {
                Write-Verbose "Unable to determine workspace from source folder: $($provider.SourcesRootPath)"
                Write-Verbose "Attempting to resolve workspace recursively from locally cached info."
                $workspaceInfos = [Microsoft.TeamFoundation.VersionControl.Client.Workstation]::Current.GetLocalWorkspaceInfoRecursively($provider.SourcesRootPath);
                if ($workspaceInfos) {
                    foreach ($workspaceInfo in $workspaceInfos) {
                        Write-Verbose "Cached workspace info discovered. Server URI: $($workspaceInfo.ServerUri) ; Name: $($workspaceInfo.Name) ; Owner Name: $($workspaceInfo.OwnerName)"
                        try {
                            $provider.Workspace = $versionControlServer.GetWorkspace($workspaceInfo)
                            break
                        } catch {
                            Write-Verbose "Determination failed. Exception: $_"
                        }
                    }
                }
            }

            if ((!$provider.Workspace) -and $env:BUILD_REPOSITORY_TFVC_WORKSPACE) {
                Write-Verbose "Attempting to resolve workspace by name: $env:BUILD_REPOSITORY_TFVC_WORKSPACE"
                try {
                    $provider.Workspace = $versionControlServer.GetWorkspace($env:BUILD_REPOSITORY_TFVC_WORKSPACE, '.')
                } catch [Microsoft.TeamFoundation.VersionControl.Client.WorkspaceNotFoundException] {
                    Write-Verbose "Workspace not found."
                } catch {
                    Write-Verbose "Determination failed. Exception: $_"
                }
            }

            if (!$provider.Workspace) {
                Write-Warning (Get-LocalizedString -Key 'Unable to determine workspace from source folder ''{0}''.' -ArgumentList $provider.SourcesRootPath)
                return
            }

            $success = $true
            return New-Object psobject -Property $provider
        }

        Write-Warning ("Only TfsVersionControl source providers are supported for TFVC tasks. Repository type: $provider")        return
    } finally {
        if (!$success) {
            Invoke-DisposeSourceProvider -Provider $provider
        }
    }
}

function Invoke-DisposeSourceProvider {
    [cmdletbinding()]
    param($Provider)

    if ($Provider.TfsTeamProjectCollection) {
        Write-Verbose 'Disposing tfsTeamProjectCollection'
        $Provider.TfsTeamProjectCollection.Dispose()
        $Provider.TfsTeamProjectCollection = $null
    }
}

Function Evaluate-Checkin {
    [cmdletbinding()]
    param(
        $checkinWorkspace, 
        $checkinEvaluationOptions, 
        $allChanges, 
        $checkinChanges, 
        $comment, 
        $note, 
        $checkedWorkitems,
        [ref] $passed
    )

    Write-Verbose "Entering Evaluate-Checkin"
    Try
    {
        $passed = $true
        $result = $checkinWorkspace.EvaluateCheckin2($checkinEvaluationOptions, $allChanges, $checkinChanges, $comment, $checkinNotes, $checkedWorkItems);
        if (-not $result.Conflicts.Length -eq 0)
        {
            $passed = $false
            foreach ($conflict in $result.Conflicts)
            {
                if ($conflict.Resolvable)
                {
                    Write-Warning $conflict.Message
                }
                else
                {
                    Write-Error $conflict.Message
                }
            }
        }
        if (-not $result.NoteFailures.Count -eq 0)
        {
            foreach ($noteFailure in $result.NoteFailures)
            {
                Write-Warning "$($noteFailure.Definition.Name): $($noteFailure.Message)"
            }
            $passed = $false;
        }
        if (-not $result.PolicyEvaluationException -eq $null)
        {
            Write-Error($result.PolicyEvaluationException.Message);
            $passed = $false;
        }
        return $result
    }
    Finally
    {
        Write-Verbose "Leaving Evaluate-Checkin"
    }
}

 
Function Handle-PolicyOverride {
    [cmdletbinding()]
    param(
        [Microsoft.TeamFoundation.VersionControl.Client.PolicyFailure[]] $policyFailures, 
        [string] $overrideComment,
        [ref] $passed
    )

    Write-Verbose "Entering Handle-PolicyOverride"

    Try
    {
        $passed = $true

        if (-not $policyFailures.Length -eq 0)
        {
            foreach ($failure in $policyFailures)
            {
                Write-Warning "$($failure.Message)"
            }
            if (-not $overrideComment -eq "")
            {
                return new-object Microsoft.TeamFoundation.VersionControl.Client.PolicyOverrideInfo( $overrideComment, $policyFailures )
            }
            $passed = $false
        }
        return $null
    }
    Finally
    {
        Write-Verbose "Leaving Handle-PolicyOverride"
    }
}

function Parse-CheckinNotes
{
    [cmdletbinding()]
    param(
        [string] $Notes
    )
    [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]] $fieldValues = (($notes -split "\s*(?:;|\r?\n)\s*") | ForEach {
        [string[]] $note = $_ -split "\s*[:=]\s*"

        if ($note.Count -ne 2)
        {
            Write-Error "Unable to parse checkin note"
            return $null
        }

        return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue($note[0].Trim(), $note[1].Trim())
    } | ?{$_ -ne $null} )

    return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNote(,$fieldValues)
}

Try
{
    $noCiComment = "**NO_CI**"
    if ($IncludeNoCIComment -eq $true)
    {
        if ($Comment -eq "")
        {
            $Comment = $noCiComment
        }
        else
        {
            $Comment = "$Comment $noCiComment"
        }
    }
       
    $provider = Get-SourceProvider

    $OnNonFatalError = [Microsoft.TeamFoundation.VersionControl.Client.ExceptionEventHandler] {
        param($sender, $e)

        if ($e.Exception -ne $null -and $e.Exception.Message -ne $null)
        {
            Write-Warning  $e.Exception.Message
        }
        if ($e.Faulure -ne $null)
        {
            Write-Warning  $e.Failure.ToString()
        }
    }
    $provider.VersionControlServer.add_NonFatalError($OnNonFatalError)

    if ($Recursion -ne "")
    {
        $RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    }
    else
    {
        $RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]"None"
    }

    if ($Itemspec -ne "")
    {
        [string[]] $FilesToCheckin = $ItemSpec -split "(;|\r?\n)"
        Write-Output $FilesToCheckin
        $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]]@($FilesToCheckin), $RecursionType )
    }
    else
    {
        $pendingChanges = $provider.Workspace.GetPendingChanges($RecursionType)
    }

    if ($Notes -ne "")
    {
        $CheckinNotes = Parse-CheckinNotes $Notes
    }

    $passed = [ref] $true

    if ($pendingChanges.Length -gt 0)
    {

        $evaluationOptions = [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"AddMissingFieldValues" -bor [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"Notes" -bor [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"Policies"
        $result = Evaluate-Checkin $provider.Workspace $evaluationOptions $pendingChanges $pendingChanges $comment $CheckinNotes $null $passed
 
        if (($passed -eq $false) -and $OverridePolicy)
        {   
            $override = Handle-PolicyOverride $result.PolicyFailures $OverridePolicyReason $passed
        }

        if ($override -eq $null -or $OverridePolicy)
        {
            Write-Verbose "Entering Workspace-Checkin"
            $provider.Workspace.CheckIn($pendingChanges, $Comment, [Microsoft.TeamFoundation.VersionControl.Client.CheckinNote]$CheckinNotes, [Microsoft.TeamFoundation.VersionControl.Client.WorkItemCheckinInfo[]]$null, [Microsoft.TeamFoundation.VersionControl.Client.PolicyOverrideInfo]$override)
            Write-Verbose "Leaving Workspace-Checkin"
        }
        else
        {
            Write-Error "Checkin policy failed"
        }
    }
    else
    {
        Write-Output "No changes to check in"
    }
}
Finally
{
    $provider.VersionControlServer.remove_NonFatalError($OnNonFatalError)
    Invoke-DisposeSourceProvider -Provider $provider
}



