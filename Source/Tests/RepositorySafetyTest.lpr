Program RepositorySafetyTest;

{ Regression checks for review findings R1-R5. Only temporary repositories are changed. }
{$MODE OBJFPC}{$H+}

Uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  Classes, SysUtils, Process, LazFileUtils, GitService, GitJobRunner, GitDiffPatch;

Var
  Failures, DetachedCalls: Integer;
  TempRoot: String;

Procedure Check(Const Name: String; Condition: Boolean);
Begin
  If Condition Then WriteLn('ok   ', Name)
  Else Begin Inc(Failures); WriteLn('FAIL ', Name); End;
End;

Function GitRun(Const Dir: String; Const Args: Array Of String): String;
Var
  P: TProcess;
  I, N: Integer;
  Buf: Array[0..4095] Of Char;
  Chunk: String;
Begin
  Result := '';
  P := TProcess.Create(Nil);
  Try
    P.Executable := 'git';
    P.CurrentDirectory := Dir;
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    For I := 0 To High(Args) Do P.Parameters.Add(Args[I]);
    P.Execute;
    Repeat
      While P.Output.NumBytesAvailable > 0 Do
        Begin
          N := P.Output.Read(Buf, SizeOf(Buf));
          If N > 0 Then
            Begin SetString(Chunk, PChar(@Buf[0]), N); Result := Result + Chunk; End;
        End;
      If Not P.Running Then Break;
      Sleep(1);
    Until False;
    While P.Output.NumBytesAvailable > 0 Do
      Begin
        N := P.Output.Read(Buf, SizeOf(Buf));
        If N > 0 Then
            Begin SetString(Chunk, PChar(@Buf[0]), N); Result := Result + Chunk; End;
      End;
    If P.ExitStatus <> 0 Then
      Raise Exception.Create('git failed: ' + Result);
  Finally
    P.Free;
  End;
End;

Procedure WriteFile(Const Path, Contents: String);
Var
  S: TFileStream;
Begin
  S := TFileStream.Create(Path, fmCreate);
  Try
    If Contents <> '' Then S.WriteBuffer(Contents[1], Length(Contents));
  Finally S.Free; End;
End;

Function ReadFile(Const Path: String): String;
Var
  S: TFileStream;
Begin
  S := TFileStream.Create(Path, fmOpenRead);
  Try
    SetLength(Result, S.Size);
    If Result <> '' Then S.ReadBuffer(Result[1], Length(Result));
  Finally S.Free; End;
End;

Procedure RemoveTree(Const Path: String);
Var
  R: TSearchRec;
  Code: Integer;
  Child: String;
Begin
  Code := FindFirst(Path + DirectorySeparator + '*', faAnyFile, R);
  Try
    While Code = 0 Do
      Begin
        If (R.Name <> '.') And (R.Name <> '..') Then
          Begin
            Child := Path + DirectorySeparator + R.Name;
            If FileIsSymlink(Child) Or ((R.Attr And faDirectory) = 0) Then
              DeleteFile(Child)
            Else RemoveTree(Child);
          End;
        Code := FindNext(R);
      End;
  Finally FindClose(R); End;
  RemoveDir(Path);
End;

Function NewRepo(Const Name: String): String;
Begin
  Result := TempRoot + DirectorySeparator + Name;
  ForceDirectories(Result);
  GitRun(Result, ['init', '-q', '-b', 'main']);
  GitRun(Result, ['config', 'user.name', 'Repository Safety Test']);
  GitRun(Result, ['config', 'user.email', 'test@example.invalid']);
  GitRun(Result, ['config', 'commit.gpgsign', 'false']);
  WriteFile(Result + '/base.txt', 'base' + #10);
  GitRun(Result, ['add', '.']);
  GitRun(Result, ['commit', '-qm', 'initial']);
End;

Procedure TestPreviewLimits;
Var
  Dir, Content: String;
  G: TGitService;
  Mem: TMemoryStream;
  FS: TFileStream;
Begin
  Dir := NewRepo('preview-limit'); G := TGitService.Create; Mem := TMemoryStream.Create;
  Try
    G.RepoPath := Dir; G.PublishEvents := False;
    FS := TFileStream.Create(Dir + '/large.txt', fmCreate);
    Try FS.Size := GitPreviewByteLimit + 1; Finally FS.Free; End;
    Check('large worktree preview rejected', Not G.ReadWorkingTreeFile('large.txt', Content));
    Check('large worktree returned no content', (Content = '') And (Pos('limit', G.LastError) > 0));
    GitRun(Dir, ['add', '.']); GitRun(Dir, ['commit', '-qm', 'large blob']);
    Check('large blob rejected before read', Not G.ReadBlobBytes('HEAD', 'large.txt', False, Mem));
    Check('large blob returned no bytes', (Mem.Size = 0) And (Pos('limit', G.LastError) > 0));
    Content := StringOfChar('x', GitPreviewByteLimit + 100);
    WriteFile(Dir + '/addition.txt', Content);
    Check('large diff output rejected', Not G.DiffPath('addition.txt', False, Content));
    Check('truncated diff is not returned', (Content = '') And (Pos('limit', G.LastError) > 0));
    Check('normal command still works after limit', G.GetConfigValue('user.name', True, Content));
  Finally Mem.Free; G.Free; End;
End;

Procedure TestFileUnion;
Var
  Entries, Merged: TGitStatusEntryArray;
  Tracked: TStringList;
  Dir, Sha, Branch, Digest, SecondDigest: String;
  G: TGitService;
Begin
  Dir := NewRepo('file-union');
  SetLength(Entries, 4);
  Entries[0].Path := 'untracked.txt'; Entries[0].IndexStatus := '?'; Entries[0].WorkTreeStatus := '?';
  Entries[1].Path := 'ignored/'; Entries[1].IndexStatus := '!'; Entries[1].WorkTreeStatus := '!';
  Entries[2].Path := 'deleted.txt'; Entries[2].IndexStatus := ' '; Entries[2].WorkTreeStatus := 'D';
  Entries[3].Path := 'control' + #1 + '=name'; Entries[3].OldPath := 'old';
  Entries[3].IndexStatus := 'R'; Entries[3].WorkTreeStatus := ' ';
  Tracked := TStringList.Create; G := TGitService.Create;
  Try
    Tracked.Add(Dir + '/base.txt'); Tracked.Add(Dir + '/deleted.txt');
    Tracked.Add(Dir + '/control' + #1 + '=name');
    Merged := MergeGitFileEntries(Dir, Entries, Tracked);
    Check('tracked/status union retains all categories once', Length(Merged) = 5);
    Check('raw control path and rename source retained', (Merged[3].Path = Entries[3].Path) And (Merged[3].OldPath = 'old'));
    Check('clean record added', (Merged[4].Path = 'base.txt') And (Merged[4].WorkTreeStatus = ' '));
    {$IFDEF UNIX}
    Tracked.Add(Dir + '/literal\name');
    Merged := MergeGitFileEntries(Dir, Entries, Tracked);
    Check('Unix backslash retained', Merged[5].Path = 'literal\name');
    {$ENDIF}
    G.RepoPath := Dir; G.PublishEvents := False;
    WriteFile(Dir + '/base.txt', 'first edit');
    Check('first dirty probe', G.ProbeRepository(Sha, Branch, Digest));
    WriteFile(Dir + '/base.txt', 'second edit');
    Check('second dirty probe', G.ProbeRepository(Sha, Branch, SecondDigest));
    Check('preview polling must not depend on porcelain change', Digest = SecondDigest);
  Finally G.Free; Tracked.Free; End;
End;

Procedure TestPartialPatches;
Var
  Dir, BeforeText, AfterText, Diff, Patch, Expected: String;
  G: TGitService;
  Lines: TStringList;
  Selected: TGitLineNumberList;
  Parsed: TGitDiffLines;
  Reverse: Boolean;
  Direction, Choice, I: Integer;
Begin
  Dir := NewRepo('partial');
  G := TGitService.Create; Lines := TStringList.Create; Selected := TGitLineNumberList.Create;
  Try
    G.RepoPath := Dir; G.PublishEvents := False;
    BeforeText := 'top' + #10 + '-- divider' + #10 + 'middle' + #10 + 'old' + #10 + 'end' + #10;
    AfterText := 'top' + #10 + '++ divider' + #10 + 'middle' + #10 + 'new' + #10 + 'end' + #10;
    WriteFile(Dir + '/patch.txt', BeforeText);
    GitRun(Dir, ['add', '.']); GitRun(Dir, ['commit', '-qm', 'patch baseline']);
    For Direction := 0 To 1 Do
      For Choice := 0 To 2 Do
        Begin
          Reverse := Direction = 1;
          GitRun(Dir, ['reset', '-q', '--hard', 'HEAD']);
          WriteFile(Dir + '/patch.txt', AfterText);
          If Reverse Then GitRun(Dir, ['add', '.']);
          Check('read partial source', G.DiffPath('patch.txt', Reverse, Diff));
          Lines.Text := Diff; Parsed := ParseGitDiff(Lines); Selected.Clear;
          For I := 0 To Lines.Count - 1 Do
            If ((Choice <> 2) And (Lines[I] = '--- divider')) Or
               ((Choice <> 1) And (Lines[I] = '+++ divider')) Then
              Begin
                Check('divider classified as change', Parsed[I].Kind In [dlAdded, dlRemoved]);
                Selected.Add(I + 1);
              End;
          Patch := BuildGitPartialPatch(Lines, 1, Lines.Count, Selected, Reverse);
          Check('apply selected patch direction ' + IntToStr(Direction) + ' choice ' + IntToStr(Choice),
            G.ApplyPatchToIndex(Patch, Reverse));
          If Reverse Then
            Begin
              Case Choice Of
                0: Expected := '-- divider';
                1: Expected := '-- divider' + #10 + '++ divider';
                2: Expected := '';
              End;
              Expected := 'top' + #10 + Expected + #10 + 'middle' + #10 + 'new' + #10 + 'end' + #10;
            End
          Else
            Begin
              Case Choice Of
                0: Expected := '++ divider';
                1: Expected := '';
                2: Expected := '-- divider' + #10 + '++ divider';
              End;
              Expected := 'top' + #10 + Expected + #10 + 'middle' + #10 + 'old' + #10 + 'end' + #10;
            End;
          If (Choice = 1) And Not Reverse Or (Choice = 2) And Reverse Then
            Expected := StringReplace(Expected, 'top' + #10#10, 'top' + #10, []);
          Check('only selected lines changed', GitRun(Dir, ['show', ':patch.txt']) = Expected);
        End;
    { Several separated hunks and a final line without a newline. Select only
      the last replacement so earlier unselected length changes affect offsets. }
    BeforeText := 'first' + #10;
    For I := 1 To 30 Do BeforeText := BeforeText + 'context ' + IntToStr(I) + #10;
    BeforeText := BeforeText + 'last';
    AfterText := StringReplace(BeforeText, 'first', 'first' + #10 + 'extra', []);
    AfterText := StringReplace(AfterText, 'last', 'changed', []);
    GitRun(Dir, ['reset', '-q', '--hard', 'HEAD']);
    WriteFile(Dir + '/patch.txt', BeforeText); GitRun(Dir, ['add', '.']);
    GitRun(Dir, ['commit', '-qm', 'separated baseline']);
    For Direction := 0 To 1 Do
      Begin
        Reverse := Direction = 1;
        GitRun(Dir, ['reset', '-q', '--hard', 'HEAD']);
        WriteFile(Dir + '/patch.txt', AfterText);
        If Reverse Then GitRun(Dir, ['add', '.']);
        Diff := GitRun(Dir, ['diff', '-U3', '--', 'patch.txt']);
        If Reverse Then Diff := GitRun(Dir, ['diff', '--cached', '-U3', '--', 'patch.txt']);
        Lines.Text := Diff; Selected.Clear;
        For I := 0 To Lines.Count - 1 Do
          If (Lines[I] = '-last') Or (Lines[I] = '+changed') Then Selected.Add(I + 1);
        Patch := BuildGitPartialPatch(Lines, 1, Lines.Count, Selected, Reverse);
        Check('separated hunks and no newline apply', G.ApplyPatchToIndex(Patch, Reverse));
        If Reverse Then Expected := StringReplace(AfterText, 'changed', 'last', [])
        Else Expected := StringReplace(BeforeText, 'last', 'changed', []);
        Check('separated hunk contents', GitRun(Dir, ['show', ':patch.txt']) = Expected);
      End;
  Finally Selected.Free; Lines.Free; G.Free; End;
End;

Procedure TestCommandResults;
Var
  Dir, Diff, Value: String;
  G: TGitService;
  Paths: TStringList;
  Summary: TGitTransferSummary;
Begin
  Dir := NewRepo('results');
  G := TGitService.Create;
  Paths := Nil;
  Try
    G.RepoPath := Dir; G.PublishEvents := False;
    Check('missing config read succeeds', G.GetConfigValue('review.missing', True, Value));
    Check('missing config is empty', (Value = '') And (G.LastError = '') And (G.LastCommand.ExitCode = 1));
    Check('missing config unset succeeds', G.UnsetConfigValue('review.missing', True));
    Check('unset code decoded', G.LastCommand.ExitCode = 5);
    Check('invalid config fails', Not G.GetConfigValue('invalid', True, Value));
    Check('config diagnostics separate', (G.LastCommand.ErrorText <> '') And (Value = ''));
    GitRun(Dir, ['config', '--add', 'review.multiple', 'one']);
    GitRun(Dir, ['config', '--add', 'review.multiple', 'two']);
    Check('multiple config values cannot silently unset', Not G.UnsetConfigValue('review.multiple', True));
    Check('root commit diff', G.ShowCommitPathDiff('HEAD', 'base.txt', Diff) And (Pos('+base', Diff) > 0));
    GitRun(Dir, ['checkout', '-qb', 'side']);
    WriteFile(Dir + '/side.txt', 'side' + #10);
    GitRun(Dir, ['add', '.']); GitRun(Dir, ['commit', '-qm', 'side']);
    GitRun(Dir, ['checkout', '-q', 'main']);
    WriteFile(Dir + '/main.txt', 'main' + #10);
    GitRun(Dir, ['add', '.']); GitRun(Dir, ['commit', '-qm', 'main']);
    GitRun(Dir, ['merge', '-q', '--no-edit', 'side']);
    Check('merge paths query', G.ListCommitPaths('HEAD', Paths));
    Check('merge compared to first parent', (Paths.Count = 1) And (Paths[0] = 'side.txt'));
    Check('merge file diff', G.ShowCommitPathDiff('HEAD', 'side.txt', Diff) And (Pos('+side', Diff) > 0));
    WriteFile(Dir + '/new.txt', 'new' + #10);
    Check('untracked diff succeeds', G.DiffPath('new.txt', False, Diff) And (Pos('+new', Diff) > 0));
    Check('missing diff fails', Not G.DiffPath('missing.txt', False, Diff));
    Check('diagnostics do not become diff', (Diff = '') And (G.LastCommand.ErrorText <> ''));
    {$IFDEF UNIX}
    WriteFile(Dir + '/unreadable.txt', 'hidden'); fpChmod(Dir + '/unreadable.txt', 0);
    If fpGetEUid <> 0 Then
      Check('unreadable diff fails', Not G.DiffPath('unreadable.txt', False, Diff));
    fpChmod(Dir + '/unreadable.txt', &600);
    {$ENDIF}
    Check('failed transfer', Not G.Fetch(Summary, 'missing-remote'));
    Check('transfer preserves diagnostics', (G.LastCommand.ErrorText <> '') And
      (Pos(G.LastError, Summary.Message) > 0));
  Finally Paths.Free; G.Free; End;
End;

Procedure TestLiteralPaths;
Var
  Dir, Diff, Indexed: String;
  G: TGitService;
  Paths: TStringList;
  Names: Array Of String;
  I: Integer;
Begin
  Dir := NewRepo('literal');
  Names := ['literal[1].txt', 'literal1.txt', '-option.txt'];
  {$IFDEF UNIX}
  Names := Concat(Names, ['star*.txt', 'star-other.txt', ':(glob)*.txt']);
  {$ENDIF}
  For I := 0 To High(Names) Do WriteFile(Dir + '/' + Names[I], 'old' + #10);
  GitRun(Dir, ['add', '.']); GitRun(Dir, ['commit', '-qm', 'names']);
  For I := 0 To High(Names) Do WriteFile(Dir + '/' + Names[I], 'changed ' + Names[I] + #10);
  G := TGitService.Create; Paths := TStringList.Create;
  Try
    G.PublishEvents := False; G.RepoPath := Dir;
    For I := 0 To High(Names) Do
      Begin
        If (Names[I] = 'literal1.txt') Or (Names[I] = 'star-other.txt') Then Continue;
        Paths.Clear; Paths.Add(Names[I]);
        Check('stage literal ' + Names[I], G.StagePaths(Paths));
        Indexed := GitRun(Dir, ['diff', '--cached', '--name-only', '-z']);
        Check('only selected path staged ' + Names[I], Indexed = Names[I] + #0);
        Check('unstage literal ' + Names[I], G.UnstagePaths(Paths));
        Check('index empty after literal unstage', GitRun(Dir, ['diff', '--cached', '--name-only']) = '');
        Check('literal diff succeeds', G.DiffPath(Names[I], False, Diff));
        Check('diff excludes bracket match', (Names[I] = 'literal1.txt') Or (Pos('changed literal1.txt', Diff) = 0));
        Check('stage all before selective unstage', G.StageAll);
        Check('unstage only literal from populated index', G.UnstagePaths(Paths));
        Indexed := GitRun(Dir, ['diff', '--cached', '--name-only', '-z']);
        Check('selected literal removed from index', Pos(#0 + Names[I] + #0, #0 + Indexed) = 0);
        Check('bracket counterpart stays staged', Pos(#0 + 'literal1.txt' + #0, #0 + Indexed) > 0);
        {$IFDEF UNIX}
        Check('wildcard counterpart stays staged', Pos(#0 + 'star-other.txt' + #0, #0 + Indexed) > 0);
        {$ENDIF}
        GitRun(Dir, ['reset', '-q', 'HEAD']);
        Check('revert literal ' + Names[I], G.RevertPaths(Paths));
        Check('selected file reverted', ReadFile(Dir + '/' + Names[I]) = 'old' + #10);
        Check('other bracket file untouched', ReadFile(Dir + '/literal1.txt') = 'changed literal1.txt' + #10);
        {$IFDEF UNIX}
        Check('other wildcard file untouched', ReadFile(Dir + '/star-other.txt') = 'changed star-other.txt' + #10);
        {$ENDIF}
      End;
  Finally Paths.Free; G.Free; End;
End;

Procedure TestRename;
Var
  Dir: String;
  G: TGitService;
  Paths: TStringList;
Begin
  Dir := NewRepo('rename');
  G := TGitService.Create; Paths := TStringList.Create;
  Try
    G.PublishEvents := False; G.RepoPath := Dir;
    GitRun(Dir, ['mv', 'base.txt', 'renamed[1].txt']);
    Paths.Add('renamed[1].txt');
    Check('unstage selected rename', G.UnstagePaths(Paths));
    Check('rename leaves no deletion staged', GitRun(Dir, ['diff', '--cached', '--name-only']) = '');
    Check('rename worktree preserved', FileExists(Dir + '/renamed[1].txt') And Not FileExists(Dir + '/base.txt'));
    GitRun(Dir, ['add', '-A']);
    Check('unstage all displayed rename paths', G.UnstagePaths(Paths));
    Check('displayed unstage all empties index', GitRun(Dir, ['diff', '--cached', '--name-only']) = '');
    GitRun(Dir, ['add', '-A']);
    Check('service unstage all', G.UnstageAll);
    Check('service unstage all empties index', GitRun(Dir, ['diff', '--cached', '--name-only']) = '');
    GitRun(Dir, ['reset', '--hard', '-q', 'HEAD']);
    DeleteFile(Dir + '/renamed[1].txt');
    WriteFile(Dir + '/base.txt', 'modified source' + #10);
    WriteFile(Dir + '/copy.txt', 'base' + #10);
    GitRun(Dir, ['add', '.']);
    Paths.Clear; Paths.Add('copy.txt');
    Check('unstage copied file', G.UnstagePaths(Paths));
    Check('copy source stays staged', GitRun(Dir, ['diff', '--cached', '--name-only', '-z']) = 'base.txt' + #0);
  Finally Paths.Free; G.Free; End;
End;

Procedure TestIgnorePaths;
Var
  Dir, Outside, LinkPath: String;
  G: TGitService;
  Lines: TStringList;
Begin
  Dir := NewRepo('ignore');
  G := TGitService.Create; Lines := TStringList.Create;
  Try
    G.PublishEvents := False; G.RepoPath := Dir; Lines.Add('build');
    Check('new ignore file saves', G.SaveIgnoreFile(Lines));
    Check('normal ignore append succeeds', G.AppendIgnorePatterns(Lines));
    Check('new nested path inside repository accepted', G.WorkingTreeFullPath('new/child.txt') <> '');
    {$IFDEF UNIX}
    Outside := TempRoot + '/outside-ignore.txt';
    LinkPath := Dir + '/.gitignore';
    DeleteFile(LinkPath);
    Check('create dangling ignore link', fpSymlink(PChar(Outside), PChar(LinkPath)) = 0);
    Check('dangling link rejected', G.WorkingTreeFullPath('.gitignore') = '');
    Check('append rejects dangling ignore', Not G.AppendIgnorePatterns(Lines));
    Check('save rejects dangling ignore', Not G.SaveIgnoreFile(Lines));
    Check('outside target not created', Not FileExists(Outside));
    WriteFile(Outside, 'keep outside' + #10);
    Check('existing outside link rejected', G.WorkingTreeFullPath('.gitignore') = '');
    Check('existing outside ignore cannot be saved', Not G.SaveIgnoreFile(Lines));
    Check('outside target unchanged', ReadFile(Outside) = 'keep outside' + #10);
    DeleteFile(LinkPath);
    WriteFile(Dir + '/inside.txt', 'keep inside' + #10);
    Check('create inside ignore link', fpSymlink('inside.txt', PChar(LinkPath)) = 0);
    Check('ignore writes reject even inside symlinks', Not G.SaveIgnoreFile(Lines));
    Check('inside target unchanged', ReadFile(Dir + '/inside.txt') = 'keep inside' + #10);
    Check('create outside directory link', fpSymlink(PChar(TempRoot), PChar(Dir + '/linked')) = 0);
    Check('missing leaf below outside link rejected', G.WorkingTreeFullPath('linked/not-created.txt') = '');
    Check('create dangling directory link', fpSymlink(PChar(TempRoot + '/absent'), PChar(Dir + '/dangling')) = 0);
    Check('missing leaf below dangling link rejected', G.WorkingTreeFullPath('dangling/child.txt') = '');
    Check('create inside directory link', fpSymlink(PChar(Dir), PChar(Dir + '/inside-dir')) = 0);
    Check('missing leaf below inside link accepted', G.WorkingTreeFullPath('inside-dir/new.txt') <> '');
    {$ENDIF}
  Finally Lines.Free; G.Free; End;
End;

Type
  TJobObserver = Class
    Done, Ok, WasCancelled, StaleRejected: Boolean;
    Followup: TGitJob;
    CurrentRepo: String;
    CurrentGeneration: QWord;
    Procedure Finished(Job: TGitJob);
    Procedure Detached(Job: TGitJob);
  End;

Procedure TJobObserver.Finished(Job: TGitJob);
Begin
  Done := True; Ok := Job.Ok; WasCancelled := Job.Cancelled;
  If Job.Kind = gjkCommit Then
    Begin
      StaleRejected := Not Job.MatchesRepository(CurrentRepo, CurrentGeneration);
      Followup := Job.CreatePushFollowup;
      Check('push intent consumed only once', Job.CreatePushFollowup = Nil);
    End;
End;

Procedure TJobObserver.Detached(Job: TGitJob);
Begin
  Inc(DetachedCalls);
End;

Procedure AwaitDone(Observer: TJobObserver);
Var
  Deadline: QWord;
Begin
  Deadline := GetTickCount64 + 10000;
  While Not Observer.Done And (GetTickCount64 < Deadline) Do
    Begin CheckSynchronize(5); Sleep(1); End;
  Check('job completes before timeout', Observer.Done);
End;

{$IFDEF UNIX}
Procedure InstallCommitBarrier(Const Dir: String);
Begin
  WriteFile(Dir + '/.git/hooks/pre-commit',
    '#!/bin/sh' + #10 +
    ': > .git/review-started' + #10 +
    'n=0' + #10 +
    'while [ ! -f .git/review-release ]; do' + #10 +
    '  sleep 0.01; n=$((n+1)); [ "$n" -lt 500 ] || exit 1' + #10 +
    'done' + #10);
  If fpChmod(PChar(Dir + '/.git/hooks/pre-commit'), &700) <> 0 Then
    Raise Exception.Create('cannot make test hook executable');
End;

Procedure AwaitCommitBarrier(Const Dir: String);
Var
  Deadline: QWord;
Begin
  Deadline := GetTickCount64 + 5000;
  While Not FileExists(Dir + '/.git/review-started') And (GetTickCount64 < Deadline) Do
    Sleep(1);
  If Not FileExists(Dir + '/.git/review-started') Then
    Raise Exception.Create('commit did not reach test barrier');
End;
{$ENDIF}

Procedure TestRepositoryContext;
Var
  A, B, Remote, BeforeB, CommitSha: String;
  Runner: TGitJobRunner;
  Observer: TJobObserver;
  Job: TGitJob;
Begin
  A := NewRepo('context-a'); B := NewRepo('context-b');
  Remote := TempRoot + '/remote.git';
  GitRun(TempRoot, ['init', '--bare', '-q', Remote]);
  GitRun(A, ['remote', 'add', 'origin', Remote]);
  BeforeB := GitRun(B, ['rev-parse', 'HEAD']);
  WriteFile(A + '/base.txt', 'new commit' + #10); GitRun(A, ['add', '.']);
  {$IFDEF UNIX}InstallCommitBarrier(A);{$ENDIF}
  Runner := TGitJobRunner.Create; Observer := TJobObserver.Create;
  Try
    Observer.CurrentRepo := A; Observer.CurrentGeneration := 1;
    Job := TGitJob.Create(gjkCommit);
    Job.RepoPath := A; Job.RepoGeneration := 1;
    Job.CommitMessage := 'originating repository'; Job.PushAfterCommit := True;
    Job.OnFinished := @Observer.Finished;
    Check('different repository rejected', Not Job.MatchesRepository(B, 1));
    Check('old visit to same repository rejected', Not Job.MatchesRepository(A, 3));
    Check('same repository context accepted', Job.MatchesRepository(A + '/', 1));
    Check('submit commit in A', Runner.Submit(Job));
    {$IFDEF UNIX}AwaitCommitBarrier(A);{$ENDIF}
    Observer.CurrentRepo := B; Observer.CurrentGeneration := 2;
    {$IFDEF UNIX}WriteFile(A + '/.git/review-release', '');{$ENDIF}
    AwaitDone(Observer);
    Check('commit succeeds', Observer.Ok);
    Check('stale completion rejected', Observer.StaleRejected);
    Check('push followup created', Assigned(Observer.Followup));
    If Assigned(Observer.Followup) Then
      Begin
        Check('push preserves repository A', Observer.Followup.RepoPath = A);
        Check('push preserves original generation', Observer.Followup.RepoGeneration = 1);
        Check('push cannot match view B', Not Observer.Followup.MatchesRepository(B, 2));
        Observer.Done := False;
        Job := Observer.Followup; Observer.Followup := Nil;
        Check('submit originating push', Runner.Submit(Job));
        AwaitDone(Observer); Check('push succeeds', Observer.Ok);
        CommitSha := GitRun(A, ['rev-parse', 'HEAD']);
        Check('A commit reaches A remote', GitRun(Remote, ['rev-parse', 'refs/heads/main']) = CommitSha);
        Check('B remains unchanged', GitRun(B, ['rev-parse', 'HEAD']) = BeforeB);
      End;
  Finally
    {$IFDEF UNIX}WriteFile(A + '/.git/review-release', '');{$ENDIF}
    Runner.DetachFinishedHandler(@Observer.Finished);
    Runner.Free; Observer.Followup.Free; Observer.Free;
  End;
End;

{$IFDEF UNIX}
Procedure TestRunningDetach;
Var
  Dir: String;
  Runner: TGitJobRunner;
  Owner, Sentinel: TJobObserver;
  Job: TGitJob;
Begin
  Dir := NewRepo('running-detach');
  WriteFile(Dir + '/base.txt', 'pending change' + #10);
  GitRun(Dir, ['add', '.']);
  InstallCommitBarrier(Dir);
  Runner := TGitJobRunner.Create;
  Owner := TJobObserver.Create; Sentinel := TJobObserver.Create;
  Try
    Job := TGitJob.Create(gjkCommit); Job.RepoPath := Dir;
    Job.CommitMessage := 'cancel me'; Job.OnFinished := @Owner.Detached;
    Check('submit blocked owner job', Runner.Submit(Job));
    AwaitCommitBarrier(Dir);
    Job := TGitJob.Create(gjkRepoProbe); Job.RepoPath := Dir;
    Job.OnFinished := @Owner.Detached;
    Check('submit queued owner job', Runner.Submit(Job));
    Job := TGitJob.Create(gjkRepoProbe); Job.RepoPath := Dir;
    Job.OnFinished := @Sentinel.Finished;
    Check('submit unrelated successor', Runner.Submit(Job));
    Runner.CancelIfHandler(@Owner.Detached);
    Runner.DetachFinishedHandler(@Owner.Detached);
    FreeAndNil(Owner);
    WriteFile(Dir + '/.git/review-release', '');
    AwaitDone(Sentinel);
    Check('cancelling running owner preserves successor', Sentinel.Ok And Not Sentinel.WasCancelled);
    Check('running and queued callbacks detached', DetachedCalls = 0);
  Finally
    WriteFile(Dir + '/.git/review-release', '');
    If Assigned(Owner) Then Runner.DetachFinishedHandler(@Owner.Detached);
    Runner.DetachFinishedHandler(@Sentinel.Finished);
    Runner.Free; Owner.Free; Sentinel.Free;
  End;
End;
{$ENDIF}

Procedure TestDetachAndCancel;
Var
  Runner: TGitJobRunner;
  Owner, Sentinel: TJobObserver;
  Job: TGitJob;
  I, J: Integer;
Begin
  Runner := TGitJobRunner.Create; Sentinel := TJobObserver.Create;
  Try
    { Do not dispatch callbacks until their owner is detached and freed.
      Repetition exercises queue/current/delivery transitions on the worker. }
    For I := 1 To 100 Do
      Begin
        Owner := TJobObserver.Create;
        For J := 1 To 16 Do
          Begin
            Job := TGitJob.Create(gjkNone); Job.Quiet := True;
            Job.OnFinished := @Owner.Detached;
            If Not Runner.Submit(Job) Then Raise Exception.Create('unexpected full queue');
          End;
        If I Mod 2 = 0 Then Sleep(1);
        Runner.CancelIfHandler(@Owner.Detached);
        Runner.DetachFinishedHandler(@Owner.Detached);
        Owner.Free;
        Sentinel.Done := False;
        Job := TGitJob.Create(gjkRepoProbe);
        Job.RepoPath := TempRoot + '/context-b'; Job.Quiet := True;
        Job.OnFinished := @Sentinel.Finished;
        If Not Runner.Submit(Job) Then Raise Exception.Create('cannot queue sentinel');
        AwaitDone(Sentinel);
        Check('unrelated next job not cancelled', Sentinel.Ok And Not Sentinel.WasCancelled);
      End;
    Check('no detached callback invoked across transitions', DetachedCalls = 0);
  Finally
    Runner.DetachFinishedHandler(@Sentinel.Finished);
    Runner.Free; Sentinel.Free;
  End;
End;

Begin
  TempRoot := GetTempFileName(GetTempDir, 'repository-safety-');
  DeleteFile(TempRoot); ForceDirectories(TempRoot);
  Try
    Try
      TestPreviewLimits;
      TestFileUnion;
      TestPartialPatches;
      TestCommandResults;
      TestLiteralPaths;
      TestRename;
      TestIgnorePaths;
      TestRepositoryContext;
      {$IFDEF UNIX}TestRunningDetach;{$ENDIF}
      TestDetachAndCancel;
    Except On E: Exception Do Begin Inc(Failures); WriteLn('FAIL exception: ', E.Message); End; End;
  Finally RemoveTree(TempRoot); End;
  WriteLn(Failures, ' failure(s).');
  If Failures <> 0 Then Halt(1);
End.
