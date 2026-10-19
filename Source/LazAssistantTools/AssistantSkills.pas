Unit AssistantSkills;

{ Load skills named in the installation settings. A file on disk is not a skill until it is added.
  Project directories are not scanned. The prompt catalog is cached until the installed list
  or a file age changes (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  AssistantSkillNoneCaption = '(None)';
  AssistantDefaultSkillName = 'free-pascal-engineer';
  { Process guide attached beside the engineer skill. Not a Pascal style skill. }
  AssistantMethodologySkillName = 'agentic-development-methodology';
  { Retired name of that guide. Leave a user-level copy in place; do not load both. }
  AssistantRetiredBehaviourSkillName = 'BEHAVE';
  { Soft cap so a huge skill cannot blow the entire context window alone. }
  AssistantSkillMaxChars = 120000;

Type
  TAssistantSkillInfo = Record
    Name: String;
    Description: String;
    WhenToUse: String;
    SkillFile: String;
  End;

  TAssistantSkillList = Array Of TAssistantSkillInfo;

Function AssistantUserSkillsRoot: String;
Function SkillNameIsSafe(Const SkillName: String): Boolean;
/// User catalog file ~/.grok/skills/Name/SKILL.md. A non-empty project root is refused.
Function ResolveSkillFile(Const SkillName, ProjectRoot: String): String;
/// Installed skills from the settings enumerator. Project directories are not scanned.
Function ListGuidanceDocuments(Const ProjectRoot: String): TAssistantSkillList;
/// Catalog lines for the system prompt. Cached until the installed list or a file age changes.
Function SkillCatalogText: String;
/// Directory name when FilePath is one SKILL.md under a known catalog root, otherwise empty.
Function CatalogNameForSkillFile(Const FilePath, ProjectRoot: String): String;
/// Name written in the document. The file stem is used only when that name is missing or unsafe.
Function SkillDocumentName(Const FilePath: String): String;
/// Safe skill name derived from a file name. Falls back to guidance.
Function SkillNameFromFile(Const FilePath: String): String;
Function LoadUserSkillBody(Const SkillName: String; Out BodyText: String; Out ErrorText: String): Boolean;
Function LoadSkillBody(Const SkillName, ProjectRoot: String; Out BodyText: String; Out ErrorText: String): Boolean;
/// Drops BEHAVE when the replacement methodology skill is also listed. Leaves the files in place.
Procedure OmitRetiredBehaviourGuide(Names: TStrings);
Function FormatSkillCatalog(Const Skills: TAssistantSkillList): String;
Function BuildSystemPromptWithSkill(Const BasePrompt, SkillName: String): String;

Type
  { Optional. A non-empty result is the file for that skill name. }
  TSkillFileResolver = Function(Const SkillName: String): String;
  { Optional. Fills Names and Paths with added guidance files. }
  TSkillFileEnumerator = Procedure(Names, Paths: TStrings);

Var
  SkillFileResolver: TSkillFileResolver;
  SkillFileEnumerator: TSkillFileEnumerator;

Implementation

Uses
  LazFileUtils, WorkflowLog;

Function AssistantUserSkillsRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetUserDir) + '.grok' + PathDelim + 'skills';
End;

Function SkillNameIsSafe(Const SkillName: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := False;
  If (SkillName = '') Or (Length(SkillName) > 64) Or (SkillName = '.') Or (SkillName = '..') Then
    Exit;
  For I := 1 To Length(SkillName) Do
    Begin
      C := SkillName[I];
      If Not (((C >= 'A') And (C <= 'Z')) Or ((C >= 'a') And (C <= 'z')) Or
         ((C >= '0') And (C <= '9')) Or (C = '.') Or (C = '_') Or (C = '-')) Then
        Exit;
    End;
  Result := True;
End;

Function PathIsInsideRoot(Const Root, Candidate: String): Boolean;
Var
  LexRoot, LexCand, PhysRoot, PhysFile: String;
Begin
  Result := False;
  LexRoot := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  LexCand := ExpandFileName(Candidate);
  If CompareFilenames(Copy(LexCand, 1, Length(LexRoot)), LexRoot) <> 0 Then
    Exit;
  PhysRoot := GetPhysicalFilename(ExcludeTrailingPathDelimiter(Root), pfeOriginal);
  If PhysRoot = '' Then
    PhysRoot := ExcludeTrailingPathDelimiter(Root);
  PhysRoot := IncludeTrailingPathDelimiter(ExpandFileName(PhysRoot));
  If FileExistsUTF8(LexCand) Then
    Begin
      PhysFile := GetPhysicalFilename(LexCand, pfeEmpty);
      If PhysFile = '' Then
        Exit;
      PhysFile := ExpandFileName(PhysFile);
      If CompareFilenames(Copy(PhysFile, 1, Length(PhysRoot)), PhysRoot) <> 0 Then
        Exit;
    End;
  Result := True;
End;

Function ResolveSkillFile(Const SkillName, ProjectRoot: String): String;
Var
  Candidate: String;
Begin
  Result := '';
  If Not SkillNameIsSafe(SkillName) Then
    Exit;
  { A project root must not select a file. Installation settings name the file. }
  If Trim(ProjectRoot) <> '' Then
    Exit;
  Candidate := IncludeTrailingPathDelimiter(AssistantUserSkillsRoot) + SkillName + PathDelim + 'SKILL.md';
  If FileExistsUTF8(Candidate) And PathIsInsideRoot(AssistantUserSkillsRoot, Candidate) Then
    Result := Candidate;
End;

Function StripYamlFrontMatter(Const Raw: String): String;
Var
  TextBody, Rest: String;
  EndPos: Integer;
Begin
  TextBody := StringReplace(Raw, #13#10, #10, [rfReplaceAll]);
  TextBody := StringReplace(TextBody, #13, #10, [rfReplaceAll]);
  If Copy(TextBody, 1, 4) <> '---'#10 Then
    Begin
      Result := Trim(Raw);
      Exit;
    End;
  Rest := Copy(TextBody, 5, MaxInt);
  EndPos := Pos(#10'---'#10, Rest);
  If EndPos < 1 Then
    Begin
      Result := Trim(Raw);
      Exit;
    End;
  Result := Trim(Copy(Rest, EndPos + Length(#10'---'#10), MaxInt));
End;

Function ExtractFrontMatterField(Const Raw, FieldName: String): String;
Var
  TextBody, Block, Line, Key, Val: String;
  EndPos, I, ColonPos: Integer;
  Lines: TStringList;
Begin
  Result := '';
  TextBody := StringReplace(Raw, #13#10, #10, [rfReplaceAll]);
  TextBody := StringReplace(TextBody, #13, #10, [rfReplaceAll]);
  If Copy(TextBody, 1, 4) <> '---'#10 Then
    Exit;
  EndPos := Pos(#10'---'#10, Copy(TextBody, 5, MaxInt));
  If EndPos < 1 Then
    Exit;
  Block := Copy(TextBody, 5, EndPos - 1);
  Lines := TStringList.Create;
  Try
    Lines.Text := Block;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        ColonPos := Pos(':', Line);
        If ColonPos < 1 Then
          Continue;
        Key := Trim(Copy(Line, 1, ColonPos - 1));
        Val := Trim(Copy(Line, ColonPos + 1, MaxInt));
        If (Length(Val) >= 2) And (Val[1] = '"') And (Val[Length(Val)] = '"') Then
          Val := Copy(Val, 2, Length(Val) - 2);
        If SameText(Key, FieldName) Then
          Begin
            Result := Val;
            Exit;
          End;
      End;
  Finally
    Lines.Free;
  End;
End;

Function DeclaredSkillName(Const Raw: String): String;
Begin
  Result := Trim(ExtractFrontMatterField(Raw, 'name'));
  If Not SkillNameIsSafe(Result) Then
    Result := '';
End;

Function SkillNameTaken(Const Skills: TAssistantSkillList; Const SkillName: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To High(Skills) Do
    If SameText(Skills[I].Name, SkillName) Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function SkillIsEnumerated(Const SkillName: String): Boolean;
Var
  Names, Paths: TStringList;
  I: Integer;
Begin
  Result := False;
  If (Trim(SkillName) = '') Or (Not Assigned(SkillFileEnumerator)) Then
    Exit;
  Names := TStringList.Create;
  Paths := TStringList.Create;
  Try
    Names.CaseSensitive := False;
    SkillFileEnumerator(Names, Paths);
    Result := Names.IndexOf(Trim(SkillName)) >= 0;
  Finally
    Paths.Free;
    Names.Free;
  End;
End;

Type
  TSkillBodyCacheEntry = Record
    Name: String;
    FilePath: String;
    Age: LongInt;
    Body: String;
  End;

Var
  { One entry per skill file. A second tagged skill must not replace the first. }
  SkillBodyCache: Array Of TSkillBodyCacheEntry;
  GuidanceCacheSignature: String;
  GuidanceCacheDocuments: TAssistantSkillList;
  GuidanceCacheCatalog: String;
  GuidanceCacheValid: Boolean;

Procedure CollectInstalledGuidance(Names, Paths: TStrings);
Begin
  If Assigned(SkillFileEnumerator) Then
    SkillFileEnumerator(Names, Paths);
End;

Function InstalledGuidanceSignature(Names, Paths: TStrings): String;
Var
  I, Limit: Integer;
Begin
  Result := IntToStr(Names.Count) + #1 + IntToStr(Paths.Count) + #2;
  Limit := Names.Count;
  If Paths.Count < Limit Then
    Limit := Paths.Count;
  For I := 0 To Limit - 1 Do
    Result := Result + Names[I] + #1 + Paths[I] + #1 + IntToStr(FileAge(Paths[I])) + #2;
End;

Function LoadSkillRaw(Const FilePath: String; Out Raw: String): Boolean;
Var
  SL: TStringList;
Begin
  Result := False;
  Raw := '';
  If (Trim(FilePath) = '') Or (Not FileExistsUTF8(FilePath)) Then
    Exit;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(FilePath);
      Raw := SL.Text;
      Result := True;
    Except
      On E: Exception Do
        WorkflowLogger.Warning('AssistantSkills', 'Failed to read ' + FilePath + ': ' + E.Message);
    End;
  Finally
    SL.Free;
  End;
End;

Function PrepareSkillBody(Const SkillName, Raw: String): String;
Begin
  Result := StripYamlFrontMatter(Raw);
  If Result = '' Then
    Result := Trim(Raw);
  If Length(Result) > AssistantSkillMaxChars Then
    Begin
      Result := Copy(Result, 1, AssistantSkillMaxChars) + LineEnding + LineEnding +
        '[Skill truncated at ' + IntToStr(AssistantSkillMaxChars) + ' characters for context size.]';
      WorkflowLogger.Warning('AssistantSkills', 'Skill ' + SkillName + ' truncated for system prompt');
    End;
End;

Function CachedSkillBody(Const SkillFile: String; Age: LongInt; Out BodyText: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  BodyText := '';
  For I := 0 To High(SkillBodyCache) Do
    If SameFileName(SkillBodyCache[I].FilePath, SkillFile) And (SkillBodyCache[I].Age = Age) And
      (SkillBodyCache[I].Body <> '') Then
      Begin
        BodyText := SkillBodyCache[I].Body;
        Result := True;
        Exit;
      End;
End;

Procedure StoreSkillBody(Const SkillName, SkillFile: String; Age: LongInt; Const BodyText: String);
Var
  I: Integer;
Begin
  If (BodyText = '') Or (Trim(SkillFile) = '') Then
    Exit;
  For I := 0 To High(SkillBodyCache) Do
    If SameFileName(SkillBodyCache[I].FilePath, SkillFile) Then
      Begin
        SkillBodyCache[I].Name := SkillName;
        SkillBodyCache[I].Age := Age;
        SkillBodyCache[I].Body := BodyText;
        Exit;
      End;
  SetLength(SkillBodyCache, Length(SkillBodyCache) + 1);
  SkillBodyCache[High(SkillBodyCache)].Name := SkillName;
  SkillBodyCache[High(SkillBodyCache)].FilePath := SkillFile;
  SkillBodyCache[High(SkillBodyCache)].Age := Age;
  SkillBodyCache[High(SkillBodyCache)].Body := BodyText;
End;

Procedure RebuildGuidanceCache(Names, Paths: TStrings; Const Signature: String);
Var
  Info: TAssistantSkillInfo;
  I: Integer;
  Declared, Raw, Body: String;
  Age: LongInt;
Begin
  GuidanceCacheDocuments := Nil;
  For I := 0 To Names.Count - 1 Do
    Begin
      If I >= Paths.Count Then
        Break;
      Raw := '';
      Declared := '';
      Info.Name := '';
      Info.Description := '';
      Info.WhenToUse := '';
      Info.SkillFile := Paths[I];
      If (Trim(Paths[I]) <> '') And FileExistsUTF8(Paths[I]) And LoadSkillRaw(Paths[I], Raw) Then
        Begin
          Declared := DeclaredSkillName(Raw);
          If Declared = '' Then
            Declared := SkillNameFromFile(Paths[I]);
          Info.Name := Declared;
          Info.Description := ExtractFrontMatterField(Raw, 'description');
          Info.WhenToUse := ExtractFrontMatterField(Raw, 'when-to-use');
          If Info.WhenToUse = '' Then
            Info.WhenToUse := ExtractFrontMatterField(Raw, 'when_to_use');
          Age := FileAge(Paths[I]);
          Body := PrepareSkillBody(Declared, Raw);
          StoreSkillBody(Declared, Paths[I], Age, Body);
        End
      Else If (Trim(Paths[I]) <> '') And FileExistsUTF8(Paths[I]) Then
        Declared := SkillNameFromFile(Paths[I])
      Else
        Declared := Trim(Names[I]);
      If Declared = '' Then
        Declared := Trim(Names[I]);
      If (Declared = '') Or SkillNameTaken(GuidanceCacheDocuments, Declared) Then
        Continue;
      Info.Name := Declared;
      If Info.SkillFile = '' Then
        Info.SkillFile := Paths[I];
      SetLength(GuidanceCacheDocuments, Length(GuidanceCacheDocuments) + 1);
      GuidanceCacheDocuments[High(GuidanceCacheDocuments)] := Info;
    End;
  GuidanceCacheCatalog := FormatSkillCatalog(GuidanceCacheDocuments);
  GuidanceCacheSignature := Signature;
  GuidanceCacheValid := True;
End;

Procedure EnsureGuidanceCache;
Var
  Names, Paths: TStringList;
  Signature: String;
Begin
  Names := TStringList.Create;
  Paths := TStringList.Create;
  Try
    CollectInstalledGuidance(Names, Paths);
    Signature := InstalledGuidanceSignature(Names, Paths);
    If GuidanceCacheValid And (Signature = GuidanceCacheSignature) Then
      Exit;
    RebuildGuidanceCache(Names, Paths, Signature);
  Finally
    Paths.Free;
    Names.Free;
  End;
End;

Function ListGuidanceDocuments(Const ProjectRoot: String): TAssistantSkillList;
Begin
  EnsureGuidanceCache;
  Result := GuidanceCacheDocuments;
End;

Function SkillCatalogText: String;
Begin
  EnsureGuidanceCache;
  Result := GuidanceCacheCatalog;
End;

Function CatalogNameForSkillFile(Const FilePath, ProjectRoot: String): String;
Var
  Clean, Dir, Name, ProjectSkills: String;
Begin
  Result := '';
  Clean := Trim(FilePath);
  If Clean = '' Then
    Exit;
  Clean := ExpandFileName(Clean);
  If Not SameText(ExtractFileName(Clean), 'SKILL.md') Then
    Exit;
  If Not FileExistsUTF8(Clean) Then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Clean));
  Name := ExtractFileName(Dir);
  If Not SkillNameIsSafe(Name) Then
    Exit;
  If PathIsInsideRoot(AssistantUserSkillsRoot, Clean) Then
    Exit(Name);
  If Trim(ProjectRoot) = '' Then
    Exit;
  ProjectSkills := IncludeTrailingPathDelimiter(ExpandFileName(Trim(ProjectRoot))) + '.assistant' + PathDelim + 'skills';
  If PathIsInsideRoot(ProjectSkills, Clean) Then
    Result := Name;
End;

Function SkillNameFromFile(Const FilePath: String): String;
Var
  Stem, Clean: String;
  I: Integer;
  C: Char;
Begin
  Stem := ChangeFileExt(ExtractFileName(Trim(FilePath)), '');
  Clean := '';
  For I := 1 To Length(Stem) Do
    Begin
      C := Stem[I];
      If ((C >= 'A') And (C <= 'Z')) Or ((C >= 'a') And (C <= 'z')) Or ((C >= '0') And (C <= '9')) Or
        (C = '.') Or (C = '_') Or (C = '-') Then
        Clean := Clean + C
      Else If (Clean = '') Or (Clean[Length(Clean)] <> '-') Then
        Clean := Clean + '-';
    End;
  While (Clean <> '') And ((Clean[1] = '-') Or (Clean[1] = '.')) Do
    Delete(Clean, 1, 1);
  While (Clean <> '') And ((Clean[Length(Clean)] = '-') Or (Clean[Length(Clean)] = '.')) Do
    Delete(Clean, Length(Clean), 1);
  If Length(Clean) > 64 Then
    Clean := Copy(Clean, 1, 64);
  While (Clean <> '') And ((Clean[Length(Clean)] = '-') Or (Clean[Length(Clean)] = '.')) Do
    Delete(Clean, Length(Clean), 1);
  If Not SkillNameIsSafe(Clean) Then
    Clean := 'guidance';
  Result := Clean;
End;

Function SkillDocumentName(Const FilePath: String): String;
Var
  SL: TStringList;
  Declared, Clean: String;
Begin
  Result := '';
  Clean := Trim(FilePath);
  If (Clean = '') Or (Not FileExistsUTF8(Clean)) Then
    Exit;
  Declared := '';
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Clean);
      Declared := DeclaredSkillName(SL.Text);
    Except
      Declared := '';
    End;
  Finally
    SL.Free;
  End;
  If Declared <> '' Then
    Exit(Declared);
  Result := SkillNameFromFile(Clean);
End;

Procedure OmitRetiredBehaviourGuide(Names: TStrings);
Var
  I: Integer;
  HasReplacement: Boolean;
Begin
  If Not Assigned(Names) Then
    Exit;
  HasReplacement := False;
  For I := 0 To Names.Count - 1 Do
    If SameText(Trim(Names[I]), AssistantMethodologySkillName) Then
      Begin
        HasReplacement := True;
        Break;
      End;
  If Not HasReplacement Then
    Exit;
  For I := Names.Count - 1 DownTo 0 Do
    If SameText(Trim(Names[I]), AssistantRetiredBehaviourSkillName) Then
      Names.Delete(I);
End;

Function FormatSkillCatalog(Const Skills: TAssistantSkillList): String;
Var
  I: Integer;
  Lines: TStringList;
  WhenText: String;
Begin
  Lines := TStringList.Create;
  Try
    If Length(Skills) = 0 Then
      Lines.Add('(No skills installed.)')
    Else
      For I := 0 To High(Skills) Do
        Begin
          Lines.Add('- `' + Skills[I].Name + '`');
          If Skills[I].Description <> '' Then
            Lines.Add('  description: ' + Skills[I].Description);
          WhenText := Skills[I].WhenToUse;
          If WhenText <> '' Then
            Lines.Add('  when-to-use: ' + WhenText);
        End;
    Lines.Add('');
    Lines.Add('Call `read_skill` with the skill name to load the full SKILL.md body. Do not guess a skill you have not loaded.');
    Result := Trim(Lines.Text);
  Finally
    Lines.Free;
  End;
End;

Function LoadSkillBody(Const SkillName, ProjectRoot: String; Out BodyText: String; Out ErrorText: String): Boolean;
Var
  SkillFile, Raw: String;
  Age: LongInt;
Begin
  Result := False;
  BodyText := '';
  ErrorText := '';
  If Trim(SkillName) = '' Then
    Begin
      ErrorText := 'No skill selected.';
      Exit;
    End;
  If Not SkillNameIsSafe(SkillName) Then
    Begin
      ErrorText := 'Invalid skill name.';
      Exit;
    End;
  SkillFile := '';
  If Assigned(SkillFileResolver) Then
    SkillFile := Trim(SkillFileResolver(SkillName));
  If SkillFile <> '' Then
    Begin
      If Not FileExistsUTF8(SkillFile) Then
        Begin
          ErrorText := 'Skill file is missing: ' + SkillFile;
          Exit;
        End;
    End
  Else If SkillIsEnumerated(SkillName) Then
    SkillFile := ResolveSkillFile(SkillName, '');
  If SkillFile = '' Then
    Begin
      ErrorText := 'Skill not found: ' + SkillName;
      Exit;
    End;
  Age := FileAge(SkillFile);
  If CachedSkillBody(SkillFile, Age, BodyText) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not LoadSkillRaw(SkillFile, Raw) Then
    Begin
      ErrorText := 'Skill file is missing: ' + SkillFile;
      Exit;
    End;
  BodyText := PrepareSkillBody(SkillName, Raw);
  Result := BodyText <> '';
  If Not Result Then
    ErrorText := 'Skill file is empty: ' + SkillName
  Else
    StoreSkillBody(SkillName, SkillFile, Age, BodyText);
End;

Function LoadUserSkillBody(Const SkillName: String; Out BodyText: String; Out ErrorText: String): Boolean;
Begin
  Result := LoadSkillBody(SkillName, '', BodyText, ErrorText);
End;

Function BuildSystemPromptWithSkill(Const BasePrompt, SkillName: String): String;
Var
  Body, Err: String;
Begin
  Result := Trim(BasePrompt);
  If Result = '' Then
    Result := 'You are a helpful Free Pascal / Lazarus expert working inside the IDE.';
  If Trim(SkillName) = '' Then
    Exit;
  If Not LoadUserSkillBody(SkillName, Body, Err) Then
    Begin
      { Absent and unreadable skills are not injected. The caller keeps the base prompt. }
      WorkflowLogger.Debug('AssistantSkills', 'Skill "' + SkillName + '" was not attached: ' + Err);
      Exit;
    End;
  Result :=
    Result + LineEnding + LineEnding +
    '----- begin user skill: ' + SkillName + ' -----' + LineEnding +
    'The user explicitly selected this skill for this chat session. Follow it as authoritative instructions for relevant work.' + LineEnding +
    LineEnding +
    Body + LineEnding +
    '----- end user skill: ' + SkillName + ' -----';
End;

Initialization

GuidanceCacheSignature := '';
GuidanceCacheDocuments := Nil;
GuidanceCacheCatalog := '';
GuidanceCacheValid := False;
SkillBodyCache := Nil;

End.
