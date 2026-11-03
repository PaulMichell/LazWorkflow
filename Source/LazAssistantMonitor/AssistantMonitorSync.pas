Unit AssistantMonitorSync;

{ Resume decisions, slice framing, state classification, and the baseline
  (c) 2026 Michell Computing.

  The mirror is the producer and the replay store. This unit does not read the
  assistant form and does not allocate a content sequence. A status or plan
  change is state, not an event. Stay under 1000 lines; split a sibling before
  crossing that line. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorMirror, AssistantMonitorOutbox;

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
  Fetch answers and turn pages are bulk. snapshot_end is the barrier. }
Function MonitorSyncClassify(Const Json: String; Out Lane: TMonitorSyncLane; Out StateKey: String): Boolean;
Function MonitorSyncStateFrame(Const Id, Key, ValueJson: String): String;
{ One state frame, or chunk frames of that value when the envelope exceeds 32 KiB. }
Function MonitorSyncEventSeq(Const Json: String): Int64;
Function MonitorSyncStateFrames(Const Id, Key, ValueJson: String): TStringArray;

{ One resume answer. State frames are not included; the caller queues those first. }
Function MonitorSyncResumeAnswer(Const Source: TMonitorResumeSource; Const RequestedId, PhoneStream, ResumeId: String;
  PhoneSeq: Int64; Const Status: TMonitorSyncStatus): TMonitorSyncAnswer;

Implementation

Uses
  AssistantSessionObserve;

Function JsonEscape(Const Text: String): String;
Var
  Index, OutLen, At: Integer;
  C: Char;
Begin
  OutLen := 0;
  For Index := 1 To Length(Text) Do
    If (Text[Index] = '"') Or (Text[Index] = '\') Then
      Inc(OutLen, 2)
    Else
      Inc(OutLen);
  SetLength(Result, OutLen);
  At := 1;
  For Index := 1 To Length(Text) Do
    Begin
      C := Text[Index];
      If (C = '"') Or (C = '\') Then
        Begin
          Result[At] := '\';
          Result[At + 1] := C;
          Inc(At, 2);
        End
      Else
        Begin
          Result[At] := C;
          Inc(At);
        End;
    End;
End;

Function EventFrame(Const ConversationId, StreamId: String; Const Event: TMonitorMirrorEvent): String;
Begin
  Result := '{"v":3,"id":"e-' + IntToStr(Event.Seq) + '","type":"event","payload":{"conversation_id":"' +
    JsonEscape(ConversationId) + '","stream_id":"' + JsonEscape(StreamId) + '","seq":' + IntToStr(Event.Seq) +
    ',"event":"' + JsonEscape(Event.Kind) + '","data":' + String(Event.Data) + '}}';
End;

Function FindSeq(Const Events: TMonitorMirrorEventArray; Seq: Int64): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := 0 To High(Events) Do
    If Events[Index].Seq = Seq Then
      Exit(Index);
End;

Function MonitorSyncCanReplay(Mirror: TMonitorMirror; Seq: Int64): Boolean;
Var
  Events: TMonitorMirrorEventArray;
  Next: Int64;
Begin
  Result := False;
  Events := Nil;
  If Not Assigned(Mirror) Or (Seq < 0) Or (Seq > Mirror.Head) Then
    Exit;
  Mirror.CopyEvents(Events);
  Next := Seq + 1;
  While Next <= Mirror.Head Do
    Begin
      If FindSeq(Events, Next) < 0 Then
        Exit;
      Inc(Next);
    End;
  Result := True;
End;

Function UnackedBytes(Const Events: TMonitorMirrorEventArray; Const ConversationId, StreamId: String;
  PhoneAck, ThroughSeq: Int64): Int64;
Var
  Index: Integer;
Begin
  Result := 0;
  For Index := 0 To High(Events) Do
    If (Events[Index].Seq > PhoneAck) And (Events[Index].Seq <= ThroughSeq) Then
      Result := Result + Length(EventFrame(ConversationId, StreamId, Events[Index]));
End;

Procedure MonitorSyncFill(Mirror: TMonitorMirror; Outbox: TMonitorOutbox; Const ConversationId, StreamId: String;
  PhoneAck: Int64; Var QueuedSeq: Int64; Out CloseLink: Boolean);
Var
  Events: TMonitorMirrorEventArray;
  NextSeq: Int64;
  Index: Integer;
  Frame: String;
Begin
  CloseLink := False;
  Events := Nil;
  If Not Assigned(Mirror) Or Not Assigned(Outbox) Or (StreamId = '') Then
    Exit;
  Mirror.CopyEvents(Events);
  While QueuedSeq < Mirror.Head Do
    Begin
      NextSeq := QueuedSeq + 1;
      Index := FindSeq(Events, NextSeq);
      If Index < 0 Then
        Exit;
      If UnackedBytes(Events, ConversationId, StreamId, PhoneAck, NextSeq) > MonitorCreditWindowBytes Then
        Exit;
      Frame := EventFrame(ConversationId, StreamId, Events[Index]);
      If Not Outbox.AppendLog(NextSeq, Frame) Then
        Exit;
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
  Next: Int64;
Begin
  Result := False;
  If (PhoneSeq < 0) Or (PhoneSeq > Source.Head) Or (PhoneSeq < Source.DroppedThrough) Then
    Exit;
  Next := PhoneSeq + 1;
  While Next <= Source.Head Do
    Begin
      If FindSeq(Source.Events, Next) < 0 Then
        Exit;
      Inc(Next);
    End;
  Result := True;
End;

Function Fnv1a64(Const Text: RawByteString): String;
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

Function BlockState(Const Block: TAssistantMonitorBlock): String;
Begin
  If Block.Running Then
    Result := 'running'
  Else If Block.Ok Then
    Result := 'ok'
  Else
    Result := 'failed';
End;

Function Preview(Const Text: String): String;
Begin
  If Length(Text) <= 80 Then
    Result := Text
  Else
    Result := Copy(Text, 1, 80);
End;

Function OutlineTurn(Const Turn: TAssistantMonitorTurn): String;
Var
  Index: Integer;
  Blocks, One: String;
Begin
  Blocks := '';
  For Index := 0 To High(Turn.Blocks) Do
    Begin
      One := '{"block_id":"' + JsonEscape(Turn.Blocks[Index].BlockId) + '","kind":"' + JsonEscape(Turn.Blocks[Index].Kind) +
        '","state":"' + BlockState(Turn.Blocks[Index]) + '","revision":' + IntToStr(Turn.Blocks[Index].Revision) +
        ',"body_bytes":' + IntToStr(Length(UTF8String(Turn.Blocks[Index].Body))) + ',"hash":"' +
        Fnv1a64(UTF8String(Turn.Blocks[Index].Body)) + '"}';
      If Blocks <> '' Then
        Blocks := Blocks + ',';
      Blocks := Blocks + One;
    End;
  Result := '{"turn_id":"' + JsonEscape(Turn.Id) + '","turn_index":' + IntToStr(Turn.TurnIndex) + ',"prompt_preview":"' +
    JsonEscape(Preview(Turn.Prompt)) + '","blocks":[' + Blocks + ']}';
End;

Procedure AddFrame(Var Answer: TMonitorSyncAnswer; Kind: TMonitorSyncFrameKind; Const Json: String);
Begin
  SetLength(Answer.Frames, Length(Answer.Frames) + 1);
  Answer.Frames[High(Answer.Frames)].Kind := Kind;
  Answer.Frames[High(Answer.Frames)].Json := Json;
End;

Function Envelope(Const Id, TypeName, Payload: String): String;
Begin
  Result := '{"v":3,"id":"' + JsonEscape(Id) + '","type":"' + TypeName + '","payload":' + Payload + '}';
End;

Function YesNo(Condition: Boolean): String;
Begin
  If Condition Then
    Result := 'true'
  Else
    Result := 'false';
End;

Function MonitorSyncResumeAnswer(Const Source: TMonitorResumeSource; Const RequestedId, PhoneStream, ResumeId: String;
  PhoneSeq: Int64; Const Status: TMonitorSyncStatus): TMonitorSyncAnswer;
Var
  Turns: String;
  Index: Integer;
  BeginPayload, PagePayload, OpenBlock, Body: String;
  Open: TAssistantMonitorBlock;
  HaveOpen: Boolean;
Begin
  Result := Default(TMonitorSyncAnswer);
  Result.Head := Source.Head;
  Result.Generation := Source.Head + 1;
  If (Not Source.Found) Or (Not Source.Observed) Then
    Begin
      Result.NotReady := True;
      AddFrame(Result, mskControl, Envelope(ResumeId + '-wait', 'not_ready', '{"conversation_id":"' +
        JsonEscape(RequestedId) + '"}'));
      Exit;
    End;
  If (PhoneStream <> '') And (LowerCase(PhoneStream) = LowerCase(Source.StreamId)) And TailHeld(Source, PhoneSeq) Then
    Begin
      Result.Replay := True;
      AddFrame(Result, mskControl, Envelope(ResumeId + '-ok', 'resume_ok', '{"conversation_id":"' +
        JsonEscape(Source.ConversationId) + '","stream_id":"' + JsonEscape(Source.StreamId) + '","from_seq":' +
        IntToStr(PhoneSeq + 1) + ',"to_seq":' + IntToStr(Source.Head) + '}'));
      Exit;
    End;
  Turns := '';
  If Source.HasLive Then
    Turns := OutlineTurn(Source.Live);
  For Index := 0 To High(Source.Turns) Do
    Begin
      If Turns <> '' Then
        Turns := Turns + ',';
      Turns := Turns + OutlineTurn(Source.Turns[Index]);
    End;
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
      OpenBlock := ',"open_block":{"block_id":"' + JsonEscape(Open.BlockId) + '","revision":' + IntToStr(Open.Revision) +
        ',"body":"' + JsonEscape(Body) + '","body_bytes":' + IntToStr(Length(UTF8String(Body))) + ',"hash":"' +
        Fnv1a64(UTF8String(Body)) + '"}';
      If Length(OpenBlock) > MonitorOutboxChunkBytes Div 2 Then
        OpenBlock := '';
    End;
  BeginPayload := '{"conversation_id":"' + JsonEscape(Source.ConversationId) + '","stream_id":"' + JsonEscape(Source.StreamId) +
    '","seq":' + IntToStr(Source.Head) + ',"title":"' + JsonEscape(Source.Title) + '","project_root":"' +
    JsonEscape(Source.ProjectRoot) + '","turn_count":' + IntToStr(Length(Source.Turns) + Ord(Source.HasLive)) +
    ',"page_count":1' + OpenBlock + '}';
  AddFrame(Result, mskControl, Envelope(ResumeId + '-begin', 'snapshot_begin', BeginPayload));
  PagePayload := '{"conversation_id":"' + JsonEscape(Source.ConversationId) + '","stream_id":"' + JsonEscape(Source.StreamId) +
    '","seq":' + IntToStr(Source.Head) + ',"page":1,"page_count":1,"turns":[' + Turns + ']}';
  AddFrame(Result, mskBulk, Envelope(ResumeId + '-page', 'snapshot_page', PagePayload));
  AddFrame(Result, mskBarrier, Envelope(ResumeId + '-end', 'snapshot_end', '{"conversation_id":"' +
    JsonEscape(Source.ConversationId) + '","stream_id":"' + JsonEscape(Source.StreamId) + '","seq":' +
    IntToStr(Source.Head) + '}'));
End;

Function QuotedField(Const Json, Name: String): String;
Var
  Token, Tail: String;
  At: Integer;
Begin
  Result := '';
  Token := '"' + Name + '":"';
  At := Pos(Token, Json);
  If At = 0 Then
    Exit;
  Tail := Copy(Json, At + Length(Token), MaxInt);
  At := Pos('"', Tail);
  If At = 0 Then
    Exit;
  Result := Copy(Tail, 1, At - 1);
End;

Function MonitorSyncClassify(Const Json: String; Out Lane: TMonitorSyncLane; Out StateKey: String): Boolean;
Var
  TypeName, Key, ItemType: String;
Begin
  Lane := mslControl;
  StateKey := '';
  Result := False;
  TypeName := QuotedField(Json, 'type');
  If TypeName = 'state' Then
    Begin
      Key := QuotedField(Json, 'key');
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
      ItemType := QuotedField(Json, 'item_type');
      If ItemType = 'state' Then
        Begin
          Lane := mslState;
          StateKey := QuotedField(Json, 'item_id');
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
End;

Function MonitorSyncStateFrame(Const Id, Key, ValueJson: String): String;
Begin
  Result := Envelope(Id, 'state', '{"key":"' + JsonEscape(Key) + '","value":' + ValueJson + '}');
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
  Whole, Piece: String;
  Part, PartCount, At, Step: Integer;
Begin
  SetLength(Result, 0);
  Whole := MonitorSyncStateFrame(Id, Key, ValueJson);
  If Length(Whole) <= MonitorOutboxChunkBytes Then
    Begin
      SetLength(Result, 1);
      Result[0] := Whole;
      Exit;
    End;
  PartCount := (Length(ValueJson) Div 20000) + 1;
  SetLength(Result, PartCount);
  At := 1;
  For Part := 1 To PartCount Do
    Begin
      Step := Length(ValueJson) - At + 1;
      If Step > 20000 Then
        Step := 20000;
      Piece := Copy(ValueJson, At, Step);
      Result[Part - 1] := Envelope(Id + '-c' + IntToStr(Part), 'chunk', '{"item_id":"' + JsonEscape(Key) +
        '","part":' + IntToStr(Part) + ',"part_count":' + IntToStr(PartCount) + ',"item_type":"state","data":"' +
        JsonEscape(Piece) + '"}');
      Inc(At, Step);
    End;
End;

End.
