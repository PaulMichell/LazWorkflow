Unit AssistantMonitorMirror;

{ Per-conversation event log and materialised model (c) 2026 Michell Computing.

  Plan item 5.3 of Documents/Plan-20261029-035918.md. The IDE thread appends
  events. A resume or a snapshot notice also builds snapshot pages on that
  thread. The connection thread replays the tail and fetches a turn from the
  model. It does not read the form. Older events are dropped once the log
  passes its byte budget; the model already holds their effect.

  Catalogue 2 patch tails live in the same log so resume can replay them.
  Item 5.6 stopped sending snapshot, transcript, and turn_data; pages replace
  those frames. A patch larger than the budget is not stored.
  Resume behind a dropped record needs a snapshot.

  ObserveTurn never writes into the turn it is given. Its arrays are shared
  with the caller's snapshot, which another thread may read (plan item 3.2 of
  Documents/Plan-20261105-130659.md). It bumps revisions on its own copy.

  Size note: exceeds the 1000 line preference. What remains is the log, the
  materialised model, and the slice split. Page JSON writers with no caller are
  gone. The log-credit class stays because the mirror test still constructs it.
  Reviewed 2026-11-05: strings are escaped by AssistantProtocol.JsonEscapeText,
  which escapes every control and writes one pass into a sized buffer, because
  those pages are built on the IDE thread. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantSessionObserve;

Const
  MonitorLogBudgetBytes = 8 * 1024 * 1024;
  MonitorSnapshotPageBytes = 32 * 1024;
  { One block page must stay under MonitorSnapshotPageBytes, or the phone drops it. }
  MonitorInlineBodyBytes = 8 * 1024;
  MonitorBlockDataBytes = 24 * 1024;
  MonitorCreditWindowBytes = 524288;
  MonitorAckIntervalMs = 250;
  { One block_append slice. A larger new body is one deferred block_replace. }
  MonitorAppendSliceBytes = 4096;

{ True when Current is Previous plus a suffix. Offset is the UTF-8 byte length of Previous. }
Function MonitorAppendSuffix(Const Previous, Current: String; Out Suffix: String; Out Offset: Integer): Boolean;
{ One snapshot_page payload for a turn fetch. Nothing in the body is truncated. }
Function MonitorTurnPageJson(Const ConversationId, StreamId: String; Seq: Int64; Const Turn: TAssistantMonitorTurn): String;

Type
  TMonitorMirrorEvent = Record
    Seq: Int64;
    Kind: String;
    Data: RawByteString;
  End;
  TMonitorMirrorEventArray = Array Of TMonitorMirrorEvent;

  TMonitorSnapshotPage = Record
    Page: Integer;
    PageCount: Integer;
    Json: String;
  End;
  TMonitorSnapshotPageArray = Array Of TMonitorSnapshotPage;
  TMonitorMirrorTurnArray = Array Of TAssistantMonitorTurn;
  TMonitorMirrorPlanArray = Array Of TAssistantMonitorPlanRow;

  TMonitorResumeSource = Record
    Found: Boolean;
    Observed: Boolean;
    ConversationId: String;
    StreamId: String;
    ProjectRoot: String;
    Title: String;
    Head: Int64;
    DroppedThrough: Int64;
    HasLive: Boolean;
    Live: TAssistantMonitorTurn;
    Turns: Array Of TAssistantMonitorTurn;
    Events: TMonitorMirrorEventArray;
  End;

  TMonitorMirrorPark = Record
    ConversationId: String;
    StreamId: String;
    ProjectRoot: String;
    Title: String;
    Head: Int64;
    AckedSeq: Int64;
    DroppedThrough: Int64;
    Bytes: Int64;
    Events: TMonitorMirrorEventArray;
    Turns: Array Of TAssistantMonitorTurn;
    Live: TAssistantMonitorTurn;
    HasLive: Boolean;
    PlanPath: String;
    PlanTitle: String;
    PlanRunning: Boolean;
    PlanRows: Array Of TAssistantMonitorPlanRow;
  End;

  TMonitorMirror = Class
  Private
    FLock: TRTLCriticalSection;
    FBudget: Int64;
    FConversationId: String;
    FStreamId: String;
    FProjectRoot: String;
    FTitle: String;
    FHead: Int64;
    FAckedSeq: Int64;
    FDroppedThrough: Int64;
    FBytes: Int64;
    FEvents: TMonitorMirrorEventArray;
    FTurns: Array Of TAssistantMonitorTurn;
    FLive: TAssistantMonitorTurn;
    FHasLive: Boolean;
    FPlanPath: String;
    FPlanTitle: String;
    FPlanRunning: Boolean;
    FPlanRows: Array Of TAssistantMonitorPlanRow;
    FParked: Array Of TMonitorMirrorPark;
    Function DropOldestLocked: Boolean;
    Procedure NoteDropLocked(Seq: Int64);
    Procedure ParkCurrentLocked;
    Function UnparkLocked(Const ConversationId, StreamId: String): Boolean;
    Procedure AppendLocked(Seq: Int64; Const Kind: String; Const Data: RawByteString);
    Function IndexOfSeqLocked(Seq: Int64): Integer;
    Function PatchIndexLocked(Seq: Int64): Integer;
    Procedure CopyTurn(Const Source: TAssistantMonitorTurn; Var Dest: TAssistantMonitorTurn);
    Function FindTurnLocked(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
  Public
    Constructor Create; Overload;
    Constructor Create(BudgetBytes: Int64); Overload;
    Destructor Destroy; Override;
    { New stream. The previous conversation's events are not this stream. }
    Procedure BeginStream(Const StreamId, ConversationId, ProjectRoot, Title: String);
    Procedure SetTitle(Const Title: String);
    Procedure RememberPatch(Seq: Int64; Const PatchJson: RawByteString);
    { True when every patch after Seq is still in the log. Seq equal to the head is an empty tail. }
    Function TryReplayPatches(Const StreamId: String; Seq, ThroughSeq: Int64; Out Events: TMonitorMirrorEventArray; Out Head: Int64): Boolean;
    { Copy of the log. Tests read the grain without sending it. }
    Function CopyEvents(Out Events: TMonitorMirrorEventArray): Integer;
    { Turn is read only. The stored copy carries the bumped block revisions. }
    Procedure ObserveTurn(Const Turn: TAssistantMonitorTurn);
    Procedure ObservePlan(Const PlanPath, PlanTitle: String; PlanRunning: Boolean; Const Rows: Array Of TAssistantMonitorPlanRow);
    Function HasModel: Boolean;
    { Stored turns or the live turn. A plan alone is not the open conversation. }
    Function HasConversation: Boolean;
    Function CopyTurns(Out Stored: TMonitorMirrorTurnArray; Out Live: TAssistantMonitorTurn; Out HasLive: Boolean): Boolean;
    { Live block faces only. The pump reuses these bodies when length and running are unchanged. }
    Function CopyLiveBlocks(Out Blocks: TAssistantMonitorBlockArray): Boolean;
    { Harness fold. A later append drops events that no longer fit. }
    Procedure SetLogBudget(Bytes: Int64);
    { One locked copy of the open or parked conversation. Encode after this returns. }
    Function CaptureResume(Const ConversationId: String; Out Source: TMonitorResumeSource): Boolean;
    Function CopyPlan(Out PlanPath, PlanTitle: String; Out PlanRunning: Boolean; Out Rows: TMonitorMirrorPlanArray): Boolean;
    Function BuildSnapshotPages(Const StreamId: String; HeadSeq: Int64; Out Pages: TMonitorSnapshotPageArray): Boolean;
    Function FetchTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
    Function FetchBlock(Const BlockId: String; Out Body: String): Boolean;
    Function BlockRevision(Const BlockId: String): Integer;
    Function DroppedThrough: Int64;
    Function Head: Int64;
    Function ByteCount: Int64;
    Procedure NoteAck(Const StreamId: String; Seq: Int64);
    Function AckedSeq: Int64;
  End;

  { Send window for log frames. The caller holds the session lock. }
  TMonitorLogCredit = Class
  Private
    FUnacked: Int64;
    FSentSeq: Array Of Int64;
    FSentBytes: Array Of Integer;
    FHeldSeq: Array Of Int64;
    FHeldJson: Array Of String;
    FHeldBytes: Int64;
  Public
    Constructor Create;
    Function CanSend(Bytes: Integer): Boolean;
    Procedure NoteSent(Seq: Int64; Bytes: Integer);
    Procedure NoteAck(Seq: Int64);
    Procedure Hold(Seq: Int64; Const Json: String);
    Function TakeHeld(Out Seq: Int64; Out Json: String): Boolean;
    Function UnackedBytes: Int64;
    Function HeldBytes: Int64;
  End;

Implementation

Uses
  SyncObjs, fpjson, AssistantProtocol;

Function Utf8Bytes(Const Text: RawByteString): Integer;
Begin
  Result := Length(Text);
End;

{ True when Current is Previous plus a suffix. Offset is the UTF-8 byte length of Previous. }
Function MonitorAppendSuffix(Const Previous, Current: String; Out Suffix: String; Out Offset: Integer): Boolean;
Var
  OldBytes, NewBytes: UTF8String;
Begin
  Result := False;
  Suffix := '';
  Offset := 0;
  OldBytes := UTF8String(Previous);
  NewBytes := UTF8String(Current);
  If (Length(OldBytes) = 0) Or (Length(NewBytes) <= Length(OldBytes)) Then
    Exit;
  If Copy(NewBytes, 1, Length(OldBytes)) <> OldBytes Then
    Exit;
  Offset := Length(OldBytes);
  Suffix := String(Copy(NewBytes, Offset + 1, MaxInt));
  Result := Suffix <> '';
End;

Function YesNo(Condition: Boolean): String;
Begin
  If Condition Then
    Result := 'true'
  Else
    Result := 'false';
End;

{ Marks the turn the desktop is showing. point_end is the last page of that turn. }
Function MarkPoint(Const Json: String; Point, PointEnd: Boolean): String;
Begin
  Result := Json;
  If (Not Point) Or (Json = '') Or (Json[1] <> '{') Then
    Exit;
  Result := '{"point":true,"point_end":' + YesNo(PointEnd) + ',' + Copy(Json, 2, MaxInt);
End;

Function BlockStateName(Const Block: TAssistantMonitorBlock): String;
Begin
  If Block.Running Then
    Result := 'running'
  Else If Block.Ok Then
    Result := 'ok'
  Else
    Result := 'failed';
End;

Function OutlineHash(Const Text: RawByteString): String;
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

Function TurnOutlineJson(Const Turn: TAssistantMonitorTurn): String;
Var
  Index: Integer;
  Blocks: String;
Begin
  Blocks := '';
  For Index := 0 To High(Turn.Blocks) Do
    Begin
      If Blocks <> '' Then
        Blocks := Blocks + ',';
      Blocks := Blocks + '{"block_id":"' + JsonEscapeText(Turn.Blocks[Index].BlockId) + '","kind":"' +
        JsonEscapeText(Turn.Blocks[Index].Kind) + '","revision":' + IntToStr(Turn.Blocks[Index].Revision) +
        ',"body_bytes":' + IntToStr(Length(UTF8String(Turn.Blocks[Index].Body))) + ',"hash":"' +
        OutlineHash(UTF8String(Turn.Blocks[Index].Body)) + '"}';
    End;
  Result := '{"turn_index":' + IntToStr(Turn.TurnIndex) + ',"turn_id":"' + JsonEscapeText(Turn.Id) + '","mode":"' +
    JsonEscapeText(Turn.Mode) + '","prompt_preview":"' + JsonEscapeText(Turn.PromptPreview) + '","created_at":"' +
    JsonEscapeText(Turn.CreatedAt) + '","duration_ms":' + IntToStr(Turn.DurationMs) + ',"blocks":[' + Blocks + ']}';
End;

Function BlockFitsInline(Const Block: TAssistantMonitorBlock): Boolean;
Begin
  Result := Utf8Bytes(Block.Body) <= MonitorInlineBodyBytes;
End;

Function BlockJson(Const Block: TAssistantMonitorBlock; Const TurnId: String): String;
Var
  Body: String;
Begin
  If BlockFitsInline(Block) Then
    Body := JsonEscapeText(Block.Body)
  Else
    Body := '';
  Result := '{"block_id":"' + JsonEscapeText(Block.BlockId) + '","turn_id":"' + JsonEscapeText(TurnId) + '","kind":"' +
    JsonEscapeText(Block.Kind) + '","title":"' + JsonEscapeText(Block.Title) + '","state":"' +
    JsonEscapeText(BlockStateName(Block)) + '","body":"' + Body + '","deferred":' + YesNo(Not BlockFitsInline(Block)) +
    ',"bytes":' + IntToStr(Utf8Bytes(Block.Body)) + '}';
End;

Function TurnPageBody(Const Turn: TAssistantMonitorTurn): String;
Var
  BlockIndex: Integer;
Begin
  Result := '"turn":{"turn_id":"' + JsonEscapeText(Turn.Id) + '","turn_index":' + IntToStr(Turn.TurnIndex) + ',"blocks":[';
  For BlockIndex := 0 To High(Turn.Blocks) Do
    Begin
      If BlockIndex > 0 Then
        Result := Result + ',';
      Result := Result + BlockJson(Turn.Blocks[BlockIndex], Turn.Id);
    End;
  Result := Result + ']}';
End;

Function MonitorTurnPageJson(Const ConversationId, StreamId: String; Seq: Int64; Const Turn: TAssistantMonitorTurn): String;
Begin
  Result := '{"conversation_id":"' + JsonEscapeText(ConversationId) + '","stream_id":"' + JsonEscapeText(StreamId) +
    '","seq":' + IntToStr(Seq) + ',' + TurnPageBody(Turn) + '}';
End;

Constructor TMonitorMirror.Create;
Begin
  Create(MonitorLogBudgetBytes);
End;

Constructor TMonitorMirror.Create(BudgetBytes: Int64);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  If BudgetBytes < 1 Then
    FBudget := MonitorLogBudgetBytes
  Else
    FBudget := BudgetBytes;
  FConversationId := '';
  FStreamId := '';
  FProjectRoot := '';
  FTitle := '';
  FHead := 0;
  FAckedSeq := 0;
  FDroppedThrough := 0;
  FBytes := 0;
  SetLength(FEvents, 0);
  SetLength(FTurns, 0);
  FLive := Default(TAssistantMonitorTurn);
  FHasLive := False;
  FPlanPath := '';
  FPlanTitle := '';
  FPlanRunning := False;
  SetLength(FPlanRows, 0);
  SetLength(FParked, 0);
End;

Destructor TMonitorMirror.Destroy;
Begin
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TMonitorMirror.NoteDropLocked(Seq: Int64);
Begin
  If Seq > FDroppedThrough Then
    FDroppedThrough := Seq;
End;

Function TMonitorMirror.DropOldestLocked: Boolean;
Var
  Index, Size: Integer;
  Dropped: Int64;
Begin
  Result := False;
  If Length(FEvents) = 0 Then
    Exit;
  { An event the phone has not acknowledged stays, so a slow phone cannot lose the tail. }
  If FEvents[0].Seq > FAckedSeq Then
    Exit;
  Result := True;
  Dropped := FEvents[0].Seq;
  Size := Utf8Bytes(FEvents[0].Data) + Length(FEvents[0].Kind);
  NoteDropLocked(Dropped);
  FBytes := FBytes - Size;
  If FBytes < 0 Then
    FBytes := 0;
  For Index := 0 To High(FEvents) - 1 Do
    FEvents[Index] := FEvents[Index + 1];
  SetLength(FEvents, Length(FEvents) - 1);
End;

Procedure TMonitorMirror.AppendLocked(Seq: Int64; Const Kind: String; Const Data: RawByteString);
Var
  Size, Index: Integer;
Begin
  Size := Utf8Bytes(Data) + Length(Kind);
  If Size > FBudget Then
    Begin
      NoteDropLocked(Seq);
      If Seq > FHead Then
        FHead := Seq;
      Exit;
    End;
  While (Length(FEvents) > 0) And (FBytes + Size > FBudget) And DropOldestLocked Do
    ;
  If FBytes + Size > FBudget Then
    Exit;
  Index := Length(FEvents);
  SetLength(FEvents, Index + 1);
  FEvents[Index].Seq := Seq;
  FEvents[Index].Kind := Kind;
  FEvents[Index].Data := Data;
  FBytes := FBytes + Size;
  If Seq > FHead Then
    FHead := Seq;
End;

Function TMonitorMirror.IndexOfSeqLocked(Seq: Int64): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := 0 To High(FEvents) Do
    If FEvents[Index].Seq = Seq Then
      Exit(Index);
End;

Function TMonitorMirror.PatchIndexLocked(Seq: Int64): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := 0 To High(FEvents) Do
    If (FEvents[Index].Kind = 'patch') And (FEvents[Index].Seq = Seq) Then
      Exit(Index);
End;

Procedure TMonitorMirror.ParkCurrentLocked;
Var
  Index: Integer;
  Park: TMonitorMirrorPark;
Begin
  If FConversationId = '' Then
    Exit;
  Park.ConversationId := FConversationId;
  Park.StreamId := FStreamId;
  Park.ProjectRoot := FProjectRoot;
  Park.Title := FTitle;
  Park.Head := FHead;
  Park.AckedSeq := FAckedSeq;
  Park.DroppedThrough := FDroppedThrough;
  Park.Bytes := FBytes;
  Park.Events := Copy(FEvents);
  SetLength(Park.Turns, Length(FTurns));
  For Index := 0 To High(FTurns) Do
    CopyTurn(FTurns[Index], Park.Turns[Index]);
  Park.HasLive := FHasLive;
  If FHasLive Then
    CopyTurn(FLive, Park.Live)
  Else
    Park.Live := Default(TAssistantMonitorTurn);
  Park.PlanPath := FPlanPath;
  Park.PlanTitle := FPlanTitle;
  Park.PlanRunning := FPlanRunning;
  Park.PlanRows := Copy(FPlanRows);
  Index := -1;
  For Index := 0 To High(FParked) Do
    If FParked[Index].ConversationId = FConversationId Then
      Break;
  If (Length(FParked) = 0) Or (FParked[Index].ConversationId <> FConversationId) Then
    Index := -1;
  If Index >= 0 Then
    FParked[Index] := Park
  Else
    Begin
      SetLength(FParked, Length(FParked) + 1);
      FParked[High(FParked)] := Park;
    End;
End;

Function TMonitorMirror.UnparkLocked(Const ConversationId, StreamId: String): Boolean;
Var
  Index, TurnIndex: Integer;
Begin
  Result := False;
  For Index := 0 To High(FParked) Do
    If (FParked[Index].ConversationId = ConversationId) And (FParked[Index].StreamId = LowerCase(StreamId)) Then
      Begin
        FConversationId := FParked[Index].ConversationId;
        FStreamId := FParked[Index].StreamId;
        FProjectRoot := FParked[Index].ProjectRoot;
        FTitle := FParked[Index].Title;
        FHead := FParked[Index].Head;
        FAckedSeq := FParked[Index].AckedSeq;
        FDroppedThrough := FParked[Index].DroppedThrough;
        FBytes := FParked[Index].Bytes;
        FEvents := Copy(FParked[Index].Events);
        SetLength(FTurns, Length(FParked[Index].Turns));
        For TurnIndex := 0 To High(FParked[Index].Turns) Do
          CopyTurn(FParked[Index].Turns[TurnIndex], FTurns[TurnIndex]);
        FHasLive := FParked[Index].HasLive;
        If FHasLive Then
          CopyTurn(FParked[Index].Live, FLive)
        Else
          FLive := Default(TAssistantMonitorTurn);
        FPlanPath := FParked[Index].PlanPath;
        FPlanTitle := FParked[Index].PlanTitle;
        FPlanRunning := FParked[Index].PlanRunning;
        FPlanRows := Copy(FParked[Index].PlanRows);
        Result := True;
        Exit;
      End;
End;

Procedure TMonitorMirror.BeginStream(Const StreamId, ConversationId, ProjectRoot, Title: String);
Begin
  EnterCriticalSection(FLock);
  Try
    If (FConversationId <> '') And (FConversationId <> ConversationId) Then
      ParkCurrentLocked;
    If UnparkLocked(ConversationId, StreamId) Then
      Begin
        FProjectRoot := ProjectRoot;
        FTitle := Title;
        Exit;
      End;
    FStreamId := LowerCase(StreamId);
    FConversationId := ConversationId;
    FProjectRoot := ProjectRoot;
    FTitle := Title;
    FHead := 0;
    FAckedSeq := 0;
    FDroppedThrough := 0;
    FBytes := 0;
    SetLength(FEvents, 0);
    SetLength(FTurns, 0);
    FLive := Default(TAssistantMonitorTurn);
    FHasLive := False;
    FPlanPath := '';
    FPlanTitle := '';
    FPlanRunning := False;
    SetLength(FPlanRows, 0);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.SetTitle(Const Title: String);
Begin
  EnterCriticalSection(FLock);
  Try
    If Title = FTitle Then
      Exit;
    FTitle := Title;
    AppendLocked(FHead + 1, 'title_changed', '{"title":"' + JsonEscapeText(Title) + '"}');
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.RememberPatch(Seq: Int64; Const PatchJson: RawByteString);
Begin
  EnterCriticalSection(FLock);
  Try
    If (Seq <= 0) Or (PatchJson = '') Or (Seq <= FDroppedThrough) Then
      Exit;
    If PatchIndexLocked(Seq) >= 0 Then
      Exit;
    AppendLocked(Seq, 'patch', PatchJson);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.TryReplayPatches(Const StreamId: String; Seq, ThroughSeq: Int64; Out Events: TMonitorMirrorEventArray;
  Out Head: Int64): Boolean;
Var
  Need: Int64;
  Index, Count: Integer;
Begin
  Result := False;
  SetLength(Events, 0);
  Head := 0;
  EnterCriticalSection(FLock);
  Try
    Head := ThroughSeq;
    If FStreamId = '' Then
      Exit;
    If LowerCase(StreamId) <> FStreamId Then
      Exit;
    If (Seq < 0) Or (Seq > ThroughSeq) Or (Seq < FDroppedThrough) Then
      Exit;
    If Seq = ThroughSeq Then
      Begin
        Result := True;
        Exit;
      End;
    Need := Seq + 1;
    Count := 0;
    While Need <= ThroughSeq Do
      Begin
        Index := PatchIndexLocked(Need);
        If Index < 0 Then
          Exit;
        SetLength(Events, Count + 1);
        Events[Count] := FEvents[Index];
        Inc(Count);
        Need := Need + 1;
      End;
    Result := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.CopyTurn(Const Source: TAssistantMonitorTurn; Var Dest: TAssistantMonitorTurn);
Var
  Index: Integer;
Begin
  Dest := Source;
  SetLength(Dest.Blocks, Length(Source.Blocks));
  For Index := 0 To High(Source.Blocks) Do
    Begin
      Dest.Blocks[Index] := Source.Blocks[Index];
      SetLength(Dest.Blocks[Index].Images, Length(Source.Blocks[Index].Images));
      If Length(Source.Blocks[Index].Images) > 0 Then
        Move(Source.Blocks[Index].Images[0], Dest.Blocks[Index].Images[0],
          Length(Source.Blocks[Index].Images) * SizeOf(TAssistantMonitorImage));
    End;
  SetLength(Dest.Images, Length(Source.Images));
  If Length(Source.Images) > 0 Then
    Move(Source.Images[0], Dest.Images[0], Length(Source.Images) * SizeOf(TAssistantMonitorImage));
End;

Function Utf8Step(Const Text: RawByteString; Index: Integer): Integer;
Var
  Lead: Byte;
Begin
  Result := 1;
  If (Index < 1) Or (Index > Length(Text)) Then
    Exit;
  Lead := Ord(Text[Index]);
  If Lead < $80 Then
    Exit;
  If (Lead And $E0) = $C0 Then
    Result := 2
  Else If (Lead And $F0) = $E0 Then
    Result := 3
  Else If (Lead And $F8) = $F0 Then
    Result := 4;
  If Index + Result - 1 > Length(Text) Then
    Result := 1;
End;

Procedure TMonitorMirror.ObserveTurn(Const Turn: TAssistantMonitorTurn);
Var
  Index, BlockIndex: Integer;
  Stored, Local: TAssistantMonitorTurn;
  Found: Boolean;
  EventJson: String;

  Function SliceFits(Const BlockId: String; Offset: Integer; Const Slice: RawByteString): Boolean;
  Var
    Data: String;
  Begin
    Data := '{"block_id":"' + JsonEscapeText(BlockId) + '","offset":' + IntToStr(Offset) + ',"text":"' +
      JsonEscapeText(String(Slice)) + '"}';
    { The framed event adds a short envelope around this object. }
    Result := Length(Data) + 256 <= MonitorSnapshotPageBytes;
  End;

  Procedure EmitAppends(Const BlockId: String; Const Text: RawByteString; StartOffset: Integer);
  Var
    At, Taken, Step: Integer;
    Slice: RawByteString;
    Data: String;
  Begin
    At := 1;
    While At <= Length(Text) Do
      Begin
        Taken := 0;
        While At + Taken <= Length(Text) Do
          Begin
            Step := Utf8Step(Text, At + Taken);
            If (Taken > 0) And ((Taken + Step > MonitorAppendSliceBytes) Or
              (Not SliceFits(BlockId, StartOffset + At - 1, Copy(Text, At, Taken + Step)))) Then
              Break;
            If Taken + Step > MonitorAppendSliceBytes Then
              Break;
            Inc(Taken, Step);
          End;
        If Taken = 0 Then
          Taken := Utf8Step(Text, At);
        Slice := Copy(Text, At, Taken);
        Data := '{"block_id":"' + JsonEscapeText(BlockId) + '","offset":' + IntToStr(StartOffset + At - 1) + ',"text":"' +
          JsonEscapeText(String(Slice)) + '"}';
        AppendLocked(FHead + 1, 'block_append', Data);
        Inc(At, Taken);
      End;
  End;

  Procedure EmitReplace(Const Block: TAssistantMonitorBlock);
  Var
    Body: RawByteString;
    Data: String;
  Begin
    Body := UTF8String(Block.Body);
    If (Length(Body) > MonitorAppendSliceBytes) Or (Not SliceFits(Block.BlockId, 0, Body)) Then
      Data := '{"block_id":"' + JsonEscapeText(Block.BlockId) + '","deferred":true,"revision":' + IntToStr(Block.Revision) +
        ',"body_bytes":' + IntToStr(Length(Body)) + '}'
    Else
      Data := '{"block_id":"' + JsonEscapeText(Block.BlockId) + '","body":"' + JsonEscapeText(Block.Body) + '"}';
    AppendLocked(FHead + 1, 'block_replace', Data);
  End;

Begin
  { Turn shares its arrays with the caller, and through ObserveSnapshot with the session's observed snapshot.
    Every write below goes to Local, which CopyTurn has made unique. }
  Local := Default(TAssistantMonitorTurn);
  CopyTurn(Turn, Local);
  EnterCriticalSection(FLock);
  Try
    Found := False;
    Stored := Default(TAssistantMonitorTurn);
    If Local.Live Then
      Begin
        Found := FHasLive And (FLive.Id = Local.Id);
        If Found Then
          CopyTurn(FLive, Stored);
      End
    Else
      For Index := 0 To High(FTurns) Do
        If FTurns[Index].Id = Local.Id Then
          Begin
            Found := True;
            CopyTurn(FTurns[Index], Stored);
            Break;
          End;
    If Not Found Then
      Begin
        EventJson := '{"turn_id":"' + JsonEscapeText(Local.Id) + '","turn_index":' + IntToStr(Local.TurnIndex) +
          ',"mode":"' + JsonEscapeText(Local.Mode) + '","created_at":"' + JsonEscapeText(Local.CreatedAt) + '"}';
        AppendLocked(FHead + 1, 'turn_open', EventJson);
      End;
    For BlockIndex := 0 To High(Local.Blocks) Do
      Begin
        Found := False;
        If BlockIndex <= High(Stored.Blocks) Then
          Found := Stored.Blocks[BlockIndex].BlockId = Local.Blocks[BlockIndex].BlockId;
        If Not Found Then
          Begin
            AppendLocked(FHead + 1, 'block_open', '{"block_id":"' + JsonEscapeText(Local.Blocks[BlockIndex].BlockId) +
              '","turn_id":"' + JsonEscapeText(Local.Id) + '","kind":"' + JsonEscapeText(Local.Blocks[BlockIndex].Kind) +
              '","ordinal":' + IntToStr(BlockIndex) + ',"title":"' + JsonEscapeText(Local.Blocks[BlockIndex].Title) + '"}');
            EventJson := Local.Blocks[BlockIndex].Body;
            If EventJson <> '' Then
              Begin
                If Length(UTF8String(EventJson)) > MonitorAppendSliceBytes Then
                  EmitReplace(Local.Blocks[BlockIndex])
                Else
                  EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(EventJson), 0);
              End;
          End
        Else If Stored.Blocks[BlockIndex].Body <> Local.Blocks[BlockIndex].Body Then
          Begin
            Local.Blocks[BlockIndex].Revision := Stored.Blocks[BlockIndex].Revision + 1;
            If Stored.Blocks[BlockIndex].Body = '' Then
              EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(Local.Blocks[BlockIndex].Body), 0)
            Else If MonitorAppendSuffix(Stored.Blocks[BlockIndex].Body, Local.Blocks[BlockIndex].Body, EventJson, Index) Then
              EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(EventJson), Index)
            Else
              EmitReplace(Local.Blocks[BlockIndex]);
          End;
        If Not Local.Blocks[BlockIndex].Running Then
          Begin
            If (Not Found) Or Stored.Blocks[BlockIndex].Running Then
              AppendLocked(FHead + 1, 'block_close', '{"block_id":"' + JsonEscapeText(Local.Blocks[BlockIndex].BlockId) +
                '","state":"' + BlockStateName(Local.Blocks[BlockIndex]) + '"}');
          End;
      End;
    For Index := 0 To High(Local.Images) Do
      Begin
        Found := False;
        For BlockIndex := 0 To High(Stored.Images) Do
          If Stored.Images[BlockIndex].Id = Local.Images[Index].Id Then
            Found := True;
        If Not Found Then
          AppendLocked(FHead + 1, 'image_added', '{"image_id":"' + JsonEscapeText(Local.Images[Index].Id) + '","turn_id":"' +
            JsonEscapeText(Local.Id) + '","name":"' + JsonEscapeText(Local.Images[Index].Name) + '","mime":"' +
            JsonEscapeText(Local.Images[Index].Mime) + '","bytes":0,"missing":' + YesNo(Local.Images[Index].Missing) + '}');
      End;
    { Local is already unique, so it is stored without a second copy. }
    If Local.Live Then
      Begin
        FLive := Local;
        FHasLive := True;
      End
    Else
      Begin
        Found := False;
        For Index := 0 To High(FTurns) Do
          If FTurns[Index].Id = Local.Id Then
            Begin
              FTurns[Index] := Local;
              Found := True;
              Break;
            End;
        If Not Found Then
          Begin
            SetLength(FTurns, Length(FTurns) + 1);
            FTurns[High(FTurns)] := Local;
            AppendLocked(FHead + 1, 'turn_close', '{"turn_id":"' + JsonEscapeText(Local.Id) + '","outcome":"done"}');
          End;
      End;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.ObservePlan(Const PlanPath, PlanTitle: String; PlanRunning: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow);
Var
  Index: Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    FPlanPath := PlanPath;
    FPlanTitle := PlanTitle;
    FPlanRunning := PlanRunning;
    SetLength(FPlanRows, Length(Rows));
    For Index := 0 To High(Rows) Do
      FPlanRows[Index] := Rows[Index];
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.HasModel: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FHasLive Or (Length(FTurns) > 0) Or (FPlanPath <> '') Or (Length(FPlanRows) > 0);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.HasConversation: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FHasLive Or (Length(FTurns) > 0);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CaptureResume(Const ConversationId: String; Out Source: TMonitorResumeSource): Boolean;
Var
  Index, TurnIndex: Integer;
  Parked: Boolean;
Begin
  Source := Default(TMonitorResumeSource);
  Result := False;
  EnterCriticalSection(FLock);
  Try
    Parked := False;
    If (ConversationId <> '') And (ConversationId <> FConversationId) Then
      Begin
        For Index := 0 To High(FParked) Do
          If FParked[Index].ConversationId = ConversationId Then
            Begin
              Source.Found := True;
              Source.ConversationId := FParked[Index].ConversationId;
              Source.StreamId := FParked[Index].StreamId;
              Source.ProjectRoot := FParked[Index].ProjectRoot;
              Source.Title := FParked[Index].Title;
              Source.Head := FParked[Index].Head;
              Source.DroppedThrough := FParked[Index].DroppedThrough;
              Source.HasLive := FParked[Index].HasLive;
              If Source.HasLive Then
                CopyTurn(FParked[Index].Live, Source.Live);
              SetLength(Source.Turns, Length(FParked[Index].Turns));
              For TurnIndex := 0 To High(FParked[Index].Turns) Do
                CopyTurn(FParked[Index].Turns[TurnIndex], Source.Turns[TurnIndex]);
              Source.Events := Copy(FParked[Index].Events);
              Source.Observed := Source.HasLive Or (Length(Source.Turns) > 0);
              Parked := True;
              Break;
            End;
        If Not Parked Then
          Exit;
      End
    Else
      Begin
        Source.Found := FConversationId <> '';
        Source.ConversationId := FConversationId;
        Source.StreamId := FStreamId;
        Source.ProjectRoot := FProjectRoot;
        Source.Title := FTitle;
        Source.Head := FHead;
        Source.DroppedThrough := FDroppedThrough;
        Source.HasLive := FHasLive;
        If FHasLive Then
          CopyTurn(FLive, Source.Live);
        SetLength(Source.Turns, Length(FTurns));
        For TurnIndex := 0 To High(FTurns) Do
          CopyTurn(FTurns[TurnIndex], Source.Turns[TurnIndex]);
        Source.Events := Copy(FEvents);
        Source.Observed := FHasLive Or (Length(FTurns) > 0);
      End;
    Result := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CopyTurns(Out Stored: TMonitorMirrorTurnArray; Out Live: TAssistantMonitorTurn;
  Out HasLive: Boolean): Boolean;
Var
  Index: Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    SetLength(Stored, Length(FTurns));
    For Index := 0 To High(FTurns) Do
      CopyTurn(FTurns[Index], Stored[Index]);
    HasLive := FHasLive;
    If FHasLive Then
      CopyTurn(FLive, Live)
    Else
      Live := Default(TAssistantMonitorTurn);
    Result := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CopyLiveBlocks(Out Blocks: TAssistantMonitorBlockArray): Boolean;
Var
  Live: TAssistantMonitorTurn;
Begin
  EnterCriticalSection(FLock);
  Try
    SetLength(Blocks, 0);
    Result := FHasLive;
    If Not Result Then
      Exit;
    Live := Default(TAssistantMonitorTurn);
    CopyTurn(FLive, Live);
    Blocks := Live.Blocks;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.SetLogBudget(Bytes: Int64);
Begin
  If Bytes < 64 Then
    Bytes := 64;
  EnterCriticalSection(FLock);
  Try
    FBudget := Bytes;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CopyPlan(Out PlanPath, PlanTitle: String; Out PlanRunning: Boolean;
  Out Rows: TMonitorMirrorPlanArray): Boolean;
Var
  Index: Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    PlanPath := FPlanPath;
    PlanTitle := FPlanTitle;
    PlanRunning := FPlanRunning;
    SetLength(Rows, Length(FPlanRows));
    For Index := 0 To High(FPlanRows) Do
      Rows[Index] := FPlanRows[Index];
    Result := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.FindTurnLocked(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  Turn := Default(TAssistantMonitorTurn);
  If FHasLive And (FLive.TurnIndex = TurnIndex) Then
    Begin
      CopyTurn(FLive, Turn);
      Exit(True);
    End;
  For Index := 0 To High(FTurns) Do
    If FTurns[Index].TurnIndex = TurnIndex Then
      Begin
        CopyTurn(FTurns[Index], Turn);
        Exit(True);
      End;
End;

Function TMonitorMirror.FetchTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FindTurnLocked(TurnIndex, Turn);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.FetchBlock(Const BlockId: String; Out Body: String): Boolean;
Var
  Index, BlockIndex: Integer;
Begin
  Result := False;
  Body := '';
  If BlockId = '' Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    If FHasLive Then
      For BlockIndex := 0 To High(FLive.Blocks) Do
        If FLive.Blocks[BlockIndex].BlockId = BlockId Then
          Begin
            Body := FLive.Blocks[BlockIndex].Body;
            Exit(True);
          End;
    For Index := 0 To High(FTurns) Do
      For BlockIndex := 0 To High(FTurns[Index].Blocks) Do
        If FTurns[Index].Blocks[BlockIndex].BlockId = BlockId Then
          Begin
            Body := FTurns[Index].Blocks[BlockIndex].Body;
            Exit(True);
          End;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.BlockRevision(Const BlockId: String): Integer;
Var
  Index, BlockIndex: Integer;
Begin
  Result := 0;
  If BlockId = '' Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    If FHasLive Then
      For BlockIndex := 0 To High(FLive.Blocks) Do
        If FLive.Blocks[BlockIndex].BlockId = BlockId Then
          Exit(Integer(FLive.Blocks[BlockIndex].Revision));
    For Index := 0 To High(FTurns) Do
      For BlockIndex := 0 To High(FTurns[Index].Blocks) Do
        If FTurns[Index].Blocks[BlockIndex].BlockId = BlockId Then
          Exit(Integer(FTurns[Index].Blocks[BlockIndex].Revision));
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.BuildSnapshotPages(Const StreamId: String; HeadSeq: Int64; Out Pages: TMonitorSnapshotPageArray): Boolean;
Var
  Outline, PageBody, PointId: String;
  Index, BlockIndex, PageNo: Integer;
  Turn: TAssistantMonitorTurn;
  IsPoint: Boolean;
Begin
  Result := False;
  SetLength(Pages, 0);
  EnterCriticalSection(FLock);
  Try
    If LowerCase(StreamId) <> FStreamId Then
      Exit;
    Outline := '"turns":[';
    For Index := 0 To High(FTurns) Do
      Begin
        If Index > 0 Then
          Outline := Outline + ',';
        Outline := Outline + TurnOutlineJson(FTurns[Index]);
      End;
    If FHasLive Then
      Begin
        If Length(FTurns) > 0 Then
          Outline := Outline + ',';
        Outline := Outline + TurnOutlineJson(FLive);
      End;
    Outline := Outline + ']';
    PointId := '';
    If FHasLive Then
      PointId := FLive.Id
    Else If Length(FTurns) > 0 Then
      PointId := FTurns[High(FTurns)].Id;
    SetLength(Pages, 1);
    Pages[0].Page := 0;
    Pages[0].Json := '{"conversation_id":"' + JsonEscapeText(FConversationId) + '","stream_id":"' + JsonEscapeText(FStreamId) +
      '","seq":' + IntToStr(HeadSeq) + ',"point_id":"' + JsonEscapeText(PointId) + '",' + Outline + '}';
    { Current turn first, then older turns newest-first. The phone draws the desktop point at once. }
    PageNo := 1;
    For Index := High(FTurns) + Ord(FHasLive) DownTo 0 Do
      Begin
        If FHasLive And (Index > High(FTurns)) Then
          Turn := FLive
        Else
          Turn := FTurns[Index];
        PageBody := MonitorTurnPageJson(FConversationId, FStreamId, HeadSeq, Turn);
        IsPoint := (PointId <> '') And (Turn.Id = PointId);
        If FHasLive And (Turn.Id = FLive.Id) And (Turn.TurnIndex = FLive.TurnIndex) Then
          PageBody := StringReplace(PageBody, '"turn":{', '"turn":{"live":true,', [rfReplaceAll]);
        { The phone drops a page larger than its 512 KiB inbound credit. One block per page stays under that. }
        If Utf8Bytes(PageBody) > MonitorSnapshotPageBytes Then
          Begin
            { The chunk packer cannot take the whole turn. One block per page, still untruncated. }
            For BlockIndex := 0 To High(Turn.Blocks) Do
              Begin
                PageBody := '{"conversation_id":"' + JsonEscapeText(FConversationId) + '","stream_id":"' +
                  JsonEscapeText(FStreamId) + '","seq":' + IntToStr(HeadSeq) + ',"turn":{"turn_id":"' +
                  JsonEscapeText(Turn.Id) + '","turn_index":' + IntToStr(Turn.TurnIndex) + ',"blocks":[' +
                  BlockJson(Turn.Blocks[BlockIndex], Turn.Id) + ']}}';
                If FHasLive And (Turn.Id = FLive.Id) Then
                  PageBody := StringReplace(PageBody, '"turn":{', '"turn":{"live":true,', [rfReplaceAll]);
                PageBody := MarkPoint(PageBody, IsPoint, IsPoint And (BlockIndex = High(Turn.Blocks)));
                SetLength(Pages, Length(Pages) + 1);
                Pages[High(Pages)].Page := PageNo;
                Pages[High(Pages)].Json := PageBody;
                Inc(PageNo);
              End;
          End
        Else
          Begin
            PageBody := MarkPoint(PageBody, IsPoint, IsPoint);
            SetLength(Pages, Length(Pages) + 1);
            Pages[High(Pages)].Page := PageNo;
            Pages[High(Pages)].Json := PageBody;
            Inc(PageNo);
          End;
      End;
    { No turn means the outline is the whole conversation. A point page lets the phone leave Syncing. }
    If (Not FHasLive) And (Length(FTurns) = 0) Then
      Begin
        PageBody := '{"conversation_id":"' + JsonEscapeText(FConversationId) + '","stream_id":"' + JsonEscapeText(FStreamId) +
          '","seq":' + IntToStr(HeadSeq) + ',"turn":{"live":true,"turn_id":"live","turn_index":-2,"blocks":[]}}';
        PageBody := MarkPoint(PageBody, True, True);
        SetLength(Pages, Length(Pages) + 1);
        Pages[High(Pages)].Page := PageNo;
        Pages[High(Pages)].Json := PageBody;
      End;
    For Index := 0 To High(Pages) Do
      Pages[Index].PageCount := Length(Pages);
    Result := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.DroppedThrough: Int64;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FDroppedThrough;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CopyEvents(Out Events: TMonitorMirrorEventArray): Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    Events := Copy(FEvents);
    Result := Length(Events);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.Head: Int64;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FHead;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.ByteCount: Int64;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FBytes;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.NoteAck(Const StreamId: String; Seq: Int64);
Begin
  If Seq < 0 Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    If LowerCase(StreamId) <> FStreamId Then
      Exit;
    If Seq > FAckedSeq Then
      FAckedSeq := Seq;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.AckedSeq: Int64;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FAckedSeq;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Constructor TMonitorLogCredit.Create;
Begin
  Inherited Create;
  FUnacked := 0;
  SetLength(FSentSeq, 0);
  SetLength(FSentBytes, 0);
  SetLength(FHeldSeq, 0);
  SetLength(FHeldJson, 0);
  FHeldBytes := 0;
End;

Function TMonitorLogCredit.CanSend(Bytes: Integer): Boolean;
Begin
  Result := (Bytes >= 0) And (FUnacked + Bytes <= MonitorCreditWindowBytes);
End;

Procedure TMonitorLogCredit.NoteSent(Seq: Int64; Bytes: Integer);
Var
  Index: Integer;
Begin
  If Bytes < 1 Then
    Exit;
  Index := Length(FSentSeq);
  SetLength(FSentSeq, Index + 1);
  SetLength(FSentBytes, Index + 1);
  FSentSeq[Index] := Seq;
  FSentBytes[Index] := Bytes;
  FUnacked := FUnacked + Bytes;
End;

Procedure TMonitorLogCredit.NoteAck(Seq: Int64);
Var
  Index, Kept: Integer;
Begin
  Kept := 0;
  FUnacked := 0;
  For Index := 0 To High(FSentSeq) Do
    If FSentSeq[Index] > Seq Then
      Begin
        FSentSeq[Kept] := FSentSeq[Index];
        FSentBytes[Kept] := FSentBytes[Index];
        FUnacked := FUnacked + FSentBytes[Kept];
        Inc(Kept);
      End;
  SetLength(FSentSeq, Kept);
  SetLength(FSentBytes, Kept);
End;

Procedure TMonitorLogCredit.Hold(Seq: Int64; Const Json: String);
Var
  Index: Integer;
Begin
  For Index := 0 To High(FHeldSeq) Do
    If FHeldSeq[Index] = Seq Then
      Begin
        FHeldBytes := FHeldBytes - Length(FHeldJson[Index]) + Length(Json);
        FHeldJson[Index] := Json;
        Exit;
      End;
  Index := Length(FHeldSeq);
  SetLength(FHeldSeq, Index + 1);
  SetLength(FHeldJson, Index + 1);
  FHeldSeq[Index] := Seq;
  FHeldJson[Index] := Json;
  FHeldBytes := FHeldBytes + Length(Json);
End;

Function TMonitorLogCredit.TakeHeld(Out Seq: Int64; Out Json: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  Seq := 0;
  Json := '';
  If Length(FHeldSeq) = 0 Then
    Exit;
  Seq := FHeldSeq[0];
  Json := FHeldJson[0];
  FHeldBytes := FHeldBytes - Length(Json);
  If FHeldBytes < 0 Then
    FHeldBytes := 0;
  For Index := 0 To High(FHeldSeq) - 1 Do
    Begin
      FHeldSeq[Index] := FHeldSeq[Index + 1];
      FHeldJson[Index] := FHeldJson[Index + 1];
    End;
  SetLength(FHeldSeq, Length(FHeldSeq) - 1);
  SetLength(FHeldJson, Length(FHeldJson) - 1);
  Result := True;
End;

Function TMonitorLogCredit.UnackedBytes: Int64;
Begin
  Result := FUnacked;
End;

Function TMonitorLogCredit.HeldBytes: Int64;
Begin
  Result := FHeldBytes;
End;

End.
