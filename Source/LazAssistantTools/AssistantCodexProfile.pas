Unit AssistantCodexProfile;

{ Derived Codex runtime profile. CODEX_HOME is not a settings store.
  config.toml is rewritten from a fixed policy on every launch.
  Model, effort, approval and runtime credentials are not written here. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;
Procedure CodexProfileEnvironment(Const ProfileDir: String; Values: TStrings);
Function PrepareCodexProfile(Const ProfileDir: String; Out ErrorText: String): Boolean;
/// True when ProfileDir is `<config>/codex/<connection-id>` and not a symbolic link.
Function CodexProfilePathIsDerived(Const ProfileDir: String): Boolean;
/// Delete that directory only. Does not create it, and refuses every other path.
Function DeleteCodexProfileDirectory(Const ProfileDir: String; Out ErrorText: String): Boolean;
Function FindCodexExecutable: String;

Implementation

Uses
  FileUtil, LazFileUtils, DirectoryListing, SafeFileAccess;

Procedure CodexProfileEnvironment(Const ProfileDir: String; Values: TStrings);
Var
  I: Integer;
Begin
  Values.Clear;
  For I := 1 To GetEnvironmentVariableCount Do Values.Add(GetEnvironmentString(I));
  Values.Values['CODEX_HOME'] := ExpandFileName(ProfileDir);
  Values.Values['OPENAI_API_KEY'] := '';
  Values.Values['CODEX_API_KEY'] := '';
  Values.Values['OPENAI_BASE_URL'] := '';
End;

Function PrepareCodexProfile(Const ProfileDir: String; Out ErrorText: String): Boolean;
Var
  Config: TStringList;
  Path: String;
Begin
  Result := False;
  ErrorText := '';
  Try
    If Not ForceDirectories(ProfileDir) Then Raise Exception.Create('Cannot create runtime profile');
    If Not ProtectOwnerOnlyDirectory(ProfileDir) Then Raise Exception.Create('Cannot protect runtime profile');
    Path := IncludeTrailingPathDelimiter(ProfileDir) + 'config.toml';
    { Dedicated profile, never the user's CLI home. Rewrite the fixed policy on
      every launch. Leave runtime auth files untouched; do not record model,
      effort, approval or credentials in this file. }
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
      ProtectOwnerOnlyFile(Path);
    Finally
      Config.Free;
    End;
    Result := True;
  Except On E: Exception Do ErrorText := E.Message;
  End;
End;

{ Same identifier rules as AssistantConnections.SafeId. }
Function ConnectionIdIsSafe(Const Value: String): Boolean;
Var
  C: Char;
Begin
  Result := (Value <> '') And (Length(Value) <= 80);
  If Not Result Then Exit;
  For C In Value Do
    If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) Then Exit(False);
End;

Function IsSymbolicLink(Const Path: String): Boolean;
Begin
  Result := FileIsSymlink(Path);
End;

Function CodexProfilePathIsDerived(Const ProfileDir: String): Boolean;
Var
  Expanded, Leaf, ParentPath: String;
Begin
  Result := False;
  If Trim(ProfileDir) = '' Then Exit;
  Expanded := ExcludeTrailingPathDelimiter(ExpandFileName(Trim(ProfileDir)));
  Leaf := ExtractFileName(Expanded);
  If Not ConnectionIdIsSafe(Leaf) Then Exit;
  ParentPath := ExcludeTrailingPathDelimiter(ExtractFilePath(Expanded));
  If ExtractFileName(ParentPath) <> 'codex' Then Exit;
  If IsSymbolicLink(Expanded) Or IsSymbolicLink(ParentPath) Then Exit;
  Result := True;
End;

Function RemovePlainDirectory(Const Directory: String): Boolean;
Var
  Info: TDirectoryScan;
  Child: String;
  Found: Integer;
Begin
  Result := False;
  If IsSymbolicLink(Directory) Then Exit;
  Found := StartDirectoryScan(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile Or faSymLink, Info);
  If Found = 0 Then
    Begin
      Try
        Repeat
          If (Info.Name = '.') Or (Info.Name = '..') Then Continue;
          Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
          If ((Info.Attr And faSymLink) <> 0) Or IsSymbolicLink(Child) Then
            Begin
              If Not DeleteFile(Child) Then Exit;
            End
          Else If (Info.Attr And faDirectory) <> 0 Then
            Begin
              If Not RemovePlainDirectory(Child) Then Exit;
            End
          Else If Not DeleteFile(Child) Then Exit;
        Until AdvanceDirectoryScan(Info) <> 0;
      Finally
        CloseDirectoryScan(Info);
      End;
    End;
  Result := RemoveDir(Directory);
End;

Function DeleteCodexProfileDirectory(Const ProfileDir: String; Out ErrorText: String): Boolean;
Var
  Expanded, ParentPath: String;
Begin
  Result := False;
  ErrorText := '';
  If Not CodexProfilePathIsDerived(ProfileDir) Then
    Begin
      ErrorText := 'Refusing to delete a path that is not a derived Codex profile directory.';
      Exit;
    End;
  Expanded := ExcludeTrailingPathDelimiter(ExpandFileName(Trim(ProfileDir)));
  ParentPath := ExcludeTrailingPathDelimiter(ExtractFilePath(Expanded));
  If IsSymbolicLink(Expanded) Or IsSymbolicLink(ParentPath) Then
    Begin
      ErrorText := 'Refusing to delete a profile path that is a symbolic link.';
      Exit;
    End;
  If Not DirectoryExists(Expanded) Then
    Begin
      If FileExists(Expanded) Then
        Begin
          ErrorText := 'Refusing to delete a profile path that is not a plain directory.';
          Exit;
        End;
      Result := True;
      Exit;
    End;
  If Not RemovePlainDirectory(Expanded) Or DirectoryExists(Expanded) Then
    ErrorText := 'Could not delete the Codex profile directory.'
  Else
    Result := True;
End;

Function FindCodexExecutable: String;
Var
  Root, Candidate, BestName: String;
  Search: TDirectoryScan;
Begin
  Result := FindDefaultExecutablePath('codex');
  If Result <> '' Then Exit;
  Root := IncludeTrailingPathDelimiter(GetUserDir) + '.vscode/extensions/';
  BestName := '';
  If StartDirectoryScan(Root + 'openai.chatgpt-*', faDirectory, Search) <> 0 Then Exit;
  Try
    Repeat
      Candidate := Root + Search.Name + '/bin/linux-x86_64/codex';
      { Later extension directories sort after older builds. Prefer the newest
        executable so a leftover alpha is not selected ahead of the current one. }
      If FileIsExecutable(Candidate) And ((BestName = '') Or (Search.Name > BestName)) Then
        Begin
          BestName := Search.Name;
          Result := Candidate;
        End;
    Until AdvanceDirectoryScan(Search) <> 0;
  Finally
    CloseDirectoryScan(Search);
  End;
End;
End.
