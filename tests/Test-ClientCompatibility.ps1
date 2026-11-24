param([switch]$Live)

$ErrorActionPreference = 'Stop'
if ($Live -and [string]::IsNullOrWhiteSpace($env:TFVC_LIVE_ACCESS_TOKEN)) {
    throw 'TFVC_LIVE_ACCESS_TOKEN is required for the live compatibility matrix.'
}
$versions = @(
    @{ Version = '14.102.0'; Model = 'Legacy' }
    @{ Version = '15.131.2'; Model = 'Modern' }
    @{ Version = '16.205.3'; Model = 'Modern' }
    @{ Version = '19.225.2'; Model = 'Modern' }
    @{ Version = '20.256.2'; Model = 'Modern' }
)

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfvc-compatibility-" + [Guid]::NewGuid().ToString('n'))
New-Item -Path $tempRoot -ItemType Directory | Out-Null
try {
    foreach ($client in $versions) {
        $version = $client.Version
        $output = Join-Path $tempRoot $version
        $intermediate = (Join-Path $tempRoot "$version-obj") + [System.IO.Path]::DirectorySeparatorChar
        Write-Host "Checking Extended Client $version"
        & dotnet build (Join-Path $PSScriptRoot 'ExtendedClient.Compatibility.csproj') --configuration Release --output $output "-p:BaseIntermediateOutputPath=$intermediate" "-p:ExtendedClientVersion=$version" --nologo
        if ($LASTEXITCODE -ne 0) { throw "Failed to restore Extended Client $version." }

        $testArguments = @(
            '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'TfvcCredentials.Tests.ps1'),
            '-OMDirectory', $output, '-ExpectedModel', $client.Model
        )
        if ($Live) { $testArguments += '-Live' }
        & powershell.exe @testArguments
        if ($LASTEXITCODE -ne 0) { throw "Credential compatibility failed for Extended Client $version." }
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
