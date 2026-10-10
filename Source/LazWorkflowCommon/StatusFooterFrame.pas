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
    UsageLabel: TLabel;
    RightLabel: TLabel;
    Procedure LabelClick(Sender: TObject);
    Procedure CentreHostResize(Sender: TObject);
  Private
    FOnLeftClick: TNotifyEvent;
    FOnSkillClick: TNotifyEvent;
    FOnCentreClick: TNotifyEvent;
    FOnRightClick: TNotifyEvent;
    ModelHintText, CentreHintText, UsageHintText: String;
    LayingOutCentre: Boolean;
    Procedure UpdateMiddleHint(LabelControl: TLabel; Const HintText: String);
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
    Procedure SetUsageText(Const Value: String);
    Procedure SetRightText(Const Value: String);
    Procedure SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
    Procedure SetLeftHint(Const Value: String);
    Procedure SetSkillHint(Const Value: String);
    Procedure SetModelHint(Const Value: String);
    Procedure SetCentreHint(Const Value: String);
    Procedure SetUsageHint(Const Value: String);
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
  ConfigureLabel(UsageLabel);
  ConfigureLabel(RightLabel);
  If Assigned(LeftLabel) Then
    Begin
      LeftLabel.Cursor := crDefault;
      LeftLabel.Font.Color := clWindowText;
      LeftLabel.OnClick := Nil;
    End;
  If Assigned(SkillLabel) Then
    SkillLabel.Visible := False;
  { Hover only. An empty caption must not reserve space on forms that share this frame. }
  If Assigned(UsageLabel) Then
    Begin
      UsageLabel.Cursor := crDefault;
      UsageLabel.Font.Color := clWindowText;
      UsageLabel.OnClick := Nil;
      UsageLabel.Visible := False;
      UsageLabel.Width := 0;
    End;
End;

Procedure TStatusFooterFrame.SetOnLeftClick(Value: TNotifyEvent);
Begin
  { The model leads the centred group. LeftLabel is optional side text. }
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

Procedure TStatusFooterFrame.UpdateMiddleHint(LabelControl: TLabel; Const HintText: String);
Begin
  If Not Assigned(LabelControl) Then
    Exit;
  LabelControl.Hint := HintText;
  LabelControl.Canvas.Font.Assign(LabelControl.Font);
  If LabelControl.Visible And (Trim(LabelControl.Caption) <> '') And
    (LabelControl.Canvas.TextWidth(LabelControl.Caption) > LabelControl.Width) And (Pos(LabelControl.Caption, HintText) = 0) Then
    Begin
      LabelControl.Hint := LabelControl.Caption;
      If HintText <> '' Then
        LabelControl.Hint := LabelControl.Hint + LineEnding + HintText;
    End;
End;

Procedure TStatusFooterFrame.LayoutCentrePair;
Var
  Labels: Array[0..2] Of TLabel;
  LabelWidths, LabelHeights, EllipsisWidths: Array[0..2] Of Integer;
  Gap, GroupWidth, AvailableWidth, Origin, MaxOrigin, Index, LabelTop: Integer;
  HasPrevious: Boolean;

  Procedure MeasureGroup;
  Var
    ItemIndex: Integer;
    HasItem: Boolean;
  Begin
    GroupWidth := 0;
    HasItem := False;
    For ItemIndex := Low(Labels) To High(Labels) Do
      If LabelWidths[ItemIndex] > 0 Then
        Begin
          If HasItem Then
            Inc(GroupWidth, Gap);
          Inc(GroupWidth, LabelWidths[ItemIndex]);
          HasItem := True;
        End;
  End;

  Procedure ShortenLabel(ItemIndex: Integer);
  Begin
    If (GroupWidth <= AvailableWidth) Or (LabelWidths[ItemIndex] = 0) Then
      Exit;
    Dec(LabelWidths[ItemIndex], GroupWidth - AvailableWidth);
    { If even an ellipsis cannot fit, remove this item and its gap from the row. }
    If LabelWidths[ItemIndex] < EllipsisWidths[ItemIndex] Then
      LabelWidths[ItemIndex] := 0;
    MeasureGroup;
  End;

Begin
  If LayingOutCentre Or Not Assigned(CentreHost) Or Not Assigned(ModelLabel) Or Not Assigned(CentreLabel) Then
    Exit;
  LayingOutCentre := True;
  Try
    Labels[0] := ModelLabel;
    Labels[1] := CentreLabel;
    Labels[2] := UsageLabel;
    Gap := Scale96ToForm(16);
    AvailableWidth := CentreHost.ClientWidth;
    For Index := Low(Labels) To High(Labels) Do
      Begin
        LabelWidths[Index] := 0;
        LabelHeights[Index] := 0;
        EllipsisWidths[Index] := 0;
        If Not Assigned(Labels[Index]) Then
          Continue;
        Labels[Index].Canvas.Font.Assign(Labels[Index].Font);
        LabelHeights[Index] := Labels[Index].Canvas.TextHeight('Hg');
        If LabelHeights[Index] > CentreHost.ClientHeight Then
          LabelHeights[Index] := CentreHost.ClientHeight;
        If Labels[Index].Visible And (Trim(Labels[Index].Caption) <> '') Then
          Begin
            LabelWidths[Index] := Labels[Index].Canvas.TextWidth(Labels[Index].Caption);
            EllipsisWidths[Index] := Labels[Index].Canvas.TextWidth('…');
          End;
      End;
    MeasureGroup;
    { Preserve context/allowance where possible: shorten model, then optional usage, then context.
      LCL paints the end ellipsis without changing Caption, so wider layouts restore the original text. }
    ShortenLabel(0);
    ShortenLabel(2);
    ShortenLabel(1);
    If Assigned(Panel) And (Panel.ClientWidth > 0) Then
      Origin := ((Panel.ClientWidth - GroupWidth) Div 2) - CentreHost.Left
    Else
      Origin := (AvailableWidth - GroupWidth) Div 2;
    MaxOrigin := AvailableWidth - GroupWidth;
    If Origin < 0 Then
      Origin := 0;
    If Origin > MaxOrigin Then
      Origin := MaxOrigin;
    HasPrevious := False;
    For Index := Low(Labels) To High(Labels) Do
      Begin
        If Not Assigned(Labels[Index]) Then
          Continue;
        If (LabelWidths[Index] > 0) And HasPrevious Then
          Inc(Origin, Gap);
        LabelTop := (CentreHost.ClientHeight - LabelHeights[Index]) Div 2;
        Labels[Index].SetBounds(Origin, LabelTop, LabelWidths[Index], LabelHeights[Index]);
        If LabelWidths[Index] > 0 Then
          Begin
            Inc(Origin, LabelWidths[Index]);
            HasPrevious := True;
          End;
      End;
    UpdateMiddleHint(ModelLabel, ModelHintText);
    UpdateMiddleHint(CentreLabel, CentreHintText);
    UpdateMiddleHint(UsageLabel, UsageHintText);
  Finally
    LayingOutCentre := False;
  End;
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
    ModelLabel.Caption := Value;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetCentreText(Const Value: String);
Begin
  If Assigned(CentreLabel) Then
    CentreLabel.Caption := Value;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetUsageText(Const Value: String);
Begin
  If Not Assigned(UsageLabel) Then
    Exit;
  UsageLabel.Caption := Value;
  UsageLabel.Cursor := crDefault;
  UsageLabel.Font.Color := clWindowText;
  UsageLabel.OnClick := Nil;
  If Trim(Value) = '' Then
    Begin
      UsageLabel.Visible := False;
      UsageLabel.Width := 0;
    End
  Else
    UsageLabel.Visible := True;
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
  ModelHintText := Value;
  UpdateMiddleHint(ModelLabel, ModelHintText);
End;

Procedure TStatusFooterFrame.SetCentreHint(Const Value: String);
Begin
  CentreHintText := Value;
  UpdateMiddleHint(CentreLabel, CentreHintText);
End;

Procedure TStatusFooterFrame.SetUsageHint(Const Value: String);
Begin
  UsageHintText := Value;
  UpdateMiddleHint(UsageLabel, UsageHintText);
End;

Procedure TStatusFooterFrame.SetRightHint(Const Value: String);
Begin
  If Assigned(RightLabel) Then
    RightLabel.Hint := Value;
End;

Initialization

RegisterClass(TStatusFooterFrame);

End.
