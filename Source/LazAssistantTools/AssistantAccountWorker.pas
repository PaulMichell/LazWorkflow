Unit AssistantAccountWorker;

{ Window-owned account queries and package shutdown (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, AssistantConnections, AssistantAccountUsage, GrokOAuth;

Type
  TAccountUsageWorker = Class(TThread)
  Private
    Slot: TAccountUsageSlot;
    Connection: TAssistantConnection;
    RuntimePath, ProfileDir: String;
    Detached: Boolean;
    LocalClient: TGrokOAuthClient;
    Original: TGrokOAuthTokens;
    Constructor CreateRequest(Const ConnectionId, Backend: String);
    Procedure CaptureTokens;
    Procedure CommitTokens;
    Procedure AcquireToken;
  Protected
    Procedure Execute; Override;
  Public
    Snapshot: TAccountUsageSnapshot;
    QueryOk: Boolean;
    Constructor CreateForSettings(Item: TAssistantConnection);
    Constructor CreateForProject(UsageSlot: TAccountUsageSlot; Const ConnectionId, Backend, Model, ApiBase, KeySource, KeyEnv, KeyValue,
      Preset, WireApi, CodexRuntime, CodexProfile: String);
    Destructor Destroy; Override;
    Procedure Detach;
  End;

Procedure DrainAccountWorkers;

Implementation

Uses
  SysUtils, WorkflowLog, AssistantCodexUsage;

Var
  Workers: TList;
  TokenLock: TRTLCriticalSection;

Constructor TAccountUsageWorker.CreateForSettings(Item: TAssistantConnection);
Begin
  CreateRequest(Item.Id, Item.Backend);
End;

Constructor TAccountUsageWorker.CreateRequest(Const ConnectionId, Backend: String);
Var
  Index: Integer;
  Previous: TAccountUsageWorker;
Begin
  Inherited Create(True);
  For Index := Workers.Count - 1 DownTo 0 Do
    Begin
      Previous := TAccountUsageWorker(Workers[Index]);
      If Previous.Detached And Previous.Finished Then
        Previous.Free;
    End;
  Connection := TAssistantConnection.Create;
  Connection.Id := ConnectionId;
  Connection.Backend := Backend;
  Workers.Add(Self);
End;

Constructor TAccountUsageWorker.CreateForProject(UsageSlot: TAccountUsageSlot; Const ConnectionId, Backend, Model, ApiBase, KeySource, KeyEnv,
  KeyValue, Preset, WireApi, CodexRuntime, CodexProfile: String);
Begin
  CreateRequest(ConnectionId, Backend);
  Connection.Model := Model;
  Connection.ApiBase := ApiBase;
  Connection.KeySource := KeySource;
  Connection.KeyEnv := KeyEnv;
  Connection.KeyValue := KeyValue;
  Connection.Preset := Preset;
  Connection.WireApi := WireApi;
  RuntimePath := CodexRuntime;
  ProfileDir := CodexProfile;
  Slot := UsageSlot;
  If Assigned(Slot) Then
    Slot.Retain;
End;

Destructor TAccountUsageWorker.Destroy;
Begin
  Workers.Remove(Self);
  Inherited Destroy;
End;

Procedure TAccountUsageWorker.Detach;
Begin
  Terminate;
  Detached := True;
  If Finished Then
    Free;
End;

Procedure DrainAccountWorkers;
Var
  Index: Integer;
  Worker: TAccountUsageWorker;
Begin
  For Index := 0 To Workers.Count - 1 Do
    TAccountUsageWorker(Workers[Index]).Terminate;
  For Index := Workers.Count - 1 DownTo 0 Do
    Begin
      Worker := TAccountUsageWorker(Workers[Index]);
      Worker.WaitFor;
      If Worker.Detached Then
        Worker.Free;
    End;
End;

Procedure TAccountUsageWorker.CaptureTokens;
Begin
  If Terminated Or Not Assigned(GrokOAuthClient) Then
    Exit;
  LocalClient := GrokOAuthClient.BeginUsageRefresh;
  Original := LocalClient.Tokens;
End;

Procedure TAccountUsageWorker.CommitTokens;
Begin
  If Not GrokOAuthClient.FinishUsageRefresh(LocalClient, Original) Then
    Connection.KeyValue := '';
End;

Procedure TAccountUsageWorker.AcquireToken;
Begin
  Connection.KeySource := 'stored';
  Connection.KeyValue := '';
  EnterCriticalSection(TokenLock);
  Try
    Synchronize(@CaptureTokens);
    If Assigned(LocalClient) Then
      Try
        Connection.KeyValue := LocalClient.GetValidAccessToken;
      Finally
        Try
          Synchronize(@CommitTokens);
        Finally
          FreeAndNil(LocalClient);
          Original := Default(TGrokOAuthTokens);
        End;
      End;
  Finally
    LeaveCriticalSection(TokenLock);
  End;
End;

Procedure TAccountUsageWorker.Execute;
Var
  ErrorText: String;
Begin
  Try
    Try
      If Terminated Then
        Exit;
      If Connection.Backend = 'grok' Then
        AcquireToken;
      If Terminated Then
        Exit;
      QueryOk := QueryWindowAccountUsage(Connection, RuntimePath, ProfileDir, Snapshot, ErrorText);
      If Assigned(Slot) And Not Terminated And Not CodexAccountUsageCancelled Then
        If Slot.StoreResult(Snapshot, QueryOk) Then
          WorkflowLogger.Warning('ProjectAssistant', 'Account usage query failed.');
    Except
      On E: Exception Do
        WorkflowLogger.Warning('ProjectAssistant', 'Account usage query failed.');
    End;
  Finally
    Connection.Free;
    If Assigned(Slot) Then
      Slot.Release;
  End;
End;

Initialization

Workers := TList.Create;
InitCriticalSection(TokenLock);

Finalization

DrainAccountWorkers;
Workers.Free;
DoneCriticalSection(TokenLock);

End.
