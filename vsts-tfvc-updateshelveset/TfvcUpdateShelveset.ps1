[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [Parameter(Mandatory=$true)]
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Update", "CreateOrUpdate")]
    [string] $Mode = "CreateOrUpdate",
    [string] $ShelvesetName = $false,
    [string] $AutoDetectAdds = $false,
    [string] $AutoDetectDeletes = $false,
    [string] $SkipEmpty = $true
) 

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1"

[string[]] $FilesToCheckin = $ItemSpec -split "(;|\r?\n)"
Write-Output $FilesToCheckin
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Output "Deleting ItemSpec: $ItemSpec, Recursive: $RecursionType, Auto-detect: $Detect"

if (($SkipEmpty -ne $true) -and ($ShelvesetName -eq "" -or $ShelvesetName -contains "`$("))
{
    throw "No shelveset specified."
}

Try
{
    $provider = Get-SourceProvider

    if ($AutoDetectAdds -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Add"
    }

    if ($AutoDetectDeletes -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Delete"
    }

    $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]]@($FilesToCheckin), $RecursionType )

    if ($ShelvesetName -contains ";")
    {
        $ShelvesetParts = $ShelvesetName -split ";"
        $ShelvesetName = $ShelvesetParts[0]
        $ShelvesetOwner = $ShelvesetParts[1]
    }
    
    $shelvesets = @($provider.VersionControlServer.QueryShelvesets("$ShelvesetName", "$ShelvesetOwner"))

    switch ($shelvesets.Count)
    {
        0{
            if ($Mode -notcontains "Create")
            {
                throw "Shelveset not found."
            }

            Write-Output "Shelveset not found, creating new shelveset: '$ShelvesetName;$ShelvesetOwner'."
            $shelveset = new-object Microsoft.TeamFoundation.VersionControl.Client.Shelveset $provider.VersionControlServer $ShelvesetName $ShelvesetOwner
            $provider.Workspace.Shelve($shelveset, @($pendingChanges), [Microsoft.TeamFoundation.VersionControl.Client.ShelvingOptions]"None");
        }
        1{
            if ($Mode -notcontains "Update")
            {
                throw "Shelveset already exists."
            }

            Write-Output "Shelveset found, updating shelveset: '$ShelvesetName;$ShelvesetOwner'."
            $shelveset = $shelvesets[0]
            $provider.Workspace.Shelve($shelveset, @($pendingChanges), [Microsoft.TeamFoundation.VersionControl.Client.ShelvingOptions]"Replace");
        }
        default{
            Write-Error "Found multiple shelvesets matching: '$ShelvesetName;$ShelvesetOwner'."
            throw "Failed"
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}