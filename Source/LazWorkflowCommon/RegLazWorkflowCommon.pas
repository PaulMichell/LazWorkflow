Unit RegLazWorkflowCommon;

{ Designer registration for shared LazWorkflow controls (c) 2026 Michell Computing. }

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
  StatusFooterFrame, SpellMemo, SpellCheckerSettingsFrame;

Procedure Register;
Begin
  { Register once here. Consumer packages must not RegisterNoIcon these classes. }
  RegisterNoIcon([TStatusFooterFrame, TSpellMemo, TSpellCheckerSettingsFrame]);
End;

End.
