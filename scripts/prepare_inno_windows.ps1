# Prepare a separate portable compiler. Existing Inno installations stay available.
$ErrorActionPreference = 'Stop'
$tools = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools'
$dir = Join-Path $tools 'inno-7.1.1'
if (Test-Path -LiteralPath (Join-Path $dir 'ISCC.exe')) { return }
$downloads = New-Item -ItemType Directory -Force -Path (Join-Path $tools 'downloads')
$installer = Join-Path $downloads.FullName 'innosetup-7.1.1-x64.exe'
$url = 'https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-7.1.1-x64.exe'
if (-not (Test-Path -LiteralPath $installer)) {
    Invoke-WebRequest -Uri $url -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer).Hash -ne '8a5a6711c3766a6e5fb74f280ba0e3551e719ce94538d901fdbd1f8f9920b3f0') {
    throw 'Inno Setup 7.1.1 installer checksum mismatch'
}
$process = Start-Process -FilePath $installer -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
    '/PORTABLE=1', '/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$dir`""
)
if ($process.ExitCode -or -not (Test-Path -LiteralPath (Join-Path $dir 'ISCC.exe'))) {
    throw "Portable Inno Setup installation failed (exit $($process.ExitCode))"
}
