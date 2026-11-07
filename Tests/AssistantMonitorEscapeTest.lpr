Program AssistantMonitorEscapeTest;

{ Monitor frames that carry user text stay valid JSON (c) 2026 Michell Computing.

  Plan item 2.1 of Documents/Plan-20261105-130659.md. Quotes, backslashes, a Windows path, a newline,
  a tab, ESC and non-ASCII text go through the state writers, the mirror page writer and a live
  in-memory session. Every frame must pass TryEncodeMonitorFrame and TryDecodeMonitorFrame, hold no
  raw control byte, and decode back to the original bytes. No sockets and no Interfaces unit.
  The runner writes this binary with a temporary -FU and -FE, never under Source/. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, AssistantMonitorLinkStubs, AssistantMonitorCarrier, AssistantMonitorCodec, AssistantMonitorFrames,
  AssistantMonitorMirror, AssistantMonitorSync, AssistantMonitorSession, AssistantSessionObserve, WorkflowSettings;

Const
  WindowsPath = 'C:\Users\Paul\Projects\Lazarus';
  PlanPath = 'Documents\Plan "draft".md';

Var
  FailCount: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;
  SettingsRoot: String;

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

{ A quote, a backslash, a Windows path, a newline, a tab, ESC, and non-ASCII text (e acute and the euro sign). }
Function AwkwardText: String;
Begin
  Result := 'Say "hi" \ ' + WindowsPath + #10 + 'next' + #9 + 'tab' + #27 + '[0m caf' + #$C3#$A9 + ' ' + #$E2#$82#$AC;
End;

{ Byte comparison. No code page conversion on either side. }
Function SameBytes(Const Left, Right: RawByteString): Boolean;
Begin
  Result := (Length(Left) = Length(Right)) And ((Length(Left) = 0) Or (CompareByte(Left[1], Right[1], Length(Left)) = 0));
End;

Function HasRawControl(Const Text: RawByteString): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 1 To Length(Text) Do
    If Ord(Text[Index]) < 32 Then
      Exit(True);
End;

{ Frames the JSON as LAM1, decodes it and parses it. Nil when any step fails or a raw control byte is present. }
Function RoundTrip(Const Json: String): TJSONObject;
Var
  Bytes: RawByteString;
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Data: TJSONData;
Begin
  Result := Nil;
  If HasRawControl(Json) Then
    Exit;
  If Not TryEncodeMonitorFrame(Json, Bytes, Status) Then
    Exit;
  If Not TryDecodeMonitorFrame(Bytes, Frame, Status) Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(Frame.Json);
  Except
    Data := Nil;
  End;
  If Data Is TJSONObject Then
    Result := TJSONObject(Data)
  Else
    Data.Free;
End;

Function ObjectField(Obj: TJSONObject; Const Name: String): TJSONObject;
Var
  Item: TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Obj) Then
    Exit;
  Item := Obj.Find(Name);
  If Item Is TJSONObject Then
    Result := TJSONObject(Item);
End;

Function ArrayItem(Obj: TJSONObject; Const Name: String; Index: Integer): TJSONObject;
Var
  Item: TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Obj) Then
    Exit;
  Item := Obj.Find(Name);
  If (Not (Item Is TJSONArray)) Or (Index < 0) Or (Index >= TJSONArray(Item).Count) Then
    Exit;
  If TJSONArray(Item).Items[Index] Is TJSONObject Then
    Result := TJSONObject(TJSONArray(Item).Items[Index]);
End;

Function TextField(Obj: TJSONObject; Const Name: String): RawByteString;
Var
  Item: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then
    Exit;
  Item := Obj.Find(Name);
  If Assigned(Item) And (Item.JSONType = jtString) Then
    Result := Item.AsString;
End;

Function BoolField(Obj: TJSONObject; Const Name: String): Boolean;
Var
  Item: TJSONData;
Begin
  Result := False;
  If Not Assigned(Obj) Then
    Exit;
  Item := Obj.Find(Name);
  If Assigned(Item) And (Item.JSONType = jtBoolean) Then
    Result := Item.AsBoolean;
End;

{ payload.value of a state frame for Key. Nil for any other frame. }
Function StateValue(Root: TJSONObject; Const Key: String): TJSONObject;
Var
  Payload: TJSONObject;
Begin
  Result := Nil;
  If (Not Assigned(Root)) Or (TextField(Root, 'type') <> 'state') Then
    Exit;
  Payload := ObjectField(Root, 'payload');
  If TextField(Payload, 'key') = Key Then
    Result := ObjectField(Payload, 'value');
End;

Procedure FillAwkwardView(Out View: TAssistantMonitorView);
Begin
  View := Default(TAssistantMonitorView);
  View.Phase := 'idle';
  View.StatusText := AwkwardText;
  View.ErrorText := AwkwardText;
  View.StartedAt := '2026-11-05T12:00:00Z';
  View.Model := AwkwardText;
  View.Backend := 'claude';
  View.ContextText := AwkwardText;
  View.ApprovalCaption := AwkwardText;
  View.Mode := 'build';
  View.TargetKind := 'project';
  View.TargetDisplay := AwkwardText;
  View.TargetRoot := WindowsPath;
  View.PlanPath := PlanPath;
  View.PlanTitle := AwkwardText;
End;

Procedure FillAwkwardRows(Out Rows: TMonitorMirrorPlanArray);
Begin
  SetLength(Rows, 1);
  Rows[0] := Default(TAssistantMonitorPlanRow);
  Rows[0].Index := 0;
  Rows[0].Level := 3;
  Rows[0].Title := AwkwardText;
  Rows[0].ParentTitle := AwkwardText;
  Rows[0].Status := 'not started';
  Rows[0].Actionable := True;
End;

Procedure CheckChoice(Const Title: String; Value: TJSONObject; Index: Integer; Const Path, Caption: String);
Var
  Item: TJSONObject;
Begin
  Item := ArrayItem(Value, 'choices', Index);
  Check(Title + ' choice ' + IntToStr(Index) + ' path round-trips', SameBytes(TextField(Item, 'path'), Path));
  Check(Title + ' choice ' + IntToStr(Index) + ' caption round-trips', SameBytes(TextField(Item, 'caption'), Caption));
End;

Procedure TestStateWriters;
Var
  Awkward, ToolId: String;
  View: TAssistantMonitorView;
  Paths, Captions: TStringList;
  Rows: TMonitorMirrorPlanArray;
  Tasks: Array Of TAssistantMonitorTaskRow;
  Root, Value, Item: TJSONObject;
  Bytes: RawByteString;
  Status: TMonitorFrameStatus;
Begin
  Awkward := AwkwardText;
  ToolId := 'tool "7" \ ' + #9 + 'x';
  { The plan asked for this to be confirmed. The writers escape every control either way. }
  WriteLn('detail fpjson accepts a raw ESC inside a string: ', TryEncodeMonitorFrame('{"a":"x' + #27 + 'y"}', Bytes, Status));
  WriteLn('detail fpjson accepts a raw newline inside a string: ',
    TryEncodeMonitorFrame('{"a":"x' + #10 + 'y"}', Bytes, Status));
  FillAwkwardView(View);
  Root := RoundTrip(MonitorSyncStateFrame('state-status', 'status', MonitorStatusValueJson(View)));
  Try
    Value := StateValue(Root, 'status');
    Check('codec status frames and decodes', Assigned(Value));
    Check('codec status text round-trips', SameBytes(TextField(Value, 'status_text'), Awkward));
    Check('codec error text round-trips', SameBytes(TextField(Value, 'error_text'), Awkward));
  Finally
    Root.Free;
  End;
  Root := RoundTrip(MonitorSyncStateFrame('state-session', 'session', MonitorSessionValueJson(View)));
  Try
    Value := StateValue(Root, 'session');
    Check('codec session frames and decodes', Assigned(Value));
    Check('codec model round-trips', SameBytes(TextField(Value, 'model'), Awkward));
    Check('codec context text round-trips', SameBytes(TextField(Value, 'context_text'), Awkward));
    Check('codec approval caption round-trips', SameBytes(TextField(Value, 'approval_caption'), Awkward));
  Finally
    Root.Free;
  End;
  Root := RoundTrip(MonitorSyncStateFrame('state-target', 'target', MonitorTargetValueJson(View)));
  Try
    Value := StateValue(Root, 'target');
    Check('codec target frames and decodes', Assigned(Value));
    Check('codec target display round-trips', SameBytes(TextField(Value, 'display'), Awkward));
    Check('codec target root keeps the Windows path', SameBytes(TextField(Value, 'root'), WindowsPath));
  Finally
    Root.Free;
  End;
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Paths.Add(WindowsPath);
    Paths.Add('D:\Work\"quoted"');
    Captions.Add(Awkward);
    Captions.Add('Second');
    Root := RoundTrip(MonitorSyncStateFrame('state-targets', 'targets', MonitorTargetsValueJson(WindowsPath, Paths, Captions)));
    Try
      Value := StateValue(Root, 'targets');
      Check('codec targets frame and decode', Assigned(Value));
      Check('codec targets current keeps the Windows path', SameBytes(TextField(Value, 'current'), WindowsPath));
      CheckChoice('codec targets', Value, 0, WindowsPath, Awkward);
      CheckChoice('codec targets', Value, 1, 'D:\Work\"quoted"', 'Second');
    Finally
      Root.Free;
    End;
    Root := RoundTrip(MonitorSyncStateFrame('state-conversations', 'conversations',
      MonitorConversationsValueJson(Awkward, True, Paths, Captions)));
    Try
      Value := StateValue(Root, 'conversations');
      Check('codec conversations frame and decode', Assigned(Value));
      Check('codec conversations current round-trips', SameBytes(TextField(Value, 'current'), Awkward));
      Check('codec conversations keep truncated', BoolField(Value, 'truncated'));
      CheckChoice('codec conversations', Value, 0, WindowsPath, Awkward);
    Finally
      Root.Free;
    End;
    Root := RoundTrip(MonitorSyncStateFrame('state-models', 'models',
      MonitorNamedChoicesValueJson(Awkward, 'claude', Awkward, True, Paths, Captions)));
    Try
      Value := StateValue(Root, 'models');
      Check('codec models frame and decode', Assigned(Value));
      Check('codec models note round-trips', SameBytes(TextField(Value, 'note'), Awkward));
      Check('codec models name the backend', TextField(Value, 'backend') = 'claude');
      CheckChoice('codec models', Value, 0, WindowsPath, Awkward);
    Finally
      Root.Free;
    End;
    Root := RoundTrip(MonitorSyncStateFrame('state-reasoning', 'reasoning',
      MonitorNamedChoicesValueJson('high', '', Awkward, False, Paths, Captions)));
    Try
      Value := StateValue(Root, 'reasoning');
      Check('codec reasoning frames and decodes', Assigned(Value));
      Check('codec reasoning has no backend field', Assigned(Value) And (Value.Find('backend') = Nil));
      Check('codec reasoning note round-trips', SameBytes(TextField(Value, 'note'), Awkward));
    Finally
      Root.Free;
    End;
    Root := RoundTrip(MonitorSyncStateFrame('state-plan-choices', 'plan_choices', MonitorPlanChoicesValueJson(Paths, Captions)));
    Try
      Value := StateValue(Root, 'plan_choices');
      Check('codec plan choices frame and decode', Assigned(Value));
      CheckChoice('codec plan choices', Value, 1, 'D:\Work\"quoted"', 'Second');
    Finally
      Root.Free;
    End;
  Finally
    Captions.Free;
    Paths.Free;
  End;
  FillAwkwardRows(Rows);
  Root := RoundTrip(MonitorSyncStateFrame('state-plan', 'plan', MonitorPlanValueJson(PlanPath, Awkward, True, 'rev-1', Rows)));
  Try
    Value := StateValue(Root, 'plan');
    Item := ArrayItem(Value, 'rows', 0);
    Check('codec plan frames and decodes', Assigned(Value));
    Check('codec plan path round-trips', SameBytes(TextField(Value, 'path'), PlanPath));
    Check('codec plan title round-trips', SameBytes(TextField(Value, 'title'), Awkward));
    Check('codec plan row title round-trips', SameBytes(TextField(Item, 'title'), Awkward));
    Check('codec plan row parent title round-trips', SameBytes(TextField(Item, 'parent_title'), Awkward));
  Finally
    Root.Free;
  End;
  SetLength(Tasks, 1);
  Tasks[0] := Default(TAssistantMonitorTaskRow);
  Tasks[0].Id := 'review';
  Tasks[0].Title := Awkward;
  Tasks[0].Summary := Awkward;
  Tasks[0].Mode := 'plan';
  Root := RoundTrip(MonitorSyncStateFrame('state-tasks', 'tasks', MonitorTasksValueJson(Tasks)));
  Try
    Item := ArrayItem(StateValue(Root, 'tasks'), 'rows', 0);
    Check('codec tasks frame and decode', Assigned(Item));
    Check('codec task title round-trips', SameBytes(TextField(Item, 'title'), Awkward));
    Check('codec task summary round-trips', SameBytes(TextField(Item, 'summary'), Awkward));
  Finally
    Root.Free;
  End;
  Root := RoundTrip(MonitorSyncStateFrame('state-approval', 'approval', MonitorApprovalValueJson(True, ToolId)));
  Try
    Value := StateValue(Root, 'approval');
    Check('codec approval frames and decodes', Assigned(Value) And BoolField(Value, 'active'));
    Check('codec approval tool id round-trips', SameBytes(TextField(Value, 'tool_id'), ToolId));
  Finally
    Root.Free;
  End;
  Root := RoundTrip(MonitorSyncStateFrame('state-conversation', 'conversation', MonitorConversationValueJson(Awkward)));
  Try
    Check('codec conversation id round-trips', SameBytes(TextField(StateValue(Root, 'conversation'), 'id'), Awkward));
  Finally
    Root.Free;
  End;
End;

Procedure FillAwkwardTurn(Out Turn: TAssistantMonitorTurn);
Begin
  Turn := Default(TAssistantMonitorTurn);
  Turn.Id := 'turn-escape';
  Turn.TurnIndex := 0;
  Turn.Mode := 'build';
  Turn.Prompt := AwkwardText;
  Turn.PromptPreview := AwkwardText;
  Turn.CreatedAt := '2026-11-05T12:00:00Z';
  Turn.Live := False;
  SetLength(Turn.Blocks, 1);
  Turn.Blocks[0] := Default(TAssistantMonitorBlock);
  Turn.Blocks[0].Kind := 'answer';
  Turn.Blocks[0].BlockId := 'turn-escape:0 "b" \';
  Turn.Blocks[0].Title := AwkwardText;
  Turn.Blocks[0].Body := AwkwardText;
  Turn.Blocks[0].Ok := True;
  Turn.Blocks[0].Revision := 3;
End;

Procedure TestMirrorPage;
Var
  Turn: TAssistantMonitorTurn;
  Root, Block: TJSONObject;
Begin
  FillAwkwardTurn(Turn);
  Root := RoundTrip(MonitorTurnPageJson('conversation "q"', 'ab12cd34', 1, Turn));
  Try
    Block := ArrayItem(ObjectField(Root, 'turn'), 'blocks', 0);
    Check('mirror turn page frames and decodes', Assigned(Block));
    Check('mirror conversation id round-trips', SameBytes(TextField(Root, 'conversation_id'), 'conversation "q"'));
    Check('mirror block id round-trips', SameBytes(TextField(Block, 'block_id'), Turn.Blocks[0].BlockId));
    Check('mirror block title round-trips', SameBytes(TextField(Block, 'title'), AwkwardText));
    Check('mirror block body round-trips', SameBytes(TextField(Block, 'body'), AwkwardText));
  Finally
    Root.Free;
  End;
End;

{ The newest sent frame of this type, decoded. The caller frees Root. }
Function FindSent(Const TypeName: String; Out Root: TJSONObject): TJSONObject;
Var
  Index: Integer;
Begin
  Result := Nil;
  Root := Nil;
  For Index := Carrier.SentCount - 1 DownTo 0 Do
    Begin
      Root := RoundTrip(Carrier.SentJson(Index));
      If Assigned(Root) And (TextField(Root, 'type') = TypeName) Then
        Begin
          Result := ObjectField(Root, 'payload');
          Exit;
        End;
      FreeAndNil(Root);
    End;
End;

{ The newest sent state value for Key, decoded. The caller frees Root. }
Function FindSentState(Const Key: String; Out Root: TJSONObject): TJSONObject;
Var
  Index: Integer;
Begin
  Result := Nil;
  Root := Nil;
  For Index := Carrier.SentCount - 1 DownTo 0 Do
    Begin
      Root := RoundTrip(Carrier.SentJson(Index));
      Result := StateValue(Root, Key);
      If Assigned(Result) Then
        Exit;
      FreeAndNil(Root);
    End;
End;

Procedure CheckEverySentFrame(Const Title: String);
Var
  Index, Bad: Integer;
  Root: TJSONObject;
Begin
  Bad := 0;
  For Index := 0 To Carrier.SentCount - 1 Do
    Begin
      Root := RoundTrip(Carrier.SentJson(Index));
      If Not Assigned(Root) Then
        Begin
          Inc(Bad);
          WriteLn('detail ', Title, ' bad frame ', Copy(Carrier.SentJson(Index), 1, 200));
        End;
      Root.Free;
    End;
  Check(Title + ' sent frames', Carrier.SentCount > 0);
  Check(Title + ' every sent frame passes TryDecodeMonitorFrame', Bad = 0);
End;

Function GoLive: Boolean;
Var
  Spare: TMonitorFrame;
  ErrorText: String;
Begin
  Result := False;
  If Not Session.StartListening('127.0.0.1', 56124, ErrorText) Then
    Exit;
  If Not Session.AcceptHandshake(Spare, True) Then
    Exit;
  Carrier.DeliverJson(EncodeMonitorHello('hello', 'Phone', '1', ''));
  { Loopback with no armed code admits the pair. }
  Carrier.DeliverJson(EncodeMonitorPair('pair', '', ''));
  Result := Session.State = mssLive;
End;

Procedure TestSessionFrames;
Var
  Awkward, ToolId, ConversationId, Json: String;
  View: TAssistantMonitorView;
  Paths, Captions: TStringList;
  Rows: TMonitorMirrorPlanArray;
  Turn: TAssistantMonitorTurn;
  Payload, Root, Value: TJSONObject;
Begin
  Awkward := AwkwardText;
  ToolId := 'tool "7" \ ' + #9 + 'x';
  ConversationId := 'conversation "q" \ ' + #27 + 'z';
  Check('session reaches live', GoLive);
  Session.DrainOutbound;
  Carrier.ClearSent;
  FillAwkwardView(View);
  FillAwkwardRows(Rows);
  Paths := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Paths.Add(WindowsPath);
    Captions.Add(Awkward);
    Session.PublishState('status', MonitorStatusValueJson(View));
    Session.PublishState('target', MonitorTargetValueJson(View));
    Session.PublishState('targets', MonitorTargetsValueJson(WindowsPath, Paths, Captions));
    Session.PublishState('conversations', MonitorConversationsValueJson(Awkward, False, Paths, Captions));
    Session.PublishState('plan', MonitorPlanValueJson(PlanPath, Awkward, True, 'rev-1', Rows));
  Finally
    Captions.Free;
    Paths.Free;
  End;
  Session.DrainOutbound;
  CheckEverySentFrame('session state');
  Value := FindSentState('status', Root);
  Try
    Check('session status text round-trips', SameBytes(TextField(Value, 'status_text'), Awkward));
  Finally
    Root.Free;
  End;
  Value := FindSentState('target', Root);
  Try
    Check('session target root keeps the Windows path', SameBytes(TextField(Value, 'root'), WindowsPath));
  Finally
    Root.Free;
  End;
  Value := FindSentState('targets', Root);
  Try
    CheckChoice('session targets', Value, 0, WindowsPath, Awkward);
  Finally
    Root.Free;
  End;
  Value := FindSentState('conversations', Root);
  Try
    Check('session conversations current round-trips', SameBytes(TextField(Value, 'current'), Awkward));
    CheckChoice('session conversations', Value, 0, WindowsPath, Awkward);
  Finally
    Root.Free;
  End;
  Value := FindSentState('plan', Root);
  Try
    Check('session plan row title round-trips', SameBytes(TextField(ArrayItem(Value, 'rows', 0), 'title'), Awkward));
  Finally
    Root.Free;
  End;
  { HandleResume writes the pending tool id and the conversation id. The snapshot names the title and root. }
  Session.SetRemoteApproval(True);
  Session.NoteApprovalRequested(ToolId, True);
  Session.BeginMirrorEpoch('ab12cd34', ConversationId, WindowsPath, Awkward);
  FillAwkwardTurn(Turn);
  Session.ObserveTurn(Turn);
  Session.DrainOutbound;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorResume('resume-escape', '', 0));
  CheckEverySentFrame('session resume');
  Value := FindSentState('approval', Root);
  Try
    Check('session resume approval is active', BoolField(Value, 'active'));
    Check('session resume tool id round-trips', SameBytes(TextField(Value, 'tool_id'), ToolId));
  Finally
    Root.Free;
  End;
  Value := FindSentState('conversation', Root);
  Try
    Check('session resume conversation id round-trips', SameBytes(TextField(Value, 'id'), ConversationId));
  Finally
    Root.Free;
  End;
  Value := FindSent('snapshot_begin', Root);
  Try
    Check('session snapshot title round-trips', SameBytes(TextField(Value, 'title'), Awkward));
    Check('session snapshot root keeps the Windows path', SameBytes(TextField(Value, 'project_root'), WindowsPath));
  Finally
    Root.Free;
  End;
  Value := FindSent('snapshot_page', Root);
  Try
    Check('session snapshot block id round-trips',
      SameBytes(TextField(ArrayItem(ArrayItem(Value, 'turns', 0), 'blocks', 0), 'block_id'), Turn.Blocks[0].BlockId));
    Check('session snapshot prompt preview round-trips',
      SameBytes(TextField(ArrayItem(Value, 'turns', 0), 'prompt_preview'), Awkward));
  Finally
    Root.Free;
  End;
  { ServeBlockGet echoes the phone's request id and block id in revision_changed. }
  Payload := TJSONObject.Create;
  Try
    Payload.Add('block_id', Turn.Blocks[0].BlockId);
    Payload.Add('offset', 0);
    Payload.Add('revision', 1);
    Json := '{"v":3,"id":"block-escape","type":"block_get","payload":' + Payload.AsJSON + '}';
  Finally
    Payload.Free;
  End;
  Carrier.ClearSent;
  Carrier.DeliverJson(Json);
  CheckEverySentFrame('session revision_changed');
  Value := FindSent('revision_changed', Root);
  Try
    Check('session revision_changed names the request', TextField(Value, 'ref') = 'block-escape');
    Check('session revision_changed block id round-trips', SameBytes(TextField(Value, 'block_id'), Turn.Blocks[0].BlockId));
  Finally
    Root.Free;
  End;
  Session.NoteApprovalClosed(ToolId);
  Session.SetRemoteApproval(False);
End;

Procedure PrepareSettings;
Var
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-escape-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
End;

Procedure CleanupSettings;
Begin
  If SettingsRoot = '' Then
    Exit;
  If WorkflowSettingsPath <> '' Then
    Begin
      DeleteFile(WorkflowSettingsPath);
      DeleteFile(WorkflowSettingsPath + '.tmp');
    End;
  SetWorkflowSettingsDirectory('');
  RemoveDir(ExcludeTrailingPathDelimiter(SettingsRoot));
  SettingsRoot := '';
End;

Begin
  FailCount := 0;
  Carrier := Nil;
  CarrierRef := Nil;
  Session := Nil;
  SettingsRoot := '';
  Try
    Try
      TestStateWriters;
      TestMirrorPage;
      PrepareSettings;
      Carrier := TMonitorMemoryCarrier.Create;
      CarrierRef := Carrier;
      Session := TMonitorSession.Create;
      Session.AttachCarrier(CarrierRef);
      Session.NoteTime(5000);
      TestSessionFrames;
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    If Assigned(Session) Then
      Session.Free;
    CarrierRef := Nil;
    Carrier := Nil;
    CleanupSettings;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorEscapeTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorEscapeTest test(s) failed.');
      Halt(1);
    End;
End.
