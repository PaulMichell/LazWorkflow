Unit GitService;

{ Git operations service – CLI primary with future libgit2 path (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Process, WorkflowEvents, WorkflowLog;

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

  TGitService = Class
  Private
    FRepoPath: String;
    FLastError: String;
    FCancelled: Boolean;
    FPublishEvents: Boolean;
    FActiveProcess: TProcess;
    FProcessLock: TRTLCriticalSection;
    FTimeoutMs: Integer;
    Procedure SetActiveProcess(Proc: TProcess);
    Procedure ClearActiveProcess;
    Function RunTimedOut(StartTick: QWord): Boolean;
    Function RunGit(Const Args: Array Of String; Out OutputText: String;
      Out ExitCode: Integer): Boolean;
    Function RunGitEx(Const WorkDir: String; Const Args: Array Of String;
      Out OutputText: String; Out ExitCode: Integer): Boolean;
    Function RunGitBinary(Const Args: Array Of String; Stream: TStream;
      Out ExitCode: Integer): Boolean;
    Function RunGitPaths(Const SubCommand: String; Const Paths: TStrings): Boolean;
    Function CountRangeCommits(Const RangeSpec: String): Integer;
    Procedure BuildTransferSummary(Const Operation, Remote, OutputText: String;
      Var Summary: TGitTransferSummary);
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
    Function GetCurrentBranch(Out Branch: String): Boolean;
    Function GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
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
    Function Commit(Const Message: String; Out NewSha: String): Boolean;
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
    Property Cancelled: Boolean Read FCancelled;
    { When False, skip WorkflowEventBus publishes (background job workers must not touch UI). }
    Property PublishEvents: Boolean Read FPublishEvents Write FPublishEvents;
    { 0 = no timeout. Checked in the drain loop so a long git can be killed. }
    Property TimeoutMs: Integer Read FTimeoutMs Write FTimeoutMs;
  End;

Function DirectoryIsEmpty(Const Dir: String): Boolean;
Function GitStatusEntryIsStaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryIsUnstaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryLabel(Const Entry: TGitStatusEntry; StagedSide: Boolean): String;

Var
  GitClient: TGitService;

Implementation

Uses
  LazFileUtils;

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
    FindClose(Rec);
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
  FCancelled := False;
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
  FCancelled := False;
End;

Function TGitService.IsCancelled: Boolean;
Begin
  Result := FCancelled;
End;

Procedure TGitService.Cancel;
Begin
  FCancelled := True;
  { Terminate under the lock so the drain loop cannot Free the process mid-call. }
  EnterCriticalSection(FProcessLock);
  Try
    If Assigned(FActiveProcess) Then
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

Function TGitService.RunGitEx(Const WorkDir: String; Const Args: Array Of String;
  Out OutputText: String; Out ExitCode: Integer): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;
  TimedOut: Boolean;
Begin
  Result := False;
  OutputText := '';
  ExitCode := -1;
  FLastError := '';
  TimedOut := False;
  StartTick := GetTickCount64;
  Buf[Low(Buf)] := 0;
  If WorkDir = '' Then
    Begin
      FLastError := 'No repository path set';
      WorkflowLogger.Error('GitService', FLastError);
      Exit;
    End;

  If IsCancelled Then
    Begin
      FLastError := 'Cancelled';
      Exit;
    End;

  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := 'git';
    Proc.CurrentDirectory := WorkDir;
    { Merge stderr so fetch/push progress lines are captured. Drain pipes without poWaitOnExit. }
    Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    Proc.Parameters.Clear;
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);

    Try
      SetActiveProcess(Proc);
      Proc.Execute;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
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
                Mem.WriteBuffer(Buf[0], BytesRead);
            End
          Else If Proc.Running Then
            Sleep(1);
        End;
      { Drain any remainder after exit. }
      While Proc.Output.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          If BytesRead > 0 Then
            Mem.WriteBuffer(Buf[0], BytesRead)
          Else
            Break;
        End;
      ExitCode := Proc.ExitStatus;
      SetLength(OutputText, Mem.Size);
      If Mem.Size > 0 Then
        Move(Mem.Memory^, OutputText[1], Mem.Size);
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
            Begin
              FLastError := Format('git %s exited %d', [Args[0], ExitCode]);
              If Trim(OutputText) <> '' Then
                FLastError := FLastError + ': ' + Trim(OutputText);
              WorkflowLogger.Warning('GitService', FLastError);
            End;
        End;
    Except
      On E: Exception Do
        Begin
          FLastError := 'Failed to run git: ' + E.Message;
          WorkflowLogger.Error('GitService', FLastError);
          Result := False;
        End;
    End;
  Finally
    ClearActiveProcess;
    Mem.Free;
    Proc.Free;
  End;
End;

Function TGitService.RunGit(Const Args: Array Of String; Out OutputText: String;
  Out ExitCode: Integer): Boolean;
Begin
  Result := RunGitEx(FRepoPath, Args, OutputText, ExitCode);
End;

Function TGitService.RunGitBinary(Const Args: Array Of String; Stream: TStream;
  Out ExitCode: Integer): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;
  TimedOut: Boolean;
Begin
  Result := False;
  ExitCode := -1;
  FLastError := '';
  TimedOut := False;
  StartTick := GetTickCount64;
  Buf[Low(Buf)] := 0;
  If (FRepoPath = '') Or (Stream = Nil) Then
    Begin
      FLastError := 'No repository path set';
      Exit;
    End;
  If IsCancelled Then
    Begin
      FLastError := 'Cancelled';
      Exit;
    End;

  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := 'git';
    Proc.CurrentDirectory := FRepoPath;
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.Parameters.Clear;
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);
    Try
      SetActiveProcess(Proc);
      Proc.Execute;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
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
                Stream.WriteBuffer(Buf[0], BytesRead);
            End
          Else If Proc.Running Then
            Sleep(1);
        End;
      While Proc.Output.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          If BytesRead > 0 Then
            Stream.WriteBuffer(Buf[0], BytesRead)
          Else
            Break;
        End;
      { Drain stderr so the process cannot block on a full pipe. }
      While Proc.Stderr.NumBytesAvailable > 0 Do
        Proc.Stderr.Read(Buf[0], SizeOf(Buf));
      ExitCode := Proc.ExitStatus;
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
            FLastError := Format('git %s exited %d', [Args[0], ExitCode]);
        End;
    Except
      On E: Exception Do
        Begin
          FLastError := 'Failed to run git: ' + E.Message;
          Result := False;
        End;
    End;
  Finally
    ClearActiveProcess;
    Proc.Free;
  End;
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

Function TGitService.ListStatus(Out Entries: TGitStatusEntryArray; IncludeUntracked: Boolean;
  IncludeIgnored: Boolean): Boolean;
Var
  Raw, Rec, Path, OldPath: String;
  ExitCode, Cursor, Count: Integer;
  X, Y: Char;
  Args: Array Of String;
Begin
  Entries := Nil;
  SetLength(Entries, 0);
  Args := Nil;
  { -z: NUL records, no quoting. Rename/copy is old path then a second NUL field. }
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

  Cursor := 1;
  Count := 0;
  While Cursor <= Length(Raw) Do
    Begin
      Rec := NextNulField(Raw, Cursor);
      If Length(Rec) < 4 Then
        Continue;
      X := Rec[1];
      Y := Rec[2];
      Path := Copy(Rec, 4, MaxInt);
      OldPath := '';
      If (X = 'R') Or (X = 'C') Or (Y = 'R') Or (Y = 'C') Then
        Begin
          OldPath := Path;
          Path := NextNulField(Raw, Cursor);
        End;
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

Function TGitService.ListTrackedFiles(Out Paths: TStringList): Boolean;
Var
  Raw, Rel, Full: String;
  ExitCode, Cursor: Integer;
Begin
  Paths := TStringList.Create;
  Paths.Sorted := True;
  Paths.Duplicates := dupIgnore;
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

Function TGitService.UnstagePaths(Paths: TStrings): Boolean;
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
  { git restore --staged -- paths  (modern); fall back handled by git version }
  SetLength(Args, 3 + Paths.Count);
  Args[0] := 'restore';
  Args[1] := '--staged';
  Args[2] := '--';
  For I := 0 To Paths.Count - 1 Do
    Args[3 + I] := Paths[I];
  Result := RunGit(Args, OutputText, ExitCode);
  If Not Result Then
    Begin
      { Older git: git reset HEAD -- paths }
      SetLength(Args, 3 + Paths.Count);
      Args[0] := 'reset';
      Args[1] := 'HEAD';
      Args[2] := '--';
      For I := 0 To Paths.Count - 1 Do
        Args[3 + I] := Paths[I];
      Result := RunGit(Args, OutputText, ExitCode);
    End;
  If Result Then
    EmitWorkingTreeChanged;
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
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := RunGit(['restore', '--staged', '.'], OutputText, ExitCode);
  If Not Result Then
    Result := RunGit(['reset', 'HEAD'], OutputText, ExitCode);
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
  IgnorePath := IncludeTrailingPathDelimiter(ExpandFileName(FRepoPath)) + '.gitignore';
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
        Lines.SaveToFile(IgnorePath);
      Result := True;
      If Changed Then
        EmitWorkingTreeChanged;
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

Function TGitService.Commit(Const Message: String; Out NewSha: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Info: TGitCommitInfo;
Begin
  NewSha := '';
  Result := False;
  If Trim(Message) = '' Then
    Begin
      FLastError := 'Commit message is empty';
      Exit;
    End;
  Result := RunGit(['commit', '-m', Message], OutputText, ExitCode);
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
  Root, Combined, Expanded: String;
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
  Result := Expanded;
End;

Function TGitService.ReadWorkingTreeFile(Const Path: String; Out Content: String): Boolean;
Var
  FullPath: String;
  List: TStringList;
Begin
  Result := False;
  Content := '';
  FullPath := WorkingTreeFullPath(Path);
  If FullPath = '' Then
    Exit;
  If Not FileExists(FullPath) Then
    Begin
      FLastError := 'File not found: ' + FullPath;
      Exit;
    End;
  List := TStringList.Create;
  Try
    Try
      List.LoadFromFile(FullPath);
      Content := List.Text;
      Result := True;
    Except
      On E: Exception Do
        FLastError := 'Could not read file: ' + E.Message;
    End;
  Finally
    List.Free;
  End;
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
      Stream.CopyFrom(FS, 0);
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
Begin
  Result := False;
  If (Path = '') Or (Stream = Nil) Then
    Exit;
  If Sha = '' Then
    Begin
      If Staged Then
        Begin
          { Indexed blob for path. }
          Spec := ':' + StringReplace(Path, '\', '/', [rfReplaceAll]);
          Result := RunGitBinary(['show', Spec], Stream, ExitCode);
        End
      Else
        Result := ReadWorkingTreeBytes(Path, Stream);
    End
  Else
    Begin
      Spec := Sha + ':' + StringReplace(Path, '\', '/', [rfReplaceAll]);
      Result := RunGitBinary(['show', Spec], Stream, ExitCode);
    End;
End;

Function TGitService.DiffPath(Const Path: String; Staged: Boolean; Out DiffText: String): Boolean;
Var
  ExitCode: Integer;
Begin
  DiffText := '';
  Result := False;
  If Path = '' Then
    Exit;
  { Large unified context embeds the whole file with +/- markers (History-style). }
  If Staged Then
    Result := RunGit(['diff', '--cached', '-U100000', '--', Path], DiffText, ExitCode)
  Else
    Begin
      Result := RunGit(['diff', '-U100000', '--', Path], DiffText, ExitCode);
      { Empty worktree diff: only synthesise "new file" for untracked paths.
        Clean tracked files must stay empty so the UI can show plain content. }
      If Result And (Trim(DiffText) = '') And (Not IsPathTracked(Path)) Then
        Begin
          Result := RunGit(['diff', '--no-index', '-U100000', '--',
            {$IFDEF WINDOWS}'NUL'{$ELSE}'/dev/null'{$ENDIF}, Path], DiffText, ExitCode);
          { git --no-index returns 1 when files differ; treat non-empty output as success. }
          If (Not Result) And (Trim(DiffText) <> '') Then
            Result := True;
        End;
    End;
  If (Not Result) And (ExitCode = 0) Then
    Result := True;
End;

Function TGitService.DiffStaged(Out DiffText: String): Boolean;
Var
  ExitCode: Integer;
Begin
  DiffText := '';
  { Exit 0 with empty body is a valid "nothing staged" result. }
  Result := RunGit(['diff', '--cached', '--stat', '-p', '--no-color'], DiffText, ExitCode);
  If (Not Result) And (ExitCode = 0) Then
    Result := True;
  If Result And (ExitCode <> 0) And (Trim(DiffText) = '') Then
    Result := False;
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
  TempName := GetTempFileName(GetTempDir, 'lazgit-partial-');
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
          DeleteFile(TempName);
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
      DeleteFile(TempName);
  End;
End;

Function TGitService.CountRangeCommits(Const RangeSpec: String): Integer;
Var
  Text: String;
  ExitCode: Integer;
Begin
  Result := 0;
  If Trim(RangeSpec) = '' Then
    Exit;
  If Not RunGit(['rev-list', '--count', RangeSpec], Text, ExitCode) Then
    Exit;
  Result := StrToIntDef(Trim(Text), 0);
  If Result < 0 Then
    Result := 0;
End;

Procedure TGitService.BuildTransferSummary(Const Operation, Remote, OutputText: String;
  Var Summary: TGitTransferSummary);
Var
  Lines: TStringList;
  I, B: Integer;
  Line, OldSha, NewSha, RangeSpec: String;
  Total, NewRefs: Integer;
  UpToDate: Boolean;

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
  Try
    Lines.Text := OutputText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If Line = '' Then
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

        If ExtractShaRange(Line, OldSha, NewSha) Then
          Begin
            { Fetch/pull: old..new is commits gained. Push uses the same form. }
            RangeSpec := OldSha + '..' + NewSha;
            B := CountRangeCommits(RangeSpec);
            If B > 0 Then
              Inc(Total, B)
            Else
              Inc(Total); { at least one update even if count fails }
          End;
      End;
  Finally
    Lines.Free;
  End;

  Summary.CommitCount := Total;
  Summary.NewRefs := NewRefs;
  Summary.UpToDate := UpToDate Or ((Total = 0) And (NewRefs = 0));

  If Summary.UpToDate And (Total = 0) And (NewRefs = 0) Then
    Summary.Message := Format('%s from %s complete.' + LineEnding + 'Already up to date.',
      [Operation, Remote])
  Else
    Begin
      Summary.Message := Format('%s from %s complete.' + LineEnding + '%d commit(s) transferred.',
        [Operation, Remote, Total]);
      If NewRefs > 0 Then
        Summary.Message := Summary.Message + LineEnding +
          Format('%d new branch/tag reference(s).', [NewRefs]);
    End;

  { Push wording: "to" rather than "from". }
  If SameText(Operation, 'Push') Then
    Begin
      If Summary.UpToDate And (Total = 0) And (NewRefs = 0) Then
        Summary.Message := Format('Push to %s complete.' + LineEnding + 'Everything up to date.', [Remote])
      Else
        Begin
          Summary.Message := Format('Push to %s complete.' + LineEnding + '%d commit(s) transferred.',
            [Remote, Total]);
          If NewRefs > 0 Then
            Summary.Message := Summary.Message + LineEnding +
              Format('%d new branch/tag reference(s).', [NewRefs]);
        End;
    End;
End;

Procedure ClearTransferSummary(Out Summary: TGitTransferSummary);
Begin
  Summary := Default(TGitTransferSummary);
End;

Function TGitService.Fetch(Out Summary: TGitTransferSummary; Const Remote: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  RemoteName: String;
Begin
  ClearTransferSummary(Summary);
  RemoteName := Remote;
  If RemoteName = '' Then
    RemoteName := 'origin';
  Result := RunGit(['fetch', RemoteName], OutputText, ExitCode);
  BuildTransferSummary('Fetch', RemoteName, OutputText, Summary);
  If Result Then
    EmitRemoteUpdated(RemoteName)
  Else
    Summary.Message := 'Fetch failed: ' + FLastError;
End;

Function TGitService.Pull(Out Summary: TGitTransferSummary; Const Remote: String;
  Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
  RemoteName: String;
Begin
  ClearTransferSummary(Summary);
  RemoteName := Remote;
  If RemoteName = '' Then
    RemoteName := 'origin';
  If Branch = '' Then
    Args := ['pull', RemoteName]
  Else
    Args := ['pull', RemoteName, Branch];
  Result := RunGit(Args, OutputText, ExitCode);
  BuildTransferSummary('Pull', RemoteName, OutputText, Summary);
  If Result Then
    EmitWorkingTreeChanged
  Else
    Summary.Message := 'Pull failed: ' + FLastError;
End;

Function TGitService.Push(Out Summary: TGitTransferSummary; Const Remote: String;
  Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
  RemoteName: String;
Begin
  ClearTransferSummary(Summary);
  RemoteName := Remote;
  If RemoteName = '' Then
    RemoteName := 'origin';
  If Branch = '' Then
    Args := ['push', RemoteName]
  Else
    Args := ['push', RemoteName, Branch];
  Result := RunGit(Args, OutputText, ExitCode);
  BuildTransferSummary('Push', RemoteName, OutputText, Summary);
  If Not Result Then
    Summary.Message := 'Push failed: ' + FLastError;
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
  If IsRepository(Dir) Then
    Begin
      WorkflowLogger.Warning('GitService', 'Already a Git repository: ' + Dir);
      FRepoPath := DetectRepository(Dir);
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
  ParentDir, Url, Dest: String;
Begin
  Result := False;
  Url := Trim(RemoteUrl);
  Dest := ExpandFileName(TargetDir);
  If Url = '' Then
    Begin
      FLastError := 'Remote URL is empty';
      Exit;
    End;
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
  { git clone runs with cwd = parent; last arg is target folder name/path. }
  If ParentDir = '' Then
    ParentDir := GetCurrentDir;
  Result := RunGitEx(ParentDir, ['clone', Url, Dest], OutputText, ExitCode);
  If Result Then
    Begin
      FRepoPath := Dest;
      WorkflowLogger.Info('GitService', 'Cloned ' + Url + ' into ' + Dest);
      EmitRepositoryStateChanged(Dest, grsClean);
    End
  Else If Trim(OutputText) <> '' Then
    FLastError := Trim(OutputText);
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
  If (Trim(Name) = '') Or (Trim(Url) = '') Then
    Begin
      FLastError := 'Remote name and URL are required';
      Exit;
    End;
  Result := RunGit(['remote', 'add', Trim(Name), Trim(Url)], OutputText, ExitCode);
End;

Function TGitService.SetRemoteUrl(Const Name, Url: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If (Trim(Name) = '') Or (Trim(Url) = '') Then
    Begin
      FLastError := 'Remote name and URL are required';
      Exit;
    End;
  Result := RunGit(['remote', 'set-url', Trim(Name), Trim(Url)], OutputText, ExitCode);
End;

Function TGitService.RemoveRemote(Const Name: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If Trim(Name) = '' Then
    Exit;
  Result := RunGit(['remote', 'remove', Trim(Name)], OutputText, ExitCode);
End;

Function TGitService.RenameRemote(Const OldName, NewName: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If (Trim(OldName) = '') Or (Trim(NewName) = '') Then
    Begin
      FLastError := 'Remote names are required';
      Exit;
    End;
  Result := RunGit(['remote', 'rename', Trim(OldName), Trim(NewName)], OutputText, ExitCode);
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
  Text: String;
  ExitCode, I: Integer;
  Lines: TStringList;
  Line: String;
Begin
  Paths := TStringList.Create;
  Paths.Duplicates := dupIgnore;
  Paths.Sorted := False;
  Result := False;
  Text := '';
  If Sha = '' Then
    Exit;
  If Not RunGit(['show', '--name-only', '--pretty=format:', Sha], Text, ExitCode) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := Text;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If Line <> '' Then
          Paths.Add(Line);
      End;
    Result := True;
  Finally
    Lines.Free;
  End;
End;

Function TGitService.ShowCommitPathDiff(Const Sha, Path: String; Out DiffText: String): Boolean;
Var
  ExitCode: Integer;
Begin
  DiffText := '';
  Result := False;
  If (Sha = '') Or (Path = '') Then
    Exit;
  { Large unified context embeds the whole file with +/- change markers. }
  Result := RunGit(['show', '-U100000', '--format=format:', '--find-renames', Sha, '--', Path], DiffText, ExitCode);
End;

Function TGitService.Checkout(Const RefName: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
  If RefName = '' Then
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
  If BranchName = '' Then
    Exit;
  If StartPoint = '' Then
    Result := RunGit(['branch', BranchName], OutputText, ExitCode)
  Else
    Result := RunGit(['branch', BranchName, StartPoint], OutputText, ExitCode);
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
  Else If ExitCode = 1 Then
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
  Else If (ExitCode = 5) Or (ExitCode = 1) Then
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
