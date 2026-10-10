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
    LayingOutCentre, UpdatingMetrics: Boolean;
    Procedure UpdateMiddleHint(LabelControl: TLabel; Const HintText: String);
    Procedure SetOnLeftClick(Value: TNotifyEvent);
    Procedure SetOnSkillClick(Value: TNotifyEvent);
    Procedure SetOnCentreClick(Value: TNotifyEvent);
    Procedure SetOnRightClick(Value: TNotifyEvent);
    Procedure ApplyClickStyle(LabelControl: TLabel; Clickable: Boolean);
    Procedure UpdateFontMetrics;
  Protected
    Procedure CreateWnd; Override;
    Procedure Loaded; Override;
    Procedure FontChanged(Sender: TObject); Override;
    Procedure ChangeScale(Multiplier, Divider: Integer); Override;
  Public
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

Procedure TStatusFooterFrame.ApplyClickStyle(LabelControl: TLabel; Clickable: Boolean);
Begin
  If Not Assigned(LabelControl) Then
    Exit;
  { Styling creates a local font. Refresh it from the inherited frame font whenever
    font metrics change, so links keep the host's family, size and scaling. }
  LabelControl.Font.Assign(Font);
  { Use the theme's foreground for the clForm surface. Underlining distinguishes
    links without using a selection-background colour as text on dark themes. }
  LabelControl.Font.Color := clBtnText;
  If Clickable Then
    Begin
      LabelControl.Cursor := crHandPoint;
      LabelControl.Font.Style := LabelControl.Font.Style + [fsUnderline];
    End
  Else
    LabelControl.Cursor := crDefault;
End;

Procedure TStatusFooterFrame.UpdateFontMetrics;
Var
  Labels: Array[0..5] Of TLabel;
  Index, TextHeight, FooterHeight: Integer;
Begin
  If UpdatingMetrics Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Or
    Not HandleAllocated Or Not Assigned(Panel) Or Not Assigned(RightLabel) Then
    Exit;
  UpdatingMetrics := True;
  Try
    ApplyClickStyle(LeftLabel, False);
    ApplyClickStyle(SkillLabel, Assigned(FOnSkillClick));
    ApplyClickStyle(ModelLabel, Assigned(FOnLeftClick));
    ApplyClickStyle(CentreLabel, Assigned(FOnCentreClick));
    ApplyClickStyle(UsageLabel, False);
    ApplyClickStyle(RightLabel, Assigned(FOnRightClick));
    Labels[0] := LeftLabel;
    Labels[1] := SkillLabel;
    Labels[2] := ModelLabel;
    Labels[3] := CentreLabel;
    Labels[4] := UsageLabel;
    Labels[5] := RightLabel;
    FooterHeight := Scale96ToForm(22);
    For Index := Low(Labels) To High(Labels) Do
      If Assigned(Labels[Index]) Then
        Begin
          Labels[Index].Canvas.Font.Assign(Labels[Index].Font);
          TextHeight := Labels[Index].Canvas.TextHeight('Hg') + 2 * Panel.ChildSizing.TopBottomSpacing;
          If TextHeight > FooterHeight Then
            FooterHeight := TextHeight;
        End;
    { Resource spacing has already been scaled by LCL. Only the 22px floor needs
      conversion here. All labels share the same padded client-height rectangle. }
    Constraints.MinHeight := FooterHeight;
    Height := FooterHeight;
    Panel.Realign;
  Finally
    UpdatingMetrics := False;
  End;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.CreateWnd;
Begin
  Inherited CreateWnd;
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.Loaded;
Begin
  Inherited Loaded;
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.FontChanged(Sender: TObject);
Begin
  Inherited FontChanged(Sender);
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.ChangeScale(Multiplier, Divider: Integer);
Var
  WasUpdating: Boolean;
Begin
  { Wait until LCL has scaled the frame font, children and resource padding once. }
  WasUpdating := UpdatingMetrics;
  UpdatingMetrics := True;
  Try
    Inherited ChangeScale(Multiplier, Divider);
  Finally
    UpdatingMetrics := WasUpdating;
  End;
  UpdateFontMetrics;
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
  LabelWidths, EllipsisWidths: Array[0..2] Of Integer;
  Gap, GroupWidth, AvailableWidth, Origin, MaxOrigin, Index: Integer;
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
  If LayingOutCentre Or UpdatingMetrics Or Not HandleAllocated Or
    Not Assigned(CentreHost) Or Not Assigned(ModelLabel) Or Not Assigned(CentreLabel) Then
    Exit;
  LayingOutCentre := True;
  Try
    Labels[0] := ModelLabel;
    Labels[1] := CentreLabel;
    Labels[2] := UsageLabel;
    Gap := CentreHost.ChildSizing.HorizontalSpacing;
    AvailableWidth := CentreHost.ClientWidth;
    For Index := Low(Labels) To High(Labels) Do
      Begin
        LabelWidths[Index] := 0;
        EllipsisWidths[Index] := 0;
        If Not Assigned(Labels[Index]) Then
          Continue;
        Labels[Index].Canvas.Font.Assign(Labels[Index].Font);
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
        Labels[Index].SetBounds(Origin, 0, LabelWidths[Index], CentreHost.ClientHeight);
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
  UsageLabel.Font.Color := clBtnText;
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
      RightLabel.Visible := Trim(Value) <> '';
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
