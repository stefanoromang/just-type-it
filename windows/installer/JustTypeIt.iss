; Just Type It for Windows – installer script (Inno Setup 6)
; Created by Stefano Roman Gunness · MIT License
; https://github.com/stefanoromang/just-type-it

#define AppName "Just Type It"
#define AppVersion "1.1.1"
#define AppPublisher "Stefano Roman Gunness"
#define AppURL "https://github.com/stefanoromang/just-type-it"
#define AppExe "JustTypeIt.exe"

[Setup]
AppId={{6F8B2C4E-3D7A-4E21-9B5C-1A2D3E4F5A6B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppCopyright=© 2026 Stefano Roman Gunness
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright=© 2026 Stefano Roman Gunness
VersionInfoDescription={#AppName} Setup
DefaultDirName={localappdata}\Programs\JustTypeIt
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Per-user install: never asks for an administrator password.
PrivilegesRequired=lowest
UsedUserAreasWarning=no
OutputDir=..\dist
OutputBaseFilename=JustTypeIt-Setup-{#AppVersion}
SetupIconFile=..\JustTypeIt\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start Just Type It when Windows starts (checks your writing in every app)"; GroupDescription: "Startup:"

[Files]
Source: "..\dist\JustTypeIt\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Free, private AI writing assistant – by Stefano Roman Gunness"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "JustTypeIt"; ValueData: """{app}\{#AppExe}"" --background"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch Just Type It"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe} /FI ""USERNAME eq {username}"""; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
