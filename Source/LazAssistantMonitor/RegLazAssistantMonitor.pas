Unit RegLazAssistantMonitor;

{ Lazarus IDE Remote Monitor package registration (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Procedure Register;

Implementation

Uses
  AssistantMonitorMain;

Procedure Register;
Begin
  RegisterAssistantMonitor;
End;

End.
