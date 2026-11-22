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
  Classes, SysUtils;

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
    { False lets any peer that reaches the listener pair without a code. A missing key loads as True. }
    RequirePairCode: Boolean;
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
{ bind_all true returns 0.0.0.0. Otherwise one IPv4 address is required.
  A saved address that exists only on a virtual adapter is not the LAN endpoint. }
Function ResolveMonitorBind(Const Settings: TMonitorSettings; Out Address, ErrorText: String): Boolean;
{ IPv4 address on the default-route interface, so another machine on the LAN can reach it. }
Function MonitorPreferredBindAddress: String;
{ False when Address is assigned only to a virtual adapter and a LAN address exists.
  An address that is not currently assigned stays true, so opening the dialog does not rewrite it. }
Function MonitorBindAddressReachesLan(Const Address: String): Boolean;
{ Every IPv4 address on the host, including loopback. Caller frees the list. }
Function MonitorInterfaceAddresses: TStringList;

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
  Result.RequirePairCode := True;
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
    If Assigned(Section.Find('require_pair_code')) And (Section.Find('require_pair_code').JSONType <> jtBoolean) Then
      Begin
        ErrorText := 'Monitor require pair code must be a boolean.';
        Exit;
      End;
    Settings.RequirePairCode := Section.Get('require_pair_code', True);
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
    Section.Add('require_pair_code', Settings.RequirePairCode);
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

Const
  EndpointAfInet = 2;
  {$IFDEF WINDOWS}
  EndpointBufferOverflow = 111;
  EndpointSkipAnycast = $0002;
  EndpointSkipMulticast = $0004;
  EndpointSkipDns = $0008;
  ForwardRowBytes = 56;
  {$ENDIF}

Type
  TMonitorEndpoint = Record
    Address: String;
    Name: String;
    IfIndex: Cardinal;
    OnDefaultRoute: Boolean;
    VirtualAdapter: Boolean;
  End;
  TMonitorEndpointArray = Array Of TMonitorEndpoint;

{$IFDEF UNIX}
Type
  PMonitorSocketIn = ^TMonitorSocketIn;
  TMonitorSocketIn = Packed Record
    {$IF DEFINED(DARWIN) OR DEFINED(BSD)}
    Len: Byte;
    Family: Byte;
    {$ELSE}
    Family: Word;
    {$ENDIF}
    Port: Word;
    Address: Array[0..3] Of Byte;
    Zero: Array[0..7] Of Byte;
  End;
  PMonitorIfAddrs = ^TMonitorIfAddrs;
  TMonitorIfAddrs = Record
    Next: PMonitorIfAddrs;
    Name: PAnsiChar;
    Flags: Cardinal;
    {$IFDEF CPU64}
    FlagPad: Cardinal;
    {$ENDIF}
    Address: PMonitorSocketIn;
    Netmask: Pointer;
    Broadcast: Pointer;
    Data: Pointer;
  End;

Function getifaddrs(Out List: PMonitorIfAddrs): Integer; Cdecl; External 'c';
Procedure freeifaddrs(List: PMonitorIfAddrs); Cdecl; External 'c';
{$ENDIF}

{$IFDEF WINDOWS}
Type
  PEndpointAdapter = ^TEndpointAdapter;
  TEndpointAdapter = Packed Record
    Length: LongWord;
    IfIndex: LongWord;
    Next: PEndpointAdapter;
    AdapterName: PAnsiChar;
    FirstUnicast: Pointer;
    FirstAnycast: Pointer;
    FirstMulticast: Pointer;
    FirstDns: Pointer;
    DnsSuffix: PWideChar;
    Description: PWideChar;
    FriendlyName: PWideChar;
  End;
  PEndpointUnicast = ^TEndpointUnicast;
  TEndpointUnicast = Packed Record
    Length: LongWord;
    Flags: LongWord;
    Next: PEndpointUnicast;
    SockAddr: PByte;
    SockLen: Integer;
  End;

Function GetAdaptersAddresses(Family, Flags: Cardinal; Reserved: Pointer; Addresses: PEndpointAdapter;
  Var Size: Cardinal): Cardinal; StdCall; External 'iphlpapi.dll' Name 'GetAdaptersAddresses';
Function GetIpForwardTable(Table: Pointer; Var Size: Cardinal; Order: Boolean): Cardinal; StdCall;
  External 'iphlpapi.dll' Name 'GetIpForwardTable';
{$ENDIF}

Function IPv4Text(Const Address: Array Of Byte): String;
Begin
  Result := IntToStr(Address[0]) + '.' + IntToStr(Address[1]) + '.' + IntToStr(Address[2]) + '.' + IntToStr(Address[3]);
End;

Function IsLoopbackAddress(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 4) = '127.';
End;

Function IsLinkLocalAddress(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 8) = '169.254.';
End;

Function IsPrivate10(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 3) = '10.';
End;

Function IsPrivate172(Const Address: String): Boolean;
Var
  Dot, Second: Integer;
Begin
  Result := False;
  If Copy(Address, 1, 4) <> '172.' Then
    Exit;
  Dot := Pos('.', Copy(Address, 5, MaxInt));
  If Dot < 2 Then
    Exit;
  Second := StrToIntDef(Copy(Address, 5, Dot - 1), -1);
  Result := (Second >= 16) And (Second <= 31);
End;

Function IsPrivate192(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 8) = '192.168.';
End;

Function AdapterIsVirtual(Const Name, Description: String): Boolean;
Var
  Text: String;
Begin
  Text := LowerCase(Name + ' ' + Description);
  Result := (Pos('hyper-v', Text) > 0) Or (Pos('vethernet', Text) > 0) Or (Pos('wsl', Text) > 0) Or
    (Pos('docker', Text) > 0) Or (Pos('virtualbox', Text) > 0) Or (Pos('vmware', Text) > 0) Or
    (Pos('bluetooth', Text) > 0) Or (Pos('loopback', Text) > 0) Or (Pos('tunnel', Text) > 0) Or
    (Pos('veth', Text) > 0) Or (Pos('virbr', Text) > 0) Or (Pos('vmnet', Text) > 0) Or
    (Pos('utun', Text) > 0) Or (Pos('awdl', Text) > 0);
End;

Procedure AddEndpoint(Var Endpoints: TMonitorEndpointArray; Const Address, Name, Description: String; IfIndex: Cardinal;
  OnDefaultRoute: Boolean);
Var
  Index: Integer;
Begin
  If Address = '' Then
    Exit;
  Index := Length(Endpoints);
  SetLength(Endpoints, Index + 1);
  Endpoints[Index].Address := Address;
  Endpoints[Index].Name := Name;
  Endpoints[Index].IfIndex := IfIndex;
  Endpoints[Index].OnDefaultRoute := OnDefaultRoute;
  Endpoints[Index].VirtualAdapter := AdapterIsVirtual(Name, Description) Or IsLoopbackAddress(Address);
End;

{$IFDEF WINDOWS}
Function DefaultRouteIfIndex: Cardinal;
Var
  Size, Status, Count, I, Metric, BestMetric: Cardinal;
  Table, Row: PByte;
Begin
  Result := 0;
  BestMetric := High(Cardinal);
  Size := 0;
  GetIpForwardTable(Nil, Size, False);
  If Size = 0 Then
    Exit;
  GetMem(Table, Size);
  Try
    Status := GetIpForwardTable(Table, Size, False);
    If Status <> 0 Then
      Exit;
    Count := PCardinal(Table)^;
    For I := 0 To Count - 1 Do
      Begin
        Row := Table + SizeOf(Cardinal) + I * ForwardRowBytes;
        If (PLongWord(Row)^ <> 0) Or (PLongWord(Row + 4)^ <> 0) Then
          Continue;
        Metric := PLongWord(Row + 36)^;
        If (Result = 0) Or (Metric < BestMetric) Then
          Begin
            Result := PLongWord(Row + 16)^;
            BestMetric := Metric;
          End;
      End;
  Finally
    FreeMem(Table);
  End;
End;

Function WideText(Value: PWideChar): String;
Begin
  If Value = Nil Then
    Result := ''
  Else
    Result := String(Value);
End;
{$ENDIF}

{$IFDEF UNIX}
Function NextRouteField(Var Line: String): String;
Var
  Index: Integer;
Begin
  While (Line <> '') And (Line[1] <= ' ') Do
    Delete(Line, 1, 1);
  Index := 1;
  While (Index <= Length(Line)) And (Line[Index] > ' ') Do
    Inc(Index);
  Result := Copy(Line, 1, Index - 1);
  Delete(Line, 1, Index - 1);
End;

Function DefaultRouteName: String;
Var
  Routes: TStringList;
  I, BestMetric, Metric: Integer;
  Line, Iface, Destination, Mask, MetricText: String;
Begin
  Result := '';
  BestMetric := MaxInt;
  If Not FileExists('/proc/net/route') Then
    Exit;
  Routes := TStringList.Create;
  Try
    Routes.LoadFromFile('/proc/net/route');
    For I := 1 To Routes.Count - 1 Do
      Begin
        Line := Routes[I];
        Iface := NextRouteField(Line);
        Destination := NextRouteField(Line);
        NextRouteField(Line);
        NextRouteField(Line);
        NextRouteField(Line);
        NextRouteField(Line);
        MetricText := NextRouteField(Line);
        Mask := NextRouteField(Line);
        If (Destination <> '00000000') Or (Mask <> '00000000') Then
          Continue;
        Metric := StrToIntDef(MetricText, MaxInt);
        If (Result = '') Or (Metric < BestMetric) Then
          Begin
            Result := Iface;
            BestMetric := Metric;
          End;
      End;
  Finally
    Routes.Free;
  End;
End;
{$ENDIF}

Procedure CollectEndpoints(Var Endpoints: TMonitorEndpointArray);
{$IFDEF UNIX}
Var
  List, Cursor: PMonitorIfAddrs;
  RouteName: String;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  Size, Status, RouteIf: Cardinal;
  Buffer: PEndpointAdapter;
  Adapter: PEndpointAdapter;
  Unicast: PEndpointUnicast;
  Name, Description: String;
{$ENDIF}
Begin
  SetLength(Endpoints, 0);
{$IFDEF UNIX}
  RouteName := DefaultRouteName;
  List := Nil;
  If getifaddrs(List) = 0 Then
    Try
      Cursor := List;
      While Assigned(Cursor) Do
        Begin
          If Assigned(Cursor^.Address) And (Cursor^.Address^.Family = EndpointAfInet) Then
            AddEndpoint(Endpoints, IPv4Text(Cursor^.Address^.Address), String(Cursor^.Name), '', 0,
              (RouteName <> '') And (String(Cursor^.Name) = RouteName));
          Cursor := Cursor^.Next;
        End;
    Finally
      freeifaddrs(List);
    End;
{$ENDIF}
{$IFDEF WINDOWS}
  RouteIf := DefaultRouteIfIndex;
  Size := 0;
  Buffer := Nil;
  Status := GetAdaptersAddresses(EndpointAfInet, EndpointSkipAnycast Or EndpointSkipMulticast Or EndpointSkipDns, Nil, Nil, Size);
  If (Status = EndpointBufferOverflow) And (Size > 0) Then
    Begin
      GetMem(Buffer, Size);
      Try
        Status := GetAdaptersAddresses(EndpointAfInet, EndpointSkipAnycast Or EndpointSkipMulticast Or EndpointSkipDns, Nil,
          Buffer, Size);
        If Status = 0 Then
          Begin
            Adapter := Buffer;
            While Assigned(Adapter) Do
              Begin
                Name := WideText(Adapter^.FriendlyName);
                Description := WideText(Adapter^.Description);
                Unicast := Adapter^.FirstUnicast;
                While Assigned(Unicast) Do
                  Begin
                    If Assigned(Unicast^.SockAddr) And (PWord(Unicast^.SockAddr)^ = EndpointAfInet) Then
                      AddEndpoint(Endpoints,
                        IPv4Text([Unicast^.SockAddr[4], Unicast^.SockAddr[5], Unicast^.SockAddr[6], Unicast^.SockAddr[7]]),
                        Name, Description, Adapter^.IfIndex, (RouteIf <> 0) And (Adapter^.IfIndex = RouteIf));
                    Unicast := Unicast^.Next;
                  End;
                Adapter := Adapter^.Next;
              End;
          End;
      Finally
        FreeMem(Buffer);
      End;
    End;
{$ENDIF}
End;

Function EndpointKind(Const Address: String): Integer;
Begin
  If IsPrivate192(Address) Then
    Result := 0
  Else If IsPrivate10(Address) Then
    Result := 1
  Else If IsPrivate172(Address) Then
    Result := 2
  Else If Not IsLinkLocalAddress(Address) And Not IsLoopbackAddress(Address) Then
    Result := 3
  Else
    Result := 4;
End;

Function ChooseEndpoint(Const Endpoints: TMonitorEndpointArray; OnRoute, SkipVirtual: Boolean; Kind: Integer): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 0 To High(Endpoints) Do
    If (Endpoints[I].OnDefaultRoute = OnRoute) And (Not SkipVirtual Or Not Endpoints[I].VirtualAdapter) And
      (EndpointKind(Endpoints[I].Address) = Kind) Then
      Exit(Endpoints[I].Address);
End;

Function MonitorPreferredBindAddress: String;
Var
  Endpoints: TMonitorEndpointArray;
  HasRoute: Boolean;
  I, Kind: Integer;
Begin
  Result := '';
  SetLength(Endpoints, 0);
  CollectEndpoints(Endpoints);
  HasRoute := False;
  For I := 0 To High(Endpoints) Do
    If Endpoints[I].OnDefaultRoute And Not Endpoints[I].VirtualAdapter And (EndpointKind(Endpoints[I].Address) < 4) Then
      HasRoute := True;
  If HasRoute Then
    For Kind := 0 To 3 Do
      Begin
        Result := ChooseEndpoint(Endpoints, True, True, Kind);
        If Result <> '' Then
          Exit;
      End;
  For Kind := 0 To 3 Do
    Begin
      Result := ChooseEndpoint(Endpoints, False, True, Kind);
      If Result <> '' Then
        Exit;
    End;
End;

Function MonitorBindAddressReachesLan(Const Address: String): Boolean;
Var
  Endpoints: TMonitorEndpointArray;
  I: Integer;
  SeenVirtual, SeenOther: Boolean;
Begin
  Result := False;
  If Address = '' Then
    Exit;
  SetLength(Endpoints, 0);
  CollectEndpoints(Endpoints);
  If MonitorPreferredBindAddress = '' Then
    Exit(True);
  SeenVirtual := False;
  SeenOther := False;
  For I := 0 To High(Endpoints) Do
    If Endpoints[I].Address = Address Then
      If Endpoints[I].VirtualAdapter Then
        SeenVirtual := True
      Else
        SeenOther := True;
  { Not assigned on this host. Keep it so a stored choice is not rewritten by opening the dialog. }
  If Not SeenVirtual And Not SeenOther Then
    Exit(True);
  Result := SeenOther;
End;

Function MonitorInterfaceAddresses: TStringList;
Var
  Endpoints: TMonitorEndpointArray;
  I: Integer;
Begin
  Result := TStringList.Create;
  SetLength(Endpoints, 0);
  CollectEndpoints(Endpoints);
  For I := 0 To High(Endpoints) Do
    Result.Add(Endpoints[I].Address);
End;

Function ResolveMonitorBind(Const Settings: TMonitorSettings; Out Address, ErrorText: String): Boolean;
Var
  Preferred: String;
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
  Preferred := MonitorPreferredBindAddress;
  If MonitorBindAddressReachesLan(Settings.BindAddress) Then
    Address := Settings.BindAddress
  Else If Preferred <> '' Then
    Address := Preferred
  Else If IsIPv4Address(Settings.BindAddress) Then
    Address := Settings.BindAddress
  Else
    Begin
      ErrorText := 'One IPv4 address is required.';
      Exit;
    End;
  Result := True;
End;

End.
