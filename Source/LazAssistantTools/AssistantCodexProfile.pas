Unit AssistantCodexProfile;

{ Separate managed-runtime profile. Never import tokens or API keys into the IDE. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Procedure CodexProfileEnvironment(Const ProfileDir: String; Values: TStrings);
Function PrepareCodexProfile(Const ProfileDir: String; Out ErrorText: String): Boolean;
Function FindCodexExecutable: String;
Implementation
Uses FileUtil, LazFileUtils {$IFDEF UNIX}, BaseUnix{$ENDIF};
Procedure CodexProfileEnvironment(Const ProfileDir: String; Values: TStrings);
Var I: Integer;
Begin
  Values.Clear;
  For I := 1 To GetEnvironmentVariableCount Do Values.Add(GetEnvironmentString(I));
  Values.Values['CODEX_HOME'] := ExpandFileName(ProfileDir);
  Values.Values['OPENAI_API_KEY'] := '';
  Values.Values['CODEX_API_KEY'] := '';
  Values.Values['OPENAI_BASE_URL'] := '';
End;
Function PrepareCodexProfile(Const ProfileDir: String; Out ErrorText: String): Boolean;
Var Config: TStringList; Path: String;
Begin
  Result := False; ErrorText := '';
  Try
    If Not ForceDirectories(ProfileDir) Then Raise Exception.Create('Cannot create runtime profile');
    {$IFDEF UNIX}
    If fpChmod(ProfileDir, &700) <> 0 Then Raise Exception.Create('Cannot protect runtime profile');
    {$ENDIF}
    Path := IncludeTrailingPathDelimiter(ProfileDir) + 'config.toml';
    { This is a dedicated application-owned profile, never the user's CLI one.
      Runtime-managed auth remains in its credential store. }
    Config := TStringList.Create;
    Try
      Config.Add('forced_login_method = "chatgpt"');
      Config.Add('model_provider = "openai"');
      Config.Add('approval_policy = "on-request"');
      Config.Add('sandbox_mode = "read-only"');
      Config.Add('web_search = "disabled"');
      Config.Add('[features]');
      Config.Add('apps = false');
      Config.Add('shell_tool = false');
      Config.Add('unified_exec = false');
      Config.Add('skill_mcp_dependency_install = false');
      Config.SaveToFile(Path);
      {$IFDEF UNIX}fpChmod(Path, &600);{$ENDIF}
    Finally Config.Free; End;
    Result := True;
  Except On E: Exception Do ErrorText := E.Message; End;
End;
Function FindCodexExecutable: String;
Var Root: String; Search: TSearchRec;
Begin
  Result := FindDefaultExecutablePath('codex');
  If Result <> '' Then Exit;
  Root := IncludeTrailingPathDelimiter(GetUserDir) + '.vscode/extensions/';
  If FindFirst(Root + 'openai.chatgpt-*', faDirectory, Search) <> 0 Then Exit;
  Try
    Repeat
      Result := Root + Search.Name + '/bin/linux-x86_64/codex';
      If FileExistsUTF8(Result) Then Exit;
    Until FindNext(Search) <> 0;
  Finally FindClose(Search); End;
  Result := '';
End;
End.
