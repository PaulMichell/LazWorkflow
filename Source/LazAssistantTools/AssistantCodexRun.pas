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
  Classes, SysUtils, AssistantCodexClient, AssistantConversation;

Type
  TCodexRunSnapshot = Record
    State: TCodexRunState;
    Content, Thinking, ErrorText: String;
    Done: Boolean;
  End;
  TAssistantCodexRun = Class(TThread)
  Private
    FLock: TRTLCriticalSection;
    FExecutable, FCwd, FModel, FPrompt, FToolsJson, FRunId, FProfile, FEffort, FDeveloperInstructions: String;
    FProjectRoot, FAttachments, FSteerInput, FToolAttachments, FLastSteerError: String;
    FMode: TAssistantMode;
    FSnapshot: TCodexRunSnapshot;
    FTool: TCodexToolRequest;
    FToolPending, FToolServicing, FToolReady, FToolSuccess: Boolean;
    FToolResult, FSteer: String;
    FTimeout: Cardinal;
    FCancelled: LongInt;
    Function Cancelled: Boolean;
    Procedure Publish(Client: TAssistantCodexClient);
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const Executable, Cwd, Model, Prompt, ToolsJson, RunId: String;
      TimeoutMs: Cardinal = 600000; Const ProfileDir: String = ''; Const Effort: String = '';
      Const DeveloperInstructions: String = ''; Mode: TAssistantMode = amInspect;
      Const ProjectRoot: String = ''; Const AttachmentsJson: String = '');
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Steer(Const Text: String): Boolean; Overload;
    { Same stored refs as a Grok steer. Unresolved pictures are not queued and are not described in text. }
    Function Steer(Const Text, AttachmentsJson: String): Boolean; Overload;
    Property LastSteerError: String Read FLastSteerError;
    Function Snapshot: TCodexRunSnapshot;
    Function HasPendingTool: Boolean;
    { Caller must run on the IDE thread. Returns after at most one tool.
      It never waits for process or network output. }
    Procedure ServiceTool;
    Function ServiceOneTool(Out Tool: TCodexToolRequest; Out Text: String; Out OK: Boolean): Boolean;
    { Queues one tool for ServiceOneTool without a Codex process. Tests only. }
    Procedure QueueToolForTest(Const ToolName, ArgumentsJson: String);
  End;

Implementation

Uses
  AssistantCodexHandshake, AssistantCodexProfile, AssistantTools, AssistantImages;

Constructor TAssistantCodexRun.Create(Const Executable, Cwd, Model, Prompt,
    ToolsJson, RunId: String; TimeoutMs: Cardinal; Const ProfileDir: String; Const Effort: String;
    Const DeveloperInstructions: String; Mode: TAssistantMode; Const ProjectRoot: String;
    Const AttachmentsJson: String);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FExecutable := Executable;
  FCwd := Cwd;
  FModel := Model;
  FPrompt := Prompt;
  FToolsJson := ToolsJson;
  FRunId := RunId;
  FTimeout := TimeoutMs;
  FProfile := ProfileDir;
  FEffort := Effort;
  FDeveloperInstructions := DeveloperInstructions;
  FMode := Mode;
  FProjectRoot := ProjectRoot;
  FAttachments := AttachmentsJson;
  FSnapshot.State := crsConnecting;
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
Begin
  EnterCriticalSection(FLock);
  Try
    FSnapshot.State := Client.State;
    FSnapshot.Content := Client.Content;
    FSnapshot.Thinking := Client.Thinking;
    FSnapshot.ErrorText := Client.LastError;
  Finally
    LeaveCriticalSection(FLock);
  End;
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
  Finally
    LeaveCriticalSection(FLock);
  End;
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
  ErrorText, Attachments: String;
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
    FToolServicing := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
  Try
    { Shared catalogue only. An unknown name is an error; do not fall through to the broker. }
    { Codex does not call the remote waiter and does not raise approval_requested. }
    OK := ExecuteAssistantToolForMode(Tool.Tool, Tool.Arguments, '', FMode, Text, ErrorText, ImageRefs);
    If Not OK Then Text := ErrorText;
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
End;

Procedure TAssistantCodexRun.Execute;
Var
  Client: TAssistantCodexClient;
  Deadline, Now, PausedAt: QWord;
  Tool: TCodexToolRequest;
  SteerInput, ToolResult, ToolAttachments, ToolCallId, ProfileError: String;
  Stage: Integer;
  HaveResult, ToolSuccess, IdeWaiting, DeadlinePaused: Boolean;
  Env: TStringList;
  RunDirectory: String;
Begin
  Client := Nil;
  Env := Nil;
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
            Finally
              LeaveCriticalSection(FLock);
            End;
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
      FSnapshot.Done := True;
      FToolPending := False;
    Finally
      LeaveCriticalSection(FLock);
    End;
  End;
End;
End.
