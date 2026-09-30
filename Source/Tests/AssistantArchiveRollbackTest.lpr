Program AssistantArchiveRollbackTest;

{ Index rename failures must roll the conversation files back. Does not depend on the clock.
  A directory at the destination makes RenameFile fail on Linux, where an existing file would be replaced.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, FileUtil, LazFileUtils, AssistantConversation;

Const
  ForcedParkId = '20200101T000000001';
  SampleArchiveId = '20200101T000000002';
  CurrentPrompt = 'current prompt stays';
  ArchivePrompt = 'archived prompt stays';

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
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-archive-rollback-' + FormatDateTime('hhnnsszzz', Now) + '-' + IntToStr(TempSerial);
  ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(Result));
End;

Function FileText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExistsUTF8(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure WriteUtf8File(Const Path, Body: String);
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Text := Body;
    Lines.SaveToFile(Path);
  Finally
    Lines.Free;
  End;
End;

Function ArchiveConvPath(Const StoreDir, ArchiveId: String): String;
Begin
  Result := StoreDir + 'conversation-' + ArchiveId + '.jsonl';
End;

Function ArchiveIdxPath(Const StoreDir, ArchiveId: String): String;
Begin
  Result := StoreDir + 'conversation-' + ArchiveId + '.index.jsonl';
End;

Function CountArchiveConversations(Const StoreDir: String): Integer;
Var
  Rec: TSearchRec;
  Code: Integer;
Begin
  Result := 0;
  Code := FindFirstUTF8(StoreDir + 'conversation-*.jsonl', faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        If (Pos('.index.', LowerCase(Rec.Name)) = 0) And ((Rec.Attr And faDirectory) = 0) Then
          Inc(Result);
        Code := FindNextUTF8(Rec);
      End;
  Finally
    FindCloseUTF8(Rec);
  End;
End;

Procedure PlantIndexDirectory(Const Path: String);
Begin
  ForceDirectoriesUTF8(Path);
  Check('index destination is a directory', DirectoryExistsUTF8(Path) And (Not FileExistsUTF8(Path)));
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

Procedure WriteSampleArchive(Const StoreDir, ArchiveId, Prompt: String);
Begin
  WriteUtf8File(ArchiveConvPath(StoreDir, ArchiveId),
    '{"id":"archived-turn","mode":"inspect","prompt":"' + Prompt + '","response":"archived answer"}');
  WriteUtf8File(ArchiveIdxPath(StoreDir, ArchiveId),
    '{"id":"archived-turn","prompt_preview":"' + Prompt + '"}');
End;

Procedure TestArchiveIndexRollsBack;
Var
  Root, StoreDir, ConvPath, IdxPath, ConvBefore: String;
  Store: TAssistantConversationStore;
  ArchiveId: String;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    SetNextArchiveIdForTest('');
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('archive fixture appended', AppendSample(Store, CurrentPrompt));
    If Not Store.Load Then
      Begin
        Check('archive fixture loaded', False);
        Exit;
      End;
    StoreDir := Store.AssistantDirectory;
    ConvPath := StoreDir + 'conversation.jsonl';
    IdxPath := StoreDir + 'conversation.index.jsonl';
    ConvBefore := FileText(ConvPath);
    SetNextArchiveIdForTest(ForcedParkId);
    PlantIndexDirectory(ArchiveIdxPath(StoreDir, ForcedParkId));
    ArchiveId := 'unset';
    Check('archive returns false', Not Store.ArchiveCurrent(ArchiveId));
    Check('archive id cleared', ArchiveId = '');
    Check('archive error names the index', Pos('conversation.index.jsonl', Store.LastError) > 0);
    Check('current conversation unchanged', FileText(ConvPath) = ConvBefore);
    Check('current index still in place', FileExistsUTF8(IdxPath) And (Pos(CurrentPrompt, FileText(IdxPath)) > 0));
    Check('archive conversation was rolled back', Not FileExistsUTF8(ArchiveConvPath(StoreDir, ForcedParkId)));
    Check('archive index destination was not replaced', DirectoryExistsUTF8(ArchiveIdxPath(StoreDir, ForcedParkId)));
    Check('no archived conversation file left', CountArchiveConversations(StoreDir) = 0);
    SetNextArchiveIdForTest(ForcedParkId);
    Check('start new refuses the failed archive', Not Store.StartNewConversation);
    Check('start new left the conversation', FileText(ConvPath) = ConvBefore);
    Check('start new left the index', FileExistsUTF8(IdxPath) And (Pos(CurrentPrompt, FileText(IdxPath)) > 0));
  Finally
    SetNextArchiveIdForTest('');
    Store.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestActivateParkIndexRollsBack;
Var
  Root, StoreDir, ConvPath, IdxPath, ConvBefore, ArchConvBefore, ArchIdxBefore: String;
  Store: TAssistantConversationStore;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    SetNextArchiveIdForTest('');
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('park fixture appended', AppendSample(Store, CurrentPrompt));
    If Not Store.Load Then
      Begin
        Check('park fixture loaded', False);
        Exit;
      End;
    StoreDir := Store.AssistantDirectory;
    ConvPath := StoreDir + 'conversation.jsonl';
    IdxPath := StoreDir + 'conversation.index.jsonl';
    WriteSampleArchive(StoreDir, SampleArchiveId, ArchivePrompt);
    ConvBefore := FileText(ConvPath);
    ArchConvBefore := FileText(ArchiveConvPath(StoreDir, SampleArchiveId));
    ArchIdxBefore := FileText(ArchiveIdxPath(StoreDir, SampleArchiveId));
    SetNextArchiveIdForTest(ForcedParkId);
    PlantIndexDirectory(ArchiveIdxPath(StoreDir, ForcedParkId));
    Check('activate park returns false', Not Store.ActivateArchive(SampleArchiveId));
    Check('activate park error names the index', Pos('park current index', Store.LastError) > 0);
    Check('park left the current conversation', FileText(ConvPath) = ConvBefore);
    Check('park left the current index', FileExistsUTF8(IdxPath) And (Pos(CurrentPrompt, FileText(IdxPath)) > 0));
    Check('park left the archive conversation', FileText(ArchiveConvPath(StoreDir, SampleArchiveId)) = ArchConvBefore);
    Check('park left the archive index', FileText(ArchiveIdxPath(StoreDir, SampleArchiveId)) = ArchIdxBefore);
    Check('park conversation was restored', Not FileExistsUTF8(ArchiveConvPath(StoreDir, ForcedParkId)));
    Check('only the original archive conversation remains', CountArchiveConversations(StoreDir) = 1);
  Finally
    SetNextArchiveIdForTest('');
    Store.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestActivateArchiveIndexRollsBack;
Var
  Root, StoreDir, ConvPath, IdxPath, ConvBefore, ArchConvBefore, ArchIdxBefore: String;
  Store: TAssistantConversationStore;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    SetNextArchiveIdForTest('');
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('activate fixture appended', AppendSample(Store, CurrentPrompt));
    StoreDir := Store.AssistantDirectory;
    ConvPath := StoreDir + 'conversation.jsonl';
    IdxPath := StoreDir + 'conversation.index.jsonl';
    ConvBefore := FileText(ConvPath);
    If Not DeleteFileUTF8(IdxPath) Then
      Begin
        Check('current index removed so the path can block the archive index', False);
        Exit;
      End;
    PlantIndexDirectory(IdxPath);
    WriteSampleArchive(StoreDir, SampleArchiveId, ArchivePrompt);
    ArchConvBefore := FileText(ArchiveConvPath(StoreDir, SampleArchiveId));
    ArchIdxBefore := FileText(ArchiveIdxPath(StoreDir, SampleArchiveId));
    Check('activate index move returns false', Not Store.ActivateArchive(SampleArchiveId));
    Check('activate index error names the archive', Pos(SampleArchiveId, Store.LastError) > 0);
    Check('activate restored the current conversation', FileText(ConvPath) = ConvBefore);
    Check('current index path still blocks the move', DirectoryExistsUTF8(IdxPath) And (Not FileExistsUTF8(IdxPath)));
    Check('activate restored the archive conversation', FileText(ArchiveConvPath(StoreDir, SampleArchiveId)) = ArchConvBefore);
    Check('activate left the archive index', FileText(ArchiveIdxPath(StoreDir, SampleArchiveId)) = ArchIdxBefore);
    Check('no parked conversation left behind', CountArchiveConversations(StoreDir) = 1);
  Finally
    SetNextArchiveIdForTest('');
    Store.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Begin
  FailCount := 0;
  TempSerial := 0;
  TestArchiveIndexRollsBack;
  TestActivateParkIndexRollsBack;
  TestActivateArchiveIndexRollsBack;
  WriteLn(FailCount, ' failure(s).');
  If FailCount <> 0 Then
    Halt(1);
End.
