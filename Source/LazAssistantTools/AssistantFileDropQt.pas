Unit AssistantFileDropQt;

{ Qt5 and Qt6 child file-drop arm (c) 2026 Michell Computing.

  acceptDrops on the main window does not cover a child widget or a scroll-area
  viewport. The hook forwards the drop to the LCL slot. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

{$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
Uses
  Controls, Forms;

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
Procedure ReleaseWidgetSetFileDrop(Form: TCustomForm);
{$ENDIF}

Implementation

{$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
Uses
  Classes, SysUtils
  {$IFDEF LCLQT5}, qt5, qtwidgets{$ENDIF}
  {$IFDEF LCLQT6}, qt6, qtwidgets{$ENDIF};

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

Procedure ArmWidgetSetFileDrop(Control: TWinControl; Form: TCustomForm);
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

Procedure ReleaseWidgetSetFileDrop(Form: TCustomForm);
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

{$IF DEFINED(LCLQT5) OR DEFINED(LCLQT6)}
Finalization
ReleaseWidgetSetFileDrop(Nil);
{$ENDIF}

End.
