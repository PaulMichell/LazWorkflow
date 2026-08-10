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
  RepositoryManagerMain, StatusFooterFrame, GitDiffView;

Procedure Register;
Begin
  { Frames used as inline children must be registered for the form designer. }
  RegisterNoIcon([TStatusFooterFrame, TGitDiffView]);
  RegisterGitManager;
End;

End.
