Program AssistantPlanRunTest;

{ Decision tests for the Run Plan end report (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, AssistantPlanRun, AssistantTurnFinish, AssistantAcceptance,
  AssistantToolBroker, AssistantClaudeClient;

Type
  TPromptWorkspace = Class(TAssistantWorkspaceAdapter)
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function CanBuild: Boolean; Override;
    Function CanTest: Boolean; Override;
    Function CanGit: Boolean; Override;
  End;

Var
  FailCount: Integer;

Function TPromptWorkspace.Identity: String; Begin Result := 'prompt-test'; End;
Function TPromptWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin Result := False; End;
Function TPromptWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin Result := False; End;
Function TPromptWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin Result := False; End;
Function TPromptWorkspace.Describe: String; Begin Result := '{}'; End;
Function TPromptWorkspace.CanBuild: Boolean; Begin Result := True; End;
Function TPromptWorkspace.CanTest: Boolean; Begin Result := True; End;
Function TPromptWorkspace.CanGit: Boolean; Begin Result := True; End;

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

Function Item(Const Title, Action: String; HasAction: Boolean): TPlanRunBlockedItem;
Begin
  Result.Title := Title;
  Result.UserAction := Action;
  Result.HasUserAction := HasAction;
End;

Function Facts(Kind: TPlanRunEndKind; Const Detail: String; Worked, NotStarted, InProgress, Blocked, Complete: Integer;
  TerminalFault: Boolean; Const Items: Array Of TPlanRunBlockedItem): TPlanRunReportFacts;
Var
  I: Integer;
Begin
  Result := DefaultPlanRunReportFacts;
  Result.Kind := Kind;
  Result.Detail := Detail;
  Result.PackagesWorked := Worked;
  Result.NotStarted := NotStarted;
  Result.InProgress := InProgress;
  Result.Blocked := Blocked;
  Result.Complete := Complete;
  Result.TerminalFault := TerminalFault;
  SetLength(Result.BlockedItems, Length(Items));
  For I := 0 To High(Items) Do
    Result.BlockedItems[I] := Items[I];
End;

Function Has(Const Report, Phrase: String): Boolean;
Begin
  Result := Pos(Phrase, Report) > 0;
End;

Procedure ExpectCounts(Const Title, Report: String; NotStarted, InProgress, Blocked, Complete: Integer);
Begin
  Check(Title, Has(Report, AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete)));
End;

Var
  Report, StartMessage, ActionText: String;
  Sample: TPlanRunReportFacts;
Procedure CheckPrompts;
  Const
    NativeNames: Array[0..9] Of String = (
      'search_in_project', 'get_project_info', 'list_directory', 'read_file', 'ensure_form_component',
      'run_compile', 'replace_in_file', 'run_git', 'update_markdown', 'write_file');
    ExpectedClaude: Array[0..8] Of String = (
      'lazarus_search_in_project', 'lazarus_read_file', 'lazarus_replace_in_buffer', 'lazarus_ensure_form_component',
      'lazarus_start_build', 'lazarus_build_status', 'lazarus_start_tests', 'lazarus_stage_patch',
      'lazarus_read_markdown_section');
  Var
    Workspace: TPromptWorkspace;
    Broker: TAssistantToolBroker;
    Tools, Native, Claude, Sparse, Name: String;
    Names: TStringList;
    I, Start: Integer;
    Function IdentChar(C: Char): Boolean;
    Begin
      Result := C In ['A'..'Z', 'a'..'z', '0'..'9', '_'];
    End;
    Function WholeWord(Const Text, Word: String): Boolean;
    Var
      P, Next: Integer;
    Begin
      Result := False;
      P := 1;
      While P <= Length(Text) - Length(Word) + 1 Do
        Begin
          If Copy(Text, P, Length(Word)) = Word Then
            Begin
              Next := P + Length(Word);
              If ((P = 1) Or Not IdentChar(Text[P - 1])) And ((Next > Length(Text)) Or Not IdentChar(Text[Next])) Then
                Exit(True);
            End;
          Inc(P);
        End;
    End;
  Begin
    Workspace := TPromptWorkspace.Create;
    Broker := TAssistantToolBroker.Create(Workspace);
    Names := TStringList.Create;
    Try
      Broker.BeginRun(awsProject);
      Tools := Broker.ToolsJson;
      Native := PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress', 'body', '5. Driver', False, False, '');
      Check('native discover sentence is unchanged',
        Pos('2. Discover with search_in_project, get_project_info, list_directory and read_file. ' +
          'Apply authorized edits using the available project tools. ' +
          'Use ensure_form_component for coordinated Pascal/LFM changes; do not create temporary probe units.', Native) > 0);
      Check('native compile sentence is unchanged',
        Pos('3. Run run_compile after edits, repair introduced errors and compile again.', Native) > 0);
      Check('native continue still names replace_in_file',
        Pos('unless a later replace_in_file failed.', PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress',
          'body', '', True, False, '')) > 0);
      Check('native prompt includes the section sentence', Pos(PlanSectionReadSentence, Native) > 0);
      Check('native prompt does not name broker tools', Pos('lazarus_', Native) = 0);
      Claude := PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress', 'body', '5. Driver', False, True, Tools);
      Claude := Claude + LineEnding + PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress', 'body', '',
        True, True, Tools);
      I := 1;
      While I <= Length(Claude) Do
        Begin
          If Copy(Claude, I, 8) = 'lazarus_' Then
            Begin
              Start := I;
              Inc(I, 8);
              While (I <= Length(Claude)) And IdentChar(Claude[I]) Do Inc(I);
              Name := Copy(Claude, Start, I - Start);
              If Names.IndexOf(Name) < 0 Then Names.Add(Name);
            End
          Else
            Inc(I);
        End;
      For I := 0 To Names.Count - 1 Do
        Check('Claude prompt names only a listed tool: ' + Names[I], Pos('"' + Names[I] + '"', Tools) > 0);
      For I := 0 To High(ExpectedClaude) Do
        If Pos('"' + ExpectedClaude[I] + '"', Tools) > 0 Then
          Check('Claude prompt names ' + ExpectedClaude[I], Pos(ExpectedClaude[I], Claude) > 0);
      For I := 0 To High(NativeNames) Do
        Check('Claude prompt does not name ' + NativeNames[I], Not WholeWord(Claude, NativeNames[I]));
      Sparse := '["lazarus_read_file"]';
      Claude := PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress', 'body', '', False, True, Sparse) +
        PlanWorkPrompt('Documents/Plan.md', '5.1 Name tools', 'in progress', 'body', '', True, True, Sparse);
      Check('a missing broker tool is not named', (Pos('lazarus_stage_patch', Claude) = 0) And
        (Pos('lazarus_start_build', Claude) = 0) And (Pos('lazarus_ensure_form_component', Claude) = 0) And
        (Pos('lazarus_run_git', Claude) = 0));
      Check('the sparse prompt still names the tool it has', Pos('lazarus_read_file', Claude) > 0);
    Finally
      Names.Free;
      Broker.Free;
      Workspace.Free;
    End;
  End;

Procedure CheckPlanItemSession;
Var
  Args: TStringList;
  Note: String;
Begin
  Args := TStringList.Create;
  Try
    AppendClaudePlanItemArguments('sonnet', '', 'item-1', False, Args);
    Check('a new plan item does not resume', Args.IndexOf('--resume') < 0);
    Check('a new plan item names its session', (Args.IndexOf('--session-id') >= 0) And
      (Args[Args.IndexOf('--session-id') + 1] = 'item-1'));
    Args.Clear;
    AppendClaudePlanItemArguments('sonnet', '', 'item-1', True, Args);
    Check('a continue turn resumes its session', (Args.IndexOf('--resume') >= 0) And
      (Args[Args.IndexOf('--resume') + 1] = 'item-1') And (Args.IndexOf('--session-id') < 0));
    Args.Clear;
    AppendClaudePlanItemArguments('sonnet', '', '', True, Args);
    Check('a continue without a session does not resume', Args.IndexOf('--resume') < 0);
  Finally
    Args.Free;
  End;
  Note := ClaudePlanItemSessionNote('5.2 Fresh session', 'item-1', False);
  Check('a started session note names the id', Has(Note, 'item-1') And Has(Note, 'started') And (Pos('resumed', Note) = 0));
  Note := ClaudePlanItemSessionNote('5.2 Fresh session', 'item-1', True);
  Check('a resumed session note names the id', Has(Note, 'item-1') And Has(Note, 'resumed'));
End;

Procedure CheckDirtySourceStop;
Const
  DirtyPas = ' M Source/Foo.pas' + LineEnding + ' M Documents/Plan.md';
  Clean = '';
  PlanOnly = ' M Documents/Plan.md';
Var
  Status: String;
Begin
  Check('a blocked item with a dirty pas file stops the run', PlanRunStopsForDirtySource(True, DirtyPas));
  Status := PlanRunDirtySourceStatus(DirtyPas);
  Check('the stop line names the pas file', Has(Status, 'Source/Foo.pas') And (Pos('Plan.md', Status) = 0));
  Check('a blocked item with a clean tree continues', Not PlanRunStopsForDirtySource(True, Clean));
  Check('a blocked item with only the plan dirty continues', Not PlanRunStopsForDirtySource(True, PlanOnly));
  Check('an item that is not blocked does not stop', Not PlanRunStopsForDirtySource(False, DirtyPas));
  Check('an untracked pas file is not tracked source', Not PlanRunStopsForDirtySource(True, '?? Source/New.pas'));
End;

Procedure CheckBuildStart;
Var
  Root, PackageFile, EmptyDir, Note: String;
  Lines: TStringList;
Begin
  Check('a target with no build input refuses to start', PlanRunBuildRefusal(True, '') = PlanRunNoBuildInput);
  Check('the refusal suggests selecting a package or project', Has(PlanRunNoBuildInput, 'Select a package or project.'));
  Check('a missing path is no build input', PlanRunBuildRefusal(True, '/no/such/build-input') = PlanRunNoBuildInput);
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-plan-build-' + IntToStr(GetProcessID);
  EmptyDir := Root + '-empty';
  ForceDirectories(Root);
  ForceDirectories(EmptyDir);
  PackageFile := IncludeTrailingPathDelimiter(Root) + 'Target.lpk';
  Lines := TStringList.Create;
  Try
    Lines.Text := 'package';
    Lines.SaveToFile(PackageFile);
    Note := PlanRunBuildRefusal(True, PackageFile);
    Check('a package target starts', Note = '');
    Check('the build tool must be able to build', PlanRunBuildRefusal(False, PackageFile) = PlanRunCannotBuildTarget);
    Check('a folder that holds a package starts', PlanRunBuildRefusal(True, Root) = '');
    Check('a folder with no package refuses', PlanRunBuildRefusal(True, EmptyDir) = PlanRunFolderHasNoPackage);
  Finally
    Lines.Free;
    DeleteFile(PackageFile);
    RemoveDir(Root);
    RemoveDir(EmptyDir);
  End;
End;

Type
  TCatalogueWorkspace = Class(TAssistantWorkspaceAdapter)
    CancelCount: Integer;
    Job: String;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function CanChangeSets: Boolean; Override;
    Function ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean; Override;
    Function CanBuild: Boolean; Override;
    Function StartBuild(Const PackagePath: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Override;
    Procedure CancelBuild; Override;
  End;

Function TCatalogueWorkspace.Identity: String;
Begin
  Result := 'catalogue-test';
End;

Function TCatalogueWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin
  CanonicalPath := 'Source/Unit.pas';
  Text := 'unit Unit;';
  ErrorText := '';
  Result := Path <> '';
End;

Function TCatalogueWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := 'not used';
  Result := False;
End;

Function TCatalogueWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := 'not used';
  Result := False;
End;

Function TCatalogueWorkspace.Describe: String;
Begin
  Result := '{}';
End;

Function TCatalogueWorkspace.CanChangeSets: Boolean;
Begin
  Result := True;
End;

Function TCatalogueWorkspace.ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean;
Begin
  Result := ReadBuffer(Path, CanonicalPath, Text, ErrorText);
  Stamp := 'stamp-1';
End;

Function TCatalogueWorkspace.CanBuild: Boolean;
Begin
  Result := True;
End;

Function TCatalogueWorkspace.StartBuild(Const PackagePath: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Job := 'job-1';
  ResultText := '{"job_id":"job-1","done":false}';
  ErrorText := '';
  Result := True;
End;

Function TCatalogueWorkspace.BuildStatus(Out ResultText, ErrorText: String): Boolean;
Begin
  ResultText := '';
  ErrorText := '';
  If Job = '' Then
    Begin
      ErrorText := 'No build.';
      Exit(False);
    End;
  ResultText := '{"job_id":"' + Job + '","done":false}';
  Result := True;
End;

Procedure TCatalogueWorkspace.CancelBuild;
Begin
  Inc(CancelCount);
  Job := '';
End;

Function JsonStringField(Const Text, Name: String): String;
Var
  Key, StartAt, EndAt: Integer;
Begin
  Result := '';
  Key := Pos('"' + Name + '":"', Text);
  If Key = 0 Then Exit;
  StartAt := Key + Length(Name) + 4;
  EndAt := StartAt;
  While (EndAt <= Length(Text)) And (Text[EndAt] <> '"') Do Inc(EndAt);
  Result := Copy(Text, StartAt, EndAt - StartAt);
End;

Procedure CheckCatalogueLeavesRun;
Var
  Workspace: TCatalogueWorkspace;
  Broker: TAssistantToolBroker;
  RunId, Reply, Err, Revision, SetId, Catalogue, OpenCatalogue: String;
  Cancels: Integer;
Begin
  Workspace := TCatalogueWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Try
    RunId := Broker.BeginRun(awsProject);
    Check('catalogue test reads a buffer', Broker.Execute(RunId, 'lazarus_read_buffer',
      '{"path":"Source/Unit.pas"}', Reply, Err));
    Revision := JsonStringField(Reply, 'revision');
    Check('catalogue test prepares a change set', Broker.Execute(RunId, 'lazarus_prepare_changes',
      '{"changes":[{"path":"Source/Unit.pas","revision":"' + Revision + '","text":"unit Unit; changed"}]}', Reply, Err));
    SetId := JsonStringField(Reply, 'change_set_id');
    Check('catalogue test starts a fake build', Broker.Execute(RunId, 'lazarus_start_build', '{}', Reply, Err) And
      (JsonStringField(Reply, 'job_id') = 'job-1'));
    Cancels := Workspace.CancelCount;
    OpenCatalogue := Broker.ToolsJson;
    Catalogue := Broker.ToolsJsonForScope(awsProject);
    Check('a scope catalogue does not replace the run id', Broker.RunId = RunId);
    Check('a scope catalogue does not cancel the build', (Workspace.CancelCount = Cancels) And (Workspace.Job = 'job-1'));
    Check('the fake build is still current', Broker.Execute(RunId, 'lazarus_build_status', '{"job_id":"job-1"}', Reply, Err) And
      (JsonStringField(Reply, 'job_id') = 'job-1'));
    Check('the prepared change set is still current', Broker.Execute(RunId, 'lazarus_change_status',
      '{"change_set_id":"' + SetId + '"}', Reply, Err) And (JsonStringField(Reply, 'change_set_id') = SetId));
    Check('the project catalogue still lists the build', Pos('"lazarus_start_build"', Catalogue) > 0);
    Check('the open run catalogue is unchanged', Broker.ToolsJson = OpenCatalogue);
    Check('a markdown catalogue does not retarget the open run',
      (Pos('"lazarus_start_build"', Broker.ToolsJsonForScope(awsMarkdown)) = 0) And (Broker.RunId = RunId) And
      (Pos('"lazarus_start_build"', Broker.ToolsJson) > 0));
  Finally
    Broker.Free;
    Workspace.Free;
  End;
End;

Begin
  FailCount := 0;
  CheckPrompts;
  CheckCatalogueLeavesRun;
  CheckPlanItemSession;
  CheckDirtySourceStop;
  CheckBuildStart;
  Check('empty plan counts match the list',
    AssistantPlanRunCountsLine(0, 0, 0, 0) = '0 not started · 0 in progress · 0 blocked · 0 complete  ·  no actionable items');
  Check('open counts match the list',
    AssistantPlanRunCountsLine(2, 1, 3, 4) = '2 not started · 1 in progress · 3 blocked · 4 complete');

  Sample := Facts(preCleanFinish, '', 2, 0, 0, 0, 5, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('clean finish names the worked count', Has(Report, 'All packages are complete (2 worked this run).'));
  ExpectCounts('clean finish counts', Report, 0, 0, 0, 5);
  Check('clean finish does not ask to run again', Not Has(Report, AssistantPlanRunAgain));
  Check('clean finish does not mention blocked actions', Not Has(Report, AssistantPlanRunBlockedLeft));

  Sample := Facts(preCleanFinish, '', 1, 0, 0, 1, 3, False, [Item('Review the form', 'review "Review the form"', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('blocked finish does not say all packages are complete', Not Has(LowerCase(Report), 'all packages are complete'));
  Check('blocked finish does not say already complete', Not Has(LowerCase(Report), 'already complete'));
  Check('blocked finish says the actions are required', Has(Report, AssistantPlanRunBlockedLeft));
  Check('blocked finish quotes the stored action',
    Has(Report, AssistantBlockedItemReport('Review the form', 'review "Review the form"')));
  Check('blocked finish does not ask to run again', Not Has(Report, AssistantPlanRunAgain));
  ExpectCounts('blocked finish counts', Report, 0, 0, 1, 3);
  Check('blocked sentence is not repeated',
    Pos(AssistantPlanRunBlockedLeft, Copy(Report, Pos(AssistantPlanRunBlockedLeft, Report) + Length(AssistantPlanRunBlockedLeft),
      MaxInt)) = 0);

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 2, 1, False,
    [Item('First', 'do the first thing', True), Item('Second', '', False)]);
  Report := AssistantPlanRunReport(Sample);
  Check('both blocked items are listed', Has(Report, AssistantBlockedItemReport('First', 'do the first thing')) And
    Has(Report, 'Blocked "Second". No user action is stored.'));
  Check('missing action is not quoted as empty', Not Has(Report, AssistantBlockedItemReport('Second', '')));

  Sample := Facts(preUserStop, 'stopped by user', 1, 1, 1, 1, 2, False, [Item('Wait', 'supply the file', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('user stop names the user', Has(Report, 'Stopped by the user.'));
  Check('user stop with open items says run again', Has(Report, AssistantPlanRunAgain));
  Check('user stop still lists the blocked action', Has(Report, AssistantBlockedItemReport('Wait', 'supply the file')));
  ExpectCounts('user stop counts', Report, 1, 1, 1, 2);
  Check('user stop does not say all packages are complete', Not Has(LowerCase(Report), 'all packages are complete'));

  Sample := Facts(preUserStop, 'stream cancelled by user', 0, 1, 0, 0, 0, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('cancelled stream is a user stop', Has(Report, 'The stream was cancelled by the user.'));
  Check('cancelled stream with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preError, 'Could not start the first package.', 0, 2, 0, 0, 1, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('error names the detail', Has(Report, 'The run ended with an error. Could not start the first package.'));
  Check('error with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preError, 'the service is gone', 1, 0, 1, 0, 0, True, []);
  Report := AssistantPlanRunReport(Sample);
  Check('terminal error does not say run again', Not Has(Report, AssistantPlanRunAgain));
  Check('terminal error keeps the fault text', Has(Report, 'the service is gone'));

  Sample := Facts(prePackageCap, '25', 4, 3, 0, 0, 4, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('package cap names the limit', Has(Report, 'Reached the package cap (25).'));
  Check('package cap with work left says run again', Has(Report, AssistantPlanRunAgain));
  ExpectCounts('package cap counts', Report, 3, 0, 0, 4);

  Sample := Facts(preContextLimit, 'context usage 96% after compact — start a New Chat', 2, 1, 1, 0, 2, True, []);
  Report := AssistantPlanRunReport(Sample);
  Check('context limit keeps the percent', Has(Report, 'context usage 96% after compact — start a New Chat'));
  Check('context limit says start a new chat', Has(Report, AssistantPlanRunNewChat));
  Check('context limit does not say run again', Not Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preContextLimit, 'context usage 97% — start a New Chat', 0, 0, 0, 1, 2, True,
    [Item('Manual', 'review it', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('context limit with only blocked items does not say all complete',
    Not Has(LowerCase(Report), 'all packages are complete'));
  Check('context limit with only blocked items names the action', Has(Report, AssistantPlanRunBlockedLeft));
  Check('context limit with only blocked items does not say run again', Not Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preNewChat, 'new chat', 1, 2, 0, 0, 1, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('new chat names the exit', Has(Report, 'A new chat started.'));
  Check('new chat with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 1, 4, False, [Item('Blocked item', 'add the missing file', True)]);
  StartMessage := AssistantPlanRunStartMessage(Sample);
  Check('start dialog does not say already complete when blocked', Not Has(LowerCase(StartMessage), 'already complete'));
  Check('start dialog does not say all packages when blocked', Not Has(LowerCase(StartMessage), 'all packages'));
  Check('start dialog says blocked items need the listed actions', Has(StartMessage, AssistantPlanRunBlockedLeft));
  Check('start dialog lists the stored action', Has(StartMessage, AssistantBlockedItemReport('Blocked item', 'add the missing file')));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 0, 6, False, []);
  StartMessage := AssistantPlanRunStartMessage(Sample);
  Check('start dialog says already complete when nothing is blocked', Has(StartMessage, AssistantPlanRunAlreadyComplete));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 0, 0, False, []);
  Check('start dialog says none found', AssistantPlanRunStartMessage(Sample) = AssistantPlanRunNoneFound);

  Check('fenced user action is not stored',
    Not PlanBodyUserAction('```' + LineEnding + 'User action: ignore this example' + LineEnding + '```', ActionText));
  Check('stored user action is the unfenced line',
    PlanBodyUserAction('```' + LineEnding + 'User action: ignore this example' + LineEnding + '```' + LineEnding +
      'User action: keep this one', ActionText) And (ActionText = 'keep this one'));
  Check('empty user action line still counts',
    PlanBodyUserAction('User action:', ActionText) And (ActionText = ''));

  Check('stall when the agent is idle and items remain', PlanRunUnexplainedStall(True, False, False, 2));
  Check('no stall while a package is sending', Not PlanRunUnexplainedStall(True, True, False, 2));
  Check('no stall after the user stops', Not PlanRunUnexplainedStall(True, False, True, 2));
  Check('no stall when the agent is not running', Not PlanRunUnexplainedStall(False, False, False, 2));
  Check('no stall when nothing is open', Not PlanRunUnexplainedStall(True, False, False, 0));
  Check('stall note uses the reconnect phrase', Has(PlanRunStallWaitNote(30), 'Waiting to reconnect.'));
  Check('stall resume uses the resume phrase', Has(PlanRunStallResumeNote, 'Resuming the call.'));
  Check('new chat continues at the threshold', PlanRunContinuesInNewChat(95, 95, True));
  Check('new chat does not continue under the threshold', Not PlanRunContinuesInNewChat(94, 95, True));
  Check('new chat does not continue when the setting is off', Not PlanRunContinuesInNewChat(99, 95, False));
  Check('missing context percent keeps 95', PlanContextContinuePercent(0) = AssistantPlanContextPercentDefault);
  Check('context percent clamps low values', PlanContextContinuePercent(10) = AssistantPlanContextPercentMin);
  Check('context percent clamps high values', PlanContextContinuePercent(120) = AssistantPlanContextPercentMax);
  Check('new chat note names the percent', Has(PlanRunNewChatNote(97), '97%'));

  If FailCount = 0 Then
    WriteLn('AssistantPlanRunTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
