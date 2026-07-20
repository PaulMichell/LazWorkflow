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
    { Fast bounded log for the graph. Safe to call from a worker thread (uses WorkDir, not shared state). }
    Function FetchLogText(Const WorkDir: String; MaxCount: Integer; Out LogText: String): Boolean;
    Function CountCommits(Const WorkDir: String; Out Total: Integer): Boolean;
    Function Fetch(Const Remote: String = 'origin'): Boolean;
    Function Pull(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
    Function Push(Const Remote: String = 'origin'; Const Branch: String = ''): Boolean;
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

Function TGitService.FetchLogText(Const WorkDir: String; MaxCount: Integer; Out LogText: String): Boolean;
Var
  ExitCode: Integer;
  Limit: String;
Begin
  LogText := '';
  If MaxCount < 1 Then
    MaxCount := 400;
  Limit := IntToStr(MaxCount);
  { Single pretty format: fixed fields, SOH separators, unix time – cheap to parse.
    --all --topo-order gives a stable graph; -n bounds cost for large repos. }
  Result := RunGitEx(WorkDir,
    ['-c', 'core.quotePath=false', 'log', '--all', '--topo-order', '-n', Limit,
     '--pretty=format:%H' + #1 + '%P' + #1 + '%s' + #1 + '%an' + #1 + '%ct' + #1 + '%D'],
    LogText, ExitCode);
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

Initialization

GitClient := TGitService.Create;

Finalization

FreeAndNil(GitClient);

End.
