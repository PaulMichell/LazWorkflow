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

  TGitService = Class
  Private
    FRepoPath: String;
    FLastError: String;
    Function RunGit(Const Args: Array Of String; Out OutputText: String;
      Out ExitCode: Integer): Boolean;
    Function RunGitEx(Const WorkDir: String; Const Args: Array Of String;
      Out OutputText: String; Out ExitCode: Integer): Boolean;
    Function RunGitPaths(Const SubCommand: String; Const Paths: TStrings): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Function DetectRepository(Const StartPath: String): String;
    Function IsRepository(Const Path: String): Boolean;
    Function GetHeadSha(Out Sha: String): Boolean;
    Function GetCurrentBranch(Out Branch: String): Boolean;
    Function GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
    Function ListStatus(Out Entries: TGitStatusEntryArray): Boolean;
    Function StagePaths(Paths: TStrings): Boolean;
    Function UnstagePaths(Paths: TStrings): Boolean;
    Function StageAll: Boolean;
    Function UnstageAll: Boolean;
    Function Commit(Const Message: String; Out NewSha: String): Boolean;
    Function DiffPath(Const Path: String; Staged: Boolean; Out DiffText: String): Boolean;
    { Apply a unified diff to the index (partial stage/unstage). Reverse undoes it. }
    Function ApplyPatchToIndex(Const PatchText: String; Reverse: Boolean = False): Boolean;
    { Full history index (SHA + parents only). Safe from worker threads. }
    Function FetchRevListParents(Const WorkDir: String; Out RevListText: String): Boolean;
    { Detail lines for specific SHAs (subject/author/time/refs). Batched, worker-safe. }
    Function FetchCommitDetails(Const WorkDir: String; Shas: TStrings; Out DetailsText: String): Boolean;
    Function CountCommits(Const WorkDir: String; Out Total: Integer): Boolean;
    Function Fetch(Const Remote: String = 'origin'): Boolean;
    Function Pull(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
    Function Push(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
    Function InitRepository(Const Path: String): Boolean;
    Function CloneRepository(Const RemoteUrl, TargetDir: String): Boolean;
    Function ListRemotes(Out Names, Urls: TStringList): Boolean;
    Function AddRemote(Const Name, Url: String): Boolean;
    Function SetRemoteUrl(Const Name, Url: String): Boolean;
    Function RemoveRemote(Const Name: String): Boolean;
    Function ShowCommit(Const Sha: String; Out Text: String): Boolean;
    Function Checkout(Const RefName: String): Boolean;
    Function CreateBranch(Const BranchName, StartPoint: String): Boolean;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
    Property LastError: String Read FLastError;
  End;

Function GitStatusEntryIsStaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryIsUnstaged(Const Entry: TGitStatusEntry): Boolean;
Function GitStatusEntryLabel(Const Entry: TGitStatusEntry; StagedSide: Boolean): String;

Var
  GitClient: TGitService;

Implementation

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
End;

Destructor TGitService.Destroy;
Begin
  Inherited Destroy;
End;

Function TGitService.RunGitEx(Const WorkDir: String; Const Args: Array Of String;
  Out OutputText: String; Out ExitCode: Integer): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
Begin
  Result := False;
  OutputText := '';
  ExitCode := -1;
  FLastError := '';
  FillChar(Buf, SizeOf(Buf), 0);
  If WorkDir = '' Then
    Begin
      FLastError := 'No repository path set';
      WorkflowLogger.Error('GitService', FLastError);
      Exit;
    End;

  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := 'git';
    Proc.CurrentDirectory := WorkDir;
    { No poWaitOnExit before draining pipes – avoid deadlock on large output. }
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.Parameters.Clear;
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);

    Try
      Proc.Execute;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
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
      Result := ExitCode = 0;
      If Not Result Then
        Begin
          FLastError := Format('git %s exited %d', [Args[0], ExitCode]);
          If Trim(OutputText) <> '' Then
            FLastError := FLastError + ': ' + Trim(OutputText);
          WorkflowLogger.Warning('GitService', FLastError);
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
    Mem.Free;
    Proc.Free;
  End;
End;

Function TGitService.RunGit(Const Args: Array Of String; Out OutputText: String;
  Out ExitCode: Integer): Boolean;
Begin
  Result := RunGitEx(FRepoPath, Args, OutputText, ExitCode);
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

Function TGitService.ListStatus(Out Entries: TGitStatusEntryArray): Boolean;
Var
  Raw, Line, Rest: String;
  ExitCode, I, ArrowPos, Count: Integer;
  Lines: TStringList;
  X, Y: Char;
  Path, OldPath: String;
Begin
  SetLength(Entries, 0);
  Result := RunGit(['status', '--porcelain', '--untracked-files=all'], Raw, ExitCode);
  If Not Result Then
    Exit;

  Lines := TStringList.Create;
  Try
    Lines.Text := Raw;
    Count := 0;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Length(Line) < 4 Then
          Continue;
        X := Line[1];
        Y := Line[2];
        Rest := Copy(Line, 4, MaxInt);
        { Strip optional quotes git uses for awkward paths. }
        If (Length(Rest) >= 2) And (Rest[1] = '"') And (Rest[Length(Rest)] = '"') Then
          Rest := Copy(Rest, 2, Length(Rest) - 2);
        OldPath := '';
        Path := Rest;
        ArrowPos := Pos(' -> ', Rest);
        If ArrowPos > 0 Then
          Begin
            OldPath := Copy(Rest, 1, ArrowPos - 1);
            Path := Copy(Rest, ArrowPos + 4, MaxInt);
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
  Finally
    Lines.Free;
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
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
End;

Function TGitService.UnstagePaths(Paths: TStrings): Boolean;
Var
  Args: Array Of String;
  I: Integer;
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
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
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
End;

Function TGitService.StageAll: Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := RunGit(['add', '-A'], OutputText, ExitCode);
  If Result Then
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
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
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
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
      WorkflowEventBus.NotifyCommitCreated(FRepoPath, Info);
      WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
      WorkflowEventBus.NotifyHeadChanged(FRepoPath, NewSha);
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
  If Staged Then
    Result := RunGit(['diff', '--cached', '--', Path], DiffText, ExitCode)
  Else
    Result := RunGit(['diff', '--', Path], DiffText, ExitCode);
  { Untracked files have no diff – show empty success. }
  If (Not Result) And (ExitCode = 0) Then
    Result := True;
End;

Function TGitService.ApplyPatchToIndex(Const PatchText: String; Reverse: Boolean): Boolean;
Var
  TempName: String;
  List: TStringList;
  Args: Array Of String;
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := False;
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
  List := TStringList.Create;
  Try
    List.Text := PatchText;
    { Ensure trailing newline – git apply is strict. }
    If (List.Count > 0) And (List[List.Count - 1] <> '') Then
      List.Add('');
    Try
      List.SaveToFile(TempName);
    Except
      On E: Exception Do
        Begin
          FLastError := 'Could not write patch: ' + E.Message;
          Exit;
        End;
    End;

    If Reverse Then
      Args := ['apply', '--cached', '--reverse', '--whitespace=nowarn', TempName]
    Else
      Args := ['apply', '--cached', '--whitespace=nowarn', TempName];

    Result := RunGit(Args, OutputText, ExitCode);
    If Result Then
      WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath)
    Else If Trim(OutputText) <> '' Then
      FLastError := Trim(OutputText);
  Finally
    List.Free;
    If FileExists(TempName) Then
      DeleteFile(TempName);
  End;
End;

Function TGitService.Fetch(Const Remote: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
Begin
  Result := RunGit(['fetch', Remote], OutputText, ExitCode);
  If Result Then
    WorkflowEventBus.NotifyRemoteUpdated(FRepoPath, Remote);
End;

Function TGitService.Pull(Const Remote: String; Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  If Branch = '' Then
    Args := ['pull', Remote]
  Else
    Args := ['pull', Remote, Branch];
  Result := RunGit(Args, OutputText, ExitCode);
  If Result Then
    WorkflowEventBus.NotifyWorkingTreeChanged(FRepoPath);
End;

Function TGitService.Push(Const Remote: String; Const Branch: String): Boolean;
Var
  OutputText: String;
  ExitCode: Integer;
  Args: Array Of String;
Begin
  If Branch = '' Then
    Args := ['push', Remote]
  Else
    Args := ['push', Remote, Branch];
  Result := RunGit(Args, OutputText, ExitCode);
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
      WorkflowEventBus.NotifyRepositoryStateChanged(Dir, grsClean);
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
  If DirectoryExists(Dest) Then
    Begin
      FLastError := 'Target folder already exists: ' + Dest;
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
      WorkflowEventBus.NotifyRepositoryStateChanged(Dest, grsClean);
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
    WorkflowEventBus.NotifyHeadChanged(FRepoPath, RefName);
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

Initialization

GitClient := TGitService.Create;

Finalization

FreeAndNil(GitClient);

End.
