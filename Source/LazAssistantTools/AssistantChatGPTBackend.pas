Unit AssistantChatGPTBackend;

{ ChatGPT turn-backend registration (c) 2026 Michell Computing.

  The connection id is codex. Reports the section 5 matrix and does not start a Codex turn.
  Subagents are offered by the live catalogue and then refused; the path does not deliver them, so the row is
  Absent. Image output is withheld: there is no vendor image endpoint to emulate. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Implementation

Uses
  AssistantCapabilities, AssistantConnections, fpjson;

Procedure ApplyCodexConfig(Item: TAssistantConnection; Config: TJSONObject);
Begin
  If Not Assigned(Item) Or Not Assigned(Config) Then
    Exit;
  If Config.Find('runtime') <> Nil Then
    Item.Runtime := Config.Get('runtime', Item.Runtime);
  If Config.Find('models_json') <> Nil Then
    Item.CachedModelsJson := Config.Get('models_json', Item.CachedModelsJson);
End;

Procedure CollectCodexConfig(Item: TAssistantConnection; Config: TJSONObject);
Begin
  If Not Assigned(Item) Or Not Assigned(Config) Then
    Exit;
End;

Function ChatGPTCapabilitySet: TAssistantCapabilitySet;
Begin
  Result := AbsentCapabilitySet;
  Result[acHarnessPrompt] := asNative;
  Result[acSkillsAndAgents] := asNative;
  Result[acTodoWrite] := asNative;
  Result[acImageInput] := asNative;
  Result[acSteer] := asNative;
  Result[acAccountUsage] := asNative;
  Result[acEffortControl] := asNative;
End;

Procedure RegisterChatGPTBackend;
Var
  Info: TAssistantBackendInfo;
Begin
  Info.Id := 'codex';
  Info.DisplayName := 'ChatGPT';
  Info.Support := ChatGPTCapabilitySet;
  Info.ShowsEffort := True;
  Info.ReadyKind := erRuntimeAndModel;
  { Each turn is an ephemeral thread. Earlier turns arrive as a bounded recap. }
  Info.Continuity := acoRecapOnly;
  RegisterAssistantBackend(Info);
  RegisterConnectionConfig('codex', @ApplyCodexConfig, @CollectCodexConfig);
End;

Initialization

RegisterChatGPTBackend;

End.
