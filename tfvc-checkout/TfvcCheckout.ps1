[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None"
  ) 

Import-Module -DisableNameChecking "$PSScriptRoot/ps_modules/VstsTfvcShared/VstsTfvcShared.psm1"
Write-Message -Type "Verbose""Entering script $($MyInvocation.MyCommand.Name)"
Write-Message -Type "Verbose""Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

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