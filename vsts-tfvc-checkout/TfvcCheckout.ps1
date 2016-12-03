[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [ValidateSet($true, $false, "")]
    [string] $Recursive, #For backwards compatibility reasons
    [string] $ApplyLocalitemExclusions = $true
) 

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1" 

[string[]] $FilesToCheckout = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion

Write-Output "Checking out ItemSpec: $ItemSpec, Recursive: $RecursionType"

Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }

    Foreach ($change in $FilesToCheckout)
    {
        Write-Output "Checkign out: $change"
        
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