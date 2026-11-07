Unit AssistantMonitorCodec;

{ Monitor catalogue 3 envelope, shared payload types and limits (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantConversation, AssistantSessionObserve;

Const
  MonitorCatalogueVersion = 3;
  { One above GrokOAuthRedirectPort. The implementation checks that relationship. }
  MonitorListenPort = 56122;
  MonitorMaxMessageIdChars = 64;
  MonitorMaxSendChars = 65536;
  { Same cap as MaxToolEventChars in AssistantActor.pas. }
  MonitorMaxToolBodyChars = 4000;
  MonitorMaxImagePartBytes = 190000;
  { 4 * ceil(190000 / 3). With the envelope budget the frame stays under 262144. }
  MonitorImagePartBase64Chars = 253336;
  MonitorImageEnvelopeBytes = 8192;
  MonitorMaxImageFetchBytes = 1048576;
  { A chunked item, joined, not one frame. Matches catalogue limit max_item_bytes. }
  MonitorMaxItemBytes = 4 * 1024 * 1024;
  { AssistantImageMaxFileBytes (8 MiB) is the store limit, not this frame budget. }
  MonitorSnapshotStoredTurns = 30;
  MonitorNoSessionReason = 'no_session';
  MonitorNoSessionMessage = 'The Project Assistant window is not open.';
  MonitorUnknownTypeReason = 'unknown_type';
  MonitorPayloadTooLargeReason = 'payload_too_large';
  MonitorHostBusyReason = 'host_busy';
  MonitorPayloadTooLargeMessage = 'Text is longer than 65536 characters.';

Type
  TMonitorMessageKind = (
    mmkUnknown,
    mmkHello,
    mmkPair,
    mmkPairOk,
    mmkHelloOk,
    mmkAuth,
    mmkRejected,
    mmkBye,
    mmkRefresh,
    mmkTurn,
    mmkMode,
    mmkSetMode,
    mmkSend,
    mmkSteer,
    mmkStop,
    mmkStatus,
    mmkTarget,
    mmkPlan,
    mmkSelectPlan,
    mmkNewPlan,
    mmkClosePlan,
    mmkWorkOnPlan,
    mmkRunPlan,
    mmkStopPlan,
    mmkTasks,
    mmkRunTask,
    mmkInsertTask,
    mmkInsertResult,
    mmkApprovalRequested,
    mmkApprovalDecision,
    mmkApprovalClosed,
    mmkImageGet,
    mmkImageData,
    mmkImageUnavailable,
    mmkNewConversation,
    mmkError,
    mmkPing,
    mmkPong,
    mmkResume,
    mmkConversationClosed,
    mmkTargets,
    mmkSelectTarget,
    mmkConversations,
    mmkSelectConversation,
    mmkModels,
    mmkSetModel,
    mmkReasoning,
    mmkSetReasoning,
    mmkPermissions,
    mmkSetPermissions,
    mmkSnapshotPage,
    mmkChunk,
    mmkCommandState,
    mmkCommandStates
  );

  { A payload owns its parsed object through a shared reference. Copies, including
    deferred commands, retain it; the last caller releases it automatically. }
  IMonitorPayload = Interface
    Function GetObject: TJSONObject;
  End;

  TMonitorPayload = Record
    Source: String;
    Parsed: IMonitorPayload;
    ObjectValue: TJSONObject;
  End;

  TMonitorMessage = Record
    Version: Integer;
    Id: String;
    Kind: TMonitorMessageKind;
    TypeName: String;
    PayloadJson: TMonitorPayload;
    Reason: String;
    { False for unknown_type and for a send or steer the text limit rejects. }
    ChangesState: Boolean;
    WireJson: String;
  End;

  TMonitorHello = Record
    ClientName: String;
    ClientVersion: String;
    ClientId: String;
    HasClientId: Boolean;
  End;

  TMonitorPair = Record
    Code: String;
    Fingerprint: String;
  End;

  TMonitorPairOk = Record
    ClientId: String;
    SessionToken: String;
  End;

  TMonitorHelloOk = Record
    Nonce: String;
    ServerName: String;
    Epoch: String;
    Cursor: Int64;
    ConversationId: String;
    ProjectRoot: String;
    Title: String;
    { Installation identity. 32 lowercase hex. The phone's hostFingerprint. }
    HostId: String;
  End;

  TMonitorAuth = Record
    ClientId: String;
    Hmac: String;
  End;

  TMonitorRejected = Record
    Reason: String;
    HostVersion: Integer;
    ClientVersion: Integer;
  End;

  TMonitorBye = Record
    Reason: String;
  End;

  TMonitorModeMessage = Record
    Mode: String;
    Locked: Boolean;
  End;

  TMonitorTargetMessage = Record
    Kind: String;
    Display: String;
    Root: String;
  End;

  TMonitorTargetChoice = Record
    Path: String;
    Caption: String;
  End;

  TMonitorTargetsMessage = Record
    Current: String;
    Choices: Array Of TMonitorTargetChoice;
  End;

  TMonitorConversationChoice = Record
    Id: String;
    Title: String;
    Current: Boolean;
  End;

  TMonitorConversationsMessage = Record
    Current: String;
    Choices: Array Of TMonitorConversationChoice;
    Truncated: Boolean;
  End;

  TMonitorModelChoice = Record
    Id: String;
    Caption: String;
  End;

  TMonitorModelsMessage = Record
    Current: String;
    Backend: String;
    Choices: Array Of TMonitorModelChoice;
    Note: String;
  End;

  TMonitorReasoningChoice = Record
    Id: String;
    Caption: String;
  End;

  TMonitorReasoningMessage = Record
    Current: String;
    Choices: Array Of TMonitorReasoningChoice;
    Note: String;
  End;

  TMonitorPermissionChoice = Record
    Id: String;
    Caption: String;
  End;

  TMonitorPermissionsMessage = Record
    Current: String;
    Backend: String;
    Choices: Array Of TMonitorPermissionChoice;
    Note: String;
  End;

  TMonitorPathMessage = Record
    Path: String;
    Title: String;
    HasTitle: Boolean;
  End;

  TMonitorTaskCommand = Record
    Id: String;
    Note: String;
  End;

  TMonitorApprovalDecision = Record
    ToolId: String;
    Allow: Boolean;
  End;

  TMonitorApprovalClosed = Record
    ToolId: String;
    Reason: String;
  End;

  TMonitorImageGet = Record
    TurnIndex: Integer;
    ImageId: String;
  End;

  TMonitorImageData = Record
    ImageId: String;
    Mime: String;
    Width: Integer;
    Height: Integer;
    Part: Integer;
    PartCount: Integer;
    Revision: Integer;
    BytesBase64: String;
  End;

  TMonitorImageUnavailable = Record
    ImageId: String;
    Reason: String;
  End;

  TMonitorErrorBody = Record
    Reason: String;
    MessageText: String;
    RefId: String;
  End;

  TMonitorTicks = Record
    Ticks: Int64;
  End;

  TMonitorBodyPart = Record
    Part: Integer;
    PartCount: Integer;
    Revision: Integer;
    Text: String;
  End;
  TMonitorBodyPartArray = Array Of TMonitorBodyPart;

  TMonitorTranscript = Record
    TurnIndex: Integer;
    Revision: Integer;
    Phase: String;
    StatusText: String;
    DurationMs: Integer;
    Blocks: Array Of TAssistantMonitorBlock;
    { Parallel to Blocks. 1 and 1 when that block was not split. }
    BlockPart: Array Of Integer;
    BlockPartCount: Array Of Integer;
    Part: Integer;
    PartCount: Integer;
  End;
  TMonitorTranscriptArray = Array Of TMonitorTranscript;

  TMonitorSnapshot = Record
    View: TAssistantMonitorView;
    StoredTurns: Array Of TAssistantMonitorTurn;
    Live: TAssistantMonitorTurn;
    HasLive: Boolean;
    PlanPath: String;
    PlanTitle: String;
    PlanRunning: Boolean;
    { Optional plan-frame body. Not written into a snapshot. }
    PlanBody: String;
    { True when this frame replaces the phone's cached document, including an empty one. }
    PlanComplete: Boolean;
    PlanRows: Array Of TAssistantMonitorPlanRow;
    TaskRows: Array Of TAssistantMonitorTaskRow;
    Approval: TAssistantApprovalNotice;
  End;

  { Client resume. Not a user command. Cursor 0 means nothing has been applied.
    Commands lists outbox ids whose outcome the phone does not know. }
  TMonitorResume = Record
    Epoch: String;
    Cursor: Int64;
    ConversationId: String;
    Commands: TStringArray;
  End;

  TMonitorCommandStateReply = Record
    Ref: String;
    State: String;
    Reason: String;
    Text: String;
  End;

  TMonitorConversationClosed = Record
    Epoch: String;
    Cursor: Int64;
    ConversationId: String;
    Title: String;
  End;

Function MonitorMessageKindName(Kind: TMonitorMessageKind): String;
Operator := (Const Json: String): TMonitorPayload;
Operator := (Const Payload: TMonitorPayload): String;
{ Child borrows Obj; Parent retains the envelope owner. A raw parent's parse must outlive the child. }
Function MonitorChildPayload(Const Parent: TMonitorPayload; Obj: TJSONObject): TMonitorPayload;

Function MonitorMessageKindFromName(Const Name: String): TMonitorMessageKind;
Function MonitorMessageIdIsSafe(Const Id: String): Boolean;
Function MonitorRejectedReasonIsKnown(Const Reason: String): Boolean;
Function MonitorApprovalCloseReasonIsKnown(Const Reason: String): Boolean;
Function MonitorImageUnavailableReasonIsKnown(Const Reason: String): Boolean;
Function MonitorModeName(Mode: TAssistantMode): String;
Function MonitorModeIsKnown(Const ModeText: String): Boolean;

{ Shared by the command and state units. Not a second catalogue. }
{ Data owns a fresh parse, or is Nil when Obj is borrowed from Json. Always free Data, never Obj. }
Function ParseMonitorObject(Const Json: TMonitorPayload; Out Data: TJSONData; Out Obj: TJSONObject): Boolean;
Function ReadMonitorString(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: String): Boolean;
Function ReadMonitorInt(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Integer): Boolean;
Function ReadMonitorInt64(Obj: TJSONObject; Const Name: String; Out Value: Int64): Boolean;
Function ReadMonitorBool(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Boolean): Boolean;
Function EncodeMonitorWith(Kind: TMonitorMessageKind; Const Id: String; Payload: TJSONObject): String;
Function EncodeMonitorOneString(Kind: TMonitorMessageKind; Const Id, Field, Value: String): String;
Function DecodeMonitorOneString(Const PayloadJson: TMonitorPayload; Const Field: String; Out Value: String): Boolean;

{ Empty when the id is unsafe or the object would exceed the frame cap. }
Function EncodeMonitorEnvelope(Kind: TMonitorMessageKind; Const Id: String; Const Payload: TJSONObject): String;
Function TryDecodeMonitorEnvelope(Const Json: String; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
Function MonitorUnknownTypeError(Const RefId, TypeName: String): String;
Function EncodeMonitorError(Const Id, Reason, MessageText, RefId: String): String;
Function DecodeMonitorError(Const PayloadJson: TMonitorPayload; Out ErrorBody: TMonitorErrorBody): Boolean;

{ ClientId empty is the first hello. A non-empty id is the reconnect shape. }








{ 32 lowercase hex digits. Empty is not valid. }
Function MonitorHostIdIsValid(Const HostId: String): Boolean;




























































{ One plan frame when it fits. Otherwise chunk frames of the same item, for the plan lane. }












{ Same cursor on every part. Empty when a single block cannot be cut down to the cap. }


{ FirstPatch copies every current block. Later patches keep only a new block, or one whose
  body, title, running flag, or ok flag changed. Duration and elapsed time do not count. }

{ False when any part of that cursor is missing, duplicated, or a different epoch. }



{ One snapshot catchup. The cursor is the snapshot cursor, not the client's discarded cursor. }




{ True when the host must send image_unavailable and keep the socket open. }







{ Messages are image_data envelopes, or empty when UnavailableReason is set. Does not close a socket. }

{ One image_data item, split into outbox chunk frames when it does not fit in 32 KiB. }

{ Wraps PayloadJson as type ItemType. A frame over the outbox chunk size becomes chunk frames. }


Implementation

Uses
  jsonparser, GrokOAuth, AssistantTasks, AssistantMonitorFrames;

{$IF MonitorListenPort <> GrokOAuthRedirectPort + 1}
  {$ERROR Listen port must stay one above GrokOAuthRedirectPort}
{$ENDIF}
{$IF MonitorImagePartBase64Chars + MonitorImageEnvelopeBytes > MonitorMaxPayloadBytes}
  {$ERROR Image part envelope exceeds the frame cap}
{$ENDIF}
{$IF ((MonitorMaxImagePartBytes + 2) Div 3) * 4 <> MonitorImagePartBase64Chars}
  {$ERROR Image part base64 size drifted}
{$ENDIF}

Type
  TMonitorPayloadOwner = Class(TInterfacedObject, IMonitorPayload)
  Private
    PayloadObject: TJSONObject;
  Public
    Constructor Create(OwnedObject: TJSONObject);
    Destructor Destroy; Override;
    Function GetObject: TJSONObject;
  End;

Constructor TMonitorPayloadOwner.Create(OwnedObject: TJSONObject);
Begin
  Inherited Create;
  PayloadObject := OwnedObject;
End;

Destructor TMonitorPayloadOwner.Destroy;
Begin
  FreeAndNil(PayloadObject);
  Inherited Destroy;
End;

Function TMonitorPayloadOwner.GetObject: TJSONObject;
Begin
  Result := PayloadObject;
End;

Operator:=(Const Json: String): TMonitorPayload;
Begin
  Result.Source := Json;
  Result.Parsed := Nil;
  Result.ObjectValue := Nil;
End;

Operator:=(Const Payload: TMonitorPayload): String;
Begin
  If Assigned(Payload.ObjectValue) Then
    Result := Payload.ObjectValue.AsJSON
  Else
    Result := Payload.Source;
End;

Function MonitorChildPayload(Const Parent: TMonitorPayload; Obj: TJSONObject): TMonitorPayload;
Begin
  Result.Source := '';
  Result.Parsed := Parent.Parsed;
  Result.ObjectValue := Obj;
End;

Const
  MonitorKindNames: Array[TMonitorMessageKind] Of String = (
    '',
    'hello',
    'pair',
    'pair_ok',
    'hello_ok',
    'auth',
    'rejected',
    'bye',
    'refresh',
    'turn',
    'mode',
    'set_mode',
    'send',
    'steer',
    'stop',
    'status',
    'target',
    'plan',
    'select_plan',
    'new_plan',
    'close_plan',
    'work_on_plan',
    'run_plan',
    'stop_plan',
    'tasks',
    'run_task',
    'insert_task',
    'insert_result',
    'approval_requested',
    'approval_decision',
    'approval_closed',
    'image_get',
    'image_data',
    'image_unavailable',
    'new_conversation',
    'error',
    'ping',
    'pong',
    'resume',
    'conversation_closed',
    'targets',
    'select_target',
    'conversations',
    'select_conversation',
    'models',
    'set_model',
    'reasoning',
    'set_reasoning',
    'permissions',
    'set_permissions',
    'snapshot_page',
    'chunk',
    'command_state',
    'command_states'
  );
  { Sorted once in source; binary lookup does not construct catalogue names. }
  MonitorSortedKinds: Array[0..52] Of TMonitorMessageKind = (
    mmkApprovalClosed,
    mmkApprovalDecision,
    mmkApprovalRequested,
    mmkAuth,
    mmkBye,
    mmkChunk,
    mmkClosePlan,
    mmkCommandState,
    mmkCommandStates,
    mmkConversationClosed,
    mmkConversations,
    mmkError,
    mmkHello,
    mmkHelloOk,
    mmkImageData,
    mmkImageGet,
    mmkImageUnavailable,
    mmkInsertResult,
    mmkInsertTask,
    mmkMode,
    mmkModels,
    mmkNewConversation,
    mmkNewPlan,
    mmkPair,
    mmkPairOk,
    mmkPermissions,
    mmkPing,
    mmkPlan,
    mmkPong,
    mmkReasoning,
    mmkRefresh,
    mmkRejected,
    mmkResume,
    mmkRunPlan,
    mmkRunTask,
    mmkSelectConversation,
    mmkSelectPlan,
    mmkSelectTarget,
    mmkSend,
    mmkSetMode,
    mmkSetModel,
    mmkSetPermissions,
    mmkSetReasoning,
    mmkSnapshotPage,
    mmkStatus,
    mmkSteer,
    mmkStop,
    mmkStopPlan,
    mmkTarget,
    mmkTargets,
    mmkTasks,
    mmkTurn,
    mmkWorkOnPlan
  );

Function MonitorMessageKindName(Kind: TMonitorMessageKind): String;
Begin
  Result := MonitorKindNames[Kind];
End;

Function MonitorMessageKindFromName(Const Name: String): TMonitorMessageKind;
Var
  First, Last, Middle, Comparison: Integer;
  Kind: TMonitorMessageKind;
Begin
  First := Low(MonitorSortedKinds);
  Last := High(MonitorSortedKinds);
  While First <= Last Do
    Begin
      Middle := First + (Last - First) Div 2;
      Kind := MonitorSortedKinds[Middle];
      Comparison := CompareStr(Name, MonitorKindNames[Kind]);
      If Comparison = 0 Then
        Exit(Kind);
      If Comparison < 0 Then
        Last := Middle - 1
      Else
        First := Middle + 1;
    End;
  Result := mmkUnknown;
End;

Function MonitorMessageIdIsSafe(Const Id: String): Boolean;
Begin
  Result := (Length(Id) <= MonitorMaxMessageIdChars) And TaskIdIsSafe(Id);
End;

Function ReasonIn(Const Reason: String; Const Names: Array Of String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To High(Names) Do
    If Reason = Names[I] Then
      Exit(True);
End;

Function MonitorRejectedReasonIsKnown(Const Reason: String): Boolean;
Begin
  Result := ReasonIn(Reason, ['protocol', 'pair_code', 'fingerprint', 'expired', 'auth', 'revoked', 'busy', 'disabled']);
End;

Function MonitorApprovalCloseReasonIsKnown(Const Reason: String): Boolean;
Begin
  Result := ReasonIn(Reason, ['allowed', 'denied', 'finished', 'timeout', 'desktop', 'disabled', 'stopped']);
End;

Function MonitorImageUnavailableReasonIsKnown(Const Reason: String): Boolean;
Begin
  Result := ReasonIn(Reason, ['missing', 'too_large', 'refused']);
End;

Function MonitorModeName(Mode: TAssistantMode): String;
Begin
  Result := AssistantModeToStr(Mode);
End;

Function MonitorModeIsKnown(Const ModeText: String): Boolean;
Var
  Mode: TAssistantMode;
Begin
  Result := False;
  For Mode := Low(TAssistantMode) To High(TAssistantMode) Do
    If AssistantModeToStr(Mode) = ModeText Then
      Exit(True);
End;

Function ParseObject(Const Json: String; Out Data: TJSONData; Out Obj: TJSONObject): Boolean;
Begin
  Result := False;
  Data := Nil;
  Obj := Nil;
  Try
    {$IFDEF MONITOR_COUNT_PARSES}
    MonitorNoteJsonParse;
    {$ENDIF}
    Data := GetJSON(Json);
  Except
    Exit;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      FreeAndNil(Data);
      Exit;
    End;
  Obj := TJSONObject(Data);
  Result := True;
End;

Function ReadString(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: String): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := '';
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Not Assigned(Node) Then
    Begin
      Result := Not Required;
      Exit;
    End;
  If Node.JSONType <> jtString Then
    Exit;
  Value := Node.AsString;
  Result := True;
End;

Function ReadInt(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Integer): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := 0;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Not Assigned(Node) Then
    Begin
      Result := Not Required;
      Exit;
    End;
  If Node.JSONType <> jtNumber Then
    Exit;
  Value := Node.AsInteger;
  Result := True;
End;

Function ReadInt64(Obj: TJSONObject; Const Name: String; Out Value: Int64): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := 0;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Then
    Exit;
  Value := Node.AsInt64;
  Result := True;
End;

Function ReadBool(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Boolean): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := False;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Not Assigned(Node) Then
    Begin
      Result := Not Required;
      Exit;
    End;
  If Node.JSONType <> jtBoolean Then
    Exit;
  Value := Node.AsBoolean;
  Result := True;
End;

Function EncodeMonitorEnvelope(Kind: TMonitorMessageKind; Const Id: String; Const Payload: TJSONObject): String;
Var
  Root: TJSONObject;
  Owned: Integer;
Begin
  Result := '';
  If (Kind = mmkUnknown) Or (Not MonitorMessageIdIsSafe(Id)) Then
    Exit;
  Root := TJSONObject.Create;
  Owned := -1;
  Try
    Root.Add('v', MonitorCatalogueVersion);
    Root.Add('id', Id);
    Root.Add('type', MonitorMessageKindName(Kind));
    { The caller still owns Payload. Add it for AsJSON, then extract it so Root.Free does not free it.
      Cloning a snapshot or image part only to serialise it was the copy 5.1 removes. }
    If Assigned(Payload) Then
      Begin
        Root.Add('payload', Payload);
        Owned := Root.Count - 1;
      End
    Else
      Root.Add('payload', TJSONObject.Create);
    Result := Root.AsJSON;
    If Length(Result) > MonitorMaxPayloadBytes Then
      Result := '';
  Finally
    If Owned >= 0 Then
      Root.Extract(Owned);
    Root.Free;
  End;
End;

Function EncodeWith(Kind: TMonitorMessageKind; Const Id: String; Payload: TJSONObject): String;
Begin
  Result := '';
  Try
    Result := EncodeMonitorEnvelope(Kind, Id, Payload);
  Finally
    Payload.Free;
  End;
End;

Function EncodeOneString(Kind: TMonitorMessageKind; Const Id, Field, Value: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add(Field, Value);
  Result := EncodeWith(Kind, Id, Payload);
End;

Function DecodeOneString(Const PayloadJson: TMonitorPayload; Const Field: String; Out Value: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Value := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, Field, True, Value);
  Finally
    Data.Free;
  End;
End;

{ Data owns a fresh parse, or is Nil when Obj is borrowed from Json. Always free Data, never Obj. }
Function ParseMonitorObject(Const Json: TMonitorPayload; Out Data: TJSONData; Out Obj: TJSONObject): Boolean;
Begin
  Data := Nil;
  Obj := Nil;
  If Assigned(Json.ObjectValue) Then
    Begin
      Obj := Json.ObjectValue;
      Exit(Assigned(Obj));
    End;
  Result := ParseObject(Json.Source, Data, Obj);
End;

Function ReadMonitorString(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: String): Boolean;
Begin
  Result := ReadString(Obj, Name, Required, Value);
End;

Function ReadMonitorInt(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Integer): Boolean;
Begin
  Result := ReadInt(Obj, Name, Required, Value);
End;

Function ReadMonitorInt64(Obj: TJSONObject; Const Name: String; Out Value: Int64): Boolean;
Begin
  Result := ReadInt64(Obj, Name, Value);
End;

Function ReadMonitorBool(Obj: TJSONObject; Const Name: String; Required: Boolean; Out Value: Boolean): Boolean;
Begin
  Result := ReadBool(Obj, Name, Required, Value);
End;

Function EncodeMonitorWith(Kind: TMonitorMessageKind; Const Id: String; Payload: TJSONObject): String;
Begin
  Result := EncodeWith(Kind, Id, Payload);
End;

Function EncodeMonitorOneString(Kind: TMonitorMessageKind; Const Id, Field, Value: String): String;
Begin
  Result := EncodeOneString(Kind, Id, Field, Value);
End;

Function DecodeMonitorOneString(Const PayloadJson: TMonitorPayload; Const Field: String; Out Value: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, Field, Value);
End;

Function EncodeMonitorError(Const Id, Reason, MessageText, RefId: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('reason', Reason);
  Payload.Add('message', MessageText);
  Payload.Add('ref', RefId);
  Result := EncodeWith(mmkError, Id, Payload);
End;

Function MonitorUnknownTypeError(Const RefId, TypeName: String): String;
Var
  Shown: String;
Begin
  Shown := TypeName;
  If Length(Shown) > MonitorMaxMessageIdChars Then
    Shown := Copy(Shown, 1, MonitorMaxMessageIdChars);
  Result := EncodeMonitorError(RefId, MonitorUnknownTypeReason, 'Unknown message type ' + Shown + '.', RefId);
End;

Function DecodeMonitorError(Const PayloadJson: TMonitorPayload; Out ErrorBody: TMonitorErrorBody): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ErrorBody.Reason := '';
  ErrorBody.MessageText := '';
  ErrorBody.RefId := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'reason', True, ErrorBody.Reason) And
      ReadString(Obj, 'message', True, ErrorBody.MessageText) And ReadString(Obj, 'ref', True, ErrorBody.RefId);
  Finally
    Data.Free;
  End;
End;

Procedure ApplyTextLimit(Var Message: TMonitorMessage; Obj: TJSONObject);
Var
  Text: String;
Begin
  If (Message.Kind <> mmkSend) And (Message.Kind <> mmkSteer) Then
    Exit;
  If Not ReadString(Obj, 'text', False, Text) Then
    Exit;
  If Length(Text) <= MonitorMaxSendChars Then
    Exit;
  Message.Kind := mmkError;
  Message.TypeName := 'error';
  Message.Reason := MonitorPayloadTooLargeReason;
  Message.ChangesState := False;
  Message.WireJson := EncodeMonitorError(Message.Id, MonitorPayloadTooLargeReason, MonitorPayloadTooLargeMessage, Message.Id);
End;

Function TryDecodeMonitorEnvelope(Const Json: String; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Payload: TJSONObject;
  TypeName, Id: String;
Begin
  Result := False;
  ErrorText := '';
  Message.Version := 0;
  Message.Id := '';
  Message.Kind := mmkUnknown;
  Message.TypeName := '';
  Message.PayloadJson := '';
  Message.Reason := '';
  Message.ChangesState := False;
  Message.WireJson := '';
  If Length(Json) > MonitorMaxPayloadBytes Then
    Begin
      ErrorText := 'Monitor message exceeds the frame cap.';
      Exit;
    End;
  Data := Nil;
  Try
    Try
      {$IFDEF MONITOR_COUNT_PARSES}
      MonitorNoteJsonParse;
      {$ENDIF}
      Data := GetJSON(Json);
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'A monitor message must be a JSON object.';
        Exit;
      End;
    Root := TJSONObject(Data);
    { Only the current catalogue is supported. }
    If Root.Get('v', 0) <> MonitorCatalogueVersion Then
      Begin
        ErrorText := 'Unsupported catalogue version.';
        Exit;
      End;
    Id := Root.Get('id', '');
    TypeName := Root.Get('type', '');
    If Not MonitorMessageIdIsSafe(Id) Then
      Begin
        ErrorText := 'Message id is not valid.';
        Exit;
      End;
    If Not (Root.Find('payload') Is TJSONObject) Then
      Begin
        ErrorText := 'Message payload must be an object.';
        Exit;
      End;
    Payload := TJSONObject(Root.Find('payload'));
    Message.Version := MonitorCatalogueVersion;
    Message.Id := Id;
    Message.TypeName := TypeName;
    Message.PayloadJson.Parsed := TMonitorPayloadOwner.Create(TJSONObject(Root.Extract('payload')));
    Message.PayloadJson.ObjectValue := Payload;
    Message.Kind := MonitorMessageKindFromName(TypeName);
    If Message.Kind = mmkUnknown Then
      Begin
        Message.Kind := mmkError;
        Message.Reason := MonitorUnknownTypeReason;
        Message.ChangesState := False;
        Message.WireJson := MonitorUnknownTypeError(Id, TypeName);
      End
    Else
      Begin
        Message.Reason := Payload.Get('reason', '');
        Message.ChangesState := True;
        Message.WireJson := Json;
        ApplyTextLimit(Message, Payload);
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function MonitorHostIdIsValid(Const HostId: String): Boolean;
Var
  Index: Integer;
  C: Char;
Begin
  Result := Length(HostId) = 32;
  If Not Result Then
    Exit;
  For Index := 1 To 32 Do
    Begin
      C := HostId[Index];
      If Not (((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'f'))) Then
        Exit(False);
    End;
End;

End.
