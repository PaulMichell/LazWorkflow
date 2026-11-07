Unit AssistantMonitorCodec;

{ Monitor catalogue version 2. Wire names are snake case. (c) 2026 Michell Computing.

  Limits live here, not in a later form. Unknown types become error / unknown_type
  and do not change session state. Observer records are mapped, not copied into a
  second view model.

  JSON is fpjson and jsonparser. Message ids use TaskIdIsSafe. Mode strings are
  AssistantModeToStr. Image bytes use the frames unit's FCL base64 helpers.
  Frame length stays in AssistantMonitorFrames (htonl / ntohl).

  Size note: exceeds the 1000 line preference. What remains is the message types,
  the envelope framing, and the stable public names. Commands are
  AssistantMonitorCommands. State codecs are AssistantMonitorState. Image and bulk
  packing are AssistantMonitorImages. Tested catalogue 2 content tables are
  AssistantMonitorContent. The public names stay here so existing tests do not change.
  Reviewed 2026-11-07: no socket, TLS, or form code in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantConversation, AssistantSessionObserve;

Const
  MonitorCatalogueVersion = 2;
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
    mmkSnapshot,
    mmkRefresh,
    mmkTranscript,
    mmkTurn,
    mmkTurnData,
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
    mmkPatch,
    mmkCatchup,
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
    { Optional on catalogue 2. 32 lowercase hex. The phone's hostFingerprint. }
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

  { One committed live change. Part and PartCount are 1 until the body exceeds the frame cap. }
  TMonitorPatch = Record
    Epoch: String;
    Cursor: Int64;
    TurnIndex: Integer;
    TurnId: String;
    Blocks: Array Of TAssistantMonitorBlock;
    { Parallel to Blocks. -1 means the body replaces. Zero or more means the body is a suffix at that UTF-8 offset. }
    AppendOffsets: Array Of Integer;
    Busy: Boolean;
    Sending: Boolean;
    PlanRunning: Boolean;
    Phase: String;
    CanSend: Boolean;
    CanSteer: Boolean;
    CanStop: Boolean;
    ElapsedMs: Integer;
    Part: Integer;
    PartCount: Integer;
    { Absent on a ring record written before the status bar travelled with the patch. }
    HasView: Boolean;
    Model: String;
    SignedIn: Boolean;
    StatusText: String;
  End;
  TMonitorPatchArray = Array Of TMonitorPatch;

  TMonitorCatchupMode = (
    mcmUnknown,
    mcmSnapshot,
    mcmEvents
  );

  { One resume result. Snapshot nests the existing snapshot object. Events lists patch payloads. }
  TMonitorCatchup = Record
    Mode: TMonitorCatchupMode;
    Epoch: String;
    Cursor: Int64;
    ConversationId: String;
    ProjectRoot: String;
    Title: String;
    Snapshot: TMonitorSnapshot;
    HasSnapshot: Boolean;
    Patches: TMonitorPatchArray;
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
Function EncodeMonitorHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Function DecodeMonitorHello(Const PayloadJson: TMonitorPayload; Out Hello: TMonitorHello): Boolean;
Function EncodeMonitorPair(Const Id, Code, Fingerprint: String): String;
Function DecodeMonitorPair(Const PayloadJson: TMonitorPayload; Out Pair: TMonitorPair): Boolean;
Function EncodeMonitorPairOk(Const Id, ClientId, SessionToken: String): String;
Function DecodeMonitorPairOk(Const PayloadJson: TMonitorPayload; Out PairOk: TMonitorPairOk): Boolean;
Function EncodeMonitorHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Function DecodeMonitorHelloOk(Const PayloadJson: TMonitorPayload; Out HelloOk: TMonitorHelloOk): Boolean;
{ 32 lowercase hex digits. Empty is not valid. }
Function MonitorHostIdIsValid(Const HostId: String): Boolean;
Function EncodeMonitorAuth(Const Id, ClientId, Hmac: String): String;
Function DecodeMonitorAuth(Const PayloadJson: TMonitorPayload; Out Auth: TMonitorAuth): Boolean;
Function EncodeMonitorRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Function DecodeMonitorRejected(Const PayloadJson: TMonitorPayload; Out Rejected: TMonitorRejected): Boolean;
Function EncodeMonitorBye(Const Id, Reason: String): String;
Function DecodeMonitorBye(Const PayloadJson: TMonitorPayload; Out Bye: TMonitorBye): Boolean;

Function TryEncodeMonitorSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function TryEncodeMonitorSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function DecodeMonitorText(Const PayloadJson: TMonitorPayload; Out Text: String): Boolean;
Function EncodeMonitorEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Function EncodeMonitorSetMode(Const Id, Mode: String): String;
Function DecodeMonitorSetMode(Const PayloadJson: TMonitorPayload; Out Mode: String): Boolean;
Function EncodeMonitorMode(Const Id, Mode: String; Locked: Boolean): String;
Function DecodeMonitorMode(Const PayloadJson: TMonitorPayload; Out ModeMessage: TMonitorModeMessage): Boolean;
Function EncodeMonitorTurnRequest(Const Id: String; TurnIndex: Integer): String;
Function DecodeMonitorTurnRequest(Const PayloadJson: TMonitorPayload; Out TurnIndex: Integer): Boolean;
Function EncodeMonitorTarget(Const Id, Kind, Display, Root: String): String;
Function DecodeMonitorTarget(Const PayloadJson: TMonitorPayload; Out Target: TMonitorTargetMessage): Boolean;
Function EncodeMonitorTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
Function DecodeMonitorTargets(Const PayloadJson: TMonitorPayload; Out Targets: TMonitorTargetsMessage): Boolean;
Function EncodeMonitorConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
Function DecodeMonitorConversations(Const PayloadJson: TMonitorPayload; Out Conversations: TMonitorConversationsMessage): Boolean;
Function EncodeMonitorSelectConversation(Const Id, ArchiveId: String): String;
Function DecodeMonitorSelectConversation(Const PayloadJson: TMonitorPayload; Out ArchiveId: String): Boolean;
Function EncodeMonitorModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorModels(Const PayloadJson: TMonitorPayload; Out Models: TMonitorModelsMessage): Boolean;
Function EncodeMonitorSetModel(Const Id, ModelId: String): String;
Function DecodeMonitorSetModel(Const PayloadJson: TMonitorPayload; Out ModelId: String): Boolean;
Function EncodeMonitorReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorReasoning(Const PayloadJson: TMonitorPayload; Out Reasoning: TMonitorReasoningMessage): Boolean;
Function EncodeMonitorSetReasoning(Const Id, Level: String): String;
Function DecodeMonitorSetReasoning(Const PayloadJson: TMonitorPayload; Out Level: String): Boolean;
Function EncodeMonitorPermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorPermissions(Const PayloadJson: TMonitorPayload; Out Permissions: TMonitorPermissionsMessage): Boolean;
Function EncodeMonitorSetPermissions(Const Id, Approval: String): String;
Function DecodeMonitorSetPermissions(Const PayloadJson: TMonitorPayload; Out Approval: String): Boolean;
Function EncodeMonitorPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Function DecodeMonitorPath(Const PayloadJson: TMonitorPayload; Out Path: String): Boolean;
Function EncodeMonitorNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Function DecodeMonitorNewPlan(Const PayloadJson: TMonitorPayload; Out Plan: TMonitorPathMessage): Boolean;
Function EncodeMonitorWorkOnPlan(Const Id: String; Index: Integer): String;
Function DecodeMonitorWorkOnPlan(Const PayloadJson: TMonitorPayload; Out Index: Integer): Boolean;
Function EncodeMonitorTaskCommand(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String): String;
Function DecodeMonitorTaskCommand(Const PayloadJson: TMonitorPayload; Out Command: TMonitorTaskCommand): Boolean;
Function EncodeMonitorInsertResult(Const Id, Text: String): String;
Function EncodeMonitorTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Function DecodeMonitorTicks(Const PayloadJson: TMonitorPayload; Out Ticks: TMonitorTicks): Boolean;

Function EncodeMonitorApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Function DecodeMonitorApprovalRequested(Const PayloadJson: TMonitorPayload; Out Notice: TAssistantApprovalNotice): Boolean;
Function EncodeMonitorApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Function DecodeMonitorApprovalDecision(Const PayloadJson: TMonitorPayload; Out Decision: TMonitorApprovalDecision): Boolean;
Function EncodeMonitorApprovalClosed(Const Id, ToolId, Reason: String): String;
Function DecodeMonitorApprovalClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorApprovalClosed): Boolean;

Function MonitorStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Function TryMonitorStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Function DecodeMonitorTurnData(Const PayloadJson: TMonitorPayload; Out Turn: TAssistantMonitorTurn): Boolean;
Function EncodeMonitorPlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings = Nil; Captions: TStrings = Nil;
  Const Epoch: String = ''; Cursor: Int64 = 0; Const Body: String = ''; Complete: Boolean = False): String;
{ One plan frame when it fits. Otherwise chunk frames of the same item, for the plan lane. }
Function PackMonitorPlanFrames(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings; Const Body: String; Complete: Boolean;
  Out Frames: TStringArray): Boolean;
Function DecodeMonitorPlan(Const PayloadJson: TMonitorPayload; Out Path, Title: String; Out Running: Boolean;
  Out Rows: TMonitorSnapshot): Boolean;
Function EncodeMonitorTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Function EncodeMonitorSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Function DecodeMonitorSnapshot(Const PayloadJson: TMonitorPayload; Out Snapshot: TMonitorSnapshot): Boolean;
Function DecodeMonitorTranscript(Const PayloadJson: TMonitorPayload; Out Transcript: TMonitorTranscript): Boolean;

Function EncodeMonitorResume(Const Id, Epoch: String; Cursor: Int64): String;
Function DecodeMonitorResume(Const PayloadJson: TMonitorPayload; Out ResumeMsg: TMonitorResume): Boolean;
Function EncodeMonitorCommandState(Const Id, Ref, State, Reason: String; Const DoneText: String = ''): String;
Function EncodeMonitorCommandStates(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;
Function EncodeMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): String;
{ Same cursor on every part. Empty when a single block cannot be cut down to the cap. }
Function PackMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Function DecodeMonitorPatch(Const PayloadJson: TMonitorPayload; Out Patch: TMonitorPatch): Boolean;
{ FirstPatch copies every current block. Later patches keep only a new block, or one whose
  body, title, running flag, or ok flag changed. Duration and elapsed time do not count. }
Function SelectDirtyMonitorBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;
{ False when any part of that cursor is missing, duplicated, or a different epoch. }
Function TryAssembleMonitorPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Function EncodeMonitorCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Function DecodeMonitorCatchup(Const PayloadJson: TMonitorPayload; Out Catchup: TMonitorCatchup): Boolean;
{ One snapshot catchup. The cursor is the snapshot cursor, not the client's discarded cursor. }
Function EncodeResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Function EncodeMonitorConversationClosed(Const Id, Epoch: String; Cursor: Int64; Const ConversationId, Title: String): String;
Function DecodeMonitorConversationClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorConversationClosed): Boolean;

{ True when the host must send image_unavailable and keep the socket open. }
Function MonitorImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Function TryBuildMonitorImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Function DecodeMonitorImageData(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Function EncodeMonitorImageUnavailable(Const Id, ImageId, Reason: String): String;
Function DecodeMonitorImageUnavailable(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageUnavailable): Boolean;
Function EncodeMonitorImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Function DecodeMonitorImageGet(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageGet): Boolean;
{ Messages are image_data envelopes, or empty when UnavailableReason is set. Does not close a socket. }
Function TryEncodeMonitorImageData(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Missing, Refused: Boolean; Out Messages: TStringArray; Out UnavailableReason: String): Boolean;
{ One image_data item, split into outbox chunk frames when it does not fit in 32 KiB. }
Function TryPackMonitorImage(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer; Const Bytes: TBytes;
  Missing, Refused: Boolean; Out Frames: TStringArray; Out UnavailableReason: String): Boolean;
{ Wraps PayloadJson as type ItemType. A frame over the outbox chunk size becomes chunk frames. }
Function PackMonitorBulkItem(Const ItemId, ItemType, PayloadJson: String; Out Frames: TStringArray): Boolean;

Implementation

Uses
  jsonparser, GrokOAuth, AssistantTasks, AssistantMonitorFrames, AssistantMonitorCommands, AssistantMonitorState,
  AssistantMonitorContent, AssistantMonitorImages;

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
    'snapshot',
    'refresh',
    'transcript',
    'turn',
    'turn_data',
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
    'patch',
    'catchup',
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
  MonitorSortedKinds: Array[0..57] Of TMonitorMessageKind = (
    mmkApprovalClosed,
    mmkApprovalDecision,
    mmkApprovalRequested,
    mmkAuth,
    mmkBye,
    mmkCatchup,
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
    mmkPatch,
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
    mmkSnapshot,
    mmkSnapshotPage,
    mmkStatus,
    mmkSteer,
    mmkStop,
    mmkStopPlan,
    mmkTarget,
    mmkTargets,
    mmkTasks,
    mmkTranscript,
    mmkTurn,
    mmkTurnData,
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
    { Catalogue 2 stays. Catalogue 3 is the event resume. Catalogue 1 is rejected. }
    If (Root.Get('v', 0) <> MonitorCatalogueVersion) And (Root.Get('v', 0) <> 3) Then
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

Function EncodeMonitorHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Begin
  Result := EncodeCommandHello(Id, ClientName, ClientVersion, ClientId);
End;

Function DecodeMonitorHello(Const PayloadJson: TMonitorPayload; Out Hello: TMonitorHello): Boolean;
Begin
  Result := DecodeCommandHello(PayloadJson, Hello);
End;

Function EncodeMonitorPair(Const Id, Code, Fingerprint: String): String;
Begin
  Result := EncodeCommandPair(Id, Code, Fingerprint);
End;

Function DecodeMonitorPair(Const PayloadJson: TMonitorPayload; Out Pair: TMonitorPair): Boolean;
Begin
  Result := DecodeCommandPair(PayloadJson, Pair);
End;

Function EncodeMonitorPairOk(Const Id, ClientId, SessionToken: String): String;
Begin
  Result := EncodeCommandPairOk(Id, ClientId, SessionToken);
End;

Function DecodeMonitorPairOk(Const PayloadJson: TMonitorPayload; Out PairOk: TMonitorPairOk): Boolean;
Begin
  Result := DecodeCommandPairOk(PayloadJson, PairOk);
End;

Function EncodeMonitorHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Begin
  Result := EncodeCommandHelloOk(Id, HelloOk);
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

Function DecodeMonitorHelloOk(Const PayloadJson: TMonitorPayload; Out HelloOk: TMonitorHelloOk): Boolean;
Begin
  Result := DecodeCommandHelloOk(PayloadJson, HelloOk);
End;

Function EncodeMonitorAuth(Const Id, ClientId, Hmac: String): String;
Begin
  Result := EncodeCommandAuth(Id, ClientId, Hmac);
End;

Function DecodeMonitorAuth(Const PayloadJson: TMonitorPayload; Out Auth: TMonitorAuth): Boolean;
Begin
  Result := DecodeCommandAuth(PayloadJson, Auth);
End;

Function EncodeMonitorRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Begin
  Result := EncodeCommandRejected(Id, Reason, HostVersion, ClientVersion);
End;

Function DecodeMonitorRejected(Const PayloadJson: TMonitorPayload; Out Rejected: TMonitorRejected): Boolean;
Begin
  Result := DecodeCommandRejected(PayloadJson, Rejected);
End;

Function EncodeMonitorBye(Const Id, Reason: String): String;
Begin
  Result := EncodeCommandBye(Id, Reason);
End;

Function DecodeMonitorBye(Const PayloadJson: TMonitorPayload; Out Bye: TMonitorBye): Boolean;
Begin
  Result := DecodeCommandBye(PayloadJson, Bye);
End;

Function TryEncodeMonitorSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeCommandSend(Id, Text, Json, ErrorJson);
End;

Function TryEncodeMonitorSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeCommandSteer(Id, Text, Json, ErrorJson);
End;

Function DecodeMonitorText(Const PayloadJson: TMonitorPayload; Out Text: String): Boolean;
Begin
  Result := DecodeCommandText(PayloadJson, Text);
End;

Function EncodeMonitorEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Begin
  Result := EncodeCommandEmpty(Kind, Id);
End;

Function EncodeMonitorSetMode(Const Id, Mode: String): String;
Begin
  Result := EncodeCommandSetMode(Id, Mode);
End;

Function DecodeMonitorSetMode(Const PayloadJson: TMonitorPayload; Out Mode: String): Boolean;
Begin
  Result := DecodeCommandSetMode(PayloadJson, Mode);
End;

Function EncodeMonitorMode(Const Id, Mode: String; Locked: Boolean): String;
Begin
  Result := EncodeCommandMode(Id, Mode, Locked);
End;

Function DecodeMonitorMode(Const PayloadJson: TMonitorPayload; Out ModeMessage: TMonitorModeMessage): Boolean;
Begin
  Result := DecodeCommandMode(PayloadJson, ModeMessage);
End;

Function EncodeMonitorTurnRequest(Const Id: String; TurnIndex: Integer): String;
Begin
  Result := EncodeCommandTurnRequest(Id, TurnIndex);
End;

Function DecodeMonitorTurnRequest(Const PayloadJson: TMonitorPayload; Out TurnIndex: Integer): Boolean;
Begin
  Result := DecodeCommandTurnRequest(PayloadJson, TurnIndex);
End;


Function EncodeMonitorTarget(Const Id, Kind, Display, Root: String): String;
Begin
  Result := EncodeStateTarget(Id, Kind, Display, Root);
End;

Function DecodeMonitorTarget(Const PayloadJson: TMonitorPayload; Out Target: TMonitorTargetMessage): Boolean;
Begin
  Result := DecodeStateTarget(PayloadJson, Target);
End;

Function EncodeMonitorTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
Begin
  Result := EncodeStateTargets(Id, Current, Paths, Captions);
End;

Function DecodeMonitorTargets(Const PayloadJson: TMonitorPayload; Out Targets: TMonitorTargetsMessage): Boolean;
Begin
  Result := DecodeStateTargets(PayloadJson, Targets);
End;

Function EncodeMonitorConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
Begin
  Result := EncodeStateConversations(Id, Current, Ids, Titles, Truncated);
End;

Function DecodeMonitorConversations(Const PayloadJson: TMonitorPayload; Out Conversations: TMonitorConversationsMessage): Boolean;
Begin
  Result := DecodeStateConversations(PayloadJson, Conversations);
End;

Function EncodeMonitorSelectConversation(Const Id, ArchiveId: String): String;
Begin
  Result := EncodeCommandSelectConversation(Id, ArchiveId);
End;

Function DecodeMonitorSelectConversation(Const PayloadJson: TMonitorPayload; Out ArchiveId: String): Boolean;
Begin
  Result := DecodeCommandSelectConversation(PayloadJson, ArchiveId);
End;

Function EncodeMonitorModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeStateModels(Id, Current, Backend, Note, Ids, Captions);
End;

Function DecodeMonitorModels(Const PayloadJson: TMonitorPayload; Out Models: TMonitorModelsMessage): Boolean;
Begin
  Result := DecodeStateModels(PayloadJson, Models);
End;

Function EncodeMonitorSetModel(Const Id, ModelId: String): String;
Begin
  Result := EncodeCommandSetModel(Id, ModelId);
End;

Function DecodeMonitorSetModel(Const PayloadJson: TMonitorPayload; Out ModelId: String): Boolean;
Begin
  Result := DecodeCommandSetModel(PayloadJson, ModelId);
End;

Function EncodeMonitorReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeStateReasoning(Id, Current, Note, Ids, Captions);
End;

Function DecodeMonitorReasoning(Const PayloadJson: TMonitorPayload; Out Reasoning: TMonitorReasoningMessage): Boolean;
Begin
  Result := DecodeStateReasoning(PayloadJson, Reasoning);
End;

Function EncodeMonitorSetReasoning(Const Id, Level: String): String;
Begin
  Result := EncodeCommandSetReasoning(Id, Level);
End;

Function DecodeMonitorSetReasoning(Const PayloadJson: TMonitorPayload; Out Level: String): Boolean;
Begin
  Result := DecodeCommandSetReasoning(PayloadJson, Level);
End;

Function EncodeMonitorPermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeStatePermissions(Id, Current, Backend, Note, Ids, Captions);
End;

Function DecodeMonitorPermissions(Const PayloadJson: TMonitorPayload; Out Permissions: TMonitorPermissionsMessage): Boolean;
Begin
  Result := DecodeStatePermissions(PayloadJson, Permissions);
End;

Function EncodeMonitorSetPermissions(Const Id, Approval: String): String;
Begin
  Result := EncodeCommandSetPermissions(Id, Approval);
End;

Function DecodeMonitorSetPermissions(Const PayloadJson: TMonitorPayload; Out Approval: String): Boolean;
Begin
  Result := DecodeCommandSetPermissions(PayloadJson, Approval);
End;

Function EncodeMonitorPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Begin
  Result := EncodeCommandPath(Kind, Id, Path);
End;

Function DecodeMonitorPath(Const PayloadJson: TMonitorPayload; Out Path: String): Boolean;
Begin
  Result := DecodeCommandPath(PayloadJson, Path);
End;

Function EncodeMonitorNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Begin
  Result := EncodeCommandNewPlan(Id, Title, HasTitle);
End;

Function DecodeMonitorNewPlan(Const PayloadJson: TMonitorPayload; Out Plan: TMonitorPathMessage): Boolean;
Begin
  Result := DecodeCommandNewPlan(PayloadJson, Plan);
End;

Function EncodeMonitorWorkOnPlan(Const Id: String; Index: Integer): String;
Begin
  Result := EncodeCommandWorkOnPlan(Id, Index);
End;

Function DecodeMonitorWorkOnPlan(Const PayloadJson: TMonitorPayload; Out Index: Integer): Boolean;
Begin
  Result := DecodeCommandWorkOnPlan(PayloadJson, Index);
End;

Function EncodeMonitorTaskCommand(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String): String;
Begin
  Result := EncodeCommandTask(Kind, Id, TaskId, Note);
End;

Function DecodeMonitorTaskCommand(Const PayloadJson: TMonitorPayload; Out Command: TMonitorTaskCommand): Boolean;
Begin
  Result := DecodeCommandTask(PayloadJson, Command);
End;

Function EncodeMonitorInsertResult(Const Id, Text: String): String;
Begin
  Result := EncodeCommandInsertResult(Id, Text);
End;

Function EncodeMonitorTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Begin
  Result := EncodeCommandTicks(Kind, Id, Ticks);
End;

Function DecodeMonitorTicks(Const PayloadJson: TMonitorPayload; Out Ticks: TMonitorTicks): Boolean;
Begin
  Result := DecodeCommandTicks(PayloadJson, Ticks);
End;

Function EncodeMonitorApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Begin
  Result := EncodeStateApprovalRequested(Id, Notice);
End;

Function DecodeMonitorApprovalRequested(Const PayloadJson: TMonitorPayload; Out Notice: TAssistantApprovalNotice): Boolean;
Begin
  Result := DecodeStateApprovalRequested(PayloadJson, Notice);
End;

Function EncodeMonitorApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Begin
  Result := EncodeStateApprovalDecision(Id, ToolId, Allow);
End;

Function DecodeMonitorApprovalDecision(Const PayloadJson: TMonitorPayload; Out Decision: TMonitorApprovalDecision): Boolean;
Begin
  Result := DecodeStateApprovalDecision(PayloadJson, Decision);
End;

Function EncodeMonitorApprovalClosed(Const Id, ToolId, Reason: String): String;
Begin
  Result := EncodeStateApprovalClosed(Id, ToolId, Reason);
End;

Function DecodeMonitorApprovalClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorApprovalClosed): Boolean;
Begin
  Result := DecodeStateApprovalClosed(PayloadJson, Closed);
End;

Function MonitorStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Begin
  Result := StateStatusToJson(View);
End;

Function TryMonitorStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Begin
  Result := TryStateStatusFromJson(Obj, View);
End;

Function DecodeMonitorTurnData(Const PayloadJson: TMonitorPayload; Out Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := DecodeContentTurnData(PayloadJson, Turn);
End;

Function EncodeMonitorPlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings = Nil; Captions: TStrings = Nil;
  Const Epoch: String = ''; Cursor: Int64 = 0; Const Body: String = ''; Complete: Boolean = False): String;
Begin
  Result := EncodeStatePlan(Id, Path, Title, Running, Rows, Paths, Captions, Epoch, Cursor, Body, Complete);
End;

Function PackMonitorPlanFrames(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings; Const Body: String; Complete: Boolean;
  Out Frames: TStringArray): Boolean;
Begin
  Result := PackStatePlanFrames(Id, Path, Title, Running, Rows, Paths, Captions, Body, Complete, Frames);
End;

Function DecodeMonitorPlan(Const PayloadJson: TMonitorPayload; Out Path, Title: String; Out Running: Boolean;
  Out Rows: TMonitorSnapshot): Boolean;
Begin
  Result := DecodeStatePlan(PayloadJson, Path, Title, Running, Rows);
End;

Function EncodeMonitorTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Begin
  Result := EncodeStateTasks(Id, Rows);
End;

Function EncodeMonitorSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Begin
  Result := EncodeContentSnapshot(Id, Snapshot);
End;

Function DecodeMonitorSnapshot(Const PayloadJson: TMonitorPayload; Out Snapshot: TMonitorSnapshot): Boolean;
Begin
  Result := DecodeContentSnapshot(PayloadJson, Snapshot);
End;

Function DecodeMonitorTranscript(Const PayloadJson: TMonitorPayload; Out Transcript: TMonitorTranscript): Boolean;
Begin
  Result := DecodeContentTranscript(PayloadJson, Transcript);
End;

Function EncodeMonitorResume(Const Id, Epoch: String; Cursor: Int64): String;
Begin
  Result := EncodeCommandResume(Id, Epoch, Cursor);
End;

Function DecodeMonitorResume(Const PayloadJson: TMonitorPayload; Out ResumeMsg: TMonitorResume): Boolean;
Begin
  Result := DecodeCommandResume(PayloadJson, ResumeMsg);
End;

Function EncodeMonitorCommandState(Const Id, Ref, State, Reason: String; Const DoneText: String = ''): String;
Begin
  Result := EncodeCommandStateFrame(Id, Ref, State, Reason, DoneText);
End;

Function EncodeMonitorCommandStates(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;
Begin
  Result := EncodeCommandStateFrames(Id, Replies);
End;

Function EncodeMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): String;
Begin
  Result := EncodeContentPatch(Id, Patch);
End;

Function PackMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Begin
  Result := PackContentPatch(Id, Patch);
End;

Function DecodeMonitorPatch(Const PayloadJson: TMonitorPayload; Out Patch: TMonitorPatch): Boolean;
Begin
  Result := DecodeContentPatch(PayloadJson, Patch);
End;

Function SelectDirtyMonitorBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;
Begin
  Result := SelectContentDirtyBlocks(Previous, Current, FirstPatch);
End;

Function TryAssembleMonitorPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Begin
  Result := TryAssembleContentPatch(Messages, Patch);
End;

Function EncodeMonitorCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Begin
  Result := EncodeContentCatchup(Id, Catchup);
End;

Function DecodeMonitorCatchup(Const PayloadJson: TMonitorPayload; Out Catchup: TMonitorCatchup): Boolean;
Begin
  Result := DecodeContentCatchup(PayloadJson, Catchup);
End;

Function EncodeResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Begin
  Result := EncodeContentResumeSnapshot(RefId, Cursor, Epoch, ConversationId, ProjectRoot, Title, Snapshot);
End;

Function EncodeMonitorConversationClosed(Const Id, Epoch: String; Cursor: Int64; Const ConversationId, Title: String): String;
Begin
  Result := EncodeStateConversationClosed(Id, Epoch, Cursor, ConversationId, Title);
End;

Function DecodeMonitorConversationClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorConversationClosed): Boolean;
Begin
  Result := DecodeStateConversationClosed(PayloadJson, Closed);
End;

Function MonitorImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Begin
  Result := ImageFetchBlocked(Missing, Refused, DecodedBytes, Reason);
End;

Function TryBuildMonitorImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Begin
  Result := TryBuildImageParts(ImageId, Mime, Width, Height, Revision, Bytes, Parts, Reason);
End;

Function DecodeMonitorImageData(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Begin
  Result := DecodeImageData(PayloadJson, Image, DecodedBytes);
End;

Function EncodeMonitorImageUnavailable(Const Id, ImageId, Reason: String): String;
Begin
  Result := EncodeImageUnavailable(Id, ImageId, Reason);
End;

Function DecodeMonitorImageUnavailable(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageUnavailable): Boolean;
Begin
  Result := DecodeImageUnavailable(PayloadJson, Image);
End;

Function EncodeMonitorImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Begin
  Result := EncodeImageGet(Id, TurnIndex, ImageId);
End;

Function DecodeMonitorImageGet(Const PayloadJson: TMonitorPayload; Out Image: TMonitorImageGet): Boolean;
Begin
  Result := DecodeImageGet(PayloadJson, Image);
End;

Function TryEncodeMonitorImageData(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Missing, Refused: Boolean; Out Messages: TStringArray; Out UnavailableReason: String): Boolean;
Begin
  Result := TryEncodeImageData(Id, ImageId, Mime, Width, Height, Revision, Bytes, Missing, Refused, Messages,
    UnavailableReason);
End;

Function TryPackMonitorImage(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer; Const Bytes: TBytes;
  Missing, Refused: Boolean; Out Frames: TStringArray; Out UnavailableReason: String): Boolean;
Begin
  Result := TryPackImage(Id, ImageId, Mime, Width, Height, Revision, Bytes, Missing, Refused, Frames, UnavailableReason);
End;

Function PackMonitorBulkItem(Const ItemId, ItemType, PayloadJson: String; Out Frames: TStringArray): Boolean;
Begin
  Result := PackImageBulkItem(ItemId, ItemType, PayloadJson, Frames);
End;

End.
