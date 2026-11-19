Program AssistantAccountRefreshTest;

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Classes, SysUtils, StdCtrls, LazIDEIntf, ProjectIntf, BaseIDEIntf,
  LazConfigStorage, WorkflowSettings, AssistantTestIDEHost, AssistantSettingsForm,
  AssistantConnections, AssistantConfig, AssistantAccountWorker, AssistantAccountUsage, GrokOAuth;

Var ConfigRoot: String;
Type
  TMemoryConfig = Class(TConfigMemStorage)
    Procedure WriteToDisk; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Function GetActiveProject: TLazProject; Override;
    Class Function GetPrimaryConfigPath: String; Override;
  End;
Procedure TMemoryConfig.WriteToDisk;
Begin End;
Function MemoryConfig(Const Filename: String; LoadFromDisk: Boolean): TConfigStorage;
Begin Result := TMemoryConfig.Create('', False); End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Nil; End;
Class Function TIDE.GetPrimaryConfigPath: String;
Begin Result := ConfigRoot; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Type
  TDelayedOAuth = Class(TGrokOAuthClient)
    Function HttpPostForm(Const Url, FormBody: String; Out ResponseBody: String; Out StatusCode: Integer): Boolean; Override;
  End;
  TPaintCounter = Class
    Count: Integer;
    Procedure Painted(Sender: TObject);
  End;

Var
  RefreshStarted, ReleaseRefresh, QueryCount, ReleaseOldQuery, OldQueryDone: LongInt;

Procedure TPaintCounter.Painted(Sender: TObject);
Begin
  Inc(Count);
End;

Procedure WaitForGate(Var Gate: LongInt);
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  While (InterlockedCompareExchange(Gate, 0, 0) = 0) And (GetTickCount64 - Started < 5000) Do
    Sleep(5);
End;

Function TDelayedOAuth.HttpPostForm(Const Url, FormBody: String; Out ResponseBody: String; Out StatusCode: Integer): Boolean;
Begin
  InterlockedIncrement(RefreshStarted);
  WaitForGate(ReleaseRefresh);
  StatusCode := 200;
  ResponseBody := '{"access_token":"fresh","refresh_token":"rotated","expires_in":3600}';
  Result := True;
End;

Function DelayedUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  First: Boolean;
  Percent: String;
Begin
  First := InterlockedIncrement(QueryCount) = 1;
  If First Then
    Begin
      WaitForGate(ReleaseOldQuery);
      Percent := '13';
    End
  Else
    Percent := '72';
  Result := (Connection.KeyValue = 'fresh') And ParseGrokAccountUsage('{"config":{"creditUsagePercent":' + Percent + '}}',
    Connection.Id, Snapshot, ErrorText);
  If First Then
    InterlockedIncrement(OldQueryDone);
End;

Procedure PumpUntil(Var Counter: LongInt; Target: Integer);
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  While (InterlockedCompareExchange(Counter, 0, 0) < Target) And (GetTickCount64 - Started < 3000) Do
    Begin
      Application.ProcessMessages;
      CheckSynchronize;
      Sleep(5);
    End;
End;

Procedure CheckDelayedRefresh;
Var
  First, Second: TAssistantSettingsForm;
  Paint: TPaintCounter;
  Tokens: TGrokOAuthTokens;
  Started: QWord;
  Selected: TListBox;
  SignedUsage: TAccountUsageSnapshot;
Begin
  DrainAccountWorkers;
  FreeAndNil(GrokOAuthClient);
  GrokOAuthClient := TDelayedOAuth.Create;
  Tokens.AccessToken := 'expired';
  Tokens.ExpiresAt := Now - 1;
  Tokens.RefreshToken := 'refreshable';
  AssistantChatConfig.ApplyOAuthTokens(Tokens);
  RegisterAccountUsageQuery('grok', @DelayedUsage);
  Paint := TPaintCounter.Create;
  First := TAssistantSettingsForm.Create(Nil);
  Try
    First.LoadFromConfig;
    GrokOAuthClient.SetTokens(Tokens);
    AssistantChatConfig.ApplyOAuthTokens(Tokens);
    First.Show;
    First.GrokAccountItem.Click;
    First.SaveToConfig;
    PumpUntil(RefreshStarted, 1);
    First.OnPaint := @Paint.Painted;
    First.Invalidate;
    PumpUntil(Paint.Count, 1);
    WriteLn('Refresh calls ', RefreshStarted, ', paints ', Paint.Count, ', queries ', QueryCount, ', ', GrokOAuthClient.StatusText);
    Check('settings repaints during expired-token refresh', (RefreshStarted = 1) And (Paint.Count > 0) And (QueryCount = 0));
    InterlockedIncrement(ReleaseRefresh);
    PumpUntil(QueryCount, 1);
    Check('refreshed token reaches the pending query', (QueryCount = 1) And (GrokOAuthClient.Tokens.RefreshToken = 'rotated'));
    Started := GetTickCount64;
    FreeAndNil(First);
    Check('settings closes while usage is pending', (GetTickCount64 - Started < 1000) And (OldQueryDone = 0));
    Second := TAssistantSettingsForm.Create(Nil);
    Try
      Second.LoadFromConfig;
      Second.Show;
      Selected := Second.ConnectionsList;
      Selected.ItemIndex := Selected.Items.Count - 1;
      Selected.OnClick(Selected);
      PumpUntil(QueryCount, 2);
      Started := GetTickCount64;
      Repeat
        Application.ProcessMessages;
        Sleep(5);
      Until (Pos('72%', Second.GrokUsageLabel.Caption) > 0) Or (GetTickCount64 - Started > 2000);
      InterlockedIncrement(ReleaseOldQuery);
      PumpUntil(OldQueryDone, 1);
      Check('reopened settings keeps its own result after the old query finishes',
        (OldQueryDone = 1) And (Pos('72%', Second.GrokUsageLabel.Caption) > 0) And (RefreshStarted = 1));
      Check('old completion is absent from shared usage', LastAccountUsageSnapshot(SignedUsage) And
        (Pos('72%', SignedUsage.Caption) > 0));
    Finally
      Second.Free;
    End;
  Finally
    First.Free;
    Paint.Free;
    DrainAccountWorkers;
  End;
End;


Var
  IDE: TIDE;
  Guid: TGuid;
Begin
  Application.Initialize;
  CreateGUID(Guid);
  ConfigRoot := ExtractFilePath(ParamStr(0)) + GUIDToString(Guid);
  ForceDirectories(ConfigRoot);
  GetIDEConfigStorage := @MemoryConfig;
  SetWorkflowSettingsDirectory(ConfigRoot);
  IDE := TIDE.Create(Nil);
  LazarusIDE := IDE;
  Try
    CheckDelayedRefresh;
  Finally
    LazarusIDE := Nil;
    IDE.Free;
  End;
End.
