Unit AssistantAccountStatus;

{ Account usage refresh for the project assistant (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, ProjectAssistantForm;

Procedure Seam_ReleaseAccountUsageRefresh(Form: TProjectAssistantForm);
Procedure Seam_AccountUsageTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_StartAccountUsageWorker(Form: TProjectAssistantForm);
Procedure Seam_NoteAccountConnectionChanged(Form: TProjectAssistantForm);
Procedure Seam_SyncCodexUsageIdle(Form: TProjectAssistantForm);
Procedure Seam_ApplyAccountUsageLabel(Form: TProjectAssistantForm);
Procedure Seam_RefreshCentreStatus(Form: TProjectAssistantForm);

Implementation

Uses
  SysUtils, DateUtils, ExtCtrls, WorkflowLog, AssistantAccountUsage, AssistantAccountWorker,
  AssistantCodexUsage, AssistantSessionObserve;

Procedure Seam_ReleaseAccountUsageRefresh(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Assigned(FAccountUsageTimer) Then
      Begin
        FAccountUsageTimer.Enabled := False;
        FAccountUsageTimer.OnTimer := Nil;
        FreeAndNil(FAccountUsageTimer);
      End;
    CancelCodexAccountUsage;
    If Assigned(FAccountUsageSlot) Then
      FAccountUsageSlot.Close;
    If Assigned(FAccountUsageWorker) Then
      Begin
        TAccountUsageWorker(FAccountUsageWorker).Detach;
        FAccountUsageWorker := Nil;
      End;
    If Assigned(FAccountUsageSlot) Then
      Begin
        FAccountUsageSlot.Release;
        FAccountUsageSlot := Nil;
      End;
    End;
End;

Procedure Seam_AccountUsageTimerTimer(Form: TProjectAssistantForm; Sender: TObject);
Var
  Due: Boolean;
Begin
  With Form Do
    Begin
    Try
      If csDestroying In ComponentState Then
        Exit;
      ApplyAccountUsageLabel;
      SyncCodexUsageIdle;
      If Not Assigned(FAccountUsageSlot) Or FAccountUsageSlot.IsClosed Then
        Exit;
      If Assigned(FAccountUsageWorker) And (Not FAccountUsageWorker.Finished) Then
        Exit;
      If (FActiveConnectionId = '') Or (Not AccountUsageRegistered(FActiveBackend)) Then
        Exit;
      If (FActiveBackend = 'codex') And ((FSending) Or FPlanAgentRunning Or FReviewInProgress) Then
        Exit;
      Due := FAccountUsageWanted;
      If Not Due Then
        Due := Showing And ((FAccountUsageAttemptId <> FActiveConnectionId) Or
          ((Now - FAccountUsageAttemptAt) >= EncodeTime(0, 3, 0, 0)));
      If Not Due Then
        Exit;
      StartAccountUsageWorker;
    Except
      On E: Exception Do
        WorkflowLogger.Warning('ProjectAssistant', 'Account usage refresh failed.');
    End;
    End;
End;

Procedure Seam_StartAccountUsageWorker(Form: TProjectAssistantForm);
Var
  Worker: TAccountUsageWorker;
Begin
  With Form Do
    Begin
    If (Not Assigned(FAccountUsageSlot)) Or FAccountUsageSlot.IsClosed Then
      Exit;
    If Assigned(FAccountUsageWorker) And (Not FAccountUsageWorker.Finished) Then
      Exit;
    If Assigned(FAccountUsageWorker) Then
      Begin
        FAccountUsageWorker.WaitFor;
        FreeAndNil(FAccountUsageWorker);
      End;
    If (FActiveConnectionId = '') Or (Not AccountUsageRegistered(FActiveBackend)) Then
      Exit;
    SyncCodexUsageIdle;
    If (FActiveBackend = 'codex') And ((FSending) Or FPlanAgentRunning Or FReviewInProgress) Then
      Exit;
    Worker := TAccountUsageWorker.CreateForProject(FAccountUsageSlot, FActiveConnectionId, FActiveBackend, FActiveModel, FAccountApiBase,
      FAccountKeySource, FAccountKeyEnv, FAccountKeyValue, FAccountPreset, FAccountWire, FCodexRuntime, FCodexProfile);
    FAccountUsageWorker := Worker;
    FAccountUsageWanted := False;
    FAccountUsageAttemptId := FActiveConnectionId;
    FAccountUsageAttemptAt := Now;
    Worker.Start;
    End;
End;

Procedure Seam_NoteAccountConnectionChanged(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    CancelCodexAccountUsage;
    SyncCodexUsageIdle;
    If Assigned(FAccountUsageSlot) Then
      FAccountUsageSlot.SetActive(FActiveConnectionId);
    FAccountUsageAttemptId := '';
    FAccountUsageAttemptAt := 0;
    FAccountUsageWanted := AccountUsageRegistered(FActiveBackend);
    ApplyAccountUsageLabel;
    End;
End;

Procedure Seam_SyncCodexUsageIdle(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    SetCodexAccountUsageIdle((FActiveBackend = 'codex') And (Not FSending) And (Not FPlanAgentRunning) And (Not FReviewInProgress));
    End;
End;

Procedure Seam_ApplyAccountUsageLabel(Form: TProjectAssistantForm);
Var
  SlotItem, Item: TAccountUsageSnapshot;
  PreviousCaption, PreviousHint: String;
Begin
  With Form Do
    Begin
    If Not Assigned(StatusFooter) Then
      Exit;
    ClearAccountUsageSnapshot(SlotItem);
    If Assigned(FAccountUsageSlot) Then
      SlotItem := FAccountUsageSlot.ReadSnapshot;
    Item := AccountUsageForFooter(FActiveConnectionId, SlotItem);
    If AccountUsageApplies(Item, FActiveConnectionId) Then
      PublishAccountUsageSnapshot(Item);
    PreviousCaption := FPlanStatusCaption;
    PreviousHint := FPlanStatusHint;
    FPlanStatusCaption := AccountUsageCaption(Item, FActiveConnectionId);
    FPlanStatusHint := AccountUsageHint(Item, FActiveConnectionId);
    RefreshCentreStatus;
    { The phone credit popup reads these strings from the next status frame. }
    If (FPlanStatusCaption <> PreviousCaption) Or (FPlanStatusHint <> PreviousHint) Then
      AssistantSessionObserve.AssistantSessionObserve(asnStatus);
    End;
End;

Procedure Seam_RefreshCentreStatus(Form: TProjectAssistantForm);
Var
  UsageHint: String;
Begin
  With Form Do
    Begin
    If Not Assigned(StatusFooter) Then
      Exit;
    StatusFooter.SetCentreText(FContextStatusText);
    StatusFooter.SetCentreHint(FContextStatusHint);
    If FPlanStatusCaption <> '' Then
      StatusFooter.SetUsageText(FPlanStatusCaption)
    Else
      StatusFooter.SetUsageText('Credits');
    UsageHint := 'Click for plan usage';
    If FPlanStatusHint <> '' Then
      UsageHint := UsageHint + LineEnding + FPlanStatusHint;
    StatusFooter.SetUsageHint(UsageHint);
    End;
End;

End.
