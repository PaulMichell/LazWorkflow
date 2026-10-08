Unit AssistantCodexUsage;

{ Idle Codex account allowance. A short-lived app-server reads
  account/rateLimits/read. The live turn client is not used, login is not
  started, and no model turn is sent. Not signed in is unknown.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantConnections, AssistantAccountUsage;

Type
  { Fixture seam. SignedIn false is unknown, not an error. Do not return an email. }
  TCodexRateLimitRead = Function(Const Executable, ProfileDir: String; Out Body: String;
    Out SignedIn: Boolean; Out ErrorText: String): Boolean;

Procedure SetCodexAccountUsageIdle(Idle: Boolean);
Procedure CancelCodexAccountUsage;
{ Both nil uses the short-lived app-server. A fixture must not start a process. }
Procedure SetCodexAccountUsageRead(ReadFn: TCodexRateLimitRead);
Function QueryCodexAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;

Implementation

Uses
  Classes, AssistantCodexHandshake, AssistantCodexClient, AssistantCodexProfile;

Const
  CodexUsageDeadlineMs = 300000;

Var
  UsageIdle: LongInt;
  UsageCancel: LongInt;
  UsageRead: TCodexRateLimitRead;

Function UsageIsIdle: Boolean;
Begin
  Result := InterlockedCompareExchange(UsageIdle, 0, 0) <> 0;
End;

Function UsageCancelled: Boolean;
Begin
  Result := InterlockedCompareExchange(UsageCancel, 0, 0) <> 0;
End;

Procedure SetCodexAccountUsageIdle(Idle: Boolean);
Begin
  If Idle Then
    InterlockedExchange(UsageCancel, 0)
  Else
    InterlockedExchange(UsageCancel, 1);
  If Idle Then
    InterlockedExchange(UsageIdle, 1)
  Else
    InterlockedExchange(UsageIdle, 0);
End;

Procedure CancelCodexAccountUsage;
Begin
  InterlockedExchange(UsageCancel, 1);
End;

Procedure SetCodexAccountUsageRead(ReadFn: TCodexRateLimitRead);
Begin
  UsageRead := ReadFn;
End;

Function UnknownCodexUsage(Connection: TAssistantConnection; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Begin
  ClearAccountUsageSnapshot(Snapshot);
  ErrorText := '';
  Result := True;
  If Assigned(Connection) Then
    Snapshot.ConnectionId := Connection.Id;
End;

Function RunCodexRateLimitRead(Const Executable, ProfileDir: String; Out Body: String;
  Out SignedIn: Boolean; Out ErrorText: String): Boolean;
Var
  Client: TAssistantCodexClient;
  Env: TStringList;
  Deadline: QWord;
  Requested: Boolean;
Begin
  Result := False;
  Body := '';
  SignedIn := False;
  ErrorText := '';
  Client := Nil;
  Env := Nil;
  Try
    Try
      If UsageCancelled Then
        Begin
          Result := True;
          Exit;
        End;
      If Not PrepareCodexProfile(ProfileDir, ErrorText) Then
        Exit;
      Client := TAssistantCodexClient.Create(60000);
      Env := TStringList.Create;
      CodexProfileEnvironment(ProfileDir, Env);
      If Not Client.Connect(Executable, ProfileDir, Env) Then
        Begin
          ErrorText := Client.LastError;
          If ErrorText = '' Then
            ErrorText := 'Codex rate-limit connection failed.';
          Exit;
        End;
      Deadline := GetTickCount64 + CodexUsageDeadlineMs;
      Requested := False;
      Repeat
        If UsageCancelled Or (GetTickCount64 >= Deadline) Then
          Begin
            Client.CancelConnection;
            If UsageCancelled Then
              Begin
                ErrorText := '';
                Result := True;
                Exit;
              End;
            ErrorText := 'Codex rate-limit read timed out.';
            Exit;
          End;
        Client.Pump;
        If Client.State = crsFailed Then
          Begin
            ErrorText := Client.LastError;
            If ErrorText = '' Then
              ErrorText := 'Codex rate-limit connection failed.';
            Exit;
          End;
        { Needs sign-in is unknown. Do not start login or a model turn. }
        If Client.Authentication.State = ccsNeedsSignIn Then
          Begin
            Result := True;
            Exit;
          End;
        If (Client.Authentication.State = ccsSubscriptionAuthenticated) And
          (Client.State In [crsReady, crsCompleted]) And (Not Requested) Then
          Begin
            Requested := Client.ReadRateLimits;
            If Not Requested Then
              Begin
                ErrorText := 'Codex rate-limit read was not started.';
                Exit;
              End;
          End;
        If Client.RateLimitsJson <> '' Then
          Begin
            Body := Client.RateLimitsJson;
            SignedIn := True;
            Result := True;
            Exit;
          End;
        Sleep(10);
      Until False;
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Codex rate-limit connection failed.';
          Result := False;
        End;
    End;
  Finally
    Client.Free;
    Env.Free;
  End;
End;

Function QueryCodexAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  Body: String;
  SignedIn: Boolean;
  ReadFn: TCodexRateLimitRead;
Begin
  Result := UnknownCodexUsage(Connection, Snapshot, ErrorText);
  If Not Assigned(Connection) Then
    Exit;
  If (RuntimePath = '') Or (ProfileDir = '') Or (Not UsageIsIdle) Or UsageCancelled Then
    Exit;
  ReadFn := UsageRead;
  SignedIn := False;
  Body := '';
  If Assigned(ReadFn) Then
    Result := ReadFn(RuntimePath, ProfileDir, Body, SignedIn, ErrorText)
  Else
    Result := RunCodexRateLimitRead(RuntimePath, ProfileDir, Body, SignedIn, ErrorText);
  If Not Result Then
    Begin
      Snapshot.Known := False;
      If ErrorText = '' Then
        ErrorText := 'Codex rate-limit connection failed.';
      Exit;
    End;
  If Not SignedIn Then
    Begin
      Result := UnknownCodexUsage(Connection, Snapshot, ErrorText);
      Exit;
    End;
  Result := ParseCodexAccountUsage(Body, Connection.Id, Snapshot, ErrorText);
End;

End.
