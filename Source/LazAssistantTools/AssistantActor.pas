Unit AssistantActor;

{ Session actor thread: Responses stream, tool rounds, steer drain, cancel (c) 2026 Michell Computing.

  Named Actor because the model message list is stored on the conversation turn. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantProtocol, AssistantSampler, AssistantEvents, AssistantService,
  AssistantConversation, AssistantHttps, AssistantImages, AssistantRecovery;

Type
  TAssistantActor = Class(TThread)
  Private
    FService: TAssistantService;
    FApiBase: String;
    FAccessToken: String;
    FModel: String;
    FReasoningEffort: String;
    FToolsJson: String;
    FOnToken: TAssistantStreamEvent;
    FOnTrace: TAssistantTraceNotify;
    FTraceLock: TRTLCriticalSection;
    FTraceQueue: Array Of TAssistantEvent;
    FEventsFile: String;
    FSteer: TAssistantSteerBuffer;
    FParser: TAssistantSseParser;
    FHttpControl: TObject;
    FHttpLock: TRTLCriticalSection;
    FSnapLock: TRTLCriticalSection;
    FContent: String;
    FThinking: String;
    FThinkingBeforeRound: String;
    FPhase: TAssistantPhase;
    FErrorText: String;
    FStatusText: String;
    FFinishEmitted: Boolean;
    FPlanWrites: Integer;
    FUseResponses: Boolean;
    FTriedResponses: Boolean;
    FResponseOutputJson: String;
    FResponsePrefix: String;
    FLoopIndex: Integer;
    FLastSnapTick: QWord;
    FPendingFinish: Boolean;
    FNotifyQueued: Boolean;
    FToolCalls: TSamplerToolCallArray;
    FPendingImageRefs: TAssistantImageRefArray;
    FServiceDetached: Boolean;
    FHttpFaultAttempt: Integer;
    FFaultSite: String;
    FFaultAttempt: Integer;
    FRecoveryStop: Boolean;
    FRecoveryStopText: String;
    FTerminalNoted: Boolean;
    FMutatingToolRan: Boolean;
    FActiveToolName: String;
    FHttpExceptionClass: String;
    FToolCallsCommitted: Boolean;
    FActiveToolIndex: Integer;
    FActiveToolRecorded: Boolean;
    FHadToolRound: Boolean;
    FQueryTruncated: Boolean;
    FQueryToolRoundCap: Boolean;
    FQueryContinue: Boolean;
    FQueryNote: String;
    FLocalContinuationCount: Integer;
    FLocalContinuationCap: Integer;
    { Snapshotted when the turn starts. The worker does not read the settings form. }
    FReconnectIntervalMs: QWord;
    FReconnectWaitMs: QWord;
    FCreditIntervalMs: QWord;
    FFaultRetryCap: Integer;
    Procedure SnapshotRecoverySettings;
    Procedure PostConnectionNote(Const Sentence: String);
    Procedure ApplyCreditWait(Const ErrorText, Body, RetryAfter: String);
    Procedure ApplyRateLimitWait(Const ErrorText, RetryAfter: String);
    Function ClassifyFault(Origin: TAssistantFaultOrigin; Const Area, ToolName, ErrorClass, ErrorText: String;
      HttpStatus, Attempt: Integer; OwnsTurn: Boolean; Const ResponseBody: String = ''): TAssistantRecovery;
    Function NextFaultAttempt(Const Site: String): Integer;
    Function ServiceWasDetached: Boolean;
    Procedure FaultSite(Out Origin: TAssistantFaultOrigin; Out Area, ToolName: String);
    Procedure PostTerminalStop(Const Area, ErrorClass, ErrorText: String);
    Procedure PostRecovery(Action: TAssistantRecoveryAction; Origin: TAssistantFaultOrigin;
      Const Area, ErrorClass, ErrorText: String);
    Function KeepRoundAfterFault(E: Exception): Boolean;
    Procedure SealUnansweredTools(Const ErrorClass, ErrorText: String);
    Procedure LogEvent(Kind: TAssistantEventKind; Const Text: String = '';
      Const ToolName: String = ''; Const ToolId: String = ''; Ok: Boolean = True;
      DurationMs: Integer = 0; Const AttachmentsJson: String = '');
    Procedure QueueTrace(Const Event: TAssistantEvent);
    Procedure NotifyTrace;
    Procedure EmitSnapshot(IsDone: Boolean; Const ErrorText: String; Force: Boolean);
    Procedure NoteReadyFacts(Truncated, ToolRoundCap: Boolean);
    Procedure DoContinuationQuery;
    Function RequestContinuation(Truncated, ToolRoundCap: Boolean): Boolean;
    Procedure InjectContinuation;
    { True when the turn should end. False when a continuation was injected. }
    Function FinishOrContinue(Truncated, ToolRoundCap: Boolean): Boolean;
    Procedure NotifyMain;
    Procedure SetPhase(Phase: TAssistantPhase);
    Procedure ApplyParserEvents(FromIndex: Integer);
    Function HttpsShouldStop: Boolean;
    Procedure AbortHttp;
    Function LockedService: TAssistantService;
    Procedure RunTools;
    Procedure RunOneTool(Const Call: TSamplerToolCall);
    Procedure FinishSpawnSlot(Const Call: TSamplerToolCall; Const RunId, KindName, ResultText,
      ErrorText: String; Ok: Boolean; DurationMs: Integer);
    Procedure RunSpawnRange(FromIndex, ToIndex: Integer);
    Function InjectPendingSteer(Svc: TAssistantService; Out VisibleNote: String): Boolean;
    Function DrainSteerIntoHistory: Boolean;
    Function BuildRoundJson(Out Url: String): String;
    Function ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
  Protected
    Procedure HttpsChunk(Const Chunk: String);
    Function DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
    Function PostRound(Const Url, RequestJson, Headers: String;
      Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean; Virtual;
    Function WaitForReconnect: Boolean; Virtual;
    { The wait DoHttpRound stored before WaitForReconnect. Tests read it without sleeping. }
    Function CurrentReconnectWaitMs: QWord;
    Procedure ExecuteTurn; Virtual;
    Procedure Execute; Override;
  Public
    Constructor Create(Service: TAssistantService; Const ApiBase, AccessToken, Model,
      ReasoningEffort, ToolsJson, EventsFile: String; OnToken: TAssistantStreamEvent);
    Destructor Destroy; Override;
    Procedure Cancel;
    Function EnqueueSteer(Const Text: String; Const ImageRefs: TAssistantImageRefArray): Boolean;
    Procedure Detach;
    Procedure DetachCallbacks;
    Property OnTrace: TAssistantTraceNotify Read FOnTrace Write FOnTrace;
  End;

Implementation

Uses
  AssistantTools, AssistantSubagents, AssistantImageAdapters, AssistantGeneratedImage, AssistantAccountUsage,
  AssistantTurnFinish, WorkflowLog;

Const
  MaxAskToolRounds = 12;
  MaxPlanToolRounds = 40;
  MaxBuildToolRounds = 80;
  SnapIntervalMs = 50;
  CancelWaitHint = 'Cancelled.';
  MaxToolEventChars = 4000;
  { After the IDE thread has begun a tool, give its own timeout time to finish. }
  IdeToolStopGraceMs = 5000;

Function MaxRoundsForSession(Svc: TAssistantService): Integer;
Begin
  If Assigned(Svc) And Svc.IsSubagentSession Then
    Result := MaxSubagentToolRounds
  Else If Assigned(Svc) Then
    Case Svc.ActiveMode Of
      amChat: Result := 1;
      amDocument: Result := MaxPlanToolRounds;
      amPlan: Result := MaxPlanToolRounds;
      amBuild: Result := MaxBuildToolRounds;
    Else
      Result := MaxAskToolRounds;
    End
  Else
    Result := MaxAskToolRounds;
End;

Function TrimSlash(Const Url: String): String;
Begin
  Result := Trim(Url);
  While (Length(Result) > 0) And (Result[Length(Result)] = '/') Do
    SetLength(Result, Length(Result) - 1);
End;

Procedure TAssistantActor.SnapshotRecoverySettings;
Begin
  { Config, not the settings form. A later change does not affect this turn. }
  FReconnectIntervalMs := AssistantReconnectIntervalMs;
  FReconnectWaitMs := FReconnectIntervalMs;
  FCreditIntervalMs := AssistantCreditIntervalMs;
  FLocalContinuationCap := AssistantAutomaticContinuationCap;
  FFaultRetryCap := AssistantFaultRetryCap(-1);
End;

Constructor TAssistantActor.Create(Service: TAssistantService; Const ApiBase, AccessToken, Model,
  ReasoningEffort, ToolsJson, EventsFile: String; OnToken: TAssistantStreamEvent);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FSnapLock);
  InitCriticalSection(FHttpLock);
  InitCriticalSection(FTraceLock);
  FService := Service;
  FApiBase := ApiBase;
  FAccessToken := AccessToken;
  FModel := Model;
  FReasoningEffort := ReasoningEffort;
  FToolsJson := ToolsJson;
  FEventsFile := EventsFile;
  FOnToken := OnToken;
  FSteer := TAssistantSteerBuffer.Create;
  FParser := TAssistantSseParser.Create;
  FHttpControl := Nil;
  FContent := '';
  FThinking := '';
  FPhase := apWaiting;
  FErrorText := '';
  FStatusText := '';
  FFinishEmitted := False;
  FPlanWrites := 0;
  FUseResponses := True;
  FTriedResponses := False;
  FResponseOutputJson := '';
  FResponsePrefix := '';
  FLoopIndex := 0;
  FLastSnapTick := 0;
  FPendingFinish := False;
  FNotifyQueued := False;
  SetLength(FToolCalls, 0);
  FServiceDetached := False;
  FHttpFaultAttempt := 0;
  FFaultSite := '';
  FFaultAttempt := 0;
  FRecoveryStop := False;
  FRecoveryStopText := '';
  FTerminalNoted := False;
  FMutatingToolRan := False;
  FActiveToolName := '';
  FHttpExceptionClass := '';
  FToolCallsCommitted := False;
  FActiveToolIndex := -1;
  FActiveToolRecorded := False;
  FHadToolRound := False;
  SnapshotRecoverySettings;
End;

Destructor TAssistantActor.Destroy;
Begin
  { Pending NotifyMain / NotifyTrace must not run after this object is gone.
    CheckSynchronize would re-raise that access violation on the IDE thread. }
  DiscardQueuedThreadMethods(Self);
  AbortHttp;
  FreeAndNil(FParser);
  FreeAndNil(FSteer);
  SetLength(FTraceQueue, 0);
  DoneCriticalSection(FTraceLock);
  DoneCriticalSection(FHttpLock);
  DoneCriticalSection(FSnapLock);
  Inherited Destroy;
End;

Procedure TAssistantActor.Cancel;
Begin
  Terminate;
  AbortHttp;
End;

Function TAssistantActor.EnqueueSteer(Const Text: String; Const ImageRefs: TAssistantImageRefArray): Boolean;
Var
  Note, Attachments: String;
  Refs: TAssistantImageRefArray;
  Svc: TAssistantService;
Begin
  Note := Trim(Text);
  SetLength(Refs, 0);
  { A steer does not change mode or tool permissions. A subagent cannot receive images. }
  Svc := LockedService;
  If Not (Assigned(Svc) And Svc.IsSubagentSession) Then
    Refs := LimitAssistantImageRefs(ImageRefs);
  Attachments := AssistantImageRefsToJson(Refs);
  Result := (Note <> '') Or (Attachments <> '');
  If Not Result Then Exit;
  FSteer.Enqueue(Note, Attachments);
  LogEvent(aekSteerQueued, Note, '', '', True, 0, Attachments);
End;

Procedure TAssistantActor.DetachCallbacks;
Begin
  EnterCriticalSection(FSnapLock);
  Try
    FOnToken := Nil;
    FOnTrace := Nil;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
End;

Procedure TAssistantActor.Detach;
Begin
  { Drop UI callbacks and the service pointer so an abandoned thread cannot
    mutate history after a new turn starts. In-flight calls already holding a
    local service reference finish against the still-alive object. }
  EnterCriticalSection(FSnapLock);
  Try
    FOnToken := Nil;
    FOnTrace := Nil;
    FService := Nil;
    FServiceDetached := True;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  AbortHttp;
End;

Function TAssistantActor.ServiceWasDetached: Boolean;
Begin
  EnterCriticalSection(FSnapLock);
  Try
    Result := FServiceDetached;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
End;

Function TAssistantActor.NextFaultAttempt(Const Site: String): Integer;
Begin
  If Site = FFaultSite Then
    Inc(FFaultAttempt)
  Else
    Begin
      FFaultSite := Site;
      FFaultAttempt := 1;
    End;
  Result := FFaultAttempt;
End;

Function TAssistantActor.ClassifyFault(Origin: TAssistantFaultOrigin; Const Area, ToolName, ErrorClass, ErrorText: String;
  HttpStatus, Attempt: Integer; OwnsTurn: Boolean; Const ResponseBody: String): TAssistantRecovery;
Var
  Fault: TAssistantFault;
Begin
  Fault := DefaultAssistantFault;
  Fault.Origin := Origin;
  Fault.Area := Area;
  Fault.ToolName := ToolName;
  Fault.ErrorClass := ErrorClass;
  Fault.ErrorText := ErrorText;
  Fault.HttpStatus := HttpStatus;
  Fault.Attempt := Attempt;
  Fault.AttemptCap := FFaultRetryCap;
  Fault.UserStopped := Terminated;
  Fault.ServiceGone := ServiceWasDetached;
  Fault.OwnsTurn := OwnsTurn;
  Fault.Detached := False;
  Fault.ResponseBody := ResponseBody;
  Result := ClassifyAssistantFault(Fault);
End;

Procedure TAssistantActor.FaultSite(Out Origin: TAssistantFaultOrigin; Out Area, ToolName: String);
Begin
  ToolName := FActiveToolName;
  If ToolName <> '' Then
    Begin
      Origin := afoTool;
      Area := 'ExecuteAssistantToolForMode';
    End
  Else
    Begin
      Origin := afoHttpRound;
      Area := 'TAssistantActor.DoHttpRound';
      ToolName := '';
    End;
End;

Procedure TAssistantActor.PostTerminalStop(Const Area, ErrorClass, ErrorText: String);
Begin
  { One note. A later fault must not retry and must not post a second recipe. }
  If FTerminalNoted Or FFinishEmitted Then
    Exit;
  FTerminalNoted := True;
  FRecoveryStop := True;
  FRecoveryStopText := AssistantRecoveryStopNote(Area, ErrorClass, ErrorText);
  EmitSnapshot(True, FRecoveryStopText, True);
  LogEvent(aekError, FRecoveryStopText);
End;

Procedure TAssistantActor.PostRecovery(Action: TAssistantRecoveryAction; Origin: TAssistantFaultOrigin;
  Const Area, ErrorClass, ErrorText: String);
Var
  Sentence: String;
Begin
  { Once per decision. The 50 ms poll must not call this. }
  If FTerminalNoted Or Terminated Or (Action = araStop) Then
    Exit;
  Sentence := AssistantRecoveryProgressNote(Action, Origin, Area, ErrorClass, ErrorText);
  If Sentence = '' Then
    Exit;
  EmitSnapshot(False, Sentence, True);
  LogEvent(aekRecovery, Sentence);
End;

Procedure TAssistantActor.PostConnectionNote(Const Sentence: String);
Begin
  If FTerminalNoted Or Terminated Or (Sentence = '') Then
    Exit;
  EmitSnapshot(False, Sentence, True);
  LogEvent(aekRecovery, Sentence);
End;

Procedure TAssistantActor.ApplyCreditWait(Const ErrorText, Body, RetryAfter: String);
Var
  Snapshot: TAccountUsageSnapshot;
  RetryAt: TDateTime;
  IntervalMs: QWord;
Begin
  If Not LastAccountUsageSnapshot(Snapshot) Then
    ClearAccountUsageSnapshot(Snapshot);
  IntervalMs := FCreditIntervalMs;
  FReconnectWaitMs := AssistantCreditWaitMs(ErrorText, Body, RetryAfter, Snapshot.HasReset, Snapshot.ResetsAt,
    IntervalMs, Now, RetryAt);
  PostConnectionNote(AssistantCreditWaitNote(ErrorText, RetryAt));
  WorkflowLogger.Warning('AssistantActor',
    Format('Waiting for credits until %s: %s', [FormatDateTime('yyyy-mm-dd hh:nn', RetryAt), ErrorText]));
End;

Procedure TAssistantActor.ApplyRateLimitWait(Const ErrorText, RetryAfter: String);
Begin
  FReconnectWaitMs := AssistantRateLimitWaitMs(RetryAfter, FReconnectIntervalMs, Now);
  If FReconnectWaitMs = 0 Then
    FReconnectWaitMs := FReconnectIntervalMs;
  PostConnectionNote(AssistantRateLimitWaitNote(ErrorText));
  WorkflowLogger.Warning('AssistantActor',
    Format('Rate limited, waiting %d seconds: %s', [FReconnectWaitMs Div 1000, ErrorText]));
End;

Function TAssistantActor.KeepRoundAfterFault(E: Exception): Boolean;
Var
  Decision: TAssistantRecovery;
  Origin: TAssistantFaultOrigin;
  Area, ToolName: String;
Begin
  Result := False;
  If FTerminalNoted Or FFinishEmitted Then
    Exit;
  If Not Assigned(E) Then
    Exit;
  FaultSite(Origin, Area, ToolName);
  Decision := ClassifyFault(Origin, Area, ToolName, E.ClassName, E.Message, 0, NextFaultAttempt(Area), True);
  Case Decision.Action Of
    araIgnore:
      Begin
        If Terminated Then
          EmitSnapshot(True, CancelWaitHint, True)
        Else
          EmitSnapshot(True, '', True);
      End;
    araStop:
      PostTerminalStop(Area, E.ClassName, E.Message);
    araRetryLastAction, araContinueTurn:
      Begin
        If FTerminalNoted Then
          Exit;
        If Origin = afoTool Then
          SealUnansweredTools(E.ClassName, E.Message);
        FActiveToolName := '';
        PostRecovery(Decision.Action, Origin, Area, E.ClassName, E.Message);
        Result := True;
      End;
  End;
End;

Procedure TAssistantActor.SealUnansweredTools(Const ErrorClass, ErrorText: String);
Var
  Svc: TAssistantService;
  I, FromIndex: Integer;
  Note: String;
Begin
  If Not FToolCallsCommitted Then
    Exit;
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  Note := 'Error: ' + AssistantRecoveryToolError('ExecuteAssistantToolForMode', ErrorClass, ErrorText);
  FromIndex := 0;
  If FActiveToolIndex >= 0 Then
    FromIndex := FActiveToolIndex;
  If FActiveToolRecorded Then
    Inc(FromIndex);
  For I := FromIndex To High(FToolCalls) Do
    If (FToolCalls[I].Id <> '') And (FToolCalls[I].Name <> '') Then
      Try
        Svc.AddToolResult(FToolCalls[I].Id, Note);
      Except
        On Inner: Exception Do
          Exit;
      End;
End;

Function TAssistantActor.LockedService: TAssistantService;
Begin
  EnterCriticalSection(FSnapLock);
  Try
    Result := FService;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
End;

Procedure TAssistantActor.AbortHttp;
Begin
  { Hold FHttpLock across Abort so the worker cannot free the control until
    Terminate / InternetCloseHandle has been issued. }
  EnterCriticalSection(FHttpLock);
  Try
    If Assigned(FHttpControl) Then
      Try
        THttpsStreamControl(FHttpControl).Abort;
      Except
      End;
  Finally
    LeaveCriticalSection(FHttpLock);
  End;
End;

Function TraceKindForUi(Kind: TAssistantEventKind): Boolean;
Begin
  Result := Kind In [aekTurnStarted, aekLoopStarted, aekToolStarted, aekToolCompleted,
    aekSteerQueued, aekInterjected, aekSubagentStarted, aekSubagentProgress,
    aekSubagentCompleted, aekTurnEnded, aekRecovery];
End;

Procedure TAssistantActor.QueueTrace(Const Event: TAssistantEvent);
Var
  N: Integer;
Begin
  If Not Assigned(FOnTrace) Then
    Exit;
  EnterCriticalSection(FTraceLock);
  Try
    N := Length(FTraceQueue);
    SetLength(FTraceQueue, N + 1);
    FTraceQueue[N] := Event;
  Finally
    LeaveCriticalSection(FTraceLock);
  End;
  Try
    Queue(@NotifyTrace);
  Except
    On E: Exception Do
      Begin
        ReportPluginException('TAssistantActor.QueueTrace', E);
        If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.QueueTrace', '', E.ClassName, E.Message, 0, 1,
          False).Action <> araIgnore Then
          Exit;
      End;
  End;
End;

Procedure TAssistantActor.NotifyTrace;
Var
  Batch: Array Of TAssistantEvent;
  I: Integer;
  Cb: TAssistantTraceNotify;
Begin
  { Whole method: a raise here is re-raised by CheckSynchronize into the Qt event loop. }
  Try
    Cb := FOnTrace;
    EnterCriticalSection(FTraceLock);
    Try
      Batch := Copy(FTraceQueue, 0, Length(FTraceQueue));
      SetLength(FTraceQueue, 0);
    Finally
      LeaveCriticalSection(FTraceLock);
    End;
    If Not Assigned(Cb) Then
      Exit;
    For I := 0 To High(Batch) Do
      Try
        Cb(Batch[I]);
      Except
        On E: Exception Do
          Begin
            ReportPluginException('TAssistantActor.NotifyTrace', E);
            If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.NotifyTrace', '', E.ClassName, E.Message,
              0, 1, False).Action <> araIgnore Then
              Exit;
          End;
      End;
  Except
    On E: Exception Do
      Begin
        ReportPluginException('TAssistantActor.NotifyTrace', E);
        If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.NotifyTrace', '', E.ClassName, E.Message, 0, 1,
          False).Action <> araIgnore Then
          Exit;
      End;
  End;
End;

Procedure TAssistantActor.LogEvent(Kind: TAssistantEventKind; Const Text: String;
  Const ToolName: String; Const ToolId: String; Ok: Boolean; DurationMs: Integer;
  Const AttachmentsJson: String);
Var
  Event: TAssistantEvent;
Begin
  Event := Default(TAssistantEvent);
  Event.Kind := Kind;
  Event.Phase := FPhase;
  Event.Text := Text;
  Event.ToolName := ToolName;
  Event.ToolId := ToolId;
  Event.LoopIndex := FLoopIndex;
  Event.Ok := Ok;
  Event.DurationMs := DurationMs;
  Event.AttachmentsJson := AttachmentsJson;
  AppendAssistantEvent(FEventsFile, Event);
  If TraceKindForUi(Kind) Then
    QueueTrace(Event);
End;

Procedure TAssistantActor.NotifyMain;
Var
  Content, Thinking, Err: String;
  Done: Boolean;
  Cb: TAssistantStreamEvent;
Begin
  { Whole method: a raise here is re-raised by CheckSynchronize into the Qt event loop. }
  Try
    EnterCriticalSection(FSnapLock);
    Try
      Content := FContent;
      Thinking := FThinking;
      Done := FPendingFinish;
      FPendingFinish := False;
      { Allow a later EmitSnapshot (including finish) to queue again while Cb runs. }
      FNotifyQueued := False;
      { Live snapshots carry a status string on the ErrorText slot; only a finished
        snapshot may report a terminal error. Progress text must not leak into finish. }
      If Done Then
        Err := FErrorText
      Else
        Err := FStatusText;
      Cb := FOnToken;
    Finally
      LeaveCriticalSection(FSnapLock);
    End;
    If Assigned(Cb) Then
      Try
        Cb(Content, Thinking, Done, Err);
      Except
        On E: Exception Do
          Begin
            ReportPluginException('TAssistantActor.NotifyMain', E);
            If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.NotifyMain', '', E.ClassName, E.Message, 0, 1,
              False).Action <> araIgnore Then
              Exit;
          End;
      End;
  Except
    On E: Exception Do
      Begin
        ReportPluginException('TAssistantActor.NotifyMain', E);
        If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.NotifyMain', '', E.ClassName, E.Message, 0, 1,
          False).Action <> araIgnore Then
          Exit;
      End;
  End;
End;

Procedure TAssistantActor.NoteReadyFacts(Truncated, ToolRoundCap: Boolean);
Var
  Svc: TAssistantService;
Begin
  Svc := LockedService;
  If Assigned(Svc) Then
    Svc.NoteTurnFinishFacts(Truncated, ToolRoundCap, FHadToolRound);
End;

Procedure TAssistantActor.DoContinuationQuery;
Var
  Svc: TAssistantService;
  Facts: TAssistantTurnFinishFacts;
  Answer: TAssistantContinuation;
Begin
  FQueryContinue := False;
  FQueryNote := '';
  Svc := LockedService;
  If Assigned(Svc) And Assigned(Svc.OnContinuationQuery) Then
    Begin
      FQueryContinue := Svc.OnContinuationQuery(FQueryTruncated, FQueryToolRoundCap, FHadToolRound, FContent);
      Exit;
    End;
  Facts := DefaultAssistantTurnFinishFacts;
  Facts.Truncated := FQueryTruncated;
  Facts.ToolRoundCap := FQueryToolRoundCap;
  Facts.HadToolRound := FHadToolRound;
  Facts.AssistantText := FContent;
  Answer := AssistantDecideContinuation(Facts, Terminated, FTerminalNoted, FLocalContinuationCount,
    FLocalContinuationCap, '');
  FQueryNote := Answer.Note;
  FQueryContinue := Answer.ContinueTurn And (Not Terminated) And (Not FTerminalNoted);
  If FQueryContinue Then
    Inc(FLocalContinuationCount);
End;

Function TAssistantActor.RequestContinuation(Truncated, ToolRoundCap: Boolean): Boolean;
Begin
  Result := False;
  If Terminated Or FTerminalNoted Or FFinishEmitted Then
    Exit;
  FQueryTruncated := Truncated;
  FQueryToolRoundCap := ToolRoundCap;
  FQueryContinue := False;
  FQueryNote := '';
  Try
    Synchronize(@DoContinuationQuery);
  Except
    On E: Exception Do
      Begin
        ReportPluginException('TAssistantActor.RequestContinuation', E);
        FQueryContinue := False;
      End;
  End;
  If Terminated Then
    FQueryContinue := False;
  If FQueryNote <> '' Then
    LogEvent(aekRecovery, FQueryNote);
  Result := FQueryContinue;
End;

Procedure TAssistantActor.InjectContinuation;
Var
  Svc: TAssistantService;
Begin
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  { A no-tool reply is not in history yet. Tool rounds already stored their text. }
  If (Not FToolCallsCommitted) And (Trim(FContent) <> '') Then
    Svc.AddMessage(amrAssistant, FContent);
  Svc.AddMessage(amrUser, AssistantContinuationInstruction);
End;

Function TAssistantActor.FinishOrContinue(Truncated, ToolRoundCap: Boolean): Boolean;
Begin
  { True: emit Ready. False: another model round in this same turn. }
  Result := True;
  If Terminated Or FTerminalNoted Or FFinishEmitted Then
    Exit;
  If Not RequestContinuation(Truncated, ToolRoundCap) Then
    Exit;
  InjectContinuation;
  LogEvent(aekLoopStarted, 'continuation');
  EmitSnapshot(False, 'Waiting for model…', True);
  Result := False;
End;

Procedure TAssistantActor.EmitSnapshot(IsDone: Boolean; Const ErrorText: String; Force: Boolean);
Var
  NowTick: QWord;
  NeedQueue: Boolean;
Begin
  If Terminated And (Not IsDone) Then
    Exit;
  If IsDone Then
    Begin
      If FFinishEmitted Then
        Exit;
      FFinishEmitted := True;
    End
  Else If Not Force Then
    Begin
      NowTick := GetTickCount64;
      If (FLastSnapTick > 0) And (NowTick - FLastSnapTick < SnapIntervalMs) Then
        Exit;
      FLastSnapTick := NowTick;
    End;
  NeedQueue := False;
  EnterCriticalSection(FSnapLock);
  Try
    If IsDone Then
      FErrorText := ErrorText
    Else If ErrorText <> '' Then
      FStatusText := ErrorText;
    FPendingFinish := FPendingFinish Or IsDone;
    If Not FNotifyQueued Then
      Begin
        FNotifyQueued := True;
        NeedQueue := True;
      End;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  If NeedQueue Then
    Try
      Queue(@NotifyMain);
    Except
      On E: Exception Do
        Begin
          ReportPluginException('TAssistantActor.EmitSnapshot', E);
          If ClassifyFault(afoCallbackAfterDetach, 'TAssistantActor.EmitSnapshot', '', E.ClassName, E.Message, 0, 1,
            False).Action <> araIgnore Then
            Exit;
        End;
    End;
End;

Procedure TAssistantActor.SetPhase(Phase: TAssistantPhase);
Begin
  If FPhase = Phase Then
    Exit;
  FPhase := Phase;
  LogEvent(aekPhaseChanged, AssistantPhaseName(Phase));
End;

Procedure TAssistantActor.ApplyParserEvents(FromIndex: Integer);
Var
  I: Integer;
  Event: TSamplerEvent;
Begin
  For I := FromIndex To FParser.EventCount - 1 Do
    Begin
      Event := FParser.GetEvent(I);
      Case Event.Kind Of
        sekThoughtDelta:
          Begin
            SetPhase(apThinking);
            FThinking := FThinkingBeforeRound + FParser.Thinking;
            EmitSnapshot(False, 'Thinking…', False);
          End;
        sekContentDelta:
          Begin
            SetPhase(apStreaming);
            FContent := FParser.Content;
            EmitSnapshot(False, 'Streaming…', False);
          End;
      Else
        { Started / tool deltas / completed handled from parser accumulators. }
      End;
    End;
End;

Procedure TAssistantActor.HttpsChunk(Const Chunk: String);
Var
  FromIndex: Integer;
Begin
  Try
    If Terminated Then
      Exit;
    If Length(FResponsePrefix) < 16384 Then
      FResponsePrefix := FResponsePrefix + Copy(Chunk, 1, 16384 - Length(FResponsePrefix));
    FromIndex := FParser.EventCount;
    FParser.Feed(Chunk);
    ApplyParserEvents(FromIndex);
  Except
    On E: EAbort Do
      Raise;
    On E: Exception Do
      Begin
        { Stay on the worker. The log is the record; re-raise the same class so the site can classify it. }
        ReportPluginException('TAssistantActor.HttpsChunk', E);
        FHttpExceptionClass := E.ClassName;
        Raise;
      End;
  End;
End;

Function TAssistantActor.HttpsShouldStop: Boolean;
Begin
  Result := Terminated;
End;

Function TAssistantActor.PostRound(Const Url, RequestJson, Headers: String;
  Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean;
Begin
  Result := HttpsPostJsonStream(Url, RequestJson, Headers, @HttpsChunk, @HttpsShouldStop,
    Control, Code, ErrorText);
End;

Function TAssistantActor.CurrentReconnectWaitMs: QWord;
Begin
  Result := FReconnectWaitMs;
End;

Function TAssistantActor.WaitForReconnect: Boolean;
Var
  StartTick, WaitMs: QWord;
Begin
  WaitMs := FReconnectWaitMs;
  StartTick := GetTickCount64;
  While (Not Terminated) And (GetTickCount64 - StartTick < WaitMs) Do
    Sleep(50);
  Result := Not Terminated;
End;

Function TAssistantActor.DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
Var
  Code: Integer;
  Headers, LastErr, RetryAfter: String;
  Control: THttpsStreamControl;
  Svc: TAssistantService;
  Decision: TAssistantRecovery;
Begin
  Result := False;
  ErrorText := '';
  LastErr := '';
  Code := 0;
  FHttpFaultAttempt := 0;
  Headers := 'Authorization: Bearer ' + FAccessToken;
  While Not Terminated Do
    Begin
      If Terminated Then
        Begin
          ErrorText := CancelWaitHint;
          If ClassifyFault(afoCancel, 'TAssistantActor.DoHttpRound', '', '', ErrorText, 0, 1, True).Action <>
            araRetryLastAction Then
            Exit;
        End;
      Code := 0;
      ErrorText := '';
      RetryAfter := '';
      FHttpExceptionClass := '';
      FParser.Reset;
      { Discard only the interrupted attempt, retaining completed tool rounds. }
      FContent := '';
      FThinking := FThinkingBeforeRound;
      SetLength(FToolCalls, 0);
      FResponseOutputJson := '';
      FResponsePrefix := '';
      Control := THttpsStreamControl.Create;
      EnterCriticalSection(FHttpLock);
      Try
        FHttpControl := Control;
      Finally
        LeaveCriticalSection(FHttpLock);
      End;
      Try
        Try
          If Not PostRound(Url, RequestJson, Headers, Control, Code, ErrorText) Then
            Begin
              If Terminated And (ErrorText = '') Then
                ErrorText := CancelWaitHint;
            End
          Else If Terminated Then
            ErrorText := CancelWaitHint
          Else If (Code < 200) Or (Code >= 300) Then
            Begin
              If ErrorText = '' Then
                ErrorText := Format('HTTP %d', [Code])
              Else
                ErrorText := Format('HTTP %d: %s', [Code, Copy(Trim(ErrorText), 1, 400)]);
              LastErr := HttpsResponseErrorMessage(FResponsePrefix);
              If LastErr <> '' Then ErrorText := Format('HTTP %d: %s', [Code, LastErr]);
            End
          Else If FParser.Incomplete Or FParser.Completed Then
            Begin
              { response.incomplete and finish_reason length are a truncated reply, not a turn error. }
              If FParser.Thinking <> '' Then
                FThinking := FThinkingBeforeRound + FParser.Thinking;
              FContent := FParser.Content;
              FResponseOutputJson := FParser.OutputJson;
              If FParser.Completed Then
                FToolCalls := FParser.ToolCalls
              Else
                SetLength(FToolCalls, 0);
              If FParser.UsageReported Then
                Begin
                  Svc := LockedService;
                  If Assigned(Svc) Then
                    Svc.NoteReportedUsage(FParser.InputTokens, FParser.OutputTokens, FParser.ReasoningTokens,
                      FParser.HasReasoning);
                End;
              FHttpFaultAttempt := 0;
              Result := True;
              Exit;
            End
          Else If FParser.Failed Then
            Begin
              ErrorText := FParser.ErrorText;
              If ErrorText = '' Then
                ErrorText := 'response.failed';
            End
          Else
            ErrorText := 'Response stream ended before completion; no tools were executed.';
        Except
          On E: Exception Do
            Begin
              ReportPluginException('TAssistantActor.DoHttpRound', E);
              FHttpExceptionClass := E.ClassName;
              If Terminated Then
                ErrorText := CancelWaitHint
              Else If E.Message <> '' Then
                ErrorText := E.Message
              Else
                ErrorText := E.ClassName;
            End;
        End;
      Finally
        RetryAfter := Control.ResponseRetryAfter;
        EnterCriticalSection(FHttpLock);
        Try
          FHttpControl := Nil;
        Finally
          LeaveCriticalSection(FHttpLock);
        End;
        Control.Free;
      End;
      If Terminated Or (ErrorText = CancelWaitHint) Then
        Begin
          ErrorText := CancelWaitHint;
          If ClassifyFault(afoCancel, 'TAssistantActor.DoHttpRound', '', '', ErrorText, Code, 1, True).Action <>
            araRetryLastAction Then
            Exit;
        End;
      Decision := ClassifyFault(afoHttpRound, 'TAssistantActor.DoHttpRound', '', '', ErrorText, Code,
        FHttpFaultAttempt + 1, True, FResponsePrefix);
      If Decision.Action <> araRetryLastAction Then
        Exit;
      Case Decision.HttpWait Of
        ahwCredits:
          Begin
            { No attempt cap. The turn stays here, so the form does not finish the reply or stop the plan. }
            ApplyCreditWait(ErrorText, FResponsePrefix, RetryAfter);
            If Not WaitForReconnect Then
              Break;
            PostConnectionNote(AssistantReconnectResumeNote);
          End;
        ahwRateLimit:
          Begin
            ApplyRateLimitWait(ErrorText, RetryAfter);
            If Not WaitForReconnect Then
              Break;
            PostConnectionNote(AssistantReconnectResumeNote);
          End;
        ahwConnection:
          Begin
            { No attempt cap. One note at the start of the wait, not on the 50 ms sleep. }
            FReconnectWaitMs := FReconnectIntervalMs;
            PostConnectionNote(AssistantReconnectWaitNote(ErrorText));
            WorkflowLogger.Warning('AssistantActor',
              Format('Reconnecting in %d seconds: %s', [FReconnectWaitMs Div 1000, ErrorText]));
            If Not WaitForReconnect Then
              Break;
            PostConnectionNote(AssistantReconnectResumeNote);
          End;
      Else
        Begin
          PostRecovery(araRetryLastAction, afoHttpRound, 'TAssistantActor.DoHttpRound', FHttpExceptionClass, ErrorText);
          FHttpFaultAttempt := FHttpFaultAttempt + 1;
        End;
      End;
    End;
  ErrorText := CancelWaitHint;
End;

Function TAssistantActor.ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
Var
  E: String;
Begin
  E := LowerCase(ErrorText);
  Result := (Pos('http 404', E) > 0) Or (Pos('http 405', E) > 0) Or
    (Pos('http 501', E) > 0);
End;

Type
  { One queued IDE-tool invocation. Independent of the actor so a timed-out
    callback cannot write into the next tool's fields or run after abandon. }
  TIdeToolDispatch = Class
  Private
    FLock: TRTLCriticalSection;
    FAbandoned: Boolean;
    FDone: Boolean;
    FRefCount: Integer;
    FName: String;
    FArgs: String;
    FMode: TAssistantMode;
    FOk: Boolean;
    FResultText: String;
    FErrorText: String;
    FImageRefs: TAssistantImageRefArray;
    FWorker: TThread;
    FStarted: Boolean;
    FStopFlag: LongInt;
    FFaulted: Boolean;
    FFaultClass: String;
    FFaultMessage: String;
    Procedure Release;
    Procedure MarkFailed(Const Area, ErrorClass, ErrorText: String);
    Procedure EnsureDone;
  Public
    Constructor Create(Const ToolName, ArgumentsJson: String; ToolMode: TAssistantMode; AbortWorker: TThread);
    Destructor Destroy; Override;
    Procedure ExecuteOnMain;
    Function HasStarted: Boolean;
    Function HasFailed: Boolean;
    Function WaitUntilDone(TimeoutMs: QWord): Boolean;
    Procedure CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String);
    Procedure CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String;
      Out ImageRefs: TAssistantImageRefArray);
    Function TookFault(Out FaultClass, FaultMessage: String): Boolean;
  End;

Constructor TIdeToolDispatch.Create(Const ToolName, ArgumentsJson: String; ToolMode: TAssistantMode; AbortWorker: TThread);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FName := ToolName;
  FArgs := ArgumentsJson;
  FMode := ToolMode;
  FWorker := AbortWorker;
  FOk := False;
  FResultText := '';
  FErrorText := '';
  FAbandoned := False;
  FDone := False;
  FStarted := False;
  FStopFlag := 0;
  FFaulted := False;
  FFaultClass := '';
  FFaultMessage := '';
  { Waiter + queued callback. Last Release Frees. }
  FRefCount := 2;
End;

Destructor TIdeToolDispatch.Destroy;
Begin
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TIdeToolDispatch.Release;
Var
  DoFree: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Dec(FRefCount);
    DoFree := FRefCount <= 0;
  Finally
    LeaveCriticalSection(FLock);
  End;
  If DoFree Then
    Free;
End;

Procedure TIdeToolDispatch.MarkFailed(Const Area, ErrorClass, ErrorText: String);
Var
  Note: String;
Begin
  Note := AssistantRecoveryToolError(Area, ErrorClass, ErrorText);
  If Note = '' Then
    Note := 'The tool failed before it could run.';
  Try
    EnterCriticalSection(FLock);
    Try
      FOk := False;
      FFaulted := True;
      If FFaultClass = '' Then
        FFaultClass := ErrorClass;
      If FFaultMessage = '' Then
        FFaultMessage := ErrorText;
      If FErrorText = '' Then
        FErrorText := Note;
      FResultText := '';
      FDone := True;
    Finally
      LeaveCriticalSection(FLock);
    End;
  Except
    FOk := False;
    FFaulted := True;
    If FErrorText = '' Then
      FErrorText := Note;
    FDone := True;
  End;
End;

Procedure TIdeToolDispatch.EnsureDone;
Begin
  Try
    EnterCriticalSection(FLock);
    Try
      If FDone Or FFaulted Then
        Begin
          If FFaulted And (FErrorText = '') Then
            FErrorText := AssistantRecoveryToolError('TIdeToolDispatch.ExecuteOnMain', FFaultClass,
              'The tool failed before it could run.');
          FDone := True;
          Exit;
        End;
      { A fault before the inner call must not leave the waiter blocked until timeout. }
      FOk := False;
      FFaulted := True;
      If FFaultClass = '' Then
        FFaultClass := 'Exception';
      If FErrorText = '' Then
        FErrorText := AssistantRecoveryToolError('TIdeToolDispatch.ExecuteOnMain', FFaultClass,
          'The tool failed before it could run.');
      FDone := True;
    Finally
      LeaveCriticalSection(FLock);
    End;
  Except
    FOk := False;
    FFaulted := True;
    If FErrorText = '' Then
      FErrorText := 'TIdeToolDispatch.ExecuteOnMain: Exception: The tool failed before it could run.';
    FDone := True;
  End;
End;

Procedure TIdeToolDispatch.ExecuteOnMain;
Var
  SkipRun, LocalFaulted: Boolean;
  ToolOk: Boolean;
  ToolResult, ToolError, LocalFaultClass, LocalFaultMessage: String;
  ImageRefs: TAssistantImageRefArray;
Begin
  { A raise escapes into CheckSynchronize and can Halt the IDE. }
  LocalFaulted := False;
  LocalFaultClass := '';
  LocalFaultMessage := '';
  Try
    Try
      SkipRun := False;
      EnterCriticalSection(FLock);
      Try
        If FAbandoned Or (FStopFlag <> 0) Then
          SkipRun := True
        Else
          FStarted := True;
      Finally
        LeaveCriticalSection(FLock);
      End;
      If SkipRun Then
        Begin
          EnterCriticalSection(FLock);
          Try
            If Not FDone Then
              Begin
                FOk := False;
                If FErrorText = '' Then
                  FErrorText := 'The tool did not start.';
                FDone := True;
              End;
          Finally
            LeaveCriticalSection(FLock);
          End;
        End
      Else
        Begin
          ToolOk := False;
          ToolResult := '';
          ToolError := '';
          ImageRefs := Nil;
          { This threadvar is the IDE thread's. The worker keeps its own binding. }
          BindToolAbortThread(FWorker);
          BindToolStopFlag(@FStopFlag);
          Try
            Try
              ToolOk := ExecuteAssistantToolForMode(FName, FArgs, FMode, ToolResult, ToolError, ImageRefs);
            Except
              On E: Exception Do
                Begin
                  ReportPluginException('TIdeToolDispatch.ExecuteOnMain', E);
                  LocalFaulted := True;
                  LocalFaultClass := E.ClassName;
                  LocalFaultMessage := E.Message;
                  ToolOk := False;
                  ToolResult := '';
                  ToolError := AssistantRecoveryToolError('ExecuteAssistantToolForMode', E.ClassName, E.Message);
                End;
            End;
          Finally
            EnterCriticalSection(FLock);
            Try
              FOk := ToolOk;
              FResultText := ToolResult;
              FImageRefs := ImageRefs;
              FFaulted := LocalFaulted;
              If LocalFaultClass <> '' Then
                FFaultClass := LocalFaultClass;
              If LocalFaultMessage <> '' Then
                FFaultMessage := LocalFaultMessage;
              If ToolError <> '' Then
                FErrorText := ToolError
              Else If LocalFaulted And (FErrorText = '') Then
                FErrorText := AssistantRecoveryToolError('ExecuteAssistantToolForMode', LocalFaultClass,
                  'The tool failed.');
              FDone := True;
            Finally
              LeaveCriticalSection(FLock);
            End;
            UnbindToolAbortThread;
          End;
        End;
    Except
      On E: Exception Do
        Begin
          ReportPluginException('TIdeToolDispatch.ExecuteOnMain', E);
          MarkFailed('TIdeToolDispatch.ExecuteOnMain', E.ClassName, E.Message);
        End;
    Else
      MarkFailed('TIdeToolDispatch.ExecuteOnMain', 'Exception', 'The tool failed before it could run.');
    End;
  Finally
    EnsureDone;
    Release;
  End;
End;

Function TIdeToolDispatch.TookFault(Out FaultClass, FaultMessage: String): Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FFaulted;
    FaultClass := FFaultClass;
    FaultMessage := FFaultMessage;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TIdeToolDispatch.HasFailed: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FFaulted Or (FDone And (Not FOk) And (FErrorText <> ''));
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TIdeToolDispatch.HasStarted: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FStarted;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TIdeToolDispatch.WaitUntilDone(TimeoutMs: QWord): Boolean;
Var
  StartTick, StopTick, NowTick: QWord;
  StopNow: Boolean;
Begin
  Result := False;
  StartTick := GetTickCount64;
  StopTick := 0;
  Repeat
    StopNow := ToolsShouldStop;
    NowTick := GetTickCount64;
    EnterCriticalSection(FLock);
    Try
      If FDone Or FFaulted Then
        Begin
          { Already failed. Do not sit until timeout and then abandon it. }
          If FFaulted And (FErrorText = '') Then
            FErrorText := AssistantRecoveryToolError('TIdeToolDispatch.ExecuteOnMain', FFaultClass,
              'The tool failed before it could run.');
          FDone := True;
          Result := True;
          Exit;
        End;
      If Not FStarted Then
        Begin
          { 30s means the IDE thread never picked the tool up. A tool that has
            started keeps the IDE thread until it finishes; abandoning it at 30s
            queued the next tool behind a busy IDE and froze the window. }
          If StopNow Or (NowTick - StartTick >= TimeoutMs) Then
            Begin
              FAbandoned := True;
              InterlockedExchange(FStopFlag, 1);
              Result := False;
              Exit;
            End;
        End
      Else If StopNow Or (NowTick - StartTick >= AssistantToolMaxCompileMs + 15000) Then
        Begin
          InterlockedExchange(FStopFlag, 1);
          If StopTick = 0 Then
            StopTick := NowTick
          Else If NowTick - StopTick >= IdeToolStopGraceMs Then
            Begin
              FAbandoned := True;
              Result := False;
              Exit;
            End;
        End;
    Finally
      LeaveCriticalSection(FLock);
    End;
    Sleep(15);
  Until False;
End;

Procedure TIdeToolDispatch.CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String;
  Out ImageRefs: TAssistantImageRefArray);
Begin
  EnterCriticalSection(FLock);
  Try
    ToolOk := FOk;
    ToolResult := FResultText;
    ToolError := FErrorText;
    ImageRefs := FImageRefs;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TIdeToolDispatch.CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String);
Var
  ImageRefs: TAssistantImageRefArray;
Begin
  CopyOutcome(ToolOk, ToolResult, ToolError, ImageRefs);
End;

Procedure TAssistantActor.RunOneTool(Const Call: TSamplerToolCall);
Var
  StartTick: QWord;
  ResultText, ErrorText, Content, AttachmentsJson, FaultClass, FaultMessage: String;
  Ok, Faulted: Boolean;
  Svc: TAssistantService;
  Mode: TAssistantMode;
  ToolDispatch: TIdeToolDispatch;
  ImageRefs: TAssistantImageRefArray;
  I, Base, Tries: Integer;
  SubagentSession: Boolean;
  Decision: TAssistantRecovery;
Begin
  Svc := LockedService;
  If Not Assigned(Svc) Or (Call.Name = '') Then
    Exit;
  Mode := Svc.ActiveMode;
  SubagentSession := Svc.IsSubagentSession;
  { Do not keep Svc across Queue/Sleep — Detach may free the service. }
  Svc := Nil;
  LogEvent(aekToolStarted, Call.Arguments, Call.Name, Call.Id);
  EmitSnapshot(False, 'Running tools…', True);
  StartTick := GetTickCount64;
  ResultText := '';
  ErrorText := '';
  ImageRefs := Nil;
  Tries := 0;
  FActiveToolName := Call.Name;
  FActiveToolRecorded := False;
  If Not AssistantToolIsReadOnly(Call.Name) Then
    FMutatingToolRan := True;
  BindToolAbortThread(Self);
  Try
    Repeat
      If FTerminalNoted Then
        Exit;
      Ok := False;
      Faulted := False;
      FaultClass := '';
      FaultMessage := '';
      ResultText := '';
      ErrorText := '';
      ImageRefs := Nil;
      Try
        If SubagentSession And SameText(Call.Name, 'write_image') Then
          Begin
            Ok := False;
            ErrorText := 'Unknown tool: write_image';
          End
        Else If ToolNeedsIdeThread(Call.Name) Then
          Begin
            ToolDispatch := TIdeToolDispatch.Create(Call.Name, Call.Arguments, Mode, Self);
            { Queue, not Synchronize: Terminate cannot unblock a stuck Synchronize. }
            TThread.Queue(Nil, @ToolDispatch.ExecuteOnMain);
            If ToolDispatch.WaitUntilDone(30000) Or ToolDispatch.HasFailed Then
              Begin
                ToolDispatch.CopyOutcome(Ok, ResultText, ErrorText, ImageRefs);
                Faulted := ToolDispatch.TookFault(FaultClass, FaultMessage);
                ToolDispatch.Release;
              End
            Else
              Begin
                { Abandoned only when the dispatch has not already failed. }
                Ok := False;
                If Terminated Then
                  ErrorText := CancelWaitHint
                Else If ToolDispatch.HasStarted Then
                  ErrorText := 'The tool did not finish on the IDE thread.'
                Else
                  ErrorText := 'Timed out waiting for the IDE thread.';
                ResultText := '';
                ToolDispatch.Release;
              End;
          End
        Else
          Ok := ExecuteAssistantToolForMode(Call.Name, Call.Arguments, Mode,
            ResultText, ErrorText, ImageRefs);
      Except
        On E: Exception Do
          Begin
            ReportPluginException('TAssistantActor.RunOneTool', E);
            Faulted := True;
            FaultClass := E.ClassName;
            FaultMessage := E.Message;
            Ok := False;
            ErrorText := AssistantRecoveryToolError('ExecuteAssistantToolForMode', E.ClassName, E.Message);
            ResultText := '';
          End;
      End;
      If Ok Or (Not Faulted) Or FTerminalNoted Then
        Break;
      Inc(Tries);
      Decision := ClassifyFault(afoTool, 'ExecuteAssistantToolForMode', Call.Name, FaultClass, FaultMessage, 0,
        NextFaultAttempt('tool:' + Call.Id), True);
      Case Decision.Action Of
        araRetryLastAction:
          If FTerminalNoted Or (Tries > 8) Then
            Begin
              PostTerminalStop('ExecuteAssistantToolForMode', FaultClass, FaultMessage);
              Exit;
            End
          Else
            PostRecovery(araRetryLastAction, afoTool, 'ExecuteAssistantToolForMode', FaultClass, FaultMessage);
        araContinueTurn:
          Begin
            PostRecovery(araContinueTurn, afoTool, 'ExecuteAssistantToolForMode', FaultClass, FaultMessage);
            Break;
          End;
        araStop:
          Begin
            { No tool result: that would be a partial recipe for another round. }
            PostTerminalStop('ExecuteAssistantToolForMode', FaultClass, FaultMessage);
            Exit;
          End;
      Else
        Exit;
      End;
    Until False;
  Finally
    UnbindToolAbortThread;
  End;
  If FRecoveryStop Or FTerminalNoted Then
    Exit;
  If Ok Then
    Content := ResultText
  Else
    Content := 'Error: ' + ErrorText;
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Begin
      If ServiceWasDetached Then
        PostTerminalStop('TAssistantActor.RunOneTool', 'Exception', AssistantServiceGoneText);
      Exit;
    End;
  Svc.AddToolResult(Call.Id, Content);
  FActiveToolRecorded := True;
  FActiveToolName := '';
  AttachmentsJson := '';
  If Ok And (Length(ImageRefs) > 0) And (Not Svc.IsSubagentSession) And
    (SameText(Call.Name, 'read_image') Or SameText(Call.Name, 'write_image')) Then
    Begin
      Base := Length(FPendingImageRefs);
      SetLength(FPendingImageRefs, Base + Length(ImageRefs));
      For I := 0 To High(ImageRefs) Do
        FPendingImageRefs[Base + I] := ImageRefs[I];
      AttachmentsJson := AssistantImageRefsToJson(ImageRefs);
    End;
  LogEvent(aekToolCompleted, Copy(Content, 1, MaxToolEventChars), Call.Name, Call.Id, Ok,
    Integer(GetTickCount64 - StartTick), AttachmentsJson);
  If Ok And (SameText(Call.Name, 'write_markdown') Or SameText(Call.Name, 'update_markdown')) Then
    Inc(FPlanWrites);
  WorkflowLogger.Info('AssistantActor',
    Format('tool %s ok=%s ms=%d', [Call.Name, BoolToStr(Ok, True), GetTickCount64 - StartTick]));
End;

Procedure TAssistantActor.FinishSpawnSlot(Const Call: TSamplerToolCall; Const RunId, KindName, ResultText,
  ErrorText: String; Ok: Boolean; DurationMs: Integer);
Var
  Content: String;
  Svc: TAssistantService;
Begin
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  If Ok Then
    Content := ResultText
  Else If ResultText <> '' Then
    Content := ResultText
  Else
    Content := 'Error: ' + ErrorText;
  Svc.AddToolResult(Call.Id, Content);
  LogEvent(aekSubagentCompleted, Copy(Content, 1, SubagentSummaryMaxChars), KindName, RunId, Ok, DurationMs);
  WorkflowLogger.Info('AssistantActor',
    Format('subagent %s ok=%s ms=%d', [RunId, BoolToStr(Ok, True), DurationMs]));
End;

Procedure TAssistantActor.RunSpawnRange(FromIndex, ToIndex: Integer);
Var
  I, Slot, NextToStart, Remaining: Integer;
  Call: TSamplerToolCall;
  Request: TSubagentRequest;
  RunIds, KindNames: Array Of String;
  Handled: Array Of Boolean;
  StartTicks: Array Of QWord;
  StartTick: QWord;
  ResultText, ErrorText, ParseErr: String;
  Ok, Progressed: Boolean;
  Svc: TAssistantService;
Begin
  { At most MaxLiveSubagents run at once; extra spawn_subagent calls wait for a slot. }
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  RunIds := Nil;
  KindNames := Nil;
  Handled := Nil;
  StartTicks := Nil;
  SetLength(RunIds, ToIndex - FromIndex + 1);
  SetLength(KindNames, ToIndex - FromIndex + 1);
  SetLength(Handled, ToIndex - FromIndex + 1);
  SetLength(StartTicks, ToIndex - FromIndex + 1);
  Remaining := 0;
  For I := FromIndex To ToIndex Do
    Begin
      Slot := I - FromIndex;
      RunIds[Slot] := '';
      KindNames[Slot] := '';
      Handled[Slot] := FToolCalls[I].Name = '';
      StartTicks[Slot] := 0;
      If Not Handled[Slot] Then
        Inc(Remaining);
    End;
  NextToStart := FromIndex;
  While Remaining > 0 Do
    Begin
      Svc := LockedService;
      If Not Assigned(Svc) Then
        Exit;
      If Terminated Then
        Begin
          Svc.CancelSubagents;
          For I := FromIndex To ToIndex Do
            Begin
              Slot := I - FromIndex;
              If Handled[Slot] Then
                Continue;
              Call := FToolCalls[I];
              If RunIds[Slot] <> '' Then
                Begin
                  ResultText := '';
                  ErrorText := '';
                  Ok := Svc.TakeSubagentResult(RunIds[Slot], ResultText, ErrorText);
                  FinishSpawnSlot(Call, RunIds[Slot], KindNames[Slot], ResultText, ErrorText, Ok,
                    Integer(GetTickCount64 - StartTicks[Slot]));
                End
              Else
                Begin
                  Svc.AddToolResult(Call.Id, 'Error: Cancelled.');
                  LogEvent(aekSubagentCompleted, 'Cancelled.', KindNames[Slot], Call.Id, False, 0);
                End;
              Handled[Slot] := True;
              Dec(Remaining);
            End;
          Exit;
        End;
      While (NextToStart <= ToIndex) And (Svc.LiveSubagentCount < MaxLiveSubagents) Do
        Begin
          Slot := NextToStart - FromIndex;
          Call := FToolCalls[NextToStart];
          Inc(NextToStart);
          If Handled[Slot] Then
            Continue;
          EmitSnapshot(False, 'Running tools…', True);
          StartTick := GetTickCount64;
          StartTicks[Slot] := StartTick;
          If Not ParseSpawnSubagentArguments(Call.Arguments, Request, ParseErr) Then
            Begin
              LogEvent(aekSubagentStarted, ParseErr, 'spawn_subagent', Call.Id, False);
              Svc.AddToolResult(Call.Id, 'Error: ' + ParseErr);
              LogEvent(aekSubagentCompleted, ParseErr, 'spawn_subagent', Call.Id, False,
                Integer(GetTickCount64 - StartTick));
              Handled[Slot] := True;
              Dec(Remaining);
              Continue;
            End;
          KindNames[Slot] := SubagentKindName(Request.Kind);
          If ReviewLensAlreadyListed(Request.Kind, KindNames, Slot - 1) Then
            Begin
              Svc.AddToolResult(Call.Id, 'Skipped duplicate ' + KindNames[Slot] +
                ' lens; one of this kind is already running in this round.');
              LogEvent(aekSubagentCompleted, 'duplicate skipped', KindNames[Slot], Call.Id, True, 0);
              Handled[Slot] := True;
              Dec(Remaining);
              Continue;
            End;
          If Not Svc.StartSubagent(Call.Arguments, RunIds[Slot], ErrorText) Then
            Begin
              { Budget should not hit here — the loop waits for a slot. Other start errors still fail. }
              If Pos('Too many live subagents', ErrorText) > 0 Then
                Begin
                  Dec(NextToStart);
                  Break;
                End;
              LogEvent(aekSubagentStarted, Request.Title, KindNames[Slot], Call.Id, False);
              Svc.AddToolResult(Call.Id, 'Error: ' + ErrorText);
              LogEvent(aekSubagentCompleted, ErrorText, KindNames[Slot], Call.Id, False,
                Integer(GetTickCount64 - StartTick));
              Handled[Slot] := True;
              Dec(Remaining);
            End
          Else
            LogEvent(aekSubagentStarted, Request.Title, KindNames[Slot], RunIds[Slot]);
        End;
      Progressed := False;
      For I := FromIndex To ToIndex Do
        Begin
          Slot := I - FromIndex;
          If Handled[Slot] Or (RunIds[Slot] = '') Then
            Continue;
          If SubagentRunTimedOut(StartTicks[Slot], GetTickCount64) Then
            Svc.AbandonSubagent(RunIds[Slot],
              Format('Timed out after %d s (still running tools).', [MaxSubagentRuntimeMs Div 1000]));
          If Svc.SubagentIsRunning(RunIds[Slot]) Then
            Continue;
          Call := FToolCalls[I];
          ResultText := '';
          ErrorText := '';
          Ok := Svc.TakeSubagentResult(RunIds[Slot], ResultText, ErrorText);
          FinishSpawnSlot(Call, RunIds[Slot], KindNames[Slot], ResultText, ErrorText, Ok,
            Integer(GetTickCount64 - StartTicks[Slot]));
          Handled[Slot] := True;
          Dec(Remaining);
          Progressed := True;
        End;
      If (Not Progressed) And (Remaining > 0) Then
        Sleep(40);
    End;
End;

Procedure TAssistantActor.RunTools;
Var
  I, J: Integer;
  ToolCallsJson: String;
  Call: TSamplerToolCall;
  Svc: TAssistantService;
  Procedure FlushReadImages;
  Begin
    If Length(FPendingImageRefs) = 0 Then Exit;
    Svc := LockedService;
    If Assigned(Svc) And (Not Svc.IsSubagentSession) Then
      Svc.AddUserMessage('', FPendingImageRefs);
    SetLength(FPendingImageRefs, 0);
  End;
Begin
  RememberResponseImages(FResponseOutputJson);
  SetLength(FPendingImageRefs, 0);
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  FHadToolRound := True;
  ToolCallsJson := '[';
  For I := 0 To High(FToolCalls) Do
    Begin
      Call := FToolCalls[I];
      If Call.Name = '' Then
        Continue;
      If Length(ToolCallsJson) > 1 Then
        ToolCallsJson := ToolCallsJson + ',';
      If Call.Id = '' Then
        Begin
          Call.Id := Format('call_%d_%d', [FLoopIndex, I]);
          FToolCalls[I].Id := Call.Id;
        End;
      ToolCallsJson := ToolCallsJson + '{"id":"' + JsonEscapeText(Call.Id) +
        '","type":"function","function":{"name":"' + JsonEscapeText(Call.Name) +
        '","arguments":"' + JsonEscapeText(Call.Arguments) + '"}}';
    End;
  ToolCallsJson := ToolCallsJson + ']';
  Svc.AddAssistantToolCalls(FContent, ToolCallsJson, FResponseOutputJson);
  FToolCallsCommitted := True;
  FActiveToolIndex := -1;
  FActiveToolRecorded := False;
  I := 0;
  While I <= High(FToolCalls) Do
    Begin
      If Terminated Then
        Begin
          FlushReadImages;
          Exit;
        End;
      Call := FToolCalls[I];
      If Call.Name = '' Then
        Begin
          Inc(I);
          Continue;
        End;
      If IsSpawnSubagentName(Call.Name) Then
        Begin
          J := I + 1;
          While J <= High(FToolCalls) Do
            Begin
              If FToolCalls[J].Name = '' Then
                Begin
                  Inc(J);
                  Continue;
                End;
              If Not IsSpawnSubagentName(FToolCalls[J].Name) Then
                Break;
              Inc(J);
            End;
          FActiveToolIndex := I;
          FActiveToolName := Call.Name;
          FActiveToolRecorded := False;
          RunSpawnRange(I, J - 1);
          If Not FTerminalNoted Then
            FActiveToolRecorded := True;
          I := J;
        End
      Else
        Begin
          FActiveToolIndex := I;
          RunOneTool(Call);
          If FRecoveryStop Or FTerminalNoted Or Terminated Then
            Begin
              FlushReadImages;
              Exit;
            End;
          Inc(I);
        End;
    End;
  FlushReadImages;
End;

Function TAssistantActor.InjectPendingSteer(Svc: TAssistantService; Out VisibleNote: String): Boolean;
Var
  Note, AttachmentsJson, ModelNote, Wrapped: String;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  VisibleNote := '';
  SetLength(Refs, 0);
  If Not Assigned(Svc) Then Exit;
  If Not FSteer.Drain(Note, AttachmentsJson) Then Exit;
  { Image parts stay on this session. They are not copied onto a subagent prompt. }
  If Not Svc.IsSubagentSession Then
    Begin
      If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Then SetLength(Refs, 0);
      Refs := LimitAssistantImageRefs(Refs);
    End;
  If (Trim(Note) = '') And (Length(Refs) = 0) Then Exit;
  VisibleNote := Note;
  ModelNote := Note;
  If (Trim(ModelNote) = '') And (Length(Refs) > 0) Then ModelNote := AssistantImageLookText;
  Wrapped := FormatSteerEnvelope(ModelNote);
  If Length(Refs) = 0 Then
    Svc.AddMessage(amrUser, Wrapped)
  Else
    Svc.AddUserMessage(Wrapped, Refs);
  Result := True;
End;

Function TAssistantActor.DrainSteerIntoHistory: Boolean;
Var
  Svc: TAssistantService;
  Note: String;
Begin
  Result := False;
  Svc := LockedService;
  If Terminated Or (Not Assigned(Svc)) Or (Not FSteer.HasPending) Then Exit;
  Result := InjectPendingSteer(Svc, Note);
  If Not Result Then Exit;
  LogEvent(aekInterjected, Note);
  EmitSnapshot(False, 'Steering at next model gap…', True);
End;

Function TAssistantActor.BuildRoundJson(Out Url: String): String;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Base: String;
  Svc: TAssistantService;
Begin
  Base := TrimSlash(FApiBase);
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Begin
      SetLength(Items, 0);
      Url := '';
      Result := '';
      Exit;
    End;
  Items := Svc.ExportSamplerItems(FUseResponses);
  Options := DefaultSamplerRequestOptions;
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Options.ProjectRoot := ProjectAssistantConversation.ProjectRoot
  Else
    Options.ProjectRoot := ProjectAssistantRoot;
  Options.Model := FModel;
  Options.ReasoningEffort := FReasoningEffort;
  Options.AnswerVerbosity := Svc.AnswerVerbosity;
  Options.MaxOutputTokens := Svc.MaxOutputTokens;
  Options.SearchMode := Svc.SearchMode;
  Options.SearchCitations := Svc.SearchCitations;
  If FUseResponses Then
    Begin
      Options.ToolsJson := CompletionsToolsToResponsesTools(FToolsJson);
      Options.IncludeEncryptedReasoning := True;
      Url := Base + '/responses';
      Result := BuildResponsesRequestJson(Items, Options);
    End
  Else
    Begin
      Options.ToolsJson := FToolsJson;
      Options.IncludeEncryptedReasoning := False;
      Url := Base + '/chat/completions';
      Result := BuildChatCompletionsRequestJson(Items, Options);
    End;
End;

Procedure TAssistantActor.Execute;
Var
  Decision: TAssistantRecovery;
  Origin: TAssistantFaultOrigin;
  Area, ToolName: String;
  Attempt: Integer;
Begin
  FRecoveryStop := False;
  FRecoveryStopText := '';
  FTerminalNoted := False;
  FMutatingToolRan := False;
  FActiveToolName := '';
  FHttpExceptionClass := '';
  FToolCallsCommitted := False;
  FActiveToolIndex := -1;
  FActiveToolRecorded := False;
  SnapshotRecoverySettings;
  Attempt := 0;
  Repeat
    Inc(Attempt);
    Try
      ExecuteTurn;
      Exit;
    Except
      On E: Exception Do
        Begin
          ReportPluginException('TAssistantActor.Execute', E);
          If FTerminalNoted Or FFinishEmitted Then
            Exit;
          { The failed site classifies. A first access violation must not finish the turn. }
          FaultSite(Origin, Area, ToolName);
          Decision := ClassifyFault(Origin, Area, ToolName, E.ClassName, E.Message, 0, NextFaultAttempt(Area), True);
          Case Decision.Action Of
            araIgnore:
              Begin
                If Terminated Then
                  EmitSnapshot(True, CancelWaitHint, True)
                Else
                  EmitSnapshot(True, '', True);
                Exit;
              End;
            araStop:
              Begin
                PostTerminalStop(Area, E.ClassName, E.Message);
                Exit;
              End;
          Else
            If FTerminalNoted Or FMutatingToolRan Or (Attempt >= 2) Then
              Begin
                PostTerminalStop(Area, E.ClassName, E.Message);
                Exit;
              End;
            PostRecovery(Decision.Action, Origin, Area, E.ClassName, E.Message);
          End;
        End;
    End;
  Until False;
End;

Procedure TAssistantActor.ExecuteTurn;
Var
  Url, RequestJson, ErrorText, CapNote, Note: String;
  RoundNo, I, MaxRounds, WritesBefore: Integer;
  RoundTruncated: Boolean;
  HitToolCap: Boolean;
  HasTools: Boolean;
  Svc: TAssistantService;
Begin
  BeginWriteImageTurn;
  ClearTurnGeneratedImages;
  FHadToolRound := False;
  RoundTruncated := False;
  FLocalContinuationCount := 0;
  LogEvent(aekTurnStarted, FModel);
  SetPhase(apWaiting);
  EmitSnapshot(False, 'Waiting for first token…', True);
  Try
  Svc := LockedService;
  MaxRounds := MaxRoundsForSession(Svc);
  Repeat
  HitToolCap := True;
  For RoundNo := 1 To MaxRounds Do
    Begin
      If FTerminalNoted Or Terminated Or (Not Assigned(LockedService)) Then
        Break;
      FActiveToolName := '';
      FToolCallsCommitted := False;
      FActiveToolIndex := -1;
      FActiveToolRecorded := False;
      FLoopIndex := RoundNo;
      Try
      If RoundNo > 1 Then
        LogEvent(aekLoopStarted, IntToStr(RoundNo));
      FThinkingBeforeRound := FThinking;
      If FThinkingBeforeRound <> '' Then
        FThinkingBeforeRound := FThinkingBeforeRound + LineEnding + LineEnding;
      SetLength(FToolCalls, 0);
      { Fresh answer channel per model loop; thinking is kept. }
      FContent := '';
      { After tools the previous snapshot stays 'Running tools…' unless we reset it. }
      EmitSnapshot(False, 'Waiting for model…', True);
      RequestJson := BuildRoundJson(Url);
      If FUseResponses Then
        FTriedResponses := True;
      If Not DoHttpRound(Url, RequestJson, ErrorText) Then
        Begin
          If (FHttpExceptionClass <> '') And (Not Terminated) And (ErrorText <> CancelWaitHint) Then
            Begin
              PostTerminalStop('TAssistantActor.DoHttpRound', FHttpExceptionClass, ErrorText);
              Exit;
            End;
          If FUseResponses And FTriedResponses And ShouldFallbackFromResponses(ErrorText) And
            (Not Terminated) Then
            Begin
              WorkflowLogger.Warning('AssistantActor', 'Responses failed, falling back to Chat Completions: ' +
                ErrorText);
              FUseResponses := False;
              RequestJson := BuildRoundJson(Url);
              If DoHttpRound(Url, RequestJson, ErrorText) Then
                ErrorText := ''
              Else
                Begin
                  If (FHttpExceptionClass <> '') And (Not Terminated) And (ErrorText <> CancelWaitHint) Then
                    PostTerminalStop('TAssistantActor.DoHttpRound', FHttpExceptionClass, ErrorText)
                  Else
                    Begin
                      EmitSnapshot(True, ErrorText, True);
                      LogEvent(aekError, ErrorText);
                    End;
                  Exit;
                End;
            End
          Else
            Begin
              If Terminated Then
                ErrorText := CancelWaitHint;
              EmitSnapshot(True, ErrorText, True);
              If ErrorText <> CancelWaitHint Then
                LogEvent(aekError, ErrorText);
              Exit;
            End;
        End;
      If Terminated Then
        Break;
      RoundTruncated := FParser.Incomplete;
      HasTools := False;
      For I := 0 To High(FToolCalls) Do
        If Trim(FToolCalls[I].Name) <> '' Then
          Begin
            HasTools := True;
            Break;
          End;
      If HasTools Then
        Begin
          SetPhase(apTools);
          { The first plan write must not end the turn. Status: complete still has to be committed. }
          WritesBefore := FPlanWrites;
          RunTools;
          If FRecoveryStop Or FTerminalNoted Then
            Begin
              If Not FTerminalNoted Then
                PostTerminalStop('TAssistantActor.ExecuteTurn', 'Exception', FRecoveryStopText);
              Exit;
            End;
          If Terminated Then
            Break;
          If (FPlanWrites > WritesBefore) And (WritesBefore > 0) Then
            Begin
              If FinishOrContinue(RoundTruncated, False) Then
                Begin
                  NoteReadyFacts(RoundTruncated, False);
                  EmitSnapshot(True, '', True);
                  LogEvent(aekTurnEnded, 'plan_write');
                  Exit;
                End;
              HitToolCap := False;
              Break;
            End;
          DrainSteerIntoHistory;
          Continue;
        End;
      If DrainSteerIntoHistory Then
        Continue;
      If FinishOrContinue(RoundTruncated, False) Then
        Begin
          NoteReadyFacts(RoundTruncated, False);
          EmitSnapshot(True, '', True);
          LogEvent(aekTurnEnded, '');
          Exit;
        End;
      HitToolCap := False;
      Break;
      Except
        On E: Exception Do
          Begin
            ReportPluginException('TAssistantActor.ExecuteTurn', E);
            If FTerminalNoted Or FFinishEmitted Then
              Exit;
            If Not KeepRoundAfterFault(E) Then
              Exit;
          End;
      End;
    End;
  If FTerminalNoted Or FFinishEmitted Then
    Exit;
  If Terminated Then
    Begin
      EmitSnapshot(True, CancelWaitHint, True);
      Exit;
    End;
  If HitToolCap Then
    Begin
      If FinishOrContinue(False, True) Then
        Begin
          CapNote :=
            '*(Tool-round limit reached after ' + IntToStr(MaxRounds) +
            ' rounds. Edits already applied are in the project.)*';
          If Trim(FContent) = '' Then
            FContent := CapNote
          Else
            FContent := TrimRight(FContent) + LineEnding + LineEnding + CapNote;
          NoteReadyFacts(False, True);
          EmitSnapshot(True, '', True);
          LogEvent(aekTurnEnded, 'tool_round_cap');
          Exit;
        End;
    End;
  Until False;
  Finally
    Try
      Svc := LockedService;
      If Assigned(Svc) And FSteer.HasPending And (Not FTerminalNoted) Then
        InjectPendingSteer(Svc, Note);
    Except
      On E: Exception Do
        Begin
          ReportPluginException('TAssistantActor.ExecuteTurn', E);
          If (Not FFinishEmitted) And (Not FTerminalNoted) And
            (ClassifyFault(afoTurn, 'TAssistantActor.InjectPendingSteer', '', E.ClassName, E.Message, 0, 1,
            True).Action = araStop) Then
            PostTerminalStop('TAssistantActor.InjectPendingSteer', E.ClassName, E.Message);
        End;
    End;
  End;
End;

End.
