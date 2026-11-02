Unit AssistantMonitorCodec;

{ Monitor catalogue version 2. Wire names are snake case. (c) 2026 Michell Computing.

  Limits live here, not in a later form. Unknown types become error / unknown_type
  and do not change session state. Observer records are mapped, not copied into a
  second view model.

  JSON is fpjson and jsonparser. Message ids use TaskIdIsSafe. Mode strings are
  AssistantModeToStr. Image bytes use the frames unit's FCL base64 helpers.
  Frame length stays in AssistantMonitorFrames (htonl / ntohl).

  Size note: exceeds the 1000 line preference. The catalogue is one table of
  message types, payload fields, and limits. Splitting it would hide a type.
  Reviewed 2026-10-30: snapshot pages and image chunks stay in this table. The old snapshot,
  transcript, and turn_data encoders remain so a catchup can still embed a snapshot object.
  Chunk packing stays one pass: a resume publishes those pages on the IDE thread.
  usage_caption and usage_hint are optional status fields, omitted when empty.
  No socket, TLS, or form code in this unit.
  v2 adds resume, patch, catchup, and conversation_closed to that same table. }

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
  MonitorMaxBodyPartBytes = 200000;
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

  TMonitorMessage = Record
    Version: Integer;
    Id: String;
    Kind: TMonitorMessageKind;
    TypeName: String;
    PayloadJson: String;
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
    PlanRows: Array Of TAssistantMonitorPlanRow;
    TaskRows: Array Of TAssistantMonitorTaskRow;
    Approval: TAssistantApprovalNotice;
  End;

  { Client resume. Not a user command. Cursor 0 means nothing has been applied.
    Commands lists outbox ids whose outcome the phone does not know. }
  TMonitorResume = Record
    Epoch: String;
    Cursor: Int64;
    Commands: TStringArray;
  End;

  TMonitorCommandStateReply = Record
    Ref: String;
    State: String;
    Reason: String;
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
Function MonitorMessageKindFromName(Const Name: String): TMonitorMessageKind;
Function MonitorMessageIdIsSafe(Const Id: String): Boolean;
Function MonitorRejectedReasonIsKnown(Const Reason: String): Boolean;
Function MonitorApprovalCloseReasonIsKnown(Const Reason: String): Boolean;
Function MonitorImageUnavailableReasonIsKnown(Const Reason: String): Boolean;
Function MonitorModeName(Mode: TAssistantMode): String;
Function MonitorModeIsKnown(Const ModeText: String): Boolean;

{ Empty when the id is unsafe or the object would exceed the frame cap. }
Function EncodeMonitorEnvelope(Kind: TMonitorMessageKind; Const Id: String; Const Payload: TJSONObject): String;
Function TryDecodeMonitorEnvelope(Const Json: String; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
Function MonitorUnknownTypeError(Const RefId, TypeName: String): String;
Function EncodeMonitorError(Const Id, Reason, MessageText, RefId: String): String;
Function DecodeMonitorError(Const PayloadJson: String; Out ErrorBody: TMonitorErrorBody): Boolean;

{ ClientId empty is the first hello. A non-empty id is the reconnect shape. }
Function EncodeMonitorHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Function DecodeMonitorHello(Const PayloadJson: String; Out Hello: TMonitorHello): Boolean;
Function EncodeMonitorPair(Const Id, Code, Fingerprint: String): String;
Function DecodeMonitorPair(Const PayloadJson: String; Out Pair: TMonitorPair): Boolean;
Function EncodeMonitorPairOk(Const Id, ClientId, SessionToken: String): String;
Function DecodeMonitorPairOk(Const PayloadJson: String; Out PairOk: TMonitorPairOk): Boolean;
Function EncodeMonitorHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Function DecodeMonitorHelloOk(Const PayloadJson: String; Out HelloOk: TMonitorHelloOk): Boolean;
{ 32 lowercase hex digits. Empty is not valid. }
Function MonitorHostIdIsValid(Const HostId: String): Boolean;
Function EncodeMonitorAuth(Const Id, ClientId, Hmac: String): String;
Function DecodeMonitorAuth(Const PayloadJson: String; Out Auth: TMonitorAuth): Boolean;
Function EncodeMonitorRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Function DecodeMonitorRejected(Const PayloadJson: String; Out Rejected: TMonitorRejected): Boolean;
Function EncodeMonitorBye(Const Id, Reason: String): String;
Function DecodeMonitorBye(Const PayloadJson: String; Out Bye: TMonitorBye): Boolean;

Function TryEncodeMonitorSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function TryEncodeMonitorSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function DecodeMonitorText(Const PayloadJson: String; Out Text: String): Boolean;
Function EncodeMonitorEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Function EncodeMonitorSetMode(Const Id, Mode: String): String;
Function DecodeMonitorSetMode(Const PayloadJson: String; Out Mode: String): Boolean;
Function EncodeMonitorMode(Const Id, Mode: String; Locked: Boolean): String;
Function DecodeMonitorMode(Const PayloadJson: String; Out ModeMessage: TMonitorModeMessage): Boolean;
Function EncodeMonitorTurnRequest(Const Id: String; TurnIndex: Integer): String;
Function DecodeMonitorTurnRequest(Const PayloadJson: String; Out TurnIndex: Integer): Boolean;
Function EncodeMonitorTarget(Const Id, Kind, Display, Root: String): String;
Function DecodeMonitorTarget(Const PayloadJson: String; Out Target: TMonitorTargetMessage): Boolean;
Function EncodeMonitorTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
Function DecodeMonitorTargets(Const PayloadJson: String; Out Targets: TMonitorTargetsMessage): Boolean;
Function EncodeMonitorConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
Function DecodeMonitorConversations(Const PayloadJson: String; Out Conversations: TMonitorConversationsMessage): Boolean;
Function EncodeMonitorSelectConversation(Const Id, ArchiveId: String): String;
Function DecodeMonitorSelectConversation(Const PayloadJson: String; Out ArchiveId: String): Boolean;
Function EncodeMonitorModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorModels(Const PayloadJson: String; Out Models: TMonitorModelsMessage): Boolean;
Function EncodeMonitorSetModel(Const Id, ModelId: String): String;
Function DecodeMonitorSetModel(Const PayloadJson: String; Out ModelId: String): Boolean;
Function EncodeMonitorReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorReasoning(Const PayloadJson: String; Out Reasoning: TMonitorReasoningMessage): Boolean;
Function EncodeMonitorSetReasoning(Const Id, Level: String): String;
Function DecodeMonitorSetReasoning(Const PayloadJson: String; Out Level: String): Boolean;
Function EncodeMonitorPermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeMonitorPermissions(Const PayloadJson: String; Out Permissions: TMonitorPermissionsMessage): Boolean;
Function EncodeMonitorSetPermissions(Const Id, Approval: String): String;
Function DecodeMonitorSetPermissions(Const PayloadJson: String; Out Approval: String): Boolean;
Function EncodeMonitorPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Function DecodeMonitorPath(Const PayloadJson: String; Out Path: String): Boolean;
Function EncodeMonitorNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Function DecodeMonitorNewPlan(Const PayloadJson: String; Out Plan: TMonitorPathMessage): Boolean;
Function EncodeMonitorWorkOnPlan(Const Id: String; Index: Integer): String;
Function DecodeMonitorWorkOnPlan(Const PayloadJson: String; Out Index: Integer): Boolean;
Function EncodeMonitorTaskCommand(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String): String;
Function DecodeMonitorTaskCommand(Const PayloadJson: String; Out Command: TMonitorTaskCommand): Boolean;
Function EncodeMonitorInsertResult(Const Id, Text: String): String;
Function EncodeMonitorTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Function DecodeMonitorTicks(Const PayloadJson: String; Out Ticks: TMonitorTicks): Boolean;

Function EncodeMonitorApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Function DecodeMonitorApprovalRequested(Const PayloadJson: String; Out Notice: TAssistantApprovalNotice): Boolean;
Function EncodeMonitorApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Function DecodeMonitorApprovalDecision(Const PayloadJson: String; Out Decision: TMonitorApprovalDecision): Boolean;
Function EncodeMonitorApprovalClosed(Const Id, ToolId, Reason: String): String;
Function DecodeMonitorApprovalClosed(Const PayloadJson: String; Out Closed: TMonitorApprovalClosed): Boolean;

Function MonitorToolBodyForWire(Const Body: String; Out Truncated: Boolean): String;
Function SplitMonitorBody(Const Body: String; Revision: Integer): TMonitorBodyPartArray;
Function MonitorBlockToJson(Const Block: TAssistantMonitorBlock; Part, PartCount, Revision: Integer): TJSONObject;
Function TryMonitorBlockFromJson(Obj: TJSONObject; Out Block: TAssistantMonitorBlock; Out Truncated: Boolean): Boolean;
Function MonitorViewToJson(Const View: TAssistantMonitorView): TJSONObject;
Function TryMonitorViewFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Function MonitorStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Function TryMonitorStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Function MonitorTurnToJson(Const Turn: TAssistantMonitorTurn; IndexOnly: Boolean): TJSONObject;
Function TryMonitorTurnFromJson(Obj: TJSONObject; IndexOnly: Boolean; Out Turn: TAssistantMonitorTurn): Boolean;
Function EncodeMonitorTurnData(Const Id: String; Const Turn: TAssistantMonitorTurn): String;
Function DecodeMonitorTurnData(Const PayloadJson: String; Out Turn: TAssistantMonitorTurn): Boolean;
Function EncodeMonitorPlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings = Nil; Captions: TStrings = Nil;
  Const Epoch: String = ''; Cursor: Int64 = 0; Const Body: String = ''): String;
Function DecodeMonitorPlan(Const PayloadJson: String; Out Path, Title: String; Out Running: Boolean;
  Out Rows: TMonitorSnapshot): Boolean;
Function EncodeMonitorTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Function EncodeMonitorSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Function DecodeMonitorSnapshot(Const PayloadJson: String; Out Snapshot: TMonitorSnapshot): Boolean;
{ Splits answer and thinking bodies that exceed 200000 bytes. Each part has part, part_count, and revision. }
Function SplitMonitorTranscript(Const Source: TMonitorTranscript): TMonitorTranscriptArray;
{ One frame when it fits. Otherwise several frames of the same blocks, in order. }
Function PackMonitorTranscript(Const Id: String; Const Transcript: TMonitorTranscript): TStringArray;
Function TryEncodeMonitorTranscript(Const Id: String; Const Transcript: TMonitorTranscript; Out Json: String): Boolean;
Function DecodeMonitorTranscript(Const PayloadJson: String; Out Transcript: TMonitorTranscript): Boolean;

Function EncodeMonitorResume(Const Id, Epoch: String; Cursor: Int64): String;
Function DecodeMonitorResume(Const PayloadJson: String; Out ResumeMsg: TMonitorResume): Boolean;
Function EncodeMonitorCommandState(Const Id, Ref, State, Reason: String): String;
Function EncodeMonitorCommandStates(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;
Function EncodeMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): String;
{ Payload object only. The ring stores this, not the frame envelope. }
Function MonitorPatchPayloadJson(Const Patch: TMonitorPatch): String;
{ Same cursor on every part. Empty when a single block cannot be cut down to the cap. }
Function PackMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Function DecodeMonitorPatch(Const PayloadJson: String; Out Patch: TMonitorPatch): Boolean;
{ FirstPatch copies every current block. Later patches keep only a new block, or one whose
  body, title, running flag, or ok flag changed. Duration and elapsed time do not count. }
Function SelectDirtyMonitorBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;
{ False when any part of that cursor is missing, duplicated, or a different epoch. }
Function TryAssembleMonitorPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Function EncodeMonitorCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Function DecodeMonitorCatchup(Const PayloadJson: String; Out Catchup: TMonitorCatchup): Boolean;
{ One snapshot catchup. The cursor is the snapshot cursor, not the client's discarded cursor. }
Function EncodeResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Function EncodeMonitorConversationClosed(Const Id, Epoch: String; Cursor: Int64; Const ConversationId, Title: String): String;
Function DecodeMonitorConversationClosed(Const PayloadJson: String; Out Closed: TMonitorConversationClosed): Boolean;

Function MonitorTurnIndexRow(TurnIndex: Integer; Const Id, Mode, CreatedAt, PromptPreview, ErrorText: String): TJSONObject;
Function LimitMonitorStoredTurns(Const Turns: TJSONArray): TJSONArray;

{ True when the host must send image_unavailable and keep the socket open. }
Function MonitorImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Function TryBuildMonitorImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Function DecodeMonitorImageData(Const PayloadJson: String; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Function EncodeMonitorImageUnavailable(Const Id, ImageId, Reason: String): String;
Function DecodeMonitorImageUnavailable(Const PayloadJson: String; Out Image: TMonitorImageUnavailable): Boolean;
Function EncodeMonitorImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Function DecodeMonitorImageGet(Const PayloadJson: String; Out Image: TMonitorImageGet): Boolean;
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
  jsonparser, GrokOAuth, AssistantTasks, AssistantMonitorFrames, AssistantMonitorOutbox;

{$IF MonitorListenPort <> GrokOAuthRedirectPort + 1}
  {$ERROR Listen port must stay one above GrokOAuthRedirectPort}
{$ENDIF}
{$IF MonitorImagePartBase64Chars + MonitorImageEnvelopeBytes > MonitorMaxPayloadBytes}
  {$ERROR Image part envelope exceeds the frame cap}
{$ENDIF}
{$IF ((MonitorMaxImagePartBytes + 2) Div 3) * 4 <> MonitorImagePartBase64Chars}
  {$ERROR Image part base64 size drifted}
{$ENDIF}

Function MonitorMessageKindName(Kind: TMonitorMessageKind): String;
Begin
  Case Kind Of
    mmkHello: Result := 'hello';
    mmkPair: Result := 'pair';
    mmkPairOk: Result := 'pair_ok';
    mmkHelloOk: Result := 'hello_ok';
    mmkAuth: Result := 'auth';
    mmkRejected: Result := 'rejected';
    mmkBye: Result := 'bye';
    mmkSnapshot: Result := 'snapshot';
    mmkRefresh: Result := 'refresh';
    mmkTranscript: Result := 'transcript';
    mmkTurn: Result := 'turn';
    mmkTurnData: Result := 'turn_data';
    mmkMode: Result := 'mode';
    mmkSetMode: Result := 'set_mode';
    mmkSend: Result := 'send';
    mmkSteer: Result := 'steer';
    mmkStop: Result := 'stop';
    mmkStatus: Result := 'status';
    mmkTarget: Result := 'target';
    mmkPlan: Result := 'plan';
    mmkSelectPlan: Result := 'select_plan';
    mmkNewPlan: Result := 'new_plan';
    mmkClosePlan: Result := 'close_plan';
    mmkWorkOnPlan: Result := 'work_on_plan';
    mmkRunPlan: Result := 'run_plan';
    mmkStopPlan: Result := 'stop_plan';
    mmkTasks: Result := 'tasks';
    mmkRunTask: Result := 'run_task';
    mmkInsertTask: Result := 'insert_task';
    mmkInsertResult: Result := 'insert_result';
    mmkApprovalRequested: Result := 'approval_requested';
    mmkApprovalDecision: Result := 'approval_decision';
    mmkApprovalClosed: Result := 'approval_closed';
    mmkImageGet: Result := 'image_get';
    mmkImageData: Result := 'image_data';
    mmkImageUnavailable: Result := 'image_unavailable';
    mmkNewConversation: Result := 'new_conversation';
    mmkError: Result := 'error';
    mmkPing: Result := 'ping';
    mmkPong: Result := 'pong';
    mmkResume: Result := 'resume';
    mmkPatch: Result := 'patch';
    mmkCatchup: Result := 'catchup';
    mmkConversationClosed: Result := 'conversation_closed';
    mmkTargets: Result := 'targets';
    mmkSelectTarget: Result := 'select_target';
    mmkConversations: Result := 'conversations';
    mmkSelectConversation: Result := 'select_conversation';
    mmkModels: Result := 'models';
    mmkSetModel: Result := 'set_model';
    mmkReasoning: Result := 'reasoning';
    mmkSetReasoning: Result := 'set_reasoning';
    mmkPermissions: Result := 'permissions';
    mmkSetPermissions: Result := 'set_permissions';
    mmkSnapshotPage: Result := 'snapshot_page';
    mmkChunk: Result := 'chunk';
    mmkCommandState: Result := 'command_state';
    mmkCommandStates: Result := 'command_states';
  Else
    Result := '';
  End;
End;

Function MonitorMessageKindFromName(Const Name: String): TMonitorMessageKind;
Var
  Kind: TMonitorMessageKind;
Begin
  Result := mmkUnknown;
  For Kind := Low(TMonitorMessageKind) To High(TMonitorMessageKind) Do
    If (Kind <> mmkUnknown) And (MonitorMessageKindName(Kind) = Name) Then
      Exit(Kind);
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
Begin
  Result := '';
  If (Kind = mmkUnknown) Or (Not MonitorMessageIdIsSafe(Id)) Then
    Exit;
  Root := TJSONObject.Create;
  Try
    Root.Add('v', MonitorCatalogueVersion);
    Root.Add('id', Id);
    Root.Add('type', MonitorMessageKindName(Kind));
    If Assigned(Payload) Then
      Root.Add('payload', TJSONObject(Payload.Clone))
    Else
      Root.Add('payload', TJSONObject.Create);
    Result := Root.AsJSON;
    If Length(Result) > MonitorMaxPayloadBytes Then
      Result := '';
  Finally
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

Function DecodeOneString(Const PayloadJson, Field: String; Out Value: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Value := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, Field, True, Value);
  Finally
    Data.Free;
  End;
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

Function DecodeMonitorError(Const PayloadJson: String; Out ErrorBody: TMonitorErrorBody): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ErrorBody.Reason := '';
  ErrorBody.MessageText := '';
  ErrorBody.RefId := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'reason', True, ErrorBody.Reason) And
      ReadString(Obj, 'message', True, ErrorBody.MessageText) And ReadString(Obj, 'ref', True, ErrorBody.RefId);
  Finally
    Data.Free;
  End;
End;

Procedure ApplyTextLimit(Var Message: TMonitorMessage);
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Text: String;
Begin
  If (Message.Kind <> mmkSend) And (Message.Kind <> mmkSteer) Then
    Exit;
  If Not ParseObject(Message.PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadString(Obj, 'text', False, Text) Then
      Exit;
    If Length(Text) <= MonitorMaxSendChars Then
      Exit;
    Message.Kind := mmkError;
    Message.TypeName := 'error';
    Message.Reason := MonitorPayloadTooLargeReason;
    Message.ChangesState := False;
    Message.WireJson := EncodeMonitorError(Message.Id, MonitorPayloadTooLargeReason, MonitorPayloadTooLargeMessage, Message.Id);
  Finally
    Data.Free;
  End;
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
  Data := Nil;
  Try
    Try
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
    Message.PayloadJson := Payload.AsJSON;
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
        ApplyTextLimit(Message);
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_name', ClientName);
  Payload.Add('client_version', ClientVersion);
  If ClientId <> '' Then
    Payload.Add('client_id', ClientId);
  Result := EncodeWith(mmkHello, Id, Payload);
End;

Function DecodeMonitorHello(Const PayloadJson: String; Out Hello: TMonitorHello): Boolean;
Var
  Data: TJSONData;
  Payload: TJSONObject;
Begin
  Result := False;
  Hello.ClientName := '';
  Hello.ClientVersion := '';
  Hello.ClientId := '';
  Hello.HasClientId := False;
  If Not ParseObject(PayloadJson, Data, Payload) Then
    Exit;
  Try
    Hello.HasClientId := Assigned(Payload.Find('client_id'));
    Result := ReadString(Payload, 'client_name', True, Hello.ClientName) And
      ReadString(Payload, 'client_version', True, Hello.ClientVersion);
    If Result And Hello.HasClientId Then
      Result := ReadString(Payload, 'client_id', True, Hello.ClientId);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorPair(Const Id, Code, Fingerprint: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('code', Code);
  Payload.Add('fingerprint', Fingerprint);
  Result := EncodeWith(mmkPair, Id, Payload);
End;

Function DecodeMonitorPair(Const PayloadJson: String; Out Pair: TMonitorPair): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Pair.Code := '';
  Pair.Fingerprint := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'code', True, Pair.Code) And ReadString(Obj, 'fingerprint', True, Pair.Fingerprint);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorPairOk(Const Id, ClientId, SessionToken: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_id', ClientId);
  Payload.Add('session_token', SessionToken);
  Result := EncodeWith(mmkPairOk, Id, Payload);
End;

Function DecodeMonitorPairOk(Const PayloadJson: String; Out PairOk: TMonitorPairOk): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  PairOk.ClientId := '';
  PairOk.SessionToken := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'client_id', True, PairOk.ClientId) And
      ReadString(Obj, 'session_token', True, PairOk.SessionToken);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('nonce', HelloOk.Nonce);
  Payload.Add('server_name', HelloOk.ServerName);
  Payload.Add('epoch', HelloOk.Epoch);
  Payload.Add('cursor', HelloOk.Cursor);
  Payload.Add('conversation_id', HelloOk.ConversationId);
  Payload.Add('project_root', HelloOk.ProjectRoot);
  Payload.Add('title', HelloOk.Title);
  If MonitorHostIdIsValid(HelloOk.HostId) Then
    Payload.Add('host_id', HelloOk.HostId);
  Result := EncodeWith(mmkHelloOk, Id, Payload);
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

Function DecodeMonitorHelloOk(Const PayloadJson: String; Out HelloOk: TMonitorHelloOk): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  HelloOk.Nonce := '';
  HelloOk.ServerName := '';
  HelloOk.Epoch := '';
  HelloOk.Cursor := 0;
  HelloOk.ConversationId := '';
  HelloOk.ProjectRoot := '';
  HelloOk.Title := '';
  HelloOk.HostId := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'nonce', True, HelloOk.Nonce) And ReadString(Obj, 'server_name', True, HelloOk.ServerName) And
      ReadString(Obj, 'epoch', True, HelloOk.Epoch) And ReadInt64(Obj, 'cursor', HelloOk.Cursor) And
      ReadString(Obj, 'conversation_id', True, HelloOk.ConversationId) And
      ReadString(Obj, 'project_root', True, HelloOk.ProjectRoot) And ReadString(Obj, 'title', True, HelloOk.Title);
    If Result Then
      Begin
        If Not ReadString(Obj, 'host_id', False, HelloOk.HostId) Then
          Result := False
        Else If (HelloOk.HostId <> '') And (Not MonitorHostIdIsValid(HelloOk.HostId)) Then
          Result := False;
      End;
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorAuth(Const Id, ClientId, Hmac: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_id', ClientId);
  Payload.Add('hmac', Hmac);
  Result := EncodeWith(mmkAuth, Id, Payload);
End;

Function DecodeMonitorAuth(Const PayloadJson: String; Out Auth: TMonitorAuth): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Auth.ClientId := '';
  Auth.Hmac := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'client_id', True, Auth.ClientId) And ReadString(Obj, 'hmac', True, Auth.Hmac);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If Not MonitorRejectedReasonIsKnown(Reason) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('reason', Reason);
  Payload.Add('host_version', HostVersion);
  Payload.Add('client_version', ClientVersion);
  Result := EncodeWith(mmkRejected, Id, Payload);
End;

Function DecodeMonitorRejected(Const PayloadJson: String; Out Rejected: TMonitorRejected): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Rejected.Reason := '';
  Rejected.HostVersion := 0;
  Rejected.ClientVersion := 0;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'reason', True, Rejected.Reason) And
      ReadInt(Obj, 'host_version', True, Rejected.HostVersion) And
      ReadInt(Obj, 'client_version', True, Rejected.ClientVersion) And
      MonitorRejectedReasonIsKnown(Rejected.Reason);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorBye(Const Id, Reason: String): String;
Begin
  Result := EncodeOneString(mmkBye, Id, 'reason', Reason);
End;

Function DecodeMonitorBye(Const PayloadJson: String; Out Bye: TMonitorBye): Boolean;
Begin
  Bye.Reason := '';
  Result := DecodeOneString(PayloadJson, 'reason', Bye.Reason);
End;

Function TryEncodeLimitedText(Kind: TMonitorMessageKind; Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := False;
  Json := '';
  ErrorJson := '';
  If Length(Text) > MonitorMaxSendChars Then
    Begin
      ErrorJson := EncodeMonitorError(Id, MonitorPayloadTooLargeReason, MonitorPayloadTooLargeMessage, Id);
      Exit;
    End;
  Json := EncodeOneString(Kind, Id, 'text', Text);
  Result := Json <> '';
End;

Function TryEncodeMonitorSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeLimitedText(mmkSend, Id, Text, Json, ErrorJson);
End;

Function TryEncodeMonitorSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeLimitedText(mmkSteer, Id, Text, Json, ErrorJson);
End;

Function DecodeMonitorText(Const PayloadJson: String; Out Text: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, 'text', Text) And (Length(Text) <= MonitorMaxSendChars);
End;

Function EncodeMonitorEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Begin
  Result := EncodeMonitorEnvelope(Kind, Id, Nil);
End;

Function EncodeMonitorSetMode(Const Id, Mode: String): String;
Begin
  Result := '';
  If Not MonitorModeIsKnown(Mode) Then
    Exit;
  Result := EncodeOneString(mmkSetMode, Id, 'mode', Mode);
End;

Function DecodeMonitorSetMode(Const PayloadJson: String; Out Mode: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, 'mode', Mode) And MonitorModeIsKnown(Mode);
End;

Function EncodeMonitorMode(Const Id, Mode: String; Locked: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('mode', Mode);
  Payload.Add('locked', Locked);
  Result := EncodeWith(mmkMode, Id, Payload);
End;

Function DecodeMonitorMode(Const PayloadJson: String; Out ModeMessage: TMonitorModeMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ModeMessage.Mode := '';
  ModeMessage.Locked := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'mode', True, ModeMessage.Mode) And ReadBool(Obj, 'locked', True, ModeMessage.Locked);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorTurnRequest(Const Id: String; TurnIndex: Integer): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('turn_index', TurnIndex);
  Result := EncodeWith(mmkTurn, Id, Payload);
End;

Function DecodeMonitorTurnRequest(Const PayloadJson: String; Out TurnIndex: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  TurnIndex := 0;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadInt(Obj, 'turn_index', True, TurnIndex);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorTarget(Const Id, Kind, Display, Root: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('kind', Kind);
  Payload.Add('display', Display);
  Payload.Add('root', Root);
  Result := EncodeWith(mmkTarget, Id, Payload);
End;

Function DecodeMonitorTarget(Const PayloadJson: String; Out Target: TMonitorTargetMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Target.Kind := '';
  Target.Display := '';
  Target.Root := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'kind', True, Target.Kind) And ReadString(Obj, 'display', True, Target.Display) And
      ReadString(Obj, 'root', True, Target.Root);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
Var
  Payload, Choice: TJSONObject;
  Choices: TJSONArray;
  Index: Integer;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('current', Current);
  Choices := TJSONArray.Create;
  Payload.Add('choices', Choices);
  If Assigned(Paths) And Assigned(Captions) Then
    For Index := 0 To Paths.Count - 1 Do
      Begin
        If Index >= Captions.Count Then
          Break;
        Choice := TJSONObject.Create;
        Choice.Add('path', Paths[Index]);
        Choice.Add('caption', Captions[Index]);
        Choices.Add(Choice);
      End;
  Result := EncodeWith(mmkTargets, Id, Payload);
End;

Function DecodeMonitorTargets(Const PayloadJson: String; Out Targets: TMonitorTargetsMessage): Boolean;
Var
  Data, Node, Item: TJSONData;
  Obj, Choice: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
Begin
  Result := False;
  Targets.Current := '';
  SetLength(Targets.Choices, 0);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadString(Obj, 'current', True, Targets.Current) Then
      Exit;
    Node := Obj.Find('choices');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Targets.Choices, Arr.Count);
    For Index := 0 To Arr.Count - 1 Do
      Begin
        Item := Arr.Items[Index];
        If Not (Item Is TJSONObject) Then
          Exit;
        Choice := TJSONObject(Item);
        Targets.Choices[Index].Path := '';
        Targets.Choices[Index].Caption := '';
        If Not ReadString(Choice, 'path', True, Targets.Choices[Index].Path) Or
          Not ReadString(Choice, 'caption', True, Targets.Choices[Index].Caption) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
Var
  Payload, Choice: TJSONObject;
  Choices: TJSONArray;
  Index: Integer;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('current', Current);
  Choices := TJSONArray.Create;
  Payload.Add('choices', Choices);
  If Assigned(Ids) And Assigned(Titles) Then
    For Index := 0 To Ids.Count - 1 Do
      Begin
        If Index >= Titles.Count Then
          Break;
        Choice := TJSONObject.Create;
        Choice.Add('id', Ids[Index]);
        Choice.Add('title', Titles[Index]);
        Choice.Add('current', Ids[Index] = Current);
        Choices.Add(Choice);
      End;
  Payload.Add('truncated', Truncated);
  Result := EncodeWith(mmkConversations, Id, Payload);
End;

Function DecodeMonitorConversations(Const PayloadJson: String; Out Conversations: TMonitorConversationsMessage): Boolean;
Var
  Data, Node, Item: TJSONData;
  Obj, Choice: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
Begin
  Result := False;
  Conversations.Current := '';
  SetLength(Conversations.Choices, 0);
  Conversations.Truncated := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadString(Obj, 'current', True, Conversations.Current) Then
      Exit;
    If Not ReadBool(Obj, 'truncated', True, Conversations.Truncated) Then
      Exit;
    Node := Obj.Find('choices');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Conversations.Choices, Arr.Count);
    For Index := 0 To Arr.Count - 1 Do
      Begin
        Item := Arr.Items[Index];
        If Not (Item Is TJSONObject) Then
          Exit;
        Choice := TJSONObject(Item);
        Conversations.Choices[Index].Id := '';
        Conversations.Choices[Index].Title := '';
        Conversations.Choices[Index].Current := False;
        If Not ReadString(Choice, 'id', True, Conversations.Choices[Index].Id) Or
          Not ReadString(Choice, 'title', True, Conversations.Choices[Index].Title) Or
          Not ReadBool(Choice, 'current', True, Conversations.Choices[Index].Current) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorSelectConversation(Const Id, ArchiveId: String): String;
Begin
  Result := EncodeOneString(mmkSelectConversation, Id, 'id', ArchiveId);
End;

Function DecodeMonitorSelectConversation(Const PayloadJson: String; Out ArchiveId: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, 'id', ArchiveId);
End;

Function EncodeNamedChoices(Kind: TMonitorMessageKind; Const Id, Current, Note: String; Ids, Captions: TStrings;
  Const ExtraName, ExtraValue: String; HasExtra: Boolean): String;
Var
  Payload, Choice: TJSONObject;
  Choices: TJSONArray;
  Index: Integer;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('current', Current);
  If HasExtra Then
    Payload.Add(ExtraName, ExtraValue);
  Choices := TJSONArray.Create;
  Payload.Add('choices', Choices);
  If Assigned(Ids) And Assigned(Captions) Then
    For Index := 0 To Ids.Count - 1 Do
      Begin
        If Index >= Captions.Count Then
          Break;
        Choice := TJSONObject.Create;
        Choice.Add('id', Ids[Index]);
        Choice.Add('caption', Captions[Index]);
        Choices.Add(Choice);
      End;
  Payload.Add('note', Note);
  Result := EncodeWith(Kind, Id, Payload);
End;

Function DecodeNamedChoices(Const PayloadJson: String; Out Current, Note: String; Out Ids, Captions: TStringList;
  Const ExtraName: String; WantExtra: Boolean; Out ExtraValue: String): Boolean;
Var
  Data, Node, Item: TJSONData;
  Obj, Choice: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
  ChoiceId, ChoiceCaption: String;
Begin
  Result := False;
  Current := '';
  Note := '';
  ExtraValue := '';
  Ids := Nil;
  Captions := Nil;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    If Not ReadString(Obj, 'current', True, Current) Then
      Exit;
    If WantExtra And (Not ReadString(Obj, ExtraName, True, ExtraValue)) Then
      Exit;
    If Not ReadString(Obj, 'note', True, Note) Then
      Exit;
    Node := Obj.Find('choices');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    For Index := 0 To Arr.Count - 1 Do
      Begin
        Item := Arr.Items[Index];
        If Not (Item Is TJSONObject) Then
          Exit;
        Choice := TJSONObject(Item);
        If Not ReadString(Choice, 'id', True, ChoiceId) Or Not ReadString(Choice, 'caption', True, ChoiceCaption) Then
          Exit;
        Ids.Add(ChoiceId);
        Captions.Add(ChoiceCaption);
      End;
    Result := True;
  Finally
    Data.Free;
    If Not Result Then
      Begin
        FreeAndNil(Ids);
        FreeAndNil(Captions);
      End;
  End;
End;

Function EncodeMonitorModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkModels, Id, Current, Note, Ids, Captions, 'backend', Backend, True);
End;

Function DecodeMonitorModels(Const PayloadJson: String; Out Models: TMonitorModelsMessage): Boolean;
Var
  Ids, Captions: TStringList;
  Index: Integer;
Begin
  Result := False;
  Models.Current := '';
  Models.Backend := '';
  SetLength(Models.Choices, 0);
  Models.Note := '';
  If Not DecodeNamedChoices(PayloadJson, Models.Current, Models.Note, Ids, Captions, 'backend', True, Models.Backend) Then
    Exit;
  Try
    SetLength(Models.Choices, Ids.Count);
    For Index := 0 To Ids.Count - 1 Do
      Begin
        Models.Choices[Index].Id := Ids[Index];
        Models.Choices[Index].Caption := Captions[Index];
      End;
    Result := True;
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Function EncodeMonitorSetModel(Const Id, ModelId: String): String;
Begin
  Result := EncodeOneString(mmkSetModel, Id, 'model', ModelId);
End;

Function DecodeMonitorSetModel(Const PayloadJson: String; Out ModelId: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, 'model', ModelId);
End;

Function EncodeMonitorReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkReasoning, Id, Current, Note, Ids, Captions, '', '', False);
End;

Function EncodeMonitorSetReasoning(Const Id, Level: String): String;
Begin
  Result := EncodeOneString(mmkSetReasoning, Id, 'level', Level);
End;

Function DecodeMonitorSetReasoning(Const PayloadJson: String; Out Level: String): Boolean;
Begin
  { Missing level is a decode failure. An empty level is model default, not that failure. }
  Result := DecodeOneString(PayloadJson, 'level', Level);
End;

Function EncodeMonitorPermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkPermissions, Id, Current, Note, Ids, Captions, 'backend', Backend, True);
End;

Function DecodeMonitorPermissions(Const PayloadJson: String; Out Permissions: TMonitorPermissionsMessage): Boolean;
Var
  Ids, Captions: TStringList;
  Index: Integer;
Begin
  Result := False;
  Permissions.Current := '';
  Permissions.Backend := '';
  SetLength(Permissions.Choices, 0);
  Permissions.Note := '';
  If Not DecodeNamedChoices(PayloadJson, Permissions.Current, Permissions.Note, Ids, Captions, 'backend', True,
    Permissions.Backend) Then
    Exit;
  Try
    SetLength(Permissions.Choices, Ids.Count);
    For Index := 0 To Ids.Count - 1 Do
      Begin
        Permissions.Choices[Index].Id := Ids[Index];
        Permissions.Choices[Index].Caption := Captions[Index];
      End;
    Result := True;
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Function EncodeMonitorSetPermissions(Const Id, Approval: String): String;
Begin
  Result := EncodeOneString(mmkSetPermissions, Id, 'approval', Approval);
End;

Function DecodeMonitorSetPermissions(Const PayloadJson: String; Out Approval: String): Boolean;
Begin
  { Missing approval is a decode failure. It is not ask. }
  Result := DecodeOneString(PayloadJson, 'approval', Approval);
End;

Function DecodeMonitorReasoning(Const PayloadJson: String; Out Reasoning: TMonitorReasoningMessage): Boolean;
Var
  Ids, Captions: TStringList;
  Index: Integer;
  Ignored: String;
Begin
  Result := False;
  Reasoning.Current := '';
  SetLength(Reasoning.Choices, 0);
  Reasoning.Note := '';
  If Not DecodeNamedChoices(PayloadJson, Reasoning.Current, Reasoning.Note, Ids, Captions, '', False, Ignored) Then
    Exit;
  Try
    SetLength(Reasoning.Choices, Ids.Count);
    For Index := 0 To Ids.Count - 1 Do
      Begin
        Reasoning.Choices[Index].Id := Ids[Index];
        Reasoning.Choices[Index].Caption := Captions[Index];
      End;
    Result := True;
  Finally
    Captions.Free;
    Ids.Free;
  End;
End;

Function EncodeMonitorPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Begin
  Result := '';
  If (Kind <> mmkSelectPlan) And (Kind <> mmkSelectTarget) Then
    Exit;
  Result := EncodeOneString(Kind, Id, 'path', Path);
End;

Function DecodeMonitorPath(Const PayloadJson: String; Out Path: String): Boolean;
Begin
  Result := DecodeOneString(PayloadJson, 'path', Path);
End;

Function EncodeMonitorNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  If HasTitle Then
    Payload.Add('title', Title);
  Result := EncodeWith(mmkNewPlan, Id, Payload);
End;

Function DecodeMonitorNewPlan(Const PayloadJson: String; Out Plan: TMonitorPathMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Plan.Path := '';
  Plan.Title := '';
  Plan.HasTitle := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Plan.HasTitle := Assigned(Obj.Find('title'));
    Result := True;
    If Plan.HasTitle Then
      Result := ReadString(Obj, 'title', True, Plan.Title);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorWorkOnPlan(Const Id: String; Index: Integer): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('index', Index);
  Result := EncodeWith(mmkWorkOnPlan, Id, Payload);
End;

Function DecodeMonitorWorkOnPlan(Const PayloadJson: String; Out Index: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Index := 0;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadInt(Obj, 'index', True, Index);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorTaskCommand(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If (Kind <> mmkRunTask) And (Kind <> mmkInsertTask) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('id', TaskId);
  Payload.Add('note', Note);
  Result := EncodeWith(Kind, Id, Payload);
End;

Function DecodeMonitorTaskCommand(Const PayloadJson: String; Out Command: TMonitorTaskCommand): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Command.Id := '';
  Command.Note := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'id', True, Command.Id) And ReadString(Obj, 'note', True, Command.Note);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorInsertResult(Const Id, Text: String): String;
Begin
  Result := EncodeOneString(mmkInsertResult, Id, 'text', Text);
End;

Function EncodeMonitorTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If (Kind <> mmkPing) And (Kind <> mmkPong) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('ticks', Ticks);
  Result := EncodeWith(Kind, Id, Payload);
End;

Function DecodeMonitorTicks(Const PayloadJson: String; Out Ticks: TMonitorTicks): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Ticks.Ticks := 0;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadInt64(Obj, 'ticks', Ticks.Ticks);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', Notice.ToolId);
  Payload.Add('tool_name', Notice.ToolName);
  Payload.Add('summary', Notice.Summary);
  Payload.Add('mode_caption', Notice.ModeCaption);
  Payload.Add('decisions_accepted', Notice.DecisionsAccepted);
  Result := EncodeWith(mmkApprovalRequested, Id, Payload);
End;

Function DecodeMonitorApprovalRequested(Const PayloadJson: String; Out Notice: TAssistantApprovalNotice): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Notice.Active := True;
  Notice.ToolId := '';
  Notice.ToolName := '';
  Notice.Summary := '';
  Notice.ModeCaption := '';
  Notice.DecisionsAccepted := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'tool_id', True, Notice.ToolId) And ReadString(Obj, 'tool_name', True, Notice.ToolName) And
      ReadString(Obj, 'summary', True, Notice.Summary) And ReadString(Obj, 'mode_caption', True, Notice.ModeCaption) And
      ReadBool(Obj, 'decisions_accepted', True, Notice.DecisionsAccepted);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', ToolId);
  Payload.Add('allow', Allow);
  Result := EncodeWith(mmkApprovalDecision, Id, Payload);
End;

Function DecodeMonitorApprovalDecision(Const PayloadJson: String; Out Decision: TMonitorApprovalDecision): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Decision.ToolId := '';
  Decision.Allow := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'tool_id', True, Decision.ToolId) And ReadBool(Obj, 'allow', True, Decision.Allow);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorApprovalClosed(Const Id, ToolId, Reason: String): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If Not MonitorApprovalCloseReasonIsKnown(Reason) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', ToolId);
  Payload.Add('reason', Reason);
  Result := EncodeWith(mmkApprovalClosed, Id, Payload);
End;

Function DecodeMonitorApprovalClosed(Const PayloadJson: String; Out Closed: TMonitorApprovalClosed): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Closed.ToolId := '';
  Closed.Reason := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'tool_id', True, Closed.ToolId) And ReadString(Obj, 'reason', True, Closed.Reason) And
      MonitorApprovalCloseReasonIsKnown(Closed.Reason);
  Finally
    Data.Free;
  End;
End;

Function MonitorToolBodyForWire(Const Body: String; Out Truncated: Boolean): String;
Begin
  Truncated := Length(Body) > MonitorMaxToolBodyChars;
  If Truncated Then
    Result := Copy(Body, 1, MonitorMaxToolBodyChars)
  Else
    Result := Body;
End;

Function Utf8Boundary(Const Body: String; Index: Integer): Integer;
Begin
  Result := Index;
  While (Result > 1) And (Result <= Length(Body)) And ((Ord(Body[Result]) And $C0) = $80) Do
    Dec(Result);
  If Result < 1 Then
    Result := 1;
End;

Function SplitMonitorBody(Const Body: String; Revision: Integer): TMonitorBodyPartArray;
Var
  StartAt, NextAt, Take, I: Integer;
Begin
  Result := Nil;
  SetLength(Result, 0);
  If Length(Body) <= MonitorMaxBodyPartBytes Then
    Begin
      SetLength(Result, 1);
      Result[0].Part := 1;
      Result[0].PartCount := 1;
      Result[0].Revision := Revision;
      Result[0].Text := Body;
      Exit;
    End;
  StartAt := 1;
  While StartAt <= Length(Body) Do
    Begin
      NextAt := StartAt + MonitorMaxBodyPartBytes;
      If NextAt > Length(Body) + 1 Then
        NextAt := Length(Body) + 1
      Else
        NextAt := Utf8Boundary(Body, NextAt);
      If NextAt <= StartAt Then
        NextAt := StartAt + 1;
      Take := NextAt - StartAt;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Text := Copy(Body, StartAt, Take);
      Result[High(Result)].Revision := Revision;
      StartAt := NextAt;
    End;
  For I := 0 To High(Result) Do
    Begin
      Result[I].Part := I + 1;
      Result[I].PartCount := Length(Result);
    End;
End;

Function ImageToJson(Const Image: TAssistantMonitorImage): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Image.Id);
  Result.Add('name', Image.Name);
  Result.Add('mime', Image.Mime);
  Result.Add('width', Image.Width);
  Result.Add('height', Image.Height);
  Result.Add('display_path', Image.DisplayPath);
  Result.Add('missing', Image.Missing);
End;

Function TryImageFromJson(Obj: TJSONObject; Out Image: TAssistantMonitorImage): Boolean;
Begin
  Result := False;
  Image.Id := '';
  Image.Name := '';
  Image.Mime := '';
  Image.Width := 0;
  Image.Height := 0;
  Image.DisplayPath := '';
  Image.Missing := False;
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadString(Obj, 'id', True, Image.Id) And ReadString(Obj, 'name', True, Image.Name) And
    ReadString(Obj, 'mime', True, Image.Mime) And ReadInt(Obj, 'width', True, Image.Width) And
    ReadInt(Obj, 'height', True, Image.Height) And ReadString(Obj, 'display_path', True, Image.DisplayPath) And
    ReadBool(Obj, 'missing', True, Image.Missing);
End;

Function ImagesToJson(Const Images: Array Of TAssistantMonitorImage): TJSONArray;
Var
  I: Integer;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Images) Do
    Result.Add(ImageToJson(Images[I]));
End;

Function MonitorBlockToJson(Const Block: TAssistantMonitorBlock; Part, PartCount, Revision: Integer): TJSONObject;
Var
  Truncated: Boolean;
  Body: String;
Begin
  Result := TJSONObject.Create;
  Result.Add('kind', Block.Kind);
  Result.Add('block_id', Block.BlockId);
  Result.Add('title', Block.Title);
  Result.Add('tool_name', Block.ToolName);
  Result.Add('tool_id', Block.ToolId);
  If Block.Kind = 'tool' Then
    Begin
      Body := MonitorToolBodyForWire(Block.Body, Truncated);
      Result.Add('body', Body);
      If Truncated Then
        Result.Add('truncated', True);
    End
  Else
    Result.Add('body', Block.Body);
  Result.Add('running', Block.Running);
  Result.Add('ok', Block.Ok);
  Result.Add('duration_ms', Block.DurationMs);
  Result.Add('images', ImagesToJson(Block.Images));
  If PartCount > 1 Then
    Begin
      Result.Add('part', Part);
      Result.Add('part_count', PartCount);
      Result.Add('revision', Revision);
    End;
End;

Function TryMonitorBlockFromJson(Obj: TJSONObject; Out Block: TAssistantMonitorBlock; Out Truncated: Boolean): Boolean;
Var
  Node: TJSONData;
  Images: TJSONArray;
  I: Integer;
  Image: TAssistantMonitorImage;
Begin
  Result := False;
  Truncated := False;
  Block.Kind := '';
  Block.BlockId := '';
  Block.Title := '';
  Block.ToolName := '';
  Block.ToolId := '';
  Block.Body := '';
  Block.Running := False;
  Block.Ok := False;
  Block.DurationMs := 0;
  SetLength(Block.Images, 0);
  If Not Assigned(Obj) Then
    Exit;
  If Not (ReadString(Obj, 'kind', True, Block.Kind) And ReadString(Obj, 'block_id', True, Block.BlockId) And
    ReadString(Obj, 'title', True, Block.Title) And ReadString(Obj, 'tool_name', True, Block.ToolName) And
    ReadString(Obj, 'tool_id', True, Block.ToolId) And ReadString(Obj, 'body', True, Block.Body) And
    ReadBool(Obj, 'running', True, Block.Running) And ReadBool(Obj, 'ok', True, Block.Ok) And
    ReadInt(Obj, 'duration_ms', True, Block.DurationMs)) Then
    Exit;
  If Block.Kind = 'tool' Then
    Begin
      If Not ReadBool(Obj, 'truncated', False, Truncated) Then
        Exit;
      If Length(Block.Body) > MonitorMaxToolBodyChars Then
        Exit;
    End;
  Node := Obj.Find('images');
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Images := TJSONArray(Node);
  SetLength(Block.Images, Images.Count);
  For I := 0 To Images.Count - 1 Do
    Begin
      If Not (Images[I] Is TJSONObject) Then
        Exit;
      If Not TryImageFromJson(TJSONObject(Images[I]), Image) Then
        Exit;
      Block.Images[I] := Image;
    End;
  Result := True;
End;

Procedure ClearView(Out View: TAssistantMonitorView);
Begin
  View.Available := False;
  View.Busy := False;
  View.Sending := False;
  View.ModeLocked := False;
  View.PlanRunning := False;
  View.Mode := '';
  View.Phase := '';
  View.StatusText := '';
  View.ElapsedMs := 0;
  View.Model := '';
  View.Backend := '';
  View.SignedIn := False;
  View.ApprovalCaption := '';
  View.Effort := '';
  View.Skill := '';
  View.ContextText := '';
  View.UsageCaption := '';
  View.UsageHint := '';
  View.TargetKind := '';
  View.TargetDisplay := '';
  View.TargetRoot := '';
  View.PlanPath := '';
  View.PlanTitle := '';
  View.CanSend := False;
  View.CanSteer := False;
  View.CanStop := False;
  View.CanChangeMode := False;
  View.RemoteApproval := False;
  View.ErrorText := '';
End;

Procedure AddStatusFields(Obj: TJSONObject; Const View: TAssistantMonitorView);
Begin
  Obj.Add('available', View.Available);
  Obj.Add('busy', View.Busy);
  Obj.Add('sending', View.Sending);
  Obj.Add('mode_locked', View.ModeLocked);
  Obj.Add('plan_running', View.PlanRunning);
  Obj.Add('phase', View.Phase);
  Obj.Add('status_text', View.StatusText);
  Obj.Add('elapsed_ms', View.ElapsedMs);
  Obj.Add('model', View.Model);
  Obj.Add('backend', View.Backend);
  Obj.Add('signed_in', View.SignedIn);
  Obj.Add('approval_caption', View.ApprovalCaption);
  Obj.Add('effort', View.Effort);
  Obj.Add('skill', View.Skill);
  Obj.Add('context_text', View.ContextText);
  Obj.Add('can_send', View.CanSend);
  Obj.Add('can_steer', View.CanSteer);
  Obj.Add('can_stop', View.CanStop);
  Obj.Add('can_change_mode', View.CanChangeMode);
  Obj.Add('remote_approval', View.RemoteApproval);
  Obj.Add('error_text', View.ErrorText);
  { Absent means this connection has not reported account usage. An empty string is not sent. }
  If View.UsageCaption <> '' Then
    Obj.Add('usage_caption', View.UsageCaption);
  If View.UsageHint <> '' Then
    Obj.Add('usage_hint', View.UsageHint);
End;

Function ReadStatusFields(Obj: TJSONObject; Var View: TAssistantMonitorView): Boolean;
Begin
  Result := ReadBool(Obj, 'available', True, View.Available) And ReadBool(Obj, 'busy', True, View.Busy) And
    ReadBool(Obj, 'sending', True, View.Sending) And ReadBool(Obj, 'mode_locked', True, View.ModeLocked) And
    ReadBool(Obj, 'plan_running', True, View.PlanRunning) And ReadString(Obj, 'phase', True, View.Phase) And
    ReadString(Obj, 'status_text', True, View.StatusText) And ReadString(Obj, 'model', True, View.Model) And
    ReadString(Obj, 'backend', True, View.Backend) And ReadBool(Obj, 'signed_in', True, View.SignedIn) And
    ReadString(Obj, 'approval_caption', True, View.ApprovalCaption) And ReadString(Obj, 'effort', True, View.Effort) And
    ReadString(Obj, 'skill', True, View.Skill) And ReadString(Obj, 'context_text', True, View.ContextText) And
    ReadBool(Obj, 'can_send', True, View.CanSend) And ReadBool(Obj, 'can_steer', True, View.CanSteer) And
    ReadBool(Obj, 'can_stop', True, View.CanStop) And ReadBool(Obj, 'can_change_mode', True, View.CanChangeMode) And
    ReadBool(Obj, 'remote_approval', True, View.RemoteApproval) And ReadString(Obj, 'error_text', True, View.ErrorText);
  If Result Then
    Begin
      View.ElapsedMs := 0;
      If Not ReadInt(Obj, 'elapsed_ms', False, View.ElapsedMs) Then
        Result := False;
      If View.ElapsedMs < 0 Then
        View.ElapsedMs := 0;
      If Not ReadString(Obj, 'usage_caption', False, View.UsageCaption) Then
        Result := False;
      If Not ReadString(Obj, 'usage_hint', False, View.UsageHint) Then
        Result := False;
    End;
End;

Function MonitorStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Begin
  Result := TJSONObject.Create;
  AddStatusFields(Result, View);
End;

Function TryMonitorStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Begin
  ClearView(View);
  Result := Assigned(Obj) And ReadStatusFields(Obj, View);
End;

Function MonitorViewToJson(Const View: TAssistantMonitorView): TJSONObject;
Begin
  Result := MonitorStatusToJson(View);
  Result.Add('mode', View.Mode);
  Result.Add('target_kind', View.TargetKind);
  Result.Add('target_display', View.TargetDisplay);
  Result.Add('target_root', View.TargetRoot);
  Result.Add('plan_path', View.PlanPath);
  Result.Add('plan_title', View.PlanTitle);
End;

Function TryMonitorViewFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Begin
  Result := False;
  ClearView(View);
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadStatusFields(Obj, View) And ReadString(Obj, 'mode', True, View.Mode) And
    ReadString(Obj, 'target_kind', True, View.TargetKind) And ReadString(Obj, 'target_display', True, View.TargetDisplay) And
    ReadString(Obj, 'target_root', True, View.TargetRoot) And ReadString(Obj, 'plan_path', True, View.PlanPath) And
    ReadString(Obj, 'plan_title', True, View.PlanTitle);
End;

Procedure ClearTurn(Out Turn: TAssistantMonitorTurn);
Begin
  Turn.TurnIndex := 0;
  Turn.Id := '';
  Turn.Mode := '';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.ErrorText := '';
  Turn.CreatedAt := '';
  Turn.DurationMs := 0;
  Turn.PromptPreview := '';
  Turn.Live := False;
  SetLength(Turn.Blocks, 0);
  SetLength(Turn.Images, 0);
End;

Function MonitorTurnToJson(Const Turn: TAssistantMonitorTurn; IndexOnly: Boolean): TJSONObject;
Var
  I: Integer;
  Blocks, Images: TJSONArray;
Begin
  Result := TJSONObject.Create;
  Result.Add('turn_index', Turn.TurnIndex);
  Result.Add('id', Turn.Id);
  Result.Add('mode', Turn.Mode);
  Result.Add('created_at', Turn.CreatedAt);
  Result.Add('prompt_preview', Turn.PromptPreview);
  Result.Add('error_text', Turn.ErrorText);
  If IndexOnly Then
    Exit;
  Result.Add('prompt', Turn.Prompt);
  Result.Add('thinking', Turn.Thinking);
  Result.Add('response', Turn.Response);
  Result.Add('duration_ms', Turn.DurationMs);
  Result.Add('live', Turn.Live);
  Blocks := TJSONArray.Create;
  For I := 0 To High(Turn.Blocks) Do
    Blocks.Add(MonitorBlockToJson(Turn.Blocks[I], 1, 1, 0));
  Result.Add('blocks', Blocks);
  Images := ImagesToJson(Turn.Images);
  Result.Add('images', Images);
End;

Function TryReadImages(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Var
  Images: TJSONArray;
  I: Integer;
  Image: TAssistantMonitorImage;
Begin
  Result := False;
  SetLength(Turn.Images, 0);
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Images := TJSONArray(Node);
  SetLength(Turn.Images, Images.Count);
  For I := 0 To Images.Count - 1 Do
    Begin
      If Not (Images[I] Is TJSONObject) Then
        Exit;
      If Not TryImageFromJson(TJSONObject(Images[I]), Image) Then
        Exit;
      Turn.Images[I] := Image;
    End;
  Result := True;
End;

Function TryReadBlocks(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Var
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  SetLength(Turn.Blocks, 0);
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Blocks := TJSONArray(Node);
  SetLength(Turn.Blocks, Blocks.Count);
  For I := 0 To Blocks.Count - 1 Do
    Begin
      If Not (Blocks[I] Is TJSONObject) Then
        Exit;
      If Not TryMonitorBlockFromJson(TJSONObject(Blocks[I]), Turn.Blocks[I], Truncated) Then
        Exit;
    End;
  Result := True;
End;

Function TryMonitorTurnFromJson(Obj: TJSONObject; IndexOnly: Boolean; Out Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := False;
  ClearTurn(Turn);
  If Not Assigned(Obj) Then
    Exit;
  If Not (ReadInt(Obj, 'turn_index', True, Turn.TurnIndex) And ReadString(Obj, 'id', True, Turn.Id) And
    ReadString(Obj, 'mode', True, Turn.Mode) And ReadString(Obj, 'created_at', True, Turn.CreatedAt) And
    ReadString(Obj, 'prompt_preview', True, Turn.PromptPreview) And ReadString(Obj, 'error_text', True, Turn.ErrorText)) Then
    Exit;
  If IndexOnly Then
    Begin
      Result := True;
      Exit;
    End;
  Result := ReadString(Obj, 'prompt', True, Turn.Prompt) And ReadString(Obj, 'thinking', True, Turn.Thinking) And
    ReadString(Obj, 'response', True, Turn.Response) And ReadInt(Obj, 'duration_ms', True, Turn.DurationMs) And
    ReadBool(Obj, 'live', True, Turn.Live) And TryReadBlocks(Obj.Find('blocks'), Turn) And TryReadImages(Obj.Find('images'), Turn);
End;

Function EncodeMonitorTurnData(Const Id: String; Const Turn: TAssistantMonitorTurn): String;
Begin
  Result := EncodeWith(mmkTurnData, Id, MonitorTurnToJson(Turn, False));
End;

Function DecodeMonitorTurnData(Const PayloadJson: String; Out Turn: TAssistantMonitorTurn): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ClearTurn(Turn);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := TryMonitorTurnFromJson(Obj, False, Turn);
  Finally
    Data.Free;
  End;
End;

Function PlanRowToJson(Const Row: TAssistantMonitorPlanRow): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('index', Row.Index);
  Result.Add('level', Row.Level);
  Result.Add('title', Row.Title);
  Result.Add('parent_title', Row.ParentTitle);
  Result.Add('status', Row.Status);
  Result.Add('actionable', Row.Actionable);
End;

Function TryPlanRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorPlanRow): Boolean;
Begin
  Result := False;
  Row.Index := 0;
  Row.Level := 0;
  Row.Title := '';
  Row.ParentTitle := '';
  Row.Status := '';
  Row.Actionable := False;
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadInt(Obj, 'index', True, Row.Index) And ReadInt(Obj, 'level', True, Row.Level) And
    ReadString(Obj, 'title', True, Row.Title) And ReadString(Obj, 'parent_title', True, Row.ParentTitle) And
    ReadString(Obj, 'status', True, Row.Status) And ReadBool(Obj, 'actionable', True, Row.Actionable);
End;

Function PlanRowsToJson(Const Rows: Array Of TAssistantMonitorPlanRow): TJSONArray;
Var
  I: Integer;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Rows) Do
    Result.Add(PlanRowToJson(Rows[I]));
End;

Function TaskRowToJson(Const Row: TAssistantMonitorTaskRow): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Row.Id);
  Result.Add('title', Row.Title);
  Result.Add('summary', Row.Summary);
  Result.Add('mode', Row.Mode);
  Result.Add('kind', Row.Kind);
  Result.Add('scope', Row.Scope);
  Result.Add('compile_first', Row.CompileFirst);
  Result.Add('enabled', Row.Enabled);
  Result.Add('needs_note', Row.NeedsNote);
End;

Function TryTaskRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorTaskRow): Boolean;
Begin
  Result := False;
  Row.Id := '';
  Row.Title := '';
  Row.Summary := '';
  Row.Mode := '';
  Row.Kind := '';
  Row.Scope := '';
  Row.CompileFirst := False;
  Row.Enabled := False;
  Row.NeedsNote := False;
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadString(Obj, 'id', True, Row.Id) And ReadString(Obj, 'title', True, Row.Title) And
    ReadString(Obj, 'summary', True, Row.Summary) And ReadString(Obj, 'mode', True, Row.Mode) And
    ReadString(Obj, 'kind', True, Row.Kind) And ReadString(Obj, 'scope', True, Row.Scope) And
    ReadBool(Obj, 'compile_first', True, Row.CompileFirst) And ReadBool(Obj, 'enabled', True, Row.Enabled) And
    ReadBool(Obj, 'needs_note', True, Row.NeedsNote);
End;

Function TaskRowsToJson(Const Rows: Array Of TAssistantMonitorTaskRow): TJSONArray;
Var
  I: Integer;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Rows) Do
    Result.Add(TaskRowToJson(Rows[I]));
End;

Function EncodeMonitorPlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings; Captions: TStrings;
  Const Epoch: String; Cursor: Int64; Const Body: String): String;
Var
  Payload, Choice: TJSONObject;
  Choices: TJSONArray;
  I: Integer;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('path', Path);
  Payload.Add('title', Title);
  Payload.Add('running', Running);
  Payload.Add('rows', PlanRowsToJson(Rows));
  { Absent means this frame has no document text. An empty string is not sent. }
  If Body <> '' Then
    Payload.Add('body', Body);
  If Epoch <> '' Then
    Begin
      Payload.Add('epoch', Epoch);
      Payload.Add('cursor', Cursor);
    End;
  If Assigned(Paths) And Assigned(Captions) Then
    Begin
      Choices := TJSONArray.Create;
      Payload.Add('choices', Choices);
      For I := 0 To Paths.Count - 1 Do
        Begin
          If I >= Captions.Count Then
            Break;
          Choice := TJSONObject.Create;
          Choice.Add('path', Paths[I]);
          Choice.Add('caption', Captions[I]);
          Choices.Add(Choice);
        End;
    End;
  Result := EncodeWith(mmkPlan, Id, Payload);
End;

Function DecodeMonitorPlan(Const PayloadJson: String; Out Path, Title: String; Out Running: Boolean;
  Out Rows: TMonitorSnapshot): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := False;
  Path := '';
  Title := '';
  Running := False;
  Rows.PlanPath := '';
  Rows.PlanTitle := '';
  Rows.PlanRunning := False;
  Rows.PlanBody := '';
  SetLength(Rows.PlanRows, 0);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadString(Obj, 'path', True, Path) And ReadString(Obj, 'title', True, Title) And
      ReadBool(Obj, 'running', True, Running)) Then
      Exit;
    Node := Obj.Find('rows');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Rows.PlanRows, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryPlanRowFromJson(TJSONObject(Arr[I]), Rows.PlanRows[I]) Then
          Exit;
      End;
    Rows.PlanPath := Path;
    Rows.PlanTitle := Title;
    Rows.PlanRunning := Running;
    If Not ReadString(Obj, 'body', False, Rows.PlanBody) Then
      Exit;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('rows', TaskRowsToJson(Rows));
  Result := EncodeWith(mmkTasks, Id, Payload);
End;

Function ApprovalToJson(Const Notice: TAssistantApprovalNotice): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('active', Notice.Active);
  Result.Add('tool_id', Notice.ToolId);
  Result.Add('tool_name', Notice.ToolName);
  Result.Add('summary', Notice.Summary);
  Result.Add('mode_caption', Notice.ModeCaption);
  Result.Add('decisions_accepted', Notice.DecisionsAccepted);
End;

Function TryApprovalFromJson(Obj: TJSONObject; Out Notice: TAssistantApprovalNotice): Boolean;
Begin
  Result := False;
  Notice.Active := False;
  Notice.ToolId := '';
  Notice.ToolName := '';
  Notice.Summary := '';
  Notice.ModeCaption := '';
  Notice.DecisionsAccepted := False;
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadBool(Obj, 'active', True, Notice.Active) And ReadString(Obj, 'tool_id', True, Notice.ToolId) And
    ReadString(Obj, 'tool_name', True, Notice.ToolName) And ReadString(Obj, 'summary', True, Notice.Summary) And
    ReadString(Obj, 'mode_caption', True, Notice.ModeCaption) And
    ReadBool(Obj, 'decisions_accepted', True, Notice.DecisionsAccepted);
End;

Function StoredTurnIsLive(Const Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := Turn.Live;
End;

Function EncodeMonitorSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Var
  Payload, PlanObj, Tasks: TJSONObject;
  TurnRows: TJSONArray;
  Kept: Array Of TAssistantMonitorTurn;
  I, Count, StartAt: Integer;
Begin
  Result := '';
  Kept := Nil;
  TurnRows := Nil;
  Count := 0;
  For I := 0 To High(Snapshot.StoredTurns) Do
    If Not StoredTurnIsLive(Snapshot.StoredTurns[I]) Then
      Inc(Count);
  SetLength(Kept, Count);
  Count := 0;
  For I := 0 To High(Snapshot.StoredTurns) Do
    If Not StoredTurnIsLive(Snapshot.StoredTurns[I]) Then
      Begin
        Kept[Count] := Snapshot.StoredTurns[I];
        Inc(Count);
      End;
  StartAt := 0;
  If Count > MonitorSnapshotStoredTurns Then
    StartAt := Count - MonitorSnapshotStoredTurns;
  TurnRows := TJSONArray.Create;
  For I := StartAt To Count - 1 Do
    TurnRows.Add(MonitorTurnToJson(Kept[I], True));
  Payload := TJSONObject.Create;
  Try
    Payload.Add('view', MonitorViewToJson(Snapshot.View));
    Payload.Add('turns', TurnRows);
    TurnRows := Nil;
    If Snapshot.HasLive Then
      Payload.Add('live', MonitorTurnToJson(Snapshot.Live, False))
    Else
      Payload.Add('live', TJSONNull.Create);
    PlanObj := TJSONObject.Create;
    PlanObj.Add('path', Snapshot.PlanPath);
    PlanObj.Add('title', Snapshot.PlanTitle);
    PlanObj.Add('running', Snapshot.PlanRunning);
    PlanObj.Add('rows', PlanRowsToJson(Snapshot.PlanRows));
    Payload.Add('plan', PlanObj);
    Tasks := TJSONObject.Create;
    Tasks.Add('rows', TaskRowsToJson(Snapshot.TaskRows));
    Payload.Add('tasks', Tasks);
    Payload.Add('approval', ApprovalToJson(Snapshot.Approval));
    Result := EncodeMonitorEnvelope(mmkSnapshot, Id, Payload);
  Finally
    TurnRows.Free;
    Payload.Free;
  End;
End;

Function DecodeMonitorSnapshot(Const PayloadJson: String; Out Snapshot: TMonitorSnapshot): Boolean;
Var
  Data: TJSONData;
  Obj, Child: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := False;
  ClearView(Snapshot.View);
  SetLength(Snapshot.StoredTurns, 0);
  ClearTurn(Snapshot.Live);
  Snapshot.HasLive := False;
  Snapshot.PlanPath := '';
  Snapshot.PlanTitle := '';
  Snapshot.PlanRunning := False;
  Snapshot.PlanBody := '';
  SetLength(Snapshot.PlanRows, 0);
  SetLength(Snapshot.TaskRows, 0);
  Snapshot.Approval.Active := False;
  Snapshot.Approval.ToolId := '';
  Snapshot.Approval.ToolName := '';
  Snapshot.Approval.Summary := '';
  Snapshot.Approval.ModeCaption := '';
  Snapshot.Approval.DecisionsAccepted := False;
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (Obj.Find('view') Is TJSONObject) Then
      Exit;
    If Not TryMonitorViewFromJson(TJSONObject(Obj.Find('view')), Snapshot.View) Then
      Exit;
    Node := Obj.Find('turns');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    If Arr.Count > MonitorSnapshotStoredTurns Then
      Exit;
    SetLength(Snapshot.StoredTurns, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryMonitorTurnFromJson(TJSONObject(Arr[I]), True, Snapshot.StoredTurns[I]) Then
          Exit;
      End;
    Node := Obj.Find('live');
    If Not Assigned(Node) Or (Node Is TJSONNull) Then
      Snapshot.HasLive := False
    Else If Node Is TJSONObject Then
      Begin
        If Not TryMonitorTurnFromJson(TJSONObject(Node), False, Snapshot.Live) Then
          Exit;
        Snapshot.HasLive := True;
      End
    Else
      Exit;
    If Not (Obj.Find('plan') Is TJSONObject) Then
      Exit;
    Child := TJSONObject(Obj.Find('plan'));
    If Not (ReadString(Child, 'path', True, Snapshot.PlanPath) And ReadString(Child, 'title', True, Snapshot.PlanTitle) And
      ReadBool(Child, 'running', True, Snapshot.PlanRunning)) Then
      Exit;
    Node := Child.Find('rows');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Snapshot.PlanRows, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryPlanRowFromJson(TJSONObject(Arr[I]), Snapshot.PlanRows[I]) Then
          Exit;
      End;
    If Not (Obj.Find('tasks') Is TJSONObject) Then
      Exit;
    Child := TJSONObject(Obj.Find('tasks'));
    Node := Child.Find('rows');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Snapshot.TaskRows, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryTaskRowFromJson(TJSONObject(Arr[I]), Snapshot.TaskRows[I]) Then
          Exit;
      End;
    If Not (Obj.Find('approval') Is TJSONObject) Then
      Exit;
    Result := TryApprovalFromJson(TJSONObject(Obj.Find('approval')), Snapshot.Approval);
  Finally
    Data.Free;
  End;
End;

Function CopyBlock(Const Block: TAssistantMonitorBlock): TAssistantMonitorBlock;
Begin
  Result := Block;
End;

Function SplitMonitorTranscript(Const Source: TMonitorTranscript): TMonitorTranscriptArray;
Var
  Pieces: Array Of TAssistantMonitorBlock;
  PiecePart, PieceCount: Array Of Integer;
  PieceN, I, J, MaxParts, FrameCount: Integer;
  Parts: TMonitorBodyPartArray;
  Slice: TAssistantMonitorBlock;
Begin
  Result := Nil;
  Pieces := Nil;
  PiecePart := Nil;
  PieceCount := Nil;
  SetLength(Result, 0);
  SetLength(Pieces, 0);
  SetLength(PiecePart, 0);
  SetLength(PieceCount, 0);
  MaxParts := 1;
  For I := 0 To High(Source.Blocks) Do
    Begin
      If (Source.Blocks[I].Kind = 'answer') Or (Source.Blocks[I].Kind = 'thinking') Then
        Parts := SplitMonitorBody(Source.Blocks[I].Body, Source.Revision)
      Else
        Begin
          SetLength(Parts, 1);
          Parts[0].Part := 1;
          Parts[0].PartCount := 1;
          Parts[0].Revision := Source.Revision;
          Parts[0].Text := Source.Blocks[I].Body;
        End;
      If Parts[0].PartCount > MaxParts Then
        MaxParts := Parts[0].PartCount;
      For J := 0 To High(Parts) Do
        Begin
          Slice := CopyBlock(Source.Blocks[I]);
          Slice.Body := Parts[J].Text;
          SetLength(Pieces, Length(Pieces) + 1);
          SetLength(PiecePart, Length(Pieces));
          SetLength(PieceCount, Length(Pieces));
          Pieces[High(Pieces)] := Slice;
          PiecePart[High(Pieces)] := Parts[J].Part;
          PieceCount[High(Pieces)] := Parts[J].PartCount;
        End;
    End;
  If Length(Source.Blocks) = 0 Then
    MaxParts := 1;
  FrameCount := MaxParts;
  SetLength(Result, FrameCount);
  For I := 0 To FrameCount - 1 Do
    Begin
      Result[I].TurnIndex := Source.TurnIndex;
      Result[I].Revision := Source.Revision;
      Result[I].Phase := Source.Phase;
      Result[I].StatusText := Source.StatusText;
      Result[I].DurationMs := Source.DurationMs;
      Result[I].Part := I + 1;
      Result[I].PartCount := FrameCount;
      SetLength(Result[I].Blocks, 0);
      SetLength(Result[I].BlockPart, 0);
      SetLength(Result[I].BlockPartCount, 0);
    End;
  For PieceN := 0 To High(Pieces) Do
    Begin
      I := PiecePart[PieceN] - 1;
      If (I < 0) Or (I > High(Result)) Then
        Continue;
      If (PieceCount[PieceN] <= 1) And (I > 0) Then
        Continue;
      SetLength(Result[I].Blocks, Length(Result[I].Blocks) + 1);
      SetLength(Result[I].BlockPart, Length(Result[I].Blocks));
      SetLength(Result[I].BlockPartCount, Length(Result[I].Blocks));
      Result[I].Blocks[High(Result[I].Blocks)] := Pieces[PieceN];
      Result[I].BlockPart[High(Result[I].Blocks)] := PiecePart[PieceN];
      Result[I].BlockPartCount[High(Result[I].Blocks)] := PieceCount[PieceN];
    End;
End;

Function TranscriptPayload(Const Transcript: TMonitorTranscript): TJSONObject;
Var
  Blocks: TJSONArray;
  I, Part, PartCount: Integer;
Begin
  Result := TJSONObject.Create;
  Result.Add('turn_index', Transcript.TurnIndex);
  Result.Add('revision', Transcript.Revision);
  Result.Add('part', Transcript.Part);
  Result.Add('part_count', Transcript.PartCount);
  Result.Add('phase', Transcript.Phase);
  Result.Add('status_text', Transcript.StatusText);
  Result.Add('duration_ms', Transcript.DurationMs);
  Blocks := TJSONArray.Create;
  For I := 0 To High(Transcript.Blocks) Do
    Begin
      Part := 1;
      PartCount := 1;
      If (I <= High(Transcript.BlockPart)) And (I <= High(Transcript.BlockPartCount)) Then
        Begin
          Part := Transcript.BlockPart[I];
          PartCount := Transcript.BlockPartCount[I];
          If Part < 1 Then
            Part := 1;
          If PartCount < 1 Then
            PartCount := 1;
        End;
      Blocks.Add(MonitorBlockToJson(Transcript.Blocks[I], Part, PartCount, Transcript.Revision));
    End;
  Result.Add('blocks', Blocks);
End;

Function TryEncodeMonitorTranscript(Const Id: String; Const Transcript: TMonitorTranscript; Out Json: String): Boolean;
Var
  Payload: TJSONObject;
Begin
  Payload := TranscriptPayload(Transcript);
  Try
    Json := EncodeMonitorEnvelope(mmkTranscript, Id, Payload);
    Result := Json <> '';
  Finally
    Payload.Free;
  End;
End;

Function PackMonitorTranscript(Const Id: String; Const Transcript: TMonitorTranscript): TStringArray;
Type
  TTranscriptPiece = Record
    Block: TAssistantMonitorBlock;
    Part: Integer;
    PartCount: Integer;
  End;
  TTranscriptPieceArray = Array Of TTranscriptPiece;

  Function EncodePieces(Const Pieces: TTranscriptPieceArray; FromIndex, ToIndex, FramePart, FrameCount: Integer): String;
  Var
    Frame: TMonitorTranscript;
    I, N: Integer;
  Begin
    Frame := Transcript;
    Frame.Part := FramePart;
    Frame.PartCount := FrameCount;
    Result := '';
    N := 0;
    SetLength(Frame.Blocks, ToIndex - FromIndex + 1);
    SetLength(Frame.BlockPart, Length(Frame.Blocks));
    SetLength(Frame.BlockPartCount, Length(Frame.Blocks));
    For I := FromIndex To ToIndex Do
      Begin
        Frame.Blocks[N] := Pieces[I].Block;
        Frame.BlockPart[N] := Pieces[I].Part;
        Frame.BlockPartCount[N] := Pieces[I].PartCount;
        Inc(N);
      End;
    If Not TryEncodeMonitorTranscript(Id, Frame, Result) Then
      Result := '';
  End;

  Procedure AddPiece(Var Pieces: TTranscriptPieceArray; Const Block: TAssistantMonitorBlock; Part, PartCount: Integer);
  Begin
    SetLength(Pieces, Length(Pieces) + 1);
    Pieces[High(Pieces)].Block := Block;
    Pieces[High(Pieces)].Part := Part;
    Pieces[High(Pieces)].PartCount := PartCount;
  End;

  Function PieceFits(Const Block: TAssistantMonitorBlock; Part, PartCount: Integer): Boolean;
  Var
    Pieces: TTranscriptPieceArray;
  Begin
    SetLength(Pieces, 1);
    Pieces[0].Block := Block;
    Pieces[0].Part := Part;
    Pieces[0].PartCount := PartCount;
    Result := EncodePieces(Pieces, 0, 0, 1, 1) <> '';
  End;

  Procedure AppendFitted(Var Pieces: TTranscriptPieceArray; Block: TAssistantMonitorBlock);
  Var
    SliceAt, PartNo, First, Count: Integer;
    Slice: TAssistantMonitorBlock;
  Begin
    If PieceFits(Block, 1, 1) Then
      Begin
        AddPiece(Pieces, Block, 1, 1);
        Exit;
      End;
    If (Block.Kind = 'thinking') Or (Block.Kind = 'answer') Or (Block.Kind = 'user') Then
      Begin
        First := Length(Pieces);
        SliceAt := 1;
        PartNo := 0;
        While SliceAt <= Length(Block.Body) Do
          Begin
            Slice := Block;
            Slice.Body := Copy(Block.Body, SliceAt, 50000);
            Inc(PartNo);
            If Not PieceFits(Slice, PartNo, PartNo) Then
              Slice.Body := Copy(Slice.Body, 1, 2000);
            AddPiece(Pieces, Slice, PartNo, 0);
            Inc(SliceAt, 50000);
          End;
        Count := Length(Pieces) - First;
        For PartNo := First To High(Pieces) Do
          Pieces[PartNo].PartCount := Count;
        Exit;
      End;
    Block.Body := Copy(Block.Body, 1, 2000);
    If Not PieceFits(Block, 1, 1) Then
      Begin
        Block.Body := Copy(Block.Body, 1, 240);
        SetLength(Block.Images, 0);
      End;
    If PieceFits(Block, 1, 1) Then
      AddPiece(Pieces, Block, 1, 1);
  End;

Var
  Pieces: TTranscriptPieceArray;
  Ends: Array Of Integer;
  I, Start, Last, FrameCount: Integer;
  Json: String;
Begin
  Result := Nil;
  If TryEncodeMonitorTranscript(Id, Transcript, Json) Then
    Begin
      SetLength(Result, 1);
      Result[0] := Json;
      Exit;
    End;
  SetLength(Pieces, 0);
  For I := 0 To High(Transcript.Blocks) Do
    AppendFitted(Pieces, Transcript.Blocks[I]);
  If Length(Pieces) = 0 Then
    Exit;
  SetLength(Ends, 0);
  Start := 0;
  While Start <= High(Pieces) Do
    Begin
      Last := Start;
      While Last < High(Pieces) Do
        Begin
          If EncodePieces(Pieces, Start, Last + 1, 1, 1) = '' Then
            Break;
          Inc(Last);
        End;
      SetLength(Ends, Length(Ends) + 1);
      Ends[High(Ends)] := Last;
      Start := Last + 1;
    End;
  FrameCount := Length(Ends);
  Start := 0;
  For I := 0 To High(Ends) Do
    Begin
      Json := EncodePieces(Pieces, Start, Ends[I], I + 1, FrameCount);
      If Json <> '' Then
        Begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Json;
        End;
      Start := Ends[I] + 1;
    End;
End;

Function DecodeMonitorTranscript(Const PayloadJson: String; Out Transcript: TMonitorTranscript): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  Transcript.TurnIndex := 0;
  Transcript.Revision := 0;
  Transcript.Phase := '';
  Transcript.StatusText := '';
  Transcript.DurationMs := 0;
  Transcript.Part := 1;
  Transcript.PartCount := 1;
  SetLength(Transcript.Blocks, 0);
  SetLength(Transcript.BlockPart, 0);
  SetLength(Transcript.BlockPartCount, 0);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadInt(Obj, 'turn_index', True, Transcript.TurnIndex) And ReadInt(Obj, 'revision', True, Transcript.Revision) And
      ReadString(Obj, 'phase', True, Transcript.Phase) And ReadString(Obj, 'status_text', True, Transcript.StatusText)) Then
      Exit;
    If Not ReadInt(Obj, 'part', False, Transcript.Part) Then
      Exit;
    If Transcript.Part < 1 Then
      Transcript.Part := 1;
    If Not ReadInt(Obj, 'part_count', False, Transcript.PartCount) Then
      Exit;
    If Transcript.PartCount < 1 Then
      Transcript.PartCount := 1;
    If Not ReadInt(Obj, 'duration_ms', False, Transcript.DurationMs) Then
      Exit;
    If Transcript.DurationMs < 0 Then
      Transcript.DurationMs := 0;
    Node := Obj.Find('blocks');
    If Not (Node Is TJSONArray) Then
      Exit;
    Blocks := TJSONArray(Node);
    SetLength(Transcript.Blocks, Blocks.Count);
    SetLength(Transcript.BlockPart, Blocks.Count);
    SetLength(Transcript.BlockPartCount, Blocks.Count);
    For I := 0 To Blocks.Count - 1 Do
      Begin
        If Not (Blocks[I] Is TJSONObject) Then
          Exit;
        If Not TryMonitorBlockFromJson(TJSONObject(Blocks[I]), Transcript.Blocks[I], Truncated) Then
          Exit;
        Transcript.BlockPart[I] := 1;
        Transcript.BlockPartCount[I] := 1;
        If Not ReadInt(TJSONObject(Blocks[I]), 'part', False, Transcript.BlockPart[I]) Then
          Exit;
        If Not ReadInt(TJSONObject(Blocks[I]), 'part_count', False, Transcript.BlockPartCount[I]) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function MonitorTurnIndexRow(TurnIndex: Integer; Const Id, Mode, CreatedAt, PromptPreview, ErrorText: String): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('turn_index', TurnIndex);
  Result.Add('id', Id);
  Result.Add('mode', Mode);
  Result.Add('created_at', CreatedAt);
  Result.Add('prompt_preview', PromptPreview);
  Result.Add('error_text', ErrorText);
End;

Function LimitMonitorStoredTurns(Const Turns: TJSONArray): TJSONArray;
Var
  Kept: TJSONArray;
  StartAt, Index: Integer;
  Item: TJSONObject;
Begin
  Result := TJSONArray.Create;
  If Not Assigned(Turns) Then
    Exit;
  Kept := TJSONArray.Create;
  Try
    For Index := 0 To Turns.Count - 1 Do
      Begin
        If Not (Turns[Index] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(Turns[Index]);
        If Item.Get('live', False) Then
          Continue;
        Kept.Add(MonitorTurnIndexRow(Item.Get('turn_index', 0), Item.Get('id', ''), Item.Get('mode', ''),
          Item.Get('created_at', ''), Item.Get('prompt_preview', ''), Item.Get('error_text', '')));
      End;
    StartAt := 0;
    If Kept.Count > MonitorSnapshotStoredTurns Then
      StartAt := Kept.Count - MonitorSnapshotStoredTurns;
    For Index := StartAt To Kept.Count - 1 Do
      Result.Add(TJSONObject(TJSONObject(Kept[Index]).Clone));
  Finally
    Kept.Free;
  End;
End;

Function MonitorImageFetchBlocked(Missing, Refused: Boolean; DecodedBytes: Int64; Out Reason: String): Boolean;
Begin
  Reason := '';
  Result := True;
  If Missing Then
    Reason := 'missing'
  Else If Refused Then
    Reason := 'refused'
  Else If DecodedBytes > MonitorMaxImageFetchBytes Then
    Reason := 'too_large'
  Else
    Result := False;
End;

Function ExpectedBase64Chars(ByteCount: Integer): Integer;
Begin
  Result := ((ByteCount + 2) Div 3) * 4;
End;

Function FramedBase64(Const Raw: RawByteString): String;
Begin
  Result := EncodeMonitorImageBytes(Raw);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
End;

Function TryBuildMonitorImageParts(Const ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Out Parts: TJSONArray; Out Reason: String): Boolean;
Var
  Total, Offset, Take, Count, Index: Integer;
  Raw: RawByteString;
  Encoded: String;
  Part: TJSONObject;
Begin
  Result := False;
  Parts := Nil;
  Reason := '';
  Raw := '';
  Total := Length(Bytes);
  If MonitorImageFetchBlocked(False, False, Total, Reason) Then
    Exit;
  If Total = 0 Then
    Count := 1
  Else
    Count := (Total + MonitorMaxImagePartBytes - 1) Div MonitorMaxImagePartBytes;
  Parts := TJSONArray.Create;
  Offset := 0;
  For Index := 0 To Count - 1 Do
    Begin
      Take := MonitorMaxImagePartBytes;
      If Offset + Take > Total Then
        Take := Total - Offset;
      SetLength(Raw, Take);
      If Take > 0 Then
        Move(Bytes[Offset], Raw[1], Take);
      Encoded := FramedBase64(Raw);
      If Length(Encoded) <> ExpectedBase64Chars(Take) Then
        Begin
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      If Length(Encoded) > MonitorImagePartBase64Chars Then
        Begin
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      Part := TJSONObject.Create;
      Part.Add('image_id', ImageId);
      Part.Add('mime', Mime);
      Part.Add('width', Width);
      Part.Add('height', Height);
      Part.Add('part', Index + 1);
      Part.Add('part_count', Count);
      Part.Add('revision', Revision);
      Part.Add('bytes_base64', Encoded);
      If Length(Part.AsJSON) + MonitorImageEnvelopeBytes > MonitorMaxPayloadBytes Then
        Begin
          Part.Free;
          FreeAndNil(Parts);
          Reason := 'too_large';
          Exit;
        End;
      Parts.Add(Part);
      Inc(Offset, Take);
    End;
  Result := True;
End;

Function DecodeMonitorImageData(Const PayloadJson: String; Out Image: TMonitorImageData; Out DecodedBytes: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Raw: RawByteString;
Begin
  Result := False;
  DecodedBytes := 0;
  Image.ImageId := '';
  Image.Mime := '';
  Image.Width := 0;
  Image.Height := 0;
  Image.Part := 0;
  Image.PartCount := 0;
  Image.Revision := 0;
  Image.BytesBase64 := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadString(Obj, 'image_id', True, Image.ImageId) And ReadString(Obj, 'mime', True, Image.Mime) And
      ReadInt(Obj, 'width', True, Image.Width) And ReadInt(Obj, 'height', True, Image.Height) And
      ReadInt(Obj, 'part', True, Image.Part) And ReadInt(Obj, 'part_count', True, Image.PartCount) And
      ReadInt(Obj, 'revision', True, Image.Revision) And ReadString(Obj, 'bytes_base64', True, Image.BytesBase64)) Then
      Exit;
    Raw := DecodeMonitorImageBytes(Image.BytesBase64);
    DecodedBytes := Length(Raw);
    Result := (DecodedBytes <= MonitorMaxImagePartBytes) And (Image.Part >= 1) And (Image.PartCount >= Image.Part);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorImageUnavailable(Const Id, ImageId, Reason: String): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If Not MonitorImageUnavailableReasonIsKnown(Reason) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('image_id', ImageId);
  Payload.Add('reason', Reason);
  Result := EncodeWith(mmkImageUnavailable, Id, Payload);
End;

Function DecodeMonitorImageUnavailable(Const PayloadJson: String; Out Image: TMonitorImageUnavailable): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Image.ImageId := '';
  Image.Reason := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'image_id', True, Image.ImageId) And ReadString(Obj, 'reason', True, Image.Reason) And
      MonitorImageUnavailableReasonIsKnown(Image.Reason);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorImageGet(Const Id: String; TurnIndex: Integer; Const ImageId: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('turn_index', TurnIndex);
  Payload.Add('image_id', ImageId);
  Result := EncodeWith(mmkImageGet, Id, Payload);
End;

Function DecodeMonitorImageGet(Const PayloadJson: String; Out Image: TMonitorImageGet): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Image.TurnIndex := 0;
  Image.ImageId := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadInt(Obj, 'turn_index', True, Image.TurnIndex) And ReadString(Obj, 'image_id', True, Image.ImageId);
  Finally
    Data.Free;
  End;
End;

Function TryEncodeMonitorImageData(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer;
  Const Bytes: TBytes; Missing, Refused: Boolean; Out Messages: TStringArray; Out UnavailableReason: String): Boolean;
Var
  Parts: TJSONArray;
  I: Integer;
  Payload: TJSONObject;
  Json: String;
Begin
  Result := False;
  Messages := Nil;
  SetLength(Messages, 0);
  UnavailableReason := '';
  Parts := Nil;
  If MonitorImageFetchBlocked(Missing, Refused, Length(Bytes), UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  If Not TryBuildMonitorImageParts(ImageId, Mime, Width, Height, Revision, Bytes, Parts, UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  Try
    SetLength(Messages, Parts.Count);
    For I := 0 To Parts.Count - 1 Do
      Begin
        If Not (Parts[I] Is TJSONObject) Then
          Exit;
        Payload := TJSONObject(Parts[I]);
        Json := EncodeMonitorEnvelope(mmkImageData, Id, Payload);
        If Json = '' Then
          Begin
            SetLength(Messages, 0);
            UnavailableReason := 'too_large';
            Exit;
          End;
        Messages[I] := Json;
      End;
    UnavailableReason := '';
    Result := True;
  Finally
    Parts.Free;
  End;
End;

{ One pass into a sized buffer. A resume publishes these pages on the IDE thread.
  Result := Result + once per byte copies the whole page on every character and Lazarus never opens. }
Function EscapedByteLen(C: Char): Integer;
Begin
  Case C Of
    '"', '\', #8, #9, #10, #12, #13: Result := 2;
  Else
    If Ord(C) < 32 Then
      Result := 6
    Else
      Result := 1;
  End;
End;

Function EscapeChunkData(Const Text: String): String;
Const
  HexDigits = '0123456789ABCDEF';
Var
  Index, OutLen, At, Code: Integer;
  C: Char;
Begin
  OutLen := 0;
  For Index := 1 To Length(Text) Do
    Inc(OutLen, EscapedByteLen(Text[Index]));
  SetLength(Result, OutLen);
  At := 1;
  For Index := 1 To Length(Text) Do
    Begin
      C := Text[Index];
      Case C Of
        '"':
          Begin
            Result[At] := '\';
            Result[At + 1] := '"';
            Inc(At, 2);
          End;
        '\':
          Begin
            Result[At] := '\';
            Result[At + 1] := '\';
            Inc(At, 2);
          End;
        #8:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'b';
            Inc(At, 2);
          End;
        #9:
          Begin
            Result[At] := '\';
            Result[At + 1] := 't';
            Inc(At, 2);
          End;
        #10:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'n';
            Inc(At, 2);
          End;
        #12:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'f';
            Inc(At, 2);
          End;
        #13:
          Begin
            Result[At] := '\';
            Result[At + 1] := 'r';
            Inc(At, 2);
          End;
      Else
        If Ord(C) < 32 Then
          Begin
            Code := Ord(C);
            Result[At] := '\';
            Result[At + 1] := 'u';
            Result[At + 2] := '0';
            Result[At + 3] := '0';
            Result[At + 4] := HexDigits[(Code Div 16) + 1];
            Result[At + 5] := HexDigits[(Code Mod 16) + 1];
            Inc(At, 6);
          End
        Else
          Begin
            Result[At] := C;
            Inc(At);
          End;
      End;
    End;
End;

Function ChunkFrame(Const Id, ItemId, ItemType, Data: String; Part, PartCount: Integer): String;
Begin
  Result := '{"v":' + IntToStr(MonitorCatalogueVersion) + ',"id":"' + Id + '","type":"chunk","payload":{"item_id":"' +
    ItemId + '","part":' + IntToStr(Part) + ',"part_count":' + IntToStr(PartCount) + ',"item_type":"' + ItemType +
    '","data":"' + EscapeChunkData(Data) + '"}}';
End;

{ Bytes of one UTF-8 code point starting at Index, or 1 for a stray byte. Never zero when Index is in range. }
Function Utf8UnitLen(Const Text: String; Index: Integer): Integer;
Var
  Lead, Need, Follow: Integer;
Begin
  Result := 1;
  If (Index < 1) Or (Index > Length(Text)) Then
    Exit(0);
  Lead := Ord(Text[Index]);
  If Lead < $80 Then
    Exit;
  If (Lead And $E0) = $C0 Then
    Need := 2
  Else If (Lead And $F0) = $E0 Then
    Need := 3
  Else If (Lead And $F8) = $F0 Then
    Need := 4
  Else
    Exit;
  Follow := 1;
  While (Index + Follow <= Length(Text)) And (Follow < Need) And ((Ord(Text[Index + Follow]) And $C0) = $80) Do
    Inc(Follow);
  If Follow = Need Then
    Result := Need;
End;

{ Source bytes from Start whose escaped form fits in DataBudget, ending on a code point. }
Function ChunkSourceLen(Const Item: String; Start, DataBudget: Integer): Integer;
Var
  Index, Escaped, UnitLen, UnitEsc, Offset: Integer;
Begin
  Result := 0;
  If (DataBudget < 1) Or (Start < 1) Or (Start > Length(Item)) Then
    Exit;
  Index := Start;
  Escaped := 0;
  While Index <= Length(Item) Do
    Begin
      UnitLen := Utf8UnitLen(Item, Index);
      If UnitLen < 1 Then
        Exit;
      UnitEsc := 0;
      For Offset := 0 To UnitLen - 1 Do
        Inc(UnitEsc, EscapedByteLen(Item[Index + Offset]));
      If Escaped + UnitEsc > DataBudget Then
        Exit;
      Inc(Escaped, UnitEsc);
      Inc(Result, UnitLen);
      Inc(Index, UnitLen);
    End;
End;

Function PackMonitorBulkItem(Const ItemId, ItemType, PayloadJson: String; Out Frames: TStringArray): Boolean;
Var
  Item, BudgetId: String;
  Start, Taken, Part, Count, Overhead, DataBudget: Integer;
  Cuts: Array Of Integer;
Begin
  Result := False;
  SetLength(Frames, 0);
  If (ItemId = '') Or (ItemType = '') Or (PayloadJson = '') Or (Not MonitorMessageIdIsSafe(ItemId)) Then
    Exit;
  Item := '{"v":' + IntToStr(MonitorCatalogueVersion) + ',"id":"' + ItemId + '","type":"' + ItemType + '","payload":' +
    PayloadJson + '}';
  If Length(Item) > MonitorMaxItemBytes Then
    Exit;
  If Length(Item) <= MonitorOutboxChunkBytes Then
    Begin
      SetLength(Frames, 1);
      Frames[0] := Item;
      Exit(True);
    End;
  { Size the slices against a full-length id and four-digit part numbers so the real frame still fits.
    One walk. Searching by rebuilding each probe locked the IDE on a multi-megabyte conversation. }
  BudgetId := StringOfChar('a', MonitorMaxMessageIdChars);
  Overhead := Length(ChunkFrame(BudgetId, ItemId, ItemType, '', 9999, 9999));
  If Overhead >= MonitorOutboxChunkBytes Then
    Exit;
  DataBudget := MonitorOutboxChunkBytes - Overhead;
  SetLength(Cuts, 0);
  Start := 1;
  While Start <= Length(Item) Do
    Begin
      Taken := ChunkSourceLen(Item, Start, DataBudget);
      If Taken < 1 Then
        Exit;
      SetLength(Cuts, Length(Cuts) + 1);
      Cuts[High(Cuts)] := Taken;
      Inc(Start, Taken);
    End;
  Count := Length(Cuts);
  SetLength(Frames, Count);
  Start := 1;
  For Part := 1 To Count Do
    Begin
      Frames[Part - 1] := ChunkFrame(ItemId + '-c' + IntToStr(Part), ItemId, ItemType, Copy(Item, Start, Cuts[Part - 1]),
        Part, Count);
      If (Length(Frames[Part - 1]) > MonitorOutboxChunkBytes) Or
        (Not MonitorMessageIdIsSafe(ItemId + '-c' + IntToStr(Part))) Then
        Begin
          SetLength(Frames, 0);
          Exit;
        End;
      Inc(Start, Cuts[Part - 1]);
    End;
  Result := True;
End;

Function TryPackMonitorImage(Const Id, ImageId, Mime: String; Width, Height, Revision: Integer; Const Bytes: TBytes;
  Missing, Refused: Boolean; Out Frames: TStringArray; Out UnavailableReason: String): Boolean;
Var
  Payload: TJSONObject;
  Raw: RawByteString;
  Encoded, PayloadJson: String;
Begin
  Result := False;
  SetLength(Frames, 0);
  UnavailableReason := '';
  If MonitorImageFetchBlocked(Missing, Refused, Length(Bytes), UnavailableReason) Then
    Begin
      Result := UnavailableReason <> '';
      Exit;
    End;
  SetLength(Raw, Length(Bytes));
  If Length(Bytes) > 0 Then
    Move(Bytes[0], Raw[1], Length(Bytes));
  Encoded := FramedBase64(Raw);
  If Length(Encoded) <> ExpectedBase64Chars(Length(Bytes)) Then
    Begin
      UnavailableReason := 'too_large';
      Exit(True);
    End;
  Payload := TJSONObject.Create;
  Try
    Payload.Add('image_id', ImageId);
    Payload.Add('mime', Mime);
    Payload.Add('width', Width);
    Payload.Add('height', Height);
    Payload.Add('part', 1);
    Payload.Add('part_count', 1);
    Payload.Add('revision', Revision);
    Payload.Add('bytes_base64', Encoded);
    PayloadJson := Payload.AsJSON;
  Finally
    Payload.Free;
  End;
  If Not PackMonitorBulkItem(Id, 'image_data', PayloadJson, Frames) Then
    Begin
      UnavailableReason := 'too_large';
      Exit(True);
    End;
  UnavailableReason := '';
  Result := True;
End;

Procedure ClearPatch(Out Patch: TMonitorPatch);
Begin
  Patch.Epoch := '';
  Patch.Cursor := 0;
  Patch.TurnIndex := 0;
  Patch.TurnId := '';
  SetLength(Patch.Blocks, 0);
  SetLength(Patch.AppendOffsets, 0);
  Patch.Busy := False;
  Patch.Sending := False;
  Patch.PlanRunning := False;
  Patch.Phase := '';
  Patch.CanSend := False;
  Patch.CanSteer := False;
  Patch.CanStop := False;
  Patch.ElapsedMs := 0;
  Patch.Part := 0;
  Patch.PartCount := 0;
  Patch.HasView := False;
  Patch.Model := '';
  Patch.SignedIn := False;
  Patch.StatusText := '';
End;

Function PatchPayload(Const Patch: TMonitorPatch): TJSONObject;
Var
  Blocks: TJSONArray;
  Node: TJSONObject;
  I: Integer;
Begin
  Result := TJSONObject.Create;
  Result.Add('epoch', Patch.Epoch);
  Result.Add('cursor', Patch.Cursor);
  Result.Add('turn_index', Patch.TurnIndex);
  Result.Add('turn_id', Patch.TurnId);
  Result.Add('part', Patch.Part);
  Result.Add('part_count', Patch.PartCount);
  Result.Add('busy', Patch.Busy);
  Result.Add('sending', Patch.Sending);
  Result.Add('plan_running', Patch.PlanRunning);
  Result.Add('phase', Patch.Phase);
  Result.Add('can_send', Patch.CanSend);
  Result.Add('can_steer', Patch.CanSteer);
  Result.Add('can_stop', Patch.CanStop);
  Result.Add('elapsed_ms', Patch.ElapsedMs);
  Result.Add('model', Patch.Model);
  Result.Add('signed_in', Patch.SignedIn);
  Result.Add('status_text', Patch.StatusText);
  Blocks := TJSONArray.Create;
  For I := 0 To High(Patch.Blocks) Do
    Begin
      Node := MonitorBlockToJson(Patch.Blocks[I], 1, 1, 0);
      If (I <= High(Patch.AppendOffsets)) And (Patch.AppendOffsets[I] >= 0) Then
        Node.Add('offset', Patch.AppendOffsets[I]);
      Blocks.Add(Node);
    End;
  Result.Add('blocks', Blocks);
End;

Function ReadCommandIds(Obj: TJSONObject; Out Ids: TStringArray): Boolean;
Var
  Node: TJSONData;
  Arr: TJSONArray;
  Index: Integer;
Begin
  Result := True;
  Ids := Nil;
  SetLength(Ids, 0);
  If Obj.IndexOfName('commands') < 0 Then
    Exit;
  Node := Obj.Find('commands');
  If Not (Node Is TJSONArray) Then
    Exit(False);
  Arr := TJSONArray(Node);
  SetLength(Ids, Arr.Count);
  For Index := 0 To Arr.Count - 1 Do
    Begin
      If Arr.Items[Index].JSONType <> jtString Then
        Exit(False);
      Ids[Index] := Arr.Items[Index].AsString;
      If Not MonitorMessageIdIsSafe(Ids[Index]) Then
        Exit(False);
    End;
End;

Function EncodeMonitorResume(Const Id, Epoch: String; Cursor: Int64): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('epoch', Epoch);
  Payload.Add('cursor', Cursor);
  Result := EncodeWith(mmkResume, Id, Payload);
End;

Function DecodeMonitorResume(Const PayloadJson: String; Out ResumeMsg: TMonitorResume): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ResumeMsg.Epoch := '';
  ResumeMsg.Cursor := 0;
  SetLength(ResumeMsg.Commands, 0);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'epoch', True, ResumeMsg.Epoch) And ReadInt64(Obj, 'cursor', ResumeMsg.Cursor) And
      ReadCommandIds(Obj, ResumeMsg.Commands);
  Finally
    Data.Free;
  End;
End;

Function EncodeMonitorCommandState(Const Id, Ref, State, Reason: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('ref', Ref);
  Payload.Add('state', State);
  If Reason <> '' Then
    Payload.Add('reason', Reason);
  Result := EncodeWith(mmkCommandState, Id, Payload);
End;

Function EncodeMonitorCommandStates(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;
Var
  Payload, Item: TJSONObject;
  States: TJSONArray;
  Index: Integer;
Begin
  Payload := TJSONObject.Create;
  States := TJSONArray.Create;
  For Index := 0 To High(Replies) Do
    Begin
      Item := TJSONObject.Create;
      Item.Add('ref', Replies[Index].Ref);
      Item.Add('state', Replies[Index].State);
      If Replies[Index].Reason <> '' Then
        Item.Add('reason', Replies[Index].Reason);
      States.Add(Item);
    End;
  Payload.Add('states', States);
  Result := EncodeWith(mmkCommandStates, Id, Payload);
End;

Function EncodeMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): String;
Begin
  Result := EncodeWith(mmkPatch, Id, PatchPayload(Patch));
End;

Function MonitorPatchPayloadJson(Const Patch: TMonitorPatch): String;
Var
  Payload: TJSONObject;
Begin
  Payload := PatchPayload(Patch);
  Try
    Result := Payload.AsJSON;
  Finally
    Payload.Free;
  End;
End;

Function DecodeMonitorPatch(Const PayloadJson: String; Out Patch: TMonitorPatch): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  ClearPatch(Patch);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadString(Obj, 'epoch', True, Patch.Epoch) And ReadInt64(Obj, 'cursor', Patch.Cursor) And
      ReadInt(Obj, 'turn_index', True, Patch.TurnIndex) And ReadString(Obj, 'turn_id', True, Patch.TurnId) And
      ReadInt(Obj, 'part', True, Patch.Part) And ReadInt(Obj, 'part_count', True, Patch.PartCount) And
      ReadBool(Obj, 'busy', True, Patch.Busy) And ReadBool(Obj, 'sending', True, Patch.Sending) And
      ReadBool(Obj, 'plan_running', True, Patch.PlanRunning) And ReadString(Obj, 'phase', True, Patch.Phase) And
      ReadBool(Obj, 'can_send', True, Patch.CanSend) And ReadBool(Obj, 'can_steer', True, Patch.CanSteer) And
      ReadBool(Obj, 'can_stop', True, Patch.CanStop) And ReadInt(Obj, 'elapsed_ms', True, Patch.ElapsedMs)) Then
      Exit;
    { Older ring records omit the status bar. A missing field must not wipe a model the phone already has. }
    Patch.HasView := Assigned(Obj.Find('model')) Or Assigned(Obj.Find('signed_in'));
    If Patch.HasView And (Not (ReadString(Obj, 'model', True, Patch.Model) And
      ReadBool(Obj, 'signed_in', True, Patch.SignedIn) And ReadString(Obj, 'status_text', True, Patch.StatusText))) Then
      Exit;
    { A v1 transcript has revision and status_text, not epoch. Missing epoch already failed above. }
    If (Patch.Part < 1) Or (Patch.PartCount < 1) Or (Patch.Part > Patch.PartCount) Then
      Exit;
    Node := Obj.Find('blocks');
    If Not (Node Is TJSONArray) Then
      Exit;
    Blocks := TJSONArray(Node);
    SetLength(Patch.Blocks, Blocks.Count);
    For I := 0 To Blocks.Count - 1 Do
      Begin
        If Not (Blocks[I] Is TJSONObject) Then
          Exit;
        If Not TryMonitorBlockFromJson(TJSONObject(Blocks[I]), Patch.Blocks[I], Truncated) Then
          Exit;
        SetLength(Patch.AppendOffsets, I + 1);
        If Assigned(TJSONObject(Blocks[I]).Find('offset')) And (TJSONObject(Blocks[I]).Find('offset').JSONType = jtNumber) Then
          Patch.AppendOffsets[I] := TJSONObject(Blocks[I]).Find('offset').AsInteger
        Else
          Patch.AppendOffsets[I] := -1;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function SelectDirtyMonitorBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;

  Function FaceSame(Const Left, Right: TAssistantMonitorBlock): Boolean;
  Begin
    Result := (Left.Title = Right.Title) And (Left.Body = Right.Body) And (Left.Running = Right.Running) And
      (Left.Ok = Right.Ok);
  End;

Var
  I, J, N: Integer;
  Seen: Boolean;
Begin
  SetLength(Result, 0);
  If FirstPatch Then
    Begin
      SetLength(Result, Length(Current));
      For I := 0 To High(Current) Do
        Result[I] := Current[I];
      Exit;
    End;
  N := 0;
  For I := 0 To High(Current) Do
    Begin
      Seen := False;
      For J := 0 To High(Previous) Do
        If Previous[J].BlockId = Current[I].BlockId Then
          Begin
            Seen := True;
            If Not FaceSame(Previous[J], Current[I]) Then
              Begin
                SetLength(Result, N + 1);
                Result[N] := Current[I];
                Inc(N);
              End;
            Break;
          End;
      If Not Seen Then
        Begin
          SetLength(Result, N + 1);
          Result[N] := Current[I];
          Inc(N);
        End;
    End;
End;

Function PackMonitorPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Type
  TPatchBlockArray = Array Of TAssistantMonitorBlock;

  Function Utf8Prefix(Const Text: String; MaxBytes: Integer): String;
  Var
    Count: Integer;
  Begin
    If (MaxBytes < 1) Or (Text = '') Then
      Exit('');
    If Length(Text) <= MaxBytes Then
      Exit(Text);
    Count := MaxBytes;
    While (Count > 0) And ((Ord(Text[Count]) And $C0) = $80) Do
      Dec(Count);
    If Count < 1 Then
      Count := 1;
    Result := Copy(Text, 1, Count);
  End;

  Function EncodeBlocks(Const Blocks: Array Of TAssistantMonitorBlock; Part, PartCount: Integer): String;
  Var
    Trial: TMonitorPatch;
    I: Integer;
  Begin
    Trial := Patch;
    Trial.Part := Part;
    Trial.PartCount := PartCount;
    { A split piece is a body fragment, not an append suffix. }
    SetLength(Trial.AppendOffsets, 0);
    SetLength(Trial.Blocks, Length(Blocks));
    For I := 0 To High(Blocks) Do
      Trial.Blocks[I] := Blocks[I];
    Result := EncodeMonitorPatch(Id, Trial);
  End;

  Function PieceFits(Const Block: TAssistantMonitorBlock): Boolean;
  Begin
    Result := EncodeBlocks([Block], 1, 1) <> '';
  End;

  Procedure AddPiece(Var Pieces: TPatchBlockArray; Const Block: TAssistantMonitorBlock);
  Begin
    SetLength(Pieces, Length(Pieces) + 1);
    Pieces[High(Pieces)] := Block;
  End;

  Function SplitBlock(Const Block: TAssistantMonitorBlock; Var Pieces: TPatchBlockArray): Boolean;
  Var
    Rest, Prefix: String;
    Trial: TAssistantMonitorBlock;
    LowN, HighN, Mid, Best: Integer;
  Begin
    Result := False;
    Rest := Block.Body;
    Repeat
      Trial := Block;
      Trial.Body := Rest;
      If PieceFits(Trial) Then
        Begin
          AddPiece(Pieces, Trial);
          Exit(True);
        End;
      If Rest = '' Then
        Exit;
      LowN := 1;
      HighN := Length(Rest) - 1;
      Best := 0;
      While LowN <= HighN Do
        Begin
          Mid := (LowN + HighN) Div 2;
          Prefix := Utf8Prefix(Rest, Mid);
          Trial.Body := Prefix;
          If PieceFits(Trial) Then
            Begin
              Best := Length(Prefix);
              LowN := Best + 1;
            End
          Else
            HighN := Mid - 1;
        End;
      If Best < 1 Then
        Exit;
      Trial.Body := Copy(Rest, 1, Best);
      AddPiece(Pieces, Trial);
      Delete(Rest, 1, Best);
    Until Rest = '';
    Result := True;
  End;

Var
  Whole: TMonitorPatch;
  Pieces, Group: TPatchBlockArray;
  Starts, Ends: Array Of Integer;
  I, StartAt, LastFit, PartNo, PartCount: Integer;
  Json: String;
Begin
  Result := Nil;
  SetLength(Result, 0);
  Pieces := Nil;
  Group := Nil;
  Whole := Patch;
  If Whole.Part < 1 Then
    Whole.Part := 1;
  If Whole.PartCount < 1 Then
    Whole.PartCount := 1;
  Json := EncodeMonitorPatch(Id, Whole);
  If Json <> '' Then
    Begin
      SetLength(Result, 1);
      Result[0] := Json;
      Exit;
    End;
  SetLength(Pieces, 0);
  For I := 0 To High(Patch.Blocks) Do
    If Not SplitBlock(Patch.Blocks[I], Pieces) Then
      Exit;
  If Length(Pieces) = 0 Then
    Exit;
  SetLength(Starts, 0);
  SetLength(Ends, 0);
  StartAt := 0;
  While StartAt <= High(Pieces) Do
    Begin
      LastFit := StartAt - 1;
      For I := StartAt To High(Pieces) Do
        Begin
          SetLength(Group, I - StartAt + 1);
          Group[I - StartAt] := Pieces[I];
          If EncodeBlocks(Group, 1, 1) = '' Then
            Break;
          LastFit := I;
        End;
      If LastFit < StartAt Then
        Exit;
      SetLength(Starts, Length(Starts) + 1);
      SetLength(Ends, Length(Starts));
      Starts[High(Starts)] := StartAt;
      Ends[High(Ends)] := LastFit;
      StartAt := LastFit + 1;
    End;
  PartCount := Length(Starts);
  SetLength(Result, PartCount);
  For PartNo := 0 To PartCount - 1 Do
    Begin
      SetLength(Group, Ends[PartNo] - Starts[PartNo] + 1);
      For I := Starts[PartNo] To Ends[PartNo] Do
        Group[I - Starts[PartNo]] := Pieces[I];
      Json := EncodeBlocks(Group, PartNo + 1, PartCount);
      If Json = '' Then
        Begin
          SetLength(Result, 0);
          Exit;
        End;
      Result[PartNo] := Json;
    End;
End;

Function TryAssembleMonitorPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Var
  I, PartCount, Index: Integer;
  Message: TMonitorMessage;
  ErrorText: String;
  Decoded: TMonitorPatch;
  Slots: TMonitorPatchArray;
  Have: Array Of Boolean;
  Epoch: String;
  Cursor: Int64;

  Procedure AppendBlock(Const Block: TAssistantMonitorBlock);
  Begin
    If (Length(Patch.Blocks) > 0) And (Patch.Blocks[High(Patch.Blocks)].BlockId = Block.BlockId) And
      (Patch.Blocks[High(Patch.Blocks)].Kind = Block.Kind) Then
      Patch.Blocks[High(Patch.Blocks)].Body := Patch.Blocks[High(Patch.Blocks)].Body + Block.Body
    Else
      Begin
        SetLength(Patch.Blocks, Length(Patch.Blocks) + 1);
        Patch.Blocks[High(Patch.Blocks)] := Block;
      End;
  End;

Begin
  Result := False;
  ClearPatch(Patch);
  If Length(Messages) = 0 Then
    Exit;
  If Not TryDecodeMonitorEnvelope(Messages[0], Message, ErrorText) Or (Message.Kind <> mmkPatch) Then
    Exit;
  If Not DecodeMonitorPatch(Message.PayloadJson, Decoded) Then
    Exit;
  PartCount := Decoded.PartCount;
  Epoch := Decoded.Epoch;
  Cursor := Decoded.Cursor;
  If (PartCount < 1) Or (Length(Messages) <> PartCount) Then
    Exit;
  SetLength(Slots, PartCount);
  SetLength(Have, PartCount);
  For I := 0 To High(Messages) Do
    Begin
      If Not TryDecodeMonitorEnvelope(Messages[I], Message, ErrorText) Or (Message.Kind <> mmkPatch) Then
        Exit;
      If Not DecodeMonitorPatch(Message.PayloadJson, Decoded) Then
        Exit;
      If (Decoded.PartCount <> PartCount) Or (Decoded.Epoch <> Epoch) Or (Decoded.Cursor <> Cursor) Then
        Exit;
      If (Decoded.Part < 1) Or (Decoded.Part > PartCount) Or Have[Decoded.Part - 1] Then
        Exit;
      Slots[Decoded.Part - 1] := Decoded;
      Have[Decoded.Part - 1] := True;
    End;
  For I := 0 To PartCount - 1 Do
    If Not Have[I] Then
      Exit;
  Patch := Slots[0];
  SetLength(Patch.Blocks, 0);
  For I := 0 To PartCount - 1 Do
    For Index := 0 To High(Slots[I].Blocks) Do
      AppendBlock(Slots[I].Blocks[Index]);
  Patch.Part := 1;
  Patch.PartCount := 1;
  Result := True;
End;

Function EncodeMonitorCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Var
  Payload: TJSONObject;
  Patches: TJSONArray;
  SnapJson, ErrorText: String;
  Message: TMonitorMessage;
  Data: TJSONData;
  SnapObj: TJSONObject;
  I: Integer;
  ModeText: String;
Begin
  Result := '';
  If Catchup.Mode = mcmSnapshot Then
    ModeText := 'snapshot'
  Else If Catchup.Mode = mcmEvents Then
    ModeText := 'events'
  Else
    Exit;
  Payload := TJSONObject.Create;
  Data := Nil;
  Try
    Payload.Add('mode', ModeText);
    Payload.Add('epoch', Catchup.Epoch);
    Payload.Add('cursor', Catchup.Cursor);
    Payload.Add('conversation_id', Catchup.ConversationId);
    Payload.Add('project_root', Catchup.ProjectRoot);
    Payload.Add('title', Catchup.Title);
    If Catchup.Mode = mcmSnapshot Then
      Begin
        If Not Catchup.HasSnapshot Then
          Exit;
        SnapJson := EncodeMonitorSnapshot('catchup-snap', Catchup.Snapshot);
        If Not TryDecodeMonitorEnvelope(SnapJson, Message, ErrorText) Then
          Exit;
        If Not ParseObject(Message.PayloadJson, Data, SnapObj) Then
          Exit;
        Payload.Add('snapshot', SnapObj);
        Data := Nil;
      End
    Else
      Begin
        Patches := TJSONArray.Create;
        For I := 0 To High(Catchup.Patches) Do
          Patches.Add(PatchPayload(Catchup.Patches[I]));
        Payload.Add('patches', Patches);
      End;
    Result := EncodeMonitorEnvelope(mmkCatchup, Id, Payload);
  Finally
    Data.Free;
    Payload.Free;
  End;
End;

Function EncodeResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Var
  Catchup: TMonitorCatchup;
Begin
  Catchup := Default(TMonitorCatchup);
  Catchup.Mode := mcmSnapshot;
  Catchup.Epoch := Epoch;
  Catchup.Cursor := Cursor;
  Catchup.ConversationId := ConversationId;
  Catchup.ProjectRoot := ProjectRoot;
  Catchup.Title := Title;
  Catchup.Snapshot := Snapshot;
  Catchup.HasSnapshot := True;
  SetLength(Catchup.Patches, 0);
  Result := EncodeMonitorCatchup(RefId, Catchup);
End;

Function DecodeMonitorCatchup(Const PayloadJson: String; Out Catchup: TMonitorCatchup): Boolean;
Var
  Data, SnapData: TJSONData;
  Obj, SnapObj: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  ModeText: String;
  I: Integer;
Begin
  Result := False;
  Catchup.Mode := mcmUnknown;
  Catchup.Epoch := '';
  Catchup.Cursor := 0;
  Catchup.ConversationId := '';
  Catchup.ProjectRoot := '';
  Catchup.Title := '';
  Catchup.HasSnapshot := False;
  SetLength(Catchup.Patches, 0);
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  SnapData := Nil;
  Try
    If Not (ReadString(Obj, 'mode', True, ModeText) And ReadString(Obj, 'epoch', True, Catchup.Epoch) And
      ReadInt64(Obj, 'cursor', Catchup.Cursor) And ReadString(Obj, 'conversation_id', True, Catchup.ConversationId) And
      ReadString(Obj, 'project_root', True, Catchup.ProjectRoot) And ReadString(Obj, 'title', True, Catchup.Title)) Then
      Exit;
    If ModeText = 'snapshot' Then
      Catchup.Mode := mcmSnapshot
    Else If ModeText = 'events' Then
      Catchup.Mode := mcmEvents
    Else
      Exit;
    If Catchup.Mode = mcmSnapshot Then
      Begin
        Node := Obj.Find('snapshot');
        If Not (Node Is TJSONObject) Then
          Exit;
        If Not DecodeMonitorSnapshot(TJSONObject(Node).AsJSON, Catchup.Snapshot) Then
          Exit;
        Catchup.HasSnapshot := True;
        Result := True;
      End
    Else
      Begin
        Node := Obj.Find('patches');
        If Not (Node Is TJSONArray) Then
          Exit;
        Arr := TJSONArray(Node);
        SetLength(Catchup.Patches, Arr.Count);
        For I := 0 To Arr.Count - 1 Do
          Begin
            If Not (Arr[I] Is TJSONObject) Then
              Exit;
            If Not DecodeMonitorPatch(TJSONObject(Arr[I]).AsJSON, Catchup.Patches[I]) Then
              Exit;
          End;
        Result := True;
      End;
  Finally
    SnapData.Free;
    Data.Free;
  End;
End;

Function EncodeMonitorConversationClosed(Const Id, Epoch: String; Cursor: Int64;
  Const ConversationId, Title: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('epoch', Epoch);
  Payload.Add('cursor', Cursor);
  Payload.Add('conversation_id', ConversationId);
  Payload.Add('title', Title);
  Result := EncodeWith(mmkConversationClosed, Id, Payload);
End;

Function DecodeMonitorConversationClosed(Const PayloadJson: String; Out Closed: TMonitorConversationClosed): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Closed.Epoch := '';
  Closed.Cursor := 0;
  Closed.ConversationId := '';
  Closed.Title := '';
  If Not ParseObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadString(Obj, 'epoch', True, Closed.Epoch) And ReadInt64(Obj, 'cursor', Closed.Cursor) And
      ReadString(Obj, 'conversation_id', True, Closed.ConversationId) And ReadString(Obj, 'title', True, Closed.Title);
  Finally
    Data.Free;
  End;
End;

End.
