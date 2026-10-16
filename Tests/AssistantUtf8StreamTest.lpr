Program AssistantUtf8StreamTest;

{ A socket read that splits a UTF-8 character must not be concatenated.
  That concatenation is the streaming access violation on Linux. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, AssistantHttps;

Procedure Check(Const Name: String; Ok: Boolean);
Begin
  If Not Ok Then
    Begin
      WriteLn(StdErr, 'FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok ', Name);
End;

Function Push(Var Carry: RawByteString; Const Bytes: RawByteString): String;
Var
  Pending: RawByteString;
Begin
  SetLength(Pending, Length(Carry) + Length(Bytes));
  If Length(Carry) > 0 Then
    Move(Carry[1], Pending[1], Length(Carry));
  If Length(Bytes) > 0 Then
    Move(Bytes[1], Pending[Length(Carry) + 1], Length(Bytes));
  Result := CompleteUtf8Chunk(Pending, Carry);
End;

Function Slice(Const Bytes: RawByteString; StartAt, Count: Integer): RawByteString;
Begin
  SetLength(Result, Count);
  If Count > 0 Then
    Move(Bytes[StartAt], Result[1], Count);
End;

Procedure CheckSplit(Const Name: String; Const Bytes: RawByteString);
Var
  Carry: RawByteString;
  Expected, Joined: String;
  Offset: Integer;
Begin
  Expected := CompleteUtf8Chunk(Bytes, Carry);
  Check(Name + ' is already complete', Carry = '');
  For Offset := 1 To Length(Bytes) - 1 Do
    Begin
      Carry := '';
      Joined := Push(Carry, Slice(Bytes, 1, Offset));
      Joined := Joined + Push(Carry, Slice(Bytes, Offset + 1, Length(Bytes) - Offset));
      Check(Name + ' split at ' + IntToStr(Offset), (Joined = Expected) And (Carry = ''));
    End;
End;

Var
  Carry: RawByteString;
  Joined: String;
  Apostrophe, Emoji, Mixed: RawByteString;
Begin
  Apostrophe := #$E2#$80#$99;
  Emoji := #$F0#$9F#$98#$80;
  Mixed := 'I' + Apostrophe + 'll check' + Emoji + #10 + 'yes';
  CheckSplit('apostrophe', Apostrophe);
  CheckSplit('emoji', Emoji);
  CheckSplit('mixed reply', Mixed);

  Carry := '';
  Joined := Push(Carry, #$F0);
  Check('lead byte is held', (Joined = '') And (Carry = #$F0));
  Joined := Joined + Push(Carry, #$9F#$98);
  Check('three of four bytes stay held', (Joined = '') And (Length(Carry) = 3));
  Joined := Joined + Push(Carry, #$80 + ' tail');
  Check('four-byte character survives three reads', (Joined = CompleteUtf8Chunk(Emoji + ' tail', Carry)) And (Carry = ''));

  WriteLn('AssistantUtf8StreamTest passed');
End.
