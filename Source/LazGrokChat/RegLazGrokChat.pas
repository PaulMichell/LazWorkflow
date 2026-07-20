Unit RegLazGrokChat;

{ Lazarus IDE Grok Chat package – registration and IDE integration (c) 2026 Michell Computing. }

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
  GrokChatMain;

Procedure Register;
Begin
  RegisterGrokChat;
End;

End.
