Unit AssistantMonitorBridge;

{ Main-thread command pump and session listener. The listener only enqueues.
  A command wait must not sit in the listen thread. The idle sweep answers
  host_busy if the IDE has not claimed the command. Resume is not a user
  command: it stays queued until the IDE thread can fill the catchup.
  It does not build provider JSON and does not replace the form trace handler.

  Size note: exceeds the 1000 line preference. The command pump, live patch,
  and resume catchup share the form and the session. Splitting them would
  duplicate the snapshot fill.
  Reviewed 2026-10-27: a conversation switch publishes its list after the snapshot.
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
    FPumpedMirror: Int64;
    FPlanStamp: String;
    FSentEpoch: String;
    FSentBlocks: Array Of TAssistantMonitorBlock;
    FSentFlagsValid: Boolean;
    FSentBusy: Boolean;
    FSentSending: Boolean;
    FSentPlanRunning: Boolean;
    FSentPhase: String;
    FSentCanSend: Boolean;
    FSentCanSteer: Boolean;
    FSentCanStop: Boolean;
    FPumping: Boolean;
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
    Procedure FillSnapshot(Form: TProjectAssistantForm; Out Snapshot: TMonitorSnapshot);
    Procedure SendCatchupSnapshot(Form: TProjectAssistantForm; Const RefId: String);
    Procedure AnswerResume(Const Id, PayloadJson: String);
    Procedure RetryDeferredResumes;
    Procedure PushStatus(Form: TProjectAssistantForm);
    Procedure PublishEpoch;
    Procedure PushPlan(Form: TProjectAssistantForm);
    Procedure PushTargets(Form: TProjectAssistantForm);
    Procedure PushConversations(Form: TProjectAssistantForm);
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
  NowMs, AgeMs: QWord;
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
        AgeMs := 0;
        If NowMs >= Command.QueuedAt Then
          AgeMs := NowMs - Command.QueuedAt;
        { Resume stays queued. A user command still unclaimed at 5 s answers host_busy. }
        If Not MonitorCommandSweepSendsBusy(Command.Kind, Command.Claimed, Command.Finished, AgeMs) Then
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
  Closed: TMonitorConversationClosed;
  ConversationId, ProjectRoot, Title, Epoch: String;
  HadEpoch: Boolean;
Begin
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  Epoch := MintMonitorEpoch;
  If Epoch = '' Then
    Exit;
  HadEpoch := False;
  If Assigned(Session) Then
    Begin
      { Commit the live patch before the closed cursor is copied. }
      Session.FlushLivePatch;
      HadEpoch := Session.CopyClosedMirror(Closed);
    End;
  If HadEpoch Then
    SendJson(EncodeMonitorConversationClosed(HostId, Closed.Epoch, Closed.Cursor, Closed.ConversationId, Closed.Title));
  ConversationId := 'current';
  ProjectRoot := '';
  Title := '';
  Form := OpenForm;
  If Assigned(Form) Then
    Form.FillMonitorIdentity(ConversationId, ProjectRoot, Title);
  If Assigned(Session) Then
    Session.BeginMirrorEpoch(Epoch, ConversationId, ProjectRoot, Title);
  FSentEpoch := '';
  FPlanStamp := '';
  SetLength(FSentBlocks, 0);
  FSentFlagsValid := False;
  { The connected client learns the new epoch from this catchup. Cursor 0 was the empty start. }
  If HadEpoch And Assigned(Form) Then
    SendCatchupSnapshot(Form, '');
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

Procedure CompactCatchupSnapshot(Var Snapshot: TMonitorSnapshot; Level: Integer);
Var
  Index: Integer;
Begin
  Case Level Of
    1:
      Begin
        For Index := 0 To High(Snapshot.Live.Blocks) Do
          Begin
            If (Snapshot.Live.Prompt = '') And (Snapshot.Live.Blocks[Index].Kind = 'user') Then
              Snapshot.Live.Prompt := Snapshot.Live.Blocks[Index].Body;
            If (Snapshot.Live.Thinking = '') And (Snapshot.Live.Blocks[Index].Kind = 'thinking') Then
              Snapshot.Live.Thinking := Snapshot.Live.Blocks[Index].Body;
            If (Snapshot.Live.Response = '') And (Snapshot.Live.Blocks[Index].Kind = 'answer') Then
              Snapshot.Live.Response := Snapshot.Live.Blocks[Index].Body;
            If Snapshot.Live.Blocks[Index].Kind = 'tool' Then
              Snapshot.Live.Blocks[Index].Body := Copy(Snapshot.Live.Blocks[Index].Body, 1, 240)
            Else If Snapshot.Live.Blocks[Index].Kind = 'thinking' Then
              Snapshot.Live.Blocks[Index].Body := Copy(Snapshot.Live.Blocks[Index].Body, 1, 240)
            Else If Length(Snapshot.Live.Blocks[Index].Body) > 800 Then
              Snapshot.Live.Blocks[Index].Body := Copy(Snapshot.Live.Blocks[Index].Body, 1, 800);
          End;
        If Snapshot.Live.PromptPreview = '' Then
          Snapshot.Live.PromptPreview := Copy(Snapshot.Live.Prompt, 1, 160);
      End;
    2:
      Begin
        SetLength(Snapshot.Live.Blocks, 0);
        SetLength(Snapshot.Live.Images, 0);
      End;
    3:
      Begin
        Snapshot.Live.Prompt := Copy(Snapshot.Live.Prompt, 1, 4000);
        Snapshot.Live.Thinking := Copy(Snapshot.Live.Thinking, 1, 4000);
        Snapshot.Live.Response := Copy(Snapshot.Live.Response, 1, 8000);
        SetLength(Snapshot.Live.Blocks, 0);
        SetLength(Snapshot.Live.Images, 0);
      End;
    4: SetLength(Snapshot.StoredTurns, 0);
    5:
      Begin
        SetLength(Snapshot.PlanRows, 0);
        SetLength(Snapshot.TaskRows, 0);
      End;
    6:
      Begin
        Snapshot.Live.Prompt := Copy(Snapshot.Live.Prompt, 1, 400);
        Snapshot.Live.Thinking := '';
        Snapshot.Live.Response := Copy(Snapshot.Live.Response, 1, 400);
      End;
  Else
    ;
  End;
End;

Function CatchupBodyStamp(Const Snapshot: TMonitorSnapshot; Level: Integer): String;
Begin
  Result := EncodeMonitorSnapshot('stamp', Snapshot);
  If Result <> '' Then
    Exit;
  Result := 'snapshot-level-' + IntToStr(Level) + #1 + IntToStr(Length(Snapshot.StoredTurns)) + #1 +
    IntToStr(Length(Snapshot.Live.Prompt)) + #1 + Copy(Snapshot.Live.Prompt, 1, 120) + #1 +
    Copy(Snapshot.Live.Response, 1, 120) + #1 + Snapshot.PlanPath;
End;

Procedure TAssistantMonitorBridge.PushSnapshot(Form: TProjectAssistantForm; Const RefId: String);
Var
  Snapshot: TMonitorSnapshot;
  Id, Json: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  FillSnapshot(Form, Snapshot);
  Id := RefId;
  If Id = '' Then
    Id := HostId;
  Json := SnapshotJson(Id, Snapshot);
  If Json <> '' Then
    SendJson(Json);
  PushPlan(Form);
  PushConversations(Form);
End;

Procedure TAssistantMonitorBridge.SendCatchupSnapshot(Form: TProjectAssistantForm; Const RefId: String);
Var
  Catchup: TMonitorCatchup;
  Session: TMonitorSession;
  Id, Json, Stamp: String;
  Cursor: Int64;
  Level: Integer;
Begin
  If Not Assigned(Form) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If (Not Assigned(Session)) Or (Session.MirrorEpoch = '') Then
    Exit;
  Catchup := Default(TMonitorCatchup);
  Catchup.Mode := mcmSnapshot;
  Session.CopyMirrorIdentity(Catchup.Epoch, Catchup.ConversationId, Catchup.ProjectRoot, Catchup.Title, Cursor);
  If Catchup.Epoch = '' Then
    Exit;
  FillSnapshot(Form, Catchup.Snapshot);
  Catchup.HasSnapshot := True;
  Id := RefId;
  If Id = '' Then
    Id := HostId;
  Json := '';
  For Level := 0 To 6 Do
    Begin
      If Level > 0 Then
        CompactCatchupSnapshot(Catchup.Snapshot, Level);
      Stamp := CatchupBodyStamp(Catchup.Snapshot, Level);
      If Not Session.CommitSnapshotCursor(Stamp, Cursor) Then
        Exit;
      Catchup.Cursor := Cursor;
      Json := EncodeResumeSnapshot(Id, Cursor, Catchup.Epoch, Catchup.ConversationId, Catchup.ProjectRoot, Catchup.Title,
        Catchup.Snapshot);
      If Json <> '' Then
        Break;
    End;
  If Json = '' Then
    Begin
      WorkflowLogger.Warning('AssistantMonitor', 'catchup snapshot did not fit');
      Exit;
    End;
  SendJson(Json);
  Session.NoteMirrorHanded(Cursor);
  { A patch sent while the phone was still on the previous epoch is dropped.
    The snapshot cursor is already past it, so that patch is not replayed.
    Forget the sent blocks and pump once more so the next cursor carries the
    trace the phone has not seen, including thinking and tool cards. }
  FSentEpoch := '';
  SetLength(FSentBlocks, 0);
  FSentFlagsValid := False;
  PumpMirror(AssistantMirrorCounter);
End;

Procedure TAssistantMonitorBridge.AnswerResume(Const Id, PayloadJson: String);
Var
  ResumeMsg: TMonitorResume;
  Catchup: TMonitorCatchup;
  Session: TMonitorSession;
  Form: TProjectAssistantForm;
  Json: String;
Begin
  If Not DecodeMonitorResume(PayloadJson, ResumeMsg) Then
    Begin
      SendError(Id, 'protocol', 'Resume payload is not valid.');
      Exit;
    End;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Not Assigned(Session) Then
    Begin
      SendError(Id, MonitorNoSessionReason, MonitorNoSessionMessage);
      Exit;
    End;
  Session.FlushLivePatch;
  { A cursor still in the ring does not fill the form. An events frame that does not fit falls through.
    An empty events list means the client is at the committed cursor. It does not mean the client has
    the model, the signed-in flag, or the live blocks. That is a snapshot, the same repair New uses. }
  If Not ResumeNeedsFormSnapshot(Session, ResumeMsg.Epoch, ResumeMsg.Cursor) Then
    Begin
      If Session.TryResumeEvents(ResumeMsg.Epoch, ResumeMsg.Cursor, Catchup) And (Length(Catchup.Patches) > 0) Then
        Begin
          Json := EncodeMonitorCatchup(Id, Catchup);
          If Json <> '' Then
            Begin
              SendJson(Json);
              Form := OpenForm;
              If Assigned(Form) Then
                PushStatus(Form);
              Exit;
            End;
        End;
    End;
  Form := OpenForm;
  If Not Assigned(Form) Then
    Begin
      SendError(Id, MonitorNoSessionReason, MonitorNoSessionMessage);
      Exit;
    End;
  If Session.MirrorEpoch = '' Then
    PublishEpoch;
  If Session.MirrorEpoch = '' Then
    Begin
      SendError(Id, MonitorNoSessionReason, MonitorNoSessionMessage);
      Exit;
    End;
  SendCatchupSnapshot(Form, Id);
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
        If (Command.Kind <> Ord(mmkResume)) Or Command.Finished Or Command.Claimed Or Command.Cancelled Or
          Command.ExecuteQueued Then
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
  RetryDeferredResumes;
  Seen := AssistantMirrorCounter;
  If Seen = FPumpedMirror Then
    Exit;
  PumpMirror(Seen);
End;

Function FlagsChanged(Const View: TAssistantMonitorView; Valid, Busy, Sending, PlanRunning, CanSend, CanSteer, CanStop: Boolean;
  Const Phase: String): Boolean;
Begin
  Result := (Not Valid) Or (Busy <> View.Busy) Or (Sending <> View.Sending) Or (PlanRunning <> View.PlanRunning) Or
    (Phase <> View.Phase) Or (CanSend <> View.CanSend) Or (CanSteer <> View.CanSteer) Or (CanStop <> View.CanStop);
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
  FirstPatch, NeedPatch: Boolean;
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
    Begin
      FPumpedMirror := Seen;
      Exit;
    End;
  Form.FillMonitorView(View);
  ApplyHostFlags(View);
  Turn := Default(TAssistantMonitorTurn);
  If Not Form.FillMonitorTurn(MonitorLiveTurnIndex, Turn, ErrorText) Then
    Turn := Default(TAssistantMonitorTurn);
  If Session.MirrorEpoch = '' Then
    PublishEpoch;
  FirstPatch := Session.MirrorEpoch <> FSentEpoch;
  If FirstPatch Then
    Begin
      SetLength(FSentBlocks, 0);
      FSentFlagsValid := False;
    End;
  Patch := Default(TMonitorPatch);
  Patch.Epoch := Session.MirrorEpoch;
  Patch.TurnIndex := Turn.TurnIndex;
  Patch.TurnId := Turn.Id;
  Patch.Blocks := SelectDirtyMonitorBlocks(FSentBlocks, Turn.Blocks, FirstPatch);
  Patch.Busy := View.Busy;
  Patch.Sending := View.Sending;
  Patch.PlanRunning := View.PlanRunning;
  Patch.Phase := View.Phase;
  Patch.CanSend := View.CanSend;
  Patch.CanSteer := View.CanSteer;
  Patch.CanStop := View.CanStop;
  Patch.ElapsedMs := View.ElapsedMs;
  Patch.HasView := True;
  Patch.Model := View.Model;
  Patch.SignedIn := View.SignedIn;
  Patch.StatusText := View.StatusText;
  Patch.Part := 1;
  Patch.PartCount := 1;
  NeedPatch := (Patch.Epoch <> '') And (FirstPatch Or (Length(Patch.Blocks) > 0) Or
    FlagsChanged(View, FSentFlagsValid, FSentBusy, FSentSending, FSentPlanRunning, FSentCanSend, FSentCanSteer,
    FSentCanStop, FSentPhase));
  If NeedPatch Then
    Begin
      Stamp := Patch.Epoch + #1 + Patch.TurnId + #1 + Patch.Phase + #1 + BoolToStr(Patch.Busy, True) +
        BoolToStr(Patch.Sending, True) + BoolToStr(Patch.PlanRunning, True);
      For I := 0 To High(Patch.Blocks) Do
        Stamp := Stamp + #1 + Patch.Blocks[I].BlockId + #1 + Patch.Blocks[I].Title + #1 + Patch.Blocks[I].Body + #1 +
          BoolToStr(Patch.Blocks[I].Running, True) + BoolToStr(Patch.Blocks[I].Ok, True);
      If Session.CommitMirrorCursor(Stamp, Cursor) Then
        Begin
          Patch.Cursor := Cursor;
          Frames := PackMonitorPatch(HostId, Patch);
          If Length(Frames) > 0 Then
            Begin
              Session.ReplaceLivePatch(Cursor, Frames);
              Session.FlushLivePatch;
              Session.RememberHandedPatch(Cursor, MonitorPatchPayloadJson(Patch));
              FSentEpoch := Patch.Epoch;
              FSentBlocks := Turn.Blocks;
              FSentFlagsValid := True;
              FSentBusy := View.Busy;
              FSentSending := View.Sending;
              FSentPlanRunning := View.PlanRunning;
              FSentPhase := View.Phase;
              FSentCanSend := View.CanSend;
              FSentCanSteer := View.CanSteer;
              FSentCanStop := View.CanStop;
            End;
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
  Finally
    FPumping := False;
  End;
End;

Procedure TAssistantMonitorBridge.PushPlan(Form: TProjectAssistantForm);
Var
  Paths, Captions: TStringList;
  View: TAssistantMonitorView;
  Rows: TAssistantMonitorPlanRows;
  Session: TMonitorSession;
  Epoch, Stamp: String;
  Cursor: Int64;
Begin
  If Not Assigned(Form) Then
    Exit;
  LockBridge;
  Try
    Session := FSession;
  Finally
    UnlockBridge;
  End;
  If Assigned(Session) Then
    Session.FlushLivePatch;
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Form.FillMonitorPlanChoices(Paths, Captions);
    Form.FillMonitorView(View);
    Form.FillMonitorPlan(Rows);
    Epoch := '';
    Cursor := 0;
    If Assigned(Session) Then
      Begin
        Epoch := Session.MirrorEpoch;
        Stamp := 'plan' + #1 + View.PlanPath + #1 + View.PlanTitle + #1 + BoolToStr(View.PlanRunning, True);
        If (Epoch <> '') And Session.CommitMirrorCursor(Stamp, Cursor) Then
          Begin
            SendJson(EncodeMonitorPlan(HostId, View.PlanPath, View.PlanTitle, View.PlanRunning, Rows, Paths, Captions,
              Epoch, Cursor));
            Session.NoteMirrorHanded(Cursor);
          End
        Else
          SendJson(EncodeMonitorPlan(HostId, View.PlanPath, View.PlanTitle, View.PlanRunning, Rows, Paths, Captions));
      End
    Else
      SendJson(EncodeMonitorPlan(HostId, View.PlanPath, View.PlanTitle, View.PlanRunning, Rows, Paths, Captions));
  Finally
    Captions.Free;
    Paths.Free;
  End;
End;

Procedure TAssistantMonitorBridge.PushTargets(Form: TProjectAssistantForm);
Var
  Paths, Captions: TStringList;
  Current: String;
Begin
  If Not Assigned(Form) Then
    Exit;
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Form.FillMonitorTargetChoices(Paths, Captions, Current);
    SendJson(EncodeMonitorTargets(HostId, Current, Paths, Captions));
  Finally
    Captions.Free;
    Paths.Free;
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
    Form.FillMonitorConversationChoices(Ids, Titles, Current, Truncated);
    SendJson(EncodeMonitorConversations(HostId, Current, Ids, Titles, Truncated));
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
          PushTargets(Form);
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
  Text, ModeText, Path, ArchiveId, ApiText: String;
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
        { An old stall Refresh must not build a snapshot on the IDE thread. }
        SendError(Id, MonitorHostBusyReason, 'The Project Assistant is busy.');
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
    If Command.Kind = Ord(mmkResume) Then
      Begin
        If Command.Cancelled Then
          Exit;
        { A modal is not a reason to answer host_busy. The timer retries after it closes. }
        If AssistantModalDepth > 0 Then
          Begin
            Command.Defer := True;
            Exit;
          End;
        Command.Claimed := True;
      End
    Else If Command.Cancelled Or (AssistantModalDepth > 0) Then
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
  If Command.Defer Then
    Exit;
  If SendBusy Then
    Begin
      SendError(Command.ClientId, MonitorHostBusyReason, 'The Project Assistant is busy.');
      Exit;
    End;
  If Not Command.Claimed Then
    Exit;
  If Command.Kind = Ord(mmkResume) Then
    Begin
      AnswerResume(Command.ClientId, Command.Payload);
      Exit;
    End;
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
