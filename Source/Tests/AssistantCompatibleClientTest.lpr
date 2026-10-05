Program AssistantCompatibleClientTest;

{ Fixture coverage for the OpenAI-compatible client. The transport answers in
  memory, so this program does not open a socket. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, AssistantConnections, AssistantCompatibleClient;

Const
  FixtureKey = 'fixture-secret-key';
  ModelListBody = '{"data":[{"id":"openai/gpt-4.1"},{"id":"meta/llama"}]}';
  UsageBody = '{"choices":[{"message":{"role":"assistant","content":"fixture answer"}}],' +
    '"usage":{"prompt_tokens":12,"completion_tokens":4,"cost":0.5}}';
  NoUsageBody = '{"choices":[{"message":{"role":"assistant","content":"plain answer"}}]}';

Var
  NextStatus: Integer;
  NextBody, LastUrl, LastHeaders, LastBody: String;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function FixtureGet(Const Url, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  LastUrl := Url;
  LastHeaders := ExtraHeaders;
  LastBody := '';
  StatusCode := NextStatus;
  ResponseBody := NextBody;
  ErrorText := '';
  Result := True;
End;

Function FixturePost(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  LastUrl := Url;
  LastHeaders := ExtraHeaders;
  LastBody := JsonBody;
  StatusCode := NextStatus;
  ResponseBody := NextBody;
  ErrorText := '';
  Result := True;
End;

Function PostedHas(Const Name: String): Boolean;
Var
  Data: TJSONData;
Begin
  Result := False;
  Data := Nil;
  Try
    Data := GetJSON(LastBody);
    Result := Assigned(Data) And (Data Is TJSONObject) And Assigned(TJSONObject(Data).Find(Name));
  Except
    On E: Exception Do
      Result := False;
  End;
  Data.Free;
End;

Function PostedInt(Const Name: String): Integer;
Var
  Data: TJSONData;
Begin
  Result := -1;
  Data := Nil;
  Try
    Data := GetJSON(LastBody);
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get(Name, -1);
  Except
    On E: Exception Do
      Result := -1;
  End;
  Data.Free;
End;

Function Messages: TJSONArray;
Begin
  Result := TJSONArray.Create;
  Result.Add(TJSONObject.Create);
  TJSONObject(Result.Items[0]).Add('role', 'user');
  TJSONObject(Result.Items[0]).Add('content', 'Say hello');
End;

Procedure PrepareConnection(Connection: TAssistantConnection; Const Preset: String; MaxTokens: Integer);
Begin
  Connection.ApiBase := AssistantOpenRouterApiBase;
  Connection.WireApi := AssistantWireChatCompletions;
  Connection.KeySource := 'stored';
  Connection.KeyValue := FixtureKey;
  Connection.Preset := Preset;
  Connection.Model := 'fixture-model';
  Connection.MaxOutputTokens := MaxTokens;
End;

Var
  Client: TAssistantCompatibleClient;
  Connection: TAssistantConnection;
  Models: TStringList;
  Sent: TJSONArray;
  Completion: TCompatibleCompletion;
  ErrorText: String;
Begin
  NextStatus := 200;
  NextBody := ModelListBody;
  LastUrl := '';
  Client := TAssistantCompatibleClient.CreateForTransport(@FixtureGet, @FixturePost);
  Connection := TAssistantConnection.Create;
  Models := TStringList.Create;
  Try
    PrepareConnection(Connection, 'openrouter', 32);
    Check('model list fixture', Client.ListModels(Connection, Models, ErrorText) And (Models.Count = 2) And
      (Models[0] = 'openai/gpt-4.1') And (Models[1] = 'meta/llama'));
    Check('model list uses the models path', LastUrl = AssistantOpenRouterApiBase + '/models');
    Check('openrouter list sends the title', Pos('X-Title: LazWorkflow', LastHeaders) > 0);
    Check('list authorization is the stored bearer', Pos('Authorization: Bearer ' + FixtureKey, LastHeaders) = 1);

    NextBody := UsageBody;
    Sent := Messages;
    Try
      Check('usage fixture completion', Client.CompleteOnce(Connection, Sent, Completion, ErrorText));
    Finally
      Sent.Free;
    End;
    Check('usage fixture returns the assistant text', Completion.Text = 'fixture answer');
    Check('usage fixture returns token counts', (Completion.PromptTokens = 12) And (Completion.CompletionTokens = 4));
    Check('usage fixture returns the cost', Completion.HasCost And (Abs(Completion.Cost - 0.5) < 0.000001));
    Check('usage fixture is reported', Completion.UsageState = CompatibleUsageReported);
    Check('completion uses chat completions', LastUrl = AssistantOpenRouterApiBase + '/chat/completions');
    Check('completion sends max tokens', PostedInt('max_tokens') = 32);
    Check('completion does not send Grok fields', Not PostedHas('reasoning') And Not PostedHas('search') And
      Not PostedHas('citation') And Not PostedHas('reasoning_effort'));
    Check('completion body does not contain the key', Pos(FixtureKey, LastBody) = 0);

    NextBody := NoUsageBody;
    Connection.Preset := 'custom';
    Connection.ApiBase := 'https://example.invalid/v1';
    Connection.MaxOutputTokens := 0;
    Sent := Messages;
    Try
      Check('no-usage fixture completion', Client.CompleteOnce(Connection, Sent, Completion, ErrorText));
    Finally
      Sent.Free;
    End;
    Check('no-usage fixture returns the text', Completion.Text = 'plain answer');
    Check('no-usage fixture is unavailable', Completion.UsageState = CompatibleUsageUnavailable);
    Check('no-usage fixture has no cost', Not Completion.HasCost);
    Check('zero token cap is omitted', Not PostedHas('max_tokens'));
    Check('custom preset does not send the title', Pos('X-Title', LastHeaders) = 0);

    NextBody := '{"object":"list"}';
    Check('non-list body is an error', Not Client.ListModels(Connection, Models, ErrorText) And
      (ErrorText = 'The response is not a model list.'));

    NextStatus := 503;
    NextBody := '{"error":{"message":"overloaded"}}';
    Check('non-200 returns the provider error', Not Client.ListModels(Connection, Models, ErrorText) And
      (Pos('HTTP 503', ErrorText) > 0) And (Pos('overloaded', ErrorText) > 0));
    Check('provider error does not contain the key', Pos(FixtureKey, ErrorText) = 0);

    LastUrl := '';
    Connection.KeySource := 'env';
    Connection.KeyEnv := 'LAZ_COMPATIBLE_FIXTURE_KEY_UNSET';
    Connection.KeyValue := '';
    Check('unset environment variable fails clearly', Not Client.ListModels(Connection, Models, ErrorText) And
      (Pos('is not set', ErrorText) > 0));
    Check('unset environment variable does not call transport', LastUrl = '');
    Check('unset message does not contain a key', Pos(FixtureKey, ErrorText) = 0);
  Finally
    Models.Free;
    Connection.Free;
    Client.Free;
  End;
End.
