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

Write-Output "Adding ItemSpec: $ItemSpec, Recursive: $RecursionType, Apply Ignorefile: $ApplyLocalitemExclusions"

Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }

    if (-not $ApplyLocalitemExclusions)
    {
        AutoPend-Workspacechanges -Provider $provider -Items @($FilesToAdd) -RecursionType $RecursionType -ChangeType "Add"
    }
    else
    {
        if ($RecursionType -eq "OneLevel")
        {
            Write-Error "RecursionType OneLevel is not supported when ignoring local item exclusions."
            return
        }

        Foreach ($change in $FilesToAdd)
        {
            Write-Output "Pending Add: $change"

            $provider.Workspace.PendAdd(
                @($change),
                $RecursionType -eq "Full",
                $null,
                [Microsoft.TeamFoundation.VersionControl.Client.LockLevel]"Unchanged",
                $false,
                $false,
                ($ApplyLocalitemExclusions -eq $true)
            )  | Out-Null
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}