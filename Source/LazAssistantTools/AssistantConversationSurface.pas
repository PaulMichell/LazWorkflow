Unit AssistantConversationSurface;

{ One canvas, one logical scroll extent and cross-section text selection. (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The picture cache stays with
  this canvas so paint, hit-testing, and section height use one image row.
  Reviewed 2026-09-26: picture colors stay in memory so paint does not depend on a device bitmap. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Types, Graphics, Controls, ExtCtrls, Menus, LMessages, StyledSurface,
  StyledTextTypes, AssistantTrace, AssistantConversationLayout;

Type
  { Scaled attachment pixels. Device bitmaps are not used: GTK blits them as empty. }
  TDisplayPicture = Class
  Public
    Width: Integer;
    Height: Integer;
    Colors: Array Of TColor;
  End;
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
  TConversationPointerHit = Record
    Position: TConversationPosition;
    ImageIndex: Integer;
  End;
  TAssistantConversationSurface = Class(TStyledSurface)
  Private
    FLayout: TConversationLayout;
    FImageRoot: String;
    Pictures: TStringList;
    Timer: TTimer;
    FShowThinking, FShowTools, FFollowTail, FUpdating, Selecting, FInTick: Boolean;
    SelectionStart, SelectionEnd: TConversationPosition;
    SavedAnchor, PendingAnchor: TConversationAnchor;
    HasPendingAnchor: Boolean;
    FocusedKey: String;
    PointerPosition: TPoint;
    CopyImageItem, SaveImageItem, ImageSeparator: TMenuItem;
    MenuImage: TTraceImageRef;
    MenuImageValid: Boolean;
    BackgroundIndex: Integer;
    FLayoutRevision, FPaintRevision, FMaxUpdateMilliseconds: QWord;
    Procedure GetDialogCode(Var Message: TLMGetDlgCode); Message LM_GETDLGCODE;
    Procedure Tick(Sender: TObject);
    Procedure LeaveConversation(ForwardDirection: Boolean);
    Procedure MenuClick(Sender: TObject);
    Procedure MenuPopup(Sender: TObject);
    Procedure CopyImageClick(Sender: TObject);
    Procedure SaveImageClick(Sender: TObject);
    Function AttachmentUnder(X, Y: Integer; Out Ref: TTraceImageRef): Boolean;
    Procedure PrepareViewport;
    Procedure RestoreAnchor(Const Anchor: TConversationAnchor);
    Function CaptureAnchor: TConversationAnchor;
    Function HitPosition(X, Y: Integer): TConversationPosition;
    Procedure SetImageRoot(Const Value: String);
    Procedure ClearPictures;
    Procedure TrimPictures;
    Function PictureFor(Const Ref: TTraceImageRef; DisplayW, DisplayH: Integer): TDisplayPicture;
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
    Procedure OpenAttachment(Const Ref: TTraceImageRef); Virtual;
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
    Function PointerHit(X, Y: Integer): TConversationPointerHit;
    Property Layout: TConversationLayout Read FLayout;
    Property ImageRoot: String Read FImageRoot Write SetImageRoot;
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
  Math, Clipbrd, LCLType, Forms, FPImage,
  StyledCanvas, StyledTextDocument, AssistantImages, AssistantImageView;

Const
  UserBubbleColor = TColor($00EFF8E5);

{ GTK StretchDraw and CopyRect of a device bitmap paint nothing on this memory
  buffer after the bubble clip, while FillRect still shows. Scale into memory
  colors and paint those with FillRect, the same primitive as the missing tile. }

Function PictureKey(Const Ref: TTraceImageRef; DisplayW, DisplayH: Integer): String;
Begin
  Result := Ref.Id + #1 + Ref.DisplayPath + #1 + IntToStr(DisplayW) + 'x' + IntToStr(DisplayH);
End;

Function ChannelByte(Value: Word): Byte;
Begin
  Result := Value Shr 8;
End;

Function PackedColor(RedByte, GreenByte, BlueByte: Byte): TColor;
Begin
  Result := TColor(RedByte Or (GreenByte Shl 8) Or (BlueByte Shl 16));
End;

Function FPColorToPacked(Const Value: TFPColor): TColor;
Begin
  Result := PackedColor(ChannelByte(Value.Red), ChannelByte(Value.Green), ChannelByte(Value.Blue));
End;

Function UserBubbleFPColor: TFPColor;
Var
  ColorValue: Integer;
Begin
  ColorValue := UserBubbleColor;
  Result.Red := (ColorValue And $FF) * 257;
  Result.Green := ((ColorValue Shr 8) And $FF) * 257;
  Result.Blue := ((ColorValue Shr 16) And $FF) * 257;
  Result.Alpha := 65535;
End;

Function ZeroAlphaMeansOpaque(Img: TFPCustomImage): Boolean;
Var
  X, Y: Integer;
Begin
  Result := True;
  For Y := 0 To Img.Height - 1 Do
    For X := 0 To Img.Width - 1 Do
      If Img.Colors[X, Y].Alpha <> 0 Then Exit(False);
End;

Function FlattenPixel(Const Src, Bubble: TFPColor; ZeroAlphaIsOpaque: Boolean): TFPColor;
Var
  Alpha: Int64;
Begin
  If ZeroAlphaIsOpaque Or (Src.Alpha >= 65535) Then
    Begin
      Result := Src;
      Result.Alpha := 65535;
      Exit;
    End;
  Alpha := Src.Alpha;
  Result.Red := (Int64(Src.Red) * Alpha + Int64(Bubble.Red) * (65535 - Alpha)) Div 65535;
  Result.Green := (Int64(Src.Green) * Alpha + Int64(Bubble.Green) * (65535 - Alpha)) Div 65535;
  Result.Blue := (Int64(Src.Blue) * Alpha + Int64(Bubble.Blue) * (65535 - Alpha)) Div 65535;
  Result.Alpha := 65535;
End;

Function ScaleToPicture(Img: TFPCustomImage; DestW, DestH: Integer): TDisplayPicture;
Var
  X, Y, X0, Y0, X1, Y1, SX, SY, StepX, StepY, Count: Integer;
  RedSum, GreenSum, BlueSum: Int64;
  Bubble, Flat: TFPColor;
  ZeroAlphaIsOpaque: Boolean;
Begin
  Result := Nil;
  If (Not Assigned(Img)) Or (Img.Width < 1) Or (Img.Height < 1) Or (DestW < 1) Or (DestH < 1) Then Exit;
  Result := TDisplayPicture.Create;
  Try
    Result.Width := DestW;
    Result.Height := DestH;
    SetLength(Result.Colors, DestW * DestH);
    ZeroAlphaIsOpaque := ZeroAlphaMeansOpaque(Img);
    Bubble := UserBubbleFPColor;
    For Y := 0 To DestH - 1 Do
      Begin
        Y0 := Y * Img.Height Div DestH;
        Y1 := (Y + 1) * Img.Height Div DestH;
        If Y1 <= Y0 Then Y1 := Y0 + 1;
        If Y1 > Img.Height Then Y1 := Img.Height;
        For X := 0 To DestW - 1 Do
          Begin
            X0 := X * Img.Width Div DestW;
            X1 := (X + 1) * Img.Width Div DestW;
            If X1 <= X0 Then X1 := X0 + 1;
            If X1 > Img.Width Then X1 := Img.Width;
            RedSum := 0;
            GreenSum := 0;
            BlueSum := 0;
            Count := 0;
            { At most a 4 by 4 sample of each source box, so a large photo does not stall the first paint. }
            StepX := Max(1, (X1 - X0) Div 4);
            StepY := Max(1, (Y1 - Y0) Div 4);
            SY := Y0;
            While SY < Y1 Do
              Begin
                SX := X0;
                While SX < X1 Do
                  Begin
                    Flat := FlattenPixel(Img.Colors[SX, SY], Bubble, ZeroAlphaIsOpaque);
                    Inc(RedSum, Flat.Red);
                    Inc(GreenSum, Flat.Green);
                    Inc(BlueSum, Flat.Blue);
                    Inc(Count);
                    Inc(SX, StepX);
                  End;
                Inc(SY, StepY);
              End;
            If Count < 1 Then Count := 1;
            Flat.Red := RedSum Div Count;
            Flat.Green := GreenSum Div Count;
            Flat.Blue := BlueSum Div Count;
            Result.Colors[Y * DestW + X] := FPColorToPacked(Flat);
          End;
      End;
  Except
    FreeAndNil(Result);
  End;
End;

Procedure PaintDisplayPicture(Canvas: TCanvas; Const Dest, Clip: TRect; Picture: TDisplayPicture);
Var
  Visible: TRect;
  X, Y, RunX, SrcX, SrcY: Integer;
  Color: TColor;
  Function SourceColor(LocalX, LocalY: Integer): TColor;
  Begin
    If LocalX < 0 Then LocalX := 0;
    If LocalY < 0 Then LocalY := 0;
    If LocalX >= Picture.Width Then LocalX := Picture.Width - 1;
    If LocalY >= Picture.Height Then LocalY := Picture.Height - 1;
    Result := Picture.Colors[LocalY * Picture.Width + LocalX];
  End;
  Function MapX(Value: Integer): Integer;
  Begin
    Result := (Value - Dest.Left) * Picture.Width Div Max(1, Dest.Right - Dest.Left);
  End;
  Function MapY(Value: Integer): Integer;
  Begin
    Result := (Value - Dest.Top) * Picture.Height Div Max(1, Dest.Bottom - Dest.Top);
  End;
  Function UniformColor(Out Value: TColor): Boolean;
  Var
    PX, PY: Integer;
  Begin
    Value := SourceColor(MapX(Visible.Left), MapY(Visible.Top));
    Result := True;
    For PY := Visible.Top To Visible.Bottom - 1 Do
      For PX := Visible.Left To Visible.Right - 1 Do
        If SourceColor(MapX(PX), MapY(PY)) <> Value Then Exit(False);
  End;
Begin
  If (Not Assigned(Picture)) Or (Picture.Width < 1) Or (Picture.Height < 1) Then Exit;
  If Length(Picture.Colors) < Picture.Width * Picture.Height Then Exit;
  Visible := Rect(0, 0, 0, 0);
  If Not IntersectRect(Visible, Dest, Clip) Then Exit;
  Canvas.Brush.Style := bsSolid;
  If UniformColor(Color) Then
    Begin
      Canvas.Brush.Color := Color;
      Canvas.FillRect(Visible);
      Exit;
    End;
  Y := Visible.Top;
  While Y < Visible.Bottom Do
    Begin
      SrcY := MapY(Y);
      X := Visible.Left;
      While X < Visible.Right Do
        Begin
          SrcX := MapX(X);
          Color := SourceColor(SrcX, SrcY);
          RunX := X + 1;
          While (RunX < Visible.Right) And (SourceColor(MapX(RunX), SrcY) = Color) Do Inc(RunX);
          Canvas.Brush.Color := Color;
          Canvas.FillRect(X, Y, RunX, Y + 1);
          X := RunX;
        End;
      Inc(Y);
    End;
End;

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
  PopupMenu.OnPopup := @MenuPopup;
  CopyImageItem := TMenuItem.Create(PopupMenu);
  CopyImageItem.Caption := 'Copy Image';
  CopyImageItem.OnClick := @CopyImageClick;
  CopyImageItem.Visible := False;
  PopupMenu.Items.Add(CopyImageItem);
  SaveImageItem := TMenuItem.Create(PopupMenu);
  SaveImageItem.Caption := 'Save Image';
  SaveImageItem.OnClick := @SaveImageClick;
  SaveImageItem.Visible := False;
  PopupMenu.Items.Add(SaveImageItem);
  ImageSeparator := TMenuItem.Create(PopupMenu);
  ImageSeparator.Caption := '-';
  ImageSeparator.Visible := False;
  PopupMenu.Items.Add(ImageSeparator);
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
  ClearPictures;
  FreeAndNil(Pictures);
  FreeAndNil(FLayout);
  Inherited Destroy;
End;

Procedure TAssistantConversationSurface.SetImageRoot(Const Value: String);
Begin
  If FImageRoot = Value Then Exit;
  FImageRoot := Value;
  ClearPictures;
  Invalidate;
End;

Procedure TAssistantConversationSurface.ClearPictures;
Var
  I: Integer;
Begin
  If Not Assigned(Pictures) Then Exit;
  For I := 0 To Pictures.Count - 1 Do Pictures.Objects[I].Free;
  Pictures.Clear;
End;

Procedure TAssistantConversationSurface.TrimPictures;
Var
  I, J, DisplayW, DisplayH, ContentW: Integer;
  Keep: TStringList;
  Ref: TTraceImageRef;
Begin
  If Not Assigned(Pictures) Or (Pictures.Count = 0) Then Exit;
  Keep := TStringList.Create;
  Try
    Keep.Sorted := True;
    Keep.Duplicates := dupIgnore;
    For I := 0 To FLayout.Count - 1 Do
      Begin
        ContentW := FLayout.ImageContentWidth(I);
        For J := 0 To High(FLayout[I].Images) Do
          Begin
            Ref := FLayout[I].Images[J];
            If Ref.Missing Then Continue;
            DisplayW := 0;
            DisplayH := 0;
            If Not ScaledImageExtent(Ref.Width, Ref.Height, ContentW, FLayout.PixelsPerInch, DisplayW, DisplayH) Then Continue;
            Keep.Add(PictureKey(Ref, DisplayW, DisplayH));
          End;
      End;
    For I := Pictures.Count - 1 DownTo 0 Do
      If Keep.IndexOf(Pictures[I]) < 0 Then
        Begin
          Pictures.Objects[I].Free;
          Pictures.Delete(I);
        End;
  Finally
    Keep.Free;
  End;
End;

Function TAssistantConversationSurface.PictureFor(Const Ref: TTraceImageRef; DisplayW, DisplayH: Integer): TDisplayPicture;
Var
  Index: Integer;
  Key, ErrorText: String;
  Img: TFPMemoryImage;
Begin
  Result := Nil;
  If Ref.Missing Or (FImageRoot = '') Or (Ref.DisplayPath = '') Or (DisplayW < 1) Or (DisplayH < 1) Then Exit;
  If Not Assigned(Pictures) Then
    Begin
      Pictures := TStringList.Create;
      Pictures.Sorted := True;
      Pictures.Duplicates := dupError;
    End;
  Key := PictureKey(Ref, DisplayW, DisplayH);
  Index := Pictures.IndexOf(Key);
  If Index >= 0 Then Exit(TDisplayPicture(Pictures.Objects[Index]));
  Img := Nil;
  Try
    If LoadStoredAssistantImage(FImageRoot, Ref.DisplayPath, Img, ErrorText) And Assigned(Img) And
      (Img.Width > 0) And (Img.Height > 0) Then
      Result := ScaleToPicture(Img, DisplayW, DisplayH);
  Except
    FreeAndNil(Result);
  End;
  FreeAndNil(Img);
  { A failed load is cached as Nil so a missing decode is not retried every paint. }
  Pictures.AddObject(Key, Result);
End;

Procedure TAssistantConversationSurface.Clear;
Begin
  Timer.Enabled := False;
  HasPendingAnchor := False;
  ClearPictures;
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
  TrimPictures;
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
  Dec(LocalY, FLayout[I].Padding + FLayout.ImageRowHeight(I));
  { The viewport top is still in the picture row. Keep the section offset. }
  If LocalY < 0 Then Exit;
  P := ItemAtHeight(Fragment.Layout.Heights, LocalY);
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
          If L >= 0 Then LocalY := FLayout[I].Padding + FLayout.ImageRowHeight(I) + Fragment.Layout.TextTop(P) +
            Fragment.Layout.Paragraphs[P].Lines[L].Top + Anchor.Offset;
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
  I, A, B, TileIndex, TileLeft, TileWidth, DisplayW, DisplayH, SlotH, PPI, ContentW: Integer;
  TileTop: Integer;
  Fragment: TConversationFragment;
  First, Last: TConversationPosition;
  StartPos, EndPos: TStyledPosition;
  Selected: Boolean;
  Style: TStyledBoxStyle;
  SectionHeight: Int64;
  TileH: Integer;
  Picture: TDisplayPicture;
  Dest: TRect;
  Procedure DrawUnavailable(Const Area: TRect; Const Caption: String);
  Begin
    If (Area.Right <= Area.Left + 4) Or (Area.Bottom <= Area.Top + 4) Then Exit;
    BufferCanvas.Rectangle(Area);
    BufferCanvas.Brush.Style := bsClear;
    BufferCanvas.TextRect(Area, Area.Left + 6, Area.Top + 4, Caption);
    BufferCanvas.Brush.Style := bsSolid;
  End;
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
      TileH := 0;
      If FLayout[I].Kind = tbkUser Then TileH := FLayout.ImageRowHeight(I);
      If FLayout[I].Visible And (Assigned(Fragment) Or (TileH > 0)) Then
        Begin
          If FLayout[I].Kind In [tbkUser, tbkAnswer] Then
            Begin
              Style := DefaultStyledBoxStyle;
              Style.CornerRadius := Scale96ToFont(12);
              Style.BorderWidth := 1;
              If FLayout[I].Kind = tbkUser Then
                Begin
                  Style.Background := UserBubbleColor;
                  Style.BorderColor := $D5E4C5;
                End
              Else
                Begin
                  Style.Background := $F7F7F7;
                  Style.BorderColor := $E4E4E4;
                End;
              SectionHeight := TileH + FLayout[I].Padding * 2;
              If Assigned(Fragment) Then SectionHeight := SectionHeight + Fragment.Height;
              Renderer.DrawBoxFrame(GetStyledBoxGeometry(OriginX + FLayout[I].Left,
                OriginY + FLayout.Top(I), FLayout[I].OuterWidth, SectionHeight, Style), Style, Clip);
            End;
          If TileH > 0 Then
            Begin
              PPI := FLayout.PixelsPerInch;
              ContentW := FLayout.ImageContentWidth(I);
              TileLeft := OriginX + FLayout[I].Left + FLayout[I].Padding;
              TileWidth := ContentW;
              If TileWidth < 48 Then TileWidth := 48;
              TileTop := Integer(OriginY + FLayout.Top(I) + FLayout[I].Padding);
              BufferCanvas.Font.Assign(Font);
              BufferCanvas.Font.Color := clGrayText;
              BufferCanvas.Brush.Style := bsSolid;
              BufferCanvas.Brush.Color := $F4F4F4;
              BufferCanvas.Pen.Color := $C8C8C8;
              For TileIndex := 0 To High(FLayout[I].Images) Do
                Begin
                  SlotH := UserImageSlotHeight(FLayout[I].Images[TileIndex], ContentW, PPI);
                  DisplayW := 0;
                  DisplayH := 0;
                  Picture := Nil;
                  If Not FLayout[I].Images[TileIndex].Missing Then
                    Begin
                      ScaledImageExtent(FLayout[I].Images[TileIndex].Width, FLayout[I].Images[TileIndex].Height,
                        ContentW, PPI, DisplayW, DisplayH);
                      Picture := PictureFor(FLayout[I].Images[TileIndex], DisplayW, DisplayH);
                    End;
                  If Assigned(Picture) And (Picture.Width > 0) And (Picture.Height > 0) Then
                    Begin
                      Dest := Rect(TileLeft, TileTop, TileLeft + Picture.Width, TileTop + Picture.Height);
                      PaintDisplayPicture(BufferCanvas, Dest, Clip, Picture);
                    End
                  Else
                    DrawUnavailable(Rect(TileLeft, TileTop + 2, TileLeft + TileWidth, TileTop + SlotH - 2),
                      MissingImageTileCaption(FLayout[I].Images[TileIndex]));
                  Inc(TileTop, SlotH);
                End;
            End;
          If Assigned(Fragment) Then
            Begin
              Selected := (A >= 0) And (B >= 0) And (I >= A) And (I <= B) And (Compare(First, Last) <> 0);
              StartPos := StyledPosition(0, 0);
              EndPos := Fragment.Document.EndPosition;
              If I = A Then StartPos := Fragment.Document.Clamp(First.Text);
              If I = B Then EndPos := Fragment.Document.Clamp(Last.Text);
              Fragment.Layout.Paint(Clip, OriginX + FLayout[I].Left + FLayout[I].Padding,
                OriginY + FLayout.Top(I) + FLayout[I].Padding + TileH, StartPos, EndPos, Selected, False);
            End;
          If Focused And (FocusedKey = FLayout[I].Key) Then
            Begin
              Style := DefaultStyledBoxStyle;
              Style.BorderWidth := 1;
              Style.BorderColor := clHighlight;
              If FLayout[I].Kind In [tbkUser, tbkAnswer] Then Style.CornerRadius := Scale96ToFont(12);
              SectionHeight := TileH + FLayout[I].Padding * 2;
              If Assigned(Fragment) Then SectionHeight := SectionHeight + Fragment.Height;
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
  LocalY := Int64(Y) - ViewRect.Top + ScrollTop - FLayout.Top(I) - FLayout[I].Padding - FLayout.ImageRowHeight(I);
  If LocalY < 0 Then
    Begin
      Result.Text := StyledPosition(0, 0);
      Exit;
    End;
  P := ItemAtHeight(Fragment.Layout.Heights, LocalY);
  Result.Text := StyledPosition(P, 0);
  If Not Assigned(Fragment.Layout.Paragraphs[P]) Then Exit;
  Result.Text.Offset := Renderer.HitTest(Fragment.Layout.Paragraphs[P], X - ViewRect.Left - FLayout[I].Left - FLayout[I].Padding - Fragment.Layout.TextLeft(P),
    LocalY - Fragment.Layout.TextTop(P), Trailing);
  Result.Text.Trailing := Trailing;
  Result.Text := Fragment.Document.Clamp(Result.Text);
End;

Function TAssistantConversationSurface.PointerHit(X, Y: Integer): TConversationPointerHit;
Var
  I, ContentLeft, ContentW: Integer;
  SectionY: Int64;
Begin
  Result.Position := HitPosition(X, Y);
  Result.ImageIndex := -1;
  I := FLayout.IndexOf(Result.Position.Key);
  If (I < 0) Or (FLayout[I].Kind <> tbkUser) Or (Length(FLayout[I].Images) = 0) Then Exit;
  ContentW := FLayout.ImageContentWidth(I);
  ContentLeft := ViewRect.Left + FLayout[I].Left + FLayout[I].Padding;
  If (X < ContentLeft) Or (X >= ContentLeft + ContentW) Then Exit;
  SectionY := Int64(Y) - ViewRect.Top + ScrollTop - FLayout.Top(I) - FLayout[I].Padding;
  Result.ImageIndex := ImageIndexInRow(FLayout[I].Images, ContentW, FLayout.PixelsPerInch, SectionY);
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
  If PointerHit(X, Y).ImageIndex >= 0 Then
    Begin
      ClearSelection;
      Selecting := False;
      FFollowTail := False;
      Invalidate;
      Exit;
    End;
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
Var
  Ref: TTraceImageRef;
Begin
  Inherited DblClick;
  Selecting := False;
  MouseCapture := False;
  If AttachmentUnder(PointerPosition.X, PointerPosition.Y, Ref) Then
    Begin
      OpenAttachment(Ref);
      Exit;
    End;
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

Function TAssistantConversationSurface.AttachmentUnder(X, Y: Integer; Out Ref: TTraceImageRef): Boolean;
Var
  Hit: TConversationPointerHit;
  Index: Integer;
Begin
  Result := False;
  Ref := Default(TTraceImageRef);
  Hit := PointerHit(X, Y);
  If Hit.ImageIndex < 0 Then Exit;
  Index := FLayout.IndexOf(Hit.Position.Key);
  If (Index < 0) Or (Hit.ImageIndex > High(FLayout[Index].Images)) Then Exit;
  Ref := FLayout[Index].Images[Hit.ImageIndex];
  Result := True;
End;

Procedure TAssistantConversationSurface.OpenAttachment(Const Ref: TTraceImageRef);
Begin
  ShowAssistantImage(FImageRoot, Ref);
End;

Procedure TAssistantConversationSurface.MenuPopup(Sender: TObject);
Begin
  MenuImageValid := AttachmentUnder(PointerPosition.X, PointerPosition.Y, MenuImage);
  CopyImageItem.Visible := MenuImageValid;
  SaveImageItem.Visible := MenuImageValid;
  ImageSeparator.Visible := MenuImageValid;
End;

Procedure TAssistantConversationSurface.CopyImageClick(Sender: TObject);
Begin
  If MenuImageValid Then CopyAssistantImage(FImageRoot, MenuImage);
End;

Procedure TAssistantConversationSurface.SaveImageClick(Sender: TObject);
Begin
  If MenuImageValid Then SaveAssistantImage(FImageRoot, MenuImage);
End;

Procedure TAssistantConversationSurface.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  I: Integer;
  Ref: TTraceImageRef;
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
    VK_RETURN:
      Begin
        If AttachmentUnder(PointerPosition.X, PointerPosition.Y, Ref) Then OpenAttachment(Ref)
        Else Toggle(FLayout.IndexOf(FocusedKey));
      End;
    VK_SPACE: Toggle(FLayout.IndexOf(FocusedKey));
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
