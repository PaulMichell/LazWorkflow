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
    Procedure SetShowThinking(Value: Boolean);
    Procedure EnsureFrame(Block: TTraceBlock);
    Procedure BindThinking(Block: TTraceBlock);
    Procedure BindTool(Block: TTraceBlock);
    Procedure BindAnswer(Block: TTraceBlock);
    Procedure BindText(Block: TTraceBlock; Const TitleColor: TColor);
    Procedure HeaderClick(Sender: TObject);
    Function LastLines(Const Text: String; MaxLines: Integer): String;
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
  ThinkingStreamHeight = 148;
  HeaderHeight = 26;
  ToolHeight = 30;
  TruncatedLineCount = 12;

Constructor TAssistantTraceView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alClient;
  FShowThinking := True;
  FTruncatedLines := TruncatedLineCount;
  Color := clWindow;
  If Assigned(TraceScroll) Then
    Begin
      TraceScroll.Color := clWindow;
      TraceScroll.ParentBackground := False;
    End;
  If Assigned(TraceHost) Then
    Begin
      TraceHost.Color := clWindow;
      TraceHost.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
      TraceHost.ChildSizing.ShrinkHorizontal := crsHomogenousChildResize;
    End;
  If Assigned(EmptyLabel) Then
    Begin
      EmptyLabel.Align := alClient;
      EmptyLabel.Alignment := taCenter;
      EmptyLabel.Layout := tlCenter;
    End;
End;

Procedure TAssistantTraceView.SetShowThinking(Value: Boolean);
Begin
  If FShowThinking = Value Then
    Exit;
  FShowThinking := Value;
End;

Function TAssistantTraceView.LastLines(Const Text: String; MaxLines: Integer): String;
Var
  SL: TStringList;
  Start, I: Integer;
Begin
  Result := Text;
  If MaxLines < 1 Then
    Exit;
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
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
  If Not (TObject(Header.Tag) Is TTraceBlock) Then
    Exit;
  Block := TTraceBlock(Header.Tag);
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
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      Panel.Parent := TraceHost;
      Panel.BevelOuter := bvNone;
      Panel.AutoSize := True;
      Panel.Align := alNone;
      Panel.Anchors := [akLeft, akTop, akRight];
      Panel.BorderSpacing.Around := 2;
      Title := TLabel.Create(Panel);
      Title.Parent := Panel;
      Title.Align := alTop;
      Title.Font.Style := [fsBold];
      Title.Font.Color := TitleColor;
      Title.Name := 'TitleLabel';
      Body := TLabel.Create(Panel);
      Body.Parent := Panel;
      Body.Align := alTop;
      Body.WordWrap := True;
      Body.Name := 'BodyLabel';
      Block.Frame := Panel;
    End
  Else
    Panel := TPanel(Block.Frame);
  Title := TLabel(Panel.FindChildControl('TitleLabel'));
  Body := TLabel(Panel.FindChildControl('BodyLabel'));
  If Assigned(Title) Then
    Title.Caption := Block.Title;
  If Assigned(Body) Then
    Body.Caption := Block.Body;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindThinking(Block: TTraceBlock);
Var
  Panel: TPanel;
  Header: TButton;
  Body: TMemo;
  ShowBody: Boolean;
  Display: String;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      Panel.Parent := TraceHost;
      Panel.BevelOuter := bvNone;
      Panel.Align := alNone;
      Panel.Anchors := [akLeft, akTop, akRight];
      Panel.Height := ThinkingStreamHeight;
      Panel.BorderSpacing.Around := 2;
      Panel.Color := clForm;
      Panel.ParentBackground := False;
      Header := TButton.Create(Panel);
      Header.Parent := Panel;
      Header.Align := alTop;
      Header.Height := HeaderHeight;
      Header.Name := 'HeaderButton';
      Header.OnClick := @HeaderClick;
      Header.Tag := PtrInt(Block);
      Body := TMemo.Create(Panel);
      Body.Parent := Panel;
      Body.Align := alClient;
      Body.Name := 'BodyMemo';
      Body.ReadOnly := True;
      Body.ScrollBars := ssAutoVertical;
      Body.BorderStyle := bsNone;
      Body.Font.Style := [fsItalic];
      Body.Font.Color := clGrayText;
      Body.Color := clForm;
      Block.Frame := Panel;
    End
  Else
    Panel := TPanel(Block.Frame);
  Header := TButton(Panel.FindChildControl('HeaderButton'));
  Body := TMemo(Panel.FindChildControl('BodyMemo'));
  If Assigned(Header) Then
    Begin
      Header.Caption := Block.Title;
      Header.Tag := PtrInt(Block);
    End;
  ShowBody := FShowThinking And (Not Block.Collapsed);
  If Assigned(Body) Then
    Begin
      Body.Visible := ShowBody;
      If Block.Running Then
        Display := LastLines(Block.Body, FTruncatedLines)
      Else
        Display := Block.Body;
      If Body.Text <> Display Then
        Body.Text := Display;
    End;
  Panel.Visible := FShowThinking Or Block.Running;
  If Not Panel.Visible Then
    Exit;
  If ShowBody Then
    Panel.Height := ThinkingStreamHeight
  Else
    Panel.Height := HeaderHeight;
End;

Procedure TAssistantTraceView.BindTool(Block: TTraceBlock);
Var
  Panel: TPanel;
  CaptionLabel, StatusLabel: TLabel;
  Status: String;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      Panel.Parent := TraceHost;
      Panel.BevelOuter := bvNone;
      Panel.Align := alNone;
      Panel.Anchors := [akLeft, akTop, akRight];
      Panel.Height := ToolHeight;
      Panel.BorderSpacing.Around := 2;
      Panel.Color := clInfoBk;
      Panel.ParentBackground := False;
      CaptionLabel := TLabel.Create(Panel);
      CaptionLabel.Parent := Panel;
      CaptionLabel.Align := alClient;
      CaptionLabel.Layout := tlCenter;
      CaptionLabel.Name := 'CaptionLabel';
      CaptionLabel.BorderSpacing.Left := 8;
      StatusLabel := TLabel.Create(Panel);
      StatusLabel.Parent := Panel;
      StatusLabel.Align := alRight;
      StatusLabel.Layout := tlCenter;
      StatusLabel.Name := 'StatusLabel';
      StatusLabel.BorderSpacing.Right := 8;
      StatusLabel.Font.Color := clGrayText;
      Block.Frame := Panel;
    End
  Else
    Panel := TPanel(Block.Frame);
  CaptionLabel := TLabel(Panel.FindChildControl('CaptionLabel'));
  StatusLabel := TLabel(Panel.FindChildControl('StatusLabel'));
  If Assigned(CaptionLabel) Then
    CaptionLabel.Caption := Block.Title;
  If Block.Running Then
    Status := FormatThoughtElapsed(Block.DurationMs)
  Else If Block.Ok Then
    Status := FormatThoughtElapsed(Block.DurationMs)
  Else
    Status := 'failed';
  If Assigned(StatusLabel) Then
    StatusLabel.Caption := Status;
  Panel.Visible := True;
End;

Procedure TAssistantTraceView.BindAnswer(Block: TTraceBlock);
Var
  Panel: TPanel;
  Title: TLabel;
  View: TMarkDownControl;
Begin
  If Not Assigned(Block.Frame) Then
    Begin
      Panel := TPanel.Create(Self);
      Panel.Parent := TraceHost;
      Panel.BevelOuter := bvNone;
      Panel.Align := alNone;
      Panel.Anchors := [akLeft, akTop, akRight];
      Panel.AutoSize := True;
      Panel.BorderSpacing.Around := 2;
      Title := TLabel.Create(Panel);
      Title.Parent := Panel;
      Title.Align := alTop;
      Title.Caption := 'Assistant';
      Title.Font.Style := [fsBold];
      Title.Name := 'TitleLabel';
      View := TMarkDownControl.Create(Panel);
      View.Parent := Panel;
      View.Align := alTop;
      View.Name := 'AnswerView';
      View.AutoSize := True;
      View.Color := clWindow;
      View.ParentColor := False;
      View.ParentBackground := False;
      View.ScrollBars := ssNone;
      View.MonoFontName := 'Monospace';
      View.BorderSpacing.Top := 4;
      Block.Frame := Panel;
    End
  Else
    Panel := TPanel(Block.Frame);
  View := TMarkDownControl(Panel.FindChildControl('AnswerView'));
  If Assigned(View) And (View.MarkDown.Text <> Block.Body) Then
    Begin
      View.MarkDown.BeginUpdate;
      Try
        View.MarkDown.Text := Block.Body;
      Finally
        View.MarkDown.EndUpdate;
      End;
      View.CalcLayout;
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
Begin
  If Assigned(TraceScroll) Then
    TraceScroll.VertScrollBar.Position := TraceScroll.VertScrollBar.Range;
End;

Procedure TAssistantTraceView.ResetFrames;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  While TraceHost.ControlCount > 0 Do
    TraceHost.Controls[0].Free;
End;

Procedure TAssistantTraceView.Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
Var
  I: Integer;
  Empty: Boolean;
Begin
  If Not Assigned(TraceHost) Then
    Exit;
  Empty := (Not Assigned(Trace)) Or (Trace.Count = 0);
  If Assigned(EmptyLabel) Then
    EmptyLabel.Visible := Empty;
  If Assigned(TraceScroll) Then
    TraceScroll.Visible := Not Empty;
  If Empty Then
    Exit;
  For I := 0 To Trace.Count - 1 Do
    EnsureFrame(Trace[I]);
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
