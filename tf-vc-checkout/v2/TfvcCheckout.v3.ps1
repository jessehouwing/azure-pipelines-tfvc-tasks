[cmdletbinding()]
param()

#Import-Module VstsTaskSdk
Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

$Itemspec                   = Get-VstsInput -Name ItemSpec                   -Default "$/" 
$Recursion                  = Get-VstsInput -Name Recursion                  -Default "None"

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"

[string[]] $FilesToCheckout = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion

Write-Message "Checking out ItemSpec: $ItemSpec, Recursive: $RecursionType"

Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }

    Foreach ($change in $FilesToCheckout)
    {
        Write-Message "Checking out: $change"
        
        $provider.Workspace.PendEdit(
            @($change),
            $RecursionType,
            $null,
            [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged"
        )  | Out-Null
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}