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
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantSessionObserve;

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
  View.Model := 'grok-test';
  View.Backend := 'native';
  View.SignedIn := True;
  View.ApprovalCaption := 'Ask';
  View.Effort := 'high';
  View.Skill := '';
  View.ContextText := 'ctx';
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

Procedure BuildSamples;
Var
  View: TAssistantMonitorView;
  Turn: TAssistantMonitorTurn;
  Snapshot: TMonitorSnapshot;
  Transcript: TMonitorTranscript;
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
  AddSample('hello-ok', mmkHelloOk, EncodeMonitorHelloOk('hello-ok', '00112233445566778899aabbccddeeff', 'LazAssistantMonitor'));
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
  AddSample('snapshot', mmkSnapshot, EncodeMonitorSnapshot('snapshot', Snapshot));
  AddSample('refresh', mmkRefresh, EncodeMonitorEmpty(mmkRefresh, 'refresh'));
  Transcript.TurnIndex := 3;
  Transcript.Revision := 2;
  Transcript.Phase := 'streaming';
  Transcript.StatusText := 'Writing';
  Transcript.Part := 1;
  Transcript.PartCount := 1;
  SetLength(Transcript.Blocks, 1);
  Transcript.Blocks[0] := SampleBlock;
  SetLength(Transcript.BlockPart, 1);
  SetLength(Transcript.BlockPartCount, 1);
  Transcript.BlockPart[0] := 1;
  Transcript.BlockPartCount[0] := 1;
  Json := '';
  Check('transcript encodes', TryEncodeMonitorTranscript('transcript', Transcript, Json));
  AddSample('transcript', mmkTranscript, Json);
  AddSample('turn', mmkTurn, EncodeMonitorTurnRequest('turn', 3));
  AddSample('turn-data', mmkTurnData, EncodeMonitorTurnData('turn-data', SampleTurn));
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
  PlanRows[0] := SamplePlanRow;
  AddSample('plan', mmkPlan, EncodeMonitorPlan('plan', 'Documents/Plan.md', 'Monitor plan', False, PlanRows));
  AddSample('select-plan', mmkSelectPlan, EncodeMonitorPath(mmkSelectPlan, 'select-plan', 'Documents/Plan.md'));
  AddSample('new-plan', mmkNewPlan, EncodeMonitorNewPlan('new-plan', 'Monitor plan', True));
  AddSample('remove-plan', mmkRemovePlan, EncodeMonitorPath(mmkRemovePlan, 'remove-plan', 'Documents/Plan.md'));
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
        (HelloOk.Nonce = '00112233445566778899aabbccddeeff') And (HelloOk.ServerName = 'LazAssistantMonitor'));
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
    mmkRefresh, mmkStop, mmkRunPlan, mmkStopPlan, mmkNewConversation:
      Check(Sample.Name + ' empty payload', PayloadIsEmpty(Sample.Json));
    mmkTranscript:
      Check('transcript fields', DecodeMonitorTranscript(Message.PayloadJson, Transcript) And (Transcript.Phase = 'streaming') And
        (Length(Transcript.Blocks) = 1) And (Transcript.Blocks[0].Body = 'Noted.'));
    mmkTurn:
      Check('turn index', DecodeMonitorTurnRequest(Message.PayloadJson, Index) And (Index = 3));
    mmkTurnData:
      Check('turn data', DecodeMonitorTurnData(Message.PayloadJson, Turn) And (Turn.Prompt = 'Show the frame.') And Turn.Live);
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
            Check('status fields', TryMonitorStatusFromJson(Payload, View) And (View.Model = 'grok-test') And View.SignedIn);
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
    mmkSelectPlan, mmkRemovePlan:
      Check(Sample.Name + ' path', DecodeMonitorPath(Message.PayloadJson, Path) And (Path = 'Documents/Plan.md'));
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
    Check(MonitorMessageKindName(Kind) + ' round-trip', Seen[Kind]);
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
  Json := '{"v":1,"id":"u1","type":"not_a_type","payload":{}}';
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

Procedure TestPlanFiles;
Var
  Files: TStringList;
  Data: TJSONData;
  Payload: TJSONObject;
  FileArray: TJSONArray;
Begin
  Files := TStringList.Create;
  Try
    Files.Add('Documents/Plan.md');
    Files.Add('Source/Notes.markdown');
    Data := GetJSON(EncodeMonitorPlan('browse', 'Documents/Plan.md', 'Plan', False, [], Files));
    Try
      Payload := TJSONObject(Data).Objects['payload'];
      FileArray := Payload.Arrays['files'];
      Check('Markdown catalogue includes project-relative paths', (FileArray.Count = 2) And
        (FileArray.Strings[0] = Files[0]) And (FileArray.Strings[1] = Files[1]));
    Finally
      Data.Free;
    End;
    Files.Clear;
    Data := GetJSON(EncodeMonitorPlan('empty', '', '', False, [], Files));
    Try
      Check('empty catalogue is explicit', TJSONObject(Data).Objects['payload'].Arrays['files'].Count = 0);
    Finally
      Data.Free;
    End;
    Data := GetJSON(EncodeMonitorPlan('ordinary', '', '', False, []));
    Try
      Check('ordinary plan notices omit catalogue', Not Assigned(TJSONObject(Data).Objects['payload'].Find('files')));
    Finally
      Data.Free;
    End;
  Finally
    Files.Free;
  End;
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
  Check('catalogue version', MonitorCatalogueVersion = 1);
  Check('payload cap', MonitorMaxPayloadBytes = 262144);
  If RepositoryRoot = '' Then
    Begin
      WriteLn('FAIL repository root');
      Halt(1);
    End;
  TestRoundTrips;
  TestOptionalTitle;
  TestPlanFiles;
  TestUnknownType;
  TestBadVersion;
  TestShortFrame;
  TestLengthCap;
  TestBadUtf8;
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
