Unit AssistantPlan;

{ Plan-mode paths, Documents/ workspace, and plan Markdown helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  AssistantDocumentsDirName = 'Documents';
  AssistantDefaultPlanFileName = 'Plan.md';
  AssistantPlanStatusNotStarted = 'not started';
  AssistantPlanStatusInProgress = 'in progress';
  AssistantPlanStatusComplete = 'complete';

Function ProjectDocumentsDir: String;
Function EnsureProjectDocumentsDir(Out ErrorText: String): Boolean;
Function DefaultPlanRelativePath: String;
Function ResolvePlanPath(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;
Function IsMarkdownPath(Const Path: String): Boolean;
Function ProjectRelativePath(Const AbsolutePath: String): String;
Function ListProjectMarkdownPlans(Out Paths: TStringList; Out ErrorText: String): Boolean;
Function DefaultNewPlanMarkdown(Const Title: String = ''): String;
Function WriteMarkdownFile(Const RelativeOrAbsolute, Content: String; OpenAfter: Boolean;
  Out Resolved: String; Out ErrorText: String): Boolean;
Function ReplaceInMarkdownFile(Const RelativeOrAbsolute, OldText, NewText: String;
  ReplaceAll, OpenAfter: Boolean; Out Resolved: String; Out ErrorText: String;
  Out ReplaceCount: Integer): Boolean;

Implementation

Uses
  LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf, AssistantMarkdownForm, WorkflowLog;

Function PlanProjectRoot: String;
Var
  Proj: TLazProject;
Begin
  { Local copy of project-root discovery to avoid unit cycles with AssistantTools. }
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Exit;
  If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
    Result := ExtractFilePath(ExpandFileName(Proj.MainFile.Filename));
  If Result = '' Then
    Result := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  Result := IncludeTrailingPathDelimiter(Result);
End;

Function PlanIsUnderRoot(Const Root, Candidate: String): Boolean;
Var
  R, C: String;
Begin
  R := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  C := ExpandFileName(Candidate);
  {$IFDEF WINDOWS}
  Result := SameText(Copy(C, 1, Length(R)), R) Or
    SameText(ExcludeTrailingPathDelimiter(C), ExcludeTrailingPathDelimiter(R));
  {$ELSE}
  Result := (Copy(C, 1, Length(R)) = R) Or
    (ExcludeTrailingPathDelimiter(C) = ExcludeTrailingPathDelimiter(R));
  {$ENDIF}
End;

Function PlanResolveUnderProject(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;
Var
  Root, Cand: String;
Begin
  Result := False;
  Resolved := '';
  ErrorText := '';
  Root := PlanProjectRoot;
  If Root = '' Then
    Begin
      ErrorText := 'No active Lazarus project is open.';
      Exit;
    End;
  Cand := Trim(RelativeOrAbsolute);
  If Cand = '' Then
    Cand := Root
  Else If FilenameIsAbsolute(Cand) Then
    Cand := ExpandFileName(Cand)
  Else
    Cand := ExpandFileName(Root + Cand);
  If Not PlanIsUnderRoot(Root, Cand) Then
    Begin
      ErrorText := 'Path is outside the active project root: ' + Cand;
      Exit;
    End;
  Resolved := Cand;
  Result := True;
End;

Function ProjectDocumentsDir: String;
Var
  Root: String;
Begin
  Root := PlanProjectRoot;
  If Root = '' Then
    Result := ''
  Else
    Result := IncludeTrailingPathDelimiter(Root + AssistantDocumentsDirName);
End;

Function EnsureProjectDocumentsDir(Out ErrorText: String): Boolean;
Var
  Dir: String;
Begin
  Result := False;
  ErrorText := '';
  Dir := ExcludeTrailingPathDelimiter(ProjectDocumentsDir);
  If Dir = '' Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  If DirectoryExistsUTF8(Dir) Then
    Begin
      Result := True;
      Exit;
    End;
  If ForceDirectoriesUTF8(Dir) Then
    Begin
      Result := True;
      WorkflowLogger.Info('AssistantPlan', 'Created Documents folder: ' + Dir);
    End
  Else
    ErrorText := 'Could not create Documents folder: ' + Dir;
End;

Function DefaultPlanRelativePath: String;
Begin
  Result := AssistantDocumentsDirName + PathDelim + AssistantDefaultPlanFileName;
End;

Function IsMarkdownPath(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.md') Or (Ext = '.markdown') Or (Ext = '.mdown');
End;

Function ProjectRelativePath(Const AbsolutePath: String): String;
Var
  Root, Full: String;
Begin
  Result := AbsolutePath;
  Root := PlanProjectRoot;
  If Root = '' Then
    Exit;
  Full := ExpandFileName(AbsolutePath);
  Root := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  {$IFDEF WINDOWS}
  If SameText(Copy(Full, 1, Length(Root)), Root) Then
    Result := Copy(Full, Length(Root) + 1, MaxInt)
  Else If SameText(ExcludeTrailingPathDelimiter(Full), ExcludeTrailingPathDelimiter(Root)) Then
    Result := '';
  {$ELSE}
  If Copy(Full, 1, Length(Root)) = Root Then
    Result := Copy(Full, Length(Root) + 1, MaxInt)
  Else If ExcludeTrailingPathDelimiter(Full) = ExcludeTrailingPathDelimiter(Root) Then
    Result := '';
  {$ENDIF}
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
End;

Function ResolvePlanPath(Const RelativeOrAbsolute: String; Out Resolved: String;
  Out ErrorText: String): Boolean;
Var
  Cand: String;
Begin
  Result := False;
  Resolved := '';
  ErrorText := '';
  Cand := Trim(RelativeOrAbsolute);
  If Cand = '' Then
    Cand := DefaultPlanRelativePath;
  If Not PlanResolveUnderProject(Cand, Resolved, ErrorText) Then
    Exit;
  If Not IsMarkdownPath(Resolved) Then
    Begin
      ErrorText := 'Plan tools only allow Markdown paths (.md): ' + Resolved;
      Resolved := '';
      Exit;
    End;
  Result := True;
End;

Function ListProjectMarkdownPlans(Out Paths: TStringList; Out ErrorText: String): Boolean;
Var
  Root, Rel, LowerRel, DocsPrefix: String;
  Files, DocsFirst, Rest: TStringList;
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  Paths := TStringList.Create;
  Root := PlanProjectRoot;
  If Root = '' Then
    Begin
      ErrorText := 'No active Lazarus project.';
      Exit;
    End;
  DocsPrefix := LowerCase(AssistantDocumentsDirName + '/');
  DocsFirst := TStringList.Create;
  Rest := TStringList.Create;
  Files := FindAllFiles(Root, '*.md', True);
  Try
    DocsFirst.Sorted := True;
    DocsFirst.Duplicates := dupIgnore;
    Rest.Sorted := True;
    Rest.Duplicates := dupIgnore;
    For I := 0 To Files.Count - 1 Do
      Begin
        If Not IsMarkdownPath(Files[I]) Then
          Continue;
        Rel := ProjectRelativePath(Files[I]);
        If Rel = '' Then
          Continue;
        LowerRel := LowerCase(StringReplace(Rel, '\', '/', [rfReplaceAll]));
        If Pos(DocsPrefix, LowerRel) = 1 Then
          DocsFirst.Add(Rel)
        Else
          Rest.Add(Rel);
      End;
    For I := 0 To DocsFirst.Count - 1 Do
      Paths.Add(DocsFirst[I]);
    For I := 0 To Rest.Count - 1 Do
      Paths.Add(Rest[I]);
    Result := True;
  Finally
    Files.Free;
    DocsFirst.Free;
    Rest.Free;
  End;
End;

Function DefaultNewPlanMarkdown(Const Title: String): String;
Var
  T: String;
Begin
  T := Trim(Title);
  If T = '' Then
    T := 'Project Plan';
  Result :=
    '# ' + T + LineEnding +
    LineEnding +
    'Generated by Project Assistant (Plan mode).' + LineEnding +
    LineEnding +
    'Work packages use a `##` heading and a **Status:** line so Code mode can ' +
    'scan this file for TODO tiles.' + LineEnding +
    LineEnding +
    'Status values: `not started` | `in progress` | `complete`' + LineEnding +
    LineEnding +
    '## 1. Overview' + LineEnding +
    LineEnding +
    'Status: ' + AssistantPlanStatusNotStarted + LineEnding +
    LineEnding +
    'Describe goals, constraints, and success criteria.' + LineEnding +
    LineEnding +
    '## 2. First work package' + LineEnding +
    LineEnding +
    'Status: ' + AssistantPlanStatusNotStarted + LineEnding +
    LineEnding +
    'Concrete implementation notes for the first slice of work.' + LineEnding;
End;

Function WriteMarkdownFile(Const RelativeOrAbsolute, Content: String; OpenAfter: Boolean;
  Out Resolved: String; Out ErrorText: String): Boolean;
Var
  Dir: String;
  SL: TStringList;
Begin
  Result := False;
  Resolved := '';
  ErrorText := '';
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Dir := ExtractFilePath(Resolved);
  If (Dir <> '') And (Not DirectoryExistsUTF8(Dir)) Then
    If Not ForceDirectoriesUTF8(Dir) Then
      Begin
        ErrorText := 'Could not create directory: ' + Dir;
        Exit;
      End;
  SL := TStringList.Create;
  Try
    Try
      SL.Text := Content;
      SL.SaveToFile(Resolved);
      Result := True;
      WorkflowLogger.Info('AssistantPlan', 'Wrote Markdown: ' + Resolved);
      If OpenAfter Then
        OpenMarkdownDocument(Resolved);
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function ReplaceInMarkdownFile(Const RelativeOrAbsolute, OldText, NewText: String;
  ReplaceAll, OpenAfter: Boolean; Out Resolved: String; Out ErrorText: String;
  Out ReplaceCount: Integer): Boolean;
Var
  SL: TStringList;
  Body: String;
  P: Integer;
Begin
  Result := False;
  Resolved := '';
  ErrorText := '';
  ReplaceCount := 0;
  If OldText = '' Then
    Begin
      ErrorText := 'old_text must not be empty.';
      Exit;
    End;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Markdown file not found: ' + Resolved;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Resolved);
      Body := SL.Text;
      If ReplaceAll Then
        Begin
          ReplaceCount := 0;
          P := 1;
          While P <= Length(Body) Do
            If Copy(Body, P, Length(OldText)) = OldText Then
              Begin
                Inc(ReplaceCount);
                Inc(P, Length(OldText));
              End
            Else
              Inc(P);
          If ReplaceCount < 1 Then
            Begin
              ErrorText := 'old_text not found in ' + Resolved;
              Exit;
            End;
          Body := StringReplace(Body, OldText, NewText, [rfReplaceAll]);
        End
      Else
        Begin
          P := Pos(OldText, Body);
          If P < 1 Then
            Begin
              ErrorText := 'old_text not found in ' + Resolved;
              Exit;
            End;
          Body := Copy(Body, 1, P - 1) + NewText + Copy(Body, P + Length(OldText), MaxInt);
          ReplaceCount := 1;
        End;
      SL.Text := Body;
      SL.SaveToFile(Resolved);
      Result := True;
      WorkflowLogger.Info('AssistantPlan',
        Format('Updated Markdown %s (%d replacement(s))', [Resolved, ReplaceCount]));
      If OpenAfter Then
        OpenMarkdownDocument(Resolved);
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

End.
