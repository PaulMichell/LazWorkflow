Unit AssistantMonitorMirror;

{ Per-conversation event log and materialised model (c) 2026 Michell Computing.

  Plan item 5.3 of Documents/Plan-20261029-035918.md. The IDE thread appends
  events. A resume or a snapshot notice also builds snapshot pages on that
  thread. The connection thread replays the tail and fetches a turn from the
  model. It does not read the form. Older events are dropped once the log
  passes its byte budget; the model already holds their effect.

  Resume behind a dropped event needs a snapshot.

  Parked conversations are capped at MonitorParkedConversations. A resume for
  one that was dropped is not ready, and the phone takes a snapshot.

  ObserveTurn never writes into the turn it is given. Its arrays are shared
  with the caller's snapshot, which another thread may read (plan item 3.2 of
  Documents/Plan-20261105-130659.md). It bumps revisions on its own copy.

  One turn has one id from turn_open to turn_close. The live turn is only the
  turn in flight, at a negative turn index. The form gives it the id it will be
  stored under. When the desktop records it, the next observation has the same
  id at a real index: the turn moves to the stored list, turn_open carries the
  new index, and turn_close follows. No body is sent again. An idle desktop
  reports the stored turn it shows as live; that is the stored turn, not a
  second copy. A turn in flight that ends without a stored row is closed and
  kept at the next index, so the phone does not keep a running turn. The
  desktop stores its next turn at that index, and the stored turn replaces it.

  Size note: exceeds the 1000 line preference. What remains is the log, the
  materialised model, and the slice split. Page JSON writers with no caller are
  gone. Catalogue 3 events are the only retained protocol records.
  Reviewed 2026-11-12: strings are escaped by AssistantProtocol.JsonEscapeText,
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
  { Conversations kept beside the open one. Older visits are dropped. }
  MonitorParkedConversations = 4;
  { The form's live turn id while nothing is in flight. With no blocks it shows nothing. }
  MonitorIdleTurnId = 'live';

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
    EventHead: Integer;
    FTurns: Array Of TAssistantMonitorTurn;
    FLive: TAssistantMonitorTurn;
    FHasLive: Boolean;
    FPlanPath: String;
    FPlanTitle: String;
    FPlanRunning: Boolean;
    FPlanRows: Array Of TAssistantMonitorPlanRow;
    FParked: Array Of TMonitorMirrorPark;
    FObserveBudget: Int64;
    FObserveUsed: Int64;
    FObservePending: Boolean;
    Function DropOldestLocked: Boolean;
    Procedure NoteDropLocked(Seq: Int64);
    Procedure ParkCurrentLocked;
    Function UnparkLocked(Const ConversationId, StreamId: String): Boolean;
    Procedure AppendLocked(Seq: Int64; Const Kind: String; Const Data: RawByteString);
    { False when this pass has spent its budget. The event is not stored. }
    Function EmitLocked(Const Kind: String; Const Data: RawByteString): Boolean;
    Function IndexOfSeqLocked(Seq: Int64): Integer;
    Procedure CopyTurn(Const Source: TAssistantMonitorTurn; Var Dest: TAssistantMonitorTurn);
    Function FindTurnLocked(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
    Function StoredIndexLocked(Const TurnId: String): Integer;
    { Closes the turn in flight and keeps it as a stored turn. Running blocks close as failed. }
    Procedure RetireLiveLocked;
  Public
    Constructor Create; Overload;
    Constructor Create(BudgetBytes: Int64); Overload;
    Destructor Destroy; Override;
    { New stream. The previous conversation's events are not this stream. }
    Procedure BeginStream(Const StreamId, ConversationId, ProjectRoot, Title: String);
    Procedure SetTitle(Const Title: String);
    { True when every patch after Seq is still in the log. Seq equal to the head is an empty tail. }
    { Copy of the log. Tests read the grain without sending it. }
    Function CopyEvents(Out Events: TMonitorMirrorEventArray): Integer;
    Function TryEvent(Seq: Int64; Out Event: TMonitorMirrorEvent): Boolean;
    { One lock. Copies events after AfterSeq, contiguous from the next sequence, while each event's lower-bound
      framed size fits in Room. Stops at a gap, at the head, or before the event that would pass Room.
      EnvelopeBase is the framed envelope of a one-digit sequence with empty kind and data, and must not exceed
      that frame. HeadSeen is the head under this lock, including when the copy is empty. }
    Function CopyLogTail(AfterSeq, Room: Int64; EnvelopeBase: Integer; Out Events: TMonitorMirrorEventArray; Out HeadSeen: Int64): Integer;
    Function CanReplay(Seq: Int64): Boolean;
    { Turn is read only. The stored copy carries the bumped block revisions. }
    Procedure ObserveTurn(Const Turn: TAssistantMonitorTurn);
    { One pass. False when the turn still has a suffix. The live cursor is the emitted prefix. }
    Function ObserveTurnLimited(Const Turn: TAssistantMonitorTurn; BudgetBytes: Int64): Boolean;
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

Implementation

Uses
  SyncObjs, fpjson, AssistantProtocol, AssistantMonitorText;

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

{ Marks the turn the desktop is showing. point_end is the last page of that turn. }
Function MarkPoint(Const Json: String; Point, PointEnd: Boolean): String;
Begin
  Result := Json;
  If (Not Point) Or (Json = '') Or (Json[1] <> '{') Then
    Exit;
  Result := '{"point":true,"point_end":' + MonitorBoolean(PointEnd) + ',' + Copy(Json, 2, MaxInt);
End;

Function BlockStateName(Const Block: TAssistantMonitorBlock): String;
Begin
  Result := MonitorBlockState(Block.Running, Block.Ok);
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
        Fnv1a64(UTF8String(Turn.Blocks[Index].Body)) + '"}';
    End;
  Result := '{"turn_index":' + IntToStr(Turn.TurnIndex) + ',"turn_id":"' + JsonEscapeText(Turn.Id) + '","mode":"' +
    JsonEscapeText(Turn.Mode) + '","prompt_preview":"' + JsonEscapeText(Turn.PromptPreview) + '","created_at":"' +
    JsonEscapeText(Turn.CreatedAt) + '","duration_ms":' + IntToStr(Turn.DurationMs) + ',"blocks":[' + Blocks + ']}';
End;

Function TurnOpenJson(Const Turn: TAssistantMonitorTurn): String;
Begin
  Result := '{"turn_id":"' + JsonEscapeText(Turn.Id) + '","turn_index":' + IntToStr(Turn.TurnIndex) + ',"mode":"' +
    JsonEscapeText(Turn.Mode) + '","prompt":"' + JsonEscapeText(Turn.Prompt) + '","created_at":"' +
    JsonEscapeText(Turn.CreatedAt) + '"}';
End;

Function TurnCloseJson(Const Turn: TAssistantMonitorTurn; Const Outcome: String): String;
Begin
  Result := '{"turn_id":"' + JsonEscapeText(Turn.Id) + '","outcome":"' + Outcome + '","duration_ms":' +
    IntToStr(Turn.DurationMs) + ',"error_text":"' + JsonEscapeText(Turn.ErrorText) + '"}';
End;

{ A stopped turn is stored with the error text cancelled. }
Function TurnOutcomeName(Const Turn: TAssistantMonitorTurn): String;
Begin
  If Turn.ErrorText = '' Then
    Result := 'done'
  Else If SameText(Turn.ErrorText, 'cancelled') Then
    Result := 'stopped'
  Else
    Result := 'failed';
End;

Function BlockCloseJson(Const Block: TAssistantMonitorBlock): String;
Begin
  Result := '{"block_id":"' + JsonEscapeText(Block.BlockId) + '","state":"' + MonitorBlockState(Block.Running, Block.Ok) +
    '","duration_ms":' + IntToStr(Block.DurationMs) + '}';
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
    JsonEscapeText(BlockStateName(Block)) + '","body":"' + Body + '","deferred":' + MonitorBoolean(Not BlockFitsInline(Block)) +
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
  FObserveBudget := -1;
  SetLength(FEvents, 0);
  EventHead := 0;
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
  Size: Integer;
  Dropped: Int64;
Begin
  Result := False;
  If EventHead = Length(FEvents) Then
    Exit;
  { An event the phone has not acknowledged stays, so a slow phone cannot lose the tail. }
  If FEvents[EventHead].Seq > FAckedSeq Then
    Exit;
  Result := True;
  Dropped := FEvents[EventHead].Seq;
  Size := Utf8Bytes(FEvents[EventHead].Data) + Length(FEvents[EventHead].Kind);
  NoteDropLocked(Dropped);
  FBytes := FBytes - Size;
  If FBytes < 0 Then
    FBytes := 0;
  FEvents[EventHead] := Default(TMonitorMirrorEvent);
  Inc(EventHead);
End;

Procedure TMonitorMirror.AppendLocked(Seq: Int64; Const Kind: String; Const Data: RawByteString);
Var
  Size, Index: Integer;
Begin
  { Compact only after at least half the storage was retired. Drops themselves are constant time. }
  If (EventHead > 0) And (EventHead >= Length(FEvents) Div 2) Then
    Begin
      FEvents := Copy(FEvents, EventHead, Length(FEvents) - EventHead);
      EventHead := 0;
    End;
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
    Begin
      { The oldest events are still unacknowledged, so they stay. This event is
        not stored. The model already holds its effect. Advance the head and
        note the drop so the sequence is not reused and a resume behind it
        takes a snapshot, as an oversize event already does. }
      NoteDropLocked(Seq);
      If Seq > FHead Then
        FHead := Seq;
      Exit;
    End;
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
  LowIndex, HighIndex, Middle: Integer;
  Offset: Int64;
Begin
  Result := -1;
  If EventHead >= Length(FEvents) Then Exit;
  Offset := Seq - FEvents[EventHead].Seq;
  If (Offset < 0) Or (Seq > FEvents[High(FEvents)].Seq) Then Exit;
  If Offset < Length(FEvents) - EventHead Then
    If FEvents[EventHead + Integer(Offset)].Seq = Seq Then
      Exit(EventHead + Integer(Offset));
  { Unstored events leave gaps. Keep those tails searchable without a linear scan. }
  LowIndex := EventHead;
  HighIndex := High(FEvents);
  While LowIndex <= HighIndex Do
    Begin
      Middle := LowIndex + (HighIndex - LowIndex) Div 2;
      If FEvents[Middle].Seq = Seq Then Exit(Middle);
      If FEvents[Middle].Seq < Seq Then LowIndex := Middle + 1 Else HighIndex := Middle - 1;
    End;
End;

Function TMonitorMirror.TryEvent(Seq: Int64; Out Event: TMonitorMirrorEvent): Boolean;
Var
  Index: Integer;
Begin
  Event := Default(TMonitorMirrorEvent);
  EnterCriticalSection(FLock);
  Try
    Index := IndexOfSeqLocked(Seq);
    Result := Index >= 0;
    If Result Then Event := FEvents[Index];
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CopyLogTail(AfterSeq, Room: Int64; EnvelopeBase: Integer; Out Events: TMonitorMirrorEventArray;
  Out HeadSeen: Int64): Integer;
Var
  Index, Last, Count, Digits: Integer;
  NextSeq, Probe, Running, Size: Int64;
Begin
  Result := 0;
  HeadSeen := 0;
  SetLength(Events, 0);
  EnterCriticalSection(FLock);
  Try
    HeadSeen := FHead;
    If (Room <= 0) Or (EnvelopeBase < 0) Or (AfterSeq >= FHead) Then Exit;
    NextSeq := AfterSeq + 1;
    Index := IndexOfSeqLocked(NextSeq);
    If Index < 0 Then Exit;
    Last := Index;
    Running := 0;
    While Index < Length(FEvents) Do
      Begin
        If FEvents[Index].Seq <> NextSeq Then Break;
        Digits := 1;
        Probe := FEvents[Index].Seq;
        While Probe >= 10 Do
          Begin
            Probe := Probe Div 10;
            Inc(Digits);
          End;
        { Two sequence fields share the extra digits. Kind and data are not escaped here, so this is a lower bound. }
        Size := Int64(EnvelopeBase) + Length(FEvents[Index].Kind) + Length(FEvents[Index].Data) + 2 * (Digits - 1);
        If Size > Room - Running Then Break;
        Running := Running + Size;
        Inc(NextSeq);
        Inc(Index);
      End;
    Count := Index - Last;
    If Count <= 0 Then Exit;
    Events := Copy(FEvents, Last, Count);
    Result := Count;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TMonitorMirror.CanReplay(Seq: Int64): Boolean;
Var
  FirstIndex, LastIndex: Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := (Seq >= 0) And (Seq <= FHead) And (Seq >= FDroppedThrough);
    If Result And (Seq < FHead) Then
      Begin
        FirstIndex := IndexOfSeqLocked(Seq + 1);
        LastIndex := IndexOfSeqLocked(FHead);
        Result := (FirstIndex >= 0) And (LastIndex >= FirstIndex) And (LastIndex - FirstIndex = FHead - Seq - 1);
      End;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TMonitorMirror.ParkCurrentLocked;
Var
  Index, Kept: Integer;
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
  Park.Events := Copy(FEvents, EventHead, Length(FEvents) - EventHead);
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
  { A revisit becomes the newest, so it is not the one dropped when the ring is full. }
  Kept := 0;
  For Index := 0 To High(FParked) Do
    If FParked[Index].ConversationId <> FConversationId Then
      Begin
        If Kept <> Index Then
          FParked[Kept] := FParked[Index];
        Inc(Kept);
      End;
  SetLength(FParked, Kept);
  If Kept >= MonitorParkedConversations Then
    Begin
      For Index := 1 To Kept - 1 Do
        FParked[Index - 1] := FParked[Index];
      Dec(Kept);
      SetLength(FParked, Kept);
    End;
  SetLength(FParked, Kept + 1);
  FParked[Kept] := Park;
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
        EventHead := 0;
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
    EventHead := 0;
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

Procedure TMonitorMirror.CopyTurn(Const Source: TAssistantMonitorTurn; Var Dest: TAssistantMonitorTurn);
Var
  Index: Integer;
Begin
  Dest := Source;
  SetLength(Dest.Blocks, Length(Source.Blocks));
  For Index := 0 To High(Source.Blocks) Do
    Begin
      Dest.Blocks[Index] := Source.Blocks[Index];
      Dest.Blocks[Index].Images := Copy(Source.Blocks[Index].Images);
    End;
  Dest.Images := Copy(Source.Images);
End;

Function Utf8Step(Const Text: RawByteString; Index: Integer): Integer;
Begin
  Result := MonitorUtf8Step(Text, Index);
  If Result = 0 Then Result := 1;
End;

{ Bytes JsonEscapeText writes for the character of Step bytes at Index. A lone byte of $80 or more becomes
  U+FFFD (3 bytes). A malformed longer sequence can still grow, so EmitAppends checks the escaped slice. }
Function EscapedCharBytes(Const Text: RawByteString; Index, Step: Integer): Integer;
Var
  Lead: Byte;
Begin
  Result := Step;
  If Step <> 1 Then
    Exit;
  Lead := Ord(Text[Index]);
  If Lead >= $80 Then
    Result := 3
  Else If Lead In [Ord('"'), Ord('\'), 8, 9, 10, 12, 13] Then
    Result := 2
  Else If Lead < 32 Then
    Result := 6;
End;

Function TMonitorMirror.StoredIndexLocked(Const TurnId: String): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  If TurnId = '' Then
    Exit;
  For Index := High(FTurns) DownTo 0 Do
    If FTurns[Index].Id = TurnId Then
      Exit(Index);
End;

Procedure TMonitorMirror.RetireLiveLocked;
Var
  Index, Next: Integer;
  Retired: TAssistantMonitorTurn;
  Outcome: String;
Begin
  If Not FHasLive Then
    Exit;
  Retired := Default(TAssistantMonitorTurn);
  CopyTurn(FLive, Retired);
  FHasLive := False;
  FLive := Default(TAssistantMonitorTurn);
  { The idle id is reused by every turn the form has not named, so it is never kept as a stored turn. }
  If (Retired.Id = '') Or (Retired.Id = MonitorIdleTurnId) Then
    Exit;
  Outcome := TurnOutcomeName(Retired);
  For Index := 0 To High(Retired.Blocks) Do
    If Retired.Blocks[Index].Running Then
      Begin
        Retired.Blocks[Index].Running := False;
        Retired.Blocks[Index].Ok := False;
        EmitLocked('block_close', BlockCloseJson(Retired.Blocks[Index]));
        Outcome := 'stopped';
      End;
  { A negative index would put the turn above the whole transcript on the phone. }
  If Retired.TurnIndex < 0 Then
    Begin
      Next := 0;
      For Index := 0 To High(FTurns) Do
        If FTurns[Index].TurnIndex >= Next Then
          Next := FTurns[Index].TurnIndex + 1;
      Retired.TurnIndex := Next;
      EmitLocked('turn_open', TurnOpenJson(Retired));
    End;
  Retired.Live := False;
  Index := StoredIndexLocked(Retired.Id);
  If Index < 0 Then
    Begin
      Index := Length(FTurns);
      SetLength(FTurns, Index + 1);
    End;
  FTurns[Index] := Retired;
  EmitLocked('turn_close', TurnCloseJson(Retired, Outcome));
End;

Function TMonitorMirror.EmitLocked(Const Kind: String; Const Data: RawByteString): Boolean;
Var
  Size: Integer;
Begin
  Result := False;
  If FObservePending Then
    Exit;
  Size := Length(Data) + Length(Kind);
  { The first event of a pass always goes out, so a budget never stalls on an empty cursor. }
  If (FObserveBudget >= 0) And (FObserveUsed > 0) And (FObserveUsed + Size > FObserveBudget) Then
    Begin
      FObservePending := True;
      Exit;
    End;
  AppendLocked(FHead + 1, Kind, Data);
  If FObserveBudget >= 0 Then
    Inc(FObserveUsed, Size);
  If (FObserveBudget >= 0) And (FObserveUsed >= FObserveBudget) Then
    FObservePending := True;
  Result := True;
End;

Function TMonitorMirror.ObserveTurnLimited(Const Turn: TAssistantMonitorTurn; BudgetBytes: Int64): Boolean;
Begin
  FObserveBudget := BudgetBytes;
  FObserveUsed := 0;
  FObservePending := False;
  Try
    ObserveTurn(Turn);
    Result := Not FObservePending;
  Finally
    FObserveBudget := -1;
    FObservePending := False;
  End;
End;

Procedure TMonitorMirror.ObserveTurn(Const Turn: TAssistantMonitorTurn);
Var
  Index, BlockIndex, Match, Kept, Emitted: Integer;
  Stored, Local: TAssistantMonitorTurn;
  Found, IdleCopy: Boolean;
  EventJson: String;

  { The stored block with this id. Hint is checked first, because blocks rarely move. }
  Function StoredBlock(Const BlockId: String; Hint: Integer): Integer;
  Var
    Probe: Integer;
  Begin
    If (Hint <= High(Stored.Blocks)) And (Stored.Blocks[Hint].BlockId = BlockId) Then
      Exit(Hint);
    Result := -1;
    If BlockId = '' Then
      Exit;
    For Probe := 0 To High(Stored.Blocks) Do
      If Stored.Blocks[Probe].BlockId = BlockId Then
        Exit(Probe);
  End;

  Function SliceFits(Const BlockId: String; Offset: Integer; Const Slice: RawByteString): Boolean;
  Var
    Data: String;
  Begin
    Data := '{"block_id":"' + JsonEscapeText(BlockId) + '","offset":' + IntToStr(Offset) + ',"text":"' +
      JsonEscapeText(String(Slice)) + '"}';
    { The framed event adds a short envelope around this object. }
    Result := Length(Data) + 256 <= MonitorSnapshotPageBytes;
  End;

  { Linear. The escaped size is summed per character and each slice is escaped once. Escaping every candidate
    prefix made a large append quadratic: 800 KiB took about 55 s on the IDE thread. }
  { False when the pass budget stopped before Text was finished. Emitted is the UTF-8 prefix sent. }
  Function EmitAppends(Const BlockId: String; Const Text: RawByteString; StartOffset: Integer; Out Emitted: Integer): Boolean;
  Var
    At, Taken, Step, Escaped, Room, Want: Integer;
    Slice: RawByteString;
    Prefix, Data: String;
  Begin
    Emitted := 0;
    Result := True;
    At := 1;
    While At <= Length(Text) Do
      Begin
        Prefix := '{"block_id":"' + JsonEscapeText(BlockId) + '","offset":' + IntToStr(StartOffset + At - 1) + ',"text":"';
        { The framed event adds a short envelope around this object. }
        Room := MonitorSnapshotPageBytes - 256 - Length(Prefix) - 2;
        Taken := 0;
        Escaped := 0;
        While At + Taken <= Length(Text) Do
          Begin
            Step := Utf8Step(Text, At + Taken);
            If Taken + Step > MonitorAppendSliceBytes Then
              Break;
            Inc(Escaped, EscapedCharBytes(Text, At + Taken, Step));
            If (Taken > 0) And (Escaped > Room) Then
              Break;
            Inc(Taken, Step);
          End;
        If Taken = 0 Then
          Taken := Utf8Step(Text, At);
        Repeat
          Slice := Copy(Text, At, Taken);
          Data := Prefix + JsonEscapeText(String(Slice)) + '"}';
          If (Length(Data) + 256 <= MonitorSnapshotPageBytes) Or (Taken <= Utf8Step(Text, At)) Then
            Break;
          { Malformed input escaped larger than counted. Halve the slice on a character boundary. }
          Want := Taken Div 2;
          Taken := 0;
          While (At + Taken <= Length(Text)) And (Taken + Utf8Step(Text, At + Taken) <= Want) Do
            Inc(Taken, Utf8Step(Text, At + Taken));
          If Taken = 0 Then
            Taken := Utf8Step(Text, At);
        Until False;
        If Not EmitLocked('block_append', Data) Then
          Begin
            Result := False;
            Exit;
          End;
        Inc(At, Taken);
        Emitted := At - 1;
      End;
  End;

  Function EmitReplace(Const Block: TAssistantMonitorBlock): Boolean;
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
    Result := EmitLocked('block_replace', Data);
  End;

Begin
  { Turn shares its arrays with the caller, and through ObserveSnapshot with the session's observed snapshot.
    Every write below goes to Local, which CopyTurn has made unique. }
  Local := Default(TAssistantMonitorTurn);
  CopyTurn(Turn, Local);
  EnterCriticalSection(FLock);
  Try
    Found := False;
    IdleCopy := False;
    Stored := Default(TAssistantMonitorTurn);
    If Local.Live Then
      Begin
        { The idle placeholder has nothing to show. A turn still in flight ended without a stored row. }
        If (Local.Id = MonitorIdleTurnId) And (Length(Local.Blocks) = 0) Then
          Begin
            RetireLiveLocked;
            Exit;
          End;
        Index := StoredIndexLocked(Local.Id);
        If Index >= 0 Then
          Begin
            { Already stored. An idle desktop shows it, or a plan run adds notes to its trace. }
            Local.Live := False;
            If Local.TurnIndex < 0 Then
              Local.TurnIndex := FTurns[Index].TurnIndex;
            IdleCopy := True;
          End
        Else If (Local.TurnIndex >= 0) And FHasLive And (FLive.Id = Local.Id) And (FLive.TurnIndex < 0) Then
          Local.Live := False;
      End;
    If (Not Local.Live) And FHasLive And (FLive.Id = Local.Id) Then
      Begin
        { The turn in flight was recorded. It keeps its id and its blocks, so only the changes go out. }
        CopyTurn(FLive, Stored);
        Found := True;
        FHasLive := False;
        FLive := Default(TAssistantMonitorTurn);
      End
    Else If FHasLive And (FLive.Id <> Local.Id) And (Local.Live Or IdleCopy) Then
      { Another turn is in flight, or the desktop is idle. The old one ended without a stored row. }
      RetireLiveLocked;
    If Not Found Then
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
    { A recorded turn moves from the live index to its stored index. The phone orders turns by that index. }
    If (Not Found) Or (Stored.TurnIndex <> Local.TurnIndex) Then
      EmitLocked('turn_open', TurnOpenJson(Local));
    For BlockIndex := 0 To High(Local.Blocks) Do
      Begin
        If FObservePending Then
          Begin
            SetLength(Local.Blocks, BlockIndex);
            Break;
          End;
        Match := StoredBlock(Local.Blocks[BlockIndex].BlockId, BlockIndex);
        Found := Match >= 0;
        { A block that moved keeps its body on the phone. block_open only gives it the new ordinal. }
        If (Not Found) Or (Match <> BlockIndex) Then
          EmitLocked('block_open', '{"block_id":"' + JsonEscapeText(Local.Blocks[BlockIndex].BlockId) +
            '","turn_id":"' + JsonEscapeText(Local.Id) + '","kind":"' + JsonEscapeText(Local.Blocks[BlockIndex].Kind) +
            '","ordinal":' + IntToStr(BlockIndex) + ',"title":"' + JsonEscapeText(Local.Blocks[BlockIndex].Title) + '"}');
        If Not Found Then
          Begin
            EventJson := Local.Blocks[BlockIndex].Body;
            If EventJson <> '' Then
              Begin
                If Length(UTF8String(EventJson)) > MonitorAppendSliceBytes Then
                  Begin
                    If Not EmitReplace(Local.Blocks[BlockIndex]) Then
                      Begin
                        SetLength(Local.Blocks, BlockIndex);
                        Break;
                      End;
                  End
                Else If Not EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(EventJson), 0, Emitted) Then
                  Local.Blocks[BlockIndex].Body := Copy(EventJson, 1, Emitted);
              End;
          End
        Else If Stored.Blocks[Match].Body <> Local.Blocks[BlockIndex].Body Then
          Begin
            Local.Blocks[BlockIndex].Revision := Stored.Blocks[Match].Revision + 1;
            If Stored.Blocks[Match].Body = '' Then
              Begin
                If Not EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(Local.Blocks[BlockIndex].Body), 0, Emitted) Then
                  Local.Blocks[BlockIndex].Body := Copy(Local.Blocks[BlockIndex].Body, 1, Emitted);
              End
            Else If MonitorAppendSuffix(Stored.Blocks[Match].Body, Local.Blocks[BlockIndex].Body, EventJson, Index) Then
              Begin
                If Not EmitAppends(Local.Blocks[BlockIndex].BlockId, UTF8String(EventJson), Index, Emitted) Then
                  Local.Blocks[BlockIndex].Body := Stored.Blocks[Match].Body + Copy(EventJson, 1, Emitted);
              End
            Else If Not EmitReplace(Local.Blocks[BlockIndex]) Then
              Begin
                Local.Blocks[BlockIndex].Body := Stored.Blocks[Match].Body;
                Local.Blocks[BlockIndex].Revision := Stored.Blocks[Match].Revision;
              End;
          End
        Else If Stored.Blocks[Match].Revision > Local.Blocks[BlockIndex].Revision Then
          { An unchanged body keeps the revision the phone was given, so a block fetch does not see it go back. }
          Local.Blocks[BlockIndex].Revision := Stored.Blocks[Match].Revision;
        If FObservePending Then
          Local.Blocks[BlockIndex].Running := True
        Else If Not Local.Blocks[BlockIndex].Running Then
          Begin
            If (Not Found) Or Stored.Blocks[Match].Running Then
              If Not EmitLocked('block_close', BlockCloseJson(Local.Blocks[BlockIndex])) Then
                Local.Blocks[BlockIndex].Running := True;
          End;
      End;
    If Not FObservePending Then
    For Index := 0 To High(Local.Images) Do
      Begin
        Found := False;
        For BlockIndex := 0 To High(Stored.Images) Do
          If Stored.Images[BlockIndex].Id = Local.Images[Index].Id Then
            Found := True;
        If Not Found Then
          EmitLocked('image_added', '{"image_id":"' + JsonEscapeText(Local.Images[Index].Id) + '","turn_id":"' +
            JsonEscapeText(Local.Id) + '","name":"' + JsonEscapeText(Local.Images[Index].Name) + '","mime":"' +
            JsonEscapeText(Local.Images[Index].Mime) + '","width":' + IntToStr(Local.Images[Index].Width) +
            ',"height":' + IntToStr(Local.Images[Index].Height) + ',"bytes":0,"missing":' + MonitorBoolean(Local.Images[Index].Missing) + '}');
      End;
    { A partial pass keeps the emitted prefix as the live cursor. The next tick appends the suffix. }
    If FObservePending Then
      Begin
        Local.Live := True;
        FLive := Local;
        FHasLive := True;
      End
    Else If Local.Live Then
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
            EmitLocked('turn_close', TurnCloseJson(Local, TurnOutcomeName(Local)));
          End;
        { A retired turn was filed at the next index, and the desktop stores its next turn there too. The stored
          turn wins, so a later snapshot outline leaves the retired one out and the phone drops it. }
        If Local.TurnIndex >= 0 Then
          Begin
            Kept := 0;
            For Index := 0 To High(FTurns) Do
              If (FTurns[Index].TurnIndex <> Local.TurnIndex) Or (FTurns[Index].Id = Local.Id) Then
                Begin
                  If Kept <> Index Then
                    FTurns[Kept] := FTurns[Index];
                  Inc(Kept);
                End;
            SetLength(FTurns, Kept);
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
        Source.Events := Copy(FEvents, EventHead, Length(FEvents) - EventHead);
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
    Events := Copy(FEvents, EventHead, Length(FEvents) - EventHead);
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

End.
