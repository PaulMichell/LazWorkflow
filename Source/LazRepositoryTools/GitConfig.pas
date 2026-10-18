Unit GitConfig;

{ Persistent LazRepositoryTools settings (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  GitConfigDefaultAutoRefresh = True;
  GitConfigDefaultIntervalSec = 5;
  GitConfigMinIntervalSec = 2;
  GitConfigMaxIntervalSec = 3600;
  GitConfigDefaultGraphFontSize = 9;
  GitConfigMinGraphFontSize = 6;
  GitConfigMaxGraphFontSize = 24;
  GitConfigDefaultRecentCount = 5;
  GitConfigMinRecentCount = 1;
  GitConfigMaxRecentCount = 30;

Type
  TGitConfig = Class
  Private
    FAutoRefresh: Boolean;
    FAutoRefreshSeconds: Integer;
    FGraphFontName: String;
    FGraphFontSize: Integer;
    FRecentCount: Integer;
    FRecentPaths: TStringList;
    Procedure SetAutoRefreshSeconds(Value: Integer);
    Procedure SetGraphFontSize(Value: Integer);
    Procedure SetGraphFontName(Const Value: String);
    Procedure SetRecentCount(Value: Integer);
    Function IndexOfRecentPath(Const Path: String): Integer;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Load;
    Procedure Save;
    Procedure Assign(Source: TGitConfig);
    /// Move a repository root to the front of the recent list and save. Missing folders are ignored.
    Procedure RememberRepository(Const RepoPath: String);
    /// Drop a path from the recent list and save. A path that is not stored is left unchanged.
    Procedure ForgetRepository(Const RepoPath: String);
    /// Newest first, limited to RecentCount. Storage keeps up to GitConfigMaxRecentCount so raising the setting restores older paths.
    Procedure CopyRecentPaths(Paths: TStrings);
    Property AutoRefresh: Boolean Read FAutoRefresh Write FAutoRefresh;
    Property AutoRefreshSeconds: Integer Read FAutoRefreshSeconds Write SetAutoRefreshSeconds;
    { Empty GraphFontName means use the form font name at draw time. }
    Property GraphFontName: String Read FGraphFontName Write SetGraphFontName;
    Property GraphFontSize: Integer Read FGraphFontSize Write SetGraphFontSize;
    Property RecentCount: Integer Read FRecentCount Write SetRecentCount;
  End;

Var
  GitManagerConfig: TGitConfig;

Implementation

Uses
  fpjson, LazFileUtils, WorkflowSettings;

Function NormalizeRepositoryPath(Const RepoPath: String): String;
Begin
  Result := Trim(RepoPath);
  If Result = '' Then Exit;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
End;

Constructor TGitConfig.Create;
Begin
  Inherited Create;
  FAutoRefresh := GitConfigDefaultAutoRefresh;
  FAutoRefreshSeconds := GitConfigDefaultIntervalSec;
  FGraphFontName := '';
  FGraphFontSize := GitConfigDefaultGraphFontSize;
  FRecentCount := GitConfigDefaultRecentCount;
  FRecentPaths := TStringList.Create;
End;

Destructor TGitConfig.Destroy;
Begin
  FreeAndNil(FRecentPaths);
  Inherited Destroy;
End;

Procedure TGitConfig.SetAutoRefreshSeconds(Value: Integer);
Begin
  If Value < GitConfigMinIntervalSec Then
    Value := GitConfigMinIntervalSec;
  If Value > GitConfigMaxIntervalSec Then
    Value := GitConfigMaxIntervalSec;
  FAutoRefreshSeconds := Value;
End;

Procedure TGitConfig.SetGraphFontSize(Value: Integer);
Begin
  If Value < GitConfigMinGraphFontSize Then
    Value := GitConfigMinGraphFontSize;
  If Value > GitConfigMaxGraphFontSize Then
    Value := GitConfigMaxGraphFontSize;
  FGraphFontSize := Value;
End;

Procedure TGitConfig.SetGraphFontName(Const Value: String);
Begin
  FGraphFontName := Trim(Value);
End;

Procedure TGitConfig.SetRecentCount(Value: Integer);
Begin
  If Value < GitConfigMinRecentCount Then
    Value := GitConfigMinRecentCount;
  If Value > GitConfigMaxRecentCount Then
    Value := GitConfigMaxRecentCount;
  FRecentCount := Value;
End;

Function TGitConfig.IndexOfRecentPath(Const Path: String): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  If Not Assigned(FRecentPaths) Then Exit;
  For Index := 0 To FRecentPaths.Count - 1 Do
    If CompareFilenames(FRecentPaths[Index], Path) = 0 Then
      Exit(Index);
End;

Procedure TGitConfig.RememberRepository(Const RepoPath: String);
Var
  Path: String;
  Index: Integer;
Begin
  Path := NormalizeRepositoryPath(RepoPath);
  If (Path = '') Or (Not DirectoryExistsUTF8(Path)) Then Exit;
  Index := IndexOfRecentPath(Path);
  If Index = 0 Then Exit;
  If Index > 0 Then FRecentPaths.Delete(Index);
  FRecentPaths.Insert(0, Path);
  While FRecentPaths.Count > GitConfigMaxRecentCount Do
    FRecentPaths.Delete(FRecentPaths.Count - 1);
  Save;
End;

Procedure TGitConfig.ForgetRepository(Const RepoPath: String);
Var
  Path: String;
  Index: Integer;
Begin
  Path := NormalizeRepositoryPath(RepoPath);
  If Path = '' Then Exit;
  Index := IndexOfRecentPath(Path);
  If Index < 0 Then Exit;
  FRecentPaths.Delete(Index);
  Save;
End;

Procedure TGitConfig.CopyRecentPaths(Paths: TStrings);
Var
  Index, Limit: Integer;
Begin
  If Not Assigned(Paths) Then Exit;
  Paths.Clear;
  If Not Assigned(FRecentPaths) Then Exit;
  Limit := FRecentCount;
  If Limit > FRecentPaths.Count Then Limit := FRecentPaths.Count;
  For Index := 0 To Limit - 1 Do
    Paths.Add(FRecentPaths[Index]);
End;

Procedure TGitConfig.Assign(Source: TGitConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FAutoRefresh := Source.AutoRefresh;
  AutoRefreshSeconds := Source.AutoRefreshSeconds;
  GraphFontName := Source.GraphFontName;
  GraphFontSize := Source.GraphFontSize;
  RecentCount := Source.RecentCount;
  FRecentPaths.Assign(Source.FRecentPaths);
End;

Procedure TGitConfig.Load;
Var
  Section: TJSONObject;
  Node: TJSONData;
  Index: Integer;
  Path: String;
Begin
  FAutoRefresh := GitConfigDefaultAutoRefresh;
  AutoRefreshSeconds := GitConfigDefaultIntervalSec;
  GraphFontName := '';
  GraphFontSize := GitConfigDefaultGraphFontSize;
  RecentCount := GitConfigDefaultRecentCount;
  FRecentPaths.Clear;
  Section := ReadWorkflowSection('repository');
  If Not Assigned(Section) Then
    Exit;
  Try
    FAutoRefresh := Section.Get('auto_refresh', GitConfigDefaultAutoRefresh);
    AutoRefreshSeconds := Section.Get('interval_sec', GitConfigDefaultIntervalSec);
    GraphFontName := Section.Get('graph_font_name', '');
    GraphFontSize := Section.Get('graph_font_size', GitConfigDefaultGraphFontSize);
    RecentCount := Section.Get('recent_count', GitConfigDefaultRecentCount);
    Node := Section.Find('recent_paths');
    If Node Is TJSONArray Then
      For Index := 0 To TJSONArray(Node).Count - 1 Do
        Begin
          If FRecentPaths.Count >= GitConfigMaxRecentCount Then Break;
          If TJSONArray(Node).Items[Index].JSONType <> jtString Then Continue;
          Path := NormalizeRepositoryPath(TJSONArray(Node).Items[Index].AsString);
          If (Path = '') Or (IndexOfRecentPath(Path) >= 0) Then Continue;
          FRecentPaths.Add(Path);
        End;
  Finally
    Section.Free;
  End;
End;

Procedure TGitConfig.Save;
Var
  Section: TJSONObject;
  Paths: TJSONArray;
  Index: Integer;
  ErrorText: String;
Begin
  Section := TJSONObject.Create;
  Try
    Section.Add('auto_refresh', FAutoRefresh);
    Section.Add('interval_sec', FAutoRefreshSeconds);
    Section.Add('graph_font_name', FGraphFontName);
    Section.Add('graph_font_size', FGraphFontSize);
    Section.Add('recent_count', FRecentCount);
    Paths := TJSONArray.Create;
    Section.Add('recent_paths', Paths);
    If Assigned(FRecentPaths) Then
      For Index := 0 To FRecentPaths.Count - 1 Do
        Paths.Add(FRecentPaths[Index]);
    WriteWorkflowSection('repository', Section, ErrorText);
  Finally
    Section.Free;
  End;
End;

Initialization

{ Create only. RegisterGitManager loads the repository section after the settings directory is known. }
GitManagerConfig := TGitConfig.Create;

Finalization

FreeAndNil(GitManagerConfig);

End.
