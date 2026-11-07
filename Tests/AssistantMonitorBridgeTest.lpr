Program AssistantMonitorBridgeTest;

{ State publication follows the bridge refresh and notice paths (c) 2026 Michell Computing.
  Uses the real form and bridge with a memory carrier. Drain on every outbox wake so state
  coalescing cannot hide repeated publications. No provider is started and the form is not shown. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils, FileUtil, fpjson, jsonparser, AssistantTestIDEHost,
  WorkflowSettings, ProjectAssistantForm, AssistantSessionObserve, AssistantMonitorSession,
  AssistantMonitorBridge, AssistantMonitorCarrier, AssistantMonitorCodec, AssistantMonitorFrames;

Const
  MenuKeys: Array[0..6] Of String = ('plan_choices', 'plan', 'targets', 'conversations', 'models', 'reasoning', 'permissions');

Type
  TDrainSink = Class
    Session: TMonitorSession;
    Draining: Boolean;
    Procedure Wake;
  End;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TDrainSink.Wake;
Begin
  If Draining Then
    Exit;
  Draining := True;
  Try
    Session.DrainOutbound;
  Finally
    Draining := False;
  End;
End;

Procedure CheckKeys(Carrier: TMonitorMemoryCarrier; Const Expected: Array Of String);
Var
  Counts: TStringList;
  Root, Payload: TJSONObject;
  Data: TJSONData;
  Index, Slot, StateCount: Integer;
  Key: String;
Begin
  Counts := TStringList.Create;
  Try
    StateCount := 0;
    For Index := 0 To Carrier.SentCount - 1 Do
      Begin
        Data := GetJSON(Carrier.SentJson(Index));
        Try
          Root := TJSONObject(Data);
          If Root.Get('type', '') <> 'state' Then
            Continue;
          Payload := TJSONObject(Root.Find('payload'));
          Key := Payload.Get('key', '');
          Inc(StateCount);
          Slot := Counts.IndexOfName(Key);
          If Slot < 0 Then
            Counts.Values[Key] := '1'
          Else
            Counts.Values[Key] := IntToStr(StrToInt(Counts.ValueFromIndex[Slot]) + 1);
        Finally
          Data.Free;
        End;
      End;
    Check('exactly the changed keys are published', StateCount = Length(Expected));
    For Index := 0 To High(Expected) Do
      Check(Expected[Index] + ' published once', Counts.Values[Expected[Index]] = '1');
  Finally
    Counts.Free;
  End;
End;

Procedure TestBridge;
Var
  Form: TProjectAssistantForm;
  Session: TMonitorSession;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Sink: TDrainSink;
  Spare: TMonitorFrame;
  ErrorText: String;
  Index: Integer;
Begin
  Form := TProjectAssistantForm.Create(Nil);
  Session := TMonitorSession.Create;
  Sink := TDrainSink.Create;
  Carrier := TMonitorMemoryCarrier.Create;
  CarrierRef := Carrier;
  Try
    Session.AttachCarrier(CarrierRef);
    Session.SetHostFingerprint('ab12cd34');
    Session.NoteTime(5000);
    Check('listen starts', Session.StartListening('127.0.0.1', 56124, ErrorText));
    Check('handshake accepted', Session.AcceptHandshake(Spare));
    Carrier.DeliverJson(EncodeMonitorHello('hello', 'Phone', '1', ''));
    Carrier.DeliverJson(EncodeMonitorPair('pair', '', ''));
    Check('memory session is live', Session.State = mssLive);
    RegisterAssistantMonitor;
    AttachAssistantMonitorBridge(Session);
    Session.DrainOutbound;
    Sink.Session := Session;
    Session.SetOutboundWake(@Sink.Wake);
    For Index := 1 To 2 Do
      Begin
        Carrier.ClearSent;
        Carrier.DeliverJson('{"v":3,"id":"menu-' + IntToStr(Index) +
          '","type":"refresh","payload":{"text":"menu_choices"}}');
        CheckSynchronize;
        Session.DrainOutbound;
        CheckKeys(Carrier, MenuKeys);
      End;
    Carrier.ClearSent;
    AssistantSessionObserve.AssistantSessionObserve(asnMode);
    CheckSynchronize;
    Session.DrainOutbound;
    CheckKeys(Carrier, ['mode']);
    Carrier.ClearSent;
    AssistantSessionObserve.AssistantSessionObserve(asnTarget);
    CheckSynchronize;
    Session.DrainOutbound;
    CheckKeys(Carrier, ['target', 'targets']);
    Carrier.ClearSent;
    AssistantSessionObserve.AssistantSessionObserve(asnTasks);
    CheckSynchronize;
    Session.DrainOutbound;
    CheckKeys(Carrier, ['tasks']);
    Carrier.ClearSent;
    AssistantSessionObserve.AssistantSessionObserve(asnStatus);
    CheckSynchronize;
    Session.DrainOutbound;
    CheckKeys(Carrier, ['status', 'session', 'mode']);
    Carrier.ClearSent;
    Carrier.DeliverJson('{"v":3,"id":"screen-wake","type":"refresh","payload":{"text":"live"}}');
    CheckSynchronize;
    Session.DrainOutbound;
    CheckKeys(Carrier, ['status', 'session', 'mode', 'target', 'tasks', 'plan_choices', 'plan']);
    {$IFDEF MONITOR_BRIDGE_TEST}
    Form.BindToActiveProject;
    CheckSynchronize;
    Check('empty form is bound for screen delivery', Form.MonitorScreenReady);
    TickMonitorBridgeForTest;
    MonitorSnapshotFillCount := 0;
    For Index := 1 To 5 Do
      TickMonitorBridgeForTest;
    Check('idle empty ticks skip snapshot and all turn fills', MonitorSnapshotFillCount = 0);
    TouchAssistantMirror;
    TickMonitorBridgeForTest;
    Check('mirror change retries empty screen once', MonitorSnapshotFillCount = 1);
    TickMonitorBridgeForTest;
    Check('retried empty screen is cached again', MonitorSnapshotFillCount = 1);
    {$ENDIF}
  Finally
    Session.SetOutboundWake(Nil);
    UnregisterAssistantMonitor;
    Sink.Free;
    Session.Free;
    CarrierRef := Nil;
    Form.Free;
  End;
End;

Var
  SettingsRoot: String;
  Guid: TGUID;
Begin
  Try
    Application.Initialize;
    If CreateGUID(Guid) <> 0 Then
      Raise Exception.Create('Could not create settings directory name');
    SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'monitor-bridge-' + GUIDToString(Guid);
    ForceDirectories(SettingsRoot);
    SetWorkflowSettingsDirectory(SettingsRoot);
    Try
      TestBridge;
    Finally
      SetWorkflowSettingsDirectory('');
      DeleteDirectory(SettingsRoot, False);
    End;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        DumpExceptionBackTrace(StdErr);
        Inc(FailCount);
      End;
  End;
  If FailCount <> 0 Then
    Halt(1);
  WriteLn('AssistantMonitorBridgeTest passed');
End.
