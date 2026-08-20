Program GitStatusParseTest;

{ Console checks for porcelain v1 -z status parsing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, Process, GitService;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TestRenameOrder;
Var
  Entries: TGitStatusEntryArray;
  Raw: String;
Begin
  { git status --porcelain=v1 -z prints destination then source. }
  Raw := 'R  new-name.txt' + #0 + 'old-name.txt' + #0;
  ParseGitStatusPorcelainV1Z(Raw, Entries);
  Check('rename count', Length(Entries) = 1);
  Check('rename dest is Path', (Length(Entries) = 1) And (Entries[0].Path = 'new-name.txt'));
  Check('rename source is OldPath', (Length(Entries) = 1) And (Entries[0].OldPath = 'old-name.txt'));
  Check('rename index status', (Length(Entries) = 1) And (Entries[0].IndexStatus = 'R'));
End;

Procedure TestCopyAndModified;
Var
  Entries: TGitStatusEntryArray;
  Raw: String;
Begin
  Raw := 'C  dest copied.txt' + #0 + 'src.txt' + #0 + 'M  plain.txt' + #0;
  ParseGitStatusPorcelainV1Z(Raw, Entries);
  Check('copy plus modified count', Length(Entries) = 2);
  Check('copy dest', (Length(Entries) = 2) And (Entries[0].Path = 'dest copied.txt'));
  Check('copy source', (Length(Entries) = 2) And (Entries[0].OldPath = 'src.txt'));
  Check('modified path', (Length(Entries) = 2) And (Entries[1].Path = 'plain.txt') And
    (Entries[1].OldPath = ''));
End;

Procedure TestEqualsInName;
Var
  Entries: TGitStatusEntryArray;
  Raw: String;
  StatusMap: TStringList;
Begin
  Raw := '?? config=debug.txt' + #0;
  ParseGitStatusPorcelainV1Z(Raw, Entries);
  Check('untracked equals in name', (Length(Entries) = 1) And (Entries[0].Path = 'config=debug.txt'));
  StatusMap := TStringList.Create;
  Try
    StatusMap.NameValueSeparator := #1;
    StatusMap.Values['config=debug.txt'] := 'modified';
    Check('status map keeps equals in name', StatusMap.Names[0] = 'config=debug.txt');
    Check('status map value', StatusMap.ValueFromIndex[0] = 'modified');
  Finally
    StatusMap.Free;
  End;
End;

Function RunProcess(Const WorkDir, Executable: String; Const Args: Array Of String): Boolean;
Var
  Proc: TProcess;
  I: Integer;
Begin
  Result := False;
  Proc := TProcess.Create(Nil);
  Try
    If WorkDir <> '' Then
      Proc.CurrentDirectory := WorkDir;
    Proc.Executable := Executable;
    Proc.Options := [poWaitOnExit, poNoConsole];
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);
    Try
      Proc.Execute;
      Result := Proc.ExitStatus = 0;
    Except
      Result := False;
    End;
  Finally
    Proc.Free;
  End;
End;

Procedure WriteTextFile(Const FileName, Contents: String);
Var
  List: TStringList;
Begin
  List := TStringList.Create;
  Try
    List.Text := Contents;
    List.SaveToFile(FileName);
  Finally
    List.Free;
  End;
End;

Procedure RemoveTree(Const Dir: String);
Var
  Rec: TSearchRec;
  Code: Integer;
  Child: String;
Begin
  If Dir = '' Then
    Exit;
  Code := FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        If (Rec.Name <> '.') And (Rec.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(Dir) + Rec.Name;
            If (Rec.Attr And faDirectory) <> 0 Then
              RemoveTree(Child)
            Else
              DeleteFile(Child);
          End;
        Code := FindNext(Rec);
      End;
  Finally
    FindClose(Rec);
  End;
  RemoveDir(Dir);
End;

Procedure TestLiveGit;
Var
  Root, Dummy: String;
  Git: TGitService;
  Entries: TGitStatusEntryArray;
  Paths: TStringList;
Begin
  If Not RunProcess('', 'git', ['--version']) Then
    Begin
      WriteLn('skip live git (git not on PATH)');
      Exit;
    End;
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-git-parse-' +
    IntToStr(GetProcessID);
  If DirectoryExists(Root) Then
    RemoveTree(Root);
  If Not ForceDirectories(Root) Then
    Begin
      WriteLn('skip live git (could not create temp dir)');
      Exit;
    End;
  Git := TGitService.Create;
  Paths := TStringList.Create;
  Try
    Git.PublishEvents := False;
    Git.RepoPath := Root;
    Check('git init', RunProcess(Root, 'git', ['init']));
    RunProcess(Root, 'git', ['config', 'user.email', 'test@example.com']);
    RunProcess(Root, 'git', ['config', 'user.name', 'Test']);
    WriteTextFile(Root + DirectorySeparator + 'old-name.txt', 'hello' + LineEnding);
    Check('git add before first commit', RunProcess(Root, 'git', ['add', 'old-name.txt']));
    Paths.Add('old-name.txt');
    Check('unstage without HEAD', Git.UnstagePaths(Paths) And (Not Git.GetHeadSha(Dummy)));
    Check('file still present after unstage', FileExists(Root + DirectorySeparator + 'old-name.txt'));
    Check('git add after unstage', RunProcess(Root, 'git', ['add', 'old-name.txt']));
    Check('first commit', RunProcess(Root, 'git', ['commit', '-m', 'initial']));
    Check('git mv', RunProcess(Root, 'git', ['mv', 'old-name.txt', 'new-name.txt']));
    Check('list rename status', Git.ListStatus(Entries, False, False) And (Length(Entries) = 1));
    Check('live rename dest', (Length(Entries) = 1) And (Entries[0].Path = 'new-name.txt'));
    Check('live rename source', (Length(Entries) = 1) And (Entries[0].OldPath = 'old-name.txt'));
    If FileExists('/etc/passwd') And RunProcess(Root, 'ln', ['-s', '/etc/passwd', 'outside.link']) Then
      Check('symlink outside repo is rejected', Git.WorkingTreeFullPath('outside.link') = '');
  Finally
    Paths.Free;
    Git.Free;
    RemoveTree(Root);
  End;
End;

Begin
  FailCount := 0;
  TestRenameOrder;
  TestCopyAndModified;
  TestEqualsInName;
  TestLiveGit;
  If FailCount = 0 Then
    Begin
      WriteLn('All checks passed.');
      ExitCode := 0;
    End
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed.');
      ExitCode := 1;
    End;
End.
