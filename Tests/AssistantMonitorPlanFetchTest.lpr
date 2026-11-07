Program AssistantMonitorPlanFetchTest;

{ plan_get streams the file on disk, including past 4 MiB (c) 2026 Michell Computing.

  Item 5.4. The worker is polled from the session. The model cap is not this path.
  Plan item 2.4 of Documents/Plan-20261105-130659.md: plan_data frames, which fpjson writes, leave on the bulk lane. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, AssistantMonitorLinkStubs, AssistantMonitorCodec, AssistantMonitorFrames,
  AssistantMonitorCarrier, AssistantMonitorSession, AssistantPlanDocument, AssistantSessionObserve, AssistantMonitorSettings,
  AssistantMonitorOutbox, AssistantMonitorSync, WorkflowSettings;

Const
  SliceBound = 24 * 1024;
  OverCap = 4 * 1024 * 1024 + 128;

Var
  FailCount: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;
  SettingsRoot, ProjectRoot: String;
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

Function Payload(Const Json: String): TJSONObject;
Var
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Result := Nil;
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
  If Root.Find('payload') Is TJSONObject Then
    Result := TJSONObject(Root.Find('payload').Clone);
  Data.Free;
End;

Function SentHas(Const Needle: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 0 To Carrier.SentCount - 1 Do
    If Pos(Needle, Carrier.SentJson(Index)) > 0 Then
      Exit(True);
End;

Function WaitSent(Const Needle: String; TimeoutMs: Integer): Boolean;
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  Repeat
    Session.NoteTime(GetTickCount64);
    If SentHas(Needle) Then
      Exit(True);
    Sleep(2);
  Until GetTickCount64 - Start >= TimeoutMs;
  Result := False;
End;

Procedure GoLive;
Var
  Spare: TMonitorFrame;
Begin
  Session.NoteSocketClosed;
  Check('5.4 handshake accepted', Session.AcceptHandshake(Spare, True));
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorHello('hello', 'Phone', '1', ''));
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorPair('pair', '', ''));
  Check('5.4 paired', Session.State = mssLive);
End;

Procedure WriteBytes(Const FileName: String; Const Body: RawByteString);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    If Body <> '' Then
      Stream.WriteBuffer(Body[1], Length(Body));
  Finally
    Stream.Free;
  End;
End;

Function MakeLarge(Const FileName: String): RawByteString;
Var
  Index: Integer;
  Euro: RawByteString;
Begin
  Euro := #$E2#$82#$AC;
  SetLength(Result, OverCap);
  For Index := 1 To OverCap Do
    Result[Index] := 'a';
  { A 24 KiB cut lands inside this character unless the host backs up. }
  If SliceBound <= OverCap - 3 Then
    Begin
      Result[SliceBound] := Euro[1];
      Result[SliceBound + 1] := Euro[2];
      Result[SliceBound + 2] := Euro[3];
    End;
  Result[OverCap] := 'Z';
  WriteBytes(FileName, Result);
End;

Function CollectPlan(Const RequestId: String; TimeoutMs: Integer; Out Body: RawByteString; Out Revision: String;
  Out Total: Int64; Out SawLast: Boolean): Boolean;
Var
  Start: QWord;
  Index, Seen: Integer;
  Item: TJSONObject;
  Text: RawByteString;
  Offset, Next: Int64;
  RefId: String;
Begin
  Result := False;
  Body := '';
  Revision := '';
  Total := -1;
  SawLast := False;
  Next := 0;
  Seen := 0;
  Start := GetTickCount64;
  While GetTickCount64 - Start < TimeoutMs Do
    Begin
      Session.NoteTime(GetTickCount64);
      While Seen < Carrier.SentCount Do
        Begin
          Index := Seen;
          Inc(Seen);
          If JsonTypeName(Carrier.SentJson(Index)) <> 'plan_data' Then
            Continue;
          Item := Payload(Carrier.SentJson(Index));
          If Not Assigned(Item) Then
            Continue;
          Try
            RefId := Item.Get('ref', '');
            If RefId <> RequestId Then
              Continue;
            If Revision = '' Then
              Revision := Item.Get('revision', '');
            If Item.Get('revision', '') <> Revision Then
              Exit;
            Offset := Item.Get('offset', -1);
            If Offset <> Next Then
              Exit;
            Text := Item.Get('text', '');
            SetCodePage(Text, CP_UTF8, False);
            Body := Body + Text;
            Next := Offset + Length(Text);
            Total := Item.Get('total_bytes', -1);
            If Item.Get('last', False) Then
              Begin
                SawLast := True;
                Result := Next = Total;
                Exit;
              End;
          Finally
            Item.Free;
          End;
        End;
      If SawLast Then
        Exit;
      Sleep(1);
    End;
End;

Procedure TestMissingAndResume;
Var
  FileName, Revision: String;
  Body: RawByteString;
  Total: Int64;
  SawLast: Boolean;
Begin
  FileName := IncludeTrailingPathDelimiter(ProjectRoot) + 'small.md';
  WriteBytes(FileName, 'hello plan');
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-miss","type":"plan_get","payload":{"path":"missing.md","offset":0,"revision":""}}');
  Check('5.4 a missing plan is not_found', WaitSent('not_found', 3000));
  Check('5.4 a missing plan is not a size sentence', Not SentHas('too large to cache') And Not SentHas('on the desktop'));

  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-small","type":"plan_get","payload":{"path":"small.md","offset":0,"revision":""}}');
  Check('5.4 a small plan streams to last', CollectPlan('pg-small', 5000, Body, Revision, Total, SawLast) And SawLast);
  Check('5.4 a small plan is the file', Body = 'hello plan');
  Check('5.4 plan_data revision is the whole file', Revision = AssistantPlanHashFile(FileName));
  Check('5.4 plan_data names the request', SentHas('pg-small'));

  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-stale","type":"plan_get","payload":{"path":"small.md","offset":4,"revision":"0000000000000000"}}');
  Check('5.4 a stale resume is revision_changed', WaitSent('revision_changed', 3000));
  Check('5.4 a stale resume keeps no body', Not SentHas('plan_data'));
End;

Procedure TestWholeFile;
Var
  FileName, Revision: String;
  Expected, Body: RawByteString;
  Total: Int64;
  SawLast: Boolean;
Begin
  FileName := IncludeTrailingPathDelimiter(ProjectRoot) + 'large.md';
  Expected := MakeLarge(FileName);
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-large","type":"plan_get","payload":{"path":"large.md","offset":0,"revision":""}}');
  Check('5.4 a plan over 4 MiB streams to last', CollectPlan('pg-large', 20000, Body, Revision, Total, SawLast) And SawLast);
  Check('5.4 total_bytes is the whole file', Total = Length(Expected));
  Check('5.4 the body is not cut at 4 MiB', Length(Body) = Length(Expected));
  Check('5.4 the body matches the file', Body = Expected);
  Check('5.4 the revision is the full-file hash', Revision = AssistantPlanHashFile(FileName));
  Check('5.4 a large plan is not replaced by a sentence', Not SentHas('too large to cache') And
    Not SentHas('The rest of the plan is on the desktop'));
End;

Procedure TestSameSizeEdit;
Var
  FileName: String;
  Writer: TFileStream;
  Bytes: RawByteString;
Begin
  FileName := IncludeTrailingPathDelimiter(ProjectRoot) + 'edit.md';
  WriteBytes(FileName, StringOfChar('Q', SliceBound * 3));
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-edit","type":"plan_get","payload":{"path":"edit.md","offset":0,"revision":""}}');
  Check('5.7 same-size edit starts streaming', WaitSent('pg-edit', 3000) And SentHas('plan_data'));
  { No cache notification: block hashes must catch an edit even within FileAge resolution. }
  Bytes := StringOfChar('Z', SliceBound * 3);
  Writer := TFileStream.Create(FileName, fmOpenWrite Or fmShareDenyNone);
  Try
    Writer.WriteBuffer(Bytes[1], Length(Bytes));
  Finally
    Writer.Free;
  End;
  Check('5.7 same-size edit is revision_changed', WaitSent('revision_changed', 3000));
  Check('5.7 same-size edit never mixes new bytes', Not SentHas(StringOfChar('Z', 32)));
End;

Procedure TestReplacement;
Var
  FileName: String;
  DataCount: Integer;
  SawChanged: Boolean;
Begin
  FileName := IncludeTrailingPathDelimiter(ProjectRoot) + 'swap.md';
  WriteBytes(FileName, StringOfChar('Q', SliceBound * 3));
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"pg-swap","type":"plan_get","payload":{"path":"swap.md","offset":0,"revision":""}}');
  DataCount := 0;
  If WaitSent('pg-swap', 3000) And SentHas('plan_data') Then
    DataCount := 1;
  Check('5.4 replacement starts from the file', DataCount = 1);
  Session.NotePlanCachedRevision('swap.md', 'ffffffffffffffff');
  WriteBytes(FileName, 'NEWPLAN-SHOULD-NOT-MIX');
  SawChanged := WaitSent('revision_changed', 3000);
  Check('5.4 a replacement is revision_changed', SawChanged);
  Check('5.4 a replacement keeps no mixed bytes', Not SentHas('NEWPLAN-SHOULD-NOT-MIX'));
End;

{ Plan item 2.4. fpjson AsJSON writes "type" : "plan_data", with spaces around the colon. The classifier must
  still see the type, and a state key in the payload, as it does for a hand-written frame. }
Procedure TestFpjsonFramesClassify;
Var
  Root, Body: TJSONObject;
  Json, StateKey: String;
  Lane: TMonitorSyncLane;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('v', 3);
    Root.Add('id', 'pf-1');
    Root.Add('type', 'plan_data');
    Body := TJSONObject.Create;
    Body.Add('ref', 'pg-1');
    Body.Add('text', 'plan');
    Root.Add('payload', Body);
    Json := Root.AsJSON;
  Finally
    Root.Free;
  End;
  Check('2.4 fpjson writes a space before the colon', Pos('"type" : "plan_data"', Json) > 0);
  Check('2.4 an fpjson plan_data frame is bulk', MonitorSyncClassify(Json, Lane, StateKey) And (Lane = mslBulk));
  Check('2.4 a spaced state frame names its key', MonitorSyncClassify(
    '{"v" : 3, "id" : "s1", "type" : "state", "payload" : {"key" : "plan", "value" : {}}}', Lane, StateKey) And
    (Lane = mslState) And (StateKey = 'plan'));
  Check('2.4 a payload field called type is not the frame type', MonitorSyncClassify(
    '{"v":3,"id":"e1","type":"error","payload":{"type":"plan_data"}}', Lane, StateKey) = False);
  Check('2.4 text that is not JSON is not classified', Not MonitorSyncClassify('{"type" : "plan_data"', Lane, StateKey));
End;

{ Plan item 2.4. With the link pulling the outbox, every plan_data frame of a fetch leaves from the bulk lane. }
Procedure TestPlanDataOnBulkLane;
Var
  FileName: String;
  Bytes: RawByteString;
  Lane: TMonitorOutboxLane;
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Item: TJSONObject;
  Start: QWord;
  DataCount, OffLane: Integer;
  SawLast: Boolean;
Begin
  FileName := IncludeTrailingPathDelimiter(ProjectRoot) + 'lanes.md';
  WriteBytes(FileName, StringOfChar('L', SliceBound * 3));
  DataCount := 0;
  OffLane := 0;
  SawLast := False;
  Session.NoteLinkPulls(True);
  Try
    Carrier.ClearSent;
    Carrier.DeliverJson('{"v":3,"id":"pg-lane","type":"plan_get","payload":{"path":"lanes.md","offset":0,"revision":""}}');
    Start := GetTickCount64;
    While (Not SawLast) And (GetTickCount64 - Start < 10000) Do
      Begin
        If Not Session.TakeOutboundFrameWithLane(Bytes, Lane) Then
          Begin
            Sleep(1);
            Continue;
          End;
        If Not TryDecodeMonitorFrame(Bytes, Frame, Status) Then
          Continue;
        If JsonTypeName(Frame.Json) <> 'plan_data' Then
          Continue;
        Item := Payload(Frame.Json);
        If Not Assigned(Item) Then
          Continue;
        Try
          If Item.Get('ref', '') <> 'pg-lane' Then
            Continue;
          Inc(DataCount);
          If Lane <> molBulk Then
            Inc(OffLane);
          SawLast := Item.Get('last', False);
        Finally
          Item.Free;
        End;
      End;
  Finally
    Session.NoteLinkPulls(False);
  End;
  Check('2.4 the fetch reaches its last slice through the outbox', SawLast);
  Check('2.4 a 72 KiB plan is more than one slice', DataCount > 1);
  Check('2.4 every plan_data frame leaves from the bulk lane', (DataCount > 0) And (OffLane = 0));
End;

Procedure Prepare;
Var
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-plan-fetch-' + GUIDToString(Guid);
  ProjectRoot := SettingsRoot + 'project';
  If Not ForceDirectories(ProjectRoot) Then
    Raise Exception.Create('Could not create ' + ProjectRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
End;

Begin
  FailCount := 0;
  Carrier := Nil;
  CarrierRef := Nil;
  Session := Nil;
  SettingsRoot := '';
  ProjectRoot := '';
  Try
    Try
      Prepare;
      TestFpjsonFramesClassify;
      Carrier := TMonitorMemoryCarrier.Create;
      CarrierRef := Carrier;
      Session := TMonitorSession.Create;
      Session.AttachCarrier(CarrierRef);
      Session.StartListening('127.0.0.1', 0, ErrorText);
      Session.BeginMirrorEpoch('aa11bb22cc33dd44ee55ff6677889900', 'conversation-1', ProjectRoot, 'Plan');
      GoLive;
      TestMissingAndResume;
      TestReplacement;
      TestSameSizeEdit;
      TestWholeFile;
      TestPlanDataOnBulkLane;
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
    If ProjectRoot <> '' Then
      Begin
        DeleteFile(IncludeTrailingPathDelimiter(ProjectRoot) + 'small.md');
        DeleteFile(IncludeTrailingPathDelimiter(ProjectRoot) + 'large.md');
        DeleteFile(IncludeTrailingPathDelimiter(ProjectRoot) + 'swap.md');
        DeleteFile(IncludeTrailingPathDelimiter(ProjectRoot) + 'lanes.md');
        RemoveDir(ProjectRoot);
      End;
    If SettingsRoot <> '' Then
      Begin
        SetWorkflowSettingsDirectory('');
        RemoveDir(ExcludeTrailingPathDelimiter(SettingsRoot));
      End;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorPlanFetchTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorPlanFetchTest test(s) failed.');
      Halt(1);
    End;
End.
