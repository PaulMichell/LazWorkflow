Unit RegLazRepositoryTools;

{ Lazarus IDE Repository Tools package – registration and IDE integration (c) 2026 Michell Computing. }

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
  RepositoryManagerMain, GitDiffView;

Procedure Register;
Begin
  { Shared Common controls are registered by RegLazWorkflowCommon. }
  RegisterNoIcon([TGitDiffView]);
  RegisterGitManager;
End;

End.
