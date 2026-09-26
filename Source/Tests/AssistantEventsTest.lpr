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
  Combined, Attachments: String;
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
    Buf.Enqueue('look here', '[{"id":"img1","name":"shot.png"}]');
    Buf.Enqueue('', '[{"id":"img2","name":"other.png"}]');
    Check('image steer pending', Buf.HasPending);
    Check('image steer drain', Buf.Drain(Combined, Attachments));
    Check('image steer keeps words', Combined = 'look here');
    Check('image steer refs merged', (Pos('img1', Attachments) > 0) And (Pos('img2', Attachments) > 0));
    Check('image steer cleared', Not Buf.HasPending);
    Buf.Enqueue('', '');
    Check('blank steer stays empty', Not Buf.HasPending);
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

Procedure TestProgressStatus;
Begin
  Check('waiting is status', IsAssistantProgressStatus('Waiting for first token…'));
  Check('model wait is status', IsAssistantProgressStatus('Waiting for model…'));
  Check('tools is status', IsAssistantProgressStatus('Running tools…'));
  Check('steer is status', IsAssistantProgressStatus('Steering at next model gap…'));
  Check('http is error', Not IsAssistantProgressStatus('HTTP 400: invalid_grant'));
  Check('empty is error', Not IsAssistantProgressStatus(''));
  Check('access violation is error', Not IsAssistantProgressStatus('Access violation'));
End;

Procedure TestParseEventRoundTrip;
Var
  Event, Loaded: TAssistantEvent;
  Line: String;
Begin
  Event := Default(TAssistantEvent);
  Event.Kind := aekSubagentCompleted;
  Event.Phase := apTools;
  Event.ToolName := 'pascal-naming';
  Event.ToolId := 'sub_1';
  Event.Text := 'No F-prefix issues.';
  Event.Ok := True;
  Event.DurationMs := 1200;
  Event.LoopIndex := 1;
  Line := AssistantEventToJson(Event);
  Check('parse roundtrip', ParseAssistantEventJson(Line, Loaded));
  Check('parse kind', Loaded.Kind = aekSubagentCompleted);
  Check('parse tool', Loaded.ToolName = 'pascal-naming');
  Check('parse id', Loaded.ToolId = 'sub_1');
  Check('parse text', Pos('F-prefix', Loaded.Text) > 0);
  Check('parse duration', Loaded.DurationMs = 1200);
  Check('kind from name', AssistantEventKindFromName('loop_started') = aekLoopStarted);
  Check('unknown kind is error', AssistantEventKindFromName('nope') = aekError);
End;

Procedure TestEventsFileLoad;
Var
  Event: TAssistantEvent;
  Path: String;
  Events: TAssistantEventArray;
Begin
  Path := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-replay-events.jsonl';
  DeleteFile(Path);
  Event := Default(TAssistantEvent);
  Event.Kind := aekTurnStarted;
  Event.Text := 'grok-4.5';
  Check('write start', AppendAssistantEvent(Path, Event));
  Event := Default(TAssistantEvent);
  Event.Kind := aekToolStarted;
  Event.ToolName := 'read_file';
  Event.ToolId := 'call_1';
  Event.Text := '{"path":"Foo.pas"}';
  Check('write tool', AppendAssistantEvent(Path, Event));
  Check('load events', LoadAssistantEventsFile(Path, Events));
  Check('load count', Length(Events) = 2);
  Check('load tool', (Length(Events) = 2) And (Events[1].Kind = aekToolStarted) And
    (Events[1].ToolId = 'call_1'));
  Check('relative path', Pos('events/', AssistantEventsRelativePath(
    '/proj/.assistant/events/a.jsonl', '/proj')) > 0);
  Check('absolute stays', AssistantEventsAbsolutePath('/tmp/x.jsonl', '/proj') = '/tmp/x.jsonl');
  DeleteFile(Path);
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
  TestParseEventRoundTrip;
  TestEventsFileLoad;
  TestProgressStatus;
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
