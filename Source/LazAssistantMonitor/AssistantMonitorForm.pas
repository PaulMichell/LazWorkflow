Unit AssistantMonitorForm;

{ Remote Monitor options dialog (c) 2026 Michell Computing.

  Static layout. The listener outlives the dialog. The phone connects to the
  shown endpoint. There is no fingerprint and no pairing code on this form.
  LCL has no adapter list, and this tree's FCL does not declare getifaddrs, so
  the layouts below are read through explicit libc and iphlpapi externals.

  LoadFields sets FieldsLoading while it fills the controls. Setting
  RemoteApprovalCheck.Checked fires its OnClick, and that handler must not
  save half-loaded fields (plan item 3.4 of Documents/Plan-20261105-130659.md). }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ActnList, Spin, Dialogs;

Type
  TAssistantMonitorForm = Class(TForm)
    ActionList: TActionList;
    EnableAction: TAction;
    DisableAction: TAction;
    RevokeAction: TAction;
    RevokeAllAction: TAction;
    BindGroup: TGroupBox;
    AddressLabel: TLabel;
    AddressEdit: TComboBox;
    PortLabel: TLabel;
    PortEdit: TSpinEdit;
    BindAllCheck: TCheckBox;
    RemoteApprovalCheck: TCheckBox;
    ButtonStrip: TPanel;
    EnableButton: TButton;
    DisableButton: TButton;
    RevokeButton: TButton;
    RevokeAllButton: TButton;
    CloseButton: TButton;
    EndpointLabel: TLabel;
    StatusMemo: TMemo;
    ClientList: TListBox;
    StatusTimer: TTimer;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormClose(Sender: TObject; Var CloseAction: TCloseAction);
    Procedure EnableActionExecute(Sender: TObject);
    Procedure DisableActionExecute(Sender: TObject);
    Procedure RevokeActionExecute(Sender: TObject);
    Procedure RevokeAllActionExecute(Sender: TObject);
    Procedure RemoteApprovalCheckClick(Sender: TObject);
    Procedure StatusTimerTimer(Sender: TObject);
    Procedure ClientListClick(Sender: TObject);
    Procedure BindAllCheckClick(Sender: TObject);
  Private
    ClientIds: TStringList;
    ClientsRevision: LongInt;
    ClientsLoaded: Boolean;
    { True while LoadFields fills the controls. Control events do not save then. }
    FieldsLoading: Boolean;
    Procedure LoadFields;
    Procedure FillAddressChoices;
    Function EndpointCaption: String;
    Procedure SaveFields(Listening: Boolean);
    Procedure RefreshState;
    Procedure RefreshClients;
    Procedure ShowBindFailure(Const Address: String; Port: Integer; Const ErrorText: String);
    Function SelectedClientId: String;
  Public
    Destructor Destroy; Override;
  End;

Procedure ShowAssistantMonitorForm;

Implementation

{$R *.lfm}

Uses
  AssistantMonitorSettings, AssistantMonitorSession, AssistantMonitorBridge,
  AssistantMonitorApproval, AssistantMonitorMain, WorkflowLog;

Const
  AfInet = 2;
  {$IFDEF WINDOWS}
  WinErrorBufferOverflow = 111;
  WinSkipAnycast = $0002;
  WinSkipMulticast = $0004;
  WinSkipDns = $0008;
  {$ENDIF}

Type
  PMonitorSocketIn = ^TMonitorSocketIn;
  TMonitorSocketIn = Packed Record
    Family: Word;
    Port: Word;
    Address: Array[0..3] Of Byte;
    Zero: Array[0..7] Of Byte;
  End;

{$IFDEF UNIX}
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
{$ENDIF}

{$IFDEF WINDOWS}
  PWinSocketAddress = ^TWinSocketAddress;
  TWinSocketAddress = Record
    SockAddr: PMonitorSocketIn;
    SockLen: Integer;
  End;
  PWinUnicast = ^TWinUnicast;
  TWinUnicast = Record
    Alignment: UInt64;
    Next: PWinUnicast;
    Address: TWinSocketAddress;
  End;
  PWinAdapter = ^TWinAdapter;
  TWinAdapter = Record
    Alignment: UInt64;
    Next: PWinAdapter;
    AdapterName: PAnsiChar;
    FirstUnicast: PWinUnicast;
  End;
{$ENDIF}

{$IFDEF UNIX}
Function getifaddrs(Out List: PMonitorIfAddrs): Integer; Cdecl; External 'c';
Procedure freeifaddrs(List: PMonitorIfAddrs); Cdecl; External 'c';
{$ENDIF}

{$IFDEF WINDOWS}
Function GetAdaptersAddresses(Family, Flags: Cardinal; Reserved: Pointer; Addresses: PWinAdapter;
  Var Size: Cardinal): Cardinal; StdCall; External 'iphlpapi.dll' Name 'GetAdaptersAddresses';
{$ENDIF}

Function IPv4Text(Const Address: Array Of Byte): String;
Begin
  Result := IntToStr(Address[0]) + '.' + IntToStr(Address[1]) + '.' + IntToStr(Address[2]) + '.' +
    IntToStr(Address[3]);
End;

Function IsLoopback(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 4) = '127.';
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

Function PreferredAddress(Addresses: TStrings): String;
Var
  I: Integer;

  Function FirstMatch(Kind: Integer): String;
  Var
    Index: Integer;
    Address: String;
  Begin
    Result := '';
    For Index := 0 To Addresses.Count - 1 Do
      Begin
        Address := Addresses[Index];
        If ((Kind = 0) And IsPrivate10(Address)) Or ((Kind = 1) And IsPrivate172(Address)) Or
          ((Kind = 2) And IsPrivate192(Address)) Then
          Exit(Address);
      End;
  End;

Begin
  Result := '';
  If Not Assigned(Addresses) Then
    Exit;
  For I := Addresses.Count - 1 DownTo 0 Do
    If IsLoopback(Addresses[I]) Then
      Addresses.Delete(I);
  Result := FirstMatch(0);
  If Result = '' Then
    Result := FirstMatch(1);
  If Result = '' Then
    Result := FirstMatch(2);
End;

Function CollectIPv4: TStringList;
{$IFDEF UNIX}
Var
  List, Cursor: PMonitorIfAddrs;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  Size, Status: Cardinal;
  Buffer: PWinAdapter;
  Adapter: PWinAdapter;
  Unicast: PWinUnicast;
{$ENDIF}
Begin
  Result := TStringList.Create;
{$IFDEF UNIX}
  List := Nil;
  If getifaddrs(List) = 0 Then
    Try
      Cursor := List;
      While Assigned(Cursor) Do
        Begin
          If Assigned(Cursor^.Address) And (Cursor^.Address^.Family = AfInet) Then
            Result.Add(IPv4Text(Cursor^.Address^.Address));
          Cursor := Cursor^.Next;
        End;
    Finally
      freeifaddrs(List);
    End;
{$ENDIF}
{$IFDEF WINDOWS}
  Size := 0;
  Buffer := Nil;
  Status := GetAdaptersAddresses(AfInet, WinSkipAnycast Or WinSkipMulticast Or WinSkipDns, Nil, Nil, Size);
  If (Status = WinErrorBufferOverflow) And (Size > 0) Then
    Begin
      GetMem(Buffer, Size);
      Try
        Status := GetAdaptersAddresses(AfInet, WinSkipAnycast Or WinSkipMulticast Or WinSkipDns, Nil, Buffer, Size);
        If Status = 0 Then
          Begin
            Adapter := Buffer;
            While Assigned(Adapter) Do
              Begin
                Unicast := Adapter^.FirstUnicast;
                While Assigned(Unicast) Do
                  Begin
                    If Assigned(Unicast^.Address.SockAddr) And (Unicast^.Address.SockAddr^.Family = AfInet) Then
                      Result.Add(IPv4Text(Unicast^.Address.SockAddr^.Address));
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

Function ProposeBindAddress: String;
Var
  Found: TStringList;
Begin
  Found := CollectIPv4;
  Try
    Result := PreferredAddress(Found);
  Finally
    Found.Free;
  End;
End;

Function ListenerRunning: Boolean;
Begin
  Result := AssistantMonitorListenerRunning;
End;

Procedure ShowAssistantMonitorForm;
Var
  Form: TAssistantMonitorForm;
Begin
  Form := TAssistantMonitorForm.Create(Nil);
  Try
    Form.ShowModal;
  Finally
    Form.Free;
  End;
End;

Function StateCaption(State: TMonitorSessionState): String;
Begin
  Case State Of
    mssStopped: Result := 'stopped';
    mssListening: Result := 'listening';
    mssAccepted: Result := 'accepted';
    mssLive: Result := 'live';
    mssBusy: Result := 'busy';
    mssRevoked: Result := 'revoked';
  Else
    Result := 'unknown';
  End;
End;

Procedure TAssistantMonitorForm.FillAddressChoices;
Var
  Found: TStringList;
  Current: String;
  I: Integer;
Begin
  Current := AddressEdit.Text;
  Found := CollectIPv4;
  Try
    AddressEdit.Items.BeginUpdate;
    Try
      AddressEdit.Items.Clear;
      For I := 0 To Found.Count - 1 Do
        If Not IsLoopback(Found[I]) Then
          AddressEdit.Items.Add(Found[I]);
      AddressEdit.Items.Add('127.0.0.1');
    Finally
      AddressEdit.Items.EndUpdate;
    End;
  Finally
    Found.Free;
  End;
  AddressEdit.Text := Current;
End;

Function TAssistantMonitorForm.EndpointCaption: String;
Var
  Found: TStrings;
  I: Integer;
  Line, Address: String;
  Port: Integer;
Begin
  Port := PortEdit.Value;
  If BindAllCheck.Checked Then
    Begin
      Found := AddressEdit.Items;
      Line := '';
      For I := 0 To Found.Count - 1 Do
        Begin
          Address := Found[I];
          If IsLoopback(Address) Then
            Continue;
          If Line <> '' Then
            Line := Line + ', ';
          Line := Line + Address + ':' + IntToStr(Port);
        End;
      If Line = '' Then
        Line := 'no LAN address found';
      Result := 'Phone endpoints  ' + Line + '. Emulator  127.0.0.1:' + IntToStr(Port);
    End
  Else If Trim(AddressEdit.Text) = '' Then
    Result := 'Choose an endpoint, then Enable.'
  Else
    Result := 'Phone endpoint  ' + Trim(AddressEdit.Text) + ':' + IntToStr(Port);
End;

Procedure TAssistantMonitorForm.LoadFields;
Var
  Settings: TMonitorSettings;
  ErrorText, Proposed: String;
Begin
  FieldsLoading := True;
  Try
    If Not LoadMonitorSettings(Settings, ErrorText) Then
      Settings := DefaultMonitorSettings;
    PortEdit.Value := Settings.Port;
    BindAllCheck.Checked := Settings.BindAll;
    RemoteApprovalCheck.Checked := Settings.RemoteApproval;
    If Settings.BindAddress <> '' Then
      AddressEdit.Text := Settings.BindAddress
    Else
      Begin
        Proposed := ProposeBindAddress;
        AddressEdit.Text := Proposed;
      End;
    If ErrorText <> '' Then
      StatusMemo.Text := ErrorText;
    FillAddressChoices;
  Finally
    FieldsLoading := False;
  End;
End;

Procedure TAssistantMonitorForm.SaveFields(Listening: Boolean);
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Settings := DefaultMonitorSettings;
  Settings.Enabled := Listening;
  Settings.Port := PortEdit.Value;
  Settings.BindAddress := Trim(AddressEdit.Text);
  Settings.BindAll := BindAllCheck.Checked;
  Settings.RemoteApproval := RemoteApprovalCheck.Checked;
  If Not SaveMonitorSettings(Settings, ErrorText) Then
    StatusMemo.Text := ErrorText;
  ApplyMonitorRemoteApproval(Settings.RemoteApproval);
  If Assigned(MonitorLiveSession) Then
    MonitorLiveSession.SetRemoteApproval(Settings.RemoteApproval);
End;

Procedure TAssistantMonitorForm.ShowBindFailure(Const Address: String; Port: Integer; Const ErrorText: String);
Begin
  MessageDlg('Could not bind ' + Address + ' port ' + IntToStr(Port) + '.' + LineEnding + ErrorText,
    mtError, [mbOK], 0);
End;

Function TAssistantMonitorForm.SelectedClientId: String;
Begin
  Result := '';
  If (ClientList.ItemIndex >= 0) And (ClientList.ItemIndex < ClientIds.Count) Then
    Result := ClientIds[ClientList.ItemIndex];
End;

Procedure TAssistantMonitorForm.RefreshClients;
Var
  Settings: TMonitorSettings;
  ErrorText, Line, Selected: String;
  I, Keep, Revision, PreviousTop: Integer;
  Ids, Names: TStringList;
Begin
  Revision := MonitorSettingsRevision;
  If ClientsLoaded And (ClientsRevision = Revision) Then
    Exit;
  ClientsRevision := Revision;
  ClientsLoaded := True;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  Ids := TStringList.Create;
  Names := TStringList.Create;
  Try
    For I := 0 To High(Settings.Clients) Do
      Begin
        Ids.Add(Settings.Clients[I].Id);
        Line := Settings.Clients[I].Name;
        If Line = '' Then
          Line := Settings.Clients[I].Id;
        Names.Add(Line);
      End;
    If (ClientIds.Text = Ids.Text) And (ClientList.Items.Text = Names.Text) Then
      Exit;
    Selected := SelectedClientId;
    PreviousTop := ClientList.TopIndex;
    ClientList.Items.BeginUpdate;
    Try
      ClientIds.Assign(Ids);
      ClientList.Items.Assign(Names);
      Keep := ClientIds.IndexOf(Selected);
      ClientList.ItemIndex := Keep;
      If ClientList.Count > 0 Then
        ClientList.TopIndex := PreviousTop;
    Finally
      ClientList.Items.EndUpdate;
    End;
  Finally
    Names.Free;
    Ids.Free;
  End;
End;

Procedure TAssistantMonitorForm.RefreshState;
Var
  Status: String;
  Running: Boolean;
Begin
  Running := ListenerRunning;
  EnableAction.Enabled := Not Running;
  DisableAction.Enabled := Running;
  RevokeAction.Enabled := SelectedClientId <> '';
  RevokeAllAction.Enabled := ClientIds.Count > 0;
  AddressEdit.Enabled := Not Running;
  PortEdit.Enabled := Not Running;
  BindAllCheck.Enabled := Not Running;
  EndpointLabel.Caption := EndpointCaption;
  If Assigned(MonitorLiveSession) Then
    Status := 'Listener ' + StateCaption(MonitorLiveSession.State) + LineEnding +
      'Bound ' + MonitorLiveSession.BoundAddress + ' port ' + IntToStr(MonitorLiveSession.BoundPort) + LineEnding +
      'Client ' + MonitorLiveSession.ConnectedClientName + LineEnding +
      'Seconds since frame ' + IntToStr(MonitorLiveSession.SecondsSinceFrame) + LineEnding +
      'Frames sent ' + IntToStr(MonitorLiveSession.FramesSent) +
      '  dropped ' + IntToStr(MonitorLiveSession.FramesDropped) + LineEnding +
      'Remote approval ' + BoolToStr(MonitorLiveSession.RemoteApproval, True)
  Else
    Status := 'Listener stopped';
  If Assigned(MonitorLiveSession) And (MonitorLiveSession.LastError <> '') Then
    Status := Status + LineEnding + MonitorLiveSession.LastError;
  StatusMemo.Text := Status;
End;

Procedure TAssistantMonitorForm.FormCreate(Sender: TObject);
Begin
  ClientIds := TStringList.Create;
  LoadFields;
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.FormShow(Sender: TObject);
Begin
  FillAddressChoices;
  ClientsLoaded := False;
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.FormClose(Sender: TObject; Var CloseAction: TCloseAction);
Begin
  SaveFields(ListenerRunning);
  CloseAction := caHide;
End;

Destructor TAssistantMonitorForm.Destroy;
Begin
  FreeAndNil(ClientIds);
  Inherited Destroy;
End;

Procedure TAssistantMonitorForm.EnableActionExecute(Sender: TObject);
Var
  ErrorText: String;
Begin
  If ListenerRunning Then
    Exit;
  SaveFields(False);
  If Not StartAssistantMonitorListener(ErrorText) Then
    Begin
      ShowBindFailure(Trim(AddressEdit.Text), PortEdit.Value, ErrorText);
      Exit;
    End;
  SaveFields(True);
  RefreshState;
End;

Procedure TAssistantMonitorForm.DisableActionExecute(Sender: TObject);
Begin
  { WaitFor pumps the main loop. A second click must not turn the timer back on while the listen thread is still clearing strings. }
  If Not DisableAction.Enabled Then
    Exit;
  DisableAction.Enabled := False;
  StatusTimer.Enabled := False;
  Try
    StopAssistantMonitorListener;
    SaveFields(False);
    WorkflowLogger.Info('AssistantMonitor', 'listen disabled');
  Finally
    RefreshState;
    StatusTimer.Enabled := True;
  End;
End;

Procedure TAssistantMonitorForm.RevokeActionExecute(Sender: TObject);
Var
  ClientId, ErrorText: String;
  Settings: TMonitorSettings;
  I, Kept: Integer;
Begin
  ClientId := SelectedClientId;
  If ClientId = '' Then
    Exit;
  If Assigned(MonitorLiveSession) Then
    MonitorLiveSession.RevokeClient(ClientId)
  Else
    Begin
      If Not LoadMonitorSettings(Settings, ErrorText) Then
        Exit;
      Kept := 0;
      For I := 0 To High(Settings.Clients) Do
        If Settings.Clients[I].Id <> ClientId Then
          Begin
            Settings.Clients[Kept] := Settings.Clients[I];
            Inc(Kept);
          End;
      SetLength(Settings.Clients, Kept);
      SaveMonitorSettings(Settings, ErrorText);
    End;
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.RevokeAllActionExecute(Sender: TObject);
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  If Assigned(MonitorLiveSession) Then
    MonitorLiveSession.RevokeAll
  Else
    Begin
      If Not LoadMonitorSettings(Settings, ErrorText) Then
        Exit;
      SetLength(Settings.Clients, 0);
      SaveMonitorSettings(Settings, ErrorText);
    End;
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.RemoteApprovalCheckClick(Sender: TObject);
Begin
  { LoadFields setting Checked fires this. The loaded value is not a user change. }
  If FieldsLoading Then
    Exit;
  SaveFields(ListenerRunning);
  RefreshState;
End;

Procedure TAssistantMonitorForm.StatusTimerTimer(Sender: TObject);
Begin
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.ClientListClick(Sender: TObject);
Begin
  RefreshState;
End;

Procedure TAssistantMonitorForm.BindAllCheckClick(Sender: TObject);
Begin
  If FieldsLoading Then
    Exit;
  FillAddressChoices;
  RefreshState;
End;
End.
