[cmdletbinding()]
param(
    [string] $Itemspec = "$/",
    [string] $Recursive = $false,
    [string] $ApplyLocalitemExclusions = $true
)


Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

$OnAssemblyResolve = [System.ResolveEventHandler] {
    param($sender, $e)
    foreach($a in [System.AppDomain]::CurrentDomain.GetAssemblies())
    {
        if ($a.FullName -eq $e.Name)
        {
            return $a
        }
    }

    if ($path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder) {
         $path = $path.TrimEnd('\'[0]) + "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\" + $e.Name + ".dll"
        if (Test-Path -PathType Leaf -LiteralPath $path)
        {
            Write-Debug "Loading assembly: $path"
            return [System.Reflection.Assembly]::LoadFrom($path)
        }
    }

    return $null
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)


[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.Client.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.Common.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.VersionControl.Client.dll")| Out-Null
[System.Reflection.Assembly]::Load("Microsoft.TeamFoundation.WorkItemTracking.Client") | Out-Null
[System.Reflection.Assembly]::Load("Microsoft.TeamFoundation.Diff") | Out-Null

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

        Write-Warning (Get-LocalizedString -Key 'Only TfsGit and TfsVersionControl source providers are supported for source indexing. Repository type: {0}' -ArgumentList $provider)
        Write-Warning (Get-LocalizedString -Key 'Unable to index sources.')
        return
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

Try
{
    $provider = Get-SourceProvider

    if (-not $Recursive -eq $true)
    {
        $Recursive = $false
    }
    else
    {
        $Recursive = $true
    }

    if (-not $ApplyLocalitemExclusions -eq $true)
    {
        $ApplyLocalitemExclusions = $false
    }
    else
    {
        $ApplyLocalitemExclusions = $true
    }

    $OnNonFatalError = [Microsoft.TeamFoundation.VersionControl.Client.ExceptionEventHandler] {
        param($sender, $e)

        Write-Warning "NonFatalError"
        Write-Warning  $e.Exception.Message
        Write-Warning  $e.Failure
    }
    $provider.VersionControlServer.add_NonFatalError($OnNonFatalError)

    $provider.Workspace.Refresh()

    Write-Output "Adding ItemSpec: $ItemSpec, Recursive: $recursive"

    if (-not $Itemspec -eq "")
    {
        [string[]] $FilesToCheckin = $ItemSpec -split ';|\r?\n'
    }

    Foreach ($change in $FilesToCheckin)
    {
        $provider.Workspace.PendAdd(
            @($change),
            $Recursive,
            $null,
            [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
            $false,
            $true,
            $ApplyLocalitemExclusions
        )  | Out-Null
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
    [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($OnAssemblyResolve)
}