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
  TGitService = Class
  Private
    FRepoPath: String;
    Function RunGit(Const Args: Array Of String; Out OutputText: String;
      Out ExitCode: Integer): Boolean;
    Function RunGitEx(Const WorkDir: String; Const Args: Array Of String;
      Out OutputText: String; Out ExitCode: Integer): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Function DetectRepository(Const StartPath: String): String;
    Function IsRepository(Const Path: String): Boolean;
    Function GetHeadSha(Out Sha: String): Boolean;
    Function GetCurrentBranch(Out Branch: String): Boolean;
    Function GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
    { Full history index (SHA + parents only). Safe from worker threads. }
    Function FetchRevListParents(Const WorkDir: String; Out RevListText: String): Boolean;
    { Detail lines for specific SHAs (subject/author/time/refs). Batched, worker-safe. }
    Function FetchCommitDetails(Const WorkDir: String; Shas: TStrings; Out DetailsText: String): Boolean;
    Function CountCommits(Const WorkDir: String; Out Total: Integer): Boolean;
    Function Fetch(Const Remote: String = 'origin'): Boolean;
    Function Pull(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
    Function Push(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
    Function InitRepository(Const Path: String): Boolean;
    Function ShowCommit(Const Sha: String; Out Text: String): Boolean;
    Function Checkout(Const RefName: String): Boolean;
    Function CreateBranch(Const BranchName, StartPoint: String): Boolean;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
  End;

Var
  GitClient: TGitService;

Implementation

Constructor TGitService.Create;
Begin
  Inherited Create;
  FRepoPath := '';
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
  FillChar(Buf, SizeOf(Buf), 0);
  If WorkDir = '' Then
    Begin
      WorkflowLogger.Error('GitService', 'No repository path set');
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
        WorkflowLogger.Warning('GitService', Format('git %s exited %d', [Args[0], ExitCode]));
    Except
      On E: Exception Do
        Begin
          WorkflowLogger.Error('GitService', 'Failed to run git: ' + E.Message);
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
      WorkflowLogger.Error('GitService', 'Init path does not exist: ' + Dir);
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
