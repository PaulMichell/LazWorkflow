Program AssistantSearchUtilTest;

{ Console checks for grep glob / regex detection, read_file ranges, and search directory skips
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils, AssistantSearchUtil;

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

Procedure TestRegexDetect;
Begin
  Check('plain text is not regex', Not PatternLooksLikeRegex('SurveyTitle'));
  Check('pipe is regex', PatternLooksLikeRegex('SurveyTitle|TitleEdit'));
  Check('escaped-dot pipe is regex', PatternLooksLikeRegex('ProjectSurvey\.SurveyTitle|dbo\.Project'));
End;

Procedure TestGlob;
Begin
  Check('empty matches all', FileMatchesSearchGlob('Main.pas', ''));
  Check('star matches all', FileMatchesSearchGlob('Main.pas', '*'));
  Check('dot-ext', FileMatchesSearchGlob('Main.pas', '.pas'));
  Check('bare ext', FileMatchesSearchGlob('Main.pas', 'pas'));
  Check('star-ext', FileMatchesSearchGlob('Main.pas', '*.pas'));
  Check('star-ext rejects other', Not FileMatchesSearchGlob('Main.lfm', '*.pas'));
  Check('brace pas', FileMatchesSearchGlob('Main.pas', '*.{pas,lfm,sql}'));
  Check('brace lfm', FileMatchesSearchGlob('ProjectManager.lfm', '*.{pas,lfm,sql}'));
  Check('brace sql', FileMatchesSearchGlob('TransferData.sql', '*.{pas,lfm,sql,inc,lrs}'));
  Check('brace rejects md', Not FileMatchesSearchGlob('Plan.md', '*.{pas,lfm}'));
  Check('basename', FileMatchesSearchGlob('/tmp/ProjectManager.pas', 'ProjectManager.pas'));
End;

Procedure TestInvalidRegex;
Var
  Lines: TStringList;
  Count: Integer;
  Text, ErrorText: String;
  Capped, Ok: Boolean;
Begin
  Check('leading star is invalid', Pos('Invalid regular expression:', SearchPatternError('**Note**|Note:', False)) = 1);
  Check('plain text has no pattern error', SearchPatternError('Note header', False) = '');
  Check('valid alternation compiles', SearchPatternError('Note|Header', False) = '');
  Check('explicit invalid regex', Pos('Invalid regular expression:', SearchPatternError('**Note**', True)) = 1);
  Lines := TStringList.Create;
  Try
    Lines.Add('Note header');
    Count := 0;
    Text := '';
    Ok := MatchSearchLines('**Note**|Note:', 'Main.pas', Lines, False, False, 20, 512, Count, Text, Capped, ErrorText);
    Check('invalid match is an error', (Not Ok) And (Pos('Invalid regular expression:', ErrorText) = 1) And (Count = 0));
    Count := 0;
    Text := '';
    ErrorText := '';
    Ok := MatchSearchLines('Note|Header', 'Main.pas', Lines, False, False, 20, 512, Count, Text, Capped, ErrorText);
    Check('valid regex matches', Ok And (ErrorText = '') And (Count = 1) And (Pos('Main.pas:1:', Text) = 1));
  Finally
    Lines.Free;
  End;
  Ok := SearchTextMatches('**Note**|Note:', 'Main.pas', 'Note header', False, 20, Text, ErrorText);
  Check('text search reports invalid regex', (Not Ok) And (Pos('Invalid regular expression:', ErrorText) = 1));
End;

Procedure TestReadRange;
Var
  StartLine, EndLine: Integer;
Begin
  StartLine := 470;
  EndLine := 180;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('end_line as count start', StartLine = 470);
  Check('end_line as count last', EndLine = 649);

  StartLine := 580;
  EndLine := 630;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('absolute end_line kept', EndLine = 630);

  StartLine := 1;
  EndLine := 0;
  ResolveReadLineRange(StartLine, EndLine, 80);
  Check('limit from start', EndLine = 80);

  StartLine := 100;
  EndLine := 9999;
  ResolveReadLineRange(StartLine, EndLine, 50);
  Check('limit wins over end_line', EndLine = 149);

  StartLine := 0;
  EndLine := 10;
  ResolveReadLineRange(StartLine, EndLine, 0);
  Check('zero start becomes 1', StartLine = 1);
End;

Procedure WriteTextFile(Const FileName, Contents: String);
Var
  Lines: TStringList;
Begin
  ForceDirectories(ExtractFilePath(FileName));
  Lines := TStringList.Create;
  Try
    Lines.Text := Contents;
    Lines.SaveToFile(FileName);
  Finally
    Lines.Free;
  End;
End;

Procedure TouchFile(Const FileName: String);
Var
  Stream: TFileStream;
Begin
  ForceDirectories(ExtractFilePath(FileName));
  Stream := TFileStream.Create(FileName, fmCreate);
  Stream.Free;
End;

Procedure DeleteTree(Const Dir: String);
Var
  Info: TSearchRec;
  Child: String;
Begin
  If (Dir = '') Or (Not DirectoryExists(Dir)) Then Exit;
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

Function FixtureRoot(Const Leaf: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-search-skip-' + Leaf + '-' +
    FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Result);
End;

Function SearchFixture(Const Root, Query: String; Out WalkCount: Integer): String;
Var
  Files, Lines: TStringList;
  FileCount, I, MatchCount: Integer;
  RootPath, Full, Rel, Piece, ErrorText: String;
  Capped: Boolean;
Begin
  Result := '';
  WalkCount := 0;
  FileCount := 0;
  Files := TStringList.Create;
  Lines := TStringList.Create;
  Try
    If Not CollectSearchableFiles(Root, '', '', Files, FileCount, WalkCount, 2500, 20000, Nil) Then
      Begin
        Result := 'walk failed';
        Exit;
      End;
    RootPath := IncludeTrailingPathDelimiter(ExpandFileName(Root));
    For I := 0 To Files.Count - 1 Do
      Begin
        Full := Files[I];
        If Copy(Full, 1, Length(RootPath)) = RootPath Then
          Rel := Copy(Full, Length(RootPath) + 1, MaxInt)
        Else
          Rel := Full;
        Rel := StringReplace(Rel, '\', '/', [rfReplaceAll]);
        Lines.LoadFromFile(Full);
        MatchCount := 0;
        Piece := '';
        If Not MatchSearchLines(Query, Rel, Lines, False, False, 20, 512, MatchCount, Piece, Capped, ErrorText) Then
          Begin
            Result := ErrorText;
            Exit;
          End;
        Result := Result + Piece;
      End;
  Finally
    Lines.Free;
    Files.Free;
  End;
End;

Procedure TestDirectoryNames;
Begin
  Check('lib is not an always-skipped name', Not IsAlwaysSkippedSearchDirectory('lib'));
  Check('units is not an always-skipped name', Not IsAlwaysSkippedSearchDirectory('Units'));
  Check('git stays skipped', IsAlwaysSkippedSearchDirectory('.git'));
  Check('svn stays skipped', IsAlwaysSkippedSearchDirectory('.svn'));
  Check('hg stays skipped', IsAlwaysSkippedSearchDirectory('.hg'));
  Check('node_modules stays skipped', IsAlwaysSkippedSearchDirectory('node_modules'));
  Check('pycache stays skipped', IsAlwaysSkippedSearchDirectory('__pycache__'));
  Check('backup stays skipped', IsAlwaysSkippedSearchDirectory('backup'));
  Check('temporary stays skipped', IsAlwaysSkippedSearchDirectory('Temporary'));
End;

Procedure TestSourceLibIsFound;
Var
  Root, Text: String;
  WalkCount: Integer;
Begin
  Root := FixtureRoot('source');
  Try
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'lib' + PathDelim + 'Helper.pas',
      'Unit Helper; Procedure UniqueHelperToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'units' + PathDelim + 'Core' + PathDelim + 'CoreHelper.pas',
      'Unit CoreHelper; Procedure UniqueUnitsToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'App.pas',
      'Unit App; Procedure UniqueAppToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'backup' + PathDelim + 'Old.pas',
      'Unit Old; Procedure UniqueBackupToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'temporary' + PathDelim + 'Tmp.pas',
      'Unit Tmp; Procedure UniqueTemporaryToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + '.git' + PathDelim + 'hidden.pas',
      'Unit Hidden; Procedure UniqueGitToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'node_modules' + PathDelim + 'pkg' + PathDelim + 'Pkg.pas',
      'Unit Pkg; Procedure UniqueNodeToken; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + '__pycache__' + PathDelim + 'Cache.pas',
      'Unit Cache; Procedure UniquePycToken; Begin End;' + LineEnding);
    Text := SearchFixture(Root, 'UniqueHelperToken', WalkCount);
    Check('search returns lib/Helper.pas', Pos('lib/Helper.pas:', Text) > 0);
    Text := SearchFixture(Root, 'UniqueUnitsToken', WalkCount);
    Check('search returns nested units source', Pos('units/Core/CoreHelper.pas:', Text) > 0);
    Text := SearchFixture(Root, 'UniqueAppToken', WalkCount);
    Check('search returns sibling source', Pos('src/App.pas:', Text) > 0);
    Text := SearchFixture(Root, 'UniqueBackupToken|UniqueTemporaryToken|UniqueGitToken|UniqueNodeToken|UniquePycToken',
      WalkCount);
    Check('backup temporary and vcs stay hidden', Text = '');
  Finally
    DeleteTree(Root);
  End;
End;

Procedure TestObjectLibIsNotWalked;
Var
  Root, LibDir, Text: String;
  Files: TStringList;
  WalkCount, FileCount, I: Integer;
Begin
  Root := FixtureRoot('objects');
  LibDir := IncludeTrailingPathDelimiter(Root) + 'lib' + PathDelim;
  Try
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'App.pas',
      'Unit App; Procedure UniqueObjectSibling; Begin End;' + LineEnding);
    For I := 1 To 20 Do
      Begin
        TouchFile(LibDir + 'unit' + IntToStr(I) + '.ppu');
        TouchFile(LibDir + 'unit' + IntToStr(I) + '.o');
      End;
    Text := SearchFixture(Root, 'UniqueObjectSibling', WalkCount);
    Check('object lib does not hide sibling source', Pos('src/App.pas:', Text) > 0);
    Check('object-only lib is not walked file by file', WalkCount < 40);
    Files := TStringList.Create;
    Try
      FileCount := 0;
      WalkCount := 0;
      Check('object lib walk starts', CollectSearchableFiles(LibDir, '', '', Files, FileCount, WalkCount, 2500, 20000, Nil));
      Check('searching the object lib does not open each file', (WalkCount = 0) And (FileCount = 0));
    Finally
      Files.Free;
    End;
  Finally
    DeleteTree(Root);
  End;
End;

Procedure TestKnownUnitOutputIsSkipped;
Var
  Root, OutputDir, Text: String;
  WalkCount, I, FileCount: Integer;
  Files: TStringList;
Begin
  Root := FixtureRoot('output');
  OutputDir := IncludeTrailingPathDelimiter(Root) + 'output';
  Try
    WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'lib' + PathDelim + 'Helper.pas',
      'Unit Helper; Procedure UniqueKeptHelper; Begin End;' + LineEnding);
    WriteTextFile(IncludeTrailingPathDelimiter(OutputDir) + 'Hidden.pas',
      'Unit Hidden; Procedure UniqueHiddenOutput; Begin End;' + LineEnding);
    For I := 1 To 20 Do
      TouchFile(IncludeTrailingPathDelimiter(OutputDir) + 'unit' + IntToStr(I) + '.o');
    Files := TStringList.Create;
    Try
      FileCount := 0;
      WalkCount := 0;
      Check('known output walk starts', CollectSearchableFiles(Root, '', OutputDir, Files, FileCount, WalkCount, 2500,
        20000, Nil));
      Check('known unit output is not walked file by file', WalkCount < 20);
      Text := '';
      For I := 0 To Files.Count - 1 Do
        If Pos('Helper.pas', Files[I]) > 0 Then
          Text := Files[I];
      Check('source lib is kept when unit output is a different directory', Text <> '');
    Finally
      Files.Free;
    End;
    Text := SearchFixture(Root, 'UniqueKeptHelper', WalkCount);
    { SearchFixture passes an empty unit-output path, so it must still find the helper. }
    Check('unknown output still returns lib/Helper.pas', Pos('lib/Helper.pas:', Text) > 0);
    Text := '';
    Files := TStringList.Create;
    Try
      FileCount := 0;
      WalkCount := 0;
      CollectSearchableFiles(Root, '', OutputDir, Files, FileCount, WalkCount, 2500, 20000, Nil);
      For I := 0 To Files.Count - 1 Do
        If Pos('Hidden.pas', Files[I]) > 0 Then
          Text := Files[I];
      Check('configured unit output is skipped even with source inside', Text = '');
    Finally
      Files.Free;
    End;
  Finally
    DeleteTree(Root);
  End;
End;

Begin
  FailCount := 0;
  TestRegexDetect;
  TestGlob;
  TestInvalidRegex;
  TestReadRange;
  TestDirectoryNames;
  TestSourceLibIsFound;
  TestObjectLibIsNotWalked;
  TestKnownUnitOutputIsSkipped;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantSearchUtil tests passed.');
      Halt(0);
    End;
  WriteLn(FailCount, ' AssistantSearchUtil test(s) failed.');
  Halt(1);
End.
