Unit AssistantSearchUtil;

{ Grep glob, regex, line ranges, and which directories search may enter (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes;

Type
  { Nil means the walk does not stop. }
  TSearchStopQuery = Function: Boolean;

{ True when the pattern is almost certainly a regex (unescaped | is the usual case). }
Function PatternLooksLikeRegex(Const Pattern: String): Boolean;
{ Empty glob matches every name. Supports .pas, pas, *.pas, and brace lists. }
Function FileMatchesSearchGlob(Const FileName, Glob: String): Boolean;
{ start_line is 1-based. limit is a line count. If limit is 0 and end_line < start_line,
  end_line is treated as a line count (Grok Build habit). }
Procedure ResolveReadLineRange(Var StartLine, EndLine: Integer; Limit: Integer);
{ Empty when the query can be searched. Explicit regex, or a pattern that looks like one, is compiled. }
Function SearchPatternError(Const Query: String; ExplicitRegex: Boolean): String;
{ Case-insensitive line search used by search_in_project.
  files_only emits the path once. Capped is true when MaxResults is reached; the cap notice is already appended. }
Function MatchSearchLines(Const Query, RelativePath: String; Lines: TStrings; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
{ Same rules against one buffer. Line numbers come from #13/#10 offsets. A final break does not add a blank line.
  Do not assign TStringList.Text for the scan. }
Function MatchSearchText(Const Query, RelativePath, Text: String; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
{ Search one text with those rules. MaxResults must be 1..200. }
Function SearchTextMatches(Const Query, RelativePath, Text: String; FilesOnly: Boolean; MaxResults: Integer;
  Out ResultText, ErrorText: String): Boolean;

{ VCS metadata, package caches, and local copies. Not lib or units: those names also hold source. }
Function IsAlwaysSkippedSearchDirectory(Const DirName: String): Boolean;
{ KnownUnitOutput empty means the project output path is unknown.
  A known unit-output directory is skipped even if it contains source. A lib or units directory is skipped
  only when it contains no .pas, .pp, .inc, .lfm, or .lpr. The search walk does not enter a skipped directory. }
Function ShouldSkipSearchDirectory(Const DirectoryPath, DirectoryName, KnownUnitOutput: String;
  ShouldStop: TSearchStopQuery): Boolean;
{ Disk walk used by grep. WalkCount counts entries this walk opens, not files inside a skipped directory. }
Function CollectSearchableFiles(Const DirPath, Glob, KnownUnitOutput: String; Files: TStrings;
  Var FileCount, WalkCount: Integer; MaxFiles, MaxWalk: Integer; ShouldStop: TSearchStopQuery): Boolean;

Implementation

Uses
  SysUtils, LazFileUtils, DirectoryListing, RegExpr;

Const
  SearchMatchLineChars = 512;
  SearchSourceProbeMaxDepth = 40;

Function PatternLooksLikeRegex(Const Pattern: String): Boolean;
Begin
  Result := Pos('|', Pattern) > 0;
End;

Function FileMatchesSearchGlob(Const FileName, Glob: String): Boolean;
Var
  G, Ext, Prefix, Suffix, Alts, Alt, Combined: String;
  BraceOpen, BraceClose, CommaAt: Integer;
Begin
  G := Trim(Glob);
  If (G = '') Or (G = '*') Or (G = '*.*') Then
    Begin
      Result := True;
      Exit;
    End;
  BraceOpen := Pos('{', G);
  BraceClose := 0;
  If BraceOpen > 0 Then
    BraceClose := Pos('}', G);
  If (BraceOpen > 0) And (BraceClose > BraceOpen) Then
    Begin
      Prefix := Copy(G, 1, BraceOpen - 1);
      Suffix := Copy(G, BraceClose + 1, MaxInt);
      Alts := Copy(G, BraceOpen + 1, BraceClose - BraceOpen - 1);
      Result := False;
      While Alts <> '' Do
        Begin
          CommaAt := Pos(',', Alts);
          If CommaAt < 1 Then
            Begin
              Alt := Trim(Alts);
              Alts := '';
            End
          Else
            Begin
              Alt := Trim(Copy(Alts, 1, CommaAt - 1));
              Delete(Alts, 1, CommaAt);
            End;
          If Alt = '' Then
            Continue;
          Combined := Prefix + Alt + Suffix;
          If FileMatchesSearchGlob(FileName, Combined) Then
            Begin
              Result := True;
              Exit;
            End;
        End;
      Exit;
    End;
  Ext := LowerCase(ExtractFileExt(FileName));
  G := LowerCase(G);
  If (Length(G) >= 2) And (G[1] = '*') And (G[2] = '.') Then
    G := Copy(G, 2, MaxInt)
  Else If (Length(G) > 0) And (G[1] <> '.') And (Pos('.', G) < 1) Then
    G := '.' + G;
  Result := Ext = G;
  If Not Result Then
    Result := LowerCase(ExtractFileName(FileName)) = LowerCase(Trim(Glob));
End;

Procedure ResolveReadLineRange(Var StartLine, EndLine: Integer; Limit: Integer);
Begin
  If StartLine < 1 Then
    StartLine := 1;
  If Limit > 0 Then
    EndLine := StartLine + Limit - 1
  Else If (EndLine > 0) And (EndLine < StartLine) Then
    EndLine := StartLine + EndLine - 1;
End;

{ SetExpression only stores the pattern. Compile raises ERegExpr now, not later in Exec. }
Function CompileSearchExpression(Re: TRegExpr; Const Query: String): String;
Begin
  Result := '';
  If Not Assigned(Re) Then
    Begin
      Result := 'Search text is unavailable.';
      Exit;
    End;
  Try
    Re.ModifierI := True;
    Re.Expression := Query;
    Re.Compile;
  Except
    On E: Exception Do
      Result := 'Invalid regular expression: ' + E.Message;
  End;
End;

Function SearchPatternError(Const Query: String; ExplicitRegex: Boolean): String;
Var
  Re: TRegExpr;
Begin
  Result := '';
  If Not (ExplicitRegex Or PatternLooksLikeRegex(Query)) Then
    Exit;
  Re := TRegExpr.Create;
  Try
    Result := CompileSearchExpression(Re, Query);
  Finally
    Re.Free;
  End;
End;

Function MatchSearchLines(Const Query, RelativePath: String; Lines: TStrings; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
Var
  Re: TRegExpr;
  LineNo: Integer;
  LineText, LowerQuery: String;
  Hit, Emitted: Boolean;
Begin
  Result := False;
  Capped := False;
  ErrorText := '';
  Re := Nil;
  If Not Assigned(Lines) Then
    Begin
      ErrorText := 'Search text is unavailable.';
      Exit;
    End;
  If UseRegex Or PatternLooksLikeRegex(Query) Then
    Begin
      Re := TRegExpr.Create;
      ErrorText := CompileSearchExpression(Re, Query);
      If ErrorText <> '' Then
        Begin
          FreeAndNil(Re);
          Exit;
        End;
    End;
  Try
    LowerQuery := LowerCase(Query);
    Emitted := False;
    For LineNo := 0 To Lines.Count - 1 Do
      Begin
        LineText := Lines[LineNo];
        If Assigned(Re) Then
          Begin
            If Length(LineText) > MaxLineChars Then
              Continue;
            Try
              Hit := Re.Exec(LineText);
            Except
              On E: Exception Do
                Begin
                  ErrorText := 'Invalid regular expression: ' + E.Message;
                  Exit;
                End;
            End;
          End
        Else
          Hit := Pos(LowerQuery, LowerCase(LineText)) > 0;
        If Not Hit Then
          Continue;
        If FilesOnly Then
          Begin
            If Emitted Then
              Continue;
            Emitted := True;
            Inc(MatchCount);
            ResultText := ResultText + RelativePath + LineEnding;
          End
        Else
          Begin
            Inc(MatchCount);
            ResultText := ResultText + Format('%s:%d: %s', [RelativePath, LineNo + 1, Trim(LineText)]) + LineEnding;
          End;
        If MatchCount >= MaxResults Then
          Begin
            ResultText := ResultText + Format('[… capped at %d matches …]', [MaxResults]);
            Capped := True;
            Result := True;
            Exit;
          End;
      End;
    Result := True;
  Finally
    Re.Free;
  End;
End;

{ #13, #10, and #13#10 are breaks. A final break does not invent the extra blank line TStringList.Text can add. }
Function NextSearchLine(Const Text: String; Var Position: Integer; Out LineText: String): Boolean;
Var
  Start, Len: Integer;
Begin
  Len := Length(Text);
  If (Position < 1) Or (Position > Len) Then
    Exit(False);
  Start := Position;
  While (Position <= Len) And (Text[Position] <> #10) And (Text[Position] <> #13) Do
    Inc(Position);
  LineText := Copy(Text, Start, Position - Start);
  If (Position <= Len) And (Text[Position] = #13) Then
    Inc(Position);
  If (Position <= Len) And (Text[Position] = #10) Then
    Inc(Position);
  Result := True;
End;

Function MatchSearchText(Const Query, RelativePath, Text: String; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
Var
  Re: TRegExpr;
  Position, LineNo: Integer;
  LineText, LowerQuery: String;
  Hit, Emitted: Boolean;
Begin
  Result := False;
  Capped := False;
  ErrorText := '';
  Re := Nil;
  If UseRegex Or PatternLooksLikeRegex(Query) Then
    Begin
      Re := TRegExpr.Create;
      ErrorText := CompileSearchExpression(Re, Query);
      If ErrorText <> '' Then
        Begin
          FreeAndNil(Re);
          Exit;
        End;
    End;
  Try
    LowerQuery := LowerCase(Query);
    Emitted := False;
    Position := 1;
    LineNo := 0;
    While NextSearchLine(Text, Position, LineText) Do
      Begin
        Inc(LineNo);
        If Assigned(Re) Then
          Begin
            If Length(LineText) > MaxLineChars Then
              Continue;
            Try
              Hit := Re.Exec(LineText);
            Except
              On E: Exception Do
                Begin
                  ErrorText := 'Invalid regular expression: ' + E.Message;
                  Exit;
                End;
            End;
          End
        Else
          Hit := Pos(LowerQuery, LowerCase(LineText)) > 0;
        If Not Hit Then
          Continue;
        If FilesOnly Then
          Begin
            If Emitted Then
              Continue;
            Emitted := True;
            Inc(MatchCount);
            ResultText := ResultText + RelativePath + LineEnding;
          End
        Else
          Begin
            Inc(MatchCount);
            ResultText := ResultText + Format('%s:%d: %s', [RelativePath, LineNo, Trim(LineText)]) + LineEnding;
          End;
        If MatchCount >= MaxResults Then
          Begin
            ResultText := ResultText + Format('[… capped at %d matches …]', [MaxResults]);
            Capped := True;
            Result := True;
            Exit;
          End;
      End;
    Result := True;
  Finally
    Re.Free;
  End;
End;

Function SearchTextMatches(Const Query, RelativePath, Text: String; FilesOnly: Boolean; MaxResults: Integer;
  Out ResultText, ErrorText: String): Boolean;
Var
  MatchCount: Integer;
  Capped: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Trim(Query) = '' Then
    Begin
      ErrorText := 'grep/search_in_project requires pattern or query.';
      Exit;
    End;
  If (MaxResults < 1) Or (MaxResults > 200) Then
    Begin
      ErrorText := 'max_results must be an integer from 1 to 200.';
      Exit;
    End;
  MatchCount := 0;
  Result := MatchSearchText(Query, RelativePath, Text, False, FilesOnly, MaxResults, SearchMatchLineChars,
    MatchCount, ResultText, Capped, ErrorText);
End;

Function IsAlwaysSkippedSearchDirectory(Const DirName: String): Boolean;
Var
  N: String;
Begin
  N := LowerCase(DirName);
  Result := (N = '.git') Or (N = '.svn') Or (N = '.hg') Or (N = 'node_modules') Or
    (N = '__pycache__') Or (N = 'backup') Or (N = 'temporary') Or (N = '.grok') Or (N = '.assistant');
End;

Function IsLibOrUnitsDirectoryName(Const DirName: String): Boolean;
Var
  N: String;
Begin
  N := LowerCase(DirName);
  Result := (N = 'lib') Or (N = 'units');
End;

Function SameSearchDirectory(Const Left, Right: String): Boolean;
Var
  LeftPath, RightPath: String;
Begin
  LeftPath := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(Trim(Left)));
  RightPath := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(Trim(Right)));
  Result := (LeftPath <> '') And (RightPath <> '') And (CompareFilenames(LeftPath, RightPath) = 0);
End;

Function IsSearchableSourceExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.inc') Or (Ext = '.lfm') Or (Ext = '.lpr');
End;

Function IsSearchableTextExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '') Or (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or
    (Ext = '.lfm') Or (Ext = '.lrs') Or (Ext = '.inc') Or (Ext = '.txt') Or
    (Ext = '.md') Or (Ext = '.json') Or (Ext = '.xml') Or (Ext = '.lpi') Or
    (Ext = '.lpk') Or (Ext = '.rc') Or (Ext = '.sql') Or (Ext = '.sh') Or
    (Ext = '.bat') Or (Ext = '.csv') Or (Ext = '.ini') Or (Ext = '.cfg') Or
    (Ext = '.yml') Or (Ext = '.yaml') Or (Ext = '.html') Or (Ext = '.css');
End;

{ Depth past the limit is treated as source so a link cycle cannot hide a real tree. }
Function DirectoryContainsSearchableSource(Const DirPath, KnownUnitOutput: String; Depth: Integer;
  ShouldStop: TSearchStopQuery): Boolean;
Var
  Info: TDirectoryScan;
  Code: Integer;
  Child: String;
Begin
  Result := False;
  If Depth > SearchSourceProbeMaxDepth Then
    Begin
      Result := True;
      Exit;
    End;
  If Assigned(ShouldStop) And ShouldStop() Then
    Begin
      Result := True;
      Exit;
    End;
  If (KnownUnitOutput <> '') And SameSearchDirectory(DirPath, KnownUnitOutput) Then Exit;
  Code := StartDirectoryScan(IncludeTrailingPathDelimiter(DirPath) + '*', faAnyFile, Info);
  Try
    While Code = 0 Do
      Begin
        If (Info.Name <> '.') And (Info.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(DirPath) + Info.Name;
            If (Info.Attr And faDirectory) <> 0 Then
              Begin
                If Not IsAlwaysSkippedSearchDirectory(Info.Name) And
                  DirectoryContainsSearchableSource(Child, KnownUnitOutput, Depth + 1, ShouldStop) Then
                  Exit(True);
              End
            Else If IsSearchableSourceExtension(Info.Name) Then
              Exit(True);
          End;
        Code := AdvanceDirectoryScan(Info);
      End;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Function ShouldSkipSearchDirectory(Const DirectoryPath, DirectoryName, KnownUnitOutput: String;
  ShouldStop: TSearchStopQuery): Boolean;
Begin
  If IsAlwaysSkippedSearchDirectory(DirectoryName) Then
    Exit(True);
  If (KnownUnitOutput <> '') And SameSearchDirectory(DirectoryPath, KnownUnitOutput) Then
    Exit(True);
  If IsLibOrUnitsDirectoryName(DirectoryName) Then
    Exit(Not DirectoryContainsSearchableSource(DirectoryPath, KnownUnitOutput, 0, ShouldStop));
  Result := False;
End;

Function CollectSearchableFiles(Const DirPath, Glob, KnownUnitOutput: String; Files: TStrings;
  Var FileCount, WalkCount: Integer; MaxFiles, MaxWalk: Integer; ShouldStop: TSearchStopQuery): Boolean;
Var
  Info: TDirectoryScan;
  Child: String;
  Code: Integer;
Begin
  Result := True;
  If Not Assigned(Files) Then
    Begin
      Result := False;
      Exit;
    End;
  If Assigned(ShouldStop) And ShouldStop() Then
    Begin
      Result := False;
      Exit;
    End;
  If (MaxFiles > 0) And (FileCount >= MaxFiles) Then Exit;
  { A skipped directory is not opened, so its object files are not walked one by one. }
  If ShouldSkipSearchDirectory(DirPath, ExtractFileName(ExcludeTrailingPathDelimiter(DirPath)), KnownUnitOutput,
    ShouldStop) Then
    Exit;
  Code := StartDirectoryScan(IncludeTrailingPathDelimiter(DirPath) + '*', faAnyFile, Info);
  Try
    While Code = 0 Do
      Begin
        If Assigned(ShouldStop) And ShouldStop() Then
          Begin
            Result := False;
            Exit;
          End;
        Inc(WalkCount);
        If (MaxWalk > 0) And (WalkCount > MaxWalk) Then
          Begin
            Result := False;
            Exit;
          End;
        If (Info.Name <> '.') And (Info.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(DirPath) + Info.Name;
            If (Info.Attr And faDirectory) <> 0 Then
              Begin
                If Not CollectSearchableFiles(Child, Glob, KnownUnitOutput, Files, FileCount, WalkCount, MaxFiles,
                  MaxWalk, ShouldStop) Then
                  Begin
                    Result := False;
                    Exit;
                  End;
              End
            Else If IsSearchableTextExtension(Child) And FileMatchesSearchGlob(Child, Glob) Then
              Begin
                Files.Add(Child);
                Inc(FileCount);
                If (MaxFiles > 0) And (FileCount >= MaxFiles) Then Exit;
              End;
          End;
        If (MaxFiles > 0) And (FileCount >= MaxFiles) Then Exit;
        Code := AdvanceDirectoryScan(Info);
      End;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

End.
