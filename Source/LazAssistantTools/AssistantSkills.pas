Unit AssistantSkills;

{ Discover and load skills from project, .assistant, and ~/.grok/skills (c) 2026 Michell Computing. }

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
  { Soft cap so a huge skill cannot blow the entire context window alone. }
  AssistantSkillMaxChars = 120000;

Type
  TAssistantSkillInfo = Record
    Name: String;
    Description: String;
    WhenToUse: String;
    SkillFile: String;
    UserInvocable: Boolean;
  End;

  TAssistantSkillList = Array Of TAssistantSkillInfo;

Function AssistantUserSkillsRoot: String;
Function SkillSearchRoots(Const ProjectRoot: String): TStringArray;
Function SkillNameIsSafe(Const SkillName: String): Boolean;
Function ResolveSkillFile(Const SkillName, ProjectRoot: String): String;
Function ListUserSkills: TAssistantSkillList;
Function ListDiscoveredSkills(Const ProjectRoot: String): TAssistantSkillList;
Function LoadUserSkillBody(Const SkillName: String; Out BodyText: String; Out ErrorText: String): Boolean;
Function LoadSkillBody(Const SkillName, ProjectRoot: String; Out BodyText: String; Out ErrorText: String): Boolean;
Function FormatSkillCatalog(Const Skills: TAssistantSkillList): String;
Function BuildSystemPromptWithSkill(Const BasePrompt, SkillName: String): String;

Implementation

Uses
  FileUtil, LazFileUtils, WorkflowLog;

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

Procedure AddRoot(Var Roots: TStringArray; Const Dir: String);
Var
  Clean: String;
  I: Integer;
Begin
  Clean := ExcludeTrailingPathDelimiter(Trim(Dir));
  If Clean = '' Then
    Exit;
  For I := 0 To High(Roots) Do
    If CompareFilenames(Roots[I], Clean) = 0 Then
      Exit;
  SetLength(Roots, Length(Roots) + 1);
  Roots[High(Roots)] := Clean;
End;

Function SkillSearchRoots(Const ProjectRoot: String): TStringArray;
Var
  Root: String;
Begin
  Result := Nil;
  Root := Trim(ProjectRoot);
  If Root <> '' Then
    Begin
      Root := IncludeTrailingPathDelimiter(ExpandFileName(Root));
      AddRoot(Result, Root + '.grok' + PathDelim + 'skills');
      AddRoot(Result, Root + '.assistant' + PathDelim + 'skills');
    End;
  AddRoot(Result, AssistantUserSkillsRoot);
End;

Function ResolveSkillFile(Const SkillName, ProjectRoot: String): String;
Var
  Roots: TStringArray;
  I: Integer;
  Candidate: String;
Begin
  Result := '';
  If Not SkillNameIsSafe(SkillName) Then
    Exit;
  Roots := SkillSearchRoots(ProjectRoot);
  For I := 0 To High(Roots) Do
    Begin
      Candidate := IncludeTrailingPathDelimiter(Roots[I]) + SkillName + PathDelim + 'SKILL.md';
      If FileExistsUTF8(Candidate) And PathIsInsideRoot(Roots[I], Candidate) Then
        Begin
          Result := Candidate;
          Exit;
        End;
    End;
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

Function ParseUserInvocable(Const Raw: String): Boolean;
Var
  Val: String;
Begin
  Val := LowerCase(Trim(ExtractFrontMatterField(Raw, 'user-invocable')));
  If Val = '' Then
    Val := LowerCase(Trim(ExtractFrontMatterField(Raw, 'user_invocable')));
  If (Val = 'false') Or (Val = 'no') Or (Val = '0') Then
    Result := False
  Else
    Result := True;
End;

Function FillSkillInfo(Const SkillDir: String; Out Info: TAssistantSkillInfo): Boolean;
Var
  SkillFile, Raw: String;
  SL: TStringList;
Begin
  Result := False;
  Info.Name := '';
  Info.Description := '';
  Info.WhenToUse := '';
  Info.SkillFile := '';
  Info.UserInvocable := True;
  SkillFile := IncludeTrailingPathDelimiter(SkillDir) + 'SKILL.md';
  If Not FileExists(SkillFile) Then
    Exit;
  Info.Name := ExtractFileName(ExcludeTrailingPathDelimiter(SkillDir));
  If Not SkillNameIsSafe(Info.Name) Then
    Exit;
  Info.SkillFile := SkillFile;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(SkillFile);
      Raw := SL.Text;
      Info.Description := ExtractFrontMatterField(Raw, 'description');
      If Info.Description = '' Then
        Info.Description := ExtractFrontMatterField(Raw, 'name');
      Info.WhenToUse := ExtractFrontMatterField(Raw, 'when-to-use');
      If Info.WhenToUse = '' Then
        Info.WhenToUse := ExtractFrontMatterField(Raw, 'when_to_use');
      Info.UserInvocable := ParseUserInvocable(Raw);
      Result := True;
    Except
      On E: Exception Do
        WorkflowLogger.Warning('AssistantSkills', 'Failed to read ' + SkillFile + ': ' + E.Message);
    End;
  Finally
    SL.Free;
  End;
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

Function ListSkillsInRoot(Const Root: String; Var Skills: TAssistantSkillList): Integer;
Var
  Dirs: TStringList;
  I: Integer;
  Info: TAssistantSkillInfo;
Begin
  Result := 0;
  If Not DirectoryExists(Root) Then
    Exit;
  Dirs := FindAllDirectories(Root, False);
  Try
    Dirs.Sort;
    For I := 0 To Dirs.Count - 1 Do
      Begin
        If Not FillSkillInfo(Dirs[I], Info) Then
          Continue;
        If SkillNameTaken(Skills, Info.Name) Then
          Continue;
        SetLength(Skills, Length(Skills) + 1);
        Skills[High(Skills)] := Info;
        Inc(Result);
      End;
  Finally
    Dirs.Free;
  End;
End;

Function ListDiscoveredSkills(Const ProjectRoot: String): TAssistantSkillList;
Var
  Roots: TStringArray;
  I: Integer;
Begin
  Result := Nil;
  Roots := SkillSearchRoots(ProjectRoot);
  For I := 0 To High(Roots) Do
    ListSkillsInRoot(Roots[I], Result);
End;

Function ListUserSkills: TAssistantSkillList;
Begin
  Result := ListDiscoveredSkills('');
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
      Lines.Add('(No skills discovered.)')
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

Var
  { In-process skill body cache — avoids disk on every prompt. }
  SkillCacheName: String;
  SkillCacheFile: String;
  SkillCacheAge: LongInt;
  SkillCacheBody: String;

Function LoadSkillBody(Const SkillName, ProjectRoot: String; Out BodyText: String; Out ErrorText: String): Boolean;
Var
  SkillFile, Raw: String;
  SL: TStringList;
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
  SkillFile := ResolveSkillFile(SkillName, ProjectRoot);
  If SkillFile = '' Then
    Begin
      ErrorText := 'Skill not found: ' + SkillName;
      Exit;
    End;
  Age := FileAge(SkillFile);
  If SameText(SkillCacheName, SkillName) And SameFileName(SkillCacheFile, SkillFile) And
    (SkillCacheAge = Age) And (SkillCacheBody <> '') Then
    Begin
      BodyText := SkillCacheBody;
      Result := True;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(SkillFile);
      Raw := SL.Text;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          Exit;
        End;
    End;
  Finally
    SL.Free;
  End;
  BodyText := StripYamlFrontMatter(Raw);
  If BodyText = '' Then
    BodyText := Trim(Raw);
  If Length(BodyText) > AssistantSkillMaxChars Then
    Begin
      BodyText := Copy(BodyText, 1, AssistantSkillMaxChars) + LineEnding + LineEnding +
        '[Skill truncated at ' + IntToStr(AssistantSkillMaxChars) + ' characters for context size.]';
      WorkflowLogger.Warning('AssistantSkills', 'Skill ' + SkillName + ' truncated for system prompt');
    End;
  Result := BodyText <> '';
  If Not Result Then
    ErrorText := 'Skill file is empty: ' + SkillName
  Else
    Begin
      SkillCacheName := SkillName;
      SkillCacheFile := SkillFile;
      SkillCacheAge := Age;
      SkillCacheBody := BodyText;
    End;
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
      WorkflowLogger.Warning('AssistantSkills', 'Could not load skill "' + SkillName + '": ' + Err);
      Result := Result + LineEnding + LineEnding +
        '(Requested user skill "' + SkillName + '" could not be loaded: ' + Err + ')';
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

SkillCacheName := '';
SkillCacheFile := '';
SkillCacheAge := -1;
SkillCacheBody := '';

End.
