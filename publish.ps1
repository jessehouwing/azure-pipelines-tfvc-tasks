[cmdletbinding()]
param(
    [string[]] $Items = @(".\vsts-tfvc-add", ".\vsts-tfvc-checkin"),
    [switch] $Force = $false
)

$patchMarkerName = "task.json.lastpatched"
$uploadMarkerName = "task.json.lastuploaded"
$packagedMarkerName = ".lastpackaged"

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

function Package-Extension
{
    $result = $false

    $patch = $Force -or {
       $item = Get-ChildItem *.* -Recurse | ?{ -not ("$($_.Name)" -eq "$packagedMarkerName") } | Sort {$_.LastWriteTime} | select -last 1
       return -not ("$($item.Name)" -eq "$packagedMarkerName")
    }

    if ($patch)
    {
        $extensionJson = ConvertFrom-Json (Get-Content ".\extension-manifest.json" -Raw)
        $Version = [System.Version]::Parse($extensionJson.Version)
        $Version = New-Object System.Version -ArgumentList $Version.Major, $Version.Minor, ($Version.Build + 1)
        $extensionJson.Version = $Version.ToString(3)
        $extensionJson | ConvertTo-JSON -Depth 255 | Out-File  ".\extension-manifest.json" -Force -Encoding ascii
        New-Item -Path . -Name $packagedMarkerName -ItemType File -Force | Out-Null
        $result = $true

        Write-Output "Updated version to $($extensionJson.Version)"
    }
    
    return $result
    tfx extension create --root . --publisher jessehouwing --extensionid jessehouwing-vsts-tfvc-tasks --output-path . --manifest-globs extension-manifest.json
}

$updated = false
foreach ($Item in $Items)
{

    if (Test-Path $Item)
    {
        Write-Output "Processing: $Item"
        $taskUpdated = Update-Version -TaskPath $item
        $updated = $updated -or $taskUpdated
        if ($taskUpdated)
        {
            $published = Publish-Task -TaskPath $Item
        }
    }
    else
    {
        Write-Error "Path not found: $Item"
    }
}

if ($updated)
{
    $packaged = Package-Extension
}