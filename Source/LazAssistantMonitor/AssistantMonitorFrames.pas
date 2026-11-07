Unit AssistantMonitorFrames;

{ LAM1 frame layout for the monitor catalogue (c) 2026 Michell Computing.

  The payload buffer is allocated only after the length field passes the cap.
  Length uses htonl and ntohl. JSON is fpjson. Image bytes use FCL base64. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorFrameMagic = 'LAM1';
  MonitorFrameVersion = 1;
  MonitorFrameHeaderSize = 12;
  MonitorMaxPayloadBytes = 262144;

Type
  TMonitorFrameStatus = (
    mfsOk,
    mfsNeedMore,
    mfsBadMagic,
    mfsBadVersion,
    mfsShort,
    mfsTooLarge,
    mfsBadUtf8,
    mfsBadJson
  );

  TMonitorFrame = Record
    Version: Byte;
    Flags: Byte;
    Json: String;
  End;

Function TryEncodeMonitorFrame(Const Json: String; Out Bytes: RawByteString; Out Status: TMonitorFrameStatus): Boolean;
{ Header and payload bytes only. No UTF-8 scan and no JSON parse. False when Json is empty or over the cap.
  Callers that did not build the object themselves use TryEncodeMonitorFrame. }
Function EncodeMonitorFrameBytes(Const Json: String; Out Bytes: RawByteString): Boolean;
{ Inbound frames check byte length and UTF-8. The envelope decoder validates JSON and its object shape. }
Function TryDecodeMonitorFrame(Const Bytes: RawByteString; Out Frame: TMonitorFrame; Out Status: TMonitorFrameStatus): Boolean;
{ Header only. mfsTooLarge means close the socket and do not read PayloadLen body bytes.
  The payload buffer is not allocated. }
Function TryInspectMonitorFrameHeader(Const Bytes: RawByteString; Out PayloadLen: Cardinal; Out Status: TMonitorFrameStatus): Boolean;
{ Streaming read. A length above the cap returns mfsTooLarge before the body is kept. }
Function TryConsumeMonitorFrame(Var Pending: RawByteString; Out Frame: TMonitorFrame; Out Status: TMonitorFrameStatus): Boolean; Overload;
{ Zero-based read offset; advances only on success and leaves Pending unchanged. Compact once after draining. }
Function TryConsumeMonitorFrame(Const Pending: RawByteString; Var ReadOffset: Integer; Out Frame: TMonitorFrame;
  Out Status: TMonitorFrameStatus): Boolean; Overload;
Function EncodeMonitorImageBytes(Const Bytes: RawByteString): String;
Function DecodeMonitorImageBytes(Const Encoded: String): RawByteString;
{ Byte count of the longest prefix of Text, at most Limit, that does not end inside a UTF-8 character.
  Copy(Text, 1, Result) keeps valid UTF-8 valid. When the first character alone is longer than Limit, that
  whole character is kept, so a caller that cuts in a loop always moves forward. Zero when Limit <= 0. }
Function MonitorUtf8CutLength(Const Text: RawByteString; Limit: Integer): Integer;

{$IFDEF MONITOR_COUNT_PARSES}
{ Counts JSON gates in the frame encoder and shared codec. Tests pass -dMONITOR_COUNT_PARSES. }
Var
  MonitorJsonParseCount: Integer;
Procedure MonitorNoteJsonParse;
{$ENDIF}

Implementation

Uses
  sockets, base64, fpjson, jsonparser;

{$IFDEF MONITOR_COUNT_PARSES}
Procedure MonitorNoteJsonParse;
Begin
  Inc(MonitorJsonParseCount);
End;
{$ENDIF}

{ Shared by the validating encoder and the trusted encoder. Length is already capped. }
Function WriteMonitorFrameBytes(Const Payload: RawByteString; Out Bytes: RawByteString): Boolean;
Var
  NetLen: Cardinal;
Begin
  Result := False;
  Bytes := '';
  If Length(Payload) > MonitorMaxPayloadBytes Then
    Exit;
  SetLength(Bytes, MonitorFrameHeaderSize + Length(Payload));
  Bytes[1] := 'L';
  Bytes[2] := 'A';
  Bytes[3] := 'M';
  Bytes[4] := '1';
  Bytes[5] := Chr(MonitorFrameVersion);
  Bytes[6] := Chr(0);
  Bytes[7] := Chr(0);
  Bytes[8] := Chr(0);
  NetLen := htonl(Cardinal(Length(Payload)));
  { Move is the read of NetLen. A typed store keeps the htonl result visible to the compiler. }
  PCardinal(@Bytes[9])^ := NetLen;
  If Length(Payload) > 0 Then
    Move(Payload[1], Bytes[MonitorFrameHeaderSize + 1], Length(Payload));
  Result := True;
End;

Function EncodeMonitorFrameBytes(Const Json: String; Out Bytes: RawByteString): Boolean;
Begin
  Bytes := '';
  Result := (Json <> '') And WriteMonitorFrameBytes(Json, Bytes);
End;

Function IsStrictUtf8(Const Bytes: RawByteString): Boolean;
Var
  Index, Len, Need, Second: Integer;
  Lead: Byte;
Begin
  Result := False;
  Index := 1;
  Len := Length(Bytes);
  While Index <= Len Do
    Begin
      Lead := Ord(Bytes[Index]);
      If Lead < $80 Then
        Need := 1
      Else If (Lead >= $C2) And (Lead <= $DF) Then
        Need := 2
      Else If (Lead >= $E0) And (Lead <= $EF) Then
        Need := 3
      Else If (Lead >= $F0) And (Lead <= $F4) Then
        Need := 4
      Else
        Exit;
      If Index + Need - 1 > Len Then
        Exit;
      If Need > 1 Then
        Begin
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
        End;
      If Need > 2 Then
        If (Ord(Bytes[Index + 2]) < $80) Or (Ord(Bytes[Index + 2]) > $BF) Then
          Exit;
      If Need > 3 Then
        If (Ord(Bytes[Index + 3]) < $80) Or (Ord(Bytes[Index + 3]) > $BF) Then
          Exit;
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

Function ReadNetworkLength(Const Bytes: RawByteString): Cardinal;
Var
  Net: Cardinal;
Begin
  Net := 0;
  Move(Bytes[9], Net, 4);
  Result := ntohl(Net);
End;

Function TryInspectMonitorFrameHeader(Const Bytes: RawByteString; Out PayloadLen: Cardinal; Out Status: TMonitorFrameStatus): Boolean;
Begin
  Result := False;
  PayloadLen := 0;
  Status := mfsShort;
  If Length(Bytes) < MonitorFrameHeaderSize Then
    Exit;
  If Copy(Bytes, 1, 4) <> MonitorFrameMagic Then
    Begin
      Status := mfsBadMagic;
      Exit;
    End;
  If Ord(Bytes[5]) <> MonitorFrameVersion Then
    Begin
      Status := mfsBadVersion;
      Exit;
    End;
  { Length is accepted before any payload buffer is allocated. }
  PayloadLen := ReadNetworkLength(Bytes);
  If PayloadLen > MonitorMaxPayloadBytes Then
    Begin
      Status := mfsTooLarge;
      Exit;
    End;
  Result := True;
  Status := mfsOk;
End;

Function FinishPayload(Const Bytes: RawByteString; PayloadLen: Cardinal; Out Frame: TMonitorFrame;
  Out Status: TMonitorFrameStatus; ReadOffset: Integer = 0): Boolean;
Var
  Raw: RawByteString;
Begin
  Result := False;
  Frame.Version := MonitorFrameVersion;
  Frame.Flags := Ord(Bytes[ReadOffset + 6]);
  Frame.Json := '';
  Status := mfsBadJson;
  Raw := '';
  SetLength(Raw, PayloadLen);
  If PayloadLen > 0 Then
    Move(Bytes[ReadOffset + MonitorFrameHeaderSize + 1], Raw[1], PayloadLen);
  If Not IsStrictUtf8(Raw) Then
    Begin
      Status := mfsBadUtf8;
      Exit;
    End;
  { The envelope decoder is the JSON gate. Mark the single payload copy as UTF-8. }
  SetCodePage(Raw, CP_UTF8, False);
  Frame.Json := Raw;
  Status := mfsOk;
  Result := True;
End;

Function PayloadIsJsonObject(Const Json: RawByteString): Boolean;
Var
  Data: TJSONData;
  Marked: RawByteString;
Begin
  Result := False;
  Data := Nil;
  Marked := Json;
  SetCodePage(Marked, CP_UTF8, False);
  Try
    Try
      If Marked = '' Then
        Exit;
      {$IFDEF MONITOR_COUNT_PARSES}
      MonitorNoteJsonParse;
      {$ENDIF}
      Data := GetJSON(Marked);
    Except
      Exit;
    End;
    Result := Data Is TJSONObject;
  Finally
    Data.Free;
  End;
End;

Function TryEncodeMonitorFrame(Const Json: String; Out Bytes: RawByteString; Out Status: TMonitorFrameStatus): Boolean;
Var
  Payload: RawByteString;
Begin
  Result := False;
  Bytes := '';
  Status := mfsTooLarge;
  If Length(Json) > MonitorMaxPayloadBytes Then
    Exit;
  Payload := Json;
  If Not IsStrictUtf8(Payload) Then
    Begin
      Status := mfsBadUtf8;
      Exit;
    End;
  If Not PayloadIsJsonObject(Payload) Then
    Begin
      Status := mfsBadJson;
      Exit;
    End;
  Result := WriteMonitorFrameBytes(Payload, Bytes);
  If Result Then
    Status := mfsOk;
End;

Function TryDecodeMonitorFrame(Const Bytes: RawByteString; Out Frame: TMonitorFrame; Out Status: TMonitorFrameStatus): Boolean;
Var
  PayloadLen: Cardinal;
Begin
  Result := False;
  Frame.Version := 0;
  Frame.Flags := 0;
  Frame.Json := '';
  If Not TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status) Then
    Begin
      If Length(Bytes) < MonitorFrameHeaderSize Then
        Status := mfsShort;
      Exit;
    End;
  If Length(Bytes) < MonitorFrameHeaderSize + Integer(PayloadLen) Then
    Begin
      Status := mfsShort;
      Exit;
    End;
  Result := FinishPayload(Bytes, PayloadLen, Frame, Status);
End;

Function TryConsumeMonitorFrame(Var Pending: RawByteString; Out Frame: TMonitorFrame; Out Status: TMonitorFrameStatus): Boolean; Overload;
Var
  ReadOffset: Integer;
Begin
  ReadOffset := 0;
  Result := TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status);
  If Result Then
    Delete(Pending, 1, ReadOffset);
End;

Function TryConsumeMonitorFrame(Const Pending: RawByteString; Var ReadOffset: Integer; Out Frame: TMonitorFrame;
  Out Status: TMonitorFrameStatus): Boolean;
Var
  PayloadLen: Cardinal;
  Have: Integer;
Begin
  Result := False;
  Frame.Version := 0;
  Frame.Flags := 0;
  Frame.Json := '';
  If (ReadOffset < 0) Or (ReadOffset > Length(Pending)) Or
    (Length(Pending) - ReadOffset < MonitorFrameHeaderSize) Then
    Begin
      Status := mfsNeedMore;
      Exit;
    End;
  If Not TryInspectMonitorFrameHeader(Copy(Pending, ReadOffset + 1, MonitorFrameHeaderSize), PayloadLen, Status) Then
    Exit;
  Have := MonitorFrameHeaderSize + Integer(PayloadLen);
  If Length(Pending) - ReadOffset < Have Then
    Begin
      Status := mfsNeedMore;
      Exit;
    End;
  Result := FinishPayload(Pending, PayloadLen, Frame, Status, ReadOffset);
  If Result Then
    Inc(ReadOffset, Have);
End;

Function EncodeMonitorImageBytes(Const Bytes: RawByteString): String;
Begin
  Result := EncodeStringBase64(Bytes);
End;

Function DecodeMonitorImageBytes(Const Encoded: String): RawByteString;
Begin
  Result := DecodeStringBase64(Encoded);
End;

End.
