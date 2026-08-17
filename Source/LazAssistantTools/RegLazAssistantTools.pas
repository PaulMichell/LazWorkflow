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
  AssistantMain, SpellMemo, SpellCheckerSettingsFrame;

Procedure Register;
Begin
  RegisterNoIcon([TSpellMemo, TSpellCheckerSettingsFrame]);
  RegisterAssistantTools;
End;

End.
