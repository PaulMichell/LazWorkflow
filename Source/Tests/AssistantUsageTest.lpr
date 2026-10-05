Program AssistantUsageTest;

{ Fixture checks for usage.jsonl. No socket and no prompt body is written.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, FileUtil, LazFileUtils, AssistantSampler, AssistantCompatibleClient, AssistantClaudeClient,
  AssistantUsage;

Const
  PromptText = 'please summarise the secret prompt body ALPHA-PROMPT';
  GrokFixture =
    'data: {"type":"response.completed","response":{"id":"resp_test","status":"completed","output":[' +
    '{"type":"message","id":"msg_test","role":"assistant","content":[{"type":"output_text","text":"The answer."}]}],' +
    '"usage":{"input_tokens":10,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":5}}}}' + LineEnding +
    LineEnding +
    'data: [DONE]' + LineEnding;
  OpenRouterBody = '{"choices":[{"message":{"role":"assistant","content":"fixture answer"}}],' +
    '"usage":{"prompt_tokens":12,"completion_tokens":4,"cost":0.5}}';
  ClaudeNoUsage = '{"result":"plain answer"}';

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

Function MakeTempRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-usage-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectoriesUTF8(Result);
End;

Function FileText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExistsUTF8(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure TestFixtures;
Var
  Root, Path, Body, ErrorText: String;
  Parser: TAssistantSseParser;
  Completion: TCompatibleCompletion;
  Turn: TClaudeTurnResult;
  Item: TAssistantUsageRecord;
  Lines: TStringList;
Begin
  Root := MakeTempRoot;
  Parser := TAssistantSseParser.Create;
  Lines := TStringList.Create;
  Try
    Parser.Feed(GrokFixture);
    Check('grok fixture reported usage', Parser.UsageReported And (Parser.InputTokens = 10) And (Parser.OutputTokens = 8));
    Item := ReportedUsageRecord('grok-1', 'grok', 'grok-4', Parser.InputTokens, Parser.OutputTokens,
      Parser.HasReasoning, Parser.ReasoningTokens, False, 0, '');
    Check('grok usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Path := UsageFilePath(Root);
    Body := FileText(Path);
    Lines.Text := Body;
    Check('grok appends one reported line', (Lines.Count = 1) And (Pos('"state":"reported"', Lines[0]) > 0));
    Check('grok line has no cost', Pos('"cost"', Lines[0]) = 0);

    Check('openrouter fixture parses', ParseCompatibleCompletion(OpenRouterBody, Completion, ErrorText) And Completion.HasCost);
    Item := ReportedUsageRecord('or-1', 'openai-compatible', 'openai/gpt-4.1', Completion.PromptTokens,
      Completion.CompletionTokens, False, 0, Completion.HasCost, Completion.Cost, '');
    Check('openrouter usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Body := FileText(Path);
    Lines.Text := Body;
    Check('openrouter appends the cost', (Lines.Count = 2) And (Pos('"cost"', Lines[1]) > 0) And (Pos('0.5', Lines[1]) > 0));

    Check('claude fixture parses', ParseClaudeTurnResult(ClaudeNoUsage, Turn, ErrorText));
    Check('claude fixture is unavailable', Turn.UsageState = ClaudeUsageUnavailable);
    Item := UnavailableUsageRecord('claude-1', 'claude', 'claude-sonnet');
    Check('claude usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Body := FileText(Path);
    Lines.Text := Body;
    Check('claude appends unavailable', (Lines.Count = 3) And (Pos('"state":"unavailable"', Lines[2]) > 0));
    Check('usage file has none of the prompt text', Pos(PromptText, Body) = 0);
    Check('usage file has none of the answer text', (Pos('The answer.', Body) = 0) And
      (Pos('fixture answer', Body) = 0) And (Pos('plain answer', Body) = 0));
  Finally
    Lines.Free;
    Parser.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Begin
  FailCount := 0;
  TestFixtures;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantUsage tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantUsage test(s) failed.');
      Halt(1);
    End;
End.
