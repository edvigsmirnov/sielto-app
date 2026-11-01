; Per-user installer over `flutter build windows --release`.
;
;   iscc /DAppVersion=1.0.0 /DFileVersion=1.0.0+42 windows\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef FileVersion
  #define FileVersion AppVersion
#endif

[Setup]
AppId={{5CDD97B9-C163-44A5-AB79-959C02F96F10}
AppName=Sielto
AppVersion={#AppVersion}
AppPublisher=Edvig Smirnov
AppPublisherURL=https://github.com/edvigsmirnov/sielto-app
DefaultDirName={autopf}\Sielto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sielto.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=..\build\installer
OutputBaseFilename=sielto-app-{#FileVersion}-windows-setup

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\Sielto"; Filename: "{app}\sielto.exe"
Name: "{autodesktop}\Sielto"; Filename: "{app}\sielto.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sielto.exe"; Description: "{cm:LaunchProgram,Sielto}"; Flags: nowait postinstall skipifsilent
