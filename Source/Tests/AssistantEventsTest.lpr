Program AssistantEventsTest;

{ Console checks for turn events, steer buffer, and tool JSON helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantProtocol, AssistantEvents;

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

Procedure TestSteerBuffer;
Var
  Buf: TAssistantSteerBuffer;
  Combined: String;
Begin
  Buf := TAssistantSteerBuffer.Create;
  Try
    Check('steer empty', Not Buf.HasPending);
    Buf.Enqueue('  use replace_in_file  ');
    Buf.Enqueue('and skip the probe unit');
    Check('steer pending', Buf.HasPending);
    Combined := Buf.DrainConcat;
    Check('steer drained', Not Buf.HasPending);
    Check('steer first note', Pos('use replace_in_file', Combined) > 0);
    Check('steer second note', Pos('skip the probe unit', Combined) > 0);
    Check('steer concat sep', Pos(LineEnding + LineEnding, Combined) > 0);
  Finally
    Buf.Free;
  End;
End;

Procedure TestSteerEnvelope;
Var
  Env: String;
Begin
  Env := FormatSteerEnvelope('do not compile yet');
  Check('envelope note', Pos('while you were working', Env) > 0);
  Check('envelope query', Pos('<user_query>', Env) > 0);
  Check('envelope body', Pos('do not compile yet', Env) > 0);
  Check('envelope close', Pos('</user_query>', Env) > 0);
End;

Procedure TestEventJson;
Var
  Event: TAssistantEvent;
  Line: String;
Begin
  Event := Default(TAssistantEvent);
  Event.Kind := aekToolStarted;
  Event.Phase := apTools;
  Event.ToolName := 'read_file';
  Event.ToolId := 'call_1';
  Event.Text := '{"path":"Foo.pas"}';
  Event.LoopIndex := 2;
  Line := AssistantEventToJson(Event);
  Check('json type', Pos('"type":"tool_started"', Line) > 0);
  Check('json tool', Pos('"tool":"read_file"', Line) > 0);
  Check('json escaped path', Pos('Foo.pas', Line) > 0);
  Check('json loop', Pos('"loop":2', Line) > 0);
End;

Procedure TestEventFile;
Var
  Event: TAssistantEvent;
  Path: String;
  SL: TStringList;
Begin
  Path := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-events-test.jsonl';
  DeleteFile(Path);
  Event := Default(TAssistantEvent);
  Event.Kind := aekTurnStarted;
  Event.Text := 'grok-4.5';
  Check('append event', AppendAssistantEvent(Path, Event));
  SL := TStringList.Create;
  Try
    SL.LoadFromFile(Path);
    Check('file lines', SL.Count = 1);
    Check('file payload', Pos('turn_started', SL[0]) > 0);
  Finally
    SL.Free;
    DeleteFile(Path);
  End;
End;

Procedure TestParseToolCalls;
Var
  Calls: TSamplerToolCallArray;
  Json: String;
Begin
  Json := '[{"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"A.pas\"}"}}]';
  Check('parse tools', ParseOpenAiToolCallsJson(Json, Calls));
  Check('parse count', Length(Calls) = 1);
  Check('parse id', (Length(Calls) = 1) And (Calls[0].Id = 'call_1'));
  Check('parse name', (Length(Calls) = 1) And (Calls[0].Name = 'read_file'));
  Check('parse args', (Length(Calls) = 1) And (Pos('A.pas', Calls[0].Arguments) > 0));
End;

Procedure TestToolsFlatten;
Var
  Completions, Responses: String;
Begin
  Completions := '[{"type":"function","function":{"name":"read_file","description":"Read a file","parameters":{"type":"object"}}}]';
  Responses := CompletionsToolsToResponsesTools(Completions);
  Check('flat has name', (Pos('"name" : "read_file"', Responses) > 0) Or (Pos('"name":"read_file"', Responses) > 0));
  Check('flat has parameters', Pos('"parameters"', Responses) > 0);
  Check('flat is array', (Length(Responses) > 0) And (Responses[1] = '['));
End;

Begin
  FailCount := 0;
  TestSteerBuffer;
  TestSteerEnvelope;
  TestEventJson;
  TestEventFile;
  TestParseToolCalls;
  TestToolsFlatten;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantEvents tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantEvents test(s) failed.');
      Halt(1);
    End;
End.
