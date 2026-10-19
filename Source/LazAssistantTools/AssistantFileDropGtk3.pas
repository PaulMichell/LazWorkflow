Unit AssistantFileDropGtk3;

{ GTK3 child file-drop arm (c) 2026 Michell Computing.

  The form widget is already a drag destination. A child Gdk window is not,
  so this unit arms the controls the form passes in. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

{$IFDEF LCLGTK3}
Uses
  Controls, Forms;

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
Procedure ReleaseWidgetSetFileDrop(Form: TCustomForm);
{$ENDIF}

Implementation

{$IFDEF LCLGTK3}
Uses
  Classes, SysUtils, gtk3widgets, LazGtk3, LazGdk3, LazGLib2, LazGObject2;

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

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
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

Procedure ReleaseWidgetSetFileDrop(Form: TCustomForm);
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

{$IFDEF LCLGTK3}
Finalization
FreeArmedDropControls;
{$ENDIF}

End.
