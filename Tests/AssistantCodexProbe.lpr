Program AssistantCodexProbe;
{ Explicit diagnostic, excluded from normal tests. Does not start model turns
  or print account identities, tokens, URLs, or raw protocol frames. }
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Classes, SysUtils, fpjson, jsonparser,
  AssistantCodexClient, AssistantCodexHandshake, AssistantCodexProfile;
Var
  Client: TAssistantCodexClient;
  Env: TStringList;
  Deadline: QWord;
  ErrorText, Model: String;
  Data, Item: TJSONData;
Procedure Failed(Const Stage: String);
Begin
  WriteLn(Stage, ' failed: ', Client.LastError);
  Halt(1);
End;
Procedure WaitReady;
Begin
  Deadline := GetTickCount64 + 30000;
  Repeat
    Client.Pump;
    Sleep(5);
  Until (Client.State In [crsReady, crsFailed]) Or
    (Client.Authentication.State = ccsNeedsSignIn) Or (GetTickCount64 >= Deadline);
End;
Begin
  If ParamCount <> 2 Then
    Begin WriteLn('Usage: AssistantCodexProbe /absolute/path/to/codex /isolated/codex/home'); Halt(2); End;
  If Not DirectoryExists(ParamStr(2)) Then
    Begin WriteLn('Create the isolated Codex home first.'); Halt(2); End;
  Env := TStringList.Create;
  Client := TAssistantCodexClient.Create(30000);
  Try
    If Not PrepareCodexProfile(ParamStr(2), ErrorText) Then
      Begin WriteLn(ErrorText); Halt(1); End;
    CodexProfileEnvironment(ParamStr(2), Env);
    If Not Client.Connect(ParamStr(1), ParamStr(2), Env) Then Failed('Qualification');
    WaitReady;
    If Client.Authentication.State = ccsNeedsSignIn Then
      Begin WriteLn('Qualified runtime initialized; ChatGPT sign-in required.'); Halt(1); End;
    If Client.State <> crsReady Then Failed('Authentication');
    WriteLn('ChatGPT account authenticated.');
    If Not Client.ListModels Then Failed('Queue model discovery');
    Deadline := GetTickCount64 + 30000;
    Repeat Client.Pump; Sleep(5);
    Until (Client.ModelsJson <> '') Or (Client.State = crsFailed) Or (GetTickCount64 >= Deadline);
    If Client.ModelsJson = '' Then Failed('Model discovery');
    Data := GetJSON(Client.ModelsJson);
    Try
      Item := Data.FindPath('data[0].id');
      If Not Assigned(Item) Then Failed('Available model');
      Model := Item.AsString;
    Finally Data.Free; End;
    WriteLn('Paginated model discovery passed.');
    If Not Client.ReadRateLimits Then Failed('Queue allowance lookup');
    Deadline := GetTickCount64 + 30000;
    Repeat Client.Pump; Sleep(5);
    Until (Client.RateLimitsJson <> '') Or (Client.State = crsFailed) Or (GetTickCount64 >= Deadline);
    If Client.RateLimitsJson = '' Then Failed('Allowance lookup');
    WriteLn('Allowance lookup passed.');
    If Not Client.CheckToolIsolation Then Failed('Queue tool isolation');
    Deadline := GetTickCount64 + 30000;
    Repeat Client.Pump; Sleep(5);
    Until Client.ToolIsolationChecked Or (Client.State = crsFailed) Or (GetTickCount64 >= Deadline);
    If Not Client.ToolIsolationChecked Then Failed('Tool isolation');
    If Not Client.StartThread(ParamStr(2), Model,
      '[{"name":"diagnostic","description":"Diagnostic only","inputSchema":{"type":"object","properties":{}}}]') Then Failed('Queue thread');
    WaitReady;
    If Client.State <> crsReady Then Failed('Thread policy');
    WriteLn('Dynamic-tool thread, provider, approval and read-only/no-network policy passed. No model turn sent.');
  Finally Client.Free; Env.Free; End;
End.
