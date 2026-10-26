Unit SpellMemo;

{ Portable LCL memo with optional Hunspell/ASpell markup (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Wrap layout, caret/selection,
  undo grouping and spell markup are one painted control so edits and
  underlines stay widgetset-free. Reviewed 2026-10-26: no hidden sibling material. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Controls, StdCtrls, Menus, ExtCtrls, Graphics, Forms, LCLType, LMessages,
  SpellMemoMarkup, SpellWordBreaker;

Type
  TSpellPaintLine = Record
    ByteStart: Integer;
    ByteLength: Integer;
    Top: Integer;
    Height: Integer;
  End;
  TSpellPaintLineArray = Array Of TSpellPaintLine;
  TSpellParagraphLayout = Class
    Text: String;
    Lines: TSpellPaintLineArray;
  End;
  TSpellEditKind = (ekTyping, ekBackspace, ekForwardDelete, ekPaste, ekDiscrete);
  TSpellUndoEntry = Record
    CharStart: Integer;
    Removed: String;
    Inserted: String;
    UndoSelStart: Integer;
    UndoSelLength: Integer;
    RedoSelStart: Integer;
    RedoSelLength: Integer;
    Kind: TSpellEditKind;
  End;

  TSpellMemo = Class(TCustomControl)
  Private
    FText: String;
    FTokenText: String;
    FTokens: TSpellTokenArray;
    FLayoutCache: TStringList;
    FLayoutWidth, FLayoutHeight, FLayoutBytes: Integer;
    FLayoutWrap: Boolean;
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
    FOnPaste: TNotifyEvent;
    FDebounce: TTimer;
    FInputLayoutTimer: TTimer;
    FInputLayoutPending: Boolean;
    FCaretTimer: TTimer;
    FCaretOn: Boolean;
    FOwnsCaret: Boolean;
    FHookedForm: TCustomForm;
    FSavedFormWindowProc: TWndMethod;
    FFocusHooks: Boolean;
    FRanges: TSpellUnderlineRangeArray;
    FOwnedPopup: TPopupMenu;
    FSpellItemCount: Integer;
    FSpellItems: TFPList;
    FSpellSuggestions: TStringList; { parallel to FSpellItems; empty for separators and commands }
    FActiveToken: String;
    FActiveStart: Integer;
    FActiveLength: Integer;
    FHostPopupHandler: TNotifyEvent;
    FHookedPopup: TPopupMenu;
    FEditUndoItem: TMenuItem;
    FEditRedoItem: TMenuItem;
    FEditCutItem: TMenuItem;
    FEditCopyItem: TMenuItem;
    FEditPasteItem: TMenuItem;
    FEditSelectAllItem: TMenuItem;
    FUndoStack: Array Of TSpellUndoEntry;
    FUndoIndex: Integer;
    FApplyingHistory: Boolean;
    FLastEditTick: QWord;
    FMenuHistory: Boolean;
    FPaintLines: TSpellPaintLineArray;
    FContentHeight: Integer;
    FScrollBar: TScrollBar;
    FUpdatingScroll: Boolean;
    FReady: Boolean;
    FIgnoreDragSelect: Boolean;
    FDragOrigin: TPoint;
    Procedure UnhookPopup;
    Procedure DebounceTimer(Sender: TObject);
    Procedure CaretTimerTick(Sender: TObject);
    Procedure ResetCaretBlink;
    Procedure AcquireCaret;
    Function CaretIsActive: Boolean;
    Procedure RefreshCaretForFocus;
    Procedure EnsureCaretFocusWatch;
    Procedure InstallFocusHooks;
    Procedure RemoveFocusHooks;
    Procedure HookHostForm;
    Procedure UnhookHostForm;
    Procedure HostFormWindowProc(Var Message: TLMessage);
    Procedure ApplicationFocusChanged(Sender: TObject);
    Procedure ScreenActiveFormChanged(Sender: TObject; Form: TCustomForm);
    Procedure ScreenActiveControlChanged(Sender: TObject; LastControl: TControl);
    Procedure ConfigChanged(Sender: TObject);
    Procedure RestartDebounce;
    Procedure ClearSpellMenu(Menu: TPopupMenu);
    Procedure DetachSpellItem(Item: TObject);
    Procedure RebuildSpellMenu(Menu: TPopupMenu);
    Procedure IgnoreClick(Sender: TObject);
    Procedure AddClick(Sender: TObject);
    Procedure PopupPopup(Sender: TObject);
    Procedure EnsurePopupHook;
    Procedure EnsureEditMenu;
    Procedure UpdateEditMenu;
    Procedure EditUndoClick(Sender: TObject);
    Procedure EditRedoClick(Sender: TObject);
    Procedure EditCutClick(Sender: TObject);
    Procedure EditCopyClick(Sender: TObject);
    Procedure EditPasteClick(Sender: TObject);
    Procedure EditSelectAllClick(Sender: TObject);
    Procedure ClearUndoHistory;
    Procedure ClearMenuHistory(Data: PtrInt);
    Procedure RememberEdit(Const Entry: TSpellUndoEntry);
    Procedure ApplyTextChange(CharStart, RemoveCount: Integer; Const Inserted: String; NewSelStart, NewSelLength: Integer);
    Procedure ReplaceRange(CharStart, RemoveCount: Integer; Const Inserted: String; Kind: TSpellEditKind);
    Function SpellActive: Boolean;
    Procedure ReplaceActiveWord(Const NewText: String);
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
    Procedure ClearLayoutCache;
    Procedure RebuildLayout;
    Procedure QueueInputLayout;
    Procedure FlushInputLayout;
    Procedure InputLayoutTimerTick(Sender: TObject);
    Procedure UpdateScrollBar;
    Procedure ScrollBarChange(Sender: TObject);
    Function ScrollY: Integer;
    Procedure EnsureCaretInView;
    Procedure MoveCaret(NewStart: Integer; ExtendSel: Boolean);
    Function CaretCharIndex: Integer;
    Function ByteBelongsToPaintLine(LineIndex, CaretByte: Integer): Boolean;
    Function CharIndexAtPoint(X, Y: Integer): Integer;
    Function CaretPixel: TPoint;
    Procedure UpdateCaret;
    Procedure InsertText(Const AddText: String);
    Procedure InsertText(Const AddText: String; Kind: TSpellEditKind);
    Procedure DeleteSelection;
    Procedure DeleteRange(CharStart, CharCount: Integer; Kind: TSpellEditKind);
    Function CharCount: Integer;
    Procedure ClampSelection;
    Function CanLayout: Boolean;
    Procedure EnsureScrollBar;
    Function MeasureAdvance(Const S: String): Integer;
  Protected
    Procedure LocateTokenAtCaret;
    Function AddSpellSuggestion(Menu: TPopupMenu; Const Suggestion: String): TMenuItem;
    Procedure SuggestionClick(Sender: TObject);
    Procedure Notification(AComponent: TComponent; Operation: TOperation); Override;
    Procedure Paint; Override;
    Procedure Resize; Override;
    Procedure FontChanged(Sender: TObject); Override;
    Procedure Loaded; Override;
    Procedure InitializeWnd; Override;
    Procedure GetDialogCode(Var Message: TLMGetDlgCode); Message LM_GETDLGCODE;
    Procedure KeyDown(Var Key: Word; Shift: TShiftState); Override;
    Procedure UTF8KeyPress(Var UTF8Key: TUTF8Char); Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure DblClick; Override;
    Procedure MouseMove(Shift: TShiftState; X, Y: Integer); Override;
    Function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; Override;
    Procedure SetParent(NewParent: TWinControl); Override;
    Procedure DoEnter; Override;
    Procedure DoExit; Override;
    Procedure DoContextPopup(MousePos: TPoint; Var Handled: Boolean); Override;
    Function RealGetText: TCaption; Override;
    Procedure RealSetText(Const Value: TCaption); Override;
    Procedure Change; Virtual;
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
    Function CanUndo: Boolean;
    Function CanRedo: Boolean;
    Procedure Undo;
    Procedure Redo;
    Procedure NoteMenuShortcut;

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
    Property OnChange: TNotifyEvent Read FOnChange Write FOnChange;
    Property OnPaste: TNotifyEvent Read FOnPaste Write FOnPaste;
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
  Dialogs, Clipbrd, LazUTF8, SpellCheckerConfig, SpellEngine, WorkflowLog;

Const
  SpellUndoLimit = 200;
  SpellUndoGroupMs = 1000;

Function SpellOpaqueColor(Value: TColor): TColor;
Begin
  { Pen and brush colours are not resolved the way TextOut resolves clDefault. }
  If (Value = clDefault) Or (Value = clNone) Then
    Value := clWindowText;
  Result := ColorToRGB(Value);
  If Result < 0 Then
    Result := ColorToRGB(clWindowText);
  If Result < 0 Then
    Result := 0;
End;

Function NormaliseMemoText(Const Value: String): String;
Begin
  Result := StringReplace(Value, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
End;

Function TypingGroupClosed(Const Value: String): Boolean;
Begin
  If Value = '' Then
    Exit(True);
  Result := Value[Length(Value)] In [#10, #9];
End;

{ Letters and punctuation stay in one burst. A space starts or continues a
  space burst, so Ctrl+Z removes the last word rather than the whole prompt. }
Function CanMergeTyping(Const Previous: TSpellUndoEntry; Const Added: String; InsertAt: Integer): Boolean;
Var
  PrevChar: String;
Begin
  Result := False;
  If (UTF8Length(Added) <> 1) Or (Added = #10) Or (Added = #9) Then
    Exit;
  If TypingGroupClosed(Previous.Inserted) Then
    Exit;
  If InsertAt <> Previous.CharStart + UTF8Length(Previous.Inserted) Then
    Exit;
  PrevChar := UTF8Copy(Previous.Inserted, UTF8Length(Previous.Inserted), 1);
  Result := (PrevChar = ' ') = (Added = ' ');
End;

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
  { Paint draws the one-pixel frame. A widget border would add a second, thicker edge. }
  BorderStyle := bsNone;
  Width := 200;
  Height := 80;
  FSpellItemCount := 0;
  FSpellItems := TFPList.Create;
  FSpellSuggestions := TStringList.Create;
  FLayoutCache := TStringList.Create;
  FLayoutCache.Sorted := True; FLayoutCache.CaseSensitive := True;
  FActiveStart := 0;
  FActiveLength := 0;
  { This LCL menu has no AutoHotkeys property. The stored suggestion, not the caption,
    is what a click applies, so an accelerator rewrite cannot change the word. }
  FOwnedPopup := TPopupMenu.Create(Nil);
  FDebounce := TTimer.Create(Nil);
  FDebounce.Enabled := False;
  FDebounce.Interval := 200;
  FDebounce.OnTimer := @DebounceTimer;
  FInputLayoutTimer := TTimer.Create(Nil);
  FInputLayoutTimer.Enabled := False;
  FInputLayoutTimer.Interval := 16;
  FInputLayoutTimer.OnTimer := @InputLayoutTimerTick;
  FCaretTimer := TTimer.Create(Nil);
  FCaretTimer.Enabled := False;
  FCaretTimer.Interval := 530;
  FCaretTimer.OnTimer := @CaretTimerTick;
  FCaretOn := False;
  FOwnsCaret := False;
  FHookedForm := Nil;
  FFocusHooks := False;
  FScrollBar := Nil;
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.RegisterChangedHandler(@ConfigChanged);
  FReady := True;
End;

Destructor TSpellMemo.Destroy;
Begin
  FReady := False;
  UnhookHostForm;
  RemoveFocusHooks;
  Application.RemoveAsyncCalls(Self);
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.UnregisterChangedHandler(@ConfigChanged);
  UnhookPopup;
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
  FreeAndNil(FInputLayoutTimer);
  FreeAndNil(FCaretTimer);
  FreeAndNil(FOwnedPopup);
  FreeAndNil(FSpellItems);
  FreeAndNil(FSpellSuggestions);
  ClearLayoutCache;
  FreeAndNil(FLayoutCache);
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
  FScrollBar.BorderSpacing.Top := 1;
  FScrollBar.BorderSpacing.Right := 1;
  FScrollBar.BorderSpacing.Bottom := 1;
  FScrollBar.Parent := Self;
  FScrollBar.Align := alRight;
End;

Function TSpellMemo.RealGetText: TCaption;
Begin
  Result := FText;
End;

Procedure TSpellMemo.RealSetText(Const Value: TCaption);
Var
  Clean: String;
Begin
  Clean := NormaliseMemoText(Value);
  If FText = Clean Then
    Exit;
  { A host replacement is not a text edit. Drop history so undo cannot return
    a previous prompt after a load, a clear, or a sent message. }
  ClearUndoHistory;
  FText := Clean;
  FSelStart := UTF8Length(FText);
  FSelLength := 0;
  FSelAnchor := FSelStart;
  If CanLayout Then
    Begin
      RebuildLayout;
      UpdateScrollBar;
      EnsureCaretInView;
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
  EnsurePopupHook;
  EnsureCaretFocusWatch;
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
    Begin
      EnsureCaretFocusWatch;
      RestartDebounce;
    End;
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
  If HandleAllocated And Not FInputLayoutPending Then
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
  If Assigned(FEditUndoItem) Then
    FEditUndoItem.Enabled := CanUndo;
  If Assigned(FEditRedoItem) Then
    FEditRedoItem.Enabled := CanRedo;
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
  If FReadOnly = Value Then
    Exit;
  FReadOnly := Value;
  If Assigned(FEditUndoItem) Then
    FEditUndoItem.Enabled := CanUndo;
  If Assigned(FEditRedoItem) Then
    FEditRedoItem.Enabled := CanRedo;
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
  FSelAnchor := FSelStart;
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
  { Host paste and explicit inserts are one step, not part of the typing burst. }
  InsertText(Value, ekPaste);
End;

Procedure TSpellMemo.SelectAll;
Begin
  FSelStart := 0;
  FSelLength := CharCount;
  FSelAnchor := 0;
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
  { The host can turn an image on the clipboard into an attachment. Text-only
    hosts leave OnPaste unset and keep the plain insert. }
  If Assigned(FOnPaste) Then
    Begin
      FOnPaste(Self);
      Exit;
    End;
  InsertText(Clipboard.AsText, ekPaste);
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

Procedure TSpellMemo.ClearLayoutCache;
Var I: Integer;
Begin
  If FLayoutCache = Nil Then Exit;
  For I := 0 To FLayoutCache.Count - 1 Do FLayoutCache.Objects[I].Free;
  FLayoutCache.Clear;
  FLayoutBytes := 0;
End;

Procedure TSpellMemo.QueueInputLayout;
Begin
  FInputLayoutPending := True;
  If CanLayout And Assigned(FInputLayoutTimer) Then
    FInputLayoutTimer.Enabled := True;
End;

Procedure TSpellMemo.FlushInputLayout;
Begin
  If Not FInputLayoutPending Or Not CanLayout Then Exit;
  RebuildLayout;
  UpdateScrollBar;
  EnsureCaretInView;
  Invalidate;
End;

Procedure TSpellMemo.InputLayoutTimerTick(Sender: TObject);
Begin
  FInputLayoutTimer.Enabled := False;
  FlushInputLayout;
End;

Procedure TSpellMemo.RebuildLayout;
Var
  Para, Remaining: String;
  Cached: TSpellParagraphLayout;
  CacheIndex, FirstRow, J, Offset: Integer;
  ParaStart, RemainStart, Count, BreakAt, LastSpace, TextPos, WalkPos, FitChars, NextBreak: Integer;
  MaxWidth, RowTop, RowH: Integer;
Begin
  If Not CanLayout Then
    Exit;
  FInputLayoutPending := False;
  If Assigned(FInputLayoutTimer) Then FInputLayoutTimer.Enabled := False;
  SetLength(FPaintLines, 0);
  Count := 0;
  RowTop := 3;
  RowH := LineHeight;
  MaxWidth := TextAreaWidth;
  Canvas.Font := Font;
  If (FLayoutWidth <> MaxWidth) Or (FLayoutHeight <> RowH) Or (FLayoutWrap <> FWordWrap) Then ClearLayoutCache;
  FLayoutWidth := MaxWidth; FLayoutHeight := RowH; FLayoutWrap := FWordWrap;
  { Bound retained paragraphs; cache keys are the exact text, preserving shaping. }
  If FLayoutCache.Count > 2048 Then ClearLayoutCache;
  TextPos := 1;
  While True Do
    Begin
      ParaStart := TextPos;
      While (TextPos <= Length(FText)) And (FText[TextPos] <> #10) Do
        Inc(TextPos);
      Para := Copy(FText, ParaStart, TextPos - ParaStart);
      FirstRow := Count;
      If FLayoutCache.Find(Para, CacheIndex) Then
        Begin
          Cached := TSpellParagraphLayout(FLayoutCache.Objects[CacheIndex]);
          SetLength(FPaintLines, Count + Length(Cached.Lines));
          For J := 0 To High(Cached.Lines) Do
            Begin
              FPaintLines[Count] := Cached.Lines[J];
              Inc(FPaintLines[Count].ByteStart, ParaStart - 1);
              FPaintLines[Count].Top := RowTop;
              Inc(Count); Inc(RowTop, RowH);
            End;
        End
      Else Begin
      RemainStart := ParaStart;
      Offset := 1;
      If Para = '' Then
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
        While Offset <= Length(Para) Do
          Begin
            If Not FWordWrap Then
              BreakAt := (Length(Para) - Offset + 1)
            Else
              Begin
                Remaining := Copy(Para, Offset, MaxInt);
                { Use the canvas's shaped text fit instead of measuring every
                  growing prefix on every key press. Qt's fallback searches
                  prefixes logarithmically; native backends can fit directly.
                  TextFitInfo returns characters, while our rows use bytes. }
                FitChars := Canvas.TextFitInfo(Remaining, MaxWidth);
                If FitChars < 1 Then FitChars := 1;
                BreakAt := UTF8CodepointToByteIndex(PChar(Remaining), Length(Remaining), FitChars);
                If BreakAt <= 0 Then BreakAt := UTF8CodepointSize(PChar(Remaining));
                { Some backends fit using advances in the complete paragraph.
                  A standalone painted prefix can differ through shaping or
                  rounding. Correct that boundary with full-prefix widths. }
                While (FitChars > 1) And
                  (MeasureAdvance(Copy(Remaining, 1, BreakAt)) > MaxWidth) Do
                  Begin
                    Dec(FitChars);
                    BreakAt := UTF8CodepointToByteIndex(PChar(Remaining), Length(Remaining), FitChars);
                  End;
                While BreakAt < Length(Remaining) Do
                  Begin
                    NextBreak := BreakAt + UTF8CodepointSize(@Remaining[BreakAt + 1]);
                    If MeasureAdvance(Copy(Remaining, 1, NextBreak)) > MaxWidth Then Break;
                    BreakAt := NextBreak;
                  End;
                If BreakAt < Length(Remaining) Then
                  Begin
                    LastSpace := 0;
                    For WalkPos := 1 To BreakAt Do
                      If Remaining[WalkPos] In [' ', #9] Then LastSpace := WalkPos;
                    If LastSpace > 0 Then BreakAt := LastSpace;
                  End;
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
            Inc(Offset, BreakAt);
          End;
      If (Length(Para) <= 262144) And (FLayoutBytes + Length(Para) <= 2097152) Then
      Begin
      Cached := TSpellParagraphLayout.Create;
      Cached.Text := Para;
      SetLength(Cached.Lines, Count - FirstRow);
      For J := FirstRow To Count - 1 Do
        Begin
          Cached.Lines[J - FirstRow] := FPaintLines[J];
          Dec(Cached.Lines[J - FirstRow].ByteStart, ParaStart - 1);
        End;
      FLayoutCache.AddObject(Para, Cached);
      Inc(FLayoutBytes, Length(Para));
      End;
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
  FlushInputLayout;
  Pixel := CaretPixel;
  Page := ClientHeight;
  If Pixel.Y < 0 Then
    If Assigned(FScrollBar) And FScrollBar.Visible Then
      FScrollBar.Position := ScrollY + Pixel.Y - 4;
  If Pixel.Y + LineHeight > Page Then
    If Assigned(FScrollBar) And FScrollBar.Visible Then
      FScrollBar.Position := ScrollY + (Pixel.Y + LineHeight - Page) + 4;
End;

Function TSpellMemo.CaretCharIndex: Integer;
Begin
  If (FSelLength > 0) And (FSelStart < FSelAnchor) Then
    Result := FSelStart
  Else
    Result := FSelStart + FSelLength;
End;

Function TSpellMemo.ByteBelongsToPaintLine(LineIndex, CaretByte: Integer): Boolean;
Var
  LineStart, LineEnd: Integer;
Begin
  Result := False;
  If (LineIndex < 0) Or (LineIndex > High(FPaintLines)) Then
    Exit;
  LineStart := FPaintLines[LineIndex].ByteStart;
  LineEnd := LineStart + FPaintLines[LineIndex].ByteLength;
  If CaretByte < LineStart Then
    Exit;
  { Soft-wrap boundaries belong to the next row; a hard newline leaves a
    byte gap and its caret position belongs to this paragraph. }
  If CaretByte < LineEnd Then
    Result := True
  Else
    Result := (CaretByte = LineEnd) And ((LineIndex = High(FPaintLines)) Or
      (FPaintLines[LineIndex + 1].ByteStart > LineEnd));
End;

Function TSpellMemo.CaretPixel: TPoint;
Var
  CaretByte, LineIndex, PrefixLen: Integer;
  Prefix: String;
Begin
  Result.X := 3;
  Result.Y := 3 - ScrollY;
  CaretByte := SpellCharToByteIndex(FText, CaretCharIndex);
  Canvas.Font := Font;
  For LineIndex := 0 To High(FPaintLines) Do
    If ByteBelongsToPaintLine(LineIndex, CaretByte) Then
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

Function TSpellMemo.CaretIsActive: Boolean;
Var
  HostForm, OwnForm, ActiveForm: TCustomForm;
  KeyControl: TWinControl;
Begin
  Result := False;
  If csDesigning In ComponentState Then
    Exit;
  If Assigned(Application) And (Not Application.Active) Then
    Exit;
  HostForm := GetParentForm(Self);
  OwnForm := GetParentForm(Self, False);
  { Deactivation leaves ActiveControl on this memo and does not call DoExit.
    FOwnsCaret must not keep the insertion point blinking in an inactive window.
    The top host covers a docked IDE window whose own Active flag lags. }
  If Assigned(HostForm) And (Not HostForm.Active) Then
    Exit;
  ActiveForm := Nil;
  If Assigned(Screen) Then
    ActiveForm := Screen.ActiveCustomForm;
  { A docked assistant is its own form. Comparing ActiveCustomForm only with the
    IDE main form hid the prompt caret until a popup changed the active form. }
  If Assigned(ActiveForm) And (ActiveForm <> HostForm) And (ActiveForm <> OwnForm) And
    (Not ActiveForm.ContainsControl(Self)) Then
    Exit;
  If Assigned(ActiveForm) And Assigned(OwnForm) And (ActiveForm = OwnForm) Then
    KeyControl := OwnForm.ActiveControl
  Else If Assigned(HostForm) Then
    KeyControl := HostForm.ActiveControl
  Else If Assigned(Screen) Then
    KeyControl := Screen.ActiveControl
  Else
    KeyControl := Nil;
  If (KeyControl = Self) Or (Assigned(KeyControl) And ContainsControl(KeyControl)) Then
    Result := True;
  Result := Result Or Focused;
  { A popup or child scrollbar can clear Focused while this window still
    delivers keys. That gap is not another control taking ActiveControl. }
  If FOwnsCaret And ((Not Assigned(KeyControl)) Or (KeyControl = Self) Or
    (Assigned(KeyControl) And ContainsControl(KeyControl))) Then
    Result := True;
End;

Procedure TSpellMemo.RefreshCaretForFocus;
Begin
  If (Not FReady) Or (csDestroying In ComponentState) Or (csDesigning In ComponentState) Then
    Exit;
  If CaretIsActive Then
    Begin
      If Not (Assigned(FCaretTimer) And FCaretTimer.Enabled) Then
        UpdateCaret;
    End
  Else
    Begin
      FCaretOn := False;
      If Assigned(FCaretTimer) Then
        FCaretTimer.Enabled := False;
      If HandleAllocated Then
        Invalidate;
    End;
End;

Procedure TSpellMemo.EnsureCaretFocusWatch;
Begin
  If csDesigning In ComponentState Then
    Exit;
  InstallFocusHooks;
  HookHostForm;
End;

Procedure TSpellMemo.InstallFocusHooks;
Begin
  If FFocusHooks Or (csDesigning In ComponentState) Then
    Exit;
  If Not Assigned(Application) Or Not Assigned(Screen) Then
    Exit;
  Application.AddOnActivateHandler(@ApplicationFocusChanged, False);
  Application.AddOnDeactivateHandler(@ApplicationFocusChanged, False);
  Screen.AddHandlerActiveFormChanged(@ScreenActiveFormChanged, False);
  Screen.AddHandlerActiveControlChanged(@ScreenActiveControlChanged, False);
  FFocusHooks := True;
End;

Procedure TSpellMemo.RemoveFocusHooks;
Begin
  If Not FFocusHooks Then
    Exit;
  If Assigned(Application) Then
    Begin
      Application.RemoveOnActivateHandler(@ApplicationFocusChanged);
      Application.RemoveOnDeactivateHandler(@ApplicationFocusChanged);
    End;
  If Assigned(Screen) Then
    Begin
      Screen.RemoveHandlerActiveFormChanged(@ScreenActiveFormChanged);
      Screen.RemoveHandlerActiveControlChanged(@ScreenActiveControlChanged);
    End;
  FFocusHooks := False;
End;

Procedure TSpellMemo.HookHostForm;
Var
  Host: TCustomForm;
Begin
  If csDesigning In ComponentState Then
    Exit;
  { Only the memo's own top-level form. A docked window shares the IDE host,
    and replacing that WindowProc would fight every other editor. }
  Host := GetParentForm(Self, False);
  If Not Assigned(Host) Or Assigned(Host.Parent) Then
    Begin
      UnhookHostForm;
      Exit;
    End;
  If (Host = FHookedForm) And (Host.WindowProc = @HostFormWindowProc) Then
    Exit;
  UnhookHostForm;
  FHookedForm := Host;
  FSavedFormWindowProc := Host.WindowProc;
  Host.FreeNotification(Self);
  Host.WindowProc := @HostFormWindowProc;
End;

Procedure TSpellMemo.UnhookHostForm;
Begin
  If Not Assigned(FHookedForm) Then
    Exit;
  FHookedForm.RemoveFreeNotification(Self);
  If FHookedForm.WindowProc = @HostFormWindowProc Then
    FHookedForm.WindowProc := FSavedFormWindowProc;
  FHookedForm := Nil;
  FSavedFormWindowProc := Nil;
End;

Procedure TSpellMemo.HostFormWindowProc(Var Message: TLMessage);
Begin
  If Assigned(FSavedFormWindowProc) Then
    FSavedFormWindowProc(Message);
  If (Message.Msg = LM_ACTIVATE) Or (Message.Msg = CM_ACTIVATE) Or (Message.Msg = CM_DEACTIVATE) Then
    RefreshCaretForFocus;
End;

{$PUSH}{$HINTS OFF}
Procedure TSpellMemo.ApplicationFocusChanged(Sender: TObject);
Begin
  RefreshCaretForFocus;
End;

Procedure TSpellMemo.ScreenActiveFormChanged(Sender: TObject; Form: TCustomForm);
Begin
  RefreshCaretForFocus;
End;

Procedure TSpellMemo.ScreenActiveControlChanged(Sender: TObject; LastControl: TControl);
Begin
  RefreshCaretForFocus;
End;
{$POP}

Procedure TSpellMemo.SetParent(NewParent: TWinControl);
Begin
  Inherited SetParent(NewParent);
  If csDestroying In ComponentState Then
    Exit;
  EnsureCaretFocusWatch;
End;

Procedure TSpellMemo.ResetCaretBlink;
Begin
  FCaretOn := True;
  If Assigned(FCaretTimer) Then
    Begin
      FCaretTimer.Enabled := False;
      FCaretTimer.Enabled := HandleAllocated And CaretIsActive;
    End;
End;

Procedure TSpellMemo.AcquireCaret;
Begin
  FOwnsCaret := True;
  UpdateCaret;
End;

Procedure TSpellMemo.CaretTimerTick(Sender: TObject);
Begin
  If (Not FReady) Or (csDestroying In ComponentState) Then
    Exit;
  If Not CaretIsActive Then
    Begin
      FCaretTimer.Enabled := False;
      FCaretOn := False;
      If HandleAllocated Then
        Invalidate;
      Exit;
    End;
  FCaretOn := Not FCaretOn;
  If HandleAllocated Then
    Invalidate;
End;

Procedure TSpellMemo.UpdateCaret;
Begin
  ResetCaretBlink;
  { A pending input layout already invalidates. Another invalidate here would
    flush that layout inside the key handler and stall rapid typing. }
  If HandleAllocated And (Not FInputLayoutPending) Then
    Invalidate;
End;

Function TSpellMemo.CharIndexAtPoint(X, Y: Integer): Integer;
Var
  LineIndex, Index, Best, CodeLen, LeftW, RightW: Integer;
  AbsY: Integer;
  LineText: String;
Begin
  FlushInputLayout;
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

Procedure TSpellMemo.ClearUndoHistory;
Begin
  FUndoStack := Nil;
  FUndoIndex := 0;
  FLastEditTick := 0;
End;

Procedure TSpellMemo.ClearMenuHistory(Data: PtrInt);
Begin
  If Data = 0 Then
    FMenuHistory := False;
End;

Procedure TSpellMemo.NoteMenuShortcut;
Begin
  { The popup accelerator runs before KeyDown. Mark this command so the key
    handler does not apply it a second time, then clear the mark if the key
    never arrives. }
  FMenuHistory := True;
  Application.QueueAsyncCall(@ClearMenuHistory, 0);
End;

Procedure TSpellMemo.RememberEdit(Const Entry: TSpellUndoEntry);
Var
  NowTick: QWord;
  Index, Last: Integer;
Begin
  If FUndoIndex < Length(FUndoStack) Then
    SetLength(FUndoStack, FUndoIndex);
  NowTick := GetTickCount64;
  Last := FUndoIndex - 1;
  If (Last >= 0) And (NowTick - FLastEditTick <= SpellUndoGroupMs) And (Entry.Kind = FUndoStack[Last].Kind) Then
    Begin
      If (Entry.Kind = ekTyping) And (Entry.Removed = '') And
        CanMergeTyping(FUndoStack[Last], Entry.Inserted, Entry.CharStart) Then
        Begin
          FUndoStack[Last].Inserted := FUndoStack[Last].Inserted + Entry.Inserted;
          FUndoStack[Last].RedoSelStart := Entry.RedoSelStart;
          FUndoStack[Last].RedoSelLength := Entry.RedoSelLength;
          FLastEditTick := NowTick;
          Exit;
        End;
      If (Entry.Kind = ekBackspace) And (Entry.Inserted = '') And (UTF8Length(Entry.Removed) = 1) And
        (Entry.CharStart + UTF8Length(Entry.Removed) = FUndoStack[Last].CharStart) Then
        Begin
          FUndoStack[Last].Removed := Entry.Removed + FUndoStack[Last].Removed;
          FUndoStack[Last].CharStart := Entry.CharStart;
          FUndoStack[Last].RedoSelStart := Entry.RedoSelStart;
          FUndoStack[Last].RedoSelLength := Entry.RedoSelLength;
          FLastEditTick := NowTick;
          Exit;
        End;
      If (Entry.Kind = ekForwardDelete) And (Entry.Inserted = '') And (UTF8Length(Entry.Removed) = 1) And
        (Entry.CharStart = FUndoStack[Last].CharStart) Then
        Begin
          FUndoStack[Last].Removed := FUndoStack[Last].Removed + Entry.Removed;
          FUndoStack[Last].RedoSelStart := Entry.RedoSelStart;
          FUndoStack[Last].RedoSelLength := Entry.RedoSelLength;
          FLastEditTick := NowTick;
          Exit;
        End;
    End;
  If FUndoIndex >= SpellUndoLimit Then
    Begin
      For Index := 1 To FUndoIndex - 1 Do
        FUndoStack[Index - 1] := FUndoStack[Index];
      Dec(FUndoIndex);
      SetLength(FUndoStack, FUndoIndex);
    End;
  SetLength(FUndoStack, FUndoIndex + 1);
  FUndoStack[FUndoIndex] := Entry;
  Inc(FUndoIndex);
  FLastEditTick := NowTick;
End;

Procedure TSpellMemo.ApplyTextChange(CharStart, RemoveCount: Integer; Const Inserted: String; NewSelStart, NewSelLength: Integer);
Var
  ByteStart, ByteEnd, Total: Integer;
Begin
  Total := CharCount;
  If CharStart < 0 Then
    CharStart := 0;
  If CharStart > Total Then
    CharStart := Total;
  If RemoveCount < 0 Then
    RemoveCount := 0;
  If CharStart + RemoveCount > Total Then
    RemoveCount := Total - CharStart;
  ByteStart := SpellCharToByteIndex(FText, CharStart);
  ByteEnd := SpellCharToByteIndex(FText, CharStart + RemoveCount);
  If ByteEnd > ByteStart Then
    System.Delete(FText, ByteStart, ByteEnd - ByteStart);
  If Inserted <> '' Then
    System.Insert(Inserted, FText, ByteStart);
  FSelStart := NewSelStart;
  FSelLength := NewSelLength;
  If FSelLength < 0 Then
    FSelLength := 0;
  FSelAnchor := FSelStart;
  ClampSelection;
  { Record edits and notify the host immediately. Coalesce text measurement
    so rapid keyboard events cannot queue behind per-character rewrapping. }
  QueueInputLayout;
  RestartDebounce;
  Change;
  If CaretIsActive Then
    UpdateCaret;
End;

Procedure TSpellMemo.ReplaceRange(CharStart, RemoveCount: Integer; Const Inserted: String; Kind: TSpellEditKind);
Var
  Clean, Removed: String;
  ByteStart, ByteEnd, Total: Integer;
  Entry: TSpellUndoEntry;
Begin
  If FReadOnly Or FApplyingHistory Then
    Exit;
  Clean := NormaliseMemoText(Inserted);
  Total := CharCount;
  If CharStart < 0 Then
    CharStart := 0;
  If CharStart > Total Then
    CharStart := Total;
  If RemoveCount < 0 Then
    RemoveCount := 0;
  If CharStart + RemoveCount > Total Then
    RemoveCount := Total - CharStart;
  If (RemoveCount = 0) And (Clean = '') Then
    Exit;
  ByteStart := SpellCharToByteIndex(FText, CharStart);
  ByteEnd := SpellCharToByteIndex(FText, CharStart + RemoveCount);
  Removed := Copy(FText, ByteStart, ByteEnd - ByteStart);
  If Removed = Clean Then
    Exit;
  Entry.CharStart := CharStart;
  Entry.Removed := Removed;
  Entry.Inserted := Clean;
  Entry.UndoSelStart := FSelStart;
  Entry.UndoSelLength := FSelLength;
  Entry.RedoSelStart := CharStart + UTF8Length(Clean);
  Entry.RedoSelLength := 0;
  Entry.Kind := Kind;
  RememberEdit(Entry);
  ApplyTextChange(CharStart, RemoveCount, Clean, Entry.RedoSelStart, Entry.RedoSelLength);
End;

Procedure TSpellMemo.DeleteRange(CharStart, CharCount: Integer; Kind: TSpellEditKind);
Begin
  ReplaceRange(CharStart, CharCount, '', Kind);
End;

Procedure TSpellMemo.DeleteSelection;
Begin
  If FSelLength > 0 Then
    DeleteRange(FSelStart, FSelLength, ekDiscrete);
End;

Procedure TSpellMemo.InsertText(Const AddText: String);
Begin
  InsertText(AddText, ekTyping);
End;

Procedure TSpellMemo.InsertText(Const AddText: String; Kind: TSpellEditKind);
Begin
  If FReadOnly Then
    Exit;
  ReplaceRange(FSelStart, FSelLength, AddText, Kind);
End;

Function TSpellMemo.CanUndo: Boolean;
Begin
  Result := (Not FReadOnly) And (FUndoIndex > 0);
End;

Function TSpellMemo.CanRedo: Boolean;
Begin
  Result := (Not FReadOnly) And (FUndoIndex < Length(FUndoStack));
End;

Procedure TSpellMemo.Undo;
Var
  Entry: TSpellUndoEntry;
Begin
  If Not CanUndo Then
    Exit;
  Dec(FUndoIndex);
  Entry := FUndoStack[FUndoIndex];
  FApplyingHistory := True;
  Try
    ApplyTextChange(Entry.CharStart, UTF8Length(Entry.Inserted), Entry.Removed, Entry.UndoSelStart, Entry.UndoSelLength);
  Finally
    FApplyingHistory := False;
  End;
End;

Procedure TSpellMemo.Redo;
Var
  Entry: TSpellUndoEntry;
Begin
  If Not CanRedo Then
    Exit;
  Entry := FUndoStack[FUndoIndex];
  Inc(FUndoIndex);
  FApplyingHistory := True;
  Try
    ApplyTextChange(Entry.CharStart, UTF8Length(Entry.Removed), Entry.Inserted, Entry.RedoSelStart, Entry.RedoSelLength);
  Finally
    FApplyingHistory := False;
  End;
End;

Procedure TSpellMemo.UTF8KeyPress(Var UTF8Key: TUTF8Char);
Begin
  Inherited UTF8KeyPress(UTF8Key);
  { An input method can deliver characters without a matching KeyDown. }
  AcquireCaret;
  If (UTF8Key = '') Or FReadOnly Then
    Exit;
  If (UTF8Key = #8) Or (UTF8Key = #127) Then
    Begin
      UTF8Key := '';
      Exit;
    End;
  If UTF8Key = #9 Then
    Begin
      If FWantTabs Then
        Begin
          InsertText(#9);
          UTF8Key := '';
        End;
      Exit;
    End;
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

Procedure TSpellMemo.GetDialogCode(Var Message: TLMGetDlgCode);
Begin
  { A painted editor must ask for the key. Otherwise GTK can swallow Ctrl+V
    before OnKeyDown, and an image paste never reaches the composer. }
  Message.Result := DLGC_WANTARROWS Or DLGC_WANTCHARS Or DLGC_WANTALLKEYS;
End;

Procedure TSpellMemo.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  Extend: Boolean;
  Caret, LineIndex, Target, CaretByte: Integer;
Begin
  AcquireCaret;
  Inherited KeyDown(Key, Shift);
  If Key In [VK_HOME, VK_END, VK_UP, VK_DOWN] Then FlushInputLayout;
  Extend := ssShift In Shift;
  Caret := CaretCharIndex;
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
        If (ssCtrl In Shift) Or (Length(FPaintLines) = 0) Then
          MoveCaret(0, Extend)
        Else
          Begin
            CaretByte := SpellCharToByteIndex(FText, Caret);
            LineIndex := 0;
            For Target := 0 To High(FPaintLines) Do
              If ByteBelongsToPaintLine(Target, CaretByte) Then
                Begin
                  LineIndex := Target;
                  Break;
                End;
            MoveCaret(SpellByteToCharOffset(FText, FPaintLines[LineIndex].ByteStart), Extend);
          End;
        Key := 0;
      End;
    VK_END:
      Begin
        If (ssCtrl In Shift) Or (Length(FPaintLines) = 0) Then
          MoveCaret(CharCount, Extend)
        Else
          Begin
            CaretByte := SpellCharToByteIndex(FText, Caret);
            LineIndex := 0;
            For Target := 0 To High(FPaintLines) Do
              If ByteBelongsToPaintLine(Target, CaretByte) Then
                Begin
                  LineIndex := Target;
                  Break;
                End;
            MoveCaret(SpellByteToCharOffset(FText, FPaintLines[LineIndex].ByteStart +
              FPaintLines[LineIndex].ByteLength), Extend);
          End;
        Key := 0;
      End;
    VK_UP, VK_DOWN:
      Begin
        CaretByte := SpellCharToByteIndex(FText, Caret);
        LineIndex := 0;
        For Target := 0 To High(FPaintLines) Do
          If ByteBelongsToPaintLine(Target, CaretByte) Then
            Begin
              LineIndex := Target;
              Break;
            End;
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
          DeleteRange(FSelStart - 1, 1, ekBackspace);
        Key := 0;
      End;
    VK_DELETE:
      Begin
        If FReadOnly Then
          Exit;
        If FSelLength > 0 Then
          DeleteSelection
        Else If FSelStart < CharCount Then
          DeleteRange(FSelStart, 1, ekForwardDelete);
        Key := 0;
      End;
    VK_Z:
      If (ssCtrl In Shift) And (Not (ssAlt In Shift)) Then
        Begin
          If Not FMenuHistory Then
            Begin
              If ssShift In Shift Then
                Redo
              Else
                Undo;
            End;
          FMenuHistory := False;
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
    VK_INSERT:
      If (ssShift In Shift) And (Not (ssCtrl In Shift)) Then
        Begin
          PasteFromClipboard;
          Key := 0;
        End;
    VK_V:
      If ssCtrl In Shift Then
        Begin
          PasteFromClipboard;
          Key := 0;
        End;
    VK_TAB:
      If FWantTabs Then
        Begin
          InsertText(#9);
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
  FOwnsCaret := True;
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
  { Right-click opens the popup. Moving the caret would drop the selection
    before OnPopup, so Cut and Copy stay disabled. Keep the current range. }
  If (Button = mbRight) And (FSelLength > 0) Then
    Exit;
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
  FOwnsCaret := True;
  EnsureCaretFocusWatch;
  UpdateCaret;
  Invalidate;
End;

Procedure TSpellMemo.DoExit;
Begin
  Inherited DoExit;
  FOwnsCaret := False;
  If Assigned(FCaretTimer) Then
    FCaretTimer.Enabled := False;
  FCaretOn := False;
  If HandleAllocated Then
    Invalidate;
End;

Procedure TSpellMemo.FontChanged(Sender: TObject);
Begin
  ClearLayoutCache;
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
  FirstRange: Integer;
  LineIndex, Y, H, X0, SX1, SX2, SelLo, SelHi, ClipLo, ClipHi: Integer;
  FirstChar, AfterChar, Byte0, Byte1, CaretW, CaretTop, CaretBottom, CaretRight: Integer;
  Pixel: TPoint;
  LineText: String;
  HasHighlight: Boolean;
  RangeIndex, RangeStart, RangeEnd, LineStart, LineEnd, U1, U2: Integer;

  Procedure DrawRun(Const Run: String; RunX: Integer; TextColor: TColor);
  Begin
    If Run = '' Then
      Exit;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TextColor;
    Canvas.TextOut(RunX, Y, Run);
  End;

  Procedure ReleaseHighlightBrush;
  Begin
    { A restored painter is opaque highlight again, while this brush object still
      says clear. The next line would not refresh it and would paint that background.
      Force a real style change so the widgetset drops the highlight brush. }
    Canvas.Brush.Color := Color;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := Font.Color;
  End;

Begin
  FirstRange := 0;
  If Not FReady Then
    Exit;
  FlushInputLayout;
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
            End;
        End;
      HasHighlight := (FSelLength > 0) And (ClipHi > ClipLo) And (SX2 > SX1);
      { One full run so kerning pairs survive. Cover the selection afterwards so
        antialiased edges are not left under the highlight text. Do not clip:
        restoring that clip on Qt puts an opaque highlight brush back, and the
        following lines paint it because their brush style has not changed. }
      If LineText <> '' Then
        If HasHighlight Then
          Begin
            DrawRun(LineText, X0, Font.Color);
            Canvas.Brush.Style := bsSolid;
            Canvas.Brush.Color := clHighlight;
            Canvas.FillRect(Rect(SX1, Y, SX2, Y + H));
            DrawRun(Copy(LineText, Byte0 + 1, Byte1 - Byte0), SX1, clHighlightText);
            ReleaseHighlightBrush;
          End
        Else
          DrawRun(LineText, X0, Font.Color);
      While (FirstRange <= High(FRanges)) And
        (FRanges[FirstRange].UTF8Start + FRanges[FirstRange].UTF8Length <= LineStart) Do Inc(FirstRange);
      If SpellActive Then
        For RangeIndex := FirstRange To High(FRanges) Do
          Begin
            RangeStart := FRanges[RangeIndex].UTF8Start;
            If RangeStart >= LineEnd Then Break;
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
  { Same frame colours as the conversation surface, so the two editors match. }
  Canvas.Brush.Style := bsSolid;
  If CaretIsActive Then
    Canvas.Brush.Color := $00C08038
  Else
    Canvas.Brush.Color := $00C8C5BE;
  Canvas.FillRect(0, 0, ClientWidth, 1);
  Canvas.FillRect(0, ClientHeight - 1, ClientWidth, ClientHeight);
  Canvas.FillRect(0, 0, 1, ClientHeight);
  Canvas.FillRect(ClientWidth - 1, 0, ClientWidth, ClientHeight);
  If CaretIsActive And (FSelLength = 0) And Assigned(FCaretTimer) And (Not FCaretTimer.Enabled) And HandleAllocated Then
    Begin
      { A missed focus return, or a timer stopped from inside its own tick,
        used to leave the insertion point invisible while typing still worked. }
      FCaretOn := True;
      FCaretTimer.Enabled := True;
    End;
  If CaretIsActive And FCaretOn And (FSelLength = 0) Then
    Begin
      Pixel := CaretPixel;
      { A 1px stroke is centred on the pixel boundary and disappears on Qt and
        scaled GTK. A filled bar is the same width other editors request. }
      CaretW := Font.PixelsPerInch Div 48;
      If CaretW < 2 Then
        CaretW := 2;
      CaretTop := Pixel.Y;
      If CaretTop < 1 Then
        CaretTop := 1;
      CaretBottom := Pixel.Y + LineHeight;
      If CaretBottom > ClientHeight - 1 Then
        CaretBottom := ClientHeight - 1;
      CaretRight := Pixel.X + CaretW;
      If Pixel.X < 1 Then
        Pixel.X := 1;
      If CaretRight > ClientWidth - 1 Then
        CaretRight := ClientWidth - 1;
      If (CaretRight > Pixel.X) And (CaretBottom > CaretTop) Then
        Begin
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := SpellOpaqueColor(Font.Color);
          Canvas.FillRect(Pixel.X, CaretTop, CaretRight, CaretBottom);
        End;
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
  If FTokenText <> FText Then
    Begin
      FTokens := SpellBreakWords(FText);
      FTokenText := FText;
    End;
  Tokens := FTokens;
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
    WorkflowLogger.Debug('SpellMemo', Format('Rescan words=%d errors=%d status=%s',
      [Length(Tokens), Count, WorkflowSpellConfig.LastStatus]));
  Invalidate;
End;

Procedure TSpellMemo.EnsureEditMenu;
Var
  Sep: TMenuItem;
Begin
  If (Not Assigned(FOwnedPopup)) Or Assigned(FEditCutItem) Then
    Exit;
  FEditUndoItem := TMenuItem.Create(FOwnedPopup);
  FEditUndoItem.Caption := 'Undo';
  FEditUndoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl]);
  FEditUndoItem.OnClick := @EditUndoClick;
  FOwnedPopup.Items.Add(FEditUndoItem);
  FEditRedoItem := TMenuItem.Create(FOwnedPopup);
  FEditRedoItem.Caption := 'Redo';
  FEditRedoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl, ssShift]);
  FEditRedoItem.OnClick := @EditRedoClick;
  FOwnedPopup.Items.Add(FEditRedoItem);
  Sep := TMenuItem.Create(FOwnedPopup);
  Sep.Caption := '-';
  FOwnedPopup.Items.Add(Sep);
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
  UpdateEditMenu;
End;

Procedure TSpellMemo.EditUndoClick(Sender: TObject);
Begin
  NoteMenuShortcut;
  Undo;
End;

Procedure TSpellMemo.EditRedoClick(Sender: TObject);
Begin
  NoteMenuShortcut;
  Redo;
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
  If Assigned(FEditUndoItem) Then
    FEditUndoItem.Enabled := CanUndo;
  If Assigned(FEditRedoItem) Then
    FEditRedoItem.Enabled := CanRedo;
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
  UnhookPopup;
  FHookedPopup := PopupMenu;
  FHostPopupHandler := Nil;
  If Assigned(FHookedPopup) Then
    Begin
      FHookedPopup.FreeNotification(Self);
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

Procedure TSpellMemo.Notification(AComponent: TComponent; Operation: TOperation);
Begin
  If Operation = opRemove Then
    Begin
      DetachSpellItem(AComponent);
      If AComponent = FHookedPopup Then
        Begin
          FHookedPopup := Nil;
          FHostPopupHandler := Nil;
        End;
      If AComponent = FHookedForm Then
        Begin
          FHookedForm := Nil;
          FSavedFormWindowProc := Nil;
        End;
    End;
  Inherited Notification(AComponent, Operation);
End;

Procedure TSpellMemo.UnhookPopup;
Var Handler: TNotifyEvent;
Begin
  ClearSpellMenu(FHookedPopup);
  If Assigned(FHookedPopup) Then
    Begin
      Handler := @PopupPopup;
      If (TMethod(FHookedPopup.OnPopup).Code = TMethod(Handler).Code) And
        (TMethod(FHookedPopup.OnPopup).Data = Pointer(Self)) Then
        FHookedPopup.OnPopup := FHostPopupHandler;
      FHookedPopup.RemoveFreeNotification(Self);
    End;
  FHookedPopup := Nil; FHostPopupHandler := Nil;
End;

Function SpellMenuCaption(Const Value: String): String;
Begin
  Result := StringReplace(Value, '&', '&&', [rfReplaceAll]);
End;

Procedure TSpellMemo.DetachSpellItem(Item: TObject);
Var
  Index: Integer;
Begin
  If Not Assigned(FSpellItems) Or Not Assigned(Item) Then
    Exit;
  Index := FSpellItems.IndexOf(Item);
  If Index < 0 Then
    Exit;
  FSpellItems.Delete(Index);
  If Assigned(FSpellSuggestions) And (Index < FSpellSuggestions.Count) Then
    FSpellSuggestions.Delete(Index);
End;

Procedure TSpellMemo.ClearSpellMenu(Menu: TPopupMenu);
Var
  Item: TMenuItem;
Begin
  If Assigned(FSpellItems) Then
    While FSpellItems.Count > 0 Do
      Begin
        Item := TMenuItem(FSpellItems.Last);
        DetachSpellItem(Item);
        Item.Free;
      End;
  FSpellItemCount := 0;
End;

Function TSpellMemo.AddSpellSuggestion(Menu: TPopupMenu; Const Suggestion: String): TMenuItem;
Begin
  Result := TMenuItem.Create(Self);
  FSpellItems.Add(Result);
  FSpellSuggestions.Add(Suggestion);
  Result.FreeNotification(Self);
  Result.Caption := SpellMenuCaption(Suggestion);
  Result.OnClick := @SuggestionClick;
  If Assigned(Menu) Then
    Begin
      Menu.Items.Insert(FSpellItemCount, Result);
      Inc(FSpellItemCount);
    End;
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
    AddSpellSuggestion(Menu, Suggestions[Index]);
  If FSpellItemCount > 0 Then
    Begin
      Item := TMenuItem.Create(Self);
      FSpellItems.Add(Item);
      FSpellSuggestions.Add('');
      Item.FreeNotification(Self);
      Item.Caption := '-';
      Menu.Items.Insert(FSpellItemCount, Item);
      Inc(FSpellItemCount);
    End;
  Item := TMenuItem.Create(Self);
  FSpellItems.Add(Item);
  FSpellSuggestions.Add('');
  Item.FreeNotification(Self);
  Item.Caption := 'Ignore "' + SpellMenuCaption(FActiveToken) + '"';
  Item.OnClick := @IgnoreClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  Item := TMenuItem.Create(Self);
  FSpellItems.Add(Item);
  FSpellSuggestions.Add('');
  Item.FreeNotification(Self);
  Item.Caption := 'Add "' + SpellMenuCaption(FActiveToken) + '" to dictionary';
  Item.OnClick := @AddClick;
  Menu.Items.Insert(FSpellItemCount, Item);
  Inc(FSpellItemCount);
  If Menu.Items.Count > FSpellItemCount Then
    Begin
      Item := TMenuItem.Create(Self);
      FSpellItems.Add(Item);
      FSpellSuggestions.Add('');
      Item.FreeNotification(Self);
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
  InsertText(NewText, ekDiscrete);
End;

Procedure TSpellMemo.SuggestionClick(Sender: TObject);
Var
  Index: Integer;
Begin
  If Not (Sender Is TMenuItem) Or Not Assigned(FSpellItems) Or Not Assigned(FSpellSuggestions) Then
    Exit;
  Index := FSpellItems.IndexOf(Sender);
  If (Index < 0) Or (Index >= FSpellSuggestions.Count) Or (FSpellSuggestions[Index] = '') Then
    Exit;
  ReplaceActiveWord(FSpellSuggestions[Index]);
End;

Procedure TSpellMemo.IgnoreClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    WorkflowSpellConfig.IgnoreWord(FActiveToken);
End;

Procedure TSpellMemo.AddClick(Sender: TObject);
Begin
  If Assigned(WorkflowSpellConfig) And (FActiveToken <> '') Then
    If Not WorkflowSpellConfig.AddToPersonal(FActiveToken) Then
      MessageDlg(WorkflowSpellConfig.LastStatus, mtWarning, [mbOK], 0);
End;

Initialization

RegisterClass(TSpellMemo);

End.
