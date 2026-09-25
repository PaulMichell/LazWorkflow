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
  LazIDEIntf, StatusFooterFrame, SpellMemo, SpellCheckerSettingsFrame, SpellCheckerConfig, WorkflowLog;

Procedure Register;
Begin
  { Register once here. Consumer packages must not RegisterNoIcon these classes. }
  RegisterNoIcon([TStatusFooterFrame, TSpellMemo, TSpellCheckerSettingsFrame]);
  If Assigned(LazarusIDE) Then
    InitializeSpellCheckerStorage(LazarusIDE.GetPrimaryConfigPath);
  { Start Hunspell as soon as the IDE loads this package so first form open does not wait. }
  If Assigned(WorkflowSpellConfig) Then
    Begin
      WorkflowSpellConfig.EnsurePreloaded;
      If Assigned(WorkflowLogger) Then
        WorkflowLogger.Info('Spell', 'Preloading spell engine in the background');
    End;
End;

End.
