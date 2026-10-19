Unit AssistantFileDropWin32;

{ Win32 child file-drop arm (c) 2026 Michell Computing.

  DragAcceptFiles on the form HWND does not cover a child window. The child
  window proc already calls IntfGetDropFilesTarget and DragFinish. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

{$IFDEF LCLWIN32}
Uses
  Controls, Forms;

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
{$ENDIF}

Implementation

{$IFDEF LCLWIN32}
Uses
  Windows;

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
Begin
  If Not Assigned(Control) Or Not Assigned(Form) Or Not Control.HandleAllocated Then
    Exit;
  DragAcceptFiles(Control.Handle, True);
End;
{$ENDIF}

End.
