Program AssistantHarnessTest;

{ Console checks for skill discovery, harness prompt, and todo_write (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, LazFileUtils, AssistantConversation, AssistantSkills,
  AssistantHarness;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure WriteTextFile(Const FileName, Body: String);
Var
  SL: TStringList;
  Dir: String;
Begin
  Dir := ExtractFilePath(FileName);
  If (Dir <> '') And (Not DirectoryExistsUTF8(Dir)) Then
    ForceDirectories(Dir);
  SL := TStringList.Create;
  Try
    SL.Text := Body;
    SL.SaveToFile(FileName);
  Finally
    SL.Free;
  End;
End;

Function MakeTempRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-harness-' + FormatDateTime('hhnnsszzz', Now);
  Result := IncludeTrailingPathDelimiter(Result);
  If DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(Result)) Then
    DeleteDirectory(ExcludeTrailingPathDelimiter(Result), False);
  ForceDirectories(Result);
End;

Procedure TestFirstNameWins;
Var
  Root: String;
  Skills: TAssistantSkillList;
Begin
  Root := MakeTempRoot;
  Try
    WriteTextFile(Root + '.grok' + PathDelim + 'skills' + PathDelim + 'alpha' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: alpha' + LineEnding + 'description: from project grok' + LineEnding +
      'when-to-use: first root' + LineEnding + '---' + LineEnding + 'BODY-GROK' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'alpha' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: alpha' + LineEnding + 'description: from assistant' + LineEnding +
      '---' + LineEnding + 'BODY-ASSISTANT' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'beta' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: beta' + LineEnding + 'description: second skill' + LineEnding +
      'user-invocable: false' + LineEnding + '---' + LineEnding + 'BODY-BETA' + LineEnding);
    Skills := ListDiscoveredSkills(Root);
    Check('two unique names', Length(Skills) >= 2);
    Check('alpha wins from first root', (Length(Skills) > 0) And SameText(Skills[0].Name, 'alpha') And
      (Pos('project grok', Skills[0].Description) > 0));
    Check('beta is listed as not invocable', (Length(Skills) > 1) And SameText(Skills[1].Name, 'beta') And
      (Not Skills[1].UserInvocable));
  Finally
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestHarnessPrompt;
Var
  Root, Prompt, Body, Err: String;
  Harness: TAssistantHarness;
Begin
  Root := MakeTempRoot;
  Harness := TAssistantHarness.Create;
  Try
    WriteTextFile(Root + 'AGENTS.md', 'Use PascalCase keywords in this repo.');
    WriteTextFile(Root + '.grok' + PathDelim + 'skills' + PathDelim + 'free-pascal-engineer' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: free-pascal-engineer' + LineEnding +
      'description: Michell Pascal style' + LineEnding + '---' + LineEnding +
      'ALWAYS USE PASCALCASE KEYWORDS.' + LineEnding);
    WriteTextFile(Root + '.grok' + PathDelim + 'skills' + PathDelim + 'imagine' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: imagine' + LineEnding + 'description: image prompts' + LineEnding +
      'when-to-use: generating images' + LineEnding + '---' + LineEnding + 'IMAGINE BODY' + LineEnding);
    Prompt := Harness.BuildSystemPrompt(amBuild, '', Root, 'Documents/Plan.md');
    Check('build prompt names Build mode', Pos('Build mode', Prompt) > 0);
    Check('catalog lists imagine', Pos('imagine', Prompt) > 0);
    Check('catalog has when-to-use', Pos('generating images', Prompt) > 0);
    Check('build attaches fpe body', Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) > 0);
    Check('AGENTS.md inlined', Pos('Use PascalCase keywords in this repo', Prompt) > 0);
    Check('work_policy section', Pos('<work_policy>', Prompt) > 0);
    Check('ide_fusion section', Pos('<ide_fusion>', Prompt) > 0);
    Prompt := Harness.BuildSystemPrompt(amChat, '', Root, '');
    Check('ask does not dump fpe body', Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) = 0);
    Check('ask still catalogs fpe', Pos('free-pascal-engineer', Prompt) > 0);
    Prompt := Harness.BuildSystemPrompt(amChat, 'imagine', Root, '');
    Check('ask pin injects imagine body', Pos('IMAGINE BODY', Prompt) > 0);
    Check('read_skill loads imagine', Harness.ReadSkill('imagine', Root, Body, Err) And (Pos('IMAGINE BODY', Body) > 0));
  Finally
    Harness.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestTodoWrite;
Var
  Harness: TAssistantHarness;
  OutText, Err: String;
  Ok: Boolean;
Begin
  Harness := TAssistantHarness.Create;
  Try
    Ok := Harness.ApplyTodoWrite(
      '{"todos":[{"id":"1","content":"read Foo","status":"pending"},{"id":"2","content":"patch Bar","status":"in_progress"}]}',
      OutText, Err);
    Check('todo replace ok', Ok And (Harness.TodoCount = 2));
    Check('todo lists in_progress', Pos('in_progress', OutText) > 0);
    Ok := Harness.ApplyTodoWrite('{"merge":true,"todos":[{"id":"1","status":"completed"}]}', OutText, Err);
    Check('todo merge ok', Ok And (Harness.TodoCount = 2) And (Harness.TodoItem(0).Status = 'completed'));
    Check('todo keeps other item', Harness.TodoItem(1).Content = 'patch Bar');
    Harness.ClearTurnTodos;
    Check('todo clear', Harness.TodoCount = 0);
  Finally
    Harness.Free;
  End;
End;

Begin
  FailCount := 0;
  TestFirstNameWins;
  TestHarnessPrompt;
  TestTodoWrite;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantHarness tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantHarness test(s) failed.');
      Halt(1);
    End;
End.
