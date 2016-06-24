[cmdletbinding()]
param() 

Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

Import-Module VstsTaskSdk

$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Require
$DeleteAdds           = Get-VstsInput -Name DeleteAdds           -Default $false         -AsBool

Write-VstsTaskVerbose "Importing modules"
Import-Module VstsTfvcShared -DisableNameChecking

[string[]] $FilesToUndo = $ItemSpec -split ';|\r?\n'
    
Write-Output "Undo ItemSpec: $ItemSpec, Recursive: $Recursion, Delete Adds: $DeleteAdds"

Try
{
    $provider = Get-SourceProvider
    
    [array] $ItemSpecs = Convert-ToItemSpecs -Paths $FilesToUndo -RecursionType $Recursion

    # Pending any deleted files to ensure they're picked up by Undo.
    AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToUndo) -RecursionType $Recursion -ChangeType "Delete" | Out-Null

    Write-Output "Undoing:"
    $ItemSpecs | %{ Write-Output $_.Item }

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