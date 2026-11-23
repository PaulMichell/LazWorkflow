Unit AssistantCompatibleBackend;

{ OpenAI-compatible capability row (c) 2026 Michell Computing.

  Not a turn backend. The image adapter exists, and the account-usage query is registered.
  Context compaction is Absent: there is no history array to compact. That corrects the old flag,
  which was true only because the id was grouped with Grok. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Implementation

Uses
  AssistantCapabilities, AssistantConnections, fpjson;

Procedure ApplyCompatibleConfig(Item: TAssistantConnection; Config: TJSONObject);
Begin
  If Not Assigned(Item) Or Not Assigned(Config) Then
    Exit;
  If Config.Find('api_base') <> Nil Then
    Item.ApiBase := Config.Get('api_base', Item.ApiBase);
  If Config.Find('preset') <> Nil Then
    Item.Preset := Config.Get('preset', Item.Preset);
  If Config.Find('key_source') <> Nil Then
    Item.KeySource := Config.Get('key_source', Item.KeySource);
  If Config.Find('key_env') <> Nil Then
    Item.KeyEnv := Config.Get('key_env', Item.KeyEnv);
  If Config.Find('key_value') <> Nil Then
    Item.KeyValue := Config.Get('key_value', Item.KeyValue);
  If Config.Find('wire_api') <> Nil Then
    Item.WireApi := Config.Get('wire_api', Item.WireApi);
End;

Procedure CollectCompatibleConfig(Item: TAssistantConnection; Config: TJSONObject);
Begin
  If Not Assigned(Item) Or Not Assigned(Config) Then
    Exit;
End;

Function CompatibleCapabilitySet: TAssistantCapabilitySet;
Begin
  Result := AbsentCapabilitySet;
  Result[acImageOutput] := asNative;
  Result[acAccountUsage] := asNative;
End;

Procedure RegisterCompatibleBackend;
Var
  Info: TAssistantBackendInfo;
Begin
  Info.Id := 'openai-compatible';
  Info.DisplayName := 'OpenAI-compatible';
  Info.Support := CompatibleCapabilitySet;
  Info.ShowsEffort := False;
  Info.ReadyKind := erNone;
  { Not a turn engine. Message history is the unused default, not a session id. }
  Info.Continuity := acoMessageHistory;
  RegisterAssistantBackend(Info);
  RegisterConnectionConfig('openai-compatible', @ApplyCompatibleConfig, @CollectCompatibleConfig);
End;

Initialization

RegisterCompatibleBackend;

End.
