Unit AssistantProjectPaths;

{ Resolve the project-local .assistant store after folder moves and Source-layout .lpi files (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  AssistantStoreFolderName = '.assistant';
  AssistantConversationFileName = 'conversation.jsonl';

{ Directory that should hold .assistant for this project file (trailing delimiter). Empty if none exists. }
Function ResolveAssistantProjectRoot(Const ProjectInfoFile, MainFileName: String): String;
{ If ProjectFile is missing (folder renamed), find a sibling tree that still contains that file name. }
Function LocateExistingProjectFile(Const ProjectFile: String): String;

Implementation

Uses
  LazFileUtils;

Function IsStopDir(Const Dir: String): Boolean;
Var
  D, Home: String;
Begin
  D := ExcludeTrailingPathDelimiter(Dir);
  Home := ExcludeTrailingPathDelimiter(GetUserDir);
  Result := (D = '') Or (D = '/') Or (CompareFilenames(D, Home) = 0);
  {$IFDEF WINDOWS}
  If (Length(D) = 2) And (D[2] = ':') Then
    Result := True;
  {$ENDIF}
End;

Function IsSourceLayoutDir(Const Dir: String): Boolean;
Var
  Base: String;
Begin
  Base := ExtractFileName(ExcludeTrailingPathDelimiter(Dir));
  Result := SameText(Base, 'Source') Or SameText(Base, 'src') Or SameText(Base, 'Units');
End;

Function ConversationPathInRoot(Const Root: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName + PathDelim + AssistantConversationFileName;
End;

Function ScoreAssistantRoot(Const Root: String): Integer;
Var
  Dir, Store: String;
  Entry: TSearchRec;
  Code: Integer;
  PackageOnly: Boolean;
Begin
  Result := 0;
  Dir := ExcludeTrailingPathDelimiter(Root);
  If (Dir = '') Or (Not DirectoryExistsUTF8(Dir)) Then
    Exit;
  If FileExistsUTF8(ConversationPathInRoot(Dir)) Then
    Result := 3
  Else
    Begin
      Store := IncludeTrailingPathDelimiter(Dir) + AssistantStoreFolderName;
      If DirectoryExistsUTF8(Store) Then
        Begin
          { Package namespaces must not redirect the legacy project's root
            discovery merely because a package was selected in this tree. }
          PackageOnly := DirectoryExistsUTF8(Store + PathDelim + 'targets');
          If PackageOnly Then
            Begin
              Code := FindFirstUTF8(Store + PathDelim + '*', faAnyFile, Entry);
              If Code = 0 Then
                Try
                  Repeat
                    If (Entry.Name <> '.') And (Entry.Name <> '..') And (Entry.Name <> 'targets') Then
                      Begin PackageOnly := False; Break; End;
                    Code := FindNextUTF8(Entry);
                  Until Code <> 0;
                Finally FindCloseUTF8(Entry); End;
            End;
          If Not PackageOnly Then Exit(2);
        End;
      If DirectoryExistsUTF8(IncludeTrailingPathDelimiter(Dir) + '.git') Then Result := 1;
    End;
End;

Function WalkToAssistantStoreRoot(Const StartDir: String): String;
Var
  Current, ParentDir, Best: String;
  BestScore, Step, Score: Integer;
Begin
  Result := '';
  If Trim(StartDir) = '' Then
    Exit;
  Current := IncludeTrailingPathDelimiter(ExpandFileNameUTF8(StartDir));
  If Not DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(Current)) Then
    Exit;
  If IsSourceLayoutDir(Current) Then
    Begin
      ParentDir := ExpandFileNameUTF8(Current + '..');
      If (ParentDir <> '') And DirectoryExistsUTF8(ParentDir) And (Not IsStopDir(ParentDir)) Then
        Current := IncludeTrailingPathDelimiter(ParentDir);
    End;
  Best := Current;
  BestScore := ScoreAssistantRoot(Current);
  For Step := 1 To 5 Do
    Begin
      ParentDir := ExpandFileNameUTF8(Current + '..');
      If (ParentDir = '') Or IsStopDir(ParentDir) Then
        Break;
      If CompareFilenames(ExcludeTrailingPathDelimiter(ParentDir), ExcludeTrailingPathDelimiter(Current)) = 0 Then
        Break;
      If Not DirectoryExistsUTF8(ParentDir) Then
        Break;
      Current := IncludeTrailingPathDelimiter(ParentDir);
      Score := ScoreAssistantRoot(Current);
      If Score > BestScore Then
        Begin
          Best := Current;
          BestScore := Score;
        End;
      If BestScore >= 3 Then
        Break;
    End;
  Result := IncludeTrailingPathDelimiter(Best);
End;

Function LocateExistingProjectFile(Const ProjectFile: String): String;
Var
  Missing, Rel, Current, ParentDir, Child, Probe, Best: String;
  BestScore, Score, Code: Integer;
  Info: TSearchRec;
Begin
  Result := '';
  If Trim(ProjectFile) = '' Then
    Exit;
  If FileExistsUTF8(ProjectFile) Then
    Begin
      Result := ExpandFileNameUTF8(ProjectFile);
      Exit;
    End;
  Missing := ExpandFileNameUTF8(ProjectFile);
  Rel := ExtractFileName(Missing);
  If Rel = '' Then
    Exit;
  Current := ExcludeTrailingPathDelimiter(ExtractFilePath(Missing));
  Best := '';
  BestScore := -1;
  While (Current <> '') And (Not IsStopDir(Current)) Do
    Begin
      ParentDir := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(IncludeTrailingPathDelimiter(Current) + '..'));
      If (ParentDir = '') Or (CompareFilenames(ParentDir, Current) = 0) Then
        Break;
      If DirectoryExistsUTF8(ParentDir) Then
        Begin
          Code := FindFirstUTF8(IncludeTrailingPathDelimiter(ParentDir) + '*', faAnyFile, Info);
          Try
            While Code = 0 Do
              Begin
                If (Info.Name <> '.') And (Info.Name <> '..') And ((Info.Attr And faDirectory) <> 0) Then
                  Begin
                    Child := IncludeTrailingPathDelimiter(ParentDir) + Info.Name;
                    If DirectoryExistsUTF8(Child) Then
                      Begin
                        Probe := IncludeTrailingPathDelimiter(Child) + Rel;
                        If FileExistsUTF8(Probe) Then
                          Begin
                            Score := ScoreAssistantRoot(WalkToAssistantStoreRoot(ExtractFilePath(Probe)));
                            If Score > BestScore Then
                              Begin
                                Best := Probe;
                                BestScore := Score;
                              End;
                          End;
                      End;
                  End;
                Code := FindNextUTF8(Info);
              End;
          Finally
            FindCloseUTF8(Info);
          End;
          If BestScore >= 3 Then
            Break;
        End;
      Rel := ExtractFileName(Current) + PathDelim + Rel;
      Current := ParentDir;
    End;
  Result := Best;
End;

Function ResolveAssistantProjectRoot(Const ProjectInfoFile, MainFileName: String): String;
Var
  InfoFile, Dir: String;
Begin
  Result := '';
  InfoFile := '';
  If Trim(ProjectInfoFile) <> '' Then
    InfoFile := LocateExistingProjectFile(ProjectInfoFile);
  If InfoFile = '' Then
    If Trim(MainFileName) <> '' Then
      InfoFile := LocateExistingProjectFile(MainFileName);
  If InfoFile = '' Then
    Exit;
  Dir := ExtractFilePath(InfoFile);
  If (Dir = '') Or (Not DirectoryExistsUTF8(Dir)) Then
    Exit;
  Result := WalkToAssistantStoreRoot(Dir);
End;

End.
