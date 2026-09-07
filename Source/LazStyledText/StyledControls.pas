Unit StyledControls;

{ Styled single-line and multiline editors using one canvas (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, ExtCtrls, Types, LMessages, LCLType, StyledTextTypes, StyledTextDocument, StyledCanvas, StyledSurface, StyledMemoLayout;

Type
  TStyledUndo = Record
    Start, BeforeEnd, AfterEnd: TStyledPosition;
    Before, After: TStyledContent;
  End;
  TCustomStyledText = Class(TStyledSurface)
  Private
    FDocument: TStyledDocument;
    FReadOnly: Boolean;
    FShowCaret: Boolean;
    FWordWrap: Boolean;
    FOnChange: TNotifyEvent;
    FOnSelectionChange: TNotifyEvent;
    FInsertionStyle: Integer;
    FWantTabs: Boolean;
    FLines: TStrings;
    SingleLine: Boolean;
    LayoutState: TStyledMemoLayout;
    Timer: TTimer;
    Anchor, Caret: TStyledPosition;
    History: Array Of TStyledUndo;
    HistoryPosition: Integer;
    Changing, Selecting, CaretCreated: Boolean;
    LastWidth, WorkIndex, PreferredX, NativeCaretHeight: Integer;
    KnownGeneration: QWord;
    PointerPosition: TPoint;
    Procedure SetParagraphBox(Const Style: TStyledBoxStyle; EnabledBox: Boolean);
    Function StyleAtPosition(Const Position: TStyledPosition): Integer;
    Function GetStyledText: UTF8String;
    Procedure SetStyledText(Const Value: UTF8String);
    Procedure SetLines(Value: TStrings);
    Procedure SetWordWrap(Value: Boolean);
    Procedure SetReadOnly(Value: Boolean);
    Procedure SetShowCaret(Value: Boolean);
    Procedure ReleaseCaret;
    Procedure DoDocumentChange(Sender: TObject; First, Removed, Added: Integer);
    Procedure DoTimer(Sender: TObject);
    Procedure ResetLayout;
    Procedure EnsureLayout(Index: Integer; Finish: Boolean = False);
    Procedure UpdateExtent;
    Procedure UpdateCaret;
    Procedure RevealCaret;
    Procedure ReplaceSelection(Const Content: TStyledContent);
    Procedure MoveCaret(Const Position: TStyledPosition; Extend: Boolean; KeepX: Boolean = False);
    Function GetSelectedText: UTF8String;
    Function GetHasSelection: Boolean;
    Procedure GetSelection(Out First, Last: TStyledPosition);
    Procedure GetDialogCode(Var Message: TLMGetDlgCode); Message LM_GETDLGCODE;
    Procedure WMSetFocus(Var Message: TLMSetFocus); Message LM_SETFOCUS;
    Function StepPosition(Const Position: TStyledPosition; ForwardStep, ByWord: Boolean): TStyledPosition;
  Protected
    Procedure DestroyWnd; Override;
    Procedure PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64); Override;
    Procedure GeometryChanged; Override;
    Procedure Scrolled; Override;
    Procedure KeyDown(Var Key: Word; Shift: TShiftState); Override;
    Procedure UTF8KeyPress(Var UTF8Key: TUTF8Char); Override;
    Procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseMove(Shift: TShiftState; X, Y: Integer); Override;
    Procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    Procedure DblClick; Override;
    Procedure DoEnter; Override;
    Procedure DoExit; Override;
  Public
    Constructor Create(OwnerComponent: TComponent); Override;
    Destructor Destroy; Override;
    Function HitTest(X, Y: Integer): TStyledPosition;
    Procedure CompleteLayout;
    Procedure SelectAll;
    Procedure SelectRange(Const First, Last: TStyledPosition);
    Procedure SelectWordAt(X, Y: Integer);
    Procedure SelectLineAt(X, Y: Integer);
    Procedure ClearSelection;
    Procedure CopyToClipboard;
    Procedure CutToClipboard;
    Procedure PasteFromClipboard;
    Procedure Undo;
    Procedure Redo;
    Procedure InsertText(Const Value: UTF8String);
    Procedure AppendText(Const Value: UTF8String; FollowTail: Boolean = True);
    Procedure ApplySelectionStyle(Style: Integer);
    Procedure GetTextAttributes(Out Style: TStyledStyle; Out Mixed: TStyledAttributes);
    Procedure ApplyTextAttributes(Const Style: TStyledStyle; Attributes: TStyledAttributes);
    Procedure ApplyParagraphBox(Const Style: TStyledBoxStyle);
    Procedure RemoveParagraphBox;
    Function CurrentParagraphBox: TStyledParagraphBox;
    Function CanUndo: Boolean;
    Function CanRedo: Boolean;
    Property Document: TStyledDocument Read FDocument;
    Property SelectedText: UTF8String Read GetSelectedText;
    Property HasSelection: Boolean Read GetHasSelection;
    Property CaretPosition: TStyledPosition Read Caret;
    Property InsertionStyle: Integer Read FInsertionStyle Write FInsertionStyle;
  Published
    Property Text: UTF8String Read GetStyledText Write SetStyledText;
    Property Lines: TStrings Read FLines Write SetLines;
    Property ReadOnly: Boolean Read FReadOnly Write SetReadOnly Default False;
    Property ShowCaret: Boolean Read FShowCaret Write SetShowCaret Default True;
    Property WordWrap: Boolean Read FWordWrap Write SetWordWrap Default True;
    Property WantTabs: Boolean Read FWantTabs Write FWantTabs Default False;
    Property OnChange: TNotifyEvent Read FOnChange Write FOnChange;
    Property OnSelectionChange: TNotifyEvent Read FOnSelectionChange Write FOnSelectionChange;
  End;
  TStyledEdit = Class(TCustomStyledText)
  Public
    Constructor Create(OwnerComponent: TComponent); Override;
  End;
  TStyledMemo = Class(TCustomStyledText);

Implementation

Uses
  SysUtils, Math, Graphics, Clipbrd, LCLIntf;

Type
  TStyledLines = Class(TStrings)
  Private
    Document: TStyledDocument;
  Protected
    Function Get(Index: Integer): String; Override;
    Function GetCount: Integer; Override;
    Procedure Put(Index: Integer; Const Value: String); Override;
    Procedure SetTextStr(Const Value: String); Override;
    Function GetTextStr: String; Override;
  Public
    Constructor Create(NewDocument: TStyledDocument);
    Procedure Clear; Override;
    Procedure Delete(Index: Integer); Override;
    Procedure Insert(Index: Integer; Const Value: String); Override;
  End;

Constructor TStyledLines.Create(NewDocument: TStyledDocument);
Begin
  Inherited Create;
  Document := NewDocument;
End;

Function TStyledLines.Get(Index: Integer): String;
Begin
  Result := Document[Index]^.Text;
End;

Function TStyledLines.GetCount: Integer;
Begin
  Result := Document.Count;
End;

Procedure TStyledLines.Put(Index: Integer; Const Value: String);
Begin
  Document.ReplaceText(StyledPosition(Index, 0), StyledPosition(Index, Length(Document[Index]^.Text)), Value, 0);
End;

Procedure TStyledLines.SetTextStr(Const Value: String);
Begin
  Document.Text := Value;
End;

Function TStyledLines.GetTextStr: String;
Begin
  Result := Document.Text;
End;

Procedure TStyledLines.Clear;
Begin
  Document.Text := '';
End;

Procedure TStyledLines.Delete(Index: Integer);
Begin
  If Index < Document.Count - 1 Then Document.ReplaceText(StyledPosition(Index, 0), StyledPosition(Index + 1, 0), '', 0)
  Else If Index > 0 Then
    Document.ReplaceText(StyledPosition(Index - 1, Length(Document[Index - 1]^.Text)), Document.EndPosition, '', 0)
  Else Clear;
End;

Procedure TStyledLines.Insert(Index: Integer; Const Value: String);
Begin
  If Index = Document.Count Then Document.ReplaceText(Document.EndPosition, Document.EndPosition, #10 + Value, 0)
  Else Document.ReplaceText(StyledPosition(Index, 0), StyledPosition(Index, 0), Value + #10, 0);
End;

Constructor TCustomStyledText.Create(OwnerComponent: TComponent);
Begin
  Inherited Create(OwnerComponent);
  FDocument := TStyledDocument.Create;
  LayoutState := TStyledMemoLayout.Create(FDocument, Renderer);
  FDocument.OnChange := @DoDocumentChange;
  FLines := TStyledLines.Create(FDocument);
  FWordWrap := True;
  FShowCaret := True;
  PreferredX := -1;
  LayoutState.RestartParagraph := -1;
  Timer := TTimer.Create(Nil);
  Timer.Interval := 25;
  Timer.Enabled := False;
  Timer.OnTimer := @DoTimer;
  Cursor := crIBeam;
  SetScrollbars(True, False);
  ResetLayout;
End;

Constructor TStyledEdit.Create(OwnerComponent: TComponent);
Begin
  Inherited Create(OwnerComponent);
  SingleLine := True;
  FWordWrap := False;
  Height := 38;
  SetScrollbars(False, False);
  ResetLayout;
End;

Destructor TCustomStyledText.Destroy;
Begin
  ReleaseCaret;
  FreeAndNil(Timer);
  FreeAndNil(FLines);
  FreeAndNil(LayoutState);
  FreeAndNil(FDocument);
  Inherited Destroy;
End;

Procedure TCustomStyledText.ResetLayout;
Begin
  If Not Assigned(FDocument) Then Exit;
  ConfigureCanvas;
  LastWidth := ViewRect.Width;
  KnownGeneration := Renderer.Generation;
  LayoutState.Reset(ViewRect.Width, FWordWrap And Not SingleLine, Max(18, Abs(Font.Height) + 5));
  WorkIndex := 0;
  If Assigned(Timer) Then Timer.Enabled := True;
  UpdateExtent;
End;

Procedure TCustomStyledText.GeometryChanged;
Begin
  If Not Assigned(FDocument) Then Exit;
  ConfigureCanvas;
  If (LastWidth <> ViewRect.Width) Or (KnownGeneration <> Renderer.Generation) Then ResetLayout;
End;

Procedure TCustomStyledText.DoDocumentChange(Sender: TObject; First, Removed, Added: Integer);
Begin
  If LayoutState.DocumentChanged(First, Removed, Added) Then WorkIndex := 0;
  If Not Changing Then
    Begin
      History := Nil;
      HistoryPosition := 0;
      Anchor := FDocument.Clamp(Anchor);
      Caret := FDocument.Clamp(Caret);
    End;
  WorkIndex := Min(WorkIndex, First);
  Timer.Enabled := True;
  Invalidate;
  If Assigned(FOnChange) Then FOnChange(Self);
End;

Procedure TCustomStyledText.EnsureLayout(Index: Integer; Finish: Boolean);
Begin
  LayoutState.Ensure(Index, Finish);
End;

Procedure TCustomStyledText.UpdateExtent;
Var
  NewWidth: Integer;
Begin
  NewWidth := ViewRect.Width;
  If Not FWordWrap Then NewWidth := Max(NewWidth, ContentWidth);
  If (Caret.Paragraph < Length(LayoutState.Paragraphs)) And Assigned(LayoutState.Paragraphs[Caret.Paragraph]) Then
    NewWidth := Max(NewWidth, LayoutState.Paragraphs[Caret.Paragraph].Width + 3);
  SetExtent(NewWidth, HeightBefore(LayoutState.Heights, FDocument.Count));
End;

Procedure TCustomStyledText.DoTimer(Sender: TObject);
Var
  Started: QWord;
  AnchorItem, Offset: Integer;
  PreviousTop: Int64;
Begin
  If Not Visible Or Not HandleAllocated Then Exit;
  ConfigureCanvas;
  If Selecting And ((PointerPosition.Y < ViewRect.Top) Or (PointerPosition.Y > ViewRect.Bottom)) Then
    Begin
      If PointerPosition.Y < ViewRect.Top Then ScrollTop := ScrollTop - 20 Else ScrollTop := ScrollTop + 20;
      MoveCaret(HitTest(PointerPosition.X, EnsureRange(PointerPosition.Y, ViewRect.Top, ViewRect.Bottom - 1)), True);
    End;
  If WorkIndex >= FDocument.Count Then
    Begin
      Timer.Enabled := Selecting;
      Exit;
    End;
  AnchorItem := ItemAtHeight(LayoutState.Heights, ScrollTop);
  Offset := ScrollTop - HeightBefore(LayoutState.Heights, AnchorItem);
  PreviousTop := ScrollTop;
  Started := GetTickCount64;
  While WorkIndex < FDocument.Count Do
    Begin
      EnsureLayout(WorkIndex);
      If LayoutState.Paragraphs[WorkIndex].Complete Then Inc(WorkIndex);
      If GetTickCount64 - Started >= 8 Then Break;
    End;
  UpdateExtent;
  If PreviousTop > 0 Then ScrollTop := HeightBefore(LayoutState.Heights, AnchorItem) + Offset;
  UpdateCaret;
  Invalidate;
End;

Procedure TCustomStyledText.PaintContent(Const Clip: TRect; OriginX: Integer; OriginY: Int64);
Var
  First, Last: TStyledPosition;
Begin
  GeometryChanged;
  GetSelection(First, Last);
  LayoutState.Paint(Clip, OriginX, OriginY, First, Last, HasSelection);
  UpdateExtent;
End;

Function TCustomStyledText.GetStyledText: UTF8String;
Begin
  Result := FDocument.Text;
End;

Procedure TCustomStyledText.SetStyledText(Const Value: UTF8String);
Var
  Clean: UTF8String;
Begin
  Clean := NormaliseStyledText(Value);
  If SingleLine Then Clean := StringReplace(Clean, #10, ' ', [rfReplaceAll]);
  FDocument.Text := Clean;
  Caret := StyledPosition(0, 0);
  Anchor := Caret;
  ScrollToStart;
End;

Procedure TCustomStyledText.SetLines(Value: TStrings);
Begin
  SetStyledText(Value.Text);
End;

Procedure TCustomStyledText.SetWordWrap(Value: Boolean);
Begin
  Value := Value And Not SingleLine;
  If FWordWrap = Value Then Exit;
  FWordWrap := Value;
  SetScrollbars(Not SingleLine, Not SingleLine And Not Value);
  LastWidth := -1;
  ResetLayout;
  Invalidate;
End;

Procedure TCustomStyledText.SetReadOnly(Value: Boolean);
Begin
  FReadOnly := Value;
  UpdateCaret;
  Invalidate;
End;

Procedure TCustomStyledText.SetShowCaret(Value: Boolean);
Begin
  If FShowCaret = Value Then Exit;
  FShowCaret := Value;
  UpdateCaret;
End;

Procedure TCustomStyledText.ReleaseCaret;
Begin
  If CaretCreated And HandleAllocated Then LCLIntf.DestroyCaret(Handle);
  CaretCreated := False;
End;

Procedure TCustomStyledText.DestroyWnd;
Begin
  ReleaseCaret;
  Inherited DestroyWnd;
End;

Procedure TCustomStyledText.WMSetFocus(Var Message: TLMSetFocus);
Begin
  Inherited WMSetFocus(Message);
  If Assigned(FDocument) Then
    Begin
      RevealCaret;
      UpdateCaret;
    End;
End;

Procedure TCustomStyledText.GetSelection(Out First, Last: TStyledPosition);
Begin
  If ComparePositions(Anchor, Caret) <= 0 Then
    Begin
      First := Anchor;
      Last := Caret;
    End
  Else
    Begin
      First := Caret;
      Last := Anchor;
    End;
End;

Function TCustomStyledText.GetHasSelection: Boolean;
Begin
  Result := ComparePositions(Anchor, Caret) <> 0;
End;

Function TCustomStyledText.GetSelectedText: UTF8String;
Var
  First, Last: TStyledPosition;
Begin
  GetSelection(First, Last);
  Result := StyledContentText(FDocument.Extract(First, Last));
End;

Procedure TCustomStyledText.SelectRange(Const First, Last: TStyledPosition);
Begin
  Anchor := FDocument.Clamp(First);
  MoveCaret(Last, True);
End;

Procedure TCustomStyledText.SelectAll;
Begin
  SelectRange(StyledPosition(0, 0), FDocument.EndPosition);
End;

Procedure TCustomStyledText.ClearSelection;
Begin
  Anchor := Caret;
  If Assigned(FOnSelectionChange) Then FOnSelectionChange(Self);
  Invalidate;
End;

Procedure TCustomStyledText.CopyToClipboard;
Begin
  If HasSelection Then Clipboard.AsText := SelectedText;
End;

Procedure TCustomStyledText.CutToClipboard;
Begin
  If ReadOnly Or Not HasSelection Then Exit;
  CopyToClipboard;
  InsertText('');
End;

Procedure TCustomStyledText.PasteFromClipboard;
Begin
  If Not ReadOnly Then InsertText(Clipboard.AsText);
End;

Procedure TCustomStyledText.ReplaceSelection(Const Content: TStyledContent);
Var
  Command: TStyledUndo;
Begin
  If ReadOnly Then Exit;
  GetSelection(Command.Start, Command.BeforeEnd);
  Command.Before := FDocument.Extract(Command.Start, Command.BeforeEnd);
  Command.After := Content;
  Changing := True;
  LayoutState.RestartParagraph := Command.Start.Paragraph;
  LayoutState.RestartOffset := Command.Start.Offset;
  Try
    Command.AfterEnd := FDocument.Replace(Command.Start, Command.BeforeEnd, Content);
  Finally
    Changing := False;
  End;
  SetLength(History, HistoryPosition + 1);
  History[HistoryPosition] := Command;
  Inc(HistoryPosition);
  { Bound the number of retained transactions; range payloads never copy unrelated paragraphs. }
  If HistoryPosition > 256 Then
    Begin
      History := Copy(History, 1, 256);
      HistoryPosition := 256;
    End;
  MoveCaret(Command.AfterEnd, False);
End;

Procedure TCustomStyledText.InsertText(Const Value: UTF8String);
Var
  Clean: UTF8String;
  First, Last: TStyledPosition;
Begin
  Clean := NormaliseStyledText(Value);
  If SingleLine Then Clean := StringReplace(Clean, #10, ' ', [rfReplaceAll]);
  GetSelection(First, Last);
  ReplaceSelection(FDocument.InsertionContent(First, Clean, FInsertionStyle));
End;

Procedure TCustomStyledText.AppendText(Const Value: UTF8String; FollowTail: Boolean);
Var
  AtEnd: Boolean;
  Last: TStyledPosition;
  Clean: UTF8String;
Begin
  Clean := NormaliseStyledText(Value);
  If SingleLine Then Clean := StringReplace(Clean, #10, ' ', [rfReplaceAll]);
  AtEnd := ScrollTop >= ContentHeight - ViewRect.Height - 3;
  Last := FDocument.EndPosition;
  Changing := True;
  LayoutState.RestartParagraph := Last.Paragraph;
  LayoutState.RestartOffset := Last.Offset;
  Try
    Last := FDocument.ReplaceText(Last, Last, Clean, FInsertionStyle);
  Finally
    Changing := False;
  End;
  History := Nil;
  HistoryPosition := 0;
  If FollowTail And AtEnd Then MoveCaret(Last, False);
End;

Procedure TCustomStyledText.ApplySelectionStyle(Style: Integer);
Var
  First, Last: TStyledPosition;
  Content: TStyledContent;
  Index: Integer;
Begin
  FInsertionStyle := Style;
  If Not HasSelection Then Exit;
  GetSelection(First, Last);
  Content := FDocument.Extract(First, Last);
  For Index := 0 To High(Content) Do
    Begin
      Content[Index].Ranges := Nil;
      AddStyledRange(Content[Index].Ranges, 0, Length(Content[Index].Text), Style);
    End;
  ReplaceSelection(Content);
  SelectRange(First, Last);
End;

Function TCustomStyledText.StyleAtPosition(Const Position: TStyledPosition): Integer;
Var
  Range: TStyledRange;
Begin
  Result := FInsertionStyle;
  For Range In FDocument[Position.Paragraph]^.Ranges Do
    If (Position.Offset >= Range.Start) And (Position.Offset < Range.Start + Range.Count) Then Exit(Range.Style);
End;

Procedure TCustomStyledText.GetTextAttributes(Out Style: TStyledStyle; Out Mixed: TStyledAttributes);
Var
  First, Last: TStyledPosition;
  ParagraphIndex, StartOffset, EndOffset: Integer;
  Range: TStyledRange;
  Current: TStyledStyle;
  Found: Boolean;
Begin
  Style := Renderer.StyleInfo[FInsertionStyle];
  Mixed := [];
  If Not HasSelection Then Exit;
  GetSelection(First, Last);
  Found := False;
  For ParagraphIndex := First.Paragraph To Last.Paragraph Do
    Begin
      StartOffset := 0;
      EndOffset := Length(FDocument[ParagraphIndex]^.Text);
      If ParagraphIndex = First.Paragraph Then StartOffset := First.Offset;
      If ParagraphIndex = Last.Paragraph Then EndOffset := Last.Offset;
      For Range In FDocument[ParagraphIndex]^.Ranges Do
        If (Range.Start < EndOffset) And (Range.Start + Range.Count > StartOffset) Then
          Begin
            Current := Renderer.StyleInfo[Range.Style];
            If Not Found Then Style := Current Else Mixed := Mixed + DifferentStyledAttributes(Style, Current);
            Found := True;
          End;
    End;
End;

Procedure TCustomStyledText.ApplyTextAttributes(Const Style: TStyledStyle; Attributes: TStyledAttributes);
Var
  First, Last: TStyledPosition;
  Content: TStyledContent;
  ParagraphIndex, RangeIndex, NewInsertionStyle: Integer;
  NewRanges: TStyledRanges;
  Range: TStyledRange;
Begin
  If ReadOnly Or (Attributes = []) Then Exit;
  NewInsertionStyle := Renderer.AddStyle(MergeStyledAttributes(Renderer.StyleInfo[FInsertionStyle], Style, Attributes));
  If HasSelection Then
    Begin
      GetSelection(First, Last);
      Content := FDocument.Extract(First, Last);
      For ParagraphIndex := 0 To High(Content) Do
        Begin
          NewRanges := Nil;
          For RangeIndex := 0 To High(Content[ParagraphIndex].Ranges) Do
            Begin
              Range := Content[ParagraphIndex].Ranges[RangeIndex];
              Range.Style := Renderer.AddStyle(MergeStyledAttributes(Renderer.StyleInfo[Range.Style], Style, Attributes));
              AddStyledRange(NewRanges, Range.Start, Range.Count, Range.Style);
            End;
          Content[ParagraphIndex].Ranges := NewRanges;
        End;
      ReplaceSelection(Content);
      SelectRange(First, Last);
    End;
  FInsertionStyle := NewInsertionStyle;
  If Assigned(FOnSelectionChange) Then FOnSelectionChange(Self);
End;

Function TCustomStyledText.CurrentParagraphBox: TStyledParagraphBox;
Var
  First, Last: TStyledPosition;
Begin
  GetSelection(First, Last);
  Result := FDocument[First.Paragraph]^.Box;
End;

Procedure TCustomStyledText.ApplyParagraphBox(Const Style: TStyledBoxStyle);
Begin
  SetParagraphBox(Style, True);
End;

Procedure TCustomStyledText.RemoveParagraphBox;
Begin
  SetParagraphBox(DefaultStyledBoxStyle, False);
End;

Procedure TCustomStyledText.SetParagraphBox(Const Style: TStyledBoxStyle; EnabledBox: Boolean);
Var
  First, Last, SavedFirst, SavedLast: TStyledPosition;
  Content: TStyledContent;
  Index: Integer;
  Box: TStyledParagraphBox;
Begin
  If ReadOnly Or SingleLine Then Exit;
  GetSelection(SavedFirst, SavedLast);
  First := StyledPosition(SavedFirst.Paragraph, 0);
  Last := SavedLast;
  If (Last.Offset = 0) And (Last.Paragraph > First.Paragraph) Then Dec(Last.Paragraph);
  Last.Offset := Length(FDocument[Last.Paragraph]^.Text);
  Content := FDocument.Extract(First, Last);
  Box := Default(TStyledParagraphBox);
  If EnabledBox Then
    Begin
      Box.Group := FDocument.NewBoxGroup;
      Box.Style := Style;
    End;
  For Index := 0 To High(Content) Do
    If EnabledBox And (Length(Content[Index].Box.Columns) > 0) Then
      Content[Index].Box.Style := Style
    Else Content[Index].Box := Box;
  SelectRange(First, Last);
  ReplaceSelection(Content);
  SelectRange(SavedFirst, SavedLast);
End;

Function TCustomStyledText.CanUndo: Boolean;
Begin
  Result := (HistoryPosition > 0) And Not ReadOnly;
End;

Function TCustomStyledText.CanRedo: Boolean;
Begin
  Result := (HistoryPosition < Length(History)) And Not ReadOnly;
End;

Procedure TCustomStyledText.Undo;
Var
  Command: TStyledUndo;
Begin
  If Not CanUndo Then Exit;
  Dec(HistoryPosition);
  Command := History[HistoryPosition];
  Changing := True;
  Try
    FDocument.Replace(Command.Start, Command.AfterEnd, Command.Before);
  Finally
    Changing := False;
  End;
  MoveCaret(Command.BeforeEnd, False);
End;

Procedure TCustomStyledText.Redo;
Var
  Command: TStyledUndo;
Begin
  If Not CanRedo Then Exit;
  Command := History[HistoryPosition];
  Inc(HistoryPosition);
  Changing := True;
  Try
    FDocument.Replace(Command.Start, Command.BeforeEnd, Command.After);
  Finally
    Changing := False;
  End;
  MoveCaret(Command.AfterEnd, False);
End;

Procedure TCustomStyledText.MoveCaret(Const Position: TStyledPosition; Extend: Boolean; KeepX: Boolean);
Begin
  Caret := FDocument.Clamp(Position);
  If Caret.Offset > 0 Then FInsertionStyle := StyleAtPosition(StyledPosition(Caret.Paragraph, Caret.Offset - 1))
  Else FInsertionStyle := StyleAtPosition(Caret);
  If Not Extend Then Anchor := Caret;
  If Not KeepX Then PreferredX := -1;
  RevealCaret;
  UpdateCaret;
  Invalidate;
  If Assigned(FOnSelectionChange) Then FOnSelectionChange(Self);
End;

Procedure TCustomStyledText.RevealCaret;
Var
  Bounds: TRect;
  LogicalTop: Int64;
Begin
  ConfigureCanvas;
  EnsureLayout(Caret.Paragraph, True);
  UpdateExtent;
  Bounds := Renderer.CaretRect(LayoutState.Paragraphs[Caret.Paragraph], Caret.Offset, Caret.Trailing);
  OffsetRect(Bounds, LayoutState.TextLeft(Caret.Paragraph), 0);
  LogicalTop := LayoutState.TextTop(Caret.Paragraph);
  If LogicalTop + Bounds.Top < ScrollTop Then ScrollTop := LogicalTop + Bounds.Top
  Else If LogicalTop + Bounds.Bottom > ScrollTop + ViewRect.Height Then ScrollTop := LogicalTop + Bounds.Bottom - ViewRect.Height;
  If Bounds.Left < ScrollLeft Then ScrollLeft := Bounds.Left
  Else If Bounds.Right > ScrollLeft + ViewRect.Width Then ScrollLeft := Bounds.Right - ViewRect.Width;
End;

Procedure TCustomStyledText.UpdateCaret;
Var
  Bounds, View: TRect;
  LogicalTop: Int64;
Begin
  If Not FShowCaret Or Not Focused Or Not HandleAllocated Then
    Begin
      ReleaseCaret;
      Exit;
    End;
  If (Caret.Paragraph >= Length(LayoutState.Paragraphs)) Or Not Assigned(LayoutState.Paragraphs[Caret.Paragraph]) Then Exit;
  ConfigureCanvas;
  Bounds := Renderer.CaretRect(LayoutState.Paragraphs[Caret.Paragraph], Caret.Offset, Caret.Trailing);
  View := ViewRect;
  OffsetRect(Bounds, LayoutState.TextLeft(Caret.Paragraph), 0);
  LogicalTop := LayoutState.TextTop(Caret.Paragraph) + Bounds.Top - ScrollTop;
  If CaretCreated And (NativeCaretHeight <> Bounds.Height) Then
    ReleaseCaret;
  If Not CaretCreated Then
    Begin
      NativeCaretHeight := Bounds.Height;
      CaretCreated := CreateCaret(Handle, 0, 2, Bounds.Height);
      If CaretCreated Then LCLIntf.ShowCaret(Handle);
    End;
  If (LogicalTop < 0) Or (LogicalTop + Bounds.Height > View.Height) Then SetCaretPosEx(Handle, -10, -100)
  Else SetCaretPosEx(Handle, View.Left + Bounds.Left - ScrollLeft, View.Top + LogicalTop);
End;

Procedure TCustomStyledText.Scrolled;
Begin
  UpdateCaret;
End;

Procedure TCustomStyledText.DoEnter;
Begin
  Inherited DoEnter;
  RevealCaret;
  UpdateCaret;
  Invalidate;
End;

Procedure TCustomStyledText.DoExit;
Begin
  Selecting := False;
  MouseCapture := False;
  ReleaseCaret;
  Inherited DoExit;
  Invalidate;
End;

Procedure TCustomStyledText.GetDialogCode(Var Message: TLMGetDlgCode);
Begin
  Message.Result := DLGC_WANTARROWS Or DLGC_WANTCHARS;
  If Not SingleLine Then Message.Result := Message.Result Or DLGC_WANTALLKEYS;
  If WantTabs Then Message.Result := Message.Result Or DLGC_WANTTAB;
End;

Function TCustomStyledText.StepPosition(Const Position: TStyledPosition; ForwardStep, ByWord: Boolean): TStyledPosition;
Var
  Value: UTF8String;
Begin
  Result := Position;
  Result.Trailing := False;
  Value := FDocument[Result.Paragraph]^.Text;
  If ForwardStep Then
    Begin
      If Result.Offset = Length(Value) Then
        Begin
          If Result.Paragraph < FDocument.Count - 1 Then Result := StyledPosition(Result.Paragraph + 1, 0);
          Exit;
        End;
      Result.Offset := NextCluster(Value, Result.Offset);
      If ByWord Then
        Begin
          While (Result.Offset < Length(Value)) And Not IsWordSeparator(Value, Result.Offset) Do
            Result.Offset := NextCluster(Value, Result.Offset);
          While (Result.Offset < Length(Value)) And IsWordSeparator(Value, Result.Offset) Do
            Result.Offset := NextCluster(Value, Result.Offset);
        End;
    End
  Else
    Begin
      If Result.Offset = 0 Then
        Begin
          If Result.Paragraph > 0 Then Result := StyledPosition(Result.Paragraph - 1, Length(FDocument[Result.Paragraph - 1]^.Text));
          Exit;
        End;
      Result.Offset := PreviousCluster(Value, Result.Offset);
      If ByWord Then
        Begin
          While (Result.Offset > 0) And IsWordSeparator(Value, Result.Offset) Do Result.Offset := PreviousCluster(Value, Result.Offset);
          While (Result.Offset > 0) And Not IsWordSeparator(Value, PreviousCluster(Value, Result.Offset)) Do
            Result.Offset := PreviousCluster(Value, Result.Offset);
        End;
    End;
End;

Procedure TCustomStyledText.KeyDown(Var Key: Word; Shift: TShiftState);
Var
  NewPosition, First, Last: TStyledPosition;
  Index, Direction, LineIndex: Integer;
  Line: TStyledVisualLine;
  CommandKey, Extend: Boolean;
  Y: Int64;
Begin
  Inherited KeyDown(Key, Shift);
  If Key = 0 Then Exit;
  CommandKey := ssCtrl In Shift;
  {$IFDEF DARWIN}CommandKey := CommandKey Or (ssMeta In Shift);{$ENDIF}
  Extend := ssShift In Shift;
  If CommandKey Then
    Case Key Of
      VK_A: Begin SelectAll; Key := 0; End;
      VK_C: Begin CopyToClipboard; Key := 0; End;
      VK_X: Begin CutToClipboard; Key := 0; End;
      VK_V: Begin PasteFromClipboard; Key := 0; End;
      VK_Z: Begin If Extend Then Redo Else Undo; Key := 0; End;
      VK_Y: Begin Redo; Key := 0; End;
    Else
    End;
  If Key = 0 Then Exit;
  NewPosition := Caret;
  ConfigureCanvas;
  EnsureLayout(Caret.Paragraph, True);
  LineIndex := LayoutState.Paragraphs[Caret.Paragraph].LineAtOffset(Caret.Offset, Caret.Trailing);
  Line := LayoutState.Paragraphs[Caret.Paragraph].Lines[LineIndex];
  Case Key Of
    VK_LEFT, VK_RIGHT:
      Begin
        If HasSelection And Not Extend Then
          Begin
            GetSelection(First, Last);
            If Key = VK_LEFT Then NewPosition := First Else NewPosition := Last;
          End
        Else NewPosition := StepPosition(Caret, Key = VK_RIGHT, CommandKey);
        MoveCaret(NewPosition, Extend);
      End;
    VK_HOME, VK_END:
      Begin
        If CommandKey Then
          Begin
            If Key = VK_HOME Then NewPosition := StyledPosition(0, 0) Else NewPosition := FDocument.EndPosition;
          End
        Else If Key = VK_HOME Then NewPosition.Offset := Line.Start
        Else
          Begin
            NewPosition.Offset := Line.Finish;
            NewPosition.Trailing := True;
          End;
        MoveCaret(NewPosition, Extend);
      End;
    VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
      Begin
        If PreferredX < 0 Then
          PreferredX := LayoutState.TextLeft(Caret.Paragraph) + Renderer.PositionX(LayoutState.Paragraphs[Caret.Paragraph], LineIndex, Caret.Offset);
        Direction := 1;
        If Key In [VK_UP, VK_PRIOR] Then Direction := -1;
        Index := Caret.Paragraph;
        Y := LayoutState.TextTop(Index) + Line.Top;
        If Key In [VK_PRIOR, VK_NEXT] Then
          Begin
            Inc(Y, Direction * ViewRect.Height);
            Index := ItemAtHeight(LayoutState.Heights, Max(Int64(0), Y));
          End
        Else If Direction < 0 Then
          Begin
            If (LayoutState.Paragraphs[Index].AtVerticalEdge(Caret.Offset, Caret.Trailing, True)) And (Index > 0) Then
              Begin
                Dec(Index);
                EnsureLayout(Index, True);
                Y := LayoutState.TextTop(Index) + LayoutState.Paragraphs[Index].Height - 1;
              End
            Else Dec(Y);
          End
        Else If (LayoutState.Paragraphs[Index].AtVerticalEdge(Caret.Offset, Caret.Trailing, False)) And (Index < FDocument.Count - 1) Then
          Begin
            Inc(Index);
            Y := LayoutState.TextTop(Index);
          End
        Else Inc(Y, Line.Height);
        EnsureLayout(Index, True);
        NewPosition.Paragraph := Index;
        NewPosition.Offset := Renderer.HitTest(LayoutState.Paragraphs[Index], PreferredX - LayoutState.TextLeft(Index),
          Max(Int64(0), Y - LayoutState.TextTop(Index)), NewPosition.Trailing);
        MoveCaret(NewPosition, Extend, True);
      End;
    VK_BACK, VK_DELETE:
      Begin
        If ReadOnly Then Begin Key := 0; Exit; End;
        If Not HasSelection Then Anchor := StepPosition(Caret, Key = VK_DELETE, CommandKey);
        InsertText('');
      End;
    VK_RETURN:
      If Not SingleLine Then InsertText(#10);
    VK_TAB:
      Begin
        If Not WantTabs Then Exit;
        InsertText(#9);
      End;
  Else
    Exit;
  End;
  Key := 0;
End;

Procedure TCustomStyledText.UTF8KeyPress(Var UTF8Key: TUTF8Char);
Begin
  Inherited UTF8KeyPress(UTF8Key);
  If (UTF8Key <> '') And (Byte(UTF8Key[1]) >= 32) Then
    Begin
      InsertText(UTF8Key);
      UTF8Key := '';
    End;
End;

Function TCustomStyledText.HitTest(X, Y: Integer): TStyledPosition;
Var
  LogicalY: Int64;
Begin
  ConfigureCanvas;
  LogicalY := Max(Int64(0), Int64(Y - ViewRect.Top) + ScrollTop);
  Result.Paragraph := ItemAtHeight(LayoutState.Heights, LogicalY);
  EnsureLayout(Result.Paragraph, True);
  Result.Offset := Renderer.HitTest(LayoutState.Paragraphs[Result.Paragraph], X - ViewRect.Left + ScrollLeft - LayoutState.TextLeft(Result.Paragraph),
    LogicalY - LayoutState.TextTop(Result.Paragraph), Result.Trailing);
End;

Procedure TCustomStyledText.CompleteLayout;
Var
  Index: Integer;
Begin
  If Not Assigned(FDocument) Then Exit;
  ConfigureCanvas;
  If (LastWidth <> ViewRect.Width) Or (KnownGeneration <> Renderer.Generation) Then ResetLayout;
  For Index := 0 To FDocument.Count - 1 Do
    EnsureLayout(Index, True);
  WorkIndex := FDocument.Count;
  If Assigned(Timer) And Not Selecting Then Timer.Enabled := False;
  UpdateExtent;
End;

Procedure TCustomStyledText.SelectWordAt(X, Y: Integer);
Var
  First, Last: TStyledPosition;
  Value: UTF8String;
Begin
  First := HitTest(X, Y);
  Last := First;
  Value := FDocument[First.Paragraph]^.Text;
  While (First.Offset > 0) And Not IsWordSeparator(Value, PreviousCluster(Value, First.Offset)) Do
    First.Offset := PreviousCluster(Value, First.Offset);
  While (Last.Offset < Length(Value)) And Not IsWordSeparator(Value, Last.Offset) Do
    Last.Offset := NextCluster(Value, Last.Offset);
  SelectRange(First, Last);
End;

Procedure TCustomStyledText.SelectLineAt(X, Y: Integer);
Var
  Position: TStyledPosition;
  LineIndex: Integer;
  Line: TStyledVisualLine;
Begin
  Position := HitTest(X, Y);
  EnsureLayout(Position.Paragraph, True);
  If (Position.Paragraph >= Length(LayoutState.Paragraphs)) Or Not Assigned(LayoutState.Paragraphs[Position.Paragraph]) Or
    (LayoutState.Paragraphs[Position.Paragraph].LineCount <= 0) Then
    Begin
      SelectRange(StyledPosition(Position.Paragraph, 0),
        StyledPosition(Position.Paragraph, Length(FDocument[Position.Paragraph]^.Text)));
      Exit;
    End;
  LineIndex := LayoutState.Paragraphs[Position.Paragraph].LineAtOffset(Position.Offset, Position.Trailing);
  Line := LayoutState.Paragraphs[Position.Paragraph].Lines[LineIndex];
  SelectRange(StyledPosition(Position.Paragraph, Line.Start), StyledPosition(Position.Paragraph, Line.Finish, True));
End;

Procedure TCustomStyledText.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseDown(Button, Shift, X, Y);
  If Button <> mbLeft Then Exit;
  SetFocus;
  PointerPosition := Point(X, Y);
  MoveCaret(HitTest(X, Y), ssShift In Shift);
  Selecting := True;
  MouseCapture := True;
  Timer.Enabled := True;
End;

Procedure TCustomStyledText.MouseMove(Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseMove(Shift, X, Y);
  PointerPosition := Point(X, Y);
  If Selecting Then MoveCaret(HitTest(X, Y), True);
End;

Procedure TCustomStyledText.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Inherited MouseUp(Button, Shift, X, Y);
  If Button <> mbLeft Then Exit;
  Selecting := False;
  MouseCapture := False;
End;

Procedure TCustomStyledText.DblClick;
Begin
  Inherited DblClick;
  SelectWordAt(PointerPosition.X, PointerPosition.Y);
End;

Initialization
  RegisterClass(TStyledEdit);
  RegisterClass(TStyledMemo);

Finalization
  UnRegisterClass(TStyledMemo);
  UnRegisterClass(TStyledEdit);

End.
