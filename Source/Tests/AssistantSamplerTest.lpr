Program AssistantSamplerTest;

{ Console checks for Responses / Chat Completions SSE parsing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantProtocol, AssistantSampler;

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

Function CountKind(Parser: TAssistantSseParser; Kind: TSamplerEventKind): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 0 To Parser.EventCount - 1 Do
    If Parser.GetEvent(I).Kind = Kind Then
      Inc(Result);
End;

Function SseLine(Const Payload: String): String;
Begin
  Result := 'data: ' + Payload + #10;
End;

Procedure FeedAll(Parser: TAssistantSseParser; Const Body: String);
Begin
  Parser.Feed(Body);
End;

Procedure TestResponsesReasoningAndText;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_test","status":"in_progress"}}') +
      SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"reasoning_item_1","output_index":0,"delta":"Let "}') +
      SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"reasoning_item_1","output_index":0,"delta":"me think."}') +
      SseLine('{"type":"response.output_text.delta","item_id":"item_test","output_index":1,"delta":"The "}') +
      SseLine('{"type":"response.output_text.delta","item_id":"item_test","output_index":1,"delta":"answer."}') +
      SseLine('{"type":"response.completed","response":{"id":"resp_test","status":"completed","output":[' +
        '{"type":"reasoning","id":"reasoning_item_1","summary":[{"type":"summary_text","text":"Let me think."}]},' +
        '{"type":"message","id":"msg_test","role":"assistant","content":[{"type":"output_text","text":"The answer."}]}],' +
        '"usage":{"input_tokens":10,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":5}}}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('responses wire', Parser.Wire = swkResponses);
    Check('responses started', CountKind(Parser, sekStreamStarted) = 1);
    Check('responses thought deltas', CountKind(Parser, sekThoughtDelta) = 2);
    Check('responses content deltas', CountKind(Parser, sekContentDelta) = 2);
    Check('responses completed once', CountKind(Parser, sekCompleted) = 1);
    Check('responses thinking accum', Parser.Thinking = 'Let me think.');
    Check('responses content accum', Parser.Content = 'The answer.');
    Check('responses input tokens', Parser.InputTokens = 10);
    Check('responses reasoning tokens', Parser.ReasoningTokens = 5);
  Finally
    Parser.Free;
  End;
End;

Procedure TestInterleavedThoughtAndContent;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_mix"}}') +
      SseLine('{"type":"response.output_item.added","output_index":0,' +
        '"item":{"type":"reasoning","id":"rs_1","summary":[]}}') +
      SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","delta":"The user wants "}') +
      SseLine('{"type":"response.output_item.added","output_index":1,' +
        '"item":{"type":"message","id":"msg_1","role":"assistant",' +
        '"content":[{"type":"output_text","text":"I''ll start"}]}}') +
      SseLine('{"type":"response.output_text.delta","item_id":"msg_1","delta":" from"}') +
      SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","delta":"me to review."}') +
      SseLine('{"type":"response.output_item.added","output_index":1,' +
        '"item":{"type":"message","id":"msg_1","role":"assistant",' +
        '"content":[{"type":"output_text","text":"I''ll start from the tree"}]}}') +
      SseLine('{"type":"response.output_text.delta","item_id":"msg_1","delta":" and walk"}');
    FeedAll(Parser, Body);
    Check('interleave thinking', Parser.Thinking = 'The user wants me to review.');
    Check('interleave content grows', Parser.Content = 'I''ll start from the tree and walk');
    Check('interleave one thought stream', Pos('The user wants The user', Parser.Thinking) = 0);
    Check('interleave one message stream', Pos('I''ll startI''ll start', Parser.Content) = 0);
  Finally
    Parser.Free;
  End;
End;

Procedure TestResponsesEncryptedHarvest;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_reason123"}}') +
      SseLine('{"type":"response.completed","response":{"id":"resp_reason123","status":"completed","output":[' +
        '{"type":"reasoning","id":"reasoning_item_1","encrypted_content":"enc_base64_secret",' +
        '"summary":[{"type":"summary_text","text":"Step by step."}]},' +
        '{"type":"message","role":"assistant","content":[{"type":"output_text","text":"42."}]}]' +
        '}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('encrypted id', Parser.EncryptedId = 'reasoning_item_1');
    Check('encrypted blob', Parser.EncryptedContent = 'enc_base64_secret');
    Check('encrypted thinking from summary', Parser.Thinking = 'Step by step.');
    Check('encrypted content from message', Parser.Content = '42.');
    Check('encrypted no extra completed', CountKind(Parser, sekCompleted) = 1);
  Finally
    Parser.Free;
  End;
End;

Procedure TestResponsesToolCall;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_test"}}') +
      SseLine('{"type":"response.reasoning_summary_text.delta","delta":"Need a file."}') +
      SseLine('{"type":"response.function_call_arguments.delta","item_id":"call_1","output_index":1,' +
        '"delta":"{\"path\":\"Foo.pas\"}"}') +
      SseLine('{"type":"response.completed","response":{"output":[' +
        '{"type":"reasoning","id":"reasoning_item_1","summary":[{"type":"summary_text","text":"Need a file."}]},' +
        '{"type":"function_call","call_id":"call_1","name":"read_file","arguments":"{\"path\":\"Foo.pas\"}"}]}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('tool thought kept', Pos('Need a file.', Parser.Thinking) > 0);
    Check('tool count', Length(Parser.ToolCalls) = 1);
    Check('tool id', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Id = 'call_1'));
    Check('tool name from completed', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Name = 'read_file'));
    Check('tool args', (Length(Parser.ToolCalls) = 1) And (Pos('Foo.pas', Parser.ToolCalls[0].Arguments) > 0));
    Check('tool delta events', CountKind(Parser, sekToolCallDelta) >= 1);
  Finally
    Parser.Free;
  End;
End;

Procedure TestOutputItemAddedDoesNotDuplicateTool;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_dup"}}') +
      SseLine('{"type":"response.output_item.added","output_index":1,' +
        '"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"list_directory",' +
        '"arguments":""}}') +
      SseLine('{"type":"response.function_call_arguments.delta","item_id":"call_1","output_index":1,' +
        '"delta":"{\"path\":\"Source\"}"}') +
      SseLine('{"type":"response.completed","response":{"output":[' +
        '{"type":"function_call","call_id":"call_1","name":"list_directory","arguments":"{\"path\":\"Source\"}"}]}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('added+delta tool count', Length(Parser.ToolCalls) = 1);
    Check('added+delta tool name', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Name = 'list_directory'));
    Check('added+delta tool id', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Id = 'call_1'));
    Check('added+delta tool args', (Length(Parser.ToolCalls) = 1) And (Pos('Source', Parser.ToolCalls[0].Arguments) > 0));
  Finally
    Parser.Free;
  End;
End;

Procedure TestDistinctToolIdsAndRepeatedArguments;
Var
  Parser: TAssistantSseParser;
  Body: String;
  I: Integer;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.output_item.added","output_index":2,' +
        '"item":{"type":"function_call","id":"fc_distinct","call_id":"call_real","name":"write_file","arguments":""}}') +
      SseLine('{"type":"response.function_call_arguments.delta","item_id":"fc_distinct","output_index":2,"delta":"x"}') +
      SseLine('{"type":"response.function_call_arguments.delta","item_id":"fc_distinct","output_index":2,"delta":"x"}');
    For I := 1 To Length(Body) Do
      Parser.Feed(Body[I]);
    Check('fragmented call ID survives item delta', Parser.ToolCalls[2].Id = 'call_real');
    Check('item ID retained separately', Parser.ToolCalls[2].ItemId = 'fc_distinct');
    Check('repeated argument bytes preserved', Parser.ToolCalls[2].Arguments = 'xx');
    Check('event call ID preserved', Parser.GetEvent(Parser.EventCount - 1).ToolId = 'call_real');
    Check('event item ID preserved', Parser.GetEvent(Parser.EventCount - 1).ToolItemId = 'fc_distinct');
    Parser.Feed(SseLine('{"type":"response.completed","response":{"output":[' +
      '{"type":"function_call","id":"fc_distinct","call_id":"call_real","name":"write_file","arguments":"{}"},' +
      '{"type":"function_call","id":"fc_second","call_id":"call_second","name":"read_file","arguments":"{}"}]}}'));
    Check('authoritative output replaces sparse streamed calls', Length(Parser.ToolCalls) = 2);
    Check('final snapshot replaces arguments', Parser.ToolCalls[0].Arguments = '{}');
    Check('second call retained', Parser.ToolCalls[1].Id = 'call_second');
    Parser.Feed(SseLine('{"type":"response.completed","response":{"output":[]}}'));
    Check('duplicate terminal ignored', CountKind(Parser, sekCompleted) = 1);
    Check('duplicate terminal does not clear tools', Length(Parser.ToolCalls) = 2);
  Finally
    Parser.Free;
  End;
End;

Procedure TestToolDoneAndInvalidIndex;
Var Parser: TAssistantSseParser;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Parser.Feed(SseLine('{"type":"response.output_item.done","output_index":0,' +
      '"item":{"type":"function_call","id":"fc_done","call_id":"call_done","name":"read_file","arguments":"{}"}}') +
      SseLine('[DONE]'));
    Check('item done captures tool', Length(Parser.ToolCalls) = 1);
    Check('item done preserves call ID', Parser.ToolCalls[0].Id = 'call_done');
    Parser.Reset;
    Parser.Feed(SseLine('{"type":"response.function_call_arguments.delta","output_index":-1,"delta":"x"}'));
    Check('invalid index fails safely', Parser.Failed);
    Check('parse failure emits event', CountKind(Parser, sekFailed) = 1);
    Parser.Feed(SseLine('[DONE]'));
    Check('parse failure cannot complete', CountKind(Parser, sekCompleted) = 0);
    Parser.Reset;
    Parser.Feed(SseLine('{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c","function":{"arguments":"x"}}]}}]}') +
      SseLine('{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"x"}}]}}]}'));
    Check('chat arguments preserve repeated chunks', Parser.ToolCalls[0].Arguments = 'xx');
  Finally
    Parser.Free;
  End;
End;

Procedure TestChatCompletionsFallback;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"id":"c1","choices":[{"index":0,"delta":{"reasoning_content":"Hmm "}}]}') +
      SseLine('{"id":"c1","choices":[{"index":0,"delta":{"reasoning_content":"yes."}}]}') +
      SseLine('{"id":"c1","choices":[{"index":0,"delta":{"content":"Done."}}]}') +
      SseLine('{"id":"c1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],' +
        '"usage":{"prompt_tokens":4,"completion_tokens":3}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('completions wire', Parser.Wire = swkChatCompletions);
    Check('completions thinking', Parser.Thinking = 'Hmm yes.');
    Check('completions content', Parser.Content = 'Done.');
    Check('completions completed', CountKind(Parser, sekCompleted) = 1);
    Check('completions prompt tokens', Parser.InputTokens = 4);
  Finally
    Parser.Free;
  End;
End;

Procedure TestChatCompletionsTools;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_9","function":{"name":"list_directory","arguments":""}}]}}]}') +
      SseLine('{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":\".\"}"}}]}}]}') +
      SseLine('{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('cc tool count', Length(Parser.ToolCalls) = 1);
    Check('cc tool name', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Name = 'list_directory'));
    Check('cc tool id', (Length(Parser.ToolCalls) = 1) And (Parser.ToolCalls[0].Id = 'call_9'));
    Check('cc tool args', (Length(Parser.ToolCalls) = 1) And (Pos('path', Parser.ToolCalls[0].Arguments) > 0));
  Finally
    Parser.Free;
  End;
End;

Procedure TestSplitChunks;
Var
  Parser: TAssistantSseParser;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Parser.Feed('data: {"type":"response.created","response":{"id":"r"}}'#10'data: {"type":"response.output_text.');
    Parser.Feed('delta","delta":"Hi"}'#10'data: [DONE]'#10);
    Check('split content', Parser.Content = 'Hi');
    Check('split completed', CountKind(Parser, sekCompleted) = 1);
  Finally
    Parser.Free;
  End;
End;

Procedure TestResponsesRequestJson;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Body: String;
Begin
  SetLength(Items, 3);
  Items[0] := SamplerInputMessage('system', 'You are the assistant.');
  Items[1] := SamplerInputReasoning('reasoning_item_1', 'enc_hidden');
  Items[2] := SamplerInputMessage('user', 'Hello');
  Options := DefaultSamplerRequestOptions;
  Options.Model := 'grok-4.5';
  Options.ReasoningEffort := 'high';
  Options.ToolsJson := '[{"type":"function","function":{"name":"read_file"}}]';
  Body := BuildResponsesRequestJson(Items, Options);
  Check('req responses path shape', Pos('"stream":true', Body) > 0);
  Check('req store false', Pos('"store":false', Body) > 0);
  Check('req include encrypted', Pos('"include":["reasoning.encrypted_content"]', Body) > 0);
  Check('req reasoning effort object', Pos('"reasoning":{"effort":"high"}', Body) > 0);
  Check('req encrypted item', Pos('"encrypted_content":"enc_hidden"', Body) > 0);
  Check('req tools array', Pos('"tools":[', Body) > 0);
  Check('req no messages key', Pos('"messages":', Body) = 0);
  Options.ReasoningEffort := 'xhigh';
  Body := BuildResponsesRequestJson(Items, Options);
  Check('req reasoning effort xhigh', Pos('"reasoning":{"effort":"xhigh"}', Body) > 0);
End;

Procedure TestChatCompletionsRequestDropsReasoning;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Body: String;
Begin
  SetLength(Items, 3);
  Items[0] := SamplerInputMessage('user', 'Hi');
  Items[1] := SamplerInputReasoning('reasoning_item_1', 'enc_hidden');
  Items[2] := SamplerInputMessage('assistant', 'Hello');
  Options := DefaultSamplerRequestOptions;
  Body := BuildChatCompletionsRequestJson(Items, Options);
  Check('cc has messages', Pos('"messages":[', Body) > 0);
  Check('cc drops encrypted', Pos('enc_hidden', Body) = 0);
  Check('cc reasoning_effort', Pos('"reasoning_effort":"high"', Body) > 0);
  Options.ReasoningEffort := 'xhigh';
  Body := BuildChatCompletionsRequestJson(Items, Options);
  Check('cc reasoning_effort xhigh', Pos('"reasoning_effort":"xhigh"', Body) > 0);
End;

Procedure TestResponsesFailedIsError;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_fail"}}') +
      SseLine('{"type":"response.failed","response":{"error":{"message":"out of credit"}}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('failed flag', Parser.Failed);
    Check('failed event', CountKind(Parser, sekFailed) = 1);
    Check('failed message', Pos('out of credit', Parser.ErrorText) > 0);
    Check('failed not completed', CountKind(Parser, sekCompleted) = 0);
  Finally
    Parser.Free;
  End;
End;

Procedure TestResponsesIncomplete;
Var
  Parser: TAssistantSseParser;
  Body: String;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Body :=
      SseLine('{"type":"response.created","response":{"id":"resp_inc"}}') +
      SseLine('{"type":"response.output_text.delta","delta":"Partial"}') +
      SseLine('{"type":"response.incomplete","response":{"status":"incomplete",' +
        '"incomplete_details":{"reason":"max_output_tokens"},' +
        '"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial"}]}]}}') +
      SseLine('[DONE]');
    FeedAll(Parser, Body);
    Check('incomplete flag', Parser.Incomplete);
    Check('incomplete not failed', Not Parser.Failed);
    Check('incomplete reason', Parser.ErrorText = 'max_output_tokens');
    Check('incomplete keeps text', Pos('Partial', Parser.Content) > 0);
  Finally
    Parser.Free;
  End;
End;

Procedure TestFunctionRoundTripItems;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Body: String;
Begin
  SetLength(Items, 2);
  Items[0] := SamplerInputFunctionCall('call_1', 'read_file', '{"path":"A.pas"}');
  Items[1] := SamplerInputFunctionOutput('call_1', 'unit A;');
  Options := DefaultSamplerRequestOptions;
  Options.IncludeEncryptedReasoning := True;
  Body := BuildResponsesRequestJson(Items, Options);
  Check('fn call type', Pos('"type":"function_call"', Body) > 0);
  Check('fn output type', Pos('"type":"function_call_output"', Body) > 0);
  Check('fn call id', Pos('"call_id":"call_1"', Body) > 0);
End;

Procedure TestInvalidToolCompletion;
Var Parser: TAssistantSseParser;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Parser.Feed(SseLine('{"type":"response.output_item.added","output_index":0,' +
      '"item":{"type":"function_call","id":"fc_only","name":"write_file","arguments":"{}"}}'));
    Check('unfinished stream is not completed', Not Parser.Completed);
    Parser.Feed(SseLine('[DONE]'));
    Check('missing call ID is rejected instead of invented', Parser.Failed And Not Parser.Completed);
    Parser.Reset;
    Parser.Feed(SseLine('{"type":"response.completed","response":{"output":[' +
      '{"type":"function_call","call_id":"c","name":"write_file","arguments":"{"}]}}'));
    Check('truncated tool JSON cannot complete', Parser.Failed And Not Parser.Completed);
    Parser.Reset;
    Parser.Feed(SseLine('{"type":"response.completed","response":{"output":[' +
      '{"type":"function_call","call_id":"c","name":"write_file","arguments":"{}"},' +
      '{"type":"function_call","call_id":"c","name":"write_file","arguments":"{}"}]}}'));
    Check('duplicate call IDs cannot execute twice', Parser.Failed And Not Parser.Completed);
  Finally Parser.Free; End;
End;

Procedure TestMarkdownDeltasAreLossless;
Const Chunks: Array[0..11] Of String = ('| Unit | Interface | Implementation |', #10,
  '|', '---|', '---|', '---|', #10, '| **', 'StyledTextTypes', '**', ' | `Classes` | `SysUtils` |', #10);
Var Parser: TAssistantSseParser; Expected, Event: String; I, J: Integer;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Expected := '';
    For I := Low(Chunks) To High(Chunks) Do
      Begin
        Expected := Expected + Chunks[I];
        Event := SseLine('{"type":"response.output_text.delta","item_id":"table","delta":"' +
          JsonEscapeText(Chunks[I]) + '"}');
        For J := 1 To Length(Event) Do Parser.Feed(Event[J]);
      End;
    Check('stream preserves every Markdown delimiter', Parser.Content = Expected);
    Parser.Reset;
    For I := Low(Chunks) To High(Chunks) Do
      Parser.Feed(SseLine('{"choices":[{"delta":{"content":"' + JsonEscapeText(Chunks[I]) + '"}}]}'));
    Check('chat stream preserves every Markdown delimiter', Parser.Content = Expected);
  Finally Parser.Free; End;
End;

Procedure TestTextSnapshots;
Var Parser: TAssistantSseParser;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    Parser.Feed(SseLine('{"type":"response.output_text.delta","item_id":"a","delta":"partial"}'));
    Parser.Feed(SseLine('{"type":"response.output_item.done","item":{"type":"message","id":"a","content":[{"type":"output_text","text":"**fixed**"}]}}'));
    Check('item snapshot replaces partial text', Parser.Content = '**fixed**');
    Parser.Feed(SseLine('{"type":"response.output_text.delta","item_id":"b","delta":"**fixed**"}'));
    Check('identical distinct items are retained', Parser.Content = '**fixed**' + LineEnding + LineEnding + '**fixed**');
    Parser.Feed(SseLine('{"type":"response.output_item.done","item":{"type":"message","id":"a","content":[{"type":"output_text","text":"earlier"}]}}'));
    Check('earlier item snapshot keeps later item', Parser.Content = 'earlier' + LineEnding + LineEnding + '**fixed**');
    Parser.Feed(SseLine('{"type":"response.completed","response":{"output":[' +
      '{"type":"message","id":"a","content":[{"type":"output_text","text":"final"}]},' +
      '{"type":"message","id":"b","content":[{"type":"output_text","text":"final"}]}]}}'));
    Check('completed output replaces all partial messages', Parser.Content = 'final' + LineEnding + LineEnding + 'final');
    Parser.Reset;
    Parser.Feed(SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"r","delta":"**"}'));
    Parser.Feed(SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"r","delta":"word"}'));
    Parser.Feed(SseLine('{"type":"response.reasoning_summary_text.delta","item_id":"r","delta":"**"}'));
    Check('reasoning deltas preserve closing formatting', Parser.Thinking = '**word**');
    Parser.Reset;
    Parser.Feed(SseLine('{"choices":[{"delta":{"content":"partial"}}]}'));
    Parser.Feed(SseLine('{"choices":[{"message":{"content":"final"},"finish_reason":"stop"}]}'));
    Check('chat message snapshot replaces deltas', Parser.Content = 'final');
  Finally Parser.Free; End;
End;

Procedure TestMergeSkipsRepeatedThought;
Var
  Accum, First: String;
  Tick: QWord;
  I: Integer;
Begin
  First := 'user asked me to review this project for bugs. The active project is EcologySurveyScheduler.';
  Accum := First;
  Check('merge first copy skipped', Not MergeSamplerText(Accum, First));
  Check('merge accum unchanged', Accum = First);
  Check('merge similar paragraph skipped', Not MergeSamplerText(Accum,
    'user asked me to review this project for bugs. The active project is EcologySurveyScheduler, not LazWorkflow.'));
  For I := 1 To 40 Do
    MergeSamplerText(Accum,
      'user asked me to review this project for bugs. The active project is EcologySurveyScheduler (' + IntToStr(I) + ').');
  Check('merge repeats do not grow a CoT wall', Accum = First);
  Check('merge new sentence appends', MergeSamplerText(Accum,
    'Next I will open the project main file and scan for nil checks.'));
  Check('merge new sentence present', Pos('scan for nil checks', Accum) > 0);
  Accum := StringOfChar('x', 20000);
  Tick := GetTickCount64;
  MergeSamplerText(Accum, 'yyyy');
  Check('merge on long accum stays fast', GetTickCount64 - Tick < 500);
End;

Begin
  FailCount := 0;
  TestResponsesReasoningAndText;
  TestInterleavedThoughtAndContent;
  TestResponsesEncryptedHarvest;
  TestResponsesToolCall;
  TestOutputItemAddedDoesNotDuplicateTool;
  TestDistinctToolIdsAndRepeatedArguments;
  TestToolDoneAndInvalidIndex;
  TestChatCompletionsFallback;
  TestChatCompletionsTools;
  TestSplitChunks;
  TestResponsesRequestJson;
  TestChatCompletionsRequestDropsReasoning;
  TestFunctionRoundTripItems;
  TestResponsesFailedIsError;
  TestResponsesIncomplete;
  TestInvalidToolCompletion;
  TestMarkdownDeltasAreLossless;
  TestTextSnapshots;
  TestMergeSkipsRepeatedThought;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantSampler tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantSampler test(s) failed.');
      Halt(1);
    End;
End.
