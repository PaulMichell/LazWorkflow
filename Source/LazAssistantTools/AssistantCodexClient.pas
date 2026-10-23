Unit AssistantCodexClient;

{ Worker-owned managed-runtime protocol. Dynamic tools are surfaced to a
  caller-owned IDE broker. Native approval requests are declined immediately
  and are never auto-approved.
  Codex builds are accepted when their generated app-server schemas support the
  wire contracts this client uses. User pictures are the same stored image refs as every
  other connection. This client sends them as documented localImage items, not a
  guessed field and not a text note. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantCodexHandshake, AssistantCodexTransport, AssistantImages, AssistantCodexQualification,
  AssistantCodexContext;

/// Shared catalogue items use function.parameters. Codex dynamicTools use name and inputSchema.
Function CodexDynamicToolsFromCatalogue(Const CatalogueJson: String): String;
/// thread/start params. DynamicToolsJson is a JSON array. Instructions are the harness prompt, not a Codex essay.
Function CodexThreadStartParams(Const WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions: String): String;
/// Documented turn input. Image refs become localImage paths of the upload derivative, then one text item.
/// An unresolved ref fails. Empty attachments is one text item. A text note is not a picture.
Function CodexUserInputJson(Const ProjectRoot, Text, AttachmentsJson: String; Out InputJson, ErrorText: String): Boolean;
/// turn/start params for text only. Image turns use CodexUserInputJson.
Function CodexTurnStartParams(Const ThreadId, Prompt, Effort: String): String;
/// turn/steer params for text only. Image steers use CodexUserInputJson.
Function CodexTurnSteerParams(Const ThreadId, TurnId, Text: String): String;
/// Missing inputModalities allows images. An explicit list without image does not. An unknown model is unknown.
Function CodexModelSelectionValid(Const ModelsJson, ModelId, Effort: String): Boolean;
Function CodexModelImageInput(Const ModelsJson, ModelId: String): TAssistantImageInput;
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
    FContextUsage: TCodexContextUsage;
    FModelItems: String;
    FModelCursors: TStringList;
    FModelCount: Integer;
    FCompatibility: TCodexCompatibility;
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
      Environment: TStrings = Nil; AccountOnly: Boolean = False; Cancelled: TCodexCancelled = Nil): Boolean;
    Procedure Pump;
    Procedure Disconnect;
    Procedure StartLogin;
    Function ListModels: Boolean;
    { Short-lived usage reader only. The live turn client must not call this. }
    Function ReadRateLimits: Boolean;
    Function CheckToolIsolation: Boolean;
    Function StartThread(Const WorkingDirectory, Model, ToolsJson: String; Const DeveloperInstructions: String = ''): Boolean;
    Function StartTurn(Const Prompt: String; Const Effort: String = ''; Const ProjectRoot: String = '';
      Const AttachmentsJson: String = ''): Boolean;
    Function Steer(Const Text: String): Boolean; Overload;
    { Builds documented localImage items. Unresolved refs fail. No project root cannot send pictures. }
    Function Steer(Const Text, AttachmentsJson: String): Boolean; Overload;
    Function Steer(Const Text, ProjectRoot, AttachmentsJson: String): Boolean; Overload;
    Function SteerInput(Const InputJson: String): Boolean;
    Procedure Interrupt;
    { May be called from the UI to force connection shutdown on next Pump.
      A non-empty Reason replaces the generic cancel text, for a timeout. }
    Procedure CancelConnection(Const Reason: String = '');
    Function TakeTool(Out Tool: TCodexToolRequest): Boolean;
    Function CompleteTool(Const CallId, Text: String; Success: Boolean): Boolean; Overload;
    { Image refs from read_image are the same store refs. They ride in contentItems when the frame can hold them. }
    Function CompleteTool(Const CallId, Text, ProjectRoot, AttachmentsJson: String; Success: Boolean): Boolean; Overload;
    Property ContextUsage: TCodexContextUsage Read FContextUsage;
    Property Compatibility: TCodexCompatibility Read FCompatibility;
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
  fpjson, jsonparser, AssistantProtocol, AssistantCodexProfile, AssistantCodexWire, AssistantCodexDiagnostics;

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
  Result := AssistantCodexWire.CodexNativeApprovalReply(Method, RequestId);
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
Begin
  Result := AssistantCodexWire.CodexThreadStartParams(WorkingDirectory, Model, DynamicToolsJson, DeveloperInstructions);
End;

Function CodexUserInputJson(Const ProjectRoot, Text, AttachmentsJson: String; Out InputJson, ErrorText: String): Boolean;
Var
  Refs: TAssistantImageRefArray;
  I: Integer;
  Path, Item, ModelText: String;
Begin
  InputJson := '';
  ErrorText := '';
  SetLength(Refs, 0);
  Result := False;
  If (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]') Then
    Begin
      If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Then
        Begin
          ErrorText := AssistantImageSendFailedPrefix + ' Attachment list is invalid.';
          Exit;
        End;
      Refs := LimitAssistantImageRefs(Refs);
    End;
  ModelText := AssistantImageModelText(Text, Length(Refs));
  InputJson := '[';
  For I := 0 To High(Refs) Do
    Begin
      If Not AssistantImageUploadFile(ProjectRoot, Refs[I], Path, ErrorText) Then
        Begin
          InputJson := '';
          If ErrorText = '' Then ErrorText := 'Stored image is missing.';
          ErrorText := AssistantImageSendFailedPrefix + ' ' + ErrorText;
          Exit;
        End;
      { Documented app-server item. Remote URLs are rejected. A data URI would exceed the frame limit. }
      Item := '{"type":"localImage","path":' + Quote(Path) + '}';
      If Length(InputJson) > 1 Then InputJson := InputJson + ',';
      InputJson := InputJson + Item;
    End;
  If Length(InputJson) > 1 Then InputJson := InputJson + ',';
  InputJson := InputJson + '{"type":"text","text":' + Quote(ModelText) + '}]';
  Result := True;
End;

Function CodexTurnStartParams(Const ThreadId, Prompt, Effort: String): String;
Var
  InputJson, ErrorText: String;
Begin
  If Not CodexUserInputJson('', Prompt, '', InputJson, ErrorText) Then
    InputJson := '[{"type":"text","text":' + Quote(Prompt) + '}]';
  Result := CodexTurnBody(ThreadId, '', InputJson, Effort, True);
End;

Function CodexTurnSteerParams(Const ThreadId, TurnId, Text: String): String;
Var
  InputJson, ErrorText: String;
Begin
  If Not CodexUserInputJson('', Text, '', InputJson, ErrorText) Then
    InputJson := '[{"type":"text","text":' + Quote(Text) + '}]';
  Result := CodexTurnBody(ThreadId, TurnId, InputJson, '', False);
End;

Function CodexModelImageInput(Const ModelsJson, ModelId: String): TAssistantImageInput;
Var
  Data, Items, Item, FoundId, Modalities: TJSONData;
  I: Integer;
  Wanted: String;
Begin
  Result := aiiUnknown;
  Wanted := Trim(ModelId);
  If (Wanted = '') Or (Trim(ModelsJson) = '') Then Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ModelsJson);
    Except
      Exit;
    End;
    If Not (Data Is TJSONObject) Then Exit;
    Items := TJSONObject(Data).Find('data');
    If Not (Items Is TJSONArray) Then Exit;
    For I := 0 To TJSONArray(Items).Count - 1 Do
      Begin
        Item := TJSONArray(Items).Items[I];
        If Not (Item Is TJSONObject) Then Continue;
        FoundId := TJSONObject(Item).Find('model');
        If Not Assigned(FoundId) Then FoundId := TJSONObject(Item).Find('id');
        If (Not Assigned(FoundId)) Or (FoundId.JSONType <> jtString) Or
          (Not SameText(Trim(FoundId.AsString), Wanted)) Then Continue;
        Modalities := TJSONObject(Item).Find('inputModalities');
        If Not Assigned(Modalities) Then Modalities := TJSONObject(Item).Find('input_modalities');
        Result := AssistantImageInputFromModalities(Modalities);
        Exit;
      End;
  Finally
    Data.Free;
  End;
End;

Function CodexModelSelectionValid(Const ModelsJson, ModelId, Effort: String): Boolean;
Var
  Data, Items, Item, Id, Levels, Level: TJSONData;
  I, J: Integer;
Begin
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ModelsJson);
      Items := Data.FindPath('data');
      If Not (Items Is TJSONArray) Then Exit;
      For I := 0 To Items.Count - 1 Do
        Begin
          Item := Items.Items[I];
          If Not (Item Is TJSONObject) Then Continue;
          Id := TJSONObject(Item).Find('model');
          If Not Assigned(Id) Then Id := TJSONObject(Item).Find('id');
          If Not Assigned(Id) Or (Id.JSONType <> jtString) Or (Id.AsString <> ModelId) Then Continue;
          If Effort = '' Then Exit(True);
          Levels := TJSONObject(Item).Find('supportedReasoningEfforts');
          If Not (Levels Is TJSONArray) Then Exit;
          For J := 0 To Levels.Count - 1 Do
            Begin
              Level := Levels.Items[J];
              If (Level Is TJSONObject) And (TJSONObject(Level).Get('reasoningEffort', '') = Effort) Then Exit(True);
            End;
          Exit;
        End;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Constructor TAssistantCodexClient.Create(RequestTimeoutMs: Cardinal);
Begin
  Inherited Create;
  FTransport := TAssistantCodexTransport.Create;
  FHandshake := TAssistantCodexHandshake.Create;
  FModelCursors := TStringList.Create;
  FSeenCalls := TStringList.Create;
  FMessageIds := TStringList.Create;
  FReasoningIds := TStringList.Create;
  FRequestTimeout := RequestTimeoutMs;
End;

Destructor TAssistantCodexClient.Destroy;
Begin
  Disconnect;
  FModelCursors.Free;
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
  FContextUsage := EmptyCodexContextUsage;
  FPendingId := '';
  FPendingMethod := '';
  FContent := '';
  FThinking := '';
  FModels := '';
  FModelItems := '';
  FModelCount := 0;
  FModelCursors.Clear;
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
    Environment: TStrings; AccountOnly: Boolean; Cancelled: TCodexCancelled): Boolean;
Var
  Args: TStringList;
  Reason: String;
Begin
  Disconnect;
  FError := '';
  Result := False;
  If Not InspectCodexRuntime(ResolveCodexExecutable(Executable), Environment, FCompatibility, Reason, Cancelled) Then
    Begin
      Fail('Codex preflight: ' + Reason);
      Exit;
    End;
  If FCompatibility.Support[ccAccount] = csUnsupported Then
    Begin
      Fail('Codex account protocol is incompatible: ' + FCompatibility.Reason[ccAccount]);
      Exit;
    End;
  If Not AccountOnly And (FCompatibility.Support[ccRun] <> csSupported) Then
    Begin
      Fail('Codex IDE execution is unavailable: ' + FCompatibility.Reason[ccRun]);
      Exit;
    End;
  If Not CodexRuntimeUnchanged(FCompatibility, Reason, Cancelled) Then
    Begin
      Fail(Reason);
      Exit;
    End;
  Args := TStringList.Create;
  Try
    CodexSubscriptionArguments(Args, Not AccountOnly);
    Result := FTransport.Start(FCompatibility.Executable, WorkingDirectory, Args, Environment);
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
  FHandshake.Start(Not AccountOnly);
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
  FHandshake.StartChatGPTLogin(FCompatibility.Support[ccLogin] <> csUnsupported,
    FCompatibility.Support[ccDeviceLogin] <> csUnsupported);
  FDeadline := GetTickCount64 + 300000;
  FlushHandshake;
End;

Function TAssistantCodexClient.ListModels: Boolean;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And
    (FState In [crsReady, crsCompleted]);
  If Result Then
    Begin
      FModelItems := '';
      FModelCount := 0;
      FModelCursors.Clear;
      FModels := '';
      Result := Request('model/list', '{"includeHidden":false,"limit":100}');
    End;
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
  If FCompatibility.Support[ccRun] <> csSupported Then
    Begin
      Fail('Codex IDE execution is unavailable: ' + FCompatibility.Reason[ccRun]);
      Exit;
    End;
  Dynamic := CodexDynamicToolsFromCatalogue(ToolsJson);
  Data := GetJSON(Dynamic);
  Try
    If Not (Data Is TJSONArray) Then Exit;
    { Built-in actions have no write permission. Approvals must be serviced by
      this client, which rejects them. Developer instructions come from the harness. }
    Result := Request('thread/start', AssistantCodexWire.CodexThreadStartParams(WorkingDirectory, Model, Dynamic,
      DeveloperInstructions, FCompatibility.Adapter = 'named-permissions-tagged-v1'));
    If Result Then
      Begin
        FContextUsage := EmptyCodexContextUsage;
        FThreadId := '';
        FState := crsStartingThread;
      End;
  Finally
    Data.Free;
  End;
End;

Function TAssistantCodexClient.StartTurn(Const Prompt: String; Const Effort: String;
  Const ProjectRoot: String; Const AttachmentsJson: String): Boolean;
Var
  InputJson, ImageError: String;
Begin
  Result := (FHandshake.State = ccsSubscriptionAuthenticated) And
    (FThreadId <> '') And (FState In [crsReady, crsCompleted]);
  If Not Result Then Exit;
  If (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]') And
    (FCompatibility.Support[ccImages] <> csSupported) Then
    Begin
      Fail('Codex image input is unavailable: ' + FCompatibility.Reason[ccImages]);
      Exit(False);
    End;
  If Not CodexUserInputJson(ProjectRoot, Prompt, AttachmentsJson, InputJson, ImageError) Then
    Begin
      Fail(ImageError);
      Exit;
    End;
  Result := Request('turn/start', CodexTurnBody(FThreadId, '', InputJson, Effort, True, FCompatibility.Support[ccSummary] = csSupported));
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
  Result := Steer(Text, '', '');
End;

Function TAssistantCodexClient.Steer(Const Text, AttachmentsJson: String): Boolean;
Begin
  Result := Steer(Text, '', AttachmentsJson);
End;

Function TAssistantCodexClient.Steer(Const Text, ProjectRoot, AttachmentsJson: String): Boolean;
Var
  InputJson, ImageError: String;
Begin
  Result := False;
  If Not CodexUserInputJson(ProjectRoot, Text, AttachmentsJson, InputJson, ImageError) Then
    Begin
      If ImageError <> '' Then FError := ImageError;
      Exit;
    End;
  Result := SteerInput(InputJson);
End;

Function TAssistantCodexClient.SteerInput(Const InputJson: String): Boolean;
Var
  Data: TJSONData;
  I: Integer;
Begin
  If FCompatibility.Support[ccSteer] <> csSupported Then
    Begin
      FError := 'Codex steering is unavailable: ' + FCompatibility.Reason[ccSteer];
      Exit(False);
    End;
  Result := (FState = crsRunning) And (FTurnId <> '') And (Length(InputJson) > 1) And (InputJson[1] = '[');
  If Not Result Then Exit;
  If Length(InputJson) > CodexMaxFrameBytes - 512 Then Exit;
  If FCompatibility.Support[ccImages] <> csSupported Then
    Begin
      Data := Nil;
      Try
        Try
          Data := GetJSON(InputJson);
          If Not (Data Is TJSONArray) Then Exit(False);
          For I := 0 To Data.Count - 1 Do
            If Not (Data.Items[I] Is TJSONObject) Or
              (TJSONObject(Data.Items[I]).Get('type', '') <> 'text') Then
              Begin
                FError := 'Codex image steering is unavailable.';
                Exit(False);
              End;
        Except
          Exit(False);
        End;
      Finally
        Data.Free;
      End;
    End;
  Result := Request('turn/steer', CodexTurnBody(FThreadId, FTurnId, InputJson, '', False));
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
Begin
  Result := CompleteTool(CallId, Text, '', '', Success);
End;

Function TAssistantCodexClient.CompleteTool(Const CallId, Text, ProjectRoot, AttachmentsJson: String;
  Success: Boolean): Boolean;
Var
  I, Budget: Integer;
  Refs: TAssistantImageRefArray;
  Items, Uri, ImageError, Note, Line: String;
Begin
  Result := False;
  If (FState <> crsRunning) Or Not FToolTaken Or (Length(FTools) = 0) Then Exit;
  If FTools[0].CallId <> CallId Then Exit;
  SetLength(Refs, 0);
  Note := Text;
  If (Trim(AttachmentsJson) <> '') And (Trim(AttachmentsJson) <> '[]') And
    ParseAssistantImageRefs(AttachmentsJson, Refs) And (Length(Refs) > 0) Then
    Begin
      Refs := LimitAssistantImageRefs(Refs);
      Budget := CodexMaxFrameBytes - Length(Note) - 1024;
      If Budget > 900000 Then Budget := 900000;
      If Length(Refs) > 0 Then Budget := Budget Div Length(Refs);
      If Budget < 64 Then
        Note := Note + LineEnding + AssistantImageSendFailedPrefix + ' Image could not be prepared for upload.';
    End
  Else
    Budget := 0;
  If (Length(Refs) > 0) And (FCompatibility.Support[ccImages] <> csSupported) Then
    Begin
      Budget := 0;
      Success := False;
      Note := Note + LineEnding + 'Codex image tool results are unavailable for this runtime.';
    End;
  Items := '[{"type":"inputText","text":' + Quote(Note) + '}';
  If Budget >= 64 Then
    For I := 0 To High(Refs) Do
      Begin
        Uri := '';
        ImageError := '';
        If AssistantImageDataUriWithin(ProjectRoot, Refs[I], Budget, Uri, ImageError) And
          (Copy(LowerCase(Uri), 1, 5) = 'data:') Then
          Items := Items + ',{"type":"inputImage","imageUrl":' + Quote(Uri) + '}'
        Else
          Begin
            If ImageError = '' Then ImageError := 'Image could not be prepared for upload.';
            Note := Note + LineEnding + AssistantImageSendFailedPrefix + ' ' + ImageError;
            Items := '[{"type":"inputText","text":' + Quote(Note) + '}';
            Break;
          End;
      End;
  Items := Items + ']';
  Line := '{"id":' + FTools[0].RequestId + ',"result":{"success":' + LowerCase(BoolToStr(Success, True)) +
    ',"contentItems":' + Items + '}}';
  If Length(Line) > CodexMaxFrameBytes Then
    Begin
      Note := Text + LineEnding + AssistantImageSendFailedPrefix + ' Image could not be prepared for upload.';
      Line := '{"id":' + FTools[0].RequestId + ',"result":{"success":' + LowerCase(BoolToStr(Success, True)) +
        ',"contentItems":[{"type":"inputText","text":' + Quote(Note) + '}]}}';
    End;
  Result := FTransport.Queue(Line);
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
        If (FThreadId = '') Or (Params.Get('threadId', '') <> FThreadId) Then Exit;
        If Method = 'thread/tokenUsage/updated' Then
          Begin
            { Thread-scoped and sometimes delivered after turn/completed. }
            Value := Params.Find('tokenUsage');
            If Value Is TJSONObject Then ParseCodexContextUsage(Value, FContextUsage);
            Exit;
          End;
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
                If Assigned(Value) And (Value.JSONType = jtString) Then Fail('Codex turn failed: ' + CodexDiagnosticCategory(Value.AsString) + '.')
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
        Value := Root.FindPath('error.code');
        N := 0;
        If Assigned(Value) And (Value.JSONType = jtNumber) Then N := Value.AsInteger;
        Value := Root.FindPath('error.message');
        Status := '';
        If Assigned(Value) And (Value.JSONType = jtString) Then Status := Value.AsString;
        Fail(CodexRequestError(FPendingMethod, N, Status));
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
        Value := Params.FindPath('sandbox.networkAccess');
        If Not Assigned(Value) Or (Value.JSONType <> jtBoolean) Or Value.AsBoolean Then
          Begin
            Fail('Codex did not disable runtime tool network access.');
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
            Else If FPendingMethod = 'model/list' Then
              Begin
                Value := Params.Find('data');
                If Not (Value Is TJSONArray) Then Raise Exception.Create('Missing models');
                Inc(FModelCount, Value.Count);
                If FModelCount > 4096 Then Raise Exception.Create('Too many models');
                For I := 0 To Value.Count - 1 Do
                  Begin
                    If FModelItems <> '' Then FModelItems := FModelItems + ',';
                    FModelItems := FModelItems + Value.Items[I].AsJSON;
                  End;
                If Length(FModelItems) > CodexMaxQueueBytes Then Raise Exception.Create('Model list limit');
                Value := Params.Find('nextCursor');
                If Assigned(Value) And (Value.JSONType <> jtNull) Then
                  Begin
                    If Value.JSONType <> jtString Then Raise Exception.Create('Invalid model cursor');
                    Status := Value.AsString;
                    If (Status = '') Or (FModelCursors.Count >= 32) Or
                      (FModelCursors.IndexOf(Status) >= 0) Then Raise Exception.Create('Repeated model cursor');
                    FModelCursors.Add(Status);
                    FPendingId := '';
                    FPendingMethod := '';
                    If Not Request('model/list', '{"includeHidden":false,"limit":100,"cursor":' + Quote(Status) + '}') Then
                      Fail('Cannot request the next model page.');
                    Exit;
                  End;
                FModels := '{"data":[' + FModelItems + '],"nextCursor":null}';
              End
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
