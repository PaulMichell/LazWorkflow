Unit AssistantPlanRun;

{ End-of-run plan status. The form posts the text; this unit owns the wording (c) 2026 Michell Computing.

  Every Run Plan exit uses one report: the plan-list counts, why the run ended,
  each blocked item's stored user action, and the next step. A finish with
  blocked items left does not say that all packages are complete. The start
  dialog uses the same rule when nothing unblocked remains.
  A blocked item that leaves tracked source uncommitted stops the run. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  AssistantPlanRunAgain = 'Next: run Run Plan again.';
  AssistantPlanRunNewChat = 'Next: start a New Chat.';
  AssistantPlanRunBlockedLeft = 'Blocked items need the listed actions. No unblocked item is left.';
  AssistantPlanRunAlreadyComplete = 'All plan packages are already complete.';
  AssistantPlanRunNoneFound = 'No plan packages were found.';
  { Status footer when Run Plan must not start. Each line suggests selecting a package or project. }
  PlanRunNoBuildInput = 'The target has no build input. Select a package or project.';
  PlanRunCannotBuildTarget = 'The build tool cannot build this target. Select a package or project.';
  PlanRunFolderHasNoPackage = 'The target folder has no Lazarus package. Select a package or project.';
  { Context continuation. 0 in storage means the default. The form does not hard-code 95. }
  AssistantPlanContextPercentDefault = 95;
  AssistantPlanContextPercentMin = 50;
  AssistantPlanContextPercentMax = 99;

Type
  TPlanRunEndKind = (
    preCleanFinish,
    preUserStop,
    preError,
    prePackageCap,
    preContextLimit,
    preNewChat,
    preUncommitted
  );

  TPlanRunBlockedItem = Record
    Title: String;
    UserAction: String;
    HasUserAction: Boolean;
  End;
  TPlanRunBlockedItemArray = Array Of TPlanRunBlockedItem;

  TPlanRunReportFacts = Record
    Kind: TPlanRunEndKind;
    Detail: String;
    PackagesWorked: Integer;
    NotStarted: Integer;
    InProgress: Integer;
    Blocked: Integer;
    Complete: Integer;
    BlockedItems: TPlanRunBlockedItemArray;
    { A fault that says not to continue with Run Plan. Context limit is that case too. }
    TerminalFault: Boolean;
    { Wall-clock time of the whole run. 0 when no run was timed, such as the start dialog. }
    ElapsedMs: QWord;
  End;

Function DefaultPlanRunReportFacts: TPlanRunReportFacts;
{ Same line as the plan list, including the empty-plan suffix. }
Function AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete: Integer): String;
Function AssistantPlanRunWhy(Const Facts: TPlanRunReportFacts): String;
{ Run total for the status card and the report: m:ss under an hour, h:mm:ss from an hour. }
Function FormatPlanRunElapsed(ElapsedMs: QWord): String;
{ One conversation report. Does not say that all packages are complete when a blocked item remains. }
Function AssistantPlanRunReport(Const Facts: TPlanRunReportFacts): String;
{ Start dialog when FindNextIncompleteBuildSection found nothing to run. }
Function AssistantPlanRunStartMessage(Const Facts: TPlanRunReportFacts): String;
{ Stored 0 keeps the default. Values outside 50..99 clamp to that range, except 0. }
Function PlanContextContinuePercent(StoredPercent: Integer): Integer;
{ A plan run at or over the threshold opens a new chat and continues, when the setting is on. }
Function PlanRunContinuesInNewChat(UsagePercent, ThresholdPercent: Integer; Enabled: Boolean): Boolean;
{ The agent is still marked running, nothing is sending, the user did not stop, and items remain. }
Function PlanRunUnexplainedStall(AgentRunning, Sending, UserStopped: Boolean; OpenItems: Integer): Boolean;
Function PlanRunStallWaitNote(WaitSeconds: Integer): String;
Function PlanRunStallResumeNote: String;
Function PlanRunNewChatNote(UsagePercent: Integer): String;
{ Trace line naming the Claude session for one plan item. Resumed is a continue turn of that item. }
Function ClaudePlanItemSessionNote(Const ItemTitle, SessionId: String; Resumed: Boolean): String;
{ Tracked source paths in git status --porcelain, comma-separated. Untracked and non-source lines are ignored. }
Function PlanRunDirtySourceFiles(Const Porcelain: String): String;
{ A blocked item with those files stops the run. A clean tree, or an item that is not blocked, does not. }
Function PlanRunStopsForDirtySource(Blocked: Boolean; Const Porcelain: String): Boolean;
{ Status line naming the dirty tracked source files. Empty when the run should continue. }
Function PlanRunDirtySourceStatus(Const Porcelain: String): String;
{ Reads git status --porcelain. False when the tree is clean, there is no repository, or Git fails. }
Function PlanRunBlockedSourceStop(Const Root: String; Out StatusLine: String): Boolean;
{ Empty when Run Plan may start. Otherwise the status line: CanBuild, and a file or a folder that holds a package. }
Function PlanRunBuildRefusal(CanBuild: Boolean; Const InputPath: String): String;
{ Work-item prompt. Claude names only tools present in ToolsJson. Native keeps the existing sentences. }
Function PlanWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String;
  ContinueSameItem, Claude: Boolean; Const ToolsJson: String): String;
Function PlanSectionReadSentence: String;

Implementation

Uses
  Classes, fpjson, jsonparser, AssistantPlan, AssistantAcceptance, AssistantGit, AssistantBuildJob;

Function PlanContextContinuePercent(StoredPercent: Integer): Integer;
Begin
  If StoredPercent <= 0 Then
    Result := AssistantPlanContextPercentDefault
  Else
    Result := StoredPercent;
  If Result < AssistantPlanContextPercentMin Then
    Result := AssistantPlanContextPercentMin;
  If Result > AssistantPlanContextPercentMax Then
    Result := AssistantPlanContextPercentMax;
End;

Function PlanRunContinuesInNewChat(UsagePercent, ThresholdPercent: Integer; Enabled: Boolean): Boolean;
Begin
  Result := Enabled And (ThresholdPercent > 0) And (UsagePercent >= ThresholdPercent);
End;

Function PlanRunUnexplainedStall(AgentRunning, Sending, UserStopped: Boolean; OpenItems: Integer): Boolean;
Begin
  Result := AgentRunning And (Not Sending) And (Not UserStopped) And (OpenItems > 0);
End;

Function PlanRunStallWaitNote(WaitSeconds: Integer): String;
Begin
  If WaitSeconds < 1 Then
    Result := 'The plan stopped with items still open. Waiting to reconnect.'
  Else
    Result := Format('The plan stopped with items still open. Waiting to reconnect. Retrying in %d seconds. Stop still interrupts the wait.',
      [WaitSeconds]);
End;

Function PlanRunStallResumeNote: String;
Begin
  Result := 'Resuming the call. The plan still has open items.';
End;

Function PlanRunNewChatNote(UsagePercent: Integer): String;
Begin
  Result := Format('Context usage %d%%. Starting a new chat and continuing the plan.', [UsagePercent]);
End;

Function ClaudePlanItemSessionNote(Const ItemTitle, SessionId: String; Resumed: Boolean): String;
Var
  Action, Title, Identifier: String;
Begin
  If Resumed Then
    Action := 'resumed'
  Else
    Action := 'started';
  Title := Trim(ItemTitle);
  Identifier := Trim(SessionId);
  If Identifier = '' Then
    Identifier := '(none)';
  Result := 'Claude session ' + Identifier + ' ' + Action;
  If Title <> '' Then
    Result := Result + ' for "' + Title + '"';
  Result := Result + '.';
End;

Function UnquoteGitPath(Const Path: String): String;
Begin
  Result := Path;
  If (Length(Result) < 2) Or (Result[1] <> '"') Or (Result[Length(Result)] <> '"') Then
    Exit;
  Result := Copy(Result, 2, Length(Result) - 2);
  Result := StringReplace(Result, '\\', '\', [rfReplaceAll]);
  Result := StringReplace(Result, '\"', '"', [rfReplaceAll]);
End;

Function PorcelainSourcePath(Const Line: String): String;
Var
  Rest: String;
  Arrow: Integer;
Begin
  Result := '';
  { XY is two columns. Do not trim: a leading space is an unstaged tracked change. }
  If (Length(Line) < 4) Or (Line[3] <> ' ') Then
    Exit;
  If (Copy(Line, 1, 2) = '??') Or (Copy(Line, 1, 2) = '!!') Or ((Line[1] = ' ') And (Line[2] = ' ')) Then
    Exit;
  Rest := Copy(Line, 4, MaxInt);
  Arrow := Pos(' -> ', Rest);
  If Arrow > 0 Then
    Rest := Copy(Rest, Arrow + 4, MaxInt);
  Result := UnquoteGitPath(Trim(Rest));
End;

Function IsTrackedSourcePath(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or (Ext = '.inc') Or (Ext = '.lfm');
End;

Function PlanRunDirtySourceFiles(Const Porcelain: String): String;
Var
  Lines, Names: TStringList;
  Index: Integer;
  Path: String;
Begin
  Result := '';
  Lines := TStringList.Create;
  Names := TStringList.Create;
  Try
    Lines.Text := Porcelain;
    For Index := 0 To Lines.Count - 1 Do
      Begin
        If (Lines[Index] = '') Or (Copy(Lines[Index], 1, 5) = 'hint:') Then
          Continue;
        Path := PorcelainSourcePath(Lines[Index]);
        If IsTrackedSourcePath(Path) And (Names.IndexOf(Path) < 0) Then
          Names.Add(Path);
      End;
    For Index := 0 To Names.Count - 1 Do
      Begin
        If Result <> '' Then
          Result := Result + ', ';
        Result := Result + Names[Index];
      End;
  Finally
    Names.Free;
    Lines.Free;
  End;
End;

Function PlanRunStopsForDirtySource(Blocked: Boolean; Const Porcelain: String): Boolean;
Begin
  Result := Blocked And (PlanRunDirtySourceFiles(Porcelain) <> '');
End;

Function PlanRunDirtySourceStatus(Const Porcelain: String): String;
Begin
  Result := PlanRunDirtySourceFiles(Porcelain);
  If Result <> '' Then
    Result := 'Stopped. Uncommitted source: ' + Result;
End;

Function PorcelainFromGitReply(Const Reply: String): String;
Var
  Data: TJSONData;
Begin
  Result := Reply;
  If (Reply = '') Or (Reply[1] <> '{') Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(Reply);
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get('output', Reply);
  Except
    Result := Reply;
  End;
  Data.Free;
End;

Function PlanRunBlockedSourceStop(Const Root: String; Out StatusLine: String): Boolean;
Var
  Reply, ErrorText, Porcelain: String;
Begin
  StatusLine := '';
  Result := False;
  If Not WorkingRootHasGitRepository(Root) Then
    Exit;
  If Not RunAssistantGit(Root, '{"arguments":["status","--porcelain"]}', Reply, ErrorText) Then
    Exit;
  Porcelain := PorcelainFromGitReply(Reply);
  Result := PlanRunStopsForDirtySource(True, Porcelain);
  If Result Then
    StatusLine := PlanRunDirtySourceStatus(Porcelain);
End;

Function PlanRunBuildRefusal(CanBuild: Boolean; Const InputPath: String): String;
Var
  Path, ErrorText: String;
  Packages: TStringList;
Begin
  Result := '';
  If Not CanBuild Then
    Exit(PlanRunCannotBuildTarget);
  Path := Trim(InputPath);
  If Path = '' Then
    Exit(PlanRunNoBuildInput);
  { A directory is also a file on Unix. Decide the folder case first. }
  If DirectoryExists(Path) Then
    Begin
      Packages := TStringList.Create;
      Try
        If ResolveFolderPackages(Path, '', Packages, ErrorText) Then
          Exit;
      Finally
        Packages.Free;
      End;
      Result := PlanRunFolderHasNoPackage;
      Exit;
    End;
  If FileExists(Path) Then
    Exit;
  Result := PlanRunNoBuildInput;
End;

Function DefaultPlanRunReportFacts: TPlanRunReportFacts;
Begin
  Result.Kind := preCleanFinish;
  Result.Detail := '';
  Result.PackagesWorked := 0;
  Result.NotStarted := 0;
  Result.InProgress := 0;
  Result.Blocked := 0;
  Result.Complete := 0;
  Result.BlockedItems := Nil;
  Result.TerminalFault := False;
  Result.ElapsedMs := 0;
End;

Function FormatPlanRunElapsed(ElapsedMs: QWord): String;
Var
  Secs: QWord;
Begin
  Secs := ElapsedMs Div 1000;
  If Secs >= 3600 Then
    Result := Format('%d:%2.2d:%2.2d', [Secs Div 3600, (Secs Mod 3600) Div 60, Secs Mod 60])
  Else
    Result := Format('%d:%2.2d', [Secs Div 60, Secs Mod 60]);
End;

Function AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete: Integer): String;
Begin
  Result := Format('%d not started · %d in progress · %d blocked · %d complete',
    [NotStarted, InProgress, Blocked, Complete]);
  If (NotStarted + InProgress + Blocked + Complete) = 0 Then
    Result := Result + '  ·  no actionable items';
End;

Function PlanRunOpenCount(Const Facts: TPlanRunReportFacts): Integer;
Begin
  Result := Facts.NotStarted + Facts.InProgress;
End;

Function AssistantPlanRunWhy(Const Facts: TPlanRunReportFacts): String;
Begin
  { Ord keeps Else reachable if a new kind is added. Result is assigned on every path. }
  Case Ord(Facts.Kind) Of
    Ord(preCleanFinish):
      Begin
        If PlanRunOpenCount(Facts) > 0 Then
          Result := 'The run stopped while items are still open.'
        Else If Facts.Blocked > 0 Then
          Result := AssistantPlanRunBlockedLeft
        Else
          Result := Format('All packages are complete (%d worked this run).', [Facts.PackagesWorked]);
      End;
    Ord(preUserStop):
      Begin
        If Pos('cancel', LowerCase(Facts.Detail)) > 0 Then
          Result := 'The stream was cancelled by the user.'
        Else
          Result := 'Stopped by the user.';
      End;
    Ord(preError):
      Begin
        Result := 'The run ended with an error.';
        If Trim(Facts.Detail) <> '' Then
          Result := Result + ' ' + Trim(Facts.Detail);
      End;
    Ord(prePackageCap):
      Begin
        If Trim(Facts.Detail) <> '' Then
          Result := 'Reached the package cap (' + Trim(Facts.Detail) + ').'
        Else
          Result := 'Reached the package cap.';
      End;
    Ord(preContextLimit):
      Begin
        If Trim(Facts.Detail) <> '' Then
          Result := Trim(Facts.Detail)
        Else
          Result := 'Context is at the limit. Start a New Chat.';
      End;
    Ord(preNewChat):
      Result := 'A new chat started.';
    Ord(preUncommitted):
      Begin
        If Trim(Facts.Detail) <> '' Then
          Result := Trim(Facts.Detail)
        Else
          Result := 'Stopped. Uncommitted source remains.';
      End;
  Else
    Result := 'The plan run ended.';
  End;
End;

Function AssistantPlanRunBlockedLines(Const Facts: TPlanRunReportFacts): String;
Var
  I: Integer;
  Line: String;
Begin
  Result := '';
  For I := 0 To High(Facts.BlockedItems) Do
    Begin
      If Facts.BlockedItems[I].HasUserAction Then
        Line := AssistantBlockedItemReport(Facts.BlockedItems[I].Title, Facts.BlockedItems[I].UserAction)
      Else
        Line := 'Blocked "' + Facts.BlockedItems[I].Title + '". No user action is stored.';
      If Result <> '' Then
        Result := Result + LineEnding;
      Result := Result + Line;
    End;
End;

Function AssistantPlanRunNextStep(Const Facts: TPlanRunReportFacts): String;
Begin
  Result := '';
  If Facts.Kind = preUncommitted Then
    Exit(AssistantPlanRunAgain);
  If PlanRunOpenCount(Facts) > 0 Then
    Begin
      If Facts.TerminalFault Or (Facts.Kind = preContextLimit) Then
        Begin
          If (Facts.Kind = preContextLimit) Or (Pos('new chat', LowerCase(Facts.Detail)) > 0) Then
            Result := AssistantPlanRunNewChat
          Else If Trim(Facts.Detail) <> '' Then
            Result := 'Next: ' + Trim(Facts.Detail)
          Else
            Result := 'Next: the run stopped on a terminal fault.';
        End
      Else
        Result := AssistantPlanRunAgain;
    End
  Else If Facts.Blocked > 0 Then
    Result := AssistantPlanRunBlockedLeft;
End;

Function AssistantPlanRunReport(Const Facts: TPlanRunReportFacts): String;
Var
  Why, NextStep, Blocked: String;
Begin
  Why := AssistantPlanRunWhy(Facts);
  Result := '**Plan run ended:** ' + Why + LineEnding + LineEnding +
    AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
  If Facts.ElapsedMs > 0 Then
    Result := Result + LineEnding + LineEnding + 'Total run time: ' + FormatPlanRunElapsed(Facts.ElapsedMs) + '.';
  Blocked := AssistantPlanRunBlockedLines(Facts);
  If Blocked <> '' Then
    Result := Result + LineEnding + LineEnding + Blocked;
  NextStep := AssistantPlanRunNextStep(Facts);
  { The clean-finish why is already the blocked sentence. Do not repeat it. }
  If (NextStep <> '') And (Pos(NextStep, Why) = 0) Then
    Result := Result + LineEnding + LineEnding + NextStep;
End;

Function AssistantPlanRunStartMessage(Const Facts: TPlanRunReportFacts): String;
Var
  Blocked: String;
Begin
  If PlanRunOpenCount(Facts) > 0 Then
    Begin
      Result := 'Run Plan can continue.' + LineEnding + LineEnding +
        AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
      Exit;
    End;
  If Facts.Blocked > 0 Then
    Begin
      Result := AssistantPlanRunBlockedLeft + LineEnding + LineEnding +
        AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
      Blocked := AssistantPlanRunBlockedLines(Facts);
      If Blocked <> '' Then
        Result := Result + LineEnding + LineEnding + Blocked;
      Exit;
    End;
  If Facts.Complete > 0 Then
    Result := AssistantPlanRunAlreadyComplete + LineEnding + LineEnding +
      AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete)
  Else
    Result := AssistantPlanRunNoneFound;
End;

Function PlanSectionReadSentence: String;
Begin
  Result := 'Read only this item''s section; use line ranges, not whole files, for large units.';
End;

Function BrokerToolListed(Const ToolsJson, Name: String): Boolean;
Begin
  Result := Pos('"' + Name + '"', ToolsJson) > 0;
End;

Function ListedTools(Const ToolsJson: String; Const Names: Array Of String): String;
Var
  I, Count: Integer;
  Chosen: Array Of String;
Begin
  Result := '';
  SetLength(Chosen, 0);
  For I := 0 To High(Names) Do
    If BrokerToolListed(ToolsJson, Names[I]) Then
      Begin
        SetLength(Chosen, Length(Chosen) + 1);
        Chosen[High(Chosen)] := Names[I];
      End;
  Count := Length(Chosen);
  For I := 0 To Count - 1 Do
    Begin
      If I = 0 Then
        Result := Chosen[I]
      Else If I = Count - 1 Then
        Result := Result + ' and ' + Chosen[I]
      Else
        Result := Result + ', ' + Chosen[I];
    End;
End;

Function ClaudeCompileSentence(Const ToolsJson: String): String;
Begin
  Result := '';
  If BrokerToolListed(ToolsJson, 'lazarus_start_build') Then
    Begin
      Result := 'Run lazarus_start_build after edits';
      If BrokerToolListed(ToolsJson, 'lazarus_build_status') Then
        Result := Result + ' and poll lazarus_build_status';
      Result := Result + '. ';
    End
  Else
    Result := 'Compile after edits when a build tool is offered. ';
  If BrokerToolListed(ToolsJson, 'lazarus_start_tests') Then
    Result := Result + 'Run lazarus_start_tests with only for named regression tests. ';
  Result := Result + 'A clean compile does not mark this item complete.';
End;

Function ClaudeCompletionRules(Const ToolsJson: String): String;
Var
  UpdateTool, GitTool: String;
Begin
  If BrokerToolListed(ToolsJson, 'lazarus_update_markdown') Then
    UpdateTool := 'lazarus_update_markdown'
  Else
    UpdateTool := 'the offered Markdown tool';
  If BrokerToolListed(ToolsJson, 'lazarus_run_git') Then
    GitTool := 'lazarus_run_git'
  Else
    GitTool := 'the offered Git tool';
  Result :=
    'When an actionable item is finished, set its Status to complete with ' + UpdateTool + '. ' +
    'Do not put Status on a ## heading. A clean compile does not complete the item. ' +
    'If the working root is a Git repository, ' + GitTool + ' commit must succeed in this turn before Status becomes complete. ' +
    'Commit the finished files first, then set the status, then commit the plan file. ' +
    'Use one -m string for the subject and body, or several -m arguments; Git joins them with a blank line. ' +
    'A commit may end with -- and the files to record, so other staged files stay staged. ' +
    'If the turn ends with Status complete and that plan file is still uncommitted, the assistant commits the plan file and keeps the status. ' +
    'If the working root has no Git repository, set Status to complete with no commit. ' +
    'Report a commit hash only from a successful ' + GitTool + ' result. If a tool fails, say so. ' +
    'During a plan run, do not open the plan viewer. Status changes update the summary list. ' +
    'If that Markdown window is already open, it is refreshed.';
End;

Function ClaudeDiscoverSentence(Const ToolsJson: String): String;
Var
  Found: String;
Begin
  Found := ListedTools(ToolsJson, ['lazarus_search_in_project', 'lazarus_read_file']);
  If Found = '' Then
    Result := '2. Discover with the offered project tools. '
  Else
    Result := '2. Discover with ' + Found + '. ';
  Result := Result + PlanSectionReadSentence + ' ';
  If BrokerToolListed(ToolsJson, 'lazarus_read_markdown_section') Then
    Result := Result + 'Use lazarus_read_markdown_section for this item''s section. ';
  Result := Result + 'Apply authorized edits using the available project tools. ';
  If BrokerToolListed(ToolsJson, 'lazarus_ensure_form_component') Then
    Result := Result + 'Use lazarus_ensure_form_component for coordinated Pascal/LFM changes; do not create temporary probe units. ';
  If BrokerToolListed(ToolsJson, 'lazarus_replace_in_buffer') Then
    Result := Result + 'Use lazarus_replace_in_buffer for surgical edits. ';
  If BrokerToolListed(ToolsJson, 'lazarus_stage_patch') Then
    Result := Result + 'Use lazarus_stage_patch to stage part of a file. ';
  Result := TrimRight(Result);
End;

Function ClaudeContinueLead(Const ToolsJson: String): String;
Begin
  Result := 'Edits already applied are in the project. Do not re-read a file you already have';
  If BrokerToolListed(ToolsJson, 'lazarus_replace_in_buffer') Then
    Result := Result + ' unless a later lazarus_replace_in_buffer failed.'
  Else
    Result := Result + '.';
  Result := Result + LineEnding + PlanSectionReadSentence + LineEnding + ClaudeCompileSentence(ToolsJson) +
    ' A folder target compiles the Lazarus packages under that folder, not the project open in the IDE.';
End;

Function PlanWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String;
  ContinueSameItem, Claude: Boolean; Const ToolsJson: String): String;
Const
  MaxBodyChars = 6000;
Var
  Body, ToolInstructions, Heading, ContinueLead: String;
Begin
  Body := Trim(SectionBody);
  If Length(Body) > MaxBodyChars Then
    Body := Copy(Body, 1, MaxBodyChars) + LineEnding + LineEnding +
      '… *(section truncated for the prompt; open the plan file for the full text.)*';
  If Claude Then
    Begin
      ToolInstructions := ClaudeDiscoverSentence(ToolsJson) + LineEnding + '3. ' + ClaudeCompileSentence(ToolsJson);
      ContinueLead := ClaudeContinueLead(ToolsJson);
    End
  Else
    Begin
      ToolInstructions :=
        '2. Discover with search_in_project, get_project_info, list_directory and read_file. Apply authorized edits using the available project tools. ' +
        'Use ensure_form_component for coordinated Pascal/LFM changes; do not create temporary probe units. ' +
        PlanSectionReadSentence + LineEnding +
        '3. Run run_compile after edits, repair introduced errors and compile again. ' +
        'A clean compile does not mark this item complete.';
      ContinueLead :=
        'Edits already applied are in the project. Do not re-read a file you already have unless a later replace_in_file failed. ' +
        PlanSectionReadSentence + LineEnding +
        'Run run_compile. A folder target compiles the Lazarus packages under that folder, not the project open in the IDE.';
    End;
  Heading := '**Active plan:** `' + PlanRel + '`' + LineEnding;
  If Trim(ParentTitle) <> '' Then
    Heading := Heading + '**Section:** ' + ParentTitle + LineEnding;
  Heading := Heading + '**Item:** ' + SectionTitle + LineEnding + '**Status:** ' + StatusText + LineEnding + LineEnding;
  If ContinueSameItem Then
    Result := 'Continue this same plan item in **Build mode**. The previous turn left it in progress.' +
      LineEnding + LineEnding + ContinueLead + LineEnding +
      'When the written acceptance criteria are met, commit the finished files, set Status to complete, then commit the plan file. ' +
      'A missing Validation line does not block that status change. A clean compile alone does not complete the item.' +
      LineEnding + LineEnding + Heading
  Else
    Result := 'Work on this plan item in **Build mode**.' + LineEnding + LineEnding + Heading;
  Result := Result +
    'Instructions:' + LineEnding + '1. Focus only on this actionable item unless blocked.' + LineEnding +
    ToolInstructions + LineEnding +
    '4. ';
  If Claude Then
    Result := Result + ClaudeCompletionRules(ToolsJson)
  Else
    Result := Result + AssistantPlanCompletionRules;
  Result := Result + LineEnding +
    '5. Follow the acceptance criteria in the section. Do not change validation requirements to make work pass. ' +
    'Unchecked acceptance items require manual review. A clean compile alone does not prove correct behavior.' +
    LineEnding + LineEnding + '----- begin plan section -----' + LineEnding + Body + LineEnding + '----- end plan section -----';
End;

End.
