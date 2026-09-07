Unit StyledTextTypes;

{ Shared styled paragraph values and position helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Graphics;

Type
  TStyledScript = (ssNormal, ssSubscript, ssSuperscript);
  TStyledWrap = (swNone, swWord, swCharacter);
  TStyledStyle = Record
    FontName: String;
    Size: Integer;
    Styles: TFontStyles;
    Foreground: TColor;
    Background: TColor;
    Script: TStyledScript;
  End;
  TStyledAttribute = (saFontName, saSize, saBold, saItalic, saUnderline, saStrikeOut, saForeground, saBackground, saScript);
  TStyledAttributes = Set Of TStyledAttribute;
  TStyledInsets = Record
    Top, Right, Bottom, Left: Integer;
  End;
  TStyledBoxStyle = Record
    Margin, Padding: TStyledInsets;
    BorderWidth, CornerRadius: Integer;
    Background, BorderColor: TColor;
  End;
  TStyledCellAlignment = (scaLeft, scaCenter, scaRight);
  TStyledColumns = Array Of TStyledCellAlignment;
  TStyledParagraphBox = Record
    Group: QWord;
    Style: TStyledBoxStyle;
    { Nonempty: this paragraph is a table row, with tab-separated cells. }
    Columns: TStyledColumns;
  End;
  TStyledBoxRect = Record
    Left, Top, Right, Bottom: Int64;
  End;
  TStyledBoxGeometry = Record
    Outer, Border, Padding, Content: TStyledBoxRect;
  End;
  TStyledRange = Record
    Start, Count, Style: Integer;
  End;
  TStyledRanges = Array Of TStyledRange;
  TStyledParagraph = Record
    Text: UTF8String;
    Ranges: TStyledRanges;
    Revision: QWord;
    Identity: QWord;
    Box: TStyledParagraphBox;
  End;
  TStyledParagraphPointer = ^TStyledParagraph;
  TStyledContent = Array Of TStyledParagraph;
  TStyledPosition = Record
    Paragraph, Offset: Integer;
    Trailing: Boolean;
  End;
  TStyledIntegers = Array Of Integer;
  TStyledHeightIndex = Record
    Values, Sums: Array Of Int64;
  End;

Function StyledInsets(All: Integer): TStyledInsets; Overload;
Function StyledInsets(Vertical, Horizontal: Integer): TStyledInsets; Overload;
Function StyledInsets(Top, Right, Bottom, Left: Integer): TStyledInsets; Overload;
Function DefaultStyledBoxStyle: TStyledBoxStyle;
Function GetStyledBoxGeometry(X, Y, Width, Height: Int64; Const Style: TStyledBoxStyle): TStyledBoxGeometry;
Function MergeStyledAttributes(Const Original, Changes: TStyledStyle; Attributes: TStyledAttributes): TStyledStyle;
Function DifferentStyledAttributes(Const First, Second: TStyledStyle): TStyledAttributes;
Function DefaultStyledStyle: TStyledStyle;
Function StyledPosition(Paragraph, Offset: Integer; Trailing: Boolean = False): TStyledPosition;
Function ComparePositions(Const First, Second: TStyledPosition): Integer;
Function NextCodepoint(Const Value: UTF8String; Offset: Integer): Integer;
Function PreviousCodepoint(Const Value: UTF8String; Offset: Integer): Integer;
Function NextCluster(Const Value: UTF8String; Offset: Integer): Integer;
Function PreviousCluster(Const Value: UTF8String; Offset: Integer): Integer;
Function IsWordSeparator(Const Value: UTF8String; Offset: Integer): Boolean;
Function NormaliseStyledText(Const Value: UTF8String): UTF8String;
Procedure AddStyledRange(Var Ranges: TStyledRanges; Start, Count, Style: Integer);
Procedure AppendStyledText(Var Paragraph: TStyledParagraph; Const Value: UTF8String; Style: Integer = 0);
Procedure ResetHeights(Var Index: TStyledHeightIndex; Count: Integer; Estimate: Int64);
Procedure SetHeight(Var Index: TStyledHeightIndex; Item: Integer; Height: Int64);
Function HeightBefore(Const Index: TStyledHeightIndex; Item: Integer): Int64;
Function ItemAtHeight(Const Index: TStyledHeightIndex; Position: Int64): Integer;

Implementation

Uses
  SysUtils, Math, LazUTF8, UnicodeData;

Function StyledInsets(Top, Right, Bottom, Left: Integer): TStyledInsets;
Begin
  Result.Top := Max(0, Top);
  Result.Right := Max(0, Right);
  Result.Bottom := Max(0, Bottom);
  Result.Left := Max(0, Left);
End;

Function StyledInsets(All: Integer): TStyledInsets;
Begin
  Result := StyledInsets(All, All, All, All);
End;

Function StyledInsets(Vertical, Horizontal: Integer): TStyledInsets;
Begin
  Result := StyledInsets(Vertical, Horizontal, Vertical, Horizontal);
End;

Function DefaultStyledBoxStyle: TStyledBoxStyle;
Begin
  Result := Default(TStyledBoxStyle);
  Result.Background := clNone;
  Result.BorderColor := clNone;
End;

Function InsetStyledBox(Const Bounds: TStyledBoxRect; Const Insets: TStyledInsets): TStyledBoxRect;
Begin
  Result.Left := Min(Bounds.Right, Bounds.Left + Max(0, Insets.Left));
  Result.Right := Max(Result.Left, Bounds.Right - Max(0, Insets.Right));
  Result.Top := Min(Bounds.Bottom, Bounds.Top + Max(0, Insets.Top));
  Result.Bottom := Max(Result.Top, Bounds.Bottom - Max(0, Insets.Bottom));
End;

Function GetStyledBoxGeometry(X, Y, Width, Height: Int64; Const Style: TStyledBoxStyle): TStyledBoxGeometry;
Begin
  Result.Outer.Left := X;
  Result.Outer.Top := Y;
  Result.Outer.Right := X + Max(Int64(0), Width);
  Result.Outer.Bottom := Y + Max(Int64(0), Height);
  Result.Border := InsetStyledBox(Result.Outer, Style.Margin);
  Result.Padding := InsetStyledBox(Result.Border, StyledInsets(Style.BorderWidth));
  Result.Content := InsetStyledBox(Result.Padding, Style.Padding);
End;

Function MergeStyledAttributes(Const Original, Changes: TStyledStyle; Attributes: TStyledAttributes): TStyledStyle;
Var
  FontStyle: TFontStyle;
Const
  StyleAttributes: Array[TFontStyle] Of TStyledAttribute = (saBold, saItalic, saUnderline, saStrikeOut);
Begin
  Result := Original;
  If saFontName In Attributes Then Result.FontName := Changes.FontName;
  If saSize In Attributes Then Result.Size := Changes.Size;
  If saForeground In Attributes Then Result.Foreground := Changes.Foreground;
  If saBackground In Attributes Then Result.Background := Changes.Background;
  If saScript In Attributes Then Result.Script := Changes.Script;
  For FontStyle := Low(TFontStyle) To High(TFontStyle) Do
    If StyleAttributes[FontStyle] In Attributes Then
      If FontStyle In Changes.Styles Then Include(Result.Styles, FontStyle) Else Exclude(Result.Styles, FontStyle);
End;

Function DifferentStyledAttributes(Const First, Second: TStyledStyle): TStyledAttributes;
Var
  Attribute: TStyledAttribute;
  Merged: TStyledStyle;
Begin
  Result := [];
  For Attribute := Low(TStyledAttribute) To High(TStyledAttribute) Do
    Begin
      Merged := MergeStyledAttributes(First, Second, [Attribute]);
      If (Merged.FontName <> First.FontName) Or (Merged.Size <> First.Size) Or (Merged.Styles <> First.Styles) Or
        (Merged.Foreground <> First.Foreground) Or (Merged.Background <> First.Background) Or (Merged.Script <> First.Script) Then
        Include(Result, Attribute);
    End;
End;

Function DefaultStyledStyle: TStyledStyle;
Begin
  Result := Default(TStyledStyle);
  Result.Foreground := clDefault;
  Result.Background := clNone;
End;

Function StyledPosition(Paragraph, Offset: Integer; Trailing: Boolean): TStyledPosition;
Begin
  Result.Paragraph := Paragraph;
  Result.Offset := Offset;
  Result.Trailing := Trailing;
End;

Function ComparePositions(Const First, Second: TStyledPosition): Integer;
Begin
  If First.Paragraph < Second.Paragraph Then Exit(-1);
  If First.Paragraph > Second.Paragraph Then Exit(1);
  Result := CompareValue(First.Offset, Second.Offset);
End;

Function NextCodepoint(Const Value: UTF8String; Offset: Integer): Integer;
Begin
  Result := Min(Length(Value), Max(0, Offset) + 1);
  While (Result < Length(Value)) And ((Byte(Value[Result + 1]) And $C0) = $80) Do Inc(Result);
End;

Function PreviousCodepoint(Const Value: UTF8String; Offset: Integer): Integer;
Begin
  Result := Max(0, Min(Length(Value), Offset) - 1);
  While (Result > 0) And ((Byte(Value[Result + 1]) And $C0) = $80) Do Dec(Result);
End;

Function CodepointAt(Const Value: UTF8String; Offset: Integer): Cardinal;
Var
  Bytes: Integer;
Begin
  Result := 0;
  If (Offset >= 0) And (Offset < Length(Value)) Then Result := UTF8CodepointToUnicode(@Value[Offset + 1], Bytes);
End;

Function IsExtend(Codepoint: Cardinal): Boolean;
Var
  Properties: PUC_Prop;
Begin
  If Codepoint < $300 Then Exit(False);
  { Use the explicit BMP/surrogate overloads: FPC 3.3.1's UCS4 Character overload
    incorrectly classifies U+0308 in the installed compiler. }
  If Codepoint <= $FFFF Then Properties := GetProps(Word(Codepoint))
  Else Properties := GetProps(UnicodeChar($D800 + ((Codepoint - $10000) Shr 10)),
    UnicodeChar($DC00 + ((Codepoint - $10000) And $3FF)));
  Result := (Assigned(Properties) And (Properties^.Category In [UGC_NonSpacingMark, UGC_CombiningMark, UGC_EnclosingMark])) Or
    ((Codepoint >= $FE00) And (Codepoint <= $FE0F)) Or ((Codepoint >= $1F3FB) And (Codepoint <= $1F3FF)) Or
    ((Codepoint >= $E0020) And (Codepoint <= $E007F));
End;

Function NextCluster(Const Value: UTF8String; Offset: Integer): Integer;
Var
  First, Following: Cardinal;
Begin
  First := CodepointAt(Value, Offset);
  Result := NextCodepoint(Value, Offset);
  If (First >= $1F1E6) And (First <= $1F1FF) Then
    Begin
      Following := CodepointAt(Value, Result);
      If (Following >= $1F1E6) And (Following <= $1F1FF) Then Result := NextCodepoint(Value, Result);
    End;
  While Result < Length(Value) Do
    Begin
      Following := CodepointAt(Value, Result);
      If IsExtend(Following) Then Result := NextCodepoint(Value, Result)
      Else If Following = $200D Then
        Begin
          Result := NextCodepoint(Value, Result);
          Result := NextCodepoint(Value, Result);
        End
      Else Break;
    End;
End;

Function PreviousCluster(Const Value: UTF8String; Offset: Integer): Integer;
Var
  Candidate, Before: Integer;
Begin
  Candidate := PreviousCodepoint(Value, Offset);
  While (Candidate > 0) And IsExtend(CodepointAt(Value, Candidate)) Do Candidate := PreviousCodepoint(Value, Candidate);
  While Candidate > 0 Do
    Begin
      Before := PreviousCodepoint(Value, Candidate);
      If CodepointAt(Value, Before) <> $200D Then Break;
      Candidate := PreviousCodepoint(Value, Before);
      While (Candidate > 0) And IsExtend(CodepointAt(Value, Candidate)) Do Candidate := PreviousCodepoint(Value, Candidate);
    End;
  { Pair regional indicators from the beginning of their contiguous sequence. }
  Before := Candidate;
  While (Before > 0) And (CodepointAt(Value, Before) >= $1F1E6) And (CodepointAt(Value, Before) <= $1F1FF) Do
    Begin
      Result := PreviousCodepoint(Value, Before);
      If (CodepointAt(Value, Result) < $1F1E6) Or (CodepointAt(Value, Result) > $1F1FF) Then Break;
      Before := Result;
    End;
  Result := Before;
  While NextCluster(Value, Result) < Offset Do Result := NextCluster(Value, Result);
End;

Function IsWordSeparator(Const Value: UTF8String; Offset: Integer): Boolean;
Begin
  Result := (Offset < 0) Or (Offset >= Length(Value));
  If Not Result Then Result := Value[Offset + 1] In [' ', #9, '.', ',', ';', ':', '!', '?', '(', ')', '[', ']', '{', '}'];
End;

Function NormaliseStyledText(Const Value: UTF8String): UTF8String;
Begin
  Result := StringReplace(Value, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #0, '', [rfReplaceAll]);
  UniqueString(Result);
  If Result <> '' Then UTF8FixBroken(PChar(Result));
End;

Procedure AddStyledRange(Var Ranges: TStyledRanges; Start, Count, Style: Integer);
Var
  Index: Integer;
Begin
  If Count <= 0 Then Exit;
  Index := High(Ranges);
  If (Index >= 0) And (Ranges[Index].Style = Style) And (Ranges[Index].Start + Ranges[Index].Count = Start) Then
    Inc(Ranges[Index].Count, Count)
  Else
    Begin
      SetLength(Ranges, Index + 2);
      Ranges[Index + 1].Start := Start;
      Ranges[Index + 1].Count := Count;
      Ranges[Index + 1].Style := Style;
    End;
End;

Procedure AppendStyledText(Var Paragraph: TStyledParagraph; Const Value: UTF8String; Style: Integer);
Begin
  AddStyledRange(Paragraph.Ranges, Length(Paragraph.Text), Length(Value), Style);
  Paragraph.Text += Value;
  Inc(Paragraph.Revision);
End;

Procedure ResetHeights(Var Index: TStyledHeightIndex; Count: Integer; Estimate: Int64);
Var
  Item: Integer;
Begin
  SetLength(Index.Values, Count);
  SetLength(Index.Sums, Count + 1);
  Index.Sums[0] := 0;
  For Item := 1 To Count Do
    Begin
      Index.Values[Item - 1] := Estimate;
      Index.Sums[Item] := (Item And -Item) * Estimate;
    End;
End;

Procedure SetHeight(Var Index: TStyledHeightIndex; Item: Integer; Height: Int64);
Var
  Delta: Int64;
Begin
  Delta := Height - Index.Values[Item];
  Index.Values[Item] := Height;
  Inc(Item);
  While Item < Length(Index.Sums) Do
    Begin
      Inc(Index.Sums[Item], Delta);
      Inc(Item, Item And -Item);
    End;
End;

Function HeightBefore(Const Index: TStyledHeightIndex; Item: Integer): Int64;
Begin
  Result := 0;
  Item := Min(Item, Length(Index.Values));
  While Item > 0 Do
    Begin
      Inc(Result, Index.Sums[Item]);
      Dec(Item, Item And -Item);
    End;
End;

Function ItemAtHeight(Const Index: TStyledHeightIndex; Position: Int64): Integer;
Var
  Step, Candidate: Integer;
Begin
  Result := 0;
  Step := 1;
  While Step < Length(Index.Values) Do Step := Step Shl 1;
  While Step > 0 Do
    Begin
      Candidate := Result + Step;
      If (Candidate < Length(Index.Sums)) And (Index.Sums[Candidate] <= Position) Then
        Begin
          Dec(Position, Index.Sums[Candidate]);
          Result := Candidate;
        End;
      Step := Step Shr 1;
    End;
  Result := Min(Result, Max(0, Length(Index.Values) - 1));
End;

End.
