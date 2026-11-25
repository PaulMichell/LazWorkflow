Program AssistantMonitorStoreTest;

{ Conversation, turn and item reads from the monitor store. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, fpjson, jsonparser, AssistantPlanDocument, AssistantSessionObserve,
  AssistantMonitorSnapshot,
  AssistantMonitorStore;

Var
  FailCount: Integer;
  TempSerial: Integer;

Type
  TFakeSource = Class(TMonitorSnapshotSource)
    LiveId, ItemId, ItemBody: String;
    Live: Boolean;
    Function Fill(Snap: TMonitorSnapshot): Boolean; Override;
  End;

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

Function TFakeSource.Fill(Snap: TMonitorSnapshot): Boolean;
Begin
  Snap.Available := True;
  Snap.HasLive := Live;
  Snap.Sending := Live;
  Snap.LiveTurnId := LiveId;
  SetLength(Snap.Items, 1);
  Snap.Items[0].Id := ItemId;
  Snap.Items[0].Kind := 'answer';
  Snap.Items[0].State := 'done';
  Snap.Items[0].Revision := 1;
  Snap.Items[0].Body := ItemBody;
  Result := True;
End;

Function MakeRoot: String;
Begin
  Inc(TempSerial);
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-store-' +
    FormatDateTime('hhnnsszzz', Now) + '-' + IntToStr(TempSerial);
  ForceDirectories(Result + PathDelim + '.assistant');
  SetMonitorStoreRoot(ExcludeTrailingPathDelimiter(Result));
End;

Procedure WriteText(Const Path, Text: String);
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Text := Text;
    Lines.SaveToFile(Path);
  Finally
    Lines.Free;
  End;
End;

Function TurnLine(Const Id, Body: String): String;
Begin
  Result := '{"id":"' + Id + '","mode":"build","prompt":"ask","created_at":"2026-01-01T00:00:00Z",' +
    '"trace":[{"id":"item-' + Id + '","kind":"answer","state":"done","rev":3,"body":"' + Body + '"}]}';
End;

Function HashRange(Const Text: AnsiString; StartAt, Count: Integer): String;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If Count > 0 Then
    AssistantPlanHashFold(Hash, Text[StartAt], Count);
  Result := AssistantPlanHashHex(Hash);
End;

Procedure Pump;
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While GetTickCount64 - Start < 400 Do
    CheckSynchronize(20);
End;

Function JsonField(Const Body, Name: String): String;
Var
  Data: TJSONData;
Begin
  Result := '';
  Data := GetJSON(Body);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get(Name, '');
  Finally
    Data.Free;
  End;
End;

Function JsonInt(Const Body, Name: String): Integer;
Var
  Data: TJSONData;
Begin
  Result := -1;
  Data := GetJSON(Body);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get(Name, -1);
  Finally
    Data.Free;
  End;
End;

Procedure TestPages;
Var
  Root, Body, ETag: String;
  Status: Integer;
  Data: TJSONData;
  Turns: TJSONArray;
Begin
  Root := MakeRoot;
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.identity.json',
    '{"id":"11111111-1111-1111-1111-111111111111"}');
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.jsonl',
    TurnLine('turn-a', StringOfChar('a', 100)) + LineEnding +
    TurnLine('turn-b', StringOfChar('b', 100)) + LineEnding);
  Check('first page fits one turn', ServeMonitorRead('/v4/conversations/11111111-1111-1111-1111-111111111111/turns',
    '/v4/conversations/11111111-1111-1111-1111-111111111111/turns?from=0&max_bytes=100', '', Status, ETag, Body) And
    (Status = 200));
  Data := GetJSON(Body);
  Try
    Turns := TJSONObject(Data).Arrays['turns'];
    Check('page stops on the byte boundary', (Turns.Count = 1) And (TJSONObject(Turns.Items[0]).Get('id', '') = 'turn-a'));
    Check('next page starts at the following turn', TJSONObject(Data).Get('next', -1) = 1);
  Finally
    Data.Free;
  End;
  Check('larger budget takes both turns', ServeMonitorRead('/v4/conversations/11111111-1111-1111-1111-111111111111/turns',
    '/v4/conversations/11111111-1111-1111-1111-111111111111/turns?max_bytes=200', '', Status, ETag, Body));
  Data := GetJSON(Body);
  Try
    Check('both turns are on the page', TJSONObject(Data).Arrays['turns'].Count = 2);
    Check('finished page has no next', TJSONObject(Data).Find('next').JSONType = jtNull);
  Finally
    Data.Free;
  End;
End;

Procedure TestTails;
Var
  Root, Body, Full, CheckHash, ETag: String;
  Status, StartAt: Integer;
  ItemBody: AnsiString;
Begin
  Root := MakeRoot;
  ItemBody := StringOfChar('a', 80) + 'TAIL';
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.identity.json',
    '{"id":"22222222-2222-2222-2222-222222222222"}');
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.jsonl',
    TurnLine('turn-tail', ItemBody) + LineEnding);
  CheckHash := HashRange(ItemBody, 80 - 63, 64);
  Check('matching tail is served', ServeMonitorRead('/v4/items/item-turn-tail',
    '/v4/items/item-turn-tail?from=80&check=' + CheckHash, '', Status, ETag, Body) And (Status = 200));
  Check('matching check returns only the tail', JsonField(Body, 'text') = 'TAIL');
  Check('matching check keeps the offset', JsonInt(Body, 'start') = 80);
  Check('bad check is served', ServeMonitorRead('/v4/items/item-turn-tail',
    '/v4/items/item-turn-tail?from=80&check=0000000000000000', '', Status, ETag, Full) And (Status = 200));
  Check('bad check returns the full body', JsonField(Full, 'text') = String(ItemBody));
  Check('bad check starts at zero', JsonInt(Full, 'start') = 0);
  ItemBody := StringOfChar('a', 64) + #$C3#$A9 + 'z';
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.jsonl',
    TurnLine('turn-utf', ItemBody) + LineEnding);
  CheckHash := HashRange(ItemBody, 65 - 63, 64);
  Check('utf-8 tail is served', ServeMonitorRead('/v4/items/item-turn-utf',
    '/v4/items/item-turn-utf?from=65&check=' + CheckHash, '', Status, ETag, Body) And (Status = 200));
  StartAt := JsonInt(Body, 'start');
  Check('offset inside a character moves back', StartAt = 64);
  Check('text starts on the character', JsonField(Body, 'text') = #$C3#$A9 + 'z');
End;

Procedure TestLiveThenStored;
Var
  Source: TFakeSource;
  Body, ETag: String;
  Status: Integer;
  Root: String;
Begin
  Root := MakeRoot;
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.identity.json',
    '{"id":"33333333-3333-3333-3333-333333333333"}');
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.jsonl',
    TurnLine('turn-same', 'stored-body') + LineEnding);
  Source := TFakeSource.Create;
  Source.Live := True;
  Source.LiveId := 'turn-same';
  Source.ItemId := 'item-live';
  Source.ItemBody := 'live-body';
  StartMonitorSnapshot(Source);
  TouchAssistantMirror;
  Pump;
  Check('live turn is served', ServeMonitorRead('/v4/turns/turn-same', '/v4/turns/turn-same?bodies=1', '', Status, ETag, Body) And
    (Status = 200));
  Check('live body comes from the snapshot', Pos('live-body', Body) > 0);
  Check('live turn keeps its id', Pos('turn-same', Body) > 0);
  Source.Live := False;
  TouchAssistantMirror;
  Pump;
  Check('stored turn is served', ServeMonitorRead('/v4/turns/turn-same', '/v4/turns/turn-same?bodies=1', '', Status, ETag, Body) And
    (Status = 200));
  Check('stored body comes from the file', Pos('stored-body', Body) > 0);
  Check('stored turn keeps the same id', Pos('"id" : "turn-same"', Body) > 0);
  StopMonitorSnapshot;
End;

Procedure TestNotModified;
Var
  Root, Body, ETag, Again: String;
  Status: Integer;
Begin
  Root := MakeRoot;
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.identity.json',
    '{"id":"44444444-4444-4444-4444-444444444444"}');
  WriteText(Root + PathDelim + '.assistant' + PathDelim + 'conversation.jsonl',
    TurnLine('turn-etag', 'same') + LineEnding);
  Check('conversation turns are readable', ServeMonitorRead('/v4/conversations/44444444-4444-4444-4444-444444444444/turns',
    '/v4/conversations/44444444-4444-4444-4444-444444444444/turns', '', Status, ETag, Body) And (Status = 200) And (ETag <> ''));
  Check('unchanged conversation is not modified', ServeMonitorRead('/v4/conversations/44444444-4444-4444-4444-444444444444/turns',
    '/v4/conversations/44444444-4444-4444-4444-444444444444/turns', '"' + ETag + '"', Status, Again, Body) And (Status = 304));
  Check('not modified has an empty body', Body = '');
End;

Begin
  FailCount := 0;
  TempSerial := 0;
  TestPages;
  TestTails;
  TestLiveThenStored;
  TestNotModified;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorStoreTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
