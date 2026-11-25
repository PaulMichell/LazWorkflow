Unit AssistantMonitorCodec;

{ Version 4 JSON encoders for the monitor contract (c) 2026 Michell Computing.

  The listener and the fixture test both call these functions. A golden file
  that changes without a matching encoder change fails that test. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, AssistantMonitorSnapshot;

Function MonitorJsonQuote(Const Value: String): String;
Function MonitorErrorJson(Const Reason, MessageText: String): String;
Function MonitorDoneJson(Const State, TurnId: String): String;
Function MonitorPairJson(Const Token, HostName, Fingerprint: String): String;
Function MonitorHelloJson(Const Epoch: String; Rev: Int64; Capabilities: TStrings): String;
Function MonitorPulseJson(Snap: TMonitorSnapshot; Const Epoch, ServerTime: String; NilStopPending: Boolean = False): String;
Function MonitorApprovalBody(Const ToolId, ToolName, Summary, ModeCaption: String; DecisionsAccepted: Boolean): String;
Function MonitorPlanJson(Const Path, Title, ETag: String; Running: Boolean; Const RowsJson: String): String;
Function MonitorChoiceListJson(Const Kind, BodyJson: String): String;
Function MonitorImageMetaJson(Const ContentType, CacheControl: String; MaxBytes: Integer): String;
Function MonitorCommandRequestJson(Const CommandId, Kind, ArgsJson: String): String;
Function MonitorConversationJson(Const Id, Title, CreatedAt, ETag: String; TurnCount: Integer; Current: Boolean): String;
Function MonitorTurnsPageJson(Const Id, ETag: String; FromIndex, NextIndex, TurnCount: Integer; Const TurnsJson: String): String;
Function MonitorTurnJson(Const Id, ETag, Mode, Prompt, CreatedAt, ErrorText, ItemsJson: String; Live: Boolean): String;
Function MonitorItemJson(Const Id, State, Text: String; Rev: Int64; TotalBytes, StartAt: Integer): String;

Implementation

Uses
  SysUtils;

Function MonitorJsonQuote(Const Value: String): String;
Var
  Index: Integer;
  C: Char;
Begin
  Result := '"';
  For Index := 1 To Length(Value) Do
    Begin
      C := Value[Index];
      Case C Of
        '"', '\': Result := Result + '\' + C;
        #8: Result := Result + '\b';
        #9: Result := Result + '\t';
        #10: Result := Result + '\n';
        #13: Result := Result + '\r';
      Else
        Result := Result + C;
      End;
    End;
  Result := Result + '"';
End;

Function BoolText(Value: Boolean): String;
Begin
  If Value Then
    Result := 'true'
  Else
    Result := 'false';
End;

Function MonitorErrorJson(Const Reason, MessageText: String): String;
Begin
  Result := '{"reason":' + MonitorJsonQuote(Reason) + ',"message":' + MonitorJsonQuote(MessageText) + '}';
End;

Function MonitorDoneJson(Const State, TurnId: String): String;
Begin
  Result := '{"state":' + MonitorJsonQuote(State);
  If TurnId <> '' Then
    Result := Result + ',"turn_id":' + MonitorJsonQuote(TurnId);
  Result := Result + '}';
End;

Function MonitorPairJson(Const Token, HostName, Fingerprint: String): String;
Begin
  Result := '{"token":' + MonitorJsonQuote(Token) + ',"host_name":' + MonitorJsonQuote(HostName) +
    ',"fingerprint":' + MonitorJsonQuote(Fingerprint) + '}';
End;

Function MonitorHelloJson(Const Epoch: String; Rev: Int64; Capabilities: TStrings): String;
Var
  Index: Integer;
  List: String;
Begin
  List := '';
  If Assigned(Capabilities) Then
    For Index := 0 To Capabilities.Count - 1 Do
      Begin
        If List <> '' Then
          List := List + ',';
        List := List + MonitorJsonQuote(Capabilities[Index]);
      End;
  Result := '{"epoch":' + MonitorJsonQuote(Epoch) + ',"rev":' + IntToStr(Rev) + ',"capabilities":[' + List + ']}';
End;

Function LiveJson(Snap: TMonitorSnapshot): String;
Var
  Index, Chosen: Integer;
  Item: String;
Begin
  If Not Assigned(Snap) Or (Not Snap.HasLive) Or (Not Snap.Sending) Or (Snap.LiveTurnId = '') Then
    Exit('null');
  Chosen := -1;
  For Index := 0 To High(Snap.Items) Do
    If Snap.Items[Index].State = 'running' Then
      Chosen := Index;
  If (Chosen < 0) And (Length(Snap.Items) > 0) Then
    Chosen := High(Snap.Items);
  If Chosen < 0 Then
    Item := 'null'
  Else
    Item := '{"id":' + MonitorJsonQuote(String(Snap.Items[Chosen].Id)) +
      ',"kind":' + MonitorJsonQuote(String(Snap.Items[Chosen].Kind)) +
      ',"state":' + MonitorJsonQuote(String(Snap.Items[Chosen].State)) +
      ',"rev":' + IntToStr(Snap.Items[Chosen].Revision) +
      ',"bytes":' + IntToStr(Length(Snap.Items[Chosen].Body)) + '}';
  Result := '{"turn_id":' + MonitorJsonQuote(String(Snap.LiveTurnId)) +
    ',"turn_index":' + IntToStr(Snap.LiveTurnIndex) +
    ',"rev":' + IntToStr(Snap.LiveRev) +
    ',"item":' + Item + '}';
End;

Function MonitorPulseJson(Snap: TMonitorSnapshot; Const Epoch, ServerTime: String; NilStopPending: Boolean = False): String;
Var
  Status, Conversation, Plan, Lists, Approval: String;
Begin
  If Assigned(Snap) Then
    Begin
      Status := '{"available":' + BoolText(Snap.Available) + ',"busy":' + BoolText(Snap.Busy) +
        ',"sending":' + BoolText(Snap.Sending) + ',"plan_running":' + BoolText(Snap.PlanRunning) +
        ',"mode":' + MonitorJsonQuote(String(Snap.Mode)) + ',"phase":' + MonitorJsonQuote(String(Snap.Phase)) +
        ',"status_text":' + MonitorJsonQuote(String(Snap.StatusText)) +
        ',"activity":' + MonitorJsonQuote(String(Snap.Activity)) +
        ',"activity_since":' + MonitorJsonQuote(String(Snap.ActivitySince)) +
        ',"turn_started_at":' + MonitorJsonQuote(String(Snap.TurnStartedAt)) +
        ',"can_send":' + BoolText(Snap.CanSend) + ',"can_steer":' + BoolText(Snap.CanSteer) +
        ',"can_stop":' + BoolText(Snap.CanStop) + ',"can_change_mode":' + BoolText(Snap.CanChangeMode) +
        ',"stop_pending":' + BoolText(Snap.StopPending Or NilStopPending) + ',"remote_approval":' + BoolText(Snap.RemoteApproval) +
        ',"error_text":' + MonitorJsonQuote(String(Snap.ErrorText)) +
        ',"usage_caption":' + MonitorJsonQuote(String(Snap.UsageCaption)) +
        ',"usage_hint":' + MonitorJsonQuote(String(Snap.UsageHint)) + '}';
      Conversation := '{"id":' + MonitorJsonQuote(String(Snap.ConversationId)) +
        ',"title":' + MonitorJsonQuote(String(Snap.ConversationTitle)) +
        ',"etag":' + MonitorJsonQuote(String(Snap.ConversationEtag)) +
        ',"turn_count":' + IntToStr(Snap.TurnCount) + '}';
      Plan := '{"path":' + MonitorJsonQuote(String(Snap.PlanPath)) +
        ',"etag":' + MonitorJsonQuote(String(Snap.PlanEtag)) +
        ',"running":' + BoolText(Snap.PlanItemRunning) +
        ',"item":' + MonitorJsonQuote(String(Snap.PlanItem)) + '}';
      Lists := '{"conversations":' + MonitorJsonQuote(String(Snap.ListConversations)) +
        ',"plans":' + MonitorJsonQuote(String(Snap.ListPlans)) +
        ',"tasks":' + MonitorJsonQuote(String(Snap.ListTasks)) + '}';
      If Snap.ApprovalActive Then
        Approval := '{"id":' + MonitorJsonQuote(String(Snap.ApprovalId)) +
          ',"tool_name":' + MonitorJsonQuote(String(Snap.ApprovalTool)) + '}'
      Else
        Approval := 'null';
    End
  Else
    Begin
      Status := '{"stop_pending":' + BoolText(NilStopPending) + '}';
      Conversation := '{"id":"","title":"","etag":"","turn_count":0}';
      Plan := '{"path":"","etag":"","running":false,"item":""}';
      Lists := '{"conversations":"","plans":"","tasks":""}';
      Approval := 'null';
    End;
  Result := '{"epoch":' + MonitorJsonQuote(Epoch) + ',"rev":' + IntToStr(0) + ',"server_time":' +
    MonitorJsonQuote(ServerTime) + ',"status":' + Status + ',"conversation":' + Conversation +
    ',"live":' + LiveJson(Snap) + ',"plan":' + Plan + ',"lists":' + Lists + ',"approval":' + Approval + '}';
  If Assigned(Snap) Then
    Result := '{"epoch":' + MonitorJsonQuote(Epoch) + ',"rev":' + IntToStr(Snap.Rev) + ',"server_time":' +
      MonitorJsonQuote(ServerTime) + ',"status":' + Status + ',"conversation":' + Conversation +
      ',"live":' + LiveJson(Snap) + ',"plan":' + Plan + ',"lists":' + Lists + ',"approval":' + Approval + '}';
End;

Function MonitorApprovalBody(Const ToolId, ToolName, Summary, ModeCaption: String; DecisionsAccepted: Boolean): String;
Begin
  Result := '{"id":' + MonitorJsonQuote(ToolId) + ',"tool_name":' + MonitorJsonQuote(ToolName) +
    ',"summary":' + MonitorJsonQuote(Summary) + ',"mode_caption":' + MonitorJsonQuote(ModeCaption) +
    ',"decisions_accepted":' + BoolText(DecisionsAccepted) + '}';
End;

Function MonitorPlanJson(Const Path, Title, ETag: String; Running: Boolean; Const RowsJson: String): String;
Begin
  Result := '{"path":' + MonitorJsonQuote(Path) + ',"title":' + MonitorJsonQuote(Title) +
    ',"etag":' + MonitorJsonQuote(ETag) + ',"running":' + BoolText(Running) + ',"rows":' + RowsJson + '}';
End;

Function MonitorChoiceListJson(Const Kind, BodyJson: String): String;
Begin
  Result := '{"kind":' + MonitorJsonQuote(Kind) + ',"items":' + BodyJson + '}';
End;

Function MonitorImageMetaJson(Const ContentType, CacheControl: String; MaxBytes: Integer): String;
Begin
  Result := '{"content_type":' + MonitorJsonQuote(ContentType) + ',"cache_control":' + MonitorJsonQuote(CacheControl) +
    ',"max_bytes":' + IntToStr(MaxBytes) + '}';
End;

Function MonitorCommandRequestJson(Const CommandId, Kind, ArgsJson: String): String;
Begin
  Result := '{"id":' + MonitorJsonQuote(CommandId) + ',"type":' + MonitorJsonQuote(Kind) + ',"args":' + ArgsJson + '}';
End;

Function MonitorConversationJson(Const Id, Title, CreatedAt, ETag: String; TurnCount: Integer; Current: Boolean): String;
Begin
  Result := '{"id":' + MonitorJsonQuote(Id) + ',"title":' + MonitorJsonQuote(Title) +
    ',"created_at":' + MonitorJsonQuote(CreatedAt) + ',"turn_count":' + IntToStr(TurnCount) +
    ',"etag":' + MonitorJsonQuote(ETag) + ',"current":' + BoolText(Current) + '}';
End;

Function MonitorTurnsPageJson(Const Id, ETag: String; FromIndex, NextIndex, TurnCount: Integer; Const TurnsJson: String): String;
Var
  NextText: String;
Begin
  If NextIndex >= TurnCount Then
    NextText := 'null'
  Else
    NextText := IntToStr(NextIndex);
  Result := '{"id":' + MonitorJsonQuote(Id) + ',"etag":' + MonitorJsonQuote(ETag) +
    ',"from":' + IntToStr(FromIndex) + ',"turns":' + TurnsJson + ',"next":' + NextText + '}';
End;

Function MonitorTurnJson(Const Id, ETag, Mode, Prompt, CreatedAt, ErrorText, ItemsJson: String; Live: Boolean): String;
Begin
  Result := '{"id":' + MonitorJsonQuote(Id) + ',"etag":' + MonitorJsonQuote(ETag) + ',"live":' + BoolText(Live) +
    ',"mode":' + MonitorJsonQuote(Mode) + ',"prompt":' + MonitorJsonQuote(Prompt) +
    ',"created_at":' + MonitorJsonQuote(CreatedAt) + ',"error":' + MonitorJsonQuote(ErrorText) +
    ',"items":' + ItemsJson + '}';
End;

Function MonitorItemJson(Const Id, State, Text: String; Rev: Int64; TotalBytes, StartAt: Integer): String;
Begin
  Result := '{"id":' + MonitorJsonQuote(Id) + ',"rev":' + IntToStr(Rev) + ',"state":' + MonitorJsonQuote(State) +
    ',"total_bytes":' + IntToStr(TotalBytes) + ',"start":' + IntToStr(StartAt) + ',"text":' + MonitorJsonQuote(Text) + '}';
End;

End.
