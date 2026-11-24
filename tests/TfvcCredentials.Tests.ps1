param(
    [Parameter(Mandatory = $true)]
    [string]$OMDirectory,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Legacy', 'Modern')]
    [string]$ExpectedModel,
    [switch]$Live
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\tf-vc-shared\v3\ps_modules\VstsTfvcShared\VstsTfvcShared.psm1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-TfvcClientCredentials'
}, $false)
. ([scriptblock]::Create($function.Extent.Text))

foreach ($name in @('Newtonsoft.Json', 'Microsoft.VisualStudio.Services.Common', 'Microsoft.TeamFoundation.Client')) {
    [Reflection.Assembly]::LoadFrom((Join-Path $OMDirectory "$name.dll")) | Out-Null
}

function Find-VisualStudio { return $OMDirectory }
function Load-Assembly {
    param($name)
    # Returning the loaded assembly exercises the already-loaded branch of the real helper.
    return [Reflection.Assembly]::LoadFrom((Join-Path $OMDirectory "$name.dll"))
}
function Get-VstsEndpoint {
    param($Name, [switch]$Require)
    if ($Name -ne 'SystemVssConnection' -or -not $Require) { throw 'Incorrect endpoint request.' }
    return @{ Auth = @{ Parameters = @{ AccessToken = $script:accessToken } } }
}
function Get-VstsTfsClientCredentials {
    param($OMDirectory)
    $script:legacyCalled = $true
    $credential = New-Object Microsoft.TeamFoundation.Client.TfsClientCredentials($false)
    $credential.AllowInteractive = $false
    $credential.Federated = New-Object Microsoft.TeamFoundation.Client.OAuthTokenCredential($script:accessToken)
    return $credential
}

$script:accessToken = 'test-token'
$script:legacyCalled = $false
$credential = Get-TfvcClientCredentials
if ($ExpectedModel -eq 'Legacy') {
    if (-not $script:legacyCalled -or $credential.GetType().FullName -ne 'Microsoft.TeamFoundation.Client.TfsClientCredentials') {
        throw 'Expected the existing legacy credential path.'
    }
} else {
    if ($script:legacyCalled -or $credential.GetType().FullName -ne 'Microsoft.VisualStudio.Services.Common.VssCredentials') {
        throw 'Expected a single modern VssCredentials object.'
    }
    if ($credential.Federated.GetType().FullName -ne 'Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential') {
        throw 'Expected an OAuth bearer credential.'
    }
    $flags = [Reflection.BindingFlags]'Instance,NonPublic,Public'
    $token = $credential.Federated.GetType().GetProperty('InitialToken', $flags).GetValue($credential.Federated, $null)
    if ($token.Value -ne $script:accessToken) { throw 'The job token was not preserved.' }
    if ($credential.PromptType -ne [Microsoft.VisualStudio.Services.Common.CredentialPromptType]::DoNotPrompt) {
        throw 'Interactive authentication must be disabled.'
    }
    $script:accessToken = ''
    try {
        $null = Get-TfvcClientCredentials
        throw 'A missing token was accepted.'
    } catch {
        if ($_.Exception.Message -ne 'SystemVssConnection does not contain an access token.') { throw }
    }
}

$collection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollection]::new(
    [uri]'https://example.invalid/collection', $credential)
if ($null -eq $collection) { throw 'Collection construction failed.' }
Write-Host "$ExpectedModel credential and collection construction passed."

if ($Live) {
    if ([string]::IsNullOrWhiteSpace($env:TFVC_LIVE_ACCESS_TOKEN)) {
        throw 'TFVC_LIVE_ACCESS_TOKEN is required for the live authentication test.'
    }
    $script:accessToken = $env:TFVC_LIVE_ACCESS_TOKEN
    Remove-Item Env:\TFVC_LIVE_ACCESS_TOKEN
    $liveCredentials = Get-TfvcClientCredentials
    $liveCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollection]::new(
        [uri]'https://dev.azure.com/jessehouwing/', $liveCredentials)
    try {
        $liveCollection.EnsureAuthenticated()
        if (-not $liveCollection.HasAuthenticated) { throw 'The collection did not authenticate.' }
        Write-Host 'Live collection authentication passed.'
    }
    finally {
        $liveCollection.Dispose()
    }
}
