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
Write-Output $FilesToCheckin
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Output "Update gated changes. ItemSpec: $ItemSpec, Recursive: $RecursionType, Skip Non-gated: $SkipNonGated."

Try
{
    $provider = Get-SourceProvider
    $owner = $provider.VersionControlServer.AuthorizedIdentity.UniqueName

    if ($ShelvesetOption -eq "Build")
    {
        $ShelvesetName = Get-TaskVariable $distributedTaskContext "Build.SourceTfvcShelveset"
        if ($ShelvesetName -eq "")
        {
            if ($SkipNonGated -eq $true)
            {
                Write-Output "Not a gated build. Skipping."
                exit
            }
            else
            {
                throw "Not a gated build."
            }
        }

        $BuildId = Get-TaskVariable $distributedTaskContext "Build.BuildId"
        $ShelvesetName = "_Build_$BuildId"
    }

    if ($AutoDetectAdds -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Add"
    }

    if ($AutoDetectDeletes -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Delete"
    }

    $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]]@($FilesToCheckin), $RecursionType )

    [Microsoft.TeamFoundation.VersionControl.Client.Shelveset[]]$shelvesets = @($provider.VersionControlServer.QueryShelvesets($ShelvesetName, $owner))

    switch ($shelvesets.Count)
    {
        1{
            Write-Output "Updating shelveset '$ShelvesetName;$owner' with local changes."
            
            $shelveset = $shelvesets[0]
            $provider.Workspace.Shelve($shelveset, @($pendingChanges), [Microsoft.TeamFoundation.VersionControl.Client.ShelvingOptions]"Replace");
            Write-Output "Done."
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}