param(
    [Parameter(Mandatory = $true)]
    [string]$TaskDirectory
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $TaskDirectory 'ps_modules\VstsTaskSdk\VstsTaskSdk.psd1') -ArgumentList @{ NonInteractive = 'true' }
Import-Module (Join-Path $TaskDirectory 'ps_modules\VstsTfvcShared\VstsTfvcShared.psm1') -DisableNameChecking

$items = @(Convert-ToItemSpecs -Paths @('$/project/file.txt') -RecursionType 'Full')
if ($items.Count -ne 1 -or $items[0].Item -ne '$/project/file.txt') {
    throw 'The packaged TFVC module could not construct an item specification.'
}
Write-Host 'Packaged TFVC module loaded successfully.'
