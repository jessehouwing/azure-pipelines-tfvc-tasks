Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-delete\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-add\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-undo\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-checkin\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-checkout\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-shelveset-update\v1 -force -recurse -exclude *.*proj

Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-delete\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-add\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-undo\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-checkin\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-checkout\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-shelveset-update\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\ps_modules\VstsTaskSdk\* $PSScriptRoot\tf-vc-dontsync\v2\ps_modules\VstsTaskSdk\ -force -recurse -exclude *.*proj

function Invoke-WithTls12Support {
    param([ScriptBlock]$ScriptBlock)

    $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
    if (($originalProtocol -band [Net.SecurityProtocolType]::Tls12) -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    try {
        & $ScriptBlock
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
    }
}

function Restore-PowerShellModule {
    param(
        [string]$ModuleName,
        [string]$Destination,
        [string]$TempRoot
    )

    $modulePackage = Join-Path $TempRoot "$ModuleName.nupkg"

    Invoke-WithTls12Support {
        $moduleUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName"
        Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePackage -UseBasicParsing
    }

    $extractPath = Join-Path $TempRoot "$ModuleName-module"
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }

    Expand-Archive -Path $modulePackage -DestinationPath $extractPath -Force

    Get-ChildItem -Path $extractPath -Recurse -Filter '[Content_Types].xml' -File | Remove-Item -Force

    $manifest = Get-ChildItem -Path $extractPath -Recurse -Filter "$ModuleName.psd1" | Select-Object -First 1
    if (-not $manifest) {
        throw "Module manifest '$ModuleName.psd1' was not found in the downloaded package."
    }

    $moduleSource = $manifest.Directory.FullName

    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $moduleSource '*') -Destination $Destination -Recurse -Force

    Get-ChildItem -Path $Destination -Recurse -Force -Include '_rels', 'package', '[Content_Types].xml', '*.nuspec' | ForEach-Object {
        if ($_.PSIsContainer) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        } else {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }

    $moduleLibPath = Join-Path $Destination 'lib'
    if (Test-Path $moduleLibPath) {
        Get-ChildItem -Path $moduleLibPath -Recurse -Force -Include '*.xml', '*.pdb' -File | Remove-Item -Force
        Get-ChildItem -Path $moduleLibPath -Directory | Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]{2,4})?$' } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }
}

function Update-VstsTaskSdkContent {
    [CmdletBinding()]
    param(
        [string]$ModuleDestination = (Join-Path $PSScriptRoot 'tf-vc-shared\v3\ps_modules\VstsTaskSdk')
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfvc-prebuild-" + [System.Guid]::NewGuid().ToString('n'))
    New-Item -Path $tempRoot -ItemType Directory | Out-Null

    try {
        Write-Host "Updating VstsTaskSdk in '$ModuleDestination'"
        Restore-PowerShellModule -ModuleName 'VstsTaskSdk' -Destination $ModuleDestination -TempRoot $tempRoot

        $libDestination = Join-Path $ModuleDestination 'lib'
        if (Test-Path $libDestination) {
            Remove-Item $libDestination -Recurse -Force
        }
        New-Item -Path $libDestination -ItemType Directory -Force | Out-Null

        $project = Join-Path $PSScriptRoot 'tf-vc-shared\v3\ExtendedClient.csproj'
        $intermediate = (Join-Path $tempRoot 'obj') + [System.IO.Path]::DirectorySeparatorChar
        & dotnet build $project --configuration Release --output $libDestination "-p:BaseIntermediateOutputPath=$intermediate" --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "Extended Client dependency build failed with exit code $LASTEXITCODE."
        }

        Remove-Item -LiteralPath (Join-Path $libDestination 'ExtendedClient.dll') -Force
        Get-ChildItem -Path $libDestination -Recurse -Force -Include '*.xml', '*.pdb' -File | Remove-Item -Force
        Get-ChildItem -Path $libDestination -Directory | Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]{2,4})?$' } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Update-VstsTaskSdkContent

Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-delete\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-add\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-undo\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-checkin\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-checkout\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-shelveset-update\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\ps_modules\VstsTaskSdk `
          $PSScriptRoot\tf-vc-dontsync\v3\ps_modules\ `
          -Force -Recurse -Exclude *.*proj
