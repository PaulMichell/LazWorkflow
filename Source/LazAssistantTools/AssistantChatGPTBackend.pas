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
  AssistantCapabilities;

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
  RegisterAssistantBackend(Info);
End;

Initialization

RegisterChatGPTBackend;

End.
