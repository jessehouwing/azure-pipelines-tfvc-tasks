[cmdletbinding()]
param(
    [string[]] $Items = @(".\vsts-tfvc-add", ".\vsts-tfvc-checkin"),
    [switch] $Force = $false
)

$patchMarkerName = "task.json.lastpatched"
$uploadMarkerName = "task.json.lastuploaded"

cd -Path $PSScriptRoot

if ($Force)
{
    Write-Warning "Force specified"
}

function Update-Version
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $TaskPath
    )

    $result = $false

    $patch = $Force -or {
       $item = Get-ChildItem $TaskPath\*.* -Recurse | ?{ -not ("$($_.Name)" -eq "$uploadMarkerName") } | Sort {$_.LastWriteTime} | select -last 1
       return -not ("$($item.Name)" -eq "$patchMarkerName")
    }

    if ($patch)
    {
        $taskJson = ConvertFrom-Json (Get-Content "$TaskPath\task.json" -Raw)
        $taskJson.Version.Patch = $taskJson.Version.Patch + 1
        $taskjson | ConvertTo-JSON -Depth 255 | Out-File  "$TaskPath\task.json" -Force -Encoding ascii
        New-Item -Path $TaskPath -Name $patchMarkerName -ItemType File -Force | Out-Null
        $result = $true

        Write-Output "Updated version to $($taskJson.Version)"
    }
    
    return $result
}

function Publish-Task
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $TaskPath
    )

    $result = $false
    $publish = $Force -or {
        $item = Get-ChildItem $TaskPath -Recurse | Sort {$_.LastWriteTime} | select -last 1
        return -not ("$($item.Name)" -eq "$uploadMarkerName")
    }

    if ($publish)
    {
        tfx build tasks upload --task-path $TaskPath
        New-Item -Path $TaskPath -Name $uploadMarkerName -ItemType File -Force | Out-Null
        $result = $true

        Write-Output Published
    }
    
    return $result
}

foreach ($Item in $Items)
{
    if (Test-Path $Item)
    {
        Write-Output "Processing: $Item"
        if (Update-Version -TaskPath $item)
        {
            $publushed = Publish-Task -TaskPath $Item
        }
    }
    else
    {
        Write-Error "Path not found: $Item"
    }
}