Unit RegLazStyledText;

{ Lazarus component palette registration for styled text controls (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Procedure Register;

Implementation

Uses
  Classes, StyledControls, StyledList;

Procedure Register;
Begin
  RegisterComponents('Styled', [TStyledEdit, TStyledMemo, TStyledList]);
End;

End.
