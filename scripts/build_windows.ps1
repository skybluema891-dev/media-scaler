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
$previousTemps = $null
try {
    foreach ($folder in @('lib','config','windows','macos','test','ai_worker','packaging','scripts')) {
        if (Test-Path (Join-Path $project $folder)) { Copy-Item (Join-Path $project $folder) $source -Recurse }
    }
    if (-not $CheckOnly) {
        New-Item -ItemType Directory -Path (Join-Path $source 'tools') | Out-Null
        foreach ($folder in @('ai','ffmpeg','licenses')) {
            Copy-Item (Join-Path $project "tools\$folder") (Join-Path $source 'tools') -Recurse
        }
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
        flutter pub get
        if ($LASTEXITCODE) { throw 'pub get failed' }
        dart analyze lib test
        if ($LASTEXITCODE) { throw 'analysis failed' }
        flutter test --no-pub
        if ($LASTEXITCODE) { throw 'test failed' }
        python -B -m unittest discover -s scripts -p 'test_release_*.py'
        if ($LASTEXITCODE) { throw 'release automation tests failed' }
        if ($CheckOnly) {
            $succeeded = $true
            return
        }
        flutter build windows --release --no-pub --build-name=$Version "--dart-define=UPDATE_REPOSITORY=$env:UPDATE_REPOSITORY" --dart-define=UPDATE_TARGET=windows-x64 -v *> (Join-Path $project 'build\windows-release.log')
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
    & $Iscc /Q "/DAppVersion=$Version" "/DSourceDir=$output" "/DOutputDir=$dist" (Join-Path $project 'packaging\windows\installer.iss')
    if ($LASTEXITCODE) { throw 'Installer build failed' }
    $succeeded = $true
} finally {
    if ($previousTemps) {
        foreach ($key in $previousTemps.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousTemps[$key], 'Process')
        }
    }
    if ($mapped) { subst $drive /D }
    $resolved = [IO.Path]::GetFullPath($stage)
    if ($succeeded -and $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $project 'build')) + [IO.Path]::DirectorySeparatorChar) -and
        (Split-Path $resolved -Leaf).StartsWith('release-stage-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    } elseif (-not $succeeded) {
        Write-Warning "Build stage kept for investigation: $resolved"
    }
}
