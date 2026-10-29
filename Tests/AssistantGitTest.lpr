Program AssistantGitTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, Process, fpjson, jsonparser,
  AssistantGit, AssistantPlan, AssistantToolBroker, AssistantWorkTarget, AssistantIDEWorkspace, AssistantConversation;
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
Const
  { How a Claude turn sets a Status line: the Lazarus update_markdown, with no live window in a console test. }
  BrokerCompletion = '{"path":"Documents/Plan.md","old_text":"Status: not started","new_text":"Status: complete","open":false}';
Var W: TWorkspace; B: TAssistantToolBroker; A: TApproval; G: TGuid;
  Run, Reply, Err, Note, PlanPath, Resolved, SelectErr, Before: String;
  Lines: TStringList; Data: TJSONData; ReplaceCount, CallsBefore: Integer; Hook: TProcess;
  IDEWorkspace: TAssistantIDEWorkspace; IDEBroker: TAssistantToolBroker;

Function PlanText: String;
Var PlanLines: TStringList;
Begin
  PlanLines := TStringList.Create;
  Try PlanLines.LoadFromFile(PlanPath); Result := PlanLines.Text; Finally PlanLines.Free; End;
End;

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
    Check('inspect read status', AssistantGitInspectReadCommand('status'));
    Check('inspect read diff', AssistantGitInspectReadCommand('diff'));
    Check('inspect read log', AssistantGitInspectReadCommand('log'));
    Check('inspect read show', AssistantGitInspectReadCommand('show'));
    Check('inspect read rev-parse', AssistantGitInspectReadCommand('rev-parse'));
    Check('inspect read ls-files', AssistantGitInspectReadCommand('ls-files'));
    Check('inspect refuses add', Not AssistantGitInspectReadCommand('add'));
    Check('inspect refuses commit', Not AssistantGitInspectReadCommand('commit'));
    Check('inspect refuses push', Not AssistantGitInspectReadCommand('push'));
    Check('description allows inspect reads',
      Pos('Inspect may use status, diff, log, show, rev-parse, and ls-files only.', AssistantGitDescription) > 0);
    Check('description is not build-only', Pos('in Build mode', AssistantGitDescription) = 0);
    Run := B.BeginRun(awsReadOnly);
    Check('Ask advertises read Git', Pos('lazarus_run_git', B.ToolsJson) > 0);
    Check('Ask status works', B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err));
    Check('Ask rejects commit', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","x"]}', Reply, Err) And
      (Pos('ls-files only', Err) > 0));
    Check('Ask rejects push', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["push"]}', Reply, Err));
    Run := B.BeginRun(awsMarkdown);
    Check('Plan hides Git', Pos('lazarus_run_git', B.ToolsJson) = 0);
    Check('Plan rejects commit', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","x"]}', Reply, Err));
    Run := B.BeginRun(awsProject);
    Data := GetJSON(B.ToolsJson); Data.Free;
    Check('Build advertises Git', Pos('lazarus_run_git', B.ToolsJson) > 0);
    B.OnApproval := @A.Approve;
    CallsBefore := W.Calls;
    Check('denied approval never invokes Git', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err) And
      (W.Calls = CallsBefore));
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
    Lines := TStringList.Create;
    Try
      Lines.LoadFromFile(W.Root + '/file with spaces.txt');
      Lines.Add('third line');
      Lines.SaveToFile(W.Root + '/file with spaces.txt');
      Lines.Text := 'keep staged';
      Lines.SaveToFile(W.Root + '/extra.txt');
    Finally Lines.Free; End;
    Check('stage the path-limited commit', RunAssistantGit(W.Root, '{"arguments":["add","--","file with spaces.txt","extra.txt"]}', Reply, Err));
    Check('commit one path and leave the other staged', RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","Subject only","-m","Body of the path commit","--","file with spaces.txt"]}', Reply, Err));
    Check('the other file stays staged', RunAssistantGit(W.Root, '{"arguments":["status","--short"]}', Reply, Err) And
      (Pos('extra.txt', Reply) > 0) And (Pos('file with spaces.txt', Reply) = 0));
    Check('the path commit subject is stored', RunAssistantGit(W.Root, '{"arguments":["log","-1","--format=%s"]}', Reply, Err) And
      (Pos('Subject only', Reply) > 0));
    Check('the path commit names only the requested file', RunAssistantGit(W.Root,
      '{"arguments":["log","-1","--name-only","--format="]}', Reply, Err) And
      (Pos('file with spaces.txt', Reply) > 0) And (Pos('extra.txt', Reply) = 0));
    Check('commit the leftover staged file', RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","Keep the extra file","--","extra.txt"]}', Reply, Err));
    Check('reject a commit path with no separator', Not RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","no path separator","extra.txt"]}', Reply, Err));
    Check('reject a commit path outside the repository', Not RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","outside","--","../outside.txt"]}', Reply, Err) And (Pos('project-relative', Err) > 0));
    Check('select the temporary folder as the target', AssistantTarget.SelectFolder(W.Root, SelectErr));
    ForceDirectories(W.Root + '/Documents');
    PlanPath := W.Root + '/Documents/Plan.md';
    Lines := TStringList.Create;
    Try
      Lines.Text := '# Image' + LineEnding + LineEnding + 'Generated by Lazarus Project Assistant.' + LineEnding +
        '## 2. Model' + LineEnding + '### 2.1 Attach refs' + LineEnding + 'Status: in progress' + LineEnding;
      Lines.SaveToFile(PlanPath);
    Finally Lines.Free; End;
    Check('commit the starting plan', RunAssistantGit(W.Root, '{"arguments":["add","--","Documents/Plan.md"]}', Reply, Err) And
      RunAssistantGit(W.Root, '{"arguments":["commit","-m","Plan: start the image item","--","Documents/Plan.md"]}', Reply, Err));
    ResetAssistantGitTurn;
    ResetAssistantPlanTurn;
    Lines := TStringList.Create;
    Try
      Lines.Text := 'finished work';
      Lines.SaveToFile(W.Root + '/work.txt');
    Finally Lines.Free; End;
    Check('commit the finished work before status', RunAssistantGit(W.Root, '{"arguments":["add","--","work.txt"]}', Reply, Err) And
      RunAssistantGit(W.Root, '{"arguments":["commit","-m","Assistant: do the work","--","work.txt"]}', Reply, Err) And AssistantGitTurnCommitted);
    Lines := TStringList.Create;
    Try
      Lines.Text := 'still staged';
      Lines.SaveToFile(W.Root + '/other-staged.txt');
    Finally Lines.Free; End;
    Check('stage an unrelated file', RunAssistantGit(W.Root, '{"arguments":["add","--","other-staged.txt"]}', Reply, Err));
    Check('status complete is allowed after the work commit', ReplaceInMarkdownFile('Documents/Plan.md',
      'Status: in progress', 'Status: complete', False, False, Resolved, Err, ReplaceCount) And (ReplaceCount = 1));
    Check('an uncommitted completion is committed with the plan file only',
      RevertUncommittedPlanCompletion(Note) And (Pos('Committed', Note) > 0) And (Pos('Documents/Plan.md', Note) > 0));
    Lines := TStringList.Create;
    Try
      Lines.LoadFromFile(PlanPath);
      Check('the completed status stays on disk', Pos('Status: complete', Lines.Text) > 0);
    Finally Lines.Free; End;
    Check('the plan file is clean and the unrelated file stays staged',
      RunAssistantGit(W.Root, '{"arguments":["status","--short"]}', Reply, Err) And
      (Pos('Documents/Plan.md', Reply) = 0) And (Pos('other-staged.txt', Reply) > 0));
    Check('the plan commit records the item', RunAssistantGit(W.Root, '{"arguments":["log","-1","--format=%s"]}', Reply, Err) And
      (Pos('Plan: mark 2.1 Attach refs complete', Reply) > 0));
    Check('the plan commit does not include the unrelated file', RunAssistantGit(W.Root,
      '{"arguments":["log","-1","--name-only","--format="]}', Reply, Err) And
      (Pos('Documents/Plan.md', Reply) > 0) And (Pos('other-staged.txt', Reply) = 0));
    Check('a second settlement does nothing', Not RevertUncommittedPlanCompletion(Note) And (Note = ''));
    Check('commit the unrelated file before the failure case', RunAssistantGit(W.Root,
      '{"arguments":["commit","-m","Assistant: keep the unrelated file"]}', Reply, Err));
    Lines := TStringList.Create;
    Try
      Lines.LoadFromFile(PlanPath);
      Lines.Add('### 2.2 Next item');
      Lines.Add('Status: not started');
      Check('add the next item without a new completion', WriteMarkdownFile(PlanPath, Lines.Text, False, Resolved, Err));
    Finally Lines.Free; End;
    Check('commit the extended plan', RunAssistantGit(W.Root, '{"arguments":["add","--","Documents/Plan.md"]}', Reply, Err) And
      RunAssistantGit(W.Root, '{"arguments":["commit","-m","Plan: add the next item","--","Documents/Plan.md"]}', Reply, Err));
    ResetAssistantPlanTurn;
    Check('mark the next item complete', ReplaceInMarkdownFile('Documents/Plan.md',
      '### 2.2 Next item' + LineEnding + 'Status: not started',
      '### 2.2 Next item' + LineEnding + 'Status: complete', False, False, Resolved, Err, ReplaceCount) And (ReplaceCount = 1));
    Check('stage the failed completion', RunAssistantGit(W.Root, '{"arguments":["add","--","Documents/Plan.md"]}', Reply, Err));
    Lines := TStringList.Create;
    Try
      Lines.Text := '#!/bin/sh' + LineEnding + 'exit 1' + LineEnding;
      Lines.SaveToFile(W.Root + '/.git/hooks/pre-commit');
    Finally Lines.Free; End;
    Hook := TProcess.Create(Nil);
    Try
      Hook.Executable := 'chmod';
      Hook.Parameters.Add('+x');
      Hook.Parameters.Add(W.Root + '/.git/hooks/pre-commit');
      Hook.Options := [poWaitOnExit, poNoConsole];
      Hook.Execute;
      Check('the failing hook is executable', Hook.ExitCode = 0);
    Finally Hook.Free; End;
    Check('a failed plan commit restores the status', RevertUncommittedPlanCompletion(Note) And (Pos('put back', Note) > 0));
    Lines := TStringList.Create;
    Try
      Lines.LoadFromFile(PlanPath);
      Check('the failed item is not complete', Pos('### 2.2 Next item' + LineEnding + 'Status: not started', Lines.Text) > 0);
      Check('the earlier item stays complete', Pos('### 2.1 Attach refs' + LineEnding + 'Status: complete', Lines.Text) > 0);
    Finally Lines.Free; End;
    Check('the failed completion is not staged', RunAssistantGit(W.Root, '{"arguments":["diff","--cached","--","Documents/Plan.md"]}', Reply, Err) And
      (Pos('diff --git', Reply) = 0));
    Check('the failed completion is not left in the worktree', RunAssistantGit(W.Root, '{"arguments":["diff","--","Documents/Plan.md"]}', Reply, Err) And
      (Pos('diff --git', Reply) = 0));
    ResetAssistantGitTurn;
    Check('status complete is refused before any commit in the turn', Not ReplaceInMarkdownFile('Documents/Plan.md',
      'Status: not started', 'Status: complete', False, False, Resolved, Err, ReplaceCount) And (Pos('run_git commit', Err) > 0));
    Check('reject destructive command', Not RunAssistantGit(W.Root, '{"arguments":["reset","--hard"]}', Reply, Err));
    Check('reject remote command', Not RunAssistantGit(W.Root, '{"arguments":["push"]}', Reply, Err));
    Check('reject path traversal', Not RunAssistantGit(W.Root, '{"arguments":["add","--","../outside"]}', Reply, Err));
    Check('reject malformed arguments', Not RunAssistantGit(W.Root, '{"arguments":[17]}', Reply, Err));
    Check('reject missing repository', Not RunAssistantGit(GetTempDir, '{"arguments":["status"]}', Reply, Err));

    { The same rule through the broker and the IDE workspace, as a Claude turn reaches it. }
    DeleteFile(W.Root + '/.git/hooks/pre-commit');
    IDEWorkspace := TAssistantIDEWorkspace.Create;
    IDEBroker := TAssistantToolBroker.Create(IDEWorkspace);
    Try
      IDEWorkspace.ToolMode := amInspect;
      Run := IDEBroker.BeginRun(awsReadOnly);
      Check('Inspect offers no Lazarus Markdown writes', Pos('lazarus_update_markdown', IDEBroker.ToolsJson) = 0);
      Check('Inspect refuses a Lazarus Markdown write', Not IDEBroker.Execute(Run, 'lazarus_update_markdown', BrokerCompletion, Reply, Err));
      IDEWorkspace.ToolMode := amBuild;
      Run := IDEBroker.BeginRun(awsProject);
      Check('Build offers the Lazarus Markdown writes', (Pos('"lazarus_write_markdown"', IDEBroker.ToolsJson) > 0) And
        (Pos('"lazarus_update_markdown"', IDEBroker.ToolsJson) > 0));
      Data := GetJSON(IDEBroker.ToolsJson); Data.Free;
      Check('a Lazarus Markdown write only writes Markdown', Not IDEBroker.Execute(Run, 'lazarus_update_markdown',
        '{"path":"work.txt","old_text":"finished","new_text":"changed","open":false}', Reply, Err) And (Pos('Markdown', Err) > 0));
      ResetAssistantGitTurn;
      ResetAssistantPlanTurn;
      Before := PlanText;
      Check('a Lazarus completion before any commit in the turn is refused as an assistant one is',
        Not IDEBroker.Execute(Run, 'lazarus_update_markdown', BrokerCompletion, Reply, Err) And (Pos('run_git commit', Err) > 0));
      Check('the refused completion leaves the plan unchanged', PlanText = Before);
      Check('there is nothing to settle after a refusal', Not RevertUncommittedPlanCompletion(Note) And (Note = ''));
      Lines := TStringList.Create;
      Try
        Lines.Text := 'more finished work';
        Lines.SaveToFile(W.Root + '/work2.txt');
      Finally Lines.Free; End;
      Check('commit the finished work through the Lazarus git tool',
        IDEBroker.Execute(Run, 'lazarus_run_git', '{"arguments":["add","--","work2.txt"]}', Reply, Err) And
        IDEBroker.Execute(Run, 'lazarus_run_git', '{"arguments":["commit","-m","Claude: do the next item","--","work2.txt"]}',
        Reply, Err) And AssistantGitTurnCommitted);
      Check('a Lazarus completion after the work commit is allowed',
        IDEBroker.Execute(Run, 'lazarus_update_markdown', BrokerCompletion, Reply, Err) And (Pos('1 replacement', Reply) > 0));
      Check('the completion is on disk', Pos('### 2.2 Next item' + LineEnding + 'Status: complete', PlanText) > 0);
      Check('the turn end commits the plan file as for an assistant turn',
        RevertUncommittedPlanCompletion(Note) And (Pos('Committed', Note) > 0) And (Pos('Documents/Plan.md', Note) > 0));
      Check('the plan file is clean after the turn', RunAssistantGit(W.Root, '{"arguments":["status","--short"]}', Reply, Err) And
        (Pos('Documents/Plan.md', Reply) = 0));
      IDEWorkspace.ToolMode := amPlan;
      Run := IDEBroker.BeginRun(awsMarkdown);
      Check('Plan offers the Lazarus Markdown writes', Pos('"lazarus_update_markdown"', IDEBroker.ToolsJson) > 0);
      ResetAssistantGitTurn;
      ResetAssistantPlanTurn;
      { Renaming a complete item's heading would count as a new completion, so this edit only adds a note. }
      Check('Plan writes a plan through the Lazarus tool', IDEBroker.Execute(Run, 'lazarus_update_markdown',
        '{"path":"Documents/Plan.md","old_text":"Generated by Lazarus Project Assistant.",' +
        '"new_text":"Generated by Lazarus Project Assistant.\n\nA note from Plan mode.","open":false}', Reply, Err) And
        (Pos('A note from Plan mode.', PlanText) > 0));
      Check('Plan cannot commit, so it cannot complete an item either', Pos('lazarus_run_git', IDEBroker.ToolsJson) = 0);
    Finally
      IDEBroker.Free;
      IDEWorkspace.Free;
    End;
    B.Cancel;
    Check('cancelled run rejects Git', Not B.Execute(Run, 'lazarus_run_git', '{"arguments":["status"]}', Reply, Err));
    WriteLn('Temporary test repository: ', W.Root);
  Finally A.Free; B.Free; W.Free; End;
End.
