Unit AssistantPlanRunHost;

{ Plan sheet and plan run for the project assistant (c) 2026 Michell Computing.
  Size note: the plan sheet and the run loop are one job. Reviewed 2026-07-14. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, Graphics, StdCtrls, ExtCtrls, LCLType, Menus, ProjectAssistantForm, AssistantPlanRun;

Procedure Seam_ReviewPlanItemClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_PlanListPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ReviewSelectedPlanItem(Form: TProjectAssistantForm);
Function Seam_SelectedPlanListIndex(Form: TProjectAssistantForm): Integer;
Procedure Seam_BuildTodoListContextPopup(Form: TProjectAssistantForm; Sender: TObject; MousePos: TPoint; Var Handled: Boolean);
Procedure Seam_BuildTodoListMouseDown(Form: TProjectAssistantForm; Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Procedure Seam_SelectPlanListRowAt(Form: TProjectAssistantForm; Const LocalPos: TPoint);
Procedure Seam_BuildTodoListDblClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_BuildTodoListDrawItem(Form: TProjectAssistantForm; Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
Procedure Seam_BuildTodoListSelectionChange(Form: TProjectAssistantForm; Sender: TObject; User: Boolean);
Procedure Seam_BuildTodoListClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_RunPlanActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ContinueRunPlan(Form: TProjectAssistantForm; Data: PtrInt);
Procedure Seam_PlanStallTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ContinuePlanInNewChat(Form: TProjectAssistantForm; UsagePercent: Integer);
Function Seam_PlanHasOpenItems(Form: TProjectAssistantForm): Boolean;
Function Seam_PlanContextThreshold(Form: TProjectAssistantForm): Integer;
Procedure Seam_ReleasePlanStallWatch(Form: TProjectAssistantForm);
Procedure Seam_MarkPlanAgentAlive(Form: TProjectAssistantForm);
Procedure Seam_EnablePlanStallTimer(Form: TProjectAssistantForm);
Procedure Seam_RunPlan(Form: TProjectAssistantForm);
Procedure Seam_StopRunPlan(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String);
Procedure Seam_PostPlanRunReport(Form: TProjectAssistantForm; Const Report: String);
Function Seam_EndRunPlan(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String): String;
Function Seam_CollectPlanRunReportFacts(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String): TPlanRunReportFacts;
Function Seam_FindNextIncompleteBuildSection(Form: TProjectAssistantForm): Integer;
Procedure Seam_BuildWorkOnSelectedPackage(Form: TProjectAssistantForm);
Function Seam_BuildWorkPrompt(Form: TProjectAssistantForm; Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String; ContinueSameItem: Boolean): String;
Function Seam_ClaudeBuildToolsJson(Form: TProjectAssistantForm): String;
Procedure Seam_OfferFixTopErrorAfterReview(Form: TProjectAssistantForm);
Procedure Seam_PrepareTopErrorAfterReview(Form: TProjectAssistantForm; ErrorCount: Integer);
Function Seam_BuildWorkSectionIsComplete(Form: TProjectAssistantForm): Boolean;
Procedure Seam_TryAutoCompleteBuildWork(Form: TProjectAssistantForm; Const StreamErrorText: String);
Procedure Seam_BeginBuildWorkTracking(Form: TProjectAssistantForm; SectionIndex: Integer; Const SectionTitle: String);
Procedure Seam_ClearBuildWorkTracking(Form: TProjectAssistantForm);
Procedure Seam_SetBuildStatusFeedback(Form: TProjectAssistantForm; Const MessageText: String);
Function Seam_BuildSelectionMessage(Form: TProjectAssistantForm): String;
Function Seam_SelectedBuildRowIsContext(Form: TProjectAssistantForm): Boolean;
Function Seam_SelectedBuildSectionIndex(Form: TProjectAssistantForm): Integer;
Procedure Seam_PlanFileTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_EnsurePlanFileTimer(Form: TProjectAssistantForm);
Function Seam_PlanDocumentRevision(Form: TProjectAssistantForm): String;
Procedure Seam_NoteMonitorPlanRevision(Form: TProjectAssistantForm);
Procedure Seam_NotePlanDiskAge(Form: TProjectAssistantForm);
Procedure Seam_RefreshBuildTodos(Form: TProjectAssistantForm);
Procedure Seam_NewPlan(Form: TProjectAssistantForm);
Procedure Seam_ActivePlanBrowseClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ActivePlanChoiceChanged(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_RefreshActivePlanChoices(Form: TProjectAssistantForm; Sender: TObject);

Implementation

Uses
  SysUtils, DateUtils, Contnrs, ComCtrls, Dialogs, Forms, LCLIntf, LazFileUtils,
  WorkflowLog, CanvasUtils, IDEMsgIntf, IDEExternToolIntf, SrcEditorIntf, AssistantPlan, AssistantPlanDocument,
  AssistantConversation, AssistantTools, AssistantService, AssistantConfig, AssistantSessionObserve,
  AssistantTrace, AssistantTurnFinish, AssistantRecovery, AssistantIDEWorkspace, AssistantToolBroker,
  AssistantMarkdownForm, AssistantClaudeClient, AssistantWorkTarget, AssistantAcceptance, AssistantBuildJob,
  AssistantGit;

Procedure Seam_ReviewPlanItemClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    ReviewSelectedPlanItem;
    End;
End;

Procedure Seam_PlanListPopupPopup(Form: TProjectAssistantForm; Sender: TObject);
Var
  HasPlan, HasItem: Boolean;
Begin
  With Form Do
    Begin
    HasPlan := GetActivePlanRelativePath <> '';
    HasItem := HasPlan And (SelectedPlanListIndex >= 0) And (Not FPlanAgentRunning);
    If Assigned(ReviewItemMenu) Then
      ReviewItemMenu.Enabled := HasItem;
    If Assigned(ReviewPlanMenu) Then
      ReviewPlanMenu.Enabled := HasPlan And (Not FPlanAgentRunning);
    If Assigned(ClosePlanMenu) Then
      ClosePlanMenu.Enabled := HasPlan And (Not FSending) And (Not FReviewInProgress) And (Not FPlanAgentRunning);
    End;
End;

Procedure Seam_ReviewSelectedPlanItem(Form: TProjectAssistantForm);
Var
  PlanRel, Err, Body, Title, Key: String;
  Idx: Integer;
  Section: TPlanSection;
Begin
  With Form Do
    Begin
    PlanRel := GetActivePlanRelativePath;
    If PlanRel = '' Then
      Begin
        RunAssistantModal('Set an active plan on the Plan tab first.', mtInformation, [mbOK], 0);
        Exit;
      End;
    Idx := SelectedPlanListIndex;
    If Idx < 0 Then
      Begin
        RunAssistantModal('Select an item in the plan list.', mtInformation, [mbOK], 0);
        Exit;
      End;
    Section := TPlanSection(BuildSections[Idx]);
    If Not Assigned(Section) Then
      Exit;
    { A ## row includes its ### items (2.1, 2.2, …). An item stays that item only. }
    If Not GetPlanSectionBody(PlanRel, Idx, Body, Err, Not Section.Actionable) Then
      Begin
        RunAssistantModal('Could not load plan section:' + LineEnding + Err, mtError, [mbOK], 0);
        Exit;
      End;
    Title := Section.Title;
    If Trim(Section.ParentTitle) <> '' Then
      Title := Section.ParentTitle + ' — ' + Title;
    Key := PlanRel + '#' + IntToStr(Idx);
    OpenMarkdownSnippet(Key, Title, Body);
    End;
End;

Function Seam_SelectedPlanListIndex(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    Result := -1;
    If Not Assigned(BuildSections) Or (BuildSections.Count = 0) Then
      Exit;
    If Assigned(BuildTodoList) And (BuildTodoList.ItemIndex >= 0) And
      (BuildTodoList.ItemIndex < BuildSections.Count) Then
      Result := BuildTodoList.ItemIndex
    Else If (FBuildSelectedIndex >= 0) And (FBuildSelectedIndex < BuildSections.Count) Then
      Result := FBuildSelectedIndex;
    End;
End;

Procedure Seam_BuildTodoListContextPopup(Form: TProjectAssistantForm; Sender: TObject; MousePos: TPoint; Var Handled: Boolean);
Begin
  With Form Do
    Begin
    Handled := False;
    SelectPlanListRowAt(MousePos);
    End;
End;

Procedure Seam_BuildTodoListMouseDown(Form: TProjectAssistantForm; Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  With Form Do
    Begin
    If Button = mbRight Then
      SelectPlanListRowAt(Point(X, Y));
    End;
End;

Procedure Seam_SelectPlanListRowAt(Form: TProjectAssistantForm; Const LocalPos: TPoint);
Var
  Idx: Integer;
Begin
  With Form Do
    Begin
    If Not Assigned(BuildTodoList) Then
      Exit;
    If (LocalPos.X < 0) Or (LocalPos.Y < 0) Then
      Exit;
    Idx := BuildTodoList.ItemAtPos(LocalPos, True);
    If Idx < 0 Then
      Exit;
    BuildTodoList.ItemIndex := Idx;
    FBuildSelectedIndex := Idx;
    End;
End;

Procedure Seam_BuildTodoListDblClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    BuildTodoListClick(Sender);
    ReviewSelectedPlanItem;
    End;
End;

Procedure Seam_BuildTodoListDrawItem(Form: TProjectAssistantForm; Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);

  Function PillCaption(Status: TPlanSectionStatus): String;
  Begin
    With Form Do
    Begin
    Case Status Of
      pssNotStarted: Result := 'Not Started';
      pssInProgress: Result := 'In Progress';
      pssComplete: Result := 'Complete';
      pssBlocked: Result := 'Blocked';
    Else
      Result := '';
    End;
    End;
  End;

  { Same treatment as the history ref cards: pastel fill, darker border, darker text. }
  Procedure PillColors(Status: TPlanSectionStatus; Out Fill, Ink, Border: TColor);
  Begin
    With Form Do
    Begin
    Case Status Of
      pssNotStarted:
        Begin
          Fill := RGBToColor(255, 243, 205);
          Ink := RGBToColor(121, 85, 0);
          Border := RGBToColor(212, 160, 23);
        End;
      pssInProgress:
        Begin
          Fill := RGBToColor(232, 245, 233);
          Ink := RGBToColor(27, 94, 32);
          Border := RGBToColor(67, 160, 71);
        End;
      pssComplete:
        Begin
          Fill := RGBToColor(227, 242, 253);
          Ink := RGBToColor(13, 71, 161);
          Border := RGBToColor(66, 165, 245);
        End;
      pssBlocked:
        Begin
          Fill := RGBToColor(255, 235, 238);
          Ink := RGBToColor(183, 28, 28);
          Border := RGBToColor(229, 57, 53);
        End;
    Else
      Begin
        Fill := clNone;
        Ink := clNone;
        Border := clNone;
      End;
    End;
    End;
  End;

Var
  List: TListBox;
  Section: TPlanSection;
  CaptionText, StatusText, TitleText: String;
  Fill, Ink, Border, RowColor: TColor;
  Selected: Boolean;
  Pad, TextH, PillWidth, PillLeft, PillTop, PillBottom, TitleLeft, TitleRight: Integer;
  TitleRect, PillRect: TRect;
  TitleStyle: TTextStyle;
Begin
  With Form Do
    Begin
    If Not (Control Is TListBox) Then
      Exit;
    List := TListBox(Control);
    Selected := odSelected In State;
    List.Canvas.Font.Assign(List.Font);
    List.Canvas.Font.Style := [];
    If Selected Then
      RowColor := ColorToRGB(clHighlight)
    Else
      RowColor := List.GetRGBColorResolvingParent;
    { Resolve clDefault through the control before blending, as the history cards
      use an explicit row colour. A raw clDefault becomes black in ColorToRGB. }
    List.Canvas.Brush.Style := bsSolid;
    List.Canvas.Brush.Color := RowColor;
    List.Canvas.FillRect(ARect);
    CaptionText := '';
    If (Index >= 0) And (Index < List.Items.Count) Then
      CaptionText := List.Items[Index];
    Section := Nil;
    If Assigned(BuildSections) And (Index >= 0) And (Index < BuildSections.Count) Then
      Section := TPlanSection(BuildSections[Index]);
    StatusText := '';
    If Assigned(Section) And Section.Actionable Then
      StatusText := PillCaption(Section.Status);
    If Assigned(Section) Then
      TitleText := Section.Title
    Else
      TitleText := CaptionText;
    Pad := Scale96ToForm(6);
    TitleLeft := ARect.Left + Pad;
    If Assigned(Section) And Section.Actionable Then
      Inc(TitleLeft, Scale96ToForm(8));
    TitleRight := ARect.Right - Pad;
    If StatusText <> '' Then
      Begin
        List.Canvas.Font.Size := 8;
        List.Canvas.Font.Quality := fqCleartypeNatural;
        PillColors(Section.Status, Fill, Ink, Border);
        PillWidth := List.Canvas.TextWidth(StatusText) + Scale96ToForm(12);
        PillLeft := ARect.Right - Pad - PillWidth;
        If PillLeft < TitleLeft + Scale96ToForm(24) Then
          PillLeft := TitleLeft + Scale96ToForm(24);
        TitleRight := PillLeft - Scale96ToForm(6);
        TextH := Scale96ToForm(18);
        PillTop := ARect.Top + ((ARect.Bottom - ARect.Top) - TextH) Div 2;
        PillBottom := PillTop + TextH;
        If PillBottom > ARect.Bottom - 1 Then
          PillBottom := ARect.Bottom - 1;
        If PillTop < ARect.Top + 1 Then
          PillTop := ARect.Top + 1;
        PillRect := Rect(PillLeft, PillTop, PillLeft + PillWidth, PillBottom);
        DrawSmoothRoundRect(List.Canvas, PillRect, Scale96ToForm(4), Fill, Border, RowColor,
          List.GetCanvasScaleFactor);
        List.Canvas.Font.Color := Ink;
        List.Canvas.Brush.Style := bsClear;
        TextH := List.Canvas.TextHeight(StatusText);
        List.Canvas.TextOut(PillRect.Left + Scale96ToForm(6), PillRect.Top + ((PillRect.Bottom - PillRect.Top) - TextH) Div 2, StatusText);
        List.Canvas.Brush.Style := bsSolid;
        List.Canvas.Font.Assign(List.Font);
      End;
    If Selected Then
      List.Canvas.Font.Color := clHighlightText
    Else
      List.Canvas.Font.Color := List.Font.Color;
    If Assigned(Section) And Not Section.Actionable Then
      List.Canvas.Font.Style := [fsBold];
    TitleRect := Rect(TitleLeft, ARect.Top, TitleRight, ARect.Bottom);
    TitleStyle := List.Canvas.TextStyle;
    TitleStyle.Alignment := taLeftJustify;
    TitleStyle.Layout := tlCenter;
    TitleStyle.SingleLine := True;
    TitleStyle.EndEllipsis := True;
    TitleStyle.Clipping := True;
    TitleStyle.Opaque := False;
    TitleStyle.SystemFont := False;
    List.Canvas.Brush.Style := bsClear;
    List.Canvas.TextRect(TitleRect, TitleLeft, TitleRect.Top, TitleText, TitleStyle);
    If odFocused In State Then
      List.Canvas.DrawFocusRect(ARect);
    End;
End;

Procedure Seam_BuildTodoListSelectionChange(Form: TProjectAssistantForm; Sender: TObject; User: Boolean);
Begin
  With Form Do
    Begin
    If Assigned(BuildTodoList) And Assigned(BuildSections) And
      (BuildTodoList.ItemIndex >= 0) And
      (BuildTodoList.ItemIndex < BuildSections.Count) Then
      FBuildSelectedIndex := BuildTodoList.ItemIndex;
    End;
End;

Procedure Seam_BuildTodoListClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If Assigned(BuildTodoList) And Assigned(BuildSections) And
      (BuildTodoList.ItemIndex >= 0) And
      (BuildTodoList.ItemIndex < BuildSections.Count) Then
      FBuildSelectedIndex := BuildTodoList.ItemIndex;
    End;
End;

Procedure Seam_RunPlanActionExecute(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    If FPlanAgentRunning Then
      Begin
        If RunAssistantModal('Stop the plan agent after the current reply finishes?',
          mtConfirmation, [mbYes, mbNo], 0) = mrYes Then
          StopRunPlan(preUserStop, 'stopped by user');
        Exit;
      End;
    RunPlan;
    End;
End;

Procedure Seam_ContinueRunPlan(Form: TProjectAssistantForm; Data: PtrInt);
Var
  Idx, Pct, Threshold: Integer;
  ContinueInNewChat: Boolean;
Begin
  With Form Do
    Begin
    If csDestroying In ComponentState Then
      Exit;
    If Not FPlanAgentRunning Then
      Exit;
    If FSending Then
      Begin
        Application.QueueAsyncCall(@ContinueRunPlan, 0);
        Exit;
      End;
    If FLastTurnHadError Then
      Begin
        StopRunPlan(preError, 'The last package ended with an error.');
        Exit;
      End;
    Threshold := PlanContextThreshold;
    If FContextLimit > 0 Then
      Begin
        If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
          FContextUsed := AssistantClient.EstimatedPromptTokens;
        Pct := (FContextUsed * 100) Div FContextLimit;
        If Pct >= Threshold Then
          Begin
            If AutoCompactAtLimitEnabled Then
              Begin
                { Compact this conversation and keep walking packages. Do not start a new chat yet. }
                FContextWarnShown := False;
                MaybeWarnHighContextUsage;
                If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
                  FContextUsed := AssistantClient.EstimatedPromptTokens;
                Pct := (FContextUsed * 100) Div FContextLimit;
              End;
            ContinueInNewChat := PlanRunContinuesInNewChat(Pct, Threshold,
              Assigned(AssistantChatConfig) And AssistantChatConfig.AutoNewChatAtContextLimit) And
              (Not FPlanNewChatThisStep);
            If Pct >= Threshold Then
              Begin
                If ContinueInNewChat Then
                  Begin
                    ContinuePlanInNewChat(Pct);
                    Exit;
                  End;
                MaybeWarnHighContextUsage;
                If AutoCompactAtLimitEnabled Then
                  StopRunPlan(preContextLimit, Format('context usage %d%% after compact — start a New Chat', [Pct]))
                Else
                  StopRunPlan(preContextLimit, Format('context usage %d%% — start a New Chat', [Pct]));
                Exit;
              End;
          End;
      End;
    If FPlanAgentPackagesDone >= FPlanAgentMaxPackages Then
      Begin
        StopRunPlan(prePackageCap, IntToStr(FPlanAgentMaxPackages));
        Exit;
      End;
    RefreshBuildTodos;
    Idx := FindNextIncompleteBuildSection;
    If Idx < 0 Then
      Begin
        StopRunPlan(preCleanFinish, '');
        Exit;
      End;
    FBuildSelectedIndex := Idx;
    If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
      BuildTodoList.ItemIndex := Idx;
    { Work saved since the last item, or left unsaved during it, is asked about before the next item starts. }
    If Not ConfirmSavedBeforeTurn(amBuild) Then
      Begin
        StopRunPlan(preUserStop, 'unsaved edits were not saved');
        Exit;
      End;
    SetBuildStatusFeedback(Format('Plan agent: package %d…', [FPlanAgentPackagesDone + 1]));
    BuildWorkOnSelectedPackage;
    If Not FSending Then
      StopRunPlan(preError, 'Failed to start the next package.');
    End;
End;

Procedure Seam_PlanStallTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Var
  WaitMs: QWord;
  WaitSeconds: Integer;
Begin
  With Form Do
    Begin
    Try
      If csDestroying In ComponentState Then
        Exit;
      If Not FPlanAgentRunning Then
        Begin
          ReleasePlanStallWatch;
          Exit;
        End;
      If FSending Or FPlanStallRestarting Or FTransportWait Or FAutoRolloverInProgress Then
        Exit;
      If Not PlanHasOpenItems Then
        Exit;
      If Not PlanRunUnexplainedStall(True, False, False, 1) Then
        Exit;
      { One second for the queued continuation to start. A lost queue is the stall. }
      If GetTickCount64 - FPlanStallArmedTick < 1000 Then
        Exit;
      WaitMs := FReconnectIntervalMs;
      If WaitMs = 0 Then
        WaitMs := AssistantReconnectIntervalMs;
      WaitSeconds := WaitMs Div 1000;
      If Not FPlanStallNoted Then
        Begin
          FPlanStallNoted := True;
          FPlanStallArmedTick := GetTickCount64;
          PostRecoverySentence(PlanRunStallWaitNote(WaitSeconds));
          SetBuildStatusFeedback(PlanRunStallWaitNote(WaitSeconds));
          Exit;
        End;
      If (WaitMs > 0) And (GetTickCount64 - FPlanStallArmedTick < WaitMs) Then
        Exit;
      FPlanStallRestarting := True;
      Try
        FPlanStallNoted := False;
        MarkPlanAgentAlive;
        PostRecoverySentence(PlanRunStallResumeNote);
        ContinueRunPlan(0);
      Finally
        FPlanStallRestarting := False;
      End;
    Except
      On E: Exception Do
        Begin
          ReleasePlanStallWatch;
          ClassifyFormFault(Form, afoPaintLayout, 'TProjectAssistantForm.PlanStallTimerTimer', E, False);
        End;
    End;
    End;
End;

Procedure Seam_ContinuePlanInNewChat(Form: TProjectAssistantForm; UsagePercent: Integer);
Begin
  With Form Do
    Begin
    FPlanNewChatThisStep := True;
    FAutoRolloverInProgress := True;
    Try
      { Keep the agent. The archived chat is not a plan-run end. }
      If Not StartNewChat(True, False) Then
        Exit;
    Finally
      FAutoRolloverInProgress := False;
    End;
    If Not FPlanAgentRunning Then
      Exit;
    SetCurrentSystemNote(PlanRunNewChatNote(UsagePercent));
    PostRecoverySentence(PlanRunNewChatNote(UsagePercent));
    MarkPlanAgentAlive;
    Application.QueueAsyncCall(@ContinueRunPlan, 0);
    End;
End;

Function Seam_PlanHasOpenItems(Form: TProjectAssistantForm): Boolean;
Begin
  With Form Do
    Begin
    Result := FindNextIncompleteBuildSection >= 0;
    End;
End;

Function Seam_PlanContextThreshold(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    If Assigned(AssistantChatConfig) Then
      Result := PlanContextContinuePercent(AssistantChatConfig.NewChatContextPercent)
    Else
      Result := AssistantPlanContextPercentDefault;
    End;
End;

Procedure Seam_ReleasePlanStallWatch(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    { Do not free the timer here. EndRunPlan and the timer event both call this. }
    FPlanStallNoted := False;
    FPlanStallRestarting := False;
    FPlanNewChatThisStep := False;
    If Assigned(FPlanStallTimer) Then
      FPlanStallTimer.Enabled := False;
    End;
End;

Procedure Seam_MarkPlanAgentAlive(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    FPlanStallArmedTick := GetTickCount64;
    FPlanStallNoted := False;
    EnablePlanStallTimer;
    End;
End;

Procedure Seam_EnablePlanStallTimer(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Not Assigned(FPlanStallTimer) Then
      Begin
        { Nil owner: a streamed form must not gain a designer timer from Create(Form). }
        FPlanStallTimer := TTimer.Create(Nil);
        FPlanStallTimer.Enabled := False;
        FPlanStallTimer.Interval := 1000;
        FPlanStallTimer.OnTimer := @PlanStallTimerTimer;
      End;
    FPlanStallTimer.Enabled := FPlanAgentRunning;
    End;
End;

Procedure Seam_RunPlan(Form: TProjectAssistantForm);
Var
  Idx: Integer;
  Note: String;
Begin
  With Form Do
    Begin
    If FSending Or FPlanAgentRunning Then
      Begin
        RunAssistantModal('Wait for the current reply to finish before starting Run Plan.',
          mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not RunPlanIsAvailable Then
      Begin
        UpdateWorkActions;
        RunAssistantModal('Set an active plan first.', mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not Assigned(FIDEWorkspace) Then FIDEWorkspace := TAssistantIDEWorkspace.Create;
    Note := PlanRunBuildRefusal(FIDEWorkspace.CanBuild, AssistantTarget.Manifest);
    If Note <> '' Then Begin SetBuildStatusFeedback(Note); Exit; End;
    { Available from Chat, Inspect, Document, Plan, or Build. Switch before any package work. }
    SelectMode(amBuild);
    RefreshBuildTodos;
    Idx := FindNextIncompleteBuildSection;
    If Idx < 0 Then
      Begin
        RunAssistantModal(AssistantPlanRunStartMessage(CollectPlanRunReportFacts(preCleanFinish, '')),
          mtInformation, [mbOK], 0);
        Exit;
      End;
    { Before the run starts, so No leaves no run, plan status or chat behind. }
    If Not ConfirmSavedBeforeTurn(amBuild) Then
      Exit;
    FPlanAgentRunning := True;
    FPlanRunStartTick := GetTickCount64;
    UpdateWorkActions;
    AssistantSessionObserve.AssistantSessionObserve(asnPlan);
    SyncCodexUsageIdle;
    SetAssistantPlanViewerQuiet(True);
    FPlanAgentPackagesDone := 0;
    FPlanAgentResumeIndex := -1;
    FClaudePlanItem.SessionId := '';
    FPlanItemUsage := '';
    FLastTurnHadError := False;
    FPlanNewChatThisStep := False;
    MarkPlanAgentAlive;
    FBuildSelectedIndex := Idx;
    If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
      BuildTodoList.ItemIndex := Idx;
    SetBuildStatusFeedback('Plan agent: starting…');
    SetCurrentSystemNote(
      '**Plan agent** started — will work through incomplete packages until complete, error, ' +
      'context ≥ 95%, or max packages.');
    BuildWorkOnSelectedPackage;
    If Not FSending Then
      StopRunPlan(preError, 'Could not start the first package.');
    End;
End;

Procedure Seam_StopRunPlan(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String);
Var
  Report: String;
Begin
  With Form Do
    Begin
    Report := EndRunPlan(Kind, Detail);
    If Report <> '' Then
      PostPlanRunReport(Report);
    End;
End;

Procedure Seam_PostPlanRunReport(Form: TProjectAssistantForm; Const Report: String);
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Trace: TAssistantTrace;
  Stored: Boolean;
Begin
  With Form Do
    Begin
    If Trim(Report) = '' Then
      Exit;
    Stored := False;
    EnsureConversationStore;
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      Begin
        Turn.Id := NewConversationTurnId;
        Turn.Mode := AssistantModeToStr(amBuild);
        { A report is a note, not a command. Do not invent a user message. }
        Turn.Prompt := '';
        Turn.Thinking := '';
        Turn.Response := Report;
        Turn.CreatedAt := IsoNowUtc;
        Turn.StartedAt := Turn.CreatedAt;
        Turn.FinishedAt := Turn.CreatedAt;
        Turn.DurationMs := 0;
        Turn.ThinkingMs := 0;
        Turn.Model := '';
        Turn.Skill := '';
        Turn.TokenEstimate := Length(Report) Div 4;
        Turn.ErrorText := '';
        Turn.PlanFile := GetActivePlanRelativePath;
        Turn.TodoId := '';
        Turn.EventsFile := '';
        { Empty message list: the report is for the user, not replayed into the model. }
        Turn.MessagesJson := '[]';
        Turn.AttachmentsJson := '';
        Turn.ClientCommandId := '';
        Turn.TraceJson := '';
        Trace := TAssistantTrace.Create;
        Try
          Trace.AddNote(Report);
          Turn.TraceJson := Trace.SaveToJson;
        Finally
          Trace.Free;
        End;
        Stored := ProjectAssistantConversation.AppendTurn(Turn, Entry);
        If Not Stored Then
          WorkflowLogger.Warning('ProjectAssistant', 'Plan run report was not stored: ' +
            ProjectAssistantConversation.LastError);
      End;
    FDisplaySystemNote := Report;
    If Stored Then
      Begin
        If Not FSending Then
          Begin
            FViewingLive := False;
            FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
          End;
        RefreshConversationList;
        RefreshChatDisplay(True, True);
      End
    Else
      Begin
        If Assigned(FTrace) Then
          FTrace.AddNote(Report);
        RefreshChatDisplay(True, True);
        If Not FSending Then
          RunAssistantModal(Report, mtInformation, [mbOK], 0);
      End;
    End;
End;

Function Seam_EndRunPlan(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String): String;
Var
  Facts: TPlanRunReportFacts;
  RunMs: QWord;
Begin
  With Form Do
    Begin
    Result := '';
    If Not FPlanAgentRunning Then
      Exit;
    { Read the run clock first, so the report's total covers the whole run. }
    RunMs := 0;
    If FPlanRunStartTick <> 0 Then
      RunMs := GetTickCount64 - FPlanRunStartTick;
    FPlanRunStartTick := 0;
    FPlanAgentRunning := False;
    UpdateWorkActions;
    ReleasePlanStallWatch;
    SetAssistantPlanViewerQuiet(False);
    Application.RemoveAsyncCalls(Form);
    RefreshBuildTodos;
    Facts := CollectPlanRunReportFacts(Kind, Detail);
    Facts.ElapsedMs := RunMs;
    Result := AssistantPlanRunReport(Facts);
    If FPlanItemUsage <> '' Then
      Result := Result + LineEnding + PlanRunUsageSummary(FPlanItemUsage);
    SetBuildStatusFeedback('Plan run ended: ' + AssistantPlanRunWhy(Facts));
    UpdateStatusFooter;
    WorkflowLogger.Info('ProjectAssistant', 'Plan run ended: ' + AssistantPlanRunWhy(Facts));
    AssistantSessionObserve.AssistantSessionObserve(asnPlan);
    End;
End;

Function Seam_CollectPlanRunReportFacts(Form: TProjectAssistantForm; Kind: TPlanRunEndKind; Const Detail: String): TPlanRunReportFacts;
Var
  I, N: Integer;
  Section: TPlanSection;
  PlanRel, Body, Err, ActionText: String;
Begin
  With Form Do
    Begin
    Result := DefaultPlanRunReportFacts;
    Result.Kind := Kind;
    Result.Detail := Detail;
    Result.PackagesWorked := FPlanAgentPackagesDone;
    Result.TerminalFault := Kind = preContextLimit;
    If Not Assigned(BuildSections) Then
      Exit;
    For I := 0 To BuildSections.Count - 1 Do
      Begin
        Section := TPlanSection(BuildSections[I]);
        If Not Section.Actionable Then
          Continue;
        Case Section.Status Of
          pssNotStarted: Inc(Result.NotStarted);
          pssInProgress: Inc(Result.InProgress);
          pssBlocked: Inc(Result.Blocked);
          pssComplete: Inc(Result.Complete);
        Else
          { Unknown status is not one of the four plan-list counts. }
        End;
      End;
    SetLength(Result.BlockedItems, Result.Blocked);
    N := 0;
    PlanRel := GetActivePlanRelativePath;
    For I := 0 To BuildSections.Count - 1 Do
      Begin
        Section := TPlanSection(BuildSections[I]);
        If (Not Section.Actionable) Or (Section.Status <> pssBlocked) Then
          Continue;
        If N > High(Result.BlockedItems) Then
          Break;
        Result.BlockedItems[N].Title := Section.Title;
        Result.BlockedItems[N].UserAction := '';
        Result.BlockedItems[N].HasUserAction := False;
        If (PlanRel <> '') And GetPlanSectionBody(PlanRel, I, Body, Err) Then
          Result.BlockedItems[N].HasUserAction := PlanBodyUserAction(Body, ActionText);
        If Result.BlockedItems[N].HasUserAction Then
          Result.BlockedItems[N].UserAction := ActionText;
        Inc(N);
      End;
    SetLength(Result.BlockedItems, N);
    End;
End;

Function Seam_FindNextIncompleteBuildSection(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    Result := NextIncompletePlanSection(BuildSections);
    End;
End;

Procedure Seam_BuildWorkOnSelectedPackage(Form: TProjectAssistantForm);
Var
  PlanRel, Err, Body, Prompt, Title, StatusText, ParentTitle: String;
  Idx: Integer;
  Section: TPlanSection;
  ContinueSame: Boolean;
Begin
  With Form Do
    Begin
    If FSending Then
      Begin
        RunAssistantModal('Wait for the current reply to finish (or Stop) before starting work.',
          mtInformation, [mbOK], 0);
        Exit;
      End;
    PlanRel := GetActivePlanRelativePath;
    If PlanRel = '' Then
      Begin
        RunAssistantModal('Set an active plan on the Plan tab first.', mtInformation, [mbOK], 0);
        Exit;
      End;
    Idx := SelectedBuildSectionIndex;
    If Idx < 0 Then
      Begin
        RunAssistantModal(BuildSelectionMessage, mtInformation, [mbOK], 0);
        Exit;
      End;
    { Before the item is marked in progress. }
    If Not ConfirmSavedBeforeTurn(amBuild) Then
      Exit;
    Section := TPlanSection(BuildSections[Idx]);
    Title := Section.Title;
    ParentTitle := Section.ParentTitle;
    StatusText := PlanSectionStatusToStr(Section.Status);
    If Section.Status = pssUnknown Then
      StatusText := 'unknown';
    { Mark in progress when starting work from a not-started package. }
    If Section.Status In [pssNotStarted, pssUnknown, pssBlocked] Then
      Begin
        If Not SetPlanSectionStatus(PlanRel, Idx, pssInProgress, Err) Then
          Begin
            RunAssistantModal('Could not set status to in progress:' + LineEnding + Err, mtWarning, [mbOK], 0);
            { Continue with the prompt anyway. }
          End
        Else
          Begin
            StatusText := PlanSectionStatusToStr(pssInProgress);
            FBuildSelectedIndex := Idx;
            RefreshBuildTodos;
            If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
              BuildTodoList.ItemIndex := Idx;
          End;
      End;
    If Not GetPlanSectionBody(PlanRel, Idx, Body, Err) Then
      Begin
        RunAssistantModal('Could not load plan section:' + LineEnding + Err, mtError, [mbOK], 0);
        Exit;
      End;
    ContinueSame := FPlanAgentRunning And (Idx = FPlanAgentResumeIndex);
    Prompt := BuildWorkPrompt(PlanRel, Title, StatusText, Body, ParentTitle, ContinueSame);
    FPlanAgentResumeIndex := -1;
    { Stay in Build mode (tools + prompt) while showing the chat turn surface. }
    BeginBuildWorkTracking(Idx, Title);
    ForceModeAndLock(amBuild);
    ShowChatSurfaceKeepMode;
    SetBuildStatusFeedback('Working on: ' + Title);
    PrepareClaudePlanItemSession(FClaudePlanItem, ContinueSame, FPlanAgentRunning, (FActiveBackend = 'claude'));
    SubmitUserText(Prompt, True);
    If Not FSending Then
      Begin
        ReleaseClaudePlanItemSession(FClaudePlanItem, FClaudeSessionId, FClaudeSessionKey);
        UnlockModeAfterSend;
        ClearBuildWorkTracking;
      End;
    End;
End;

Function Seam_BuildWorkPrompt(Form: TProjectAssistantForm; Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String; ContinueSameItem: Boolean): String;
Var
  Tools: String;
Begin
  With Form Do
    Begin
    Tools := '';
    If (FActiveBackend = 'claude') Then
      Tools := ClaudeBuildToolsJson;
    Result := PlanWorkPrompt(PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle, ContinueSameItem,
      (FActiveBackend = 'claude'), Tools);
    End;
End;

Function Seam_ClaudeBuildToolsJson(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    Result := '';
    If Not Assigned(FIDEWorkspace) Then FIDEWorkspace := TAssistantIDEWorkspace.Create;
    If Not Assigned(FToolBroker) Then FToolBroker := TAssistantToolBroker.Create(FIDEWorkspace);
    { A prompt must not start a run. BeginRun would cancel a build and replace the open run id. }
    Result := FToolBroker.ToolsJsonForScope(awsProject);
    End;
End;

Procedure Seam_OfferFixTopErrorAfterReview(Form: TProjectAssistantForm);
Var
  Line: TMessageLine;
  Note, MsgText: String;
Begin
  With Form Do
    Begin
    If Not FPendingReviewErrorOffer Then
      Exit;
    FPendingReviewErrorOffer := False;
    Line := ResolveMessageLineForFix(True);
    If Not Assigned(Line) Then
      Begin
        Note := Format('Review found **%d error(s)**. Open Messages, then click **Fix Error**.',
          [FReviewErrorCount]);
        If FViewingLive Then
          FDisplaySystemNote := Note
        Else
          SetCurrentSystemNote(Note);
        Exit;
      End;
    If Assigned(IDEMessagesWindow) Then
      IDEMessagesWindow.SelectMsgLine(Line);
    If Line.TranslatedMsg <> '' Then
      MsgText := Line.TranslatedMsg
    Else
      MsgText := Line.Msg;
    If Line.Filename <> '' Then
      MsgText := ExtractFileName(Line.GetFullFilename) + ': ' + MsgText;
    Note :=
      Format('Review found **%d error(s)**. Top error is selected in Messages.', [FReviewErrorCount]) +
      LineEnding + LineEnding +
      '**' + Trim(MsgText) + '**' + LineEnding + LineEnding +
      'Click **Fix Error** (or Assistant → Fix Error in Build mode) to apply a Build-mode fix with tools.';
    If FViewingLive Then
      Begin
        If FDisplaySystemNote <> '' Then
          FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Note
        Else
          FDisplaySystemNote := Note;
      End
    Else
      SetCurrentSystemNote(Note);
    StatusFooter.SetRightText('Review: Fix Error ready');
    End;
End;

Procedure Seam_PrepareTopErrorAfterReview(Form: TProjectAssistantForm; ErrorCount: Integer);
Var
  Line: TMessageLine;
Begin
  With Form Do
    Begin
    FReviewErrorCount := ErrorCount;
    FPendingReviewErrorOffer := ErrorCount > 0;
    If Not FPendingReviewErrorOffer Then
      Exit;
    Line := ResolveMessageLineForFix(True);
    If Assigned(Line) And Assigned(IDEMessagesWindow) Then
      IDEMessagesWindow.SelectMsgLine(Line);
    End;
End;

Function Seam_BuildWorkSectionIsComplete(Form: TProjectAssistantForm): Boolean;
Var
  Sections: TObjectList;
  Err: String;
Begin
  With Form Do
    Begin
    Result := False;
    If (FBuildWorkPlanPath = '') Or (FBuildWorkSectionIndex < 0) Then
      Exit;
    Sections := TObjectList.Create(True);
    Try
      If Not ScanPlanSections(FBuildWorkPlanPath, Sections, Err) Then
        Exit;
      If FBuildWorkSectionIndex >= Sections.Count Then
        Exit;
      Result := TPlanSection(Sections[FBuildWorkSectionIndex]).Status = pssComplete;
    Finally
      Sections.Free;
    End;
    End;
End;

Procedure Seam_TryAutoCompleteBuildWork(Form: TProjectAssistantForm; Const StreamErrorText: String);
Var
  PlanRel, Err, Note, CurrentPlan, TrackedTitle, TrackedBody: String;
  TrackedStatus: TPlanSectionStatus;
  Idx: Integer; Editor: TSourceEditorInterface;

  Procedure ShowBuildNote(Const Reason: String);
  Begin
    With Form Do
    Begin
    If Reason = '' Then
      Exit;
    If FViewingLive Then
      Begin
        If FDisplaySystemNote <> '' Then
          FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Reason
        Else
          FDisplaySystemNote := Reason;
      End
    Else
      SetCurrentSystemNote(Reason);
    End;
  End;

  Procedure LeaveInProgress(Const Reason: String);
  Begin
    With Form Do
    Begin
    { Same item on the next plan turn. Do not mark blocked and do not stop the run. }
    If FPlanAgentRunning Then
      FPlanAgentResumeIndex := FBuildWorkSectionIndex;
    SetBuildStatusFeedback(Reason);
    ShowBuildNote(Reason);
    End;
  End;

  Function ContinuationCapReached: Boolean;
  Begin
    With Form Do
    Begin
    Result := (FContinuationCap < 1) Or (FContinuationCount >= FContinuationCap);
    End;
  End;

  Function ReadTrackedSection(Out Title, Body: String; Out Status: TPlanSectionStatus): Boolean;
  Var
    Sections: TObjectList;
    Section: TPlanSection;
    ReadErr: String;
  Begin
    With Form Do
    Begin
    Result := False;
    Title := FBuildWorkSectionTitle;
    Body := FBuildWorkBody;
    Status := pssUnknown;
    If (FBuildWorkPlanPath = '') Or (FBuildWorkSectionIndex < 0) Then
      Exit;
    Sections := TObjectList.Create(True);
    Try
      If Not ScanPlanSections(FBuildWorkPlanPath, Sections, ReadErr) Then
        Exit;
      If FBuildWorkSectionIndex >= Sections.Count Then
        Exit;
      Section := TPlanSection(Sections[FBuildWorkSectionIndex]);
      Status := Section.Status;
      If Section.Title <> '' Then
        Title := Section.Title;
      If Not GetPlanSectionBody(FBuildWorkPlanPath, FBuildWorkSectionIndex, Body, ReadErr) Then
        Body := FBuildWorkBody;
      Result := True;
    Finally
      Sections.Free;
    End;
    End;
  End;

  Procedure ApplyRealBlock(Const Title, FallbackAction: String);
  Var
    Stored, BlockErr, Report: String;
  Begin
    With Form Do
    Begin
    FPlanAgentResumeIndex := -1;
    If Not SetPlanSectionBlocked(FBuildWorkPlanPath, FBuildWorkSectionIndex, FallbackAction, Stored, BlockErr) Then
      Begin
        SetBuildStatusFeedback('Could not mark the item blocked: ' + BlockErr);
        Exit;
      End;
    Report := AssistantBlockedItemReport(Title, Stored);
    SetBuildStatusFeedback(Report);
    ShowBuildNote(Report);
    RefreshBuildTodos;
    If FPlanAgentRunning And PlanRunBlockedSourceStop(ProjectAssistantRoot, Report) Then
      StopRunPlan(preUncommitted, Report);
    End;
  End;

Begin
  With Form Do
    Begin
    Idx := FBuildWorkSectionIndex;
    If Idx < 0 Then Exit;
    If StreamErrorText <> '' Then
      Begin
        SetBuildStatusFeedback('Work interrupted — item still in progress.');
        RefreshBuildTodos;
        Exit;
      End;
    { The saved plan is authoritative. The pre-turn text has no Validation line on most items,
      and stopping on that text ended the run after a completion had already been written. }
    If FPlanAgentRunning And BuildWorkSectionIsComplete Then
      Begin
        FPlanAgentResumeIndex := -1;
        SetBuildStatusFeedback(Format('%s → complete', [FBuildWorkSectionTitle]));
        Exit;
      End;
    { The saved section is authoritative. A start-of-turn snapshot misses a status the model just wrote. }
    If Not ReadTrackedSection(TrackedTitle, TrackedBody, TrackedStatus) Then
      Begin
        TrackedTitle := FBuildWorkSectionTitle;
        TrackedBody := FBuildWorkBody;
        TrackedStatus := pssUnknown;
      End;
    { Block only when a person must act. A missing Validation line and a failed build stay in progress. }
    If FBuildWorkPlanPath <> '' Then
      Case AssistantRealBlock(TrackedBody, TrackedStatus = pssBlocked, ContinuationCapReached) Of
        arbModel:
          Begin
            ApplyRealBlock(TrackedTitle, AssistantModelBlockAction(TrackedTitle));
            Exit;
          End;
        arbManual:
          Begin
            ApplyRealBlock(TrackedTitle, AssistantManualBlockAction(TrackedTitle));
            Exit;
          End;
        arbUnchecked:
          Begin
            ApplyRealBlock(TrackedTitle, AssistantUncheckedBlockAction(TrackedTitle));
            Exit;
          End;
      Else
      End;
    { A failed build stays in progress. Dirty source on a blocked item stops the run. }
    If Not CheckAssistantAcceptance(TrackedBody, FCompletionBuildJSON, FCompletionTestJSON, Note) Then
      Begin
        LeaveInProgress(Note);
        Exit;
      End;
    If WorkingRootHasGitRepository(ProjectAssistantRoot) Then
      Begin
        Note := Note + ' This working root is a Git repository, so the item stays in progress until a commit contains the completion.';
        LeaveInProgress(Note);
        Exit;
      End;
    If (FBuildWorkPlanPath = '') Or Not Assigned(FIDEWorkspace) Or
      (FIDEWorkspace.Identity <> FBuildWorkIdentity) Or
      Not ResolvePlanPath(GetActivePlanRelativePath, PlanRel, Err) Or (PlanRel <> FBuildWorkPlanPath) Or
      Not ReadBuildInput(PlanRel, CurrentPlan, Err) Or (CurrentPlan <> FBuildWorkPlanText) Then
      Begin
        SetBuildStatusFeedback('Project or plan changed during work; review before using Done.');
        Exit;
      End;
    If Not Assigned(SourceEditorManagerIntf) Then Exit;
    Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(PlanRel);
    If Assigned(Editor) And (Editor.Modified Or (Editor.SourceText <> CurrentPlan)) Then
      Begin
        SetBuildStatusFeedback('Plan has unsaved edits; review before using Done.');
        Exit;
      End;
    { The full saved plan still matches the selected section snapshot. }
    FBuildSelectedIndex := Idx;
    If Not SetPlanSectionStatus(PlanRel, Idx, pssComplete, Err) Then
      Begin
        SetBuildStatusFeedback('Auto-complete failed: ' + Err);
        WorkflowLogger.Warning('ProjectAssistant', 'Auto Status complete failed: ' + Err);
        Exit;
      End;
    RefreshBuildTodos;
    If Assigned(BuildTodoList) And (Idx >= 0) And (Idx < BuildTodoList.Items.Count) Then
      Begin
        BuildTodoList.ItemIndex := Idx;
        FBuildSelectedIndex := Idx;
      End;
    Note := Format('Auto-marked **%s** complete. %s', [FBuildWorkSectionTitle, Note]);
    SetBuildStatusFeedback(Format('%s → complete (auto)', [FBuildWorkSectionTitle]));
    If FViewingLive Then
      Begin
        If FDisplaySystemNote <> '' Then
          FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Note
        Else
          FDisplaySystemNote := Note;
      End
    Else
      SetCurrentSystemNote(Note);
    WorkflowLogger.Info('ProjectAssistant', 'Auto Status complete: ' + FBuildWorkSectionTitle);
    ClearBuildWorkTracking;
    End;
End;

Procedure Seam_BeginBuildWorkTracking(Form: TProjectAssistantForm; SectionIndex: Integer; Const SectionTitle: String);
Var Note: String;
Begin
  With Form Do
    Begin
    ClearBuildWorkTracking;
    FBuildWorkSectionIndex := SectionIndex; FBuildWorkSectionTitle := SectionTitle;
    If Not Assigned(FIDEWorkspace) Then FIDEWorkspace := TAssistantIDEWorkspace.Create;
    FBuildWorkIdentity := FIDEWorkspace.Identity;
    If Not ResolvePlanPath(GetActivePlanRelativePath, FBuildWorkPlanPath, Note) Or
      Not ReadBuildInput(FBuildWorkPlanPath, FBuildWorkPlanText, Note) Or
      Not GetPlanSectionBody(FBuildWorkPlanPath, SectionIndex, FBuildWorkBody, Note) Then
      FBuildWorkPlanPath := '';
    End;
End;

Procedure Seam_ClearBuildWorkTracking(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    FBuildWorkSectionIndex := -1;
    FBuildWorkSectionTitle := '';
    FBuildWorkPlanPath := ''; FBuildWorkPlanText := ''; FBuildWorkBody := ''; FBuildWorkIdentity := '';
    FCompletionBuildJSON := ''; FCompletionTestJSON := '';
    End;
End;

Procedure Seam_SetBuildStatusFeedback(Form: TProjectAssistantForm; Const MessageText: String);
Var
  Last: TTraceBlock;
Begin
  With Form Do
    Begin
    { The right-hand label is the progress slot. Build notes belong on the live trace. }
    If (MessageText = '') Or (csDestroying In ComponentState) Then
      Exit;
    If Assigned(FTrace) Then
      Begin
        Last := Nil;
        If FTrace.Count > 0 Then
          Last := FTrace[FTrace.Count - 1];
        If (Not Assigned(Last)) Or (Last.Kind <> tbkNote) Or (Last.Body <> MessageText) Then
          Begin
            FTrace.AddNote(MessageText);
            If FViewingLive And Assigned(FTraceView) Then
              FTraceView.Sync(FTrace, True);
            AssistantSessionObserve.TouchAssistantMirror;
          End;
      End
    Else
      SetCurrentSystemNote(MessageText);
    WorkflowLogger.Info('ProjectAssistant', 'Build work: ' + MessageText);
    End;
End;

Function Seam_BuildSelectionMessage(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    If SelectedBuildRowIsContext Then
      Result := 'Select an actionable item (### with Status), not a section heading.'
    Else
      Result := 'Select an actionable item in the list.';
    End;
End;

Function Seam_SelectedBuildRowIsContext(Form: TProjectAssistantForm): Boolean;
Var
  Idx: Integer;
Begin
  With Form Do
    Begin
    Result := False;
    If Not Assigned(BuildSections) Or (BuildSections.Count = 0) Then
      Exit;
    Idx := -1;
    If (FBuildSelectedIndex >= 0) And (FBuildSelectedIndex < BuildSections.Count) Then
      Idx := FBuildSelectedIndex
    Else If Assigned(BuildTodoList) And (BuildTodoList.ItemIndex >= 0) And
      (BuildTodoList.ItemIndex < BuildSections.Count) Then
      Idx := BuildTodoList.ItemIndex;
    Result := (Idx >= 0) And (Not TPlanSection(BuildSections[Idx]).Actionable);
    End;
End;

Function Seam_SelectedBuildSectionIndex(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    Result := -1;
    If Not Assigned(BuildSections) Or (BuildSections.Count = 0) Then
      Exit;
    { Prefer the remembered index: button clicks often clear ListBox.ItemIndex on GTK. }
    If (FBuildSelectedIndex >= 0) And (FBuildSelectedIndex < BuildSections.Count) Then
      Result := FBuildSelectedIndex
    Else If Assigned(BuildTodoList) And (BuildTodoList.ItemIndex >= 0) And
      (BuildTodoList.ItemIndex < BuildSections.Count) Then
      Result := BuildTodoList.ItemIndex;
    If (Result >= 0) And (Not TPlanSection(BuildSections[Result]).Actionable) Then
      Result := -1;
    End;
End;

Procedure Seam_PlanFileTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Var
  PlanRel: String;
  Age: LongInt;
  Bytes: Int64;
  Revision: String;
Begin
  With Form Do
    Begin
    If (csDestroying In ComponentState) Or (Not (Sender Is TTimer)) Then
      Exit;
    PlanRel := GetActivePlanRelativePath;
    If Not AssistantPlanFileStamp(PlanRel, Age, Bytes) Then
      Begin
        If (FPlanDiskAge <> -1) Or (FPlanDocumentRevision <> '') Then
          RefreshBuildTodos;
        Exit;
      End;
    If (Age = FPlanDiskAge) And (Bytes = FPlanDiskBytes) Then
      Begin
        FPlanDiskPendingAge := Age;
        FPlanDiskPendingBytes := Bytes;
        { A large file is hashed off this thread. The timer only notices the cache. }
        If Bytes > AssistantPlanInlineHashBytes Then
          Begin
            Revision := AssistantPlanCachedRevision(PlanRel, Age, Bytes);
            If (Revision <> '') And (Revision <> FPlanDocumentRevision) Then
              RefreshBuildTodos;
            Exit;
          End;
        { Same-second saves can keep the timestamp. Hash once a second while a plan is open. }
        If (FPlanHashTick <> 0) And (GetTickCount64 - FPlanHashTick < 1000) Then
          Exit;
        FPlanHashTick := GetTickCount64;
        Revision := AssistantPlanFileRevision(PlanRel);
        If Revision = FPlanDocumentRevision Then
          Exit;
        RefreshBuildTodos;
        Exit;
      End;
    { One quiet tick, so a save that touches the file twice is scanned once. }
    If (Age <> FPlanDiskPendingAge) Or (Bytes <> FPlanDiskPendingBytes) Then
      Begin
        FPlanDiskPendingAge := Age;
        FPlanDiskPendingBytes := Bytes;
        Exit;
      End;
    RefreshBuildTodos;
    End;
End;

Procedure Seam_EnsurePlanFileTimer(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Assigned(FPlanFileTimer) Or (csDestroying In ComponentState) Then
      Exit;
    { Nil owner: a streamed form must not gain a designer timer from Create(Form). }
    FPlanFileTimer := TTimer.Create(Nil);
    FPlanFileTimer.Enabled := False;
    FPlanFileTimer.Interval := 250;
    FPlanFileTimer.OnTimer := @PlanFileTimerTimer;
    FPlanFileTimer.Enabled := True;
    End;
End;

Function Seam_PlanDocumentRevision(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    Result := FPlanDocumentRevision;
    End;
End;

Procedure Seam_NoteMonitorPlanRevision(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    NotePlanDiskAge;
    End;
End;

Procedure Seam_NotePlanDiskAge(Form: TProjectAssistantForm);
Var
  PlanRel: String;
  Age: LongInt;
  Bytes: Int64;
Begin
  With Form Do
    Begin
    PlanRel := GetActivePlanRelativePath;
    If Not AssistantPlanFileStamp(PlanRel, Age, Bytes) Then
      Begin
        Age := -1;
        Bytes := -1;
      End;
    FPlanDiskAge := Age;
    FPlanDiskPendingAge := Age;
    FPlanDiskBytes := Bytes;
    FPlanDiskPendingBytes := Bytes;
    If Bytes > AssistantPlanInlineHashBytes Then
      FPlanDocumentRevision := AssistantPlanCachedRevision(PlanRel, Age, Bytes)
    Else
      FPlanDocumentRevision := AssistantPlanFileRevision(PlanRel);
    FPlanHashTick := GetTickCount64;
    End;
End;

Procedure Seam_RefreshBuildTodos(Form: TProjectAssistantForm);
Var
  PlanRel, Err: String;
  I, KeepHeading, SelectIndex, NotStarted, InProgress, Blocked, Complete: Integer;
  Section: TPlanSection;

  Procedure ShowPlanCounts;
  Begin
    With Form Do
    Begin
    If Not Assigned(BuildStatusLabel) Then
      Exit;
    BuildStatusLabel.Caption := AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete);
    End;
  End;

Begin
  With Form Do
    Begin
    If Assigned(BuildStatusLabel) Then
      BuildStatusLabel.Caption := '';
    If Not Assigned(BuildTodoList) Then
      Begin
        NotePlanDiskAge;
        AssistantSessionObserve.AssistantSessionObserve(asnPlan);
        AssistantSessionObserve.TouchAssistantMirror;
        Exit;
      End;
    PlanRel := GetActivePlanRelativePath;
    KeepHeading := -1;
    If Assigned(BuildSections) And (FBuildSelectedIndex >= 0) And
      (FBuildSelectedIndex < BuildSections.Count) Then
      KeepHeading := TPlanSection(BuildSections[FBuildSelectedIndex]).HeadingLineIndex
    Else If Assigned(BuildTodoList) And Assigned(BuildSections) And
      (BuildTodoList.ItemIndex >= 0) And (BuildTodoList.ItemIndex < BuildSections.Count) Then
      KeepHeading := TPlanSection(BuildSections[BuildTodoList.ItemIndex]).HeadingLineIndex;
    BuildTodoList.Items.BeginUpdate;
    Try
      BuildTodoList.Items.Clear;
      If Assigned(BuildSections) Then
        BuildSections.Clear;
      If PlanRel = '' Then
        Begin
          FBuildSelectedIndex := -1;
          Exit;
        End;
      If Not ScanPlanSections(PlanRel, BuildSections, Err) Then
        Begin
          BuildTodoList.Items.Add('(' + Err + ')');
          FBuildSelectedIndex := -1;
          Exit;
        End;
      If BuildSections.Count = 0 Then
        Begin
          BuildTodoList.Items.Add(
            '(No plan sections. Add ## context headings, and ### items whose next non-empty line is ' +
            'Status: not started | in progress | complete | blocked.)');
          FBuildSelectedIndex := -1;
          NotStarted := 0;
          InProgress := 0;
          Blocked := 0;
          Complete := 0;
          ShowPlanCounts;
          Exit;
        End;
      NotStarted := 0;
      InProgress := 0;
      Blocked := 0;
      Complete := 0;
      For I := 0 To BuildSections.Count - 1 Do
        Begin
          Section := TPlanSection(BuildSections[I]);
          BuildTodoList.Items.Add(FormatPlanSectionTile(Section));
          If Not Section.Actionable Then
            Continue;
          Case Section.Status Of
            pssNotStarted: Inc(NotStarted);
            pssInProgress: Inc(InProgress);
            pssBlocked: Inc(Blocked);
            pssComplete: Inc(Complete);
          Else
            { }
          End;
        End;
      ShowPlanCounts;
      SelectIndex := -1;
      If KeepHeading >= 0 Then
        For I := 0 To BuildSections.Count - 1 Do
          If TPlanSection(BuildSections[I]).HeadingLineIndex = KeepHeading Then
            Begin
              SelectIndex := I;
              Break;
            End;
      If SelectIndex < 0 Then
        Begin
          For I := 0 To BuildSections.Count - 1 Do
            If TPlanSection(BuildSections[I]).Actionable And
              (TPlanSection(BuildSections[I]).Status = pssInProgress) Then
              Begin
                SelectIndex := I;
                Break;
              End;
          If SelectIndex < 0 Then
            For I := 0 To BuildSections.Count - 1 Do
              If TPlanSection(BuildSections[I]).Actionable And
                (TPlanSection(BuildSections[I]).Status = pssNotStarted) Then
                Begin
                  SelectIndex := I;
                  Break;
                End;
        End;
      If SelectIndex >= 0 Then
        BuildTodoList.ItemIndex := SelectIndex
      Else If BuildTodoList.Items.Count > 0 Then
        BuildTodoList.ItemIndex := 0;
      FBuildSelectedIndex := BuildTodoList.ItemIndex;
    Finally
      BuildTodoList.Items.EndUpdate;
      NotePlanDiskAge;
      If Assigned(BuildTodoList) Then
        BuildTodoList.Invalidate;
      AssistantSessionObserve.AssistantSessionObserve(asnPlan);
      AssistantSessionObserve.TouchAssistantMirror;
    End;
    End;
End;

Procedure Seam_NewPlan(Form: TProjectAssistantForm);
Var
  Title, Rel, Resolved, Err, Content: String;
Begin
  With Form Do
    Begin
    SelectMode(amPlan);
    Title := 'Project Plan';
    If Not RunAssistantModal('New plan', 'Plan title:', Title) Then
      Exit;
    If Trim(Title) = '' Then
      Title := 'Project Plan';
    Rel := DefaultPlanRelativePath;
    If FileExistsUTF8(ExpandFileName(ProjectRootPath + Rel)) Or
      FileExistsUTF8(ExpandFileName(ProjectRootPath + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]))) Then
      Rel := AssistantDocumentsDirName + PathDelim +
        'Plan-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.md';
    Content := DefaultNewPlanMarkdown(Title);
    If Not WriteMarkdownFile(Rel, Content, Resolved, Err) Then
      Begin
        RunAssistantModal(Err, mtError, [mbOK], 0);
        Exit;
      End;
    SetActivePlanRelativePath(ProjectRelativePath(Resolved));
    PersistShellConfig;
    If Not AddAvailableAssistantPlan(Resolved, Err) Then
      RunAssistantModal(Err, mtWarning, [mbOK], 0);
    RefreshActivePlanChoices(Nil);
    RefreshBuildTodos;
    UpdateWorkActions;
    SetCurrentSystemNote('Created plan **' + GetActivePlanRelativePath +
      '**. Stay in **Plan** mode and send a message to refine it with the model.');
    End;
End;

Procedure Seam_ActivePlanBrowseClick(Form: TProjectAssistantForm; Sender: TObject);
Var
  Dialog: TOpenDialog;
  InitialDir, Resolved, Title, Err, Rel, Rejected, ChosenPath: String;
  I: Integer;
  Added: Boolean;
Begin
  With Form Do
    Begin
    If FSending Or FReviewInProgress Then
      Exit;
    Dialog := TOpenDialog.Create(Nil);
    Try
      Dialog.Title := 'Add plans';
      Dialog.Filter := 'Markdown (*.md)|*.md';
      Dialog.Options := Dialog.Options + [ofFileMustExist, ofAllowMultiSelect];
      InitialDir := ExcludeTrailingPathDelimiter(ProjectDocumentsDir);
      If (InitialDir = '') Or (Not DirectoryExistsUTF8(InitialDir)) Then
        InitialDir := ExcludeTrailingPathDelimiter(ProjectRootPath);
      Dialog.InitialDir := InitialDir;
      If Not Dialog.Execute Then
        Exit;
      Added := False;
      Rejected := '';
      Rel := '';
      For I := 0 To Dialog.Files.Count - 1 Do
        Begin
          ChosenPath := Dialog.Files[I];
          If Not ResolvePlanPath(ChosenPath, Resolved, Err) Then
            Begin
              Rejected := Rejected + ChosenPath + ': ' + Err + LineEnding;
              Continue;
            End;
          If Not TryReadAssistantPlanIdentity(Resolved, Title, Err) Then
            Begin
              Rejected := Rejected + ExtractFileName(Resolved) + ': ' + Err + LineEnding;
              Continue;
            End;
          If Not AddAvailableAssistantPlan(Resolved, Err) Then
            Begin
              Rejected := Rejected + ExtractFileName(Resolved) + ': ' + Err + LineEnding;
              Continue;
            End;
          Rel := ProjectRelativePath(Resolved);
          Added := True;
        End;
      If Added Then
        Begin
          SetActivePlanRelativePath(Rel);
          PersistShellConfig;
          RefreshActivePlanChoices(Nil);
          RefreshBuildTodos;
          UpdateWorkActions;
        End;
      If Rejected <> '' Then
        RunAssistantModal('Some files were not added:' + LineEnding + Rejected, mtError, [mbOK], 0);
    Finally
      Dialog.Free;
    End;
    If Sender <> ActivePlanBrowseButton Then
      Exit;
    End;
End;

Procedure Seam_ActivePlanChoiceChanged(Form: TProjectAssistantForm; Sender: TObject);
Var
  Rel: String;
Begin
  With Form Do
    Begin
    If FRefreshingPlans Then
      Exit;
    If FSending Or FReviewInProgress Then
      Begin
        RefreshActivePlanChoices(Nil);
        Exit;
      End;
    If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
      Exit;
    If (ActivePlanCombo.ItemIndex < 0) Or (ActivePlanCombo.ItemIndex >= ActivePlanPaths.Count) Then
      Exit;
    Rel := ActivePlanPaths[ActivePlanCombo.ItemIndex];
    If SameText(Rel, GetActivePlanRelativePath) Then
      Exit;
    SetActivePlanRelativePath(Rel);
    PersistShellConfig;
    RefreshBuildTodos;
    UpdateWorkActions;
    If Sender <> ActivePlanCombo Then
      Exit;
    End;
End;

Procedure Seam_RefreshActivePlanChoices(Form: TProjectAssistantForm; Sender: TObject);
Var
  Paths, Titles: TStringList;
  Err, ActivePlan, CaptionText: String;
  I, Selected: Integer;
  ActiveMissing: Boolean;
Begin
  With Form Do
    Begin
    If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
      Exit;
    { OnDropDown passes the combo. Other callers pass Nil. Both refill from the settings. }
    If (Sender <> Nil) And (Sender <> ActivePlanCombo) Then
      Exit;
    FRefreshingPlans := True;
    ActivePlanCombo.Items.BeginUpdate;
    Try
      ActivePlanCombo.Items.Clear;
      ActivePlanPaths.Clear;
      ActivePlan := GetActivePlanRelativePath;
      Selected := -1;
      Paths := Nil;
      Titles := Nil;
      ActiveMissing := False;
      If ListAvailableAssistantPlans(ActivePlan, Paths, Titles, ActiveMissing, Err) Then
        Begin
          If ActiveMissing Then
            Begin
              SetActivePlanRelativePath('');
              PersistShellConfig;
              ActivePlan := '';
              WorkflowLogger.Info('ProjectAssistant', 'Removed missing active plan from the available list.');
            End;
          For I := 0 To Paths.Count - 1 Do
            Begin
              If I < Titles.Count Then
                CaptionText := Titles[I]
              Else
                CaptionText := PlanComboCaption('', Paths[I]);
              ActivePlanCombo.Items.Add(CaptionText);
              ActivePlanPaths.Add(Paths[I]);
              If SameText(Paths[I], ActivePlan) Then
                Selected := I;
            End;
        End
      Else If Err <> '' Then
        WorkflowLogger.Warning('ProjectAssistant', 'Available plan list: ' + Err);
      ActivePlanCombo.ItemIndex := Selected;
      ActivePlanCombo.ParentShowHint := False;
      ActivePlanCombo.ShowHint := Selected >= 0;
      If Selected >= 0 Then
        ActivePlanCombo.Hint := ActivePlanPaths[Selected]
      Else
        ActivePlanCombo.Hint := '';
    Finally
      ActivePlanCombo.Items.EndUpdate;
      FRefreshingPlans := False;
      Paths.Free;
      Titles.Free;
    End;
    If ActiveMissing Then
      RefreshBuildTodos;
    UpdateWorkActions;
    AssistantSessionObserve.AssistantSessionObserve(asnPlan);
    End;
End;

End.
