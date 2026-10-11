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
      Const DeveloperInstructions: String = ''; Mode: TAssistantMode = amInspect);
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Steer(Const Text: String): Boolean; Overload;
    { Refs are not queued. This protocol has no image item; the composer keeps the pictures. }
    Function Steer(Const Text, AttachmentsJson: String): Boolean; Overload;
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
  AssistantCodexHandshake, AssistantCodexProfile, AssistantTools;

Constructor TAssistantCodexRun.Create(Const Executable, Cwd, Model, Prompt,
    ToolsJson, RunId: String; TimeoutMs: Cardinal; Const ProfileDir: String; Const Effort: String;
    Const DeveloperInstructions: String; Mode: TAssistantMode);
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
Begin
  Result := False;
  { Do not store image refs as the steer note. The form keeps the 3.2 warning. }
  If (Not CodexImagesSupported) And (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]') Then Exit;
  EnterCriticalSection(FLock);
  Try
    Result := Not Cancelled And Not FSnapshot.Done And (FSteer = '') And
      (Length(Text) <= 65536) And (Text <> '');
    If Result Then FSteer := Text;
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
  ErrorText: String;
Begin
  Result := False;
  Tool := Default(TCodexToolRequest);
  Text := '';
  OK := False;
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
    OK := ExecuteAssistantToolForMode(Tool.Tool, Tool.Arguments, FMode, Text, ErrorText);
    If Not OK Then Text := ErrorText;
    Result := True;
    EnterCriticalSection(FLock);
    Try
      If Not Cancelled And Not FSnapshot.Done And FToolPending Then
        Begin
          FToolResult := Text;
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
  SteerText, ToolResult, ToolCallId, ProfileError: String;
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
      If Not Client.Connect(FExecutable, RunDirectory, Env) Then
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
            If Client.CheckToolIsolation Then Stage := 3;
          End
            Else If (Stage = 3) And Client.ToolIsolationChecked Then
              Begin
                If Client.StartThread(RunDirectory, FModel, FToolsJson, FDeveloperInstructions) Then Stage := 1;
              End
                Else If (Stage = 1) And (Client.State = crsReady) Then
                  Begin
                    If Client.StartTurn(FPrompt, FEffort) Then Stage := 2;
                  End;
        EnterCriticalSection(FLock);
        Try
          HaveResult := FToolPending And FToolReady;
          If HaveResult Then
            Begin
              ToolCallId := FTool.CallId;
              ToolResult := FToolResult;
              ToolSuccess := FToolSuccess;
              FToolPending := False;
              FToolReady := False;
              FToolResult := '';
            End;
          SteerText := FSteer;
        Finally
          LeaveCriticalSection(FLock);
        End;
        { A failed send can stop the process. Never hold the UI snapshot lock
          across client operations, process cleanup or any other wait. }
        If HaveResult Then Client.CompleteTool(ToolCallId, ToolResult, ToolSuccess);
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
        If (SteerText <> '') And Client.Steer(SteerText) Then
          Begin
            EnterCriticalSection(FLock);
            Try
              FSteer := '';
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
