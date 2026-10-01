Unit GitService;

{ Git operations service – CLI primary with future libgit2 path (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Process, WorkflowEvents, WorkflowLog;

Const
  GitPreviewByteLimit = 8 * 1024 * 1024;

Type
  TGitStatusEntry = Record
    Path: String;
    OldPath: String; { rename/copy source }
    IndexStatus: Char; { staged column of porcelain XY }
    WorkTreeStatus: Char; { unstaged column }
  End;
  TGitStatusEntryArray = Array Of TGitStatusEntry;

  { Result of fetch / pull / push for user-facing summaries. }
  TGitTransferSummary = Record
    Remote: String;
    CommitCount: Integer;
    NewRefs: Integer;
    UpToDate: Boolean;
    Message: String;
  End;

  TGitRemoteSnapshot = Record
    RepoPath, ConfigPath, ConfigText, RefsText: String;
  End;

  TGitCommandResult = Record
    Success: Boolean;
    ExitCode: Integer;
    Signalled: Boolean;
    OutputText, ErrorText: String;
  End;

  TGitService = Class
  Private
    FRepoPath: String;
    FLastError: String;
    FLastCommand: TGitCommandResult;
    FOutputLimit: Int64;
    FCancelled: LongInt;
    FPublishEvents: Boolean;
    FActiveProcess: TProcess;
    FProcessLock: TRTLCriticalSection;
    FTimeoutMs: Integer;
    Function BlobByteSize(Const Spec: String): Int64;
    Function DiffContextLines(Const Path, Sha: String; Staged: Boolean): Integer;
    Procedure SetActiveProcess(Proc: TProcess);
    Procedure ClearActiveProcess;
    Function RunTimedOut(StartTick: QWord): Boolean;
    { Shared execute/drain/cancel/timeout. MergeStderr captures git messages in OutStream. }
    Function RunGitPump(Const WorkDir: String; Const Args: Array Of String;
      OutStream: TStream; Out ExitCode: Integer): Boolean;
    Function RunGit(Const Args: Array Of String; Out OutputText: String;
      Out ExitCode: Integer; IncludeDiagnostics: Boolean = False): Boolean;
    Function RunGitEx(Const WorkDir: String; Const Args: Array Of String;
      Out OutputText: String; Out ExitCode: Integer): Boolean;
    Function RunGitBinary(Const Args: Array Of String; Stream: TStream;
      Out ExitCode: Integer): Boolean;
    Function ExpandUnstagePaths(Paths: TStrings; Expanded: TStringList): Boolean;
    Function RunGitPaths(Const SubCommand: String; Const Paths: TStrings): Boolean;
    Function CountAheadOfUpstream: Integer;
    Procedure BuildTransferSummary(Const Operation, Remote, OutputText: String;
      Var Summary: TGitTransferSummary);
    Function AcceptTransferRemote(Const Operation, Remote: String; Out RemoteName: String;
      Out Summary: TGitTransferSummary): Boolean;
    Function AcceptTransferBranch(Const Operation, Branch: String; Out BranchName: String;
      Out Summary: TGitTransferSummary): Boolean;
    Procedure RestoreTransferCommand(Const OperationError: String; Const OperationResult: TGitCommandResult);
    Function IsCancelled: Boolean;
    Procedure EmitWorkingTreeChanged;
    Procedure EmitHeadChanged(Const NewHeadSha: String);
    Procedure EmitCommitCreated(Const Info: TGitCommitInfo);
    Procedure EmitRepositoryStateChanged(Const Path: String; NewState: TGitRepositoryState);
    Procedure EmitRemoteUpdated(Const RemoteName: String);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Cooperative cancel for background jobs: marks cancelled and kills the active git process. }
    Procedure Cancel;
    Procedure ResetCancel;
    Function DetectRepository(Const StartPath: String): String;
    Function IsRepository(Const Path: String): Boolean;
    Function GetHeadSha(Out Sha: String): Boolean;
    { True when HEAD has a parent (not the root/first commit). }
    Function HeadHasParent: Boolean;
    { True when Sha is reachable from any remote-tracking ref. Query failure leaves Pushed False. }
    Function IsCommitPushed(Const Sha: String; Out Pushed: Boolean): Boolean;
    Function GetCurrentBranch(Out Branch: String): Boolean;
    Function GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
    { One process: HEAD, branch, and a digest of porcelain v2 --branch output. }
    Function RefDigest(Out Digest: String): Boolean;
    Function ProbeRepository(Out HeadSha, Branch, Digest: String): Boolean;
    Function ListStatus(Out Entries: TGitStatusEntryArray; IncludeUntracked: Boolean = False;
      IncludeIgnored: Boolean = False): Boolean;
    { Tracked paths (ls-files -z). Caller frees Paths. }
    Function ListTrackedFiles(Out Paths: TStringList): Boolean;
    Function StagePaths(Paths: TStrings): Boolean;
    Function UnstagePaths(Paths: TStrings): Boolean;
    Function StageAll: Boolean;
    Function UnstageAll: Boolean;
    { Restore paths in index and worktree to HEAD (discards local changes). }
    Function RevertPaths(Paths: TStrings): Boolean;
    { Append unique patterns to the repository-root .gitignore. }
    Function AppendIgnorePatterns(Patterns: TStrings): Boolean;
    { Validate again at save time; never write through a .gitignore symlink. }
    Function SaveIgnoreFile(Lines: TStrings): Boolean;
    Function Commit(Const Message: String; Out NewSha: String; Amend: Boolean = False): Boolean;
    { Move HEAD to its parent. Soft keeps the last commit staged; mixed returns it to the worktree. }
    Function ResetLastCommit(Soft: Boolean): Boolean;
    { Full commit message (subject and body) for Sha. }
    Function GetCommitMessage(Const Sha: String; Out MessageText: String): Boolean;
    Function DiffPath(Const Path: String; Staged: Boolean; Out DiffText: String): Boolean;
    { Unified diff of the index vs HEAD (git diff --cached). Empty when nothing staged. }
    Function DiffStaged(Out DiffText: String): Boolean;
    { Short status for commit prompts (porcelain, truncated). }
    Function StatusSummaryForCommit(Out SummaryText: String): Boolean;
    { True when Path is tracked in the index (not untracked). }
    Function IsPathTracked(Const Path: String): Boolean;
    { Absolute path for a repo-relative working-tree path. }
    Function WorkingTreeFullPath(Const Path: String): String;
    { Working-tree file contents (for clean tracked files with no diff). }
    Function ReadWorkingTreeFile(Const Path: String; Out Content: String): Boolean;
    { Raw bytes from working tree into Stream (from start of Stream). }
    Function ReadWorkingTreeBytes(Const Path: String; Stream: TStream): Boolean;
    { Raw blob bytes: working tree (Sha=''), index (:path when Staged), or commit (Sha:path). }
    Function ReadBlobBytes(Const Sha, Path: String; Staged: Boolean; Stream: TStream): Boolean;
    { Apply a unified diff to the index (partial stage/unstage). Reverse undoes it. }
    Function ApplyPatchToIndex(Const PatchText: String; Reverse: Boolean = False): Boolean;
    { Full history index (SHA + parents only). Safe from worker threads. }
    Function FetchRevListParents(Const WorkDir: String; Out RevListText: String): Boolean;
    { Full rev-list plus the first DetailCount commit subjects for a single UI apply. }
    Function FetchHistoryPreview(Const WorkDir: String; DetailCount: Integer;
      Out RevListText, DetailsText: String; Out DetailsOk: Boolean): Boolean;
    { Detail lines for specific SHAs (subject/author/time/refs). Batched, worker-safe. }
    Function FetchCommitDetails(Const WorkDir: String; Shas: TStrings; Out DetailsText: String): Boolean;
    Function CountCommits(Const WorkDir: String; Out Total: Integer): Boolean;
    Function Fetch(Out Summary: TGitTransferSummary; Const Remote: String = 'origin'): Boolean;
    Function Pull(Out Summary: TGitTransferSummary; Const Remote: String = 'origin';
      Const Branch: String = ''): Boolean;
    Function Push(Out Summary: TGitTransferSummary; Const Remote: String = 'origin';
      Const Branch: String = ''): Boolean;
    Function InitRepository(Const Path: String): Boolean;
    Function CloneRepository(Const RemoteUrl, TargetDir: String): Boolean;
    Function SnapshotRemotes(Out Snapshot: TGitRemoteSnapshot): Boolean;
    Function RestoreRemotes(Const Snapshot: TGitRemoteSnapshot): Boolean;
    Function ListRemotes(Out Names, Urls: TStringList): Boolean;
    Function AddRemote(Const Name, Url: String): Boolean;
    Function SetRemoteUrl(Const Name, Url: String): Boolean;
    Function RemoveRemote(Const Name: String): Boolean;
    Function RenameRemote(Const OldName, NewName: String): Boolean;
    Function ShowCommit(Const Sha: String; Out Text: String): Boolean;
    { Paths changed in a commit (name-only, no renames rewritten). Caller frees Paths. }
    Function ListCommitPaths(Const Sha: String; Out Paths: TStringList): Boolean;
    { Full-file unified diff for one path in a commit (large context for embedded view). }
    Function ShowCommitPathDiff(Const Sha, Path: String; Out DiffText: String): Boolean;
    Function Checkout(Const RefName: String): Boolean;
    Function CreateBranch(Const BranchName, StartPoint: String): Boolean;
    { Local/global config helpers. Unset keys return True with Value=''. }
    Function GetConfigValue(Const Key: String; LocalOnly: Boolean; Out Value: String): Boolean;
    Function SetConfigValue(Const Key, Value: String; LocalOnly: Boolean): Boolean;
    Function UnsetConfigValue(Const Key: String; LocalOnly: Boolean): Boolean;
    { Absolute path to the git directory (.git or bare root). }
    Function GetGitDir(Out GitDir: String): Boolean;
    { Contents of .git/description (repository short description). }
    Function GetDescription(Out Description: String): Boolean;
    Function SetDescription(Const Description: String): Boolean;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
    Property LastError: String Read FLastError;
    Property LastCommand: TGitCommandResult Read FLastCommand;
    Property Cancelled: Boolean Read IsCancelled;
    { When False, skip WorkflowEventBus publishes (background job workers must not touch UI). }
    Property PublishEvents: Boolean Read FPublishEvents Write FPublishEvents;
    { 0 = no timeout. Checked in the drain loop so a long git can be killed. }
    Property TimeoutMs: Integer Read FTimeoutMs Write FTimeoutMs;
  End;

Function DirectoryIsEmpty(Const Dir: String): Boolean;
Function GitStatusEntryIsStaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryIsUnstaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryLabel(Const Entry: TGitStatusEntry; StagedSide: Boolean): String;
{ Porcelain v1 -z: XY space path NUL; rename/copy is dest NUL source NUL. }
Procedure ParseGitStatusPorcelainV1Z(Const Raw: String; Out Entries: TGitStatusEntryArray);

Var
  GitClient: TGitService;

{ Union status with absolute tracked paths, preserving raw Git filenames. }
Function MergeGitFileEntries(Const RepoPath: String; Const Entries: TGitStatusEntryArray;
  Tracked: TStrings): TGitStatusEntryArray;

Implementation

Uses
  LazFileUtils{$IFDEF UNIX}, BaseUnix{$ENDIF}{$IFDEF WINDOWS}, Windows{$ENDIF};

Function MergeGitFileEntries(Const RepoPath: String; Const Entries: TGitStatusEntryArray;
  Tracked: TStrings): TGitStatusEntryArray;
Var
  Paths: TStringList;
  I, N: Integer;
  Root, Rel: String;
Begin
  Result := Copy(Entries);
  N := Length(Result);
  If Assigned(Tracked) Then SetLength(Result, N + Tracked.Count);
  Paths := TStringList.Create;
  Try
    Paths.Sorted := True; Paths.Duplicates := dupIgnore;
    Paths.CaseSensitive := FileNameCaseSensitive;
    For I := 0 To High(Entries) Do Paths.Add(Entries[I].Path);
    Root := IncludeTrailingPathDelimiter(ExpandFileName(RepoPath));
    If Assigned(Tracked) Then
      For I := 0 To Tracked.Count - 1 Do
        Begin
          If CompareFilenames(Copy(Tracked[I], 1, Length(Root)), Root) <> 0 Then Continue;
          Rel := Copy(Tracked[I], Length(Root) + 1, MaxInt);
          {$IFDEF WINDOWS}Rel := StringReplace(Rel, '\', '/', [rfReplaceAll]);{$ENDIF}
          If (Rel = '') Or (Paths.IndexOf(Rel) >= 0) Then Continue;
          Paths.Add(Rel);
          Result[N].Path := Rel; Result[N].IndexStatus := ' '; Result[N].WorkTreeStatus := ' ';
          Inc(N);
        End;
    SetLength(Result, N);
  Finally Paths.Free; End;
End;

Function DirectoryIsEmpty(Const Dir: String): Boolean;
Var
  Rec: TSearchRec;
  Code: Integer;
Begin
  Result := False;
  If Not DirectoryExists(Dir) Then
    Exit;
  Result := True;
  Code := FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        If (Rec.Name <> '.') And (Rec.Name <> '..') Then
          Begin
            Result := False;
            Exit;
          End;
        Code := FindNext(Rec);
      End;
  Finally
    SysUtils.FindClose(Rec);
  End;
End;

Function GitStatusEntryIsStaged(Const Entry: TGitStatusEntry): Boolean;
Begin
  Result := (Entry.IndexStatus <> ' ') And (Entry.IndexStatus <> '?') And (Entry.IndexStatus <> '!');
End;

Function GitStatusEntryIsUnstaged(Const Entry: TGitStatusEntry): Boolean;
Begin
  Result := (Entry.WorkTreeStatus <> ' ') Or (Entry.IndexStatus = '?') Or (Entry.IndexStatus = '!');
End;

Function GitStatusEntryLabel(Const Entry: TGitStatusEntry; StagedSide: Boolean): String;
Var
  Code: Char;
Begin
  If StagedSide Then
    Code := Entry.IndexStatus
  Else If Entry.IndexStatus = '?' Then
    Code := '?'
  Else
    Code := Entry.WorkTreeStatus;
  Case Code Of
    'M': Result := 'modified:  ';
    'A': Result := 'new file:  ';
    'D': Result := 'deleted:   ';
    'R': Result := 'renamed:   ';
    'C': Result := 'copied:    ';
    'U': Result := 'unmerged:  ';
    'T': Result := 'typechange:';
    '?': Result := 'untracked: ';
    '!': Result := 'ignored:   ';
  Else
    Result := Code + ':         ';
  End;
  If (Entry.OldPath <> '') And ((Code = 'R') Or (Code = 'C')) Then
    Result := Result + Entry.OldPath + ' -> ' + Entry.Path
  Else
    Result := Result + Entry.Path;
End;

Constructor TGitService.Create;
Begin
  Inherited Create;
  FRepoPath := '';
  FLastError := '';
  InterlockedExchange(FCancelled, 0);
  FPublishEvents := True;
  FActiveProcess := Nil;
  FTimeoutMs := 0;
  InitCriticalSection(FProcessLock);
End;

Function TGitService.RunTimedOut(StartTick: QWord): Boolean;
Begin
  Result := (FTimeoutMs > 0) And ((GetTickCount64 - StartTick) >= QWord(FTimeoutMs));
End;

Procedure TGitService.SetActiveProcess(Proc: TProcess);
Begin
  EnterCriticalSection(FProcessLock);
  Try
    FActiveProcess := Proc;
  Finally
    LeaveCriticalSection(FProcessLock);
  End;
End;

Procedure TGitService.ClearActiveProcess;
Begin
  EnterCriticalSection(FProcessLock);
  Try
    FActiveProcess := Nil;
  Finally
    LeaveCriticalSection(FProcessLock);
  End;
End;

Procedure TGitService.EmitWorkingTreeChanged;
Begin
  If FPublishEvents And Assigned(WorkflowEventBus) And (FRepoPath <> '') Then
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
End;

Procedure TGitService.EmitHeadChanged(Const NewHeadSha: String);
Begin
  If FPublishEvents And Assigned(WorkflowEventBus) And (FRepoPath <> '') Then
    WorkflowEventBus.NotifyHeadChanged(FRepoPath, NewHeadSha);
End;

Procedure TGitService.EmitCommitCreated(Const Info: TGitCommitInfo);
Begin
  If FPublishEvents And Assigned(WorkflowEventBus) And (FRepoPath <> '') Then
    WorkflowEventBus.NotifyCommitCreated(FRepoPath, Info);
End;

Procedure TGitService.EmitRepositoryStateChanged(Const Path: String; NewState: TGitRepositoryState);
Begin
  If FPublishEvents And Assigned(WorkflowEventBus) And (Path <> '') Then
    WorkflowEventBus.NotifyRepositoryStateChanged(Path, NewState);
End;

Procedure TGitService.EmitRemoteUpdated(Const RemoteName: String);
Begin
  If FPublishEvents And Assigned(WorkflowEventBus) And (FRepoPath <> '') Then
    WorkflowEventBus.NotifyRemoteUpdated(FRepoPath, RemoteName);
End;

Procedure TGitService.ResetCancel;
Begin
  InterlockedExchange(FCancelled, 0);
End;

Function TGitService.IsCancelled: Boolean;
Begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
End;

Procedure TGitService.Cancel;
Begin
  InterlockedExchange(FCancelled, 1);
  { Terminate under the lock so the drain loop cannot Free the process mid-call. }
  EnterCriticalSection(FProcessLock);
  Try
    If Assigned(FActiveProcess) And (FActiveProcess.ProcessID > 0) Then
      Try
        FActiveProcess.Terminate(1);
      Except
      End;
  Finally
    LeaveCriticalSection(FProcessLock);
  End;
End;

Destructor TGitService.Destroy;
Begin
  Cancel;
  DoneCriticalSection(FProcessLock);
  Inherited Destroy;
End;

Function TGitService.RunGitPump(Const WorkDir: String; Const Args: Array Of String;
  OutStream: TStream; Out ExitCode: Integer): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;
  TimedOut: Boolean;
  ErrorStream: TStringStream;
Begin
  Result := False;
  ExitCode := -1;
  FLastError := '';
  FLastCommand := Default(TGitCommandResult);
  FLastCommand.ExitCode := -1;
  TimedOut := False;
  StartTick := GetTickCount64;
  Buf[Low(Buf)] := 0;
  If (WorkDir = '') Or (OutStream = Nil) Then
    Begin
      FLastError := 'No repository path set';
      If WorkDir = '' Then
        WorkflowLogger.Error('GitService', FLastError);
      Exit;
    End;
  If IsCancelled Then
    Begin
      FLastError := 'Cancelled';
      Exit;
    End;

  Proc := TProcess.Create(Nil);
  ErrorStream := TStringStream.Create('');
  Try
    Proc.Executable := 'git';
    Proc.CurrentDirectory := WorkDir;
    { Always hide the process. On Windows, omitting poNoConsole allocates a
      console for git.exe. Credential Manager is a separate GUI and does not
      need this window; status belongs on the Manage form. }
    Proc.Options := [poUsePipes, poNoConsole];

    Proc.ShowWindow := swoHIDE;
    Proc.Parameters.Clear;
    { Every path API takes filenames, never user-supplied Git patterns. }
    Proc.Parameters.Add('--literal-pathspecs');
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);

    Try
      { Never expose an unlaunched process to Cancel: on Unix Terminate with
        PID zero signals the whole IDE process group. Cancellation between
        Execute and publication is handled by the first drain-loop check. }
      Proc.Execute;
      SetActiveProcess(Proc);
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Or
            (Proc.Stderr.NumBytesAvailable > 0) Do
        Begin
          If IsCancelled Or RunTimedOut(StartTick) Then
            Begin
              TimedOut := RunTimedOut(StartTick);
              Try
                Proc.Terminate(1);
              Except
              End;
              Break;
            End;
          If Proc.Output.NumBytesAvailable > 0 Then
            Begin
              BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
              If BytesRead > 0 Then
                Begin
                  If (FOutputLimit > 0) And (OutStream.Size + BytesRead > FOutputLimit) Then
                    Raise EStreamError.Create('Preview exceeds 8 MiB limit');
                  OutStream.WriteBuffer(Buf[0], BytesRead);
                End;
            End;
          If Proc.Stderr.NumBytesAvailable > 0 Then
            Begin
              BytesRead := Proc.Stderr.Read(Buf[0], SizeOf(Buf));
              If BytesRead > 0 Then ErrorStream.WriteBuffer(Buf[0], BytesRead);
            End;
          If Proc.Running And (Proc.Output.NumBytesAvailable = 0) And
             (Proc.Stderr.NumBytesAvailable = 0) Then
            Sleep(1);
        End;
      While Proc.Output.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          If BytesRead > 0 Then
            Begin
              If (FOutputLimit > 0) And (OutStream.Size + BytesRead > FOutputLimit) Then
                Raise EStreamError.Create('Preview exceeds 8 MiB limit');
              OutStream.WriteBuffer(Buf[0], BytesRead);
            End
          Else
            Break;
        End;
      While Proc.Stderr.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Stderr.Read(Buf[0], SizeOf(Buf));
          If BytesRead <= 0 Then Break;
          ErrorStream.WriteBuffer(Buf[0], BytesRead);
        End;
      FLastCommand.ErrorText := ErrorStream.DataString;
      {$IFDEF UNIX}
      FLastCommand.Signalled := Not WIFEXITED(Proc.ExitStatus);
      If FLastCommand.Signalled Then ExitCode := -1
      Else ExitCode := WEXITSTATUS(Proc.ExitStatus);
      {$ELSE}
      ExitCode := Proc.ExitStatus;
      {$ENDIF}
      FLastCommand.ExitCode := ExitCode;
      If TimedOut Then
        Begin
          FLastError := 'Timed out';
          Result := False;
        End
      Else If IsCancelled Then
        Begin
          FLastError := 'Cancelled';
          Result := False;
        End
      Else
        Begin
          Result := ExitCode = 0;
          If Not Result Then
            FLastError := Format('git %s exited %d', [Args[0], ExitCode]) +
              ': ' + Trim(FLastCommand.ErrorText);
        End;
    Except
      On E: Exception Do
        Begin
          If Proc.Running Then Proc.Terminate(1);
          FLastError := 'Failed to run git: ' + E.Message;
          WorkflowLogger.Error('GitService', FLastError);
          Result := False;
        End;
    End;
  Finally
    FLastCommand.ErrorText := ErrorStream.DataString;
    FLastCommand.Success := Result;
    ClearActiveProcess;
    ErrorStream.Free;
    Proc.Free;
  End;
End;

Function TGitService.RunGitEx(Const WorkDir: String; Const Args: Array Of String;
  Out OutputText: String; Out ExitCode: Integer): Boolean;
Var
  Mem: TMemoryStream;
Begin
  OutputText := '';
  Mem := TMemoryStream.Create;
  Try
    Result := RunGitPump(WorkDir, Args, Mem, ExitCode);
    SetLength(OutputText, Mem.Size);
    If Mem.Size > 0 Then
      Move(Mem.Memory^, OutputText[1], Mem.Size);
    FLastCommand.OutputText := OutputText;
    If (Not Result) And (FLastError <> 'Timed out') And (FLastError <> 'Cancelled') And
       (Pos('Failed to run git:', FLastError) <> 1) Then
      Begin
        If Trim(OutputText) <> '' Then
          FLastError := FLastError + ': ' + Trim(OutputText);
        If FLastError <> '' Then
          WorkflowLogger.Warning('GitService', FLastError);
      End;
  Finally
    Mem.Free;
  End;
End;

Function TGitService.RunGit(Const Args: Array Of String; Out OutputText: String;
  Out ExitCode: Integer; IncludeDiagnostics: Boolean): Boolean;
Begin
  Result := RunGitEx(FRepoPath, Args, OutputText, ExitCode);
  If IncludeDiagnostics And (FLastCommand.ErrorText <> '') Then
    OutputText := OutputText + LineEnding + FLastCommand.ErrorText;
End;

Function TGitService.RunGitBinary(Const Args: Array Of String; Stream: TStream;
  Out ExitCode: Integer): Boolean;
Begin
  Result := RunGitPump(FRepoPath, Args, Stream, ExitCode);
End;

Function TGitService.FetchRevListParents(Const WorkDir: String; Out RevListText: String): Boolean;
Var
  ExitCode: Integer;
Begin
  { Compact full-history index: one line per commit "sha [parent…]".
    Enough for lanes/edges without loading subjects for every commit. }
  RevListText := '';
  Result := RunGitEx(WorkDir, ['rev-list', '--all', '--topo-order', '--parents'], RevListText, ExitCode);
End;

Procedure CollectLeadingShas(Const RevListText: String; MaxCount: Integer; Shas: TStrings);
Var
  Lines: TStringList;
  I, SpacePos: Integer;
  Line, Sha: String;
Begin
  If (Shas = Nil) Or (MaxCount < 1) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := RevListText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        If Shas.Count >= MaxCount Then
          Break;
        Line := Trim(Lines[I]);
        If Line = '' Then
          Continue;
        SpacePos := Pos(' ', Line);
        If SpacePos > 0 Then
          Sha := Copy(Line, 1, SpacePos - 1)
        Else
          Sha := Line;
        If Sha <> '' Then
          Shas.Add(Sha);
      End;
  Finally
    Lines.Free;
  End;
End;

Function TGitService.FetchHistoryPreview(Const WorkDir: String; DetailCount: Integer;
  Out RevListText, DetailsText: String; Out DetailsOk: Boolean): Boolean;
Var
  Shas: TStringList;
Begin
  RevListText := '';
  DetailsText := '';
  DetailsOk := False;
  Result := FetchRevListParents(WorkDir, RevListText);
  If Not Result Or (DetailCount < 1) Then
    Exit;
  Shas := TStringList.Create;
  Try
    CollectLeadingShas(RevListText, DetailCount, Shas);
    If Shas.Count > 0 Then
      DetailsOk := FetchCommitDetails(WorkDir, Shas, DetailsText);
  Finally
    Shas.Free;
  End;
End;

Function TGitService.FetchCommitDetails(Const WorkDir: String; Shas: TStrings; Out DetailsText: String): Boolean;
Var
  ExitCode, I: Integer;
  Args: Array Of String;
Begin
  DetailsText := '';
  Result := False;
  Args := Nil;
  If (Shas = Nil) Or (Shas.Count = 0) Then
    Exit;

  { --no-walk: resolve only listed SHAs (O(batch), not O(history)). }
  SetLength(Args, 5 + Shas.Count);
  Args[0] := '-c';
  Args[1] := 'core.quotePath=false';
  Args[2] := 'log';
  Args[3] := '--no-walk=unsorted';
  Args[4] := '--pretty=format:%H' + #1 + '%s' + #1 + '%an' + #1 + '%ct' + #1 + '%D';
  For I := 0 To Shas.Count - 1 Do
    Args[5 + I] := Shas[I];

  Result := RunGitEx(WorkDir, Args, DetailsText, ExitCode);
End;

Function TGitService.CountCommits(Const WorkDir: String; Out Total: Integer): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Total := 0;
  Result := RunGitEx(WorkDir, ['rev-list', '--all', '--count'], OutputText, ExitCode);
  If Result Then
    Total := StrToIntDef(Trim(OutputText), 0);
End;

Function TGitService.DetectRepository(Const StartPath: String): String;
Var
  Dir, Candidate: String;
Begin
  Result := '';
  Dir := ExpandFileName(StartPath);
  While Dir <> '' Do
    Begin
      Candidate := IncludeTrailingPathDelimiter(Dir) + '.git';
      If DirectoryExists(Candidate) Or FileExists(Candidate) Then
        Begin
          Result := Dir;
          Exit;
        End;
      If ExtractFileDir(Dir) = Dir Then
        Break; { reached root }
      Dir := ExtractFileDir(Dir);
    End;
End;

Function TGitService.IsRepository(Const Path: String): Boolean;
Begin
  Result := DetectRepository(Path) <> '';
End;

Function TGitService.GetHeadSha(Out Sha: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Sha := '';
  Result := RunGit(['rev-parse', 'HEAD'], OutputText, ExitCode);
  If Result Then
    Sha := Trim(OutputText);
End;

Function TGitService.HeadHasParent: Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := RunGit(['rev-parse', '--verify', '--quiet', 'HEAD~1'], OutputText, ExitCode);
End;

Function TGitService.IsCommitPushed(Const Sha: String; Out Pushed: Boolean): Boolean;
Var
  OutputText, Trimmed: String;
  ExitCode: Integer;
Begin
  Pushed := False;
  Result := False;
  Trimmed := Trim(Sha);
  If Trimmed = '' Then
    Exit;
  { First matching remote-tracking ref is enough. Empty output means Sha is local-only. }
  Result := RunGit(['for-each-ref', '--count=1', '--contains=' + Trimmed, '--format=%(refname)',
    'refs/remotes'], OutputText, ExitCode);
  If Result Then
    Pushed := Trim(OutputText) <> '';
End;

Function TGitService.GetCurrentBranch(Out Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Branch := '';
  Result := RunGit(['rev-parse', '--abbrev-ref', 'HEAD'], OutputText, ExitCode);
  If Result Then
    Branch := Trim(OutputText);
End;

Function TGitService.GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Clean := True;
  Porcelain := '';
  Result := RunGit(['status', '--porcelain'], OutputText, ExitCode);
  If Result Then
    Begin
      Porcelain := OutputText;
      Clean := Trim(OutputText) = '';
    End;
End;

Function TGitService.RefDigest(Out Digest: String): Boolean;
Var Code: Integer;
Begin
  Result := RunGit(['for-each-ref', '--format=%(refname) %(objectname)', '--sort=refname'], Digest, Code);
End;

Function TGitService.ProbeRepository(Out HeadSha, Branch, Digest: String): Boolean;
Var
  OutputText, Line: String;
  ExitCode, I: Integer;
  Lines: TStringList;
Begin
  HeadSha := '';
  Branch := '';
  Digest := '';
  Result := RunGit(['-c', 'core.quotePath=false', 'status', '--porcelain=v2', '--branch'],
    OutputText, ExitCode);
  If Not Result Then
    Exit;
  Digest := OutputText;
  Lines := TStringList.Create;
  Try
    Lines.Text := OutputText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Copy(Line, 1, 13) = '# branch.oid ' Then
          HeadSha := Trim(Copy(Line, 14, MaxInt))
        Else If Copy(Line, 1, 14) = '# branch.head ' Then
          Branch := Trim(Copy(Line, 15, MaxInt));
      End;
  Finally
    Lines.Free;
  End;
  If (Branch = '(detached)') Or (Branch = '') Then
    If HeadSha <> '' Then
      Branch := 'HEAD';
End;

Function GitNameIsSafe(Const Name: String): Boolean;
Var
  Clean: String;
Begin
  Clean := Trim(Name);
  Result := (Clean <> '') And (Clean[1] <> '-');
End;

Function GitStringHasAsciiControl(Const Value: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 1 To Length(Value) Do
    If (Value[I] < #32) Or (Value[I] = #127) Then
      Begin
        Result := True;
        Exit;
      End;
End;

{ Clone URLs are positional. Reject option-like and control text before Git runs. }
Function GitCloneUrlRejection(Const RemoteUrl: String; Out Reason: String): Boolean;
Var
  Clean: String;
Begin
  Reason := '';
  Result := True;
  If GitStringHasAsciiControl(RemoteUrl) Then
    Reason := 'Remote URL was rejected because it contains a control character'
  Else
    Begin
      Clean := Trim(RemoteUrl);
      If Clean = '' Then
        Reason := 'Remote URL is empty'
      Else If Clean[1] = '-' Then
        Reason := 'Remote URL was rejected because it looks like a Git option'
      Else
        Result := False;
    End;
End;

Function NextNulField(Const S: String; Var Pos: Integer): String;
Var
  StartPos: Integer;
Begin
  StartPos := Pos;
  While (Pos <= Length(S)) And (S[Pos] <> #0) Do
    Inc(Pos);
  Result := Copy(S, StartPos, Pos - StartPos);
  If (Pos <= Length(S)) And (S[Pos] = #0) Then
    Inc(Pos);
End;

Procedure ParseGitStatusPorcelainV1Z(Const Raw: String; Out Entries: TGitStatusEntryArray);
Var
  Rec, Path, OldPath: String;
  Cursor, Count: Integer;
  X, Y: Char;
Begin
  Entries := Nil;
  SetLength(Entries, 0);
  Cursor := 1;
  Count := 0;
  While Cursor <= Length(Raw) Do
    Begin
      Rec := NextNulField(Raw, Cursor);
      If Length(Rec) < 4 Then
        Continue;
      X := Rec[1];
      Y := Rec[2];
      { -z reverses rename/copy field order: destination first, source second. }
      Path := Copy(Rec, 4, MaxInt);
      OldPath := '';
      If (X = 'R') Or (X = 'C') Or (Y = 'R') Or (Y = 'C') Then
        OldPath := NextNulField(Raw, Cursor);
      If Path = '' Then
        Continue;
      Inc(Count);
      SetLength(Entries, Count);
      Entries[Count - 1].Path := Path;
      Entries[Count - 1].OldPath := OldPath;
      Entries[Count - 1].IndexStatus := X;
      Entries[Count - 1].WorkTreeStatus := Y;
    End;
End;

Function TGitService.ListStatus(Out Entries: TGitStatusEntryArray; IncludeUntracked: Boolean;
  IncludeIgnored: Boolean): Boolean;
Var
  Raw: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  Entries := Nil;
  SetLength(Entries, 0);
  Args := Nil;
  { -z: NUL records, no quoting. Rename/copy is dest then source. }
  If IncludeIgnored Then
    Args := ['-c', 'core.quotePath=false', 'status', '--porcelain=v1', '-z',
      '--untracked-files=all', '--ignored']
  Else If IncludeUntracked Then
    Args := ['-c', 'core.quotePath=false', 'status', '--porcelain=v1', '-z',
      '--untracked-files=all']
  Else
    Args := ['-c', 'core.quotePath=false', 'status', '--porcelain=v1', '-z',
      '--untracked-files=no'];
  Result := RunGit(Args, Raw, ExitCode);
  If Not Result Then
    Exit;
  ParseGitStatusPorcelainV1Z(Raw, Entries);
End;

Function TGitService.ListTrackedFiles(Out Paths: TStringList): Boolean;
Var
  Raw, Rel, Full: String;
  ExitCode, Cursor: Integer;
Begin
  Paths := TStringList.Create;
  Paths.Sorted := True;
  Paths.Duplicates := dupIgnore;
  Paths.CaseSensitive := FileNameCaseSensitive;
  Result := RunGit(['-c', 'core.quotePath=false', 'ls-files', '-z'], Raw, ExitCode);
  If Not Result Then
    Exit;
  Cursor := 1;
  While Cursor <= Length(Raw) Do
    Begin
      Rel := NextNulField(Raw, Cursor);
      If Rel = '' Then
        Continue;
      Full := WorkingTreeFullPath(Rel);
      If Full <> '' Then
        Paths.Add(Full);
    End;
End;

Function TGitService.RunGitPaths(Const SubCommand: String; Const Paths: TStrings): Boolean;
Var
  Args: Array Of String;
  I: Integer;
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  Args := Nil;
  If (Paths = Nil) Or (Paths.Count = 0) Then
    Exit;
  { git <cmd> -- path1 path2 ... }
  SetLength(Args, 2 + Paths.Count);
  Args[0] := SubCommand;
  Args[1] := '--';
  For I := 0 To Paths.Count - 1 Do
    Args[2 + I] := Paths[I];
  Result := RunGit(Args, OutputText, ExitCode);
End;

Function TGitService.StagePaths(Paths: TStrings): Boolean;
Begin
  Result := RunGitPaths('add', Paths);
  If Result Then
    EmitWorkingTreeChanged;
End;

Function TGitService.ExpandUnstagePaths(Paths: TStrings; Expanded: TStringList): Boolean;
Var
  Entries: TGitStatusEntryArray;
  I: Integer;
Begin
  { Resolve against fresh index status rather than a possibly stale UI row.
    A rename is one displayed change but two paths in the index. Copies must
    not unstage the independent source file. }
  Result := ListStatus(Entries, False, False);
  If Not Result Then
    Exit;
  Expanded.CaseSensitive := True;
  Expanded.AddStrings(Paths);
  For I := 0 To High(Entries) Do
    If (Entries[I].IndexStatus = 'R') And (Entries[I].OldPath <> '') And
       (Expanded.IndexOf(Entries[I].Path) >= 0) And
       (Expanded.IndexOf(Entries[I].OldPath) < 0) Then
      Expanded.Add(Entries[I].OldPath);
End;

Function TGitService.UnstagePaths(Paths: TStrings): Boolean;
Var
  Args: Array Of String;
  Expanded: TStringList;
  I: Integer;
  OutputText, DummySha: String;
  ExitCode: Integer;
Begin
  Result := False;
  Args := Nil;
  If (Paths = Nil) Or (Paths.Count = 0) Then
    Exit;
  Expanded := TStringList.Create;
  Try
    If Not ExpandUnstagePaths(Paths, Expanded) Then
      Exit;
    If GetHeadSha(DummySha) Then
      Begin
        { git restore --staged -- paths  (modern); fall back handled by git version }
        SetLength(Args, 3 + Expanded.Count);
        Args[0] := 'restore';
        Args[1] := '--staged';
        Args[2] := '--';
        For I := 0 To Expanded.Count - 1 Do
          Args[3 + I] := Expanded[I];
        Result := RunGit(Args, OutputText, ExitCode);
        If Not Result Then
          Begin
            { Older git: git reset HEAD -- paths }
            SetLength(Args, 3 + Expanded.Count);
            Args[0] := 'reset';
            Args[1] := 'HEAD';
            Args[2] := '--';
            For I := 0 To Expanded.Count - 1 Do
              Args[3 + I] := Expanded[I];
            Result := RunGit(Args, OutputText, ExitCode);
          End;
      End
    Else
      Begin
        { Newly initialised repo: restore/reset need HEAD. Drop paths from the index. }
        SetLength(Args, 4 + Expanded.Count);
        Args[0] := 'rm';
        Args[1] := '--cached';
        Args[2] := '-f';
        Args[3] := '--';
        For I := 0 To Expanded.Count - 1 Do
          Args[4 + I] := Expanded[I];
        Result := RunGit(Args, OutputText, ExitCode);
      End;
    If Result Then
      EmitWorkingTreeChanged;
  Finally
    Expanded.Free;
  End;
End;

Function TGitService.StageAll: Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := RunGit(['add', '-A'], OutputText, ExitCode);
  If Result Then
    EmitWorkingTreeChanged;
End;

Function TGitService.UnstageAll: Boolean;
Var
  OutputText, DummySha: String;
  ExitCode: Integer;
Begin
  If GetHeadSha(DummySha) Then
    Begin
      Result := RunGit(['restore', '--staged', '.'], OutputText, ExitCode);
      If Not Result Then
        Result := RunGit(['reset', 'HEAD'], OutputText, ExitCode);
    End
  Else
    Result := RunGit(['rm', '-r', '--cached', '-f', '.'], OutputText, ExitCode);
  If Result Then
    EmitWorkingTreeChanged;
End;

Function TGitService.RevertPaths(Paths: TStrings): Boolean;
Var
  Args: Array Of String;
  I: Integer;
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  Args := Nil;
  If (Paths = Nil) Or (Paths.Count = 0) Then
    Exit;
  { Modern: restore staged + worktree content from HEAD for listed paths. }
  SetLength(Args, 5 + Paths.Count);
  Args[0] := 'restore';
  Args[1] := '--source=HEAD';
  Args[2] := '--staged';
  Args[3] := '--worktree';
  Args[4] := '--';
  For I := 0 To Paths.Count - 1 Do
    Args[5 + I] := Paths[I];
  Result := RunGit(Args, OutputText, ExitCode);
  If Not Result Then
    Begin
      { Older git: checkout HEAD -- paths }
      SetLength(Args, 3 + Paths.Count);
      Args[0] := 'checkout';
      Args[1] := 'HEAD';
      Args[2] := '--';
      For I := 0 To Paths.Count - 1 Do
        Args[3 + I] := Paths[I];
      Result := RunGit(Args, OutputText, ExitCode);
    End;
  If Result Then
    EmitWorkingTreeChanged;
End;

Function TGitService.AppendIgnorePatterns(Patterns: TStrings): Boolean;
Var
  IgnorePath, Pattern: String;
  Lines: TStringList;
  I: Integer;
  Changed: Boolean;
Begin
  Result := False;
  FLastError := '';
  If (FRepoPath = '') Or (Patterns = Nil) Or (Patterns.Count = 0) Then
    Begin
      FLastError := 'No ignore patterns to append';
      Exit;
    End;
  IgnorePath := WorkingTreeFullPath('.gitignore');
  If IgnorePath = '' Then
    Begin
      If FLastError = '' Then
        FLastError := 'Could not resolve .gitignore path';
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    Try
      If FileExists(IgnorePath) Then
        Lines.LoadFromFile(IgnorePath);
      Changed := False;
      For I := 0 To Patterns.Count - 1 Do
        Begin
          Pattern := Trim(Patterns[I]);
          If Pattern = '' Then
            Continue;
          Pattern := StringReplace(Pattern, '\', '/', [rfReplaceAll]);
          { Anchor repo-relative paths (not already rooted, negated, or a glob). }
          If (Pattern[1] <> '/') And (Pattern[1] <> '!') And (Pos('*', Pattern) = 0) Then
            Pattern := '/' + Pattern;
          If Lines.IndexOf(Pattern) < 0 Then
            Begin
              Lines.Add(Pattern);
              Changed := True;
            End;
        End;
      If Changed Then
        Exit(SaveIgnoreFile(Lines));
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          Result := False;
        End;
    End;
  Finally
    Lines.Free;
  End;
End;

Function TGitService.SaveIgnoreFile(Lines: TStrings): Boolean;
Var
  IgnorePath: String;
Begin
  Result := False;
  FLastError := '';
  If Lines = Nil Then
    Exit;
  IgnorePath := WorkingTreeFullPath('.gitignore');
  If IgnorePath = '' Then
    Exit;
  If FileIsSymlink(IgnorePath) Then
    Begin
      FLastError := 'Cannot write through a .gitignore symbolic link';
      Exit;
    End;
  Try
    Lines.SaveToFile(IgnorePath);
    Result := True;
    EmitWorkingTreeChanged;
  Except
    On E: Exception Do
      FLastError := 'Could not save .gitignore: ' + E.Message;
  End;
End;

Function TGitService.Commit(Const Message: String; Out NewSha: String; Amend: Boolean): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Info: TGitCommitInfo;
  Args: Array Of String;
Begin
  NewSha := '';
  Result := False;
  Args := Nil;
  If Trim(Message) = '' Then
    Begin
      FLastError := 'Commit message is empty';
      Exit;
    End;
  If Amend Then
    Args := ['commit', '--amend', '-m', Message]
  Else
    Args := ['commit', '-m', Message];
  Result := RunGit(Args, OutputText, ExitCode);
  If Not Result Then
    Exit;
  If GetHeadSha(NewSha) Then
    Begin
      Info.Sha := NewSha;
      Info.ShortSha := Copy(NewSha, 1, 7);
      Info.Summary := Trim(Message);
      Info.AuthorName := '';
      Info.AuthorEmail := '';
      Info.CommitDate := Now;
      Info.ParentCount := 1;
      EmitCommitCreated(Info);
      EmitWorkingTreeChanged;
      EmitHeadChanged(NewSha);
    End;
End;

Function TGitService.ResetLastCommit(Soft: Boolean): Boolean;
Var
  OutputText, NewSha: String;
  ExitCode: Integer;
  Mode: String;
Begin
  Result := False;
  If Soft Then
    Mode := '--soft'
  Else
    Mode := '--mixed';
  If HeadHasParent Then
    Result := RunGit(['reset', '-q', Mode, 'HEAD~1'], OutputText, ExitCode)
  Else If Soft Then
    Begin
      FLastError := 'The first commit cannot be unpacked for amend';
      Result := False;
    End
  Else
    Begin
      Result := RunGit(['update-ref', '-d', 'HEAD'], OutputText, ExitCode);
      If Result Then
        Result := UnstageAll;
    End;
  If Result Then
    Begin
      If GetHeadSha(NewSha) Then
        EmitHeadChanged(NewSha)
      Else
        EmitHeadChanged('');
      EmitWorkingTreeChanged;
    End;
End;

Function TGitService.GetCommitMessage(Const Sha: String; Out MessageText: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  MessageText := '';
  Result := False;
  If Trim(Sha) = '' Then
    Begin
      FLastError := 'Commit SHA is empty';
      Exit;
    End;
  Result := RunGit(['log', '-1', '--format=%B', Trim(Sha)], OutputText, ExitCode);
  If Result Then
    MessageText := TrimRight(OutputText);
End;

Function TGitService.IsPathTracked(Const Path: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If Path = '' Then
    Exit;
  { Exit 0 only when the path is in the index. }
  Result := RunGit(['ls-files', '--error-unmatch', '--', Path], OutputText, ExitCode);
End;

Function TGitService.WorkingTreeFullPath(Const Path: String): String;
Var
  Root, Combined, Expanded, PhysicalRoot, PhysicalPath, Existing, Parent: String;
Begin
  Result := '';
  If (Trim(Path) = '') Or (FRepoPath = '') Then
    Exit;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(FRepoPath));
  If FilenameIsAbsolute(Path) Then
    Expanded := ExpandFileName(Path)
  Else
    Begin
      Combined := StringReplace(Path, '/', DirectorySeparator, [rfReplaceAll]);
      Expanded := ExpandFileName(Root + Combined);
    End;
  If (Expanded = '') Or (CompareFilenames(Copy(Expanded, 1, Length(Root)), Root) <> 0) Then
    Begin
      FLastError := 'Path is outside the repository: ' + Path;
      Exit;
    End;
  { Check the nearest existing ancestor as well as existing files. FileExists
    follows symlinks and is false for dangling links, so test those explicitly. }
  Existing := Expanded;
  While Not FileExistsUTF8(Existing) And Not DirectoryExistsUTF8(Existing) Do
    Begin
      If FileIsSymlink(Existing) Then
        Begin
          FLastError := 'Path contains a dangling symbolic link: ' + Path;
          Exit;
        End;
      Parent := ExtractFileDir(Existing);
      If (Parent = '') Or (Parent = Existing) Then
        Begin
          FLastError := 'Path cannot be resolved: ' + Path;
          Exit;
        End;
      Existing := Parent;
    End;
  PhysicalRoot := GetPhysicalFilename(ExcludeTrailingPathDelimiter(Root), pfeEmpty);
  PhysicalPath := GetPhysicalFilename(Existing, pfeEmpty);
  If (PhysicalRoot = '') Or (PhysicalPath = '') Then
    Begin
      FLastError := 'Path cannot be resolved: ' + Path;
      Exit;
    End;
  PhysicalRoot := IncludeTrailingPathDelimiter(ExpandFileName(PhysicalRoot));
  PhysicalPath := IncludeTrailingPathDelimiter(ExpandFileName(PhysicalPath));
  If CompareFilenames(Copy(PhysicalPath, 1, Length(PhysicalRoot)), PhysicalRoot) <> 0 Then
    Begin
      FLastError := 'Path is outside the repository: ' + Path;
      Exit;
    End;
  Result := Expanded;
End;

Function TGitService.ReadWorkingTreeFile(Const Path: String; Out Content: String): Boolean;
Var Mem: TMemoryStream;
Begin
  Content := ''; Mem := TMemoryStream.Create;
  Try
    Result := ReadWorkingTreeBytes(Path, Mem);
    If Result Then
      Begin
        SetLength(Content, Mem.Size);
        If Mem.Size > 0 Then Move(Mem.Memory^, Content[1], Mem.Size);
      End;
  Finally Mem.Free; End;
End;

Function TGitService.ReadWorkingTreeBytes(Const Path: String; Stream: TStream): Boolean;
Var
  FullPath: String;
  FS: TFileStream;
Begin
  Result := False;
  If Stream = Nil Then
    Exit;
  FullPath := WorkingTreeFullPath(Path);
  If (FullPath = '') Or Not FileExists(FullPath) Then
    Begin
      FLastError := 'File not found: ' + FullPath;
      Exit;
    End;
  Try
    FS := TFileStream.Create(FullPath, fmOpenRead Or fmShareDenyNone);
    Try
      If FS.Size > GitPreviewByteLimit Then
        Begin
          FLastError := 'Preview exceeds 8 MiB limit';
          Exit;
        End;
      If FS.Size > 0 Then Stream.CopyFrom(FS, FS.Size);
      Result := True;
    Finally
      FS.Free;
    End;
  Except
    On E: Exception Do
      FLastError := 'Could not read file: ' + E.Message;
  End;
End;

Function TGitService.ReadBlobBytes(Const Sha, Path: String; Staged: Boolean; Stream: TStream): Boolean;
Var
  ExitCode: Integer;
  Spec: String;
  PreviousLimit: Int64;
Begin
  Result := False;
  If (Path = '') Or (Stream = Nil) Then Exit;
  If (Sha = '') And Not Staged Then Exit(ReadWorkingTreeBytes(Path, Stream));
  Spec := Sha + ':' + Path;
  If BlobByteSize(Spec) > GitPreviewByteLimit Then
    Begin
      FLastError := 'Preview exceeds 8 MiB limit';
      Exit;
    End;
  PreviousLimit := FOutputLimit; FOutputLimit := GitPreviewByteLimit;
  Try
    Result := RunGitBinary(['show', Spec], Stream, ExitCode);
    If Not Result Then Stream.Size := 0;
  Finally FOutputLimit := PreviousLimit; End;
End;

Function TGitService.BlobByteSize(Const Spec: String): Int64;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := 0;
  If Spec = '' Then
    Exit;
  If RunGit(['cat-file', '-s', Spec], OutputText, ExitCode) Then
    Result := StrToInt64Def(Trim(OutputText), 0);
End;

Function TGitService.DiffContextLines(Const Path, Sha: String; Staged: Boolean): Integer;
Var
  Spec: String;
  ByteSize: Int64;
  FullPath: String;
Const
  EmbedLimit = 262144;
  NormalContext = 50;
  LargeContext = 3;
Begin
  Result := NormalContext;
  ByteSize := 0;
  If Sha <> '' Then
    Begin
      Spec := Sha + ':' + StringReplace(Path, '\', '/', [rfReplaceAll]);
      ByteSize := BlobByteSize(Spec);
    End
  Else If Staged Then
    ByteSize := BlobByteSize(':' + StringReplace(Path, '\', '/', [rfReplaceAll]))
  Else
    Begin
      FullPath := WorkingTreeFullPath(Path);
      If (FullPath <> '') And FileExists(FullPath) Then
        ByteSize := FileSizeUtf8(FullPath);
    End;
  If ByteSize > EmbedLimit Then
    Result := LargeContext;
End;

Function TGitService.DiffPath(Const Path: String; Staged: Boolean; Out DiffText: String): Boolean;
Var
  PreviousLimit: Int64;
  ExitCode: Integer;
  ContextFlag: String;
Begin
  PreviousLimit := FOutputLimit; FOutputLimit := GitPreviewByteLimit;
  Try
  DiffText := '';
  Result := False;
  If Path = '' Then
    Exit;
  ContextFlag := '-U' + IntToStr(DiffContextLines(Path, '', Staged));
  If Staged Then
    Result := RunGit(['diff', '--no-color', '--no-ext-diff', '--no-textconv', '--cached', ContextFlag, '--', Path], DiffText, ExitCode)
  Else
    Begin
      Result := RunGit(['diff', '--no-color', '--no-ext-diff', '--no-textconv', ContextFlag, '--', Path], DiffText, ExitCode);
      { Empty worktree diff: only synthesise "new file" for untracked paths.
        Clean tracked files must stay empty so the UI can show plain content. }
      If Result And (Trim(DiffText) = '') And (Not IsPathTracked(Path)) Then
        Begin
          Result := RunGit(['diff', '--no-color', '--no-ext-diff', '--no-textconv', '--no-index', ContextFlag, '--',
            {$IFDEF WINDOWS}'NUL'{$ELSE}'/dev/null'{$ENDIF}, Path], DiffText, ExitCode);
          { Exit 1 means files differ; diagnostics and other failures are not a diff. }
          If (ExitCode = 1) And (FLastCommand.ErrorText = '') And
            (DiffText <> '') And Not IsCancelled And (FLastError <> 'Timed out') Then
            Begin
              Result := True;
              FLastError := '';
            End;
        End;
    End;

  Finally
    FOutputLimit := PreviousLimit;
    If Not Result Then DiffText := '';
  End;
End;

Function TGitService.DiffStaged(Out DiffText: String): Boolean;
Var
  PreviousLimit: Int64;
  ExitCode: Integer;
Begin
  PreviousLimit := FOutputLimit; FOutputLimit := GitPreviewByteLimit;
  Try
  DiffText := '';
  { Exit 0 with empty body is a valid "nothing staged" result. }
  Result := RunGit(['diff', '--cached', '--stat', '-p', '--no-color'], DiffText, ExitCode);

  Finally
    FOutputLimit := PreviousLimit;
    If Not Result Then DiffText := '';
  End;
End;

Function TGitService.StatusSummaryForCommit(Out SummaryText: String): Boolean;
Var
  ExitCode: Integer;
  Raw: String;
  Lines: TStringList;
  I, Limit: Integer;
Begin
  SummaryText := '';
  Result := RunGit(['status', '--short'], Raw, ExitCode);
  If Not Result Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := Raw;
    Limit := Lines.Count;
    If Limit > 40 Then
      Limit := 40;
    For I := 0 To Limit - 1 Do
      If Trim(Lines[I]) <> '' Then
        Begin
          If SummaryText <> '' Then
            SummaryText := SummaryText + LineEnding;
          SummaryText := SummaryText + Lines[I];
        End;
    If Lines.Count > Limit Then
      SummaryText := SummaryText + LineEnding +
        Format('… and %d more path(s)', [Lines.Count - Limit]);
  Finally
    Lines.Free;
  End;
  Result := True;
End;

Function TGitService.ApplyPatchToIndex(Const PatchText: String; Reverse: Boolean): Boolean;
Var
  TempName, Payload, OutputText: String;
  Stream: TFileStream;
  Args: Array Of String;
  ExitCode: Integer;
Begin
  Result := False;
  Args := Nil;
  If Trim(PatchText) = '' Then
    Begin
      FLastError := 'Empty patch';
      Exit;
    End;
  TempName := SysUtils.GetTempFileName(GetTempDir, 'lazgit-partial-');
  If TempName = '' Then
    Begin
      FLastError := 'Could not create temporary patch file';
      Exit;
    End;
  Payload := PatchText;
  If Payload[Length(Payload)] <> #10 Then
    Payload := Payload + #10;
  Try
    Stream := TFileStream.Create(TempName, fmCreate);
    Try
      Stream.WriteBuffer(Payload[1], Length(Payload));
    Finally
      Stream.Free;
    End;
  Except
    On E: Exception Do
      Begin
        FLastError := 'Could not write patch: ' + E.Message;
        If FileExists(TempName) Then
          SysUtils.DeleteFile(TempName);
        Exit;
      End;
  End;

  Try
    If Reverse Then
      Args := ['apply', '--cached', '--reverse', '--whitespace=nowarn', '--check', TempName]
    Else
      Args := ['apply', '--cached', '--whitespace=nowarn', '--check', TempName];
    Result := RunGit(Args, OutputText, ExitCode);
    If Not Result Then
      Begin
        If Trim(OutputText) <> '' Then
          FLastError := Trim(OutputText);
        Exit;
      End;
    If Reverse Then
      Args := ['apply', '--cached', '--reverse', '--whitespace=nowarn', TempName]
    Else
      Args := ['apply', '--cached', '--whitespace=nowarn', TempName];
    Result := RunGit(Args, OutputText, ExitCode);
    If Result Then
      EmitWorkingTreeChanged
    Else If Trim(OutputText) <> '' Then
      FLastError := Trim(OutputText);
  Finally
    If FileExists(TempName) Then
      SysUtils.DeleteFile(TempName);
  End;
End;

Function TGitService.CountAheadOfUpstream: Integer;
Var
  Text: String;
  ExitCode: Integer;
Begin
  Result := 0;
  If Not RunGit(['rev-list', '--count', '@{upstream}..HEAD'], Text, ExitCode) Then
    Exit;
  Result := StrToIntDef(Trim(Text), 0);
  If Result < 0 Then
    Result := 0;
End;

Procedure TGitService.BuildTransferSummary(Const Operation, Remote, OutputText: String;
  Var Summary: TGitTransferSummary);
Var
  Lines, SeenRanges, SeenCommits, RangeCommits: TStringList;
  I: Integer;
  Raw, Line, OldSha, NewSha: String;
  Total, NewRefs: Integer;
  UpToDate: Boolean;
  Flag: Char;

  Function IsHexChar(C: Char): Boolean;
  Begin
    Result := (C In ['0'..'9', 'a'..'f', 'A'..'F']);
  End;

  Function ExtractShaRange(Const S: String; Out LeftSha, RightSha: String): Boolean;
  Var
    DotPos, L, R: Integer;
  Begin
    Result := False;
    LeftSha := '';
    RightSha := '';
    DotPos := Pos('..', S);
    If DotPos < 2 Then
      Exit;
    L := DotPos - 1;
    While (L >= 1) And IsHexChar(S[L]) Do
      Dec(L);
    Inc(L);
    R := DotPos + 2;
    While (R <= Length(S)) And IsHexChar(S[R]) Do
      Inc(R);
    LeftSha := Copy(S, L, DotPos - L);
    RightSha := Copy(S, DotPos + 2, R - (DotPos + 2));
    { Reject tiny fragments that are not object ids. }
    Result := (Length(LeftSha) >= 7) And (Length(RightSha) >= 7);
  End;

  Function SameAbbreviatedSha(Const A, B: String): Boolean;
  Var
    Left, Right: String;
  Begin
    Left := LowerCase(A);
    Right := LowerCase(B);
    If Length(Left) > Length(Right) Then
      Result := Copy(Left, 1, Length(Right)) = Right
    Else
      Result := Copy(Right, 1, Length(Left)) = Left;
  End;

  Function RangeLeft(Const Spec: String): String;
  Begin
    Result := Copy(Spec, 1, Pos('..', Spec) - 1);
  End;

  Procedure RememberRange(Const LeftSha, RightSha: String);
  Var
    J, DotPos: Integer;
    ExistingLeft, ExistingRight: String;
  Begin
    For J := 0 To SeenRanges.Count - 1 Do
      Begin
        DotPos := Pos('..', SeenRanges[J]);
        ExistingLeft := Copy(SeenRanges[J], 1, DotPos - 1);
        ExistingRight := Copy(SeenRanges[J], DotPos + 2, MaxInt);
        { The same range may be printed twice, or once with a shorter object id. }
        If SameAbbreviatedSha(ExistingLeft, LeftSha) And SameAbbreviatedSha(ExistingRight, RightSha) Then
          Begin
            If Length(LeftSha) > Length(ExistingLeft) Then
              ExistingLeft := LowerCase(LeftSha);
            If Length(RightSha) > Length(ExistingRight) Then
              ExistingRight := LowerCase(RightSha);
            SeenRanges[J] := ExistingLeft + '..' + ExistingRight;
            Exit;
          End;
      End;
    SeenRanges.Add(LowerCase(LeftSha) + '..' + LowerCase(RightSha));
  End;

  Procedure AddUniqueCommits(Const CommitText: String);
  Var
    J: Integer;
    CommitSha: String;
  Begin
    RangeCommits.Text := CommitText;
    For J := 0 To RangeCommits.Count - 1 Do
      Begin
        CommitSha := Trim(RangeCommits[J]);
        If (CommitSha <> '') And (SeenCommits.IndexOf(CommitSha) < 0) Then
          Begin
            SeenCommits.Add(CommitSha);
            Inc(Total);
          End;
      End;
  End;

  Procedure CountRangesSeparately;
  Var
    J, Code: Integer;
    CommitText: String;
  Begin
    For J := 0 To SeenRanges.Count - 1 Do
      If RunGit(['rev-list', SeenRanges[J]], CommitText, Code) Then
        AddUniqueCommits(CommitText)
      Else
        Inc(Total);
  End;

  Function RangesShareExcludedTip: Boolean;
  Var
    J: Integer;
    First: String;
  Begin
    Result := True;
    If SeenRanges.Count <= 1 Then
      Exit;
    First := RangeLeft(SeenRanges[0]);
    For J := 1 To SeenRanges.Count - 1 Do
      If Not SameAbbreviatedSha(First, RangeLeft(SeenRanges[J])) Then
        Exit(False);
  End;

  Procedure CountCollectedRanges;
  Var
    Args: Array Of String;
    J, Code: Integer;
    CommitText: String;
  Begin
    Args := Nil;
    If SeenRanges.Count = 0 Then
      Exit;
    { rev-list of several A..B specs excludes every left tip from the whole walk.
      That is the union when the ranges share one excluded tip. Different bases
      would drop commits that belong only to the wider range, so those stay on
      the per-range path. A failed combined call uses that path too, so one bad
      spec does not zero the count. }
    If Not RangesShareExcludedTip Then
      Begin
        CountRangesSeparately;
        Exit;
      End;
    SetLength(Args, SeenRanges.Count + 1);
    Args[0] := 'rev-list';
    For J := 0 To SeenRanges.Count - 1 Do
      Args[J + 1] := SeenRanges[J];
    If RunGit(Args, CommitText, Code) Then
      AddUniqueCommits(CommitText)
    Else
      CountRangesSeparately;
  End;

  Procedure AddRangeFrom(Const S: String; CountEvenIfMissing: Boolean);
  Begin
    If ExtractShaRange(S, OldSha, NewSha) Then
      RememberRange(OldSha, NewSha)
    Else If CountEvenIfMissing Then
      Inc(Total);
  End;

  Procedure AssignTransferMessage(Const Action, IdleText: String);
  Begin
    If Summary.UpToDate Then
      Summary.Message := Format('%s complete.' + LineEnding + '%s', [Action, IdleText])
    Else If (Total > 0) Or (NewRefs > 0) Then
      Begin
        Summary.Message := Format('%s complete.' + LineEnding + '%d commit(s) transferred.',
          [Action, Total]);
        If NewRefs > 0 Then
          Summary.Message := Summary.Message + LineEnding +
            Format('%d new branch/tag reference(s).', [NewRefs]);
      End
    Else
      Summary.Message := Format('%s complete.', [Action]);
  End;

Begin
  Summary.Remote := Remote;
  Summary.CommitCount := 0;
  Summary.NewRefs := 0;
  Summary.UpToDate := False;
  Summary.Message := '';
  Total := 0;
  NewRefs := 0;
  UpToDate := False;

  Lines := TStringList.Create;
  SeenRanges := TStringList.Create;
  SeenCommits := TStringList.Create;
  RangeCommits := TStringList.Create;
  Try
    SeenCommits.Sorted := True;
    Lines.Text := OutputText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Raw := Lines[I];
        { Porcelain is flag + TAB + fields. Do not Trim first: a fast-forward is
          flagged with a leading space, which Trim would discard. }
        If (Length(Raw) >= 2) And (Raw[2] = #9) Then
          Begin
            Flag := Raw[1];
            Case Flag Of
              '=':
                UpToDate := True;
              '*':
                Inc(NewRefs);
              ' ', '+':
                AddRangeFrom(Raw, True);
            Else
              AddRangeFrom(Raw, False);
            End;
            Continue;
          End;

        Line := Trim(Raw);
        If (Line = '') Or (Line[1] = '#') Or SameText(Line, 'Done') Then
          Continue;

        If (Pos('Already up to date', Line) > 0) Or
           (Pos('Already up-to-date', Line) > 0) Or
           (Pos('Everything up-to-date', Line) > 0) Then
          Begin
            UpToDate := True;
            Continue;
          End;

        If (Pos('[new branch]', Line) > 0) Or (Pos('[new tag]', Line) > 0) Or
           (Pos('[new ref]', Line) > 0) Then
          Begin
            { The text after "->" is a ref name, not old..new. Counting that
              ref would be the whole reachable history. }
            Inc(NewRefs);
            Continue;
          End;

        AddRangeFrom(Line, False);
      End;
    CountCollectedRanges;
  Finally
    RangeCommits.Free;
    SeenCommits.Free;
    SeenRanges.Free;
    Lines.Free;
  End;

  Summary.CommitCount := Total;
  Summary.NewRefs := NewRefs;
  { Only claim up-to-date when git said so. Empty/unparsed output used to look
    like a successful no-op even when commits were actually pushed. }
  Summary.UpToDate := UpToDate And (Total = 0) And (NewRefs = 0);

  AssignTransferMessage(Operation + ' from ' + Remote, 'Already up to date.');
  If SameText(Operation, 'Push') Then
    AssignTransferMessage('Push to ' + Remote, 'Everything up to date.');
End;

Procedure ClearTransferSummary(Out Summary: TGitTransferSummary);
Begin
  Summary := Default(TGitTransferSummary);
End;

Function TGitService.AcceptTransferRemote(Const Operation, Remote: String; Out RemoteName: String;
  Out Summary: TGitTransferSummary): Boolean;
Begin
  ClearTransferSummary(Summary);
  If Remote = '' Then
    RemoteName := 'origin'
  Else
    RemoteName := Trim(Remote);
  Result := GitNameIsSafe(RemoteName);
  If Result Then
    Exit;
  FLastError := 'Remote name was rejected';
  Summary.Message := Operation + ' failed: ' + FLastError;
End;

Function TGitService.AcceptTransferBranch(Const Operation, Branch: String; Out BranchName: String;
  Out Summary: TGitTransferSummary): Boolean;
Begin
  BranchName := Trim(Branch);
  Result := (BranchName = '') Or GitNameIsSafe(BranchName);
  If Result Then
    Exit;
  FLastError := 'Branch name was rejected';
  Summary.Message := Operation + ' failed: ' + FLastError;
End;

Procedure TGitService.RestoreTransferCommand(Const OperationError: String;
  Const OperationResult: TGitCommandResult);
Begin
  FLastError := OperationError;
  FLastCommand := OperationResult;
End;

Function TGitService.Fetch(Out Summary: TGitTransferSummary; Const Remote: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  RemoteName, OperationError: String;
  OperationResult: TGitCommandResult;
Begin
  Result := False;
  If Not AcceptTransferRemote('Fetch', Remote, RemoteName, Summary) Then
    Exit;
  { '--' stops option parsing if a later edit drops the name check. }
  Result := RunGit(['fetch', '--', RemoteName], OutputText, ExitCode, True);
  OperationError := FLastError;
  OperationResult := FLastCommand;
  BuildTransferSummary('Fetch', RemoteName, OutputText, Summary);
  If Result Then
    EmitRemoteUpdated(RemoteName)
  Else
    Summary.Message := 'Fetch failed: ' + OperationError;
  RestoreTransferCommand(OperationError, OperationResult);
End;

Function TGitService.Pull(Out Summary: TGitTransferSummary; Const Remote: String;
  Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
  RemoteName, BranchName, OperationError: String;
  OperationResult: TGitCommandResult;
Begin
  Result := False;
  If Not AcceptTransferRemote('Pull', Remote, RemoteName, Summary) Then
    Exit;
  If Not AcceptTransferBranch('Pull', Branch, BranchName, Summary) Then
    Exit;
  If BranchName = '' Then
    Args := ['pull', '--', RemoteName]
  Else
    Args := ['pull', '--', RemoteName, BranchName];
  Result := RunGit(Args, OutputText, ExitCode, True);
  OperationError := FLastError;
  OperationResult := FLastCommand;
  BuildTransferSummary('Pull', RemoteName, OutputText, Summary);
  If Result Then
    EmitWorkingTreeChanged
  Else
    Summary.Message := 'Pull failed: ' + OperationError;
  RestoreTransferCommand(OperationError, OperationResult);
End;

Function TGitService.Push(Out Summary: TGitTransferSummary; Const Remote: String;
  Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode, Ahead: Integer;
  Args: Array Of String;
  RemoteName, BranchName, OperationError: String;
  OperationResult: TGitCommandResult;
Begin
  Result := False;
  If Not AcceptTransferRemote('Push', Remote, RemoteName, Summary) Then
    Exit;
  If Not AcceptTransferBranch('Push', Branch, BranchName, Summary) Then
    Exit;
  { Porcelain is machine-readable. Push HEAD of this work tree, not a guessed branch.
    '--' ends options before the remote and refspec. }
  If BranchName = '' Then
    Args := ['push', '--porcelain', '--', RemoteName, 'HEAD']
  Else
    Args := ['push', '--porcelain', '--', RemoteName, BranchName];
  Result := RunGit(Args, OutputText, ExitCode, True);
  OperationError := FLastError;
  OperationResult := FLastCommand;
  BuildTransferSummary('Push', RemoteName, OutputText, Summary);
  If Result Then
    Begin
      Ahead := CountAheadOfUpstream;
      If Ahead > 0 Then
        Begin
          Summary.UpToDate := False;
          If Summary.CommitCount < Ahead Then
            Summary.CommitCount := Ahead;
          Summary.Message := Format('Push to %s complete.' + LineEnding +
            'This branch is still %d commit(s) ahead of its upstream.', [RemoteName, Ahead]);
        End;
    End
  Else
    Summary.Message := 'Push failed: ' + OperationError;
  RestoreTransferCommand(OperationError, OperationResult);
End;

Function TGitService.InitRepository(Const Path: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Dir: String;
Begin
  Result := False;
  Dir := ExpandFileName(Path);
  If Dir = '' Then
    Exit;
  If Not DirectoryExists(Dir) Then
    Begin
      FLastError := 'Init path does not exist: ' + Dir;
      WorkflowLogger.Error('GitService', FLastError);
      Exit;
    End;
  If DirectoryExists(IncludeTrailingPathDelimiter(Dir) + '.git') Or
     FileExists(IncludeTrailingPathDelimiter(Dir) + '.git') Then
    Begin
      WorkflowLogger.Warning('GitService', 'Already a Git repository: ' + Dir);
      FRepoPath := Dir;
      Result := True;
      Exit;
    End;
  Result := RunGitEx(Dir, ['init'], OutputText, ExitCode);
  If Result Then
    Begin
      FRepoPath := Dir;
      WorkflowLogger.Info('GitService', 'Initialised repository at ' + Dir);
      EmitRepositoryStateChanged(Dir, grsClean);
    End;
End;

Function TGitService.CloneRepository(Const RemoteUrl, TargetDir: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  ParentDir, Url, Dest, Rejection: String;
Begin
  Result := False;
  If GitCloneUrlRejection(RemoteUrl, Rejection) Then
    Begin
      { Do not log RemoteUrl. A rejected value may be a Git option, not a URL. }
      FLastError := Rejection;
      Exit;
    End;
  Url := Trim(RemoteUrl);
  Dest := ExpandFileName(TargetDir);
  If Dest = '' Then
    Begin
      FLastError := 'Target directory is empty';
      Exit;
    End;
  ParentDir := ExtractFileDir(ExcludeTrailingPathDelimiter(Dest));
  If (ParentDir <> '') And (Not DirectoryExists(ParentDir)) Then
    Begin
      FLastError := 'Parent folder does not exist: ' + ParentDir;
      Exit;
    End;
  If DirectoryExists(Dest) And (Not DirectoryIsEmpty(Dest)) Then
    Begin
      FLastError := 'Target folder already exists and is not empty: ' + Dest;
      Exit;
    End;
  { git clone runs with cwd = parent; last arg is target folder name/path.
    '--' stops option parsing so a URL cannot be --upload-pack=... if a caller skips the check. }
  If ParentDir = '' Then
    ParentDir := GetCurrentDir;
  Result := RunGitEx(ParentDir, ['clone', '--', Url, Dest], OutputText, ExitCode);
  If Result Then
    Begin
      FRepoPath := Dest;
      WorkflowLogger.Info('GitService', 'Cloned ' + Url + ' into ' + Dest);
      EmitRepositoryStateChanged(Dest, grsClean);
    End
  Else If Trim(OutputText) <> '' Then
    FLastError := Trim(OutputText);
End;

Function TGitService.SnapshotRemotes(Out Snapshot: TGitRemoteSnapshot): Boolean;
Var Code: Integer; Path: String; Stream: TFileStream;
Begin
  Snapshot := Default(TGitRemoteSnapshot);
  Result := False;
  If Not RunGit(['rev-parse', '--git-path', 'config'], Path, Code) Then Exit;
  Path := Trim(Path);
  If Not FilenameIsAbsolute(Path) Then Path := IncludeTrailingPathDelimiter(FRepoPath) + Path;
  Path := GetPhysicalFilename(Path, pfeEmpty);
  If Path = '' Then
    Begin
      FLastError := 'Could not resolve repository config';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
    Try
      SetLength(Snapshot.ConfigText, Stream.Size);
      If Stream.Size > 0 Then Stream.ReadBuffer(Snapshot.ConfigText[1], Stream.Size);
    Finally Stream.Free; End;
  Except On E: Exception Do
  Begin
    FLastError := E.Message;
    Exit;
  End;
  End;
  If Not RunGit(['for-each-ref', '--format=%(refname) %(objectname) %(symref)', 'refs/remotes/'], Snapshot.RefsText, Code) Then Exit;
  Snapshot.RepoPath := FRepoPath; Snapshot.ConfigPath := Path; Result := True;
End;

Function TGitService.RestoreRemotes(Const Snapshot: TGitRemoteSnapshot): Boolean;
Var
  LockPath, Text, Name, Sha, Target, Errors: String;
  Handle: THandle;
  Stream: THandleStream;
  Current, Original, OriginalRefNames: TStringList;
  I, P, Code: Integer;
  {$IFDEF UNIX}Info: Stat;{$ENDIF}
  Procedure RecordFailure;
  Begin
    Errors := Errors + FLastError + LineEnding;
  End;
Begin
  Result := False;
  If (Snapshot.ConfigPath = '') Or (CompareFilenames(Snapshot.RepoPath, FRepoPath) <> 0) Then
    Begin
      FLastError := 'Remote snapshot belongs to another repository';
      Exit;
    End;
  LockPath := Snapshot.ConfigPath + '.lock';
  {$IFDEF UNIX}
  Handle := fpOpen(PChar(LockPath), O_WRONLY Or O_CREAT Or O_EXCL, &600);
  {$ELSE}
  Handle := Windows.CreateFile(PChar(LockPath), GENERIC_WRITE, 0, Nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  {$ENDIF}
  If Handle = THandle(-1) Then
    Begin
      FLastError := 'Could not lock config for remote rollback: ' + SysErrorMessage(GetLastOSError);
      Exit;
    End;
  Try
    Try
      Stream := THandleStream.Create(Handle);
      Try
        If Snapshot.ConfigText <> '' Then Stream.WriteBuffer(Snapshot.ConfigText[1], Length(Snapshot.ConfigText));
      Finally Stream.Free; FileClose(Handle); End;
      {$IFDEF UNIX}
      If fpStat(PChar(Snapshot.ConfigPath), Info) = 0 Then fpChmod(PChar(LockPath), Info.st_mode And &777);
      If Not RenameFile(LockPath, Snapshot.ConfigPath) Then Raise Exception.Create('Could not restore repository config');
      {$ELSE}
      If Not MoveFileEx(PChar(LockPath), PChar(Snapshot.ConfigPath), MOVEFILE_REPLACE_EXISTING Or MOVEFILE_WRITE_THROUGH) Then
        Raise Exception.Create('Could not restore repository config');
      {$ENDIF}
    Except On E: Exception Do
    Begin
      FLastError := E.Message;
      Exit;
    End;
    End;
  Finally
    If FileExists(LockPath) Then SysUtils.DeleteFile(LockPath);
  End;
  Current := TStringList.Create; Original := TStringList.Create;
  OriginalRefNames := TStringList.Create; OriginalRefNames.CaseSensitive := True;
  Errors := '';
  Try
    Original.Text := Snapshot.RefsText;
    For I := 0 To Original.Count - 1 Do
      OriginalRefNames.Add(Copy(Original[I], 1, Pos(' ', Original[I]) - 1));
    If Not RunGit(['for-each-ref', '--format=%(refname)', 'refs/remotes/'], Text, Code) Then Exit;
    Current.Text := Text;
    For I := 0 To Current.Count - 1 Do
      Begin
        Name := Current[I];
        { Reference names contain no spaces/newlines. Snapshot lines include a
          trailing space after the name, so prefix matching is unambiguous. }
        If OriginalRefNames.IndexOf(Name) < 0 Then
          If Not RunGit(['update-ref', '--no-deref', '-d', Name], Text, Code) Then RecordFailure;
      End;
    For I := 0 To Original.Count - 1 Do
      Begin
        Text := Original[I]; P := Pos(' ', Text);
        Name := Copy(Text, 1, P - 1); Delete(Text, 1, P);
        P := Pos(' ', Text); Sha := Copy(Text, 1, P - 1); Target := Copy(Text, P + 1, MaxInt);
        If Target <> '' Then
          Begin
            If Not RunGit(['symbolic-ref', Name, Target], Text, Code) Then RecordFailure;
          End
        Else If Not RunGit(['update-ref', '--no-deref', Name, Sha], Text, Code) Then RecordFailure;
      End;
    Result := Errors = '';
    FLastError := Trim(Errors);
  Finally OriginalRefNames.Free; Current.Free; Original.Free; End;
End;

Function TGitService.ListRemotes(Out Names, Urls: TStringList): Boolean;
Var
  OutputText, Line, Name, Url: String;
  ExitCode, I, TabPos: Integer;
  Lines: TStringList;
Begin
  Result := False;
  Names := TStringList.Create;
  Urls := TStringList.Create;

  If Not RunGit(['remote', '-v'], OutputText, ExitCode) Then
    Exit;

  Lines := TStringList.Create;
  Try
    Lines.Text := OutputText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If Line = '' Then
          Continue;
        { name\turl (fetch|push) – keep one row per remote (fetch). }
        If Pos('(push)', Line) > 0 Then
          Continue;
        TabPos := Pos(#9, Line);
        If TabPos = 0 Then
          TabPos := Pos(' ', Line);
        If TabPos = 0 Then
          Continue;
        Name := Copy(Line, 1, TabPos - 1);
        Url := Trim(Copy(Line, TabPos + 1, MaxInt));
        If Pos(' (', Url) > 0 Then
          Url := Trim(Copy(Url, 1, Pos(' (', Url) - 1));
        If Names.IndexOf(Name) < 0 Then
          Begin
            Names.Add(Name);
            Urls.Add(Url);
          End;
      End;
  Finally
    Lines.Free;
  End;
  Result := True;
End;

Function TGitService.AddRemote(Const Name, Url: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If (Not GitNameIsSafe(Name)) Or (Trim(Url) = '') Then
    Begin
      FLastError := 'Remote name and URL are required';
      Exit;
    End;
  Result := RunGit(['remote', 'add', '--', Trim(Name), Trim(Url)], OutputText, ExitCode);
End;

Function TGitService.SetRemoteUrl(Const Name, Url: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If (Not GitNameIsSafe(Name)) Or (Trim(Url) = '') Then
    Begin
      FLastError := 'Remote name and URL are required';
      Exit;
    End;
  Result := RunGit(['remote', 'set-url', '--', Trim(Name), Trim(Url)], OutputText, ExitCode);
End;

Function TGitService.RemoveRemote(Const Name: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If Not GitNameIsSafe(Name) Then
    Exit;
  Result := RunGit(['remote', 'remove', '--', Trim(Name)], OutputText, ExitCode);
End;

Function TGitService.RenameRemote(Const OldName, NewName: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If (Not GitNameIsSafe(OldName)) Or (Not GitNameIsSafe(NewName)) Then
    Begin
      FLastError := 'Remote names are required';
      Exit;
    End;
  Result := RunGit(['remote', 'rename', '--', Trim(OldName), Trim(NewName)], OutputText, ExitCode);
End;

Function TGitService.ShowCommit(Const Sha: String; Out Text: String): Boolean;
Var
  ExitCode: Integer;
Begin
  Text := '';
  Result := False;
  If Sha = '' Then
    Exit;
  Result := RunGit(['show', '--stat', '--format=fuller', Sha], Text, ExitCode);
End;

Function TGitService.ListCommitPaths(Const Sha: String; Out Paths: TStringList): Boolean;
Var
  Text, Rel: String;
  ExitCode, Cursor: Integer;
Begin
  Paths := TStringList.Create;
  Paths.Duplicates := dupIgnore;
  Paths.Sorted := False;
  Result := False;
  Text := '';
  If Sha = '' Then
    Exit;
  { diff-tree vs first parent (and --root for the initial commit). git show uses a
    combined merge diff, which is empty for a clean merge. }
  If Not RunGit(['-c', 'core.quotePath=false', 'diff-tree', '--no-commit-id', '--name-only',
    '-r', '-z', '--root', '--diff-merges=first-parent', Sha], Text, ExitCode) Then
    Exit;
  Cursor := 1;
  While Cursor <= Length(Text) Do
    Begin
      Rel := NextNulField(Text, Cursor);
      If Rel <> '' Then
        Paths.Add(Rel);
    End;
  Result := True;
End;

Function TGitService.ShowCommitPathDiff(Const Sha, Path: String; Out DiffText: String): Boolean;
Var
  PreviousLimit: Int64;
  ExitCode: Integer;
Begin
  PreviousLimit := FOutputLimit; FOutputLimit := GitPreviewByteLimit;
  Try
  DiffText := '';
  Result := False;
  If (Sha = '') Or (Path = '') Then
    Exit;
  Result := RunGit(['diff-tree', '--root', '--diff-merges=first-parent', '--no-commit-id',
    '--no-color', '--no-ext-diff', '--no-textconv', '-p', '--find-renames',
    '-U' + IntToStr(DiffContextLines(Path, Sha, False)), Sha, '--', Path], DiffText, ExitCode);
  Finally
    FOutputLimit := PreviousLimit;
    If Not Result Then DiffText := '';
  End;
End;

Function TGitService.Checkout(Const RefName: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If Not GitNameIsSafe(RefName) Then
    Exit;
  Result := RunGit(['checkout', RefName], OutputText, ExitCode);
  If Result Then
    EmitHeadChanged(RefName);
End;

Function TGitService.CreateBranch(Const BranchName, StartPoint: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If Not GitNameIsSafe(BranchName) Then
    Exit;
  If StartPoint = '' Then
    Result := RunGit(['branch', '--', Trim(BranchName)], OutputText, ExitCode)
  Else If Not GitNameIsSafe(StartPoint) Then
    Exit
  Else
    Result := RunGit(['branch', '--', Trim(BranchName), Trim(StartPoint)], OutputText, ExitCode);
End;

Function TGitService.GetConfigValue(Const Key: String; LocalOnly: Boolean; Out Value: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  Result := False;
  Value := '';
  If Trim(Key) = '' Then
    Begin
      FLastError := 'Config key is empty.';
      Exit;
    End;
  If LocalOnly Then
    Args := ['config', '--local', '--get', Key]
  Else
    Args := ['config', '--get', Key];
  { Exit code 1 = key not set; treat as success with empty value. }
  If RunGit(Args, OutputText, ExitCode) Then
    Begin
      Value := Trim(OutputText);
      Result := True;
    End
  Else If (ExitCode = 1) And Not IsCancelled And
    (FLastError <> 'Timed out') And (FLastCommand.ErrorText = '') Then
    Begin
      Value := '';
      FLastError := '';
      Result := True;
    End;
End;

Function TGitService.UnsetConfigValue(Const Key: String; LocalOnly: Boolean): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  Result := False;
  If Trim(Key) = '' Then
    Begin
      FLastError := 'Config key is empty.';
      Exit;
    End;
  If LocalOnly Then
    Args := ['config', '--local', '--unset', Key]
  Else
    Args := ['config', '--global', '--unset', Key];
  If RunGit(Args, OutputText, ExitCode) Then
    Result := True
  Else If ((ExitCode = 5) Or (ExitCode = 1)) And Not IsCancelled And
    (FLastError <> 'Timed out') And (FLastCommand.ErrorText = '') Then
    Begin
      { Key was not set — already unset. }
      FLastError := '';
      Result := True;
    End;
End;

Function TGitService.SetConfigValue(Const Key, Value: String; LocalOnly: Boolean): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
  Trimmed: String;
Begin
  Result := False;
  If Trim(Key) = '' Then
    Begin
      FLastError := 'Config key is empty.';
      Exit;
    End;
  Trimmed := Trim(Value);
  If Trimmed = '' Then
    Begin
      Result := UnsetConfigValue(Key, LocalOnly);
      Exit;
    End;
  If LocalOnly Then
    Args := ['config', '--local', Key, Trimmed]
  Else
    Args := ['config', '--global', Key, Trimmed];
  Result := RunGit(Args, OutputText, ExitCode);
End;

Function TGitService.GetGitDir(Out GitDir: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Dir: String;
Begin
  Result := False;
  GitDir := '';
  If Not RunGit(['rev-parse', '--git-dir'], OutputText, ExitCode) Then
    Exit;
  Dir := Trim(OutputText);
  If Dir = '' Then
    Exit;
  If FilenameIsAbsolute(Dir) Then
    GitDir := ExpandFileName(Dir)
  Else
    GitDir := ExpandFileName(IncludeTrailingPathDelimiter(FRepoPath) + Dir);
  Result := DirectoryExists(GitDir) Or FileExists(GitDir);
  If Not Result Then
    FLastError := 'Git directory not found: ' + GitDir;
End;

Function TGitService.GetDescription(Out Description: String): Boolean;
Var
  GitDir, Path: String;
  SL: TStringList;
Begin
  Result := False;
  Description := '';
  If Not GetGitDir(GitDir) Then
    Exit;
  Path := IncludeTrailingPathDelimiter(GitDir) + 'description';
  If Not FileExists(Path) Then
    Begin
      Description := '';
      Result := True;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Path);
      Description := SL.Text;
      { Trim one trailing line ending for editor comfort. }
      While (Length(Description) > 0) And
        ((Description[Length(Description)] = #10) Or (Description[Length(Description)] = #13)) Do
        SetLength(Description, Length(Description) - 1);
      Result := True;
    Except
      On E: Exception Do
        FLastError := 'Failed to read description: ' + E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function TGitService.SetDescription(Const Description: String): Boolean;
Var
  GitDir, Path: String;
  SL: TStringList;
  Body: String;
Begin
  Result := False;
  If Not GetGitDir(GitDir) Then
    Exit;
  Path := IncludeTrailingPathDelimiter(GitDir) + 'description';
  Body := Description;
  { Ensure a trailing newline like stock git description files. }
  If (Body <> '') And (Body[Length(Body)] <> #10) Then
    Body := Body + LineEnding;
  SL := TStringList.Create;
  Try
    Try
      SL.Text := Body;
      SL.SaveToFile(Path);
      Result := True;
      FLastError := '';
    Except
      On E: Exception Do
        FLastError := 'Failed to write description: ' + E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Initialization

GitClient := TGitService.Create;

Finalization

FreeAndNil(GitClient);

End.
