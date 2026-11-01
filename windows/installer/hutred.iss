; Установщик Hutred для Windows (Inno Setup).
; Собирается в облаке: из папки Release получается один Hutred-Setup.exe —
; запустил, «Далее», и на рабочем столе появляется ярлык.
; Автообновление запускает его тихо (/VERYSILENT), и он сам открывает новую версию.
#define AppVersion GetEnv("HUTRED_VERSION")

[Setup]
AppId={{6C0B8E5E-7A2B-4C55-9C1E-5D2C1B1E7A11}
AppName=Hutred
AppVersion={#AppVersion}
AppPublisher=Hutred
DefaultDirName={localappdata}\Programs\Hutred
DefaultGroupName=Hutred
; Ставится только для текущего пользователя — права администратора не нужны.
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Hutred-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\hutred.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Ярлык на рабочем столе"; GroupDescription: "Дополнительно:"
Name: "autostart"; Description: "Запускать вместе с Windows"; GroupDescription: "Дополнительно:"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Hutred"; ValueData: """{app}\hutred.exe"" --minimized"; Tasks: autostart; Flags: uninsdeletevalue

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Hutred"; Filename: "{app}\hutred.exe"
Name: "{autodesktop}\Hutred"; Filename: "{app}\hutred.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\hutred.exe"; Description: "Запустить Hutred"; Flags: nowait postinstall skipifsilent
; Тихое автообновление: после установки сразу открываем новую версию.
Filename: "{app}\hutred.exe"; Flags: nowait; Check: WizardSilent
