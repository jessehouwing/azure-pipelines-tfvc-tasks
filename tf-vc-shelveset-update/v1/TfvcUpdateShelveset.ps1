[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [Parameter(Mandatory=$true)]
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [string] $AutoDetectAdds = $false,
    [string] $AutoDetectDeletes = $false,
    [string] $SkipNonGated = $true
) 

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1"

[string[]] $FilesToCheckin = $ItemSpec -split "(;|\r?\n)"
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }
    
    $IsShelvesetBuild = (Get-TaskVariable $distributedTaskContext "Build.SourceTfvcShelveset") -ne ""
    $shevesets = @()

    if ($IsShelvesetBuild)
    {
        $BuildId = Get-TaskVariable $distributedTaskContext "Build.BuildId"
        $ShelvesetName = "_Build_$BuildId"
        $Owner = $provider.VersionControlServer.AuthorizedIdentity.UniqueName

        $shelvesets += @($provider.VersionControlServer.QueryShelvesets($ShelvesetName, $Owner))
        $IsGatedBuild = ($shelvesets.Count -eq 1)
    }

    if ($IsGatedBuild)
    {
        if ($AutoDetectAdds -eq $true)
        {
            AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Add"
        }

        if ($AutoDetectDeletes -eq $true)
        {
            AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Delete"
        }

        $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]]@($FilesToCheckin), $RecursionType )
        $shelveset = $shelvesets[0]

        Write-Output "Updating shelveset ($ShelvesetName;$Owner) with local changes."
        
        $provider.Workspace.Shelve($shelveset, @($pendingChanges), [Microsoft.TeamFoundation.VersionControl.Client.ShelvingOptions]"Replace");
        Write-Output "Done."
    }
    else
    {
        if ($SkipNonGated -eq $true)
        {
            Write-Output "Not a gated build. Ignoring."
            exit
        }
        else
        {
            throw "Not a gated build."
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}