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
            $ProbingPaths.Add($PSScriptRoot) | Out-Null
        }
        if ($env:AGENT_HOMEDIRECTORY -ne $null )
        {
            $ProbingPaths.Add((Join-Path $env:AGENT_HOMEDIRECTORY "\Agent\Worker\")) | Out-Null
        } 
        if ($env:AGENT_SERVEROMDIRECTORY -ne $null)
        {
            $ProbingPaths.Add($env:AGENT_SERVEROMDIRECTORY) | Out-Null
        }

        $VS1454Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1464Path -ne $null)
        {
            $ProbingPaths.Add((Join-Path $VS1464Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\")) | Out-Null
        }

        $VS1432Path = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0" -Name 'ShellFolder' -ErrorAction Ignore).ShellFolder
        if ($VS1432Path -ne $null)
        {
            $ProbingPaths.Add((Join-Path $VS1432Path "\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\")) | Out-Null
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
            $versionControlServer.add_NonFatalError($OnNonFatalError)
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
}

function Detect-WorkspaceChanges{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Provider,
        [Parameter(Mandatory=$true)]
        [string[]] $Items,
        [Parameter(Mandatory=$true)]
        [Microsoft.TeamFoundation.VersionControl.Client.RecursionType] $RecursionType,
        [Microsoft.TeamFoundation.VersionControl.Client.ChangeType] $ChangeType
    )

    $pendingChanges = $null
    $ItemSpecs = [Microsoft.TeamFoundation.VersionControl.Client.ItemSpec]::FromStrings(@($Items), $RecursionType)
    
    $provider.Workspace.Refresh()

    $provider.Workspace.GetPendingChangesWithCandidates($ItemSpecs, $false, [ref] $pendingChanges)
    
    return ($pendingChanges |
        ?{ $_.ChangeType -band $ChangeType } |
        Select-Object $_.ServerItem)
}

function AutoPend-WorkspaceChanges
{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Provider,
        [Parameter(Mandatory=$true)]
        [string[]] $Items,
        [Parameter(Mandatory=$true)]
        [Microsoft.TeamFoundation.VersionControl.Client.RecursionType] $RecursionType,
        [Microsoft.TeamFoundation.VersionControl.Client.ChangeType] $ChangeType,
        [Parameter(Mandatory=$false)]
        [bool] $ApplyLocalItemExclusions = $false
    )

    [string[]] $DetectedItems = Detect-WorkspaceChanges -Provider $Provider -Items @($Items) -RecursionType $RecursionType -ChangeType $Changetype
    
    if ($DetectedItems.Length -eq 0)
    {
        Write-Output "No changes detected."
        return
    }

    switch ($ChangeType) 
    { 
        "Delete"
        {
            $provider.Workspace.PendDelete(
                @($DetectedItems),
                [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]"None",
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $true,
                $true
            )  | Out-Null
        }

        "Add"
        {
            $provider.Workspace.PendAdd(
                @($DetectedItems),
                $false,
                $null,
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $false,
                $false,
                $ApplyLocalitemExclusions
            )  | Out-Null
        }

        default 
        {
            Write-Error "Unsupported auto-pend operation: $ChangeType"
        }
    }
}

Export-ModuleMember -Function Invoke-DisposeSourceProvider
Export-ModuleMember -Function Get-SourceProvider
Export-ModuleMember -Function AutoPend-WorkspaceChanges