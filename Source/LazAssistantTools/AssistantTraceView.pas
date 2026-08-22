Unit AssistantTraceView;

{ Scrollable current-turn trace: user, thinking, tools, answer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, AssistantTrace;

Type
  TAssistantTraceView = Class(TFrame)
    TraceScroll: TScrollBox;
    TraceHost: TPanel;
    EmptyLabel: TLabel;
  Private
    FShowThinking: Boolean;
    FTruncatedLines: Integer;
    FBoundTrace: TAssistantTrace;
    Procedure SetShowThinking(Value: Boolean);
    Procedure ApplyVerticalStack(Host: TWinControl);
    Procedure InitHostedPanel(Panel: TPanel; AutoSizePanel: Boolean; FixedHeight: Integer);
    Function NamedChild(Host: TWinControl; Const ChildName: String): TControl;
    Function BlockForFrame(Frame: TObject): TTraceBlock;
    Procedure OrderFrames(Trace: TAssistantTrace);
    Procedure EnsureFrame(Block: TTraceBlock);
    Procedure BindThinking(Block: TTraceBlock);
    Procedure BindTool(Block: TTraceBlock);
    Procedure BindAnswer(Block: TTraceBlock);
    Procedure BindText(Block: TTraceBlock; Const TitleColor: TColor);
    Procedure HeaderClick(Sender: TObject);
    Function LastLines(Const SourceText: String; MaxLines: Integer): String;
    Procedure ScrollToEnd;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure ResetFrames;
    Procedure Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
    Procedure RefreshElapsed(Trace: TAssistantTrace);
    Property ShowThinking: Boolean Read FShowThinking Write SetShowThinking;
  End;

Implementation

{$R *.lfm}

Uses
  MarkDown.Control;

Const
  HeaderHeight = 26;
  ToolHeight = 30;
  TruncatedLineCount = 12;

Constructor TAssistantTraceView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alClient;
  FShowThinking := True;
  FTruncatedLines := TruncatedLineCount;
  FBoundTrace := Nil;
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
      ApplyVerticalStack(TraceHost);
    End;
  If Assigned(EmptyLabel) Then
    Begin
      EmptyLabel.Align := alClient;
      EmptyLabel.Alignment := taCenter;
      EmptyLabel.Layout := tlCenter;
    End;
End;

Procedure TAssistantTraceView.ApplyVerticalStack(Host: TWinControl);
Begin
  If Not Assigned(Host) Then
    Exit;
  { ControlsPerLine is per column when Layout is cclTopToBottomThenLeftToRight, so
    TTB+1 is a horizontal row. LTR+1 is one child per row (a vertical stack). }
  Host.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Host.ChildSizing.ControlsPerLine := 1;
  Host.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
  Host.ChildSizing.ShrinkHorizontal := crsHomogenousChildResize;
End;

Procedure TAssistantTraceView.InitHostedPanel(Panel: TPanel; AutoSizePanel: Boolean; FixedHeight: Integer);
Begin
  Panel.Parent := TraceHost;
  Panel.BevelOuter := bvNone;
  Panel.Align := alNone;
  { akRight takes a child out of ChildSizing and stacks every block at (0,0). }
  Panel.Anchors := [akLeft, akTop];
  Panel.BorderSpacing.Around := 2;
  Panel.ParentBackground := False;
  If AutoSizePanel Then
    Begin
      Panel.AutoSize := True;
      ApplyVerticalStack(Panel);
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

Function TAssistantTraceView.BlockForFrame(Frame: TObject): TTraceBlock;
Var
  I: Integer;
Begin
  Result := Nil;
  If (Not Assigned(FBoundTrace)) Or (Not Assigned(Frame)) Then
    Exit;
  For I := 0 To FBoundTrace.Count - 1 Do
    If FBoundTrace[I].Frame = Frame Then
      Begin
        Result := FBoundTrace[I];
        Exit;
      End;
End;

Procedure TAssistantTraceView.OrderFrames(Trace: TAssistantTrace);
Var
  I, Wanted: Integer;
  Hosted: TControl;
Begin
  If (Not Assigned(TraceHost)) Or (Not Assigned(Trace)) Then
    Exit;
  Wanted := 0;
  For I := 0 To Trace.Count - 1 Do
    Begin
      If Not Assigned(Trace[I].Frame) Then
        Continue;
      If Not (Trace[I].Frame Is TControl) Then
        Continue;
      Hosted := TControl(Trace[I].Frame);
      If Hosted.Parent <> TraceHost Then
        Continue;
      If (Wanted >= TraceHost.ControlCount) Or (TraceHost.Controls[Wanted] <> Hosted) Then
        Begin
          TraceHost.RemoveControl(Hosted);
          TraceHost.InsertControl(Hosted, Wanted);
        End;
      Inc(Wanted);
    End;
End;

Procedure TAssistantTraceView.SetShowThinking(Value: Boolean);
Begin
  If FShowThinking = Value Then
    Exit;
  FShowThinking := Value;
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

Procedure TAssistantTraceView.HeaderClick(Sender: TObject);
Var
  Block: TTraceBlock;
  Header: TControl;
Begin
  If Not (Sender Is TControl) Then
    Exit;
  Header := TControl(Sender);
  Block := BlockForFrame(Header.Parent);
  If Not Assigned(Block) Then
    Exit;
  If Block.Kind <> tbkThinking Then
    Exit;
  If Block.Running Then
    Exit;
  Block.Collapsed := Not Block.Collapsed;
  BindThinking(Block);
End;

Procedure TAssistantTraceView.BindText(Block: TTraceBlock; Const TitleColor: TColor);
Var
  Panel: TPanel;
  Title, Body: TLabel;
  Child: TControl;
Begin
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
      Body := TLabel.Create(Panel);
      Body.Parent := Panel;
      Body.Align := alNone;
      Body.Anchors := [akLeft, akTop];
      Body.WordWrap := True;
      Body.Name := 'BodyLabel';
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
  Child := NamedChild(Panel, 'BodyLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Body;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindThinking(Block: TTraceBlock);
Var
  Panel: TPanel;
  Header: TButton;
  Body: TLabel;
  Child: TControl;
  ShowBody: Boolean;
  Display: String;
Begin
  { Drop the old fixed-height TMemo layout if a previous build left one. }
  If Assigned(Block.Frame) And (Block.Frame Is TPanel) Then
    If NamedChild(TPanel(Block.Frame), 'BodyLabel') = Nil Then
      Begin
        TPanel(Block.Frame).Free;
        Block.Frame := Nil;
      End;
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Panel.Color := clForm;
      Header := TButton.Create(Panel);
      Header.Parent := Panel;
      Header.Align := alNone;
      Header.Anchors := [akLeft, akTop];
      Header.AutoSize := False;
      Header.Height := HeaderHeight;
      Header.Name := 'HeaderButton';
      Header.OnClick := @HeaderClick;
      Body := TLabel.Create(Panel);
      Body.Parent := Panel;
      Body.Align := alNone;
      Body.Anchors := [akLeft, akTop];
      Body.WordWrap := True;
      Body.AutoSize := True;
      Body.Name := 'BodyLabel';
      Body.Font.Style := [fsItalic];
      Body.Font.Color := clGrayText;
      Body.ShowAccelChar := False;
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
  Child := NamedChild(Panel, 'HeaderButton');
  If Child Is TButton Then
    TButton(Child).Caption := Block.Title;
  ShowBody := (FShowThinking And (Not Block.Collapsed)) Or Block.Running;
  If Block.Running Then
    Display := LastLines(Block.Body, FTruncatedLines)
  Else
    Display := Block.Body;
  Child := NamedChild(Panel, 'BodyLabel');
  If Child Is TLabel Then
    Begin
      Body := TLabel(Child);
      Body.Caption := Display;
      Body.Visible := ShowBody;
    End;
  Panel.Visible := FShowThinking Or Block.Running;
  If Assigned(TraceHost) And (TraceHost.ClientWidth > 32) Then
    Panel.Width := TraceHost.ClientWidth;
  Panel.AutoSize := True;
End;

Procedure TAssistantTraceView.BindTool(Block: TTraceBlock);
Var
  Panel: TPanel;
  Child: TControl;
  Status: String;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, False, ToolHeight);
      Panel.Color := clInfoBk;
      Child := TLabel.Create(Panel);
      Child.Parent := Panel;
      Child.Align := alClient;
      TLabel(Child).Layout := tlCenter;
      Child.Name := 'CaptionLabel';
      Child.BorderSpacing.Left := 8;
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
  Child := NamedChild(Panel, 'CaptionLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Block.Title;
  If Block.Running Or Block.Ok Then
    Status := FormatThoughtElapsed(Block.DurationMs)
  Else
    Status := 'failed';
  Child := NamedChild(Panel, 'StatusLabel');
  If Child Is TLabel Then
    TLabel(Child).Caption := Status;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindAnswer(Block: TTraceBlock);
Var
  Panel: TPanel;
  Title: TLabel;
  View: TMarkDownControl;
  Child: TControl;
  PrefW, PrefH: Integer;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      InitHostedPanel(Panel, True, 0);
      Title := TLabel.Create(Panel);
      Title.Parent := Panel;
      Title.Align := alNone;
      Title.Anchors := [akLeft, akTop];
      Title.Caption := 'Assistant';
      Title.Font.Style := [fsBold];
      Title.Name := 'TitleLabel';
      View := TMarkDownControl.Create(Panel);
      View.Parent := Panel;
      View.Align := alNone;
      View.Anchors := [akLeft, akTop];
      View.Name := 'AnswerView';
      { Nested AutoSize + CalcLayout AdjustSize AVs inside a ChildSizing host. }
      View.AutoSize := False;
      View.Color := clWindow;
      View.ParentColor := False;
      View.ParentBackground := False;
      View.ScrollBars := ssNone;
      View.MonoFontName := 'Monospace';
      View.BorderSpacing.Top := 4;
      Block.Frame := Panel;
    End
  Else If Block.Frame Is TPanel Then
    Panel := TPanel(Block.Frame)
  Else
    Exit;
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
        If Panel.ClientWidth > 0 Then
          View.Width := Panel.ClientWidth;
        View.CalcLayout;
        PrefW := 0;
        PrefH := 0;
        View.GetPreferredSize(PrefW, PrefH);
        If PrefH < 24 Then
          PrefH := 24;
        View.Height := PrefH;
      Except
        View.Height := 48;
      End;
    End;
  Panel.Visible := Block.Body <> '';
End;

Procedure TAssistantTraceView.EnsureFrame(Block: TTraceBlock);
Begin
  Case Block.Kind Of
    tbkThinking: BindThinking(Block);
    tbkTool: BindTool(Block);
    tbkAnswer: BindAnswer(Block);
    tbkSteer: BindText(Block, clNavy);
    tbkNote: BindText(Block, clMaroon);
  Else
    BindText(Block, clWindowText);
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
  { Range is the content height; the last valid thumb position is Range - page. }
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
  If Not Assigned(TraceHost) Then
    Exit;
  WasAuto := TraceHost.AutoSize;
  TraceHost.AutoSize := False;
  TraceHost.ChildSizing.Layout := cclNone;
  Try
    While TraceHost.ControlCount > 0 Do
      TraceHost.Controls[0].Free;
  Finally
    ApplyVerticalStack(TraceHost);
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
  Empty := (Not Assigned(Trace)) Or (Trace.Count = 0);
  If Assigned(EmptyLabel) Then
    EmptyLabel.Visible := Empty;
  If Assigned(TraceScroll) Then
    TraceScroll.Visible := Not Empty;
  If Empty Then
    Exit;
  For I := 0 To Trace.Count - 1 Do
    Try
      EnsureFrame(Trace[I]);
    Except
      { A single block must not take down the rest of the turn. }
    End;
  OrderFrames(Trace);
  If ScrollBottom Then
    ScrollToEnd;
End;

Procedure TAssistantTraceView.RefreshElapsed(Trace: TAssistantTrace);
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  If Not Assigned(Trace) Then
    Exit;
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

Initialization

RegisterClass(TAssistantTraceView);

End.
