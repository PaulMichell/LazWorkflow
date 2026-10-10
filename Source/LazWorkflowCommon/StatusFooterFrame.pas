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
  TFooterItem = (fiLeft, fiSkill, fiModel, fiCentre, fiUsage, fiRight);
  TFooterItemState = Record
    FullText, HintText, SingleLineText: String;
    NaturalWidth, EllipsisWidth, AllocatedWidth, DisplayWidth: Integer;
  End;

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
    Items: Array[TFooterItem] Of TFooterItemState;
    ActivityPhase: String;
    ActivityWidth: Integer;
    LayingOutCentre, UpdatingMetrics: Boolean;
    Function ItemLabel(Item: TFooterItem): TLabel;
    Procedure MeasureItem(Item: TFooterItem);
    Procedure MeasureActivity;
    Function RightGroupWidth: Integer;
    Procedure FitItem(Item: TFooterItem; AvailableWidth: Integer);
    Procedure UpdateItemHint(Item: TFooterItem);
    Procedure SetItemHint(Item: TFooterItem; Const Value: String);
    Procedure SetItemText(Item: TFooterItem; Const Value: String);
    Procedure UpdateRightText(Const Value, Phase: String);
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
    /// Reserve stable timer space for a phase; SetRightText releases the reservation.
    Procedure SetRightActivityText(Const Value, Phase: String);
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

Uses
  Math, LazUTF8;

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
  Item: TFooterItem;
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
    For Item := Low(TFooterItem) To High(TFooterItem) Do
      MeasureItem(Item);
    MeasureActivity;
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
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.SetOnSkillClick(Value: TNotifyEvent);
Begin
  FOnSkillClick := Value;
  ApplyClickStyle(SkillLabel, Assigned(Value));
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.SetOnCentreClick(Value: TNotifyEvent);
Begin
  FOnCentreClick := Value;
  ApplyClickStyle(CentreLabel, Assigned(Value));
  UpdateFontMetrics;
End;

Procedure TStatusFooterFrame.SetOnRightClick(Value: TNotifyEvent);
Begin
  FOnRightClick := Value;
  ApplyClickStyle(RightLabel, Assigned(Value));
  UpdateFontMetrics;
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

Function TStatusFooterFrame.ItemLabel(Item: TFooterItem): TLabel;
Begin
  Case Item Of
    fiLeft: Result := LeftLabel;
    fiSkill: Result := SkillLabel;
    fiModel: Result := ModelLabel;
    fiCentre: Result := CentreLabel;
    fiUsage: Result := UsageLabel;
  Else
    Result := RightLabel;
  End;
End;

Procedure TStatusFooterFrame.MeasureItem(Item: TFooterItem);
Var
  LabelControl: TLabel;
Begin
  LabelControl := ItemLabel(Item);
  If Not Assigned(LabelControl) Then
    Exit;
  With Items[Item] Do
    Begin
      SingleLineText := StringReplace(FullText, #13#10, ' ', [rfReplaceAll]);
      SingleLineText := StringReplace(SingleLineText, #13, ' ', [rfReplaceAll]);
      SingleLineText := StringReplace(SingleLineText, #10, ' ', [rfReplaceAll]);
      SingleLineText := StringReplace(SingleLineText, #9, ' ', [rfReplaceAll]);
      LabelControl.Canvas.Font.Assign(LabelControl.Font);
      If Trim(SingleLineText) = '' Then
        NaturalWidth := 0
      Else
        NaturalWidth := LabelControl.Canvas.TextWidth(SingleLineText);
      EllipsisWidth := LabelControl.Canvas.TextWidth('…');
    End;
End;

Procedure TStatusFooterFrame.MeasureActivity;
Var
  Digit: Char;
  DigitWidth: Integer;
Begin
  ActivityWidth := 0;
  If (ActivityPhase = '') Or Not Assigned(RightLabel) Then
    Exit;
  RightLabel.Canvas.Font.Assign(RightLabel.Font);
  DigitWidth := 0;
  For Digit := '0' To '9' Do
    DigitWidth := Max(DigitWidth, RightLabel.Canvas.TextWidth(Digit));
  { Reserve three hour/minute digits and both clock separators, using the widest
    digit in the actual font. Phase changes may move the group; normal ticks do not. }
  ActivityWidth := RightLabel.Canvas.TextWidth(ActivityPhase + ' ') +
    7 * DigitWidth + 2 * RightLabel.Canvas.TextWidth(':');
End;

Function TStatusFooterFrame.RightGroupWidth: Integer;
Var
  UsableWidth: Integer;
Begin
  Result := 0;
  If Not Assigned(Panel) Or Not Assigned(RightLabel) Or Not RightLabel.Visible Or (Items[fiRight].NaturalWidth = 0) Then
    Exit;
  UsableWidth := Max(0, Panel.ClientWidth - 2 * Panel.ChildSizing.LeftRightSpacing);
  Result := Min(UsableWidth Div 3, Max(ActivityWidth, Items[fiRight].NaturalWidth));
  If Result < Items[fiRight].EllipsisWidth Then
    Result := 0;
End;

Procedure TStatusFooterFrame.UpdateItemHint(Item: TFooterItem);
Var
  LabelControl: TLabel;
  NewHint: String;
Begin
  LabelControl := ItemLabel(Item);
  If Not Assigned(LabelControl) Then
    Exit;
  NewHint := Items[Item].HintText;
  { Keep the full value independently of the painted caption and the caller's
    explanatory hint, including when a later Set*Hint follows Set*Text. }
  If (Items[Item].FullText <> '') And (Pos(Items[Item].FullText, NewHint) = 0) Then
    Begin
      If NewHint <> '' Then
        NewHint := LineEnding + NewHint;
      NewHint := Items[Item].FullText + NewHint;
    End;
  If LabelControl.Hint <> NewHint Then
    LabelControl.Hint := NewHint;
End;

Procedure TStatusFooterFrame.SetItemHint(Item: TFooterItem; Const Value: String);
Begin
  Items[Item].HintText := Value;
  UpdateItemHint(Item);
End;

Procedure TStatusFooterFrame.FitItem(Item: TFooterItem; AvailableWidth: Integer);
Var
  LabelControl: TLabel;
  DisplayText, Candidate: String;
  LowCount, HighCount, KeepCount, CharacterCount, PrefixCount: Integer;
  MiddleEllipsis: Boolean;
Begin
  LabelControl := ItemLabel(Item);
  If Not Assigned(LabelControl) Then
    Exit;
  Items[Item].AllocatedWidth := Max(0, AvailableWidth);
  DisplayText := '';
  LabelControl.Canvas.Font.Assign(LabelControl.Font);
  If LabelControl.Visible And (Items[Item].NaturalWidth > 0) Then
    If Items[Item].NaturalWidth <= AvailableWidth Then
      DisplayText := Items[Item].SingleLineText
    Else If Items[Item].EllipsisWidth <= AvailableWidth Then
      Begin
        DisplayText := '…';
        CharacterCount := UTF8Length(Items[Item].SingleLineText);
        { These are the shared hosts' path/branch positions. Slashes in model
          names or work-message prose do not turn those items into paths. }
        MiddleEllipsis := (Item In [fiLeft, fiCentre]) And
          ((Pos('/', Items[Item].SingleLineText) > 0) Or (Pos('\', Items[Item].SingleLineText) > 0));
        LowCount := 1;
        HighCount := CharacterCount - 1;
        While LowCount <= HighCount Do
          Begin
            KeepCount := (LowCount + HighCount) Div 2;
            If MiddleEllipsis Then
              Begin
                PrefixCount := KeepCount Div 2;
                Candidate := UTF8Copy(Items[Item].SingleLineText, 1, PrefixCount) + '…' +
                  UTF8Copy(Items[Item].SingleLineText, CharacterCount - (KeepCount - PrefixCount) + 1, KeepCount - PrefixCount);
              End
            Else
              Candidate := UTF8Copy(Items[Item].SingleLineText, 1, KeepCount) + '…';
            If LabelControl.Canvas.TextWidth(Candidate) <= AvailableWidth Then
              Begin
                DisplayText := Candidate;
                LowCount := KeepCount + 1;
              End
            Else
              HighCount := KeepCount - 1;
          End;
      End;
  Items[Item].DisplayWidth := LabelControl.Canvas.TextWidth(DisplayText);
  If LabelControl.Caption <> DisplayText Then
    LabelControl.Caption := DisplayText;
  UpdateItemHint(Item);
End;

Procedure TStatusFooterFrame.SetItemText(Item: TFooterItem; Const Value: String);
Var
  LabelControl: TLabel;
  OldWidth, OldDisplayWidth: Integer;
  WasVisible: Boolean;
Begin
  LabelControl := ItemLabel(Item);
  If Not Assigned(LabelControl) Or (Items[Item].FullText = Value) Then
    Exit;
  OldWidth := Items[Item].NaturalWidth;
  OldDisplayWidth := Items[Item].DisplayWidth;
  WasVisible := LabelControl.Visible;
  Items[Item].FullText := Value;
  { Defer geometry until the complete text and visibility are consistent. }
  LayingOutCentre := True;
  Try
    LabelControl.Visible := Trim(Value) <> '';
  Finally
    LayingOutCentre := False;
  End;
  UpdateItemHint(Item);
  If Not HandleAllocated Or (csLoading In ComponentState) Then
    Exit;
  MeasureItem(Item);
  If (OldWidth = Items[Item].NaturalWidth) And (WasVisible = LabelControl.Visible) Then
    Begin
      FitItem(Item, Items[Item].AllocatedWidth);
      If OldDisplayWidth = Items[Item].DisplayWidth Then
        Exit;
    End;
  LayoutCentrePair;
End;

Procedure TStatusFooterFrame.UpdateRightText(Const Value, Phase: String);
Var
  PreviousWidth, PreviousDisplayWidth: Integer;
  PhaseChanged: Boolean;
Begin
  If Not Assigned(RightLabel) Then
    Exit;
  PhaseChanged := ActivityPhase <> Phase;
  If (Items[fiRight].FullText = Value) And Not PhaseChanged Then
    Exit;
  PreviousWidth := RightGroupWidth;
  PreviousDisplayWidth := Items[fiRight].DisplayWidth;
  ActivityPhase := Phase;
  Items[fiRight].FullText := Value;
  LayingOutCentre := True;
  Try
    RightLabel.Visible := Trim(Value) <> '';
  Finally
    LayingOutCentre := False;
  End;
  UpdateItemHint(fiRight);
  If Not HandleAllocated Or (csLoading In ComponentState) Then
    Exit;
  MeasureItem(fiRight);
  If PhaseChanged Then
    MeasureActivity;
  If (PreviousWidth <> RightGroupWidth) Or PhaseChanged Then
    LayoutCentrePair
  Else
    Begin
      { The reservation did not change. Only repaint and right-align this item;
        the middle group's geometry is untouched by ordinary elapsed ticks. }
      FitItem(fiRight, RightGroupWidth);
      If (ActivityPhase = '') And (PreviousDisplayWidth <> Items[fiRight].DisplayWidth) Then
        Begin
          LayoutCentrePair;
          Exit;
        End;
      RightLabel.SetBounds(Panel.ClientWidth - Panel.ChildSizing.LeftRightSpacing - Items[fiRight].DisplayWidth,
        Panel.ChildSizing.TopBottomSpacing, Items[fiRight].DisplayWidth, CentreHost.Height);
    End;
End;

Procedure TStatusFooterFrame.SetLeftText(Const Value: String);
Begin
  SetItemText(fiLeft, Value);
End;

Procedure TStatusFooterFrame.LayoutCentrePair;
Var
  Widths: Array[TFooterItem] Of Integer;
  Item: TFooterItem;
  Gap, GroupWidth, AvailableWidth, Origin, RowTop, RowHeight: Integer;
  OuterLeft, OuterRight, UsableWidth, LeftLimit, LeftWidth, RightWidth, Remaining: Integer;
  CentreStart, CentreEnd: Integer;
  HasPrevious: Boolean;

  Function MeasureGroup(FirstItem, LastItem: TFooterItem): Integer;
  Var
    GroupItem: TFooterItem;
  Begin
    Result := 0;
    For GroupItem := FirstItem To LastItem Do
      If Widths[GroupItem] > 0 Then
        Begin
          If Result > 0 Then
            Inc(Result, Gap);
          Inc(Result, Widths[GroupItem]);
        End;
  End;

  Procedure ShortenMiddle(ShortItem: TFooterItem);
  Begin
    If (GroupWidth <= AvailableWidth) Or (Widths[ShortItem] = 0) Then
      Exit;
    Widths[ShortItem] := Max(Min(Widths[ShortItem], Items[ShortItem].EllipsisWidth),
      Widths[ShortItem] - (GroupWidth - AvailableWidth));
    GroupWidth := MeasureGroup(fiModel, fiUsage);
  End;

  Procedure OmitMiddle(OmitItem: TFooterItem);
  Begin
    If GroupWidth <= AvailableWidth Then
      Exit;
    Widths[OmitItem] := 0;
    GroupWidth := MeasureGroup(fiModel, fiUsage);
  End;

Begin
  If LayingOutCentre Or UpdatingMetrics Or Not HandleAllocated Or (csLoading In ComponentState) Or
    (csDestroying In ComponentState) Or Not Assigned(Panel) Or Not Assigned(CentreHost) Or Not Assigned(RightLabel) Then
    Exit;
  LayingOutCentre := True;
  Try
    Gap := Panel.ChildSizing.HorizontalSpacing;
    OuterLeft := Min(Panel.ChildSizing.LeftRightSpacing, Panel.ClientWidth Div 2);
    OuterRight := Panel.ClientWidth - OuterLeft;
    UsableWidth := Max(0, OuterRight - OuterLeft);
    RowTop := Panel.ChildSizing.TopBottomSpacing;
    RowHeight := Max(0, Panel.ClientHeight - 2 * RowTop);
    For Item := Low(TFooterItem) To High(TFooterItem) Do
      If Assigned(ItemLabel(Item)) And ItemLabel(Item).Visible Then
        Widths[Item] := Items[Item].NaturalWidth
      Else
        Widths[Item] := 0;

    { A short side group uses only its content width. If both left items are
      long, share the cap while returning any unused share to its neighbour. }
    LeftLimit := UsableWidth Div 4;
    If MeasureGroup(fiLeft, fiSkill) > LeftLimit Then
      Begin
        If (Widths[fiLeft] > 0) And (Widths[fiSkill] > 0) Then
          Begin
            Remaining := Max(0, LeftLimit - Gap);
            Widths[fiLeft] := Min(Widths[fiLeft], Remaining Div 2);
            Widths[fiSkill] := Min(Widths[fiSkill], Remaining - Widths[fiLeft]);
            Widths[fiLeft] := Min(Items[fiLeft].NaturalWidth, Remaining - Widths[fiSkill]);
          End
        Else
          Begin
            Widths[fiLeft] := Min(Widths[fiLeft], LeftLimit);
            Widths[fiSkill] := Min(Widths[fiSkill], LeftLimit);
          End;
      End;
    For Item := fiLeft To fiSkill Do
      Begin
        FitItem(Item, Widths[Item]);
        Widths[Item] := Items[Item].DisplayWidth;
      End;
    LeftWidth := MeasureGroup(fiLeft, fiSkill);
    RightWidth := RightGroupWidth;
    FitItem(fiRight, RightWidth);
    If ActivityPhase = '' Then
      RightWidth := Items[fiRight].DisplayWidth;

    CentreStart := OuterLeft + LeftWidth;
    CentreEnd := OuterRight - RightWidth;
    If LeftWidth > 0 Then
      Inc(CentreStart, Min(Gap, Max(0, CentreEnd - CentreStart)));
    If RightWidth > 0 Then
      Dec(CentreEnd, Min(Gap, Max(0, CentreEnd - CentreStart)));
    AvailableWidth := Max(0, CentreEnd - CentreStart);
    CentreHost.SetBounds(CentreStart, RowTop, AvailableWidth, RowHeight);

    Origin := OuterLeft;
    HasPrevious := False;
    { Explicit display order avoids depending on the alLeft stacking order. }
    For Item := fiLeft To fiSkill Do
      Begin
        If (Widths[Item] > 0) And HasPrevious Then
          Inc(Origin, Gap);
        ItemLabel(Item).SetBounds(Origin, RowTop, Widths[Item], RowHeight);
        If Widths[Item] > 0 Then
          Begin
            Inc(Origin, Widths[Item]);
            HasPrevious := True;
          End;
      End;
    RightLabel.SetBounds(OuterRight - Items[fiRight].DisplayWidth, RowTop, Items[fiRight].DisplayWidth, RowHeight);

    GroupWidth := MeasureGroup(fiModel, fiUsage);
    { Preserve context/allowance first. Fitting produces the actual painted
      text before centring, so ellipsis slack never skews the midpoint. }
    ShortenMiddle(fiModel);
    ShortenMiddle(fiUsage);
    ShortenMiddle(fiCentre);
    { Only omit an item when even the ellipses and their gaps cannot fit. }
    OmitMiddle(fiModel);
    OmitMiddle(fiUsage);
    OmitMiddle(fiCentre);
    For Item := fiModel To fiUsage Do
      Begin
        FitItem(Item, Widths[Item]);
        Widths[Item] := Items[Item].DisplayWidth;
      End;
    GroupWidth := MeasureGroup(fiModel, fiUsage);
    Origin := ((Panel.ClientWidth - GroupWidth) Div 2) - CentreHost.Left;
    Origin := Max(0, Min(Origin, AvailableWidth - GroupWidth));
    HasPrevious := False;
    For Item := fiModel To fiUsage Do
      Begin
        If (Widths[Item] > 0) And HasPrevious Then
          Inc(Origin, Gap);
        ItemLabel(Item).SetBounds(Origin, 0, Widths[Item], RowHeight);
        If Widths[Item] > 0 Then
          Begin
            Inc(Origin, Widths[Item]);
            HasPrevious := True;
          End;
      End;
  Finally
    LayingOutCentre := False;
  End;
End;

Procedure TStatusFooterFrame.CentreHostResize(Sender: TObject);
Begin
  If (Sender = CentreHost) Or (Sender = Panel) Then
    LayoutCentrePair;
End;

Procedure TStatusFooterFrame.SetSkillText(Const Value: String);
Begin
  SetItemText(fiSkill, Value);
End;

Procedure TStatusFooterFrame.SetModelText(Const Value: String);
Begin
  SetItemText(fiModel, Value);
End;

Procedure TStatusFooterFrame.SetCentreText(Const Value: String);
Begin
  SetItemText(fiCentre, Value);
End;

Procedure TStatusFooterFrame.SetUsageText(Const Value: String);
Begin
  SetItemText(fiUsage, Value);
End;

Procedure TStatusFooterFrame.SetRightText(Const Value: String);
Begin
  UpdateRightText(Value, '');
End;

Procedure TStatusFooterFrame.SetRightActivityText(Const Value, Phase: String);
Begin
  UpdateRightText(Value, Phase);
End;

Procedure TStatusFooterFrame.SetAll(Const NewLeftText, NewCentreText, NewRightText: String);
Begin
  SetLeftText(NewLeftText);
  SetCentreText(NewCentreText);
  SetRightText(NewRightText);
End;

Procedure TStatusFooterFrame.SetLeftHint(Const Value: String);
Begin
  SetItemHint(fiLeft, Value);
End;

Procedure TStatusFooterFrame.SetSkillHint(Const Value: String);
Begin
  SetItemHint(fiSkill, Value);
End;

Procedure TStatusFooterFrame.SetModelHint(Const Value: String);
Begin
  SetItemHint(fiModel, Value);
End;

Procedure TStatusFooterFrame.SetCentreHint(Const Value: String);
Begin
  SetItemHint(fiCentre, Value);
End;

Procedure TStatusFooterFrame.SetUsageHint(Const Value: String);
Begin
  SetItemHint(fiUsage, Value);
End;

Procedure TStatusFooterFrame.SetRightHint(Const Value: String);
Begin
  SetItemHint(fiRight, Value);
End;

Initialization

RegisterClass(TStatusFooterFrame);

End.
