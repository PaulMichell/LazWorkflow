Unit AssistantFileDrop;

{ Native file-drop arming for controls the form window does not cover (c) 2026 Michell Computing.

  LCL facility: TCustomForm.AllowDropFiles and OnDropFiles. The form implements
  that event. TCocoaWSCustomForm.SetAllowDropFiles registers the content view,
  and AppKit walks an unregistered child up to that view, so Cocoa needs no
  extra arm. TWin32WSCustomForm.SetAllowDropFiles calls DragAcceptFiles on the
  form HWND only. TQtWSCustomForm.SetAllowDropFiles sets acceptDrops on the
  main window only. GTK3 has no SetAllowDropFiles, and FileDragTarget is unused,
  so a child is not a drop destination. Those three arm the controls passed in. }

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
  Classes, SysUtils
  {$IFDEF LCLGTK3}, gtk3widgets, LazGtk3, LazGdk3, LazGLib2, LazGObject2{$ENDIF}
  {$IFDEF LCLWIN32}, Windows{$ENDIF}
  {$IFDEF LCLQT5}, qt5, qtwidgets{$ENDIF}
  {$IFDEF LCLQT6}, qt6, qtwidgets{$ENDIF};

{$IFDEF LCLGTK3}
Type
  TGtkDropArm = Class
    Control: TWinControl;
    OwnerForm: TCustomForm;
  End;

Var
  { Armed LCL controls. Removed when their window is destroyed so a reused pointer is not treated as already armed. }
  ArmedDropControls: TList;

Function FindGtkDropArm(Control: TWinControl): TGtkDropArm;
Var
  I: Integer;
  Arm: TGtkDropArm;
Begin
  Result := Nil;
  If Not Assigned(ArmedDropControls) Or Not Assigned(Control) Then
    Exit;
  For I := 0 To ArmedDropControls.Count - 1 Do
    Begin
      Arm := TGtkDropArm(ArmedDropControls[I]);
      If Arm.Control = Control Then
        Exit(Arm);
    End;
End;

Procedure GtkFileDropReceived(Widget: PGtkWidget; Context: PGdkDragContext; X, Y: LongInt; Data: PGtkSelectionData;
  Info: LongWord; Time: LongWord; UserData: Pointer); cdecl;
Var
  Uris: PPChar;
  I: Integer;
  Names: Array Of String;
  Form: TCustomForm;
  Accepted: Boolean;
Begin
  Accepted := False;
  Names := Nil;
  Uris := Nil;
  Try
    If Not (TObject(UserData) Is TCustomForm) Then
      Exit;
    Form := TCustomForm(UserData);
    If Not Assigned(Data) Then
      Exit;
    Uris := PPChar(gtk_selection_data_get_uris(Data));
    If Uris = Nil Then
      Exit;
    I := 0;
    While Uris[I] <> Nil Do
      Begin
        SetLength(Names, Length(Names) + 1);
        Names[High(Names)] := Uris[I];
        Inc(I);
      End;
    If (Length(Names) > 0) And Assigned(Form.OnDropFiles) Then
      Begin
        Form.OnDropFiles(Form, Names);
        Accepted := True;
      End;
  Finally
    If Uris <> Nil Then
      g_strfreev(Uris);
    If Context <> Nil Then
      gtk_drag_finish(Context, Accepted, False, Time);
  End;
End;

Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
Var
  Target: TGtkTargetEntry;
  Native: PGtkWidget;
  ConnectFlags: TGConnectFlags;
  Arm: TGtkDropArm;
Begin
  If Not Assigned(Control) Or Not Assigned(Form) Or Not Control.HandleAllocated Or
    Not (TObject(Control.Handle) Is TGtk3Widget) Then
    Exit;
  If FindGtkDropArm(Control) <> Nil Then
    Exit;
  Native := TGtk3Widget(Control.Handle).Widget;
  If Native = Nil Then
    Exit;
  Target.target := 'text/uri-list';
  Target.flags := 0;
  Target.info := 0;
  ConnectFlags := Default(TGConnectFlags);
  gtk_drag_dest_set(Native, GTK_DEST_DEFAULT_ALL, @Target, 1, [GDK_ACTION_COPY]);
  g_signal_connect_data(Native, 'drag-data-received', TGCallback(@GtkFileDropReceived), Form, Nil, ConnectFlags);
  If Not Assigned(ArmedDropControls) Then
    ArmedDropControls := TList.Create;
  Arm := TGtkDropArm.Create;
  Arm.Control := Control;
  Arm.OwnerForm := Form;
  ArmedDropControls.Add(Arm);
End;

Procedure ReleaseGtkFileDrop(Form: TCustomForm);
Var
  I: Integer;
  Arm: TGtkDropArm;
Begin
  If Not Assigned(ArmedDropControls) Or Not Assigned(Form) Then
    Exit;
  { FormDestroy runs while these controls are still alive. Drop them now, before the heap can reuse the pointer. }
  For I := ArmedDropControls.Count - 1 DownTo 0 Do
    Begin
      Arm := TGtkDropArm(ArmedDropControls[I]);
      If Arm.OwnerForm <> Form Then
        Continue;
      ArmedDropControls.Delete(I);
      Arm.Free;
    End;
  If ArmedDropControls.Count = 0 Then
    FreeAndNil(ArmedDropControls);
End;

Procedure FreeArmedDropControls;
Var
  I: Integer;
Begin
  If Not Assigned(ArmedDropControls) Then
    Exit;
  For I := ArmedDropControls.Count - 1 DownTo 0 Do
    TGtkDropArm(ArmedDropControls[I]).Free;
  FreeAndNil(ArmedDropControls);
End;
{$ENDIF}

{$IFDEF LCLWIN32}
Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
Begin
  If Not Assigned(Control) Or Not Assigned(Form) Or Not Control.HandleAllocated Then
    Exit;
  { The child window proc already calls IntfGetDropFilesTarget and DragFinish. }
  DragAcceptFiles(Control.Handle, True);
End;
{$ENDIF}

{$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
Type
  TQtFileDropArm = Class
    OwnerForm: TCustomForm;
    QtObject: TQtWidget;
    Hook: QObject_hookH;
    Function Filter(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
  End;

Var
  QtFileDropArms: TList;

Function TQtFileDropArm.Filter(Sender: QObjectH; Event: QEventH): Boolean; cdecl;
Begin
  Result := False;
  If Not Assigned(QtObject) Or (QEvent_type(Event) <> QEventDrop) Then
    Exit;
  Result := QtObject.slotDropFiles(Sender, Event);
End;

Procedure HookQtDrop(Form: TCustomForm; QtObject: TQtWidget; Widget: QWidgetH);
Var
  Arm: TQtFileDropArm;
Begin
  If Widget = Nil Then
    Exit;
  QWidget_setAcceptDrops(Widget, True);
  If Not Assigned(QtFileDropArms) Then
    QtFileDropArms := TList.Create;
  Arm := TQtFileDropArm.Create;
  Arm.OwnerForm := Form;
  Arm.QtObject := QtObject;
  Arm.Hook := QObject_hook_create(Widget);
  QObject_hook_hook_events(Arm.Hook, @Arm.Filter);
  QtFileDropArms.Add(Arm);
End;

Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
Var
  QtObject: TQtWidget;
  Viewport: QWidgetH;
Begin
  If Not Assigned(Control) Or Not Assigned(Form) Or Not Control.HandleAllocated Then
    Exit;
  QtObject := TQtWidget(Control.Handle);
  HookQtDrop(Form, QtObject, QtObject.Widget);
  If QtObject Is TQtAbstractScrollArea Then
    Begin
      Viewport := TQtAbstractScrollArea(QtObject).viewportWidget;
      If Viewport <> QtObject.Widget Then
        HookQtDrop(Form, QtObject, Viewport);
    End;
End;

Procedure ReleaseQtFileDrop(Form: TCustomForm);
Var
  I: Integer;
  Arm: TQtFileDropArm;
Begin
  If Not Assigned(QtFileDropArms) Then
    Exit;
  For I := QtFileDropArms.Count - 1 DownTo 0 Do
    Begin
      Arm := TQtFileDropArm(QtFileDropArms[I]);
      If Assigned(Form) And (Arm.OwnerForm <> Form) Then
        Continue;
      If Arm.Hook <> Nil Then
        QObject_hook_destroy(Arm.Hook);
      Arm.Free;
      QtFileDropArms.Delete(I);
    End;
  If QtFileDropArms.Count = 0 Then
    FreeAndNil(QtFileDropArms);
End;
{$ENDIF}

{$IF NOT DEFINED(LCLGTK3) AND NOT DEFINED(LCLWIN32) AND NOT DEFINED(LCLQT5) AND NOT DEFINED(LCLQT6)}
Procedure ArmControlFileDrop(Control: TWinControl; Form: TCustomForm);
Begin
  { Cocoa: TCocoaWSCustomForm.SetAllowDropFiles already delivers the drop. }
  If Assigned(Control) And Assigned(Form) Then
    Exit;
End;
{$ENDIF}

Procedure ReleaseInputFileDrop(Form: TCustomForm);
Begin
  If Not Assigned(Form) Then
    Exit;
  {$IFDEF LCLGTK3}
  ReleaseGtkFileDrop(Form);
  {$ENDIF}
  {$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
  ReleaseQtFileDrop(Form);
  {$ENDIF}
End;

Finalization

{$IFDEF LCLGTK3}
FreeArmedDropControls;
{$ENDIF}
{$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
ReleaseQtFileDrop(Nil);
{$ENDIF}

End.
