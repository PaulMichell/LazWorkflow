Unit AssistantMonitorForm;

{ Remote Monitor options dialog (c) 2026 Michell Computing.

  Static layout. The listener outlives the dialog. The phone connects to the
  shown endpoint, which is the default-route address rather than a virtual
  adapter such as WSL. The certificate fingerprint is the SHA-256 of that host
  certificate, grouped in pairs. Pairing codes are single-use and expire after
  two minutes. Require pairing code, on by default, can be turned off so any
  phone that reaches the endpoint pairs without one. The pairing store reads the
  saved choice on the next attempt. Start and Stop open and close the HTTPS
  listener. Catalogue 3 frame counters are not shown.
  LCL has no adapter list. Adapter enumeration lives in AssistantMonitorSettings.

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
    RequirePairCodeCheck: TCheckBox;
    ButtonStrip: TPanel;
    EnableButton: TButton;
    DisableButton: TButton;
    RevokeButton: TButton;
    RevokeAllButton: TButton;
    CloseButton: TButton;
    EndpointLabel: TLabel;
    FingerprintLabel: TLabel;
    StatusMemo: TMemo;
    ClientList: TListBox;
    StatusTimer: TTimer;
    PairCodeEdit: TEdit;
    PairButton: TButton;
    PairAction: TAction;
    Procedure FormCreate(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormClose(Sender: TObject; Var CloseAction: TCloseAction);
    Procedure EnableActionExecute(Sender: TObject);
    Procedure DisableActionExecute(Sender: TObject);
    Procedure RevokeActionExecute(Sender: TObject);
    Procedure RevokeAllActionExecute(Sender: TObject);
    Procedure RemoteApprovalCheckClick(Sender: TObject);
    Procedure RequirePairCodeCheckClick(Sender: TObject);
    Procedure StatusTimerTimer(Sender: TObject);
    Procedure ClientListClick(Sender: TObject);
    Procedure BindAllCheckClick(Sender: TObject);

    Procedure PairActionExecute(Sender: TObject);
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
  AssistantMonitorSettings, AssistantMonitorApproval, AssistantMonitorMain, AssistantMonitorPair, AssistantMonitorServer,
  AssistantMonitorTls, WorkflowLog;

Function IsLoopback(Const Address: String): Boolean;
Begin
  Result := Copy(Address, 1, 4) = '127.';
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

Procedure TAssistantMonitorForm.FillAddressChoices;
Var
  Found: TStringList;
  Current: String;
  I: Integer;
Begin
  Current := AddressEdit.Text;
  Found := MonitorInterfaceAddresses;
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
  ErrorText: String;
Begin
  FieldsLoading := True;
  Try
    If Not LoadMonitorSettings(Settings, ErrorText) Then
      Settings := DefaultMonitorSettings;
    PortEdit.Value := Settings.Port;
    BindAllCheck.Checked := Settings.BindAll;
    RemoteApprovalCheck.Checked := Settings.RemoteApproval;
    RequirePairCodeCheck.Checked := Settings.RequirePairCode;
    { A stored address that is not on an adapter is kept. One that exists only on a virtual adapter,
      such as WSL 172.29.0.1, is not reachable from the LAN and is replaced by the default-route address. }
    If (Settings.BindAddress <> '') And MonitorBindAddressReachesLan(Settings.BindAddress) Then
      AddressEdit.Text := Settings.BindAddress
    Else
      AddressEdit.Text := MonitorPreferredBindAddress;
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
  Settings.RequirePairCode := RequirePairCodeCheck.Checked;
  If Not SaveMonitorSettings(Settings, ErrorText) Then
    StatusMemo.Text := ErrorText;
  ApplyMonitorRemoteApproval(Settings.RemoteApproval);
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
  Status, NoteError, Fingerprint, FingerprintError: String;
  Running: Boolean;
  NoteSettings: TMonitorSettings;
Begin
  Running := ListenerRunning;
  EnableAction.Enabled := Not Running;
  DisableAction.Enabled := Running;
  PairAction.Enabled := Running;
  If Not RequirePairCodeCheck.Checked Then
    PairCodeEdit.Text := 'No pairing code is required. Any phone that reaches this endpoint can pair.'
  Else If Running And (MonitorPairCodeText <> '') Then
    PairCodeEdit.Text := MonitorPairCodeText
  Else
    PairCodeEdit.Text := 'Generate a pairing code, then enter it on the phone. Codes expire after two minutes.';
  RevokeAction.Enabled := SelectedClientId <> '';
  RevokeAllAction.Enabled := ClientIds.Count > 0;
  AddressEdit.Enabled := Not Running;
  PortEdit.Enabled := Not Running;
  BindAllCheck.Enabled := Not Running;
  EndpointLabel.Caption := EndpointCaption;
  If MonitorHostFingerprint(Fingerprint, FingerprintError) Then
    FingerprintLabel.Caption := 'Fingerprint  ' + MonitorFingerprintText(Fingerprint)
  Else If FingerprintError <> '' Then
    FingerprintLabel.Caption := 'Fingerprint  ' + FingerprintError
  Else
    FingerprintLabel.Caption := 'Fingerprint';
  If Running Then
    Status := 'Listener listening' + LineEnding + 'Bound ' + MonitorHttpsAddress + ' port ' + IntToStr(MonitorHttpsPort)
  Else
    Status := 'Listener stopped';
  If Not LoadMonitorSettings(NoteSettings, NoteError) Then
    Status := Status + LineEnding + NoteError
  Else If NoteSettings.LegacyNote Then
    Status := Status + LineEnding + MonitorLegacyPairingNote;
  StatusMemo.Text := Status;
End;

Procedure TAssistantMonitorForm.FormCreate(Sender: TObject);
Var
  ErrorText: String;
Begin
  ClientIds := TStringList.Create;
  SettleLegacyMonitorPairings(ErrorText);
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
Begin
  ClientId := SelectedClientId;
  If ClientId = '' Then
    Exit;
  If Not RevokeMonitorPairedClient(ClientId, ErrorText) Then
    Begin
      StatusMemo.Text := ErrorText;
      Exit;
    End;
  RefreshClients;
  RefreshState;
End;

Procedure TAssistantMonitorForm.RevokeAllActionExecute(Sender: TObject);
Var
  ErrorText: String;
Begin
  If Not RevokeAllMonitorPairedClients(ErrorText) Then
    StatusMemo.Text := ErrorText;
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

Procedure TAssistantMonitorForm.RequirePairCodeCheckClick(Sender: TObject);
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

Procedure TAssistantMonitorForm.PairActionExecute(Sender: TObject);
Var
  Code: String;
Begin
  If Not ListenerRunning Then
    Exit;
  If Not RequirePairCodeCheck.Checked Then
    Begin
      PairCodeEdit.Text := 'No pairing code is required. Any phone that reaches this endpoint can pair.';
      Exit;
    End;
  If Not IssueMonitorPairCode(Code) Then
    Begin
      StatusMemo.Text := 'Could not generate a pairing code.';
      Exit;
    End;
  PairCodeEdit.Text := Code;
  StatusMemo.Text := 'Pairing code ready. It expires in two minutes.';
End;
End.
