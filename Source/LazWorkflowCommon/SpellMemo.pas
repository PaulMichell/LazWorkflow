Unit SpellMemo;

{ Portable LCL memo with optional Hunspell/ASpell markup (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Wrap layout, caret/selection
  and spell markup are one painted control so underlines stay widgetset-free.
  Reviewed 2026-08: no hidden sibling material. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Controls, StdCtrls, Menus, ExtCtrls, Graphics, Forms, LCLType, LMessages,
  SpellMemoMarkup;

Type
  TSpellPaintLine = Record
    ByteStart: Integer;
    ByteLength: Integer;
    Top: Integer;
    Height: Integer;
  End;
  TSpellPaintLineArray = Array Of TSpellPaintLine;

  TSpellMemo = Class(TCustomControl)
  Private
    FText: String;
    FUseSharedConfig: Boolean;
    FWordWrap: Boolean;
    FWantTabs: Boolean;
    FWantReturns: Boolean;
    FReadOnly: Boolean;
    FScrollBars: TScrollStyle;
    FSelStart: Integer;
    FSelLength: Integer;
    FSelAnchor: Integer;
    FOnChange: TNotifyEvent;
    FDebounce: TTimer;
    FCaretTimer: TTimer;
    FCaretOn: Boolean;
    FRanges: TSpellUnderlineRangeArray;
    FOwnedPopup: TPopupMenu;
    FSpellItemCount: Integer;
    FActiveToken: String;
    FActiveStart: Integer;
    FActiveLength: Integer;
    FHostPopupHandler: TNotifyEvent;
    FHookedPopup: TPopupMenu;
    FEditCutItem: TMenuItem;
    FEditCopyItem: TMenuItem;
    FEditPasteItem: TMenuItem;
    FEditSelectAllItem: TMenuItem;
    FPaintLines: TSpellPaintLineArray;
    FContentHeight: Integer;
    FScrollBar: TScrollBar;
    FUpdatingScroll: Boolean;
    FReady: Boolean;
    FIgnoreDragSelect: Boolean;
    FDragOrigin: TPoint;
    Procedure DebounceTimer(Sender: TObject);
    Procedure CaretTimerTick(Sender: TObject);
    Procedure ResetCaretBlink;
    Procedure ConfigChanged(Sender: TObject);
    Procedure RestartDebounce;
    Procedure ClearSpellMenu(Menu: TPopupMenu);
    Procedure RebuildSpellMenu(Menu: TPopupMenu);
    Procedure SuggestionClick(Sender: TObject);
    Procedure IgnoreClick(Sender: TObject);
    Procedure AddClick(Sender: TObject);
    Procedure PopupPopup(Sender: TObject);
    Procedure EnsurePopupHook;
    Procedure EnsureEditMenu;
    Procedure UpdateEditMenu;
    Procedure EditCutClick(Sender: TObject);
    Procedure EditCopyClick(Sender: TObject);
    Procedure EditPasteClick(Sender: TObject);
    Procedure EditSelectAllClick(Sender: TObject);
    Function SpellActive: Boolean;
    Procedure ReplaceActiveWord(Const NewText: String);
    Procedure LocateTokenAtCaret;
    Procedure SetWordWrap(Value: Boolean);
    Procedure SetWantTabs(Value: Boolean);
    Procedure SetWantReturns(Value: Boolean);
    Procedure SetReadOnly(Value: Boolean);
    Procedure SetScrollBars(Value: TScrollStyle);
    Procedure SetSelStart(Value: Integer);
    Procedure SetSelLength(Value: Integer);
    Function GetSelText: String;
    Procedure SetSelText(Const Value: String);
    Function TextAreaWidth: Integer;
    Function LineHeight: Integer;
    Procedure RebuildLayout;
    Procedure UpdateScrollBar;
    Procedure ScrollBarChange(Sender: TObject);
    Function ScrollY: Integer;
    Procedure EnsureCaretInView;
    Procedure MoveCaret(NewStart: Integer; ExtendSel: Boolean);
    Function CharIndexAtPoint(X, Y: Integer): Integer;
    Function CaretPixel: TPoint;
    Procedure UpdateCaret;
    Procedure InsertText(Const AddText: String);
    Procedure DeleteSelection;
    Procedure DeleteRange(CharStart, CharCount: Integer);
    Function CharCount: Integer;
    Procedure ClampSelection;
    Function CanLayout: Boolean;
    Procedure EnsureScrollBar;
    Function MeasureAdvance(Const S: String): Integer;
  Protected
    Procedure Paint; Override;
    Procedure Resize; Override;
    Procedure FontChanged(Sender: TObject); Override;
    Procedure Loaded; Override;
    Procedure InitializeWnd; Override;
    Procedure KeyDown(Var Key: Word; Shift: TShiftState); Override;
    Procedure UTF8KeyPress(Var UTF8Key: TUTF8Char); Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure DblClick; Override;
    Procedure MouseMove(Shift: TShiftState; X, Y: Integer); Override;
    Function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; Override;
    Procedure DoEnter; Override;
    Procedure DoExit; Override;
    Procedure DoContextPopup(MousePos: TPoint; Var Handled: Boolean); Override;
    Function RealGetText: TCaption; Override;
    Procedure RealSetText(Const Value: TCaption); Override;
    Procedure Change; Virtual;
    Property OnChange: TNotifyEvent Read FOnChange Write FOnChange;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Rescan;
    Procedure Clear;
    Procedure SelectAll;
    Function GetTextLen: Integer; Override;
    Procedure CopyToClipboard;
    Procedure CutToClipboard;
    Procedure PasteFromClipboard;

    Property SelStart: Integer Read FSelStart Write SetSelStart;
    Property SelLength: Integer Read FSelLength Write SetSelLength;
    Property SelText: String Read GetSelText Write SetSelText;
  Published
    Property Align;
    Property Anchors;
    Property BorderSpacing;
    Property Color Default clWindow;
    Property Constraints;
    Property Enabled;
    Property Font;
    Property ParentFont;
    Property ParentShowHint;
    Property PopupMenu;
    Property ReadOnly: Boolean Read FReadOnly Write SetReadOnly Default False;
    Property ScrollBars: TScrollStyle Read FScrollBars Write SetScrollBars Default ssAutoVertical;
    Property ShowHint;
    Property TabOrder;
    Property TabStop Default True;
    Property Text;
    Property UseSharedConfig: Boolean Read FUseSharedConfig Write FUseSharedConfig Default True;
    Property Visible;
    Property WantReturns: Boolean Read FWantReturns Write SetWantReturns Default True;
    Property WantTabs: Boolean Read FWantTabs Write SetWantTabs Default False;
    Property WordWrap: Boolean Read FWordWrap Write SetWordWrap Default True;
    Property OnClick;
    Property OnDblClick;
    Property OnEnter;
    Property OnExit;
    Property OnKeyDown;
    Property OnKeyPress;
    Property OnKeyUp;
    Property OnMouseDown;
    Property OnMouseMove;
    Property OnMouseUp;
    Property OnResize;
    Property OnUTF8KeyPress;
  End;

Implementation

Uses
  Clipbrd, LCLIntf, LazUTF8, SpellCheckerConfig, SpellWordBreaker, SpellEngine, WorkflowLog;

Constructor TSpellMemo.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FUseSharedConfig := True;
  FWordWrap := True;
  FWantTabs := False;
  FWantReturns := True;
  FReadOnly := False;
  FScrollBars := ssAutoVertical;
  ControlStyle := ControlStyle + [csOpaque, csClickEvents, csDoubleClicks, csCaptureMouse];
  Color := clWindow;
  ParentColor := False;
  ParentFont := True;
  TabStop := True;
  DoubleBuffered := True;
  BorderStyle := bsSingle;
  Width := 200;
  Height := 80;
  FSpellItemCount := 0;
  FActiveStart := 0;
  FActiveLength := 0;
  FOwnedPopup := TPopupMenu.Create(Nil);
  FDebounce := TTimer.Create(Nil);
  FDebounce.Enabled := False;
  FDebounce.Interval := 200;
  FDebounce.OnTimer := @DebounceTimer;
  FCaretTimer := TTimer.Create(Nil);
  FCaretTimer.Enabled := False;
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := @CaretTimerTick;
  FCaretOn := False;
  FScrollBar := Nil;
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.RegisterChangedHandler(@ConfigChanged);
  FReady := True;
End;

Destructor TSpellMemo.Destroy;
Begin
  FReady := False;
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.UnregisterChangedHandler(@ConfigChanged);
  If Assigned(FHookedPopup) Then
    FHookedPopup.OnPopup := FHostPopupHandler;
  If Assigned(FDebounce) Then
    FDebounce.Enabled := False;
  If Assigned(FCaretTimer) Then
    FCaretTimer.Enabled := False;
  If Assigned(FScrollBar) Then
    Begin
      FScrollBar.OnChange := Nil;
      FScrollBar.Parent := Nil;
    End;
  FreeAndNil(FDebounce);
  FreeAndNil(FCaretTimer);
  FreeAndNil(FOwnedPopup);
  FreeAndNil(FScrollBar);
  Inherited Destroy;
End;

Function TSpellMemo.CanLayout: Boolean;
Begin
  Result := FReady And (Not (csLoading In ComponentState)) And (Not (csDestroying In ComponentState)) And
    HandleAllocated;
End;

Procedure TSpellMemo.EnsureScrollBar;
Begin
  If Assigned(FScrollBar) Or (Not FReady) Then
    Exit;
  FScrollBar := TScrollBar.Create(Nil);
  FScrollBar.Kind := sbVertical;
  FScrollBar.Width := 16;
  FScrollBar.Visible := False;
  FScrollBar.OnChange := @ScrollBarChange;
  FScrollBar.Parent := Self;
  FScrollBar.Align := alRight;
End;

Function TSpellMemo.RealGetText: TCaption;
Begin
  Result := FText;
End;

Procedure TSpellMemo.RealSetText(Const Value: TCaption);
Begin
  If FText = Value Then
    Exit;
  FText := Value;
  FSelStart := UTF8Length(FText);
  FSelLength := 0;
  FSelAnchor := FSelStart;
  If CanLayout Then
    Begin
      RebuildLayout;
      UpdateScrollBar;
    End;
  Invalidate;
  RestartDebounce;
  Change;
End;

Procedure TSpellMemo.Clear;
Begin
  Text := '';
End;

Procedure TSpellMemo.Loaded;
Begin
  Inherited Loaded;
  If csDesigning In ComponentState Then
    Exit;
  If FUseSharedConfig And Assigned(WorkflowSpellConfig) And (Not WorkflowSpellConfig.IsReady) Then
    WorkflowSpellConfig.Apply;
  EnsurePopupHook;
  If CanLayout Then
    Begin
      EnsureScrollBar;
      RebuildLayout;
      UpdateScrollBar;
    End;
  RestartDebounce;
End;

Procedure TSpellMemo.InitializeWnd;
Begin
  Inherited InitializeWnd;
  If CanLayout Then
    Begin
      EnsureScrollBar;
      RebuildLayout;
      UpdateScrollBar;
    End;
  If Not (csDesigning In ComponentState) Then
    RestartDebounce;
End;

Function TSpellMemo.SpellActive: Boolean;
Begin
  Result := FUseSharedConfig And Assigned(WorkflowSpellConfig) And WorkflowSpellConfig.IsReady And
    (Not (csDesigning In ComponentState));
End;

Procedure TSpellMemo.RestartDebounce;
Begin
  If (Not FReady) Or (Not Assigned(FDebounce)) Then
    Exit;
  FDebounce.Enabled := False;
  If SpellActive Then
    FDebounce.Enabled := True
  Else
    SetLength(FRanges, 0);
  If HandleAllocated Then
    Invalidate;
End;

Procedure TSpellMemo.ConfigChanged(Sender: TObject);
Begin
  RestartDebounce;
End;

Procedure TSpellMemo.DebounceTimer(Sender: TObject);
Begin
  FDebounce.Enabled := False;
  Rescan;
End;

Procedure TSpellMemo.Change;
Begin
  If Assigned(FOnChange) Then
    FOnChange(Self);
End;

Procedure TSpellMemo.SetWordWrap(Value: Boolean);
Begin
  If FWordWrap = Value Then
    Exit;
  FWordWrap := Value;
  If CanLayout Then
    Begin
      RebuildLayout;
      UpdateScrollBar;
    End;
  Invalidate;
End;

Procedure TSpellMemo.SetWantTabs(Value: Boolean);
Begin
  FWantTabs := Value;
End;

Procedure TSpellMemo.SetWantReturns(Value: Boolean);
Begin
  FWantReturns := Value;
End;

Procedure TSpellMemo.SetReadOnly(Value: Boolean);
Begin
  FReadOnly := Value;
End;

Procedure TSpellMemo.SetScrollBars(Value: TScrollStyle);
Begin
  If FScrollBars = Value Then
    Exit;
  FScrollBars := Value;
  If CanLayout Then
    Begin
      EnsureScrollBar;
      UpdateScrollBar;
      RebuildLayout;
    End;
  Invalidate;
End;

Function TSpellMemo.CharCount: Integer;
Begin
  Result := UTF8Length(FText);
End;

Procedure TSpellMemo.ClampSelection;
Var
  Count: Integer;
Begin
  Count := CharCount;
  If FSelStart < 0 Then
    FSelStart := 0;
  If FSelStart > Count Then
    FSelStart := Count;
  If FSelLength < 0 Then
    FSelLength := 0;
  If FSelStart + FSelLength > Count Then
    FSelLength := Count - FSelStart;
End;

Procedure TSpellMemo.SetSelStart(Value: Integer);
Begin
  FSelStart := Value;
  FSelLength := 0;
  ClampSelection;
  EnsureCaretInView;
  UpdateCaret;
  Invalidate;
End;

Procedure TSpellMemo.SetSelLength(Value: Integer);
Begin
  FSelLength := Value;
  ClampSelection;
  Invalidate;
End;

Function TSpellMemo.GetSelText: String;
Var
  ByteStart, ByteEnd: Integer;
Begin
  ClampSelection;
  ByteStart := SpellCharToByteIndex(FText, FSelStart);
  ByteEnd := SpellCharToByteIndex(FText, FSelStart + FSelLength);
  Result := Copy(FText, ByteStart, ByteEnd - ByteStart);
End;

Procedure TSpellMemo.SetSelText(Const Value: String);
Begin
  InsertText(Value);
End;

Procedure TSpellMemo.SelectAll;
Begin
  FSelStart := 0;
  FSelLength := CharCount;
  Invalidate;
End;

Function TSpellMemo.GetTextLen: Integer;
Begin
  { TWinControl.GetTextLen asks the native window, which this painted control
    never fills. Hosts such as the assistant popup use GetTextLen > 0. }
  Result := Length(FText);
End;

Procedure TSpellMemo.CopyToClipboard;
Begin
  If FSelLength > 0 Then
    Clipboard.AsText := SelText;
End;

Procedure TSpellMemo.CutToClipboard;
Begin
  If FReadOnly Then
    Exit;
  CopyToClipboard;
  DeleteSelection;
End;

Procedure TSpellMemo.PasteFromClipboard;
Begin
  If FReadOnly Then
    Exit;
  InsertText(Clipboard.AsText);
End;

Function TSpellMemo.TextAreaWidth: Integer;
Begin
  Result := ClientWidth - 6;
  If Assigned(FScrollBar) And FScrollBar.Visible Then
    Result := Result - FScrollBar.Width;
  If Result < 20 Then
    Result := 20;
End;

Function TSpellMemo.MeasureAdvance(Const S: String): Integer;
Begin
  { Full-string width so kerning pairs (dj, AV, …) match the painted run. }
  If S = '' Then
    Result := 0
  Else
    Result := Canvas.TextWidth(S);
End;

Function TSpellMemo.LineHeight: Integer;
Begin
  Result := 16;
  If Not CanLayout Then
    Exit;
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Hg') + 2;
  If Result < 12 Then
    Result := 12;
End;

Procedure TSpellMemo.RebuildLayout;
Var
  Para, Remain, Piece: String;
  ParaStart, RemainStart, Count, BreakAt, LastSpace, TextPos, WalkPos, CodeLen: Integer;
  UsedWidth, CharWidth, MaxWidth, RowTop, RowH: Integer;
  CodePoint: Cardinal;
Begin
  If Not CanLayout Then
    Exit;
  SetLength(FPaintLines, 0);
  Count := 0;
  RowTop := 3;
  RowH := LineHeight;
  MaxWidth := TextAreaWidth;
  Canvas.Font := Font;
  TextPos := 1;
  While True Do
    Begin
      ParaStart := TextPos;
      While (TextPos <= Length(FText)) And (FText[TextPos] <> #10) Do
        Inc(TextPos);
      Para := Copy(FText, ParaStart, TextPos - ParaStart);
      Remain := Para;
      RemainStart := ParaStart;
      If Remain = '' Then
        Begin
          If Count >= Length(FPaintLines) Then
            SetLength(FPaintLines, Count + 16);
          FPaintLines[Count].ByteStart := ParaStart;
          FPaintLines[Count].ByteLength := 0;
          FPaintLines[Count].Top := RowTop;
          FPaintLines[Count].Height := RowH;
          Inc(Count);
          Inc(RowTop, RowH);
        End
      Else
        While Remain <> '' Do
          Begin
            If Not FWordWrap Then
              BreakAt := Length(Remain)
            Else
              Begin
                UsedWidth := 0;
                BreakAt := 0;
                LastSpace := 0;
                WalkPos := 1;
                While WalkPos <= Length(Remain) Do
                  Begin
                    CodePoint := UTF8CodepointToUnicode(@Remain[WalkPos], CodeLen);
                    If CodeLen <= 0 Then
                      Break;
                    Piece := Copy(Remain, WalkPos, CodeLen);
                    CharWidth := Canvas.TextWidth(Piece);
                    If (UsedWidth + CharWidth > MaxWidth) And (BreakAt > 0) Then
                      Begin
                        If LastSpace > 0 Then
                          BreakAt := LastSpace;
                        Break;
                      End;
                    UsedWidth := UsedWidth + CharWidth;
                    BreakAt := WalkPos + CodeLen - 1;
                    If (Remain[WalkPos] = ' ') Or (CodePoint = 9) Then
                      LastSpace := BreakAt;
                    Inc(WalkPos, CodeLen);
                  End;
                If BreakAt <= 0 Then
                  BreakAt := Length(Remain);
              End;
            If Count >= Length(FPaintLines) Then
              SetLength(FPaintLines, Count + 16);
            FPaintLines[Count].ByteStart := RemainStart;
            FPaintLines[Count].ByteLength := BreakAt;
            FPaintLines[Count].Top := RowTop;
            FPaintLines[Count].Height := RowH;
            Inc(Count);
            Inc(RowTop, RowH);
            Inc(RemainStart, BreakAt);
            Delete(Remain, 1, BreakAt);
          End;
      If TextPos > Length(FText) Then
        Break;
      If FText[TextPos] = #10 Then
        Inc(TextPos);
    End;
  If Count = 0 Then
    Begin
      SetLength(FPaintLines, 1);
      FPaintLines[0].ByteStart := 1;
      FPaintLines[0].ByteLength := 0;
      FPaintLines[0].Top := 3;
      FPaintLines[0].Height := RowH;
      Count := 1;
      RowTop := 3 + RowH;
    End;
  SetLength(FPaintLines, Count);
  FContentHeight := RowTop + 3;
End;

Procedure TSpellMemo.UpdateScrollBar;
Var
  NeedBar: Boolean;
  PageSize, MaxPos: Integer;
Begin
  If Not CanLayout Then
    Exit;
  EnsureScrollBar;
  If Not Assigned(FScrollBar) Then
    Exit;
  NeedBar := (FScrollBars In [ssVertical, ssAutoVertical, ssBoth, ssAutoBoth]) And
    (FContentHeight > ClientHeight);
  If FScrollBars In [ssVertical, ssBoth] Then
    NeedBar := True;
  If FScrollBar.Visible <> NeedBar Then
    Begin
      FUpdatingScroll := True;
      FScrollBar.Visible := NeedBar;
      FUpdatingScroll := False;
      RebuildLayout;
    End;
  If Not NeedBar Then
    Exit;
  PageSize := ClientHeight;
  If PageSize < 1 Then
    PageSize := 1;
  MaxPos := FContentHeight - PageSize;
  If MaxPos < 0 Then
    MaxPos := 0;
  FUpdatingScroll := True;
  FScrollBar.Min := 0;
  FScrollBar.Max := MaxPos + PageSize;
  FScrollBar.PageSize := PageSize;
  If FScrollBar.Position > MaxPos Then
    FScrollBar.Position := MaxPos;
  FUpdatingScroll := False;
End;

Procedure TSpellMemo.ScrollBarChange(Sender: TObject);
Begin
  If FUpdatingScroll Then
    Exit;
  Invalidate;
  UpdateCaret;
End;

Function TSpellMemo.ScrollY: Integer;
Begin
  Result := 0;
  If Assigned(FScrollBar) And FScrollBar.Visible Then
    Result := FScrollBar.Position;
End;

Procedure TSpellMemo.EnsureCaretInView;
Var
  Pixel: TPoint;
  Page: Integer;
Begin
  Pixel := CaretPixel;
  Page := ClientHeight;
  If Pixel.Y < 0 Then
    If Assigned(FScrollBar) And FScrollBar.Visible Then
      FScrollBar.Position := ScrollY + Pixel.Y - 4;
  If Pixel.Y + LineHeight > Page Then
    If Assigned(FScrollBar) And FScrollBar.Visible Then
      FScrollBar.Position := ScrollY + (Pixel.Y + LineHeight - Page) + 4;
End;

Function TSpellMemo.CaretPixel: TPoint;
Var
  CaretByte, LineIndex, PrefixLen: Integer;
  Prefix: String;
Begin
  Result.X := 3;
  Result.Y := 3 - ScrollY;
  CaretByte := SpellCharToByteIndex(FText, FSelStart + FSelLength);
  Canvas.Font := Font;
  For LineIndex := 0 To High(FPaintLines) Do
    If (CaretByte >= FPaintLines[LineIndex].ByteStart) And
      (CaretByte <= FPaintLines[LineIndex].ByteStart + FPaintLines[LineIndex].ByteLength) Then
      Begin
        PrefixLen := CaretByte - FPaintLines[LineIndex].ByteStart;
        Prefix := Copy(FText, FPaintLines[LineIndex].ByteStart, PrefixLen);
        Result.X := 3 + MeasureAdvance(Prefix);
        Result.Y := FPaintLines[LineIndex].Top - ScrollY;
        Exit;
      End;
  If Length(FPaintLines) > 0 Then
    Begin
      Result.Y := FPaintLines[High(FPaintLines)].Top - ScrollY;
      Result.X := 3 + MeasureAdvance(Copy(FText, FPaintLines[High(FPaintLines)].ByteStart,
        FPaintLines[High(FPaintLines)].ByteLength));
    End;
End;

Procedure TSpellMemo.ResetCaretBlink;
Begin
  FCaretOn := True;
  If Assigned(FCaretTimer) Then
    Begin
      FCaretTimer.Enabled := False;
      FCaretTimer.Enabled := Focused And (Not (csDesigning In ComponentState));
    End;
End;

Procedure TSpellMemo.CaretTimerTick(Sender: TObject);
Begin
  If (Not FReady) Or (csDestroying In ComponentState) Then
    Exit;
  FCaretOn := Not FCaretOn;
  If HandleAllocated Then
    Invalidate;
End;

Procedure TSpellMemo.UpdateCaret;
Begin
  ResetCaretBlink;
  If HandleAllocated Then
    Invalidate;
End;

Function TSpellMemo.CharIndexAtPoint(X, Y: Integer): Integer;
Var
  LineIndex, Index, Best, CodeLen, LeftW, RightW: Integer;
  AbsY: Integer;
  LineText: String;
Begin
  Result := 0;
  AbsY := Y + ScrollY;
  Canvas.Font := Font;
  If Length(FPaintLines) = 0 Then
    Exit;
  LineIndex := 0;
  While (LineIndex < High(FPaintLines)) And
    (AbsY >= FPaintLines[LineIndex].Top + FPaintLines[LineIndex].Height) Do
    Inc(LineIndex);
  LineText := Copy(FText, FPaintLines[LineIndex].ByteStart, FPaintLines[LineIndex].ByteLength);
  Best := FPaintLines[LineIndex].ByteStart;
  Index := 1;
  While Index <= Length(LineText) Do
    Begin
      UTF8CodepointToUnicode(@LineText[Index], CodeLen);
      If CodeLen <= 0 Then
        Break;
      LeftW := 3 + MeasureAdvance(Copy(LineText, 1, Index - 1));
      RightW := 3 + MeasureAdvance(Copy(LineText, 1, Index + CodeLen - 1));
      If X < (LeftW + RightW) Div 2 Then
        Break;
      Inc(Index, CodeLen);
      Best := FPaintLines[LineIndex].ByteStart + Index - 1;
    End;
  Result := SpellByteToCharOffset(FText, Best);
End;

Procedure TSpellMemo.MoveCaret(NewStart: Integer; ExtendSel: Boolean);
Begin
  If NewStart < 0 Then
    NewStart := 0;
  If NewStart > CharCount Then
    NewStart := CharCount;
  If ExtendSel Then
    Begin
      If NewStart >= FSelAnchor Then
        Begin
          FSelStart := FSelAnchor;
          FSelLength := NewStart - FSelAnchor;
        End
      Else
        Begin
          FSelStart := NewStart;
          FSelLength := FSelAnchor - NewStart;
        End;
    End
  Else
    Begin
      FSelStart := NewStart;
      FSelLength := 0;
      FSelAnchor := NewStart;
    End;
  ClampSelection;
  EnsureCaretInView;
  UpdateCaret;
  Invalidate;
  RestartDebounce;
End;

Procedure TSpellMemo.DeleteRange(CharStart, CharCount: Integer);
Var
  ByteStart, ByteEnd: Integer;
Begin
  If (CharCount <= 0) Or FReadOnly Then
    Exit;
  ByteStart := SpellCharToByteIndex(FText, CharStart);
  ByteEnd := SpellCharToByteIndex(FText, CharStart + CharCount);
  System.Delete(FText, ByteStart, ByteEnd - ByteStart);
  FSelStart := CharStart;
  FSelLength := 0;
  RebuildLayout;
  UpdateScrollBar;
  EnsureCaretInView;
  Invalidate;
  RestartDebounce;
  Change;
End;

Procedure TSpellMemo.DeleteSelection;
Begin
  If FSelLength > 0 Then
    DeleteRange(FSelStart, FSelLength);
End;

Procedure TSpellMemo.InsertText(Const AddText: String);
Var
  Clean: String;
  ByteStart, ByteEnd: Integer;
Begin
  If FReadOnly Then
    Exit;
  Clean := StringReplace(AddText, #13#10, #10, [rfReplaceAll]);
  Clean := StringReplace(Clean, #13, #10, [rfReplaceAll]);
  If FSelLength > 0 Then
    Begin
      ByteStart := SpellCharToByteIndex(FText, FSelStart);
      ByteEnd := SpellCharToByteIndex(FText, FSelStart + FSelLength);
      System.Delete(FText, ByteStart, ByteEnd - ByteStart);
    End
  Else
    ByteStart := SpellCharToByteIndex(FText, FSelStart);
  System.Insert(Clean, FText, ByteStart);
  FSelStart := FSelStart + UTF8Length(Clean);
  FSelLength := 0;
  RebuildLayout;
  UpdateScrollBar;
  EnsureCaretInView;
  Invalidate;
  RestartDebounce;
  Change;
End;

Procedure TSpellMemo.UTF8KeyPress(Var UTF8Key: TUTF8Char);
Begin
  Inherited UTF8KeyPress(UTF8Key);
  If (UTF8Key = '') Or FReadOnly Then
    Exit;
  If (UTF8Key = #8) Or (UTF8Key = #127) Then
    Begin
      UTF8Key := '';
      Exit;
    End;
  If (UTF8Key = #9) And (Not FWantTabs) Then
    Exit;
  If (UTF8Key = #13) Or (UTF8Key = #10) Then
    Begin
      If FWantReturns Then
        InsertText(#10);
      UTF8Key := '';
      Exit;
    End;
  If UTF8Key >= ' ' Then
    Begin
      InsertText(UTF8Key);
      UTF8Key := '';
    End;
End;

Procedure TSpellMemo.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  Extend: Boolean;
  Caret, LineIndex, Target, CaretByte: Integer;
Begin
  Inherited KeyDown(Key, Shift);
  Extend := ssShift In Shift;
  Caret := FSelStart + FSelLength;
  If FSelLength = 0 Then
    Caret := FSelStart;
  Case Key Of
    VK_LEFT:
      Begin
        If (Not Extend) And (FSelLength > 0) Then
          MoveCaret(FSelStart, False)
        Else
          MoveCaret(Caret - 1, Extend);
        Key := 0;
      End;
    VK_RIGHT:
      Begin
        If (Not Extend) And (FSelLength > 0) Then
          MoveCaret(FSelStart + FSelLength, False)
        Else
          MoveCaret(Caret + 1, Extend);
        Key := 0;
      End;
    VK_HOME:
      Begin
        MoveCaret(0, Extend);
        Key := 0;
      End;
    VK_END:
      Begin
        MoveCaret(CharCount, Extend);
        Key := 0;
      End;
    VK_UP, VK_DOWN:
      Begin
        CaretByte := SpellCharToByteIndex(FText, Caret);
        LineIndex := 0;
        For Target := 0 To High(FPaintLines) Do
          If (CaretByte >= FPaintLines[Target].ByteStart) And
            (CaretByte <= FPaintLines[Target].ByteStart + FPaintLines[Target].ByteLength) Then
            LineIndex := Target;
        If Key = VK_UP Then
          Dec(LineIndex)
        Else
          Inc(LineIndex);
        If LineIndex < 0 Then
          LineIndex := 0;
        If LineIndex > High(FPaintLines) Then
          LineIndex := High(FPaintLines);
        MoveCaret(CharIndexAtPoint(CaretPixel.X, FPaintLines[LineIndex].Top - ScrollY + 1), Extend);
        Key := 0;
      End;
    VK_BACK:
      Begin
        If FReadOnly Then
          Exit;
        If FSelLength > 0 Then
          DeleteSelection
        Else If FSelStart > 0 Then
          DeleteRange(FSelStart - 1, 1);
        Key := 0;
      End;
    VK_DELETE:
      Begin
        If FReadOnly Then
          Exit;
        If FSelLength > 0 Then
          DeleteSelection
        Else If FSelStart < CharCount Then
          DeleteRange(FSelStart, 1);
        Key := 0;
      End;
    VK_A:
      If ssCtrl In Shift Then
        Begin
          SelectAll;
          Key := 0;
        End;
    VK_C:
      If ssCtrl In Shift Then
        Begin
          CopyToClipboard;
          Key := 0;
        End;
    VK_X:
      If ssCtrl In Shift Then
        Begin
          CutToClipboard;
          Key := 0;
        End;
    VK_V:
      If ssCtrl In Shift Then
        Begin
          PasteFromClipboard;
          Key := 0;
        End;
  Else
  End;
End;

Procedure TSpellMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Var
  NewPos: Integer;
Begin
  Inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  EnsurePopupHook;
  FDragOrigin := Point(X, Y);
  { The second button-down of a double-click must not move the caret. LCL then
    fires DblClick; any following MouseMove would otherwise drag-select. }
  If (Button = mbLeft) And (ssDouble In Shift) Then
    Begin
      FIgnoreDragSelect := True;
      Exit;
    End;
  FIgnoreDragSelect := False;
  NewPos := CharIndexAtPoint(X, Y);
  MoveCaret(NewPos, ssShift In Shift);
End;

Procedure TSpellMemo.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseUp(Button, Shift, X, Y);
  If Button = mbLeft Then
    FIgnoreDragSelect := False;
End;

Procedure TSpellMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseMove(Shift, X, Y);
  If Not (ssLeft In Shift) Or FIgnoreDragSelect Then
    Exit;
  If (Abs(X - FDragOrigin.X) < Mouse.DragThreshold) And
    (Abs(Y - FDragOrigin.Y) < Mouse.DragThreshold) Then
    Exit;
  MoveCaret(CharIndexAtPoint(X, Y), True);
End;

Function TSpellMemo.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
Begin
  Result := True;
  If Assigned(FScrollBar) And FScrollBar.Visible Then
    FScrollBar.Position := FScrollBar.Position - (WheelDelta Div 120) * LineHeight;
  Invalidate;
End;

Procedure TSpellMemo.DoEnter;
Begin
  Inherited DoEnter;
  UpdateCaret;
  Invalidate;
End;

Procedure TSpellMemo.DoExit;
Begin
  Inherited DoExit;
  If Assigned(FCaretTimer) Then
    FCaretTimer.Enabled := False;
  FCaretOn := False;
  If HandleAllocated Then
    Invalidate;
End;

Procedure TSpellMemo.FontChanged(Sender: TObject);
Begin
  Inherited FontChanged(Sender);
  If Not CanLayout Then
    Exit;
  RebuildLayout;
  UpdateScrollBar;
  Invalidate;
End;

Procedure TSpellMemo.Resize;
Begin
  Inherited Resize;
  If Not CanLayout Then
    Exit;
  RebuildLayout;
  UpdateScrollBar;
  Invalidate;
End;

Procedure TSpellMemo.Paint;
Var
  LineIndex, Y, H, X0, SX1, SX2, SelLo, SelHi, ClipLo, ClipHi: Integer;
  FirstChar, AfterChar, Byte0, Byte1, SavedDC: Integer;
  Pixel: TPoint;
  LineText: String;
  RangeIndex, RangeStart, RangeEnd, LineStart, LineEnd, U1, U2: Integer;
Begin
  If Not FReady Then
    Exit;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  ClampSelection;
  SelLo := FSelStart;
  SelHi := FSelStart + FSelLength;
  If SelHi < SelLo Then
    Begin
      FirstChar := SelLo;
      SelLo := SelHi;
      SelHi := FirstChar;
    End;
  X0 := 3;
  For LineIndex := 0 To High(FPaintLines) Do
    Begin
      Y := FPaintLines[LineIndex].Top - ScrollY;
      H := FPaintLines[LineIndex].Height;
      If (Y + H < 0) Or (Y > ClientHeight) Then
        Continue;
      LineStart := FPaintLines[LineIndex].ByteStart;
      LineEnd := LineStart + FPaintLines[LineIndex].ByteLength;
      LineText := Copy(FText, LineStart, FPaintLines[LineIndex].ByteLength);
      ClipLo := 0;
      ClipHi := 0;
      SX1 := 0;
      SX2 := 0;
      If (FSelLength > 0) And (LineText <> '') Then
        Begin
          FirstChar := SpellByteToCharOffset(FText, LineStart);
          AfterChar := SpellByteToCharOffset(FText, LineEnd);
          ClipLo := SelLo;
          ClipHi := SelHi;
          If ClipLo < FirstChar Then
            ClipLo := FirstChar;
          If ClipHi > AfterChar Then
            ClipHi := AfterChar;
          If ClipHi > ClipLo Then
            Begin
              Byte0 := SpellCharToByteIndex(FText, ClipLo) - LineStart;
              Byte1 := SpellCharToByteIndex(FText, ClipHi) - LineStart;
              If Byte0 < 0 Then
                Byte0 := 0;
              If Byte1 < 0 Then
                Byte1 := 0;
              If Byte0 > Length(LineText) Then
                Byte0 := Length(LineText);
              If Byte1 > Length(LineText) Then
                Byte1 := Length(LineText);
              SX1 := X0 + MeasureAdvance(Copy(LineText, 1, Byte0));
              SX2 := X0 + MeasureAdvance(Copy(LineText, 1, Byte1));
              Canvas.Brush.Style := bsSolid;
              Canvas.Brush.Color := clHighlight;
              Canvas.FillRect(Rect(SX1, Y, SX2, Y + H));
            End;
        End;
      { One run, transparent brush: per-glyph backgrounds clip kerning overhangs. }
      If LineText <> '' Then
        Begin
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := Font.Color;
          Canvas.TextOut(X0, Y, LineText);
          If (FSelLength > 0) And (ClipHi > ClipLo) Then
            Begin
              SavedDC := SaveDC(Canvas.Handle);
              Try
                IntersectClipRect(Canvas.Handle, SX1, Y, SX2, Y + H);
                Canvas.Font.Color := clHighlightText;
                Canvas.TextOut(X0, Y, LineText);
              Finally
                RestoreDC(Canvas.Handle, SavedDC);
              End;
              Canvas.Font.Color := Font.Color;
            End;
        End;
      If SpellActive Then
        For RangeIndex := 0 To High(FRanges) Do
          Begin
            RangeStart := FRanges[RangeIndex].UTF8Start;
            RangeEnd := RangeStart + FRanges[RangeIndex].UTF8Length;
            If (RangeEnd <= LineStart) Or (RangeStart >= LineEnd) Then
              Continue;
            If RangeStart < LineStart Then
              RangeStart := LineStart;
            If RangeEnd > LineEnd Then
              RangeEnd := LineEnd;
            U1 := X0 + MeasureAdvance(Copy(FText, LineStart, RangeStart - LineStart));
            U2 := X0 + MeasureAdvance(Copy(FText, LineStart, RangeEnd - LineStart));
            DrawErrorUnderline(Canvas, U1, U2, Y + H - 3);
          End;
    End;
  If Focused And FCaretOn And (FSelLength = 0) And (Not (csDesigning In ComponentState)) Then
    Begin
      Pixel := CaretPixel;
      Canvas.Pen.Color := Font.Color;
      Canvas.Pen.Width := 1;
      Canvas.MoveTo(Pixel.X, Pixel.Y + 1);
      Canvas.LineTo(Pixel.X, Pixel.Y + LineHeight - 1);
    End;
End;

Procedure TSpellMemo.Rescan;
Var
  Tokens: TSpellTokenArray;
  Index, Count, CaretByte: Integer;
Begin
  SetLength(FRanges, 0);
  If Not SpellActive Then
    Begin
      Invalidate;
      Exit;
    End;
  CaretByte := SpellCharToByteIndex(FText, FSelStart + FSelLength);
  Tokens := SpellBreakWords(FText);
  Count := 0;
  For Index := 0 To High(Tokens) Do
    Begin
      If (FSelLength = 0) And (Not SpellWordIsComplete(FText, Tokens[Index], CaretByte)) Then
        Continue;
      If Not WorkflowSpellConfig.IsWordCorrect(Tokens[Index].Text) Then
        Begin
          If Count >= Length(FRanges) Then
            SetLength(FRanges, Count + 16);
          FRanges[Count].UTF8Start := Tokens[Index].ByteStart;
          FRanges[Count].UTF8Length := Tokens[Index].ByteLength;
          Inc(Count);
        End;
    End;
  SetLength(FRanges, Count);
  If Assigned(WorkflowLogger) Then
    WorkflowLogger.Info('SpellMemo', Format('Rescan words=%d errors=%d status=%s',
      [Length(Tokens), Count, WorkflowSpellConfig.LastStatus]));
  Invalidate;
End;

Procedure TSpellMemo.EnsureEditMenu;
Var
  Sep: TMenuItem;
Begin
  If (Not Assigned(FOwnedPopup)) Or Assigned(FEditCutItem) Then
    Exit;
  FEditCutItem := TMenuItem.Create(FOwnedPopup);
  FEditCutItem.Caption := 'Cut';
  FEditCutItem.ShortCut := ShortCut(Ord('X'), [ssCtrl]);
  FEditCutItem.OnClick := @EditCutClick;
  FOwnedPopup.Items.Add(FEditCutItem);
  FEditCopyItem := TMenuItem.Create(FOwnedPopup);
  FEditCopyItem.Caption := 'Copy';
  FEditCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  FEditCopyItem.OnClick := @EditCopyClick;
  FOwnedPopup.Items.Add(FEditCopyItem);
  FEditPasteItem := TMenuItem.Create(FOwnedPopup);
  FEditPasteItem.Caption := 'Paste';
  FEditPasteItem.ShortCut := ShortCut(Ord('V'), [ssCtrl]);
  FEditPasteItem.OnClick := @EditPasteClick;
  FOwnedPopup.Items.Add(FEditPasteItem);
  Sep := TMenuItem.Create(FOwnedPopup);
  Sep.Caption := '-';
  FOwnedPopup.Items.Add(Sep);
  FEditSelectAllItem := TMenuItem.Create(FOwnedPopup);
  FEditSelectAllItem.Caption := 'Select All';
  FEditSelectAllItem.ShortCut := ShortCut(Ord('A'), [ssCtrl]);
  FEditSelectAllItem.OnClick := @EditSelectAllClick;
  FOwnedPopup.Items.Add(FEditSelectAllItem);
End;

Procedure TSpellMemo.EditCutClick(Sender: TObject);
Begin
  CutToClipboard;
End;

Procedure TSpellMemo.EditCopyClick(Sender: TObject);
Begin
  CopyToClipboard;
End;

Procedure TSpellMemo.EditPasteClick(Sender: TObject);
Begin
  PasteFromClipboard;
End;

Procedure TSpellMemo.EditSelectAllClick(Sender: TObject);
Begin
  SelectAll;
End;

Procedure TSpellMemo.UpdateEditMenu;
Var
  HasSel, CanEdit: Boolean;
Begin
  HasSel := FSelLength > 0;
  CanEdit := Not FReadOnly;
  If Assigned(FEditCutItem) Then
    FEditCutItem.Enabled := HasSel And CanEdit;
  If Assigned(FEditCopyItem) Then
    FEditCopyItem.Enabled := HasSel;
  If Assigned(FEditPasteItem) Then
    FEditPasteItem.Enabled := CanEdit And Clipboard.HasFormat(CF_TEXT);
  If Assigned(FEditSelectAllItem) Then
    FEditSelectAllItem.Enabled := FText <> '';
End;

Procedure TSpellMemo.EnsurePopupHook;
Begin
  If PopupMenu = Nil Then
    Begin
      EnsureEditMenu;
      PopupMenu := FOwnedPopup;
    End;
  If PopupMenu = FHookedPopup Then
    Exit;
  If Assigned(FHookedPopup) Then
    FHookedPopup.OnPopup := FHostPopupHandler;
  FHookedPopup := PopupMenu;
  FHostPopupHandler := Nil;
  If Assigned(FHookedPopup) Then
    Begin
      FHostPopupHandler := FHookedPopup.OnPopup;
      FHookedPopup.OnPopup := @PopupPopup;
    End;
End;

Procedure TSpellMemo.DoContextPopup(MousePos: TPoint; Var Handled: Boolean);
Begin
  EnsurePopupHook;
  Inherited DoContextPopup(MousePos, Handled);
End;

Procedure TSpellMemo.LocateTokenAtCaret;
Var
  BytePos: Integer;
  Token: TSpellToken;
Begin
  FActiveToken := '';
  FActiveStart := 0;
  FActiveLength := 0;
  BytePos := SpellCharToByteIndex(FText, FSelStart + FSelLength);
  If SpellTokenAt(FText, BytePos, Token) Then
    Begin
      FActiveToken := Token.Text;
      FActiveStart := Token.ByteStart;
      FActiveLength := Token.ByteLength;
    End;
End;

Procedure TSpellMemo.ClearSpellMenu(Menu: TPopupMenu);
Begin
  If Not Assigned(Menu) Then
    Exit;
  While (FSpellItemCount > 0) And (Menu.Items.Count > 0) Do
    Begin
      Menu.Items[0].Free;
      Dec(FSpellItemCount);
    End;
  FSpellItemCount := 0;
End;

Procedure TSpellMemo.RebuildSpellMenu(Menu: TPopupMenu);
Var
  Suggestions: TSpellStringArray;
  Index: Integer;
  Item: TMenuItem;
Begin
  ClearSpellMenu(Menu);
  If Not Assigned(Menu) Or Not SpellActive Then
    Exit;
  LocateTokenAtCaret;
  If (FActiveToken = '') Or WorkflowSpellConfig.IsWordCorrect(FActiveToken) Then
    Exit;
  Suggestions := WorkflowSpellConfig.GetSuggestions(FActiveToken, 12);
  For Index := 0 To High(Suggestions) Do
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := Suggestions[Index];
      Item.OnClick := @SuggestionClick;
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
  If FSpellItemCount > 0 Then
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := '-';
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
  Item := TMenuItem.Create(Menu);
  Item.Caption := 'Ignore "' + FActiveToken + '"';
  Item.OnClick := @IgnoreClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  Item := TMenuItem.Create(Menu);
  Item.Caption := 'Add "' + FActiveToken + '" to dictionary';
  Item.OnClick := @AddClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  If Menu.Items.Count > FSpellItemCount Then
    Begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := '-';
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
End;

Procedure TSpellMemo.PopupPopup(Sender: TObject);
Begin
  RebuildSpellMenu(Sender As TPopupMenu);
  If Sender = FOwnedPopup Then
    UpdateEditMenu;
  If Assigned(FHostPopupHandler) Then
    FHostPopupHandler(Sender);
End;

Procedure TSpellMemo.DblClick;
Var
  Token: TSpellToken;
  BytePos, CharStart, CharEnd: Integer;
Begin
  Inherited DblClick;
  FIgnoreDragSelect := True;
  BytePos := SpellCharToByteIndex(FText, FSelStart + FSelLength);
  If Not SpellRawTokenAt(FText, BytePos, Token) Then
    Exit;
  CharStart := SpellByteToCharOffset(FText, Token.ByteStart);
  CharEnd := SpellByteToCharOffset(FText, Token.ByteStart + Token.ByteLength);
  FSelStart := CharStart;
  FSelLength := CharEnd - CharStart;
  FSelAnchor := CharStart;
  ResetCaretBlink;
  Invalidate;
  RestartDebounce;
End;

Procedure TSpellMemo.ReplaceActiveWord(Const NewText: String);
Var
  CharStart, CharEnd: Integer;
Begin
  If (FActiveStart < 1) Or (FActiveLength <= 0) Then
    Exit;
  CharStart := SpellByteToCharOffset(FText, FActiveStart);
  CharEnd := SpellByteToCharOffset(FText, FActiveStart + FActiveLength);
  FSelStart := CharStart;
  FSelLength := CharEnd - CharStart;
  InsertText(NewText);
End;

Procedure TSpellMemo.SuggestionClick(Sender: TObject);
Begin
  If Sender Is TMenuItem Then
    ReplaceActiveWord(StringReplace(TMenuItem(Sender).Caption, '&', '', [rfReplaceAll]));
End;

Procedure TSpellMemo.IgnoreClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    WorkflowSpellConfig.IgnoreWord(FActiveToken);
End;

Procedure TSpellMemo.AddClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    WorkflowSpellConfig.AddToPersonal(FActiveToken);
End;

Initialization

RegisterClass(TSpellMemo);

End.
