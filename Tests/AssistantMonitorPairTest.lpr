Program AssistantMonitorPairTest;

{ Pairing, hashed tokens, and revocation. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, jsonparser, AssistantMonitorPair, AssistantMonitorPulse;

Var
  FailCount: Integer;

Type
  TPulseThread = Class(TThread)
    Token: String;
    Status: Integer;
    Body: String;
    FinishedTick: QWord;
    Procedure Execute; Override;
  End;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TPulseThread.Execute;
Begin
  ServeMonitorPulse(Token, 'epoch-a', 0, 150, Status, Body);
  FinishedTick := GetTickCount64;
End;

Function TokenOf(Const Answer: String): String;
Var
  Data: TJSONData;
Begin
  Result := '';
  Data := GetJSON(Answer);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get('token', '');
  Finally
    Data.Free;
  End;
End;

Function Pair(Const Code, ClientId: String; Out Status: Integer; Out Answer: String): Boolean;
Begin
  Result := ServeMonitorPair('{"code":"' + Code + '","client_id":"' + ClientId + '","client_name":"Phone"}', Status, Answer);
End;

Procedure TestPairAndRevoke;
Var
  Code, Answer, Token: String;
  Status, HelloStatus: Integer;
  HelloBody: String;
  Pulse: TPulseThread;
  Started: QWord;
Begin
  BeginMonitorPairFixture;
  SetMonitorPulseEpoch('epoch-a');
  Check('code is issued', IssueMonitorPairCode(Code) And (Length(Code) = 10));
  Check('good code pairs', Pair(Code, 'phone-1', Status, Answer) And (Status = 200));
  Token := TokenOf(Answer);
  Check('token is issued', Token <> '');
  Check('reused code is refused', Pair(Code, 'phone-2', Status, Answer) And (Status <> 200));
  Check('another code is issued', IssueMonitorPairCode(Code));
  ExpireMonitorPairCode;
  Check('expired code is refused', Pair(Code, 'phone-3', Status, Answer) And (Status <> 200));
  Check('fresh code is issued', IssueMonitorPairCode(Code));
  Check('fresh code pairs', Pair(Code, 'phone-1', Status, Answer) And (Status = 200));
  Token := TokenOf(Answer);
  Check('hello is authorised', MonitorAuthorize(Token, HelloStatus, HelloBody) = maAccepted);
  Pulse := TPulseThread.Create(True);
  Pulse.FreeOnTerminate := False;
  Pulse.Token := Token;
  Pulse.Start;
  Started := GetTickCount64;
  While (MonitorPulseWaiting(Token) < 1) And (GetTickCount64 - Started < 2000) Do
    CheckSynchronize(10);
  Check('pulse is waiting', MonitorPulseWaiting(Token) = 1);
  Started := GetTickCount64;
  Check('revoke succeeds', RevokeMonitorPairedClient('phone-1', Answer));
  While (Pulse.FinishedTick = 0) And (GetTickCount64 - Started < 50) Do
    CheckSynchronize(1);
  Check('waiting pulse answered within 50 ms', (Pulse.FinishedTick <> 0) And (Pulse.FinishedTick <= Started + 50));
  Pulse.WaitFor;
  Check('waiting pulse is 403', (Pulse.Status = 403) And (Pos('revoked', Pulse.Body) > 0));
  Check('hello after revocation is 403', MonitorAuthorize(Token, HelloStatus, HelloBody) = maRevoked);
  Pulse.Free;
  EndMonitorPairFixture;
  ResetMonitorPulseClients;
End;

Begin
  FailCount := 0;
  TestPairAndRevoke;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorPairTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
