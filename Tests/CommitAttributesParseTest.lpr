Program CommitAttributesParseTest;

{ Parser and live git checks for the History commit information record (c) 2026 Michell Computing. }

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

Function FieldRecord(Const Sha, AuthorName, AuthorEmail, AuthorTime, CommitterName, CommitterEmail,
  CommitterTime, Parents, Refs, Message: String): String;
Begin
  Result := Sha + #0 + AuthorName + #0 + AuthorEmail + #0 + AuthorTime + #0 + CommitterName + #0 +
    CommitterEmail + #0 + CommitterTime + #0 + Parents + #0 + Refs + #0 + Message;
End;

Procedure TestFullRecord;
Var
  Info: TGitCommitAttributes;
  Raw: String;
Begin
  Raw := FieldRecord('abc123', 'Ada Lovelace', 'ada@example.com', '1700000000', 'Ada Lovelace',
    'ada@example.com', '1700000000', 'parentone parenttwo', 'HEAD -> main, origin/main, tag: v1',
    'Subject line' + #10 + #10 + 'Body with, comma' + #10);
  Check('full record parses', ParseCommitAttributes(Raw, Info));
  Check('sha', Info.Sha = 'abc123');
  Check('author name', Info.AuthorName = 'Ada Lovelace');
  Check('author email', Info.AuthorEmail = 'ada@example.com');
  Check('author time', Info.AuthorTime = 1700000000);
  Check('committer name', Info.CommitterName = 'Ada Lovelace');
  Check('parents stay space-separated', Info.Parents = 'parentone parenttwo');
  Check('refs keep commas', Info.Refs = 'HEAD -> main, origin/main, tag: v1');
  Check('message keeps comma and blank line', Info.Message = 'Subject line' + #10 + #10 + 'Body with, comma');
End;

Procedure TestMessageNulAndRoot;
Var
  Info: TGitCommitAttributes;
  Raw: String;
Begin
  Raw := FieldRecord('abc', 'Author', 'a@example.com', '1', 'Committer', 'c@example.com', '2', '', '',
    'line' + #0 + 'after nul');
  Check('embedded nul parses', ParseCommitAttributes(Raw, Info));
  Check('message keeps embedded nul', Info.Message = 'line' + #0 + 'after nul');
  Check('empty parents', Info.Parents = '');
  Check('empty refs', Info.Refs = '');
  Check('different committer time', Info.CommitterTime = 2);
End;

Procedure TestRejectedRecords;
Var
  Info: TGitCommitAttributes;
Begin
  Info.Sha := 'stale';
  Check('empty input fails', Not ParseCommitAttributes('', Info));
  Check('failed parse clears sha', Info.Sha = '');
  Check('too few separators fails', Not ParseCommitAttributes('only-sha' + #0 + 'name', Info));
  Check('bad time fails', Not ParseCommitAttributes(FieldRecord('abc', 'A', 'a@b.c', 'nope', 'A', 'a@b.c', '1',
    '', '', 'msg'), Info));
  Check('bad time clears sha', Info.Sha = '');
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
  Root, FirstSha, SecondSha: String;
  Git: TGitService;
  Info: TGitCommitAttributes;
Begin
  If Not RunProcess('', 'git', ['--version']) Then
    Begin
      WriteLn('skip live git (git not on PATH)');
      Exit;
    End;
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-commit-info-' + IntToStr(GetProcessID);
  If DirectoryExists(Root) Then
    RemoveTree(Root);
  If Not ForceDirectories(Root) Then
    Begin
      WriteLn('skip live git (could not create temp dir)');
      Exit;
    End;
  Git := TGitService.Create;
  Try
    Git.PublishEvents := False;
    Git.RepoPath := Root;
    Check('git init', RunProcess(Root, 'git', ['init']));
    Check('committer name', RunProcess(Root, 'git', ['config', 'user.name', 'Committer']));
    Check('committer email', RunProcess(Root, 'git', ['config', 'user.email', 'committer@example.com']));
    WriteTextFile(Root + DirectorySeparator + 'note.txt', 'hello' + LineEnding);
    Check('git add', RunProcess(Root, 'git', ['add', 'note.txt']));
    Check('first commit', RunProcess(Root, 'git', ['commit', '-m', 'root subject']));
    Check('head sha', Git.GetHeadSha(FirstSha) And (Length(FirstSha) = 40));
    Check('read root commit', Git.GetCommitAttributes(FirstSha, Info));
    If Info.Sha = '' Then
      WriteLn('  root error: ', Git.LastError);
    Check('root sha matches', Info.Sha = FirstSha);
    Check('root has no parents', Info.Parents = '');
    Check('root refs mention HEAD', Pos('HEAD', Info.Refs) > 0);
    Check('root message', Info.Message = 'root subject');
    WriteTextFile(Root + DirectorySeparator + 'note.txt', 'changed' + LineEnding);
    Check('git add second', RunProcess(Root, 'git', ['add', 'note.txt']));
    Check('second commit', RunProcess(Root, 'git', ['commit', '--author=Author <author@example.com>',
      '--date=@1700000000', '-m', 'Subject line', '-m', 'Body with, comma']));
    Check('second head', Git.GetHeadSha(SecondSha) And (Length(SecondSha) = 40));
    Check('read second commit', Git.GetCommitAttributes(SecondSha, Info));
    If Info.AuthorName = '' Then
      WriteLn('  second error: ', Git.LastError);
    Check('author name', Info.AuthorName = 'Author');
    Check('author email', Info.AuthorEmail = 'author@example.com');
    Check('author time', Info.AuthorTime = 1700000000);
    Check('committer name', Info.CommitterName = 'Committer');
    Check('committer email', Info.CommitterEmail = 'committer@example.com');
    Check('committer time differs', Info.CommitterTime <> Info.AuthorTime);
    Check('parent is first sha', Info.Parents = FirstSha);
    Check('live message', Info.Message = 'Subject line' + #10 + #10 + 'Body with, comma');
    Check('bad sha fails', Not Git.GetCommitAttributes('not-a-sha', Info));
    Check('bad sha clears record', Info.Sha = '');
  Finally
    Git.Free;
    RemoveTree(Root);
  End;
End;

Begin
  FailCount := 0;
  TestFullRecord;
  TestMessageNulAndRoot;
  TestRejectedRecords;
  TestLiveGit;
  If FailCount = 0 Then
    WriteLn('ok')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
