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
AppName=メディア・スケーラー
AppVersion={#AppVersion}
AppPublisher=Media Scaler Project
DefaultDirName={localappdata}\Programs\MediaScaler
DefaultGroupName=メディア・スケーラー
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=MediaScaler-{#AppVersion}-windows-setup
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\media_scaler.exe
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
[Tasks]
Name: desktopicon; Description: "デスクトップにショートカットを作成"; Flags: unchecked
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\メディア・スケーラー"; Filename: "{app}\media_scaler.exe"
Name: "{autodesktop}\メディア・スケーラー"; Filename: "{app}\media_scaler.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\media_scaler.exe"; Description: "メディア・スケーラーを起動"; Flags: nowait postinstall skipifsilent
