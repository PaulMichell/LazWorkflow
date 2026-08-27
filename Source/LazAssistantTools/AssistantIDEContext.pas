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
  { After several turns, only attach a light summary so history stays under the
    model token limit (full file can be re-read via tools). }
  AssistantContextMaxActiveCharsLight = 8000;
  AssistantContextMaxProjectFiles = 250;

Function BuildIDEContextBlock: String;
{ Smaller attach for long conversations (cursor + selection or short head of file). }
Function BuildIDEContextBlockLight: String;
{ Project-relative dirty editor buffers plus git porcelain paths, one per line. }
Function FormatChangedProjectFiles: String;

Implementation

Uses
  Process, LazFileUtils, FileUtil, LazIDEIntf, SrcEditorIntf, ProjectIntf, WorkflowLog,
  AssistantConversation;

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

Function ProjectRootForContext: String;
Begin
  Result := ProjectAssistantRoot;
End;

Function AddUniqueLine(Lines: TStrings; Const Item: String): Boolean;
Var
  Line: String;
Begin
  Result := False;
  Line := Trim(Item);
  Line := StringReplace(Line, '\', '/', [rfReplaceAll]);
  If Line = '' Then
    Exit;
  If Lines.IndexOf(Line) >= 0 Then
    Exit;
  Lines.Add(Line);
  Result := True;
End;

Procedure AddEditorModifiedFiles(Const Root: String; Files: TStrings);
Var
  I: Integer;
  Ed: TSourceEditorInterface;
  FullPath, Rel: String;
Begin
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Ed := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Ed) Or (Not Ed.Modified) Then
        Continue;
      FullPath := ExpandFileName(Ed.FileName);
      If FullPath = '' Then
        Continue;
      If Root <> '' Then
        Rel := CreateRelativePath(FullPath, Root, True)
      Else
        Rel := FullPath;
      AddUniqueLine(Files, Rel);
    End;
End;

Procedure AddGitPorcelainFiles(Const Root: String; Files: TStrings);
Var
  Proc: TProcess;
  OutputStream: TStringStream;
  Bytes: Array[0..2047] Of Byte;
  N, I: Integer;
  Lines: TStringList;
  Line, Path: String;
Begin
  If (Root = '') Or (Not DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(Root))) Then
    Exit;
  Proc := TProcess.Create(Nil);
  OutputStream := TStringStream.Create('');
  Lines := TStringList.Create;
  Try
    FillChar(Bytes, SizeOf(Bytes), 0);
    Proc.Executable := FindDefaultExecutablePath('git');
    If Proc.Executable = '' Then
      Exit;
    Proc.CurrentDirectory := ExcludeTrailingPathDelimiter(Root);
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.ShowWindow := swoHIDE;
    Proc.Parameters.Add('status');
    Proc.Parameters.Add('--porcelain');
    Try
      Proc.Execute;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
          N := Proc.Output.NumBytesAvailable;
          If N > Length(Bytes) Then
            N := Length(Bytes);
          If N > 0 Then
            Begin
              N := Proc.Output.Read(Bytes, N);
              If N > 0 Then
                OutputStream.Write(Bytes[0], N);
            End
          Else
            Sleep(5);
        End;
      Proc.WaitOnExit;
    Except
      Exit;
    End;
    Lines.Text := OutputStream.DataString;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Length(Line) < 4 Then
          Continue;
        Path := Trim(Copy(Line, 4, MaxInt));
        If Pos(' -> ', Path) > 0 Then
          Path := Trim(Copy(Path, Pos(' -> ', Path) + 4, MaxInt));
        If (Length(Path) >= 2) And (Path[1] = '"') And (Path[Length(Path)] = '"') Then
          Path := Copy(Path, 2, Length(Path) - 2);
        AddUniqueLine(Files, Path);
      End;
  Finally
    Lines.Free;
    OutputStream.Free;
    Proc.Free;
  End;
End;

Function FormatChangedProjectFiles: String;
Var
  Root: String;
  Files: TStringList;
  I, Cap: Integer;
Begin
  Result := '';
  Files := TStringList.Create;
  Try
    Files.Duplicates := dupIgnore;
    Files.Sorted := False;
    Root := ProjectRootForContext;
    AddEditorModifiedFiles(Root, Files);
    AddGitPorcelainFiles(Root, Files);
    Cap := Files.Count;
    If Cap > 40 Then
      Cap := 40;
    For I := 0 To Cap - 1 Do
      Begin
        If Result <> '' Then
          Result := Result + LineEnding;
        Result := Result + '- ' + Files[I];
      End;
    If Files.Count > Cap Then
      Result := Result + LineEnding + Format('- … and %d more', [Files.Count - Cap]);
  Finally
    Files.Free;
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

Function BuildIDEContextBlockLight: String;
Var
  Ed: TSourceEditorInterface;
  Sel: String;
  CursorPos: TPoint;
  Head: String;
Begin
  Result :=
    '----- begin IDE context (light) -----' + LineEnding +
    'Long conversation: only a short editor summary is attached. Use read_file for full sources.' +
    LineEnding;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      Result := Result + 'Active editor: (unavailable)' + LineEnding +
        '----- end IDE context -----';
      Exit;
    End;
  Ed := SourceEditorManagerIntf.ActiveEditor;
  If Not Assigned(Ed) Then
    Begin
      Result := Result + 'Active editor: (none)' + LineEnding +
        '----- end IDE context -----';
      Exit;
    End;
  CursorPos := Ed.CursorTextXY;
  Result := Result +
    'Active editor: ' + Ed.FileName + LineEnding +
    Format('Cursor: line %d, column %d', [CursorPos.Y, CursorPos.X]) + LineEnding +
    'Modified: ' + BoolToStr(Ed.Modified, True) + LineEnding;
  Sel := Ed.Selection;
  If Trim(Sel) <> '' Then
    Result := Result + LineEnding + 'Selected text:' + LineEnding +
      CapText(Sel, AssistantContextMaxActiveCharsLight)
  Else
    Begin
      Head := Ed.SourceText;
      If Head = '' Then
        Head := Ed.Lines.Text;
      Result := Result + LineEnding + 'Start of active file (truncated):' + LineEnding +
        CapText(Head, AssistantContextMaxActiveCharsLight);
    End;
  Result := Result + LineEnding + '----- end IDE context -----';
  WorkflowLogger.Debug('AssistantIDEContext',
    'Built light IDE context block (' + IntToStr(Length(Result)) + ' chars)');
End;

End.
