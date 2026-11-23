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
  AssistantCapabilities;

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
  RegisterAssistantBackend(Info);
End;

Initialization

RegisterCompatibleBackend;

End.
