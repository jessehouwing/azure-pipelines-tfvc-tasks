[cmdletbinding()]
param()

#Import-Module VstsTaskSdk

$Itemspec                   = Get-VstsInput -Name ItemSpec                   -Default "$/" 
$Recursion                  = Get-VstsInput -Name Recursion                  -Default "None"
$Recursive                  = Get-VstsInput -Name Recursive                  -Default $false        -AsBool
$ApplyLocalitemExclusions   = Get-VstsInput -Name ApplyLocalitemExclusions   -Default $false        -AsBool

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"

#Backwards compatiblity for the old boolean parameter
if ($recursive -ne "")
{
    Write-Message -Type "Warning"  "Detected old parameter convention for Recursive. Please update build task configuration."
    if ($recursive)
    {
        $Recursion = "Full"
    }
    else
    {
        $Recursion = "None"
    }
    Write-Message -Type "Verbose" "Auto-corrected to: $Recursion"
}

[string[]] $FilesToAdd = $ItemSpec -split ';|\r?\n'
$RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion

Write-Message "Adding ItemSpec: $ItemSpec, Recursive: $RecursionType, Apply Ignorefile: $ApplyLocalitemExclusions"

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
            Write-Message -Type "Error"  "RecursionType OneLevel is not supported when ignoring local item exclusions."
            return
        }

        Foreach ($change in $FilesToAdd)
        {
            Write-Message "Pending Add: $change"

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