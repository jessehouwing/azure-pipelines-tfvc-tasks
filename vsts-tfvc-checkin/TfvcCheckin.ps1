[cmdletbinding()]
param(
    [string] $Comment = "",
    [string] $IncludeNoCIComment = $true,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $Itemspec = "$/*",
    [Parameter(Mandatory=$true)]
    [ValidateSet("None", "Full", "OneLevel")]
    [string] $Recursion = "Full",
    [Parameter(Mandatory=$true)]
    [string] $ConfirmUnderstand = $false,
    [string] $OverridePolicy = $false,
    [string] $OverridePolicyReason = "",
    [string] $Notes = "",

    [string] $AutoDetectAdds = $false,
    [string] $AutoDetectDeletes = $false
)

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-tfvc-shared.psm1"

if (-not ($ConfirmUnderstand -eq $true))
{
    Write-Error "Checking in sources during build can cause delays in your builds, recursive builds, mismatches between sources and symbols and other issues."
}

Function Evaluate-Checkin {
    [cmdletbinding()]
    param(
        $checkinWorkspace, 
        $checkinEvaluationOptions, 
        $allChanges, 
        $checkinChanges, 
        $comment, 
        $note, 
        $checkedWorkitems,
        [ref] $passed
    )

    Write-Verbose "Entering Evaluate-Checkin"
    Try
    {
        $passed = $true
        $result = $checkinWorkspace.EvaluateCheckin2($checkinEvaluationOptions, $allChanges, $checkinChanges, $comment, $checkinNotes, $checkedWorkItems);
        if ($result.Conflicts.Length -ne 0)
        {
            $passed = $false
            foreach ($conflict in $result.Conflicts)
            {
                if ($conflict.Resolvable)
                {
                    Write-Warning $conflict.Message
                }
                else
                {
                    Write-Error $conflict.Message
                }
            }
        }
        if ($result.NoteFailures.Count -ne 0)
        {
            foreach ($noteFailure in $result.NoteFailures)
            {
                Write-Warning "$($noteFailure.Definition.Name): $($noteFailure.Message)"
            }
            $passed = $false;
        }
        if ($result.PolicyEvaluationException -ne $null)
        {
            Write-Error($result.PolicyEvaluationException.Message);
            $passed = $false;
        }
        return $result
    }
    Finally
    {
        Write-Verbose "Leaving Evaluate-Checkin"
    }
}

Function Handle-PolicyOverride {
    [cmdletbinding()]
    param(
        [Microsoft.TeamFoundation.VersionControl.Client.PolicyFailure[]] $policyFailures, 
        [string] $overrideComment,
        [ref] $passed
    )

    Write-Verbose "Entering Handle-PolicyOverride"

    Try
    {
        $passed = $true

        if ($policyFailures.Length -ne 0)
        {
            foreach ($failure in $policyFailures)
            {
                Write-Warning "$($failure.Message)"
            }
            if ($overrideComment -ne "")
            {
                return new-object Microsoft.TeamFoundation.VersionControl.Client.PolicyOverrideInfo( $overrideComment, $policyFailures )
            }
            $passed = $false
        }
        return $null
    }
    Finally
    {
        Write-Verbose "Leaving Handle-PolicyOverride"
    }
}

function Parse-CheckinNotes {
    [cmdletbinding()]
    param(
        [string] $Notes
    )
    [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]] $fieldValues = (($notes -split "\s*(?:;|\r?\n)\s*") | ForEach {
        [string[]] $note = $_ -split "\s*[:=]\s*"

        if ($note.Count -ne 2)
        {
            Write-Error "Unable to parse checkin note"
            return $null
        }

        return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue($note[0].Trim(), $note[1].Trim())
    } | ?{$_ -ne $null} )

    if ($fieldValues.Length -gt 0)
    {
        return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNote(,$fieldValues)
    }
}

Try
{
    $noCiComment = "**NO_CI**"
    if ($IncludeNoCIComment -eq $true)
    {
        if ($Comment -eq "")
        {
            $Comment = $noCiComment
        }
        else
        {
            $Comment = "$Comment $noCiComment"
        }
    }
       
    $provider = Get-SourceProvider

    $RecursionType = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]$Recursion

    [string[]] $FilesToCheckin = $ItemSpec -split "(;|\r?\n)"
    Write-Output $FilesToCheckin

    if ($AutoDetectAdds -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Add"
    }

    if ($AutoDetectDeletes -eq $true)
    {
        AutoPend-WorkspaceChanges -Provider $provider -Items @($FilesToCheckin) -RecursionType $RecursionType -ChangeType "Delete"
    }
        
    $pendingChanges = $provider.Workspace.GetPendingChanges( [string[]]@($FilesToCheckin), $RecursionType )
    
    if ($Notes -ne $null -and $Notes.Trim() -ne "")
    {
        $CheckinNotes = Parse-CheckinNotes $Notes
    }

    $passed = [ref] $true

    if ($pendingChanges.Length -gt 0)
    {

        $evaluationOptions = [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"AddMissingFieldValues" -bor [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"Notes" -bor [Microsoft.TeamFoundation.VersionControl.Client.CheckinEvaluationOptions]"Policies"
        $result = Evaluate-Checkin $provider.Workspace $evaluationOptions $pendingChanges $pendingChanges $comment $CheckinNotes $null $passed
 
        if (($passed -eq $false) -and $OverridePolicy)
        {   
            $override = Handle-PolicyOverride $result.PolicyFailures $OverridePolicyReason $passed
        }

        if (($override -eq $null) -or $OverridePolicy)
        {
            Write-Verbose "Entering Workspace-Checkin"
            $changeset = $provider.Workspace.CheckIn($pendingChanges, $Comment, [Microsoft.TeamFoundation.VersionControl.Client.CheckinNote]$CheckinNotes, [Microsoft.TeamFoundation.VersionControl.Client.WorkItemCheckinInfo[]]$null, [Microsoft.TeamFoundation.VersionControl.Client.PolicyOverrideInfo]$override)
            Write-Output "Checked in changeset: $changeset"
            Write-Verbose "Leaving Workspace-Checkin"
        }
        else
        {
            Write-Error "Checkin policy failed"
        }
    }
    else
    {
        Write-Output "No changes to check in"
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}



