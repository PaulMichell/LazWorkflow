Program AssistantMonitorGrainTest;

{ Grain the hybrid does not speak yet (c) 2026 Michell Computing.

  Memory carrier and the mirror log. No sockets and no Interfaces unit.
  Each check names the item that turns it green. Do not weaken an assertion
  to match catalogue 2. Item 7.1 is that item. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  AssistantMonitorCommands, Classes, SysUtils, fpjson, jsonparser, AssistantMonitorLinkStubs, AssistantMonitorCodec, AssistantMonitorFrames,
  AssistantMonitorCarrier, AssistantMonitorSession, AssistantMonitorMirror, AssistantSessionObserve, AssistantMonitorSettings,
  WorkflowSettings;

Const
  SliceBytes = 4096;
  TenKib = 10 * 1024;
  FnvOffsetBasis = UInt64(14695981039346656037);
  FnvPrime = UInt64(1099511628211);

Var
  FailCount: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;
  SettingsRoot: String;
  ErrorText: String;

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

Function Fnv1a64(Const Text: RawByteString): String;
Var
  Hash: UInt64;
  I: Integer;
Begin
  { The runner compiles with overflow checks. The hash is defined to wrap. }
  {$PUSH}{$Q-}{$R-}
  Hash := FnvOffsetBasis;
  For I := 1 To Length(Text) Do
    Begin
      Hash := Hash Xor Ord(Text[I]);
      Hash := Hash * FnvPrime;
    End;
  {$POP}
  Result := LowerCase(HexStr(Hash, 16));
End;

Function JsonTypeName(Const Json: String): String;
Var
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Result := '';
  Data := Nil;
  Try
    Data := GetJSON(Json);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Root := TJSONObject(Data);
  Try
    Result := Root.Get('type', '');
  Finally
    Data.Free;
  End;
End;

Function PayloadText(Const Json, Name: String): String;
Var
  Data: TJSONData;
  Root, Payload: TJSONObject;
Begin
  Result := '';
  Data := Nil;
  Try
    Data := GetJSON(Json);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Root := TJSONObject(Data);
  Try
    If Not (Root.Find('payload') Is TJSONObject) Then
      Exit;
    Payload := TJSONObject(Root.Find('payload'));
    Result := Payload.Get(Name, '');
  Finally
    Data.Free;
  End;
End;

Function SentHasType(Const TypeName: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To Carrier.SentCount - 1 Do
    If JsonTypeName(Carrier.SentJson(I)) = TypeName Then
      Exit(True);
End;

Procedure FillBlock(Var Block: TAssistantMonitorBlock; Const Id, Body: String; Running: Boolean);
Begin
  Block := Default(TAssistantMonitorBlock);
  Block.Kind := 'answer';
  Block.BlockId := Id;
  Block.Title := '';
  Block.Body := Body;
  Block.Running := Running;
  Block.Ok := Not Running;
End;

Function MakeTurn(Const Body: String; Running: Boolean; Const ImageId: String): TAssistantMonitorTurn;
Begin
  Result := Default(TAssistantMonitorTurn);
  Result.TurnIndex := 0;
  Result.Id := 't-1';
  Result.Mode := 'Build';
  Result.Prompt := 'Grow the block';
  Result.CreatedAt := '2026-11-03T12:00:00Z';
  Result.Live := True;
  SetLength(Result.Blocks, 1);
  FillBlock(Result.Blocks[0], 'b-1', Body, Running);
  If ImageId <> '' Then
    Begin
      SetLength(Result.Images, 1);
      Result.Images[0] := Default(TAssistantMonitorImage);
      Result.Images[0].Id := ImageId;
      Result.Images[0].Name := 'shot.png';
      Result.Images[0].Mime := 'image/png';
      Result.Images[0].Missing := False;
    End;
End;

Function TenKibBody: RawByteString;
Var
  Euro: RawByteString;
Begin
  { A 3-byte character sits on the 4096 boundary so a byte split would cut it. }
  Euro := #$E2#$82#$AC;
  Result := StringOfChar('a', 4095) + Euro + StringOfChar('b', TenKib - 4095 - Length(Euro));
End;

Function PreviousOffset(Const Events: TMonitorMirrorEventArray; Index: Integer): Integer;
Var
  J: Integer;
  Data: TJSONData;
  Obj: TJSONObject;
  Text: String;
  Offset: Integer;
Begin
  Result := -1;
  For J := Index - 1 DownTo 0 Do
    If Events[J].Kind = 'block_append' Then
      Begin
        Data := GetJSON(Events[J].Data);
        Try
          Obj := TJSONObject(Data);
          Offset := Obj.Get('offset', 0);
          Text := Obj.Get('text', '');
          Result := Offset + Length(RawByteString(Text));
        Finally
          Data.Free;
        End;
        Exit;
      End;
End;

Procedure TestAppendSlices;
Var
  Mirror: TMonitorMirror;
  Events: TMonitorMirrorEventArray;
  Turn: TAssistantMonitorTurn;
  Body, Replaced: RawByteString;
  Pages: TMonitorSnapshotPageArray;
  I, Appends, Replaces: Integer;
  SawNewHash, SawOldHash: Boolean;
  Offset, Previous: Integer;
  Data: TJSONData;
  Obj: TJSONObject;
  Text: String;
  HashBefore, HashAfter: String;
Begin
  Events := Nil;
  Mirror := TMonitorMirror.Create;
  Try
    Mirror.BeginStream('aa', 'conversation-1', '/work', 'Grain');
    Body := TenKibBody;
    Turn := MakeTurn('', True, '');
    Mirror.ObserveTurn(Turn);
    Turn := MakeTurn(Body, True, '');
    Mirror.ObserveTurn(Turn);
    Check('7.1 the log is readable', Mirror.CopyEvents(Events) > 0);
    Appends := 0;
    Previous := -1;
    For I := 0 To High(Events) Do
      Begin
        Check('7.1 a growing block does not queue a patch', Events[I].Kind <> 'patch');
        If Events[I].Kind <> 'block_append' Then
          Continue;
        Inc(Appends);
        Data := Nil;
        Try
          Data := GetJSON(Events[I].Data);
        Except
          Data := Nil;
        End;
        If Not (Data Is TJSONObject) Then
          Begin
            Data.Free;
            Check('7.1 block_append data is JSON', False);
            Continue;
          End;
        Obj := TJSONObject(Data);
        Try
          Offset := Obj.Get('offset', -1);
          Text := Obj.Get('text', '');
          If Previous >= 0 Then
            Check('7.1 append sequences are consecutive', Events[I].Seq = Events[Previous].Seq + 1);
          Check('7.1 append offsets match the previous UTF-8 length', (Appends = 1) Or (Offset = PreviousOffset(Events, I)));
          Check('7.1 a slice is at most 4 KiB', Length(RawByteString(Text)) <= SliceBytes);
          Check('7.1 a multi-byte UTF-8 character is not split', (Pos(#$E2, Text) = 0) Or (Pos(#$E2#$82#$AC, Text) > 0));
        Finally
          Data.Free;
        End;
        Previous := I;
      End;
    Check('7.1 a 10 KiB growth is three block_append slices', Appends = 3);
    HashBefore := Fnv1a64(Body);
    Replaced := Body;
    Replaced[1] := 'z';
    Turn := MakeTurn(Replaced, True, '');
    Mirror.ObserveTurn(Turn);
    Mirror.CopyEvents(Events);
    Replaces := 0;
    For I := 0 To High(Events) Do
      If Events[I].Kind = 'block_replace' Then
        Begin
          Inc(Replaces);
          Check('7.1 a replace over 4 KiB is deferred', Pos('"deferred":true', Events[I].Data) > 0);
          Check('7.1 a deferred replace does not carry the body', Pos('"body":', Events[I].Data) = 0);
        End;
    Check('7.1 a same-length replacement is one block_replace', Replaces = 1);
    HashAfter := Fnv1a64(Replaced);
    Mirror.BuildSnapshotPages('aa', Mirror.Head, Pages);
    SawNewHash := False;
    SawOldHash := False;
    For I := 0 To High(Pages) Do
      Begin
        If Pos(HashAfter, Pages[I].Json) > 0 Then
          SawNewHash := True;
        If Pos(HashBefore, Pages[I].Json) > 0 Then
          SawOldHash := True;
      End;
    Check('7.1 the outline hash changes when the body is replaced', SawNewHash And Not SawOldHash);
  Finally
    Mirror.Free;
  End;
End;

Procedure TestNewBlockBody;
Var
  Mirror: TMonitorMirror;
  Events: TMonitorMirrorEventArray;
  I, OpenAt, BodyAt, CloseAt, ImageAt: Integer;
Begin
  Events := Nil;
  Mirror := TMonitorMirror.Create;
  Try
    Mirror.BeginStream('aa', 'conversation-1', '/work', 'Grain');
    Mirror.ObserveTurn(MakeTurn('Hello', False, 'img-1'));
    Mirror.CopyEvents(Events);
    OpenAt := -1;
    BodyAt := -1;
    CloseAt := -1;
    ImageAt := -1;
    For I := 0 To High(Events) Do
      Begin
        If (Events[I].Kind = 'block_open') And (OpenAt < 0) Then
          OpenAt := I;
        If ((Events[I].Kind = 'block_append') Or (Events[I].Kind = 'block_replace')) And (BodyAt < 0) Then
          BodyAt := I;
        If (Events[I].Kind = 'block_close') And (CloseAt < 0) Then
          CloseAt := I;
        If Events[I].Kind = 'image_added' Then
          ImageAt := I;
      End;
    Check('7.1 a new block emits block_open', OpenAt >= 0);
    Check('7.1 body events follow block_open', (BodyAt > OpenAt) And (OpenAt >= 0));
    Check('7.1 block_close follows the body events', (CloseAt > BodyAt) And (BodyAt >= 0));
    Check('7.1 image_added is still recorded', ImageAt >= 0);
  Finally
    Mirror.Free;
  End;
End;

Procedure GoLive;
Var
  Spare: TMonitorFrame;
Begin
  Session.NoteSocketClosed;
  Check('7.1 handshake accepted', Session.AcceptHandshake(Spare, True));
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandHello('hello', 'Phone', '1', ''));
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandPair('pair', '', ''));
  Check('7.1 paired', Session.State = mssLive);
End;

Procedure TestPriority;
Var
  I, StatusAt, SliceAt: Integer;
  Slice, Status: String;
Begin
  Carrier.ClearSent;
  Slice := '{"v":3,"id":"e-1","type":"event","payload":{"conversation_id":"c","stream_id":"aa","seq":1,' +
    '"event":"block_append","data":{"block_id":"b-1","offset":0,"text":"x"}}}';
  Status := '{"v":3,"id":"s-1","type":"status","payload":{"busy":false,"sending":false}}';
  Check('7.1 slice queued', Session.TryQueueHostJson(Slice));
  Check('7.1 status queued while slices are queued', Session.TryQueueHostJson(Status));
  Session.DrainOutbound;
  StatusAt := -1;
  SliceAt := -1;
  For I := 0 To Carrier.SentCount - 1 Do
    Begin
      If JsonTypeName(Carrier.SentJson(I)) = 'status' Then
        StatusAt := I;
      If JsonTypeName(Carrier.SentJson(I)) = 'event' Then
        SliceAt := I;
    End;
  Check('7.1 a status queued while slices are queued is taken first', (StatusAt >= 0) And (SliceAt >= 0) And
    (StatusAt < SliceAt));
End;

Procedure TestResumeAndBaseline;
Var
  I: Integer;
  SawPatch, SawCatchup, SawSlice, SawHash, SawBody, SawNotReady, EndBeforePage: Boolean;
  PageAt, EndAt: Integer;
Begin
  Session.BeginMirrorEpoch('aa11bb22cc33dd44ee55ff6677889900', 'conversation-1', '/work', 'Grain');
  Session.ObserveTurn(MakeTurn('', True, ''));
  Session.ObserveTurn(MakeTurn(TenKibBody, True, ''));
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"r-1","type":"resume","payload":{"conversation_id":"conversation-1",' +
    '"stream_id":"aa11bb22cc33dd44ee55ff6677889900","seq":0,"commands":[]}}');
  Session.DrainOutbound;
  SawPatch := False;
  SawCatchup := False;
  SawSlice := False;
  For I := 0 To Carrier.SentCount - 1 Do
    Begin
      If JsonTypeName(Carrier.SentJson(I)) = 'patch' Then
        SawPatch := True;
      If JsonTypeName(Carrier.SentJson(I)) = 'catchup' Then
        SawCatchup := True;
      If (JsonTypeName(Carrier.SentJson(I)) = 'event') And (Pos('block_append', Carrier.SentJson(I)) > 0) Then
        SawSlice := True;
    End;
  Check('7.1 a resume still in the log queues only the missing slices', SawSlice And Not SawPatch And Not SawCatchup);

  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"r-2","type":"resume","payload":{"conversation_id":"conversation-1",' +
    '"stream_id":"ffffffffffffffffffffffffffffffff","seq":0,"commands":[]}}');
  Session.DrainOutbound;
  SawCatchup := False;
  SawHash := False;
  SawBody := False;
  PageAt := -1;
  EndAt := -1;
  For I := 0 To Carrier.SentCount - 1 Do
    Begin
      If JsonTypeName(Carrier.SentJson(I)) = 'catchup' Then
        SawCatchup := True;
      If JsonTypeName(Carrier.SentJson(I)) = 'snapshot_page' Then
        Begin
          If PageAt < 0 Then
            PageAt := I;
          If Pos('"hash":', Carrier.SentJson(I)) > 0 Then
            SawHash := True;
          If Pos('"body":', Carrier.SentJson(I)) > 0 Then
            SawBody := True;
        End;
      If JsonTypeName(Carrier.SentJson(I)) = 'snapshot_end' Then
        EndAt := I;
    End;
  Check('7.1 a resume that misses the log queues one baseline with hashes', SawHash And Not SawCatchup And Not SawBody);
  Check('7.1 snapshot_end is not taken before its pages', (PageAt >= 0) And (EndAt > PageAt));

  Carrier.ClearSent;
  Session.BeginMirrorEpoch('bb22cc33dd44ee55ff667788990011aa', 'conversation-empty', '/work', 'Empty');
  Carrier.DeliverJson('{"v":3,"id":"r-3","type":"resume","payload":{"conversation_id":"conversation-empty",' +
    '"stream_id":"","seq":0,"commands":[]}}');
  Session.DrainOutbound;
  SawNotReady := SentHasType('not_ready');
  EndBeforePage := SentHasType('snapshot_page') Or SentHasType('snapshot');
  Check('7.1 an empty or unloaded conversation is not_ready', SawNotReady And Not EndBeforePage);
End;

Procedure TestCreditAndGeneration;
Var
  I, EventsSent, DroppedBefore: Integer;
  Big, Ping: String;
  WindowFull: Boolean;
Begin
  Carrier.ClearSent;
  Big := '{"v":3,"id":"e-big","type":"event","payload":{"seq":1,"event":"block_append","data":{"text":"' +
    StringOfChar('q', 60000) + '"}}}';
  WindowFull := False;
  For I := 1 To 20 Do
    Begin
      Big := '{"v":3,"id":"e-big-' + IntToStr(I) + '","type":"event","payload":{"seq":' + IntToStr(I) +
        ',"event":"block_append","data":{"text":"' + StringOfChar('q', 60000) + '"}}}';
      If Not Session.TryQueueHostJson(Big) Then
        WindowFull := True;
    End;
  Session.DrainOutbound;
  EventsSent := 0;
  For I := 0 To Carrier.SentCount - 1 Do
    If JsonTypeName(Carrier.SentJson(I)) = 'event' Then
      Inc(EventsSent);
  Check('7.1 with the credit window full no further slice is taken', WindowFull Or (EventsSent * 60000 <= MonitorCreditWindowBytes));
  Carrier.ClearSent;
  Ping := EncodeCommandTicks(mmkPing, 'ping-credit', 77);
  Carrier.DeliverJson(Ping);
  Session.DrainOutbound;
  Check('7.1 state and control still go when the window is full', SentHasType('pong'));
  Check('7.1 the host still answers ping when the client is not acknowledging', SentHasType('pong'));

  DroppedBefore := Session.FramesDropped;
  Carrier.ClearSent;
  For I := 1 To 5 Do
    Session.TryQueueHostJson('{"v":3,"id":"bulk-' + IntToStr(I) + '","type":"image_data","payload":{"image_id":"img-' +
      IntToStr(I) + '"}}');
  Carrier.DeliverJson('{"v":3,"id":"r-4","type":"resume","payload":{"conversation_id":"conversation-1",' +
    '"stream_id":"aa11bb22cc33dd44ee55ff6677889900","seq":1,"commands":[]}}');
  Session.DrainOutbound;
  Check('7.1 a second resume discards unsent frames of the previous generation', Not SentHasType('image_data'));
  Check('7.1 discarding a generation does not count the frames as dropped', Session.FramesDropped = DroppedBefore);

  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"bg-1","type":"block_get","payload":{"conversation_id":"conversation-1",' +
    '"block_id":"b-1","offset":0,"prefix_hash":"cbf29ce484222325","revision":1}}');
  Session.ObserveTurn(MakeTurn('replaced', True, ''));
  Carrier.DeliverJson('{"v":3,"id":"bg-2","type":"block_get","payload":{"conversation_id":"conversation-1",' +
    '"block_id":"b-1","offset":0,"prefix_hash":"cbf29ce484222325","revision":1}}');
  Session.DrainOutbound;
  WindowFull := False;
  For I := 0 To Carrier.SentCount - 1 Do
    If Pos('revision_changed', Carrier.SentJson(I)) > 0 Then
      WindowFull := True;
  Check('7.1 a fetch for a revision that has been replaced is revision_changed', WindowFull);
End;

Procedure PrepareSettings;
Var
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-grain-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
End;

Begin
  FailCount := 0;
  Carrier := Nil;
  CarrierRef := Nil;
  Session := Nil;
  SettingsRoot := '';
  Try
    Try
      Try
        TestAppendSlices;
      Except
        On E: Exception Do
          Begin
            WriteLn('FAIL 7.1 append slices raised ', E.Message);
            Inc(FailCount);
          End;
      End;
      Try
        TestNewBlockBody;
      Except
        On E: Exception Do
          Begin
            WriteLn('FAIL 7.1 new block raised ', E.Message);
            Inc(FailCount);
          End;
      End;
      PrepareSettings;
      Carrier := TMonitorMemoryCarrier.Create;
      CarrierRef := Carrier;
      Session := TMonitorSession.Create;
      Session.AttachCarrier(CarrierRef);
      Session.StartListening('127.0.0.1', 0, ErrorText);
      Try
        GoLive;
        TestPriority;
        TestResumeAndBaseline;
        TestCreditAndGeneration;
      Except
        On E: Exception Do
          Begin
            WriteLn('FAIL 7.1 session grain raised ', E.Message);
            Inc(FailCount);
          End;
      End;
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    FreeAndNil(Session);
    Carrier := Nil;
    CarrierRef := Nil;
    If SettingsRoot <> '' Then
      Begin
        SetWorkflowSettingsDirectory('');
        RemoveDir(ExcludeTrailingPathDelimiter(SettingsRoot));
      End;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorGrainTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorGrainTest test(s) failed.');
      Halt(1);
    End;
End.