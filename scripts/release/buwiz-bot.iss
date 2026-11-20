#ifndef AppVersion
  #error AppVersion must be passed by build-windows.ps1
#endif
#ifndef StageDir
  #error StageDir must be passed by build-windows.ps1
#endif

[Setup]
AppId={{A37F2EB6-2642-472D-9D85-DF38F71A9C14}
AppName=Buwiz Bot
AppVersion={#AppVersion}
AppPublisher=Goldcoders Corp
AppPublisherURL=https://buwiz.com
DefaultDirName={localappdata}\Programs\Buwiz Bot
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultGroupName=Buwiz Bot
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\bin\buwiz-bot.exe
OutputBaseFilename=Buwiz-Bot-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SignedUninstaller=no
ChangesAssociations=yes
CloseApplications=yes

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Buwiz Bot"; Filename: "{app}\bin\buwiz-bot.exe"; WorkingDir: "{userappdata}"

[Registry]
Root: HKCU; Subkey: "Software\Classes\buwiz"; ValueType: string; ValueName: ""; ValueData: "URL:Buwiz Bot"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\buwiz"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\buwiz\DefaultIcon"; ValueType: string; ValueData: "{app}\bin\buwiz-bot.exe,0"
Root: HKCU; Subkey: "Software\Classes\buwiz\shell\open\command"; ValueType: string; ValueData: """{app}\bin\buwiz-bot.exe"" ""%1"""
