Program AssistantConversationIdentityTest;

{ A conversation id is a GUID, including a new unsaved chat, and it stays with the archive.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, FileUtil, LazFileUtils, fpjson, jsonparser, AssistantConversation;

Var
  FailCount: Integer;
  TempSerial: Integer;

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

Function MakeTempRoot: String;
Begin
  Inc(TempSerial);
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-conversation-id-' +
    FormatDateTime('hhnnsszzz', Now) + '-' + IntToStr(TempSerial);
  ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(Result));
End;

Function ReadIdentity(Const Path: String; Out Id, Epoch: String; Out Cursor: Int64): Boolean;
Var
  Lines: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
Begin
  Result := False;
  Id := '';
  Epoch := '';
  Cursor := 0;
  If Not FileExistsUTF8(Path) Then
    Exit;
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Try
      Lines.LoadFromFile(Path);
      Data := GetJSON(Lines.Text);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Id := Obj.Get('id', '');
      Epoch := Obj.Get('epoch', '');
      Node := Obj.Find('cursor');
      If Assigned(Node) And (Node.JSONType = jtNumber) Then
        Cursor := Node.AsInt64;
      Result := True;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
    Lines.Free;
  End;
End;

Function AppendSample(Store: TAssistantConversationStore; Const Prompt: String): Boolean;
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
Begin
  Turn := Default(TConversationTurn);
  Turn.Id := 'turn-1';
  Turn.Mode := 'build';
  Turn.Prompt := Prompt;
  Turn.Response := 'answer';
  Turn.CreatedAt := '2026-01-01T00:00:00Z';
  Result := Store.AppendTurn(Turn, Entry);
End;

Procedure TestNewConversationHasAStableId;
Var
  Root, FirstId, SecondId, Epoch: String;
  Cursor: Int64;
  Store, Reloaded: TAssistantConversationStore;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    FirstId := Store.MonitorConversationId;
    Check('unsaved id is a guid', MonitorConversationIdIsValid(FirstId));
    Check('unsaved id is not current', FirstId <> 'current');
    Check('open id matches', Store.OpenConversationId = FirstId);
    Check('identity file exists', FileExistsUTF8(Store.AssistantDirectory + 'conversation.identity.json'));
    Check('asking again keeps the id', Store.MonitorConversationId = FirstId);
    Store.NoteMonitorLogPosition('ab12cd34', 7);
    Store.ReadMonitorLogPosition(Epoch, Cursor);
    Check('log position remembered', (Epoch = 'ab12cd34') And (Cursor = 7));
  Finally
    Store.Free;
  End;
  Reloaded := TAssistantConversationStore.Create;
  Try
    Reloaded.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    SecondId := Reloaded.MonitorConversationId;
    Check('reload keeps the id', SecondId = FirstId);
    Reloaded.ReadMonitorLogPosition(Epoch, Cursor);
    Check('reload keeps the log position', (Epoch = 'ab12cd34') And (Cursor = 7));
  Finally
    Reloaded.Free;
  End;
End;

Procedure TestArchiveKeepsTheId;
Var
  Root, OpenId, ArchivedId, NewId, Epoch: String;
  Cursor: Int64;
  Store: TAssistantConversationStore;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    SetNextArchiveIdForTest('20200101T000000001');
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('turn appended', AppendSample(Store, 'keep this chat'));
    OpenId := Store.MonitorConversationId;
    Store.NoteMonitorLogPosition('epoch-one', 4);
    Check('start new', Store.StartNewConversation);
    NewId := Store.MonitorConversationId;
    Check('new chat has its own id', MonitorConversationIdIsValid(NewId) And (NewId <> OpenId));
    Check('new chat is not current', NewId <> 'current');
    Check('archive identity file exists',
      FileExistsUTF8(Store.AssistantDirectory + 'conversation-20200101T000000001.identity.json'));
    If Not ReadIdentity(Store.AssistantDirectory + 'conversation-20200101T000000001.identity.json',
      ArchivedId, Epoch, Cursor) Then
      Begin
        Check('archived identity readable', False);
        Exit;
      End;
    Check('archive kept the id', ArchivedId = OpenId);
    Check('archive kept the log position', (Epoch = 'epoch-one') And (Cursor = 4));
    Check('activate archive', Store.ActivateArchive('20200101T000000001'));
    Check('activated id is the archived one', Store.MonitorConversationId = OpenId);
    Store.ReadMonitorLogPosition(Epoch, Cursor);
    Check('activated log position restored', (Epoch = 'epoch-one') And (Cursor = 4));
  Finally
    Store.Free;
    SetNextArchiveIdForTest('');
  End;
End;

Begin
  FailCount := 0;
  TestNewConversationHasAStableId;
  TestArchiveKeepsTheId;
  If FailCount = 0 Then
    WriteLn('AssistantConversationIdentityTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failure(s)');
      Halt(1);
    End;
End.
