[cmdletbinding()]
param() 

#Import-Module VstsTaskSdk
Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Default "Full"               
$SkipNonGated         = Get-VstsInput -Name SkipNonGated         -Default $true         -AsBool
$AutoDetectAdds       = Get-VstsInput -Name AutoDetectAdds       -Default $false        -AsBool
$AutoDetectDeletes    = Get-VstsInput -Name AutoDetectDeletes    -Default $false        -AsBool

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"

[string[]] $FilesToCheckin = $ItemSpec -split "(;|\r?\n)"
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Try
{
    $provider = Get-SourceProvider
    
    $IsShelvesetBuild = (Get-VstsTaskVariable -Name "Build.SourceTfvcShelveset") -ne ""
    $shelvesets = @()

    if ($IsShelvesetBuild)
    {
        $BuildId = Get-VstsTaskVariable -Name "Build.BuildId"
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