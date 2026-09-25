Program AssistantGitTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, Process, fpjson, jsonparser,
  AssistantGit, AssistantPlan, AssistantToolBroker;
Type
  TWorkspace = Class(TAssistantWorkspaceAdapter)
    Root: String; Calls: Integer;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function CanGit: Boolean; Override;
    Function RunGit(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
  End;
  TApproval = Class
    Allow: Boolean;
    Function Approve(Const Tool, Path, OldText, NewText: String): Boolean;
  End;
Function TWorkspace.Identity: String; Begin Result := Root; End;
Function TWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Begin Result := False; End;
Function TWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Begin Result := False; End;
Function TWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Begin Result := False; End;
Function TWorkspace.Describe: String; Begin Result := '{}'; End;
Function TWorkspace.CanGit: Boolean; Begin Result := True; End;
Function TWorkspace.RunGit(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin Inc(Calls); Result := RunAssistantGit(Root, Arguments, ResultText, ErrorText); End;
Function TApproval.Approve(Const Tool, Path, OldText, NewText: String): Boolean;
Begin Result := Allow; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('PASS ', Name); End;
Procedure SetupGit(Const Root: String; Const Args: Array Of String);
Var P: TProcess; I: Integer;
Begin
  P := TProcess.Create(Nil);
  Try
    P.Executable := 'git'; P.CurrentDirectory := Root; P.Options := [poWaitOnExit, poNoConsole];
    For I := 0 To High(Args) Do P.Parameters.Add(Args[I]);
    P.Execute; Check('temporary repository setup', P.ExitCode = 0);
  Finally P.Free; End;
End;
Var W: TWorkspace; B: TAssistantToolBroker; A: TApproval; G: TGuid;
  Run, Reply, Err: String; Lines: TStringList; Data: TJSONData;
Begin
  CreateGUID(G); W := TWorkspace.Create;
  W.Root := IncludeTrailingPathDelimiter(GetTempDir) + 'assistant-git-' + GUIDToString(G);
  ForceDirectories(W.Root);
  B := TAssistantToolBroker.Create(W); A := TApproval.Create;
  Try
    SetupGit(W.Root, ['init', '-q']);
    SetupGit(W.Root, ['config', 'user.name', 'Assistant Test']);
    SetupGit(W.Root, ['config', 'user.email', 'assistant-test@example.invalid']);
    SetupGit(W.Root, ['config', 'commit.gpgsign', 'false']);
    Lines := TStringList.Create;
    Try
      Lines.Text := 'requested change'; Lines.SaveToFile(W.Root + '/file with spaces.txt');
      Lines.Text := 'unrelated change'; Lines.SaveToFile(W.Root + '/unrelated.txt');
    Finally Lines.Free; End;
    Run := B.BeginRun(awsReadOnly);
    Check('Ask hides Git', Pos('lazarus_run_git', B.ToolsJson) = 0);
    Check('Ask rejects Git', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err));
    Run := B.BeginRun(awsMarkdown);
    Check('Plan hides Git', Pos('lazarus_run_git', B.ToolsJson) = 0);
    Check('Plan rejects commit', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","x"]}', Reply, Err));
    Run := B.BeginRun(awsProject);
    Data := GetJSON(B.ToolsJson); Data.Free;
    Check('Build advertises Git', Pos('lazarus_run_git', B.ToolsJson) > 0);
    B.OnApproval := @A.Approve;
    Check('denied approval never invokes Git', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err) And (W.Calls = 0));
    B.OnApproval := Nil;
    Check('status works', B.Execute(Run, 'lazarus_run_git', '{"arguments":["status","--short"]}', Reply, Err));
    Check('status sees unrelated file', Pos('unrelated.txt', Reply) > 0);
    Check('stage explicit filename with spaces', B.Execute(Run, 'lazarus_run_git', '{"arguments":["add","--","file with spaces.txt"]}', Reply, Err));
    Check('review staged diff', B.Execute(Run, 'lazarus_run_git', '{"arguments":["diff","--cached"]}', Reply, Err) And (Pos('requested change', Reply) > 0));
    Check('commit with literal shell metacharacters', B.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","Fix spaces; $(echo nope) & literal"]}', Reply, Err));
    Check('verify commit message', B.Execute(Run, 'lazarus_run_git', '{"arguments":["log","-1","--format=%s"]}', Reply, Err) And (Pos('$(echo nope)', Reply) > 0));
    Check('unrelated file remains untracked', B.Execute(Run, 'lazarus_run_git', '{"arguments":["status","--short"]}', Reply, Err) And (Pos('?? unrelated.txt', Reply) > 0));
    Check('empty commit fails with diagnostics', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","empty"]}', Reply, Err) And (Pos('exit code', Err) > 0));
    Check('reject global directory override', Not RunAssistantGit(W.Root, '{"arguments":["-C","..","status"]}', Reply, Err));
    Check('reject amend', Not RunAssistantGit(W.Root, '{"arguments":["commit","--amend","-m","x"]}', Reply, Err));
    Check('reject a commit message with no text', Not RunAssistantGit(W.Root, '{"arguments":["commit","-m"]}', Reply, Err) And
      (Pos('one -m string', Err) > 0));
    Lines := TStringList.Create;
    Try
      Lines.LoadFromFile(W.Root + '/file with spaces.txt');
      Lines.Add('second line');
      Lines.SaveToFile(W.Root + '/file with spaces.txt');
    Finally Lines.Free; End;
    Check('stage the follow-up', RunAssistantGit(W.Root, '{"arguments":["add","--","file with spaces.txt"]}', Reply, Err));
    Check('commit subject and body', RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","Subject line","-m","Body line"]}', Reply, Err));
    Check('both paragraphs are stored', RunAssistantGit(W.Root, '{"arguments":["log","-1","--format=%B"]}', Reply, Err) And
      (Pos('Subject line', Reply) > 0) And (Pos('Body line', Reply) > 0));
    Check('a successful commit is remembered for this turn', AssistantGitTurnCommitted);
    ResetAssistantGitTurn;
    Check('the turn commit flag clears', Not AssistantGitTurnCommitted);
    Check('temporary repository is detected', WorkingRootHasGitRepository(W.Root));
    Check('a directory without .git is not a repository', Not WorkingRootHasGitRepository(GetTempDir));
    Check('in progress does not complete an item', Not PlanBodyIntroducesCompletion(
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: not started'#10,
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: in progress'#10));
    Check('complete is a new completion', PlanBodyIntroducesCompletion(
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: in progress'#10,
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: complete'#10));
    Check('the same complete item is not new', Not PlanBodyIntroducesCompletion(
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: complete'#10,
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: complete'#10));
    Check('a fenced status is not a completion', Not PlanBodyIntroducesCompletion(
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: in progress'#10,
      '# T'#10#10'Generated by Lazarus Project Assistant.'#10'## 1. A'#10'### 1.1 Item'#10'Status: in progress'#10 +
      '```'#10'Status: complete'#10'```'#10));
    Check('reject destructive command', Not RunAssistantGit(W.Root, '{"arguments":["reset","--hard"]}', Reply, Err));
    Check('reject remote command', Not RunAssistantGit(W.Root, '{"arguments":["push"]}', Reply, Err));
    Check('reject path traversal', Not RunAssistantGit(W.Root, '{"arguments":["add","--","../outside"]}', Reply, Err));
    Check('reject malformed arguments', Not RunAssistantGit(W.Root, '{"arguments":[17]}', Reply, Err));
    Check('reject missing repository', Not RunAssistantGit(GetTempDir, '{"arguments":["status"]}', Reply, Err));
    B.Cancel;
    Check('cancelled run rejects Git', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err));
    WriteLn('Temporary test repository: ', W.Root);
  Finally A.Free; B.Free; W.Free; End;
End.