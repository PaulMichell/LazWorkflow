Program AssistantCodexProbe;
{ Explicit diagnostic, excluded from normal tests. Does not start model turns
  or print account identities, tokens, URLs, or raw protocol frames. }
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, AssistantCodexClient, AssistantCodexHandshake;
Var Client: TAssistantCodexClient; Env: TStringList; Deadline: QWord; I: Integer;
Begin
  If ParamCount <> 2 Then
    Begin WriteLn('Usage: AssistantCodexProbe /absolute/path/to/codex /isolated/codex/home'); Halt(2); End;
  If Not DirectoryExists(ParamStr(2)) Then
    Begin WriteLn('Create the isolated Codex home first.'); Halt(2); End;
  Env := TStringList.Create;
  Client := TAssistantCodexClient.Create(10000);
  Try
    For I := 1 To GetEnvironmentVariableCount Do Env.Add(GetEnvironmentString(I));
    Env.Values['CODEX_HOME'] := ExpandFileName(ParamStr(2));
    Env.Values['OPENAI_API_KEY'] := '';
    Env.Values['CODEX_API_KEY'] := '';
    If Not Client.Connect(ParamStr(1), ParamStr(2), Env) Then
      Begin WriteLn(Client.LastError); Halt(1); End;
    Deadline := GetTickCount64 + 15000;
    Repeat
      Client.Pump; Sleep(5);
    Until (Client.State In [crsReady, crsFailed]) Or
      (Client.Authentication.State = ccsNeedsSignIn) Or (GetTickCount64 >= Deadline);
    If Client.Authentication.State = ccsNeedsSignIn Then
      WriteLn('Qualified runtime initialized; ChatGPT sign-in required. No model request sent.')
    Else If Client.State = crsReady Then
      WriteLn('Qualified runtime initialized; ChatGPT account authenticated. Quota not checked. No model request sent.')
    Else Begin WriteLn('Probe failed: ', Client.LastError); Halt(1); End;
  Finally Client.Free; Env.Free; End;
End.
