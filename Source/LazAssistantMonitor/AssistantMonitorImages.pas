Unit AssistantMonitorImages;

{ Image fetch codecs and the bulk chunk packer. image_get and image_data stay on the live path.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantMonitorCodec;

Function ImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Function ExpectedBase64Chars(ByteCount: Integer): Integer;
Function FramedBase64(Const Raw: RawByteString): String;
Function TryBuildImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Function DecodeImageData(Const PayloadJson: String; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Function EncodeImageUnavailable(Const Id, ImageId, Reason: String): String;
Function DecodeImageUnavailable(Const PayloadJson: String; Out Image: TMonitorImageUnavailable): Boolean;
Function EncodeImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Function DecodeImageGet(Const PayloadJson: String; Out Image: TMonitorImageGet): Boolean;
Function TryEncodeImageData(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Missing, Refused: Boolean; Out Messages: TStringArray; Out UnavailableReason: String): Boolean;
Function EscapedByteLen(C: Char): Integer;
Function EscapeChunkData(Const Text: String): String;
Function ChunkFrame(Const Id, ItemId, ItemType, Data: String; Part, PartCount: Integer): String;
Function Utf8UnitLen(Const Text: String; Index: Integer): Integer;
Function ChunkSourceLen(Const Item: String; Start, DataBudget: Integer): Integer;
Function PackImageBulkItem(Const ItemId, ItemType, PayloadJson: String; Out Frames: TStringArray): Boolean;
Function TryPackImage(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer; Const Bytes: TBytes;
  Missing, Refused: Boolean; Out Frames: TStringArray; Out UnavailableReason: String): Boolean;

Implementation

Uses
  AssistantMonitorFrames, AssistantMonitorOutbox;

Function ImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Begin
  Reason := '';
  Result := True;
  If Missing Then
    Reason := 'missing'
  Else If Refused Then
    Reason := 'refused'
  Else If DecodedBytes > MonitorMaxImageFetchBytes Then
    Reason := 'too_large'
  Else
    Result := False;
End;

Function ExpectedBase64Chars(ByteCount: Integer): Integer;
Begin
  Result := ((ByteCount + 2) Div 3) * 4;
End;

Function FramedBase64(Const Raw: RawByteString): String;
Begin
  Result := EncodeMonitorImageBytes(Raw);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
End;

Function TryBuildImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Var
  Total, Offset, Take, Count, Index: Integer;
  Raw: RawByteString;
  Encoded: String;
  Part: TJSONObject;
Begin
  Result := False;
  Parts := Nil;
  Reason := '';
  Raw := '';
  Total := Length(Bytes);
  If ImageFetchBlocked(False, False, Total, Reason) Then
    Exit;
  If Total = 0 Then
    Count := 1
  Else
    Count := (Total + MonitorMaxImagePartBytes - 1) Div MonitorMaxImagePartBytes;
  Parts := TJSONArray.Create;
  Offset := 0;
  For Index := 0 To Count - 1 Do
    Begin
      Take := MonitorMaxImagePartBytes;
      If Offset + Take > Total Then
        Take := Total - Offset;
      SetLength(Raw, Take);
      If Take > 0 Then
        Move(Bytes[Offset], Raw[1], Take);
      Encoded := FramedBase64(Raw);
      If Length(Encoded) <> ExpectedBase64Chars(Take) Then
        Begin
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      If Length(Encoded) > MonitorImagePartBase64Chars Then
        Begin
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      Part := TJSONObject.Create;
      Part.Add('image_id', ImageId);
      Part.Add('mime', Mime);
      Part.Add('width', Width);
      Part.Add('height', Height);
      Part.Add('part', Index + 1);
      Part.Add('part_count', Count);
      Part.Add('revision', Revision);
      Part.Add('bytes_base64', Encoded);
      If Length(Part.AsJSON) + MonitorImageEnvelopeBytes > MonitorMaxPayloadBytes Then
        Begin
          Part.Free;
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      Parts.Add(Part);
      Inc(Offset, Take);
    End;
  Result := True;
End;

Function DecodeImageData(Const PayloadJson: String; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Raw: RawByteString;
Begin
  Result := False;
  DecodedBytes := 0;
  Image.ImageId := '';
  Image.Mime := '';
  Image.Width := 0;
  Image.Height := 0;
  Image.Part := 0;
  Image.PartCount := 0;
  Image.Revision := 0;
  Image.BytesBase64 := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadMonitorString(Obj, 'image_id', True, Image.ImageId) And ReadMonitorString(Obj, 'mime', True, Image.Mime) And
      ReadMonitorInt(Obj, 'width', True, Image.Width) And ReadMonitorInt(Obj, 'height', True, Image.Height) And
      ReadMonitorInt(Obj, 'part', True, Image.Part) And ReadMonitorInt(Obj, 'part_count', True, Image.PartCount) And
      ReadMonitorInt(Obj, 'revision', True, Image.Revision) And ReadMonitorString(Obj, 'bytes_base64', True, Image.BytesBase64)) Then
      Exit;
    Raw := DecodeMonitorImageBytes(Image.BytesBase64);
    DecodedBytes := Length(Raw);
    Result := (DecodedBytes <= MonitorMaxImagePartBytes) And (Image.Part >= 1) And (Image.PartCount >= Image.Part);
  Finally
    Data.Free;
  End;
End;

Function EncodeImageUnavailable(Const Id, ImageId, Reason: String): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If Not MonitorImageUnavailableReasonIsKnown(Reason) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('image_id', ImageId);
  Payload.Add('reason', Reason);
  Result := EncodeMonitorWith(mmkImageUnavailable, Id, Payload);
End;

Function DecodeImageUnavailable(Const PayloadJson: String; Out Image: TMonitorImageUnavailable): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Image.ImageId := '';
  Image.Reason := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'image_id', True, Image.ImageId) And ReadMonitorString(Obj, 'reason', True, Image.Reason) And
      MonitorImageUnavailableReasonIsKnown(Image.Reason);
  Finally
    Data.Free;
  End;
End;

Function EncodeImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('turn_index', TurnIndex);
  Payload.Add('image_id', ImageId);
  Result := EncodeMonitorWith(mmkImageGet, Id, Payload);
End;

Function DecodeImageGet(Const PayloadJson: String; Out Image: TMonitorImageGet): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Image.TurnIndex := 0;
  Image.ImageId := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorInt(Obj, 'turn_index', True, Image.TurnIndex) And ReadMonitorString(Obj, 'image_id', True, Image.ImageId);
  Finally
    Data.Free;
  End;
End;

Function TryEncodeImageData(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Missing, Refused: Boolean; Out Messages: TStringArray; Out UnavailableReason: String): Boolean;
Var
  Parts: TJSONArray;
  I: Integer;
  Payload: TJSONObject;
  Json: String;
Begin
  Result := False;
  Messages := Nil;
  SetLength(Messages, 0);
  UnavailableReason := '';
  Parts := Nil;
  If ImageFetchBlocked(Missing, Refused, Length(Bytes), UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  If Not TryBuildImageParts(ImageId, Mime, Width, Height, Revision, Bytes, Parts, UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  Try
    SetLength(Messages, Parts.Count);
    For I := 0 To Parts.Count - 1 Do
      Begin
        If Not (Parts[I] Is TJSONObject) Then
          Exit;
        Payload := TJSONObject(Parts[I]);
        Json := EncodeMonitorEnvelope(mmkImageData, Id, Payload);
        If Json = '' Then
          Begin
            SetLength(Messages, 0);
            UnavailableReason := 'too_large';
            Exit;
          End;
        Messages[I] := Json;
      End;
    UnavailableReason := '';
    Result := True;
  Finally
    Parts.Free;
  End;
End;

{ One pass into a sized buffer. A resume publishes these pages on the IDE thread.
  Result := Result + once per byte copies the whole page on every character and Lazarus never opens. }
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

Function ChunkFrame(Const Id, ItemId, ItemType, Data: String; Part, PartCount: Integer): String;
Begin
  Result := '{"v":' + IntToStr(MonitorCatalogueVersion) + ',"id":"' + Id + '","type":"chunk","payload":{"item_id":"' +
    ItemId + '","part":' + IntToStr(Part) + ',"part_count":' + IntToStr(PartCount) + ',"item_type":"' + ItemType +
    '","data":"' + EscapeChunkData(Data) + '"}}';
End;

{ Bytes of one UTF-8 code point starting at Index, or 1 for a stray byte. Never zero when Index is in range. }
Function Utf8UnitLen(Const Text: String; Index: Integer): Integer;
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

{ Source bytes from Start whose escaped form fits in DataBudget, ending on a code point. }
Function ChunkSourceLen(Const Item: String; Start, DataBudget: Integer): Integer;
Var
  Index, Escaped, UnitLen, UnitEsc, Offset: Integer;
Begin
  Result := 0;
  If (DataBudget < 1) Or (Start < 1) Or (Start > Length(Item)) Then
    Exit;
  Index := Start;
  Escaped := 0;
  While Index <= Length(Item) Do
    Begin
      UnitLen := Utf8UnitLen(Item, Index);
      If UnitLen < 1 Then
        Exit;
      UnitEsc := 0;
      For Offset := 0 To UnitLen - 1 Do
        Inc(UnitEsc, EscapedByteLen(Item[Index + Offset]));
      If Escaped + UnitEsc > DataBudget Then
        Exit;
      Inc(Escaped, UnitEsc);
      Inc(Result, UnitLen);
      Inc(Index, UnitLen);
    End;
End;

Function PackImageBulkItem(Const ItemId, ItemType, PayloadJson: String; Out Frames: TStringArray): Boolean;
Var
  Item, BudgetId: String;
  Start, Taken, Part, Count, Overhead, DataBudget: Integer;
  Cuts: Array Of Integer;
Begin
  Result := False;
  SetLength(Frames, 0);
  If (ItemId = '') Or (ItemType = '') Or (PayloadJson = '') Or (Not MonitorMessageIdIsSafe(ItemId)) Then
    Exit;
  Item := '{"v":' + IntToStr(MonitorCatalogueVersion) + ',"id":"' + ItemId + '","type":"' + ItemType + '","payload":' +
    PayloadJson + '}';
  If Length(Item) > MonitorMaxItemBytes Then
    Exit;
  If Length(Item) <= MonitorOutboxChunkBytes Then
    Begin
      SetLength(Frames, 1);
      Frames[0] := Item;
      Exit(True);
    End;
  { Size the slices against a full-length id and four-digit part numbers so the real frame still fits.
    One walk. Searching by rebuilding each probe locked the IDE on a multi-megabyte conversation. }
  BudgetId := StringOfChar('a', MonitorMaxMessageIdChars);
  Overhead := Length(ChunkFrame(BudgetId, ItemId, ItemType, '', 9999, 9999));
  If Overhead >= MonitorOutboxChunkBytes Then
    Exit;
  DataBudget := MonitorOutboxChunkBytes - Overhead;
  SetLength(Cuts, 0);
  Start := 1;
  While Start <= Length(Item) Do
    Begin
      Taken := ChunkSourceLen(Item, Start, DataBudget);
      If Taken < 1 Then
        Exit;
      SetLength(Cuts, Length(Cuts) + 1);
      Cuts[High(Cuts)] := Taken;
      Inc(Start, Taken);
    End;
  Count := Length(Cuts);
  SetLength(Frames, Count);
  Start := 1;
  For Part := 1 To Count Do
    Begin
      Frames[Part - 1] := ChunkFrame(ItemId + '-c' + IntToStr(Part), ItemId, ItemType, Copy(Item, Start, Cuts[Part - 1]),
        Part, Count);
      If (Length(Frames[Part - 1]) > MonitorOutboxChunkBytes) Or
        (Not MonitorMessageIdIsSafe(ItemId + '-c' + IntToStr(Part))) Then
        Begin
          SetLength(Frames, 0);
          Exit;
        End;
      Inc(Start, Cuts[Part - 1]);
    End;
  Result := True;
End;

Function TryPackImage(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer; Const Bytes: TBytes;
  Missing, Refused: Boolean; Out Frames: TStringArray; Out UnavailableReason: String): Boolean;
Var
  Payload: TJSONObject;
  Raw: RawByteString;
  Encoded, PayloadJson: String;
Begin
  Result := False;
  SetLength(Frames, 0);
  UnavailableReason := '';
  If ImageFetchBlocked(Missing, Refused, Length(Bytes), UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  SetLength(Raw, Length(Bytes));
  If Length(Bytes) > 0 Then
    Move(Bytes[0], Raw[1], Length(Bytes));
  Encoded := FramedBase64(Raw);
  If Length(Encoded) <> ExpectedBase64Chars(Length(Bytes)) Then
    Begin
      UnavailableReason := 'too_large';
      Exit(True);
    End;
  Payload := TJSONObject.Create;
  Try
    Payload.Add('image_id', ImageId);
    Payload.Add('mime', Mime);
    Payload.Add('width', Width);
    Payload.Add('height', Height);
    Payload.Add('part', 1);
    Payload.Add('part_count', 1);
    Payload.Add('revision', Revision);
    Payload.Add('bytes_base64', Encoded);
    PayloadJson := Payload.AsJSON;
  Finally
    Payload.Free;
  End;
  If Not PackImageBulkItem(Id, 'image_data', PayloadJson, Frames) Then
    Begin
      UnavailableReason := 'too_large';
      Exit(True);
    End;
  UnavailableReason := '';
  Result := True;
End;


End.
