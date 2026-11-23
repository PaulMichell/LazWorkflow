Unit AssistantClaudeBackend;

{ Claude turn-backend registration (c) 2026 Michell Computing.

  Reports the section 5 matrix. Does not start Claude Code and does not append a system prompt.
  Effort is sent on the turn and is not shown in the footer yet; the row is still Native because the wire
  delivers it. Image output is withheld. Account usage stays unregistered on purpose. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Implementation

Uses
  AssistantCapabilities;

Function ClaudeCapabilitySet: TAssistantCapabilitySet;
Begin
  Result := AbsentCapabilitySet;
  Result[acTodoWrite] := asNative;
  Result[acImageInput] := asNative;
  Result[acRevisionEdits] := asNative;
  Result[acAsyncWork] := asNative;
  Result[acEffortControl] := asNative;
End;

Procedure RegisterClaudeBackend;
Var
  Info: TAssistantBackendInfo;
Begin
  Info.Id := 'claude';
  Info.DisplayName := 'Claude';
  Info.Support := ClaudeCapabilitySet;
  { Sent on the turn. The footer does not show it. }
  Info.ShowsEffort := False;
  RegisterAssistantBackend(Info);
End;

Initialization

RegisterClaudeBackend;

End.
