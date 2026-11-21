param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if ($env:COMMON_APP_DEV -ne $project -or -not $env:COMMON_APP_RELEASE) {
    throw 'Run via common-apps manager after validating the Windows candidate.'
}
$candidate = Join-Path $project 'build\candidate'
$app = Get-Item -LiteralPath (Join-Path $candidate "app\$Version")
$distribution = Get-Item -LiteralPath $env:COMMON_APP_RELEASE
$installer = Join-Path $candidate "dist\MediaScaler-$Version-windows-setup.exe"
$destination = Join-Path $distribution.FullName "Windows-$Version"
$setup = Join-Path $app.FullName 'Media Scaler Setup.exe'
$exeInfo = (Get-Item -LiteralPath (Join-Path $app.FullName 'Media Scaler.exe')).VersionInfo
$setupInfo = (Get-Item -LiteralPath $installer).VersionInfo
if ($app.LinkType -or $distribution.LinkType -or
    $exeInfo.ProductName -ne 'Media Scaler' -or $exeInfo.ProductVersion -ne $Version -or
    $setupInfo.ProductName.Trim() -ne 'Media Scaler' -or $setupInfo.ProductVersion.Trim() -ne $Version -or
    (Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $setup)) {
    throw 'Candidate could not be promoted safely.'
}
[IO.File]::Move($installer, $setup)
try {
    [IO.Directory]::Move($app.FullName, $destination)
} catch {
    [IO.File]::Move($setup, $installer)
    throw
}
$destination
