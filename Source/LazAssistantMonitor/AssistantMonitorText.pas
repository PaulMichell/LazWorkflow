Unit AssistantMonitorText;

{ Shared monitor byte and text helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Function Fnv1a64(Const Text: RawByteString): String;
Function MonitorBoolean(Condition: Boolean): String;
Function MonitorBlockState(Running, Ok: Boolean): String;
Function IsStrictUtf8(Const Bytes: RawByteString): Boolean;
Function Utf8Need(Lead: Byte): Integer;
Function SequenceOk(Const Bytes: RawByteString; Index, Need: Integer): Boolean;
Function MonitorUtf8Step(Const Text: String; Index: Integer): Integer;
Function MonitorUtf8CutLength(Const Text: RawByteString; Limit: Integer): Integer;
Function EscapedByteLen(C: Char): Integer;
{ Byte-preserving JSON escaping, also used for bounded chunk payloads. }
Function EscapeChunkData(Const Text: String): String;

Implementation

Uses
  SysUtils;

Function Fnv1a64(Const Text: RawByteString): String;
Var
  Hash: UInt64;
  Index: Integer;
Begin
  {$PUSH}{$Q-}{$R-}
  Hash := UInt64(14695981039346656037);
  For Index := 1 To Length(Text) Do
    Begin
      Hash := Hash Xor Ord(Text[Index]);
      Hash := Hash * UInt64(1099511628211);
    End;
  {$POP}
  Result := LowerCase(HexStr(Hash, 16));
End;

Function MonitorBoolean(Condition: Boolean): String;
Begin
  If Condition Then
    Result := 'true'
  Else
    Result := 'false';
End;

Function MonitorBlockState(Running, Ok: Boolean): String;
Begin
  If Running Then
    Result := 'running'
  Else If Ok Then
    Result := 'ok'
  Else
    Result := 'failed';
End;

Function Utf8Need(Lead: Byte): Integer;
Begin
  If Lead < $80 Then
    Result := 1
  Else If (Lead >= $C2) And (Lead <= $DF) Then
    Result := 2
  Else If (Lead >= $E0) And (Lead <= $EF) Then
    Result := 3
  Else If (Lead >= $F0) And (Lead <= $F4) Then
    Result := 4
  Else
    Result := 0;
End;

Function SequenceOk(Const Bytes: RawByteString; Index, Need: Integer): Boolean;
Var
  Lead, Second: Byte;
Begin
  Result := False;
  If (Index < 1) Or (Need < 1) Or (Need > 4) Or (Index + Need - 1 > Length(Bytes)) Then
    Exit;
  Lead := Ord(Bytes[Index]);
  If Need = 1 Then
    Exit(True);
  Second := Ord(Bytes[Index + 1]);
  If (Second < $80) Or (Second > $BF) Then
    Exit;
  If (Lead = $E0) And (Second < $A0) Then
    Exit;
  If (Lead = $ED) And (Second > $9F) Then
    Exit;
  If (Lead = $F0) And (Second < $90) Then
    Exit;
  If (Lead = $F4) And (Second > $8F) Then
    Exit;
  If (Need > 2) And ((Ord(Bytes[Index + 2]) < $80) Or (Ord(Bytes[Index + 2]) > $BF)) Then
    Exit;
  If (Need > 3) And ((Ord(Bytes[Index + 3]) < $80) Or (Ord(Bytes[Index + 3]) > $BF)) Then
    Exit;
  Result := True;
End;

Function IsStrictUtf8(Const Bytes: RawByteString): Boolean;
Var
  Index, Need: Integer;
Begin
  Index := 1;
  While Index <= Length(Bytes) Do
    Begin
      Need := Utf8Need(Ord(Bytes[Index]));
      If Not SequenceOk(Bytes, Index, Need) Then
        Exit(False);
      Inc(Index, Need);
    End;
  Result := True;
End;

Function IsUtf8Continuation(Value: Char): Boolean;
Begin
  Result := (Ord(Value) And $C0) = $80;
End;

Function MonitorUtf8CutLength(Const Text: RawByteString; Limit: Integer): Integer;
Var
  Back: Integer;
Begin
  If Limit <= 0 Then
    Exit(0);
  If Length(Text) <= Limit Then
    Exit(Length(Text));
  { Text[Result + 1] is the first byte left out. A continuation byte there means the cut is inside a character.
    A UTF-8 character has at most three continuation bytes; more than that is not UTF-8, so cut at Limit. }
  Result := Limit;
  Back := 0;
  While (Result > 0) And (Back < 3) And IsUtf8Continuation(Text[Result + 1]) Do
    Begin
      Dec(Result);
      Inc(Back);
    End;
  If (Result > 0) And IsUtf8Continuation(Text[Result + 1]) Then
    Exit(Limit);
  If Result = 0 Then
    Begin
      Result := 1;
      While (Result < Length(Text)) And (Result < 4) And IsUtf8Continuation(Text[Result + 1]) Do
        Inc(Result);
    End;
End;

Function MonitorUtf8Step(Const Text: String; Index: Integer): Integer;
Var
  Lead, Need, Follow: Integer;
Begin
  Result := 1;
  If (Index < 1) Or (Index > Length(Text)) Then
    Exit(0);
  Lead := Ord(Text[Index]);
  If Lead < $80 Then
    Exit;
  If (Lead And $E0) = $C0 Then
    Need := 2
  Else If (Lead And $F0) = $E0 Then
    Need := 3
  Else If (Lead And $F8) = $F0 Then
    Need := 4
  Else
    Exit;
  Follow := 1;
  While (Index + Follow <= Length(Text)) And (Follow < Need) And ((Ord(Text[Index + Follow]) And $C0) = $80) Do
    Inc(Follow);
  If Follow = Need Then
    Result := Need;
End;


Function EscapedByteLen(C: Char): Integer;
Begin
  Case C Of
    '"', '\', #8, #9, #10, #12, #13: Result := 2;
  Else
    If Ord(C) < 32 Then
      Result := 6
    Else
      Result := 1;
  End;
End;

Function EscapeChunkData(Const Text: String): String;
Const
  HexDigits = '0123456789ABCDEF';
Var
  Index, OutLen, At, Code: Integer;
  C: Char;
Begin
  OutLen := 0;
  For Index := 1 To Length(Text) Do
    Inc(OutLen, EscapedByteLen(Text[Index]));
  SetLength(Result, OutLen);
  At := 1;
  For Index := 1 To Length(Text) Do
    Begin
      C := Text[Index];
      Case C Of
        '"':
          Begin
            Result[At] := '\';
            Result[At + 1] := '"';
            Inc(At, 2);
          End;
        '\':
          Begin
            Result[At] := '\';
            Result[At + 1] := '\';
            Inc(At, 2);
          End;
        #8:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'b';
            Inc(At, 2);
          End;
        #9:
          Begin
            Result[At] := '\';
            Result[At + 1] := 't';
            Inc(At, 2);
          End;
        #10:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'n';
            Inc(At, 2);
          End;
        #12:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'f';
            Inc(At, 2);
          End;
        #13:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'r';
            Inc(At, 2);
          End;
      Else
        If Ord(C) < 32 Then
          Begin
            Code := Ord(C);
            Result[At] := '\';
            Result[At + 1] := 'u';
            Result[At + 2] := '0';
            Result[At + 3] := '0';
            Result[At + 4] := HexDigits[(Code Div 16) + 1];
            Result[At + 5] := HexDigits[(Code Mod 16) + 1];
            Inc(At, 6);
          End
        Else
          Begin
            Result[At] := C;
            Inc(At);
          End;
      End;
    End;
End;

End.
