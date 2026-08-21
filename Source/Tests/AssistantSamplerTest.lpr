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

Begin
  FailCount := 0;
  TestResponsesReasoningAndText;
  TestResponsesEncryptedHarvest;
  TestResponsesToolCall;
  TestChatCompletionsFallback;
  TestChatCompletionsTools;
  TestSplitChunks;
  TestResponsesRequestJson;
  TestChatCompletionsRequestDropsReasoning;
  TestFunctionRoundTripItems;
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
