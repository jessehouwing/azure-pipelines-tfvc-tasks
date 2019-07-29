[cmdletbinding()]
param() 

#Import-Module VstsTaskSdk
Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Require
$DeleteAdds           = Get-VstsInput -Name DeleteAdds           -Default $false         -AsBool

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"

[string[]] $FilesToUndo = $ItemSpec -split ';|\r?\n'
    
Write-Message "Undo ItemSpec: $ItemSpec, Recursive: $Recursion, Delete Adds: $DeleteAdds"

Try
{
    $provider = Get-SourceProvider
    
    [array] $ItemSpecs = Convert-ToItemSpecs -Paths $FilesToUndo -RecursionType $Recursion

    # Pending any deleted files to ensure they're picked up by Undo.
    AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToUndo) -RecursionType $Recursion -ChangeType "Delete" | Out-Null

    Write-Message "Undoing:"
    $ItemSpecs | %{ Write-Message $_.Item }

    $provider.Workspace.Undo(
        @($ItemSpecs),
        $true,                 # updateDisk,
        $DeleteAdds -eq $true, # deleteAdds,
        @(),                   # itemAttributeFilters,
        @()                    # itemPropertyFilters
    )  | Out-Null
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}