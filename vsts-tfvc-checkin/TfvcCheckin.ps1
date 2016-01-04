[cmdletbinding()]
param(
    [string] $Comment = "",
    [string] $IncludeNoCIComment = $true,
    [string] $Itemspec = "**\*;-:**\bin\**;-:**\obj\**;-:**\`$tf\**",
    [string] $Recursion = "Full"
)

Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.Client.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.Common.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$env:AGENT_HOMEDIRECTORY\Agent\Worker\Microsoft.TeamFoundation.VersionControl.Client.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.TeamFoundation.WorkItemTracking.Client.dll") | Out-Null



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
        if ($provider.Name -eq 'TfsGit') {
            $provider.CollectionUrl = "$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI".TrimEnd('/')
            $provider.RepoId = $env:BUILD_REPOSITORY_ID
            $provider.CommitId = $env:BUILD_SOURCEVERSION
            $success = $true
            return New-Object psobject -Property $provider
        }
        
        if ($provider.Name -eq 'TfsVersionControl') {
            $serviceEndpoint = Get-ServiceEndpoint -Context $distributedTaskContext -Name $env:BUILD_REPOSITORY_NAME
            $tfsClientCredentials = Get-TfsClientCredentials -ServiceEndpoint $serviceEndpoint
            
            $provider.TfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
                $serviceEndpoint.Url,
                $tfsClientCredentials)
            $versionControlServer = $provider.TfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
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

$provider = Get-SourceProvider

if (-not $Recursion -eq "")
{
    $RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
}
else
{
    $RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]"None"
}

#not ideal as it operates against the local filesystem and can't 
if (-not $Itemspec -eq "")
{
    if ($ItemSpec.Contains("*") -Or $ItemSpec.Contains("?") -Or $ItemSpec.Contains(";") -Or $ItemSpec.Contains("-:"))
    {
        Write-Verbose "Pattern found in itemspec parameter. Calling Find-Files."
        Write-Verbose "Calling Find-Files with pattern: $ItemSpec"    
        [string[]] $FilesToCheckin = @(Find-Files -SearchPattern $ItemSpec -RootFolder $env:BUILD_SOURCESDIRECTORY -IncludeFiles $true -IncludeFolders $true )
    }
    else
    {
        Write-Verbose "No Pattern found in solution parameter."
        [string[]] $FilesToCheckin = @($ItemSpec)
    }

    $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]] @($FilesToCheckin), $RecursionType )
}
else
{
    $pendingChanges = $provider.Workspace.GetPendingChanges($RecursionType)
}



$provider.Workspace.CheckIn($pendingChanges, $Comment)

Invoke-DisposeSourceProvider -Provider $provider