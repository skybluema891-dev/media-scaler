#ifndef AppVersion
  #define AppVersion "1.1.2"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
[Setup]
AppId={{D95D1FD9-8B40-46CE-AF11-32C6599A8C42}
AppName=Media Scaler
AppVersion={#AppVersion}
AppPublisher=Media Scaler Project
DefaultDirName={localappdata}\Programs\MediaScaler
DefaultGroupName=Media Scaler
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=MediaScaler-{#AppVersion}-windows-setup
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Media Scaler.exe
UninstallDisplayName=Media Scaler
VersionInfoProductName=Media Scaler
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
[Tasks]
Name: desktopicon; Description: "デスクトップにショートカットを作成"; Flags: unchecked
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Media Scaler"; Filename: "{app}\Media Scaler.exe"
Name: "{autodesktop}\Media Scaler"; Filename: "{app}\Media Scaler.exe"; Tasks: desktopicon
[InstallDelete]
Type: files; Name: "{app}\media_scaler.exe"
Type: files; Name: "{autoprograms}\メディア・スケーラー\メディア・スケーラー.lnk"
Type: dirifempty; Name: "{autoprograms}\メディア・スケーラー"
Type: files; Name: "{autodesktop}\メディア・スケーラー.lnk"
[Run]
Filename: "{app}\Media Scaler.exe"; Description: "Media Scaler を起動"; Flags: nowait postinstall skipifsilent
