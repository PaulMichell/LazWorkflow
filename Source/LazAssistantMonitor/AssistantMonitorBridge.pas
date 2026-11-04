Unit AssistantMonitorBridge;

{ Main-thread command pump and session listener. The listener only enqueues.
  A command wait must not sit in the listen thread. The idle sweep answers
  host_busy if the IDE has not claimed the command. Resume is not a user
  command: it stays queued until the IDE thread can fill the catchup.
  It does not build provider JSON and does not replace the form trace handler.

  Size note: exceeds the 1000 line preference. What remains is the change-triggered
  observation and the IDE command pump. Dirty-block patch construction is gone.
  Reviewed 2026-11-03: the 1 s timer is a backstop. A counter wake queues one pump,
  coalesced to 20 ms. The change pump publishes plan rows and does not read the plan file.
  The live pump uses FillMonitorLiveChanges and does not copy an unchanged block body.
  No provider or socket code in this unit.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorSession, AssistantMonitorSettings;

Const
  MonitorLiveTurnIndex = -2;
  MonitorSnapshotTurnCap = 30;

Procedure AttachAssistantMonitorBridge(Session: TMonitorSession);
Procedure DetachAssistantMonitorBridge;
/// Stores aadAllow or aadDeny and signals. Does not run the tool. A second answer returns false.
Function DecideAssistantMonitorApproval(Const ToolId: String; Allow: Boolean): Boolean;
/// Main thread. Registers the session listener and the remote approval waiter.
Procedure RegisterAssistantMonitor;
/// Clears the listener and the waiter. Does not stop a listen thread.
Procedure UnregisterAssistantMonitor;
{ Main thread. Copies settings for a listener start. The listen thread keeps that copy. }
Function CaptureMonitorListenSnapshot(Out Settings: TMonitorSettings; Out ErrorText: String): Boolean;

Implementation

Uses
  Classes, SyncObjs, Forms, ExtCtrls, fpjson, WorkflowLog, AssistantSessionObserve, AssistantMonitorCodec,
  AssistantMonitorMirror, AssistantMonitorApproval, AssistantTools, AssistantConversation,
  ProjectAssistantForm;

Type
  TMonitorQueuedCommand = Class
    Kind: Integer;
    ClientId: String;
    Payload: String;
    Generation: Integer;
    Cancelled: Boolean;
    Claimed: Boolean;
    BusySent: Boolean;
    Finished: Boolean;
    Defer: Boolean;
    ExecuteQueued: Boolean;
    QueuedAt: QWord;
    RefCount: Integer;
    Procedure Execute;
    Procedure Release;
  End;

  TMonitorNoticeJob = Class
    Kind: TAssistantSessionNoticeKind;
    Approval: TAssistantApprovalNotice;
    HasApproval: Boolean;
    Procedure Execute;
  End;

  TAssistantMonitorBridge = Class
  Private
    FLock: TRTLCriticalSection;
    FOutstanding: TFPList;
    FSession: TMonitorSession;
    FStatusQueued: Boolean;
    FStatusDirty: Boolean;
    FMirrorTimer: TTimer;
    FCoalesceTimer: TTimer;
    FPumpPending: Boolean;
    FCoalesceUntil: QWord;
    FPumpedMirror: Int64;
    FPlanStamp: String;
    FSentEpoch: String;
    FSentFlagsValid: Boolean;
    FSentBusy: Boolean;
    FSentSending: Boolean;
    FSentPlanRunning: Boolean;
    FSentPhase: String;
    FSentCanSend: Boolean;
    FSentCanSteer: Boolean;
    FSentCanStop: Boolean;
    FSentModel: String;
    FSentStatusText: String;
    FPumping: Boolean;
    { Epoch and conversation already copied to the connected phone. Cleared when it drops. }
    FDeliveredScreen: String;
    Procedure LockBridge;
    Procedure UnlockBridge;
    { Caller holds FLock. True when this command was still listed. }
    Function ForgetCommand(Command: TMonitorQueuedCommand): Boolean;
    Procedure SweepCommands;
    Procedure DropOutstanding;
    Procedure Hear(Kind: TAssistantSessionNoticeKind);
    Procedure HandleCommand(Kind: Integer; Const Id, PayloadJson: String);
    Procedure HandleApprovalClosed(Const ToolId, Reason: String);
    Procedure DeliverNotice(Job: TMonitorNoticeJob);
    Procedure SendJson(Const Json: String);
    Procedure SendError(Const RefId, Reason, MessageText: String);
    Function HostId: String;
    Function OpenForm: TProjectAssistantForm;
    { True while the window is still opening. A resume waits instead of saying it is missing. }
    Function ResumeFormPending(Command: TMonitorQueuedCommand): Boolean;
    Procedure ApplyHostFlags(Const View: TAssistantMonitorView);
    Procedure PushSnapshot(Form: TProjectAssistantForm; Const RefId: String);
    Procedure PublishSamplingLists(Form: TProjectAssistantForm);
    Procedure FillSnapshot(Form: TProjectAssistantForm; Out Snapshot: TMonitorSnapshot);

    Procedure RetryDeferredResumes;
    Procedure PublishStateKeys(Form: TProjectAssistantForm);
    Procedure PushStatus(Form: TProjectAssistantForm);
    Procedure PushLiveState;
    Procedure NoteOpenLogPosition;
    Procedure PublishEpoch;
    Procedure PushPlan(Form: TProjectAssistantForm);
    Procedure PushMenuLists(Form: TProjectAssistantForm);
    Procedure PushTargets(Form: TProjectAssistantForm);
    Procedure PushConversations(Form: TProjectAssistantForm);
    Procedure PushModels(Form: TProjectAssistantForm);
    Procedure PushReasoning(Form: TProjectAssistantForm);
    Procedure PushPermissions(Form: TProjectAssistantForm);
    Procedure MirrorTimerTimer(Sender: TObject);
    Procedure NoteMirrorWake;
    Procedure SchedulePump(Data: PtrInt);
    Procedure QueuedPump(Data: PtrInt);
    Procedure CoalesceTimerTimer(Sender: TObject);
    Procedure DeliverOpenScreen;
    Procedure PumpMirror(Seen: Int64);
    Procedure PublishPlanRows(Form: TProjectAssistantForm);
    Procedure FinishStatusPush;
    Procedure RunCommand(Command: TMonitorQueuedCommand);
    Function DispatchCommand(Form: TProjectAssistantForm; Kind: Integer; Const Id, PayloadJson: String;
      Out ErrorText, DoneText: String): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Attach(Session: TMonitorSession);
    Procedure Detach;
  End;

Var
  Bridge: TAssistantMonitorBridge;

Function SnapshotHasOpenTurn(Const Snapshot: TMonitorSnapshot): Boolean; Forward;

Procedure TMonitorQueuedCommand.Release;
Begin
  If InterlockedDecrement(RefCount) = 0 Then
    Free;
End;

Procedure TMonitorQueuedCommand.Execute;
Var
  Listed: Boolean;
Begin
  Defer := False;
  Try
    Try
      If Assigned(Bridge) Then
        Bridge.RunCommand(Self);
    Except
      On E: Exception Do
        ReportPluginException('AssistantMonitorBridge.Command', E);
    End;
  Finally
    If Defer Then
      Begin
        If Assigned(Bridge) Then
          Begin
            Bridge.LockBridge;
            Try
              ExecuteQueued := False;
            Finally
              Bridge.UnlockBridge;
            End;
          End;
        Release;
      End
    Else
      Begin
        Listed := False;
        If Assigned(Bridge) Then
          Begin
            Bridge.LockBridge;
            Try
              Finished := True;
              Listed := Bridge.ForgetCommand(Self);
            Finally
              Bridge.UnlockBridge;
            End;
          End;
        If Listed Then
          Release;
        Release;
      End;
  End;
End;

Procedure TMonitorNoticeJob.Execute;
Begin
  Try
    Try
      If Assigned(Bridge) Then
        Bridge.DeliverNotice(Self);
    Except
      On E: Exception Do
        ReportPluginException('AssistantMonitorBridge.Notice', E);
    End;
  Finally
    Free;
  End;
End;

Constructor TAssistantMonitorBridge.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FOutstanding := TFPList.Create;
  FSession := Nil;
  FPumpedMirror := 0;
  FPlanStamp := '';
  { Not owned by a form, so the designer cannot stream it. }
  FMirrorTimer := TTimer.Create(Nil);
  FMirrorTimer.Enabled := False;
  FMirrorTimer.Interval := 1000;
  FMirrorTimer.OnTimer := @MirrorTimerTimer;
  FCoalesceTimer := TTimer.Create(Nil);
  FCoalesceTimer.Enabled := False;
  FCoalesceTimer.Interval := 20;
  FCoalesceTimer.OnTimer := @CoalesceTimerTimer;
End;

Destructor TAssistantMonitorBridge.Destroy;
Begin
  Detach;
  FreeAndNil(FCoalesceTimer);
  FreeAndNil(FMirrorTimer);
  FreeAndNil(FOutstanding);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Function TAssistantMonitorBridge.ForgetCommand(Command: TMonitorQueuedCommand): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  If (Not Assigned(Command)) Or (Not Assigned(FOutstanding)) Then
    Exit;
  Index := FOutstanding.IndexOf(Command);
  If Index < 0 Then
    Exit;
  FOutstanding.Delete(Index);
  Result := True;
End;

Procedure TAssistantMonitorBridge.DropOutstanding;
Var
  Index: Integer;
  Command: TMonitorQueuedCommand;
Begin
  If Not Assigned(FOutstanding) Then
    Exit;
  LockBridge;
  Try
    For Index := 0 To FOutstanding.Count - 1 Do
      Begin
        Command := TMonitorQueuedCommand(FOutstanding[Index]);
        Command.Cancelled := True;
        Command.Release;
      End;
    FOutstanding.Clear;
  Finally
    UnlockBridge;
  End;
End;

Procedure TAssistantMonitorBridge.SweepCommands;
Begin
  { A slow IDE is not a refusal. The command stays outstanding and was already answered queued. }
  RetryDeferredResumes;
End;

Procedure TAssistantMonitorBridge.LockBridge;
Begin
  EnterCriticalSection(FLock);
End;

Procedure TAssistantMonitorBridge.UnlockBridge;
Begin
  LeaveCriticalSection(FLock);
End;

Procedure TAssistantMonitorBridge.Attach(Session: TMonitorSession);
Begin
  LockBridge;
  Try
    FSession := Session;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Begin
      Session.OnCommand := @HandleCommand;
      Session.SetIdleHandler(@SweepCommands);
      Session.SetApprovalCloseHandler(@HandleApprovalClosed);
    End;
  PublishEpoch;
  SetAssistantMirrorWake(@NoteMirrorWake);
  If Assigned(FMirrorTimer) Then
    FMirrorTimer.Enabled := Assigned(Session);
End;

Procedure TAssistantMonitorBridge.Detach;
Var
  Session: TMonitorSession;
Begin
  SetAssistantMirrorWake(Nil);
  FPumpPending := False;
  FCoalesceUntil := 0;
  If Assigned(FCoalesceTimer) Then
    FCoalesceTimer.Enabled := False;
  If Assigned(FMirrorTimer) Then
    FMirrorTimer.Enabled := False;
  LockBridge;
  Try
    Session := FSession;
    FSession := Nil;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Begin
      Session.OnCommand := Nil;
      Session.SetIdleHandler(Nil);
      Session.SetApprovalCloseHandler(Nil);
    End;
  DropOutstanding;
End;

Function TAssistantMonitorBridge.HostId: String;
Var
  Session: TMonitorSession;
Begin
  Result := 'bridge';
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Result := Session.AllocateHostId;
End;

Procedure TAssistantMonitorBridge.SendJson(Const Json: String);
Var
  Session: TMonitorSession;
Begin
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Session.SendHostJson(Json);
End;

Procedure TAssistantMonitorBridge.SendError(Const RefId, Reason, MessageText: String);
Var
  Session: TMonitorSession;
Begin
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Session.NoteCommandRejected(RefId, Reason);
  SendJson(EncodeMonitorError(HostId, Reason, MessageText, RefId));
End;

Function LongRunningCommand(Kind: Integer): Boolean;
Begin
  { send is done when the turn ends. run_plan and run_task are done when the plan flag drops.
    A steer finishes when the form accepts it. }
  Result := (Kind = Ord(mmkSend)) Or (Kind = Ord(mmkRunPlan)) Or (Kind = Ord(mmkWorkOnPlan)) Or
    (Kind = Ord(mmkRunTask));
End;

Function TAssistantMonitorBridge.OpenForm: TProjectAssistantForm;
Var
  I: Integer;
  Form: TCustomForm;

  Function Usable(Candidate: TCustomForm): Boolean;
  Begin
    Result := (Candidate Is TProjectAssistantForm) And (Not (csDestroying In Candidate.ComponentState));
  End;

Begin
  Result := OpenProjectAssistantForm;
  If Assigned(Result) Then
    Exit;
  For I := 0 To Screen.CustomFormCount - 1 Do
    Begin
      Form := Screen.CustomForms[I];
      If Usable(Form) Then
        Exit(TProjectAssistantForm(Form));
    End;
  For I := 0 To Screen.FormCount - 1 Do
    Begin
      Form := Screen.Forms[I];
      If Usable(Form) Then
        Exit(TProjectAssistantForm(Form));
    End;
End;

Function TAssistantMonitorBridge.ResumeFormPending(Command: TMonitorQueuedCommand): Boolean;
Var
  Form: TProjectAssistantForm;
  Age: QWord;
Begin
  Form := OpenForm;
  If Assigned(Form) And Form.MonitorScreenReady Then
    Exit(False);
  Age := GetTickCount64 - Command.QueuedAt;
  { The window is open and the conversation is still loading. An empty page here
    is what the phone saves as this chat with no turns. }
  If Assigned(Form) Then
    Exit(Age < 60000);
  { No window yet. Do not tell the phone it is missing for the first few seconds. }
  Result := Age < 8000;
End;

Procedure TAssistantMonitorBridge.ApplyHostFlags(Const View: TAssistantMonitorView);
Var
  Flags: TMonitorHostFlags;
  Session: TMonitorSession;
Begin
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Exit;
  Flags.Sending := View.Sending;
  Flags.PlanAgentRunning := View.PlanRunning;
  Flags.CanSend := View.CanSend;
  Flags.CanSteer := View.CanSteer;
  Flags.CanStop := View.CanStop;
  Flags.CanChangeMode := View.CanChangeMode;
  Flags.ModeLocked := View.ModeLocked;
  Session.SetHostFlags(Flags);
End;

Procedure TAssistantMonitorBridge.PublishSamplingLists(Form: TProjectAssistantForm);
Var
  PublishModels, PublishReasoning, PublishPermissions: Boolean;
Begin
  If Not Assigned(Form) Then
    Exit;
  If Not Form.TakeSamplingListPublish(PublishModels, PublishReasoning, PublishPermissions) Then
    Exit;
  If PublishModels Then
    PushModels(Form);
  If PublishReasoning Then
    PushReasoning(Form);
  If PublishPermissions Then
    PushPermissions(Form);
End;

Procedure TAssistantMonitorBridge.FinishStatusPush;
Var
  Again: Boolean;
  Job: TMonitorNoticeJob;
Begin
  LockBridge;
  Try
    Again := FStatusDirty;
    FStatusDirty := False;
    If Not Again Then
      FStatusQueued := False;
  Finally
    UnlockBridge;
  End;
  If Not Again Then
    Exit;
  Job := TMonitorNoticeJob.Create;
  Job.Kind := asnStatus;
  TThread.Queue(Nil, @Job.Execute);
End;

Procedure TAssistantMonitorBridge.NoteOpenLogPosition;
Var
  Session: TMonitorSession;
  Epoch: String;
  Cursor: Int64;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Exit;
  Epoch := Session.MirrorEpoch;
  If Epoch = '' Then
    Exit;
  Cursor := Session.MirrorCursor;
  ProjectAssistantConversation.NoteMonitorLogPosition(Epoch, Cursor);
End;

Function FormConversationMoved(Form: TProjectAssistantForm; Session: TMonitorSession): Boolean;
Var
  ConversationId, ProjectRoot, Title, Epoch, MirrorId, MirrorRoot, MirrorTitle: String;
  Cursor: Int64;
Begin
  Result := False;
  If (Not Assigned(Form)) Or (Not Assigned(Session)) Then
    Exit;
  Form.FillMonitorIdentity(ConversationId, ProjectRoot, Title);
  If (ConversationId = '') Or (ConversationId = 'current') Then
    Exit;
  Session.CopyMirrorIdentity(Epoch, MirrorId, MirrorRoot, MirrorTitle, Cursor);
  Result := MirrorId <> ConversationId;
End;

Procedure TAssistantMonitorBridge.PublishEpoch;
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  Closed: TMonitorConversationClosed;
  ConversationId, ProjectRoot, Title, Epoch, MirrorEpoch, MirrorId, MirrorRoot, MirrorTitle: String;
  SavedCursor, MirrorCursor: Int64;
  HadEpoch: Boolean;
Begin
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  Form := OpenForm;
  ConversationId := '';
  ProjectRoot := '';
  Title := '';
  If Assigned(Form) Then
    Form.FillMonitorIdentity(ConversationId, ProjectRoot, Title);
  { New already opened this conversation. A second publish must not close it. }
  If Assigned(Session) And (ConversationId <> '') And (ConversationId <> 'current') Then
    Begin
      Session.CopyMirrorIdentity(MirrorEpoch, MirrorId, MirrorRoot, MirrorTitle, MirrorCursor);
      If (MirrorId = ConversationId) And (MirrorEpoch <> '') Then
        Exit;
    End;
  HadEpoch := False;
  If Assigned(Session) Then
    Begin
      { Commit the live patch before the closed cursor is copied. }
      Session.FlushLivePatch;
      HadEpoch := Session.CopyClosedMirror(Closed);
      { The previous dump must not fill the phone, or sit in front of this empty chat. }
      Session.DiscardUnsentBulk;
    End;
  If HadEpoch Then
    Begin
      SendJson(EncodeMonitorConversationClosed(HostId, Closed.Epoch, Closed.Cursor, Closed.ConversationId, Closed.Title));
      If Assigned(ProjectAssistantConversation) Then
        ProjectAssistantConversation.SaveClosedLogPosition(Closed.ConversationId, Closed.Epoch, Closed.Cursor);
    End;
  Epoch := '';
  SavedCursor := 0;
  If Assigned(ProjectAssistantConversation) Then
    ProjectAssistantConversation.ReadMonitorLogPosition(Epoch, SavedCursor);
  If Not Assigned(Session) Then
    Exit;
  If (Epoch <> '') And (ConversationId <> '') And (ConversationId <> 'current') Then
    Session.RestoreMirror(Epoch, ConversationId, ProjectRoot, Title, SavedCursor)
  Else
    Begin
      Epoch := MintMonitorEpoch;
      If Epoch = '' Then
        Exit;
      Session.BeginMirrorEpoch(Epoch, ConversationId, ProjectRoot, Title);
    End;
  FSentEpoch := '';
  FPlanStamp := '';
  FSentFlagsValid := False;
End;

Function JsonBool(Condition: Boolean): String;
Begin
  If Condition Then
    Result := 'true'
  Else
    Result := 'false';
End;

Function ChoiceArray(Paths, Captions: TStrings): String;
Var
  Index: Integer;
  One: String;
Begin
  Result := '';
  If (Not Assigned(Paths)) Or (Not Assigned(Captions)) Then
    Exit;
  For Index := 0 To Paths.Count - 1 Do
    Begin
      If Index >= Captions.Count Then
        Break;
      One := '{"path":"' + Paths[Index] + '","caption":"' + Captions[Index] + '"}';
      If Result <> '' Then
        Result := Result + ',';
      Result := Result + One;
    End;
End;

Procedure TAssistantMonitorBridge.PublishStateKeys(Form: TProjectAssistantForm);
Var
  Session: TMonitorSession;
  View: TAssistantMonitorView;
  Rows: TAssistantMonitorPlanRows;
  Tasks: TAssistantMonitorTaskRows;
  Paths, Captions, Ids, Titles: TStringList;
  Current, Backend, Note, PlanRows, TaskRows: String;
  Index: Integer;
  Truncated: Boolean;
Begin
  If Not Assigned(Form) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Exit;
  Form.FillMonitorView(View);
  View.RemoteApproval := MonitorRemoteApprovalEnabled;
  ApplyHostFlags(View);
  Session.PublishState('status', '{"busy":' + JsonBool(View.Sending Or View.PlanRunning) + ',"sending":' +
    JsonBool(View.Sending) + ',"plan_running":' + JsonBool(View.PlanRunning) + ',"phase":"' + View.Phase +
    '","status_text":"' + View.StatusText + '","started_at":"' + View.StartedAt + '","can_send":' +
    JsonBool(View.CanSend) + ',"can_steer":' + JsonBool(View.CanSteer) + ',"can_stop":' + JsonBool(View.CanStop) +
    ',"can_change_mode":' + JsonBool(View.CanChangeMode) + ',"error_text":"' + View.ErrorText + '"}');
  Session.PublishState('session', '{"model":"' + View.Model + '","backend":"' + View.Backend + '","signed_in":' +
    JsonBool(View.SignedIn) + ',"effort":"' + View.Effort + '","skill":"' + View.Skill + '","context_text":"' +
    View.ContextText + '","remote_approval":' + JsonBool(View.RemoteApproval) + ',"approval_caption":"' +
    View.ApprovalCaption + '"}');
  Session.PublishState('mode', '{"mode":"' + View.Mode + '","locked":' + JsonBool(View.ModeLocked) + '}');
  Session.PublishState('target', '{"kind":"' + View.TargetKind + '","display":"' + View.TargetDisplay + '","root":"' +
    View.TargetRoot + '"}');
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Ids := TStringList.Create;
  Titles := TStringList.Create;
  Try
    Form.FillMonitorTargetChoices(Paths, Captions, Current);
    Session.PublishState('targets', '{"current":"' + Current + '","choices":[' + ChoiceArray(Paths, Captions) + ']}');
    Paths.Clear;
    Captions.Clear;
    Form.FillMonitorConversationChoices(Ids, Titles, Current, Truncated);
    Session.PublishState('conversations', '{"current":"' + Current + '","truncated":' + JsonBool(Truncated) +
      ',"choices":[' + ChoiceArray(Ids, Titles) + ']}');
    Ids.Clear;
    Titles.Clear;
    Form.FillMonitorModelChoices(Ids, Captions, Current, Backend, Note);
    Session.PublishState('models', '{"current":"' + Current + '","backend":"' + Backend + '","note":"' + Note +
      '","choices":[' + ChoiceArray(Ids, Captions) + ']}');
    Ids.Clear;
    Captions.Clear;
    Form.FillMonitorReasoningChoices(Ids, Captions, Current, Note);
    Session.PublishState('reasoning', '{"current":"' + Current + '","note":"' + Note + '","choices":[' +
      ChoiceArray(Ids, Captions) + ']}');
    Ids.Clear;
    Captions.Clear;
    Form.FillMonitorPermissionsChoices(Ids, Captions, Current, Backend, Note);
    Session.PublishState('permissions', '{"current":"' + Current + '","backend":"' + Backend + '","note":"' + Note +
      '","choices":[' + ChoiceArray(Ids, Captions) + ']}');
    Paths.Clear;
    Captions.Clear;
    Form.FillMonitorPlanChoices(Paths, Captions);
    Session.PublishState('plan_choices', '{"choices":[' + ChoiceArray(Paths, Captions) + ']}');
    Form.FillMonitorPlan(Rows);
    PlanRows := '';
    For Index := 0 To High(Rows) Do
      Begin
        If PlanRows <> '' Then
          PlanRows := PlanRows + ',';
        PlanRows := PlanRows + '{"index":' + IntToStr(Rows[Index].Index) + ',"level":' + IntToStr(Rows[Index].Level) +
          ',"title":"' + Rows[Index].Title + '","parent_title":"' + Rows[Index].ParentTitle + '","status":"' +
          Rows[Index].Status + '","actionable":' + JsonBool(Rows[Index].Actionable) + '}';
      End;
    Session.PublishState('plan', '{"path":"' + View.PlanPath + '","title":"' + View.PlanTitle + '","running":' +
      JsonBool(View.PlanRunning) + ',"revision":"' + Form.PlanDocumentRevision + '","rows":[' + PlanRows + ']}');
    Session.NotePlanCachedRevision(View.PlanPath, Form.PlanDocumentRevision);
    Form.FillMonitorTasks(Tasks);
    TaskRows := '';
    For Index := 0 To High(Tasks) Do
      Begin
        If TaskRows <> '' Then
          TaskRows := TaskRows + ',';
        TaskRows := TaskRows + '{"id":"' + Tasks[Index].Id + '","title":"' + Tasks[Index].Title + '","summary":"' +
          Tasks[Index].Summary + '","mode":"' + Tasks[Index].Mode + '"}';
      End;
    Session.PublishState('tasks', '{"rows":[' + TaskRows + ']}');
  Finally
    Titles.Free;
    Ids.Free;
    Captions.Free;
    Paths.Free;
  End;
End;

Procedure TAssistantMonitorBridge.PushStatus(Form: TProjectAssistantForm);
Begin
  Try
    If Not Assigned(Form) Then
      Exit;
    PublishStateKeys(Form);
    { A connection reload sets the flags. The requested lists follow this status frame. }
    PublishSamplingLists(Form);
  Finally
    FinishStatusPush;
  End;
End;

Procedure TAssistantMonitorBridge.FillSnapshot(Form: TProjectAssistantForm; Out Snapshot: TMonitorSnapshot);
Var
  Turn: TAssistantMonitorTurn;
  ErrorText: String;
  Index, Kept: Integer;
Begin
  Snapshot := Default(TMonitorSnapshot);
  If Not Assigned(Form) Then
    Exit;
  Form.FillMonitorView(Snapshot.View);
  Snapshot.View.RemoteApproval := MonitorRemoteApprovalEnabled;
  ApplyHostFlags(Snapshot.View);
  Form.FillMonitorPlan(Snapshot.PlanRows);
  Form.FillMonitorTasks(Snapshot.TaskRows);
  Snapshot.PlanPath := Snapshot.View.PlanPath;
  Snapshot.PlanTitle := Snapshot.View.PlanTitle;
  Snapshot.PlanRunning := Snapshot.View.PlanRunning;
  Snapshot.Approval := CurrentAssistantApproval;
  Kept := 0;
  For Index := 0 To MonitorSnapshotTurnCap - 1 Do
    Begin
      If Not Form.FillMonitorTurn(Index, Turn, ErrorText) Then
        Break;
      SetLength(Snapshot.StoredTurns, Kept + 1);
      Snapshot.StoredTurns[Kept] := Turn;
      Inc(Kept);
    End;
  Snapshot.HasLive := Form.FillMonitorTurn(MonitorLiveTurnIndex, Snapshot.Live, ErrorText);
End;

Procedure TAssistantMonitorBridge.PushSnapshot(Form: TProjectAssistantForm; Const RefId: String);
Var
  Snapshot: TMonitorSnapshot;
  Session: TMonitorSession;
  Id: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Exit;
  FillSnapshot(Form, Snapshot);
  Id := RefId;
  If Id = '' Then
    Id := HostId;
  If Session.MirrorEpoch = '' Then
    PublishEpoch;
  { BeginStream clears a new epoch. Copy the open turn after that, or the phone gets an empty page. }
  { The outline goes out on resume. A body page is not a second content path. }
  Session.ObserveSnapshot(Snapshot);
End;

Procedure TAssistantMonitorBridge.RetryDeferredResumes;
Var
  Index, Count: Integer;
  Command: TMonitorQueuedCommand;
  Pending: Array Of TMonitorQueuedCommand;
Begin
  If AssistantModalDepth > 0 Then
    Exit;
  If Not Assigned(FOutstanding) Then
    Exit;
  Count := 0;
  SetLength(Pending, 0);
  LockBridge;
  Try
    For Index := 0 To FOutstanding.Count - 1 Do
      Begin
        Command := TMonitorQueuedCommand(FOutstanding[Index]);
        If Command.Finished Or Command.Claimed Or Command.Cancelled Or Command.ExecuteQueued Then
          Continue;
        Command.ExecuteQueued := True;
        InterlockedIncrement(Command.RefCount);
        SetLength(Pending, Count + 1);
        Pending[Count] := Command;
        Inc(Count);
      End;
  Finally
    UnlockBridge;
  End;
  For Index := 0 To Count - 1 Do
    Try
      TThread.Queue(Nil, @Pending[Index].Execute);
    Except
      On E: Exception Do
        Begin
          LockBridge;
          Try
            Pending[Index].ExecuteQueued := False;
          Finally
            UnlockBridge;
          End;
          Pending[Index].Release;
          ReportPluginException('AssistantMonitorBridge.Resume', E);
        End;
    End;
End;

Function PlanRowsStamp(Const Rows: TAssistantMonitorPlanRows; Const Path, Title, Revision: String;
  Running: Boolean): String;
Var
  I: Integer;
Begin
  Result := Path + #1 + Title + #1 + BoolToStr(Running, True) + #1 + Revision;
  For I := 0 To High(Rows) Do
    Result := Result + #1 + IntToStr(Rows[I].Index) + #1 + Rows[I].Status + #1 + Rows[I].Title;
End;

Function SnapshotHasOpenTurn(Const Snapshot: TMonitorSnapshot): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 0 To High(Snapshot.StoredTurns) Do
    If Snapshot.StoredTurns[Index].Id <> '' Then
      Exit(True);
  If Not Snapshot.HasLive Then
    Exit;
  { The idle placeholder is not the stored chat. Sending it is the blank page. }
  If (Snapshot.Live.Id <> '') And (Snapshot.Live.Id <> 'live') Then
    Exit(True);
  Result := Length(Snapshot.Live.Blocks) > 0;
End;

Procedure TAssistantMonitorBridge.DeliverOpenScreen;
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  Snapshot: TMonitorSnapshot;
  ConversationId, ProjectRoot, Title, Epoch, MirrorId, MirrorRoot, MirrorTitle, Key: String;
  Cursor: Int64;
Begin
  Form := OpenForm;
  If (Not Assigned(Form)) Or (Not Form.MonitorScreenReady) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If (Not Assigned(Session)) Or (Not Session.ClientAuthenticated) Then
    Begin
      FDeliveredScreen := '';
      Exit;
    End;
  Form.FillMonitorIdentity(ConversationId, ProjectRoot, Title);
  Session.CopyMirrorIdentity(Epoch, MirrorId, MirrorRoot, MirrorTitle, Cursor);
  If Epoch = '' Then
    Exit;
  Key := Epoch + #1 + ConversationId;
  If Key = FDeliveredScreen Then
    Exit;
  FillSnapshot(Form, Snapshot);
  { An empty page is not a conversation. The link thread sends a baseline once turns exist. }
  If Not SnapshotHasOpenTurn(Snapshot) Then
    Exit;
  Session.ObserveSnapshot(Snapshot);
  FDeliveredScreen := Key;
End;

Procedure TAssistantMonitorBridge.NoteMirrorWake;
Begin
  LockBridge;
  Try
    If FPumpPending Then
      Exit;
    FPumpPending := True;
  Finally
    UnlockBridge;
  End;
  If GetCurrentThreadId = MainThreadID Then
    SchedulePump(0)
  Else
    Application.QueueAsyncCall(@SchedulePump, 0);
End;

Procedure TAssistantMonitorBridge.SchedulePump(Data: PtrInt);
Var
  NowMs, WaitMs: QWord;
Begin
  LockBridge;
  Try
    If Not Assigned(FSession) Then
      Begin
        FPumpPending := False;
        Exit;
      End;
  Finally
    UnlockBridge;
  End;
  NowMs := GetTickCount64;
  If (FCoalesceUntil <> 0) And (NowMs < FCoalesceUntil) Then
    Begin
      WaitMs := FCoalesceUntil - NowMs;
      If WaitMs < 1 Then
        WaitMs := 1;
      If WaitMs > 20 Then
        WaitMs := 20;
      If Assigned(FCoalesceTimer) Then
        Begin
          FCoalesceTimer.Enabled := False;
          FCoalesceTimer.Interval := WaitMs;
          FCoalesceTimer.Enabled := True;
        End;
      Exit;
    End;
  FCoalesceUntil := NowMs + 20;
  Application.QueueAsyncCall(@QueuedPump, 0);
End;

Procedure TAssistantMonitorBridge.QueuedPump(Data: PtrInt);
Var
  Seen: Int64;
Begin
  If Assigned(FCoalesceTimer) Then
    FCoalesceTimer.Enabled := False;
  Seen := AssistantMirrorCounter;
  If (Seen <> FPumpedMirror) Or (FSentEpoch = '') Then
    PumpMirror(Seen);
  LockBridge;
  Try
    FPumpPending := False;
  Finally
    UnlockBridge;
  End;
  If AssistantMirrorCounter <> FPumpedMirror Then
    NoteMirrorWake;
End;

Procedure TAssistantMonitorBridge.CoalesceTimerTimer(Sender: TObject);
Begin
  If Assigned(FCoalesceTimer) Then
    FCoalesceTimer.Enabled := False;
  Application.QueueAsyncCall(@QueuedPump, 0);
End;

Procedure TAssistantMonitorBridge.MirrorTimerTimer(Sender: TObject);
Var
  Seen: Int64;
Begin
  If Not (Sender Is TTimer) Then
    Exit;
  RetryDeferredResumes;
  Seen := AssistantMirrorCounter;
  { Backstop only. A missed wake, or a phone that connected after the last tick. }
  If (Seen <> FPumpedMirror) Or (FSentEpoch = '') Then
    PumpMirror(Seen);
  DeliverOpenScreen;
End;

Function FlagsChanged(Const View: TAssistantMonitorView; Valid, Busy, Sending, PlanRunning, CanSend, CanSteer, CanStop: Boolean;
  Const Phase, SentModel, SentStatus: String): Boolean;
Begin
  Result := (Not Valid) Or (Busy <> View.Busy) Or (Sending <> View.Sending) Or (PlanRunning <> View.PlanRunning) Or
    (Phase <> View.Phase) Or (CanSend <> View.CanSend) Or (CanSteer <> View.CanSteer) Or (CanStop <> View.CanStop) Or
    (SentModel <> View.Model) Or (SentStatus <> View.StatusText);
End;

Procedure TAssistantMonitorBridge.PumpMirror(Seen: Int64);
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  View: TAssistantMonitorView;
  Turn: TAssistantMonitorTurn;
  Sent: TAssistantMonitorBlockArray;
  Rows: TAssistantMonitorPlanRows;
  ErrorText, PlanStamp: String;
Begin
  If FPumping Then
    Exit;
  FPumping := True;
  Try
  Form := OpenForm;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If (Not Assigned(Session)) Or (Not Assigned(Form)) Then
    Exit;
  Form.FillMonitorView(View);
  ApplyHostFlags(View);
  { New has already minted the next id. Do not observe its note onto the closed mirror. }
  If FormConversationMoved(Form, Session) Then
    PublishEpoch;
  Turn := Default(TAssistantMonitorTurn);
  SetLength(Sent, 0);
  { The mirror holds the last observation. Unchanged bodies are not copied again. }
  If Not Session.CopyLiveBlocks(Sent) Then
    SetLength(Sent, 0);
  If Not Form.FillMonitorLiveChanges(Sent, Turn, ErrorText) Then
    Turn := Default(TAssistantMonitorTurn);
  If Turn.Id <> '' Then
    Session.ObserveTurn(Turn);
  If Session.MirrorEpoch = '' Then
    PublishEpoch;
  If Session.MirrorEpoch <> '' Then
    FSentEpoch := Session.MirrorEpoch;
  { Status is state. It does not allocate a content sequence. }
  If FlagsChanged(View, FSentFlagsValid, FSentBusy, FSentSending, FSentPlanRunning, FSentCanSend, FSentCanSteer,
    FSentCanStop, FSentPhase, FSentModel, FSentStatusText) Then
    Begin
      FSentFlagsValid := True;
      FSentBusy := View.Busy;
      FSentSending := View.Sending;
      FSentPlanRunning := View.PlanRunning;
      FSentPhase := View.Phase;
      FSentCanSend := View.CanSend;
      FSentCanSteer := View.CanSteer;
      FSentCanStop := View.CanStop;
      FSentModel := View.Model;
      FSentStatusText := View.StatusText;
      PushStatus(Form);
    End;
  Form.FillMonitorPlan(Rows);
  Session.ObservePlan(View.PlanPath, View.PlanTitle, View.PlanRunning, Rows);
  PlanStamp := PlanRowsStamp(Rows, View.PlanPath, View.PlanTitle, Form.PlanDocumentRevision, View.PlanRunning);
  If PlanStamp <> FPlanStamp Then
    Begin
      PublishPlanRows(Form);
      FPlanStamp := PlanStamp;
    End;
  FPumpedMirror := Seen;
  NoteOpenLogPosition;
  Finally
    FPumping := False;
  End;
End;

Procedure TAssistantMonitorBridge.PublishPlanRows(Form: TProjectAssistantForm);
Begin
  PublishStateKeys(Form);
End;

Procedure TAssistantMonitorBridge.PushPlan(Form: TProjectAssistantForm);
Var
  View: TAssistantMonitorView;
  Rows: TAssistantMonitorPlanRows;
Begin
  If Not Assigned(Form) Then
    Exit;
  Form.NoteMonitorPlanRevision;
  PublishStateKeys(Form);
  Form.FillMonitorPlan(Rows);
  Form.FillMonitorView(View);
  FPlanStamp := PlanRowsStamp(Rows, View.PlanPath, View.PlanTitle, Form.PlanDocumentRevision, View.PlanRunning);
End;

Procedure TAssistantMonitorBridge.PushMenuLists(Form: TProjectAssistantForm);
Begin
  PushTargets(Form);
  PushConversations(Form);
  PushModels(Form);
  PushReasoning(Form);
  PushPermissions(Form);
End;

Procedure TAssistantMonitorBridge.PushTargets(Form: TProjectAssistantForm);
Begin
  PublishStateKeys(Form);
End;

Procedure TAssistantMonitorBridge.PushModels(Form: TProjectAssistantForm);
Var
  Ids, Captions: TStringList;
  Current, Backend, Note: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    PublishStateKeys(Form);
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Procedure TAssistantMonitorBridge.PushReasoning(Form: TProjectAssistantForm);
Var
  Ids, Captions: TStringList;
  Current, Note: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    PublishStateKeys(Form);
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Procedure TAssistantMonitorBridge.PushPermissions(Form: TProjectAssistantForm);
Var
  Ids, Captions: TStringList;
  Current, Backend, Note: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    PublishStateKeys(Form);
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Procedure TAssistantMonitorBridge.PushConversations(Form: TProjectAssistantForm);
Var
  Ids, Titles: TStringList;
  Current: String;
  Truncated: Boolean;
Begin
  If Not Assigned(Form) Then
    Exit;
  Ids := TStringList.Create;
  Titles := TStringList.Create;
  Try
    PublishStateKeys(Form);
  Finally
    Titles.Free;
    Ids.Free;
  End;
End;

Procedure TAssistantMonitorBridge.DeliverNotice(Job: TMonitorNoticeJob);
Var
  Form: TProjectAssistantForm;
  View: TAssistantMonitorView;
  Tasks: TAssistantMonitorTaskRows;
  Session: TMonitorSession;
Begin
  If Not Assigned(Job) Then
    Exit;
  Form := OpenForm;
  Case Job.Kind Of
    asnTranscript, asnPhase:
      ;
    asnMode:
      If Assigned(Form) Then
        Begin
          PublishStateKeys(Form);
        End;
    asnTarget:
      If Assigned(Form) Then
        Begin
          PublishStateKeys(Form);
        End;
    asnPlan:
      If Assigned(Form) Then
        PushPlan(Form);
    asnTasks:
      If Assigned(Form) Then
        Begin
          PublishStateKeys(Form);
        End;
    asnStatus, asnError, asnSession:
      { The idle flags and the model travel here. A patch alone can miss both. }
      PushStatus(Form);
    asnSnapshot:
      PushSnapshot(Form, '');
    asnIdentity:
      PublishEpoch;
    asnApproval:
      Begin
        If Not Job.HasApproval Then
          Exit;
        LockBridge;
        Try
          Session := FSession;
        Finally
          UnlockBridge;
        End;
        If Job.Approval.Active Then
          Begin
            If Assigned(Session) Then
              Session.NoteApprovalRequested(Job.Approval.ToolId, Job.Approval.DecisionsAccepted);
            SendJson(EncodeMonitorApprovalRequested(HostId, Job.Approval));
          End
        Else
          Begin
            If Assigned(Session) Then
              Session.NoteApprovalClosed(Job.Approval.ToolId);
            SendJson(EncodeMonitorApprovalClosed(HostId, Job.Approval.ToolId, Job.Approval.Reason));
          End;
      End;
  Else
    ;
  End;
End;

Procedure TAssistantMonitorBridge.Hear(Kind: TAssistantSessionNoticeKind);
Var
  Job: TMonitorNoticeJob;
  QueueStatus: Boolean;
Begin
  Try
    QueueStatus := True;
    If Kind = asnStatus Then
      Begin
        LockBridge;
        Try
          If FStatusQueued Then
            Begin
              FStatusDirty := True;
              QueueStatus := False;
            End
          Else
            FStatusQueued := True;
        Finally
          UnlockBridge;
        End;
      End;
    If Not QueueStatus Then
      Exit;
    Try
      Job := TMonitorNoticeJob.Create;
      Job.Kind := Kind;
      Job.HasApproval := Kind = asnApproval;
      If Job.HasApproval Then
        Job.Approval := CurrentAssistantApproval;
      TThread.Queue(Nil, @Job.Execute);
    Except
      On E: Exception Do
        Begin
          If Kind = asnStatus Then
            Begin
              LockBridge;
              Try
                FStatusQueued := False;
              Finally
                UnlockBridge;
              End;
            End;
          Raise;
        End;
    End;
  Except
    On E: Exception Do
      ReportPluginException('AssistantMonitorBridge.Hear', E);
  End;
End;

Procedure TAssistantMonitorBridge.HandleApprovalClosed(Const ToolId, Reason: String);
Begin
  Try
    SendJson(EncodeMonitorApprovalClosed(HostId, ToolId, Reason));
  Except
    On E: Exception Do
      ReportPluginException('AssistantMonitorBridge.ApprovalClosed', E);
  End;
End;

Function TAssistantMonitorBridge.DispatchCommand(Form: TProjectAssistantForm; Kind: Integer;
  Const Id, PayloadJson: String; Out ErrorText, DoneText: String): Boolean;
Var
  Text, ModeText, Path, ArchiveId, ApiText, Level, Approval: String;
  Plan: TMonitorPathMessage;
  Task: TMonitorTaskCommand;
  Image: TMonitorImageGet;
  Turn: TAssistantMonitorTurn;
  Session: TMonitorSession;
  Data: TBytes;
  Mime: String;
  ImageWidth, ImageHeight, Index: Integer;
  Messages: TStringArray;
  Unavailable: String;
Begin
  Result := False;
  ErrorText := '';
  DoneText := '';
  Case Kind Of
    Ord(mmkSend):
      Begin
        If Not DecodeMonitorText(PayloadJson, Text) Then
          Text := '';
        Result := Form.RemoteSubmit(Text, ErrorText);
      End;
    Ord(mmkSteer):
      Begin
        If Not DecodeMonitorText(PayloadJson, Text) Then
          Text := '';
        Result := Form.RemoteSteer(Text, ErrorText);
      End;
    Ord(mmkStop):
      Result := Form.RemoteStop(ErrorText);
    Ord(mmkSetMode):
      Begin
        If Not DecodeMonitorSetMode(PayloadJson, ModeText) Then
          ModeText := '';
        Result := Form.RemoteSelectMode(ModeText, ErrorText);
      End;
    Ord(mmkNewConversation):
      Result := Form.RemoteNewConversation(ErrorText);
    Ord(mmkSelectPlan):
      Begin
        If Not DecodeMonitorPath(PayloadJson, Path) Then
          Path := '';
        Result := Form.RemoteSelectPlan(Path, ErrorText);
      End;
    Ord(mmkSelectTarget):
      Begin
        { An empty path is Current Project. A missing path is not that value. }
        If Not DecodeMonitorPath(PayloadJson, Path) Then
          Exit;
        Result := Form.RemoteSelectTarget(Path, ErrorText);
      End;
    Ord(mmkSelectConversation):
      Begin
        { An empty id is the open conversation. A missing id is not that value. }
        If Not DecodeMonitorSelectConversation(PayloadJson, ArchiveId) Then
          Exit;
        Result := Form.RemoteSelectConversation(ArchiveId, ErrorText);
      End;
    Ord(mmkSetModel):
      Begin
        { A missing model is not an empty id. }
        If Not DecodeMonitorSetModel(PayloadJson, ArchiveId) Then
          Exit;
        Result := Form.RemoteSelectModel(ArchiveId, ErrorText);
      End;
    Ord(mmkSetReasoning):
      Begin
        { A missing level is not model default. An empty level is. }
        If Not DecodeMonitorSetReasoning(PayloadJson, Level) Then
          Exit;
        Result := Form.RemoteSelectReasoning(Level, ErrorText);
      End;
    Ord(mmkSetPermissions):
      Begin
        { A missing approval is not ask. This is not an approval decision. }
        If Not DecodeMonitorSetPermissions(PayloadJson, Approval) Then
          Exit;
        Result := Form.RemoteSelectPermissions(Approval, ErrorText);
      End;
    Ord(mmkNewPlan):
      Begin
        Plan.Title := '';
        Plan.HasTitle := False;
        DecodeMonitorNewPlan(PayloadJson, Plan);
        If Not Plan.HasTitle Then
          Plan.Title := '';
        Result := Form.RemoteNewPlan(Plan.Title, ErrorText);
      End;
    Ord(mmkClosePlan):
      Result := Form.RemoteClosePlan(ErrorText);
    Ord(mmkWorkOnPlan):
      Begin
        ErrorText := 'Use Run Plan. It starts at the first item that is not complete.';
        Result := False;
      End;
    Ord(mmkRunPlan):
      Result := Form.RemoteRunPlan(ErrorText);
    Ord(mmkStopPlan):
      Result := Form.RemoteStopPlan(ErrorText);
    Ord(mmkRunTask):
      Begin
        Task.Id := '';
        Task.Note := '';
        DecodeMonitorTaskCommand(PayloadJson, Task);
        Result := Form.RemoteRunTask(Task.Id, Task.Note, ErrorText);
      End;
    Ord(mmkInsertTask):
      Begin
        Task.Id := '';
        Task.Note := '';
        ApiText := '';
        DecodeMonitorTaskCommand(PayloadJson, Task);
        Result := Form.RemoteInsertTask(Task.Id, Task.Note, ApiText, ErrorText);
        If Result Then
          DoneText := ApiText;
      End;
    Ord(mmkRefresh):
      Begin
        If Not DecodeMonitorText(PayloadJson, Text) Then
          Text := '';
        If Text = 'plan_choices' Then
          Begin
            PushPlan(Form);
            Result := True;
          End
        Else If Text = 'menu_choices' Then
          Begin
            PushPlan(Form);
            PushMenuLists(Form);
            Result := True;
          End
        Else
          Begin
            { An old stall Refresh must not build a snapshot on the IDE thread. }
            SendError(Id, MonitorHostBusyReason, 'The Project Assistant is busy.');
            Result := True;
          End;
      End;
    Ord(mmkTurn):
      Begin
        Index := 0;
        If Not DecodeMonitorTurnRequest(PayloadJson, Index) Then
          Begin
            ErrorText := 'missing';
            Exit;
          End;
        LockBridge;
        Try
          Session := FSession;
        Finally
          UnlockBridge;
        End;
        If Assigned(Session) And Session.FetchMirrorTurn(Index, Turn) Then
          Begin
            Session.SendTurnPage(Id, Turn);
            Result := True;
            Exit;
          End;
        Result := Form.RemoteTurn(Index, Turn, ErrorText);
        If Result And Assigned(Session) Then
          Session.SendTurnPage(Id, Turn);
      End;
    Ord(mmkImageGet):
      Begin
        Image.TurnIndex := 0;
        Image.ImageId := '';
        If Not DecodeMonitorImageGet(PayloadJson, Image) Then
          Begin
            ErrorText := 'missing';
            Exit;
          End;
        Result := Form.RemoteImage(Image.TurnIndex, Image.ImageId, Data, Mime, ImageWidth, ImageHeight, ErrorText);
        If Not Result Then
          Begin
            If ErrorText = '' Then
              ErrorText := 'missing';
            SendJson(EncodeMonitorImageUnavailable(Id, Image.ImageId, 'missing'));
            Result := True;
            ErrorText := '';
          End
        Else If TryPackMonitorImage(Id, Image.ImageId, Mime, ImageWidth, ImageHeight, 1, Data, False, False,
          Messages, Unavailable) Then
          Begin
            LockBridge;
            Try
              Session := FSession;
            Finally
              UnlockBridge;
            End;
            If Assigned(Session) Then
              Session.SendPackedFrames(Messages);
          End
        Else
          Begin
            If Unavailable = '' Then
              Unavailable := 'missing';
            SendJson(EncodeMonitorImageUnavailable(Id, Image.ImageId, Unavailable));
          End;
      End;
  Else
    ErrorText := 'Unknown message type.';
  End;
End;

Function LiveRefresh(Const PayloadJson: String): Boolean;
Var
  Text: String;
Begin
  Result := DecodeMonitorText(PayloadJson, Text) And (Text = 'live');
End;

Procedure TAssistantMonitorBridge.PushLiveState;
Var
  Form: TProjectAssistantForm;
Begin
  Form := OpenForm;
  If Not Assigned(Form) Then
    Exit;
  { Status and the plan are not in the head pages. A running plan must not wait for the next row change. }
  PushStatus(Form);
  PushPlan(Form);
End;

Procedure TAssistantMonitorBridge.RunCommand(Command: TMonitorQueuedCommand);
Var
  Form: TProjectAssistantForm;
  ErrorText, DoneText: String;
  Ok: Boolean;
Begin
  If Not Assigned(Command) Then
    Exit;
  { A screen wake. Not a user command, and a running plan must not refuse it. }
  If (Command.Kind = Ord(mmkRefresh)) And LiveRefresh(Command.Payload) Then
    Begin
      PushLiveState;
      Exit;
    End;
  LockBridge;
  Try
    If Command.Cancelled Then
      Exit;
    { A modal defers every command. A cancelled command sends nothing. }
    If AssistantModalDepth > 0 Then
      Begin
        Command.Defer := True;
        Exit;
      End;
    If (Command.Kind = Ord(mmkResume)) And ResumeFormPending(Command) Then
      Begin
        Command.Defer := True;
        Exit;
      End;
    Command.Claimed := True;
  Finally
    UnlockBridge;
  End;
  If Command.Defer Or (Not Command.Claimed) Then
    Exit;
  { Resume is answered on the link thread. A queued copy is not a second answer. }
  If Command.Kind = Ord(mmkResume) Then
    Exit;
  LockBridge;
  Try
    If Assigned(FSession) Then
      FSession.NoteCommandAccepted(Command.ClientId);
  Finally
    UnlockBridge;
  End;
  Form := OpenForm;
  If Not Assigned(Form) Then
    Begin
      SendError(Command.ClientId, MonitorNoSessionReason, MonitorNoSessionMessage);
      Exit;
    End;
  DoneText := '';
  Ok := DispatchCommand(Form, Command.Kind, Command.ClientId, Command.Payload, ErrorText, DoneText);
  If Not Ok Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'The desktop control is not available.';
      SendError(Command.ClientId, 'command', ErrorText);
    End
  Else If Not LongRunningCommand(Command.Kind) Then
    Begin
      LockBridge;
      Try
        If Assigned(FSession) Then
          FSession.NoteCommandDone(Command.ClientId, DoneText);
      Finally
        UnlockBridge;
      End;
    End;
End;

Procedure TAssistantMonitorBridge.HandleCommand(Kind: Integer; Const Id, PayloadJson: String);
Var
  Command: TMonitorQueuedCommand;
Begin
  Command := TMonitorQueuedCommand.Create;
  Command.Kind := Kind;
  Command.ClientId := Id;
  Command.Payload := PayloadJson;
  Command.Cancelled := False;
  Command.Claimed := False;
  Command.BusySent := False;
  Command.Finished := False;
  Command.Defer := False;
  Command.ExecuteQueued := True;
  Command.QueuedAt := GetTickCount64;
  Command.RefCount := 2;
  LockBridge;
  Try
    FOutstanding.Add(Command);
  Finally
    UnlockBridge;
  End;
  Try
    TThread.Queue(Nil, @Command.Execute);
  Except
    On E: Exception Do
      Begin
        LockBridge;
        Try
          ForgetCommand(Command);
        Finally
          UnlockBridge;
        End;
        Command.Release;
        Command.Release;
        ReportPluginException('AssistantMonitorBridge.HandleCommand', E);
      End;
  End;
End;

Procedure AttachAssistantMonitorBridge(Session: TMonitorSession);
Begin
  If Assigned(Bridge) Then
    Bridge.Attach(Session);
End;

Procedure DetachAssistantMonitorBridge;
Begin
  If Assigned(Bridge) Then
    Bridge.Detach;
End;

Function DecideAssistantMonitorApproval(Const ToolId: String; Allow: Boolean): Boolean;
Var
  Session: TMonitorSession;
Begin
  Result := False;
  If Not Assigned(Bridge) Then
    Exit;
  Bridge.LockBridge;
  Try
    Session := Bridge.FSession;
  Finally
    Bridge.UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Exit;
  Result := Session.ApplyApprovalDecision(ToolId, Allow);
End;

Procedure RegisterAssistantMonitor;
Begin
  If Not Assigned(Bridge) Then
    Bridge := TAssistantMonitorBridge.Create;
  SetAssistantSessionListener(@Bridge.Hear);
  SetAssistantRemoteApproval(@AssistantMonitorApprovalWait);
End;

Procedure UnregisterAssistantMonitor;
Begin
  SetAssistantSessionListener(Nil);
  SetAssistantRemoteApproval(Nil);
End;

Function CaptureMonitorListenSnapshot(Out Settings: TMonitorSettings; Out ErrorText: String): Boolean;
Begin
  Result := LoadMonitorSettings(Settings, ErrorText);
  If Result Then
    ApplyMonitorRemoteApproval(Settings.RemoteApproval);
End;

Initialization

Bridge := TAssistantMonitorBridge.Create;

Finalization

UnregisterAssistantMonitor;
FreeAndNil(Bridge);

End.
