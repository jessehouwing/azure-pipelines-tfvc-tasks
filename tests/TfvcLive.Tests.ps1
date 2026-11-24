param(
    [Parameter(Mandatory = $true)]
    [string]$TaskDirectory,
    [uri]$CollectionUri = 'https://dev.azure.com/jessehouwing/'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:TFVC_LIVE_ACCESS_TOKEN)) {
    throw 'TFVC_LIVE_ACCESS_TOKEN is required for the live authentication test.'
}
if ($CollectionUri.Scheme -ne 'https' -or $CollectionUri.Host -ne 'dev.azure.com') {
    throw 'The live authentication test requires an HTTPS dev.azure.com collection URI.'
}

$env:ENDPOINT_URL_SYSTEMVSSCONNECTION = $CollectionUri.AbsoluteUri
$env:ENDPOINT_AUTH_SYSTEMVSSCONNECTION = @{
    scheme = 'OAuth'
    parameters = @{ AccessToken = $env:TFVC_LIVE_ACCESS_TOKEN }
} | ConvertTo-Json -Compress
$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = $CollectionUri.AbsoluteUri
Remove-Item Env:\TFVC_LIVE_ACCESS_TOKEN

Import-Module (Join-Path $TaskDirectory 'ps_modules\VstsTaskSdk\VstsTaskSdk.psd1') -ArgumentList @{ NonInteractive = 'true' }
& (Get-Module VstsTaskSdk) { Initialize-Inputs }
Import-Module (Join-Path $TaskDirectory 'ps_modules\VstsTfvcShared\VstsTfvcShared.psm1') -DisableNameChecking

$collection = Get-TfsTeamProjectCollection
try {
    if (-not $collection.HasAuthenticated) {
        throw 'The collection did not authenticate.'
    }
    Write-Host "Authenticated to $($CollectionUri.AbsoluteUri)."
}
finally {
    if ($collection) { $collection.Dispose() }
}
