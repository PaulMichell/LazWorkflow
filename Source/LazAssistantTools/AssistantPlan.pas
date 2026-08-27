Unit AssistantPlan;

{ Plan-mode paths, Documents/ workspace, and plan Markdown helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Const
  AssistantDocumentsDirName = 'Documents';
  AssistantDefaultPlanFileName = 'Plan.md';
  AssistantPlanStatusNotStarted = 'not started';
  AssistantPlanStatusInProgress = 'in progress';
  AssistantPlanStatusComplete = 'complete';

Type
  TPlanSectionStatus = (pssUnknown, pssNotStarted, pssInProgress, pssComplete);

  { One ## work package from a plan Markdown file (Build mode TODO tile). }
  TPlanSection = Class
  Public
    Title: String;
    Status: TPlanSectionStatus;
    StatusText: String;
    HeadingLineIndex: Integer; { 0-based line of ## heading }
    StatusLineIndex: Integer; { 0-based line of Status:; -1 if missing }
  End;

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

Function PlanSectionStatusToStr(Status: TPlanSectionStatus): String;
Function StrToPlanSectionStatus(Const StatusText: String): TPlanSectionStatus;
Function FormatPlanSectionTile(Section: TPlanSection; Index: Integer): String;
{ Scan AbsolutePath (or resolved relative) into Sections (of TPlanSection; caller owns list). }
Function ScanPlanSections(Const RelativeOrAbsolute: String; Sections: TObjectList;
  Out ErrorText: String): Boolean;
{ Rewrite Status: line for Sections[SectionIndex]; rescans not performed. }
Function SetPlanSectionStatus(Const RelativeOrAbsolute: String; SectionIndex: Integer;
  NewStatus: TPlanSectionStatus; Out ErrorText: String): Boolean;
{ Body of one section (heading through line before next ##/###), for Build "Work on this". }
Function GetPlanSectionBody(Const RelativeOrAbsolute: String; SectionIndex: Integer;
  Out BodyText: String; Out ErrorText: String): Boolean;

Implementation

Uses
  LazFileUtils, FileUtil, AssistantMarkdownForm, WorkflowLog, AssistantConversation;

Function PlanProjectRoot: String;
Begin
  { Independent of AssistantTools to avoid a unit cycle. }
  Result := ProjectAssistantRoot;
End;

Function PlanIsUnderRoot(Const Root, Candidate: String): Boolean;
Var
  LexRoot, LexCand, Probe, PhysRoot, PhysCand: String;
Begin
  Result := False;
  LexRoot := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  LexCand := ExpandFileName(Candidate);
  If (LexCand = '') Or ((CompareFilenames(Copy(LexCand, 1, Length(LexRoot)), LexRoot) <> 0) And
     (CompareFilenames(ExcludeTrailingPathDelimiter(LexCand), ExcludeTrailingPathDelimiter(LexRoot)) <> 0)) Then
    Exit;
  PhysRoot := GetPhysicalFilename(ExcludeTrailingPathDelimiter(LexRoot), pfeOriginal);
  If PhysRoot = '' Then
    PhysRoot := ExcludeTrailingPathDelimiter(LexRoot);
  PhysRoot := IncludeTrailingPathDelimiter(ExpandFileName(PhysRoot));
  Probe := LexCand;
  While (Probe <> '') And (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Do
    Begin
      If ExtractFileDir(Probe) = Probe Then
        Break;
      Probe := ExcludeTrailingPathDelimiter(ExtractFileDir(Probe));
    End;
  If (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Then
    Begin
      Result := True;
      Exit;
    End;
  PhysCand := GetPhysicalFilename(Probe, pfeEmpty);
  If PhysCand = '' Then
    Exit;
  PhysCand := ExpandFileName(PhysCand);
  Result := (CompareFilenames(Copy(PhysCand, 1, Length(PhysRoot)), PhysRoot) = 0) Or
    (CompareFilenames(ExcludeTrailingPathDelimiter(PhysCand), ExcludeTrailingPathDelimiter(PhysRoot)) = 0);
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
    'Work packages use a `##` heading and a **Status:** line so Build mode can ' +
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
      { Always refresh an open viewer; open a new one when requested. }
      If OpenAfter Or Assigned(FindMarkdownDocument(Resolved)) Then
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
      If OpenAfter Or Assigned(FindMarkdownDocument(Resolved)) Then
        OpenMarkdownDocument(Resolved);
    Except
      On E: Exception Do
        ErrorText := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function PlanSectionStatusToStr(Status: TPlanSectionStatus): String;
Begin
  Case Status Of
    pssNotStarted: Result := AssistantPlanStatusNotStarted;
    pssInProgress: Result := AssistantPlanStatusInProgress;
    pssComplete: Result := AssistantPlanStatusComplete;
  Else
    Result := 'unknown';
  End;
End;

Function StrToPlanSectionStatus(Const StatusText: String): TPlanSectionStatus;
Var
  T: String;
Begin
  T := LowerCase(Trim(StatusText));
  T := StringReplace(T, '*', '', [rfReplaceAll]);
  T := Trim(T);
  If (T = AssistantPlanStatusNotStarted) Or (T = 'todo') Or (T = 'pending') Then
    Result := pssNotStarted
  Else If (T = AssistantPlanStatusInProgress) Or (T = 'wip') Or (T = 'doing') Then
    Result := pssInProgress
  Else If (T = AssistantPlanStatusComplete) Or (T = 'done') Or (T = 'finished') Then
    Result := pssComplete
  Else
    Result := pssUnknown;
End;

Function FormatPlanSectionTile(Section: TPlanSection; Index: Integer): String;
Var
  StatusLabel: String;
Begin
  If Not Assigned(Section) Then
    Begin
      Result := '';
      Exit;
    End;
  Case Section.Status Of
    pssNotStarted: StatusLabel := 'Not started';
    pssInProgress: StatusLabel := 'In progress';
    pssComplete: StatusLabel := 'Complete';
  Else
    StatusLabel := 'No status';
  End;
  Result := Format('%d. %s — %s', [Index + 1, Section.Title, StatusLabel]);
End;

Function IsMarkdownHeadingLine(Const Line: String; Out Title: String): Boolean;
Var
  S: String;
  Level: Integer;
Begin
  Result := False;
  Title := '';
  S := Trim(Line);
  If Length(S) < 3 Then
    Exit;
  If S[1] <> '#' Then
    Exit;
  Level := 0;
  While (Level < Length(S)) And (S[Level + 1] = '#') Do
    Inc(Level);
  { Work packages: ## or ### (not # document title alone). }
  If (Level < 2) Or (Level > 3) Then
    Exit;
  Title := Trim(Copy(S, Level + 1, MaxInt));
  While (Title <> '') And (Title[1] = ' ') Do
    Delete(Title, 1, 1);
  If Title = '' Then
    Exit;
  Result := True;
End;

Function ParseStatusLine(Const Line: String; Out StatusText: String): Boolean;
Var
  S, Lower: String;
  P: Integer;
Begin
  Result := False;
  StatusText := '';
  S := Trim(Line);
  S := StringReplace(S, '**', '', [rfReplaceAll]);
  S := StringReplace(S, '*', '', [rfReplaceAll]);
  S := Trim(S);
  Lower := LowerCase(S);
  If Pos('status:', Lower) <> 1 Then
    Exit;
  P := Pos(':', S);
  If P < 1 Then
    Exit;
  StatusText := Trim(Copy(S, P + 1, MaxInt));
  Result := StatusText <> '';
End;

Function ScanPlanSections(Const RelativeOrAbsolute: String; Sections: TObjectList;
  Out ErrorText: String): Boolean;
Var
  Resolved: String;
  SL: TStringList;
  I: Integer;
  Title, StatusText: String;
  Section: TPlanSection;
  J: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(Sections) Then
    Begin
      ErrorText := 'Sections list is nil.';
      Exit;
    End;
  Sections.Clear;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      ErrorText := 'Plan file not found: ' + Resolved;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Resolved);
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          Exit;
        End;
    End;
    I := 0;
    While I < SL.Count Do
      Begin
        If IsMarkdownHeadingLine(SL[I], Title) Then
          Begin
            Section := TPlanSection.Create;
            Section.Title := Title;
            Section.HeadingLineIndex := I;
            Section.StatusLineIndex := -1;
            Section.Status := pssUnknown;
            Section.StatusText := '';
            { First non-empty line under heading may be Status:. }
            J := I + 1;
            While J < SL.Count Do
              Begin
                If IsMarkdownHeadingLine(SL[J], Title) Then
                  Break;
                If Trim(SL[J]) = '' Then
                  Begin
                    Inc(J);
                    Continue;
                  End;
                If ParseStatusLine(SL[J], StatusText) Then
                  Begin
                    Section.StatusLineIndex := J;
                    Section.StatusText := StatusText;
                    Section.Status := StrToPlanSectionStatus(StatusText);
                  End;
                Break;
              End;
            Sections.Add(Section);
          End;
        Inc(I);
      End;
    Result := True;
    WorkflowLogger.Info('AssistantPlan',
      Format('Scanned %d plan section(s) from %s', [Sections.Count, Resolved]));
  Finally
    SL.Free;
  End;
End;

Function SetPlanSectionStatus(Const RelativeOrAbsolute: String; SectionIndex: Integer;
  NewStatus: TPlanSectionStatus; Out ErrorText: String): Boolean;
Var
  Resolved: String;
  Sections: TObjectList;
  Section: TPlanSection;
  SL: TStringList;
  StatusLine: String;
Begin
  Result := False;
  ErrorText := '';
  If NewStatus = pssUnknown Then
    Begin
      ErrorText := 'Cannot set status to unknown.';
      Exit;
    End;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Sections := TObjectList.Create(True);
  Try
    If Not ScanPlanSections(Resolved, Sections, ErrorText) Then
      Exit;
    If (SectionIndex < 0) Or (SectionIndex >= Sections.Count) Then
      Begin
        ErrorText := 'Section index out of range.';
        Exit;
      End;
    Section := TPlanSection(Sections[SectionIndex]);
    StatusLine := 'Status: ' + PlanSectionStatusToStr(NewStatus);
    SL := TStringList.Create;
    Try
      Try
        SL.LoadFromFile(Resolved);
        If Section.StatusLineIndex >= 0 Then
          Begin
            If Section.StatusLineIndex >= SL.Count Then
              Begin
                ErrorText := 'Status line index invalid after load.';
                Exit;
              End;
            SL[Section.StatusLineIndex] := StatusLine;
          End
        Else
          Begin
            { Insert blank line + Status: immediately under the heading. }
            If Section.HeadingLineIndex >= SL.Count Then
              Begin
                ErrorText := 'Heading line index invalid after load.';
                Exit;
              End;
            If (Section.HeadingLineIndex + 1 < SL.Count) And
              (Trim(SL[Section.HeadingLineIndex + 1]) = '') Then
              SL.Insert(Section.HeadingLineIndex + 2, StatusLine)
            Else
              Begin
                SL.Insert(Section.HeadingLineIndex + 1, '');
                SL.Insert(Section.HeadingLineIndex + 2, StatusLine);
              End;
          End;
        SL.SaveToFile(Resolved);
        Result := True;
        WorkflowLogger.Info('AssistantPlan',
          Format('Set section "%s" to %s in %s',
            [Section.Title, PlanSectionStatusToStr(NewStatus), Resolved]));
        { Reload open viewer only — do not re-enter full OpenMarkdownDocument create path. }
        ReloadMarkdownDocument(Resolved, True);
      Except
        On E: Exception Do
          ErrorText := E.Message;
      End;
    Finally
      SL.Free;
    End;
  Finally
    Sections.Free;
  End;
End;

Function GetPlanSectionBody(Const RelativeOrAbsolute: String; SectionIndex: Integer;
  Out BodyText: String; Out ErrorText: String): Boolean;
Var
  Resolved: String;
  Sections: TObjectList;
  Section, NextSection: TPlanSection;
  SL: TStringList;
  FirstLine, LastLine, I: Integer;
Begin
  Result := False;
  BodyText := '';
  ErrorText := '';
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Sections := TObjectList.Create(True);
  Try
    If Not ScanPlanSections(Resolved, Sections, ErrorText) Then
      Exit;
    If (SectionIndex < 0) Or (SectionIndex >= Sections.Count) Then
      Begin
        ErrorText := 'Section index out of range.';
        Exit;
      End;
    Section := TPlanSection(Sections[SectionIndex]);
    FirstLine := Section.HeadingLineIndex;
    If SectionIndex + 1 < Sections.Count Then
      Begin
        NextSection := TPlanSection(Sections[SectionIndex + 1]);
        LastLine := NextSection.HeadingLineIndex - 1;
      End
    Else
      LastLine := High(Integer);
    SL := TStringList.Create;
    Try
      Try
        SL.LoadFromFile(Resolved);
        If FirstLine >= SL.Count Then
          Begin
            ErrorText := 'Heading line out of range.';
            Exit;
          End;
        If LastLine >= SL.Count Then
          LastLine := SL.Count - 1;
        BodyText := '';
        For I := FirstLine To LastLine Do
          Begin
            If BodyText <> '' Then
              BodyText := BodyText + LineEnding;
            BodyText := BodyText + SL[I];
          End;
        While (Length(BodyText) > 0) And
          ((BodyText[Length(BodyText)] = #10) Or (BodyText[Length(BodyText)] = #13)) Do
          SetLength(BodyText, Length(BodyText) - 1);
        Result := Trim(BodyText) <> '';
        If Not Result Then
          ErrorText := 'Section body is empty.';
      Except
        On E: Exception Do
          ErrorText := E.Message;
      End;
    Finally
      SL.Free;
    End;
  Finally
    Sections.Free;
  End;
End;

End.
