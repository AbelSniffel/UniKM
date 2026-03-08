; Inno Setup script for UniKM

[Setup]
AppName=UniKM
AppVersion=1.1.0
VersionInfoVersion=1.1.0
DefaultDirName={pf}\UniKM
DefaultGroupName=UniKM
OutputDir=dist
OutputBaseFilename=UniKM-Setup
Compression=lzma2
DisableDirPage=no
UninstallDisplayIcon={app}\unikm.exe
UninstallFilesDir={app}
UninstallLogMode=append

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; copy all release binaries
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[InstallDelete]
; ensure installation directory is emptied before copying new files
Type: filesandordirs; Name: "{app}\*"

[Icons]
Name: "{group}\UniKM"; Filename: "{app}\unikm.exe"
Name: "{userdesktop}\UniKM"; Filename: "{app}\unikm.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\unikm.exe"; Description: "Launch UniKM"; Flags: nowait postinstall skipifsilent

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RC: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // force-kill the process; taskkill waits until termination
    Exec(ExpandConstant('{cmd}'), '/C taskkill /F /IM unikm.exe', '', SW_HIDE, ewWaitUntilTerminated, RC);
  end;
end;

[UninstallRun]
; none (handled in code)

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
