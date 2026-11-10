Unit AssistantMonitorCommands;

{ Command codecs for the monitor catalogue (c) 2026 Michell Computing.

  Handshake, send, mode, plan commands, task commands, resume, and command-state
  frames. Framing stays in AssistantMonitorCodec. This unit does not read the
  assistant form. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, fpjson, AssistantMonitorCodec;

Function EncodeCommandHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Function DecodeCommandHello(Const PayloadJson: TMonitorPayload; Out Hello: TMonitorHello): Boolean;
Function EncodeCommandPair(Const Id, Code, Fingerprint: String): String;
Function DecodeCommandPair(Const PayloadJson: TMonitorPayload; Out Pair: TMonitorPair): Boolean;
Function EncodeCommandPairOk(Const Id, ClientId, SessionToken: String): String;
Function DecodeCommandPairOk(Const PayloadJson: TMonitorPayload; Out PairOk: TMonitorPairOk): Boolean;
Function EncodeCommandHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Function DecodeCommandHelloOk(Const PayloadJson: TMonitorPayload; Out HelloOk: TMonitorHelloOk): Boolean;
Function EncodeCommandAuth(Const Id, ClientId, Hmac: String): String;
Function DecodeCommandAuth(Const PayloadJson: TMonitorPayload; Out Auth: TMonitorAuth): Boolean;
Function EncodeCommandRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Function DecodeCommandRejected(Const PayloadJson: TMonitorPayload; Out Rejected: TMonitorRejected): Boolean;
Function EncodeCommandBye(Const Id, Reason: String): String;
Function DecodeCommandBye(Const PayloadJson: TMonitorPayload; Out Bye: TMonitorBye): Boolean;
{ SaveFirst is the phone's Yes to the save question: the desktop saves its unsaved edits, then starts the turn. }
Function TryEncodeCommandSend(Const Id, Text: String; Out Json, ErrorJson: String; SaveFirst: Boolean = False): Boolean;
Function TryEncodeCommandSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function DecodeCommandText(Const PayloadJson: TMonitorPayload; Out Text: String): Boolean;
{ Optional save_first on send, run_plan and run_task. Missing, or not a boolean, is False. }
Function DecodeCommandSaveFirst(Const PayloadJson: TMonitorPayload): Boolean;
Function EncodeCommandRunPlan(Const Id: String; SaveFirst: Boolean): String;
Function EncodeCommandEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Function EncodeCommandSetMode(Const Id, Mode: String): String;
Function DecodeCommandSetMode(Const PayloadJson: TMonitorPayload; Out Mode: String): Boolean;
Function EncodeCommandMode(Const Id, Mode: String; Locked: Boolean): String;
Function DecodeCommandMode(Const PayloadJson: TMonitorPayload; Out ModeMessage: TMonitorModeMessage): Boolean;
Function EncodeCommandTurnRequest(Const Id: String; TurnIndex: Integer): String;
Function DecodeCommandTurnRequest(Const PayloadJson: TMonitorPayload; Out TurnIndex: Integer): Boolean;

Function EncodeCommandSelectConversation(Const Id, ArchiveId: String): String;
Function DecodeCommandSelectConversation(Const PayloadJson: TMonitorPayload; Out ArchiveId: String): Boolean;
Function EncodeCommandSetModel(Const Id, ModelId: String): String;
Function DecodeCommandSetModel(Const PayloadJson: TMonitorPayload; Out ModelId: String): Boolean;
Function EncodeCommandSetReasoning(Const Id, Level: String): String;
Function DecodeCommandSetReasoning(Const PayloadJson: TMonitorPayload; Out Level: String): Boolean;
Function EncodeCommandSetPermissions(Const Id, Approval: String): String;
Function DecodeCommandSetPermissions(Const PayloadJson: TMonitorPayload; Out Approval: String): Boolean;
Function EncodeCommandPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Function DecodeCommandPath(Const PayloadJson: TMonitorPayload; Out Path: String): Boolean;
Function EncodeCommandNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Function DecodeCommandNewPlan(Const PayloadJson: TMonitorPayload; Out Plan: TMonitorPathMessage): Boolean;
Function EncodeCommandWorkOnPlan(Const Id: String; Index: Integer): String;
Function DecodeCommandWorkOnPlan(Const PayloadJson: TMonitorPayload; Out Index: Integer): Boolean;
Function EncodeCommandTask(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String; SaveFirst: Boolean = False): String;
Function DecodeCommandTask(Const PayloadJson: TMonitorPayload; Out Command: TMonitorTaskCommand): Boolean;
Function EncodeCommandInsertResult(Const Id, Text: String): String;
Function EncodeCommandTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Function DecodeCommandTicks(Const PayloadJson: TMonitorPayload; Out Ticks: TMonitorTicks): Boolean;
Function ReadCommandIds(Obj: TJSONObject; Out Ids: TStringArray): Boolean;
Function EncodeCommandResume(Const Id, Epoch: String; Cursor: Int64): String;
Function DecodeCommandResume(Const PayloadJson: TMonitorPayload; Out ResumeMsg: TMonitorResume): Boolean;
Function EncodeCommandStateFrame(Const Id, Ref, State, Reason: String; Const DoneText: String = ''): String;
Function EncodeCommandStateFrames(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;

Implementation

Function EncodeCommandHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_name', ClientName);
  Payload.Add('client_version', ClientVersion);
  If ClientId <> '' Then
    Payload.Add('client_id', ClientId);
  Result := EncodeMonitorWith(mmkHello, Id, Payload);
End;

Function DecodeCommandHello(Const PayloadJson: TMonitorPayload; Out Hello: TMonitorHello): Boolean;
Var
  Data: TJSONData;
  Payload: TJSONObject;
Begin
  Result := False;
  Hello.ClientName := '';
  Hello.ClientVersion := '';
  Hello.ClientId := '';
  Hello.HasClientId := False;
  If Not ParseMonitorObject(PayloadJson, Data, Payload) Then
    Exit;
  Try
    Hello.HasClientId := Assigned(Payload.Find('client_id'));
    Result := ReadMonitorString(Payload, 'client_name', True, Hello.ClientName) And
      ReadMonitorString(Payload, 'client_version', True, Hello.ClientVersion);
    If Result And Hello.HasClientId Then
      Result := ReadMonitorString(Payload, 'client_id', True, Hello.ClientId);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandPair(Const Id, Code, Fingerprint: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('code', Code);
  Payload.Add('fingerprint', Fingerprint);
  Result := EncodeMonitorWith(mmkPair, Id, Payload);
End;

Function DecodeCommandPair(Const PayloadJson: TMonitorPayload; Out Pair: TMonitorPair): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Pair.Code := '';
  Pair.Fingerprint := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'code', True, Pair.Code) And ReadMonitorString(Obj, 'fingerprint', True, Pair.Fingerprint);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandPairOk(Const Id, ClientId, SessionToken: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_id', ClientId);
  Payload.Add('session_token', SessionToken);
  Result := EncodeMonitorWith(mmkPairOk, Id, Payload);
End;

Function DecodeCommandPairOk(Const PayloadJson: TMonitorPayload; Out PairOk: TMonitorPairOk): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  PairOk.ClientId := '';
  PairOk.SessionToken := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'client_id', True, PairOk.ClientId) And
      ReadMonitorString(Obj, 'session_token', True, PairOk.SessionToken);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
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
  Result := EncodeMonitorWith(mmkHelloOk, Id, Payload);
End;

Function DecodeCommandHelloOk(Const PayloadJson: TMonitorPayload; Out HelloOk: TMonitorHelloOk): Boolean;
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
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'nonce', True, HelloOk.Nonce) And ReadMonitorString(Obj, 'server_name', True, HelloOk.ServerName) And
      ReadMonitorString(Obj, 'epoch', True, HelloOk.Epoch) And ReadMonitorInt64(Obj, 'cursor', HelloOk.Cursor) And
      ReadMonitorString(Obj, 'conversation_id', True, HelloOk.ConversationId) And
      ReadMonitorString(Obj, 'project_root', True, HelloOk.ProjectRoot) And ReadMonitorString(Obj, 'title', True, HelloOk.Title);
    If Result Then
      Begin
        If Not ReadMonitorString(Obj, 'host_id', False, HelloOk.HostId) Then
          Result := False
        Else If (HelloOk.HostId <> '') And (Not MonitorHostIdIsValid(HelloOk.HostId)) Then
          Result := False;
      End;
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandAuth(Const Id, ClientId, Hmac: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('client_id', ClientId);
  Payload.Add('hmac', Hmac);
  Result := EncodeMonitorWith(mmkAuth, Id, Payload);
End;

Function DecodeCommandAuth(Const PayloadJson: TMonitorPayload; Out Auth: TMonitorAuth): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Auth.ClientId := '';
  Auth.Hmac := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'client_id', True, Auth.ClientId) And ReadMonitorString(Obj, 'hmac', True, Auth.Hmac);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
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
  Result := EncodeMonitorWith(mmkRejected, Id, Payload);
End;

Function DecodeCommandRejected(Const PayloadJson: TMonitorPayload; Out Rejected: TMonitorRejected): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Rejected.Reason := '';
  Rejected.HostVersion := 0;
  Rejected.ClientVersion := 0;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'reason', True, Rejected.Reason) And
      ReadMonitorInt(Obj, 'host_version', True, Rejected.HostVersion) And
      ReadMonitorInt(Obj, 'client_version', True, Rejected.ClientVersion) And
      MonitorRejectedReasonIsKnown(Rejected.Reason);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandBye(Const Id, Reason: String): String;
Begin
  Result := EncodeMonitorOneString(mmkBye, Id, 'reason', Reason);
End;

Function DecodeCommandBye(Const PayloadJson: TMonitorPayload; Out Bye: TMonitorBye): Boolean;
Begin
  Bye.Reason := '';
  Result := DecodeMonitorOneString(PayloadJson, 'reason', Bye.Reason);
End;

Function TryEncodeCommandLimited(Kind: TMonitorMessageKind; Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := False;
  Json := '';
  ErrorJson := '';
  If Length(Text) > MonitorMaxSendChars Then
    Begin
      ErrorJson := EncodeMonitorError(Id, MonitorPayloadTooLargeReason, MonitorPayloadTooLargeMessage, Id);
      Exit;
    End;
  Json := EncodeMonitorOneString(Kind, Id, 'text', Text);
  Result := Json <> '';
End;

Function TryEncodeCommandSend(Const Id, Text: String; Out Json, ErrorJson: String; SaveFirst: Boolean): Boolean;
Var
  Payload: TJSONObject;
Begin
  If Not SaveFirst Then
    Exit(TryEncodeCommandLimited(mmkSend, Id, Text, Json, ErrorJson));
  Result := False;
  Json := '';
  ErrorJson := '';
  If Length(Text) > MonitorMaxSendChars Then
    Begin
      ErrorJson := EncodeMonitorError(Id, MonitorPayloadTooLargeReason, MonitorPayloadTooLargeMessage, Id);
      Exit;
    End;
  Payload := TJSONObject.Create;
  Payload.Add('text', Text);
  Payload.Add('save_first', True);
  Json := EncodeMonitorWith(mmkSend, Id, Payload);
  Result := Json <> '';
End;

Function DecodeCommandSaveFirst(Const PayloadJson: TMonitorPayload): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadMonitorBool(Obj, 'save_first', False, Result) Then
      Result := False;
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandRunPlan(Const Id: String; SaveFirst: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  If Not SaveFirst Then
    Exit(EncodeCommandEmpty(mmkRunPlan, Id));
  Payload := TJSONObject.Create;
  Payload.Add('save_first', True);
  Result := EncodeMonitorWith(mmkRunPlan, Id, Payload);
End;

Function TryEncodeCommandSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeCommandLimited(mmkSteer, Id, Text, Json, ErrorJson);
End;

Function DecodeCommandText(Const PayloadJson: TMonitorPayload; Out Text: String): Boolean;
Begin
  Result := DecodeMonitorOneString(PayloadJson, 'text', Text) And (Length(Text) <= MonitorMaxSendChars);
End;

Function EncodeCommandEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Begin
  Result := EncodeMonitorEnvelope(Kind, Id, Nil);
End;

Function EncodeCommandSetMode(Const Id, Mode: String): String;
Begin
  Result := '';
  If Not MonitorModeIsKnown(Mode) Then
    Exit;
  Result := EncodeMonitorOneString(mmkSetMode, Id, 'mode', Mode);
End;

Function DecodeCommandSetMode(Const PayloadJson: TMonitorPayload; Out Mode: String): Boolean;
Begin
  Result := DecodeMonitorOneString(PayloadJson, 'mode', Mode) And MonitorModeIsKnown(Mode);
End;

Function EncodeCommandMode(Const Id, Mode: String; Locked: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('mode', Mode);
  Payload.Add('locked', Locked);
  Result := EncodeMonitorWith(mmkMode, Id, Payload);
End;

Function DecodeCommandMode(Const PayloadJson: TMonitorPayload; Out ModeMessage: TMonitorModeMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ModeMessage.Mode := '';
  ModeMessage.Locked := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'mode', True, ModeMessage.Mode) And ReadMonitorBool(Obj, 'locked', True, ModeMessage.Locked);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandTurnRequest(Const Id: String; TurnIndex: Integer): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('turn_index', TurnIndex);
  Result := EncodeMonitorWith(mmkTurn, Id, Payload);
End;

Function DecodeCommandTurnRequest(Const PayloadJson: TMonitorPayload; Out TurnIndex: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  TurnIndex := 0;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorInt(Obj, 'turn_index', True, TurnIndex);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandSelectConversation(Const Id, ArchiveId: String): String;
Begin
  Result := EncodeMonitorOneString(mmkSelectConversation, Id, 'id', ArchiveId);
End;

Function DecodeCommandSelectConversation(Const PayloadJson: TMonitorPayload; Out ArchiveId: String): Boolean;
Begin
  Result := DecodeMonitorOneString(PayloadJson, 'id', ArchiveId);
End;

Function EncodeCommandSetModel(Const Id, ModelId: String): String;
Begin
  Result := EncodeMonitorOneString(mmkSetModel, Id, 'model', ModelId);
End;

Function DecodeCommandSetModel(Const PayloadJson: TMonitorPayload; Out ModelId: String): Boolean;
Begin
  Result := DecodeMonitorOneString(PayloadJson, 'model', ModelId);
End;

Function EncodeCommandSetReasoning(Const Id, Level: String): String;
Begin
  Result := EncodeMonitorOneString(mmkSetReasoning, Id, 'level', Level);
End;

Function DecodeCommandSetReasoning(Const PayloadJson: TMonitorPayload; Out Level: String): Boolean;
Begin
  { Missing level is a decode failure. An empty level is model default, not that failure. }
  Result := DecodeMonitorOneString(PayloadJson, 'level', Level);
End;

Function EncodeCommandSetPermissions(Const Id, Approval: String): String;
Begin
  Result := EncodeMonitorOneString(mmkSetPermissions, Id, 'approval', Approval);
End;

Function DecodeCommandSetPermissions(Const PayloadJson: TMonitorPayload; Out Approval: String): Boolean;
Begin
  { Missing approval is a decode failure. It is not ask. }
  Result := DecodeMonitorOneString(PayloadJson, 'approval', Approval);
End;

Function EncodeCommandPath(Kind: TMonitorMessageKind; Const Id, Path: String): String;
Begin
  Result := '';
  If (Kind <> mmkSelectPlan) And (Kind <> mmkSelectTarget) Then
    Exit;
  Result := EncodeMonitorOneString(Kind, Id, 'path', Path);
End;

Function DecodeCommandPath(Const PayloadJson: TMonitorPayload; Out Path: String): Boolean;
Begin
  Result := DecodeMonitorOneString(PayloadJson, 'path', Path);
End;

Function EncodeCommandNewPlan(Const Id, Title: String; HasTitle: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  If HasTitle Then
    Payload.Add('title', Title);
  Result := EncodeMonitorWith(mmkNewPlan, Id, Payload);
End;

Function DecodeCommandNewPlan(Const PayloadJson: TMonitorPayload; Out Plan: TMonitorPathMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Plan.Path := '';
  Plan.Title := '';
  Plan.HasTitle := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Plan.HasTitle := Assigned(Obj.Find('title'));
    Result := True;
    If Plan.HasTitle Then
      Result := ReadMonitorString(Obj, 'title', True, Plan.Title);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandWorkOnPlan(Const Id: String; Index: Integer): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('index', Index);
  Result := EncodeMonitorWith(mmkWorkOnPlan, Id, Payload);
End;

Function DecodeCommandWorkOnPlan(Const PayloadJson: TMonitorPayload; Out Index: Integer): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Index := 0;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorInt(Obj, 'index', True, Index);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandTask(Kind: TMonitorMessageKind; Const Id, TaskId, Note: String; SaveFirst: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If (Kind <> mmkRunTask) And (Kind <> mmkInsertTask) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('id', TaskId);
  Payload.Add('note', Note);
  { Insert only fills the composer; it starts nothing, so it has nothing to save first. }
  If SaveFirst And (Kind = mmkRunTask) Then
    Payload.Add('save_first', True);
  Result := EncodeMonitorWith(Kind, Id, Payload);
End;

Function DecodeCommandTask(Const PayloadJson: TMonitorPayload; Out Command: TMonitorTaskCommand): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Command.Id := '';
  Command.Note := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'id', True, Command.Id) And ReadMonitorString(Obj, 'note', True, Command.Note);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandInsertResult(Const Id, Text: String): String;
Begin
  Result := EncodeMonitorOneString(mmkInsertResult, Id, 'text', Text);
End;

Function EncodeCommandTicks(Kind: TMonitorMessageKind; Const Id: String; Ticks: Int64): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If (Kind <> mmkPing) And (Kind <> mmkPong) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('ticks', Ticks);
  Result := EncodeMonitorWith(Kind, Id, Payload);
End;

Function DecodeCommandTicks(Const PayloadJson: TMonitorPayload; Out Ticks: TMonitorTicks): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Ticks.Ticks := 0;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorInt64(Obj, 'ticks', Ticks.Ticks);
  Finally
    Data.Free;
  End;
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

Function EncodeCommandResume(Const Id, Epoch: String; Cursor: Int64): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('epoch', Epoch);
  Payload.Add('cursor', Cursor);
  Result := EncodeMonitorWith(mmkResume, Id, Payload);
End;

Function DecodeCommandResume(Const PayloadJson: TMonitorPayload; Out ResumeMsg: TMonitorResume): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  HasCursor, HasEpoch: Boolean;
Begin
  Result := False;
  ResumeMsg.Epoch := '';
  ResumeMsg.Cursor := 0;
  ResumeMsg.ConversationId := '';
  SetLength(ResumeMsg.Commands, 0);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    HasCursor := ReadMonitorInt64(Obj, 'cursor', ResumeMsg.Cursor);
    If Not HasCursor Then
      HasCursor := ReadMonitorInt64(Obj, 'seq', ResumeMsg.Cursor);
    HasEpoch := Obj.IndexOfName('epoch') >= 0;
    If HasEpoch Then
      ReadMonitorString(Obj, 'epoch', False, ResumeMsg.Epoch)
    Else If Obj.IndexOfName('stream_id') >= 0 Then
      Begin
        ReadMonitorString(Obj, 'stream_id', False, ResumeMsg.Epoch);
        HasEpoch := True;
      End;
    ReadMonitorString(Obj, 'conversation_id', False, ResumeMsg.ConversationId);
    Result := HasEpoch And HasCursor And ReadCommandIds(Obj, ResumeMsg.Commands);
  Finally
    Data.Free;
  End;
End;

Function EncodeCommandStateFrame(Const Id, Ref, State, Reason: String; Const DoneText: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('ref', Ref);
  Payload.Add('state', State);
  If Reason <> '' Then
    Payload.Add('reason', Reason);
  If DoneText <> '' Then
    Payload.Add('text', DoneText);
  Result := EncodeMonitorWith(mmkCommandState, Id, Payload);
End;

Function EncodeCommandStateFrames(Const Id: String; Const Replies: Array Of TMonitorCommandStateReply): String;
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
      If Replies[Index].Text <> '' Then
        Item.Add('text', Replies[Index].Text);
      States.Add(Item);
    End;
  Payload.Add('states', States);
  Result := EncodeMonitorWith(mmkCommandStates, Id, Payload);
End;


End.
