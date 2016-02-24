[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [Parameter(Mandatory=$true)]
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [string] $Detect = $true
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

[string[]] $FilesToDelete = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Output "Deleting ItemSpec: $ItemSpec, Recursive: $RecursionType, Auto-detect: $Detect"

Try
{
    $provider = Get-SourceProvider

    if ($Detect -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToDelete) -RecursionType $RecursionType -ChangeType "Delete"
    }
    else
    {
        Foreach ($delete in $FilesToDelete)
        {

            $provider.Workspace.PendDelete(
                @($delete),
                $RecursionType,
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $true,
                $true
            )  | Out-Null
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}