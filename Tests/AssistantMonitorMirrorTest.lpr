Program AssistantMonitorMirrorTest;

{ The monitor log keeps each conversation, folds old events into the model, and pages a snapshot.
  State chunks and prompt previews are cut between UTF-8 characters (plan item 2.3).
  Observing a turn leaves the caller's record untouched (plan item 3.2).
  An event that cannot be stored still advances the head and is noted as a drop (plan item 4.1).
  Only the four newest parked conversations are kept (plan item 4.3).
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, fpjson, jsonparser, AssistantSessionObserve, AssistantMonitorMirror, AssistantMonitorFrames,
  AssistantMonitorOutbox, AssistantMonitorSync;

Const
  { The euro sign, three bytes in UTF-8. }
  Euro = #$E2#$82#$AC;

Var
  FailCount: Integer;

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

{ Byte comparison. No code page conversion on either side. }
Function SameBytes(Const Left, Right: RawByteString): Boolean;
Begin
  Result := (Length(Left) = Length(Right)) And ((Length(Left) = 0) Or (CompareByte(Left[1], Right[1], Length(Left)) = 0));
End;

{ Appends bytes with Move, so the join is not converted between code pages. }
Procedure AppendBytes(Var Target: RawByteString; Const Piece: RawByteString);
Var
  Start: Integer;
Begin
  If Piece = '' Then
    Exit;
  Start := Length(Target);
  SetLength(Target, Start + Length(Piece));
  Move(Piece[1], Target[Start + 1], Length(Piece));
End;

Function SampleTurn(Const TurnId, Body: String; TurnIndex: Integer): TAssistantMonitorTurn;
Begin
  Result := Default(TAssistantMonitorTurn);
  Result.TurnIndex := TurnIndex;
  Result.Id := TurnId;
  Result.Mode := 'build';
  Result.Prompt := 'prompt';
  Result.PromptPreview := 'prompt';
  Result.CreatedAt := '2026-01-01T00:00:00Z';
  SetLength(Result.Blocks, 1);
  Result.Blocks[0].Kind := 'answer';
  Result.Blocks[0].BlockId := TurnId + '-block';
  Result.Blocks[0].Body := Body;
  Result.Blocks[0].Ok := True;
  SetLength(Result.Images, 1);
  Result.Images[0].Id := TurnId + '-image';
  Result.Images[0].Name := 'shot.png';
  Result.Images[0].Mime := 'image/png';
End;

Procedure TestFoldAndReplay;
Var
  Log: TMonitorMirror;
  Turn: TAssistantMonitorTurn;
  Pages: TMonitorSnapshotPageArray;
  Suffix: String;
  Offset: Integer;
Begin
  Log := TMonitorMirror.Create;
  Try
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    Check('a new stream is not a conversation yet', Not Log.HasConversation);
    Log.ObserveTurn(SampleTurn('turn-a', StringOfChar('x', MonitorInlineBodyBytes + 1), 0));
    Check('an observed turn is the open conversation', Log.HasConversation);
    Check('model keeps full bodies', Log.FetchTurn(0, Turn) And (Length(Turn.Blocks[0].Body) = MonitorInlineBodyBytes + 1));
    Check('snapshot pages contain the turn list', Log.BuildSnapshotPages('ab12cd34', Log.Head, Pages) And
      (Length(Pages) >= 2) And (Pos('"turns":', Pages[0].Json) > 0));
    Check('a large body is deferred', Pos('"deferred":true', Pages[1].Json) > 0);
    Check('UTF-8 append offset is in bytes', MonitorAppendSuffix('Größe → ', 'Größe → 10 s.', Suffix, Offset) And
      (Offset = 12) And (Suffix = '10 s.'));
    Check('a changed prefix is not an append', Not MonitorAppendSuffix('old text', 'new text', Suffix, Offset));
  Finally
    Log.Free;
  End;
End;

{ A body of Size bytes with a quote, a backslash, a newline and a #1 in every thousand. }
Function MarkedBody(Size: Integer): String;
Var
  Index: Integer;
Begin
  Result := StringOfChar('a', Size);
  For Index := 1 To Length(Result) Do
    Case Index Mod 1000 Of
      0: Result[Index] := '"';
      1: Result[Index] := '\';
      2: Result[Index] := #10;
      3: Result[Index] := #1;
    Else
      ;
    End;
End;

Function IsJson(Const Text: String): Boolean;
Var
  Data: TJSONData;
Begin
  Try
    Data := GetJSON(Text);
    Result := Data <> Nil;
    Data.Free;
  Except
    Result := False;
  End;
End;

{ A large append to a live block is cut into block_append slices in linear time. Each slice fits a page, is
  valid JSON, and the slices join back to the appended text. AssistantMonitorLinkTest appends 800 KiB this way;
  the quadratic cut took about 55 s on the IDE thread and tripped the 30 s heartbeat. }
Procedure TestLargeAppend;
Var
  Log: TMonitorMirror;
  Turn: TAssistantMonitorTurn;
  Events: TMonitorMirrorEventArray;
  Data: TJSONData;
  Started: QWord;
  Index, Appends, First: Integer;
  Fits: Boolean;
  Added, Joined: String;
Begin
  Log := TMonitorMirror.Create;
  Try
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    Turn := SampleTurn('turn-big', 'start', 1);
    Turn.Live := True;
    Turn.Blocks[0].Running := True;
    Log.ObserveTurn(Turn);
    Log.CopyEvents(Events);
    First := Length(Events);
    Added := MarkedBody(800 * 1024);
    Turn.Blocks[0].Body := 'start' + Added;
    Started := GetTickCount64;
    Log.ObserveTurn(Turn);
    Check('an 800 KiB append is sliced in under 2 s', GetTickCount64 - Started < 2000);
    Log.CopyEvents(Events);
    Appends := 0;
    Fits := True;
    Joined := '';
    For Index := First To High(Events) Do
      If Events[Index].Kind = 'block_append' Then
        Begin
          Inc(Appends);
          Fits := Fits And (Length(Events[Index].Data) + 256 <= MonitorSnapshotPageBytes);
          Data := Nil;
          Try
            Data := GetJSON(String(Events[Index].Data));
            If Data Is TJSONObject Then
              Joined := Joined + TJSONObject(Data).Get('text', '')
            Else
              Fits := False;
          Except
            Fits := False;
          End;
          Data.Free;
        End;
    Check('the append is cut into slices', Appends >= Length(Added) Div MonitorAppendSliceBytes);
    Check('every slice fits a page and is valid JSON', Fits);
    Check('the slices join back to the appended text', Joined = Added);
  Finally
    Log.Free;
  End;
End;

Procedure TestBodyEscape;
Var
  Page: String;
  Started: QWord;
Begin
  Started := GetTickCount64;
  Page := MonitorTurnPageJson('conversation-a', 'ab12cd34', 1, SampleTurn('turn-big', MarkedBody(200000), 2));
  Check('a quoted body escapes in one pass', (GetTickCount64 - Started < 2000) And (Page <> ''));
  { A body over MonitorInlineBodyBytes is deferred and left out of the page, so the escapes are checked on one that fits. }
  Page := MonitorTurnPageJson('conversation-a', 'ab12cd34', 1, SampleTurn('turn-esc', MarkedBody(MonitorInlineBodyBytes - 1024), 2));
  Check('the escape body is sent inline', Pos('"deferred":false', Page) > 0);
  Check('quotes, slashes, and newlines are escaped', (Pos('\"', Page) > 0) And (Pos('\\', Page) > 0) And (Pos('\n', Page) > 0));
  { Plan item 2.1: every control below #32 is escaped, so the page is valid JSON. }
  Check('other controls are escaped', (Pos(#1, Page) = 0) And (Pos('\u0001', Page) > 0));
  Check('the escaped page is valid JSON', IsJson(Page));
End;

Procedure TestLiveBlocks;
Var
  Log: TMonitorMirror;
  Turn: TAssistantMonitorTurn;
  Blocks: TAssistantMonitorBlockArray;
Begin
  Log := TMonitorMirror.Create;
  Try
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    SetLength(Blocks, 1);
    Check('no live turn has no blocks', (Not Log.CopyLiveBlocks(Blocks)) And (Length(Blocks) = 0));
    Turn := SampleTurn('live', 'hello', -2);
    Turn.Live := True;
    Log.ObserveTurn(Turn);
    Check('live blocks are the observed body', Log.CopyLiveBlocks(Blocks) And (Length(Blocks) = 1) And
      (Blocks[0].BlockId = 'live-block') And (Blocks[0].Body = 'hello'));
    Turn.Blocks[0].Body := 'hello!';
    Log.ObserveTurn(Turn);
    Check('a longer live body is the new face', Log.CopyLiveBlocks(Blocks) And (Length(Blocks) = 1) And
      (Blocks[0].Body = 'hello!'));
  Finally
    Log.Free;
  End;
End;

{ Plan item 3.2. The same turn is observed twice with a changed body. The mirror bumps the block revision in its
  own copy. The caller's record, and a second record that shares its arrays as the session's observed snapshot
  does, still hold the original revision. }
Procedure TestObserveLeavesCallerAlone;
Var
  Log: TMonitorMirror;
  Turn, Shared: TAssistantMonitorTurn;
  Live: Boolean;
  Name, BlockId, Body: String;
Begin
  For Live := False To True Do
    Begin
      If Live Then
        Name := 'live turn'
      Else
        Name := 'stored turn';
      Log := TMonitorMirror.Create;
      Try
        Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
        Turn := SampleTurn('turn-r', 'first', 0);
        Turn.Live := Live;
        Turn.Blocks[0].Revision := 7;
        BlockId := Turn.Blocks[0].BlockId;
        Log.ObserveTurn(Turn);
        Check('a new ' + Name + ' keeps the caller revision in the mirror', Log.BlockRevision(BlockId) = 7);
        Turn.Blocks[0].Body := 'first, then more';
        Shared := Turn;
        Log.ObserveTurn(Turn);
        Check('a changed ' + Name + ' bumps the mirror revision', Log.BlockRevision(BlockId) = 8);
        Check('the caller''s ' + Name + ' keeps its original revision', Turn.Blocks[0].Revision = 7);
        Check('a record sharing the ' + Name + ' arrays keeps its original revision', Shared.Blocks[0].Revision = 7);
        Body := '';
        Check('the mirror holds the changed ' + Name + ' body', Log.FetchBlock(BlockId, Body) And
          (Body = 'first, then more'));
      Finally
        Log.Free;
      End;
    End;
End;

{ The payload object of an encoded frame, or Nil. The caller frees Root. }
Function FramePayload(Const Json: String; Out Root: TJSONData): TJSONObject;
Begin
  Result := Nil;
  Root := Nil;
  Try
    Root := GetJSON(Json);
  Except
    Root := Nil;
  End;
  If (Root Is TJSONObject) And (TJSONObject(Root).Find('payload') Is TJSONObject) Then
    Result := TJSONObject(TJSONObject(Root).Find('payload'));
End;

Procedure TestUtf8CutHelper;
Begin
  Check('a cut inside a character steps back to its start', MonitorUtf8CutLength('a' + Euro + 'b', 2) = 1);
  Check('a cut one byte short of the end of a character steps back', MonitorUtf8CutLength('a' + Euro + 'b', 3) = 1);
  Check('a cut on a boundary is kept', MonitorUtf8CutLength('a' + Euro + 'b', 4) = 4);
  Check('a short text is kept whole', MonitorUtf8CutLength('a' + Euro, 80) = 4);
  Check('a limit inside the first character keeps that character', MonitorUtf8CutLength(Euro + 'b', 1) = 3);
  Check('a zero limit keeps nothing', MonitorUtf8CutLength('abc', 0) = 0);
End;

{ Plan item 2.3. A state value over 32 KiB of 3-byte characters is cut into chunks that each encode, and the
  chunk data joins back to the exact value. The value starts with six ASCII bytes, so a cut every 20000 bytes
  would fall inside a character. }
Procedure TestStateChunksKeepCharacters;
Var
  Value: String;
  Joined, Piece: RawByteString;
  Frames: TStringArray;
  Index, Encoded, Fitted, Counted: Integer;
  Bytes: RawByteString;
  Status: TMonitorFrameStatus;
  Root: TJSONData;
  Payload: TJSONObject;
Begin
  Value := '{"t":"';
  For Index := 1 To 12000 Do
    Value := Value + Euro;
  Value := Value + '"}';
  Check('the state value is over 32 KiB', Length(Value) > 32 * 1024);
  Frames := MonitorSyncStateFrames('h1', 'conversations', Value);
  Check('the value is sent as more than one chunk', Length(Frames) > 1);
  Joined := '';
  Encoded := 0;
  Fitted := 0;
  Counted := 0;
  For Index := 0 To High(Frames) Do
    Begin
      If TryEncodeMonitorFrame(Frames[Index], Bytes, Status) Then
        Inc(Encoded);
      If Length(Frames[Index]) <= MonitorOutboxChunkBytes Then
        Inc(Fitted);
      Payload := FramePayload(Frames[Index], Root);
      Try
        If Assigned(Payload) Then
          Begin
            If Payload.Get('part_count', 0) = Length(Frames) Then
              Inc(Counted);
            Piece := RawByteString(Payload.Get('data', ''));
            AppendBytes(Joined, Piece);
          End;
      Finally
        Root.Free;
      End;
    End;
  Check('every chunk encodes as a LAM1 frame', Encoded = Length(Frames));
  Check('every chunk fits the outbox chunk size', Fitted = Length(Frames));
  Check('every chunk names the real part count', Counted = Length(Frames));
  Check('the joined chunk data is the value', SameBytes(Joined, RawByteString(Value)));
End;

{ Plan item 2.3. A prompt whose 80th byte is inside a character still gives a snapshot page that encodes,
  and its preview is the prompt cut at the last whole character. }
Procedure TestPreviewKeepsCharacters;
Var
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
  Expected: String;
  Index, PageIndex: Integer;
  Bytes: RawByteString;
  FrameStatus: TMonitorFrameStatus;
  Root: TJSONData;
  Payload: TJSONObject;
  Turns: TJSONArray;
  Preview: RawByteString;
Begin
  Source := Default(TMonitorResumeSource);
  Source.Found := True;
  Source.Observed := True;
  Source.ConversationId := 'conversation-a';
  Source.StreamId := 'ab12cd34';
  Source.HasLive := True;
  Source.Live := SampleTurn('live', 'hello', -2);
  { One ASCII byte, then euro signs. Bytes 80 to 82 are the 27th euro sign. }
  Source.Live.Prompt := 'a';
  For Index := 1 To 30 Do
    Source.Live.Prompt := Source.Live.Prompt + Euro;
  Expected := 'a';
  For Index := 1 To 26 Do
    Expected := Expected + Euro;
  Status := Default(TMonitorSyncStatus);
  Answer := MonitorSyncResumeAnswer(Source, 'conversation-a', '', 'resume-1', 0, Status);
  PageIndex := -1;
  For Index := 0 To High(Answer.Frames) Do
    If Answer.Frames[Index].Kind = mskBulk Then
      PageIndex := Index;
  Check('the resume answer has a snapshot page', PageIndex >= 0);
  If PageIndex < 0 Then
    Exit;
  Check('the snapshot page encodes as a LAM1 frame', TryEncodeMonitorFrame(Answer.Frames[PageIndex].Json, Bytes, FrameStatus));
  Preview := '';
  Payload := FramePayload(Answer.Frames[PageIndex].Json, Root);
  Try
    If Assigned(Payload) And (Payload.Find('turns') Is TJSONArray) Then
      Begin
        Turns := TJSONArray(Payload.Find('turns'));
        If (Turns.Count > 0) And (Turns.Items[0] Is TJSONObject) Then
          Preview := RawByteString(TJSONObject(Turns.Items[0]).Get('prompt_preview', ''));
      End;
  Finally
    Root.Free;
  End;
  Check('the preview stops at the last whole character', SameBytes(Preview, RawByteString(Expected)));
  Check('the preview is at most 80 bytes', Length(Preview) <= 80);
End;

Procedure TestLargeResumePages;
Var
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
  Outbox: TMonitorOutbox;
  Index, BlockIndex, Pages, Taken, TurnIndex, Blocks: Integer;
  Root: TJSONData;
  Payload, Turn: TJSONObject;
  Turns: TJSONArray;
  Bytes: RawByteString;
  FrameStatus: TMonitorFrameStatus;
  Lane: TMonitorOutboxLane;
Begin
  Source := Default(TMonitorResumeSource);
  Source.Found := True;
  Source.Observed := True;
  Source.ConversationId := 'large-chat';
  Source.StreamId := 'ab12cd34';
  SetLength(Source.Turns, 30);
  For Index := 0 To High(Source.Turns) Do
    Begin
      Source.Turns[Index] := SampleTurn('turn-' + IntToStr(Index), 'reply', Index);
      SetLength(Source.Turns[Index].Blocks, 300);
      For BlockIndex := 0 To High(Source.Turns[Index].Blocks) Do
        Begin
          Source.Turns[Index].Blocks[BlockIndex].BlockId := 'block-' + IntToStr(Index) + '-' + IntToStr(BlockIndex);
          Source.Turns[Index].Blocks[BlockIndex].Kind := 'answer';
        End;
    End;
  Status := Default(TMonitorSyncStatus);
  Answer := MonitorSyncResumeAnswer(Source, '', '', 'large-resume', 0, Status);
  Pages := 0;
  Blocks := 0;
  Outbox := TMonitorOutbox.Create;
  Try
    For Index := 0 To High(Answer.Frames) Do
      If Answer.Frames[Index].Kind = mskBulk Then
        Begin
          Inc(Pages);
          Payload := FramePayload(Answer.Frames[Index].Json, Root);
          Try
            Turns := TJSONArray(Payload.Find('turns'));
            For TurnIndex := 0 To Turns.Count - 1 Do
              Begin
                Turn := TJSONObject(Turns.Items[TurnIndex]);
                Inc(Blocks, TJSONArray(Turn.Find('blocks')).Count);
              End;
            Check('outline page count matches the begin frame',
              Payload.Get('page_count', 0) = Length(Answer.Frames) - 2);
          Finally
            Root.Free;
          End;
          If TryEncodeMonitorFrame(Answer.Frames[Index].Json, Bytes, FrameStatus) Then
            Outbox.AddGeneratedBulk(Bytes, Answer.Generation);
        End;
    Taken := 0;
    While Outbox.Take(Bytes, Lane) Do
      Inc(Taken);
    Check('a large conversation is paged', Pages > 1);
    Check('paging preserves every block of every turn', Blocks = 9000);
    Check('every large conversation page survives the outbox', (Pages > 0) And (Taken = Pages));
  Finally
    Outbox.Free;
  End;
End;

{ Plan item 4.1. A log full of unacknowledged events cannot drop the oldest to make room. The event that
  will not fit must still advance the head and move DroppedThrough, so a phone resuming from an older
  sequence takes a snapshot instead of a replay that looks complete. }
Procedure TestUnstoredEventRecordsDrop;
Var
  Log: TMonitorMirror;
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
  Turn: TAssistantMonitorTurn;
  BeforeHead: Int64;
Begin
  Log := TMonitorMirror.Create;
  Try
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    Log.ObserveTurn(SampleTurn('turn-a', 'body', 0));
    Log.SetLogBudget(64);
    Check('the unacked log is already over the small budget', Log.ByteCount > 64);
    Check('nothing has been dropped yet', Log.DroppedThrough = 0);
    BeforeHead := Log.Head;
    { No NoteAck. The oldest event stays, so the next append cannot be stored. }
    Log.SetTitle('Two');
    Log.SetTitle('Three');
    Check('an event that cannot be stored moves DroppedThrough', Log.DroppedThrough = BeforeHead + 2);
    Check('an event that cannot be stored advances the head', Log.Head = BeforeHead + 2);
    Check('the model still holds the observed turn', Log.FetchTurn(0, Turn) And (Turn.Id = 'turn-a'));
    Check('the resume source is the open conversation', Log.CaptureResume('conversation-a', Source) And Source.Found And
      Source.Observed And (Source.DroppedThrough = Log.DroppedThrough));
    Status := Default(TMonitorSyncStatus);
    Answer := MonitorSyncResumeAnswer(Source, 'conversation-a', 'ab12cd34', 'resume-old', 0, Status);
    Check('a resume from an old sequence is not a replay', Not Answer.Replay);
    Check('a resume from an old sequence is a snapshot', (Not Answer.NotReady) And (Length(Answer.Frames) >= 1) And
      (Pos('"type":"snapshot_begin"', Answer.Frames[0].Json) > 0));
    Check('the snapshot carries the title the log could not store', Pos('"title":"Three"', Answer.Frames[0].Json) > 0);
    Answer := MonitorSyncResumeAnswer(Source, 'conversation-a', 'ab12cd34', 'resume-now', Source.Head, Status);
    Check('a resume at the head is still a replay', Answer.Replay And (Not Answer.NotReady));
  Finally
    Log.Free;
  End;
End;

{ Plan item 4.3. Six parked conversations leave only the four newest. A resume of the oldest is not ready,
  so the phone takes a snapshot instead of a log that no longer exists. }
Procedure TestParkedConversationsAreBounded;
Var
  Log: TMonitorMirror;
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
  Index: Integer;
  Id: String;
Begin
  Log := TMonitorMirror.Create;
  Try
    For Index := 1 To 6 Do
      Begin
        Id := 'conversation-' + IntToStr(Index);
        Log.BeginStream('stream' + IntToStr(Index), Id, '/work', 'Title ' + IntToStr(Index));
        Log.ObserveTurn(SampleTurn('turn-' + IntToStr(Index), 'body', Index));
      End;
    { The seventh stream parks the sixth. Six conversations have been parked. }
    Log.BeginStream('stream7', 'conversation-7', '/work', 'Title 7');
    For Index := 1 To 2 Do
      Check('parked conversation ' + IntToStr(Index) + ' was dropped',
        Not Log.CaptureResume('conversation-' + IntToStr(Index), Source));
    For Index := 3 To 6 Do
      Check('parked conversation ' + IntToStr(Index) + ' is kept',
        Log.CaptureResume('conversation-' + IntToStr(Index), Source) And Source.Found And Source.Observed);
    Check('the open conversation is not one of the parked four', Log.CaptureResume('conversation-7', Source) And Source.Found);
    Status := Default(TMonitorSyncStatus);
    Log.CaptureResume('conversation-1', Source);
    Answer := MonitorSyncResumeAnswer(Source, 'conversation-1', 'stream1', 'resume-old', 0, Status);
    Check('resuming the oldest parked conversation is not ready', Answer.NotReady);
    Check('resuming the oldest parked conversation is not a replay', Not Answer.Replay);
  Finally
    Log.Free;
  End;
End;

{ A generous five-second bound catches quadratic fill/replay while allowing shared CI hosts. }
Procedure TestIndexedTailTiming;
Const
  EventCount = 20000;
  TimeLimitMs = 5000;
Var
  Log: TMonitorMirror;
  Outbox: TMonitorOutbox;
  Events: TMonitorMirrorEventArray;
  Event: TMonitorMirrorEvent;
  Index, Taken: Integer;
  Queued, Previous, Head: Int64;
  Started, Elapsed: QWord;
  CloseLink: Boolean;
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Log := TMonitorMirror.Create;
  Outbox := TMonitorOutbox.Create;
  Try
    Log.BeginStream('ab12cd34', 'timing', '/work', 'Timing');
    For Index := 1 To EventCount Do Log.SetTitle('Title ' + IntToStr(Index));
    Started := GetTickCount64;
    Queued := 0;
    Taken := 0;
    While Queued < EventCount Do
      Begin
        Previous := Queued;
        MonitorSyncFill(Log, Outbox, 'timing', 'ab12cd34', Previous, Queued, CloseLink);
        If CloseLink Or (Queued = Previous) Then Break;
        While Outbox.Take(Frame, Lane) Do Inc(Taken);
        Outbox.Acknowledge(Queued);
      End;
    Check('20,000 events fill in credit-sized batches', (Queued = EventCount) And (Taken = EventCount) And Not CloseLink);
    Check('indexed tail can replay', MonitorSyncCanReplay(Log, 0));
    Check('20,000 events remain available', (Log.CopyEvents(Events) = EventCount) And
      (Events[0].Seq = 1) And (Events[High(Events)].Seq = EventCount));
    Elapsed := GetTickCount64 - Started;
    WriteLn('20,000-event fill and replay: ', Elapsed, ' ms (bound ', TimeLimitMs, ' ms)');
    Check('fill and replay stay under timing bound', Elapsed < TimeLimitMs);
    Outbox.Acknowledge(Queued);
    Check('ack removes running log bytes', Outbox.LogPayloadBytes = 0);
    { Exercise retired storage, compaction and copies, then a gap followed by a valid suffix. }
    Log.NoteAck('ab12cd34', EventCount);
    Log.SetLogBudget(800000);
    For Index := EventCount + 1 To EventCount * 2 Do Log.SetTitle('Title ' + IntToStr(Index));
    Log.CopyEvents(Events);
    Check('retired head is excluded from copies', (Events[0].Seq > 1) And (Events[High(Events)].Seq = EventCount * 2));
    Check('indexed lookup survives drops and compaction', Log.TryEvent(EventCount * 2, Event) And (Event.Seq = EventCount * 2));
    Log.SetLogBudget(1);
    Log.SetTitle('Gap');
    Log.SetLogBudget(1000000);
    Log.SetTitle('After gap');
    Check('a gap prevents replay across it', Not MonitorSyncCanReplay(Log, EventCount * 2));
    Check('suffix after a gap remains replayable', MonitorSyncCanReplay(Log, EventCount * 2 + 1) And
      Log.TryEvent(EventCount * 2 + 2, Event));
  Finally
    Outbox.Free;
    Log.Free;
  End;
End;

Begin
  FailCount := 0;
  TestIndexedTailTiming;
  TestFoldAndReplay;
  TestUnstoredEventRecordsDrop;
  TestParkedConversationsAreBounded;
  TestBodyEscape;
  TestLargeAppend;
  TestLiveBlocks;
  TestObserveLeavesCallerAlone;
  TestUtf8CutHelper;
  TestStateChunksKeepCharacters;
  TestPreviewKeepsCharacters;
  TestLargeResumePages;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorMirrorTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failure(s)');
      Halt(1);
    End;
End.
