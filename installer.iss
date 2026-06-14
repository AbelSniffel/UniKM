; Inno Setup script for UniKM

[Setup]
AppName=UniKM
AppVersion=1.3.0
VersionInfoVersion=1.3.0
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
const
  FirewallAppRuleName = 'UniKM';
  FirewallUdpRuleName = 'UniKM Device Sync (UDP Discovery)';
  FirewallTcpRuleName = 'UniKM Device Sync (TCP Transfer)';

function QuoteArg(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

function ExecHidden(const FileName, Params: String): Integer;
var
  ResultCode: Integer;
begin
  if Exec(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := ResultCode
  else
    Result := -1;
end;

procedure RemoveFirewallRules();
var
  AppPath: String;
begin
  AppPath := ExpandConstant('{app}\unikm.exe');

  ExecHidden(
    ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall delete rule name=' + QuoteArg(FirewallAppRuleName)
  );
  ExecHidden(
    ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall delete rule name=' + QuoteArg(FirewallUdpRuleName) +
    ' program=' + QuoteArg(AppPath)
  );
  ExecHidden(
    ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall delete rule name=' + QuoteArg(FirewallTcpRuleName) +
    ' program=' + QuoteArg(AppPath)
  );
  ExecHidden(
    ExpandConstant('{sys}\netsh.exe'),
    'firewall delete allowedprogram program=' + QuoteArg(AppPath)
  );
end;

procedure AddFirewallRules();
var
  AppPath: String;
begin
  AppPath := ExpandConstant('{app}\unikm.exe');
  if not FileExists(AppPath) then
    exit;

  RemoveFirewallRules();
  ExecHidden(
    ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall add rule name=' + QuoteArg(FirewallAppRuleName) +
    ' dir=in action=allow enable=yes profile=private,public ' +
    'program=' + QuoteArg(AppPath) + ' remoteip=LocalSubnet'
  );
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    AddFirewallRules();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RC: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    RemoveFirewallRules();
    // force-kill the process; taskkill waits until termination
    Exec(ExpandConstant('{cmd}'), '/C taskkill /F /IM unikm.exe', '', SW_HIDE, ewWaitUntilTerminated, RC);
  end;
end;

[UninstallRun]
; none (handled in code)

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
