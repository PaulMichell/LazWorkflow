Unit AssistantCodeToolsGuard;

{ Main-thread serialization across assistant adapters and IDE callbacks. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Function EnterAssistantCodeTools: Boolean;
Procedure LeaveAssistantCodeTools;

Implementation

Var
  Busy: Boolean = False;

Function EnterAssistantCodeTools: Boolean;
Begin
  Result := Not Busy;
  If Result Then Busy := True;
End;

Procedure LeaveAssistantCodeTools;
Begin
  Busy := False;
End;
End.
