Unit GitPathUtils;

{ Shared project start-path and Files-tab path actions (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, ProjectIntf;

Function GitProjectStartPath(AProject: TLazProject): String;
Function GitIdeStartPath: String;
Function ConfirmGitPathAction(Const ActionTitle, ActionVerb: String; Paths: TStrings): Boolean;
Function MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;

Implementation

Uses
  Controls, Dialogs, FileUtil, LazIDEIntf, Process
  {$IFDEF WINDOWS}, ShellApi{$ENDIF};

Function GitProjectStartPath(AProject: TLazProject): String;
Begin
  Result := '';
  Try
    If Not Assigned(AProject) Or AProject.IsVirtual Then
      Exit;
    If AProject.ProjectInfoFile <> '' Then
      Result := ExtractFilePath(ExpandFileName(AProject.ProjectInfoFile));
    If (Result = '') And Assigned(AProject.MainFile) And (AProject.MainFile.Filename <> '') Then
      Result := ExtractFilePath(ExpandFileName(AProject.MainFile.Filename));
  Except
    Result := '';
  End;
End;

Function GitIdeStartPath: String;
Begin
  Result := '';
  Try
    If Assigned(LazarusIDE) Then
      Result := GitProjectStartPath(LazarusIDE.ActiveProject);
  Except
    { Active project can be half-destroyed during IDE project switch. }
    Result := '';
  End;
End;

Function FormatPathActionSummary(Const ActionVerb: String; Paths: TStrings): String;
Var
  I, Shown: Integer;
  Body: String;
Const
  MaxListed = 15;
Begin
  Body := '';
  Shown := 0;
  If Assigned(Paths) Then
    For I := 0 To Paths.Count - 1 Do
      Begin
        If Shown >= MaxListed Then
          Begin
            Body := Body + LineEnding + Format('…and %d more', [Paths.Count - MaxListed]);
            Break;
          End;
        If Body <> '' Then
          Body := Body + LineEnding;
        Body := Body + Paths[I];
        Inc(Shown);
      End;
  If Paths = Nil Then
    Result := ActionVerb
  Else
    Result := Format('%s the following %d file(s)?' + LineEnding + LineEnding + '%s',
      [ActionVerb, Paths.Count, Body]);
End;

Function ConfirmGitPathAction(Const ActionTitle, ActionVerb: String; Paths: TStrings): Boolean;
Begin
  Result := False;
  If (Paths = Nil) Or (Paths.Count = 0) Then
    Exit;
  Result := MessageDlg(ActionTitle, FormatPathActionSummary(ActionVerb, Paths),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes;
End;

Function MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  Op: TSHFileOpStructW;
  FromBuf: UnicodeString;
{$ELSE}
Var
  Proc: TProcess;
  Cmd: String;
{$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  If FullPath = '' Then
    Begin
      ErrorText := 'Empty path';
      Exit;
    End;
  If (Not FileExists(FullPath)) And (Not DirectoryExists(FullPath)) Then
    Begin
      ErrorText := 'Path does not exist: ' + FullPath;
      Exit;
    End;

{$IFDEF WINDOWS}
  FromBuf := UTF8Decode(FullPath) + #0#0;
  FillChar(Op, SizeOf(Op), 0);
  Op.Wnd := 0;
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(FromBuf);
  Op.fFlags := FOF_ALLOWUNDO Or FOF_NOCONFIRMATION Or FOF_SILENT Or FOF_NOERRORUI;
  If SHFileOperationW(@Op) = 0 Then
    Result := Not (FileExists(FullPath) Or DirectoryExists(FullPath))
  Else
    ErrorText := 'Windows could not move the item to the Recycle Bin';
{$ELSE}
  Proc := TProcess.Create(Nil);
  Try
    Proc.Options := [poWaitOnExit, poNoConsole];
    Cmd := FindDefaultExecutablePath('gio');
    If Cmd <> '' Then
      Begin
        Proc.Executable := Cmd;
        Proc.Parameters.Add('trash');
        Proc.Parameters.Add(FullPath);
        Try
          Proc.Execute;
          Result := Proc.ExitStatus = 0;
        Except
          Result := False;
        End;
      End;
    If Not Result Then
      Begin
        Proc.Parameters.Clear;
        Cmd := FindDefaultExecutablePath('trash-put');
        If Cmd = '' Then
          Cmd := FindDefaultExecutablePath('trash');
        If Cmd <> '' Then
          Begin
            Proc.Executable := Cmd;
            Proc.Parameters.Add(FullPath);
            Try
              Proc.Execute;
              Result := Proc.ExitStatus = 0;
            Except
              Result := False;
            End;
          End;
      End;
    If Not Result Then
      Begin
        {$IFDEF DARWIN}
        Proc.Parameters.Clear;
        Proc.Executable := '/usr/bin/osascript';
        Proc.Parameters.Add('-e');
        Proc.Parameters.Add('tell application "Finder" to delete POSIX file "' +
          StringReplace(FullPath, '"', '\"', [rfReplaceAll]) + '"');
        Try
          Proc.Execute;
          Result := Proc.ExitStatus = 0;
        Except
          Result := False;
        End;
        {$ENDIF}
      End;
    If Not Result Then
      ErrorText := 'Could not move to the waste bin: ' + FullPath;
  Finally
    Proc.Free;
  End;
{$ENDIF}
End;

End.
