Unit AssistantConversationSurface;

{ One canvas, one logical scroll extent and cross-section text selection. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Types, Controls, ExtCtrls, Menus, LMessages, StyledSurface,
  StyledTextTypes, AssistantTrace, AssistantConversationLayout;

Type
  TConversationPosition = Record
    Key: String;
    Text: TStyledPosition;
  End;
  TConversationAnchor = Record
    Key: String;
    Text: TStyledPosition;
    Offset: Int64;
    TextAnchor: Boolean;
    Index: Integer;
  End;
  TConversationViewState = Class
  Public
    Anchor: TConversationAnchor;
    FollowTail: Boolean;
  End;
  TAssistantConversationSurface = Class(TStyledSurface)
  Private
    FLayout: TConversationLayout;
    Timer: TTimer;
    FShowThinking, FShowTools, FFollowTail, FUpdating, Selecting, FInTick: Boolean;
    SelectionStart, SelectionEnd: TConversationPosition;
    SavedAnchor, PendingAnchor: TConversationAnchor;
    HasPendingAnchor: Boolean;
    FocusedKey: String;
    PointerPosition: TPoint;
    BackgroundIndex: Integer;
    FLayoutRevision, FPaintRevision, FMaxUpdateMilliseconds: QWord;
    Procedure GetDialogCode(Var Message: TLMGetDlgCode); Message LM_GETDLGCODE;
    Procedure Tick(Sender: TObject);
    Procedure LeaveConversation(ForwardDirection: Boolean);
    Procedure MenuClick(Sender: TObject);
    Procedure PrepareViewport;
    Procedure RestoreAnchor(Const Anchor: TConversationAnchor);
    Function CaptureAnchor: TConversationAnchor;
    Function HitPosition(X, Y: Integer): TConversationPosition;
    Function Compare(Const A, B: TConversationPosition): Integer;
    Procedure SetFilters(Thinking, Tools: Boolean);
    Procedure SetShowThinking(Value: Boolean);
    Procedure SetShowTools(Value: Boolean);
    Function GetSelectedText: String;
    Procedure SelectionBounds(Out First, Last: TConversationPosition);
  Protected
    Procedure PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64); Override;
    Procedure GeometryChanged; Override;
    Procedure Scrolled; Override;
    Function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePosition: TPoint): Boolean; Override;
    Procedure KeyDown(Var Key: Word; Shift: TShiftState); Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseMove(Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure DblClick; Override;
  Public
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    Function SaveViewState: TConversationViewState;
    Procedure RestoreViewState(State: TConversationViewState);
    Procedure BeginDocument;
    Procedure AddBlock(Const Key: String; Block: TTraceBlock);
    Procedure EndDocument;
    Procedure Clear;
    Procedure JumpToEnd;
    Procedure JumpToStart;
    Procedure NavigateTo(Const Key: String);
    Procedure Toggle(Index: Integer);
    Procedure CompleteLayout;
    Procedure SelectAll;
    Procedure SelectRange(Const First, Last: TConversationPosition);
    Procedure SelectWord;
    Procedure SelectLine;
    Procedure ClearSelection;
    Function MarkdownText: String;
    Property Layout: TConversationLayout Read FLayout;
    Property FollowTail: Boolean Read FFollowTail;
    Property SelectedText: String Read GetSelectedText;
    Property ShowThinking: Boolean Read FShowThinking Write SetShowThinking;
    Property ShowToolUse: Boolean Read FShowTools Write SetShowTools;
    Property MaxUpdateMilliseconds: QWord Read FMaxUpdateMilliseconds;
    Property LayoutRevision: QWord Read FLayoutRevision;
    Property PaintRevision: QWord Read FPaintRevision;
  End;

Implementation

Uses
  Math, Graphics, Clipbrd, LCLType, Forms, StyledCanvas, StyledTextDocument;

Constructor TAssistantConversationSurface.Create(AOwner: TComponent);
Var
  Item: TMenuItem;
  I: Integer;
Const
  Captions: Array[0..5] Of String = ('Copy', 'Copy Markdown', 'Select word', 'Select line', 'Select all', 'Jump to latest');
Begin
  Inherited Create(AOwner);
  FFollowTail := True;
  FShowThinking := True;
  FShowTools := True;
  Font.Size := 10;
  FLayout := TConversationLayout.Create(Renderer);
  Timer := TTimer.Create(Self);
  Timer.Interval := 20;
  Timer.Enabled := False;
  Timer.OnTimer := @Tick;
  PopupMenu := TPopupMenu.Create(Self);
  For I := 0 To High(Captions) Do
    Begin
      Item := TMenuItem.Create(PopupMenu);
      Item.Caption := Captions[I];
      Item.Tag := I;
      Item.OnClick := @MenuClick;
      PopupMenu.Items.Add(Item);
    End;
  SetScrollbars(True, False);
  AccessibleName := 'Assistant conversation';
End;

Destructor TAssistantConversationSurface.Destroy;
Begin
  If Assigned(Timer) Then Timer.Enabled := False;
  FreeAndNil(FLayout);
  Inherited Destroy;
End;

Procedure TAssistantConversationSurface.Clear;
Begin
  Timer.Enabled := False;
  HasPendingAnchor := False;
  FLayout.Clear;
  BackgroundIndex := 0;
  ClearSelection;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, 0);
    ScrollTop := 0;
  Finally
    FUpdating := False;
  End;
  FFollowTail := True;
  Inc(FLayoutRevision);
  Invalidate;
End;

Function TAssistantConversationSurface.SaveViewState: TConversationViewState;
Begin
  Result := TConversationViewState.Create;
  Result.Anchor := CaptureAnchor;
  Result.FollowTail := FFollowTail;
End;

Procedure TAssistantConversationSurface.RestoreViewState(State: TConversationViewState);
Begin
  If Not Assigned(State) Then Exit;
  HasPendingAnchor := False;
  FFollowTail := State.FollowTail;
  FUpdating := True;
  Try
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(State.Anchor);
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
  Invalidate;
End;

Procedure TAssistantConversationSurface.BeginDocument;
Begin
  SavedAnchor := CaptureAnchor;
  FLayout.BeginSync;
End;

Procedure TAssistantConversationSurface.AddBlock(Const Key: String; Block: TTraceBlock);
Begin
  FLayout.Add(Key, Block);
End;

Procedure TAssistantConversationSurface.EndDocument;
Begin
  FLayout.EndSync;
  ConfigureCanvas;
  FLayout.Configure(ViewRect.Width, Max(10, Font.Size), FShowThinking, FShowTools, Font.PixelsPerInch);
  BackgroundIndex := 0;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(SavedAnchor);
  Finally
    FUpdating := False;
  End;
  If (FLayout.IndexOf(SelectionStart.Key) < 0) Or (FLayout.IndexOf(SelectionEnd.Key) < 0) Then ClearSelection;
  PrepareViewport;
  Timer.Enabled := FLayout.Count > 0;
  Invalidate;
End;

Function TAssistantConversationSurface.CaptureAnchor: TConversationAnchor;
Var
  I, P, L: Integer;
  Fragment: TConversationFragment;
  LocalY: Int64;
Begin
  If HasPendingAnchor Then Exit(PendingAnchor);
  Result := Default(TConversationAnchor);
  Result.Index := -1;
  If Not Assigned(FLayout) Then Exit;
  I := FLayout.AtY(ScrollTop);
  If I < 0 Then Exit;
  Result.Index := I;
  Result.Key := FLayout[I].Key;
  LocalY := ScrollTop - FLayout.Top(I);
  Result.Offset := LocalY;
  Fragment := FLayout[I].Fragment;
  If Not Assigned(Fragment) Then Exit;
  Dec(LocalY, FLayout[I].Padding);
  P := ItemAtHeight(Fragment.Layout.Heights, Max(Int64(0), LocalY));
  If Not Assigned(Fragment.Layout.Paragraphs[P]) Then Exit;
  L := Fragment.Layout.Paragraphs[P].LineAtY(LocalY - Fragment.Layout.TextTop(P));
  If L < 0 Then Exit;
  Result.Text := StyledPosition(P, Fragment.Layout.Paragraphs[P].Lines[L].Start);
  Result.Offset := LocalY - Fragment.Layout.TextTop(P) - Fragment.Layout.Paragraphs[P].Lines[L].Top;
  Result.TextAnchor := True;
End;

Procedure TAssistantConversationSurface.RestoreAnchor(Const Anchor: TConversationAnchor);
Var
  I, P, L: Integer;
  LocalY: Int64;
  Fragment: TConversationFragment;
Begin
  HasPendingAnchor := False;
  I := FLayout.IndexOf(Anchor.Key);
  If (I < 0) Or Not FLayout[I].Visible Then
    Begin
      I := Max(0, Anchor.Index);
      While (I < FLayout.Count) And Not FLayout[I].Visible Do Inc(I);
      If I >= FLayout.Count Then
        Begin
          I := Min(Anchor.Index, FLayout.Count - 1);
          While (I >= 0) And Not FLayout[I].Visible Do Dec(I);
        End;
      If I < 0 Then
        Begin
          ScrollTop := 0;
          Exit;
        End;
      ScrollTop := FLayout.Top(I);
      Exit;
    End;
  LocalY := Anchor.Offset;
  Fragment := FLayout[I].Fragment;
  If Anchor.TextAnchor And Not Assigned(Fragment) Then
    Begin
      FLayout.PrepareSection(I, 0, 0);
      Fragment := FLayout[I].Fragment;
    End;
  If Anchor.TextAnchor And Assigned(Fragment) Then
    Begin
      P := EnsureRange(Anchor.Text.Paragraph, 0, Fragment.Document.Count - 1);
      { A large paragraph may have only its first lines measured. Do not
        replace the requested text position with that temporary last line. }
      If Not FLayout.PreparePosition(I, Anchor.Text) Then
        Begin
          PendingAnchor := Anchor;
          HasPendingAnchor := True;
          FLayout.Reindex;
          SetExtent(ViewRect.Width, FLayout.TotalHeight);
          Exit;
        End;
      If FLayout[I].Collapsed Then FLayout[I].ShortHeight := Fragment.Height
      Else FLayout[I].FullHeight := Fragment.Height;
      FLayout.Reindex;
      SetExtent(ViewRect.Width, FLayout.TotalHeight);
      If Assigned(Fragment.Layout.Paragraphs[P]) Then
        Begin
          L := Fragment.Layout.Paragraphs[P].LineAtOffset(Anchor.Text.Offset);
          If L >= 0 Then LocalY := FLayout[I].Padding + Fragment.Layout.TextTop(P) + Fragment.Layout.Paragraphs[P].Lines[L].Top + Anchor.Offset;
        End;
    End;
  ScrollTop := FLayout.Top(I) + Max(Int64(0), Min(LocalY, FLayout.Heights.Values[I] - 1));
End;

Procedure TAssistantConversationSurface.PrepareViewport;
Var
  Anchor: TConversationAnchor;
  I, First, Last, Pass: Integer;
  LocalTop: Int64;
Begin
  If FUpdating Or Not Assigned(FLayout) Then Exit;
  If Not FInTick Then FLayout.BeginWorkSlice;
  FUpdating := True;
  Try
    Anchor := CaptureAnchor;
    { A measurement can move a block across the viewport. Republish before
      looking up its neighbors; painting itself never changes these heights. }
    For Pass := 1 To 2 Do
      Begin
        First := FLayout.AtY(ScrollTop);
        Last := First;
        I := First;
        While (I >= 0) And (I < FLayout.Count) And (FLayout.Top(I) < ScrollTop + ViewRect.Height + 200) Do
          Begin
            If FLayout[I].Visible Then
              Begin
                LocalTop := ScrollTop - FLayout.Top(I);
                FLayout.PrepareSection(I, LocalTop, LocalTop + ViewRect.Height + 200);
                Last := I;
              End;
            Inc(I);
          End;
        FLayout.Reindex;
        SetExtent(ViewRect.Width, FLayout.TotalHeight);
        If FFollowTail Then ScrollToEnd
        Else RestoreAnchor(Anchor);
      End;
    FLayout.TrimDrawings(First, Last, ScrollTop, ScrollTop + ViewRect.Height);
    Inc(FLayoutRevision);
  Finally
    FUpdating := False;
  End;
  If Assigned(Timer) And Not FInTick And (FLayout.PendingWork Or FLayout.LayoutIncomplete) Then Timer.Enabled := True;
End;

Procedure TAssistantConversationSurface.Tick(Sender: TObject);
Var
  Deadline, Started: QWord;
  Anchor: TConversationAnchor;
Begin
  If FUpdating Or (csDestroying In ComponentState) Then Exit;
  Started := GetTickCount64;
  Timer.Enabled := False;
  FInTick := True;
  FLayout.BeginWorkSlice;
  Try
    If Selecting Then
      Begin
        If PointerPosition.Y < ViewRect.Top Then ScrollTop := ScrollTop - 20
        Else If PointerPosition.Y > ViewRect.Bottom Then ScrollTop := ScrollTop + 20;
        SelectionEnd := HitPosition(PointerPosition.X, EnsureRange(PointerPosition.Y, ViewRect.Top, ViewRect.Bottom - 1));
      End;
    PrepareViewport;
    Anchor := CaptureAnchor;
    Deadline := GetTickCount64 + 8;
    { Viewport preparation and reindexing can consume the previous slice on a
    large history. Give offscreen measurement its own bounded slice so it
    cannot be starved indefinitely by the visible content. }
    FLayout.BeginWorkSlice;
    While (BackgroundIndex < FLayout.Count) And (GetTickCount64 < Deadline) Do
      Begin
        If FLayout.PrepareSection(BackgroundIndex, 0, 0) Then Inc(BackgroundIndex)
        Else Break;
      End;
    FLayout.Reindex;
    FUpdating := True;
    Try
      SetExtent(ViewRect.Width, FLayout.TotalHeight);
      If FFollowTail Then ScrollToEnd
      Else RestoreAnchor(Anchor);
    Finally
      FUpdating := False;
    End;
    PrepareViewport;
    Invalidate;
  Finally
    FInTick := False;
    FMaxUpdateMilliseconds := Max(FMaxUpdateMilliseconds, GetTickCount64 - Started);
    { Rearm after work completes. A periodic timer shorter than a large update
      can otherwise keep the GTK event pump busy until all history is measured. }
    Timer.Enabled := Selecting Or (BackgroundIndex < FLayout.Count) Or FLayout.PendingWork Or FLayout.LayoutIncomplete;
  End;
End;

Procedure TAssistantConversationSurface.CompleteLayout;
Var
  I: Integer;
  Anchor: TConversationAnchor;
Begin
  Anchor := CaptureAnchor;
  For I := 0 To FLayout.Count - 1 Do FLayout.PrepareSection(I, 0, High(Int64), True);
  FLayout.Reindex;
  BackgroundIndex := FLayout.Count;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(Anchor);
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
  Invalidate;
End;

Procedure TAssistantConversationSurface.GeometryChanged;
Var
  Anchor: TConversationAnchor;
Begin
  If Not Assigned(FLayout) Or FUpdating Then Exit;
  Anchor := CaptureAnchor;
  ConfigureCanvas;
  FLayout.Configure(ViewRect.Width, Max(10, Font.Size), FShowThinking, FShowTools, Font.PixelsPerInch);
  BackgroundIndex := 0;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(Anchor);
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
  Timer.Enabled := FLayout.Count > 0;
End;

Procedure TAssistantConversationSurface.Scrolled;
Begin
  If FUpdating Then Exit;
  HasPendingAnchor := False;
  FFollowTail := Not Selecting And (ScrollTop >= Max(Int64(0), ContentHeight - ViewRect.Height) - 3);
  PrepareViewport;
End;

Function TAssistantConversationSurface.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
    MousePosition: TPoint): Boolean;
Begin
  HasPendingAnchor := False;
  Result := Inherited DoMouseWheel(Shift, WheelDelta, MousePosition);
End;

Procedure TAssistantConversationSurface.JumpToEnd;
Begin
  HasPendingAnchor := False;
  FFollowTail := True;
  FUpdating := True;
  Try
    ScrollToEnd;
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
  Invalidate;
End;

Procedure TAssistantConversationSurface.JumpToStart;
Begin
  HasPendingAnchor := False;
  FFollowTail := False;
  ScrollTop := 0;
  FFollowTail := False;
  PrepareViewport;
  Invalidate;
End;

Procedure TAssistantConversationSurface.NavigateTo(Const Key: String);
Var
  I: Integer;
Begin
  I := FLayout.IndexOf(Key);
  If I < 0 Then Exit;
  HasPendingAnchor := False;
  FFollowTail := False;
  FUpdating := True;
  Try
    ScrollTop := FLayout.Top(I);
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
  Invalidate;
End;

Procedure TAssistantConversationSurface.SetFilters(Thinking, Tools: Boolean);
Var
  Anchor: TConversationAnchor;
Begin
  If (Thinking = FShowThinking) And (Tools = FShowTools) Then Exit;
  Anchor := CaptureAnchor;
  ClearSelection;
  FShowThinking := Thinking;
  FShowTools := Tools;
  FLayout.Configure(ViewRect.Width, Max(10, Font.Size), Thinking, Tools, Font.PixelsPerInch);
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(Anchor);
  Finally
    FUpdating := False;
  End;
  BackgroundIndex := 0;
  PrepareViewport;
  Timer.Enabled := True;
  Invalidate;
End;

Procedure TAssistantConversationSurface.SetShowThinking(Value: Boolean);
Begin
  SetFilters(Value, FShowTools);
End;

Procedure TAssistantConversationSurface.SetShowTools(Value: Boolean);
Begin
  SetFilters(FShowThinking, Value);
End;

Procedure TAssistantConversationSurface.Toggle(Index: Integer);
Var
  Anchor: TConversationAnchor;
Begin
  If (Index < 0) Or (Index >= FLayout.Count) Or Not (FLayout[Index].Kind In [tbkThinking, tbkTool, tbkSubagent]) Then Exit;
  Anchor := CaptureAnchor;
  ClearSelection;
  FLayout[Index].Collapsed := Not FLayout[Index].Collapsed;
  FLayout[Index].UserCollapsed := True;
  FLayout.PrepareSection(Index, 0, ViewRect.Height);
  FLayout.Reindex;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(Anchor);
  Finally
    FUpdating := False;
  End;
  BackgroundIndex := Min(BackgroundIndex, Index);
  PrepareViewport;
  Timer.Enabled := True;
  Invalidate;
End;

Procedure TAssistantConversationSurface.PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64);
Var
  I, A, B: Integer;
  Fragment: TConversationFragment;
  First, Last: TConversationPosition;
  StartPos, EndPos: TStyledPosition;
  Selected: Boolean;
  Style: TStyledBoxStyle;
  SectionHeight: Int64;
Begin
  FPaintRevision := FLayoutRevision;
  If FLayout.TotalHeight = 0 Then
    Begin
      BufferCanvas.Font.Assign(Font);
      BufferCanvas.Font.Color := clGrayText;
      BufferCanvas.TextOut(OriginX + 6, Clip.Top + 6, 'Type a message below to start.');
      Exit;
    End;
  SelectionBounds(First, Last);
  A := FLayout.IndexOf(First.Key);
  B := FLayout.IndexOf(Last.Key);
  I := FLayout.AtY(Clip.Top - OriginY);
  While (I >= 0) And (I < FLayout.Count) And (OriginY + FLayout.Top(I) < Clip.Bottom) Do
    Begin
      Fragment := FLayout[I].Fragment;
      If FLayout[I].Visible And Assigned(Fragment) Then
        Begin
          If FLayout[I].Kind In [tbkUser, tbkAnswer] Then
            Begin
              Style := DefaultStyledBoxStyle;
              Style.CornerRadius := Scale96ToFont(12);
              Style.BorderWidth := 1;
              If FLayout[I].Kind = tbkUser Then
                Begin
                  Style.Background := $EFF8E5;
                  Style.BorderColor := $D5E4C5;
                End
              Else
                Begin
                  Style.Background := $F7F7F7;
                  Style.BorderColor := $E4E4E4;
                End;
              SectionHeight := Fragment.Height + FLayout[I].Padding * 2;
              Renderer.DrawBoxFrame(GetStyledBoxGeometry(OriginX + FLayout[I].Left,
                OriginY + FLayout.Top(I), FLayout[I].OuterWidth, SectionHeight, Style), Style, Clip);
            End;
          Selected := (A >= 0) And (B >= 0) And (I >= A) And (I <= B) And (Compare(First, Last) <> 0);
          StartPos := StyledPosition(0, 0);
          EndPos := Fragment.Document.EndPosition;
          If I = A Then StartPos := Fragment.Document.Clamp(First.Text);
          If I = B Then EndPos := Fragment.Document.Clamp(Last.Text);
          Fragment.Layout.Paint(Clip, OriginX + FLayout[I].Left + FLayout[I].Padding, OriginY + FLayout.Top(I) + FLayout[I].Padding, StartPos, EndPos, Selected, False);
          If Focused And (FocusedKey = FLayout[I].Key) Then
            Begin
              Style := DefaultStyledBoxStyle;
              Style.BorderWidth := 1;
              Style.BorderColor := clHighlight;
              If FLayout[I].Kind In [tbkUser, tbkAnswer] Then Style.CornerRadius := Scale96ToFont(12);
              SectionHeight := Fragment.Height + FLayout[I].Padding * 2;
              Renderer.DrawBoxFrame(GetStyledBoxGeometry(OriginX + FLayout[I].Left,
                OriginY + FLayout.Top(I), FLayout[I].OuterWidth, SectionHeight, Style), Style, Clip);
            End;
        End;
      Inc(I);
    End;
End;

Function TAssistantConversationSurface.HitPosition(X, Y: Integer): TConversationPosition;
Var
  I, P: Integer;
  LocalY: Int64;
  Fragment: TConversationFragment;
  Trailing: Boolean;
Begin
  Result := Default(TConversationPosition);
  PrepareViewport;
  I := FLayout.AtY(Int64(Y) - ViewRect.Top + ScrollTop);
  If I < 0 Then Exit;
  Result.Key := FLayout[I].Key;
  Fragment := FLayout[I].Fragment;
  If Not Assigned(Fragment) Then Exit;
  LocalY := Int64(Y) - ViewRect.Top + ScrollTop - FLayout.Top(I) - FLayout[I].Padding;
  P := ItemAtHeight(Fragment.Layout.Heights, LocalY);
  Result.Text := StyledPosition(P, 0);
  If Not Assigned(Fragment.Layout.Paragraphs[P]) Then Exit;
  Result.Text.Offset := Renderer.HitTest(Fragment.Layout.Paragraphs[P], X - ViewRect.Left - FLayout[I].Left - FLayout[I].Padding - Fragment.Layout.TextLeft(P),
    LocalY - Fragment.Layout.TextTop(P), Trailing);
  Result.Text.Trailing := Trailing;
  Result.Text := Fragment.Document.Clamp(Result.Text);
End;

Function TAssistantConversationSurface.Compare(Const A, B: TConversationPosition): Integer;
Begin
  Result := FLayout.IndexOf(A.Key) - FLayout.IndexOf(B.Key);
  If Result = 0 Then Result := ComparePositions(A.Text, B.Text);
End;

Procedure TAssistantConversationSurface.SelectionBounds(Out First, Last: TConversationPosition);
Begin
  First := SelectionStart;
  Last := SelectionEnd;
  If Compare(First, Last) > 0 Then
    Begin
      First := SelectionEnd;
      Last := SelectionStart;
    End;
End;

Procedure TAssistantConversationSurface.SelectRange(Const First, Last: TConversationPosition);
Begin
  SelectionStart := First;
  SelectionEnd := Last;
  Invalidate;
End;

Procedure TAssistantConversationSurface.ClearSelection;
Begin
  SelectionStart := Default(TConversationPosition);
  SelectionEnd := SelectionStart;
  Invalidate;
End;

Procedure TAssistantConversationSurface.SelectAll;
Var
  I: Integer;
Begin
  ClearSelection;
  For I := 0 To FLayout.Count - 1 Do
    If FLayout[I].Visible Then
      Begin
        If SelectionStart.Key = '' Then
          Begin
            SelectionStart.Key := FLayout[I].Key;
            SelectionStart.Text := StyledPosition(0, 0);
          End;
        SelectionEnd.Key := FLayout[I].Key;
        SelectionEnd.Text := StyledPosition(High(Integer), High(Integer));
      End;
  Invalidate;
End;

Function TAssistantConversationSurface.GetSelectedText: String;
Var
  First, Last: TConversationPosition;
  Anchor: TConversationAnchor;
  A, B, I: Integer;
  Fragment: TConversationFragment;
  StartPos, EndPos: TStyledPosition;
Begin
  Anchor := CaptureAnchor;
  Result := '';
  SelectionBounds(First, Last);
  A := FLayout.IndexOf(First.Key);
  B := FLayout.IndexOf(Last.Key);
  If (A < 0) Or (B < 0) Or (Compare(First, Last) = 0) Then Exit;
  For I := A To B Do If FLayout[I].Visible Then
    Begin
      FLayout.PrepareSection(I, 0, 0);
      Fragment := FLayout[I].Fragment;
      StartPos := StyledPosition(0, 0);
      EndPos := Fragment.Document.EndPosition;
      If I = A Then StartPos := Fragment.Document.Clamp(First.Text);
      If I = B Then EndPos := Fragment.Document.Clamp(Last.Text);
      If Result <> '' Then Result += LineEnding + LineEnding;
      Result += StyledContentText(Fragment.Document.Extract(StartPos, EndPos));
    End;
  FLayout.Reindex;
  FUpdating := True;
  Try
    SetExtent(ViewRect.Width, FLayout.TotalHeight);
    If FFollowTail Then ScrollToEnd
    Else RestoreAnchor(Anchor);
  Finally
    FUpdating := False;
  End;
  PrepareViewport;
End;

Function TAssistantConversationSurface.MarkdownText: String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 0 To FLayout.Count - 1 Do
    Begin
      If Result <> '' Then Result += LineEnding + LineEnding;
      Result += '### ' + FLayout[I].Title + LineEnding + LineEnding + FLayout[I].Body;
      If FLayout[I].Footer <> '' Then Result += LineEnding + LineEnding + '*' + FLayout[I].Footer + '*';
    End;
End;

Procedure TAssistantConversationSurface.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Var
  I: Integer;
  Position: TConversationPosition;
Begin
  Inherited MouseDown(Button, Shift, X, Y);
  PointerPosition := Point(X, Y);
  If CanFocus Then SetFocus;
  If Button <> mbLeft Then Exit;
  HasPendingAnchor := False;
  Position := HitPosition(X, Y);
  I := FLayout.IndexOf(Position.Key);
  FocusedKey := Position.Key;
  If (Position.Text.Paragraph = 0) And (I >= 0) And (X < ViewRect.Left + Scale96ToFont(24)) Then
    Begin
      Toggle(I);
      Exit;
    End;
  If Not (ssShift In Shift) Then SelectionStart := Position;
  SelectionEnd := Position;
  Selecting := True;
  MouseCapture := True;
  FFollowTail := False;
  Timer.Enabled := True;
  Invalidate;
End;

Procedure TAssistantConversationSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseMove(Shift, X, Y);
  PointerPosition := Point(X, Y);
  If Selecting Then
    Begin
      SelectionEnd := HitPosition(X, Y);
      Invalidate;
    End;
End;

Procedure TAssistantConversationSurface.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseUp(Button, Shift, X, Y);
  If Button = mbLeft Then
    Begin
      Selecting := False;
      MouseCapture := False;
    End;
End;

Procedure TAssistantConversationSurface.SelectWord;
Var
  Position: TConversationPosition;
  I, L, R: Integer;
  LineText: String;
  Fragment: TConversationFragment;
Begin
  Position := HitPosition(PointerPosition.X, PointerPosition.Y);
  I := FLayout.IndexOf(Position.Key);
  If I < 0 Then Exit;
  Fragment := FLayout[I].Fragment;
  If Not Assigned(Fragment) Then Exit;
  LineText := Fragment.Document[Position.Text.Paragraph]^.Text;
  L := Position.Text.Offset;
  R := L;
  While (L > 0) And Not IsWordSeparator(LineText, PreviousCodepoint(LineText, L)) Do L := PreviousCodepoint(LineText, L);
  While (R < Length(LineText)) And Not IsWordSeparator(LineText, R) Do R := NextCodepoint(LineText, R);
  SelectionStart := Position;
  SelectionStart.Text.Offset := L;
  SelectionEnd := Position;
  SelectionEnd.Text.Offset := R;
  Invalidate;
End;

Procedure TAssistantConversationSurface.SelectLine;
Var
  Position: TConversationPosition;
  I, L: Integer;
  Fragment: TConversationFragment;
  TextLayout: TStyledLayout;
Begin
  Position := HitPosition(PointerPosition.X, PointerPosition.Y);
  I := FLayout.IndexOf(Position.Key);
  If I < 0 Then Exit;
  Fragment := FLayout[I].Fragment;
  If Not Assigned(Fragment) Then Exit;
  TextLayout := Fragment.Layout.Paragraphs[Position.Text.Paragraph];
  If Not Assigned(TextLayout) Then Exit;
  L := TextLayout.LineAtOffset(Position.Text.Offset);
  If L < 0 Then Exit;
  SelectionStart := Position;
  SelectionEnd := Position;
  SelectionStart.Text.Offset := TextLayout.Lines[L].Start;
  SelectionEnd.Text.Offset := TextLayout.Lines[L].Finish;
  Invalidate;
End;

Procedure TAssistantConversationSurface.DblClick;
Begin
  Inherited DblClick;
  Selecting := False;
  MouseCapture := False;
  SelectWord;
End;

Procedure TAssistantConversationSurface.GetDialogCode(Var Message: TLMGetDlgCode);
Begin
  Message.Result := DLGC_WANTARROWS Or DLGC_WANTCHARS Or DLGC_WANTALLKEYS Or DLGC_WANTTAB;
End;

Procedure TAssistantConversationSurface.LeaveConversation(ForwardDirection: Boolean);
Var
  Form: TCustomForm;
Begin
  { The trace frame contains only this surface. Search the form's full tab
    order so leaving the last item does not wrap back into the same control. }
  Form := GetParentForm(Self);
  If Assigned(Form) Then Form.SelectNext(Self, ForwardDirection, True);
End;

Procedure TAssistantConversationSurface.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  I: Integer;
Begin
  If ssCtrl In Shift Then
    Case Key Of VK_A:
    Begin
      SelectAll;
      Key := 0;
    End;
      VK_C:
      Begin
        Clipboard.AsText := SelectedText;
        Key := 0;
      End;
    End;
  If Key In [VK_HOME, VK_END, VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT] Then HasPendingAnchor := False;
  Case Key Of
    VK_HOME: JumpToStart;
    VK_END: JumpToEnd;
    VK_UP: ScrollTop := ScrollTop - 24;
    VK_DOWN: ScrollTop := ScrollTop + 24;
    VK_PRIOR: ScrollTop := ScrollTop - ViewRect.Height;
    VK_NEXT: ScrollTop := ScrollTop + ViewRect.Height;
    VK_RETURN, VK_SPACE: Toggle(FLayout.IndexOf(FocusedKey));
    VK_TAB:
    Begin
      If ssCtrl In Shift Then
        Begin
          LeaveConversation(Not (ssShift In Shift));
          Key := 0;
          Exit;
        End;
      I := FLayout.IndexOf(FocusedKey);
      If ssShift In Shift Then Dec(I)
      Else Inc(I);
      While (I >= 0) And (I < FLayout.Count) And Not FLayout[I].Visible Do If ssShift In Shift Then Dec(I)
      Else Inc(I);
      If (I >= 0) And (I < FLayout.Count) Then
        Begin
          FocusedKey := FLayout[I].Key;
          NavigateTo(FocusedKey);
          Key := 0;
        End
      Else LeaveConversation(Not (ssShift In Shift));
    End;
  Else
    Begin
      Inherited KeyDown(Key, Shift);
      Exit;
    End;
  End;
  Key := 0;
End;

Procedure TAssistantConversationSurface.MenuClick(Sender: TObject);
Begin
  Case TMenuItem(Sender).Tag Of
    0: Clipboard.AsText := SelectedText;
    1: Clipboard.AsText := MarkdownText;
    2: SelectWord;
    3: SelectLine;
    4: SelectAll;
    5: JumpToEnd;
  End;
End;
End.
