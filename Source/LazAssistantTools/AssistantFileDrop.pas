Unit AssistantFileDrop;

{ File-drop arm for controls the form window does not cover (c) 2026 Michell Computing.

  LCL facility: TCustomForm.AllowDropFiles and OnDropFiles. Checked LCL 5.99.0.0:
  TWinControl has no AllowDropFiles. TWin32WSCustomForm.SetAllowDropFiles calls
  DragAcceptFiles on the form HWND only. TQtWSCustomForm.SetAllowDropFiles sets
  acceptDrops on the main window only. TGtk3WSCustomForm.SetAllowDropFiles sets
  a drag destination on the form widget only, so a child window is still not a
  drop target. TCocoaWSCustomForm.SetAllowDropFiles registers the content view,
  and AppKit walks an unregistered child up to that view. Widgetset bodies live
  in their own units. This unit does not use them. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Controls, Forms;

/// Arms one control so a file drop on it reaches Form.OnDropFiles. Cocoa is a no-op.
Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
/// Forgets controls armed for Form. Frees the bookkeeping list when the last form goes.
Procedure ReleaseInputFileDrop(Form: TCustomForm);

Implementation

Uses
  {$IFDEF LCLGTK3}AssistantFileDropGtk3{$ENDIF}
  {$IFDEF LCLWIN32}AssistantFileDropWin32{$ENDIF}
  {$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}AssistantFileDropQt{$ENDIF}
  {$IF NOT DEFINED(LCLGTK3) AND NOT DEFINED(LCLWIN32) AND NOT DEFINED(LCLQT5) AND NOT DEFINED(LCLQT6)}
  SysUtils
  {$ENDIF};

Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
Begin
  {$IF DEFINED(LCLGTK3) OR DEFINED(LCLWIN32) OR DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
  ArmWidgetSetFileDrop(Control, Form);
  {$ELSE}
  { Cocoa: the content view already delivers the drop. }
  If Assigned(Control) And Assigned(Form) Then
    Exit;
  {$ENDIF}
End;

Procedure ReleaseInputFileDrop(Form: TCustomForm);
Begin
  {$IF DEFINED(LCLGTK3) OR DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
  ReleaseWidgetSetFileDrop(Form);
  {$ELSE}
  If Assigned(Form) Then
    Exit;
  {$ENDIF}
End;

End.
