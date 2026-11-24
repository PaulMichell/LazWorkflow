Unit GitHistoryIndex;

{ Background commit-graph index for Manage Repository (c) 2026 Michell Computing.

  A full rev-list of a large repository takes long enough that waiting for it
  before painting locks the window on "Indexing commit history…". This unit
  shows the newest commits first, parses and lays out the rest off the UI
  thread, and reuses a refs-keyed cache when the graph has not changed.
  The shared Git job queue is left free for Changes and Files. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, GitGraphModel;

Type
  TGitHistoryPhase = (hipHead, hipFull, hipFailed);

  { Model is owned by the callee when the function returns True. Nil is not adopted. }
  TGitHistoryAdopt = Function(Sender: TObject; Generation: Integer; Phase: TGitHistoryPhase;
    Model: TGitGraphModel): Boolean Of Object;

  TGitHistoryIndex = Class
  Private
    FLock: TRTLCriticalSection;
    FThread: TThread;
    FGit: TObject;
    FPendingModel: TGitGraphModel;
    FPendingPhase: TGitHistoryPhase;
    FPendingFailed: Boolean;
    FPendingGeneration: Integer;
    FGeneration: Integer;
    FRepoPath: String;
    FStopFlag: LongInt;
    FOnAdopt: TGitHistoryAdopt;
    Function Stopping: Boolean;
    Procedure Publish(Phase: TGitHistoryPhase; Model: TGitGraphModel);
    Procedure Deliver;
    Function TryShowCacheHead(Out CachedKey: String): Boolean;
    Function PublishCachedFull(Const LiveKey: String): Boolean;
    Procedure IndexFromGit(Const LiveKey: String; StaleShown: Boolean);
    Procedure Run;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Cancels any walk already in progress, then starts one for RepoPath. }
    Procedure Start(Const RepoPath: String; Generation: Integer);
    Procedure Stop;
    Property OnAdopt: TGitHistoryAdopt Read FOnAdopt Write FOnAdopt;
  End;

Implementation

Uses
  sha1, LazFileUtils, SafeFileAccess, WorkflowLog, WorkflowSettings, GitService;

Const
  HistoryCacheMagic = 'LWHI1';
  HistoryCacheMaxBytes = 64 * 1024 * 1024;
  HistoryCacheHeadBytes = 256 * 1024;

Type
  TGitHistoryWorker = Class(TThread)
  Private
    FIndex: TGitHistoryIndex;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Index: TGitHistoryIndex);
  End;

Function HistoryIdentityKey(Const Identity: String): String;
Begin
  Result := SHA1Print(SHA1String(Identity));
End;

Function HistoryCacheDirectory: String;
Begin
  Result := '';
  If WorkflowSettingsDirectory = '' Then
    Exit;
  Result := IncludeTrailingPathDelimiter(WorkflowSettingsDirectory) + 'repository-history';
End;

Function HistoryCacheFile(Const RepoPath: String): String;
Begin
  Result := '';
  If (RepoPath = '') Or (HistoryCacheDirectory = '') Then
    Exit;
  Result := IncludeTrailingPathDelimiter(HistoryCacheDirectory) + HistoryIdentityKey(RepoPath) + '.index';
End;

Function ReadCacheText(Const Path: String; MaxBytes: Integer; AllowPrefix: Boolean; Out Text: String): Boolean;
Var
  Stream: TFileStream;
  Size: Int64;
  Count: LongInt;
Begin
  Result := False;
  Text := '';
  If (Path = '') Or (MaxBytes < 1) Or FileIsSymlink(Path) Or Not FileExistsUTF8(Path) Then
    Exit;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Size := Stream.Size;
    If (Not AllowPrefix) And (Size > MaxBytes) Then
      Exit;
    If Size > MaxBytes Then
      Count := MaxBytes
    Else
      Count := Size;
    SetLength(Text, Count);
    If Count > 0 Then
      Stream.ReadBuffer(Text[1], Count);
    Result := True;
  Finally
    Stream.Free;
  End;
End;

Function CacheHeader(Const Text: String; Out RepoPath, Identity, Body: String): Boolean;
Var
  Cursor, L: Integer;

  Function TakeLine: String;
  Var
    Start: Integer;
  Begin
    Start := Cursor;
    While (Cursor <= L) And (Text[Cursor] <> #10) And (Text[Cursor] <> #13) Do
      Inc(Cursor);
    Result := Copy(Text, Start, Cursor - Start);
    If (Cursor <= L) And (Text[Cursor] = #13) Then
      Inc(Cursor);
    If (Cursor <= L) And (Text[Cursor] = #10) Then
      Inc(Cursor);
  End;

Begin
  Result := False;
  RepoPath := '';
  Identity := '';
  Body := '';
  L := Length(Text);
  Cursor := 1;
  If TakeLine <> HistoryCacheMagic Then
    Exit;
  RepoPath := TakeLine;
  Identity := TakeLine;
  If TakeLine <> '' Then
    Exit;
  If (RepoPath = '') Or (Pos(#10, RepoPath) > 0) Or (Pos(#13, RepoPath) > 0) Or (Length(Identity) <> 40) Then
    Exit;
  Body := Copy(Text, Cursor, MaxInt);
  Result := True;
End;

Function LoadHistoryCacheHead(Const RepoPath: String; MaxCommits: Integer; Out Identity, HeadText: String): Boolean;
Var
  Text, StoredPath, Body: String;
Begin
  Result := False;
  Identity := '';
  HeadText := '';
  If Not ReadCacheText(HistoryCacheFile(RepoPath), HistoryCacheHeadBytes, True, Text) Then
    Exit;
  If Not CacheHeader(Text, StoredPath, Identity, Body) Then
    Exit;
  If CompareFilenames(StoredPath, RepoPath) <> 0 Then
    Exit;
  HeadText := GitRevListHead(Body, MaxCommits);
  Result := HeadText <> '';
End;

Function LoadHistoryCache(Const RepoPath: String; Out Identity, RevListText: String): Boolean;
Var
  Text, StoredPath: String;
Begin
  Result := False;
  Identity := '';
  RevListText := '';
  If Not ReadCacheText(HistoryCacheFile(RepoPath), HistoryCacheMaxBytes, False, Text) Then
    Exit;
  If Not CacheHeader(Text, StoredPath, Identity, RevListText) Then
    Exit;
  Result := CompareFilenames(StoredPath, RepoPath) = 0;
  If Not Result Then
    RevListText := '';
End;

Function SaveHistoryCache(Const RepoPath, Identity, RevListText: String): Boolean;
Var
  Path, Temp, Header, ErrorText: String;
  Stream: TFileStream;
Begin
  Result := False;
  If (RepoPath = '') Or (Length(Identity) <> 40) Or (RevListText = '') Or (HistoryCacheDirectory = '') Then
    Exit;
  If (Pos(#10, RepoPath) > 0) Or (Pos(#13, RepoPath) > 0) Then
    Exit;
  If Not ForceDirectoriesUTF8(HistoryCacheDirectory) Then
    Exit;
  Path := HistoryCacheFile(RepoPath);
  Temp := Path + '.tmp';
  Header := HistoryCacheMagic + LineEnding + RepoPath + LineEnding + Identity + LineEnding + LineEnding;
  Stream := Nil;
  Try
    If FileExistsUTF8(Temp) Then
      DeleteFileUTF8(Temp);
    Stream := TFileStream.Create(Temp, fmCreate);
    If Header <> '' Then
      Stream.WriteBuffer(Header[1], Length(Header));
    If RevListText <> '' Then
      Stream.WriteBuffer(RevListText[1], Length(RevListText));
    FreeAndNil(Stream);
    If Not ProtectOwnerOnlyFile(Temp) Then
      Begin
        DeleteFileUTF8(Temp);
        Exit;
      End;
    If Not RenameFile(Temp, Path) Then
      Begin
        DeleteFileUTF8(Path);
        If Not RenameFile(Temp, Path) Then
          Begin
            DeleteFileUTF8(Temp);
            Exit;
          End;
      End;
    Result := True;
  Except
    On E: Exception Do
      Begin
        ErrorText := E.Message;
        WorkflowLogger.Warning('GitHistoryIndex', 'Could not store history cache: ' + ErrorText);
        FreeAndNil(Stream);
        DeleteFileUTF8(Temp);
      End;
  End;
End;

Constructor TGitHistoryWorker.Create(Index: TGitHistoryIndex);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FIndex := Index;
End;

Procedure TGitHistoryWorker.Execute;
Begin
  Try
    FIndex.Run;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('GitHistoryIndex', E.Message);
        FIndex.Publish(hipFailed, Nil);
      End;
  End;
End;

Constructor TGitHistoryIndex.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FThread := Nil;
  FGit := Nil;
  FPendingModel := Nil;
  FPendingPhase := hipFailed;
  FPendingFailed := False;
  FGeneration := 0;
  FRepoPath := '';
  FStopFlag := 0;
  FOnAdopt := Nil;
End;

Destructor TGitHistoryIndex.Destroy;
Begin
  FOnAdopt := Nil;
  Stop;
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Function TGitHistoryIndex.Stopping: Boolean;
Begin
  Result := InterlockedCompareExchange(FStopFlag, 0, 0) <> 0;
End;

Procedure TGitHistoryIndex.Publish(Phase: TGitHistoryPhase; Model: TGitGraphModel);
Var
  Replaced: TGitGraphModel;
  Git: TGitService;
Begin
  Replaced := Nil;
  Git := TGitService(FGit);
  If Stopping Or (Assigned(Git) And Git.Cancelled) Then
    Begin
      FreeAndNil(Model);
      Exit;
    End;
  EnterCriticalSection(FLock);
  Try
    If Model <> Nil Then
      Begin
        Replaced := FPendingModel;
        FPendingModel := Model;
        FPendingPhase := Phase;
        FPendingGeneration := FGeneration;
      End
    Else
      Begin
        FPendingFailed := True;
        FPendingGeneration := FGeneration;
      End;
  Finally
    LeaveCriticalSection(FLock);
  End;
  FreeAndNil(Replaced);
  If Assigned(FThread) Then
    TThread.Queue(FThread, @Deliver);
End;

Procedure TGitHistoryIndex.Deliver;
Var
  Model: TGitGraphModel;
  Phase: TGitHistoryPhase;
  Generation: Integer;
  Failed, Adopted: Boolean;
Begin
  { Queued on the IDE thread. A replaced window must not see this model. }
  EnterCriticalSection(FLock);
  Try
    Model := FPendingModel;
    Phase := FPendingPhase;
    Generation := FPendingGeneration;
    Failed := FPendingFailed;
    FPendingModel := Nil;
    FPendingFailed := False;
  Finally
    LeaveCriticalSection(FLock);
  End;
  Adopted := False;
  Try
    If Assigned(Model) And Assigned(FOnAdopt) And Not Stopping Then
      Adopted := FOnAdopt(Self, Generation, Phase, Model);
    If Failed And Assigned(FOnAdopt) And Not Stopping Then
      FOnAdopt(Self, Generation, hipFailed, Nil);
  Except
    On E: Exception Do
      WorkflowLogger.Error('GitHistoryIndex', 'Deliver: ' + E.Message);
  End;
  If Not Adopted Then
    FreeAndNil(Model);
End;

Function BuildModel(Const RevListText: String): TGitGraphModel;
Begin
  Result := TGitGraphModel.Create;
  Result.ParseRevListParents(RevListText);
End;

Function TGitHistoryIndex.TryShowCacheHead(Out CachedKey: String): Boolean;
Var
  HeadText: String;
  Model: TGitGraphModel;
Begin
  Result := False;
  CachedKey := '';
  If Not LoadHistoryCacheHead(FRepoPath, GitGraphHeadWindow, CachedKey, HeadText) Then
    Exit;
  Model := BuildModel(HeadText);
  If Model.Count < 1 Then
    Begin
      Model.Free;
      Exit;
    End;
  Publish(hipHead, Model);
  Result := Not Stopping;
End;

Function TGitHistoryIndex.PublishCachedFull(Const LiveKey: String): Boolean;
Var
  StoredKey, Body: String;
  Model: TGitGraphModel;
Begin
  Result := False;
  If (LiveKey = '') Or Stopping Then
    Exit;
  If Not LoadHistoryCache(FRepoPath, StoredKey, Body) Then
    Exit;
  If StoredKey <> LiveKey Then
    Exit;
  Model := BuildModel(Body);
  If Model.Count < 1 Then
    Begin
      Model.Free;
      Exit;
    End;
  WorkflowLogger.Info('GitHistoryIndex', 'History cache hit: ' + IntToStr(Model.Count) + ' commits');
  Publish(hipFull, Model);
  Result := True;
End;

Procedure TGitHistoryIndex.IndexFromGit(Const LiveKey: String; StaleShown: Boolean);
Var
  HeadText, FullText, Fresh, SaveKey: String;
  Model: TGitGraphModel;
  Git: TGitService;
Begin
  Git := TGitService(FGit);
  If Stopping Or Git.Cancelled Then
    Exit;
  If Not Git.FetchRevListParents(FRepoPath, HeadText, GitGraphHeadWindow) Then
    Begin
      If Git.LastError <> '' Then
        WorkflowLogger.Warning('GitHistoryIndex', Git.LastError);
      If StaleShown Then
        Publish(hipFull, TGitGraphModel.Create)
      Else
        Publish(hipFailed, Nil);
      Exit;
    End;
  If Stopping Or Git.Cancelled Then
    Exit;
  Model := BuildModel(HeadText);
  If Model.Count < 1 Then
    Begin
      Model.Free;
      If StaleShown Then
        Publish(hipFull, TGitGraphModel.Create)
      Else
        Publish(hipFailed, Nil);
      Exit;
    End;
  Publish(hipHead, Model);
  If Stopping Or Git.Cancelled Then
    Exit;
  If Not Git.FetchRevListParents(FRepoPath, FullText, 0) Then
    Begin
      If Git.LastError <> '' Then
        WorkflowLogger.Warning('GitHistoryIndex', Git.LastError);
      Publish(hipFailed, Nil);
      Exit;
    End;
  If Stopping Or Git.Cancelled Then
    Exit;
  Model := BuildModel(FullText);
  SaveKey := LiveKey;
  Fresh := '';
  If Git.HistoryIdentity(Fresh) And (Fresh <> '') Then
    Begin
      SaveKey := HistoryIdentityKey(Fresh);
      If (LiveKey = '') Or (SaveKey = LiveKey) Then
        SaveHistoryCache(FRepoPath, SaveKey, FullText);
    End
  Else If LiveKey <> '' Then
    SaveHistoryCache(FRepoPath, LiveKey, FullText);
  WorkflowLogger.Info('GitHistoryIndex', 'Indexed ' + IntToStr(Model.Count) + ' commits');
  Publish(hipFull, Model);
End;

Procedure TGitHistoryIndex.Run;
Var
  CachedKey, LiveIdentity, LiveKey: String;
  Git: TGitService;
  CacheShown: Boolean;
Begin
  Git := TGitService(FGit);
  Git.ResetCancel;
  CachedKey := '';
  CacheShown := False;
  If Not Stopping Then
    CacheShown := TryShowCacheHead(CachedKey);
  LiveIdentity := '';
  LiveKey := '';
  If Not Stopping And Not Git.Cancelled And Git.HistoryIdentity(LiveIdentity) And (LiveIdentity <> '') Then
    LiveKey := HistoryIdentityKey(LiveIdentity);
  If Stopping Or Git.Cancelled Then
    Exit;
  If (LiveKey <> '') And (LiveKey = CachedKey) And PublishCachedFull(LiveKey) Then
    Exit;
  IndexFromGit(LiveKey, CacheShown And (LiveKey <> '') And (LiveKey <> CachedKey));
End;

Procedure TGitHistoryIndex.Start(Const RepoPath: String; Generation: Integer);
Var
  Git: TGitService;
Begin
  Stop;
  InterlockedExchange(FStopFlag, 0);
  FGeneration := Generation;
  FRepoPath := RepoPath;
  FPendingFailed := False;
  Git := TGitService.Create;
  Git.PublishEvents := False;
  Git.RepoPath := RepoPath;
  Git.ResetCancel;
  FGit := Git;
  FThread := TGitHistoryWorker.Create(Self);
  FThread.Start;
End;

Procedure TGitHistoryIndex.Stop;
Var
  Pending: TGitGraphModel;
  Git: TGitService;
Begin
  InterlockedExchange(FStopFlag, 1);
  Git := TGitService(FGit);
  If Assigned(Git) Then
    Git.Cancel;
  If Assigned(FThread) Then
    Begin
      FThread.Terminate;
      FThread.WaitFor;
      TThread.RemoveQueuedEvents(FThread);
      FreeAndNil(FThread);
    End;
  EnterCriticalSection(FLock);
  Try
    Pending := FPendingModel;
    FPendingModel := Nil;
    FPendingFailed := False;
  Finally
    LeaveCriticalSection(FLock);
  End;
  FreeAndNil(Pending);
  Git := TGitService(FGit);
  FGit := Nil;
  FreeAndNil(Git);
End;

End.
