Unit AssistantMonitorCommands;

{ Command codecs for the monitor catalogue (c) 2026 Michell Computing.

  Handshake, send, and command-state frames. Framing stays in
  AssistantMonitorCodec. This unit does not read the assistant form. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, fpjson, AssistantMonitorCodec;

Function EncodeCommandHello(Const Id, ClientName, ClientVersion, ClientId: String): String;
Function DecodeCommandHello(Const PayloadJson: String; Out Hello: TMonitorHello): Boolean;
Function EncodeCommandPair(Const Id, Code, Fingerprint: String): String;
Function DecodeCommandPair(Const PayloadJson: String; Out Pair: TMonitorPair): Boolean;
Function EncodeCommandPairOk(Const Id, ClientId, SessionToken: String): String;
Function DecodeCommandPairOk(Const PayloadJson: String; Out PairOk: TMonitorPairOk): Boolean;
Function EncodeCommandHelloOk(Const Id: String; Const HelloOk: TMonitorHelloOk): String;
Function DecodeCommandHelloOk(Const PayloadJson: String; Out HelloOk: TMonitorHelloOk): Boolean;
Function EncodeCommandAuth(Const Id, ClientId, Hmac: String): String;
Function DecodeCommandAuth(Const PayloadJson: String; Out Auth: TMonitorAuth): Boolean;
Function EncodeCommandRejected(Const Id, Reason: String; HostVersion, ClientVersion: Integer): String;
Function DecodeCommandRejected(Const PayloadJson: String; Out Rejected: TMonitorRejected): Boolean;
Function EncodeCommandBye(Const Id, Reason: String): String;
Function DecodeCommandBye(Const PayloadJson: String; Out Bye: TMonitorBye): Boolean;
Function TryEncodeCommandSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function TryEncodeCommandSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Function DecodeCommandText(Const PayloadJson: String; Out Text: String): Boolean;
Function EncodeCommandEmpty(Kind: TMonitorMessageKind; Const Id: String): String;
Function EncodeCommandSetMode(Const Id, Mode: String): String;
Function DecodeCommandSetMode(Const PayloadJson: String; Out Mode: String): Boolean;
Function EncodeCommandMode(Const Id, Mode: String; Locked: Boolean): String;
Function DecodeCommandMode(Const PayloadJson: String; Out ModeMessage: TMonitorModeMessage): Boolean;
Function EncodeCommandTurnRequest(Const Id: String; TurnIndex: Integer): String;
Function DecodeCommandTurnRequest(Const PayloadJson: String; Out TurnIndex: Integer): Boolean;

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

Function DecodeCommandHello(Const PayloadJson: String; Out Hello: TMonitorHello): Boolean;
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

Function DecodeCommandPair(Const PayloadJson: String; Out Pair: TMonitorPair): Boolean;
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

Function DecodeCommandPairOk(Const PayloadJson: String; Out PairOk: TMonitorPairOk): Boolean;
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

Function DecodeCommandHelloOk(Const PayloadJson: String; Out HelloOk: TMonitorHelloOk): Boolean;
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

Function DecodeCommandAuth(Const PayloadJson: String; Out Auth: TMonitorAuth): Boolean;
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

Function DecodeCommandRejected(Const PayloadJson: String; Out Rejected: TMonitorRejected): Boolean;
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

Function DecodeCommandBye(Const PayloadJson: String; Out Bye: TMonitorBye): Boolean;
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

Function TryEncodeCommandSend(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeCommandLimited(mmkSend, Id, Text, Json, ErrorJson);
End;

Function TryEncodeCommandSteer(Const Id, Text: String; Out Json, ErrorJson: String): Boolean;
Begin
  Result := TryEncodeCommandLimited(mmkSteer, Id, Text, Json, ErrorJson);
End;

Function DecodeCommandText(Const PayloadJson: String; Out Text: String): Boolean;
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

Function DecodeCommandSetMode(Const PayloadJson: String; Out Mode: String): Boolean;
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

Function DecodeCommandMode(Const PayloadJson: String; Out ModeMessage: TMonitorModeMessage): Boolean;
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

Function DecodeCommandTurnRequest(Const PayloadJson: String; Out TurnIndex: Integer): Boolean;
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

End.
