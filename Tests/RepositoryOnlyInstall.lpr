Program RepositoryOnlyInstall;

{ Repository-only uses clause: Common and Repository units, no Assistant or StyledText.
  Suggest stays disabled while SuggestCommitMessageFunc is nil. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, LazFileUtils,
  GitConfig, GitJobRunner, ManageRepositoryForm, WorkflowEvents, WorkflowSettings;

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

Function StubSuggest(Const DiffText, StatusSummary: String; Out MessageText, ErrorText: String): Boolean;
Begin
  MessageText := 'unused';
  ErrorText := '';
  Result := True;
End;

Type
  TSuggestProbe = Class
    Done: Boolean;
    Ok: Boolean;
    ErrorText: String;
    Procedure Finished(Job: TGitJob);
  End;

Procedure TSuggestProbe.Finished(Job: TGitJob);
Begin
  Done := True;
  Ok := Job.Ok;
  ErrorText := Job.ErrorText;
End;

Procedure CheckSuggestDisabled;
Var
  Probe: TSuggestProbe;
  Job: TGitJob;
  Started: QWord;
Begin
  SuggestCommitMessageFunc := Nil;
  Check('suggest unavailable when the hook is nil', Not SuggestCommitMessageAvailable);
  Check('suggest action disabled when the hook is nil', Not SuggestCommitActionEnabled(True, True));
  SuggestCommitMessageFunc := @StubSuggest;
  Check('suggest action can enable only after a handler is registered', SuggestCommitActionEnabled(True, True));
  SuggestCommitMessageFunc := Nil;
  Check('clearing the hook disables suggest again', Not SuggestCommitActionEnabled(True, True));

  Probe := TSuggestProbe.Create;
  Try
    Job := TGitJob.Create(gjkSuggestMessage);
    Job.Quiet := True;
    Job.OnFinished := @Probe.Finished;
    Check('nil suggest job can be queued', GitJobs.Submit(Job));
    Started := GetTickCount64;
    While (Not Probe.Done) And (GetTickCount64 - Started < 5000) Do
      CheckSynchronize(20);
    Check('nil suggest job finished', Probe.Done);
    Check('nil suggest job did not succeed', Not Probe.Ok);
    Check('nil suggest job reports that suggestion is unavailable',
      Probe.ErrorText = 'Commit message suggestion is not available.');
  Finally
    Probe.Free;
  End;
End;

Procedure CheckRepositorySaveLeavesAssistant;
Var
  Section: TJSONObject;
  ErrorText: String;
  Config: TGitConfig;
  Guid: TGuid;
  Root: String;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-repository-only-' + GUIDToString(Guid);
  If Not ForceDirectories(Root) Then
    Raise Exception.Create('Could not create ' + Root);
  SetWorkflowSettingsDirectory(Root);
  Try
    Section := TJSONObject.Create;
    Try
      Section.Add('marker', 'keep-assistant');
      Section.Add('include_ide_context', True);
      Check('seed assistant section without assistant units', WriteWorkflowSection('assistant', Section, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
    Finally
      Section.Free;
    End;
    Config := TGitConfig.Create;
    Try
      Config.AutoRefresh := False;
      Config.AutoRefreshSeconds := 23;
      Config.GraphFontName := 'RepoOnlyFont';
      Config.GraphFontSize := 11;
      Config.Save;
    Finally
      Config.Free;
    End;
    Section := ReadWorkflowSection('assistant');
    Try
      Check('repository save leaves the assistant section', Assigned(Section));
      Check('repository save leaves the assistant marker',
        Assigned(Section) And (Section.Get('marker', '') = 'keep-assistant'));
    Finally
      Section.Free;
    End;
    Section := ReadWorkflowSection('repository');
    Try
      Check('repository section written by repository save', Assigned(Section));
      Check('repository interval written', Assigned(Section) And (Section.Get('interval_sec', 0) = 23));
      Check('repository font written', Assigned(Section) And (Section.Get('graph_font_name', '') = 'RepoOnlyFont'));
    Finally
      Section.Free;
    End;
  Finally
    DeleteFile(WorkflowSettingsPath);
    DeleteFile(WorkflowSettingsPath + '.tmp');
    SetWorkflowSettingsDirectory('');
    RemoveDir(ExcludeTrailingPathDelimiter(Root));
  End;
End;

Function ExpectedRepositoryPath(Const Path: String): String;
Begin
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Path));
End;

Procedure CheckRecentRepositories;
Var
  Config, Reloaded: TGitConfig;
  Paths: TStringList;
  Section: TJSONObject;
  Guid: TGuid;
  Root, One, Two, Three: String;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-repository-recent-' + GUIDToString(Guid);
  One := Root + 'one';
  Two := Root + 'two';
  Three := Root + 'three';
  If Not ForceDirectories(One) Or Not ForceDirectories(Two) Or Not ForceDirectories(Three) Then
    Raise Exception.Create('Could not create recent-repository folders');
  SetWorkflowSettingsDirectory(Root);
  Try
    Config := TGitConfig.Create;
    Try
      Check('recent count defaults to five', Config.RecentCount = GitConfigDefaultRecentCount);
      Config.RecentCount := 2;
      Config.RememberRepository(One);
      Config.RememberRepository(Two + PathDelim);
      Config.RememberRepository(Three);
      Config.RememberRepository(Root + 'missing');
      Paths := TStringList.Create;
      Try
        Config.CopyRecentPaths(Paths);
        Check('menu list is limited to the configured count', Paths.Count = 2);
        Check('newest repository is first', CompareFilenames(Paths[0], ExpectedRepositoryPath(Three)) = 0);
        Check('previous repository is second', CompareFilenames(Paths[1], ExpectedRepositoryPath(Two)) = 0);
      Finally
        Paths.Free;
      End;
      Config.RecentCount := 3;
      Paths := TStringList.Create;
      Try
        Config.CopyRecentPaths(Paths);
        Check('raising the count restores a stored older path', Paths.Count = 3);
        Check('restored path is the oldest of the three', CompareFilenames(Paths[2], ExpectedRepositoryPath(One)) = 0);
      Finally
        Paths.Free;
      End;
      Config.RememberRepository(Two);
      Paths := TStringList.Create;
      Try
        Config.CopyRecentPaths(Paths);
        Check('remembering an older path moves it to the front', CompareFilenames(Paths[0], ExpectedRepositoryPath(Two)) = 0);
        Check('moved path is not duplicated', Paths.Count = 3);
      Finally
        Paths.Free;
      End;
      Config.AutoRefreshSeconds := 29;
      Config.Save;
      Config.RecentCount := 99;
      Check('recent count clamps to the maximum', Config.RecentCount = GitConfigMaxRecentCount);
      Config.RecentCount := 0;
      Check('recent count clamps to the minimum', Config.RecentCount = GitConfigMinRecentCount);
      Config.RecentCount := 3;
      Config.ForgetRepository(Two);
    Finally
      Config.Free;
    End;

    Reloaded := TGitConfig.Create;
    Try
      Reloaded.Load;
      Check('saved recent count reloads', Reloaded.RecentCount = 3);
      Check('interval saved with the recent list reloads', Reloaded.AutoRefreshSeconds = 29);
      Paths := TStringList.Create;
      Try
        Reloaded.CopyRecentPaths(Paths);
        Check('remaining paths reload newest first', (Paths.Count = 2) And
          (CompareFilenames(Paths[0], ExpectedRepositoryPath(Three)) = 0) And
          (CompareFilenames(Paths[1], ExpectedRepositoryPath(One)) = 0));
      Finally
        Paths.Free;
      End;
    Finally
      Reloaded.Free;
    End;

    Section := ReadWorkflowSection('repository');
    Try
      Check('recent count is stored with repository settings',
        Assigned(Section) And (Section.Get('recent_count', 0) = 3));
      Check('recent paths are stored as an array',
        Assigned(Section) And (Section.Find('recent_paths') Is TJSONArray) And
        (TJSONArray(Section.Find('recent_paths')).Count = 2));
    Finally
      Section.Free;
    End;
  Finally
    DeleteFile(WorkflowSettingsPath);
    DeleteFile(WorkflowSettingsPath + '.tmp');
    SetWorkflowSettingsDirectory('');
    RemoveDir(One);
    RemoveDir(Two);
    RemoveDir(Three);
    RemoveDir(ExcludeTrailingPathDelimiter(Root));
  End;
End;

Begin
  FailCount := 0;
  Try
    CheckSuggestDisabled;
    CheckRepositorySaveLeavesAssistant;
    CheckRecentRepositories;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
        Exit;
      End;
  End;
  If FailCount = 0 Then
    WriteLn('PASS repository-only install leaves suggest disabled')
  Else
    Begin
      WriteLn('FAIL ', FailCount, ' checks');
      ExitCode := 1;
    End;
End.
