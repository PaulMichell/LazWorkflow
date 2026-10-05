Unit StyledList;

{ Virtual styled list with bounded layouts and indexed heights (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, Types, StyledTextTypes, StyledCanvas, StyledSurface;

Type
  TStyledGetItemEvent = Procedure(Sender: TObject; Index: Integer; Out Paragraph: TStyledParagraph) Of Object;
  TStyledListSlot = Record
    Index: Integer;
    Paragraph: TStyledParagraph;
    Layout: TStyledLayout;
  End;
  TStyledList = Class(TStyledSurface)
  Private
    FItems: TStringList;
    FItemCount, FItemIndex, FItemHeight: Integer;
    FWordWrap, FMultiSelect: Boolean;
    FOnGetItem: TStyledGetItemEvent;
    FOnSelectionChange: TNotifyEvent;
    FProviderRequests, FLastPaintedItems: QWord;
    Slots: Array[0..127] Of TStyledListSlot;
    Heights: TStyledHeightIndex;
    Selected: Array Of Boolean;
    SelectionAnchor, LastWidth: Integer;
    KnownGeneration: QWord;
    Function GetItems: TStrings;
    Procedure SetItems(Value: TStrings);
    Procedure SetItemCount(Value: Integer);
    Procedure SetItemIndex(Value: Integer);
    Procedure SetItemHeight(Value: Integer);
    Procedure SetWordWrap(Value: Boolean);
    Procedure SetProvider(Value: TStyledGetItemEvent);
    Procedure DoItemsChange(Sender: TObject);
    Procedure ResetCache;
    Function PrepareItem(Index: Integer): Integer;
    Procedure SelectItem(Index: Integer; Shift: TShiftState);
    Function ItemTop(Index: Integer): Int64;
    Function TotalHeight: Int64;
  Protected
    Procedure PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64); Override;
    Procedure GeometryChanged; Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure KeyDown(Var Key: Word; Shift: TShiftState); Override;
  Public
    Constructor Create(OwnerComponent: TComponent); Override;
    Destructor Destroy; Override;
    Function ItemAtY(Y: Int64): Integer;
    Function IsSelected(Index: Integer): Boolean;
    Procedure InvalidateItem(Index: Integer);
    Procedure ScrollItemIntoView(Index: Integer);
    Property ProviderRequests: QWord Read FProviderRequests;
    Property LastPaintedItems: QWord Read FLastPaintedItems;
  Published
    Property Items: TStrings Read GetItems Write SetItems;
    Property ItemCount: Integer Read FItemCount Write SetItemCount Default 0;
    Property ItemIndex: Integer Read FItemIndex Write SetItemIndex Default -1;
    Property ItemHeight: Integer Read FItemHeight Write SetItemHeight Default 36;
    Property WordWrap: Boolean Read FWordWrap Write SetWordWrap Default False;
    Property MultiSelect: Boolean Read FMultiSelect Write FMultiSelect Default False;
    Property OnGetItem: TStyledGetItemEvent Read FOnGetItem Write SetProvider;
    Property OnSelectionChange: TNotifyEvent Read FOnSelectionChange Write FOnSelectionChange;
  End;

Implementation

Uses
  SysUtils, Math, Graphics, LCLType, LCLIntf;

Constructor TStyledList.Create(OwnerComponent: TComponent);
Var
  Index: Integer;
Begin
  Inherited Create(OwnerComponent);
  FItemIndex := -1;
  SelectionAnchor := -1;
  FItemHeight := 36;
  FItems := TStringList.Create;
  FItems.OnChange := @DoItemsChange;
  For Index := 0 To High(Slots) Do Slots[Index].Index := -1;
  SetScrollbars(True, False);
End;

Destructor TStyledList.Destroy;
Var
  Index: Integer;
Begin
  FreeAndNil(FItems);
  For Index := 0 To High(Slots) Do Slots[Index].Layout.Free;
  Inherited Destroy;
End;

Function TStyledList.GetItems: TStrings;
Begin
  Result := FItems;
End;

Procedure TStyledList.SetItems(Value: TStrings);
Begin
  FItems.Assign(Value);
End;

Procedure TStyledList.DoItemsChange(Sender: TObject);
Begin
  SetItemCount(FItems.Count);
  ResetCache;
End;

Procedure TStyledList.SetItemCount(Value: Integer);
Begin
  Value := Max(0, Value);
  If FItemCount = Value Then Exit;
  FItemCount := Value;
  FItemIndex := Min(FItemIndex, Value - 1);
  If (SelectionAnchor < 0) Or (SelectionAnchor >= Value) Then
    SelectionAnchor := -1;
  SetLength(Selected, Value);
  ResetCache;
End;

Procedure TStyledList.SetProvider(Value: TStyledGetItemEvent);
Begin
  FOnGetItem := Value;
  ResetCache;
End;

Procedure TStyledList.SetItemHeight(Value: Integer);
Begin
  FItemHeight := Max(12, Value);
  ResetCache;
End;

Procedure TStyledList.SetWordWrap(Value: Boolean);
Begin
  If FWordWrap = Value Then Exit;
  FWordWrap := Value;
  ResetCache;
End;

Procedure TStyledList.ResetCache;
Var
  Index, AnchorIndex: Integer;
Begin
  If Not Assigned(FItems) Then Exit;
  AnchorIndex := ItemAtY(ScrollTop);
  For Index := 0 To High(Slots) Do
    Begin
      Slots[Index].Index := -1;
      Slots[Index].Paragraph := Default(TStyledParagraph);
      FreeAndNil(Slots[Index].Layout);
    End;
  ConfigureCanvas;
  LastWidth := ViewRect.Width;
  KnownGeneration := Renderer.Generation;
  If FWordWrap Then ResetHeights(Heights, FItemCount, FItemHeight)
  Else ResetHeights(Heights, 0, 0);
  SetExtent(ViewRect.Width, TotalHeight);
  If AnchorIndex >= 0 Then ScrollTop := ItemTop(AnchorIndex);
  Invalidate;
End;

Procedure TStyledList.GeometryChanged;
Begin
  If Not Assigned(FItems) Then Exit;
  ConfigureCanvas;
  If (LastWidth <> ViewRect.Width) Or (KnownGeneration <> Renderer.Generation) Then ResetCache;
End;

Function TStyledList.ItemTop(Index: Integer): Int64;
Begin
  If FWordWrap Then Result := HeightBefore(Heights, Index) Else Result := Int64(Index) * FItemHeight;
End;

Function TStyledList.TotalHeight: Int64;
Begin
  Result := ItemTop(FItemCount);
End;

Function TStyledList.ItemAtY(Y: Int64): Integer;
Begin
  If FItemCount = 0 Then Exit(-1);
  If FWordWrap Then Result := ItemAtHeight(Heights, Max(Int64(0), Y))
  Else Result := Min(Int64(FItemCount - 1), Max(Int64(0), Y) Div Max(1, FItemHeight));
End;

Function TStyledList.PrepareItem(Index: Integer): Integer;
Var
  Wrap: TStyledWrap;
Begin
  Result := Index Mod Length(Slots);
  If Slots[Result].Index = Index Then Exit;
  Slots[Result].Paragraph := Default(TStyledParagraph);
  If Assigned(FOnGetItem) Then
    Begin
      FOnGetItem(Self, Index, Slots[Result].Paragraph);
      Inc(FProviderRequests);
    End
  Else If Index < FItems.Count Then AppendStyledText(Slots[Result].Paragraph, FItems[Index]);
  Slots[Result].Index := Index;
  If Not Assigned(Slots[Result].Layout) Then Slots[Result].Layout := TStyledLayout.Create;
  Slots[Result].Layout.Clear;
  If FWordWrap Then Wrap := swWord Else Wrap := swNone;
  Renderer.Prepare(Slots[Result].Layout, Slots[Result].Paragraph, Max(1, ViewRect.Width - 12), Wrap);
  If FWordWrap Then SetHeight(Heights, Index, Max(Int64(FItemHeight), Slots[Result].Layout.Height + 12));
End;

Procedure TStyledList.PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64);
Var
  Index, Slot: Integer;
  LogicalTop, Bottom: Int64;
  Bounds, TextClip: TRect;
  Foreground: TColor;
Begin
  GeometryChanged;
  FLastPaintedItems := 0;
  Index := ItemAtY(Clip.Top - OriginY);
  If Index < 0 Then Exit;
  While Index < FItemCount Do
    Begin
      LogicalTop := OriginY + ItemTop(Index);
      If LogicalTop >= Clip.Bottom Then Break;
      Slot := PrepareItem(Index);
      Bottom := OriginY + ItemTop(Index + 1);
      Bounds := Rect(Clip.Left, Max(Int64(Clip.Top), LogicalTop), Clip.Right, Min(Int64(Clip.Bottom), Bottom));
      BufferCanvas.Brush.Style := bsSolid;
      If IsSelected(Index) Then
        Begin
          BufferCanvas.Brush.Color := clHighlight;
          Foreground := clHighlightText;
        End
      Else
        Begin
          If Odd(Index) Then BufferCanvas.Brush.Color := $00F7F5F1 Else BufferCanvas.Brush.Color := Color;
          Foreground := clDefault;
        End;
      BufferCanvas.FillRect(Bounds);
      TextClip := Bounds;
      BufferCanvas.SaveHandleState;
      Try
        IntersectClipRect(BufferCanvas.Handle, TextClip.Left, TextClip.Top, TextClip.Right, TextClip.Bottom);
        Renderer.Draw(Slots[Slot].Layout, OriginX + 6, LogicalTop + 6, TextClip, -1, -1, Foreground);
      Finally
        BufferCanvas.RestoreHandleState;
      End;
      If (Index = FItemIndex) And Focused Then
        Begin
          { Paint only the outline: GTK3 can fill Rectangle even with a clear
            brush, covering text that was already drawn in the selected row. }
          BufferCanvas.Brush.Style := bsSolid;
          BufferCanvas.Brush.Color := $00908070;
          BufferCanvas.FillRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Top + 1);
          BufferCanvas.FillRect(Bounds.Left, Bounds.Bottom - 1, Bounds.Right, Bounds.Bottom);
          BufferCanvas.FillRect(Bounds.Left, Bounds.Top, Bounds.Left + 1, Bounds.Bottom);
          BufferCanvas.FillRect(Bounds.Right - 1, Bounds.Top, Bounds.Right, Bounds.Bottom);
        End;
      Inc(FLastPaintedItems);
      Inc(Index);
    End;
  SetExtent(ViewRect.Width, TotalHeight);
End;

Function TStyledList.IsSelected(Index: Integer): Boolean;
Begin
  Result := (Index >= 0) And (Index < FItemCount);
  If Result Then
    If MultiSelect Then Result := Selected[Index] Else Result := Index = FItemIndex;
End;

Procedure TStyledList.SelectItem(Index: Integer; Shift: TShiftState);
Var
  Position: Integer;
Begin
  If FItemCount = 0 Then Exit;
  Index := EnsureRange(Index, 0, FItemCount - 1);
  If MultiSelect Then
    Begin
      If Not (ssCtrl In Shift) Then
        For Position := 0 To High(Selected) Do Selected[Position] := False;
      If (ssShift In Shift) And (SelectionAnchor >= 0) Then
        Begin
          For Position := Min(SelectionAnchor, Index) To Max(SelectionAnchor, Index) Do
            If (Position >= 0) And (Position <= High(Selected)) Then
              Selected[Position] := True;
        End
      Else Selected[Index] := Not Selected[Index];
    End;
  If Not (ssShift In Shift) Then SelectionAnchor := Index;
  FItemIndex := Index;
  ScrollItemIntoView(Index);
  Invalidate;
  If Assigned(FOnSelectionChange) Then FOnSelectionChange(Self);
End;

Procedure TStyledList.SetItemIndex(Value: Integer);
Begin
  If Value < 0 Then
    Begin
      FItemIndex := -1;
      Invalidate;
    End
  Else SelectItem(Value, []);
End;

Procedure TStyledList.ScrollItemIntoView(Index: Integer);
Var
  LogicalTop, Bottom: Int64;
Begin
  If (Index < 0) Or (Index >= FItemCount) Then Exit;
  ConfigureCanvas;
  PrepareItem(Index);
  SetExtent(ViewRect.Width, TotalHeight);
  LogicalTop := ItemTop(Index);
  Bottom := ItemTop(Index + 1);
  If LogicalTop < ScrollTop Then ScrollTop := LogicalTop
  Else If Bottom > ScrollTop + ViewRect.Height Then ScrollTop := Bottom - ViewRect.Height;
End;

Procedure TStyledList.InvalidateItem(Index: Integer);
Var
  Slot: Integer;
Begin
  If (Index < 0) Or (Index >= FItemCount) Then Exit;
  Slot := Index Mod Length(Slots);
  If Slots[Slot].Index = Index Then Slots[Slot].Index := -1;
  Invalidate;
End;

Procedure TStyledList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseDown(Button, Shift, X, Y);
  If Button <> mbLeft Then Exit;
  SetFocus;
  If (Y >= ViewRect.Top) And (Y < ViewRect.Bottom) And (Y - ViewRect.Top + ScrollTop < TotalHeight) Then
    SelectItem(ItemAtY(Y - ViewRect.Top + ScrollTop), Shift);
End;

Procedure TStyledList.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  Index: Integer;
Begin
  Inherited KeyDown(Key, Shift);
  Index := Max(0, FItemIndex);
  Case Key Of
    VK_UP: Dec(Index);
    VK_DOWN: Inc(Index);
    VK_HOME: Index := 0;
    VK_END: Index := FItemCount - 1;
    VK_PRIOR: Dec(Index, Max(1, ViewRect.Height Div FItemHeight));
    VK_NEXT: Inc(Index, Max(1, ViewRect.Height Div FItemHeight));
    VK_SPACE: ;
  Else
    Exit;
  End;
  SelectItem(Index, Shift);
  Key := 0;
End;

Initialization
  RegisterClass(TStyledList);

Finalization
  UnRegisterClass(TStyledList);

End.
