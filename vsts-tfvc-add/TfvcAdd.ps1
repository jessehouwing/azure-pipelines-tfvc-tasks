[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [ValidateSet($true, $false, "")]
    [string] $Recursive,
    [string] $ApplyLocalitemExclusions = $true
) 

Write-Verbose "Entering script $MyInvocation.MyCommand.Name"
Write-Verbose "Parameter Values"
foreach($key in $PSBoundParameters.Keys)
{
    Write-Verbose ($key + ' = ' + $PSBoundParameters[$key])
}

Write-Verbose "Importing modules"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common" 
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1" 

#Backwards compatiblity for the old boolean parameter
if ($recursive -ne "")
{
    Write-Warning "Detected old parameter convention for Recursive. Please update build task configuration."
    if ($recursive)
    {
        $Recursion = "Full"
    }
    else
    {
        $Recursion = "None"
    }
    Write-Verbose "Auto-corrected to: $Recursion"
}

[string[]] $FilesToAdd = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion

Write-Output "Adding ItemSpec: $ItemSpec, Recursive: $recursive, Apply Ignorefile: $ApplyLocalitemExclusions"

Try
{
    $provider = Get-SourceProvider

    AutoPend-Workspacechanges -Provider $provider -Items @($FilesToAdd) -RecursionType $RecursionType -ChangeType "Add" -ApplyLocalitemExclusions ($ApplyLocalitemExclusions -eq $true)
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}