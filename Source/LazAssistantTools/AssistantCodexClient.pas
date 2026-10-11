Unit AssistantCodexClient;

{ Worker-owned managed-runtime protocol. Dynamic tools are surfaced to a
  caller-owned IDE broker. Native approval requests are declined immediately
  and are never auto-approved.
  A release Codex CLI is accepted when its generated app-server schema still has the
  fields this client uses. Pictures stay on the Grok connection. This client does
  not send an image input item. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantCodexHandshake, AssistantCodexTransport;

Const
  { Image support is the Grok connection. Do not add a guessed local_image field here. }
  CodexImagesSupported = False;

/// Shared catalogue items use function.parameters. Codex dynamicTools use name and inputSchema.
Function CodexDynamicToolsFromCatalogue(Const CatalogueJson: String): String;
/// thread/start params. DynamicToolsJson is a JSON array. Instructions are the harness prompt, not a Codex essay.
Function CodexThreadStartParams(Const WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions: String): String;
/// turn/start params for this client. One text item. No image item and no local path.
Function CodexTurnStartParams(Const ThreadId, Prompt, Effort: String): String;
/// turn/steer params for this client. One text item. No image item: 2.4 found none in this protocol.
Function CodexTurnSteerParams(Const ThreadId, TurnId, Text: String): String;
/// JSON-RPC result for a server approval request. Command and file changes are declined.
/// A permissions escalation is granted nothing. RequestId is the raw JSON id token.
Function CodexNativeApprovalReply(Const Method, RequestId: String): String;
Function IsCodexApprovalRequest(Const Method: String): Boolean;

Type
  TCodexRunState = (crsDisconnected, crsConnecting, crsReady, crsStartingThread,
    crsStartingTurn, crsRunning, crsCancelling, crsCompleted, crsFailed);
  TCodexToolRequest = Record
    RequestId, CallId, ThreadId, TurnId, Tool, Arguments: String;
    ContentBefore, ThinkingBefore: String;
  End;
  TAssistantCodexClient = Class
  Private
    FTransport: TAssistantCodexTransport;
    FHandshake: TAssistantCodexHandshake;
    FState: TCodexRunState;
    FThreadId, FTurnId, FContent, FThinking, FError, FModels, FRateLimits: String;
    FToolIsolationChecked: Boolean;
    FMessageIds: TStringList;
    FMessageId: String;
    FMessageStart: Integer;
    FReasoningIds: TStringList;
    FReasoningId: String;
    FReasoningStart, FSummaryIndex: Integer;
    FPendingId, FPendingMethod: String;
    FNextId: Int64;
    FDeadline: QWord;
    FRequestTimeout: Cardinal;
    FTools: Array Of TCodexToolRequest;
    FSeenCalls: TStringList;
    FToolTaken: Boolean;
    Function Request(Const Method, Params: String): Boolean;
    Procedure Fail(Const Reason: String);
    Procedure HandleFrame(Const Frame: String);
    Procedure FlushHandshake;
    Procedure MessageText(Const ItemId, Text: String; Complete: Boolean);
    Procedure ReasoningText(Const ItemId, Text: String; SummaryIndex: Integer; Complete: Boolean);
  Public
    Constructor Create(RequestTimeoutMs: Cardinal = 30000);
    Destructor Destroy; Override;
    Function Connect(Const Executable, WorkingDirectory: String;
      Environment: TStrings = Nil): Boolean;
    Procedure Pump;
    Procedure Disconnect;
    Procedure StartLogin;
    Function ListModels: Boolean;
    { Short-lived usage reader only. The live turn client must not call this. }
    Function ReadRateLimits: Boolean;
    Function CheckToolIsolation: Boolean;
    Function StartThread(Const WorkingDirectory, Model, ToolsJson: String; Const DeveloperInstructions: String = ''): Boolean;
    Function StartTurn(Const Prompt: String; Const Effort: String = ''): Boolean;
    Function Steer(Const Text: String): Boolean; Overload;
    { Image refs are refused while CodexImagesSupported is false. A text note is not the picture. }
    Function Steer(Const Text, AttachmentsJson: String): Boolean; Overload;
    Procedure Interrupt;
    { May be called from the UI to force connection shutdown on next Pump.
      A non-empty Reason replaces the generic cancel text, for a timeout. }
    Procedure CancelConnection(Const Reason: String = '');
    Function TakeTool(Out Tool: TCodexToolRequest): Boolean;
    Function CompleteTool(Const CallId, Text: String; Success: Boolean): Boolean;
    Property ToolIsolationChecked: Boolean Read FToolIsolationChecked;
    Property State: TCodexRunState Read FState;
    Property Authentication: TAssistantCodexHandshake Read FHandshake;
    Property Content: String Read FContent;
    Property Thinking: String Read FThinking;
    Property LastError: String Read FError;
    Property ModelsJson: String Read FModels;
    Property RateLimitsJson: String Read FRateLimits;
    Property ThreadId: String Read FThreadId;
    Property TurnId: String Read FTurnId;
  End;

Implementation

Uses
  fpjson, jsonparser, AssistantProtocol, AssistantCodexQualification;

Function Quote(Const S: String): String;
Begin
  Result := '"' + JsonEscapeText(S) + '"';
End;

Function IsCodexApprovalRequest(Const Method: String): Boolean;
Begin
  Result := (Length(Method) >= 16) And (Copy(Method, Length(Method) - 15, 16) = '/requestApproval');
End;

Function CodexNativeApprovalReply(Const Method, RequestId: String): String;
Begin
  { Permissions escalation is not a decision object. Grant nothing so the turn continues. }
  If Method = 'item/permissions/requestApproval' Then
    Result := '{"id":' + RequestId + ',"result":{"permissions":{},"scope":"none"}}'
  Else
    Result := '{"id":' + RequestId + ',"result":{"decision":"decline"}}';
End;

Function CopyJson(Node: TJSONData): TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Node) Then Exit;
  Try
    Result := GetJSON(Node.AsJSON);
  Except
    Result := Nil;
  End;
End;

Function CodexDynamicToolsFromCatalogue(Const CatalogueJson: String): String;
Var
  Data, Fn, Schema: TJSONData;
  Source, Converted: TJSONArray;
  Item, FnObj, Tool: TJSONObject;
  I: Integer;
Begin
  Result := '[]';
  If Trim(CatalogueJson) = '' Then Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(CatalogueJson);
    Except
      Exit;
    End;
    If Not (Data Is TJSONArray) Then Exit;
    Source := TJSONArray(Data);
    Converted := TJSONArray.Create;
    Try
      For I := 0 To Source.Count - 1 Do
        Begin
          If Not (Source[I] Is TJSONObject) Then Continue;
          Item := TJSONObject(Source[I]);
          Fn := Item.Find('function');
          If Assigned(Fn) And (Fn Is TJSONObject) Then
            Begin
              FnObj := TJSONObject(Fn);
              Tool := TJSONObject.Create;
              Tool.Add('type', 'function');
              Tool.Add('name', FnObj.Get('name', ''));
              Tool.Add('description', FnObj.Get('description', ''));
              Schema := CopyJson(FnObj.Find('parameters'));
              If Not Assigned(Schema) Then Schema := GetJSON('{"type":"object","properties":{}}');
              Tool.Add('inputSchema', Schema);
              Converted.Add(Tool);
            End
          Else If Item.Get('name', '') <> '' Then
            Begin
              Schema := CopyJson(Item);
              If Assigned(Schema) Then Converted.Add(Schema);
            End;
        End;
      Result := Converted.AsJSON;
    Finally
      Converted.Free;
    End;
  Finally
    Data.Free;
  End;
End;

Function CodexThreadStartParams(Const WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions: String): String;
Var
  Tools: String;
Begin
  Tools := Trim(DynamicToolsJson);
  If Tools = '' Then Tools := '[]';
  Result := '{"cwd":' + Quote(WorkingDirectory) +
    ',"model":' + Quote(Model) + ',"modelProvider":"openai",' +
    '"approvalPolicy":"on-request","permissions":"lazarus_ide","ephemeral":true,' +
    '"environments":[],"dynamicTools":' + Tools +
    ',"developerInstructions":' + Quote(DeveloperInstructions) +
    ',"config":{"forced_login_method":"chatgpt","model_provider":"openai"}}';
End;

Function CodexTurnStartParams(Const ThreadId, Prompt, Effort: String): String;
Var
  Options: String;
Begin
  Options := '';
  If Effort <> '' Then Options := ',"effort":' + Quote(Effort);
  Result := '{"threadId":' + Quote(ThreadId) +
    ',"input":[{"type":"text","text":' + Quote(Prompt) + '}],' +
    '"approvalPolicy":"on-request","permissions":"lazarus_ide","summary":"auto"' + Options + '}';
End;

Function CodexTurnSteerParams(Const ThreadId, TurnId, Text: String): String;
Begin
  { No protocol image item in this version. Do not add a guessed field or a local path. }
  Result := '{"threadId":' + Quote(ThreadId) + ',"expectedTurnId":' + Quote(TurnId) +
    ',"input":[{"type":"text","text":' + Quote(Text) + '}]}';
End;

Constructor TAssistantCodexClient.Create(RequestTimeoutMs: Cardinal);
Begin
  Inherited Create;
  FTransport := TAssistantCodexTransport.Create;
  FHandshake := TAssistantCodexHandshake.Create;
  FSeenCalls := TStringList.Create;
  FMessageIds := TStringList.Create;
  FReasoningIds := TStringList.Create;
  FRequestTimeout := RequestTimeoutMs;
End;

Destructor TAssistantCodexClient.Destroy;
Begin
  Disconnect;
  FSeenCalls.Free;
  FMessageIds.Free;
  FReasoningIds.Free;
  FHandshake.Free;
  FTransport.Free;
  Inherited Destroy;
End;

Procedure TAssistantCodexClient.Disconnect;
Begin
  FTransport.Stop;
  FHandshake.Close;
  FState := crsDisconnected;
  FThreadId := '';
  FTurnId := '';
  FPendingId := '';
  FPendingMethod := '';
  FContent := '';
  FThinking := '';
  FModels := '';
  FRateLimits := '';
  FToolIsolationChecked := False;
  FMessageIds.Clear;
  FMessageId := '';
  FMessageStart := 1;
  FReasoningIds.Clear;
  FReasoningId := '';
  FReasoningStart := 1;
  FSummaryIndex := -1;
  FSeenCalls.Clear;
  SetLength(FTools, 0);
  FToolTaken := False;
End;

Function TAssistantCodexClient.Connect(Const Executable, WorkingDirectory: String;
    Environment: TStrings): Boolean;
Var
  Args: TStringList;
  Observed, Reason: String;
Begin
  Disconnect;
  FError := '';
  Args := TStringList.Create;
  Try
    If Not ReadCodexVersion(Executable, Environment, Observed, Reason) Then
      Begin
        Fail(Reason);
        Result := False;
        Exit;
      End;
    If Not QualifyCodexRuntime(Executable, Observed, Environment, Reason) Then
      Begin
        Fail(Reason);
        Result := False;
        Exit;
      End;
    CodexSubscriptionArguments(Args);
    Result := FTransport.Start(Executable, WorkingDirectory, Args, Environment);
  Finally
    Args.Free;
  End;
  If Not Result Then
    Begin
      Fail(FTransport.LastError);
      Exit;
    End;
  FState := crsConnecting;
  FDeadline := GetTickCount64 + FRequestTimeout;
  FHandshake.Start(True);
  FlushHandshake;
End;

Procedure TAssistantCodexClient.Fail(Const Reason: String);
Var
  SavedContent, SavedThinking: String;
Begin
  SavedContent := FContent;
  SavedThinking := FThinking;
  Disconnect;
  FContent := SavedContent;
  FThinking := SavedThinking;
  FState := crsFailed;
  FError := Reason;
End;

Procedure TAssistantCodexClient.FlushHandshake;
Var
  Frame: String;
Begin
  While FHandshake.TakeOutgoing(Frame) Do
    If Not FTransport.Queue(TrimRight(Frame)) Then
      Begin
        Fail(FTransport.LastError);
        Exit;
      End;
End;

Function TAssistantCodexClient.Request(Const Method, Params: String): Boolean;
Begin
  Result := False;
  If (FPendingId <> '') Or (FState In [crsDisconnected, crsFailed]) Then Exit;
  Inc(FNextId);
  FPendingId := 'laz-' + IntToStr(FNextId);
  FPendingMethod := Method;
  FDeadline := GetTickCount64 + FRequestTimeout;
  Result := FTransport.Queue('{"id":' + Quote(FPendingId) +
    ',"method":' + Quote(Method) + ',"params":' + Params + '}');
  If Not Result Then Fail(FTransport.LastError);
End;

Procedure TAssistantCodexClient.StartLogin;
Begin
  FHandshake.StartChatGPTLogin;
  FDeadline := GetTickCount64 + 300000;
  FlushHandshake;
End;

Function TAssistantCodexClient.ListModels: Boolean;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And
    (FState In [crsReady, crsCompleted]);
  If Result Then Result := Request('model/list', '{"includeHidden":false,"limit":100}');
End;

Function TAssistantCodexClient.ReadRateLimits: Boolean;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And
    (FState In [crsReady, crsCompleted]);
  If Result Then Result := Request('account/rateLimits/read', '{}');
End;

Function TAssistantCodexClient.CheckToolIsolation: Boolean;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And (FState = crsReady);
  If Result Then Result := Request('mcpServerStatus/list', '{"limit":100}');
End;

Function TAssistantCodexClient.StartThread(Const WorkingDirectory, Model, ToolsJson, DeveloperInstructions: String): Boolean;
Var
  Data: TJSONData;
  Dynamic: String;
Begin
  Result := False;
  If (FHandshake.State <> ccsSubscriptionAuthenticated) Or
    Not (FState In [crsReady, crsCompleted]) Or Not FToolIsolationChecked Then Exit;
  Dynamic := CodexDynamicToolsFromCatalogue(ToolsJson);
  Data := GetJSON(Dynamic);
  Try
    If Not (Data Is TJSONArray) Then Exit;
    { Built-in actions have no write permission. Approvals must be serviced by
      this client, which rejects them. Developer instructions come from the harness. }
    Result := Request('thread/start', CodexThreadStartParams(WorkingDirectory, Model, Dynamic, DeveloperInstructions));
    If Result Then FState := crsStartingThread;
  Finally
    Data.Free;
  End;
End;

Function TAssistantCodexClient.StartTurn(Const Prompt: String; Const Effort: String): Boolean;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And
    (FThreadId <> '') And (FState In [crsReady, crsCompleted]);
  If Not Result Then Exit;
  { Text only. A note is not a picture, and a path would fail the minimal read sandbox. }
  Result := Request('turn/start', CodexTurnStartParams(FThreadId, Prompt, Effort));
  If Result Then
    Begin
      FContent := '';
      FThinking := '';
      FTurnId := '';
      FMessageIds.Clear;
      FMessageId := '';
      FMessageStart := 1;
      FReasoningIds.Clear;
      FReasoningId := '';
      FReasoningStart := 1;
      FSummaryIndex := -1;
      FSeenCalls.Clear;
      SetLength(FTools, 0);
      FToolTaken := False;
      FState := crsStartingTurn;
    End;
End;

Function TAssistantCodexClient.Steer(Const Text: String): Boolean;
Begin
  Result := Steer(Text, '');
End;

Function TAssistantCodexClient.Steer(Const Text, AttachmentsJson: String): Boolean;
Begin
  Result := False;
  { 2.4 found no image input item. Refuse the refs instead of describing the file in text. }
  If (Not CodexImagesSupported) And (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]') Then Exit;
  Result := (FState = crsRunning) And (FTurnId <> '');
  If Result Then Result := Request('turn/steer', CodexTurnSteerParams(FThreadId, FTurnId, Text));
End;

Procedure TAssistantCodexClient.Interrupt;
Begin
  If Not (FState In [crsStartingThread, crsStartingTurn, crsRunning]) Then Exit;
  If (FTurnId = '') Or (FPendingId <> '') Then
    Begin
      CancelConnection;
      Exit;
    End;
  If Request('turn/interrupt', '{"threadId":' + Quote(FThreadId) + ',"turnId":' + Quote(FTurnId) + '}') Then
    Begin
      FState := crsCancelling;
      SetLength(FTools, 0);
      FToolTaken := False;
    End;
End;

Procedure TAssistantCodexClient.CancelConnection(Const Reason: String);
Begin
  FTransport.Cancel(Reason);
End;

Function TAssistantCodexClient.TakeTool(Out Tool: TCodexToolRequest): Boolean;
Begin
  Tool := Default(TCodexToolRequest);
  Result := (Length(FTools) > 0) And Not FToolTaken And (FState = crsRunning);
  If Result Then
    Begin
      Tool := FTools[0];
      FToolTaken := True;
    End;
End;

Function TAssistantCodexClient.CompleteTool(Const CallId, Text: String; Success: Boolean): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If (FState <> crsRunning) Or Not FToolTaken Or (Length(FTools) = 0) Then Exit;
  If FTools[0].CallId <> CallId Then Exit;
  Result := FTransport.Queue('{"id":' + FTools[0].RequestId +
    ',"result":{"success":' + LowerCase(BoolToStr(Success, True)) +
    ',"contentItems":[{"type":"inputText","text":' + Quote(Text) + '}]}}');
  If Not Result Then
    Begin
      Fail(FTransport.LastError);
      Exit;
    End;
  For I := 1 To High(FTools) Do FTools[I - 1] := FTools[I];
  SetLength(FTools, Length(FTools) - 1);
  FToolTaken := False;
End;

Procedure TAssistantCodexClient.MessageText(Const ItemId, Text: String; Complete: Boolean);
Var
  Key: String;
Begin
  Key := ItemId;
  If Key = '' Then Key := 'legacy-message';
  If FMessageId <> Key Then
    Begin
      { Repeated completion of an earlier item must not duplicate its text. }
      If FMessageIds.IndexOf(Key) >= 0 Then Exit;
      If FMessageIds.Count >= 1024 Then
        Begin
          Fail('Too many Codex message items.');
          Exit;
        End;
      FMessageIds.Add(Key);
      FMessageId := Key;
      If FContent <> '' Then FContent := FContent + LineEnding + LineEnding;
      FMessageStart := Length(FContent) + 1;
    End;
  If Complete Then SetLength(FContent, FMessageStart - 1);
  FContent := FContent + Text;
End;

Procedure TAssistantCodexClient.ReasoningText(Const ItemId, Text: String;
    SummaryIndex: Integer; Complete: Boolean);
Var
  Key: String;
Begin
  Key := ItemId;
  If Key = '' Then Key := 'legacy-reasoning';
  If FReasoningId <> Key Then
    Begin
      If FReasoningIds.IndexOf(Key) >= 0 Then Exit;
      If FReasoningIds.Count >= 1024 Then
        Begin
          Fail('Too many Codex reasoning items.');
          Exit;
        End;
      FReasoningIds.Add(Key);
      FReasoningId := Key;
      If FThinking <> '' Then FThinking := FThinking + LineEnding + LineEnding;
      FReasoningStart := Length(FThinking) + 1;
      FSummaryIndex := -1;
    End;
  If Complete Then SetLength(FThinking, FReasoningStart - 1)
  Else If (FSummaryIndex <> SummaryIndex) And (Length(FThinking) >= FReasoningStart) Then
    FThinking := FThinking + LineEnding + LineEnding;
  FSummaryIndex := SummaryIndex;
  FThinking := FThinking + Text;
End;

Procedure TAssistantCodexClient.HandleFrame(Const Frame: String);
Var
  Data, Node, Value: TJSONData;
  Root, Params, Turn: TJSONObject;
  Method, Id, Status, SummaryText: String;
  N, I: Integer;
  Parts: TJSONData;
  Tool: TCodexToolRequest;
Begin
  Data := GetJSON(Frame);
  Try
    If Not (Data Is TJSONObject) Then Raise Exception.Create('Expected object');
    Root := TJSONObject(Data);
    Method := Root.Get('method', '');
    Node := Root.Find('id');
    If (Pos('account/', Method) = 1) Or
      ((Method = '') And Assigned(Node) And (Node.JSONType = jtNumber)) Then
        Begin
          FHandshake.Feed(Frame + #10);
          Exit;
        End;
    If (Method <> '') And Assigned(Node) Then
      Begin
        If Not (Node.JSONType In [jtString, jtNumber]) Then Raise Exception.Create('Invalid ID');
        If IsCodexApprovalRequest(Method) Then
          Begin
            { Answer immediately. A JSON-RPC error leaves ChatGPT waiting until the turn times out. }
            If Not FTransport.Queue(CodexNativeApprovalReply(Method, Node.AsJSON)) Then
              Fail(FTransport.LastError)
            Else
              Begin
                If FThinking <> '' Then FThinking := FThinking + LineEnding + LineEnding;
                FThinking := FThinking + 'Declined ' + Method +
                  '. Native shell and editor changes are not approved. Use write_markdown for plans and documents.';
              End;
            Exit;
          End;
        Value := Root.Find('params');
        If (Method <> 'item/tool/call') Or (FState <> crsRunning) Or
          Not (Value Is TJSONObject) Then
            Begin
              FTransport.Queue('{"id":' + Node.AsJSON + ',"error":{"code":-32601,"message":"Unsupported client request"}}');
              Exit;
            End;
        Params := TJSONObject(Value);
        Tool := Default(TCodexToolRequest);
        Tool.RequestId := Node.AsJSON;
        Tool.ThreadId := Params.Get('threadId', '');
        Tool.TurnId := Params.Get('turnId', '');
        Tool.CallId := Params.Get('callId', '');
        Tool.Tool := Params.Get('tool', '');
        Value := Params.Find('arguments');
        If (Tool.ThreadId <> FThreadId) Or (Tool.TurnId <> FTurnId) Or
          (Tool.CallId = '') Or (Tool.Tool = '') Or Not (Value Is TJSONObject) Or
          (FSeenCalls.IndexOf(Tool.CallId) >= 0) Or (Length(FTools) >= 16) Or
          (FSeenCalls.Count >= 1024) Then
            Begin
              Fail('Invalid, stale or duplicate Codex tool request.');
              Exit;
            End;
        Tool.Arguments := Value.AsJSON;
        Tool.ContentBefore := FContent;
        Tool.ThinkingBefore := FThinking;
        FSeenCalls.Add(Tool.CallId);
        N := Length(FTools);
        SetLength(FTools, N + 1);
        FTools[N] := Tool;
        Exit;
      End;
    If Method <> '' Then
      Begin
        Value := Root.Find('params');
        If Not (Value Is TJSONObject) Then Exit;
        Params := TJSONObject(Value);
        If Params.Get('threadId', '') <> FThreadId Then Exit;
        If (Method = 'turn/started') And (FState = crsStartingTurn) Then
          Begin
            Value := Params.Find('turn');
            If Value Is TJSONObject Then FTurnId := TJSONObject(Value).Get('id', '');
            If FTurnId <> '' Then FState := crsRunning;
          End;
        If Not (FState In [crsStartingTurn, crsRunning, crsCancelling]) Then Exit;
        If Method = 'turn/completed' Then
          Begin
            Value := Params.Find('turn');
            If Not (Value Is TJSONObject) Then Exit;
            Turn := TJSONObject(Value);
            If (FTurnId = '') Or (Turn.Get('id', '') <> FTurnId) Then Exit;
            Status := Turn.Get('status', '');
            If Status = 'failed' Then
              Begin
                Value := Turn.FindPath('error.message');
                If Assigned(Value) And (Value.JSONType = jtString) Then Fail(Copy(Value.AsString, 1, 2048))
                Else Fail('Codex turn failed.');
                Exit;
              End;
            If Not (Status = 'completed') And Not (Status = 'interrupted') Then Exit;
            FState := crsCompleted;
            FPendingId := '';
            FPendingMethod := '';
            SetLength(FTools, 0);
            FToolTaken := False;
          End
            Else If (Params.Get('turnId', '') = FTurnId) And (FTurnId <> '') Then
              Begin
                If Method = 'item/agentMessage/delta' Then
                  MessageText(Params.Get('itemId', ''), Params.Get('delta', ''), False)
                Else If Method = 'item/completed' Then
                  Begin
                    Value := Params.Find('item');
                    If (Value Is TJSONObject) And (TJSONObject(Value).Get('type', '') = 'agentMessage') Then
                      MessageText(TJSONObject(Value).Get('id', ''), TJSONObject(Value).Get('text', ''), True)
                    Else If (Value Is TJSONObject) And (TJSONObject(Value).Get('type', '') = 'reasoning') Then
                      Begin
                        Parts := TJSONObject(Value).Find('summary');
                        SummaryText := '';
                        If Parts Is TJSONArray Then
                          For I := 0 To Parts.Count - 1 Do
                            If (Parts.Items[I].JSONType = jtString) And (Parts.Items[I].AsString <> '') Then
                              Begin
                                If SummaryText <> '' Then SummaryText := SummaryText + LineEnding + LineEnding;
                                SummaryText := SummaryText + Parts.Items[I].AsString;
                              End;
                        If SummaryText <> '' Then
                          ReasoningText(TJSONObject(Value).Get('id', ''), SummaryText, 0, True);
                      End;
                  End
                        Else If Method = 'item/reasoning/summaryTextDelta' Then
                          ReasoningText(Params.Get('itemId', ''), Params.Get('delta', ''), Params.Get('summaryIndex', 0), False)
                        Else If Method = 'item/reasoning/textDelta' Then
                          ReasoningText(Params.Get('itemId', ''), Params.Get('delta', ''), Params.Get('contentIndex', 0), False);
                If (Length(FContent) > CodexMaxQueueBytes) Or (Length(FThinking) > CodexMaxQueueBytes) Then
                  Fail('Codex turn text limit exceeded.');
              End;
        Exit;
      End;
    If Not Assigned(Node) Or (Node.JSONType <> jtString) Then Exit;
    Id := Node.AsString;
    If (FPendingId = '') Or (Id <> FPendingId) Then Exit;
    If Assigned(Root.Find('error')) Then
      Begin
        Value := Root.FindPath('error.message');
        If Assigned(Value) And (Value.JSONType = jtString) Then
          Fail('Codex: ' + Copy(Value.AsString, 1, 2048))
        Else Fail('Codex rejected ' + FPendingMethod + '.');
        Exit;
      End;
    Value := Root.Find('result');
    If Not (Value Is TJSONObject) Then Raise Exception.Create('Missing result');
    Params := TJSONObject(Value);
    If FPendingMethod = 'thread/start' Then
      Begin
        If (Params.Get('modelProvider', '') <> 'openai') Or
          (Params.Get('approvalPolicy', '') <> 'on-request') Then
            Begin
              Fail('Codex did not apply the required provider/approval policy.');
              Exit;
            End;
        Value := Params.FindPath('sandbox.type');
        If Not Assigned(Value) Or (Value.AsString <> 'readOnly') Then
          Begin
            Fail('Codex did not apply the required read-only runtime sandbox.');
            Exit;
          End;
        Value := Params.Find('thread');
        If Not (Value Is TJSONObject) Then Raise Exception.Create('Missing thread');
        FThreadId := TJSONObject(Value).Get('id', '');
        If FThreadId = '' Then Raise Exception.Create('Missing thread ID');
        FState := crsReady;
      End
        Else If FPendingMethod = 'turn/start' Then
          Begin
            Value := Params.Find('turn');
            If Not (Value Is TJSONObject) Then Raise Exception.Create('Missing turn');
            FTurnId := TJSONObject(Value).Get('id', '');
            If FTurnId = '' Then Raise Exception.Create('Missing turn ID');
            FState := crsRunning;
          End
            Else If FPendingMethod = 'model/list' Then FModels := Params.AsJSON
            Else If FPendingMethod = 'account/rateLimits/read' Then FRateLimits := Params.AsJSON
            Else If FPendingMethod = 'mcpServerStatus/list' Then
              Begin
                Value := Params.Find('data');
                If Not (Value Is TJSONArray) Or (TJSONArray(Value).Count <> 0) Or
                  ((Params.Find('nextCursor') <> Nil) And (Params.Find('nextCursor').JSONType <> jtNull)) Then
                    Begin
                      Fail('External runtime tools are enabled. Use the dedicated Lazarus Codex profile.');
                      Exit;
                    End;
                FToolIsolationChecked := True;
              End;
    FPendingId := '';
    FPendingMethod := '';
  Finally
    Data.Free;
  End;
End;

Procedure TAssistantCodexClient.Pump;
Var
  Frame: String;
Begin
  If FState In [crsDisconnected, crsFailed] Then Exit;
  Try
    FTransport.Poll;
    While FTransport.TakeFrame(Frame) Do
      Begin
        HandleFrame(Frame);
        If FState = crsFailed Then Exit;
      End;
    If FTransport.LastError <> '' Then
      Begin
        Fail(FTransport.LastError);
        Exit;
      End;
    If FHandshake.State = ccsFailed Then
      Begin
        Fail(FHandshake.LastError);
        Exit;
      End;
    If (FState <> crsConnecting) And (FHandshake.State <> ccsSubscriptionAuthenticated) Then
      Begin
        Fail('ChatGPT subscription authentication changed; run stopped.');
        Exit;
      End;
    If (FState = crsConnecting) And (FHandshake.State = ccsSubscriptionAuthenticated) Then FState := crsReady;
    FlushHandshake;
    If ((FPendingId <> '') Or (FState = crsCancelling) Or
      ((FState = crsConnecting) And (FHandshake.State <> ccsNeedsSignIn))) And
      (GetTickCount64 >= FDeadline) Then Fail('Codex connection/request timed out.');
  Except
    On E: Exception Do Fail('Invalid Codex protocol response.');
  End;
End;
End.
