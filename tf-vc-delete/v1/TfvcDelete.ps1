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

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1"

[string[]] $FilesToDelete = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion
    
Write-Output "Deleting ItemSpec: $ItemSpec, Recursive: $RecursionType, Auto-detect: $Detect"

Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }

    if ($Detect -eq $true)
    {
        Write-Debug "Auto-Detect enabled"
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToDelete) -RecursionType $RecursionType -ChangeType "Delete"
    }
    else
    {
        Write-Debug "Auto-Detect disabled"
        
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