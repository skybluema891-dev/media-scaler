param([string]$Version = "", [string]$Iscc = "")
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if (-not $Version) {
    $Version = ((Select-String '^version:' (Join-Path $project 'pubspec.yaml')).Line -replace '^version:\s*', '').Split('+')[0].Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be MAJOR.MINOR.PATCH' }
# Windows Flutter AOT requires an ASCII build path. SUBST keeps all files in the requested folder.
$stage = Join-Path $project ('build\release-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$source = Join-Path $stage 'src'
New-Item -ItemType Directory -Path $source | Out-Null
$drive = @('R:','S:','T:','U:') | Where-Object { -not (Test-Path ($_ + '\')) } | Select-Object -First 1
if (-not $drive) { throw 'No free build drive' }
try {
    foreach ($folder in @('lib','config','windows','macos','test','ai_worker','packaging','scripts')) {
        if (Test-Path (Join-Path $project $folder)) { Copy-Item (Join-Path $project $folder) $source -Recurse }
    }
    New-Item -ItemType Directory -Path (Join-Path $source 'tools') | Out-Null
    foreach ($folder in @('ai','ffmpeg','licenses')) {
        Copy-Item (Join-Path $project "tools\$folder") (Join-Path $source 'tools') -Recurse
    }
    foreach ($file in @('pubspec.yaml','pubspec.lock','analysis_options.yaml','.metadata','THIRD_PARTY_NOTICES.txt','パラメーター設定ガイド.txt')) {
        Copy-Item (Join-Path $project $file) $source
    }
    subst $drive $stage
    if ($LASTEXITCODE) { throw 'Build drive mapping failed' }
    Push-Location ($drive + '\src')
    try {
        flutter pub get
        if ($LASTEXITCODE) { throw 'pub get failed' }
        dart analyze lib test
        if ($LASTEXITCODE) { throw 'analysis failed' }
        flutter test --no-pub
        if ($LASTEXITCODE) { throw 'test failed' }
        flutter build windows --release --no-pub --build-name=$Version "--dart-define=UPDATE_REPOSITORY=$env:UPDATE_REPOSITORY" --dart-define=UPDATE_TARGET=windows-x64 -v *> (Join-Path $project 'build\windows-release.log')
        if ($LASTEXITCODE) { throw 'Windows build failed' }
        $output = Join-Path $project "app\$Version"
        New-Item -ItemType Directory -Force $output | Out-Null
        Copy-Item '.\build\windows\x64\runner\Release\*' $output -Recurse -Force
    } finally { Pop-Location }
    $dist = Join-Path $project 'dist'
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
            (Join-Path $project 'tools\inno\ISCC.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Iscc) { throw 'Inno Setup compiler is required for installer' }
    & $Iscc /Q "/DAppVersion=$Version" "/DSourceDir=$output" "/DOutputDir=$dist" (Join-Path $project 'packaging\windows\installer.iss')
    if ($LASTEXITCODE) { throw 'Installer build failed' }
    Copy-Item (Join-Path $dist "MediaScaler-$Version-windows-setup.exe") (Join-Path $project '01_インストール.exe') -Force
    # Keep the existing easy-to-find launcher usable.
    $compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    & $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll "/win32icon:$project\windows\runner\resources\app_icon.ico" "/out:$project\00_メディア・スケーラー.exe" (Join-Path $project 'windows_launcher\Program.cs')
    if ($LASTEXITCODE) { throw 'Launcher build failed' }
} finally {
    subst $drive /D
    $resolved = [IO.Path]::GetFullPath($stage)
    if ($resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $project 'build')) + [IO.Path]::DirectorySeparatorChar) -and
        (Split-Path $resolved -Leaf).StartsWith('release-stage-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
