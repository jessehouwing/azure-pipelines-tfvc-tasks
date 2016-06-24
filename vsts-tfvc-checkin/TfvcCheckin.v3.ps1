[cmdletbinding()]
param()

Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

Import-Module VstsTaskSdk

$Comment              = Get-VstsInput -Name Comment              -Default ""
$IncludeNoCIComment   = Get-VstsInput -Name IncludeNoCIComment   -Default $true         -AsBool
$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Require               -AsBool
$ConfirmUnderstand    = Get-VstsInput -Name ConfirmUnderstand    -Require               -AsBool
$OverridePolicy       = Get-VstsInout -Name OverridePolicy       -Default $false        -AsBool
$OverridePolicyReason = Get-VstsInput -Name OverridePolicyReason -Default ""
$Noted                = Get-VstsInput -Name Notes                -Default ""
$Skipgated            = Get-VstsInput -Name SkipGated            -Default $true         -AsBool
$SkipShelveset        = Get-VstsInput -Name SkipShelveset        -Default $true         -AsBool
$AutoDetectAdds       = Get-VstsInput -Name AutoDetectAdds       -Default $false        -AsBool
$AutoDetectDeletes    = Get-VstsInput -Name AutoDetectDeletes    -Default $false        -AsBool
$BypassGatedCheckin   = Get-VstsInput -Name BypassGatedCheckin   -Default $false        -AsBool

Write-VstsTaskVerbose "Importing modules"
Import-Module VstsTfvcShared -DisableNameChecking


if (-not ($ConfirmUnderstand -eq $true))
{
    Write-VstsTaskError "Checking in sources during build can cause delays in your builds, recursive builds, mismatches between sources and symbols and other issues."
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

    Write-VstsTaskVerbose "Entering Evaluate-Checkin"
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
                    Write-VstsTaskWarning $conflict.Message
                }
                else
                {
                    Write-VstsTaskError $conflict.Message
                }
            }
        }
        if ($result.NoteFailures.Count -ne 0)
        {
            foreach ($noteFailure in $result.NoteFailures)
            {
                Write-VstsTaskWarning "$($noteFailure.Definition.Name): $($noteFailure.Message)"
            }
            $passed = $false;
        }
        if ($result.PolicyEvaluationException -ne $null)
        {
            Write-VstsTaskError($result.PolicyEvaluationException.Message);
            $passed = $false;
        }
        return $result
    }
    Finally
    {
        Write-VstsTaskVerbose "Leaving Evaluate-Checkin"
    }
}

Function Handle-PolicyOverride {
    [cmdletbinding()]
    param(
        [Microsoft.TeamFoundation.VersionControl.Client.PolicyFailure[]] $policyFailures, 
        [string] $overrideComment,
        [ref] $passed
    )

    Write-VstsTaskVerbose "Entering Handle-PolicyOverride"

    Try
    {
        $passed = $true

        if ($policyFailures.Length -ne 0)
        {
            foreach ($failure in $policyFailures)
            {
                Write-VstsTaskWarning "$($failure.Message)"
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
        Write-VstsTaskVerbose "Leaving Handle-PolicyOverride"
    }
}

function Parse-CheckinNotes {
    [cmdletbinding()]
    param(
        [string] $Notes
    )

    try
    {
        $JsonParseFailed = $false
        $ParsedNotes = ($Notes | ConvertFrom-Json)
        [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]] $fieldValues = $ParsedNotes |
            %{ Get-Member -MemberType NoteProperty -InputObject $_ | %{
                return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue([string]$_.Name.Trim(), $ParsedNotes.$($_.Name).Trim())
            }}
    }
    catch
    {
        $JsonParseFailed = $true
    }

    if ($JsonParseFailed)
    {
        [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]] $fieldValues = (($notes -split "\s*(?:;|\r?\n)\s*") | ForEach {
            [string[]] $note = $_ -split "\s*[:=]\s*"

            if ($note.Count -eq 1)
            {
                Write-VstsTaskError "Ignoring Checkin note without value"
                return $null
            }
            elseif ($note.Count -ne 2)
            {
                Write-VstsTaskError "Unable to parse checkin note"
                return $null
            }

            return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue($note[0].Trim(), $note[1].Trim())
        } | ?{$_ -ne $null} )

        Write-VstsTaskWarning "Using old Notes notation, please switch to the new Json format:"
        $ParsedNotes = "{ }" | ConvertFrom-Json
        foreach ($fieldValue in $fieldValues)
        {
            Add-Member -InputObject $ParsedNotes -NotePropertyName  $fieldValue.Name -NotePropertyValue $fieldValue.Value -Force
        }
        
        Write-VstsTaskWarning ($ParsedNotes | ConvertTo-Json -Depth 5 )
    }

    if ($fieldValues.Length -gt 0)
    {
        return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNote(,$fieldValues)
    }
}

Try
{
    $provider = Get-SourceProvider

    $BuildSourceTfvcShelveset = Get-TaskVariable $distributedTaskContext "Build.SourceTfvcShelveset"
    Write-VstsTaskDebug "Build.SourceTfvcShelveset = '$BuildSourceTfvcShelveset'."
    $IsShelvesetBuild = "$BuildSourceTfvcShelveset" -ne ""
    $IsGatedBuild = $false
    
    if ($SkipGated -eq $false -and $IsShelvesetBuild)
    {
        $Shevesets = @()
        $BuildId = Get-TaskVariable $distributedTaskContext "Build.BuildId"
        $ShelvesetName = "_Build_$BuildId"
        $Owner = $provider.VersionControlServer.AuthorizedIdentity.UniqueName

        $Shevesets += @($provider.VersionControlServer.QueryShelvesets($ShelvesetName, $Owner))
        $IsGatedBuild = ($Shevesets.Count -eq 1)
    }

    if (($SkipShelveset -eq $true) -and $IsShelvesetBuild)
    {
        Write-Output "Shelveset build. Ignoring."
    }
    elseif (($SkipGated -eq $true) -and $IsGatedBuild)
    {
        Write-Output "Gated build. Ignoring."
    }
    else
    {
        $noCiComment = "***NO_CI***"
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
                $checkInParameters = new-object Microsoft.TeamFoundation.VersionControl.Client.WorkspaceCheckInParameters(@($pendingChanges), $Comment)
                $checkinParameters.Author = $env:BUILD_QUEUEDBY
                if ($CheckinNotes -ne $null)
                {
                    $checkInParameters.CheckinNotes = $CheckinNotes
                }
                $checkInParameters.PolicyOverride = $override
                $checkInParameters.QueueBuildForGatedCheckIn = -not ($BypassGatedCheckin -eq $true)
                $checkInParameters.OverrideGatedCheckIn = ($BypassGatedCheckin -eq $true)
                $checkInParameters.AllowUnchangedContent = $false
                $checkInParameters.NoAutoResolve = $false
                #$checkInParameters.CheckinDate = Get-Date

                Write-VstsTaskVerbose "Entering Workspace-Checkin"
                $provider.VersionControlServer.StripUnsupportedCheckinOptions($checkInParameters)

                $changeset = $provider.Workspace.CheckIn($checkInParameters)
                Write-Output "Checked in changeset: $changeset"
                Write-VstsTaskVerbose "Leaving Workspace-Checkin"
            }
            else
            {
                Write-VstsTaskError "Checkin policy failed"
            }
        }
        else
        {
            Write-Output "No changes to check in"
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}



