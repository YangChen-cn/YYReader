#define AppName "YYReader"
#define AppPublisher "YangChen-cn"
#define AppExeName "YYReader.Windows.exe"
#define AppId "{{6B9D0FD9-959F-4F94-B03E-C58EF3361794}"

#ifndef MyAppVersion
  #define MyAppVersion "1.2.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\..\dist\windows\publish"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppVerName={#AppName} {#MyAppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/YangChen-cn/YYReader
AppSupportURL=https://github.com/YangChen-cn/YYReader/issues
AppUpdatesURL=https://github.com/YangChen-cn/YYReader/releases
DefaultDirName={localappdata}\Programs\YYReader
DefaultGroupName=YYReader
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=YYReader-Setup-x64-{#MyAppVersion}
SetupIconFile=..\YYReader.Windows\Assets\AppIcon.ico
UninstallDisplayIcon={app}\Assets\YYReader-AppIcon-{#MyAppVersion}.ico
UninstallDisplayName={#AppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} 安装程序
VersionInfoProductName={#AppName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.17763

[Languages]
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: checkedonce

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\Assets\AppIcon.ico"; DestDir: "{app}\Assets"; DestName: "YYReader-AppIcon-{#MyAppVersion}.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\YYReader"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\YYReader-AppIcon-{#MyAppVersion}.ico"
Name: "{autodesktop}\YYReader"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\Assets\YYReader-AppIcon-{#MyAppVersion}.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 YYReader"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
