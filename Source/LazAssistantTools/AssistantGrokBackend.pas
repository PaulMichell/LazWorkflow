Unit AssistantGrokBackend;

{ Grok turn-backend registration (c) 2026 Michell Computing.

  Reports the section 5 matrix. Does not start a turn and does not wrap the actor.
  Image output is the profile flag, not a hard absence. Subagents are this engine's own child runs. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Implementation

Uses
  AssistantCapabilities;

Function GrokCapabilitySet: TAssistantCapabilitySet;
Begin
  Result := AbsentCapabilitySet;
  Result[acHarnessPrompt] := asNative;
  Result[acSkillsAndAgents] := asNative;
  Result[acSubagents] := asNative;
  Result[acTodoWrite] := asNative;
  Result[acImageInput] := asNative;
  Result[acImageOutput] := asNative;
  Result[acWebSearch] := asNative;
  Result[acSteer] := asNative;
  Result[acPhoneApproval] := asNative;
  Result[acContextCompaction] := asNative;
  Result[acEventsJSONL] := asNative;
  Result[acAccountUsage] := asNative;
  Result[acEffortControl] := asNative;
End;

Procedure RegisterGrokBackend;
Var
  Info: TAssistantBackendInfo;
Begin
  Info.Id := 'grok';
  Info.DisplayName := 'Grok';
  Info.Support := GrokCapabilitySet;
  Info.ShowsEffort := True;
  Info.ReadyKind := erSignedIn;
  { The service keeps the message array. This engine has no session id. }
  Info.Continuity := acoMessageHistory;
  RegisterAssistantBackend(Info);
End;

Initialization

RegisterGrokBackend;

End.
