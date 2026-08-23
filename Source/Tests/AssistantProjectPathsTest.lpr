Program AssistantProjectPathsTest;

{ Console checks for .assistant root lookup after a project folder rename (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantProjectPaths;

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

Function SameDir(Const LeftPath, RightPath: String): Boolean;
Begin
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(LeftPath)) =
    ExcludeTrailingPathDelimiter(ExpandFileName(RightPath));
End;

Procedure WriteTextFile(Const FileName, Contents: String);
Var
  SL: TStringList;
Begin
  ForceDirectories(ExtractFilePath(FileName));
  SL := TStringList.Create;
  Try
    SL.Text := Contents;
    SL.SaveToFile(FileName);
  Finally
    SL.Free;
  End;
End;

Procedure DeleteTree(Const Dir: String);
Var
  Info: TSearchRec;
  Child: String;
Begin
  If (Dir = '') Or (Not DirectoryExists(Dir)) Then
    Exit;
  If FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, Info) = 0 Then
    Try
      Repeat
        If (Info.Name <> '.') And (Info.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(Dir) + Info.Name;
            If (Info.Attr And faDirectory) <> 0 Then
              DeleteTree(Child)
            Else
              DeleteFile(Child);
          End;
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  RmDir(Dir);
End;

Procedure TestRenameFindsAssistant;
Var
  Base, OldRepo, NewRepo, OldLpi, NewLpi, Conv, Root: String;
Begin
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'lazasst-root-' + FormatDateTime('hhnnsszzz', Now);
  OldRepo := IncludeTrailingPathDelimiter(Base) + 'EcologySurveryScheduler';
  NewRepo := IncludeTrailingPathDelimiter(Base) + 'EcologySurveyScheduler';
  Try
    NewLpi := IncludeTrailingPathDelimiter(NewRepo) + 'Source' + PathDelim + 'EcologySurveryScheduler.lpi';
    Conv := IncludeTrailingPathDelimiter(NewRepo) + AssistantStoreFolderName + PathDelim + AssistantConversationFileName;
    WriteTextFile(NewLpi, '<?xml version="1.0"?><CONFIG/>');
    WriteTextFile(Conv, '{"id":"t1","prompt":"hello"}' + LineEnding);
    OldLpi := IncludeTrailingPathDelimiter(OldRepo) + 'Source' + PathDelim + 'EcologySurveryScheduler.lpi';
    Root := ResolveAssistantProjectRoot(OldLpi, '');
    Check('stale path finds renamed repo', SameDir(Root, NewRepo));
    Root := ResolveAssistantProjectRoot(NewLpi, '');
    Check('new path finds repo with .assistant', SameDir(Root, NewRepo));
    Root := ResolveAssistantProjectRoot('', IncludeTrailingPathDelimiter(NewRepo) + 'Source' + PathDelim + 'Main.pas');
    Check('missing main file does not invent a root', Root = '');
    WriteTextFile(IncludeTrailingPathDelimiter(NewRepo) + 'Source' + PathDelim + 'Main.pas', 'Unit Main;' + LineEnding);
    Root := ResolveAssistantProjectRoot('', IncludeTrailingPathDelimiter(NewRepo) + 'Source' + PathDelim + 'Main.pas');
    Check('main file under Source walks to repo', SameDir(Root, NewRepo));
  Finally
    DeleteTree(Base);
  End;
End;

Procedure TestNestedProjectWalksToRepoAssistant;
Var
  Base, Repo, NestedLpi, Root: String;
Begin
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'lazasst-nested-' + FormatDateTime('hhnnsszzz', Now);
  Repo := IncludeTrailingPathDelimiter(Base) + 'EcologySurveyScheduler';
  Try
    NestedLpi := IncludeTrailingPathDelimiter(Repo) + 'WorkProgrammingSource' + PathDelim + 'WorkProgramming.lpi';
    WriteTextFile(NestedLpi, '<?xml version="1.0"?><CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Repo) + AssistantStoreFolderName + PathDelim + AssistantConversationFileName,
      '{"id":"t1"}' + LineEnding);
    Root := ResolveAssistantProjectRoot(NestedLpi, '');
    Check('nested .lpi walks up to repo .assistant', SameDir(Root, Repo));
  Finally
    DeleteTree(Base);
  End;
End;

Procedure TestMissingPathWithoutSiblingIsEmpty;
Var
  Root: String;
Begin
  Root := ResolveAssistantProjectRoot('/no/such/EcologySurveryScheduler/Source/App.lpi', '');
  Check('missing tree without a sibling is empty', Root = '');
End;

Procedure TestRealRenamedEcologyFolder;
Var
  Root, NewRoot: String;
Begin
  NewRoot := '/home/paul/Projects/EcologySurveyScheduler';
  If Not DirectoryExists(NewRoot) Then
    Begin
      WriteLn('skip  real EcologySurveyScheduler tree not present');
      Exit;
    End;
  Root := ResolveAssistantProjectRoot(
    '/home/paul/Projects/EcologySurveryScheduler/Source/EcologySurveryScheduler.lpi', '');
  Check('Lazarus recent-project path finds EcologySurveyScheduler', SameDir(Root, NewRoot));
  Root := ResolveAssistantProjectRoot(
    '/home/paul/Projects/EcologySurveyScheduler/Source/EcologySurveryScheduler.lpi', '');
  Check('opened EcologySurveyScheduler.lpi uses repo .assistant', SameDir(Root, NewRoot));
End;

Begin
  FailCount := 0;
  TestRenameFindsAssistant;
  TestNestedProjectWalksToRepoAssistant;
  TestMissingPathWithoutSiblingIsEmpty;
  TestRealRenamedEcologyFolder;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantProjectPaths tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantProjectPaths test(s) failed.');
      Halt(1);
    End;
End.
