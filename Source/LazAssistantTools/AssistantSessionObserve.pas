Unit AssistantSessionObserve;

{ Dormant session observer for an optional monitor package.
  A nil listener changes nothing. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs;

Type
  TAssistantSessionNoticeKind = (
    asnTranscript,
    asnPhase,
    asnMode,
    asnTarget,
    asnPlan,
    asnTasks,
    asnStatus,
    asnApproval,
    asnSession,
    asnError
  );

  TAssistantSessionListener = Procedure(Kind: TAssistantSessionNoticeKind) Of Object;

  TAssistantMonitorImage = Record
    Id: String;
    Name: String;
    Mime: String;
    Width: Integer;
    Height: Integer;
    DisplayPath: String;
    Missing: Boolean;
  End;

  TAssistantMonitorBlock = Record
    Kind: String;       { user, thinking, tool, answer, note, steer, subagent, worked }
    BlockId: String;
    Title: String;
    ToolName: String;
    ToolId: String;
    Body: String;
    Running: Boolean;
    Ok: Boolean;
    DurationMs: Integer;
    Images: Array Of TAssistantMonitorImage;
  End;

  TAssistantMonitorTurn = Record
    TurnIndex: Integer; { -2 matches LiveConversationMarker on the form; stored turns are >= 0 }
    Id: String;
    Mode: String;
    Prompt: String;
    Thinking: String;
    Response: String;
    ErrorText: String;
    CreatedAt: String;
    DurationMs: Integer;
    PromptPreview: String;
    Live: Boolean;
    Blocks: Array Of TAssistantMonitorBlock;
    Images: Array Of TAssistantMonitorImage;
  End;

  TAssistantMonitorPlanRow = Record
    Index: Integer;
    Level: Integer;
    Title: String;
    ParentTitle: String;
    Status: String;
    Actionable: Boolean;
  End;

  TAssistantMonitorTaskRow = Record
    Id: String;
    Title: String;
    Summary: String;
    Mode: String;
    Kind: String;       { prompt or format }
    Scope: String;
    CompileFirst: Boolean;
    Enabled: Boolean;
    NeedsNote: Boolean;
  End;

  TAssistantMonitorView = Record
    Available: Boolean;
    Busy: Boolean;
    Sending: Boolean;
    ModeLocked: Boolean;
    PlanRunning: Boolean;
    Mode: String;
    Phase: String;
    StatusText: String;
    Model: String;
    Backend: String;
    SignedIn: Boolean;
    ApprovalCaption: String;
    Effort: String;
    Skill: String;
    ContextText: String;
    TargetKind: String;
    TargetDisplay: String;
    TargetRoot: String;
    PlanPath: String;
    PlanTitle: String;
    CanSend: Boolean;
    CanSteer: Boolean;
    CanStop: Boolean;
    CanChangeMode: Boolean;
    RemoteApproval: Boolean;
    ErrorText: String;
  End;

  TAssistantApprovalNotice = Record
    Active: Boolean;
    ToolId: String;
    ToolName: String;
    Summary: String;
    ModeCaption: String;
    DecisionsAccepted: Boolean;
    { Close reason from ClearAssistantApproval. Empty on a publish or queue. }
    Reason: String;
  End;

  { aadNone means no answer is stored. A bare signal leaves this value.
    aadNone is not an allow. }
  TAssistantApprovalDecision = (
    aadNone,
    aadAllow,
    aadDeny,
    aadStopped);

/// Main thread only. Stores the listener under the lock and does not raise a notice.
Procedure SetAssistantSessionListener(Listener: TAssistantSessionListener);
/// True when a listener is stored. Reads the pointer under the lock.
Function AssistantSessionListenerAssigned: Boolean;
/// Main thread only. Returns False immediately when the listener is nil. Copies the method and calls it outside the lock.
Function AssistantSessionObserve(Kind: TAssistantSessionNoticeKind): Boolean;

/// Stores the notice, then notifies before return on the main thread. Any other thread queues.
Procedure PublishAssistantApproval(Const Notice: TAssistantApprovalNotice);
/// Stores the notice and always queues the notify, including when the caller is already on the main thread.
Procedure QueueAssistantApproval(Const Notice: TAssistantApprovalNotice);
/// Stores an inactive notice under the lock, including Reason, then notifies the same way as Publish.
Procedure ClearAssistantApproval(Const ToolId, Reason: String);
/// Copy of the stored notice. Empty and inactive until the first publish, queue, or clear.
Function CurrentAssistantApproval: TAssistantApprovalNotice;

/// Main-thread modal depth. A nil listener does not skip the counter.
Procedure BeginAssistantModal;
/// Decrements the modal depth. Does not go below zero.
Procedure EndAssistantModal;
/// Current modal depth. A value above zero means a queued command must not call the form.
Function AssistantModalDepth: Integer;

/// Stores the event and resets the stored decision to aadNone. A nil event is a no-op.
Procedure ArmAssistantApprovalWait(Event: PRTLEvent);
/// Writes only while the stored decision is aadNone. A later store leaves the first decision in place.
Procedure StoreAssistantApprovalDecision(Decision: TAssistantApprovalDecision);
/// Stored decision. aadNone means no answer is stored.
Function ReadAssistantApprovalDecision: TAssistantApprovalDecision;
/// Copies the event and sets it outside the lock. A nil event returns immediately. The signal carries no decision.
Procedure SignalAssistantApprovalWait;

Implementation

Uses
  WorkflowLog;

Type
  TAssistantSessionObserveHub = Class
  Public
    Procedure NotifyApproval;
  End;

Var
  ObserveLock: TRTLCriticalSection;
  ObserveHub: TAssistantSessionObserveHub;
  SessionListener: TAssistantSessionListener;
  ApprovalNotice: TAssistantApprovalNotice;
  ModalDepth: Integer;
  ApprovalEvent: PRTLEvent;
  ApprovalDecision: TAssistantApprovalDecision;

Function CopySessionListener: TAssistantSessionListener;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Result := SessionListener;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure CallSessionListener(Kind: TAssistantSessionNoticeKind);
Var
  Listener: TAssistantSessionListener;
Begin
  Listener := CopySessionListener;
  If Assigned(Listener) Then
    Listener(Kind);
End;

Procedure StoreApprovalNotice(Const Notice: TAssistantApprovalNotice);
Begin
  EnterCriticalSection(ObserveLock);
  Try
    ApprovalNotice := Notice;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure QueueApprovalNotify;
Begin
  TThread.Queue(Nil, @ObserveHub.NotifyApproval);
End;

Function RunningOnMainThread: Boolean;
Begin
  Result := GetCurrentThreadID = MainThreadID;
End;

Procedure NotifyApprovalNowOrQueue;
Begin
  If RunningOnMainThread Then
    CallSessionListener(asnApproval)
  Else
    QueueApprovalNotify;
End;

Procedure TAssistantSessionObserveHub.NotifyApproval;
Begin
  { A raise here is re-raised by CheckSynchronize into the IDE loop. }
  Try
    CallSessionListener(asnApproval);
  Except
    On E: Exception Do
      ReportPluginException('AssistantSessionObserve.NotifyApproval', E);
  End;
End;

Procedure SetAssistantSessionListener(Listener: TAssistantSessionListener);
Begin
  EnterCriticalSection(ObserveLock);
  Try
    SessionListener := Listener;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Function AssistantSessionListenerAssigned: Boolean;
Begin
  Result := Assigned(CopySessionListener);
End;

Function AssistantSessionObserve(Kind: TAssistantSessionNoticeKind): Boolean;
Var
  Listener: TAssistantSessionListener;
Begin
  Listener := CopySessionListener;
  If Not Assigned(Listener) Then
    Exit(False);
  Result := True;
  Listener(Kind);
End;

Procedure PublishAssistantApproval(Const Notice: TAssistantApprovalNotice);
Var
  Stored: TAssistantApprovalNotice;
Begin
  Stored := Notice;
  Stored.Reason := '';
  StoreApprovalNotice(Stored);
  NotifyApprovalNowOrQueue;
End;

Procedure QueueAssistantApproval(Const Notice: TAssistantApprovalNotice);
Var
  Stored: TAssistantApprovalNotice;
Begin
  Stored := Notice;
  Stored.Reason := '';
  StoreApprovalNotice(Stored);
  QueueApprovalNotify;
End;

Procedure ClearAssistantApproval(Const ToolId, Reason: String);
Var
  Notice: TAssistantApprovalNotice;
Begin
  Notice := Default(TAssistantApprovalNotice);
  Notice.Active := False;
  Notice.ToolId := ToolId;
  Notice.Reason := Reason;
  StoreApprovalNotice(Notice);
  NotifyApprovalNowOrQueue;
End;

Function CurrentAssistantApproval: TAssistantApprovalNotice;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Result := ApprovalNotice;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure BeginAssistantModal;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Inc(ModalDepth);
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure EndAssistantModal;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    If ModalDepth > 0 Then
      Dec(ModalDepth);
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Function AssistantModalDepth: Integer;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Result := ModalDepth;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure ArmAssistantApprovalWait(Event: PRTLEvent);
Begin
  If Not Assigned(Event) Then
    Exit;
  EnterCriticalSection(ObserveLock);
  Try
    ApprovalEvent := Event;
    ApprovalDecision := aadNone;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure StoreAssistantApprovalDecision(Decision: TAssistantApprovalDecision);
Begin
  EnterCriticalSection(ObserveLock);
  Try
    If ApprovalDecision = aadNone Then
      ApprovalDecision := Decision;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Function ReadAssistantApprovalDecision: TAssistantApprovalDecision;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Result := ApprovalDecision;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
End;

Procedure SignalAssistantApprovalWait;
Var
  Event: PRTLEvent;
Begin
  EnterCriticalSection(ObserveLock);
  Try
    Event := ApprovalEvent;
  Finally
    LeaveCriticalSection(ObserveLock);
  End;
  If Not Assigned(Event) Then
    Exit;
  RTLEventSetEvent(Event);
End;

Initialization

  InitCriticalSection(ObserveLock);
  ObserveHub := TAssistantSessionObserveHub.Create;
  ApprovalDecision := aadNone;
  ModalDepth := 0;
  ApprovalEvent := Nil;

Finalization

  If Assigned(ObserveHub) Then
    Begin
      Try
        TThread.RemoveQueuedEvents(Nil, @ObserveHub.NotifyApproval);
      Except
        On E: Exception Do
          ReportPluginException('AssistantSessionObserve.Finalization', E);
      End;
      FreeAndNil(ObserveHub);
    End;
  DoneCriticalSection(ObserveLock);

End.
