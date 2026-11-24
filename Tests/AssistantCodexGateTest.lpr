Program AssistantCodexGateTest;

{ ChatGPT tool calls use the Grok gate. No Codex process and no second Ask dialog.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, AssistantTools, AssistantConfig, AssistantCodexClient, AssistantCodexRun, AssistantConversation;

Const
  MarkdownRefusal =
    'A plan or document is written with write_markdown or update_markdown, not by editing it in the source editor.';

Var
  FailCount, SeenCalls: Integer;
  SeenId, SeenSummary: String;

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

Function AllowWaiter(Const ToolName, ToolId, ArgumentsJson: String; Aborting: TAssistantApprovalAbort;
  Out ErrorText: String; Out Handled: Boolean): Boolean;
Begin
  Inc(SeenCalls);
  SeenId := ToolId;
  SeenSummary := ArgumentsJson;
  Handled := True;
  ErrorText := '';
  Result := True;
  If Assigned(Aborting) Then
    Result := True;
End;

Procedure ResetSeen;
Begin
  SeenCalls := 0;
  SeenId := '';
  SeenSummary := '';
End;

Function Served(Mode: TAssistantMode; Const ToolName, Arguments: String; Out Text: String; Out OK: Boolean): Boolean;
Var
  Run: TAssistantCodexRun;
  Tool: TCodexToolRequest;
Begin
  ResetSeen;
  Run := TAssistantCodexRun.Create('codex', '', 'model', 'prompt', '[]', 'run', 1000, '', '', '', Mode);
  Try
    Run.QueueToolForTest(ToolName, Arguments);
    Result := Run.ServiceOneTool(Tool, Text, OK);
  Finally
    Run.Free;
  End;
End;

Procedure TestInspectRefusal;
Var
  Text: String;
  OK: Boolean;
Begin
  Check('inspect refuses run_compile', Served(amInspect, 'run_compile', '{}', Text, OK) And (Not OK) And
    (Text = 'Tool "run_compile" is not available in inspect mode.') And (SeenCalls = 0));
  Check('inspect refuses write_file', Served(amInspect, 'write_file', '{"path":"Unit.pas","content":"unit Unit;"}',
    Text, OK) And (Not OK) And (Text = 'Tool "write_file" is not available in inspect mode.') And (SeenCalls = 0));
  Check('inspect refuses delete_path', Served(amInspect, 'delete_path', '{"path":"Unit.pas"}', Text, OK) And (Not OK) And
    (Text = 'Tool "delete_path" is not available in inspect mode.') And (SeenCalls = 0));
End;

Procedure TestMarkdownRefusal;
Var
  Text: String;
  OK: Boolean;
Begin
  Check('chatgpt write_file refuses a plan path', Served(amBuild, 'write_file',
    '{"path":"Documents/Plan.md","content":"# Plan"}', Text, OK) And (Not OK) And (Text = MarkdownRefusal) And
    (SeenCalls = 0));
  Check('chatgpt replace_in_file refuses a plan path', Served(amBuild, 'replace_in_file',
    '{"path":"Documents/Plan.md","old_text":"Status: not started","new_text":"Status: complete"}', Text, OK) And
    (Not OK) And (Text = MarkdownRefusal) And (SeenCalls = 0));
End;

Procedure TestAskOnce;
Var
  Text, Arguments: String;
  OK: Boolean;
Begin
  Arguments := '{"path":"Source/Unit.pas","content":"Unit Unit;"}';
  Check('allowed tool is serviced', Served(amBuild, 'write_file', Arguments, Text, OK));
  Check('ask runs once', SeenCalls = 1);
  Check('ask uses the codex call id', SeenId = 'test-call');
  Check('ask uses the summary, not the raw arguments', (SeenSummary <> '') And (SeenSummary <> Arguments));
End;

Begin
  FailCount := 0;
  SetAssistantRemoteApproval(@AllowWaiter);
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.ApprovalMode := 'ask';
  Try
    TestInspectRefusal;
    TestMarkdownRefusal;
    TestAskOnce;
  Finally
    SetAssistantRemoteApproval(Nil);
  End;
  If FailCount = 0 Then
    WriteLn('AssistantCodexGateTest passed')
  Else
    Begin
      WriteLn(FailCount, ' codex gate check(s) failed.');
      Halt(1);
    End;
End.
