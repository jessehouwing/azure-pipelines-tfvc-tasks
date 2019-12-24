import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

Write-Warning ("Version 1.x of this task is deprecated. Please update to 2.x before logging any issues.")

function Load-Assembly {
    [cmdletbinding()]
    param(
        [string] $name,
        [array] $ProbingPaths = @()
    )

    if ($ProbingPaths.Length -eq 0)
    {
        Write-Debug "Setting default assembly locations"

        if ($env:AGENT_HOMEDIRECTORY -ne $null )
        {
            $ProbingPaths += (Join-Path $env:AGENT_HOMEDIRECTORY "\Agent\Worker\")
        } 
        if ($env:AGENT_SERVEROMDIRECTORY -ne $null)
        {
            $ProbingPaths += $env:AGENT_SERVEROMDIRECTORY
        }

        $VS1464Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1464Path -ne $null)
        {
            $ProbingPaths += (Join-Path $VS1464Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\")
        }

        $VS1432Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1432Path -ne $null)
        {
            $ProbingPaths += (Join-Path $VS1432Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\")
        }
    }

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
        $path = [System.IO.Path]::Combine($path, "$($assemblyToLoad.Name).dll")
        if (Test-Path -PathType Leaf -LiteralPath $path)
        {
            if ([System.Reflection.AssemblyName]::GetAssemblyName($path).Name -eq $assemblyToLoad.Name)
            {
                Write-Debug "Loading assembly: $path"
                $assembly = [System.Reflection.Assembly]::LoadFrom($path)
                return;
            }
        }
    }

    throw "Could not load assembly: $Name"
}

Load-Assembly "Microsoft.TeamFoundation.Client"
Load-Assembly "Microsoft.TeamFoundation.Common"
Load-Assembly "Microsoft.TeamFoundation.VersionControl.Client"
Load-Assembly "Microsoft.TeamFoundation.WorkItemTracking.Client"
Load-Assembly "Microsoft.TeamFoundation.Diff"

$OnNonFatalError = [Microsoft.TeamFoundation.VersionControl.Client.ExceptionEventHandler] {
    param($sender, $e)

    if ($e.Exception -ne $null -and $e.Exception.Message -ne $null)
    {
        Write-Warning  $e.Exception.Message
    }
    if ($e.Failure -ne $null -and $e.Failure.Message -ne $null)
    {
        Write-Warning  $e.Failure.Message
        if ($e.Failure.Warnings -ne $null -and $e.Failure.Warnings.Length -gt 0)
        {
            foreach ($warning in $e.Failure.Warnings)
            {
                Write-Warning $warning.ParentOrChildTask
            }
        }
    }
}

function Get-SourceProvider {
    [cmdletbinding()]
    param()

    Write-Debug "Entering Get-SourceProvider"
    $provider = @{
        Name = $env:BUILD_REPOSITORY_PROVIDER
        SourcesRootPath = $env:BUILD_SOURCESDIRECTORY
        TeamProjectId = $env:SYSTEM_TEAMPROJECTID
    }
    $success = $false
    try {
        if ($provider.Name -eq 'TfsVersionControl') {
			$RepositoryName = $env:BUILD_REPOSITORY_NAME
			if ($env:BUILD_REPOSITORY_NAME -eq '')
			{
				$RepositoryName = $env:SYSTEM_TEAMPROJECT
			}
            $serviceEndpoint = Get-ServiceEndpoint -Context $distributedTaskContext -Name $RepositoryName
            $tfsClientCredentials = Get-TfsClientCredentials -ServiceEndpoint $serviceEndpoint

            $provider.TfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
                $serviceEndpoint.Url,
                $tfsClientCredentials)

            $versionControlServer = $provider.TfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
            $versionControlServer.add_NonFatalError($OnNonFatalError)

            $workstation = [Microsoft.TeamFoundation.VersionControl.Client.Workstation]::Current
            $workstation.EnsureUpdateWorkspaceInfoCache($versionControlServer, $versionControlServer.AuthorizedUser)
            
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
                Write-Warning ("Unable to determine workspace from source folder $($provider.SourcesRootPath).")
                return
            }

            if ($provider.Workspace.Location -eq "Server")
            {
                Write-Warning "Server workspace support is experimental."
            }

            $provider.Workspace.Refresh()

            $success = $true
            return New-Object psobject -Property $provider
        }

        Write-Warning ("Only TfsVersionControl source providers are supported for TFVC tasks. Repository type: $provider")
        return
    } finally {
        if (!$success) {
            Invoke-DisposeSourceProvider -Provider $provider
        }
        Write-Debug "Leaving Get-SourceProvider"
    }

}

function Invoke-DisposeSourceProvider {
    [cmdletbinding()]
    param($Provider)
    
    Write-Debug "Entering Invoke-DisposeSourceProvider"

    if ($Provider)
    {
        if ($Provider.VersionControlServer)
        {
            $Provider.VersionControlServer.remove_NonFatalError($OnNonFatalError)
        }

        if ($Provider.TfsTeamProjectCollection) {
            Write-Verbose 'Disposing tfsTeamProjectCollection'
            $Provider.TfsTeamProjectCollection.Dispose()
            $Provider.TfsTeamProjectCollection = $null
        }
    }

    Write-Debug "Leaving Invoke-DisposeSourceProvider"
}

function Detect-WorkspaceChanges {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Provider,
        [Parameter(Mandatory=$true)]
        [array] $Items,
        [Parameter(Mandatory=$true)]
        [Microsoft.TeamFoundation.VersionControl.Client.RecursionType] $RecursionType,
        [Microsoft.TeamFoundation.VersionControl.Client.ChangeType] $ChangeType
    )

    Write-Debug "Entering Detect-WorkspaceChanges"

    try
    {
        $AllWorkspaceChanges = @()
        $ItemSpecs = @( Convert-ToItemSpecs -Paths $Items -RecursionType $RecursionType )

        $provider.Workspace.Refresh()
        $CurrentPendingChanges = $provider.Workspace.GetPendingChanges([Microsoft.TeamFoundation.VersionControl.Client.ItemSpec[]]$ItemSpecs, $false)
        $workspaceChanges = $provider.Workspace.GetPendingChangesWithCandidates($ItemSpecs, $false, [ref] $AllWorkspaceChanges)

        $detectedChanges = $AllWorkspaceChanges | Where-Object { $CurrentPendingChanges.ServerItem -notcontains $_.ServerItem } | Where-Object { (($_.ChangeType -band $ChangeType) -eq $ChangeType) -and $_.IsCandidate} 
        
        return $detectedChanges | %{ $_.ServerItem }
    }
    finally
    {
        Write-Debug "Leaving Detect-WorkspaceChanges"    
    }
}

function AutoPend-WorkspaceChanges {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Provider,
        [Parameter(Mandatory=$true)]
        [array] $Items,
        [Parameter(Mandatory=$true)]
        [Microsoft.TeamFoundation.VersionControl.Client.RecursionType] $RecursionType,
        [Microsoft.TeamFoundation.VersionControl.Client.ChangeType] $ChangeType
    )

    Write-Debug "Entering AutoPend-WorkspaceChanges"

    $DetectedChanges = @(Detect-WorkspaceChanges -Provider $Provider -Items $Items -RecursionType $RecursionType -ChangeType $Changetype)

    if ($DetectedChanges.Length -le 0)
    {
        Write-Output "No $ChangeType detected."
        return
    }

    Write-Output "Pending $($ChangeType): "
    $DetectedChanges | %{ Write-output $_ }

    switch ($ChangeType) 
    { 
        "Delete"
        {
            $provider.Workspace.PendDelete(
                $DetectedChanges,
                [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]"None",
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $true,
                $true
            )  |Out-Null
        }

        "Add"
        {
            $provider.Workspace.PendAdd(
                $DetectedChanges,
                $false, #recursive
                $null,  
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $false, 
                $false, #silent
                $true #ApplyLocalItemExclusions, Since GetPendingChangesWithCandidates ignores these anyway.
            )  |Out-Null
        }

        default 
        {
            Write-Error "Unsupported auto-pend operation: $ChangeType"
        }
    }
    
    Write-Debug "Leaving AutoPend-WorkspaceChanges"
}

function Convert-ToItemSpecs {
    param (
        [array] $Paths = @(),
        [Microsoft.TeamFoundation.VersionControl.Client.RecursionType] $RecursionType = "None"
    )

    return @([Microsoft.TeamFoundation.VersionControl.Client.ItemSpec]::FromStrings($Paths, $RecursionType))
}

Export-ModuleMember -Function Invoke-DisposeSourceProvider
Export-ModuleMember -Function Get-SourceProvider
Export-ModuleMember -Function AutoPend-WorkspaceChanges
Export-ModuleMember -Function Convert-ToItemSpecs
