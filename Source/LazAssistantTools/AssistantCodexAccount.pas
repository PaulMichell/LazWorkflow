Unit AssistantCodexAccount;

{ Account/model discovery runs off the IDE thread. No model turns are sent. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantCodexHandshake;

Type
  TCodexAccountSnapshot = Record
    Done: Boolean;
    State: TCodexConnectionState;
    LoginUrl, ModelsJson, ErrorText: String;
  End;
  TAssistantCodexAccount = Class(TThread)
  Private
    FLock: TRTLCriticalSection;
    FExecutable, FProfile: String;
    FLogin: Boolean;
    FCancelled: LongInt;
    FSnapshot: TCodexAccountSnapshot;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const Executable, ProfileDir: String; Login: Boolean);
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Snapshot: TCodexAccountSnapshot;
  End;

Implementation

Uses
  AssistantCodexClient, AssistantCodexProfile;

Constructor TAssistantCodexAccount.Create(Const Executable, ProfileDir: String; Login: Boolean);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FExecutable := Executable;
  FProfile := ProfileDir;
  FLogin := Login;
  FSnapshot.State := ccsInitializing;
End;

Destructor TAssistantCodexAccount.Destroy;
Begin
  Inherited Destroy;
  DoneCriticalSection(FLock);
End;

Procedure TAssistantCodexAccount.Cancel;
Begin
  InterlockedExchange(FCancelled, 1);
End;

Function TAssistantCodexAccount.Snapshot: TCodexAccountSnapshot;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FSnapshot;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAssistantCodexAccount.Execute;
Var
  Client: TAssistantCodexClient;
  Env: TStringList;
  Value: TCodexAccountSnapshot;
  Deadline: QWord;
  LoginStarted, ModelsRequested: Boolean;
Begin
  Client := Nil;
  Env := Nil;
  Value := Default(TCodexAccountSnapshot);
  Try
    Try
      If InterlockedCompareExchange(FCancelled, 0, 0) <> 0 Then Exit;
      If Not PrepareCodexProfile(FProfile, Value.ErrorText) Then Exit;
      Client := TAssistantCodexClient.Create(10000);
      Env := TStringList.Create;
      CodexProfileEnvironment(FProfile, Env);
      If Not Client.Connect(FExecutable, FProfile, Env) Then
        Begin
          Value.ErrorText := Client.LastError;
          Exit;
        End;
      Deadline := GetTickCount64 + 300000;
      LoginStarted := False;
      ModelsRequested := False;
      Repeat
        If (InterlockedCompareExchange(FCancelled, 0, 0) <> 0) Or
          (GetTickCount64 >= Deadline) Then Client.CancelConnection;
        Client.Pump;
        Value.State := Client.Authentication.State;
        Value.ErrorText := Client.LastError;
        Value.LoginUrl := Client.Authentication.LoginUrl;
        Value.ModelsJson := Client.ModelsJson;
        If Client.State = crsFailed Then Break;
        If Value.State = ccsNeedsSignIn Then
          Begin
            If Not FLogin Or LoginStarted Then Break;
            Client.StartLogin;
            LoginStarted := True;
          End;
        If (Value.State = ccsSubscriptionAuthenticated) And Not ModelsRequested Then
          ModelsRequested := Client.ListModels;
        EnterCriticalSection(FLock);
        Try
          FSnapshot := Value;
        Finally
          LeaveCriticalSection(FLock);
        End;
        If Value.ModelsJson <> '' Then Break;
        Sleep(10);
      Until False;
    Except
      On E: Exception Do Value.ErrorText := 'Codex account connection failed.';
    End;
  Finally
    Client.Free;
    Env.Free;
    Value.Done := True;
    If Value.ErrorText <> '' Then Value.State := ccsFailed;
    EnterCriticalSection(FLock);
    Try
      FSnapshot := Value;
    Finally
      LeaveCriticalSection(FLock);
    End;
  End;
End;
End.
