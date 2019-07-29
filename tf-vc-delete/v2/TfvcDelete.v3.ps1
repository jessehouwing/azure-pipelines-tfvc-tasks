[cmdletbinding()]
param() 

#Import-Module VstsTaskSdk
Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Require
$Detect               = Get-VstsInput -Name AutoDetectAdds       -Default $true         -AsBool

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"

[string[]] $FilesToDelete = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Message "Deleting ItemSpec: $ItemSpec, Recursive: $RecursionType, Auto-detect: $Detect"

Try
{
    $provider = Get-SourceProvider

    if ($Detect -eq $true)
    {
        Write-Message -Type "Debug" "Auto-Detect enabled"
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToDelete) -RecursionType $RecursionType -ChangeType "Delete"
    }
    else
    {
        Write-Message -Type "Debug" "Auto-Detect disabled"
        
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