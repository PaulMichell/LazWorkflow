Program AssistantCodexProbe;
{ Explicit diagnostic, excluded from normal tests. Starts a model turn only with --image
  and does not print account identities, tokens, URLs, or raw protocol frames. }
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, fpjson, jsonparser,
  AssistantCodexClient, AssistantCodexHandshake, AssistantCodexProfile, AssistantImages, SafeFileAccess;
Var
  Client: TAssistantCodexClient;
  Env: TStringList;
  Deadline: QWord;
  ErrorText, Model, Catalogue: String;
  Tool: TCodexToolRequest;
  Reserved: Boolean;
  Data, Item: TJSONData;
Procedure Failed(Const Stage: String);
Begin
  WriteLn(Stage, ' failed: ', Client.LastError);
  Halt(1);
End;
Procedure CheckArtifact;
Var
  Relative, Folder: String;
  Entry: TSearchRec;
  Bytes: TBytes;
Begin
  Relative := 'generated_images' + PathDelim + Client.ThreadId + PathDelim;
  Folder := IncludeTrailingPathDelimiter(ParamStr(2)) + Relative;
  If FindFirst(Folder + '*.png', faAnyFile, Entry) <> 0 Then Failed('Thread image artifact');
  Try
    If ReadBoundedArtifact(ParamStr(2), Relative + Entry.Name, 1, Bytes) Then Failed('Artifact size limit');
    If Not ReadBoundedArtifact(ParamStr(2), Relative + Entry.Name, AssistantImageMaxFileBytes, Bytes) Then Failed('Artifact containment');
    If (Length(Bytes) <> Length(Client.GeneratedImage.Bytes)) Or
      Not CompareMem(@Bytes[0], @Client.GeneratedImage.Bytes[0], Length(Bytes)) Then Failed('Artifact contents');
  Finally
    FindClose(Entry);
  End;
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
  If (ParamCount <> 2) And Not ((ParamCount = 3) And (ParamStr(3) = '--image')) Then
    Begin WriteLn('Usage: AssistantCodexProbe /absolute/path/to/codex /isolated/codex/home [--image]'); Halt(2); End;
  If Not DirectoryExists(ParamStr(2)) Then
    Begin WriteLn('Create the isolated Codex home first.'); Halt(2); End;
  Env := TStringList.Create;
  Client := TAssistantCodexClient.Create(30000);
  Try
    If Not PrepareCodexProfile(ParamStr(2), ErrorText) Then
      Begin WriteLn(ErrorText); Halt(1); End;
    CodexProfileEnvironment(ParamStr(2), Env);
    If ParamStr(1) = '--auto' Then Model := FindCodexExecutable Else Model := ParamStr(1);
    If Not Client.Connect(Model, ParamStr(2), Env) Then Failed('Qualification');
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
    Catalogue := '[{"name":"diagnostic","description":"Diagnostic only","inputSchema":{"type":"object","properties":{}}}]';
    If ParamCount = 3 Then
      Catalogue := '[{"name":"write_image","description":"Reserve the diagnostic image destination","inputSchema":{"type":"object","properties":{}}}]';
    If Not Client.StartThread(ParamStr(2), Model, Catalogue) Then Failed('Queue thread');
    WaitReady;
    If Client.State <> crsReady Then Failed('Thread policy');
    WriteLn('Dynamic-tool thread and isolation policy passed.');
    If ParamCount = 3 Then
      Begin
        If Not Client.StartTurn('Call write_image once, then use native image generation once to draw a blue circle on white.') Then Failed('Queue image turn');
        Deadline := GetTickCount64 + 300000;
        Reserved := False;
        Repeat
          Client.Pump;
          If Client.TakeTool(Tool) Then
            Begin
              If Reserved Or (Tool.Tool <> 'write_image') Then Failed('Unexpected image request');
              Reserved := Client.CompleteTool(Tool.CallId, 'Reserved. Generate the requested image once.', True);
              If Not Reserved Then Failed('Reservation');
            End;
          Sleep(5);
        Until (Client.State In [crsCompleted, crsFailed]) Or (GetTickCount64 >= Deadline);
        If Client.State <> crsCompleted Then Failed('Image turn');
        If (Client.GeneratedImageError <> '') Or (Client.GeneratedImage.Mime <> 'image/png') Then Failed('Image validation');
        CheckArtifact;
        WriteLn('Retrieved generated PNG, ', Length(Client.GeneratedImage.Bytes), ' bytes.');
      End;
  Finally Client.Free; Env.Free; End;
End.
