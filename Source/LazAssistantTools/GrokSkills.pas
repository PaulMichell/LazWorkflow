Unit GrokSkills;

{ Discover and load Grok user skills (~/.grok/skills) for LazAssistantTools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  GrokSkillNoneCaption = '(None)';
  { Soft cap so a huge skill cannot blow the entire context window alone. }
  GrokSkillMaxChars = 120000;

Type
  TGrokSkillInfo = Record
    Name: String;
    Description: String;
    SkillFile: String;
  End;

  TGrokSkillList = Array Of TGrokSkillInfo;

Function GrokUserSkillsRoot: String;
Function ListUserSkills: TGrokSkillList;
Function LoadUserSkillBody(Const SkillName: String; Out BodyText: String; Out ErrorText: String): Boolean;
Function BuildSystemPromptWithSkill(Const BasePrompt, SkillName: String): String;

Implementation

Uses
  FileUtil, LazFileUtils, WorkflowLog;

Function GrokUserSkillsRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetUserDir) + '.grok' + PathDelim + 'skills';
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

Function ListUserSkills: TGrokSkillList;
Var
  Root, SkillDir, SkillFile, Raw: String;
  Dirs: TStringList;
  I: Integer;
  Info: TGrokSkillInfo;
  SL: TStringList;
Begin
  SetLength(Result, 0);
  Root := GrokUserSkillsRoot;
  If Not DirectoryExists(Root) Then
    Exit;
  Dirs := FindAllDirectories(Root, False);
  Try
    Dirs.Sort;
    For I := 0 To Dirs.Count - 1 Do
      Begin
        SkillDir := Dirs[I];
        SkillFile := IncludeTrailingPathDelimiter(SkillDir) + 'SKILL.md';
        If Not FileExists(SkillFile) Then
          Continue;
        Info.Name := ExtractFileName(ExcludeTrailingPathDelimiter(SkillDir));
        Info.SkillFile := SkillFile;
        Info.Description := '';
        SL := TStringList.Create;
        Try
          Try
            SL.LoadFromFile(SkillFile);
            Raw := SL.Text;
            Info.Description := ExtractFrontMatterField(Raw, 'description');
            If Info.Description = '' Then
              Info.Description := ExtractFrontMatterField(Raw, 'name');
          Except
            On E: Exception Do
              WorkflowLogger.Warning('GrokSkills', 'Failed to read ' + SkillFile + ': ' + E.Message);
          End;
        Finally
          SL.Free;
        End;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Info;
      End;
  Finally
    Dirs.Free;
  End;
End;

Function LoadUserSkillBody(Const SkillName: String; Out BodyText: String; Out ErrorText: String): Boolean;
Var
  SkillFile, Raw: String;
  SL: TStringList;
Begin
  Result := False;
  BodyText := '';
  ErrorText := '';
  If Trim(SkillName) = '' Then
    Begin
      ErrorText := 'No skill selected.';
      Exit;
    End;
  SkillFile := IncludeTrailingPathDelimiter(GrokUserSkillsRoot) + SkillName + PathDelim + 'SKILL.md';
  If Not FileExists(SkillFile) Then
    Begin
      ErrorText := 'Skill not found: ' + SkillName;
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
  If Length(BodyText) > GrokSkillMaxChars Then
    Begin
      BodyText := Copy(BodyText, 1, GrokSkillMaxChars) + LineEnding + LineEnding +
        '[Skill truncated at ' + IntToStr(GrokSkillMaxChars) + ' characters for context size.]';
      WorkflowLogger.Warning('GrokSkills', 'Skill ' + SkillName + ' truncated for system prompt');
    End;
  Result := BodyText <> '';
  If Not Result Then
    ErrorText := 'Skill file is empty: ' + SkillName;
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
      WorkflowLogger.Warning('GrokSkills', 'Could not load skill "' + SkillName + '": ' + Err);
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

End.
