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
    FStreaming: Boolean;
    FStreamStartedAt: TDateTime;
    FLivePanel: TPanel;
    FLiveClock: TMemo;
    FCopyPopup: TPopupMenu;
    Procedure SetShowThinking(Value: Boolean);
    Procedure SetStreaming(Value: Boolean);
    Function LineHeightPx: Integer;
    Procedure ApplyVerticalStack(Host: TWinControl; Inner: Boolean);
    Procedure InitHostedPanel(Panel: TPanel; AutoSizePanel: Boolean; FixedHeight: Integer);
    Function NamedChild(Host: TWinControl; Const ChildName: String): TControl;
    Procedure OrderFrames(Trace: TAssistantTrace);
    Procedure EnsureFrame(Block: TTraceBlock);
    Procedure BindThinking(Block: TTraceBlock);
    Procedure BindTool(Block: TTraceBlock);
    Procedure BindAnswer(Block: TTraceBlock);
    Procedure BindRichCard(Block: TTraceBlock; Const TitleColor: TColor);
    Procedure BindUser(Block: TTraceBlock);
    Procedure SplitTrailingMdFooter(Const SourceText: String; Out BodyText, FooterText: String);
    Procedure EnsureCopyPopup;
    Procedure CopyPopupPopup(Sender: TObject);
    Procedure CopyItemClick(Sender: TObject);
    Procedure SelectAllItemClick(Sender: TObject);
    Function MakeSelectableMemo(Host: TWinControl; Const ChildName: String; Italic, Gray: Boolean): TMemo;
    Procedure BindSelectableMemo(Memo: TMemo; Const SourceText: String);
    Function WrappedTextHeight(Const TypeFace: TFont; Const SourceText: String; MaxWidth: Integer): Integer;
    Procedure EnsureLiveBar;
    Procedure BindLiveBar;
    Function LastLines(Const SourceText: String; MaxLines: Integer): String;
    Procedure ScrollToEnd;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure ResetFrames;
    Procedure Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
    Procedure RefreshElapsed(Trace: TAssistantTrace);
    Property ShowThinking: Boolean Read FShowThinking Write SetShowThinking;
    Property Streaming: Boolean Read FStreaming Write SetStreaming;
    Property StreamStartedAt: TDateTime Read FStreamStartedAt Write FStreamStartedAt;
  End;

Implementation

{$R *.lfm}

Uses
  Clipbrd, DateUtils, LCLIntf, LCLType, MarkDown.Control;

Const
  HeaderHeight = 26;
  ToolHeight = 30;
  TruncatedLineCount = 12;
  CardInnerPad = 8;

Constructor TAssistantTraceView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alClient;
  FShowThinking := True;
  FTruncatedLines := TruncatedLineCount;
  FBoundTrace := Nil;
  FStreaming := False;
  FStreamStartedAt := 0;
  FLivePanel := Nil;
  FLiveClock := Nil;
  FCopyPopup := Nil;
  Color := clWindow;
  If Assigned(TraceScroll) Then
    Begin
      TraceScroll.Color := clWindow;
      TraceScroll.ParentBackground := False;
      TraceScroll.AutoScroll := True;
      TraceScroll.HorzScrollBar.Visible := False;
    End;
  If Assigned(TraceHost) Then
    Begin
      TraceHost.Color := clWindow;
      ApplyVerticalStack(TraceHost, False);
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
  FLivePanel := Nil;
  FLiveClock := Nil;
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
  Panel.Parent := TraceHost;
  Panel.BevelOuter := bvNone;
  Panel.Align := alNone;
  Panel.Anchors := [akLeft, akTop];
  Panel.BorderSpacing.Around := 0;
  Panel.ParentBackground := False;
  If AutoSizePanel Then
    Begin
      Panel.AutoSize := True;
      ApplyVerticalStack(Panel, True);
    End
  Else
    Begin
      Panel.AutoSize := False;
      Panel.Height := FixedHeight;
    End;
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

Procedure TAssistantTraceView.OrderFrames(Trace: TAssistantTrace);
Var
  I, Wanted: Integer;
  Hosted: TControl;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  Wanted := 0;
  If Assigned(Trace) Then
  For I := 0 To Trace.Count - 1 Do
    Begin
      If Not Assigned(Trace[I].Frame) Then
        Continue;
      If Not (Trace[I].Frame Is TControl) Then
        Continue;
      Hosted := TControl(Trace[I].Frame);
      If Hosted.Parent <> TraceHost Then
        Continue;
      If Not Hosted.Visible Then
        Continue;
      If (Wanted >= TraceHost.ControlCount) Or (TraceHost.Controls[Wanted] <> Hosted) Then
        Begin
          TraceHost.RemoveControl(Hosted);
          TraceHost.InsertControl(Hosted, Wanted);
        End;
      Inc(Wanted);
    End;
  If Assigned(FLivePanel) And FLivePanel.Visible And (FLivePanel.Parent = TraceHost) Then
    Begin
      If (Wanted >= TraceHost.ControlCount) Or (TraceHost.Controls[Wanted] <> FLivePanel) Then
        Begin
          TraceHost.RemoveControl(FLivePanel);
          TraceHost.InsertControl(FLivePanel, Wanted);
        End;
    End;
End;

Procedure TAssistantTraceView.SetShowThinking(Value: Boolean);
Begin
  If FShowThinking = Value Then
    Exit;
  FShowThinking := Value;
End;

Procedure TAssistantTraceView.SetStreaming(Value: Boolean);
Begin
  FStreaming := Value;
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
  Result.TabStop := True;
  Result.PopupMenu := FCopyPopup;
  Result.Color := Host.Color;
  If Italic Then
    Result.Font.Style := [fsItalic];
  If Gray Then
    Result.Font.Color := clGrayText;
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
  MaxW := 0;
  If Assigned(TraceHost) Then
    MaxW := TraceHost.ClientWidth - (CardInnerPad * 4);
  If MaxW < 40 Then
    MaxW := 40;
  Memo.AutoSize := False;
  Memo.Width := MaxW;
  H := WrappedTextHeight(Memo.Font, SourceText, MaxW);
  Memo.Constraints.MinHeight := H;
  Memo.Constraints.MaxHeight := H;
  Memo.Height := H;
  Memo.ScrollBars := ssNone;
End;

Function TAssistantTraceView.LastLines(Const SourceText: String; MaxLines: Integer): String;
Var
  SL: TStringList;
  Start, I: Integer;
Begin
  Result := SourceText;
  If MaxLines < 1 Then
    Exit;
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(SourceText, #13#10, #10, [rfReplaceAll]);
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
  Title, Footer: TLabel;
  Body: TMemo;
  Child: TControl;
  BodyText, FooterText: String;
Begin
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'FooterLabel') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Title := TLabel.Create(Panel);
      Title.Parent := Panel;
      Title.Align := alNone;
      Title.Anchors := [akLeft, akTop];
      Title.Font.Style := [fsBold];
      Title.Name := 'TitleLabel';
      Body := MakeSelectableMemo(Panel, 'BodyMemo', False, False);
      Footer := TLabel.Create(Panel);
      Footer.Parent := Panel;
      Footer.Align := alNone;
      Footer.Anchors := [akLeft, akTop];
      Footer.WordWrap := True;
      Footer.Font.Style := [fsItalic];
      Footer.Font.Color := clGrayText;
      Footer.Name := 'FooterLabel';
      If Footer.Font.Size > 0 Then
        Footer.Font.Size := Footer.Font.Size - 1
      Else If Footer.Font.Height < 0 Then
        Footer.Font.Height := Round(Footer.Font.Height * 0.9);
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  SplitTrailingMdFooter(Block.Body, BodyText, FooterText);
  Child := NamedChild(Panel, 'TitleLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Title;
  Child := NamedChild(Panel, 'BodyMemo');
  If Child Is TMemo Then
    BindSelectableMemo(TMemo(Child), BodyText);
  Child := NamedChild(Panel, 'FooterLabel');
  If Child Is TLabel Then
    Begin
      Footer := TLabel(Child);
      Footer.Caption := FooterText;
      Footer.Visible := FooterText <> '';
    End;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindThinking(Block: TTraceBlock);
Var
  Panel: TPanel;
  Header: TLabel;
  Body: TMemo;
  Child: TControl;
  Display: String;
Begin
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'BodyMemo') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Panel.Color := clForm;
      Header := TLabel.Create(Panel);
      Header.Parent := Panel;
      Header.Align := alNone;
      Header.Anchors := [akLeft, akTop];
      Header.Font.Style := [fsBold];
      Header.Font.Color := clGrayText;
      Header.Name := 'HeaderLabel';
      Body := MakeSelectableMemo(Panel, 'BodyMemo', True, True);
      Body.Color := clForm;
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  Child := NamedChild(Panel, 'HeaderLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Title;
  If Block.Running Then
    Display := LastLines(Block.Body, FTruncatedLines)
  Else
    Display := Block.Body;
  Child := NamedChild(Panel, 'BodyMemo');
  If Child Is TMemo Then
    BindSelectableMemo(TMemo(Child), Display);
  { Hide Thinking drops thought cards; the live bar still shows while the turn runs. }
  Panel.Visible := FShowThinking;
  If Assigned(TraceHost) And (TraceHost.ClientWidth > 32) Then
    Panel.Width := TraceHost.ClientWidth;
  Panel.AutoSize := True;
End;

Procedure TAssistantTraceView.BindTool(Block: TTraceBlock);
Var
  Panel: TPanel;
  Body: TMemo;
  Child: TControl;
  Status, Line: String;
Begin
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'BodyMemo') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, False, ToolHeight);
      Panel.Color := clInfoBk;
      Body := MakeSelectableMemo(Panel, 'BodyMemo', False, False);
      Body.Parent := Panel;
      Body.Align := alClient;
      Body.Color := clInfoBk;
      Body.BorderSpacing.Left := 8;
      Child := TLabel.Create(Panel);
      Child.Parent := Panel;
      Child.Align := alRight;
      TLabel(Child).Layout := tlCenter;
      Child.Name := 'StatusLabel';
      Child.BorderSpacing.Right := 8;
      TLabel(Child).Font.Color := clGrayText;
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
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
    End;
  Child := NamedChild(Panel, 'StatusLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Status;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindRichCard(Block: TTraceBlock; Const TitleColor: TColor);
Var
  Panel: TPanel;
  Title: TLabel;
  View: TMarkDownControl;
  Child: TControl;
  PrefW, PrefH: Integer;
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
      Title := TLabel.Create(Panel);
      Title.Parent := Panel;
      Title.Align := alNone;
      Title.Anchors := [akLeft, akTop];
      Title.Font.Style := [fsBold];
      Title.Font.Color := TitleColor;
      Title.Name := 'TitleLabel';
      View := TMarkDownControl.Create(Panel);
      View.Parent := Panel;
      View.Align := alNone;
      View.Anchors := [akLeft, akTop];
      View.Name := 'AnswerView';
      View.AutoSize := False;
      View.Color := clWindow;
      View.ParentColor := False;
      View.ParentBackground := False;
      View.ScrollBars := ssNone;
      View.MonoFontName := 'Monospace';
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  Child := NamedChild(Panel, 'TitleLabel');
  If Child Is TLabel Then
    Begin
      Title := TLabel(Child);
      Title.Caption := Block.Title;
      Title.Font.Color := TitleColor;
    End;
  Child := NamedChild(Panel, 'AnswerView');
  If Child Is TMarkDownControl Then
    Begin
      View := TMarkDownControl(Child);
      Try
        If View.MarkDown.Text <> Block.Body Then
          Begin
            View.MarkDown.BeginUpdate;
            Try
              View.MarkDown.Text := Block.Body;
            Finally
              View.MarkDown.EndUpdate;
            End;
          End;
        If Assigned(TraceHost) And (TraceHost.ClientWidth > 40) Then
          View.Width := TraceHost.ClientWidth - (CardInnerPad * 4)
        Else If Panel.ClientWidth > 0 Then
          View.Width := Panel.ClientWidth;
        View.CalcLayout;
        PrefW := 0;
        PrefH := 0;
        View.GetPreferredSize(PrefW, PrefH);
        If PrefH < LineHeightPx Then
          PrefH := LineHeightPx;
        View.Height := PrefH;
      Except
        View.Height := LineHeightPx * 2;
      End;
    End;
  Panel.Visible := Block.Body <> '';
End;

Procedure TAssistantTraceView.BindAnswer(Block: TTraceBlock);
Begin
  BindRichCard(Block, clWindowText);
End;

Procedure TAssistantTraceView.EnsureLiveBar;
Begin
  If Assigned(FLivePanel) Then
    Exit;
  EnsureCopyPopup;
  FLivePanel := TPanel.Create(Self);
  InitHostedPanel(FLivePanel, False, HeaderHeight);
  FLivePanel.Color := clForm;
  FLiveClock := MakeSelectableMemo(FLivePanel, 'LiveClock', True, True);
  FLiveClock.Parent := FLivePanel;
  FLiveClock.Align := alClient;
  FLiveClock.Color := clForm;
  FLiveClock.BorderSpacing.Left := 8;
  FLivePanel.Visible := False;
End;

Procedure TAssistantTraceView.BindLiveBar;
Var
  ElapsedMs: Integer;
Begin
  EnsureLiveBar;
  If Not Assigned(FLivePanel) Then
    Exit;
  FLivePanel.Visible := FStreaming;
  If Not FStreaming Then
    Exit;
  ElapsedMs := 0;
  If FStreamStartedAt > 0 Then
    ElapsedMs := MilliSecondsBetween(Now, FStreamStartedAt);
  If Assigned(FLiveClock) Then
    FLiveClock.Text := 'Thinking… ' + FormatThinkingClock(ElapsedMs);
End;

Procedure TAssistantTraceView.EnsureFrame(Block: TTraceBlock);
Begin
  Case Block.Kind Of
    tbkUser: BindUser(Block);
    tbkThinking: BindThinking(Block);
    tbkTool: BindTool(Block);
    tbkAnswer: BindAnswer(Block);
    tbkSteer: BindRichCard(Block, clNavy);
    tbkNote: BindRichCard(Block, clMaroon);
  Else
    BindUser(Block);
  End;
End;

Procedure TAssistantTraceView.ScrollToEnd;
Var
  MaxPos: Integer;
Begin
  If Not Assigned(TraceScroll) Then
    Exit;
  If Assigned(TraceHost) Then
    Begin
      TraceHost.InvalidatePreferredSize;
      TraceHost.AdjustSize;
    End;
  MaxPos := TraceScroll.VertScrollBar.Range - TraceScroll.ClientHeight;
  If MaxPos < 0 Then
    MaxPos := 0;
  TraceScroll.VertScrollBar.Position := MaxPos;
End;

Procedure TAssistantTraceView.ResetFrames;
Var
  WasAuto: Boolean;
Begin
  If Assigned(FBoundTrace) Then
    FBoundTrace.NilFrames;
  FLivePanel := Nil;
  FLiveClock := Nil;
  If Not Assigned(TraceHost) Then
    Exit;
  WasAuto := TraceHost.AutoSize;
  TraceHost.AutoSize := False;
  TraceHost.ChildSizing.Layout := cclNone;
  Try
    While TraceHost.ControlCount > 0 Do
      TraceHost.Controls[0].Free;
  Finally
    ApplyVerticalStack(TraceHost, False);
    TraceHost.AutoSize := WasAuto;
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
  Empty := ((Not Assigned(Trace)) Or (Trace.Count = 0)) And (Not FStreaming);
  If Assigned(EmptyLabel) Then
    EmptyLabel.Visible := Empty;
  If Assigned(TraceScroll) Then
    TraceScroll.Visible := Not Empty;
  If Empty Then
    Exit;
  If Assigned(Trace) Then
    For I := 0 To Trace.Count - 1 Do
      Try
        EnsureFrame(Trace[I]);
      Except
      End;
  BindLiveBar;
  OrderFrames(Trace);
  If ScrollBottom Then
    ScrollToEnd;
End;

Procedure TAssistantTraceView.RefreshElapsed(Trace: TAssistantTrace);
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  If Assigned(Trace) Then
    Begin
      Trace.TickElapsed;
      For I := 0 To Trace.Count - 1 Do
        Begin
          Block := Trace[I];
          If Not Assigned(Block.Frame) Then
            Continue;
          If Block.Kind = tbkThinking Then
            BindThinking(Block)
          Else If Block.Kind = tbkTool Then
            BindTool(Block);
        End;
    End;
  If FStreaming Then
    BindLiveBar;
End;

Initialization

RegisterClass(TAssistantTraceView);

End.
