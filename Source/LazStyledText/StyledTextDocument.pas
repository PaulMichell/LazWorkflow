Unit StyledTextDocument;

{ Paragraph-local styled text storage and range mutations (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, StyledTextTypes;

Type
  TStyledDocumentChange = Procedure(Sender: TObject; First, Removed, Added: Integer) Of Object;
  TStyledDocument = Class
  Private
    Paragraphs: TStyledContent;
    NextIdentity, NextBoxGroup: QWord;
    FCount: Integer;
    FOnChange: TStyledDocumentChange;
    Function GetParagraph(Index: Integer): TStyledParagraphPointer;
    Function GetText: UTF8String;
    Procedure SetText(Const NewText: UTF8String);
  Public
    Constructor Create;
    Function Clamp(Const Position: TStyledPosition): TStyledPosition;
    Function Extract(Const First, Last: TStyledPosition): TStyledContent;
    Function Replace(Const First, Last: TStyledPosition; Const Content: TStyledContent): TStyledPosition;
    Function NewBoxGroup: QWord;
    Function InsertionContent(Const Position: TStyledPosition; Const Value: UTF8String; Style: Integer): TStyledContent;
    Function ReplaceText(Const First, Last: TStyledPosition; Const Value: UTF8String; Style: Integer): TStyledPosition;
    Procedure SetParagraph(Index: Integer; Const Paragraph: TStyledParagraph);
    Procedure ApplyStyle(Const First, Last: TStyledPosition; Style: Integer);
    Function EndPosition: TStyledPosition;
    Function Validate: Boolean;
    Property Count: Integer Read FCount;
    Property Items[Index: Integer]: TStyledParagraphPointer Read GetParagraph; Default;
    Property Text: UTF8String Read GetText Write SetText;
    Property OnChange: TStyledDocumentChange Read FOnChange Write FOnChange;
  End;

Function StyledContentFromText(Const Value: UTF8String; Style: Integer = 0): TStyledContent;
Function StyledContentText(Const Content: TStyledContent): UTF8String;

Implementation

Uses
  SysUtils, Math;

Function SliceParagraph(Const Paragraph: TStyledParagraph; Start, Count: Integer): TStyledParagraph;
Var
  Range: TStyledRange;
  Left, Right: Integer;
Begin
  Result := Default(TStyledParagraph);
  Result.Text := Copy(Paragraph.Text, Start + 1, Count);
  Result.Box := Paragraph.Box;
  Result.Box.Columns := Copy(Paragraph.Box.Columns);
  For Range In Paragraph.Ranges Do
    Begin
      Left := Max(Start, Range.Start);
      Right := Min(Start + Count, Range.Start + Range.Count);
      AddStyledRange(Result.Ranges, Left - Start, Right - Left, Range.Style);
    End;
End;

Procedure JoinParagraph(Var Target: TStyledParagraph; Const Suffix: TStyledParagraph);
Var
  Range: TStyledRange;
  Offset: Integer;
Begin
  Offset := Length(Target.Text);
  For Range In Suffix.Ranges Do AddStyledRange(Target.Ranges, Offset + Range.Start, Range.Count, Range.Style);
  Target.Text += Suffix.Text;
End;

Function StyledContentFromText(Const Value: UTF8String; Style: Integer): TStyledContent;
Var
  Clean: UTF8String;
  Index, Start, Count, Item: Integer;
Begin
  Result := Nil;
  Clean := NormaliseStyledText(Value);
  Count := 1;
  For Index := 1 To Length(Clean) Do If Clean[Index] = #10 Then Inc(Count);
  SetLength(Result, Count);
  Start := 1;
  Item := 0;
  For Index := 1 To Length(Clean) + 1 Do
    If (Index > Length(Clean)) Or (Clean[Index] = #10) Then
      Begin
        AppendStyledText(Result[Item], Copy(Clean, Start, Index - Start), Style);
        Inc(Item);
        Start := Index + 1;
      End;
End;

Function StyledContentText(Const Content: TStyledContent): UTF8String;
Var
  Size, Offset, Index, Part: SizeInt;
Begin
  Size := Max(0, Length(Content) - 1);
  For Index := 0 To High(Content) Do Inc(Size, Length(Content[Index].Text));
  SetLength(Result, Size);
  Offset := 1;
  For Index := 0 To High(Content) Do
    Begin
      If Index > 0 Then
        Begin
          Result[Offset] := #10;
          Inc(Offset);
        End;
      Part := Length(Content[Index].Text);
      If Part > 0 Then Move(Content[Index].Text[1], Result[Offset], Part);
      Inc(Offset, Part);
    End;
End;

Constructor TStyledDocument.Create;
Begin
  Inherited Create;
  NextIdentity := 1;
  NextBoxGroup := 1;
  SetText('');
End;

Function TStyledDocument.GetParagraph(Index: Integer): TStyledParagraphPointer;
Begin
  If (Index < 0) Or (Index >= FCount) Then Raise ERangeError.Create('Paragraph index outside document');
  Result := @Paragraphs[Index];
End;

Function TStyledDocument.EndPosition: TStyledPosition;
Begin
  Result := StyledPosition(FCount - 1, Length(Paragraphs[FCount - 1].Text));
End;

Function TStyledDocument.Clamp(Const Position: TStyledPosition): TStyledPosition;
Begin
  Result := Position;
  Result.Paragraph := EnsureRange(Result.Paragraph, 0, FCount - 1);
  Result.Offset := EnsureRange(Result.Offset, 0, Length(Paragraphs[Result.Paragraph].Text));
  While (Result.Offset > 0) And (Result.Offset < Length(Paragraphs[Result.Paragraph].Text)) And
    ((Byte(Paragraphs[Result.Paragraph].Text[Result.Offset + 1]) And $C0) = $80) Do Dec(Result.Offset);
End;

Function TStyledDocument.Extract(Const First, Last: TStyledPosition): TStyledContent;
Var
  Start, Finish: TStyledPosition;
  Index, Left, Right: Integer;
Begin
  Result := Nil;
  Start := Clamp(First);
  Finish := Clamp(Last);
  If ComparePositions(Start, Finish) > 0 Then Raise ERangeError.Create('Reversed text range');
  SetLength(Result, Finish.Paragraph - Start.Paragraph + 1);
  For Index := Start.Paragraph To Finish.Paragraph Do
    Begin
      Left := 0;
      Right := Length(Paragraphs[Index].Text);
      If Index = Start.Paragraph Then Left := Start.Offset;
      If Index = Finish.Paragraph Then Right := Finish.Offset;
      Result[Index - Start.Paragraph] := SliceParagraph(Paragraphs[Index], Left, Right - Left);
    End;
End;

Function TStyledDocument.Replace(Const First, Last: TStyledPosition; Const Content: TStyledContent): TStyledPosition;
Var
  Start, Finish: TStyledPosition;
  Replacement: TStyledContent;
  Prefix, Suffix: TStyledParagraph;
  Index, Removed, Added, Delta, NewCount: Integer;
  Identity, Revision: QWord;
Begin
  Start := Clamp(First);
  Finish := Clamp(Last);
  If ComparePositions(Start, Finish) > 0 Then Raise ERangeError.Create('Reversed text range');
  Added := Max(1, Length(Content));
  SetLength(Replacement, Added);
  For Index := 0 To High(Content) Do
    Begin
      Replacement[Index] := Content[Index];
      NextBoxGroup := Max(NextBoxGroup, Content[Index].Box.Group + 1);
      Replacement[Index].Ranges := Copy(Content[Index].Ranges);
      Replacement[Index].Box.Columns := Copy(Content[Index].Box.Columns);
    End;
  Prefix := SliceParagraph(Paragraphs[Start.Paragraph], 0, Start.Offset);
  Suffix := SliceParagraph(Paragraphs[Finish.Paragraph], Finish.Offset, Length(Paragraphs[Finish.Paragraph].Text) - Finish.Offset);
  Identity := Paragraphs[Start.Paragraph].Identity;
  Revision := Paragraphs[Start.Paragraph].Revision + 1;
  Prefix.Box := Replacement[0].Box;
  JoinParagraph(Prefix, Replacement[0]);
  Replacement[0] := Prefix;
  Result := StyledPosition(Start.Paragraph + Added - 1, Length(Replacement[Added - 1].Text));
  JoinParagraph(Replacement[Added - 1], Suffix);
  Removed := Finish.Paragraph - Start.Paragraph + 1;
  Delta := Added - Removed;
  NewCount := FCount + Delta;
  If NewCount > Length(Paragraphs) Then SetLength(Paragraphs, Max(NewCount, Max(16, Length(Paragraphs) * 2)));
  If Delta > 0 Then
    For Index := FCount - 1 DownTo Finish.Paragraph + 1 Do Paragraphs[Index + Delta] := Paragraphs[Index]
  Else If Delta < 0 Then
    For Index := Finish.Paragraph + 1 To FCount - 1 Do Paragraphs[Index + Delta] := Paragraphs[Index];
  For Index := 0 To Added - 1 Do
    Begin
      Paragraphs[Start.Paragraph + Index] := Replacement[Index];
      Paragraphs[Start.Paragraph + Index].Revision := Revision;
      If Index = 0 Then Paragraphs[Start.Paragraph + Index].Identity := Identity
      Else
        Begin
          Paragraphs[Start.Paragraph + Index].Identity := NextIdentity;
          Inc(NextIdentity);
        End;
    End;
  For Index := NewCount To FCount - 1 Do Paragraphs[Index] := Default(TStyledParagraph);
  FCount := NewCount;
  If Assigned(FOnChange) Then FOnChange(Self, Start.Paragraph, Removed, Added);
End;

Function TStyledDocument.NewBoxGroup: QWord;
Begin
  Result := NextBoxGroup;
  Inc(NextBoxGroup);
End;

Function TStyledDocument.InsertionContent(Const Position: TStyledPosition; Const Value: UTF8String; Style: Integer): TStyledContent;
Var
  Index: Integer;
  Start: TStyledPosition;
Begin
  Start := Clamp(Position);
  Result := StyledContentFromText(Value, Style);
  For Index := 0 To High(Result) Do Result[Index].Box := Paragraphs[Start.Paragraph].Box;
End;

Function TStyledDocument.ReplaceText(Const First, Last: TStyledPosition; Const Value: UTF8String; Style: Integer): TStyledPosition;
Begin
  Result := Replace(First, Last, InsertionContent(First, Value, Style));
End;

Procedure TStyledDocument.SetParagraph(Index: Integer; Const Paragraph: TStyledParagraph);
Var
  Content: TStyledContent;
Begin
  SetLength(Content, 1);
  Content[0] := Paragraph;
  Replace(StyledPosition(Index, 0), StyledPosition(Index, Length(Items[Index]^.Text)), Content);
End;

Procedure TStyledDocument.ApplyStyle(Const First, Last: TStyledPosition; Style: Integer);
Var
  Content: TStyledContent;
  Index: Integer;
Begin
  Content := Extract(First, Last);
  For Index := 0 To High(Content) Do
    Begin
      Content[Index].Ranges := Nil;
      AddStyledRange(Content[Index].Ranges, 0, Length(Content[Index].Text), Style);
    End;
  Replace(First, Last, Content);
End;

Function TStyledDocument.GetText: UTF8String;
Begin
  Result := StyledContentText(Copy(Paragraphs, 0, FCount));
End;

Procedure TStyledDocument.SetText(Const NewText: UTF8String);
Var
  OldCount, Index: Integer;
Begin
  OldCount := FCount;
  Paragraphs := StyledContentFromText(NewText);
  FCount := Length(Paragraphs);
  For Index := 0 To FCount - 1 Do
    Begin
      Paragraphs[Index].Identity := NextIdentity;
      Inc(NextIdentity);
    End;
  If Assigned(FOnChange) Then FOnChange(Self, 0, OldCount, FCount);
End;

Function TStyledDocument.Validate: Boolean;
Var
  Index, Offset: Integer;
  Range: TStyledRange;
Begin
  Result := FCount > 0;
  For Index := 0 To FCount - 1 Do
    Begin
      Offset := 0;
      For Range In Paragraphs[Index].Ranges Do
        Begin
          If (Range.Start <> Offset) Or (Range.Count <= 0) Or (Range.Style < 0) Then Exit(False);
          Inc(Offset, Range.Count);
        End;
      If Offset <> Length(Paragraphs[Index].Text) Then Exit(False);
    End;
End;

End.
