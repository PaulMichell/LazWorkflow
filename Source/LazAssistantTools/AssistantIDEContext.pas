Unit AssistantIDEContext;

{ Collect active editor and project context for LazAssistantTools prompts (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  { Keep the default context modest so first-token latency stays reasonable.
    Selection is preferred; full-file attach is capped. }
  AssistantContextMaxActiveChars = 48000;
  AssistantContextMaxProjectFiles = 250;

Function BuildIDEContextBlock: String;

Implementation

Uses
  LazIDEIntf, SrcEditorIntf, ProjectIntf, WorkflowLog;

Function CapText(Const TextValue: String; MaxChars: Integer): String;
Begin
  If Length(TextValue) <= MaxChars Then
    Result := TextValue
  Else
    Result := Copy(TextValue, 1, MaxChars) + LineEnding +
      '[… truncated at ' + IntToStr(MaxChars) + ' characters …]';
End;

Function BuildActiveEditorSection: String;
Var
  Ed: TSourceEditorInterface;
  Sel, Src: String;
  CursorPos: TPoint;
Begin
  Result := '';
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      Result := 'Active editor: (source editor manager unavailable)';
      Exit;
    End;
  Ed := SourceEditorManagerIntf.ActiveEditor;
  If Not Assigned(Ed) Then
    Begin
      Result := 'Active editor: (none)';
      Exit;
    End;
  CursorPos := Ed.CursorTextXY;
  Result :=
    'Active editor: ' + Ed.FileName + LineEnding +
    Format('Cursor: line %d, column %d', [CursorPos.Y, CursorPos.X]) + LineEnding +
    'Modified: ' + BoolToStr(Ed.Modified, True);
  Sel := Ed.Selection;
  If Trim(Sel) <> '' Then
    Result := Result + LineEnding + LineEnding +
      'Selected text:' + LineEnding +
      CapText(Sel, AssistantContextMaxActiveChars)
  Else
    Begin
      Src := Ed.SourceText;
      If Src = '' Then
        Src := Ed.Lines.Text;
      Result := Result + LineEnding + LineEnding +
        'Full source of active editor:' + LineEnding +
        CapText(Src, AssistantContextMaxActiveChars);
    End;
End;

Function BuildProjectFilesSection: String;
Var
  Proj: TLazProject;
  I, Listed: Integer;
  Fn: String;
  Lines: TStringList;
Begin
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Begin
      Result := 'Project: (LazarusIDE unavailable)';
      Exit;
    End;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Begin
      Result := 'Project: (no active project)';
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    If Assigned(Proj.MainFile) Then
      Lines.Add('Main file: ' + Proj.MainFile.Filename)
    Else
      Lines.Add('Main file: (none)');
    Lines.Add('Project info: ' + Proj.ProjectInfoFile);
    Lines.Add('Files in project:');
    Listed := 0;
    For I := 0 To Proj.FileCount - 1 Do
      Begin
        If Not Assigned(Proj.Files[I]) Then
          Continue;
        Fn := Proj.Files[I].Filename;
        If Fn = '' Then
          Continue;
        Inc(Listed);
        If Listed <= AssistantContextMaxProjectFiles Then
          Lines.Add('  ' + Fn);
      End;
    If Listed > AssistantContextMaxProjectFiles Then
      Lines.Add(Format('  … and %d more files (list capped at %d)',
        [Listed - AssistantContextMaxProjectFiles, AssistantContextMaxProjectFiles]));
    If Listed = 0 Then
      Lines.Add('  (no files listed)');
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Function BuildIDEContextBlock: String;
Begin
  Result :=
    '----- begin IDE context -----' + LineEnding +
    'The following is live context from the Lazarus IDE. Prefer it when answering about the code or project.' + LineEnding +
    LineEnding +
    TrimRight(BuildActiveEditorSection) + LineEnding +
    LineEnding +
    TrimRight(BuildProjectFilesSection) + LineEnding +
    '----- end IDE context -----';
  WorkflowLogger.Debug('AssistantIDEContext', 'Built IDE context block (' + IntToStr(Length(Result)) + ' chars)');
End;

End.
