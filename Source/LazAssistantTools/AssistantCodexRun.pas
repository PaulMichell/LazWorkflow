Unit AssistantCodexRun;

{ Thread boundary for a managed Codex run. The worker owns the process/client;
  the IDE timer calls ServiceTool on the main thread. No Synchronize, IDE
  pointers, or main-thread waits occur inside Execute. Destroy only after Done. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantCodexClient, AssistantConversation, AssistantCodexContext, AssistantEvents, AssistantGeneratedImage;

Type
  TCodexImageReservation = Record
    RequestId, Destination, ErrorText: String;
    Image: TAssistantGeneratedImage;
    Overwrite, Finished: Boolean;
  End;
  TCodexRunSnapshot = Record
    State: TCodexRunState;
    Content, Thinking, ErrorText: String;
    Images: Array Of TCodexImageReservation;
    ContextUsage: TCodexContextUsage;
    Done: Boolean;
  End;
  TAssistantCodexRun = Class(TThread)
  Private
    FLock: TRTLCriticalSection;
    FExecutable, FCwd, FModel, FPrompt, FToolsJson, FRunId, FProfile, FEffort, FDeveloperInstructions: String;
    FProjectRoot, FAttachments, FSteerInput, FToolAttachments, FLastSteerError: String;
    FMode: TAssistantMode;
    FSnapshot: TCodexRunSnapshot;
    FEvents: TAssistantEventLog;
    FTool: TCodexToolRequest;
    FToolPending, FToolServicing, FToolReady, FToolSuccess: Boolean;
    FToolResult, FSteer: String;
    ReplayUnsafe: Boolean;
    FTimeout, ReconnectDelayMs: Cardinal;
    FCancelled: LongInt;
    Function Cancelled: Boolean;
    Procedure Publish(Client: TAssistantCodexClient);
    Procedure NoteEvent(Kind: TAssistantEventKind; Const Text: String = ''; Const ToolName: String = '';
      Const ToolId: String = ''; Ok: Boolean = True; Const AttachmentsJson: String = '');
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const Executable, Cwd, Model, Prompt, ToolsJson, RunId: String;
      TimeoutMs: Cardinal = 600000; Const ProfileDir: String = ''; Const Effort: String = '';
      Const DeveloperInstructions: String = ''; Mode: TAssistantMode = amInspect;
      Const ProjectRoot: String = ''; Const AttachmentsJson: String = ''; Const EventsFile: String = '');
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Steer(Const Text: String): Boolean; Overload;
    { Same stored refs as a Grok steer. Unresolved pictures are not queued and are not described in text. }
    Function Steer(Const Text, AttachmentsJson: String): Boolean; Overload;
    Property LastSteerError: String Read FLastSteerError;
    Function Snapshot: TCodexRunSnapshot;
    Function TurnSnapshot: TAssistantTurnSnapshot;
    Function ContextUsage: TCodexContextUsage;
    Function TakeEvents: TAssistantEventArray;
    Function HasPendingTool: Boolean;
    { Caller must run on the IDE thread. Returns after at most one tool.
      It never waits for process or network output. }
    Procedure ServiceTool;
    Function ServiceOneTool(Out Tool: TCodexToolRequest; Out Text: String; Out OK: Boolean): Boolean;
    { Queues one tool for ServiceOneTool without a Codex process. Tests only. }
    Procedure QueueToolForTest(Const ToolName, ArgumentsJson: String);
  End;

/// Ask summary for one Codex tool call. content is the new text when new_text and text are empty.
Function CodexToolApprovalSummary(Const ArgumentsJson: String): String;

Implementation

Uses
  fpjson, jsonparser, AssistantCodexHandshake, AssistantCodexProfile, AssistantTools, AssistantImages, AssistantRecovery,
  AssistantToolBroker, AssistantConfig, AssistantMCPBridge, AssistantWorkTarget;

Constructor TAssistantCodexRun.Create(Const Executable, Cwd, Model, Prompt,
    ToolsJson, RunId: String; TimeoutMs: Cardinal; Const ProfileDir: String; Const Effort: String;
    Const DeveloperInstructions: String; Mode: TAssistantMode; Const ProjectRoot: String;
    Const AttachmentsJson: String; Const EventsFile: String);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FEvents := TAssistantEventLog.Create(EventsFile);
  FExecutable := Executable;
  FCwd := Cwd;
  FModel := Model;
  FPrompt := Prompt;
  FToolsJson := ToolsJson;
  FRunId := RunId;
  FTimeout := TimeoutMs;
  ReconnectDelayMs := DefaultReconnectIntervalSeconds * 1000;
  If Assigned(AssistantChatConfig) And (AssistantChatConfig.ReconnectIntervalSeconds > 0) Then
    ReconnectDelayMs := Cardinal(AssistantChatConfig.ReconnectIntervalSeconds) * 1000;
  FProfile := ProfileDir;
  FEffort := Effort;
  FDeveloperInstructions := DeveloperInstructions;
  FMode := Mode;
  FProjectRoot := ProjectRoot;
  FAttachments := AttachmentsJson;
  FSnapshot.State := crsConnecting;
  FSnapshot.ContextUsage := EmptyCodexContextUsage;
End;

Destructor TAssistantCodexRun.Destroy;
Var
  Servicing: Boolean;
Begin
  { The detached reaper may outlive a cancelled runtime while an IDE tool is
    still returning from a callback. Keep its handoff state alive until then. }
  Repeat
    EnterCriticalSection(FLock);
    Try
      Servicing := FToolServicing;
    Finally
      LeaveCriticalSection(FLock);
    End;
    If Servicing Then Sleep(1);
  Until Not Servicing;
  { TThread.Destroy joins. Owner must poll Snapshot.Done before destruction
    to keep Lazarus responsive, including after cancelling during shutdown. }
  Inherited Destroy;
  FreeAndNil(FEvents);
  DoneCriticalSection(FLock);
End;

Procedure TAssistantCodexRun.Cancel;
Begin
  InterlockedExchange(FCancelled, 1);
End;

Function TAssistantCodexRun.Cancelled: Boolean;
Begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
End;

Function TAssistantCodexRun.Steer(Const Text: String): Boolean;
Begin
  Result := Steer(Text, '');
End;

Function TAssistantCodexRun.Steer(Const Text, AttachmentsJson: String): Boolean;
Var
  InputJson, ErrorText: String;
  HasPictures: Boolean;
Begin
  Result := False;
  FLastSteerError := '';
  HasPictures := (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]');
  If (Trim(Text) = '') And (Not HasPictures) Then Exit;
  If Not CodexUserInputJson(FProjectRoot, Text, AttachmentsJson, InputJson, ErrorText) Then
    Begin
      FLastSteerError := ErrorText;
      Exit;
    End;
  EnterCriticalSection(FLock);
  Try
    Result := Not Cancelled And Not FSnapshot.Done And (FSteerInput = '') And
      (Length(Text) <= 65536) And (Length(InputJson) <= 65536);
    If Result Then
      Begin
        ReplayUnsafe := True;
        FSteer := Text;
        FSteerInput := InputJson;
      End
    Else If FSteerInput <> '' Then
      FLastSteerError := 'A steer is already queued.'
    Else
      FLastSteerError := 'The steer could not be queued.';
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAssistantCodexRun.Snapshot: TCodexRunSnapshot;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FSnapshot;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAssistantCodexRun.NoteEvent(Kind: TAssistantEventKind; Const Text: String; Const ToolName: String;
  Const ToolId: String; Ok: Boolean; Const AttachmentsJson: String);
Var
  Event: TAssistantEvent;
Begin
  If Not Assigned(FEvents) Then
    Exit;
  Event := MakeAssistantEvent(Kind, apWaiting, Text, ToolName, ToolId, Ok, 0, AttachmentsJson);
  If Kind In [aekToolStarted, aekToolCompleted] Then
    Event.Phase := apTools;
  FEvents.Append(Event);
End;

Function TAssistantCodexRun.ContextUsage: TCodexContextUsage;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FSnapshot.ContextUsage;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAssistantCodexRun.TakeEvents: TAssistantEventArray;
Begin
  If Assigned(FEvents) Then
    Result := FEvents.TakePending
  Else
    Result := Nil;
End;

Function TAssistantCodexRun.TurnSnapshot: TAssistantTurnSnapshot;
Var
  Pending: Boolean;
Begin
  Result := EmptyAssistantTurnSnapshot;
  EnterCriticalSection(FLock);
  Try
    Result.Content := FSnapshot.Content;
    Result.Thinking := FSnapshot.Thinking;
    Result.ErrorText := FSnapshot.ErrorText;
    Result.Done := FSnapshot.Done;
    Pending := FToolPending And Not FToolReady;
    Result.Usage.Reported := FSnapshot.ContextUsage.Reported;
    Result.Usage.ContextWindow := FSnapshot.ContextUsage.ModelContextWindow;
    Result.Usage.ContextTokens := FSnapshot.ContextUsage.Last.TotalTokens;
    Result.Usage.InputTokens := FSnapshot.ContextUsage.Last.InputTokens;
    Result.Usage.OutputTokens := FSnapshot.ContextUsage.Last.OutputTokens;
    Result.Usage.CachedInputTokens := FSnapshot.ContextUsage.Last.CachedInputTokens;
    Result.Usage.ReasoningTokens := FSnapshot.ContextUsage.Last.ReasoningOutputTokens;
    Result.Usage.HasCached := FSnapshot.ContextUsage.Last.CachedInputTokens > 0;
    Result.Usage.HasReasoning := FSnapshot.ContextUsage.Last.ReasoningOutputTokens > 0;
  Finally
    LeaveCriticalSection(FLock);
  End;
  If Pending Then
    Result.Phase := AssistantPhaseRunning
  Else If Result.Content <> '' Then
    Result.Phase := AssistantPhaseStreaming
  Else If Result.Thinking <> '' Then
    Result.Phase := AssistantPhaseThinking
  Else
    Result.Phase := AssistantPhaseWaiting;
  If Assigned(FEvents) Then
    Begin
      Result.EventsFile := FEvents.FileName;
      Result.ReplaySafe := Not FEvents.ToolRan;
      If FEvents.ToolRan Then
        Result.ToolCount := 1;
    End;
End;

Function TAssistantCodexRun.HasPendingTool: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FToolPending And Not FToolReady And Not FSnapshot.Done;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAssistantCodexRun.Publish(Client: TAssistantCodexClient);
Var
  Index: Integer;
Begin
  EnterCriticalSection(FLock);
  Try
    Index := High(FSnapshot.Images);
    If (Index >= 0) And Not FSnapshot.Images[Index].Finished And (FSnapshot.Images[Index].RequestId = Client.CompletedImageCall) Then
      Begin
        FSnapshot.Images := Copy(FSnapshot.Images);
        FSnapshot.Images[Index].ErrorText := Client.GeneratedImageError;
        If Client.GeneratedImageError = '' Then
          If SameText(ExtractFileExt(FSnapshot.Images[Index].Destination), '.png') And (Client.GeneratedImage.Mime = 'image/png') Then
            FSnapshot.Images[Index].Image := Client.GeneratedImage
          Else
            FSnapshot.Images[Index].ErrorText := 'Generated image format differs from the approved destination extension.';
        FSnapshot.Images[Index].Finished := True;
      End;
    FSnapshot.State := Client.State;
    FSnapshot.Content := Client.Content;
    FSnapshot.Thinking := Client.Thinking;
    FSnapshot.ErrorText := Client.LastError;
    FSnapshot.ContextUsage := Client.ContextUsage;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function CodexToolApprovalSummary(Const ArgumentsJson: String): String;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Path, OldText, NewText: String;
Begin
  Path := '';
  OldText := '';
  NewText := '';
  Data := Nil;
  Try
    Data := GetJSON(ArgumentsJson);
  Except
    Data := Nil;
  End;
  If Data Is TJSONObject Then
    Begin
      Obj := TJSONObject(Data);
      Path := Obj.Get('path', '');
      OldText := Obj.Get('old_text', '');
      NewText := Obj.Get('new_text', '');
      If NewText = '' Then
        NewText := Obj.Get('text', '');
      { write_file and write_markdown send the body in content, not new_text or text. }
      If NewText = '' Then
        NewText := Obj.Get('content', '');
    End;
  Data.Free;
  If (Path = '') And (OldText = '') And (NewText = '') Then
    NewText := ArgumentsJson;
  Result := MCPApprovalSummary(Path, OldText, NewText);
End;

Procedure TAssistantCodexRun.QueueToolForTest(Const ToolName, ArgumentsJson: String);
Begin
  EnterCriticalSection(FLock);
  Try
    FTool := Default(TCodexToolRequest);
    FTool.Tool := ToolName;
    FTool.Arguments := ArgumentsJson;
    FTool.CallId := 'test-call';
    FToolPending := True;
    FToolReady := False;
    FToolServicing := False;
    FSnapshot.Done := False;
    ReplayUnsafe := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
  NoteEvent(aekToolStarted, ArgumentsJson, ToolName, 'test-call');
End;

Procedure TAssistantCodexRun.ServiceTool;
Var
  Tool: TCodexToolRequest;
  Text: String;
  OK: Boolean;
Begin
  ServiceOneTool(Tool, Text, OK);
End;

Function TAssistantCodexRun.ServiceOneTool(Out Tool: TCodexToolRequest; Out Text: String; Out OK: Boolean): Boolean;
Var
  ErrorText, Attachments, TargetIdentity, Destination, ApprovalSummary: String;
  Overwrite, PendingImage: Boolean;
  Index: Integer;
  ImageRefs: TAssistantImageRefArray;
Begin
  Result := False;
  Tool := Default(TCodexToolRequest);
  Text := '';
  OK := False;
  SetLength(ImageRefs, 0);
  EnterCriticalSection(FLock);
  Try
    If Cancelled Or FSnapshot.Done Or Not FToolPending Or FToolReady Or FToolServicing Then Exit;
    Tool := FTool;
    Index := High(FSnapshot.Images);
    PendingImage := (Index >= 0) And Not FSnapshot.Images[Index].Finished;
    ReplayUnsafe := True;
    FToolServicing := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
  Try
    { One executor. Preflight is the Grok gate before Ask. After Ask succeeds, that gate runs
      with approval skipped so the dialog is not shown twice. }
    TargetIdentity := AssistantTarget.Identity;
    ApprovalSummary := CodexToolApprovalSummary(Tool.Arguments);
    If Not AssistantToolPreflight(Tool.Tool, Tool.Arguments, FMode, ErrorText) Then
      Begin
        OK := False;
        Text := ErrorText;
      End
    Else If (Tool.Tool = 'write_image') And PendingImage Then
      Text := 'The previous image request is still pending.'
    Else If (Tool.Tool = 'write_image') And Not CodexImageDestination(Tool.Arguments, Destination, ApprovalSummary, ErrorText, Overwrite) Then
      Text := ErrorText
    Else If Not ApproveToolIfNeeded(Tool.Tool, Tool.CallId, ApprovalSummary, ErrorText) Then
      Begin
        OK := False;
        Text := ErrorText;
      End
    Else If AssistantTarget.Identity <> TargetIdentity Then
      Begin
        OK := False;
        ErrorText := 'Assistant target changed during approval.';
        Text := ErrorText;
      End
    Else If Tool.Tool = 'write_image' Then
      Begin
        EnterCriticalSection(FLock);
        Try
          If Not Cancelled Then
            Begin
              Index := Length(FSnapshot.Images);
              SetLength(FSnapshot.Images, Index + 1);
              FSnapshot.Images[Index].RequestId := Tool.CallId;
              FSnapshot.Images[Index].Destination := Destination;
              FSnapshot.Images[Index].Overwrite := Overwrite;
              OK := True;
              Text := 'Destination reserved. Invoke native image generation exactly once with the requested prompt.';
            End;
        Finally
          LeaveCriticalSection(FLock);
        End;
      End
    Else
      Begin
        OK := ExecuteAssistantToolForMode(Tool.Tool, Tool.Arguments, Tool.CallId, FMode, Text, ErrorText, ImageRefs, True);
        If Not OK Then Text := ErrorText;
      End;
    Attachments := '';
    If OK Then Attachments := AssistantImageRefsToJson(ImageRefs);
    Result := True;
    EnterCriticalSection(FLock);
    Try
      If Not Cancelled And Not FSnapshot.Done And FToolPending Then
        Begin
          FToolResult := Text;
          FToolAttachments := Attachments;
          FToolSuccess := OK;
          FToolReady := True;
        End;
    Finally
      LeaveCriticalSection(FLock);
    End;
  Finally
    EnterCriticalSection(FLock);
    Try
      FToolServicing := False;
    Finally
      LeaveCriticalSection(FLock);
    End;
  End;
  If Result Then
    NoteEvent(aekToolCompleted, Text, Tool.Tool, Tool.CallId, OK, Attachments);
End;

Procedure TAssistantCodexRun.Execute;
Var
  Client: TAssistantCodexClient;
  Deadline, Now, PausedAt, RetryAt: QWord;
  Tool: TCodexToolRequest;
  SteerInput, ToolResult, ToolAttachments, ToolCallId, ProfileError: String;
  Stage: Integer;
  HaveResult, ToolSuccess, IdeWaiting, DeadlinePaused: Boolean;
  Env: TStringList;
  RunDirectory: String;
Begin
  Client := Nil;
  Env := Nil;
  NoteEvent(aekTurnStarted, FModel);
  Try
    Try
      If Cancelled Then
        Begin
          EnterCriticalSection(FLock);
          Try
            FSnapshot.State := crsFailed;
            FSnapshot.ErrorText := 'Codex run cancelled.';
          Finally
            LeaveCriticalSection(FLock);
          End;
          Exit;
        End;
      Client := TAssistantCodexClient.Create(5000);
      RunDirectory := FCwd;
      If FProfile <> '' Then
        Begin
          If Not PrepareCodexProfile(FProfile, ProfileError) Then
            Begin
              EnterCriticalSection(FLock);
              Try
                FSnapshot.State := crsFailed;
                FSnapshot.ErrorText := ProfileError;
              Finally
                LeaveCriticalSection(FLock);
              End;
              Exit;
            End;
          RunDirectory := FProfile;
          Env := TStringList.Create;
          CodexProfileEnvironment(FProfile, Env);
        End;
      If Not Client.Connect(FExecutable, RunDirectory, Env, False, @Cancelled) Then
        Begin
          Publish(Client);
          Exit;
        End;
      Deadline := GetTickCount64 + FTimeout;
      DeadlinePaused := False;
      PausedAt := 0;
      RetryAt := 0;
      Stage := 0;
      Repeat
        Now := GetTickCount64;
        IdeWaiting := False;
        EnterCriticalSection(FLock);
        Try
          { Time spent in an IDE dynamic tool does not consume the turn limit. }
          IdeWaiting := FToolPending And Not FToolReady;
        Finally
          LeaveCriticalSection(FLock);
        End;
        If Cancelled Then
          Client.CancelConnection
        Else If Client.State = crsWaitingReconnect Then
          Begin
            If RetryAt = 0 Then RetryAt := Now + ReconnectDelayMs;
            If Now >= RetryAt Then
              Begin
                Client.StartTurn('Continue the interrupted task from the work already recorded in this thread.', FEffort);
                RetryAt := 0;
                Deadline := Now + FTimeout;
              End;
          End
        Else If IdeWaiting Then
          Begin
            If Not DeadlinePaused Then
              Begin
                PausedAt := Now;
                DeadlinePaused := True;
              End;
          End
        Else
          Begin
            If DeadlinePaused Then
              Begin
                Deadline := Deadline + (Now - PausedAt);
                DeadlinePaused := False;
              End;
            If Now >= Deadline Then
              Client.CancelConnection(Format(
                'Codex turn timed out after %d s while waiting for the model or an approval result.',
                [FTimeout Div 1000]));
          End;
        Client.Pump;
        If (Client.State = crsConnecting) And (Client.Authentication.State = ccsNeedsSignIn) Then
          Begin
            EnterCriticalSection(FLock);
            Try
              FSnapshot.State := crsFailed;
              FSnapshot.ErrorText := 'Sign in to the qualified Codex runtime with ChatGPT before starting a run.';
            Finally
              LeaveCriticalSection(FLock);
            End;
            Exit;
          End;
        If (Stage = 0) And (Client.State = crsReady) Then
          Begin
            If Client.ListModels Then Stage := 4;
          End
            Else If (Stage = 4) And (Client.ModelsJson <> '') Then
              Begin
                If Not CodexModelSelectionValid(Client.ModelsJson, FModel, FEffort) Then
                  Client.CancelConnection('Codex selected model or reasoning effort is no longer available. Check this connection and select an available model and effort.')
                Else If Client.CheckToolIsolation Then Stage := 3;
              End
            Else If (Stage = 3) And Client.ToolIsolationChecked Then
              Begin
                If Client.StartThread(RunDirectory, FModel, FToolsJson, FDeveloperInstructions) Then Stage := 1;
              End
                Else If (Stage = 1) And (Client.State = crsReady) Then
                  Begin
                    If Client.StartTurn(FPrompt, FEffort, FProjectRoot, FAttachments) Then Stage := 2;
                  End;
        EnterCriticalSection(FLock);
        Try
          HaveResult := FToolPending And FToolReady;
          If HaveResult Then
            Begin
              ToolCallId := FTool.CallId;
              ToolResult := FToolResult;
              ToolAttachments := FToolAttachments;
              ToolSuccess := FToolSuccess;
              FToolPending := False;
              FToolReady := False;
              FToolResult := '';
              FToolAttachments := '';
            End;
          SteerInput := FSteerInput;
        Finally
          LeaveCriticalSection(FLock);
        End;
        { A failed send can stop the process. Never hold the UI snapshot lock
          across client operations, process cleanup or any other wait. }
        If HaveResult Then Client.CompleteTool(ToolCallId, ToolResult, FProjectRoot, ToolAttachments, ToolSuccess);
        If Client.TakeTool(Tool) Then
          Begin
            EnterCriticalSection(FLock);
            Try
              FTool := Tool;
              FToolPending := True;
              ReplayUnsafe := True;
            Finally
              LeaveCriticalSection(FLock);
            End;
            NoteEvent(aekToolStarted, Tool.Arguments, Tool.Tool, Tool.CallId);
          End;
        If (SteerInput <> '') And Client.SteerInput(SteerInput) Then
          Begin
            EnterCriticalSection(FLock);
            Try
              FSteer := '';
              FSteerInput := '';
            Finally
              LeaveCriticalSection(FLock);
            End;
          End;
        Publish(Client);
        If Client.State In [crsFailed, crsCompleted] Then Break;
        Sleep(5);
      Until False;
    Except
      On E: Exception Do
        Begin
          EnterCriticalSection(FLock);
          Try
            FSnapshot.State := crsFailed;
            FSnapshot.ErrorText := 'Codex worker failed; no metered fallback was attempted.';
            If E.Message <> '' Then
              FSnapshot.ErrorText := FSnapshot.ErrorText + ' ' + E.Message;
          Finally
            LeaveCriticalSection(FLock);
          End;
        End;
    End;
  Finally
    Client.Free;
    Env.Free;
    EnterCriticalSection(FLock);
    Try
      If Not ReplayUnsafe And Not Cancelled And (FSnapshot.ErrorText <> '') And
        (ClassifyDroppedTransport(CodexRetryPrefix + FSnapshot.ErrorText, '', False).Action = araRetryLastAction) Then
        FSnapshot.ErrorText := CodexRetryPrefix + FSnapshot.ErrorText;
      FSnapshot.Done := True;
      FToolPending := False;
    Finally
      LeaveCriticalSection(FLock);
    End;
    If FSnapshot.ErrorText <> '' Then
      NoteEvent(aekError, FSnapshot.ErrorText, '', '', False)
    Else
      NoteEvent(aekTurnEnded, FSnapshot.Content);
  End;
End;
End.
