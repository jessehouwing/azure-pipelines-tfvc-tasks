[cmdletbinding()]
param()

#Import-Module VstsTaskSdk
Write-VstsTaskVerbose "Entering script $($MyInvocation.MyCommand.Name)"

$Comment              = Get-VstsInput -Name Comment              -Default ""
$IncludeNoCIComment   = Get-VstsInput -Name IncludeNoCIComment   -Default $true         -AsBool
$Itemspec             = Get-VstsInput -Name ItemSpec             -Require 
$Recursion            = Get-VstsInput -Name Recursion            -Default "Full"               
$ConfirmUnderstand    = Get-VstsInput -Name ConfirmUnderstand    -Require               -AsBool
$OverridePolicy       = Get-VstsInput -Name OverridePolicy       -Default $false        -AsBool
$OverridePolicyReason = Get-VstsInput -Name OverridePolicyReason -Default ""
$Notes                = Get-VstsInput -Name Notes                -Default ""
$Skipgated            = Get-VstsInput -Name SkipGated            -Default $true         -AsBool
$SkipShelveset        = Get-VstsInput -Name SkipShelveset        -Default $true         -AsBool
$AutoDetectAdds       = Get-VstsInput -Name AutoDetectAdds       -Default $false        -AsBool
$AutoDetectDeletes    = Get-VstsInput -Name AutoDetectDeletes    -Default $false        -AsBool
$BypassGatedCheckin   = Get-VstsInput -Name BypassGatedCheckin   -Default $false        -AsBool

$Author               = Get-VstsInput -Name Author               -Default ""
$AuthorCustom         = Get-VstsInput -Name AuthorCustom         -Default ""

Import-Module ".\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1" -DisableNameChecking
Write-Message -Type "Verbose"  "Importing modules"
Write-Message -Type "Verbose"  "Entering script $($MyInvocation.MyCommand.Name)"


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

    Write-Message -Type "Verbose" "Entering Evaluate-Checkin"
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
                    Write-Message -Type "Warning" $conflict.Message
                }
                else
                {
                    Write-Message -Type "Error" $conflict.Message
                }
            }
        }
        if ($result.NoteFailures.Count -ne 0)
        {
            foreach ($noteFailure in $result.NoteFailures)
            {
                Write-Message -Type "Warning" "$($noteFailure.Definition.Name): $($noteFailure.Message)"
            }
            $passed = $false;
        }
        if ($result.PolicyEvaluationException -ne $null)
        {
            Write-Message -Type "Error" $result.PolicyEvaluationException.Message;
            $passed = $false;
        }
        return $result
    }
    Finally
    {
        Write-Message -Type "Verbose" "Leaving Evaluate-Checkin"
    }
}

Function Handle-PolicyOverride {
    [cmdletbinding()]
    param(
        [Microsoft.TeamFoundation.VersionControl.Client.PolicyFailure[]] $policyFailures, 
        [string] $overrideComment,
        [ref] $passed
    )

    Write-Message -Type "Verbose" "Entering Handle-PolicyOverride"

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
        Write-Message -Type "Verbose" "Leaving Handle-PolicyOverride"
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
        [Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue[]] $fieldValues = (($notes -split "\s*(?:;|\r?\n)\s*") | %{
            [string[]] $note = $_ -split "\s*[:=]\s*"

            if ($note.Count -eq 1)
            {
                Write-Message -Type "Error" "Ignoring Checkin note without value"
                return $null
            }
            elseif ($note.Count -ne 2)
            {
                Write-Message -Type "Error" "Unable to parse checkin note"
                return $null
            }

            return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNoteFieldValue($note[0].Trim(), $note[1].Trim())
        } | ?{$_ -ne $null} )

        Write-Message -Type "Warning" "Using old Notes notation, please switch to the new Json format:"
        $ParsedNotes = "{ }" | ConvertFrom-Json
        foreach ($fieldValue in $fieldValues)
        {
            Add-Member -InputObject $ParsedNotes -NotePropertyName  $fieldValue.Name -NotePropertyValue $fieldValue.Value -Force
        }
        
        Write-Message -Type "Warning" ($ParsedNotes | ConvertTo-Json -Depth 5 )
    }

    if ($fieldValues.Length -gt 0)
    {
        return new-object Microsoft.TeamFoundation.VersionControl.Client.CheckinNote(,$fieldValues)
    }
}

Try
{
    $provider = Get-SourceProvider

    $BuildSourceTfvcShelveset = Get-VstsTaskVariable -Name "Build.SourceTfvcShelveset"
    Write-Message -Type "Debug" "Build.SourceTfvcShelveset = '$BuildSourceTfvcShelveset'."
    $IsShelvesetBuild = "$BuildSourceTfvcShelveset" -ne ""
    $IsGatedBuild = $false
    
    if ($SkipGated -eq $false -and $IsShelvesetBuild)
    {
        $Shevesets = @()
        $BuildId = Get-VstsTaskVariable -Name "Build.BuildId"
        $ShelvesetName = "_Build_$BuildId"
        $Owner = $provider.VersionControlServer.AuthorizedIdentity.UniqueName

        $Shevesets += @($provider.VersionControlServer.QueryShelvesets($ShelvesetName, $Owner))
        $IsGatedBuild = ($Shevesets.Count -eq 1)
    }

    if (($SkipShelveset -eq $true) -and $IsShelvesetBuild)
    {
        Write-Message "Shelveset build. Ignoring."
    }
    elseif (($SkipGated -eq $true) -and $IsGatedBuild)
    {
        Write-Message "Gated build. Ignoring."
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
        Write-Message $FilesToCheckin

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
                
                switch ($Author)
				{
					"RequestedFor" { $AuthorCustom = $env:BUILD_REQUESTEDFOR }
					"RequestedForId" { $AuthorCustom = $env:BUILD_REQUESTEDFORID }
					"QueuedBy" { $AuthorCustom = $env:BUILD_QUEUEDBY }
					"QueuedById" { $AuthorCustom = $env:BUILD_QUEUEDBYID }
					"None" { $AuthorCustom = $null }
					default { $AuthorCustom = $null }
				}
				if ($AuthorCustom -ne $null)
                {
					$checkInParameters.Author = $AuthorCustom
				}
                
                if ($CheckinNotes -ne $null)
                {
                    $checkInParameters.CheckinNotes = $CheckinNotes
                }
                $checkInParameters.PolicyOverride = $override
                $checkInParameters.QueueBuildForGatedCheckIn = -not ($BypassGatedCheckin -eq $true)
                $checkInParameters.OverrideGatedCheckIn = ($BypassGatedCheckin -eq $true)
                $checkInParameters.AllowUnchangedContent = $false
                $checkInParameters.NoAutoResolve = $false

                Write-Message -Type "Verbose" "Entering Workspace-Checkin"
                $provider.VersionControlServer.StripUnsupportedCheckinOptions($checkInParameters)

                $changeset = $provider.Workspace.CheckIn($checkInParameters)
                Write-Message "Checked in changeset: $changeset"
                Write-Message -Type "Verbose" "Leaving Workspace-Checkin"
            }
            else
            {
                Write-Message -Type "Error" "Checkin policy failed"
            }
        }
        else
        {
            Write-Message "No changes to check in"
        }
    }
}
Finally
{
    Invoke-DisposeSourceProvider -Provider $provider
}



