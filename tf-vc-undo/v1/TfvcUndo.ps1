[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/",
    [Parameter(Mandatory=$true)]
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "None",
    [Parameter(Mandatory=$false)]
    [ValidateSet("true", "false")]
    [string] $DeleteAdds = $false
)

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1"

[string[]] $FilesToUndo = $ItemSpec -split ';|\r?\n'
    
Write-Output "Undo ItemSpec: $ItemSpec, Recursive: $Recursion, Delete Adds: $DeleteAdds"

Try
{
    $provider = Get-SourceProvider
    if (-not $provider)
    {
        return;
    }
    
    [array] $ItemSpecs = Convert-ToItemSpecs -Paths $FilesToUndo -RecursionType $Recursion

    # Pending any deleted files to ensure they're picked up by Undo.
    AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToUndo) -RecursionType $Recursion -ChangeType "Delete" | Out-Null

    Write-Output "Undoing:"
    $ItemSpecs | %{ Write-Output $_.Item }

    $provider.Workspace.Undo(
        @($ItemSpecs),
        $true,                 # updateDisk,
        $DeleteAdds -eq $true, # deleteAdds,
        @(),                   # itemAttributeFilters,
        @()                    # itemPropertyFilters
    )  | Out-Null
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}