Program AssistantMonitorMirrorTest;

{ The monitor log keeps each conversation, folds old events into the model, and pages a snapshot.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantSessionObserve, AssistantMonitorMirror;

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
  Events: TMonitorMirrorEventArray;
  Head: Int64;
  Turn: TAssistantMonitorTurn;
  Pages: TMonitorSnapshotPageArray;
  Stored: Array Of TAssistantMonitorTurn;
  Live: TAssistantMonitorTurn;
  HasLive: Boolean;
  Suffix, HeldJson: String;
  Offset: Integer;
  HeldSeq: Int64;
  Credit: TMonitorLogCredit;
  Keep: TMonitorMirror;
Begin
  Log := TMonitorMirror.Create(64);
  Try
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    Log.RememberPatch(1, StringOfChar('a', 40));
    Log.RememberPatch(2, StringOfChar('b', 40));
    Check('an unacked patch is not dropped to make room', Log.DroppedThrough = 0);
    Check('resume still has the unacked patch', Log.TryReplayPatches('ab12cd34', 0, 1, Events, Head) And
      (Length(Events) = 1) And (Events[0].Seq = 1));
    Log.NoteAck('ab12cd34', 1);
    Log.RememberPatch(2, StringOfChar('b', 40));
    Check('an ack lets the older patch be folded', Log.DroppedThrough >= 1);
    Check('resume at the kept patch is a tail', Log.TryReplayPatches('ab12cd34', 1, 2, Events, Head) And
      (Length(Events) = 1) And (Events[0].Seq = 2));
    Log.ObserveTurn(SampleTurn('turn-a', StringOfChar('x', MonitorInlineBodyBytes + 1), 0));
    Check('folded events still materialise the turn', Log.FetchTurn(0, Turn) And (Turn.Id = 'turn-a') And
      (Length(Turn.Blocks[0].Body) = MonitorInlineBodyBytes + 1) And (Turn.Images[0].Id = 'turn-a-image'));
    Check('snapshot pages start with the turn list', Log.BuildSnapshotPages('ab12cd34', Log.Head, Pages) And
      (Length(Pages) >= 2) And (Pos('"turns":', Pages[0].Json) > 0) And (Pages[1].Page = 1));
    Check('a large body is marked deferred, not cut', Pos('"deferred":true', Pages[1].Json) > 0);
    Log.BeginStream('eeff0011', 'conversation-b', '/work/Two', 'Two');
    Log.RememberPatch(1, 'second');
    Log.BeginStream('ab12cd34', 'conversation-a', '/work/One', 'One');
    Check('the first conversation still has its turn', Log.FetchTurn(0, Turn) And (Turn.Id = 'turn-a'));
    Check('the second conversation is not this stream', Not Log.TryReplayPatches('eeff0011', 0, 1, Events, Head));
    Log.CopyTurns(Stored, Live, HasLive);
    Check('copy does not need a form', Length(Stored) = 1);
    Check('a grown body is an append at the UTF-8 length', MonitorAppendSuffix('Größe → ', 'Größe → 10 s.', Suffix, Offset) And
      (Offset = 12) And (Suffix = '10 s.'));
    Check('a changed prefix is not an append', Not MonitorAppendSuffix('old text', 'new text', Suffix, Offset));
    Credit := TMonitorLogCredit.Create;
    Try
      Credit.NoteSent(1, 400000);
      Check('credit accepts a frame inside the window', Credit.CanSend(100000));
      Credit.NoteSent(2, 200000);
      Check('credit window holds the next frame', Not Credit.CanSend(1));
      Credit.Hold(3, 'held');
      Credit.NoteAck(2);
      Check('an ack releases the unacked bytes', Credit.UnackedBytes = 0);
      Check('the held frame can leave after the ack', Credit.TakeHeld(HeldSeq, HeldJson) And (HeldSeq = 3) And (HeldJson = 'held'));
    Finally
      Credit.Free;
    End;
    Keep := TMonitorMirror.Create(20);
    Try
      Keep.BeginStream('ab12cd34', 'conversation-a', '/work', 'One');
      Keep.RememberPatch(1, 'aaaa');
      Check('the first event is stored', Keep.ByteCount = 9);
      Keep.RememberPatch(2, 'bbbbbbbb');
      Check('an unacked event is not folded away', Keep.ByteCount = 9);
      Keep.NoteAck('ab12cd34', 1);
      Keep.RememberPatch(3, 'cccccccc');
      Check('an acknowledged event can be folded', (Keep.AckedSeq = 1) And (Keep.ByteCount = 13));
    Finally
      Keep.Free;
    End;
  Finally
    Log.Free;
  End;
End;

Begin
  FailCount := 0;
  TestFoldAndReplay;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorMirrorTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failure(s)');
      Halt(1);
    End;
End.
