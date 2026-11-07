Program AssistantMonitorCodecTest;

{ Console round-trip of the monitor catalogue and LAM1 frames (c) 2026 Michell Computing.

  No Interfaces unit. The runner writes this binary with a temporary -FU and -FE,
  never under Source/. -dump writes lowercase hex fixtures under
  Tests/Fixtures/monitor-frames/. Whitespace in those files is insignificant.
  -dump is a test flag, not a product switch. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, AssistantMonitorLinkStubs,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorOutbox, AssistantSessionObserve;

Type
  TWireSample = Record
    Name: String;
    Kind: TMonitorMessageKind;
    Json: String;
  End;

Var
  FailCount: Integer;
  DumpFixtures: Boolean;
  Samples: Array Of TWireSample;
  ImageBytes: TBytes;

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

Function FixtureDirectory: String;
Begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + 'monitor-frames';
End;

Function ReadText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExists(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure AddSample(Const Name: String; Kind: TMonitorMessageKind; Const Json: String);
Begin
  SetLength(Samples, Length(Samples) + 1);
  Samples[High(Samples)].Name := Name;
  Samples[High(Samples)].Kind := Kind;
  Samples[High(Samples)].Json := Json;
End;

Function PayloadObject(Const Json: String; Out Data: TJSONData; Out Payload: TJSONObject): Boolean;
Var
  Root: TJSONObject;
Begin
  Result := False;
  Data := Nil;
  Payload := Nil;
  Try
    Data := GetJSON(Json);
  Except
    Exit;
  End;
  If Not (Data Is TJSONObject) Then
    Exit;
  Root := TJSONObject(Data);
  If Not (Root.Find('payload') Is TJSONObject) Then
    Exit;
  Payload := TJSONObject(Root.Find('payload'));
  Result := True;
End;

Function PayloadIsEmpty(Const Json: String): Boolean;
Var
  Data: TJSONData;
  Payload: TJSONObject;
Begin
  Result := False;
  If Not PayloadObject(Json, Data, Payload) Then
    Exit;
  Try
    Result := Payload.Count = 0;
  Finally
    Data.Free;
  End;
End;

Function BigEndianLength(Const Bytes: RawByteString): Cardinal;
Begin
  Result := 0;
  If Length(Bytes) < MonitorFrameHeaderSize Then
    Exit;
  Result := (Cardinal(Ord(Bytes[9])) Shl 24) Or (Cardinal(Ord(Bytes[10])) Shl 16) Or
    (Cardinal(Ord(Bytes[11])) Shl 8) Or Cardinal(Ord(Bytes[12]));
End;

Procedure CheckLam1(Const Title: String; Const Bytes: RawByteString; PayloadLen: Integer);
Begin
  Check(Title + ' LAM1', (Length(Bytes) >= 4) And (Copy(Bytes, 1, 4) = 'LAM1'));
  Check(Title + ' version byte', (Length(Bytes) >= 5) And (Ord(Bytes[5]) = MonitorFrameVersion));
  Check(Title + ' flags zero', (Length(Bytes) >= 6) And (Ord(Bytes[6]) = 0));
  Check(Title + ' reserved zero', (Length(Bytes) >= 8) And (Ord(Bytes[7]) = 0) And (Ord(Bytes[8]) = 0));
  { Read the length as big-endian bytes. Do not call ntohl, so a host-endian store fails here. }
  Check(Title + ' big-endian length', BigEndianLength(Bytes) = Cardinal(PayloadLen));
  Check(Title + ' length byte 0', Ord(Bytes[9]) = (PayloadLen Shr 24) And $FF);
  Check(Title + ' length byte 1', Ord(Bytes[10]) = (PayloadLen Shr 16) And $FF);
  Check(Title + ' length byte 2', Ord(Bytes[11]) = (PayloadLen Shr 8) And $FF);
  Check(Title + ' length byte 3', Ord(Bytes[12]) = PayloadLen And $FF);
  If PayloadLen > 255 Then
    Check(Title + ' length is not little-endian', Ord(Bytes[9]) <> (PayloadLen And $FF));
End;

Function HexEncode(Const Bytes: RawByteString): String;
Const
  Digits = '0123456789abcdef';
Var
  I, At: Integer;
Begin
  Result := '';
  SetLength(Result, Length(Bytes) * 2 + (Length(Bytes) + 31) Div 32);
  At := 1;
  For I := 1 To Length(Bytes) Do
    Begin
      Result[At] := Digits[(Ord(Bytes[I]) Shr 4) + 1];
      Result[At + 1] := Digits[(Ord(Bytes[I]) And $0F) + 1];
      Inc(At, 2);
      If (I Mod 32 = 0) Or (I = Length(Bytes)) Then
        Begin
          Result[At] := #10;
          Inc(At);
        End;
    End;
  SetLength(Result, At - 1);
End;

Function HexValue(C: Char): Integer;
Begin
  Result := -1;
  If (C >= '0') And (C <= '9') Then
    Result := Ord(C) - Ord('0')
  Else If (C >= 'a') And (C <= 'f') Then
    Result := Ord(C) - Ord('a') + 10
  Else If (C >= 'A') And (C <= 'F') Then
    Result := Ord(C) - Ord('A') + 10;
End;

Function HexDecode(Const Text: String; Out Bytes: RawByteString): Boolean;
Var
  I, Value, HighNibble, Count: Integer;
  C: Char;
Begin
  Result := False;
  Bytes := '';
  HighNibble := -1;
  Count := 0;
  For I := 1 To Length(Text) Do
    Begin
      C := Text[I];
      If (C = ' ') Or (C = #9) Or (C = #10) Or (C = #13) Then
        Continue;
      Value := HexValue(C);
      If Value < 0 Then
        Exit;
      If HighNibble < 0 Then
        HighNibble := Value
      Else
        Begin
          Inc(Count);
          SetLength(Bytes, Count);
          Bytes[Count] := Chr((HighNibble Shl 4) Or Value);
          HighNibble := -1;
        End;
    End;
  Result := HighNibble < 0;
End;

Function FixturePath(Const Name: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(FixtureDirectory) + Name + '.hex';
End;

Procedure WriteFixture(Const Name: String; Const Bytes: RawByteString);
Var
  Stream: TFileStream;
  Text: RawByteString;
Begin
  If Not ForceDirectories(FixtureDirectory) Then
    Begin
      Check(Name + ' fixture directory', False);
      Exit;
    End;
  Text := HexEncode(Bytes);
  Stream := TFileStream.Create(FixturePath(Name), fmCreate);
  Try
    If Text <> '' Then
      Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Procedure CheckFixture(Const Name: String; Const Bytes: RawByteString);
Var
  Stored: RawByteString;
Begin
  If Not FileExists(FixturePath(Name)) Then
    Begin
      Check(Name + ' fixture exists', False);
      Exit;
    End;
  If Not HexDecode(ReadText(FixturePath(Name)), Stored) Then
    Begin
      Check(Name + ' fixture hex', False);
      Exit;
    End;
  Check(Name + ' fixture matches', Stored = Bytes);
End;

Function Header(Version: Byte; PayloadLen: Cardinal): RawByteString;
Begin
  SetLength(Result, MonitorFrameHeaderSize);
  Result[1] := 'L';
  Result[2] := 'A';
  Result[3] := 'M';
  Result[4] := '1';
  Result[5] := Chr(Version);
  Result[6] := Chr(0);
  Result[7] := Chr(0);
  Result[8] := Chr(0);
  Result[9] := Chr((PayloadLen Shr 24) And $FF);
  Result[10] := Chr((PayloadLen Shr 16) And $FF);
  Result[11] := Chr((PayloadLen Shr 8) And $FF);
  Result[12] := Chr(PayloadLen And $FF);
End;

Procedure FillView(Out View: TAssistantMonitorView);
Begin
  View.Available := True;
  View.Busy := False;
  View.Sending := False;
  View.ModeLocked := False;
  View.PlanRunning := False;
  View.Mode := 'build';
  View.Phase := 'idle';
  View.StatusText := 'Ready';
  View.ElapsedMs := 0;
  View.Model := 'grok-test';
  View.Backend := 'native';
  View.SignedIn := True;
  View.ApprovalCaption := 'Ask';
  View.Effort := 'high';
  View.Skill := '';
  View.ContextText := 'ctx';
  View.UsageCaption := '';
  View.UsageHint := '';
  View.TargetKind := 'project';
  View.TargetDisplay := 'LazWorkflow';
  View.TargetRoot := '/work/LazWorkflow';
  View.PlanPath := 'Documents/Plan.md';
  View.PlanTitle := 'Monitor plan';
  View.CanSend := True;
  View.CanSteer := False;
  View.CanStop := False;
  View.CanChangeMode := True;
  View.RemoteApproval := False;
  View.ErrorText := '';
End;

Function SampleBlock: TAssistantMonitorBlock;
Begin
  Result.Kind := 'answer';
  Result.BlockId := 'block-1';
  Result.Title := 'Answer';
  Result.ToolName := '';
  Result.ToolId := '';
  Result.Body := 'Noted.';
  Result.Running := False;
  Result.Ok := True;
  Result.DurationMs := 12;
  SetLength(Result.Images, 0);
End;

Function SampleTurn: TAssistantMonitorTurn;
Begin
  Result.TurnIndex := 3;
  Result.Id := 'turn-3';
  Result.Mode := 'build';
  Result.Prompt := 'Show the frame.';
  Result.Thinking := '';
  Result.Response := 'Noted.';
  Result.ErrorText := '';
  Result.CreatedAt := '2026-10-19T12:00:00Z';
  Result.DurationMs := 12;
  Result.PromptPreview := 'Show the frame.';
  Result.Live := True;
  SetLength(Result.Blocks, 1);
  Result.Blocks[0] := SampleBlock;
  SetLength(Result.Images, 0);
End;

Function SamplePlanRow: TAssistantMonitorPlanRow;
Begin
  Result.Index := 1;
  Result.Level := 2;
  Result.Title := 'Codec tests';
  Result.ParentTitle := 'Session core';
  Result.Status := 'in progress';
  Result.Actionable := True;
End;

Function SampleTaskRow: TAssistantMonitorTaskRow;
Begin
  Result.Id := 'review-unit';
  Result.Title := 'Review unit';
  Result.Summary := 'Read the diff.';
  Result.Mode := 'build';
  Result.Kind := 'prompt';
  Result.Scope := 'project';
  Result.CompileFirst := False;
  Result.Enabled := True;
  Result.NeedsNote := False;
End;

Procedure AddImageSamples;
Var
  Messages: TStringArray;
  Reason: String;
  I, Decoded: Integer;
  Image: TMonitorImageData;
  Message: TMonitorMessage;
  ErrorText: String;
  Raw: RawByteString;
  Joined: TBytes;
Begin
  Messages := Nil;
  SetLength(ImageBytes, MonitorMaxImagePartBytes + 16);
  For I := 0 To High(ImageBytes) Do
    ImageBytes[I] := Byte((I * 17 + 3) And $FF);
  Check('image parts encode', TryEncodeMonitorImageData('image-parts', 'tile-1', 'image/png', 8, 8, 4, ImageBytes, False, False,
    Messages, Reason));
  Check('image part count', Length(Messages) = 2);
  If Length(Messages) <> 2 Then
    Exit;
  SetLength(Joined, 0);
  For I := 0 To 1 Do
    Begin
      Check('image part envelope ' + IntToStr(I + 1), TryDecodeMonitorEnvelope(Messages[I], Message, ErrorText) And
        (Message.Kind = mmkImageData));
      Check('image part payload ' + IntToStr(I + 1), DecodeMonitorImageData(Message.PayloadJson, Image, Decoded));
      Check('image part index ' + IntToStr(I + 1), (Image.Part = I + 1) And (Image.PartCount = 2) And (Image.Revision = 4));
      Raw := DecodeMonitorImageBytes(Image.BytesBase64);
      Check('image part bytes ' + IntToStr(I + 1), Length(Raw) = Decoded);
      SetLength(Joined, Length(Joined) + Length(Raw));
      If Length(Raw) > 0 Then
        Move(Raw[1], Joined[Length(Joined) - Length(Raw)], Length(Raw));
      AddSample('image-data-part-' + IntToStr(I + 1), mmkImageData, Messages[I]);
    End;
  Check('image parts reassemble', (Length(Joined) = Length(ImageBytes)) And
    CompareMem(@Joined[0], @ImageBytes[0], Length(ImageBytes)));
End;

Procedure AddTargetSamples;
Var
  Paths, Captions: TStringList;
Begin
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Paths.Add('');
    Captions.Add('Current Project');
    Paths.Add('/work/Other');
    Captions.Add('Other');
    AddSample('targets', mmkTargets, EncodeMonitorTargets('targets', '', Paths, Captions));
  Finally
    Captions.Free;
    Paths.Free;
  End;
  AddSample('select-target', mmkSelectTarget, EncodeMonitorPath(mmkSelectTarget, 'select-target', ''));
End;

Procedure AddConversationSamples;
Var
  Ids, Titles: TStringList;
Begin
  Ids := TStringList.Create;
  Titles := TStringList.Create;
  Try
    Ids.Add('');
    Titles.Add('Current — hello');
    Ids.Add('20261019T120000000');
    Titles.Add('Older (2)');
    AddSample('conversations', mmkConversations, EncodeMonitorConversations('conversations', '', Ids, Titles, True));
  Finally
    Titles.Free;
    Ids.Free;
  End;
  AddSample('select-conversation', mmkSelectConversation, EncodeMonitorSelectConversation('select-conversation', ''));
End;

Procedure AddSamplingSamples;
Var
  Ids, Captions: TStringList;
Begin
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Ids.Add('grok-4');
    Captions.Add('grok-4 — 256k context');
    Ids.Add('grok-3');
    Captions.Add('grok-3');
    AddSample('models', mmkModels, EncodeMonitorModels('models', 'grok-4', 'grok', '', Ids, Captions));
    Ids.Clear;
    Captions.Clear;
    Ids.Add('');
    Captions.Add('Model default');
    Ids.Add('high');
    Captions.Add('High');
    AddSample('reasoning', mmkReasoning, EncodeMonitorReasoning('reasoning', '', 'This connection does not set an effort level.', Ids, Captions));
    Ids.Clear;
    Captions.Clear;
    Ids.Add('ask');
    Captions.Add('Ask — confirm each write/compile');
    Ids.Add('auto');
    Captions.Add('Auto — allow project tools');
    Ids.Add('always');
    Captions.Add('Always — never prompt (like Build always-approve)');
    AddSample('permissions', mmkPermissions, EncodeMonitorPermissions('permissions', 'ask', 'grok', '', Ids, Captions));
  Finally
    Captions.Free;
    Ids.Free;
  End;
  AddSample('set-model', mmkSetModel, EncodeMonitorSetModel('set-model', 'grok-4'));
  AddSample('set-reasoning', mmkSetReasoning, EncodeMonitorSetReasoning('set-reasoning', ''));
  AddSample('set-permissions', mmkSetPermissions, EncodeMonitorSetPermissions('set-permissions', 'auto'));
End;

{ One refused reply with a reason, so the optional field is in the stored frame. }
Function SampleCommandStates: String;
Var
  Replies: Array Of TMonitorCommandStateReply;
Begin
  SetLength(Replies, 1);
  Replies[0].Ref := 'steer-1';
  Replies[0].State := 'refused';
  Replies[0].Reason := 'busy';
  Replies[0].Text := '';
  Result := EncodeMonitorCommandStates('command-states', Replies);
End;

Procedure BuildSamples;
Var
  View: TAssistantMonitorView;
  Turn: TAssistantMonitorTurn;
  Snapshot: TMonitorSnapshot;
  Transcript: TMonitorTranscript;
  Patch: TMonitorPatch;
  Catchup: TMonitorCatchup;
  HelloOk: TMonitorHelloOk;
  Notice: TAssistantApprovalNotice;
  PlanRows: Array[0..0] Of TAssistantMonitorPlanRow;
  TaskRows: Array[0..0] Of TAssistantMonitorTaskRow;
  Payload: TJSONObject;
  Json, ErrorJson: String;
  Tiny: TBytes;
  Messages: TStringArray;
  Reason: String;
Begin
  SetLength(Samples, 0);
  AddSample('hello-first', mmkHello, EncodeMonitorHello('hello-first', 'Phone', '1', ''));
  AddSample('hello-reconnect', mmkHello, EncodeMonitorHello('hello-reconnect', 'Phone', '1', 'client-1'));
  AddSample('pair', mmkPair, EncodeMonitorPair('pair', 'ABCDEFGHJK', 'ab12cd34'));
  AddSample('pair-ok', mmkPairOk, EncodeMonitorPairOk('pair-ok', 'client-1', 'token-1'));
  HelloOk.Nonce := '00112233445566778899aabbccddeeff';
  HelloOk.ServerName := 'LazAssistantMonitor';
  HelloOk.Epoch := 'ab12';
  HelloOk.Cursor := 0;
  HelloOk.ConversationId := 'current';
  HelloOk.ProjectRoot := '/work/LazWorkflow';
  HelloOk.Title := 'Current';
  HelloOk.HostId := '';
  AddSample('hello-ok', mmkHelloOk, EncodeMonitorHelloOk('hello-ok', HelloOk));
  AddSample('auth', mmkAuth, EncodeMonitorAuth('auth', 'client-1', 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899'));
  AddSample('rejected', mmkRejected, EncodeMonitorRejected('rejected', 'busy', 1, 1));
  AddSample('bye', mmkBye, EncodeMonitorBye('bye', 'revoked'));
  FillView(View);
  Snapshot.View := View;
  SetLength(Snapshot.StoredTurns, 1);
  Turn := SampleTurn;
  Turn.Live := False;
  Turn.TurnIndex := 2;
  Turn.Id := 'turn-2';
  Snapshot.StoredTurns[0] := Turn;
  Snapshot.Live := SampleTurn;
  Snapshot.HasLive := True;
  Snapshot.PlanPath := 'Documents/Plan.md';
  Snapshot.PlanTitle := 'Monitor plan';
  Snapshot.PlanRunning := False;
  SetLength(Snapshot.PlanRows, 1);
  Snapshot.PlanRows[0] := SamplePlanRow;
  SetLength(Snapshot.TaskRows, 1);
  Snapshot.TaskRows[0] := SampleTaskRow;
  Notice.Active := False;
  Notice.ToolId := '';
  Notice.ToolName := '';
  Notice.Summary := '';
  Notice.ModeCaption := '';
  Notice.DecisionsAccepted := False;
  Notice.Reason := '';
  Snapshot.Approval := Notice;
  AddSample('resume', mmkResume, EncodeMonitorResume('resume', 'abc123', 4));
  Patch := Default(TMonitorPatch);
  { The golden fixture carries signed_in=true; initialise it explicitly for heap-check builds too. }
  Patch.SignedIn := True;
  Patch.Epoch := 'abc123';
  Patch.Cursor := 4;
  Patch.TurnIndex := 3;
  Patch.TurnId := 'turn-3';
  Patch.Busy := True;
  Patch.Sending := True;
  Patch.PlanRunning := False;
  Patch.Phase := 'streaming';
  Patch.CanSend := False;
  Patch.CanSteer := True;
  Patch.CanStop := True;
  Patch.ElapsedMs := 1200;
  Patch.Part := 1;
  Patch.PartCount := 1;
  SetLength(Patch.Blocks, 1);
  Patch.Blocks[0] := SampleBlock;
  AddSample('patch', mmkPatch, EncodeMonitorPatch('patch', Patch));
  Catchup.Mode := mcmSnapshot;
  Catchup.Epoch := 'abc123';
  Catchup.Cursor := 4;
  Catchup.ConversationId := 'current';
  Catchup.ProjectRoot := '/work/LazWorkflow';
  Catchup.Title := 'Monitor plan';
  Catchup.Snapshot := Snapshot;
  Catchup.HasSnapshot := True;
  SetLength(Catchup.Patches, 0);
  AddSample('catchup-snapshot', mmkCatchup, EncodeMonitorCatchup('catchup-snapshot', Catchup));
  Catchup.Mode := mcmEvents;
  Catchup.HasSnapshot := False;
  SetLength(Catchup.Patches, 1);
  Catchup.Patches[0] := Patch;
  AddSample('catchup-events', mmkCatchup, EncodeMonitorCatchup('catchup-events', Catchup));
  AddSample('conversation-closed', mmkConversationClosed,
    EncodeMonitorConversationClosed('conversation-closed', 'abc123', 4, 'conversation-20261019T120000000', 'Monitor plan'));
  AddSample('refresh', mmkRefresh, EncodeMonitorEmpty(mmkRefresh, 'refresh'));
  Transcript.TurnIndex := 3;
  Transcript.Revision := 2;
  Transcript.Phase := 'streaming';
  Transcript.StatusText := 'Writing';
  Transcript.DurationMs := 12;
  Transcript.Part := 1;
  Transcript.PartCount := 1;
  SetLength(Transcript.Blocks, 1);
  Transcript.Blocks[0] := SampleBlock;
  SetLength(Transcript.BlockPart, 1);
  SetLength(Transcript.BlockPartCount, 1);
  Transcript.BlockPart[0] := 1;
  Transcript.BlockPartCount[0] := 1;
  AddSample('turn', mmkTurn, EncodeMonitorTurnRequest('turn', 3));
  AddSample('snapshot-page', mmkSnapshotPage, '{"v":2,"id":"snapshot-page","type":"snapshot_page","payload":{"conversation_id":"c1","stream_id":"abc","seq":1,"turn":{"turn_id":"t1","turn_index":0,"blocks":[]}}}');
  AddSample('chunk', mmkChunk, '{"v":2,"id":"chunk-1","type":"chunk","payload":{"item_id":"img-1","part":1,"part_count":1,"item_type":"image_data","data":"{}"}}');
  AddSample('command-state', mmkCommandState, EncodeMonitorCommandState('command-state', 'send-1', 'done', '', 'Sent.'));
  AddSample('command-states', mmkCommandStates, SampleCommandStates);
  AddSample('mode', mmkMode, EncodeMonitorMode('mode', 'build', True));
  AddSample('set-mode', mmkSetMode, EncodeMonitorSetMode('set-mode', 'plan'));
  Json := '';
  ErrorJson := '';
  Check('send encodes', TryEncodeMonitorSend('send', 'hello from the phone', Json, ErrorJson));
  AddSample('send', mmkSend, Json);
  Check('steer encodes', TryEncodeMonitorSteer('steer', 'use the codec', Json, ErrorJson));
  AddSample('steer', mmkSteer, Json);
  AddSample('stop', mmkStop, EncodeMonitorEmpty(mmkStop, 'stop'));
  Payload := MonitorStatusToJson(View);
  Try
    AddSample('status', mmkStatus, EncodeMonitorEnvelope(mmkStatus, 'status', Payload));
  Finally
    Payload.Free;
  End;
  AddSample('target', mmkTarget, EncodeMonitorTarget('target', 'project', 'LazWorkflow', '/work/LazWorkflow'));
  AddTargetSamples;
  AddConversationSamples;
  AddSamplingSamples;
  PlanRows[0] := SamplePlanRow;
  AddSample('plan', mmkPlan, EncodeMonitorPlan('plan', 'Documents/Plan.md', 'Monitor plan', False, PlanRows));
  AddSample('select-plan', mmkSelectPlan, EncodeMonitorPath(mmkSelectPlan, 'select-plan', 'Documents/Plan.md'));
  AddSample('new-plan', mmkNewPlan, EncodeMonitorNewPlan('new-plan', 'Monitor plan', True));
  AddSample('close-plan', mmkClosePlan, EncodeMonitorEmpty(mmkClosePlan, 'close-plan'));
  AddSample('work-on-plan', mmkWorkOnPlan, EncodeMonitorWorkOnPlan('work-on-plan', 2));
  AddSample('run-plan', mmkRunPlan, EncodeMonitorEmpty(mmkRunPlan, 'run-plan'));
  AddSample('stop-plan', mmkStopPlan, EncodeMonitorEmpty(mmkStopPlan, 'stop-plan'));
  TaskRows[0] := SampleTaskRow;
  AddSample('tasks', mmkTasks, EncodeMonitorTasks('tasks', TaskRows));
  AddSample('run-task', mmkRunTask, EncodeMonitorTaskCommand(mmkRunTask, 'run-task', 'review-unit', ''));
  AddSample('insert-task', mmkInsertTask, EncodeMonitorTaskCommand(mmkInsertTask, 'insert-task', 'review-unit', 'note'));
  AddSample('insert-result', mmkInsertResult, EncodeMonitorInsertResult('insert-result', 'expanded prompt'));
  Notice.Active := True;
  Notice.ToolId := 'tool-1';
  Notice.ToolName := 'write_file';
  Notice.Summary := 'Write the test.';
  Notice.ModeCaption := 'Ask';
  Notice.DecisionsAccepted := True;
  Notice.Reason := '';
  AddSample('approval-requested', mmkApprovalRequested, EncodeMonitorApprovalRequested('approval-requested', Notice));
  AddSample('approval-decision', mmkApprovalDecision, EncodeMonitorApprovalDecision('approval-decision', 'tool-1', True));
  AddSample('approval-closed', mmkApprovalClosed, EncodeMonitorApprovalClosed('approval-closed', 'tool-1', 'desktop'));
  AddSample('image-get', mmkImageGet, EncodeMonitorImageGet('image-get', 3, 'tile-1'));
  SetLength(Tiny, 4);
  Tiny[0] := 1;
  Tiny[1] := 2;
  Tiny[2] := 3;
  Tiny[3] := 4;
  Messages := Nil;
  Check('single image encodes', TryEncodeMonitorImageData('image-data', 'tile-1', 'image/png', 8, 8, 1, Tiny, False, False,
    Messages, Reason));
  If Length(Messages) = 1 Then
    AddSample('image-data', mmkImageData, Messages[0])
  Else
    AddSample('image-data', mmkImageData, '');
  AddImageSamples;
  AddSample('image-unavailable', mmkImageUnavailable, EncodeMonitorImageUnavailable('image-unavailable', 'tile-1', 'missing'));
  AddSample('new-conversation', mmkNewConversation, EncodeMonitorEmpty(mmkNewConversation, 'new-conversation'));
  AddSample('error', mmkError, EncodeMonitorError('error', 'unknown_type', 'Unknown message type widget.', 'widget-1'));
  AddSample('ping', mmkPing, EncodeMonitorTicks(mmkPing, 'ping', 15000));
  AddSample('pong', mmkPong, EncodeMonitorTicks(mmkPong, 'pong', 15000));
End;

Procedure CheckTyped(Const Sample: TWireSample);
Var
  Message: TMonitorMessage;
  ErrorText, Text, Mode, Path: String;
  Hello: TMonitorHello;
  Pair: TMonitorPair;
  PairOk: TMonitorPairOk;
  HelloOk: TMonitorHelloOk;
  Auth: TMonitorAuth;
  Rejected: TMonitorRejected;
  Bye: TMonitorBye;
  Snapshot: TMonitorSnapshot;
  Transcript: TMonitorTranscript;
  Turn: TAssistantMonitorTurn;
  ModeMessage: TMonitorModeMessage;
  Target: TMonitorTargetMessage;
  Targets: TMonitorTargetsMessage;
  Conversations: TMonitorConversationsMessage;
  ArchiveId, ModelId, Level, Approval: String;
  Models: TMonitorModelsMessage;
  Reasoning: TMonitorReasoningMessage;
  Permissions: TMonitorPermissionsMessage;
  Plan: TMonitorPathMessage;
  Index, Decoded: Integer;
  Command: TMonitorTaskCommand;
  Notice: TAssistantApprovalNotice;
  Decision: TMonitorApprovalDecision;
  Closed: TMonitorApprovalClosed;
  ImageGet: TMonitorImageGet;
  Image: TMonitorImageData;
  Unavailable: TMonitorImageUnavailable;
  ErrorBody: TMonitorErrorBody;
  ResumeMsg: TMonitorResume;
  Patch: TMonitorPatch;
  Catchup: TMonitorCatchup;
  ClosedTalk: TMonitorConversationClosed;
  Ticks: TMonitorTicks;
  Data: TJSONData;
  Payload: TJSONObject;
  View: TAssistantMonitorView;
  Running: Boolean;
  Rows: TMonitorSnapshot;
Begin
  If Not TryDecodeMonitorEnvelope(Sample.Json, Message, ErrorText) Then
    Begin
      Check(Sample.Name + ' typed envelope', False);
      Exit;
    End;
  Case Sample.Kind Of
    mmkHello:
      Begin
        Check(Sample.Name + ' hello', DecodeMonitorHello(Message.PayloadJson, Hello));
        Check(Sample.Name + ' client name', Hello.ClientName = 'Phone');
        If Sample.Name = 'hello-first' Then
          Check('hello-first has no client id', (Not Hello.HasClientId) And (Pos('client_id', Sample.Json) = 0))
        Else
          Check('hello-reconnect has client id', Hello.HasClientId And (Hello.ClientId = 'client-1'));
      End;
    mmkPair:
      Check('pair fields', DecodeMonitorPair(Message.PayloadJson, Pair) And (Pair.Code = 'ABCDEFGHJK') And
        (Pair.Fingerprint = 'ab12cd34'));
    mmkPairOk:
      Check('pair_ok fields', DecodeMonitorPairOk(Message.PayloadJson, PairOk) And (PairOk.ClientId = 'client-1') And
        (PairOk.SessionToken = 'token-1'));
    mmkHelloOk:
      Check('hello_ok fields', DecodeMonitorHelloOk(Message.PayloadJson, HelloOk) And
        (HelloOk.Nonce = '00112233445566778899aabbccddeeff') And (HelloOk.ServerName = 'LazAssistantMonitor') And
        (HelloOk.Epoch = 'ab12') And (HelloOk.Cursor = 0) And (HelloOk.ConversationId = 'current') And
        (HelloOk.ProjectRoot = '/work/LazWorkflow') And (HelloOk.Title = 'Current'));
    mmkAuth:
      Check('auth fields', DecodeMonitorAuth(Message.PayloadJson, Auth) And (Auth.ClientId = 'client-1') And (Auth.Hmac <> ''));
    mmkRejected:
      Check('rejected fields', DecodeMonitorRejected(Message.PayloadJson, Rejected) And (Rejected.Reason = 'busy') And
        (Rejected.HostVersion = 1));
    mmkBye:
      Check('bye reason', DecodeMonitorBye(Message.PayloadJson, Bye) And (Bye.Reason = 'revoked'));
    mmkSnapshot:
      Check('snapshot fields', DecodeMonitorSnapshot(Message.PayloadJson, Snapshot) And (Snapshot.View.Model = 'grok-test') And
        (Snapshot.View.SignedIn) And Snapshot.HasLive And (Snapshot.Live.Id = 'turn-3') And
        (Snapshot.PlanTitle = 'Monitor plan') And (Length(Snapshot.TaskRows) = 1));
    mmkRefresh, mmkStop, mmkRunPlan, mmkStopPlan, mmkNewConversation, mmkClosePlan:
      Check(Sample.Name + ' empty payload', PayloadIsEmpty(Sample.Json));
    mmkTranscript:
      Check('transcript fields', DecodeMonitorTranscript(Message.PayloadJson, Transcript) And (Transcript.Phase = 'streaming') And
        (Length(Transcript.Blocks) = 1) And (Transcript.Blocks[0].Body = 'Noted.'));
    mmkTurn:
      Check('turn index', DecodeMonitorTurnRequest(Message.PayloadJson, Index) And (Index = 3));
    mmkTurnData:
      Check('turn data', DecodeMonitorTurnData(Message.PayloadJson, Turn) And (Turn.Prompt = 'Show the frame.') And Turn.Live);
    mmkSnapshotPage, mmkChunk:
      Begin
        Check(Sample.Name + ' payload', PayloadObject(Sample.Json, Data, Payload));
        Data.Free;
      End;
    mmkCommandState:
      Begin
        Check('command_state fields', PayloadObject(Sample.Json, Data, Payload) And (Payload.Get('ref', '') = 'send-1') And
          (Payload.Get('state', '') = 'done') And (Payload.Get('text', '') = 'Sent.') And (Payload.Find('reason') = Nil));
        Data.Free;
      End;
    mmkCommandStates:
      Begin
        Check('command_states fields', PayloadObject(Sample.Json, Data, Payload) And (Payload.Find('states') Is TJSONArray) And
          (TJSONArray(Payload.Find('states')).Count = 1) And
          (TJSONArray(Payload.Find('states')).Objects[0].Get('reason', '') = 'busy'));
        Data.Free;
      End;
    mmkMode:
      Check('mode fields', DecodeMonitorMode(Message.PayloadJson, ModeMessage) And (ModeMessage.Mode = 'build') And ModeMessage.Locked);
    mmkSetMode:
      Check('set_mode', DecodeMonitorSetMode(Message.PayloadJson, Mode) And (Mode = 'plan'));
    mmkSend, mmkSteer, mmkInsertResult:
      Check(Sample.Name + ' text', DecodeMonitorText(Message.PayloadJson, Text) And (Text <> ''));
    mmkStatus:
      Begin
        Check('status payload', PayloadObject(Sample.Json, Data, Payload));
        If Assigned(Data) Then
          Try
            Check('status fields', TryMonitorStatusFromJson(Payload, View) And (View.Model = 'grok-test') And View.SignedIn And
              (View.UsageCaption = '') And (View.UsageHint = ''));
          Finally
            Data.Free;
          End;
      End;
    mmkTarget:
      Check('target fields', DecodeMonitorTarget(Message.PayloadJson, Target) And (Target.Kind = 'project') And
        (Target.Display = 'LazWorkflow'));
    mmkPlan:
      Check('plan fields', DecodeMonitorPlan(Message.PayloadJson, Path, Text, Running, Rows) And (Text = 'Monitor plan') And
        (Length(Rows.PlanRows) = 1) And (Rows.PlanRows[0].Title = 'Codec tests'));
    mmkSelectPlan:
      Check(Sample.Name + ' path', DecodeMonitorPath(Message.PayloadJson, Path) And (Path = 'Documents/Plan.md'));
    mmkTargets:
      Check('targets fields', DecodeMonitorTargets(Message.PayloadJson, Targets) And (Targets.Current = '') And
        (Length(Targets.Choices) = 2) And (Targets.Choices[0].Path = '') And
        (Targets.Choices[0].Caption = 'Current Project') And (Targets.Choices[1].Path = '/work/Other'));
    mmkSelectTarget:
      Check('select_target empty path', DecodeMonitorPath(Message.PayloadJson, Path) And (Path = ''));
    mmkConversations:
      Check('conversations fields', DecodeMonitorConversations(Message.PayloadJson, Conversations) And (Conversations.Current = '') And
        Conversations.Truncated And (Length(Conversations.Choices) = 2) And (Conversations.Choices[0].Id = '') And
        Conversations.Choices[0].Current And (Conversations.Choices[0].Title = 'Current — hello') And
        (Conversations.Choices[1].Id = '20261019T120000000') And (Not Conversations.Choices[1].Current));
    mmkSelectConversation:
      Check('select_conversation empty id', DecodeMonitorSelectConversation(Message.PayloadJson, ArchiveId) And (ArchiveId = ''));
    mmkModels:
      Check('models fields', DecodeMonitorModels(Message.PayloadJson, Models) And (Models.Current = 'grok-4') And
        (Models.Backend = 'grok') And (Models.Note = '') And (Length(Models.Choices) = 2) And
        (Models.Choices[0].Caption = 'grok-4 — 256k context'));
    mmkSetModel:
      Check('set_model id', DecodeMonitorSetModel(Message.PayloadJson, ModelId) And (ModelId = 'grok-4'));
    mmkSetReasoning:
      Check('set_reasoning empty level', DecodeMonitorSetReasoning(Message.PayloadJson, Level) And (Level = ''));
    mmkPermissions:
      Check('permissions fields', DecodeMonitorPermissions(Message.PayloadJson, Permissions) And (Permissions.Current = 'ask') And
        (Permissions.Backend = 'grok') And (Permissions.Note = '') And (Length(Permissions.Choices) = 3) And
        (Permissions.Choices[0].Id = 'ask') And (Permissions.Choices[0].Caption = 'Ask — confirm each write/compile') And
        (Permissions.Choices[1].Caption = 'Auto — allow project tools') And
        (Permissions.Choices[2].Caption = 'Always — never prompt (like Build always-approve)'));
    mmkSetPermissions:
      Check('set_permissions approval', DecodeMonitorSetPermissions(Message.PayloadJson, Approval) And (Approval = 'auto') And
        Not DecodeMonitorApprovalDecision(Message.PayloadJson, Decision));
    mmkReasoning:
      Check('reasoning empty id', DecodeMonitorReasoning(Message.PayloadJson, Reasoning) And (Reasoning.Current = '') And
        (Length(Reasoning.Choices) = 2) And (Reasoning.Choices[0].Id = '') And (Reasoning.Choices[0].Caption = 'Model default') And
        (Reasoning.Note = 'This connection does not set an effort level.'));
    mmkNewPlan:
      Check('new_plan title', DecodeMonitorNewPlan(Message.PayloadJson, Plan) And Plan.HasTitle And (Plan.Title = 'Monitor plan'));
    mmkWorkOnPlan:
      Check('work_on_plan index', DecodeMonitorWorkOnPlan(Message.PayloadJson, Index) And (Index = 2));
    mmkTasks:
      Begin
        Check('tasks payload', PayloadObject(Sample.Json, Data, Payload));
        If Assigned(Data) Then
          Try
            Check('tasks row', (Payload.Find('rows') Is TJSONArray) And (TJSONArray(Payload.Find('rows')).Count = 1) And
              (TJSONObject(TJSONArray(Payload.Find('rows'))[0]).Get('id', '') = 'review-unit'));
          Finally
            Data.Free;
          End;
      End;
    mmkRunTask, mmkInsertTask:
      Check(Sample.Name + ' task', DecodeMonitorTaskCommand(Message.PayloadJson, Command) And (Command.Id = 'review-unit'));
    mmkApprovalRequested:
      Check('approval_requested', DecodeMonitorApprovalRequested(Message.PayloadJson, Notice) And (Notice.ToolId = 'tool-1') And
        Notice.DecisionsAccepted);
    mmkApprovalDecision:
      Check('approval_decision', DecodeMonitorApprovalDecision(Message.PayloadJson, Decision) And Decision.Allow And
        (Decision.ToolId = 'tool-1'));
    mmkApprovalClosed:
      Check('approval_closed', DecodeMonitorApprovalClosed(Message.PayloadJson, Closed) And (Closed.Reason = 'desktop'));
    mmkImageGet:
      Check('image_get', DecodeMonitorImageGet(Message.PayloadJson, ImageGet) And (ImageGet.TurnIndex = 3) And
        (ImageGet.ImageId = 'tile-1'));
    mmkImageData:
      Begin
        Check(Sample.Name + ' image', DecodeMonitorImageData(Message.PayloadJson, Image, Decoded) And (Image.ImageId = 'tile-1') And
          (Image.Mime = 'image/png') And (Decoded > 0) And (Decoded <= MonitorMaxImagePartBytes));
        If Sample.Name = 'image-data-part-1' Then
          Check('image part 1 size', (Image.Part = 1) And (Image.PartCount = 2) And (Decoded = MonitorMaxImagePartBytes));
        If Sample.Name = 'image-data-part-2' Then
          Check('image part 2 size', (Image.Part = 2) And (Image.PartCount = 2) And (Decoded = 16));
      End;
    mmkImageUnavailable:
      Check('image_unavailable', DecodeMonitorImageUnavailable(Message.PayloadJson, Unavailable) And (Unavailable.Reason = 'missing'));
    mmkError:
      Check('error fields', DecodeMonitorError(Message.PayloadJson, ErrorBody) And (ErrorBody.Reason = 'unknown_type') And
        (ErrorBody.RefId = 'widget-1'));
    mmkPing, mmkPong:
      Check(Sample.Name + ' ticks', DecodeMonitorTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 15000));
    mmkResume:
      Check('resume fields', DecodeMonitorResume(Message.PayloadJson, ResumeMsg) And (ResumeMsg.Epoch = 'abc123') And
        (ResumeMsg.Cursor = 4));
    mmkPatch:
      Check('patch fields', DecodeMonitorPatch(Message.PayloadJson, Patch) And (Patch.Epoch = 'abc123') And (Patch.Cursor = 4) And
        (Patch.TurnId = 'turn-3') And Patch.Busy And (Patch.Part = 1) And (Patch.PartCount = 1) And
        (Length(Patch.Blocks) = 1) And (Patch.Blocks[0].Body = 'Noted.'));
    mmkCatchup:
      Begin
        Check(Sample.Name + ' catchup', DecodeMonitorCatchup(Message.PayloadJson, Catchup) And (Catchup.Epoch = 'abc123') And
          (Catchup.Cursor = 4) And (Catchup.ConversationId <> '') And (Catchup.ProjectRoot = '/work/LazWorkflow'));
        If Sample.Name = 'catchup-snapshot' Then
          Check('catchup snapshot', (Catchup.Mode = mcmSnapshot) And Catchup.HasSnapshot And (Catchup.Snapshot.PlanTitle = 'Monitor plan'))
        Else
          Check('catchup events', (Catchup.Mode = mcmEvents) And (Length(Catchup.Patches) = 1) And
            (Catchup.Patches[0].TurnId = 'turn-3'));
      End;
    mmkConversationClosed:
      Check('conversation_closed fields', DecodeMonitorConversationClosed(Message.PayloadJson, ClosedTalk) And
        (ClosedTalk.Epoch = 'abc123') And (ClosedTalk.Cursor = 4) And
        (ClosedTalk.ConversationId = 'conversation-20261019T120000000') And (ClosedTalk.Title = 'Monitor plan'));
  Else
    Check(Sample.Name + ' typed', False);
  End;
End;

Procedure CheckSample(Const Sample: TWireSample);
Var
  Bytes: RawByteString;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
Begin
  Check(Sample.Name + ' json', Sample.Json <> '');
  If Sample.Json = '' Then
    Exit;
  Check(Sample.Name + ' frame', TryEncodeMonitorFrame(Sample.Json, Bytes, Status) And (Status = mfsOk));
  If Status <> mfsOk Then
    Exit;
  Check(Sample.Name + ' under cap', Length(Sample.Json) <= MonitorMaxPayloadBytes);
  CheckLam1(Sample.Name, Bytes, Length(Sample.Json));
  Check(Sample.Name + ' frame decodes', TryDecodeMonitorFrame(Bytes, Frame, Status) And (Status = mfsOk) And (Frame.Json = Sample.Json));
  If DumpFixtures Then
    WriteFixture(Sample.Name, Bytes)
  Else
    CheckFixture(Sample.Name, Bytes);
End;

Procedure TestRoundTrips;
Var
  I: Integer;
  Seen: Array[TMonitorMessageKind] Of Boolean;
  Kind: TMonitorMessageKind;
Begin
  BuildSamples;
  For Kind := Low(TMonitorMessageKind) To High(TMonitorMessageKind) Do
    Seen[Kind] := False;
  For I := 0 To High(Samples) Do
    Begin
      Check(Samples[I].Name + ' envelope', Samples[I].Json <> '');
      If Samples[I].Json = '' Then
        Continue;
      CheckTyped(Samples[I]);
      CheckSample(Samples[I]);
      Seen[Samples[I].Kind] := True;
    End;
  For Kind := Succ(mmkUnknown) To High(TMonitorMessageKind) Do
    Begin
      { Retired content types are no longer sent. Their fixtures are gone. }
      If Kind In [mmkSnapshot, mmkTranscript, mmkTurnData] Then
        Continue;
      Check(MonitorMessageKindName(Kind) + ' round-trip', Seen[Kind]);
    End;
End;

Function TextIsCompleteUtf8(Const Text: String): Boolean;
Var
  Index, Lead, Need, Follow: Integer;
Begin
  Result := True;
  Index := 1;
  While Index <= Length(Text) Do
    Begin
      Lead := Ord(Text[Index]);
      If Lead < $80 Then
        Need := 1
      Else If (Lead And $E0) = $C0 Then
        Need := 2
      Else If (Lead And $F0) = $E0 Then
        Need := 3
      Else If (Lead And $F8) = $F0 Then
        Need := 4
      Else
        Exit(False);
      If Index + Need - 1 > Length(Text) Then
        Exit(False);
      For Follow := 1 To Need - 1 Do
        If (Ord(Text[Index + Follow]) And $C0) <> $80 Then
          Exit(False);
      Inc(Index, Need);
    End;
End;

Procedure TestLargeChunkPack;
Const
  PayloadBytes = 900000;
Var
  Payload, Expected, Piece, Joined, Euro: String;
  Frames: TStringArray;
  Data: TJSONData;
  Root, PayloadObj: TJSONObject;
  Started: QWord;
  Index, Part, PartCount: Integer;
Begin
  SetLength(Payload, PayloadBytes);
  For Index := 1 To PayloadBytes Do
    Payload[Index] := 'a';
  Euro := #$E2#$82#$AC;
  Index := 1;
  While Index <= PayloadBytes - 16 Do
    Begin
      Payload[Index] := '"';
      Payload[Index + 1] := '\';
      Payload[Index + 2] := #8;
      Payload[Index + 3] := #9;
      Payload[Index + 4] := #10;
      Payload[Index + 5] := #12;
      Payload[Index + 6] := #13;
      Payload[Index + 7] := #1;
      Payload[Index + 8] := Euro[1];
      Payload[Index + 9] := Euro[2];
      Payload[Index + 10] := Euro[3];
      Inc(Index, 10000);
    End;
  Payload[PayloadBytes - 2] := Euro[1];
  Payload[PayloadBytes - 1] := Euro[2];
  Payload[PayloadBytes] := Euro[3];
  Started := GetTickCount64;
  Check('large page packs', PackMonitorBulkItem('bulk-pack', 'snapshot_page', Payload, Frames));
  Check('large page packs promptly', GetTickCount64 - Started < 2000);
  Check('large page is chunked', Length(Frames) > 1);
  Expected := '{"v":' + IntToStr(MonitorCatalogueVersion) + ',"id":"bulk-pack","type":"snapshot_page","payload":' +
    Payload + '}';
  Joined := '';
  PartCount := 0;
  For Index := 0 To High(Frames) Do
    Begin
      Check('chunk fits the outbox', Length(Frames[Index]) <= MonitorOutboxChunkBytes);
      Data := Nil;
      If Not PayloadObject(Frames[Index], Data, PayloadObj) Then
        Begin
          Data.Free;
          Check('chunk payload', False);
          Continue;
        End;
      Try
        Root := TJSONObject(Data);
        Part := PayloadObj.Get('part', 0);
        If Index = 0 Then
          PartCount := PayloadObj.Get('part_count', 0);
        Piece := PayloadObj.Get('data', '');
        Check('chunk fields', (Root.Get('type', '') = 'chunk') And (Part = Index + 1) And
          (PayloadObj.Get('part_count', 0) = Length(Frames)) And (PartCount = Length(Frames)) And
          (PayloadObj.Get('item_id', '') = 'bulk-pack') And (PayloadObj.Get('item_type', '') = 'snapshot_page'));
        Check('chunk is whole UTF-8', TextIsCompleteUtf8(Piece));
        Joined := Joined + Piece;
      Finally
        Data.Free;
      End;
    End;
  Check('chunks rebuild the item', Joined = Expected);
End;

Procedure TestPatchOverCap;
Var
  Patch, Part, Assembled: TMonitorPatch;
  Messages, Missing: TStringArray;
  Message: TMonitorMessage;
  ErrorText: String;
  I: Integer;
Begin
  Patch.Epoch := 'abc123';
  Patch.Cursor := 9;
  Patch.TurnIndex := 3;
  Patch.TurnId := 'turn-3';
  Patch.Busy := True;
  Patch.Sending := True;
  Patch.PlanRunning := False;
  Patch.Phase := 'streaming';
  Patch.CanSend := False;
  Patch.CanSteer := True;
  Patch.CanStop := True;
  Patch.ElapsedMs := 50;
  Patch.Part := 1;
  Patch.PartCount := 1;
  SetLength(Patch.Blocks, 2);
  Patch.Blocks[0] := SampleBlock;
  Patch.Blocks[1] := SampleBlock;
  Patch.Blocks[0].BlockId := 'block-a';
  Patch.Blocks[1].BlockId := 'block-b';
  Patch.Blocks[0].Body := StringOfChar('a', 150000);
  Patch.Blocks[1].Body := StringOfChar('b', 150000);
  Messages := PackMonitorPatch('patch-over', Patch);
  Check('over-cap patch splits', Length(Messages) >= 2);
  If Length(Messages) < 2 Then
    Exit;
  For I := 0 To High(Messages) Do
    Begin
      Check('over-cap part envelope', TryDecodeMonitorEnvelope(Messages[I], Message, ErrorText) And (Message.Kind = mmkPatch));
      Check('over-cap part fields', DecodeMonitorPatch(Message.PayloadJson, Part) And (Part.Cursor = 9) And
        (Part.Epoch = 'abc123') And (Part.Part = I + 1) And (Part.PartCount = Length(Messages)));
    End;
  Check('over-cap assembles', TryAssembleMonitorPatch(Messages, Assembled) And (Assembled.Cursor = 9) And
    (Length(Assembled.Blocks) = 2) And (Assembled.Blocks[0].Body = Patch.Blocks[0].Body) And
    (Assembled.Blocks[1].Body = Patch.Blocks[1].Body));
  SetLength(Missing, Length(Messages) - 1);
  For I := 0 To High(Missing) Do
    Missing[I] := Messages[I];
  Check('missing patch part is not success', Not TryAssembleMonitorPatch(Missing, Assembled));
End;

Procedure TestVersion2PatchAndClosed;
Var
  Patch, Part: TMonitorPatch;
  Closed: TMonitorConversationClosed;
  Messages: TStringArray;
  Message: TMonitorMessage;
  ErrorText: String;
  Data: TJSONData;
  I: Integer;
Begin
  Patch := Default(TMonitorPatch);
  Patch.Epoch := 'abc123';
  Patch.Cursor := 4;
  Patch.TurnIndex := 1;
  Patch.TurnId := 'turn-1';
  Patch.Part := 1;
  Patch.PartCount := 1;
  Patch.CanSend := True;
  SetLength(Patch.Blocks, 2);
  Patch.Blocks[0] := SampleBlock;
  Patch.Blocks[1] := SampleBlock;
  Check('version 2 patch envelope', TryDecodeMonitorEnvelope(EncodeMonitorPatch('patch-v2', Patch), Message, ErrorText) And
    (Message.Version = 2) And (Message.Kind = mmkPatch));
  Patch.Blocks[0].Body := StringOfChar('p', 150000);
  Patch.Blocks[1].Body := StringOfChar('q', 150000);
  Messages := PackMonitorPatch('patch-parts', Patch);
  Check('patch parts are version 2', Length(Messages) >= 2);
  For I := 0 To High(Messages) Do
    Begin
      Check('patch part version 2', TryDecodeMonitorEnvelope(Messages[I], Message, ErrorText) And (Message.Version = 2) And
        (Message.Kind = mmkPatch));
      Check('patch part index', DecodeMonitorPatch(Message.PayloadJson, Part) And (Part.Part = I + 1) And
        (Part.PartCount = Length(Messages)) And (Part.Cursor = 4));
    End;
  Check('conversation_closed version 2', TryDecodeMonitorEnvelope(
    EncodeMonitorConversationClosed('closed-v2', 'abc123', 4, 'conversation-20261019T120000000', 'Monitor plan'),
    Message, ErrorText) And (Message.Version = 2) And (Message.Kind = mmkConversationClosed));
  Check('conversation_closed payload', DecodeMonitorConversationClosed(Message.PayloadJson, Closed) And
    (Closed.ConversationId = 'conversation-20261019T120000000') And (Closed.Cursor = 4) And (Closed.Title = 'Monitor plan'));
  Data := Nil;
  Try
    Data := GetJSON(Message.WireJson);
    Check('conversation_closed wire version', (Data Is TJSONObject) And (TJSONObject(Data).Get('v', 0) = 2));
  Finally
    Data.Free;
  End;
End;

Procedure TestDirtyBlocks;
Var
  Previous, Current, Dirty: TAssistantMonitorBlockArray;
Begin
  SetLength(Previous, 1);
  SetLength(Current, 2);
  Previous[0] := SampleBlock;
  Current[0] := SampleBlock;
  Current[0].DurationMs := 99;
  Current[1] := SampleBlock;
  Current[1].BlockId := 'block-2';
  Current[1].Body := 'Next.';
  Dirty := SelectDirtyMonitorBlocks(Previous, Current, False);
  Check('unchanged block is omitted', Length(Dirty) = 1);
  Check('new block is kept', (Length(Dirty) = 1) And (Dirty[0].BlockId = 'block-2'));
  Current[0].Body := 'Changed.';
  Dirty := SelectDirtyMonitorBlocks(Previous, Current, False);
  Check('changed body is kept', Length(Dirty) = 2);
  Dirty := SelectDirtyMonitorBlocks(Previous, Current, True);
  Check('first patch sends every block', Length(Dirty) = 2);
End;

Procedure TestModelNote;
Var
  Ids, Captions: TStringList;
  Models: TMonitorModelsMessage;
  Json, ErrorText: String;
  Message: TMonitorMessage;
Begin
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Ids.Add('grok-4');
    Captions.Add('grok-4');
    Json := EncodeMonitorModels('models-note', 'grok-4', 'grok', 'The rest of this list is in desktop Settings.', Ids, Captions);
  Finally
    Captions.Free;
    Ids.Free;
  End;
  Check('model note encodes', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkModels));
  Check('model note round trip', DecodeMonitorModels(Message.PayloadJson, Models) And (Models.Current = 'grok-4') And
    (Models.Backend = 'grok') And (Models.Note = 'The rest of this list is in desktop Settings.') And
    (Length(Models.Choices) = 1) And (Models.Choices[0].Id = 'grok-4'));
End;

Procedure TestPermissionsCaptions;
Var
  Ids, Captions: TStringList;
  Permissions: TMonitorPermissionsMessage;
  Approval, Json, ErrorText: String;
  Message: TMonitorMessage;
Begin
  Approval := 'kept';
  Check('missing approval is not ask', Not DecodeMonitorSetPermissions('{}', Approval));
  Check('missing approval stays empty', Approval = '');
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Ids.Add('ask');
    Captions.Add('Ask before file changes and builds');
    Ids.Add('auto');
    Captions.Add('Auto: allow project tools');
    Ids.Add('always');
    Captions.Add('Always: allow registered tools');
    Json := EncodeMonitorPermissions('permissions-codex', 'always', 'codex', '', Ids, Captions);
  Finally
    Captions.Free;
    Ids.Free;
  End;
  Check('codex permissions encode', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkPermissions));
  Check('codex permissions captions', DecodeMonitorPermissions(Message.PayloadJson, Permissions) And
    (Permissions.Current = 'always') And (Permissions.Backend = 'codex') And (Length(Permissions.Choices) = 3) And
    (Permissions.Choices[0].Caption = 'Ask before file changes and builds') And
    (Permissions.Choices[1].Caption = 'Auto: allow project tools') And
    (Permissions.Choices[2].Caption = 'Always: allow registered tools'));
End;

Procedure TestSetReasoningLevel;
Var
  Level, Json, ErrorText: String;
  Message: TMonitorMessage;
Begin
  Level := 'kept';
  Check('missing level is not model default', Not DecodeMonitorSetReasoning('{}', Level));
  Check('missing level stays empty', Level = '');
  Json := EncodeMonitorSetReasoning('set-reasoning-high', 'high');
  Check('set_reasoning high encodes', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkSetReasoning));
  Check('set_reasoning high level', DecodeMonitorSetReasoning(Message.PayloadJson, Level) And (Level = 'high'));
End;

Procedure TestSelectTargetPathIsNotAnId;
Var
  Message: TMonitorMessage;
  ErrorText, Path, Json: String;
Begin
  Json := EncodeMonitorPath(mmkSelectTarget, 'select-target-space', '/work/My Folder');
  Check('folder path encodes', Json <> '');
  Check('folder path envelope', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkSelectTarget));
  Check('folder path is not an id check', DecodeMonitorPath(Message.PayloadJson, Path) And (Path = '/work/My Folder'));
End;

Procedure TestOldCatalogue;
Var
  Message: TMonitorMessage;
  ErrorText, Json: String;
  Patch: TMonitorPatch;
Begin
  Json := '{"v":1,"id":"old-patch","type":"patch","payload":{"epoch":"abc123","cursor":1,"turn_index":0,' +
    '"turn_id":"t","part":1,"part_count":1,"busy":false,"sending":false,"plan_running":false,"phase":"",' +
    '"can_send":true,"can_steer":false,"can_stop":false,"elapsed_ms":0,"blocks":[]}}';
  Check('v1 envelope is not decoded', Not TryDecodeMonitorEnvelope(Json, Message, ErrorText));
  Check('v1 mismatch names version', Pos('version', LowerCase(ErrorText)) > 0);
  Json := '{"turn_index":1,"revision":2,"part":1,"part_count":1,"phase":"streaming","status_text":"Writing",' +
    '"duration_ms":1,"blocks":[]}';
  Check('v1 transcript is not a patch', Not DecodeMonitorPatch(Json, Patch));
End;

Procedure TestPlanDocumentFrames;
Var
  Frames: TStringArray;
  Body, Json, Path, Title: String;
  Index: Integer;
  Data: TJSONData;
  Payload: TJSONObject;
  Running: Boolean;
  Rows: TMonitorSnapshot;
Begin
  SetLength(Frames, 0);
  Body := StringOfChar('a', MonitorMaxPayloadBytes);
  Check('a plan larger than one frame splits', PackMonitorPlanFrames('plan-big', 'Documents/Plan.md', 'Big', False, [],
    Nil, Nil, Body, True, Frames) And (Length(Frames) > 1));
  For Index := 0 To High(Frames) Do
    Check('plan chunk fits one frame', Length(Frames[Index]) <= MonitorMaxPayloadBytes);
  Check('a fitting plan is one frame', PackMonitorPlanFrames('plan-small', 'Documents/Plan.md', 'Small', False, [],
    Nil, Nil, '# Plan', True, Frames) And (Length(Frames) = 1));
  Data := GetJSON(Frames[0]);
  Try
    Payload := TJSONObject(TJSONObject(Data).Find('payload'));
    Check('a fitting plan is complete', DecodeMonitorPlan(Payload.AsJSON, Path, Title, Running, Rows) And
      Rows.PlanComplete And (Rows.PlanBody = '# Plan'));
  Finally
    Data.Free;
  End;
  Json := EncodeMonitorPlan('plan-clear', 'Documents/Plan.md', 'Plan', False, [], Nil, Nil, '', 0, '', True);
  Check('an empty complete plan omits body', (Json <> '') And (Pos('"body"', Json) = 0));
  Data := GetJSON(Json);
  Try
    Payload := TJSONObject(TJSONObject(Data).Find('payload'));
    Check('an empty complete plan is marked', DecodeMonitorPlan(Payload.AsJSON, Path, Title, Running, Rows) And
      Rows.PlanComplete And (Rows.PlanBody = ''));
  Finally
    Data.Free;
  End;
End;

Procedure TestPlanBody;
Var
  Json: String;
  Data: TJSONData;
  Payload: TJSONObject;
  Path, Title: String;
  Running: Boolean;
  Rows: TMonitorSnapshot;
Begin
  Json := EncodeMonitorPlan('plan-empty-body', 'Documents/Plan.md', 'Monitor plan', False, []);
  Check('empty plan body is omitted', Pos('"body"', Json) = 0);
  Json := EncodeMonitorPlan('plan-body', 'Documents/Plan.md', 'Monitor plan', False, [], Nil, Nil, '', 0, '# Plan');
  Check('plan body encodes', Json <> '');
  Data := GetJSON(Json);
  Try
    Check('plan body envelope', Data Is TJSONObject);
    Payload := TJSONObject(TJSONObject(Data).Find('payload'));
    Check('plan body field', DecodeMonitorPlan(Payload.AsJSON, Path, Title, Running, Rows) And (Rows.PlanBody = '# Plan') And
      (Path = 'Documents/Plan.md') And (Not Running));
  Finally
    Data.Free;
  End;
  Data := GetJSON('{"path":"Documents/Plan.md","title":"Plan","running":false,"rows":[],"body":1}');
  Try
    Check('plan body must be text', (Data Is TJSONObject) And
      (Not DecodeMonitorPlan(TJSONObject(Data).AsJSON, Path, Title, Running, Rows)));
  Finally
    Data.Free;
  End;
End;

Procedure TestUsageFields;
Var
  View, Decoded: TAssistantMonitorView;
  Payload: TJSONObject;
  Data: TJSONData;
  Json: String;
Begin
  FillView(View);
  Payload := MonitorStatusToJson(View);
  Try
    Json := Payload.AsJSON;
    Check('empty usage is omitted', (Pos('usage_caption', Json) = 0) And (Pos('usage_hint', Json) = 0));
    Check('omitted usage decodes empty', TryMonitorStatusFromJson(Payload, Decoded) And (Decoded.UsageCaption = '') And
      (Decoded.UsageHint = '') And (Decoded.Model = 'grok-test'));
  Finally
    Payload.Free;
  End;
  View.UsageCaption := 'Credits used: 42%';
  View.UsageHint := 'Weekly limit: 42%' + LineEnding + 'Next reset: October 30, 18:00';
  Payload := MonitorStatusToJson(View);
  Try
    Check('usage round trip', TryMonitorStatusFromJson(Payload, Decoded) And
      (Decoded.UsageCaption = 'Credits used: 42%') And (Decoded.UsageHint = View.UsageHint) And
      (Decoded.Model = 'grok-test'));
    Check('usage fields are present', (Pos('"usage_caption"', Payload.AsJSON) > 0) And
      (Pos('"usage_hint"', Payload.AsJSON) > 0));
  Finally
    Payload.Free;
  End;
  Data := GetJSON('{"available":true,"busy":false,"sending":false,"mode_locked":false,"plan_running":false,' +
    '"phase":"idle","status_text":"Ready","model":"grok-test","backend":"native","signed_in":true,' +
    '"approval_caption":"Ask","effort":"high","skill":"","context_text":"ctx","can_send":true,' +
    '"can_steer":false,"can_stop":false,"can_change_mode":true,"remote_approval":false,"error_text":"",' +
    '"usage_caption":1}');
  Try
    Check('usage caption must be text', (Data Is TJSONObject) And (Not TryMonitorStatusFromJson(TJSONObject(Data), Decoded)));
  Finally
    Data.Free;
  End;
End;

Procedure TestOptionalTitle;
Var
  Message: TMonitorMessage;
  ErrorText: String;
  Plan: TMonitorPathMessage;
  Json: String;
Begin
  Json := EncodeMonitorNewPlan('new-plan-empty', '', False);
  Check('new_plan omits title', Pos('"title"', Json) = 0);
  Check('new_plan empty envelope', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkNewPlan));
  Check('new_plan title absent', DecodeMonitorNewPlan(Message.PayloadJson, Plan) And (Not Plan.HasTitle));
End;

Procedure TestUnknownType;
Var
  Message: TMonitorMessage;
  ErrorText: String;
  ErrorBody: TMonitorErrorBody;
  Json: String;
Begin
  Json := '{"v":2,"id":"u1","type":"not_a_type","payload":{}}';
  Check('unknown type decodes as error', TryDecodeMonitorEnvelope(Json, Message, ErrorText));
  Check('unknown type kind', Message.Kind = mmkError);
  Check('unknown type reason', Message.Reason = 'unknown_type');
  Check('unknown type does not change state', Not Message.ChangesState);
  Json := Message.WireJson;
  Check('unknown type error envelope', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkError));
  Check('unknown type error payload', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
    (ErrorBody.Reason = MonitorUnknownTypeReason) And (ErrorBody.RefId = 'u1'));
End;

Procedure TestBadVersion;
Var
  Bytes: RawByteString;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
  PayloadLen: Cardinal;
Begin
  Check('seed frame', TryEncodeMonitorFrame('{"v":1,"id":"v1","type":"ping","payload":{"ticks":1}}', Bytes, Status));
  If Length(Bytes) < MonitorFrameHeaderSize Then
    Exit;
  Bytes[5] := Chr(2);
  Check('bad version inspect', (Not TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status)) And (Status = mfsBadVersion));
  Check('bad version decode', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsBadVersion));
  Check('bad version consume', (Not TryConsumeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsBadVersion));
  Bytes[5] := Chr(0);
  Check('zero version rejected', (Not TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status)) And (Status = mfsBadVersion));
End;

Procedure TestPlanChoices;
Var
  Paths, Captions: TStringList;
  Data: TJSONData;
  Choices: TJSONArray;
Begin
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Paths.Add('Documents/Second.md');
    Paths.Add('Documents/First.md');
    Captions.Add('Second plan (Documents/Second.md)');
    Captions.Add('First plan');
    Data := GetJSON(EncodeMonitorPlan('choices', Paths[1], 'First plan', False, [], Paths, Captions));
    Try
      Choices := TJSONObject(Data).Objects['payload'].Arrays['choices'];
      Check('plan choices preserve desktop order and captions', (Choices.Count = 2) And
        (Choices.Objects[0].Strings['path'] = Paths[0]) And (Choices.Objects[0].Strings['caption'] = Captions[0]) And
        (Choices.Objects[1].Strings['path'] = Paths[1]) And (Choices.Objects[1].Strings['caption'] = Captions[1]));
      Check('active path is independent of choice order', TJSONObject(Data).Objects['payload'].Strings['path'] = Paths[1]);
      Check('plan choices replace file catalogue', Not Assigned(TJSONObject(Data).Objects['payload'].Find('files')));
    Finally
      Data.Free;
    End;
    Paths.Clear;
    Captions.Clear;
    Data := GetJSON(EncodeMonitorPlan('empty', '', '', False, [], Paths, Captions));
    Try
      Check('empty choices are explicit', TJSONObject(Data).Objects['payload'].Arrays['choices'].Count = 0);
    Finally
      Data.Free;
    End;
    Data := GetJSON(EncodeMonitorPlan('ordinary', '', '', False, []));
    Try
      Check('older plan messages may omit choices', Not Assigned(TJSONObject(Data).Objects['payload'].Find('choices')));
    Finally
      Data.Free;
    End;
  Finally
    Captions.Free;
    Paths.Free;
  End;
End;

Procedure TestBufferedFrames;
Var
  Bytes, Pending, Original, Tail: RawByteString;
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  I, ReadOffset, BeforeOffset: Integer;
Begin
  Check('batch frame encoded', TryEncodeMonitorFrame('{"v":3,"id":"batch","type":"ping","payload":{}}', Bytes, Status));
  SetLength(Pending, Length(Bytes) * 1000);
  For I := 0 To 999 Do
    Move(Bytes[1], Pending[I * Length(Bytes) + 1], Length(Bytes));
  Tail := Copy(Bytes, 1, Length(Bytes) - 1);
  Pending := Pending + Tail;
  Original := Pending;
  ReadOffset := 0;
  For I := 1 To 1000 Do
    Begin
      Check('buffered frame ' + IntToStr(I), TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status) And
        (Frame.Json = '{"v":3,"id":"batch","type":"ping","payload":{}}'));
      Check('buffered offset ' + IntToStr(I), ReadOffset = I * Length(Bytes));
    End;
  Check('batch buffer unchanged', Pending = Original);
  BeforeOffset := ReadOffset;
  Check('batch partial tail waits', (Not TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status)) And
    (Status = mfsNeedMore) And (ReadOffset = BeforeOffset));
  Delete(Pending, 1, ReadOffset);
  Check('batch compact retains partial tail', Pending = Tail);
  Pending := Pending + Copy(Bytes, Length(Bytes), 1);
  ReadOffset := 0;
  Check('batch completed tail consumed', TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status) And
    (ReadOffset = Length(Bytes)));
  Pending := Bytes + 'BAD!' + Copy(Bytes, 5, MaxInt);
  ReadOffset := Length(Bytes);
  Check('batch invalid header at offset', (Not TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status)) And
    (Status = mfsBadMagic) And (ReadOffset = Length(Bytes)));
End;

Procedure TestShortFrame;
Var
  Bytes, Pending: RawByteString;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
  PayloadLen: Cardinal;
Begin
  Bytes := '';
  Check('empty frame is short', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsShort));
  Bytes := Copy('LAM1', 1, 3);
  Check('three-byte frame is short', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsShort));
  Bytes := Header(MonitorFrameVersion, 20);
  Check('header without body is short', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsShort));
  Check('short header inspect needs more body later', TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status) And (PayloadLen = 20));
  Pending := Bytes;
  Check('short consume needs more', (Not TryConsumeMonitorFrame(Pending, Frame, Status)) And (Status = mfsNeedMore));
  Check('short consume keeps the header', Pending = Bytes);
End;

Procedure TestLengthCap;
Var
  Bytes, Pending: RawByteString;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
  PayloadLen: Cardinal;
Begin
  { 01 00 00 00 is 16777216 big-endian and 1 little-endian. A host-endian read must not accept it. }
  Bytes := Header(MonitorFrameVersion, 0);
  Bytes[9] := Chr($01);
  Bytes[10] := Chr($00);
  Bytes[11] := Chr($00);
  Bytes[12] := Chr($00);
  Check('high length byte is too large', (Not TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status)) And (Status = mfsTooLarge));
  Check('high length byte decode', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsTooLarge));
  Pending := Bytes;
  Check('high length byte consume', (Not TryConsumeMonitorFrame(Pending, Frame, Status)) And (Status = mfsTooLarge));
  Bytes := Header(MonitorFrameVersion, MonitorMaxPayloadBytes + 1);
  Check('length 262145 inspect', (Not TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status)) And (Status = mfsTooLarge));
  Check('length 262145 decode', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsTooLarge));
  Pending := Bytes;
  Check('length 262145 consume', (Not TryConsumeMonitorFrame(Pending, Frame, Status)) And (Status = mfsTooLarge));
  Check('over-cap body was not required', Length(Bytes) = MonitorFrameHeaderSize);
  Bytes := Header(MonitorFrameVersion, MonitorMaxPayloadBytes);
  Check('length 262144 is allowed', TryInspectMonitorFrameHeader(Bytes, PayloadLen, Status) And (Status = mfsOk) And
    (PayloadLen = MonitorMaxPayloadBytes));
  Check('length 262144 without body is short', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsShort));
End;

Procedure TestBadUtf8;
Var
  Bytes, Pending: RawByteString;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
Begin
  Bytes := Header(MonitorFrameVersion, 1) + #$FF;
  Check('non-utf8 decode', (Not TryDecodeMonitorFrame(Bytes, Frame, Status)) And (Status = mfsBadUtf8));
  Pending := Bytes;
  Check('non-utf8 consume', (Not TryConsumeMonitorFrame(Pending, Frame, Status)) And (Status = mfsBadUtf8));
  Check('non-utf8 encode', (Not TryEncodeMonitorFrame('{"bad":"' + #$FF + '"}', Bytes, Status)) And (Status = mfsBadUtf8));
End;

Procedure TestInboundSingleParse;
Var
  Message, Copied: TMonitorMessage;
  Saved: TMonitorPayload;
  Frame: TMonitorFrame;
  Bytes: RawByteString;
  Status: TMonitorFrameStatus;
  ErrorText, Text: String;
  Data: TJSONData;
  Obj, SavedObject: TJSONObject;
  Kind: TMonitorMessageKind;
Begin
  For Kind := Succ(Low(TMonitorMessageKind)) To High(TMonitorMessageKind) Do
    Check('kind lookup ' + MonitorMessageKindName(Kind), MonitorMessageKindFromName(MonitorMessageKindName(Kind)) = Kind);
  Check('kind lookup empty', MonitorMessageKindFromName('') = mmkUnknown);
  Check('kind lookup case sensitive', MonitorMessageKindFromName('Send') = mmkUnknown);
  Check('kind lookup unknown', MonitorMessageKindFromName('send_more') = mmkUnknown);
  Check('trusted inbound fixture', EncodeMonitorFrameBytes(
    '{"v":2,"id":"once","type":"send","payload":{"text":"hello"}}', Bytes));
  {$IFDEF MONITOR_COUNT_PARSES}
  MonitorJsonParseCount := 0;
  {$ENDIF}
  Check('single parse frame', TryDecodeMonitorFrame(Bytes, Frame, Status) And (Status = mfsOk));
  Check('single parse envelope', TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText));
  Check('single parse text', DecodeMonitorText(Message.PayloadJson, Text) And (Text = 'hello'));
  Check('single parse repeated typed decode', DecodeMonitorText(Message.PayloadJson, Text) And (Text = 'hello'));
  Check('payload is borrowed', ParseMonitorObject(Message.PayloadJson, Data, Obj) And (Data = Nil));
  SavedObject := Obj;
  Copied := Message;
  Saved := Message.PayloadJson;
  Check('overwrite message envelope', TryDecodeMonitorEnvelope(
    '{"v":2,"id":"next","type":"stop","payload":{}}', Message, ErrorText));
  Check('copied message keeps payload', DecodeMonitorText(Copied.PayloadJson, Text) And (Text = 'hello'));
  Copied.PayloadJson := '';
  Check('deferred payload keeps object', ParseMonitorObject(Saved, Data, Obj) And (Obj = SavedObject) And (Data = Nil));
  Check('deferred payload typed decode', DecodeMonitorText(Saved, Text) And (Text = 'hello'));
  {$IFDEF MONITOR_COUNT_PARSES}
  Check('one JSON parse per envelope including typed decodes', MonitorJsonParseCount = 2);
  {$ENDIF}
  Check('failure clears previous message', Not TryDecodeMonitorEnvelope('{', Message, ErrorText));
  Check('failed envelope releases payload', Not Assigned(Message.PayloadJson.Parsed));
End;

Procedure TestBadJsonEnvelope;
Const
  Invalid: Array[0..3] Of String = ('{', '[]', 'null', '{"v":2,"id":"bad","type":"send","payload":[]}');
Var
  I: Integer;
  Bytes, Pending: RawByteString;
  Frame: TMonitorFrame;
  Message: TMonitorMessage;
  Status: TMonitorFrameStatus;
  ErrorText: String;
Begin
  For I := Low(Invalid) To High(Invalid) Do
    Begin
      Bytes := Header(MonitorFrameVersion, Length(Invalid[I])) + Invalid[I];
      Check('bad JSON passes byte frame ' + IntToStr(I), TryDecodeMonitorFrame(Bytes, Frame, Status) And (Status = mfsOk));
      Check('bad JSON rejected by envelope ' + IntToStr(I), Not TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText));
      Pending := Bytes;
      Check('bad JSON consumed as frame ' + IntToStr(I), TryConsumeMonitorFrame(Pending, Frame, Status) And (Pending = ''));
      Check('consumed bad JSON rejected by envelope ' + IntToStr(I), Not TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText));
    End;
  Check('bad JSON validating encoder status', (Not TryEncodeMonitorFrame('{', Bytes, Status)) And (Status = mfsBadJson));
  Check('non-object validating encoder status', (Not TryEncodeMonitorFrame('[]', Bytes, Status)) And (Status = mfsBadJson));
End;

Procedure TestDumpIsNotAProductSwitch;
Const
  Names: Array[0..4] Of String = (
    'AssistantMonitorCodec.pas', 'AssistantMonitorFrames.pas', 'AssistantMonitorSession.pas',
    'AssistantMonitorCarrier.pas', 'AssistantMonitorSettings.pas');
Var
  I: Integer;
  Path, Text: String;
Begin
  For I := 0 To High(Names) Do
    Begin
      Path := IncludeTrailingPathDelimiter(RepositoryRoot) + 'Source' + PathDelim + 'LazAssistantMonitor' + PathDelim + Names[I];
      Text := ReadText(Path);
      Check(Names[I] + ' has no -dump', (Text <> '') And (Pos('-dump', Text) = 0));
    End;
End;

Procedure ParseArguments;
Var
  I: Integer;
Begin
  DumpFixtures := False;
  For I := 1 To ParamCount Do
    If ParamStr(I) = '-dump' Then
      DumpFixtures := True
    Else
      Begin
        WriteLn('Unknown argument: ', ParamStr(I));
        Halt(2);
      End;
End;

Begin
  FailCount := 0;
  ParseArguments;
  Check('magic constant is LAM1', MonitorFrameMagic = 'LAM1');
  Check('catalogue version', MonitorCatalogueVersion = 2);
  Check('payload cap', MonitorMaxPayloadBytes = 262144);
  If RepositoryRoot = '' Then
    Begin
      WriteLn('FAIL repository root');
      Halt(1);
    End;
  TestRoundTrips;
  TestPlanBody;
  TestPlanDocumentFrames;
  TestUsageFields;
  TestModelNote;
  TestPermissionsCaptions;
  TestSetReasoningLevel;
  TestSelectTargetPathIsNotAnId;
  TestPatchOverCap;
  TestLargeChunkPack;
  TestVersion2PatchAndClosed;
  TestOldCatalogue;
  TestDirtyBlocks;
  TestOptionalTitle;
  TestPlanChoices;
  TestUnknownType;
  TestBadVersion;
  TestShortFrame;
  TestBufferedFrames;
  TestLengthCap;
  TestBadUtf8;
  TestBadJsonEnvelope;
  TestInboundSingleParse;
  TestDumpIsNotAProductSwitch;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorCodecTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorCodecTest test(s) failed.');
      Halt(1);
    End;
End.
