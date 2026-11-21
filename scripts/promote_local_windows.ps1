param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if ($env:COMMON_APP_DEV -ne $project -or -not $env:COMMON_APP_RELEASE -or
    $env:COMMON_APP_DATA_MODE -ne 'portable') {
    throw 'Run via common-apps manager after validating the Windows candidate.'
}
$candidate = Join-Path $project 'build\candidate'
$app = Get-Item -LiteralPath (Join-Path $candidate "app\$Version")
$distribution = Get-Item -LiteralPath $env:COMMON_APP_RELEASE
$installer = Join-Path $candidate "dist\MediaScaler-$Version-windows-setup.exe"
$destination = Join-Path $distribution.FullName "Windows-$Version"
$setup = Join-Path $app.FullName 'Media Scaler Setup.exe'
$runtime = Join-Path $app.FullName 'runtime.json'
$exeInfo = (Get-Item -LiteralPath (Join-Path $app.FullName 'Media Scaler.exe')).VersionInfo
$setupInfo = (Get-Item -LiteralPath $installer).VersionInfo
if ($app.LinkType -or $distribution.LinkType -or
    $exeInfo.ProductName -ne 'Media Scaler' -or $exeInfo.ProductVersion -ne $Version -or
    $setupInfo.ProductName.Trim() -ne 'Media Scaler' -or $setupInfo.ProductVersion.Trim() -ne $Version -or
    (Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $setup) -or
    -not (Test-Path -LiteralPath $runtime -PathType Leaf)) {
    throw 'Candidate could not be promoted safely.'
}
$config = Get-Content -LiteralPath $runtime -Raw | ConvertFrom-Json -AsHashtable
if ($config.id -ne $env:COMMON_APP_ID -or $config.data_mode -ne 'portable') {
    throw 'Unexpected candidate runtime configuration.'
}
$originalRuntime = [IO.File]::ReadAllBytes($runtime)
$config.data_relative = [IO.Path]::GetRelativePath($destination, $env:COMMON_APP_DATA)
[IO.File]::Move($installer, $setup)
try {
    $config | ConvertTo-Json | Set-Content -LiteralPath $runtime -Encoding utf8
    [IO.Directory]::Move($app.FullName, $destination)
} catch {
    [IO.File]::Move($setup, $installer)
    [IO.File]::WriteAllBytes($runtime, $originalRuntime)
    throw
}
$destination
