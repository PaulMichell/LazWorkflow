Unit LazWorkflowCommon;

{ Shared foundation for LazGitManager and LazGrokChat packages (c) 2026 Michell Computing. }

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
  LazarusPackageIntf;

Procedure Register;
Begin
  { No components to register on the palette. This package provides interfaces,
    event bus and helpers only. }
End;

End.
