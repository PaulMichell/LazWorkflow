Unit RegLazAssistantTools;

{ Lazarus IDE Assistant Tools package – registration and IDE integration (c) 2026 Michell Computing. }

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
  MenuIntf, IDECommands, IDEWindowIntf, LazarusPackageIntf,
  AssistantMain;

Procedure Register;
Begin
  RegisterAssistantTools;
End;

End.
