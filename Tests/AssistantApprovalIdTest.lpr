Program AssistantApprovalIdTest;

{ Proves Ask mode reaches the phone waiter with a real tool-call id. No phone and no process.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, AssistantTools, AssistantConfig, AssistantMCPBridge, AssistantCodexClient, AssistantCodexRun,
  AssistantConversation;

Var
  FailCount: Integer;
  SeenName, SeenId, SeenSummary: String;
  SeenCalls: Integer;

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

Function StubWaiter(Const ToolName, ToolId, ArgumentsJson: String; Aborting: TAssistantApprovalAbort;
  Out ErrorText: String; Out Handled: Boolean): Boolean;
Begin
  Inc(SeenCalls);
  SeenName := ToolName;
  SeenId := ToolId;
  SeenSummary := ArgumentsJson;
  Handled := True;
  ErrorText := 'denied in test';
  Result := False;
  If Assigned(Aborting) Then
    Result := False;
End;

Procedure ResetSeen;
Begin
  SeenCalls := 0;
  SeenName := '';
  SeenId := '';
  SeenSummary := '';
End;

Procedure TestClaudeId;
Var
  ErrorText, Summary: String;
Begin
  ResetSeen;
  Summary := MCPApprovalSummary('Main.pas', 'old line', 'new line');
  Check('claude approval is asked', Not ApproveBrokerToolCall('replace_in_file', 'mcp-9', 'Main.pas',
    'old line', 'new line', ErrorText));
  Check('claude waiter ran', SeenCalls = 1);
  Check('claude id is the request id', SeenId = 'mcp-9');
  Check('claude summary is the broker summary', SeenSummary = Summary);
  Check('claude summary is not a raw argument prefix', Pos('"change":', SeenSummary) > 0);
End;

Procedure TestCodexId;
Var
  Run: TAssistantCodexRun;
  Tool: TCodexToolRequest;
  Text, Arguments, Summary: String;
  OK: Boolean;
Begin
  ResetSeen;
  Arguments := '{"path":"Main.pas","old_text":"old line","new_text":"new line"}';
  Summary := MCPApprovalSummary('Main.pas', 'old line', 'new line');
  Run := TAssistantCodexRun.Create('codex', '', 'model', 'prompt', '[]', 'run', 1000, '', '', '', amBuild);
  Try
    Run.QueueToolForTest('replace_in_file', Arguments);
    Check('codex tool is serviced', Run.ServiceOneTool(Tool, Text, OK));
    Check('codex ask denies before the tool runs', Not OK);
    Check('codex waiter ran', SeenCalls = 1);
    Check('codex id is the call id', SeenId = 'test-call');
    Check('codex summary is the broker summary', SeenSummary = Summary);
    Check('codex summary is not the raw arguments', SeenSummary <> Arguments);
  Finally
    Run.Free;
  End;
End;

Begin
  FailCount := 0;
  SetAssistantRemoteApproval(@StubWaiter);
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.ApprovalMode := 'ask';
  Try
    TestClaudeId;
    TestCodexId;
  Finally
    SetAssistantRemoteApproval(Nil);
  End;
  If FailCount = 0 Then
    WriteLn('All approval ids were non-empty.')
  Else
    Begin
      WriteLn(FailCount, ' approval id check(s) failed.');
      Halt(1);
    End;
End.
