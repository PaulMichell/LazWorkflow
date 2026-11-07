Unit AssistantMonitorSettings;

{ The only writer of the monitor settings section (c) 2026 Michell Computing.

  Certificate paths are derived, not stored. Client tokens are monitor session
  tokens. The pair code is not a field. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorSettingsSection = 'monitor';
  MonitorBindAllAddress = '0.0.0.0';

Type
  TMonitorClientRecord = Record
    Id: String;
    Name: String;
    { Monitor session token. Not an OAuth access token or refresh token. }
    Token: String;
    Fingerprint: String;
    PairedAt: String;
  End;
  TMonitorClientArray = Array Of TMonitorClientRecord;

  TMonitorSettings = Record
    Enabled: Boolean;
    Port: Integer;
    BindAddress: String;
    BindAll: Boolean;
    RemoteApproval: Boolean;
    { 32 lowercase hex. Stable across certificate renewal. Empty until ensured. }
    HostId: String;
    Clients: TMonitorClientArray;
  End;

Function DefaultMonitorSettings: TMonitorSettings;
Function LoadMonitorSettings(Out Settings: TMonitorSettings; Out ErrorText: String): Boolean;
/// Removes the client from an in-memory list; persistence remains the caller's responsibility.
Procedure RevokeMonitorClient(Var Clients: TMonitorClientArray; Const ClientId: String); Overload;
/// Revokes a stored client when no session is running.
Function RevokeMonitorClient(Const ClientId: String; Out ErrorText: String): Boolean; Overload;
Function MonitorSettingsRevision: LongInt;
Function SaveMonitorSettings(Const Settings: TMonitorSettings; Out ErrorText: String): Boolean;
{ Mints host_id once and keeps it in the monitor settings. }
Function EnsureMonitorHostId(Out HostId, ErrorText: String): Boolean;
Function MonitorCertificateFile: String;
Function MonitorKeyFile: String;
{ bind_all true returns 0.0.0.0. Otherwise one IPv4 address is required. }
Function ResolveMonitorBind(Const Settings: TMonitorSettings; Out Address, ErrorText: String): Boolean;

Implementation

Uses
  fpjson, fphashutils, WorkflowSettings, AssistantMonitorCodec;

Var
  SettingsRevision: LongInt = 0;

Function MonitorSettingsRevision: LongInt;
Begin
  Result := InterlockedCompareExchange(SettingsRevision, 0, 0);
End;

Procedure RevokeMonitorClient(Var Clients: TMonitorClientArray; Const ClientId: String);
Var
  I, Kept: Integer;
Begin
  Kept := 0;
  For I := 0 To High(Clients) Do
    If Clients[I].Id <> ClientId Then
      Begin
        Clients[Kept] := Clients[I];
        Inc(Kept);
      End;
  SetLength(Clients, Kept);
End;

Function RevokeMonitorClient(Const ClientId: String; Out ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
Begin
  Result := LoadMonitorSettings(Settings, ErrorText);
  If Not Result Then
    Exit;
  RevokeMonitorClient(Settings.Clients, ClientId);
  Result := SaveMonitorSettings(Settings, ErrorText);
End;

Function IsIPv4Address(Const Text: String): Boolean;
Var
  Rest, Part: String;
  Dot, I, Value: Integer;
Begin
  Result := False;
  Rest := Text;
  If Rest = '' Then
    Exit;
  For I := 1 To 4 Do
    Begin
      Dot := Pos('.', Rest);
      If I < 4 Then
        Begin
          If Dot < 2 Then
            Exit;
          Part := Copy(Rest, 1, Dot - 1);
          Delete(Rest, 1, Dot);
        End
      Else
        Begin
          If (Dot > 0) Or (Rest = '') Then
            Exit;
          Part := Rest;
        End;
      If (Part = '') Or (Length(Part) > 3) Then
        Exit;
      Value := StrToIntDef(Part, -1);
      If (Value < 0) Or (Value > 255) Or (IntToStr(Value) <> Part) Then
        Exit;
    End;
  Result := True;
End;

Function DefaultMonitorSettings: TMonitorSettings;
Begin
  Result.Enabled := False;
  Result.Port := MonitorListenPort;
  Result.BindAddress := '';
  Result.BindAll := False;
  Result.RemoteApproval := False;
  Result.HostId := '';
  SetLength(Result.Clients, 0);
End;

Function ReadClients(Node: TJSONData; Out Clients: TMonitorClientArray; Out ErrorText: String): Boolean;
Var
  Arr: TJSONArray;
  Item: TJSONObject;
  I, Kept: Integer;
Begin
  Result := False;
  ErrorText := '';
  Clients := Nil;
  SetLength(Clients, 0);
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Begin
      ErrorText := 'Monitor clients must be an array.';
      Exit;
    End;
  Arr := TJSONArray(Node);
  SetLength(Clients, Arr.Count);
  Kept := 0;
  For I := 0 To Arr.Count - 1 Do
    Begin
      If Not (Arr[I] Is TJSONObject) Then
        Begin
          ErrorText := 'A monitor client must be an object.';
          Exit;
        End;
      Item := TJSONObject(Arr[I]);
      Clients[Kept].Id := Item.Get('id', '');
      Clients[Kept].Name := Item.Get('name', '');
      Clients[Kept].Token := Item.Get('token', '');
      Clients[Kept].Fingerprint := Item.Get('fingerprint', '');
      Clients[Kept].PairedAt := Item.Get('paired_at', '');
      If Clients[Kept].Id = '' Then
        Begin
          ErrorText := 'A monitor client needs an id.';
          Exit;
        End;
      Inc(Kept);
    End;
  SetLength(Clients, Kept);
  Result := True;
End;

Function LoadMonitorSettings(Out Settings: TMonitorSettings; Out ErrorText: String): Boolean;
Var
  Section: TJSONObject;
  PortNode: TJSONData;
Begin
  Result := False;
  ErrorText := '';
  Settings := DefaultMonitorSettings;
  Section := ReadWorkflowSection(MonitorSettingsSection);
  If Not Assigned(Section) Then
    Begin
      Result := True;
      Exit;
    End;
  Try
    If Assigned(Section.Find('enabled')) And (Section.Find('enabled').JSONType <> jtBoolean) Then
      Begin
        ErrorText := 'Monitor enabled must be a boolean.';
        Exit;
      End;
    Settings.Enabled := Section.Get('enabled', False);
    PortNode := Section.Find('port');
    If Not Assigned(PortNode) Then
      Settings.Port := MonitorListenPort
    Else If PortNode.JSONType <> jtNumber Then
      Begin
        ErrorText := 'Monitor port must be a number.';
        Exit;
      End
    Else
      Begin
        Settings.Port := PortNode.AsInteger;
        If (Settings.Port < 1) Or (Settings.Port > 65535) Then
          Begin
            ErrorText := 'Monitor port is out of range.';
            Exit;
          End;
      End;
    If Assigned(Section.Find('bind_address')) And (Section.Find('bind_address').JSONType <> jtString) Then
      Begin
        ErrorText := 'Monitor bind address must be a string.';
        Exit;
      End;
    Settings.BindAddress := Section.Get('bind_address', '');
    If Assigned(Section.Find('bind_all')) And (Section.Find('bind_all').JSONType <> jtBoolean) Then
      Begin
        ErrorText := 'Monitor bind all must be a boolean.';
        Exit;
      End;
    Settings.BindAll := Section.Get('bind_all', False);
    If Assigned(Section.Find('remote_approval')) And (Section.Find('remote_approval').JSONType <> jtBoolean) Then
      Begin
        ErrorText := 'Monitor remote approval must be a boolean.';
        Exit;
      End;
    Settings.RemoteApproval := Section.Get('remote_approval', False);
    If Assigned(Section.Find('host_id')) And (Section.Find('host_id').JSONType <> jtString) Then
      Begin
        ErrorText := 'Monitor host id must be a string.';
        Exit;
      End;
    Settings.HostId := LowerCase(Section.Get('host_id', ''));
    If (Settings.HostId <> '') And (Not MonitorHostIdIsValid(Settings.HostId)) Then
      Begin
        ErrorText := 'Monitor host id is not valid.';
        Exit;
      End;
    If Not ReadClients(Section.Find('clients'), Settings.Clients, ErrorText) Then
      Exit;
    Result := True;
  Finally
    Section.Free;
  End;
End;

Function StoredHostId: String;
Var
  Section: TJSONObject;
Begin
  Result := '';
  Section := ReadWorkflowSection(MonitorSettingsSection);
  If Not Assigned(Section) Then
    Exit;
  Try
    If Assigned(Section.Find('host_id')) And (Section.Find('host_id').JSONType = jtString) Then
      Result := LowerCase(Section.Get('host_id', ''));
  Finally
    Section.Free;
  End;
  If Not MonitorHostIdIsValid(Result) Then
    Result := '';
End;

Function NewMonitorHostId: String;
Var
  Bytes: TBytes;
  Hex: AnsiString;
  Guid: TGuid;
  Index: Integer;
  C: Char;
Begin
  Result := '';
  Bytes := Nil;
  SetLength(Bytes, 16);
  If (Length(Bytes) = 16) And CryptoGetRandomBytes(@Bytes[0], 16) Then
    Begin
      Hex := BytesToHexStr(Bytes);
      Result := LowerCase(String(Hex));
      If MonitorHostIdIsValid(Result) Then
        Exit;
    End;
  If CreateGUID(Guid) <> 0 Then
    Exit;
  Result := LowerCase(GUIDToString(Guid));
  Index := 1;
  While Index <= Length(Result) Do
    Begin
      C := Result[Index];
      If ((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'f')) Then
        Inc(Index)
      Else
        Delete(Result, Index, 1);
    End;
  If Not MonitorHostIdIsValid(Result) Then
    Result := '';
End;

Function SaveMonitorSettings(Const Settings: TMonitorSettings; Out ErrorText: String): Boolean;
Var
  Section, Client: TJSONObject;
  Clients: TJSONArray;
  I: Integer;
  KeptHostId: String;
Begin
  Result := False;
  ErrorText := '';
  Section := TJSONObject.Create;
  Try
    Section.Add('enabled', Settings.Enabled);
    Section.Add('port', Settings.Port);
    Section.Add('bind_address', Settings.BindAddress);
    Section.Add('bind_all', Settings.BindAll);
    Section.Add('remote_approval', Settings.RemoteApproval);
    KeptHostId := Settings.HostId;
    If Not MonitorHostIdIsValid(KeptHostId) Then
      KeptHostId := StoredHostId;
    If MonitorHostIdIsValid(KeptHostId) Then
      Section.Add('host_id', KeptHostId);
    Clients := TJSONArray.Create;
    Section.Add('clients', Clients);
    For I := 0 To High(Settings.Clients) Do
      Begin
        Client := TJSONObject.Create;
        Client.Add('id', Settings.Clients[I].Id);
        Client.Add('name', Settings.Clients[I].Name);
        Client.Add('token', Settings.Clients[I].Token);
        Client.Add('fingerprint', Settings.Clients[I].Fingerprint);
        Client.Add('paired_at', Settings.Clients[I].PairedAt);
        Clients.Add(Client);
      End;
    Result := WriteWorkflowSection(MonitorSettingsSection, Section, ErrorText);
    If Result Then
      InterlockedIncrement(SettingsRevision);
  Finally
    Section.Free;
  End;
End;

Function EnsureMonitorHostId(Out HostId, ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
Begin
  Result := False;
  HostId := '';
  ErrorText := '';
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  If MonitorHostIdIsValid(Settings.HostId) Then
    Begin
      HostId := Settings.HostId;
      Result := True;
      Exit;
    End;
  Settings.HostId := NewMonitorHostId;
  If Not MonitorHostIdIsValid(Settings.HostId) Then
    Begin
      ErrorText := 'Could not mint the monitor host id.';
      Exit;
    End;
  If Not SaveMonitorSettings(Settings, ErrorText) Then
    Exit;
  HostId := Settings.HostId;
  Result := True;
End;

Function MonitorCertificateFile: String;
Begin
  Result := WorkflowSettingsDirectory + 'assistant-monitor' + PathDelim + 'host.crt';
End;

Function MonitorKeyFile: String;
Begin
  Result := WorkflowSettingsDirectory + 'assistant-monitor' + PathDelim + 'host.key';
End;

Function ResolveMonitorBind(Const Settings: TMonitorSettings; Out Address, ErrorText: String): Boolean;
Begin
  Result := False;
  Address := '';
  ErrorText := '';
  If Settings.BindAll Then
    Begin
      Address := MonitorBindAllAddress;
      Result := True;
      Exit;
    End;
  If Not IsIPv4Address(Settings.BindAddress) Then
    Begin
      ErrorText := 'One IPv4 address is required.';
      Exit;
    End;
  Address := Settings.BindAddress;
  Result := True;
End;

End.
