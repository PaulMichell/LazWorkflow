Unit AssistantMonitorBridge;

{ Main-thread command pump and session listener. The listener only enqueues.
  A command wait must not sit in the listen thread. The idle sweep answers
  host_busy if the IDE has not claimed the command. It does not build provider
  JSON and does not replace the form trace handler.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorSession, AssistantMonitorSettings;

Const
  MonitorCommandWaitMs = 5000;
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
  AssistantMonitorFrames, AssistantMonitorApproval, AssistantTools, ProjectAssistantForm;

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
    FPumpedMirror: Int64;
    FPlanStamp: String;
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
    Procedure ApplyHostFlags(Const View: TAssistantMonitorView);
    Procedure PushTranscript(Form: TProjectAssistantForm);
    Procedure PushSnapshot(Form: TProjectAssistantForm; Const RefId: String);
    Procedure PushStatus(Form: TProjectAssistantForm);
    Procedure PublishEpoch;
    Procedure PushPlan(Form: TProjectAssistantForm);
    Procedure MirrorTimerTimer(Sender: TObject);
    Procedure PumpMirror(Seen: Int64);
    Procedure FinishStatusPush;
    Procedure RunCommand(Command: TMonitorQueuedCommand);
    Function DispatchCommand(Form: TProjectAssistantForm; Kind: Integer; Const Id, PayloadJson: String;
      Out ErrorText: String): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Attach(Session: TMonitorSession);
    Procedure Detach;
  End;

Var
  Bridge: TAssistantMonitorBridge;

Procedure TMonitorQueuedCommand.Release;
Begin
  If InterlockedDecrement(RefCount) = 0 Then
    Free;
End;

Procedure TMonitorQueuedCommand.Execute;
Var
  Listed: Boolean;
Begin
  Try
    Try
      If Assigned(Bridge) Then
        Bridge.RunCommand(Self);
    Except
      On E: Exception Do
        ReportPluginException('AssistantMonitorBridge.Command', E);
    End;
  Finally
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
  FMirrorTimer.Interval := 150;
  FMirrorTimer.OnTimer := @MirrorTimerTimer;
End;

Destructor TAssistantMonitorBridge.Destroy;
Begin
  Detach;
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
Var
  Index, Count: Integer;
  NowMs: QWord;
  Command: TMonitorQueuedCommand;
  Expired: Array Of TMonitorQueuedCommand;
  Notify: Array Of Boolean;
Begin
  If Not Assigned(FOutstanding) Then
    Exit;
  NowMs := GetTickCount64;
  Count := 0;
  LockBridge;
  Try
    Index := 0;
    While Index < FOutstanding.Count Do
      Begin
        Command := TMonitorQueuedCommand(FOutstanding[Index]);
        If Command.Finished Or Command.Claimed Or (NowMs - Command.QueuedAt < MonitorCommandWaitMs) Then
          Begin
            Inc(Index);
            Continue;
          End;
        Command.Cancelled := True;
        SetLength(Expired, Count + 1);
        SetLength(Notify, Count + 1);
        Expired[Count] := Command;
        Notify[Count] := Not Command.BusySent;
        Command.BusySent := True;
        FOutstanding.Delete(Index);
        Inc(Count);
      End;
  Finally
    UnlockBridge;
  End;
  For Index := 0 To Count - 1 Do
    Begin
      Try
        If Notify[Index] Then
          SendError(Expired[Index].ClientId, MonitorHostBusyReason, 'The Project Assistant is busy.');
      Except
        On E: Exception Do
          ReportPluginException('AssistantMonitorBridge.Sweep', E);
      End;
      Expired[Index].Release;
    End;
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
  If Assigned(FMirrorTimer) Then
    FMirrorTimer.Enabled := Assigned(Session);
End;

Procedure TAssistantMonitorBridge.Detach;
Var
  Session: TMonitorSession;
Begin
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
Begin
  SendJson(EncodeMonitorError(HostId, Reason, MessageText, RefId));
End;

Function TAssistantMonitorBridge.OpenForm: TProjectAssistantForm;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  Result := Nil;
  For I := 0 To Screen.CustomFormCount - 1 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And (Not (csDestroying In Form.ComponentState)) Then
        Exit(TProjectAssistantForm(Form));
    End;
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

Procedure TAssistantMonitorBridge.PushTranscript(Form: TProjectAssistantForm);
Var
  Turn: TAssistantMonitorTurn;
  View: TAssistantMonitorView;
  Transcript: TMonitorTranscript;
  Frames: TStringArray;
  ErrorText: String;
  Session: TMonitorSession;
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
  If Not Form.FillMonitorTurn(MonitorLiveTurnIndex, Turn, ErrorText) Then
    Exit;
  Form.FillMonitorView(View);
  Transcript := Default(TMonitorTranscript);
  Transcript.TurnIndex := Turn.TurnIndex;
  Transcript.Revision := Session.NextTranscriptRevision(Turn.TurnIndex);
  Transcript.Phase := View.Phase;
  Transcript.StatusText := View.StatusText;
  Transcript.DurationMs := View.ElapsedMs;
  If Transcript.DurationMs <= 0 Then
    Transcript.DurationMs := Turn.DurationMs;
  Transcript.Blocks := Turn.Blocks;
  Transcript.Part := 1;
  Transcript.PartCount := 1;
  Frames := PackMonitorTranscript(HostId, Transcript);
  If Length(Frames) = 0 Then
    Exit;
  Session.QueueTranscriptParts(Turn.TurnIndex, Frames);
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

Procedure TAssistantMonitorBridge.PublishEpoch;
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  ConversationId, ProjectRoot, Title, Epoch: String;
Begin
  ConversationId := 'current';
  ProjectRoot := '';
  Title := '';
  Form := OpenForm;
  If Assigned(Form) Then
    Form.FillMonitorIdentity(ConversationId, ProjectRoot, Title);
  Epoch := MintMonitorEpoch;
  If Epoch = '' Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Session.BeginMirrorEpoch(Epoch, ConversationId, ProjectRoot, Title);
End;

Procedure TAssistantMonitorBridge.PushStatus(Form: TProjectAssistantForm);
Var
  View: TAssistantMonitorView;
  Payload: TJSONObject;
Begin
  Try
    If Not Assigned(Form) Then
      Exit;
    Form.FillMonitorView(View);
    View.RemoteApproval := MonitorRemoteApprovalEnabled;
    ApplyHostFlags(View);
    { The phone rejects a partial status. This is the same object the snapshot view uses. }
    Payload := MonitorStatusToJson(View);
    Try
      SendJson(EncodeMonitorEnvelope(mmkStatus, HostId, Payload));
    Finally
      Payload.Free;
    End;
  Finally
    FinishStatusPush;
  End;
End;

{ EncodeMonitorEnvelope returns an empty string when the frame is over the cap.
  A length check on that result never sees the overflow, so the snapshot was dropped. }
Function SnapshotJson(Const Id: String; Snapshot: TMonitorSnapshot): String;

  Procedure KeepTextFromBlocks(Var Turn: TAssistantMonitorTurn);
  Var
    I: Integer;
  Begin
    For I := 0 To High(Turn.Blocks) Do
      Begin
        If (Turn.Prompt = '') And (Turn.Blocks[I].Kind = 'user') Then
          Turn.Prompt := Turn.Blocks[I].Body;
        If (Turn.Thinking = '') And (Turn.Blocks[I].Kind = 'thinking') Then
          Turn.Thinking := Turn.Blocks[I].Body;
        If (Turn.Response = '') And (Turn.Blocks[I].Kind = 'answer') Then
          Turn.Response := Turn.Blocks[I].Body;
      End;
    If Turn.PromptPreview = '' Then
      Turn.PromptPreview := Copy(Turn.Prompt, 1, 160);
  End;

  Procedure CompactLiveBlocks(Var Turn: TAssistantMonitorTurn);
  Var
    I: Integer;
  Begin
    For I := 0 To High(Turn.Blocks) Do
      Begin
        If Turn.Blocks[I].Kind = 'tool' Then
          Turn.Blocks[I].Body := Copy(Turn.Blocks[I].Body, 1, 240)
        Else If Turn.Blocks[I].Kind = 'thinking' Then
          Turn.Blocks[I].Body := Copy(Turn.Blocks[I].Body, 1, 240)
        Else If Length(Turn.Blocks[I].Body) > 800 Then
          Turn.Blocks[I].Body := Copy(Turn.Blocks[I].Body, 1, 800);
      End;
  End;

  Procedure TruncateLiveText(Var Turn: TAssistantMonitorTurn);
  Begin
    Turn.Prompt := Copy(Turn.Prompt, 1, 4000);
    Turn.Thinking := Copy(Turn.Thinking, 1, 4000);
    Turn.Response := Copy(Turn.Response, 1, 8000);
    SetLength(Turn.Blocks, 0);
    SetLength(Turn.Images, 0);
  End;

Begin
  Result := EncodeMonitorSnapshot(Id, Snapshot);
  If Result <> '' Then
    Exit;
  KeepTextFromBlocks(Snapshot.Live);
  CompactLiveBlocks(Snapshot.Live);
  Result := EncodeMonitorSnapshot(Id, Snapshot);
  If Result <> '' Then
    Exit;
  SetLength(Snapshot.Live.Blocks, 0);
  SetLength(Snapshot.Live.Images, 0);
  Result := EncodeMonitorSnapshot(Id, Snapshot);
  If Result <> '' Then
    Exit;
  TruncateLiveText(Snapshot.Live);
  Result := EncodeMonitorSnapshot(Id, Snapshot);
End;

Procedure TAssistantMonitorBridge.PushSnapshot(Form: TProjectAssistantForm; Const RefId: String);
Var
  Snapshot: TMonitorSnapshot;
  Turn: TAssistantMonitorTurn;
  ErrorText, Id, Json: String;
  Index, Kept: Integer;
Begin
  If Not Assigned(Form) Then
    Exit;
  Snapshot := Default(TMonitorSnapshot);
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
  Id := RefId;
  If Id = '' Then
    Id := HostId;
  Json := SnapshotJson(Id, Snapshot);
  If Json <> '' Then
    SendJson(Json);
  PushPlan(Form);
End;

Function PlanRowsStamp(Const Rows: TAssistantMonitorPlanRows; Const Path, Title: String; Running: Boolean): String;
Var
  I: Integer;
Begin
  Result := Path + #1 + Title + #1 + BoolToStr(Running, True);
  For I := 0 To High(Rows) Do
    Result := Result + #1 + IntToStr(Rows[I].Index) + #1 + Rows[I].Status + #1 + Rows[I].Title;
End;

Procedure TAssistantMonitorBridge.MirrorTimerTimer(Sender: TObject);
Var
  Seen: Int64;
Begin
  If Not (Sender Is TTimer) Then
    Exit;
  Seen := AssistantMirrorCounter;
  If Seen = FPumpedMirror Then
    Exit;
  PumpMirror(Seen);
End;

Procedure TAssistantMonitorBridge.PumpMirror(Seen: Int64);
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  View: TAssistantMonitorView;
  Turn: TAssistantMonitorTurn;
  Patch: TMonitorPatch;
  Rows: TAssistantMonitorPlanRows;
  Frames: TStringArray;
  ErrorText, Stamp, PlanStamp: String;
  Cursor: Int64;
  I: Integer;
Begin
  Form := OpenForm;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If (Not Assigned(Session)) Or (Not Assigned(Form)) Then
    Begin
      FPumpedMirror := Seen;
      Exit;
    End;
  Form.FillMonitorView(View);
  ApplyHostFlags(View);
  Turn := Default(TAssistantMonitorTurn);
  If Not Form.FillMonitorTurn(MonitorLiveTurnIndex, Turn, ErrorText) Then
    Turn := Default(TAssistantMonitorTurn);
  Patch := Default(TMonitorPatch);
  Patch.Epoch := Session.MirrorEpoch;
  If Patch.Epoch = '' Then
    Begin
      PublishEpoch;
      Patch.Epoch := Session.MirrorEpoch;
    End;
  Patch.TurnIndex := Turn.TurnIndex;
  Patch.TurnId := Turn.Id;
  Patch.Blocks := Turn.Blocks;
  Patch.Busy := View.Busy;
  Patch.Sending := View.Sending;
  Patch.PlanRunning := View.PlanRunning;
  Patch.Phase := View.Phase;
  Patch.CanSend := View.CanSend;
  Patch.CanSteer := View.CanSteer;
  Patch.CanStop := View.CanStop;
  Patch.ElapsedMs := View.ElapsedMs;
  Patch.Part := 1;
  Patch.PartCount := 1;
  { Elapsed time is not part of the commit key. A clock tick must not mint a cursor. }
  Stamp := Patch.Epoch + #1 + Patch.TurnId + #1 + Patch.Phase + #1 + BoolToStr(Patch.Busy, True) +
    BoolToStr(Patch.Sending, True) + BoolToStr(Patch.PlanRunning, True) + BoolToStr(Patch.CanSend, True) +
    BoolToStr(Patch.CanSteer, True) + BoolToStr(Patch.CanStop, True);
  For I := 0 To High(Patch.Blocks) Do
    Stamp := Stamp + #1 + Patch.Blocks[I].BlockId + #1 + Patch.Blocks[I].Kind + #1 + Patch.Blocks[I].Title + #1 +
      Patch.Blocks[I].Body + #1 + BoolToStr(Patch.Blocks[I].Running, True) + BoolToStr(Patch.Blocks[I].Ok, True);
  If (Patch.Epoch <> '') And Session.CommitMirrorCursor(Stamp, Cursor) Then
    Begin
      Patch.Cursor := Cursor;
      Frames := PackMonitorPatch(HostId, Patch);
      If Length(Frames) > 0 Then
        Begin
          For I := 0 To High(Frames) Do
            Session.SendHostJson(Frames[I]);
          Session.NoteMirrorHanded(Cursor);
        End;
    End;
  Form.FillMonitorPlan(Rows);
  PlanStamp := PlanRowsStamp(Rows, View.PlanPath, View.PlanTitle, View.PlanRunning);
  If PlanStamp <> FPlanStamp Then
    Begin
      PushPlan(Form);
      FPlanStamp := PlanStamp;
    End;
  FPumpedMirror := Seen;
End;

Procedure TAssistantMonitorBridge.PushPlan(Form: TProjectAssistantForm);
Var
  Paths, Captions: TStringList;
  View: TAssistantMonitorView;
  Rows: TAssistantMonitorPlanRows;
Begin
  If Not Assigned(Form) Then
    Exit;
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Form.FillMonitorPlanChoices(Paths, Captions);
    Form.FillMonitorView(View);
    Form.FillMonitorPlan(Rows);
    SendJson(EncodeMonitorPlan(HostId, View.PlanPath, View.PlanTitle, View.PlanRunning, Rows, Paths, Captions));
  Finally
    Captions.Free;
    Paths.Free;
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
      PushTranscript(Form);
    asnMode:
      If Assigned(Form) Then
        Begin
          Form.FillMonitorView(View);
          ApplyHostFlags(View);
          SendJson(EncodeMonitorMode(HostId, View.Mode, View.ModeLocked));
        End;
    asnTarget:
      If Assigned(Form) Then
        Begin
          Form.FillMonitorView(View);
          SendJson(EncodeMonitorTarget(HostId, View.TargetKind, View.TargetDisplay, View.TargetRoot));
        End;
    asnPlan:
      PushPlan(Form);
    asnTasks:
      If Assigned(Form) Then
        Begin
          Form.FillMonitorTasks(Tasks);
          SendJson(EncodeMonitorTasks(HostId, Tasks));
        End;
    asnStatus, asnError, asnSession:
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
  Const Id, PayloadJson: String; Out ErrorText: String): Boolean;
Var
  Text, ModeText, Path, ApiText: String;
  Plan: TMonitorPathMessage;
  Task: TMonitorTaskCommand;
  Image: TMonitorImageGet;
  Turn: TAssistantMonitorTurn;
  Data: TBytes;
  Mime: String;
  ImageWidth, ImageHeight, Index: Integer;
  Messages: TStringArray;
  Unavailable: String;
Begin
  Result := False;
  ErrorText := '';
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
    Ord(mmkNewPlan):
      Begin
        Plan.Title := '';
        Plan.HasTitle := False;
        DecodeMonitorNewPlan(PayloadJson, Plan);
        If Not Plan.HasTitle Then
          Plan.Title := '';
        Result := Form.RemoteNewPlan(Plan.Title, ErrorText);
      End;
    Ord(mmkRemovePlan):
      Result := Form.RemoteRemovePlan(ErrorText);
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
          SendJson(EncodeMonitorInsertResult(Id, ApiText));
      End;
    Ord(mmkRefresh):
      Begin
        If DecodeMonitorText(PayloadJson, Text) And (Text = 'plan_choices') Then
          PushPlan(Form)
        Else
          PushSnapshot(Form, Id);
        Result := True;
      End;
    Ord(mmkTurn):
      Begin
        Index := 0;
        If Not DecodeMonitorTurnRequest(PayloadJson, Index) Then
          Begin
            ErrorText := 'missing';
            Exit;
          End;
        Result := Form.RemoteTurn(Index, Turn, ErrorText);
        If Result Then
          SendJson(EncodeMonitorTurnData(Id, Turn));
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
        Else If TryEncodeMonitorImageData(Id, Image.ImageId, Mime, ImageWidth, ImageHeight, 1, Data, False, False,
          Messages, Unavailable) Then
          Begin
            For Index := 0 To High(Messages) Do
              SendJson(Messages[Index]);
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

Procedure TAssistantMonitorBridge.RunCommand(Command: TMonitorQueuedCommand);
Var
  Form: TProjectAssistantForm;
  ErrorText: String;
  Ok, SendBusy: Boolean;
Begin
  If Not Assigned(Command) Then
    Exit;
  SendBusy := False;
  LockBridge;
  Try
    If Command.Cancelled Or (AssistantModalDepth > 0) Then
      Begin
        If (Not Command.Cancelled) And (Not Command.BusySent) Then
          Begin
            Command.BusySent := True;
            SendBusy := True;
          End;
      End
    Else
      Command.Claimed := True;
  Finally
    UnlockBridge;
  End;
  If SendBusy Then
    Begin
      SendError(Command.ClientId, MonitorHostBusyReason, 'The Project Assistant is busy.');
      Exit;
    End;
  If Not Command.Claimed Then
    Exit;
  Form := OpenForm;
  If Not Assigned(Form) Then
    Begin
      SendError(Command.ClientId, MonitorNoSessionReason, MonitorNoSessionMessage);
      Exit;
    End;
  Ok := DispatchCommand(Form, Command.Kind, Command.ClientId, Command.Payload, ErrorText);
  If Not Ok Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'The desktop control is not available.';
      SendError(Command.ClientId, 'command', ErrorText);
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
