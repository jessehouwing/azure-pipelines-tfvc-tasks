[cmdletbinding()]
param(
    [string] $Itemspec = "$/",
    [string] $Recursive = $false,
    [string] $ApplyLocalitemExclusions = $true
) 


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

        $VS14Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS14Path -ne $null)
        {
            $ProbingPaths.Add((Join-Path $VS14Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\"))
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

    foreach ($path in $ProbingPaths)
    {
        Write-Debug "Checking in $path"

        $path = [System.IO.Path]::Combine($path, "$($Name).dll")
        Write-Debug "Looking for $path"
        if (Test-Path -PathType Leaf -LiteralPath $path)
        {
            Write-Debug "Found assembly: $path"
            if ([System.Reflection.AssemblyName]::GetAssemblyName($path).Name -eq $Name)
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
    $provider.VersionControlServer.remove_NonFatalError($OnNonFatalError)
    Invoke-DisposeSourceProvider -Provider $provider
}