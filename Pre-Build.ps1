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

function New-TemporaryDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tfvc-prebuild-" + [System.Guid]::NewGuid().ToString('n'))
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    return $path
}

function ConvertTo-NormalizedFramework {
    param([string]$Framework)

    if ([string]::IsNullOrWhiteSpace($Framework)) { return '' }

    $value = $Framework.Trim()
    if ($value -match '^net[0-9a-zA-Z]+$') {
        return $value.ToLowerInvariant()
    }

    if ($value -match '^\.NETFramework(?<version>[0-9\.]+)$') {
        $version = $Matches['version'].Replace('.', '')
        return "net$version"
    }

    if ($value -match '^\.NETStandard(?<version>[0-9\.]+)$') {
        $version = $Matches['version'].Replace('.', '')
        return "netstandard$version"
    }

    return $value.ToLowerInvariant()
}

function ConvertTo-VersionObject {
    param([string]$Version)

    $numeric = ($Version.Split('-'))[0]
    $parts = $numeric.Split('.')
    while ($parts.Count -lt 4) { $parts += '0' }
    $normalised = ($parts[0..([Math]::Min($parts.Count - 1, 3))] -join '.')
    return [Version]::Parse($normalised)
}

function Compare-Version {
    param([Version]$Left, [Version]$Right)

    return [System.Collections.Comparer]::DefaultInvariant.Compare($Left, $Right)
}

function Resolve-NuGetVersion {
    param(
        [string]$PackageId,
        [string]$VersionRange,
        [switch]$AllowPrerelease
    )

    $versions = Invoke-WithTls12Support {
        $url = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLowerInvariant())/index.json"
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing
        return @($response.versions)
    }

    $availableStable = $versions | Where-Object { $_ -and ($_ -notmatch '-') }
    $availableAll = $versions | Where-Object { $_ }

    if (-not $availableAll) {
        throw "No versions found for package '$PackageId'."
    }

    if (-not $availableStable -and -not $AllowPrerelease) {
        throw "No stable versions found for package '$PackageId'."
    }

    $sortedStable = $availableStable | Sort-Object { ConvertTo-VersionObject $_ }
    $sortedAll = $availableAll | Sort-Object { ConvertTo-VersionObject $_ }

    if ([string]::IsNullOrWhiteSpace($VersionRange)) {
        if ($AllowPrerelease) {
            return $sortedAll[-1]
        }

        return $sortedStable[-1]
    }

    $range = $VersionRange.Trim()
    if ($range -match '^\[([^\]]+)\]$') {
        return $Matches[1]
    }

    if ($range[0] -ne '[' -and $range[0] -ne '(') {
        $range = "[$range,)"
    }

    $lowerInclusive = $range.StartsWith('[')
    $upperInclusive = $range.EndsWith(']')

    $body = $range.TrimStart('(', '[').TrimEnd(')', ']')
    $parts = $body.Split(',')
    $lower = $null
    $upper = $null

    if ($parts.Count -gt 0) {
        $lowerValue = $parts[0].Trim()
        if ($lowerValue) { $lower = ConvertTo-VersionObject $lowerValue }
    }

    if ($parts.Count -gt 1) {
        $upperValue = $parts[1].Trim()
        if ($upperValue) { $upper = ConvertTo-VersionObject $upperValue }
    }

    $candidates = if ($AllowPrerelease) { $sortedAll } else { $sortedStable }

    $matching = foreach ($version in $candidates) {
        $candidate = ConvertTo-VersionObject $version

        if ($lower) {
            $cmpLower = Compare-Version $candidate $lower
            if ($cmpLower -lt 0 -or ($cmpLower -eq 0 -and -not $lowerInclusive)) {
                continue
            }
        }

        if ($upper) {
            $cmpUpper = Compare-Version $candidate $upper
            if ($cmpUpper -gt 0 -or ($cmpUpper -eq 0 -and -not $upperInclusive)) {
                continue
            }
        }

        $version
    }

    if (-not $matching) {
        throw "Could not resolve a version of '$PackageId' that satisfies the range '$VersionRange'."
    }

    return $matching | Select-Object -Last 1
}

function Expand-NuGetPackage {
    param(
        [string]$PackageId,
        [string]$Version,
        [string]$DestinationRoot
    )

    $packageFileName = "$($PackageId.ToLowerInvariant()).$Version.nupkg"
    $packageFile = Join-Path $DestinationRoot $packageFileName
    $extractPath = Join-Path $DestinationRoot "$($PackageId.ToLowerInvariant()).$Version"

    Invoke-WithTls12Support {
        $packageUrl = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLowerInvariant())/$Version/$packageFileName"
        Invoke-WebRequest -Uri $packageUrl -OutFile $packageFile -UseBasicParsing
    }

    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }

    Expand-Archive -Path $packageFile -DestinationPath $extractPath -Force
    return $extractPath
}

function Get-NuGetDependencies {
    param(
        [string]$PackageRoot,
        [string[]]$FrameworkPreference
    )

    $nuspec = Get-ChildItem -Path $PackageRoot -Filter '*.nuspec' | Select-Object -First 1
    if (-not $nuspec) { return @() }

    [xml]$nuspecContent = Get-Content -Path $nuspec.FullName
    $dependenciesNode = $nuspecContent.package.metadata.dependencies
    if (-not $dependenciesNode) { return @() }

    $groups = @()
    if ($dependenciesNode.group) {
        $groups = @($dependenciesNode.group)
    } elseif ($dependenciesNode.dependency) {
        $groups = @($dependenciesNode)
    }

    if (-not $groups) { return @() }

    $groupMap = @{}
    foreach ($group in $groups) {
        $tfm = ConvertTo-NormalizedFramework $group.targetFramework
        if (-not $groupMap.ContainsKey($tfm)) {
            $groupMap[$tfm] = @()
        }

        $items = $group.dependency
        if (-not $items) { continue }
        if ($items -isnot [System.Array]) { $items = @($items) }

        foreach ($dependency in $items) {
            if (-not $dependency.id) { continue }
            $groupMap[$tfm] += ,([PSCustomObject]@{
                    Id = $dependency.id
                    Version = $dependency.version
                })
        }
    }

    $selected = @()
    $seen = @{}

    foreach ($framework in $FrameworkPreference) {
        if (-not $groupMap.ContainsKey($framework)) { continue }

        foreach ($dependency in $groupMap[$framework]) {
            $key = $dependency.Id.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $selected += ,$dependency
            $seen[$key] = $true
        }
    }

    if (-not $selected -and $groupMap.ContainsKey('')) {
        foreach ($dependency in $groupMap['']) {
            $key = $dependency.Id.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $selected += ,$dependency
            $seen[$key] = $true
        }
    }

    if (-not $selected) {
        $firstGroup = $groupMap.GetEnumerator() | Select-Object -First 1
        if ($firstGroup) {
            foreach ($dependency in $firstGroup.Value) {
                $key = $dependency.Id.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $selected += ,$dependency
                $seen[$key] = $true
            }
        }
    }

    return $selected
}

function Copy-PackageAssemblies {
    param(
        [string]$PackageId,
        [string]$PackageRoot,
        [string]$Destination,
        [string[]]$PreferredFrameworks,
        [string[]]$FallbackFrameworks
    )

    $libRoot = Join-Path $PackageRoot 'lib'
    if (-not (Test-Path $libRoot)) { return }

    $selectedFramework = $null
    foreach ($framework in $PreferredFrameworks) {
        $candidate = Join-Path $libRoot $framework
        if (Test-Path $candidate) {
            $selectedFramework = $candidate
            break
        }
    }

    if (-not $selectedFramework) {
        foreach ($framework in $FallbackFrameworks) {
            $candidate = Join-Path $libRoot $framework
            if (Test-Path $candidate) {
                Write-Warning "Falling back to '$framework' assets for '$PackageId'."
                $selectedFramework = $candidate
                break
            }
        }
    }

    if (-not $selectedFramework) {
        Write-Warning "No compatible assets found in package '$PackageId'."
        return
    }

    Copy-Item -Path (Join-Path $selectedFramework '*') -Destination $Destination -Recurse -Force

    $runtimeRoot = Join-Path $PackageRoot 'runtimes'
    if (Test-Path $runtimeRoot) {
        Get-ChildItem -Path $runtimeRoot -Recurse -Include *.dll | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
        }
    }

    $dataStoreFiles = Get-ChildItem -Path $PackageRoot -Recurse -Include 'Microsoft.WITDataStore*.dll' -File
    foreach ($file in $dataStoreFiles) {
        $destinationName = $file.Name
        if ($destinationName -ieq 'Microsoft.WITDataStore.dll') {
            if ($file.FullName -match '(amd64|x64)') {
                $destinationName = 'Microsoft.WITDataStore64.dll'
            } elseif ($file.FullName -match '(x86|32)') {
                $destinationName = 'Microsoft.WITDataStore32.dll'
            }
        }

        Copy-Item -Path $file.FullName -Destination (Join-Path $Destination $destinationName) -Force
    }

    Get-ChildItem -Path $Destination -Recurse -Force -Include '*.xml', '*.pdb' -File | Remove-Item -Force
    Get-ChildItem -Path $Destination -Directory | Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]{2,4})?$' } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Restore-NuGetPackage {
    param(
        [string]$PackageId,
        [string]$Destination,
        [string[]]$PreferredFrameworks,
        [string[]]$FallbackFrameworks,
        [string]$TempRoot,
        [hashtable]$ResolvedPackages,
        [string]$VersionRange,
        [switch]$AllowPrerelease
    )

    if ($ResolvedPackages.ContainsKey($PackageId)) {
        return
    }

    $version = Resolve-NuGetVersion -PackageId $PackageId -VersionRange $VersionRange -AllowPrerelease:$AllowPrerelease
    $ResolvedPackages[$PackageId] = $version
    Write-Host "Restoring $PackageId $version"

    $packageRoot = Expand-NuGetPackage -PackageId $PackageId -Version $version -DestinationRoot $TempRoot

    Copy-PackageAssemblies -PackageId $PackageId -PackageRoot $packageRoot -Destination $Destination -PreferredFrameworks $PreferredFrameworks -FallbackFrameworks $FallbackFrameworks

    $dependencyFrameworks = $PreferredFrameworks + $FallbackFrameworks + @('native')
    $dependencies = Get-NuGetDependencies -PackageRoot $packageRoot -FrameworkPreference $dependencyFrameworks

    foreach ($dependency in $dependencies) {
        $isPrerelease = $AllowPrerelease -or ($dependency.Version -and $dependency.Version -match '-')
        Restore-NuGetPackage -PackageId $dependency.Id -Destination $Destination -PreferredFrameworks $PreferredFrameworks -FallbackFrameworks $FallbackFrameworks -TempRoot $TempRoot -ResolvedPackages $ResolvedPackages -VersionRange $dependency.Version -AllowPrerelease:$isPrerelease
    }

    Get-ChildItem -Path $Destination -Recurse -Force -Include '*.xml', '*.pdb' -File | Remove-Item -Force
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
        [string]$ModuleDestination = (Join-Path $PSScriptRoot 'tf-vc-shared\v3\ps_modules\VstsTaskSdk'),
        [string]$ExtendedClientPackage = 'Microsoft.TeamFoundationServer.ExtendedClient'
    )

    $preferredFrameworks = @('net472', 'net471', 'net47')
    $fallbackFrameworks = @('net462', 'net461', 'net46', 'net452', 'net451', 'net45')
    $resolvedPackages = @{}
    $tempRoot = New-TemporaryDirectory

    try {
        Write-Host "Updating VstsTaskSdk in '$ModuleDestination'"
        Restore-PowerShellModule -ModuleName 'VstsTaskSdk' -Destination $ModuleDestination -TempRoot $tempRoot

        $libDestination = Join-Path $ModuleDestination 'lib'
        if (Test-Path $libDestination) {
            Remove-Item $libDestination -Recurse -Force
        }
        New-Item -Path $libDestination -ItemType Directory -Force | Out-Null

        Restore-NuGetPackage -PackageId $ExtendedClientPackage -Destination $libDestination -PreferredFrameworks $preferredFrameworks -FallbackFrameworks $fallbackFrameworks -TempRoot $tempRoot -ResolvedPackages $resolvedPackages -VersionRange $null -AllowPrerelease
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

