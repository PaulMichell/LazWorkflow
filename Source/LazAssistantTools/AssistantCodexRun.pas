Unit AssistantCodexRun;

{ Thread boundary for a managed Codex run. The worker owns the process/client;
  the IDE timer calls ServiceTool on the main thread. No Synchronize, IDE
  pointers, or main-thread waits occur inside Execute. Destroy only after Done. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, AssistantCodexClient, AssistantToolBroker;
Type
  TCodexRunSnapshot = Record
    State: TCodexRunState;
    Content, Thinking, ErrorText: String;
    Done: Boolean;
  End;
  TAssistantCodexRun = Class(TThread)
  Private
    FLock: TRTLCriticalSection;
    FExecutable, FCwd, FModel, FPrompt, FToolsJson, FRunId, FProfile, FEffort: String;
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
      TimeoutMs: Cardinal = 600000; Const ProfileDir: String = ''; Const Effort: String = '');
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Steer(Const Text: String): Boolean;
    Function Snapshot: TCodexRunSnapshot;
    { Caller must run on the broker's owning IDE thread. Returns after at most
      one short buffer operation; it never waits for process/network output. }
    Procedure ServiceTool(Broker: TAssistantToolBroker);
    Function ServiceOneTool(Broker: TAssistantToolBroker; Out Tool: TCodexToolRequest;
      Out Text: String; Out OK: Boolean): Boolean;
  End;
Implementation
Uses AssistantCodexHandshake, AssistantCodexProfile;
Constructor TAssistantCodexRun.Create(Const Executable, Cwd, Model, Prompt,
  ToolsJson, RunId: String; TimeoutMs: Cardinal; Const ProfileDir: String; Const Effort: String);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FExecutable := Executable; FCwd := Cwd; FModel := Model; FPrompt := Prompt;
  FToolsJson := ToolsJson; FRunId := RunId; FTimeout := TimeoutMs; FProfile := ProfileDir;
  FEffort := Effort; FSnapshot.State := crsConnecting;
End;
Destructor TAssistantCodexRun.Destroy;
Begin
  { TThread.Destroy joins. Owner must poll Snapshot.Done before destruction
    to keep Lazarus responsive, including after cancelling during shutdown. }
  Inherited Destroy;
  DoneCriticalSection(FLock);
End;
Procedure TAssistantCodexRun.Cancel;
Begin InterlockedExchange(FCancelled, 1); End;
Function TAssistantCodexRun.Cancelled: Boolean;
Begin Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0; End;
Function TAssistantCodexRun.Steer(Const Text: String): Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := Not Cancelled And Not FSnapshot.Done And (FSteer = '') And
      (Length(Text) <= 65536) And (Text <> '');
    If Result Then FSteer := Text;
  Finally LeaveCriticalSection(FLock); End;
End;
Function TAssistantCodexRun.Snapshot: TCodexRunSnapshot;
Begin
  EnterCriticalSection(FLock);
  Try Result := FSnapshot; Finally LeaveCriticalSection(FLock); End;
End;
Procedure TAssistantCodexRun.Publish(Client: TAssistantCodexClient);
Begin
  EnterCriticalSection(FLock);
  Try
    FSnapshot.State := Client.State;
    FSnapshot.Content := Client.Content;
    FSnapshot.Thinking := Client.Thinking;
    FSnapshot.ErrorText := Client.LastError;
  Finally LeaveCriticalSection(FLock); End;
End;
Procedure TAssistantCodexRun.ServiceTool(Broker: TAssistantToolBroker);
Var Tool: TCodexToolRequest; Text: String; OK: Boolean;
Begin ServiceOneTool(Broker, Tool, Text, OK); End;
Function TAssistantCodexRun.ServiceOneTool(Broker: TAssistantToolBroker;
  Out Tool: TCodexToolRequest; Out Text: String; Out OK: Boolean): Boolean;
Var ErrorText: String;
Begin
  Result := False; Tool := Default(TCodexToolRequest); Text := ''; OK := False;
  EnterCriticalSection(FLock);
  Try
    If Cancelled Or FSnapshot.Done Or Not FToolPending Or FToolReady Or FToolServicing Then Exit;
    Tool := FTool;
    FToolServicing := True;
  Finally LeaveCriticalSection(FLock); End;
  OK := Broker.Execute(FRunId, Tool.Tool, Tool.Arguments, Text, ErrorText);
  If Not OK Then Text := ErrorText;
  Result := True;
  EnterCriticalSection(FLock);
  Try
    If Not Cancelled And Not FSnapshot.Done And FToolPending Then
      Begin FToolResult := Text; FToolSuccess := OK; FToolReady := True; End;
    FToolServicing := False;
  Finally LeaveCriticalSection(FLock); End;
End;
Procedure TAssistantCodexRun.Execute;
Var Client: TAssistantCodexClient; Deadline: QWord; Tool: TCodexToolRequest;
  SteerText, ToolResult, ToolCallId: String; Stage: Integer;
  HaveResult, ToolSuccess: Boolean; Env: TStringList; RunDirectory: String;
Begin
  Client := Nil; Env := Nil;
  Try
    Try
      If Cancelled Then
        Begin
          EnterCriticalSection(FLock);
          Try FSnapshot.State := crsFailed; FSnapshot.ErrorText := 'Codex run cancelled.';
          Finally LeaveCriticalSection(FLock); End;
          Exit;
        End;
      Client := TAssistantCodexClient.Create(5000);
      RunDirectory := FCwd;
      If FProfile <> '' Then
        Begin
          RunDirectory := FProfile;
          Env := TStringList.Create;
          CodexProfileEnvironment(FProfile, Env);
        End;
      If Not Client.Connect(FExecutable, RunDirectory, Env) Then Begin Publish(Client); Exit; End;
      Deadline := GetTickCount64 + FTimeout;
      Stage := 0;
      Repeat
        If Cancelled Then Client.CancelConnection;
        If GetTickCount64 >= Deadline Then Client.CancelConnection;
        Client.Pump;
        If (Client.State = crsConnecting) And (Client.Authentication.State = ccsNeedsSignIn) Then
          Begin
            EnterCriticalSection(FLock);
            Try
              FSnapshot.State := crsFailed;
              FSnapshot.ErrorText := 'Sign in to the qualified Codex runtime with ChatGPT before starting a run.';
            Finally LeaveCriticalSection(FLock); End;
            Exit;
          End;
        If (Stage = 0) And (Client.State = crsReady) Then
          Begin
            If Client.CheckToolIsolation Then Stage := 3;
          End
        Else If (Stage = 3) And Client.ToolIsolationChecked Then
          Begin If Client.StartThread(RunDirectory, FModel, FToolsJson) Then Stage := 1; End
        Else If (Stage = 1) And (Client.State = crsReady) Then
          Begin
            If Client.StartTurn(FPrompt, FEffort) Then Stage := 2;
          End;
        EnterCriticalSection(FLock);
        Try
          HaveResult := FToolPending And FToolReady;
          If HaveResult Then
            Begin
              ToolCallId := FTool.CallId; ToolResult := FToolResult; ToolSuccess := FToolSuccess;
              FToolPending := False; FToolReady := False; FToolResult := '';
            End;
          SteerText := FSteer;
        Finally LeaveCriticalSection(FLock); End;
        { A failed send can stop the process. Never hold the UI snapshot lock
          across client operations, process cleanup or any other wait. }
        If HaveResult Then Client.CompleteTool(ToolCallId, ToolResult, ToolSuccess);
        If Client.TakeTool(Tool) Then
          Begin
            EnterCriticalSection(FLock);
            Try FTool := Tool; FToolPending := True;
            Finally LeaveCriticalSection(FLock); End;
          End;
        If (SteerText <> '') And Client.Steer(SteerText) Then
          Begin
            EnterCriticalSection(FLock);
            Try FSteer := ''; Finally LeaveCriticalSection(FLock); End;
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
          Finally LeaveCriticalSection(FLock); End;
        End;
    End;
  Finally
    Client.Free; Env.Free;
    EnterCriticalSection(FLock);
    Try FSnapshot.Done := True; FToolPending := False;
    Finally LeaveCriticalSection(FLock); End;
  End;
End;
End.
