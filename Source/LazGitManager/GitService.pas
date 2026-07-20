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
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Function DetectRepository(Const StartPath: String): String;
    Function IsRepository(Const Path: String): Boolean;
    Function GetHeadSha(Out Sha: String): Boolean;
    Function GetCurrentBranch(Out Branch: String): Boolean;
    Function GetStatus(Out Clean: Boolean; Out Porcelain: String): Boolean;
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

Function TGitService.RunGit(Const Args: Array Of String; Out OutputText: String;
  Out ExitCode: Integer): Boolean;
Var
  Proc: TProcess;
  I: Integer;
  OutputLines: TStringList;
Begin
  Result := False;
  OutputText := '';
  ExitCode := -1;
  If FRepoPath = '' Then
    Begin
      WorkflowLogger.Error('GitService', 'No repository path set');
      Exit;
    End;

  Proc := TProcess.Create(Nil);
  OutputLines := TStringList.Create;
  Try
    Proc.Executable := 'git';
    Proc.CurrentDirectory := FRepoPath;
    Proc.Options := [poUsePipes, poNoConsole, poWaitOnExit];
    Proc.Parameters.Clear;
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);

    Try
      Proc.Execute;
      OutputLines.LoadFromStream(Proc.Output);
      OutputText := OutputLines.Text;
      ExitCode := Proc.ExitStatus;
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
    OutputLines.Free;
    Proc.Free;
  End;
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
