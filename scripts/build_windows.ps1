param(
    [string]$Version = "",
    [string]$Iscc = "",
    [string]$OutputRoot = "",
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
# MSBuild worker processes must exit before the verification run is sealed.
$env:MSBUILDDISABLENODEREUSE = '1'
$project = Split-Path $PSScriptRoot -Parent
if (-not $Version) {
    $Version = ((Select-String '^version:' (Join-Path $project 'pubspec.yaml')).Line -replace '^version:\s*', '').Split('+')[0].Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be MAJOR.MINOR.PATCH' }
if (-not $OutputRoot) { $OutputRoot = $project }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$output = Join-Path $OutputRoot "app\$Version"
$dist = Join-Path $OutputRoot 'dist'
if (-not $CheckOnly -and ((Test-Path -LiteralPath $output) -or
    (Test-Path -LiteralPath (Join-Path $dist "MediaScaler-$Version-windows-setup.exe")))) {
    throw 'A bundle for this version already exists at OutputRoot. Select a fresh build destination.'
}
# Windows Flutter AOT requires an ASCII build path. SUBST keeps all files in the requested folder.
$stage = Join-Path $project ('build\release-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$source = Join-Path $stage 'src'
New-Item -ItemType Directory -Path $source | Out-Null
$drive = @('R:','S:','T:','U:') | Where-Object { -not (Test-Path ($_ + '\')) } | Select-Object -First 1
if (-not $drive) { throw 'No free build drive' }
$succeeded = $false
$mapped = $false
$sdkDrive = $null
$pluginJunctions = @()
$previousTemps = $null
$previousPubCache = $env:PUB_CACHE
$python = Join-Path $project 'tools\sdk\python\python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
$flutter = 'flutter'
$dart = 'dart'
try {
    $sdk = Join-Path $project 'tools\sdk'
    if (Test-Path -LiteralPath (Join-Path $sdk 'flutter\bin\flutter.bat')) {
        # Flutter's Windows launchers require a path without parentheses.
        foreach ($letter in @('V:', 'W:', 'X:', 'Y:')) {
            if (Test-Path ($letter + '\')) { continue }
            subst $letter $sdk
            if (-not $LASTEXITCODE) { $sdkDrive = $letter; break }
        }
        if (-not $sdkDrive) { throw 'No free Flutter SDK drive' }
        $flutter = Join-Path ($sdkDrive + '\') 'flutter\bin\flutter.bat'
        $dart = Join-Path ($sdkDrive + '\') 'flutter\bin\dart.bat'
        $env:PUB_CACHE = Join-Path ($sdkDrive + '\') 'pub-cache'
    }
    foreach ($folder in @('lib','config','windows','macos','test','ai_worker','packaging','scripts')) {
        if (Test-Path (Join-Path $project $folder)) { Copy-Item (Join-Path $project $folder) $source -Recurse }
    }
    if (-not $CheckOnly) {
        New-Item -ItemType Directory -Path (Join-Path $source 'tools') | Out-Null
        foreach ($folder in @('ai','ffmpeg','licenses')) {
            Copy-Item (Join-Path $project "tools\$folder") (Join-Path $source 'tools') -Recurse
        }
        Copy-Item (Join-Path $source 'ai_worker\worker.py') (Join-Path $source 'tools\ai\windows\worker.py') -Force
    }
    foreach ($file in @('pubspec.yaml','pubspec.lock','analysis_options.yaml','.metadata','THIRD_PARTY_NOTICES.txt','パラメーター設定ガイド.txt')) {
        Copy-Item (Join-Path $project $file) $source
    }
    subst $drive $stage
    if ($LASTEXITCODE) { throw 'Build drive mapping failed' }
    $mapped = $true
    # Native test runners and tools can hit MAX_PATH through the verification
    # temp directory even when the source itself is on the short drive.
    $previousTemps = @{ TMP = $env:TMP; TEMP = $env:TEMP; TMPDIR = $env:TMPDIR }
    $shortTemp = Join-Path ($drive + '\') 'tmp'
    New-Item -ItemType Directory -Path $shortTemp | Out-Null
    $env:TMP = $env:TEMP = $env:TMPDIR = $shortTemp
    Push-Location ($drive + '\src')
    try {
        $pubOutput = & $flutter pub get 2>&1
        $pubExit = $LASTEXITCODE
        $pubOutput | Write-Output
        if ($pubExit -and ($pubOutput -match 'Building with plugins requires symlink support')) {
            # Flutter has already resolved packages and generated the plugin list.
            # Use ordinary directory junctions in this disposable stage.
            $metadata = Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
            $links = New-Item -ItemType Directory -Path 'windows/flutter/ephemeral/.plugin_symlinks' -Force
            foreach ($plugin in $metadata.plugins.windows) {
                if ($plugin.name -notmatch '^[a-z][a-z0-9_]*$' -or
                    -not [IO.Path]::IsPathFullyQualified($plugin.path) -or
                    -not (Test-Path -LiteralPath $plugin.path -PathType Container)) {
                    throw 'Invalid path in Flutter plugin metadata'
                }
                $link = Join-Path $links.FullName $plugin.name
                if (-not (Test-Path -LiteralPath $link)) {
                    New-Item -ItemType Junction -Path $link -Target ([IO.Path]::GetFullPath($plugin.path)) | Out-Null
                    $pluginJunctions += $link
                }
            }
            & $flutter pub get
            $pubExit = $LASTEXITCODE
        }
        if ($pubExit) { throw 'pub get failed' }
        & $dart analyze lib test
        if ($LASTEXITCODE) { throw 'analysis failed' }
        & $flutter test --no-pub
        if ($LASTEXITCODE) { throw 'test failed' }
        & $python -B -m unittest discover -s scripts -p 'test_release_*.py'
        if ($LASTEXITCODE) { throw 'release automation tests failed' }
        if ($CheckOnly) {
            $succeeded = $true
            return
        }
        $repository = $env:UPDATE_REPOSITORY
        if (-not $repository -and $env:COMMON_APP_DEV -eq $project) {
            $repository = 'skybluema891-dev/media-scaler'
        }
        & $flutter build windows --release --no-pub --build-name=$Version "--dart-define=UPDATE_REPOSITORY=$repository" --dart-define=UPDATE_TARGET=windows-x64 -v *> (Join-Path $project 'build\windows-release.log')
        if ($LASTEXITCODE) { throw 'Windows build failed' }
        New-Item -ItemType Directory -Force $output | Out-Null
        Copy-Item '.\build\windows\x64\runner\Release\*' $output -Recurse -Force
        Rename-Item -LiteralPath (Join-Path $output 'media_scaler.exe') -NewName 'Media Scaler.exe'
    } finally { Pop-Location }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products '*' -property installationPath
    $crt = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory |
        Sort-Object Name -Descending | ForEach-Object {
            Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter '*.CRT' -ErrorAction SilentlyContinue
        } | Select-Object -First 1
    if (-not $crt) { throw 'Microsoft C++ redistributable DLLs not found' }
    Copy-Item (Join-Path $crt.FullName '*.dll') $output -Force
    New-Item -ItemType Directory -Force $dist | Out-Null
    if (-not $Iscc) {
        $Iscc = @("$env:ProgramFiles\Inno Setup 7\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            (Join-Path $project 'tools\inno\ISCC.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Iscc) { throw 'Inno Setup compiler is required for installer' }
    # Inno enumerates the embedded packages using legacy Windows paths.
    $payload = Join-Path ($drive + '\') 'package-input'
    New-Item -ItemType Junction -Path $payload -Target $output | Out-Null
    try {
        & $Iscc /Q "/DAppVersion=$Version" "/DSourceDir=$payload" "/DOutputDir=$dist" (Join-Path $project 'packaging\windows\installer.iss')
        if ($LASTEXITCODE) { throw 'Installer build failed' }
    } finally {
        [IO.Directory]::Delete($payload)
    }
    if ($env:COMMON_APP_DEV -eq $project -and $env:COMMON_APP_DATA_MODE -eq 'portable') {
        @{
            id = $env:COMMON_APP_ID
            data_mode = 'portable'
            data_relative = [IO.Path]::GetRelativePath($output, $env:COMMON_APP_DATA)
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'runtime.json') -Encoding utf8
    }
    $succeeded = $true
} finally {
    foreach ($link in $pluginJunctions) {
        if ((Get-Item -LiteralPath $link -ErrorAction SilentlyContinue).LinkType -eq 'Junction') {
            [IO.Directory]::Delete($link)
        }
    }
    if ($previousTemps) {
        foreach ($key in $previousTemps.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousTemps[$key], 'Process')
        }
    }
    if ($mapped) { subst $drive /D }
    $env:PUB_CACHE = $previousPubCache
    if ($sdkDrive) { subst $sdkDrive /D }
    $resolved = [IO.Path]::GetFullPath($stage)
    if ($succeeded -and $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $project 'build')) + [IO.Path]::DirectorySeparatorChar) -and
        (Split-Path $resolved -Leaf).StartsWith('release-stage-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    } elseif (-not $succeeded) {
        Write-Warning "Build stage kept for investigation: $resolved"
    }
}
