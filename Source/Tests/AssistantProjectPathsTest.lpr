Program AssistantProjectPathsTest;

{ Console checks for .assistant root lookup after a project folder rename (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  BaseUnix,
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

Procedure TestActualFolderRename;
Var
  Base, OldRoot, NewRoot, RelativeLpi, Root: String;
Begin
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'lazasst-rename-' + FormatDateTime('hhnnsszzz', Now);
  OldRoot := IncludeTrailingPathDelimiter(Base) + 'EcologySurveryScheduler';
  NewRoot := IncludeTrailingPathDelimiter(Base) + 'EcologySurveyScheduler';
  RelativeLpi := 'Source' + PathDelim + 'EcologySurveryScheduler.lpi';
  Try
    WriteTextFile(IncludeTrailingPathDelimiter(OldRoot) + RelativeLpi, '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(OldRoot) + AssistantStoreFolderName +
      PathDelim + AssistantConversationFileName, '{"id":"fixture"}');
    Check('fixture project folder renamed', RenameFile(OldRoot, NewRoot));
    Root := ResolveAssistantProjectRoot(IncludeTrailingPathDelimiter(OldRoot) + RelativeLpi, '');
    Check('recent-project path resolves actual rename', SameDir(Root, NewRoot));
    Root := ResolveAssistantProjectRoot(IncludeTrailingPathDelimiter(NewRoot) + RelativeLpi, '');
    Check('opened renamed project uses repo assistant store', SameDir(Root, NewRoot));
  Finally
    DeleteTree(Base);
  End;
End;

Procedure TestFolderCompileFiles;
Var
  Base, Root: String;
  Files: TStringList;
  Function Listed(Const RelativePath: String): Boolean;
  Begin
    Result := Files.IndexOf(ExpandFileName(IncludeTrailingPathDelimiter(Root) + RelativePath)) >= 0;
  End;
Begin
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'lazasst-compile-' + FormatDateTime('hhnnsszzz', Now);
  Root := IncludeTrailingPathDelimiter(Base) + 'Repo';
  Files := TStringList.Create;
  Try
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Packages/LazAssistantTools.lpk', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Packages/LazWorkflowCommon.lpk', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'dummy.lpi', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Source/Tools/PascalStyle.lpi', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'lib/hidden.lpi', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Lib/hidden.lpk', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Backup/old.lpk', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + '.git/hidden.lpk', '<CONFIG/>');
    WriteTextFile(IncludeTrailingPathDelimiter(Base) + 'Outside/escaped.lpk', '<CONFIG/>');
    {$IFDEF UNIX}
    Check('directory symlink created',
      FpSymlink(PChar(IncludeTrailingPathDelimiter(Base) + 'Outside'), PChar(IncludeTrailingPathDelimiter(Root) + 'Packages/Link')) = 0);
    Check('package symlink created',
      FpSymlink(PChar(IncludeTrailingPathDelimiter(Base) + 'Outside/escaped.lpk'),
        PChar(IncludeTrailingPathDelimiter(Root) + 'Packages/link.lpk')) = 0);
    {$ENDIF}
    CollectFolderCompileFiles(Root, Files);
    Check('folder compile keeps both packages', (Files.Count = 2) And
      Listed('Packages/LazAssistantTools.lpk') And Listed('Packages/LazWorkflowCommon.lpk'));
    Check('folder compile skips projects, output, backup, and hidden files',
      Not Listed('dummy.lpi') And Not Listed('Source/Tools/PascalStyle.lpi') And
      Not Listed('lib/hidden.lpi') And Not Listed('Lib/hidden.lpk') And
      Not Listed('Backup/old.lpk') And Not Listed('.git/hidden.lpk') And Not Listed('Packages/link.lpk'));
    DeleteFile(IncludeTrailingPathDelimiter(Root) + 'Packages/LazAssistantTools.lpk');
    DeleteFile(IncludeTrailingPathDelimiter(Root) + 'Packages/LazWorkflowCommon.lpk');
    CollectFolderCompileFiles(Root, Files);
    Check('folder without a package compiles its projects', (Files.Count = 2) And
      Listed('dummy.lpi') And Listed('Source/Tools/PascalStyle.lpi'));
    CollectFolderCompileFiles(IncludeTrailingPathDelimiter(Base) + 'Missing', Files);
    Check('missing folder compiles nothing', Files.Count = 0);
  Finally
    {$IFDEF UNIX}
    FpUnlink(PChar(IncludeTrailingPathDelimiter(Root) + 'Packages/Link'));
    FpUnlink(PChar(IncludeTrailingPathDelimiter(Root) + 'Packages/link.lpk'));
    {$ENDIF}
    Files.Free;
    DeleteTree(Base);
  End;
End;

Begin
  FailCount := 0;
  TestRenameFindsAssistant;
  TestFolderCompileFiles;
  TestNestedProjectWalksToRepoAssistant;
  TestMissingPathWithoutSiblingIsEmpty;
  TestActualFolderRename;
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
