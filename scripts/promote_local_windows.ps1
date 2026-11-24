[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')][string]$Version,
    [ValidatePattern('\A(?:[0-9a-f]{12}|[0-9a-f]{40})\z')][string]$SourceSha
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if ($env:COMMON_APP_DEV -ne $project -or -not $env:COMMON_APP_RELEASE -or
    $env:COMMON_APP_DATA_MODE -ne 'portable') {
    throw 'Run via common-apps manager after validating the Windows candidate.'
}
function Get-UnlinkedItem([string]$Path) {
    $entry = Get-Item -LiteralPath $Path -Force
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint -or $entry.LinkType) {
        throw "Linked candidate or distribution path: $Path"
    }
    $entry
}
function Get-PackageVersionInfo([string]$Path) {
    $file = Get-UnlinkedItem $Path
    # The Win32 version lookup loses metadata on a long ordinary drive path.
    if ($file.FullName -match '^[A-Za-z]:\\') {
        return [Diagnostics.FileVersionInfo]::GetVersionInfo(('\\?\' + $file.FullName))
    }
    $file.VersionInfo
}
$build = Get-UnlinkedItem (Join-Path $project 'build')
$candidateName = 'candidate'
if ($PSBoundParameters.ContainsKey('SourceSha')) {
    $prefix = $SourceSha.Substring(0, 12)
    $commit = git -C $project rev-parse --verify --end-of-options "${prefix}^{commit}"
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '\A[0-9a-f]{40}\z' -or
        -not $commit.StartsWith($SourceSha, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The specified candidate commit was not found.'
    }
    $candidateName = "candidate-$($commit.Substring(0, 12))"
}
$candidate = Get-UnlinkedItem (Join-Path $build.FullName $candidateName)
$apps = Get-UnlinkedItem (Join-Path $candidate.FullName 'app')
$dist = Get-UnlinkedItem (Join-Path $candidate.FullName 'dist')
$app = Get-UnlinkedItem (Join-Path $apps.FullName $Version)
$distribution = Get-UnlinkedItem $env:COMMON_APP_RELEASE
$installer = Join-Path $dist.FullName "MediaScaler-$Version-windows-setup.exe"
$destination = Join-Path $distribution.FullName "Windows-$Version"
$setup = Join-Path $app.FullName 'Media Scaler Setup.exe'
$runtime = Join-Path $app.FullName 'runtime.json'
$exeInfo = Get-PackageVersionInfo (Join-Path $app.FullName 'Media Scaler.exe')
$setupInfo = Get-PackageVersionInfo $installer
if (
    $exeInfo.ProductName -ne 'Media Scaler' -or $exeInfo.ProductVersion -ne $Version -or
    $setupInfo.ProductName.Trim() -ne 'Media Scaler' -or $setupInfo.ProductVersion.Trim() -ne $Version -or
    (Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $setup) -or
    -not (Test-Path -LiteralPath $runtime -PathType Leaf)) {
    throw 'Candidate could not be promoted safely.'
}
if (Get-ChildItem -LiteralPath $app.FullName -Force -Recurse -Attributes ReparsePoint | Select-Object -First 1) {
    throw 'The packaged app contains a linked file or directory.'
}
$null = Get-UnlinkedItem $runtime
$config = Get-Content -LiteralPath $runtime -Raw | ConvertFrom-Json -AsHashtable
if ($config.id -ne $env:COMMON_APP_ID -or $config.data_mode -ne 'portable') {
    throw 'Unexpected candidate runtime configuration.'
}
$config.data_relative = [IO.Path]::GetRelativePath($destination, $env:COMMON_APP_DATA)
if (-not $PSCmdlet.ShouldProcess($destination, "Promote $($candidate.FullName)")) { return }

if ($SourceSha) {
    # Retain the exact tested app, runtime and installer at their SHA-addressed paths.
    $stagePath = Join-Path $build.FullName ("promotion-" + [guid]::NewGuid().ToString('N'))
    $stage = New-Item -ItemType Directory -Path $stagePath
    try {
        foreach ($entry in Get-ChildItem -LiteralPath $app.FullName -Force) {
            Copy-Item -LiteralPath $entry.FullName -Destination $stage.FullName -Recurse -Force
        }
        [IO.File]::Copy($installer, (Join-Path $stage.FullName 'Media Scaler Setup.exe'))
        $config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage.FullName 'runtime.json') -Encoding utf8
        [IO.Directory]::Move($stage.FullName, $destination)
    } finally {
        if (Test-Path -LiteralPath $stage.FullName) {
            $left = Get-Item -LiteralPath $stage.FullName
            if ($left.Parent.FullName -eq $build.FullName -and $left.FullName -eq $stagePath -and
                -not ($left.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $left.FullName -Recurse -Force
            }
        }
    }
    $destination
    return
}

$originalRuntime = [IO.File]::ReadAllBytes($runtime)
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
