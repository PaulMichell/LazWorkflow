Program AssistantMonitorProtocolV3Test;

{ Checks the catalogue 3 golden fixtures (c) 2026 Michell Computing.

  Plan item 5.1 of Documents/Plan-20261029-035918.md. Reads Tests/Fixtures/Monitor/catalogue.json
  and every message under Tests/Fixtures/Monitor/messages/, and checks each message against the
  catalogue: envelope, type, payload fields and their JSON kinds, event data, state values, the
  closed value sets and the frame size. Every type, event kind and state key needs a fixture.
  The chunk fixtures must join into a valid message, and append offsets count UTF-8 bytes.
  Every message is version 3 except a protocol rejection, which uses the client's version.
  The shared limits are compared with this code base's constants. The Kotlin
  ProtocolV3FixtureTest makes the same checks on the same files.
  No catalogue 3 codec exists yet. When it does (items 5.3 to 5.6), the codec tests take these
  fixtures over. No sockets and no Interfaces unit. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, AssistantMonitorLinkStubs, AssistantMonitorFrames, AssistantMonitorCodec,
  AssistantMonitorSession, AssistantMonitorOutbox, AssistantMonitorCommandIntake;

Type
  TFixture = Record
    Name: String;
    Bytes: Int64;
    Data: TJSONData;
  End;

Var
  FailCount: Integer;
  Problem: String;
  CatalogueData: TJSONData;
  Catalogue: TJSONObject;
  Fixtures: Array Of TFixture;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

{ Records the first reason a validation failed. Always False, so callers can Exit(Fail(...)). }
Function Fail(Const Text: String): Boolean;
Begin
  If Problem = '' Then
    Problem := Text;
  Result := False;
End;

Function RepositoryRoot: String;
Var
  I: Integer;
  Probe, Dir: String;
Begin
  Result := '';
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'RunAssistantTests.pas') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
End;

Function FixtureRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + 'Monitor' + PathDelim;
End;

{ Raw file bytes, marked UTF-8 so fpjson takes them without a code page conversion. }
Function ReadUtf8File(Const Path: String): RawByteString;
Var
  Stream: TFileStream;
Begin
  Result := '';
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
  Try
    SetLength(Result, Stream.Size);
    If Stream.Size > 0 Then
      Stream.ReadBuffer(Result[1], Stream.Size);
  Finally
    Stream.Free;
  End;
  SetCodePage(Result, CP_UTF8, False);
End;

Function ParseOrNil(Const Text: RawByteString): TJSONData;
Begin
  Result := Nil;
  Try
    Result := GetJSON(Text);
  Except
    Result := Nil;
  End;
End;

Function Section(Owner: TJSONObject; Const Name: String): TJSONObject;
Var
  Found: TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Owner) Then
    Exit;
  Found := Owner.Find(Name);
  If Assigned(Found) And (Found.JSONType = jtObject) Then
    Result := TJSONObject(Found);
End;

Function IsInteger(Value: TJSONData): Boolean;
Begin
  Result := Assigned(Value) And (Value.JSONType = jtNumber) And
    (TJSONNumber(Value).NumberType In [ntInteger, ntInt64, ntQWord]);
End;

Function IsHex32(Const Text: String): Boolean;
Var
  I: Integer;
Begin
  Result := Length(Text) = 32;
  If Not Result Then
    Exit;
  For I := 1 To Length(Text) Do
    If Not (Text[I] In ['0'..'9', 'a'..'f']) Then
      Exit(False);
End;

Function EnumHas(Const EnumName, Value: String): Boolean;
Var
  List: TJSONData;
  I: Integer;
Begin
  Result := False;
  List := Nil;
  If Assigned(Section(Catalogue, 'enums')) Then
    List := Section(Catalogue, 'enums').Find(EnumName);
  If (Not Assigned(List)) Or (List.JSONType <> jtArray) Then
    Exit;
  For I := 0 To TJSONArray(List).Count - 1 Do
    If TJSONArray(List).Items[I].AsString = Value Then
      Exit(True);
End;

Function ValidateObject(Const Path: String; Obj: TJSONObject; Spec: TJSONObject): Boolean; Forward;

Function ValidateNamed(Const Path: String; Value: TJSONData; Const SectionName, Name: String): Boolean;
Var
  Spec: TJSONObject;
Begin
  Spec := Section(Section(Catalogue, SectionName), Name);
  If Not Assigned(Spec) Then
    Exit(Fail(Path + ': ' + SectionName + ' has no "' + Name + '"'));
  If Value.JSONType <> jtObject Then
    Exit(Fail(Path + ' is not an object'));
  Result := ValidateObject(Path, TJSONObject(Value), Spec);
End;

{ Owner is the object that holds Value. event_data and state_value read their sibling event or key. }
Function CheckKind(Const Path: String; Value: TJSONData; Const Kind: String; Owner: TJSONObject): Boolean;
Var
  Rest: String;
  I: Integer;
  Members: TJSONObject;
Begin
  Result := False;
  If Kind = 'string' Then
    Result := Value.JSONType = jtString
  Else If Kind = 'integer' Then
    Result := IsInteger(Value)
  Else If Kind = 'boolean' Then
    Result := Value.JSONType = jtBoolean
  Else If Kind = 'object' Then
    Result := Value.JSONType = jtObject
  Else If Kind = 'array' Then
    Result := Value.JSONType = jtArray
  Else If Kind = 'id' Then
    Result := (Value.JSONType = jtString) And MonitorMessageIdIsSafe(Value.AsString)
  Else If Kind = 'hex32' Then
    Result := (Value.JSONType = jtString) And IsHex32(Value.AsString)
  Else If Kind = 'event_data' Then
    Exit(ValidateNamed(Path, Value, 'events', Owner.Get('event', '')))
  Else If Kind = 'state_value' Then
    Exit(ValidateNamed(Path, Value, 'state', Owner.Get('key', '')))
  Else If Kind = 'state_map' Then
    Begin
      If Value.JSONType <> jtObject Then
        Exit(Fail(Path + ' is not an object'));
      Members := TJSONObject(Value);
      For I := 0 To Members.Count - 1 Do
        If Not ValidateNamed(Path + '.' + Members.Names[I], Members.Items[I], 'state', Members.Names[I]) Then
          Exit(False);
      Exit(True);
    End
  Else If Copy(Kind, 1, 5) = 'enum:' Then
    Result := (Value.JSONType = jtString) And EnumHas(Copy(Kind, 6, MaxInt), Value.AsString)
  Else If Copy(Kind, 1, 7) = 'object:' Then
    Exit(ValidateNamed(Path, Value, 'objects', Copy(Kind, 8, MaxInt)))
  Else If Copy(Kind, 1, 6) = 'array:' Then
    Begin
      If Value.JSONType <> jtArray Then
        Exit(Fail(Path + ' is not an array'));
      Rest := Copy(Kind, 7, MaxInt);
      For I := 0 To TJSONArray(Value).Count - 1 Do
        If Not CheckKind(Path + '[' + IntToStr(I) + ']', TJSONArray(Value).Items[I], Rest, Nil) Then
          Exit(False);
      Exit(True);
    End
  Else
    Exit(Fail(Path + ': unknown kind ' + Kind));
  If Not Result Then
    Fail(Path + ' is not ' + Kind);
End;

Function ValidateObject(Const Path: String; Obj: TJSONObject; Spec: TJSONObject): Boolean;
Var
  Required, Optional: TJSONObject;
  Found, KindData: TJSONData;
  I: Integer;
  Name: String;
Begin
  Required := Section(Spec, 'required');
  Optional := Section(Spec, 'optional');
  If (Not Assigned(Required)) Or (Not Assigned(Optional)) Then
    Exit(Fail(Path + ': spec has no required or optional'));
  For I := 0 To Required.Count - 1 Do
    Begin
      Name := Required.Names[I];
      Found := Obj.Find(Name);
      If Not Assigned(Found) Then
        Exit(Fail(Path + '.' + Name + ' is missing'));
      If Not CheckKind(Path + '.' + Name, Found, Required.Items[I].AsString, Obj) Then
        Exit(False);
    End;
  For I := 0 To Obj.Count - 1 Do
    Begin
      Name := Obj.Names[I];
      If Assigned(Required.Find(Name)) Then
        Continue;
      KindData := Optional.Find(Name);
      If Not Assigned(KindData) Then
        Exit(Fail(Path + '.' + Name + ' is not in the catalogue'));
      If Not CheckKind(Path + '.' + Name, Obj.Items[I], KindData.AsString, Obj) Then
        Exit(False);
    End;
  Result := True;
End;

Function Limit(Const Name: String): Int64;
Var
  Found: TJSONData;
Begin
  Result := -1;
  Found := Nil;
  If Assigned(Section(Catalogue, 'limits')) Then
    Found := Section(Catalogue, 'limits').Find(Name);
  If IsInteger(Found) Then
    Result := Found.AsInt64;
End;

Procedure LoadCatalogue;
Begin
  CatalogueData := ParseOrNil(ReadUtf8File(FixtureRoot + 'catalogue.json'));
  Catalogue := Nil;
  If Assigned(CatalogueData) And (CatalogueData.JSONType = jtObject) Then
    Catalogue := TJSONObject(CatalogueData);
  Check('catalogue.json is a JSON object', Assigned(Catalogue));
  If Not Assigned(Catalogue) Then
    Exit;
  Check('catalogue is version 3', IsInteger(Catalogue.Find('catalogue')) And (Catalogue.Find('catalogue').AsInteger = 3));
  Check('catalogue has every section', Assigned(Section(Catalogue, 'limits')) And Assigned(Section(Catalogue, 'enums')) And
    Assigned(Section(Catalogue, 'objects')) And Assigned(Section(Catalogue, 'types')) And
    Assigned(Section(Catalogue, 'events')) And Assigned(Section(Catalogue, 'state')));
End;

Procedure TestTypeTable;
Var
  Types, Spec: TJSONObject;
  I: Integer;
  Good: Boolean;
Begin
  Types := Section(Catalogue, 'types');
  Good := True;
  Problem := '';
  For I := 0 To Types.Count - 1 Do
    Begin
      Spec := Section(Types, Types.Names[I]);
      If (Not Assigned(Spec)) Or (Not EnumHas('direction', Spec.Get('direction', ''))) Or
        (Not EnumHas('lane', Spec.Get('lane', ''))) Or (Not Assigned(Section(Spec, 'required'))) Or
        (Not Assigned(Section(Spec, 'optional'))) Then
        Begin
          Good := Fail('type ' + Types.Names[I] + ' has a bad direction, lane or field list');
          Break;
        End;
      { A type only the phone sends has no host lane, and every host type has one. }
      If (Spec.Get('direction', '') = 'phone') <> (Spec.Get('lane', '') = 'none') Then
        Begin
          Good := Fail('type ' + Types.Names[I] + ' lane does not match its direction');
          Break;
        End;
    End;
  Check('every type has a direction, a lane and field lists ' + Problem, Good);
End;

Procedure TestLimits;
Begin
  Check('limit max_frame_payload_bytes matches MonitorMaxPayloadBytes', Limit('max_frame_payload_bytes') = MonitorMaxPayloadBytes);
  Check('limit frame_header_bytes matches MonitorFrameHeaderSize', Limit('frame_header_bytes') = MonitorFrameHeaderSize);
  Check('limit outbox_frame_bytes matches MonitorOutboxChunkBytes', Limit('outbox_frame_bytes') = MonitorOutboxChunkBytes);
  Check('limit max_item_bytes matches MonitorOutboxBulkBudget', Limit('max_item_bytes') = MonitorOutboxBulkBudget);
  Check('limit log_budget_bytes matches MonitorOutboxLogBudget', Limit('log_budget_bytes') = MonitorOutboxLogBudget);
  Check('limit max_message_id_chars matches MonitorMaxMessageIdChars', Limit('max_message_id_chars') = MonitorMaxMessageIdChars);
  Check('limit max_send_chars matches MonitorMaxSendChars', Limit('max_send_chars') = MonitorMaxSendChars);
  Check('limit heartbeat_ms matches MonitorHeartbeatMs', Limit('heartbeat_ms') = MonitorHeartbeatMs);
  Check('limit dead_link_ms matches MonitorDeadSessionMs', Limit('dead_link_ms') = MonitorDeadSessionMs);
  Check('limit partial_frame_ms matches MonitorPartialFrameMs', Limit('partial_frame_ms') = MonitorPartialFrameMs);
  Check('limit pair_code_ttl_ms matches MonitorPairCodeTtlMs', Limit('pair_code_ttl_ms') = MonitorPairCodeTtlMs);
  Check('limit nonce_ttl_ms matches MonitorNonceTtlMs', Limit('nonce_ttl_ms') = MonitorNonceTtlMs);
  Check('limit command_memory matches MonitorCommandMemory', Limit('command_memory') = MonitorCommandMemory);
  Check('limit max_image_fetch_bytes matches MonitorMaxImageFetchBytes', Limit('max_image_fetch_bytes') = MonitorMaxImageFetchBytes);
  Check('keepalive starts at the dead-link time', Limit('keepalive_idle_s') * 1000 = Limit('dead_link_ms'));
  Check('keepalive repeats at the heartbeat interval', Limit('keepalive_interval_s') * 1000 = Limit('heartbeat_ms'));
End;

Procedure TestCommandStateNames;
Var
  State: TMonitorCommandState;
  Good: Boolean;
Begin
  Good := True;
  For State := Low(TMonitorCommandState) To High(TMonitorCommandState) Do
    Good := Good And EnumHas('command_state', MonitorCommandStateName(State));
  Check('every intake table state is a catalogue command_state', Good);
End;

Procedure LoadFixtures;
Var
  Info: TSearchRec;
  Dir: String;
  Index: Integer;
Begin
  SetLength(Fixtures, 0);
  Dir := FixtureRoot + 'messages' + PathDelim;
  If FindFirst(Dir + '*.json', faAnyFile, Info) = 0 Then
    Try
      Repeat
        Index := Length(Fixtures);
        SetLength(Fixtures, Index + 1);
        Fixtures[Index].Name := Info.Name;
        Fixtures[Index].Bytes := Info.Size;
        Fixtures[Index].Data := ParseOrNil(ReadUtf8File(Dir + Info.Name));
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  Check('message fixtures found', Length(Fixtures) > 0);
End;

Function FixtureNamed(Const Name: String): TJSONObject;
Var
  I: Integer;
Begin
  Result := Nil;
  For I := 0 To High(Fixtures) Do
    If (Fixtures[I].Name = Name) And Assigned(Fixtures[I].Data) And (Fixtures[I].Data.JSONType = jtObject) Then
      Exit(TJSONObject(Fixtures[I].Data));
End;

Function ValidateEnvelope(Const Path: String; Root: TJSONObject; Const ExpectType: String): Boolean;
Var
  TypeName: String;
  Spec: TJSONObject;
  Version: Int64;
Begin
  If (Root.Count <> 4) Or (Not Assigned(Root.Find('v'))) Or (Not Assigned(Root.Find('id'))) Or
    (Not Assigned(Root.Find('type'))) Or (Not Assigned(Root.Find('payload'))) Then
    Exit(Fail(Path + ': the envelope must be exactly v, id, type and payload'));
  If Not IsInteger(Root.Find('v')) Then
    Exit(Fail(Path + ': v is not an integer'));
  Version := Root.Find('v').AsInt64;
  TypeName := Root.Get('type', '');
  { A protocol rejection is written in the client's version, so an older app can read it (spec section 3). }
  If (Version <> 3) And ((TypeName <> 'rejected') Or (Version < 1) Or (Version > 2)) Then
    Exit(Fail(Path + ': v is not 3'));
  If Not CheckKind(Path + '.id', Root.Find('id'), 'id', Root) Then
    Exit(False);
  Spec := Section(Section(Catalogue, 'types'), TypeName);
  If Not Assigned(Spec) Then
    Exit(Fail(Path + ': type ' + TypeName + ' is not in the catalogue'));
  If (ExpectType <> '') And (TypeName <> ExpectType) Then
    Exit(Fail(Path + ': type ' + TypeName + ' does not match ' + ExpectType));
  If Root.Find('payload').JSONType <> jtObject Then
    Exit(Fail(Path + ': payload is not an object'));
  Result := ValidateObject(Path + '.payload', TJSONObject(Root.Find('payload')), Spec);
End;

Procedure TestFixtures;
Var
  I, Dash: Integer;
  Stem, TypeName: String;
  Root, Payload: TJSONObject;
  SeenTypes, SeenEvents, SeenKeys: TStringList;
  Good: Boolean;

  Procedure CheckCovered(Const What: String; Spec: TJSONObject; Seen: TStringList);
  Var
    J: Integer;
    Missing: String;
  Begin
    Missing := '';
    For J := 0 To Spec.Count - 1 Do
      If Seen.IndexOf(Spec.Names[J]) < 0 Then
        Missing := Missing + ' ' + Spec.Names[J];
    Check('every ' + What + ' has a fixture' + Missing, Missing = '');
  End;

Begin
  SeenTypes := TStringList.Create;
  SeenEvents := TStringList.Create;
  SeenKeys := TStringList.Create;
  Try
    For I := 0 To High(Fixtures) Do
      Begin
        Check(Fixtures[I].Name + ' is a JSON object', Assigned(Fixtures[I].Data) And (Fixtures[I].Data.JSONType = jtObject));
        If (Not Assigned(Fixtures[I].Data)) Or (Fixtures[I].Data.JSONType <> jtObject) Then
          Continue;
        Root := TJSONObject(Fixtures[I].Data);
        Stem := ChangeFileExt(Fixtures[I].Name, '');
        Dash := Pos('-', Stem);
        TypeName := Stem;
        If Dash > 0 Then
          TypeName := Copy(Stem, 1, Dash - 1);
        { Validate first: the title shows the reason the validation recorded. }
        Problem := '';
        Good := ValidateEnvelope(Fixtures[I].Name, Root, TypeName);
        Check(Fixtures[I].Name + ' matches the catalogue ' + Problem, Good);
        Check(Fixtures[I].Name + ' fits one outbox frame', Fixtures[I].Bytes <= Limit('outbox_frame_bytes'));
        SeenTypes.Add(Root.Get('type', ''));
        Payload := Section(Root, 'payload');
        If Not Assigned(Payload) Then
          Continue;
        If Root.Get('type', '') = 'event' Then
          SeenEvents.Add(Payload.Get('event', ''))
        Else If Root.Get('type', '') = 'state' Then
          SeenKeys.Add(Payload.Get('key', ''));
      End;
    CheckCovered('type', Section(Catalogue, 'types'), SeenTypes);
    CheckCovered('event kind', Section(Catalogue, 'events'), SeenEvents);
    CheckCovered('state key', Section(Catalogue, 'state'), SeenKeys);
  Finally
    SeenKeys.Free;
    SeenEvents.Free;
    SeenTypes.Free;
  End;
End;

{ Spec section 3: an older app must be able to read the rejection that tells it to update. }
Procedure TestRejectedVersion;
Var
  Rejected, Payload: TJSONObject;
Begin
  Rejected := FixtureNamed('rejected-old-client.json');
  Payload := Section(Rejected, 'payload');
  Check('the old-client rejection fixture loads', Assigned(Payload));
  If Not Assigned(Payload) Then
    Exit;
  Check('a protocol rejection is written in the client''s version', Rejected.Get('v', 0) = Payload.Get('client_version', -1));
  Check('the old-client rejection is not version 3', Rejected.Get('v', 0) <> 3);
End;

Procedure TestChunkJoin;
Var
  First, Second, FirstPayload, SecondPayload: TJSONObject;
  Joined: UTF8String;
  JoinedData: TJSONData;
  Good: Boolean;
Begin
  First := FixtureNamed('chunk-1.json');
  Second := FixtureNamed('chunk-2.json');
  Check('both chunk fixtures load', Assigned(First) And Assigned(Second));
  If (Not Assigned(First)) Or (Not Assigned(Second)) Then
    Exit;
  FirstPayload := Section(First, 'payload');
  SecondPayload := Section(Second, 'payload');
  Check('chunks are parts 1 and 2 of one item', (FirstPayload.Get('item_id', '') = SecondPayload.Get('item_id', '')) And
    (FirstPayload.Get('part', 0) = 1) And (SecondPayload.Get('part', 0) = 2) And
    (FirstPayload.Get('part_count', 0) = 2) And (SecondPayload.Get('part_count', 0) = 2));
  Joined := UTF8String(FirstPayload.Get('data', '')) + UTF8String(SecondPayload.Get('data', ''));
  JoinedData := ParseOrNil(Joined);
  Try
    Check('joined chunk data is a JSON object', Assigned(JoinedData) And (JoinedData.JSONType = jtObject));
    If (Not Assigned(JoinedData)) Or (JoinedData.JSONType <> jtObject) Then
      Exit;
    Problem := '';
    Good := ValidateEnvelope('joined chunk', TJSONObject(JoinedData), FirstPayload.Get('item_type', ''));
    Check('joined chunk data is a valid ' + FirstPayload.Get('item_type', '') + ' message ' + Problem, Good);
    Check('a joined item is not another chunk', TJSONObject(JoinedData).Get('type', '') <> 'chunk');
  Finally
    JoinedData.Free;
  End;
End;

Procedure TestAppendOffsets;
Var
  First, Second, FirstData, SecondData: TJSONObject;
  FirstText: UTF8String;
Begin
  First := FixtureNamed('event-block_append-first.json');
  Second := FixtureNamed('event-block_append-second.json');
  Check('both append fixtures load', Assigned(First) And Assigned(Second));
  If (Not Assigned(First)) Or (Not Assigned(Second)) Then
    Exit;
  FirstData := Section(Section(First, 'payload'), 'data');
  SecondData := Section(Section(Second, 'payload'), 'data');
  Check('append fixtures carry data', Assigned(FirstData) And Assigned(SecondData));
  If (Not Assigned(FirstData)) Or (Not Assigned(SecondData)) Then
    Exit;
  FirstText := UTF8String(FirstData.Get('text', ''));
  Check('the first append text is not ASCII', Length(FirstText) > Length(UnicodeString(FirstText)));
  Check('appends are to one block', FirstData.Get('block_id', '') = SecondData.Get('block_id', ''));
  Check('the first append starts at offset 0', FirstData.Get('offset', -1) = 0);
  Check('the second offset is the first text in UTF-8 bytes', SecondData.Get('offset', -1) = Length(FirstText));
  Check('the second append is the next seq',
    Section(Second, 'payload').Get('seq', Int64(0)) = Section(First, 'payload').Get('seq', Int64(0)) + 1);
End;

Procedure FreeFixtures;
Var
  I: Integer;
Begin
  For I := 0 To High(Fixtures) Do
    FreeAndNil(Fixtures[I].Data);
  SetLength(Fixtures, 0);
End;

Begin
  FailCount := 0;
  CatalogueData := Nil;
  Catalogue := Nil;
  If RepositoryRoot = '' Then
    Begin
      WriteLn('FAIL repository root');
      Halt(1);
    End;
  Try
    Try
      LoadCatalogue;
      If Assigned(Catalogue) Then
        Begin
          TestTypeTable;
          TestLimits;
          TestCommandStateNames;
          LoadFixtures;
          TestFixtures;
          TestRejectedVersion;
          TestChunkJoin;
          TestAppendOffsets;
        End;
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    FreeFixtures;
    FreeAndNil(CatalogueData);
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorProtocolV3Test tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorProtocolV3Test test(s) failed.');
      Halt(1);
    End;
End.
