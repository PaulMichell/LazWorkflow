Unit AssistantMonitorSync;

{ Frames stored mirror events for the log lane (c) 2026 Michell Computing.

  The mirror is the producer and the replay store. This unit does not read the
  assistant form and does not allocate a content sequence. A status or plan
  change is state, not an event. }

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

Implementation

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

End.
