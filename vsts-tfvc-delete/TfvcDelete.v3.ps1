[cmdletbinding()]
param() 

Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

Import-Module VstsTaskSdk

$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Require
$Detect               = Get-VstsInput -Name AutoDetectAdds       -Default $true         -AsBool

Write-VstsTaskVerbose "Importing modules"
Import-Module VstsTfvcShared -DisableNameChecking

[string[]] $FilesToDelete = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Output "Deleting ItemSpec: $ItemSpec, Recursive: $RecursionType, Auto-detect: $Detect"

Try
{
    $provider = Get-SourceProvider

    if ($Detect -eq $true)
    {
        Write-VstsTaskDebug "Auto-Detect enabled"
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToDelete) -RecursionType $RecursionType -ChangeType "Delete"
    }
    else
    {
        Write-VstsTaskDebug "Auto-Detect disabled"
        
        Foreach ($change in $FilesToDelete)
        {
            Write-Output "Pending Delete: $change"

            $provider.Workspace.PendDelete(
                @($change),
                $RecursionType,
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $false,
                $true
            )  | Out-Null
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}