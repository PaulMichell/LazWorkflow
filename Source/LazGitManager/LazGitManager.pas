Unit LazGitManager;

{ Lazarus IDE Git Manager package – registration and IDE integration (c) 2026 Michell Computing. }

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
  GitManagerMain, GitGraphForm;

Procedure Register;
Begin
  RegisterGitManager;
End;

End.
