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
  Controls, Dialogs, LazIDEIntf, WasteBin;

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
Begin
  Result := WasteBin.MovePathToWasteBin(FullPath, ErrorText);
End;

End.
