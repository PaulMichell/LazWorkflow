Unit AssistantMonitorStore;

{ Thread-safe reader for monitor conversation files (c) 2026 Michell Computing.

  Reads conversation.jsonl and conversation-*.jsonl with a shared lock so the IDE
  can append while a phone reads. Parsed turns are cached by content etag.
  Archived conversations are read from their archive files and are not loaded
  into the form. A live turn is served from the published snapshot. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorTurnsDefaultMaxBytes = 512 * 1024;
  MonitorTurnCacheLimit = 16;

Procedure SetMonitorStoreRoot(Const Root: String);
Function MonitorAssistantDirectory: String;
Function ServeMonitorRead(Const Path, Uri, IfNoneMatch: String; Out Status: Integer; Out ETag, Body: String): Boolean;

Implementation

Uses
  Classes, SyncObjs, LazFileUtils, fpjson, jsonparser, AssistantPlanDocument, AssistantProjectPaths,
  AssistantConversation, AssistantMonitorSnapshot;

Type
  TStoredItem = Record
    Id, Kind, State: String;
    Revision: QWord;
    Body: AnsiString;
  End;

  TCachedTurn = Class
    ETag, Id, Mode, Prompt, Thinking, Response, CreatedAt, ErrorText: String;
    Items: Array Of TStoredItem;
  End;

Var
  StoreLock: TRTLCriticalSection;
  StoreRoot: String;
  TurnCache: TList;

Function HashText(Const Text: AnsiString): String;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If Text <> '' Then
    AssistantPlanHashFold(Hash, Text[1], Length(Text));
  Result := AssistantPlanHashHex(Hash);
End;

Function HashRange(Const Text: AnsiString; StartAt, Count: Integer): String;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If (Count > 0) And (StartAt >= 1) And (StartAt <= Length(Text)) Then
    AssistantPlanHashFold(Hash, Text[StartAt], Count);
  Result := AssistantPlanHashHex(Hash);
End;

Function StripQuotes(Const Value: String): String;
Begin
  Result := Trim(Value);
  If SameText(Copy(Result, 1, 2), 'W/') Then
    Delete(Result, 1, 2);
  Result := Trim(Result);
  If (Length(Result) >= 2) And (Result[1] = '"') And (Result[Length(Result)] = '"') Then
    Result := Copy(Result, 2, Length(Result) - 2);
End;

Function QueryValue(Const Uri, Name: String): String;
Var
  Query, Part, Key: String;
  At, Amp: Integer;
Begin
  Result := '';
  At := Pos('?', Uri);
  If At = 0 Then
    Exit;
  Query := Copy(Uri, At + 1, MaxInt);
  While Query <> '' Do
    Begin
      Amp := Pos('&', Query);
      If Amp = 0 Then
        Begin
          Part := Query;
          Query := '';
        End
      Else
        Begin
          Part := Copy(Query, 1, Amp - 1);
          Delete(Query, 1, Amp);
        End;
      At := Pos('=', Part);
      If At = 0 Then
        Continue;
      Key := Copy(Part, 1, At - 1);
      If SameText(Key, Name) Then
        Exit(Copy(Part, At + 1, MaxInt));
    End;
End;

Function StoreDirectory: String;
Begin
  If StoreRoot <> '' Then
    Result := IncludeTrailingPathDelimiter(StoreRoot) + AssistantStoreFolderName + PathDelim
  Else If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Result := ProjectAssistantConversation.AssistantDirectory
  Else
    Result := '';
End;

Function ReadSharedText(Const Path: String; Out Text: AnsiString): Boolean;
Var
  Stream: TFileStream;
Begin
  Result := False;
  Text := '';
  If (Path = '') Or (Not FileExistsUTF8(Path)) Or FileIsSymlink(Path) Then
    Exit;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
    Try
      SetLength(Text, Stream.Size);
      If Length(Text) > 0 Then
        Stream.ReadBuffer(Text[1], Length(Text));
      Result := True;
    Finally
      Stream.Free;
    End;
  Except
    On E: Exception Do
      Result := False;
  End;
End;

Function Utf8CharStart(Const Text: AnsiString; Offset: Integer): Integer;
Begin
  { Offset is 0-based. Walk back over UTF-8 continuation bytes. }
  Result := Offset;
  If Result < 0 Then
    Exit(0);
  If Result >= Length(Text) Then
    Exit(Length(Text));
  While (Result > 0) And ((Ord(Text[Result + 1]) And $C0) = $80) Do
    Dec(Result);
End;

Procedure SplitLines(Const Text: AnsiString; Lines: TStringList);
Var
  StartAt, Index: Integer;
  Line: String;
Begin
  Lines.Clear;
  StartAt := 1;
  For Index := 1 To Length(Text) Do
    If Text[Index] = #10 Then
      Begin
        Line := Copy(Text, StartAt, Index - StartAt);
        If (Line <> '') And (Line[Length(Line)] = #13) Then
          Delete(Line, Length(Line), 1);
        If Trim(Line) <> '' Then
          Lines.Add(Line);
        StartAt := Index + 1;
      End;
  If StartAt <= Length(Text) Then
    Begin
      Line := Copy(Text, StartAt, MaxInt);
      If (Line <> '') And (Line[Length(Line)] = #13) Then
        Delete(Line, Length(Line), 1);
      If Trim(Line) <> '' Then
        Lines.Add(Line);
    End;
End;

Function ItemStateOf(Obj: TJSONObject): String;
Begin
  Result := Obj.Get('state', '');
  If Result <> '' Then
    Exit;
  If Obj.Get('running', False) Then
    Result := 'running'
  Else If Not Obj.Get('ok', True) Then
    Result := 'failed'
  Else
    Result := 'done';
End;

Procedure ParseItems(Turn: TCachedTurn; Const TraceJson: String);
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Index, Count: Integer;
Begin
  SetLength(Turn.Items, 0);
  If Trim(TraceJson) = '' Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(TraceJson);
    If Not (Data Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Data);
    SetLength(Turn.Items, Arr.Count);
    Count := 0;
    For Index := 0 To Arr.Count - 1 Do
      If Arr.Items[Index] Is TJSONObject Then
        Begin
          Obj := TJSONObject(Arr.Items[Index]);
          Turn.Items[Count].Id := Obj.Get('id', '');
          Turn.Items[Count].Kind := Obj.Get('kind', '');
          Turn.Items[Count].State := ItemStateOf(Obj);
          Turn.Items[Count].Revision := QWord(Obj.Get('rev', 0));
          If Obj.Get('revision', 0) <> 0 Then
            Turn.Items[Count].Revision := QWord(Obj.Get('revision', 0));
          Turn.Items[Count].Body := Obj.Get('body', '');
          If Turn.Items[Count].Id <> '' Then
            Inc(Count);
        End;
    SetLength(Turn.Items, Count);
  Except
    SetLength(Turn.Items, 0);
  End;
  Data.Free;
End;

Function ParseTurn(Const Line, ETag: String): TCachedTurn;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := TCachedTurn.Create;
  Result.ETag := ETag;
  Data := Nil;
  Try
    Data := GetJSON(Line);
    If Data Is TJSONObject Then
      Begin
        Obj := TJSONObject(Data);
        Result.Id := Obj.Get('id', '');
        Result.Mode := Obj.Get('mode', '');
        Result.Prompt := Obj.Get('prompt', '');
        Result.Thinking := Obj.Get('thinking', '');
        Result.Response := Obj.Get('response', '');
        Result.CreatedAt := Obj.Get('created_at', '');
        Result.ErrorText := Obj.Get('error', '');
        If Assigned(Obj.Find('trace')) Then
          ParseItems(Result, Obj.Find('trace').AsJSON);
      End;
  Except
    Result.Id := '';
  End;
  Data.Free;
End;

Function CacheFind(Const ETag: String): TCachedTurn;
Var
  Index: Integer;
Begin
  Result := Nil;
  For Index := 0 To TurnCache.Count - 1 Do
    If TCachedTurn(TurnCache[Index]).ETag = ETag Then
      Begin
        Result := TCachedTurn(TurnCache[Index]);
        TurnCache.Move(Index, 0);
        Exit;
      End;
End;

Function CachedTurnForLine(Const Line: String): TCachedTurn;
Var
  ETag: String;
Begin
  ETag := HashText(Line);
  EnterCriticalSection(StoreLock);
  Try
    Result := CacheFind(ETag);
    If Assigned(Result) Then
      Exit;
    Result := ParseTurn(Line, ETag);
    TurnCache.Insert(0, Result);
    While TurnCache.Count > MonitorTurnCacheLimit Do
      Begin
        TCachedTurn(TurnCache[TurnCache.Count - 1]).Free;
        TurnCache.Delete(TurnCache.Count - 1);
      End;
  Finally
    LeaveCriticalSection(StoreLock);
  End;
End;

Function TurnBytes(Turn: TCachedTurn): Integer;
Var
  Index: Integer;
Begin
  Result := 0;
  For Index := 0 To High(Turn.Items) Do
    Inc(Result, Length(Turn.Items[Index].Body));
  If Result = 0 Then
    Result := Length(Turn.Prompt) + Length(Turn.Thinking) + Length(Turn.Response);
End;

Procedure AddItemJson(Arr: TJSONArray; Const Item: TStoredItem; WithBody: Boolean);
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Obj.Add('id', Item.Id);
  Obj.Add('kind', Item.Kind);
  Obj.Add('state', Item.State);
  Obj.Add('rev', Item.Revision);
  Obj.Add('bytes', Length(Item.Body));
  If WithBody Then
    Obj.Add('body', String(Item.Body));
  Arr.Add(Obj);
End;

Function TurnJson(Turn: TCachedTurn; WithBodies: Boolean): TJSONObject;
Var
  Items: TJSONArray;
  Index: Integer;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Turn.Id);
  Result.Add('etag', Turn.ETag);
  Result.Add('live', False);
  Result.Add('mode', Turn.Mode);
  Result.Add('prompt', Turn.Prompt);
  Result.Add('created_at', Turn.CreatedAt);
  Result.Add('error', Turn.ErrorText);
  Items := TJSONArray.Create;
  For Index := 0 To High(Turn.Items) Do
    AddItemJson(Items, Turn.Items[Index], WithBodies);
  Result.Add('items', Items);
End;

Function ArchiveStamp(Const FileName: String): String;
Begin
  Result := '';
  If Not SameText(Copy(FileName, 1, Length('conversation-')), 'conversation-') Then
    Exit;
  If Not SameText(Copy(FileName, Length(FileName) - 5, 6), '.jsonl') Then
    Exit;
  If SameText(Copy(FileName, Length(FileName) - 11, 12), '.index.jsonl') Then
    Exit;
  Result := Copy(FileName, Length('conversation-') + 1, Length(FileName) - Length('conversation-') - Length('.jsonl'));
  If Pos('.', Result) > 0 Then
    Result := '';
End;

Procedure ListConversationFiles(Files: TStringList);
Var
  Dir, Stamp: String;
  Info: TSearchRec;
Begin
  Files.Clear;
  Dir := StoreDirectory;
  If (Dir = '') Or (Not DirectoryExistsUTF8(Dir)) Then
    Exit;
  If FileExistsUTF8(Dir + 'conversation.jsonl') And (Not FileIsSymlink(Dir + 'conversation.jsonl')) Then
    Files.Add('conversation.jsonl');
  If FindFirstUTF8(Dir + 'conversation-*.jsonl', faAnyFile, Info) = 0 Then
    Begin
      Try
        Repeat
          Stamp := ArchiveStamp(Info.Name);
          If (Stamp <> '') And (Not FileIsSymlink(Dir + Info.Name)) Then
            Files.Add(Info.Name);
        Until FindNextUTF8(Info) <> 0;
      Finally
        FindCloseUTF8(Info);
      End;
    End;
End;

Function IdentityFor(Const Dir, JsonlName: String): String;
Var
  Stamp: String;
Begin
  If SameText(JsonlName, 'conversation.jsonl') Then
    Result := Dir + 'conversation.identity.json'
  Else
    Begin
      Stamp := ArchiveStamp(JsonlName);
      Result := Dir + 'conversation-' + Stamp + '.identity.json';
    End;
End;

Function ReadIdentityId(Const Path: String): String;
Var
  Text: AnsiString;
  Data: TJSONData;
Begin
  Result := '';
  If Not ReadSharedText(Path, Text) Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(Text);
    If Data Is TJSONObject Then
      Result := LowerCase(Trim(TJSONObject(Data).Get('id', '')));
  Except
    Result := '';
  End;
  Data.Free;
  If Not MonitorConversationIdIsValid(Result) Then
    Result := '';
End;

Function FindConversationFile(Const ConversationId: String; Out JsonlPath, ETag: String): Boolean;
Var
  Dir: String;
  Names: TStringList;
  Index: Integer;
  Text: AnsiString;
Begin
  Result := False;
  JsonlPath := '';
  ETag := '';
  Dir := StoreDirectory;
  Names := TStringList.Create;
  Try
    ListConversationFiles(Names);
    For Index := 0 To Names.Count - 1 Do
      If SameText(ReadIdentityId(IdentityFor(Dir, Names[Index])), ConversationId) Then
        Begin
          JsonlPath := Dir + Names[Index];
          If ReadSharedText(JsonlPath, Text) Then
            ETag := HashText(Text);
          Result := True;
          Exit;
        End;
  Finally
    Names.Free;
  End;
End;

Function LoadTurns(Const JsonlPath: String; Lines: TStringList): String;
Var
  Text: AnsiString;
Begin
  Result := '';
  If Not ReadSharedText(JsonlPath, Text) Then
    Exit;
  Result := HashText(Text);
  SplitLines(Text, Lines);
End;

Function ServeConversations(Const IfNoneMatch: String; Out Status: Integer; Out ETag, Body: String): Boolean;
Var
  Dir: String;
  Names: TStringList;
  Index: Integer;
  Lines: TStringList;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Data: TJSONData;
  Text: AnsiString;
  Id, Title, Created, Joined: String;
Begin
  Result := True;
  Dir := StoreDirectory;
  Names := TStringList.Create;
  Lines := TStringList.Create;
  Arr := TJSONArray.Create;
  Try
    ListConversationFiles(Names);
    Joined := '';
    For Index := 0 To Names.Count - 1 Do
      Begin
        Id := ReadIdentityId(IdentityFor(Dir, Names[Index]));
        If Id = '' Then
          Continue;
        If Not ReadSharedText(Dir + Names[Index], Text) Then
          Continue;
        Joined := Joined + HashText(Text) + #10;
      End;
    ETag := HashText(Joined);
    If (IfNoneMatch <> '') And SameText(StripQuotes(IfNoneMatch), ETag) Then
      Begin
        Status := 304;
        Body := '';
        Exit;
      End;
    For Index := 0 To Names.Count - 1 Do
      Begin
        Id := ReadIdentityId(IdentityFor(Dir, Names[Index]));
        If Id = '' Then
          Continue;
        If Not ReadSharedText(Dir + Names[Index], Text) Then
          Continue;
        SplitLines(Text, Lines);
        Title := '';
        Created := '';
        If Lines.Count > 0 Then
          Begin
            Data := GetJSON(Lines[0]);
            Try
              If Data Is TJSONObject Then
                Begin
                  Title := TJSONObject(Data).Get('prompt', '');
                  Created := TJSONObject(Data).Get('created_at', '');
                End;
            Finally
              Data.Free;
            End;
          End;
        Obj := TJSONObject.Create;
        Obj.Add('id', Id);
        Obj.Add('title', Title);
        Obj.Add('created_at', Created);
        Obj.Add('turn_count', Lines.Count);
        Obj.Add('etag', HashText(Text));
        Obj.Add('current', SameText(Names[Index], 'conversation.jsonl'));
        Arr.Add(Obj);
      End;
    Status := 200;
    Body := Arr.AsJSON;
  Finally
    Arr.Free;
    Lines.Free;
    Names.Free;
  End;
End;

Function ServeTurns(Const ConversationId: String; FromIndex, MaxBytes: Integer; Const IfNoneMatch: String;
  Out Status: Integer; Out ETag, Body: String): Boolean;
Var
  JsonlPath: String;
  Lines: TStringList;
  Root: TJSONObject;
  Turns: TJSONArray;
  Cached: TCachedTurn;
  Index, Used, Limit: Integer;
  NextIndex: Integer;
Begin
  Result := True;
  If Not FindConversationFile(ConversationId, JsonlPath, ETag) Then
    Begin
      Status := 404;
      Body := '{"reason":"not_found","message":"That conversation is not on this host."}';
      Exit;
    End;
  If (IfNoneMatch <> '') And SameText(StripQuotes(IfNoneMatch), ETag) Then
    Begin
      Status := 304;
      Body := '';
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    LoadTurns(JsonlPath, Lines);
    Limit := MaxBytes;
    If Limit <= 0 Then
      Limit := MonitorTurnsDefaultMaxBytes;
    If FromIndex < 0 Then
      FromIndex := 0;
    Used := 0;
    NextIndex := Lines.Count;
    Root := TJSONObject.Create;
    Turns := TJSONArray.Create;
    Try
      Root.Add('id', ConversationId);
      Root.Add('etag', ETag);
      Root.Add('from', FromIndex);
      For Index := FromIndex To Lines.Count - 1 Do
        Begin
          Cached := CachedTurnForLine(Lines[Index]);
          If (Turns.Count > 0) And (Used + TurnBytes(Cached) > Limit) Then
            Begin
              NextIndex := Index;
              Break;
            End;
          Inc(Used, TurnBytes(Cached));
          Turns.Add(TurnJson(Cached, True));
          NextIndex := Index + 1;
        End;
      Root.Add('turns', Turns);
      If NextIndex >= Lines.Count Then
        Root.Add('next', TJSONNull.Create)
      Else
        Root.Add('next', NextIndex);
      Status := 200;
      Body := Root.AsJSON;
    Finally
      Root.Free;
    End;
  Finally
    Lines.Free;
  End;
End;

Function FindStoredTurn(Const TurnId: String; Out Line, ETag: String): Boolean;
Var
  Dir: String;
  Names, Lines: TStringList;
  FileIndex, LineIndex: Integer;
  Text: AnsiString;
  Cached: TCachedTurn;
Begin
  Result := False;
  Line := '';
  ETag := '';
  Dir := StoreDirectory;
  Names := TStringList.Create;
  Lines := TStringList.Create;
  Try
    ListConversationFiles(Names);
    For FileIndex := 0 To Names.Count - 1 Do
      Begin
        If Not ReadSharedText(Dir + Names[FileIndex], Text) Then
          Continue;
        SplitLines(Text, Lines);
        For LineIndex := 0 To Lines.Count - 1 Do
          Begin
            Cached := CachedTurnForLine(Lines[LineIndex]);
            If Cached.Id = TurnId Then
              Begin
                Line := Lines[LineIndex];
                ETag := Cached.ETag;
                Result := True;
                Exit;
              End;
          End;
      End;
  Finally
    Lines.Free;
    Names.Free;
  End;
End;

Function LiveTurnJson(Const TurnId: String; WithBodies: Boolean; Out Found: Boolean): TJSONObject;
Var
  Snap: TMonitorSnapshot;
  Items: TJSONArray;
  Item: TStoredItem;
  Index: Integer;
Begin
  Result := Nil;
  Found := False;
  Snap := PublishedMonitorSnapshot;
  If Not Assigned(Snap) Then
    Exit;
  Try
    If Not (Snap.HasLive And (Snap.LiveTurnId = TurnId)) Then
      Exit;
    Found := True;
    Result := TJSONObject.Create;
    Result.Add('id', String(Snap.LiveTurnId));
    Result.Add('live', True);
    Result.Add('mode', String(Snap.Mode));
    Items := TJSONArray.Create;
    For Index := 0 To High(Snap.Items) Do
      Begin
        Item.Id := Snap.Items[Index].Id;
        Item.Kind := Snap.Items[Index].Kind;
        Item.State := Snap.Items[Index].State;
        Item.Revision := Snap.Items[Index].Revision;
        Item.Body := Snap.Items[Index].Body;
        AddItemJson(Items, Item, WithBodies);
      End;
    Result.Add('items', Items);
  Finally
    Snap.Release;
  End;
End;

Function ServeOneTurn(Const TurnId: String; WithBodies: Boolean; Const IfNoneMatch: String;
  Out Status: Integer; Out ETag, Body: String): Boolean;
Var
  Line: String;
  Live, Obj: TJSONObject;
  Found: Boolean;
Begin
  Result := True;
  Live := LiveTurnJson(TurnId, WithBodies, Found);
  If Found Then
    Begin
      ETag := '';
      Status := 200;
      Body := Live.AsJSON;
      Live.Free;
      Exit;
    End;
  If Not FindStoredTurn(TurnId, Line, ETag) Then
    Begin
      Status := 404;
      Body := '{"reason":"not_found","message":"That turn is not in this conversation."}';
      Exit;
    End;
  If (IfNoneMatch <> '') And SameText(StripQuotes(IfNoneMatch), ETag) Then
    Begin
      Status := 304;
      Body := '';
      Exit;
    End;
  Obj := TurnJson(CachedTurnForLine(Line), WithBodies);
  Try
    Status := 200;
    Body := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function FindItem(Const ItemId: String; Out Item: TStoredItem; Out Found: Boolean): Boolean;
Var
  Snap: TMonitorSnapshot;
  Dir: String;
  Names, Lines: TStringList;
  FileIndex, LineIndex, ItemIndex: Integer;
  Text: AnsiString;
  Cached: TCachedTurn;
Begin
  Result := True;
  Found := False;
  Item := Default(TStoredItem);
  Snap := PublishedMonitorSnapshot;
  If Assigned(Snap) Then
    Begin
      Try
        If Snap.HasLive Then
          For ItemIndex := 0 To High(Snap.Items) Do
            If Snap.Items[ItemIndex].Id = ItemId Then
              Begin
                Item.Id := Snap.Items[ItemIndex].Id;
                Item.Kind := Snap.Items[ItemIndex].Kind;
                Item.State := Snap.Items[ItemIndex].State;
                Item.Revision := Snap.Items[ItemIndex].Revision;
                Item.Body := Snap.Items[ItemIndex].Body;
                Found := True;
                Exit;
              End;
      Finally
        Snap.Release;
      End;
    End;
  Dir := StoreDirectory;
  Names := TStringList.Create;
  Lines := TStringList.Create;
  Try
    ListConversationFiles(Names);
    For FileIndex := 0 To Names.Count - 1 Do
      Begin
        If Not ReadSharedText(Dir + Names[FileIndex], Text) Then
          Continue;
        SplitLines(Text, Lines);
        For LineIndex := 0 To Lines.Count - 1 Do
          Begin
            Cached := CachedTurnForLine(Lines[LineIndex]);
            For ItemIndex := 0 To High(Cached.Items) Do
              If Cached.Items[ItemIndex].Id = ItemId Then
                Begin
                  Item := Cached.Items[ItemIndex];
                  Found := True;
                  Exit;
                End;
          End;
      End;
  Finally
    Lines.Free;
    Names.Free;
  End;
End;

Function ServeItem(Const ItemId: String; FromByte: Integer; Const CheckHash: String;
  Out Status: Integer; Out ETag, Body: String): Boolean;
Var
  Item: TStoredItem;
  Found, Tail: Boolean;
  StartAt, CheckAt: Integer;
  Obj: TJSONObject;
  Text: AnsiString;
Begin
  Result := True;
  ETag := '';
  If Not FindItem(ItemId, Item, Found) Or (Not Found) Then
    Begin
      Status := 404;
      Body := '{"reason":"not_found","message":"That item is not in this conversation."}';
      Exit;
    End;
  Tail := False;
  StartAt := 0;
  If (FromByte > 0) And (FromByte <= Length(Item.Body)) And (FromByte >= 64) And (CheckHash <> '') Then
    Begin
      CheckAt := FromByte - 63;
      Tail := SameText(HashRange(Item.Body, CheckAt, 64), CheckHash);
      If Tail Then
        StartAt := Utf8CharStart(Item.Body, FromByte);
    End;
  If Tail Then
    Text := Copy(Item.Body, StartAt + 1, MaxInt)
  Else
    Begin
      StartAt := 0;
      Text := Item.Body;
    End;
  Obj := TJSONObject.Create;
  Try
    Obj.Add('id', Item.Id);
    Obj.Add('rev', Item.Revision);
    Obj.Add('state', Item.State);
    Obj.Add('total_bytes', Length(Item.Body));
    Obj.Add('start', StartAt);
    Obj.Add('text', String(Text));
    Status := 200;
    Body := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function PathId(Const Path, Prefix, Suffix: String): String;
Begin
  Result := '';
  If Not SameText(Copy(Path, 1, Length(Prefix)), Prefix) Then
    Exit;
  If (Suffix <> '') And (Not SameText(Copy(Path, Length(Path) - Length(Suffix) + 1, Length(Suffix)), Suffix)) Then
    Exit;
  If Suffix = '' Then
    Result := Copy(Path, Length(Prefix) + 1, MaxInt)
  Else
    Result := Copy(Path, Length(Prefix) + 1, Length(Path) - Length(Prefix) - Length(Suffix));
End;

Function ServeMonitorRead(Const Path, Uri, IfNoneMatch: String; Out Status: Integer; Out ETag, Body: String): Boolean;
Var
  Id: String;
  FromIndex, MaxBytes, FromByte: Integer;
  Bodies: Boolean;
Begin
  Status := 404;
  ETag := '';
  Body := '';
  If SameText(Path, '/v4/conversations') Then
    Exit(ServeConversations(IfNoneMatch, Status, ETag, Body));
  Id := PathId(Path, '/v4/conversations/', '/turns');
  If Id <> '' Then
    Begin
      FromIndex := StrToIntDef(QueryValue(Uri, 'from'), 0);
      MaxBytes := StrToIntDef(QueryValue(Uri, 'max_bytes'), MonitorTurnsDefaultMaxBytes);
      Exit(ServeTurns(Id, FromIndex, MaxBytes, IfNoneMatch, Status, ETag, Body));
    End;
  Id := PathId(Path, '/v4/turns/', '');
  If (Id <> '') And (Pos('/', Id) = 0) Then
    Begin
      Bodies := QueryValue(Uri, 'bodies') <> '0';
      Exit(ServeOneTurn(Id, Bodies, IfNoneMatch, Status, ETag, Body));
    End;
  Id := PathId(Path, '/v4/items/', '');
  If (Id <> '') And (Pos('/', Id) = 0) Then
    Begin
      FromByte := StrToIntDef(QueryValue(Uri, 'from'), 0);
      Exit(ServeItem(Id, FromByte, QueryValue(Uri, 'check'), Status, ETag, Body));
    End;
  Result := False;
End;

Function MonitorAssistantDirectory: String;
Begin
  Result := StoreDirectory;
End;

Procedure SetMonitorStoreRoot(Const Root: String);
Begin
  EnterCriticalSection(StoreLock);
  Try
    StoreRoot := ExcludeTrailingPathDelimiter(Root);
  Finally
    LeaveCriticalSection(StoreLock);
  End;
End;

Procedure ClearCache;
Var
  Index: Integer;
Begin
  For Index := 0 To TurnCache.Count - 1 Do
    TCachedTurn(TurnCache[Index]).Free;
  TurnCache.Clear;
End;

Initialization

  InitCriticalSection(StoreLock);
  TurnCache := TList.Create;

Finalization

  ClearCache;
  TurnCache.Free;
  DoneCriticalSection(StoreLock);

End.
