Unit AssistantTraceView;

{ Scrollable current-turn trace: user, thinking, tools, answer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Menus, AssistantTrace;

Type
  TAssistantTraceView = Class(TFrame)
    TraceScroll: TScrollBox;
    TraceHost: TPanel;
    EmptyLabel: TLabel;
  Private
    FShowThinking: Boolean;
    FTruncatedLines: Integer;
    FBoundTrace: TAssistantTrace;
    FCopyPopup: TPopupMenu;
    FLastContentWidth: Integer;
    FRelayouting: Boolean;
    Procedure SetShowThinking(Value: Boolean);
    Function LineHeightPx: Integer;
    Procedure ApplyVerticalStack(Host: TWinControl; Inner: Boolean);
    Procedure InitHostedPanel(Panel: TPanel; AutoSizePanel: Boolean; FixedHeight: Integer);
    Procedure FinishHostedPanel(Panel: TPanel; AutoSizePanel: Boolean);
    Function NamedChild(Host: TWinControl; Const ChildName: String): TControl;
    Function EnsureFooterLabel(Panel: TPanel): TLabel;
    Function OrderFrames(Trace: TAssistantTrace): Integer;
    Procedure EnsureFrame(Block: TTraceBlock);
    Procedure BindThinking(Block: TTraceBlock);
    Procedure BindTool(Block: TTraceBlock);
    Procedure BindSubagent(Block: TTraceBlock);
    Procedure BindAnswer(Block: TTraceBlock);
    Procedure BindRichCard(Block: TTraceBlock; Const TitleColor: TColor);
    Procedure BindUser(Block: TTraceBlock);
    Procedure SplitTrailingMdFooter(Const SourceText: String; Out BodyText, FooterText: String);
    Procedure EnsureCopyPopup;
    Procedure CopyPopupPopup(Sender: TObject);
    Procedure CopyItemClick(Sender: TObject);
    Procedure SelectAllItemClick(Sender: TObject);
    Function MakeSelectableMemo(Host: TWinControl; Const ChildName: String; Italic, Gray: Boolean): TMemo;
    Function MakeFooterLabel(Host: TWinControl): TLabel;
    Procedure BindBlockFooter(Panel: TPanel; Const FooterText: String);
    Procedure BindSelectableMemo(Memo: TMemo; Const SourceText: String);
    Function ContentWidth: Integer;
    Function WrappedTextHeight(Const TypeFace: TFont; Const SourceText: String; MaxWidth: Integer): Integer;
    Function LastLines(Const SourceText: String; MaxLines: Integer; MaxChars: Integer = 0): String;
    Procedure ScrollToEnd;
    Function HostedContentHeight: Integer;
    Function ScrollHandleReady: Boolean;
    Procedure SetVertScrollPos(NewPos: Integer);
    Procedure ApplyScrollRange(ForceBottom: Boolean);
    Procedure FitHostToContent;
    Procedure RelayoutIfWidthChanged;
    Procedure LockControlHeight(Control: TControl; NewHeight: Integer);
    Procedure LockControlWidth(Control: TControl; NewWidth: Integer);
    Function ViewportWidth: Integer;
    Procedure ApplyHostWidth;
  Protected
    Procedure Resize; Override;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure ResetFrames;
    Procedure Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
    Procedure ScrollToStart;
    Procedure RefreshElapsed(Trace: TAssistantTrace);
    Property ShowThinking: Boolean Read FShowThinking Write SetShowThinking;
  End;

Implementation

{$R *.lfm}

Uses
  Clipbrd, LCLIntf, LCLType, MarkDown.Control, AssistantSubagents;

Const
  HeaderHeight = 26;
  ToolHeight = 30;
  TruncatedLineCount = 24;
  CardInnerPad = 8;
  { GTK SendMoveSizeMessages uses a signed 16-bit Top/Left. Stay below 32767. }
  MaxSafeWidgetCoord = 30000;
  { Tall answers scroll inside the card instead of stretching the host. }
  MaxMarkdownCardHeight = 4000;

Function ClampWidgetCoordValue(Value: Integer): Integer;
Begin
  If Value < 0 Then
    Result := 0
  Else If Value > MaxSafeWidgetCoord Then
    Result := MaxSafeWidgetCoord
  Else
    Result := Value;
End;

Function EstimateWrappedHeight(Const TypeFace: TFont; Const SourceText: String; MaxWidth, MinLineH: Integer): Integer;
Var
  Bmp: TBitmap;
  R: TRect;
Begin
  Result := MinLineH;
  If (SourceText = '') Or (MaxWidth < 8) Then
    Exit;
  Bmp := TBitmap.Create;
  Try
    Bmp.SetSize(1, 1);
    Bmp.Canvas.Font.Assign(TypeFace);
    R := Rect(0, 0, MaxWidth, 0);
    DrawText(Bmp.Canvas.Handle, PChar(SourceText), Length(SourceText), R,
      DT_CALCRECT Or DT_WORDBREAK Or DT_NOPREFIX);
    Result := R.Bottom - R.Top + 2;
    If Result < MinLineH Then
      Result := MinLineH;
  Finally
    Bmp.Free;
  End;
End;

Procedure SizeMarkdownView(View: TMarkDownControl; Const Body: String; MaxW, MinLineH: Integer);
Var
  PrefW, PrefH, Est: Integer;
  TextChanged: Boolean;
Begin
  If Not Assigned(View) Then
    Exit;
  Try
    If MaxW < 80 Then
      MaxW := View.Width;
    TextChanged := View.MarkDown.Text <> Body;
    { Re-layout only when the body or wrap width changed. Sync walks every card
      on each live snapshot; repeating CalcLayout on a finished CoT pegs the UI.
      Recap if a previous layout exceeded the GTK coordinate limit. }
    If (Not TextChanged) And (Abs(View.Width - MaxW) < 2) And (MaxW >= 80) And
      (View.Height >= MinLineH) And (View.Height <= MaxMarkdownCardHeight) Then
      Exit;
    { Drop the previous lock first: GetPreferredSize is clamped by MaxHeight, so a
      growing answer would stay truncated at its first measured line. }
    View.Constraints.MinHeight := 0;
    View.Constraints.MaxHeight := 0;
    If View.Font.Name <> '' Then
      View.FontName := View.Font.Name;
    If View.Font.Size > 0 Then
      View.BaseFontSize := View.Font.Size;
    If TextChanged Then
      Begin
        View.MarkDown.BeginUpdate;
        Try
          View.MarkDown.Text := Body;
        Finally
          View.MarkDown.EndUpdate;
        End;
      End;
    If MaxW < 80 Then
      Begin
        If MinLineH > 0 Then
          View.Height := MinLineH;
        Exit;
      End;
    If (Not View.HandleAllocated) And Assigned(View.Parent) And View.Parent.HandleAllocated Then
      View.HandleNeeded;
    If Not View.HandleAllocated Then
      Begin
        If MinLineH > 0 Then
          View.Height := MinLineH;
        Exit;
      End;
    View.AutoSize := False;
    View.Constraints.MinWidth := 0;
    View.Constraints.MaxWidth := 0;
    View.Width := MaxW;
    View.Constraints.MinWidth := MaxW;
    View.Constraints.MaxWidth := MaxW;
    If View.HandleAllocated Then
      View.CalcLayoutForWidth(MaxW)
    Else
      View.CalcLayout;
    PrefW := 0;
    PrefH := 0;
    View.GetPreferredSize(PrefW, PrefH);
    If PrefH < MinLineH Then
      PrefH := MinLineH;
    { EstimateWrappedHeight wraps raw markdown as one blob and is only a floor
      when layout failed. Shrinking to it clips headings/lists and can leave
      ScrolledTop past the visible head with no inner scrollbar. }
    Est := EstimateWrappedHeight(View.Font, Body, MaxW, MinLineH);
    If PrefH <= MinLineH Then
      Begin
        If Est > PrefH Then
          PrefH := Est;
      End;
    If PrefH > MaxMarkdownCardHeight Then
      Begin
        View.ScrollBars := ssAutoVertical;
        PrefH := MaxMarkdownCardHeight;
      End
    Else
      View.ScrollBars := ssNone;
    View.Height := PrefH;
    View.Constraints.MinHeight := PrefH;
    View.Constraints.MaxHeight := PrefH;
    If TextChanged Then
      View.ResetScroll;
  Except
    View.Height := MinLineH * 2;
  End;
End;

Constructor TAssistantTraceView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alClient;
  FShowThinking := True;
  FTruncatedLines := TruncatedLineCount;
  FBoundTrace := Nil;
  FCopyPopup := Nil;
  FLastContentWidth := 0;
  FRelayouting := False;
  Color := clWindow;
  If Assigned(TraceScroll) Then
    Begin
      TraceScroll.Color := clWindow;
      TraceScroll.ParentBackground := False;
      { AutoScroll on GTK uses child Top values that already include the scroll
        offset, which inflates Range and leaves a blank band above the cards. }
      TraceScroll.AutoScroll := False;
      TraceScroll.HorzScrollBar.Visible := False;
    End;
  If Assigned(TraceHost) Then
    Begin
      TraceHost.Color := clWindow;
      { alTop inside a GTK scrollbox can cap height to the viewport, so later
        cards are laid out but the range never grows. Size the host ourselves.
        AutoSize must stay off: with Align=alNone it also shrinks the width to
        short titles such as Thinking. ChildSizing is also off: we stack cards
        by SetBounds so scroll offset cannot leak into Top. }
      TraceHost.Align := alNone;
      TraceHost.AutoSize := False;
      TraceHost.Left := 0;
      TraceHost.Top := 0;
      TraceHost.ChildSizing.Layout := cclNone;
    End;
  If Assigned(EmptyLabel) Then
    Begin
      EmptyLabel.Align := alClient;
      EmptyLabel.Alignment := taCenter;
      EmptyLabel.Layout := tlCenter;
    End;
End;

Destructor TAssistantTraceView.Destroy;
Begin
  If Assigned(FCopyPopup) Then
    FreeAndNil(FCopyPopup);
  Inherited Destroy;
End;

Function TAssistantTraceView.LineHeightPx: Integer;
Begin
  { Do not HandleNeeded here: Create runs before Parent is set. }
  Result := 16;
  If HandleAllocated Then
    Result := Canvas.TextHeight('Hg')
  Else
    Result := Abs(Font.Height);
  If Result < 12 Then
    Result := 16;
End;

Procedure TAssistantTraceView.ApplyVerticalStack(Host: TWinControl; Inner: Boolean);
Var
  Gap: Integer;
Begin
  If Not Assigned(Host) Then
    Exit;
  { ControlsPerLine is per column when Layout is cclTopToBottomThenLeftToRight, so
    TTB+1 is a horizontal row. LTR+1 is one child per row (a vertical stack). }
  Host.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Host.ChildSizing.ControlsPerLine := 1;
  Host.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
  Host.ChildSizing.ShrinkHorizontal := crsHomogenousChildResize;
  Host.ChildSizing.EnlargeVertical := crsAnchorAligning;
  Host.ChildSizing.ShrinkVertical := crsAnchorAligning;
  If Inner Then
    Begin
      Host.ChildSizing.LeftRightSpacing := CardInnerPad;
      Host.ChildSizing.TopBottomSpacing := CardInnerPad;
      Host.ChildSizing.VerticalSpacing := 4;
    End
  Else
    Begin
      Gap := LineHeightPx Div 2;
      If Gap < 6 Then
        Gap := 8;
      Host.ChildSizing.LeftRightSpacing := CardInnerPad;
      Host.ChildSizing.TopBottomSpacing := CardInnerPad;
      Host.ChildSizing.VerticalSpacing := Gap;
    End;
End;

Procedure TAssistantTraceView.InitHostedPanel(Panel: TPanel; AutoSizePanel: Boolean; FixedHeight: Integer);
Begin
  { ChildSizing stays off until FinishHostedPanel so markdown is not asked for a
    preferred size while siblings are still being parented. }
  Panel.Parent := TraceHost;
  Panel.BevelOuter := bvNone;
  Panel.Align := alNone;
  Panel.Anchors := [akLeft, akTop];
  Panel.BorderSpacing.Around := 0;
  Panel.ParentBackground := False;
  Panel.AutoSize := False;
  Panel.ChildSizing.Layout := cclNone;
  If Not AutoSizePanel Then
    Panel.Height := FixedHeight;
End;

Procedure TAssistantTraceView.FinishHostedPanel(Panel: TPanel; AutoSizePanel: Boolean);
Begin
  If Not AutoSizePanel Then
    Exit;
  ApplyVerticalStack(Panel, True);
  Panel.AutoSize := True;
End;

Procedure TAssistantTraceView.LockControlHeight(Control: TControl; NewHeight: Integer);
Begin
  If Not Assigned(Control) Then
    Exit;
  If NewHeight < 1 Then
    NewHeight := 1;
  NewHeight := ClampWidgetCoordValue(NewHeight);
  Control.AutoSize := False;
  Control.Constraints.MinHeight := 0;
  Control.Constraints.MaxHeight := 0;
  Control.Height := NewHeight;
  Control.Constraints.MinHeight := NewHeight;
  Control.Constraints.MaxHeight := NewHeight;
End;

Procedure TAssistantTraceView.LockControlWidth(Control: TControl; NewWidth: Integer);
Begin
  If Not Assigned(Control) Then
    Exit;
  If NewWidth < 1 Then
    NewWidth := 1;
  Control.Constraints.MinWidth := 0;
  Control.Constraints.MaxWidth := 0;
  Control.Width := NewWidth;
  Control.Constraints.MinWidth := NewWidth;
  Control.Constraints.MaxWidth := NewWidth;
End;

Function TAssistantTraceView.ViewportWidth: Integer;
Begin
  Result := 0;
  If Assigned(TraceScroll) Then
    Begin
      Result := TraceScroll.ClientWidth;
      If Result < 80 Then
        Result := TraceScroll.Width;
    End;
  If (Result < 80) And Assigned(TraceHost) Then
    Result := TraceHost.Width;
  If Result < 80 Then
    Result := 0;
End;

Procedure TAssistantTraceView.ApplyHostWidth;
Var
  W: Integer;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  W := ViewportWidth;
  TraceHost.AutoSize := False;
  TraceHost.Left := 0;
  TraceHost.Top := 0;
  If W < 80 Then
    Exit;
  TraceHost.Constraints.MinWidth := 0;
  TraceHost.Constraints.MaxWidth := 0;
  If TraceHost.Width <> W Then
    TraceHost.Width := W;
  LockControlWidth(TraceHost, W);
End;

Function TAssistantTraceView.NamedChild(Host: TWinControl; Const ChildName: String): TControl;
Var
  I: Integer;
Begin
  Result := Nil;
  If (Not Assigned(Host)) Or (ChildName = '') Then
    Exit;
  For I := 0 To Host.ControlCount - 1 Do
    If CompareText(Host.Controls[I].Name, ChildName) = 0 Then
      Begin
        Result := Host.Controls[I];
        Exit;
      End;
End;

Function TAssistantTraceView.OrderFrames(Trace: TAssistantTrace): Integer;
Var
  I, Y, Gap, LeftPad, InnerW, CardH: Integer;
  Card: TControl;
  Block: TTraceBlock;
  Panel: TWinControl;
Begin
  { Position in trace order with SetBounds. Re-parenting or ChildSizing while
    scrolled inflates the GTK range and parks a blank band above the user card.
    AutoSize on a card would shrink it to the title "Thinking"; lock width to
    the pane and only let height follow the wrapped body. }
  Result := CardInnerPad;
  If (Not Assigned(Trace)) Or (Not Assigned(TraceHost)) Then
    Exit;
  LeftPad := CardInnerPad;
  Gap := LineHeightPx Div 2;
  If Gap < 6 Then
    Gap := 8;
  InnerW := TraceHost.Width - (LeftPad * 2);
  If InnerW < 80 Then
    InnerW := TraceHost.Width;
  If InnerW < 1 Then
    InnerW := 1;
  Y := CardInnerPad;
  For I := 0 To Trace.Count - 1 Do
    Begin
      Block := Trace[I];
      If (Not Assigned(Block)) Or (Not Assigned(Block.Frame)) Then
        Continue;
      If Not (Block.Frame Is TControl) Then
        Continue;
      Card := TControl(Block.Frame);
      If Not Card.Visible Then
        Continue;
      Card.Align := alNone;
      Card.Anchors := [akLeft, akTop];
      LockControlWidth(Card, InnerW);
      If Card Is TWinControl Then
        Begin
          Panel := TWinControl(Card);
          If Panel.AutoSize Then
            Begin
              Panel.InvalidatePreferredSize;
              Panel.AdjustSize;
            End;
        End;
      CardH := Card.Height;
      If CardH < 1 Then
        CardH := LineHeightPx;
      If Y >= MaxSafeWidgetCoord Then
        Begin
          Card.Visible := False;
          Continue;
        End;
      If Y + CardH > MaxSafeWidgetCoord Then
        CardH := MaxSafeWidgetCoord - Y;
      If CardH < 1 Then
        CardH := 1;
      Card.SetBounds(LeftPad, ClampWidgetCoordValue(Y), InnerW, CardH);
      LockControlWidth(Card, InnerW);
      Inc(Y, CardH + Gap);
      If Y > MaxSafeWidgetCoord Then
        Y := MaxSafeWidgetCoord;
    End;
  Result := Y - Gap + CardInnerPad;
  If Result < CardInnerPad Then
    Result := CardInnerPad;
End;

Procedure TAssistantTraceView.Resize;
Begin
  Inherited Resize;
  If Assigned(TraceHost) And Assigned(TraceScroll) And (TraceScroll.ClientWidth > 0) Then
    If TraceHost.Width <> TraceScroll.ClientWidth Then
      FitHostToContent;
  RelayoutIfWidthChanged;
End;

Procedure TAssistantTraceView.RelayoutIfWidthChanged;
Var
  W: Integer;
Begin
  If FRelayouting Then
    Exit;
  If csDestroying In ComponentState Then
    Exit;
  If Not Assigned(FBoundTrace) Then
    Exit;
  W := ContentWidth;
  If W < 80 Then
    Exit;
  If Abs(W - FLastContentWidth) < 12 Then
    Exit;
  FRelayouting := True;
  Try
    FLastContentWidth := W;
    Sync(FBoundTrace, False);
  Finally
    FRelayouting := False;
  End;
End;

Procedure TAssistantTraceView.SetShowThinking(Value: Boolean);
Begin
  If FShowThinking = Value Then
    Exit;
  FShowThinking := Value;
End;

Procedure TAssistantTraceView.EnsureCopyPopup;
Var
  CopyItem, SelectItem: TMenuItem;
Begin
  If Assigned(FCopyPopup) Then
    Exit;
  FCopyPopup := TPopupMenu.Create(Nil);
  FCopyPopup.OnPopup := @CopyPopupPopup;
  CopyItem := TMenuItem.Create(FCopyPopup);
  CopyItem.Caption := 'Copy';
  CopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  CopyItem.OnClick := @CopyItemClick;
  FCopyPopup.Items.Add(CopyItem);
  SelectItem := TMenuItem.Create(FCopyPopup);
  SelectItem.Caption := 'Select All';
  SelectItem.ShortCut := ShortCut(Ord('A'), [ssCtrl]);
  SelectItem.OnClick := @SelectAllItemClick;
  FCopyPopup.Items.Add(SelectItem);
End;

Procedure TAssistantTraceView.CopyPopupPopup(Sender: TObject);
Var
  CopyItem: TMenuItem;
  Edit: TCustomEdit;
Begin
  If FCopyPopup.Items.Count = 0 Then
    Exit;
  CopyItem := FCopyPopup.Items[0];
  Edit := Nil;
  If FCopyPopup.PopupComponent Is TCustomEdit Then
    Edit := TCustomEdit(FCopyPopup.PopupComponent);
  CopyItem.Enabled := Assigned(Edit) And (Edit.SelLength > 0);
End;

Procedure TAssistantTraceView.CopyItemClick(Sender: TObject);
Begin
  If FCopyPopup.PopupComponent Is TCustomEdit Then
    TCustomEdit(FCopyPopup.PopupComponent).CopyToClipboard;
End;

Procedure TAssistantTraceView.SelectAllItemClick(Sender: TObject);
Begin
  If FCopyPopup.PopupComponent Is TCustomEdit Then
    TCustomEdit(FCopyPopup.PopupComponent).SelectAll;
End;

Function TAssistantTraceView.MakeSelectableMemo(Host: TWinControl; Const ChildName: String; Italic, Gray: Boolean): TMemo;
Begin
  EnsureCopyPopup;
  Result := TMemo.Create(Host);
  Result.Parent := Host;
  Result.Align := alNone;
  Result.Anchors := [akLeft, akTop];
  Result.Name := ChildName;
  Result.ReadOnly := True;
  Result.BorderStyle := bsNone;
  Result.ScrollBars := ssNone;
  Result.WordWrap := True;
  Result.WantReturns := True;
  Result.WantTabs := False;
  Result.HideSelection := False;
  Result.TabStop := False;
  Result.PopupMenu := FCopyPopup;
  Result.Color := Host.Color;
  If Italic Then
    Result.Font.Style := [fsItalic];
  If Gray Then
    Result.Font.Color := clGrayText;
End;

Function TAssistantTraceView.MakeFooterLabel(Host: TWinControl): TLabel;
Begin
  Result := TLabel.Create(Host);
  Result.Align := alNone;
  Result.Anchors := [akLeft, akTop];
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Font.Style := [fsItalic];
  Result.Font.Color := clGrayText;
  Result.Name := 'FooterLabel';
  Result.Caption := '';
  Result.Visible := False;
  If Result.Font.Size > 0 Then
    Result.Font.Size := Result.Font.Size - 1
  Else If Result.Font.Height < 0 Then
    Result.Font.Height := Round(Result.Font.Height * 0.9);
  Result.Parent := Host;
End;

Function TAssistantTraceView.EnsureFooterLabel(Panel: TPanel): TLabel;
Var
  Child: TControl;
  SavedLayout: TControlChildrenLayout;
Begin
  Result := Nil;
  If Not Assigned(Panel) Then
    Exit;
  Child := NamedChild(Panel, 'FooterLabel');
  If Child Is TLabel Then
    Begin
      Result := TLabel(Child);
      Exit;
    End;
  SavedLayout := Panel.ChildSizing.Layout;
  Panel.ChildSizing.Layout := cclNone;
  Try
    Result := MakeFooterLabel(Panel);
  Finally
    Panel.ChildSizing.Layout := SavedLayout;
  End;
End;

Procedure TAssistantTraceView.BindBlockFooter(Panel: TPanel; Const FooterText: String);
Var
  Child: TControl;
  Footer: TLabel;
Begin
  Child := NamedChild(Panel, 'FooterLabel');
  If Not (Child Is TLabel) Then
    Exit;
  Footer := TLabel(Child);
  Footer.Caption := FooterText;
  Footer.Visible := FooterText <> '';
End;

Function TAssistantTraceView.WrappedTextHeight(Const TypeFace: TFont; Const SourceText: String; MaxWidth: Integer): Integer;
Var
  Bmp: TBitmap;
  R: TRect;
  Sample: String;
  LineH: Integer;
Begin
  Sample := SourceText;
  If Sample = '' Then
    Sample := 'Hg';
  If MaxWidth < 8 Then
    MaxWidth := 8;
  Bmp := TBitmap.Create;
  Try
    Bmp.SetSize(1, 1);
    Bmp.Canvas.Font.Assign(TypeFace);
    R := Rect(0, 0, MaxWidth, 0);
    DrawText(Bmp.Canvas.Handle, PChar(Sample), Length(Sample), R,
      DT_CALCRECT Or DT_WORDBREAK Or DT_NOPREFIX);
    LineH := Bmp.Canvas.TextHeight('Hg');
    Result := R.Bottom - R.Top + 2;
    If Result < LineH + 2 Then
      Result := LineH + 2;
  Finally
    Bmp.Free;
  End;
End;

Procedure TAssistantTraceView.BindSelectableMemo(Memo: TMemo; Const SourceText: String);
Var
  MaxW, H: Integer;
Begin
  If Not Assigned(Memo) Then
    Exit;
  If Memo.Text <> SourceText Then
    Memo.Text := SourceText;
  MaxW := ContentWidth;
  Memo.AutoSize := False;
  Memo.Constraints.MinHeight := 0;
  Memo.Constraints.MaxHeight := 0;
  If MaxW < 80 Then
    Exit;
  LockControlWidth(Memo, MaxW);
  H := WrappedTextHeight(Memo.Font, SourceText, MaxW);
  If H > MaxMarkdownCardHeight Then
    Begin
      Memo.ScrollBars := ssAutoVertical;
      H := MaxMarkdownCardHeight;
    End
  Else
    Memo.ScrollBars := ssNone;
  { GTK TMemo preferred height is several lines; lock to the wrapped text. }
  Memo.Constraints.MinHeight := H;
  Memo.Constraints.MaxHeight := H;
  Memo.Height := H;
End;

Function TAssistantTraceView.ContentWidth: Integer;
Var
  W: Integer;
Begin
  Result := 0;
  W := ViewportWidth;
  If W < 80 Then
    Exit;
  Result := W - (CardInnerPad * 4);
  If Result < 80 Then
    Result := W - (CardInnerPad * 2);
  If Result < 40 Then
    Result := W;
End;

Function TAssistantTraceView.LastLines(Const SourceText: String; MaxLines: Integer; MaxChars: Integer): String;
Var
  SL: TStringList;
  Start, I: Integer;
Begin
  Result := SourceText;
  If MaxChars > 0 Then
    If Length(Result) > MaxChars Then
      Result := '…' + Copy(Result, Length(Result) - MaxChars + 1, MaxChars);
  If MaxLines < 1 Then
    Exit;
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
    SL.Text := StringReplace(SL.Text, #13, #10, [rfReplaceAll]);
    If SL.Count <= MaxLines Then
      Exit;
    Start := SL.Count - MaxLines;
    Result := '';
    For I := Start To SL.Count - 1 Do
      Begin
        If Result <> '' Then
          Result := Result + LineEnding;
        Result := Result + SL[I];
      End;
    Result := '…' + LineEnding + Result;
  Finally
    SL.Free;
  End;
End;

Procedure TAssistantTraceView.SplitTrailingMdFooter(Const SourceText: String; Out BodyText, FooterText: String);
Var
  SL: TStringList;
  I, LastNonEmpty: Integer;
  Last, Inner: String;
Begin
  BodyText := TrimRight(SourceText);
  FooterText := '';
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(SourceText, #13#10, #10, [rfReplaceAll]);
    LastNonEmpty := -1;
    For I := SL.Count - 1 DownTo 0 Do
      If Trim(SL[I]) <> '' Then
        Begin
          LastNonEmpty := I;
          Break;
        End;
    If LastNonEmpty < 0 Then
      Exit;
    Last := Trim(SL[LastNonEmpty]);
    If (Length(Last) >= 5) And (Copy(Last, 1, 2) = '*(') And (Copy(Last, Length(Last) - 1, 2) = ')*') Then
      Begin
        Inner := Trim(Copy(Last, 3, Length(Last) - 4));
        FooterText := Inner;
        SL.Delete(LastNonEmpty);
        While (SL.Count > 0) And (Trim(SL[SL.Count - 1]) = '') Do
          SL.Delete(SL.Count - 1);
        BodyText := TrimRight(SL.Text);
      End;
  Finally
    SL.Free;
  End;
End;

Procedure TAssistantTraceView.BindUser(Block: TTraceBlock);
Var
  Panel: TPanel;
  Title: TLabel;
  Child: TControl;
  BodyText, FooterText: String;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Block.Frame := Panel;
      Title := TLabel.Create(Panel);
      Title.Align := alNone;
      Title.Anchors := [akLeft, akTop];
      Title.Font.Style := [fsBold];
      Title.Name := 'TitleLabel';
      Title.Caption := Block.Title;
      Title.Parent := Panel;
      MakeSelectableMemo(Panel, 'BodyMemo', False, False);
      MakeFooterLabel(Panel);
      FinishHostedPanel(Panel, True);
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  EnsureFooterLabel(Panel);
  SplitTrailingMdFooter(Block.Body, BodyText, FooterText);
  Child := NamedChild(Panel, 'TitleLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Title;
  Child := NamedChild(Panel, 'BodyMemo');
  If Child Is TMemo Then
    BindSelectableMemo(TMemo(Child), BodyText);
  BindBlockFooter(Panel, FooterText);
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindThinking(Block: TTraceBlock);
Var
  Panel: TPanel;
  Header: TLabel;
  View: TMarkDownControl;
  Child: TControl;
  Display: String;
Begin
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'ThoughtView') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Block.Frame := Panel;
      Panel.ParentColor := True;
      Panel.ParentBackground := True;
      Header := TLabel.Create(Panel);
      Header.Align := alNone;
      Header.Anchors := [akLeft, akTop];
      Header.Font.Style := [fsBold];
      Header.Font.Color := clGrayText;
      Header.Name := 'HeaderLabel';
      Header.Caption := Block.Title;
      Header.Parent := Panel;
      View := TMarkDownControl.Create(Panel);
      View.AutoSize := False;
      View.Align := alNone;
      View.Anchors := [akLeft, akTop];
      View.Name := 'ThoughtView';
      View.Color := clWindow;
      View.ParentColor := True;
      View.ParentBackground := True;
      View.BorderStyle := bsNone;
      View.ScrollBars := ssNone;
      View.FontColor := clGrayText;
      View.FontQuoteColor := clGrayText;
      View.MonoFontName := 'Monospace';
      View.Parent := Panel;
      MakeFooterLabel(Panel);
      FinishHostedPanel(Panel, True);
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  EnsureFooterLabel(Panel);
  Child := NamedChild(Panel, 'HeaderLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Title;
  { CoT is often one long wrap with few line breaks; cap chars as well as lines.
    Never markdown-parse the full accumulated thought on the UI thread. }
  Display := LastLines(Block.Body, FTruncatedLines, 2000);
  View := Nil;
  Child := NamedChild(Panel, 'ThoughtView');
  If Child Is TMarkDownControl Then
    Begin
      View := TMarkDownControl(Child);
      SizeMarkdownView(View, Display, ContentWidth, LineHeightPx);
      View.Visible := FShowThinking;
    End;
  Panel.InvalidatePreferredSize;
  If Block.Running Then
    BindBlockFooter(Panel, '')
  Else
    BindBlockFooter(Panel, Block.Footer);
  { Hide Thinking drops thought bodies; a running card keeps the timer line. }
  Panel.Visible := FShowThinking Or Block.Running;
  { AutoSize + markdown GetPreferredSize on a growing CoT starves the event loop. }
  Panel.AutoSize := False;
  If Assigned(View) And View.Visible Then
    LockControlHeight(Panel, LineHeightPx + 6 + View.Height + CardInnerPad)
  Else
    LockControlHeight(Panel, LineHeightPx + CardInnerPad);
End;

Procedure TAssistantTraceView.BindTool(Block: TTraceBlock);
Var
  Panel: TPanel;
  Body: TMemo;
  Child: TControl;
  Status, Line: String;
  RowH: Integer;
Begin
  RowH := LineHeightPx + 12;
  If RowH < ToolHeight Then
    RowH := ToolHeight;
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'BodyMemo') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, False, RowH);
      Block.Frame := Panel;
      Panel.Color := clInfoBk;
      LockControlHeight(Panel, RowH);
      Body := MakeSelectableMemo(Panel, 'BodyMemo', False, False);
      Body.Align := alClient;
      Body.Color := clInfoBk;
      Body.WordWrap := False;
      Body.BorderSpacing.Left := 8;
      LockControlHeight(Body, RowH);
      Child := TLabel.Create(Panel);
      Child.Parent := Panel;
      Child.Align := alRight;
      TLabel(Child).Layout := tlCenter;
      Child.Name := 'StatusLabel';
      Child.BorderSpacing.Right := 8;
      TLabel(Child).Font.Color := clGrayText;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  LockControlHeight(Panel, RowH);
  If Block.Running Or Block.Ok Then
    Status := FormatThoughtElapsed(Block.DurationMs)
  Else
    Status := 'failed';
  Line := Block.Title;
  Child := NamedChild(Panel, 'BodyMemo');
  If Child Is TMemo Then
    Begin
      Body := TMemo(Child);
      If Body.Text <> Line Then
        Body.Text := Line;
      LockControlHeight(Body, RowH);
    End;
  Child := NamedChild(Panel, 'StatusLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Status;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindSubagent(Block: TTraceBlock);
Var
  KindCaption: String;
Begin
  KindCaption := SubagentKindCaption(ParseSubagentKind(Block.ToolName));
  If Block.Running Then
    Begin
      If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
        If NamedChild(TPanel(Block.Frame), 'BodyMemo') = Nil Then
          Begin
            TPanel(Block.Frame).Free;
            Block.Frame := Nil;
          End;
      If Block.Title = '' Then
        Block.Title := SubagentRunningTitle(KindCaption, 'Starting');
      BindTool(Block);
    End
  Else
    Begin
      If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
        If NamedChild(TPanel(Block.Frame), 'AnswerView') = Nil Then
          Begin
            TPanel(Block.Frame).Free;
            Block.Frame := Nil;
          End;
      If Block.Title = '' Then
        Block.Title := SubagentFinishedTitle(KindCaption, Block.Title);
      BindRichCard(Block, clNavy);
    End;
End;

Procedure TAssistantTraceView.BindRichCard(Block: TTraceBlock; Const TitleColor: TColor);
Var
  Panel: TPanel;
  Title: TLabel;
  View: TMarkDownControl;
  Child: TControl;
Begin
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'AnswerView') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Block.Frame := Panel;
      Title := TLabel.Create(Panel);
      Title.Align := alNone;
      Title.Anchors := [akLeft, akTop];
      Title.Font.Style := [fsBold];
      Title.Font.Color := TitleColor;
      Title.Name := 'TitleLabel';
      Title.Caption := Block.Title;
      Title.Parent := Panel;
      View := TMarkDownControl.Create(Panel);
      View.AutoSize := False;
      View.Align := alNone;
      View.Anchors := [akLeft, akTop];
      View.Name := 'AnswerView';
      View.Color := clWindow;
      View.ParentColor := False;
      View.ParentBackground := False;
      View.ScrollBars := ssNone;
      View.MonoFontName := 'Monospace';
      View.Parent := Panel;
      MakeFooterLabel(Panel);
      FinishHostedPanel(Panel, True);
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  EnsureFooterLabel(Panel);
  Child := NamedChild(Panel, 'TitleLabel');
  If Child Is TLabel Then
    Begin
      Title := TLabel(Child);
      Title.Caption := Block.Title;
      Title.Font.Color := TitleColor;
    End;
  View := Nil;
  Child := NamedChild(Panel, 'AnswerView');
  If Child Is TMarkDownControl Then
    Begin
      View := TMarkDownControl(Child);
      SizeMarkdownView(View, Block.Body, ContentWidth, LineHeightPx);
    End;
  BindBlockFooter(Panel, Block.Footer);
  Panel.InvalidatePreferredSize;
  Panel.Visible := (Block.Body <> '') Or (Block.Footer <> '');
  Panel.AutoSize := False;
  If Assigned(View) And View.Visible Then
    LockControlHeight(Panel, LineHeightPx + 6 + View.Height + CardInnerPad)
  Else
    LockControlHeight(Panel, LineHeightPx + CardInnerPad);
End;

Procedure TAssistantTraceView.BindAnswer(Block: TTraceBlock);
Var
  Child: TControl;
  H: Integer;
Begin
  { Live growing text: memo wrap, not markdown parse. Finish swaps to markdown. }
  If Block.Running Then
    Begin
      If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
        If NamedChild(TPanel(Block.Frame), 'BodyMemo') = Nil Then
          Begin
            TPanel(Block.Frame).Free;
            Block.Frame := Nil;
          End;
      BindUser(Block);
      If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
        Begin
          Child := NamedChild(TPanel(Block.Frame), 'BodyMemo');
          H := LineHeightPx + CardInnerPad;
          If Assigned(Child) Then
            H := LineHeightPx + 6 + Child.Height + CardInnerPad;
          LockControlHeight(TPanel(Block.Frame), H);
        End;
    End
  Else
    BindRichCard(Block, clWindowText);
End;

Procedure TAssistantTraceView.EnsureFrame(Block: TTraceBlock);
Begin
  Case Block.Kind Of
    tbkUser: BindUser(Block);
    tbkThinking: BindThinking(Block);
    tbkTool: BindTool(Block);
    tbkSubagent: BindSubagent(Block);
    tbkAnswer: BindAnswer(Block);
    tbkSteer: BindRichCard(Block, clNavy);
    tbkNote: BindRichCard(Block, clMaroon);
  End;
End;

Function TAssistantTraceView.ScrollHandleReady: Boolean;
Begin
  Result := Assigned(TraceScroll) And TraceScroll.HandleAllocated And
    TraceScroll.Visible And (Not (csDestroying In TraceScroll.ComponentState));
End;

Procedure TAssistantTraceView.SetVertScrollPos(NewPos: Integer);
Begin
  { TScrollingWinControl.ScrollBy always calls ScrollBy_WS, which raises
    "Handle not allocated" if the GTK widget is not realized yet. }
  If Not ScrollHandleReady Then
    Exit;
  If NewPos < 0 Then
    NewPos := 0;
  If TraceScroll.VertScrollBar.Position <> NewPos Then
    TraceScroll.VertScrollBar.Position := NewPos;
End;

Function TAssistantTraceView.HostedContentHeight: Integer;
Var
  I, Bottom: Integer;
  Card: TControl;
Begin
  Result := CardInnerPad;
  If Not Assigned(TraceHost) Then
    Exit;
  Bottom := 0;
  For I := 0 To TraceHost.ControlCount - 1 Do
    Begin
      Card := TraceHost.Controls[I];
      If (Not Assigned(Card)) Or (Not Card.Visible) Then
        Continue;
      If Card.Top + Card.Height > Bottom Then
        Bottom := Card.Top + Card.Height;
    End;
  If Bottom > 0 Then
    Result := Bottom + CardInnerPad;
  If Result < 1 Then
    Result := 1;
End;

Procedure TAssistantTraceView.ApplyScrollRange(ForceBottom: Boolean);
Var
  MaxPos, NewH, Page, SavedPos, OldRange, OldPage: Integer;
  Follow: Boolean;
Begin
  If (Not Assigned(TraceScroll)) Or (Not Assigned(TraceHost)) Then
    Exit;
  SavedPos := TraceScroll.VertScrollBar.Position;
  OldRange := TraceScroll.VertScrollBar.Range;
  OldPage := TraceScroll.VertScrollBar.Page;
  Follow := ForceBottom Or ScrollShouldFollowTail(SavedPos, OldRange, OldPage, 24);
  If TraceHost.Left <> 0 Then
    TraceHost.Left := 0;
  If TraceHost.Top <> 0 Then
    TraceHost.Top := 0;
  If Assigned(FBoundTrace) Then
    NewH := OrderFrames(FBoundTrace)
  Else
    NewH := HostedContentHeight;
  If NewH < 1 Then
    NewH := 1;
  NewH := ClampWidgetCoordValue(NewH);
  If TraceHost.Height <> NewH Then
    TraceHost.Height := NewH;
  Page := TraceScroll.ClientHeight;
  If Page < 1 Then
    Page := 1;
  If TraceScroll.HorzScrollBar.Range <> 0 Then
    TraceScroll.HorzScrollBar.Range := 0;
  If TraceScroll.HorzScrollBar.Page <> TraceScroll.ClientWidth Then
    TraceScroll.HorzScrollBar.Page := TraceScroll.ClientWidth;
  If TraceScroll.VertScrollBar.Range <> NewH Then
    TraceScroll.VertScrollBar.Range := NewH;
  If TraceScroll.VertScrollBar.Page <> Page Then
    TraceScroll.VertScrollBar.Page := Page;
  MaxPos := NewH - Page;
  If MaxPos < 0 Then
    MaxPos := 0;
  If Follow Then
    SetVertScrollPos(MaxPos)
  Else
    Begin
      If SavedPos > MaxPos Then
        SavedPos := MaxPos;
      SetVertScrollPos(SavedPos);
    End;
End;

Procedure TAssistantTraceView.FitHostToContent;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  ApplyHostWidth;
  ApplyScrollRange(False);
End;

Procedure TAssistantTraceView.ScrollToStart;
Var
  CardIndex, ChildIndex: Integer;
  Card: TWinControl;
  Child: TControl;
Begin
  SetVertScrollPos(0);
  If Not Assigned(TraceHost) Then
    Exit;
  For CardIndex := 0 To TraceHost.ControlCount - 1 Do
    Begin
      If Not (TraceHost.Controls[CardIndex] Is TWinControl) Then
        Continue;
      Card := TWinControl(TraceHost.Controls[CardIndex]);
      For ChildIndex := 0 To Card.ControlCount - 1 Do
        Begin
          Child := Card.Controls[ChildIndex];
          If Child Is TMarkDownControl Then
            TMarkDownControl(Child).ResetScroll;
        End;
    End;
End;

Procedure TAssistantTraceView.ScrollToEnd;
Begin
  If Not Assigned(TraceScroll) Then
    Exit;
  ApplyHostWidth;
  ApplyScrollRange(True);
End;

Procedure TAssistantTraceView.ResetFrames;
Begin
  If Assigned(FBoundTrace) Then
    FBoundTrace.NilFrames;
  FLastContentWidth := 0;
  If Not Assigned(TraceHost) Then
    Exit;
  TraceHost.AutoSize := False;
  TraceHost.ChildSizing.Layout := cclNone;
  Try
    While TraceHost.ControlCount > 0 Do
      TraceHost.Controls[0].Free;
  Finally
    TraceHost.ChildSizing.Layout := cclNone;
    TraceHost.Left := 0;
    TraceHost.Top := 0;
    TraceHost.AutoSize := False;
  End;
End;

Procedure TAssistantTraceView.Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
Var
  I: Integer;
  Empty: Boolean;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  FBoundTrace := Trace;
  Empty := (Not Assigned(Trace)) Or (Trace.Count = 0);
  If Assigned(EmptyLabel) Then
    Begin
      EmptyLabel.Visible := Empty;
      If Empty Then
        EmptyLabel.BringToFront;
    End;
  { Do not hide TraceScroll when empty: GTK destroys the handle, and the next
    VertScrollBar.Position write raises TWinControl.ScrollBy_WS. }
  If Empty Then
    Exit;
  If Assigned(TraceScroll) Then
    TraceScroll.AutoScroll := False;
  ApplyHostWidth;
  If Assigned(Trace) Then
    For I := 0 To Trace.Count - 1 Do
      Try
        EnsureFrame(Trace[I]);
      Except
      End;
  If ContentWidth >= 80 Then
    FLastContentWidth := ContentWidth;
  { ScrollBottom only follows the tail when the bar is already at max. A user
    who scrolled up keeps their position; Range grows so they can reach new content. }
  ApplyScrollRange(False);
End;

Procedure TAssistantTraceView.RefreshElapsed(Trace: TAssistantTrace);
Var
  I: Integer;
  Block: TTraceBlock;
  Header: TControl;
Begin
  If Not Assigned(Trace) Then
    Exit;
  Trace.TickElapsed;
  For I := 0 To Trace.Count - 1 Do
    Begin
      Block := Trace[I];
      If (Not Assigned(Block.Frame)) Or (Not (Block.Frame Is TPanel)) Then
        Continue;
      If Block.Kind = tbkThinking Then
        Begin
          Header := NamedChild(TPanel(Block.Frame), 'HeaderLabel');
          If Header Is TLabel Then
            TLabel(Header).Caption := Block.Title;
        End
      Else If Block.Kind = tbkTool Then
        BindTool(Block)
      Else If (Block.Kind = tbkSubagent) And Block.Running Then
        BindSubagent(Block);
    End;
End;

Initialization

RegisterClass(TAssistantTraceView);

End.
