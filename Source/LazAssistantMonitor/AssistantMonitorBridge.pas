Unit AssistantMonitorBridge;

{ Main-thread command pump and session listener. The listener only enqueues.
  It does not build provider JSON and does not replace the form trace handler.
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
  Classes, SyncObjs, Forms, fpjson, WorkflowLog, AssistantSessionObserve, AssistantMonitorCodec,
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
    Done: PRTLEvent;
    RefCount: Integer;
    Procedure Execute;
    Procedure Retain;
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
    FSession: TMonitorSession;
    FGeneration: Integer;
    FStatusQueued: Boolean;
    FStatusDirty: Boolean;
    Procedure LockBridge;
    Procedure UnlockBridge;
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
    Procedure PushPlan(Form: TProjectAssistantForm);
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

Procedure TMonitorQueuedCommand.Retain;
Begin
  InterlockedIncrement(RefCount);
End;

Procedure TMonitorQueuedCommand.Release;
Begin
  If InterlockedDecrement(RefCount) = 0 Then
    Begin
      If Assigned(Done) Then
        RTLEventDestroy(Done);
      Done := Nil;
      Free;
    End;
End;

Procedure TMonitorQueuedCommand.Execute;
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
    If Assigned(Bridge) Then
      Bridge.LockBridge;
    Try
      Finished := True;
    Finally
      If Assigned(Bridge) Then
        Bridge.UnlockBridge;
    End;
    If Assigned(Done) Then
      RTLEventSetEvent(Done);
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
  FSession := Nil;
  FGeneration := 0;
End;

Destructor TAssistantMonitorBridge.Destroy;
Begin
  Detach;
  DoneCriticalSection(FLock);
  Inherited Destroy;
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
      Session.SetApprovalCloseHandler(@HandleApprovalClosed);
    End;
End;

Procedure TAssistantMonitorBridge.Detach;
Var
  Session: TMonitorSession;
Begin
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
      Session.SetApprovalCloseHandler(Nil);
    End;
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
  Transcript: TMonitorTranscript;
  ErrorText, Json: String;
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
  Transcript := Default(TMonitorTranscript);
  Transcript.TurnIndex := Turn.TurnIndex;
  Transcript.Revision := Session.NextTranscriptRevision(Turn.TurnIndex);
  Transcript.DurationMs := Turn.DurationMs;
  Transcript.Blocks := Turn.Blocks;
  If Not TryEncodeMonitorTranscript(HostId, Transcript, Json) Then
    Exit;
  Session.QueueTranscript(Turn.TurnIndex, Json);
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
        Index := -1;
        DecodeMonitorWorkOnPlan(PayloadJson, Index);
        Result := Form.RemoteWorkOnPlan(Index, ErrorText);
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
  SendBusy: Boolean;
Begin
  Command := TMonitorQueuedCommand.Create;
  Command.Kind := Kind;
  Command.ClientId := Id;
  Command.Payload := PayloadJson;
  Command.Cancelled := False;
  Command.Claimed := False;
  Command.BusySent := False;
  Command.Finished := False;
  Command.RefCount := 2;
  Command.Done := RTLEventCreate;
  LockBridge;
  Try
    Inc(FGeneration);
    Command.Generation := FGeneration;
  Finally
    UnlockBridge;
  End;
  Try
    TThread.Queue(Nil, @Command.Execute);
    RTLEventWaitFor(Command.Done, MonitorCommandWaitMs);
    SendBusy := False;
    LockBridge;
    Try
      If Not Command.Finished Then
        If Not Command.Claimed Then
          Begin
            Command.Cancelled := True;
            SendBusy := Not Command.BusySent;
            Command.BusySent := True;
          End;
    Finally
      UnlockBridge;
    End;
    If SendBusy Then
      SendError(Id, MonitorHostBusyReason, 'The Project Assistant is busy.');
  Finally
    Command.Release;
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
