Unit AssistantActor;

{ Session actor thread: Responses stream, tool rounds, steer drain, cancel (c) 2026 Michell Computing.

  Named Actor because AssistantSession.pas already holds the legacy transcript file. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantProtocol, AssistantSampler, AssistantEvents, AssistantService,
  AssistantConversation;

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
    FPhase: TAssistantPhase;
    FErrorText: String;
    FStatusText: String;
    FFinishEmitted: Boolean;
    FWrotePlan: Boolean;
    FUseResponses: Boolean;
    FTriedResponses: Boolean;
    FEncryptedId: String;
    FEncryptedContent: String;
    FLoopIndex: Integer;
    FLastSnapTick: QWord;
    FPendingFinish: Boolean;
    FNotifyQueued: Boolean;
    FToolCalls: TSamplerToolCallArray;
    Procedure LogEvent(Kind: TAssistantEventKind; Const Text: String = '';
      Const ToolName: String = ''; Const ToolId: String = ''; Ok: Boolean = True;
      DurationMs: Integer = 0);
    Procedure QueueTrace(Const Event: TAssistantEvent);
    Procedure NotifyTrace;
    Procedure EmitSnapshot(IsDone: Boolean; Const ErrorText: String; Force: Boolean);
    Procedure NotifyMain;
    Procedure SetPhase(Phase: TAssistantPhase);
    Procedure ApplyParserEvents(FromIndex: Integer);
    Procedure AppendThinking(Const Delta: String);
    Function DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
    Procedure HttpsChunk(Const Chunk: String);
    Function HttpsShouldStop: Boolean;
    Procedure AbortHttp;
    Function LockedService: TAssistantService;
    Procedure RunTools;
    Procedure RunOneTool(Const Call: TSamplerToolCall);
    Procedure FinishSpawnSlot(Const Call: TSamplerToolCall; Const RunId, KindName, ResultText,
      ErrorText: String; Ok: Boolean; DurationMs: Integer);
    Procedure RunSpawnRange(FromIndex, ToIndex: Integer);
    Function DrainSteerIntoHistory: Boolean;
    Function BuildRoundJson(Out Url: String): String;
    Function ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Service: TAssistantService; Const ApiBase, AccessToken, Model,
      ReasoningEffort, ToolsJson, EventsFile: String; OnToken: TAssistantStreamEvent);
    Destructor Destroy; Override;
    Procedure Cancel;
    Procedure EnqueueSteer(Const Text: String);
    Procedure Detach;
    Property OnTrace: TAssistantTraceNotify Read FOnTrace Write FOnTrace;
  End;

Implementation

Uses
  AssistantHttps, AssistantTools, AssistantSubagents, WorkflowLog;

Const
  MaxAskToolRounds = 12;
  MaxPlanToolRounds = 40;
  MaxBuildToolRounds = 80;
  SnapIntervalMs = 50;
  CancelWaitHint = 'Cancelled.';
  MaxToolEventChars = 4000;

Function MaxRoundsForSession(Svc: TAssistantService): Integer;
Begin
  If Assigned(Svc) And Svc.IsSubagentSession Then
    Result := MaxSubagentToolRounds
  Else If Assigned(Svc) Then
    Case Svc.ActiveMode Of
      amPlan: Result := MaxPlanToolRounds;
      amBuild: Result := MaxBuildToolRounds;
    Else
      Result := MaxAskToolRounds;
    End
  Else
    Result := MaxAskToolRounds;
End;

Function IsTransientNetworkError(Const ErrorText: String): Boolean;
Var
  E: String;
Begin
  E := LowerCase(ErrorText);
  Result :=
    (Pos('host name resolution', E) > 0) Or
    (Pos('could not resolve', E) > 0) Or
    (Pos('name or service not known', E) > 0) Or
    (Pos('temporary failure in name resolution', E) > 0) Or
    (Pos('network is unreachable', E) > 0) Or
    (Pos('connection refused', E) > 0) Or
    (Pos('connection reset', E) > 0) Or
    (Pos('timed out', E) > 0) Or
    (Pos('timeout', E) > 0) Or
    (Pos('socket error', E) > 0);
End;

Function TrimSlash(Const Url: String): String;
Begin
  Result := Trim(Url);
  While (Length(Result) > 0) And (Result[Length(Result)] = '/') Do
    SetLength(Result, Length(Result) - 1);
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
  FWrotePlan := False;
  FUseResponses := True;
  FTriedResponses := False;
  FEncryptedId := '';
  FEncryptedContent := '';
  FLoopIndex := 0;
  FLastSnapTick := 0;
  FPendingFinish := False;
  FNotifyQueued := False;
  SetLength(FToolCalls, 0);
End;

Destructor TAssistantActor.Destroy;
Begin
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

Procedure TAssistantActor.EnqueueSteer(Const Text: String);
Begin
  If Trim(Text) = '' Then
    Exit;
  FSteer.Enqueue(Text);
  LogEvent(aekSteerQueued, Trim(Text));
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
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  AbortHttp;
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
    aekSubagentCompleted, aekTurnEnded];
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
  Queue(@NotifyTrace);
End;

Procedure TAssistantActor.NotifyTrace;
Var
  Batch: Array Of TAssistantEvent;
  I: Integer;
  Cb: TAssistantTraceNotify;
Begin
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
        WorkflowLogger.Warning('AssistantActor', 'Trace notify failed: ' + E.Message);
    End;
End;

Procedure TAssistantActor.LogEvent(Kind: TAssistantEventKind; Const Text: String;
  Const ToolName: String; Const ToolId: String; Ok: Boolean; DurationMs: Integer);
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
        WorkflowLogger.Warning('AssistantActor', 'UI snapshot failed: ' + E.Message);
    End;
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
    Queue(@NotifyMain);
End;

Procedure TAssistantActor.SetPhase(Phase: TAssistantPhase);
Begin
  If FPhase = Phase Then
    Exit;
  FPhase := Phase;
  LogEvent(aekPhaseChanged, AssistantPhaseName(Phase));
End;

Procedure TAssistantActor.AppendThinking(Const Delta: String);
Begin
  If Delta = '' Then
    Exit;
  MergeSamplerText(FThinking, Delta);
  If FPhase = apWaiting Then
    SetPhase(apThinking);
  EmitSnapshot(False, '', False);
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
            AppendThinking(Event.Text);
          End;
        sekContentDelta:
          Begin
            SetPhase(apStreaming);
            MergeSamplerText(FContent, Event.Text);
            EmitSnapshot(False, '', False);
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
  If Terminated Then
    Exit;
  FromIndex := FParser.EventCount;
  FParser.Feed(Chunk);
  ApplyParserEvents(FromIndex);
End;

Function TAssistantActor.HttpsShouldStop: Boolean;
Begin
  Result := Terminated;
End;

Function TAssistantActor.DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
Const
  MaxAttempts = 3;
Var
  Code, Attempt: Integer;
  Headers, LastErr: String;
  Control: THttpsStreamControl;
Begin
  Result := False;
  ErrorText := '';
  LastErr := '';
  Headers := 'Authorization: Bearer ' + FAccessToken;
  For Attempt := 1 To MaxAttempts Do
    Begin
      If Terminated Then
        Begin
          ErrorText := CancelWaitHint;
          Exit;
        End;
      FParser.Reset;
      Control := THttpsStreamControl.Create;
      EnterCriticalSection(FHttpLock);
      Try
        FHttpControl := Control;
      Finally
        LeaveCriticalSection(FHttpLock);
      End;
      Try
        Try
          If Not HttpsPostJsonStream(Url, RequestJson, Headers, @HttpsChunk, @HttpsShouldStop,
            Control, Code, ErrorText) Then
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
            End
          Else If FParser.Failed Then
            Begin
              ErrorText := FParser.ErrorText;
              If ErrorText = '' Then
                ErrorText := 'response.failed';
            End
          Else If FParser.Incomplete And (Length(FParser.ToolCalls) = 0) And (Trim(FParser.Content) = '') Then
            Begin
              ErrorText := FParser.ErrorText;
              If ErrorText = '' Then
                ErrorText := 'response.incomplete';
            End
          Else
            Begin
              If FParser.Thinking <> '' Then
                MergeSamplerText(FThinking, FParser.Thinking);
              If (FParser.Content <> '') And (FContent = '') Then
                FContent := FParser.Content;
              If FParser.EncryptedContent <> '' Then
                Begin
                  FEncryptedContent := FParser.EncryptedContent;
                  FEncryptedId := FParser.EncryptedId;
                End;
              FToolCalls := FParser.ToolCalls;
              If FParser.Incomplete Then
                Begin
                  WorkflowLogger.Warning('AssistantActor', 'Incomplete response: ' + FParser.ErrorText);
                  If (FContent <> '') And (Pos('[Incomplete response', FContent) < 1) Then
                    FContent := FContent + LineEnding + LineEnding +
                      '*[Incomplete response: ' + FParser.ErrorText + ']*';
                End;
              Result := True;
              Exit;
            End;
        Except
          On E: Exception Do
            If Terminated Then
              ErrorText := CancelWaitHint
            Else
              ErrorText := E.Message;
        End;
      Finally
        EnterCriticalSection(FHttpLock);
        Try
          FHttpControl := Nil;
        Finally
          LeaveCriticalSection(FHttpLock);
        End;
        Control.Free;
      End;
      LastErr := ErrorText;
      If Terminated Or (ErrorText = CancelWaitHint) Then
        Exit;
      If (Not IsTransientNetworkError(ErrorText)) Then
        Exit;
      If Attempt < MaxAttempts Then
        Begin
          WorkflowLogger.Warning('AssistantActor',
            Format('Transient network error (attempt %d/%d): %s', [Attempt, MaxAttempts, ErrorText]));
          Sleep(200 * Attempt);
        End;
    End;
  ErrorText := LastErr;
End;

Function TAssistantActor.ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
Var
  E: String;
Begin
  E := LowerCase(ErrorText);
  Result := (Pos('http 404', E) > 0) Or (Pos('http 405', E) > 0) Or
    (Pos('http 400', E) > 0) Or (Pos('not found', E) > 0) Or
    (Pos('unknown', E) > 0) Or (Pos('not supported', E) > 0);
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
    Procedure Release;
  Public
    Constructor Create(Const ToolName, ArgumentsJson: String; ToolMode: TAssistantMode);
    Destructor Destroy; Override;
    Procedure ExecuteOnMain;
    Function WaitUntilDone(TimeoutMs: QWord): Boolean;
    Procedure CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String);
  End;

Constructor TIdeToolDispatch.Create(Const ToolName, ArgumentsJson: String; ToolMode: TAssistantMode);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FName := ToolName;
  FArgs := ArgumentsJson;
  FMode := ToolMode;
  FOk := False;
  FResultText := '';
  FErrorText := '';
  FAbandoned := False;
  FDone := False;
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

Procedure TIdeToolDispatch.ExecuteOnMain;
Var
  SkipRun: Boolean;
  ToolOk: Boolean;
  ToolResult, ToolError: String;
Begin
  SkipRun := False;
  EnterCriticalSection(FLock);
  Try
    If FAbandoned Then
      SkipRun := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
  If SkipRun Then
    Begin
      Release;
      Exit;
    End;
  ToolOk := False;
  ToolResult := '';
  ToolError := '';
  Try
    ToolOk := ExecuteAssistantToolForMode(FName, FArgs, FMode, ToolResult, ToolError);
  Finally
    EnterCriticalSection(FLock);
    Try
      FOk := ToolOk;
      FResultText := ToolResult;
      FErrorText := ToolError;
      FDone := True;
    Finally
      LeaveCriticalSection(FLock);
    End;
    Release;
  End;
End;

Function TIdeToolDispatch.WaitUntilDone(TimeoutMs: QWord): Boolean;
Var
  StartTick: QWord;
  StopNow: Boolean;
Begin
  Result := False;
  StartTick := GetTickCount64;
  Repeat
    EnterCriticalSection(FLock);
    Try
      If FDone Then
        Begin
          Result := True;
          Exit;
        End;
      StopNow := ToolsShouldStop Or (GetTickCount64 - StartTick >= TimeoutMs);
      If StopNow Then
        Begin
          FAbandoned := True;
          Result := False;
          Exit;
        End;
    Finally
      LeaveCriticalSection(FLock);
    End;
    Sleep(15);
  Until False;
End;

Procedure TIdeToolDispatch.CopyOutcome(Out ToolOk: Boolean; Out ToolResult, ToolError: String);
Begin
  EnterCriticalSection(FLock);
  Try
    ToolOk := FOk;
    ToolResult := FResultText;
    ToolError := FErrorText;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAssistantActor.RunOneTool(Const Call: TSamplerToolCall);
Var
  StartTick: QWord;
  ResultText, ErrorText, Content: String;
  Ok: Boolean;
  Svc: TAssistantService;
  Mode: TAssistantMode;
  ToolDispatch: TIdeToolDispatch;
Begin
  Svc := LockedService;
  If Not Assigned(Svc) Or (Call.Name = '') Then
    Exit;
  Mode := Svc.ActiveMode;
  { Do not keep Svc across Queue/Sleep — Detach may free the service. }
  Svc := Nil;
  LogEvent(aekToolStarted, Call.Arguments, Call.Name, Call.Id);
  EmitSnapshot(False, 'Running tools…', True);
  StartTick := GetTickCount64;
  ResultText := '';
  ErrorText := '';
  BindToolAbortThread(Self);
  Try
    Try
      If ToolNeedsIdeThread(Call.Name) Then
        Begin
          ToolDispatch := TIdeToolDispatch.Create(Call.Name, Call.Arguments, Mode);
          { Queue, not Synchronize: Terminate cannot unblock a stuck Synchronize. }
          TThread.Queue(Nil, @ToolDispatch.ExecuteOnMain);
          If ToolDispatch.WaitUntilDone(30000) Then
            Begin
              ToolDispatch.CopyOutcome(Ok, ResultText, ErrorText);
              ToolDispatch.Release;
            End
          Else
            Begin
              { Abandoned: ExecuteOnMain will not start, or will Free after. }
              ToolDispatch.Release;
              Ok := False;
              If Terminated Then
                ErrorText := CancelWaitHint
              Else
                ErrorText := 'Timed out waiting for the IDE thread.';
              ResultText := '';
            End;
        End
      Else
        Ok := ExecuteAssistantToolForMode(Call.Name, Call.Arguments, Mode,
          ResultText, ErrorText);
    Except
      On E: Exception Do
        Begin
          Ok := False;
          ErrorText := 'Tool raised: ' + E.Message;
          ResultText := '';
        End;
    End;
  Finally
    UnbindToolAbortThread;
  End;
  If Ok Then
    Content := ResultText
  Else
    Content := 'Error: ' + ErrorText;
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
  Svc.AddToolResult(Call.Id, Content);
  LogEvent(aekToolCompleted, Copy(Content, 1, MaxToolEventChars), Call.Name, Call.Id, Ok,
    Integer(GetTickCount64 - StartTick));
  If Ok And (SameText(Call.Name, 'write_markdown') Or SameText(Call.Name, 'update_markdown')) Then
    FWrotePlan := True;
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
Begin
  Svc := LockedService;
  If Not Assigned(Svc) Then
    Exit;
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
  Svc.AddAssistantToolCalls(FContent, ToolCallsJson);
  I := 0;
  While I <= High(FToolCalls) Do
    Begin
      If Terminated Then
        Exit;
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
          RunSpawnRange(I, J - 1);
          I := J;
        End
      Else
        Begin
          RunOneTool(Call);
          Inc(I);
        End;
    End;
End;

Function TAssistantActor.DrainSteerIntoHistory: Boolean;
Var
  Note, Wrapped: String;
  Svc: TAssistantService;
Begin
  Result := False;
  Svc := LockedService;
  If Terminated Or (Not Assigned(Svc)) Then
    Exit;
  Note := FSteer.DrainConcat;
  If Note = '' Then
    Exit;
  Wrapped := FormatSteerEnvelope(Note);
  Svc.AddMessage(amrUser, Wrapped);
  LogEvent(aekInterjected, Note);
  EmitSnapshot(False, 'Steering at next model gap…', True);
  Result := True;
End;

Function TAssistantActor.BuildRoundJson(Out Url: String): String;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Base: String;
  I, InsertAt: Integer;
  Shifted: TSamplerInputItemArray;
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
  Items := Svc.ExportSamplerItems;
  If (FEncryptedContent <> '') And FUseResponses Then
    Begin
      InsertAt := Length(Items);
      SetLength(Shifted, Length(Items) + 1);
      For I := 0 To High(Items) Do
        Shifted[I] := Items[I];
      Shifted[InsertAt] := SamplerInputReasoning(FEncryptedId, FEncryptedContent);
      Items := Shifted;
    End;
  Options := DefaultSamplerRequestOptions;
  Options.Model := FModel;
  Options.ReasoningEffort := FReasoningEffort;
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
  Url, RequestJson, ErrorText, CapNote: String;
  RoundNo, I, MaxRounds: Integer;
  HasTools: Boolean;
  WroteBefore: Boolean;
  Svc: TAssistantService;
Begin
  LogEvent(aekTurnStarted, FModel);
  SetPhase(apWaiting);
  EmitSnapshot(False, 'Waiting for first token…', True);
  Try
  Svc := LockedService;
  MaxRounds := MaxRoundsForSession(Svc);
  For RoundNo := 1 To MaxRounds Do
    Begin
      If Terminated Or (Not Assigned(LockedService)) Then
        Break;
      FLoopIndex := RoundNo;
      If RoundNo > 1 Then
        Begin
          LogEvent(aekLoopStarted, IntToStr(RoundNo));
          If FThinking <> '' Then
            MergeSamplerText(FThinking, LineEnding + LineEnding);
        End;
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
                  EmitSnapshot(True, ErrorText, True);
                  LogEvent(aekError, ErrorText);
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
          WroteBefore := FWrotePlan;
          RunTools;
          If Terminated Then
            Break;
          If FWrotePlan And WroteBefore Then
            Begin
              EmitSnapshot(True, '', True);
              LogEvent(aekTurnEnded, 'plan_write');
              Exit;
            End;
          DrainSteerIntoHistory;
          Continue;
        End;
      If DrainSteerIntoHistory Then
        Continue;
      EmitSnapshot(True, '', True);
      LogEvent(aekTurnEnded, '');
      Exit;
    End;
  If Terminated Then
    EmitSnapshot(True, CancelWaitHint, True)
  Else
    Begin
      CapNote :=
        '*(Tool-round limit reached after ' + IntToStr(MaxRounds) +
        ' rounds. Edits already applied are in the project. Send a follow-up to continue ' +
        'from the last tool results — do not re-read files you already have unless a later ' +
        'replace_in_file failed.)*';
      If Trim(FContent) = '' Then
        FContent := CapNote
      Else
        FContent := TrimRight(FContent) + LineEnding + LineEnding + CapNote;
      EmitSnapshot(True, '', True);
      LogEvent(aekTurnEnded, 'round_cap');
    End;
  Finally
    Svc := LockedService;
    If Assigned(Svc) And FSteer.HasPending Then
      Svc.AddMessage(amrUser, FormatSteerEnvelope(FSteer.DrainConcat));
  End;
End;

End.
