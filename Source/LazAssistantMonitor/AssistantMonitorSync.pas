Unit AssistantMonitorSync;

{ Resume decisions, slice framing, state classification, state values, and the baseline
  (c) 2026 Michell Computing.

  The mirror is the producer and the replay store. This unit does not read the
  assistant form and does not allocate a content sequence. A status or plan
  change is state, not an event. Every string written into a frame goes through
  AssistantProtocol.JsonEscapeText, which escapes every control below #32.
  Stay under 1000 lines; split a sibling before crossing that line. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantSessionObserve, AssistantMonitorMirror, AssistantMonitorOutbox;

{ Queues the next contiguous event after QueuedSeq while the unacknowledged
  framed bytes stay inside the credit window. A gap stops the fill. CloseLink
  is set when the log lane passes its budget. }
{ True when every event after Seq is still stored, or Seq is already the head. }
Function MonitorSyncCanReplay(Mirror: TMonitorMirror; Seq: Int64): Boolean;
Procedure MonitorSyncFill(Mirror: TMonitorMirror; Outbox: TMonitorOutbox; Const ConversationId, StreamId: String;
  PhoneAck: Int64; Var QueuedSeq: Int64; Out CloseLink: Boolean);

Type
  TMonitorSyncFrameKind = (mskControl, mskBulk, mskBarrier);

  TMonitorSyncAnswerFrame = Record
    Kind: TMonitorSyncFrameKind;
    Json: String;
  End;

  TMonitorSyncAnswer = Record
    Replay: Boolean;
    NotReady: Boolean;
    Head: Int64;
    Generation: Int64;
    Frames: Array Of TMonitorSyncAnswerFrame;
  End;

  TMonitorSyncStatus = Record
    Busy: Boolean;
    Sending: Boolean;
    PlanRunning: Boolean;
    CanSend: Boolean;
    CanSteer: Boolean;
    CanStop: Boolean;
    CanChangeMode: Boolean;
    Phase: String;
    StatusText: String;
    ApprovalActive: Boolean;
    ApprovalToolId: String;
  End;

Type
  TMonitorSyncLane = (mslControl, mslState, mslLog, mslBulk, mslBarrier);

{ Control and approval stay on control. Other state names its key. Slices are the log.
  Fetch answers and turn pages are bulk. snapshot_end is the barrier. The frame is parsed, so a frame
  written by fpjson AsJSON, with spaces around each colon, is classified like a hand-written one. }
Function MonitorSyncClassify(Const Json: String; Out Lane: TMonitorSyncLane; Out StateKey: String): Boolean;
Function MonitorSyncStateFrame(Const Id, Key, ValueJson: String): String;
{ One state frame, or chunk frames of that value when the envelope exceeds 32 KiB. }
Function MonitorSyncEventSeq(Const Json: String): Int64;
Function MonitorSyncStateFrames(Const Id, Key, ValueJson: String): TStringArray;

{ One resume answer. State frames are not included; the caller queues those first. }
Function MonitorSyncResumeAnswer(Const Source: TMonitorResumeSource; Const RequestedId, PhoneStream, ResumeId: String;
  PhoneSeq: Int64; Const Status: TMonitorSyncStatus): TMonitorSyncAnswer;

{ State values for TMonitorSession.PublishState. Each returns one JSON object. Strings are escaped here,
  so status text, paths, titles and notes may hold quotes, backslashes, controls and non-ASCII text. }
Function MonitorConversationValueJson(Const ConversationId: String): String;
Function MonitorStatusValueJson(Const View: TAssistantMonitorView): String;
/// Status for a resume. The phase, status text, start time and error are empty.
Function MonitorResumeStatusValueJson(Const Status: TMonitorSyncStatus): String;
Function MonitorApprovalValueJson(Active: Boolean; Const ToolId: String): String;
Function MonitorSessionValueJson(Const View: TAssistantMonitorView): String;
Function MonitorModeValueJson(Const View: TAssistantMonitorView): String;
Function MonitorTargetValueJson(Const View: TAssistantMonitorView): String;
/// Pairs Paths[i] with Captions[i] as {"path","caption"}. Stops at the shorter list.
Function MonitorChoiceArrayJson(Paths, Captions: TStrings): String;
Function MonitorTargetsValueJson(Const Current: String; Paths, Captions: TStrings): String;
Function MonitorConversationsValueJson(Const Current: String; Truncated: Boolean; Ids, Titles: TStrings): String;
/// Models and permissions name a backend. Reasoning passes HasBackend False and has no backend field.
Function MonitorNamedChoicesValueJson(Const Current, Backend, Note: String; HasBackend: Boolean; Ids, Captions: TStrings): String;
Function MonitorPlanChoicesValueJson(Paths, Captions: TStrings): String;
Function MonitorPlanValueJson(Const Path, Title: String; Running: Boolean; Const Revision: String;
  Const Rows: Array Of TAssistantMonitorPlanRow): String;
Function MonitorTasksValueJson(Const Rows: Array Of TAssistantMonitorTaskRow): String;

Implementation

Uses
  fpjson, jsonparser, AssistantProtocol, AssistantMonitorFrames, AssistantMonitorText;

Const
  { Bytes of the prompt kept as a turn's preview. }
  MonitorPreviewBytes = 80;
  { Raw value bytes per state chunk, and the most a chunk's escaped data may take. The escaped data and the
    chunk envelope together stay under MonitorOutboxChunkBytes. }
  MonitorStateChunkRawBytes = 20000;
  MonitorStateChunkDataBytes = 28000;
  { A body whose escaped text is this size or smaller rides in the baseline outline. Thoughts, prompts, notes and
    answers then arrive with the outline; a larger body, usually a tool result, is fetched by block_get. The limit
    is on escaped bytes so that one block with its fields stays inside the 24 KiB outline page. }
  MonitorOutlineBodyBytes = 16 * 1024;

Function EventFrame(Const ConversationId, StreamId: String; Const Event: TMonitorMirrorEvent): String;
Begin
  Result := '{"v":3,"id":"e-' + IntToStr(Event.Seq) + '","type":"event","payload":{"conversation_id":"' +
    JsonEscapeText(ConversationId) + '","stream_id":"' + JsonEscapeText(StreamId) + '","seq":' + IntToStr(Event.Seq) +
    ',"event":"' + JsonEscapeText(Event.Kind) + '","data":' + String(Event.Data) + '}}';
End;

Function FindSeq(Const Events: TMonitorMirrorEventArray; Seq: Int64): Integer;
Var
  Offset: Int64;
  LowIndex, HighIndex, Middle: Integer;
Begin
  Result := -1;
  If Length(Events) = 0 Then Exit;
  Offset := Seq - Events[0].Seq;
  If (Offset >= 0) And (Offset < Length(Events)) Then
    If Events[Integer(Offset)].Seq = Seq Then Exit(Integer(Offset));
  LowIndex := 0;
  HighIndex := High(Events);
  While LowIndex <= HighIndex Do
    Begin
      Middle := LowIndex + (HighIndex - LowIndex) Div 2;
      If Events[Middle].Seq = Seq Then Exit(Middle);
      If Events[Middle].Seq < Seq Then LowIndex := Middle + 1 Else HighIndex := Middle - 1;
    End;
End;

Function MonitorSyncCanReplay(Mirror: TMonitorMirror; Seq: Int64): Boolean;
Begin
  Result := Assigned(Mirror);
  If Result Then Result := Mirror.CanReplay(Seq);
End;

Procedure MonitorSyncFill(Mirror: TMonitorMirror; Outbox: TMonitorOutbox; Const ConversationId, StreamId: String;
  PhoneAck: Int64; Var QueuedSeq: Int64; Out CloseLink: Boolean);
Var
  Event: TMonitorMirrorEvent;
  NextSeq, Unacked: Int64;
  Frame: String;
  Encoded: RawByteString;
Begin
  CloseLink := False;
  Encoded := '';
  If Not Assigned(Mirror) Or Not Assigned(Outbox) Or (StreamId = '') Then
    Exit;
  { The outbox owns queued frames through acknowledgement, including frames already sent. }
  Outbox.Acknowledge(PhoneAck);
  Unacked := Outbox.LogPayloadBytes;
  While QueuedSeq < Mirror.Head Do
    Begin
      NextSeq := QueuedSeq + 1;
      If Not Mirror.TryEvent(NextSeq, Event) Then Exit;
      Frame := EventFrame(ConversationId, StreamId, Event);
      If Unacked + Length(Frame) > MonitorCreditWindowBytes Then Exit;
      { The link writes these bytes. A raw JSON object is not a LAM1 frame. The producer built the object,
        so the header is written without another parse. }
      If Not EncodeMonitorFrameBytes(Frame, Encoded) Then
        Exit;
      If Not Outbox.AppendLog(NextSeq, Encoded) Then
        Exit;
      Inc(Unacked, Length(Frame));
      QueuedSeq := NextSeq;
      If Outbox.LogOverflowed Then
        Begin
          CloseLink := True;
          Exit;
        End;
    End;
End;

Function TailHeld(Const Source: TMonitorResumeSource; PhoneSeq: Int64): Boolean;
Var
  FirstIndex, LastIndex: Integer;
Begin
  Result := False;
  If (PhoneSeq < 0) Or (PhoneSeq > Source.Head) Or (PhoneSeq < Source.DroppedThrough) Then Exit;
  If PhoneSeq = Source.Head Then Exit(True);
  FirstIndex := FindSeq(Source.Events, PhoneSeq + 1);
  LastIndex := FindSeq(Source.Events, Source.Head);
  { Sorted unique sequences form a complete tail exactly when count equals sequence distance. }
  Result := (FirstIndex >= 0) And (LastIndex >= FirstIndex) And
    (LastIndex - FirstIndex = Source.Head - PhoneSeq - 1);
End;

Function BlockState(Const Block: TAssistantMonitorBlock): String;
Begin
  Result := MonitorBlockState(Block.Running, Block.Ok);
End;

{ One outline block. The title always rides; the phone has no other way to learn it. The body rides when its escaped
  text is at most MonitorOutlineBodyBytes, so a restored conversation reads the same as the desktop before any
  block_get. }
Function OutlineBlock(Const Block: TAssistantMonitorBlock): String;
Var
  Escaped: String;
Begin
  Result := '{"block_id":"' + JsonEscapeText(Block.BlockId) + '","kind":"' + JsonEscapeText(Block.Kind) + '","title":"' +
    JsonEscapeText(Block.Title) + '","state":"' + BlockState(Block) + '","revision":' + IntToStr(Block.Revision) +
    ',"body_bytes":' + IntToStr(Length(UTF8String(Block.Body))) + ',"hash":"' + Fnv1a64(UTF8String(Block.Body)) + '"';
  { A body far over the limit is not escaped only to be measured. Escaping never shortens text. }
  If Length(Block.Body) <= MonitorOutlineBodyBytes Then
    Begin
      Escaped := JsonEscapeText(Block.Body);
      If Length(Escaped) <= MonitorOutlineBodyBytes Then
        Result := Result + ',"body":"' + Escaped + '"';
    End;
  Result := Result + '}';
End;

{ At most MonitorPreviewBytes of the prompt, cut between UTF-8 characters. A cut inside a character would be
  replaced by JsonEscapeText, so the preview would no longer be a prefix of the prompt. }
Function Preview(Const Text: String): String;
Begin
  Result := Copy(Text, 1, MonitorUtf8CutLength(Text, MonitorPreviewBytes));
End;

Function OutlineTurn(Const Turn: TAssistantMonitorTurn; FirstBlock, BlockCount: Integer): String;
Var
  Index: Integer;
  Blocks, One: String;
Begin
  Blocks := '';
  For Index := FirstBlock To FirstBlock + BlockCount - 1 Do
    Begin
      One := OutlineBlock(Turn.Blocks[Index]);
      If Blocks <> '' Then
        Blocks := Blocks + ',';
      Blocks := Blocks + One;
    End;
  Result := '{"turn_id":"' + JsonEscapeText(Turn.Id) + '","turn_index":' + IntToStr(Turn.TurnIndex) + ',"prompt_preview":"' +
    JsonEscapeText(Preview(Turn.Prompt)) + '","blocks":[' + Blocks + ']}';
End;

Procedure AddFrame(Var Answer: TMonitorSyncAnswer; Kind: TMonitorSyncFrameKind; Const Json: String);
Begin
  SetLength(Answer.Frames, Length(Answer.Frames) + 1);
  Answer.Frames[High(Answer.Frames)].Kind := Kind;
  Answer.Frames[High(Answer.Frames)].Json := Json;
End;

Function Envelope(Const Id, TypeName, Payload: String): String;
Begin
  Result := '{"v":3,"id":"' + JsonEscapeText(Id) + '","type":"' + TypeName + '","payload":' + Payload + '}';
End;

Function MonitorSyncResumeAnswer(Const Source: TMonitorResumeSource; Const RequestedId, PhoneStream, ResumeId: String;
  PhoneSeq: Int64; Const Status: TMonitorSyncStatus): TMonitorSyncAnswer;
Var
  Turns: String;
  Index: Integer;
  BeginPayload, PagePayload, OpenBlock, Body: String;
  Open: TAssistantMonitorBlock;
  HaveOpen: Boolean;
  Pages: TStringArray;

  Procedure FinishPage;
  Begin
    If Turns = '' Then
      Exit;
    SetLength(Pages, Length(Pages) + 1);
    Pages[High(Pages)] := Turns;
    Turns := '';
  End;

  Procedure AddTurn(Const Turn: TAssistantMonitorTurn; FirstBlock, BlockCount: Integer);
  Const
    OutlinePageBytes = 24 * 1024;
  Var
    Outline: String;
    Half: Integer;
  Begin
    Outline := OutlineTurn(Turn, FirstBlock, BlockCount);
    { A single long turn can have hundreds of tool blocks. Repeat its identity on
      subsequent pages so every block arrives without exceeding the queue limit. }
    If (Length(Outline) > OutlinePageBytes) And (BlockCount > 1) Then
      Begin
        Half := BlockCount Div 2;
        AddTurn(Turn, FirstBlock, Half);
        AddTurn(Turn, FirstBlock + Half, BlockCount - Half);
        Exit;
      End;
    If (Turns <> '') And (Length(Turns) + Length(Outline) + 1 > OutlinePageBytes) Then
      FinishPage;
    If Turns <> '' Then
      Turns := Turns + ',';
    Turns := Turns + Outline;
  End;

Begin
  Result := Default(TMonitorSyncAnswer);
  Result.Head := Source.Head;
  Result.Generation := Source.Head + 1;
  If (Not Source.Found) Or (Not Source.Observed) Then
    Begin
      Result.NotReady := True;
      AddFrame(Result, mskControl, Envelope(ResumeId + '-wait', 'not_ready', '{"conversation_id":"' +
        JsonEscapeText(RequestedId) + '"}'));
      Exit;
    End;
  If (PhoneStream <> '') And (LowerCase(PhoneStream) = LowerCase(Source.StreamId)) And TailHeld(Source, PhoneSeq) Then
    Begin
      Result.Replay := True;
      AddFrame(Result, mskControl, Envelope(ResumeId + '-ok', 'resume_ok', '{"conversation_id":"' +
        JsonEscapeText(Source.ConversationId) + '","stream_id":"' + JsonEscapeText(Source.StreamId) + '","from_seq":' +
        IntToStr(PhoneSeq + 1) + ',"to_seq":' + IntToStr(Source.Head) + '}'));
      Exit;
    End;
  Turns := '';
  SetLength(Pages, 0);
  If Source.HasLive Then
    AddTurn(Source.Live, 0, Length(Source.Live.Blocks));
  For Index := 0 To High(Source.Turns) Do
    AddTurn(Source.Turns[Index], 0, Length(Source.Turns[Index].Blocks));
  FinishPage;
  HaveOpen := False;
  Open := Default(TAssistantMonitorBlock);
  If Source.HasLive Then
    For Index := 0 To High(Source.Live.Blocks) Do
      If Source.Live.Blocks[Index].Running Then
        Begin
          Open := Source.Live.Blocks[Index];
          HaveOpen := True;
          Break;
        End;
  OpenBlock := '';
  If HaveOpen Then
    Begin
      Body := Open.Body;
      OpenBlock := ',"open_block":{"block_id":"' + JsonEscapeText(Open.BlockId) + '","revision":' + IntToStr(Open.Revision) +
        ',"body":"' + JsonEscapeText(Body) + '","body_bytes":' + IntToStr(Length(UTF8String(Body))) + ',"hash":"' +
        Fnv1a64(UTF8String(Body)) + '"}';
      If Length(OpenBlock) > MonitorOutboxChunkBytes Div 2 Then
        OpenBlock := '';
    End;
  BeginPayload := '{"conversation_id":"' + JsonEscapeText(Source.ConversationId) + '","stream_id":"' +
    JsonEscapeText(Source.StreamId) + '","seq":' + IntToStr(Source.Head) + ',"title":"' + JsonEscapeText(Source.Title) +
    '","project_root":"' + JsonEscapeText(Source.ProjectRoot) + '","turn_count":' +
    IntToStr(Length(Source.Turns) + Ord(Source.HasLive)) + ',"page_count":' + IntToStr(Length(Pages)) + OpenBlock + '}';
  AddFrame(Result, mskControl, Envelope(ResumeId + '-begin', 'snapshot_begin', BeginPayload));
  For Index := 0 To High(Pages) Do
    Begin
      PagePayload := '{"conversation_id":"' + JsonEscapeText(Source.ConversationId) + '","stream_id":"' +
        JsonEscapeText(Source.StreamId) + '","seq":' + IntToStr(Source.Head) + ',"page":' + IntToStr(Index + 1) +
        ',"page_count":' + IntToStr(Length(Pages)) + ',"turns":[' + Pages[Index] + ']}';
      AddFrame(Result, mskBulk, Envelope(ResumeId + '-page-' + IntToStr(Index + 1), 'snapshot_page', PagePayload));
    End;
  AddFrame(Result, mskBarrier, Envelope(ResumeId + '-end', 'snapshot_end', '{"conversation_id":"' +
    JsonEscapeText(Source.ConversationId) + '","stream_id":"' + JsonEscapeText(Source.StreamId) + '","seq":' +
    IntToStr(Source.Head) + '}'));
End;

{ The string member Name of Obj. Empty when Obj is Nil, or the member is missing or is not a string. }
Function StringMember(Obj: TJSONObject; Const Name: String): String;
Var
  Item: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then
    Exit;
  Item := Obj.Find(Name);
  If Item Is TJSONString Then
    Result := Item.AsString;
End;

Function MonitorSyncClassify(Const Json: String; Out Lane: TMonitorSyncLane; Out StateKey: String): Boolean;
Var
  Data: TJSONData;
  Root, Payload: TJSONObject;
  TypeName, Key, ItemType: String;
Begin
  Lane := mslControl;
  StateKey := '';
  Result := False;
  { Parsed, not searched as text. fpjson AsJSON writes "type" : "plan_data", with spaces. Known producers
    pass the lane to QueueFrame and do not call this. Unknown-origin frames still do. }
  Data := Nil;
  Try
    {$IFDEF MONITOR_COUNT_PARSES}
    MonitorNoteJsonParse;
    {$ENDIF}
    Data := GetJSON(Json);
  Except
    Data := Nil;
  End;
  Try
    If Not (Data Is TJSONObject) Then
      Exit;
    Root := TJSONObject(Data);
    Payload := Nil;
    If Root.Find('payload') Is TJSONObject Then
      Payload := TJSONObject(Root.Find('payload'));
    TypeName := StringMember(Root, 'type');
    If TypeName = 'state' Then
      Begin
        Key := StringMember(Payload, 'key');
        StateKey := Key;
        If Key = 'approval' Then
          Lane := mslControl
        Else
          Lane := mslState;
        Result := True;
      End
    Else If TypeName = 'event' Then
      Begin
        Lane := mslLog;
        Result := True;
      End
    Else If (TypeName = 'block_data') Or (TypeName = 'image_data') Or (TypeName = 'plan_data') Or
      (TypeName = 'snapshot_page') Then
      Begin
        Lane := mslBulk;
        Result := True;
      End
    Else If TypeName = 'snapshot_end' Then
      Begin
        Lane := mslBarrier;
        Result := True;
      End
    Else If TypeName = 'chunk' Then
      Begin
        ItemType := StringMember(Payload, 'item_type');
        If ItemType = 'state' Then
          Begin
            Lane := mslState;
            StateKey := StringMember(Payload, 'item_id');
            If StateKey = 'approval' Then
              Lane := mslControl;
            Result := True;
          End
        Else If (ItemType = 'block_data') Or (ItemType = 'image_data') Or (ItemType = 'plan_data') Or
          (ItemType = 'snapshot_page') Then
          Begin
            Lane := mslBulk;
            Result := True;
          End;
      End;
  Finally
    Data.Free;
  End;
End;

Function MonitorSyncStateFrame(Const Id, Key, ValueJson: String): String;
Begin
  Result := Envelope(Id, 'state', '{"key":"' + JsonEscapeText(Key) + '","value":' + ValueJson + '}');
End;

Function MonitorSyncEventSeq(Const Json: String): Int64;
Var
  Token, Tail: String;
  At, EndAt: Integer;
Begin
  Result := 0;
  Token := '"seq":';
  At := Pos(Token, Json);
  If At = 0 Then
    Exit;
  Tail := Copy(Json, At + Length(Token), 24);
  EndAt := 1;
  While (EndAt <= Length(Tail)) And (Tail[EndAt] In ['0'..'9', '-']) Do
    Inc(EndAt);
  Result := StrToInt64Def(Copy(Tail, 1, EndAt - 1), 0);
End;

Function MonitorSyncStateFrames(Const Id, Key, ValueJson: String): TStringArray;
Var
  Whole, Rest: String;
  Pieces: TStringArray;
  Part, At, Step: Integer;
Begin
  SetLength(Result, 0);
  Whole := MonitorSyncStateFrame(Id, Key, ValueJson);
  If Length(Whole) <= MonitorOutboxChunkBytes Then
    Begin
      SetLength(Result, 1);
      Result[0] := Whole;
      Exit;
    End;
  { The raw value is cut before it is escaped, and only between UTF-8 characters. Each chunk is then valid UTF-8,
    and JsonEscapeText has no broken character to replace. A cut inside a \u escape of the value is harmless,
    because the phone joins the decoded data strings before it parses the value. A piece whose escaped form would
    not fit the chunk is cut again at half its length. }
  SetLength(Pieces, 0);
  At := 1;
  While At <= Length(ValueJson) Do
    Begin
      Rest := Copy(ValueJson, At, MonitorStateChunkRawBytes + 4);
      Step := MonitorUtf8CutLength(Rest, MonitorStateChunkRawBytes);
      While (Step > 1) And (Length(JsonEscapeText(Copy(Rest, 1, Step))) > MonitorStateChunkDataBytes) Do
        Step := MonitorUtf8CutLength(Rest, Step Div 2);
      SetLength(Pieces, Length(Pieces) + 1);
      Pieces[High(Pieces)] := Copy(Rest, 1, Step);
      Inc(At, Step);
    End;
  SetLength(Result, Length(Pieces));
  For Part := 1 To Length(Pieces) Do
    Result[Part - 1] := Envelope(Id + '-c' + IntToStr(Part), 'chunk', '{"item_id":"' + JsonEscapeText(Key) +
      '","part":' + IntToStr(Part) + ',"part_count":' + IntToStr(Length(Pieces)) + ',"item_type":"state","data":"' +
      JsonEscapeText(Pieces[Part - 1]) + '"}');
End;

{ A JSON string literal, quotes included. }
Function Quoted(Const Text: String): String;
Begin
  Result := '"' + JsonEscapeText(Text) + '"';
End;

Function MonitorConversationValueJson(Const ConversationId: String): String;
Begin
  Result := '{"id":' + Quoted(ConversationId) + '}';
End;

Function MonitorStatusValueJson(Const View: TAssistantMonitorView): String;
Begin
  Result := '{"busy":' + MonitorBoolean(View.Sending Or View.PlanRunning) + ',"sending":' + MonitorBoolean(View.Sending) + ',"plan_running":' +
    MonitorBoolean(View.PlanRunning) + ',"phase":' + Quoted(View.Phase) + ',"status_text":' + Quoted(View.StatusText) +
    ',"started_at":' + Quoted(View.StartedAt) + ',"can_send":' + MonitorBoolean(View.CanSend) + ',"can_steer":' +
    MonitorBoolean(View.CanSteer) + ',"can_stop":' + MonitorBoolean(View.CanStop) + ',"can_change_mode":' + MonitorBoolean(View.CanChangeMode) +
    ',"error_text":' + Quoted(View.ErrorText) + '}';
End;

Function MonitorResumeStatusValueJson(Const Status: TMonitorSyncStatus): String;
Begin
  Result := '{"busy":' + MonitorBoolean(Status.Busy) + ',"sending":' + MonitorBoolean(Status.Sending) + ',"plan_running":' +
    MonitorBoolean(Status.PlanRunning) + ',"phase":"","status_text":"","can_send":' + MonitorBoolean(Status.CanSend) + ',"can_steer":' +
    MonitorBoolean(Status.CanSteer) + ',"can_stop":' + MonitorBoolean(Status.CanStop) + ',"can_change_mode":' + MonitorBoolean(Status.CanChangeMode) +
    ',"started_at":"","error_text":""}';
End;

Function MonitorApprovalValueJson(Active: Boolean; Const ToolId: String): String;
Begin
  If Active Then
    Result := '{"active":true,"tool_id":' + Quoted(ToolId) + '}'
  Else
    Result := '{"active":false}';
End;

Function MonitorSessionValueJson(Const View: TAssistantMonitorView): String;
Begin
  Result := '{"model":' + Quoted(View.Model) + ',"backend":' + Quoted(View.Backend) + ',"signed_in":' +
    MonitorBoolean(View.SignedIn) + ',"effort":' + Quoted(View.Effort) + ',"skill":' + Quoted(View.Skill) + ',"context_text":' +
    Quoted(View.ContextText) + ',"remote_approval":' + MonitorBoolean(View.RemoteApproval) + ',"approval_caption":' +
    Quoted(View.ApprovalCaption) + '}';
End;

Function MonitorModeValueJson(Const View: TAssistantMonitorView): String;
Begin
  Result := '{"mode":' + Quoted(View.Mode) + ',"locked":' + MonitorBoolean(View.ModeLocked) + '}';
End;

Function MonitorTargetValueJson(Const View: TAssistantMonitorView): String;
Begin
  Result := '{"kind":' + Quoted(View.TargetKind) + ',"display":' + Quoted(View.TargetDisplay) + ',"root":' +
    Quoted(View.TargetRoot) + '}';
End;

Function MonitorChoiceArrayJson(Paths, Captions: TStrings): String;
Var
  Index: Integer;
Begin
  Result := '';
  If (Not Assigned(Paths)) Or (Not Assigned(Captions)) Then
    Exit;
  For Index := 0 To Paths.Count - 1 Do
    Begin
      If Index >= Captions.Count Then
        Break;
      If Result <> '' Then
        Result := Result + ',';
      Result := Result + '{"path":' + Quoted(Paths[Index]) + ',"caption":' + Quoted(Captions[Index]) + '}';
    End;
End;

Function MonitorTargetsValueJson(Const Current: String; Paths, Captions: TStrings): String;
Begin
  Result := '{"current":' + Quoted(Current) + ',"choices":[' + MonitorChoiceArrayJson(Paths, Captions) + ']}';
End;

Function MonitorConversationsValueJson(Const Current: String; Truncated: Boolean; Ids, Titles: TStrings): String;
Begin
  Result := '{"current":' + Quoted(Current) + ',"truncated":' + MonitorBoolean(Truncated) + ',"choices":[' +
    MonitorChoiceArrayJson(Ids, Titles) + ']}';
End;

Function MonitorNamedChoicesValueJson(Const Current, Backend, Note: String; HasBackend: Boolean; Ids, Captions: TStrings): String;
Begin
  Result := '{"current":' + Quoted(Current);
  If HasBackend Then
    Result := Result + ',"backend":' + Quoted(Backend);
  Result := Result + ',"note":' + Quoted(Note) + ',"choices":[' + MonitorChoiceArrayJson(Ids, Captions) + ']}';
End;

Function MonitorPlanChoicesValueJson(Paths, Captions: TStrings): String;
Begin
  Result := '{"choices":[' + MonitorChoiceArrayJson(Paths, Captions) + ']}';
End;

Function MonitorPlanValueJson(Const Path, Title: String; Running: Boolean; Const Revision: String;
  Const Rows: Array Of TAssistantMonitorPlanRow): String;
Var
  Index: Integer;
  RowsJson: String;
Begin
  RowsJson := '';
  For Index := 0 To High(Rows) Do
    Begin
      If RowsJson <> '' Then
        RowsJson := RowsJson + ',';
      RowsJson := RowsJson + '{"index":' + IntToStr(Rows[Index].Index) + ',"level":' + IntToStr(Rows[Index].Level) +
        ',"title":' + Quoted(Rows[Index].Title) + ',"parent_title":' + Quoted(Rows[Index].ParentTitle) + ',"status":' +
        Quoted(Rows[Index].Status) + ',"actionable":' + MonitorBoolean(Rows[Index].Actionable) + '}';
    End;
  Result := '{"path":' + Quoted(Path) + ',"title":' + Quoted(Title) + ',"running":' + MonitorBoolean(Running) + ',"revision":' +
    Quoted(Revision) + ',"rows":[' + RowsJson + ']}';
End;

Function MonitorTasksValueJson(Const Rows: Array Of TAssistantMonitorTaskRow): String;
Var
  Index: Integer;
  RowsJson: String;
Begin
  RowsJson := '';
  For Index := 0 To High(Rows) Do
    Begin
      If RowsJson <> '' Then
        RowsJson := RowsJson + ',';
      RowsJson := RowsJson + '{"id":' + Quoted(Rows[Index].Id) + ',"title":' + Quoted(Rows[Index].Title) + ',"summary":' +
        Quoted(Rows[Index].Summary) + ',"mode":' + Quoted(Rows[Index].Mode) + '}';
    End;
  Result := '{"rows":[' + RowsJson + ']}';
End;

End.
