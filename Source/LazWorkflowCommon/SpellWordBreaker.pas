Unit SpellWordBreaker;

{ UTF-8 prose word iterator for TSpellMemo (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TSpellToken = Record
    ByteStart: Integer;
    ByteLength: Integer;
    Text: String;
    IsProse: Boolean;
  End;
  TSpellTokenArray = Array Of TSpellToken;

  TSpellWordBreaker = Class
  Private
    FText: String;
    FPos: Integer;
  Public
    Procedure SetText(Const Value: String);
    Function NextWord(Out Token: TSpellToken): Boolean;
  End;

Function SpellBreakWords(Const Value: String): TSpellTokenArray;
Function SpellTokenAt(Const Value: String; BytePos: Integer; Out Token: TSpellToken): Boolean;
Function SpellRawTokenAt(Const Value: String; BytePos: Integer; Out Token: TSpellToken): Boolean;
Function SpellWordIsComplete(Const Value: String; Const Token: TSpellToken; CaretByte: Integer): Boolean;

Implementation

Uses
  Character, LazUTF8;

Function IsApostrophe(CodePoint: Cardinal): Boolean;
Begin
  Result := (CodePoint = Ord('''')) Or (CodePoint = $2019) Or (CodePoint = $02BC);
End;

Function IsTokenChar(CodePoint: Cardinal): Boolean;
Begin
  Result := TCharacter.IsLetter(UnicodeChar(CodePoint)) Or TCharacter.IsDigit(UnicodeChar(CodePoint)) Or
    (CodePoint = Ord('_')) Or IsApostrophe(CodePoint);
End;

Function TokenIsProse(Const TokenText: String): Boolean;
Var
  Index, CodeLen: Integer;
  CodePoint: Cardinal;
  HasLetter, HasDigit, HasUnderscore: Boolean;
Begin
  Result := False;
  HasLetter := False;
  HasDigit := False;
  HasUnderscore := False;
  Index := 1;
  While Index <= Length(TokenText) Do
    Begin
      CodePoint := UTF8CodepointToUnicode(@TokenText[Index], CodeLen);
      If CodeLen <= 0 Then
        Break;
      If CodePoint = Ord('_') Then
        HasUnderscore := True
      Else If TCharacter.IsDigit(UnicodeChar(CodePoint)) Then
        HasDigit := True
      Else If TCharacter.IsLetter(UnicodeChar(CodePoint)) Then
        HasLetter := True;
      Inc(Index, CodeLen);
    End;
  Result := HasLetter And (Not HasDigit) And (Not HasUnderscore) And (UTF8Length(TokenText) >= 2);
End;

Function StripEdgeApostrophes(Const TokenText: String; Var ByteStart, ByteLength: Integer): String;
Var
  FirstLen, LastLen: Integer;
  FirstCP, LastCP: Cardinal;
  LastStart: Integer;
Begin
  Result := TokenText;
  While Result <> '' Do
    Begin
      FirstCP := UTF8CodepointToUnicode(@Result[1], FirstLen);
      If (FirstLen > 0) And IsApostrophe(FirstCP) Then
        Begin
          Inc(ByteStart, FirstLen);
          Dec(ByteLength, FirstLen);
          Delete(Result, 1, FirstLen);
        End
      Else
        Break;
    End;
  While Result <> '' Do
    Begin
      LastStart := UTF8FindNearestCharStart(PChar(Result), Length(Result), Length(Result) - 1);
      If LastStart < 0 Then
        Break;
      LastCP := UTF8CodepointToUnicode(@Result[LastStart + 1], LastLen);
      If (LastLen > 0) And IsApostrophe(LastCP) Then
        Begin
          Dec(ByteLength, LastLen);
          SetLength(Result, Length(Result) - LastLen);
        End
      Else
        Break;
    End;
End;

Procedure TSpellWordBreaker.SetText(Const Value: String);
Begin
  FText := Value;
  FPos := 1;
End;

Function TSpellWordBreaker.NextWord(Out Token: TSpellToken): Boolean;
Var
  CodePoint: Cardinal;
  CodeLen: Integer;
  StartPos: Integer;
Begin
  Result := False;
  Token.ByteStart := 0;
  Token.ByteLength := 0;
  Token.Text := '';
  Token.IsProse := False;
  While FPos <= Length(FText) Do
    Begin
      CodePoint := UTF8CodepointToUnicode(@FText[FPos], CodeLen);
      If CodeLen <= 0 Then
        Exit;
      If IsTokenChar(CodePoint) Then
        Break;
      Inc(FPos, CodeLen);
    End;
  If FPos > Length(FText) Then
    Exit;
  StartPos := FPos;
  While FPos <= Length(FText) Do
    Begin
      CodePoint := UTF8CodepointToUnicode(@FText[FPos], CodeLen);
      If (CodeLen <= 0) Or (Not IsTokenChar(CodePoint)) Then
        Break;
      Inc(FPos, CodeLen);
    End;
  Token.ByteStart := StartPos;
  Token.ByteLength := FPos - StartPos;
  Token.Text := Copy(FText, Token.ByteStart, Token.ByteLength);
  Token.Text := StripEdgeApostrophes(Token.Text, Token.ByteStart, Token.ByteLength);
  Token.IsProse := TokenIsProse(Token.Text);
  If Token.IsProse Then
    Begin
      If (Token.ByteStart > 1) And (FText[Token.ByteStart - 1] In ['/', '\', '.']) Then
        Token.IsProse := False;
      If (Token.ByteStart + Token.ByteLength <= Length(FText)) And
        (FText[Token.ByteStart + Token.ByteLength] In ['/', '\']) Then
        Token.IsProse := False;
    End;
  Result := Token.ByteLength > 0;
End;

Function SpellBreakWords(Const Value: String): TSpellTokenArray;
Var
  Breaker: TSpellWordBreaker;
  Token: TSpellToken;
  Count: Integer;
Begin
  Result := Nil;
  SetLength(Result, 0);
  Breaker := TSpellWordBreaker.Create;
  Try
    Breaker.SetText(Value);
    Count := 0;
    While Breaker.NextWord(Token) Do
      Begin
        If Not Token.IsProse Then
          Continue;
        If Count >= Length(Result) Then
          SetLength(Result, Count + 16);
        Result[Count] := Token;
        Inc(Count);
      End;
    SetLength(Result, Count);
  Finally
    Breaker.Free;
  End;
End;

Function SpellWordIsComplete(Const Value: String; Const Token: TSpellToken; CaretByte: Integer): Boolean;
Var
  After, CodeLen: Integer;
  CodePoint: Cardinal;
Begin
  Result := True;
  After := Token.ByteStart + Token.ByteLength;
  If (After >= 1) And (After <= Length(Value)) Then
    Begin
      CodePoint := UTF8CodepointToUnicode(@Value[After], CodeLen);
      If (CodeLen > 0) And (Not IsTokenChar(CodePoint)) Then
        Exit;
    End;
  { No terminator yet: still being typed if the caret is in or just after the word. }
  Result := (CaretByte < Token.ByteStart) Or (CaretByte > After);
End;

Function SpellTokenAt(Const Value: String; BytePos: Integer; Out Token: TSpellToken): Boolean;
Var
  Tokens: TSpellTokenArray;
  Index: Integer;
Begin
  Result := False;
  Token.ByteStart := 0;
  Token.ByteLength := 0;
  Token.Text := '';
  Token.IsProse := False;
  If BytePos < 1 Then
    BytePos := 1;
  If BytePos > Length(Value) + 1 Then
    BytePos := Length(Value) + 1;
  Tokens := SpellBreakWords(Value);
  For Index := 0 To High(Tokens) Do
    If (BytePos >= Tokens[Index].ByteStart) And (BytePos <= Tokens[Index].ByteStart + Tokens[Index].ByteLength) Then
      Begin
        Token := Tokens[Index];
        Result := True;
        Exit;
      End;
End;

Function SpellRawTokenAt(Const Value: String; BytePos: Integer; Out Token: TSpellToken): Boolean;
Var
  Breaker: TSpellWordBreaker;
  Found: TSpellToken;
Begin
  Result := False;
  Token.ByteStart := 0;
  Token.ByteLength := 0;
  Token.Text := '';
  Token.IsProse := False;
  If BytePos < 1 Then
    BytePos := 1;
  If BytePos > Length(Value) + 1 Then
    BytePos := Length(Value) + 1;
  Breaker := TSpellWordBreaker.Create;
  Try
    Breaker.SetText(Value);
    While Breaker.NextWord(Found) Do
      If (BytePos >= Found.ByteStart) And (BytePos <= Found.ByteStart + Found.ByteLength) Then
        Begin
          Token := Found;
          Result := True;
          Exit;
        End;
  Finally
    Breaker.Free;
  End;
End;

End.
