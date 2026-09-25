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
  Classes, SysUtils, fpjson,
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

Begin
  FailCount := 0;
  Try
    CheckSuggestDisabled;
    CheckRepositorySaveLeavesAssistant;
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
