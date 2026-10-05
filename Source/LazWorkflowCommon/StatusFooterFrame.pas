Unit StatusFooterFrame;

{ Reusable status footer frame for chat and tool windows (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls;

Type
  TStatusFooterFrame = Class(TFrame)
    Panel: TPanel;
    SkillLabel: TLabel;
    LeftLabel: TLabel;
    CentreHost: TPanel;
    ModelLabel: TLabel;
    CentreLabel: TLabel;
    RightLabel: TLabel;
    Procedure LabelClick(Sender: TObject);
    Procedure CentreHostResize(Sender: TObject);
  Private
    FOnLeftClick: TNotifyEvent;
    FOnSkillClick: TNotifyEvent;
    FOnCentreClick: TNotifyEvent;
    FOnRightClick: TNotifyEvent;
    Procedure SetOnLeftClick(Value: TNotifyEvent);
    Procedure SetOnSkillClick(Value: TNotifyEvent);
    Procedure SetOnCentreClick(Value: TNotifyEvent);
    Procedure SetOnRightClick(Value: TNotifyEvent);
    Procedure ApplyClickStyle(ALabel: TLabel; Clickable: Boolean);
    Procedure ConfigureLabel(ALabel: TLabel);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetLeftText(Const Value: String);
    Procedure SetSkillText(Const Value: String);
    Procedure SetModelText(Const Value: String);
    Procedure SetCentreText(Const Value: String);
    Procedure SetRightText(Const Value: String);
    Procedure SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
    Procedure SetLeftHint(Const Value: String);
    Procedure SetSkillHint(Const Value: String);
    Procedure SetModelHint(Const Value: String);
    Procedure SetCentreHint(Const Value: String);
    Procedure SetRightHint(Const Value: String);
    Procedure LayoutCentrePair;
    Property LeftText: String Write SetLeftText;
    Property SkillText: String Write SetSkillText;
    Property CentreText: String Write SetCentreText;
    Property RightText: String Write SetRightText;
    Property OnLeftClick: TNotifyEvent Read FOnLeftClick Write SetOnLeftClick;
    Property OnSkillClick: TNotifyEvent Read FOnSkillClick Write SetOnSkillClick;
    Property OnCentreClick: TNotifyEvent Read FOnCentreClick Write SetOnCentreClick;
    Property OnRightClick: TNotifyEvent Read FOnRightClick Write SetOnRightClick;
  End;

Implementation

{$R *.lfm}

Procedure TStatusFooterFrame.ApplyClickStyle(ALabel: TLabel; Clickable: Boolean);
Begin
  If Not Assigned(ALabel) Then
    Exit;
  If Clickable Then
    Begin
      ALabel.Cursor := crHandPoint;
      ALabel.Font.Color := clHighlight;
    End
  Else
    Begin
      ALabel.Cursor := crDefault;
      ALabel.Font.Color := clWindowText;
    End;
End;

Procedure TStatusFooterFrame.ConfigureLabel(ALabel: TLabel);
Begin
  If Not Assigned(ALabel) Then
    Exit;
  ALabel.ParentFont := False;
  ALabel.ShowHint := True;
  ALabel.OnClick := @LabelClick;
End;

Constructor TStatusFooterFrame.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alBottom;
  Height := Scale96ToForm(22);
  ConfigureLabel(LeftLabel);
  ConfigureLabel(SkillLabel);
  ConfigureLabel(ModelLabel);
  ConfigureLabel(CentreLabel);
  ConfigureLabel(RightLabel);
  If Assigned(LeftLabel) Then
    Begin
      LeftLabel.Cursor := crDefault;
      LeftLabel.Font.Color := clWindowText;
      LeftLabel.OnClick := Nil;
    End;
  If Assigned(SkillLabel) Then
    SkillLabel.Visible := False;
End;

Procedure TStatusFooterFrame.SetOnLeftClick(Value: TNotifyEvent);
Begin
  { The model line is centred on the footer. LeftLabel is optional side text. }
  FOnLeftClick := Value;
  ApplyClickStyle(ModelLabel, Assigned(Value));
  If Assigned(LeftLabel) Then
    Begin
      LeftLabel.Cursor := crDefault;
      LeftLabel.OnClick := Nil;
    End;
End;

Procedure TStatusFooterFrame.SetOnSkillClick(Value: TNotifyEvent);
Begin
  FOnSkillClick := Value;
  ApplyClickStyle(SkillLabel, Assigned(Value));
End;

Procedure TStatusFooterFrame.SetOnCentreClick(Value: TNotifyEvent);
Begin
  FOnCentreClick := Value;
  ApplyClickStyle(CentreLabel, Assigned(Value));
End;

Procedure TStatusFooterFrame.SetOnRightClick(Value: TNotifyEvent);
Begin
  FOnRightClick := Value;
  ApplyClickStyle(RightLabel, Assigned(Value));
End;

Procedure TStatusFooterFrame.LabelClick(Sender: TObject);
Begin
  If (Sender = ModelLabel) Or (Sender = LeftLabel) Then
    Begin
      If Assigned(FOnLeftClick) And (Sender = ModelLabel) Then
        FOnLeftClick(Sender);
    End
  Else If Sender = SkillLabel Then
    Begin
      If Assigned(FOnSkillClick) Then
        FOnSkillClick(Sender);
    End
  Else If Sender = CentreLabel Then
    Begin
      If Assigned(FOnCentreClick) Then
        FOnCentreClick(Sender);
    End
  Else If Sender = RightLabel Then
    Begin
      If Assigned(FOnRightClick) Then
        FOnRightClick(Sender);
    End;
End;

Procedure TStatusFooterFrame.SetLeftText(Const Value: String);
Begin
  If Assigned(LeftLabel) Then
    Begin
      LeftLabel.AutoSize := True;
      LeftLabel.Caption := Value;
      If Trim(Value) = '' Then
        Begin
          LeftLabel.Visible := False;
          LeftLabel.Align := alNone;
          LeftLabel.Width := 0;
        End
      Else
        Begin
          LeftLabel.Align := alLeft;
          LeftLabel.Visible := True;
        End;
    End;
  If Assigned(Panel) Then
    Panel.Realign;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.LayoutCentrePair;
Var
  Gap, Origin, ModelTop, CentreTop, MinOrigin, MaxOrigin: Integer;
Begin
  If Not Assigned(CentreHost) Or Not Assigned(ModelLabel) Or Not Assigned(CentreLabel) Then
    Exit;
  ModelLabel.AutoSize := True;
  CentreLabel.AutoSize := True;
  Gap := Scale96ToForm(16);
  { Centre the model line on the whole footer. Context stays to its right and must not pull that line off centre. }
  If Assigned(Panel) And (Panel.ClientWidth > 0) Then
    Origin := ((Panel.ClientWidth - ModelLabel.Width) Div 2) - CentreHost.Left
  Else
    Origin := (CentreHost.ClientWidth - ModelLabel.Width) Div 2;
  MinOrigin := 0;
  MaxOrigin := CentreHost.ClientWidth - ModelLabel.Width - Gap - CentreLabel.Width;
  If MaxOrigin < MinOrigin Then
    MaxOrigin := MinOrigin;
  If Origin < MinOrigin Then
    Origin := MinOrigin;
  If Origin > MaxOrigin Then
    Origin := MaxOrigin;
  ModelTop := (CentreHost.ClientHeight - ModelLabel.Height) Div 2;
  If ModelTop < 0 Then
    ModelTop := 0;
  CentreTop := (CentreHost.ClientHeight - CentreLabel.Height) Div 2;
  If CentreTop < 0 Then
    CentreTop := 0;
  ModelLabel.SetBounds(Origin, ModelTop, ModelLabel.Width, ModelLabel.Height);
  CentreLabel.SetBounds(Origin + ModelLabel.Width + Gap, CentreTop, CentreLabel.Width, CentreLabel.Height);
End;

Procedure TStatusFooterFrame.CentreHostResize(Sender: TObject);
Begin
  If Sender = CentreHost Then
    LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetSkillText(Const Value: String);
Begin
  If Not Assigned(SkillLabel) Then
    Exit;
  SkillLabel.AutoSize := True;
  SkillLabel.Caption := Value;
  SkillLabel.Visible := Trim(Value) <> '';
  If Assigned(Panel) Then
    Panel.Realign;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetModelText(Const Value: String);
Begin
  If Assigned(ModelLabel) Then
    Begin
      ModelLabel.AutoSize := True;
      ModelLabel.Caption := Value;
    End;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetCentreText(Const Value: String);
Begin
  If Assigned(CentreLabel) Then
    Begin
      CentreLabel.AutoSize := True;
      CentreLabel.Caption := Value;
    End;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetRightText(Const Value: String);
Begin
  If Assigned(RightLabel) Then
    Begin
      RightLabel.AutoSize := True;
      RightLabel.Caption := Value;
    End;
  If Assigned(Panel) Then
    Panel.Realign;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
Begin
  SetLeftText(NewLeftText);
  SetCentreText(NewCentreText);
  SetRightText(NewRightText);
End;

Procedure TStatusFooterFrame.SetLeftHint(Const Value: String);
Begin
  If Assigned(LeftLabel) Then
    LeftLabel.Hint := Value;
End;

Procedure TStatusFooterFrame.SetSkillHint(Const Value: String);
Begin
  If Assigned(SkillLabel) Then
    SkillLabel.Hint := Value;
End;

Procedure TStatusFooterFrame.SetModelHint(Const Value: String);
Begin
  If Assigned(ModelLabel) Then
    ModelLabel.Hint := Value;
End;

Procedure TStatusFooterFrame.SetCentreHint(Const Value: String);
Begin
  If Assigned(CentreLabel) Then
    CentreLabel.Hint := Value;
End;

Procedure TStatusFooterFrame.SetRightHint(Const Value: String);
Begin
  If Assigned(RightLabel) Then
    RightLabel.Hint := Value;
End;

Initialization

RegisterClass(TStatusFooterFrame);

End.
