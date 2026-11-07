Unit AssistantMonitorState;

{ State codecs for the monitor catalogue. Menus, plan, tasks, approval, and status fields. Not a second sync unit.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantMonitorCodec, AssistantSessionObserve;

Function EncodeStateTarget(Const Id, Kind, Display, Root: String): String;
Function DecodeStateTarget(Const PayloadJson: TMonitorPayload; Out Target: TMonitorTargetMessage): Boolean;
Function EncodeStateTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
Function DecodeStateTargets(Const PayloadJson: TMonitorPayload; Out Targets: TMonitorTargetsMessage): Boolean;
Function EncodeStateConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
Function DecodeStateConversations(Const PayloadJson: TMonitorPayload; Out Conversations: TMonitorConversationsMessage): Boolean;
Function EncodeNamedChoices(Kind: TMonitorMessageKind; Const Id, Current, Note: String; Ids, Captions: TStrings;
  Const ExtraName, ExtraValue: String; HasExtra: Boolean): String;
Function DecodeNamedChoices(Const PayloadJson: TMonitorPayload; Out Current, Note: String; Out Ids, Captions: TStringList;
  Const ExtraName: String; WantExtra: Boolean; Out ExtraValue: String): Boolean;
Function EncodeStateModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeStateModels(Const PayloadJson: TMonitorPayload; Out Models: TMonitorModelsMessage): Boolean;
Function EncodeStateReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Function EncodeStatePermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Function DecodeStatePermissions(Const PayloadJson: TMonitorPayload; Out Permissions: TMonitorPermissionsMessage): Boolean;
Function DecodeStateReasoning(Const PayloadJson: TMonitorPayload; Out Reasoning: TMonitorReasoningMessage): Boolean;
Function EncodeStateApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Function DecodeStateApprovalRequested(Const PayloadJson: TMonitorPayload; Out Notice: TAssistantApprovalNotice): Boolean;
Function EncodeStateApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Function DecodeStateApprovalDecision(Const PayloadJson: TMonitorPayload; Out Decision: TMonitorApprovalDecision): Boolean;
Function EncodeStateApprovalClosed(Const Id, ToolId, Reason: String): String;
Function DecodeStateApprovalClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorApprovalClosed): Boolean;
Procedure StateClearView(Out View: TAssistantMonitorView);
Procedure AddStatusFields(Obj: TJSONObject; Const View: TAssistantMonitorView);
Function StateReadStatusFields(Obj: TJSONObject; Var View: TAssistantMonitorView): Boolean;
Function StateStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Function TryStateStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Function PlanRowToJson(Const Row: TAssistantMonitorPlanRow): TJSONObject;
Function TryStatePlanRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorPlanRow): Boolean;
Function StatePlanRowsToJson(Const Rows: Array Of TAssistantMonitorPlanRow): TJSONArray;
Function TaskRowToJson(Const Row: TAssistantMonitorTaskRow): TJSONObject;
Function TryStateTaskRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorTaskRow): Boolean;
Function StateTaskRowsToJson(Const Rows: Array Of TAssistantMonitorTaskRow): TJSONArray;
Function PlanPayload(Const Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings;
  Const Epoch: String; Cursor: Int64; Const Body: String; Complete: Boolean): TJSONObject;
Function EncodeStatePlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings; Captions: TStrings;
  Const Epoch: String; Cursor: Int64; Const Body: String; Complete: Boolean): String;
Function PackStatePlanFrames(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings; Const Body: String; Complete: Boolean;
  Out Frames: TStringArray): Boolean;
Function DecodeStatePlan(Const PayloadJson: TMonitorPayload; Out Path, Title: String; Out Running: Boolean;
  Out Rows: TMonitorSnapshot): Boolean;
Function EncodeStateTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Function StateApprovalToJson(Const Notice: TAssistantApprovalNotice): TJSONObject;
Function TryStateApprovalFromJson(Obj: TJSONObject; Out Notice: TAssistantApprovalNotice): Boolean;
Function EncodeStateConversationClosed(Const Id, Epoch: String; Cursor: Int64;
  Const ConversationId, Title: String): String;
Function DecodeStateConversationClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorConversationClosed): Boolean;

Implementation

Function EncodeStateTarget(Const Id, Kind, Display, Root: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('kind', Kind);
  Payload.Add('display', Display);
  Payload.Add('root', Root);
  Result := EncodeMonitorWith(mmkTarget, Id, Payload);
End;

Function DecodeStateTarget(Const PayloadJson: TMonitorPayload; Out Target: TMonitorTargetMessage): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Target.Kind := '';
  Target.Display := '';
  Target.Root := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'kind', True, Target.Kind) And ReadMonitorString(Obj, 'display', True, Target.Display) And
      ReadMonitorString(Obj, 'root', True, Target.Root);
  Finally
    Data.Free;
  End;
End;

Function EncodeStateTargets(Const Id, Current: String; Paths, Captions: TStrings): String;
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
  Result := EncodeMonitorWith(mmkTargets, Id, Payload);
End;

Function DecodeStateTargets(Const PayloadJson: TMonitorPayload; Out Targets: TMonitorTargetsMessage): Boolean;
Var
  Data, Node, Item: TJSONData;
  Obj, Choice: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
Begin
  Result := False;
  Targets.Current := '';
  SetLength(Targets.Choices, 0);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadMonitorString(Obj, 'current', True, Targets.Current) Then
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
        If Not ReadMonitorString(Choice, 'path', True, Targets.Choices[Index].Path) Or
          Not ReadMonitorString(Choice, 'caption', True, Targets.Choices[Index].Caption) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeStateConversations(Const Id, Current: String; Ids, Titles: TStrings; Truncated: Boolean): String;
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
  Result := EncodeMonitorWith(mmkConversations, Id, Payload);
End;

Function DecodeStateConversations(Const PayloadJson: TMonitorPayload; Out Conversations: TMonitorConversationsMessage): Boolean;
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
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not ReadMonitorString(Obj, 'current', True, Conversations.Current) Then
      Exit;
    If Not ReadMonitorBool(Obj, 'truncated', True, Conversations.Truncated) Then
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
        If Not ReadMonitorString(Choice, 'id', True, Conversations.Choices[Index].Id) Or
          Not ReadMonitorString(Choice, 'title', True, Conversations.Choices[Index].Title) Or
          Not ReadMonitorBool(Choice, 'current', True, Conversations.Choices[Index].Current) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
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
  Result := EncodeMonitorWith(Kind, Id, Payload);
End;

Function DecodeNamedChoices(Const PayloadJson: TMonitorPayload; Out Current, Note: String; Out Ids, Captions: TStringList;
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
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    If Not ReadMonitorString(Obj, 'current', True, Current) Then
      Exit;
    If WantExtra And (Not ReadMonitorString(Obj, ExtraName, True, ExtraValue)) Then
      Exit;
    If Not ReadMonitorString(Obj, 'note', True, Note) Then
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
        If Not ReadMonitorString(Choice, 'id', True, ChoiceId) Or Not ReadMonitorString(Choice, 'caption', True, ChoiceCaption) Then
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

Function EncodeStateModels(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkModels, Id, Current, Note, Ids, Captions, 'backend', Backend, True);
End;

Function DecodeStateModels(Const PayloadJson: TMonitorPayload; Out Models: TMonitorModelsMessage): Boolean;
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

Function EncodeStateReasoning(Const Id, Current, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkReasoning, Id, Current, Note, Ids, Captions, '', '', False);
End;

Function EncodeStatePermissions(Const Id, Current, Backend, Note: String; Ids, Captions: TStrings): String;
Begin
  Result := EncodeNamedChoices(mmkPermissions, Id, Current, Note, Ids, Captions, 'backend', Backend, True);
End;

Function DecodeStatePermissions(Const PayloadJson: TMonitorPayload; Out Permissions: TMonitorPermissionsMessage): Boolean;
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

Function DecodeStateReasoning(Const PayloadJson: TMonitorPayload; Out Reasoning: TMonitorReasoningMessage): Boolean;
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

Function EncodeStateApprovalRequested(Const Id: String; Const Notice: TAssistantApprovalNotice): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', Notice.ToolId);
  Payload.Add('tool_name', Notice.ToolName);
  Payload.Add('summary', Notice.Summary);
  Payload.Add('mode_caption', Notice.ModeCaption);
  Payload.Add('decisions_accepted', Notice.DecisionsAccepted);
  Result := EncodeMonitorWith(mmkApprovalRequested, Id, Payload);
End;

Function DecodeStateApprovalRequested(Const PayloadJson: TMonitorPayload; Out Notice: TAssistantApprovalNotice): Boolean;
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
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'tool_id', True, Notice.ToolId) And ReadMonitorString(Obj, 'tool_name', True, Notice.ToolName) And
      ReadMonitorString(Obj, 'summary', True, Notice.Summary) And ReadMonitorString(Obj, 'mode_caption', True, Notice.ModeCaption) And
      ReadMonitorBool(Obj, 'decisions_accepted', True, Notice.DecisionsAccepted);
  Finally
    Data.Free;
  End;
End;

Function EncodeStateApprovalDecision(Const Id, ToolId: String; Allow: Boolean): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', ToolId);
  Payload.Add('allow', Allow);
  Result := EncodeMonitorWith(mmkApprovalDecision, Id, Payload);
End;

Function DecodeStateApprovalDecision(Const PayloadJson: TMonitorPayload; Out Decision: TMonitorApprovalDecision): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Decision.ToolId := '';
  Decision.Allow := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'tool_id', True, Decision.ToolId) And ReadMonitorBool(Obj, 'allow', True, Decision.Allow);
  Finally
    Data.Free;
  End;
End;

Function EncodeStateApprovalClosed(Const Id, ToolId, Reason: String): String;
Var
  Payload: TJSONObject;
Begin
  Result := '';
  If Not MonitorApprovalCloseReasonIsKnown(Reason) Then
    Exit;
  Payload := TJSONObject.Create;
  Payload.Add('tool_id', ToolId);
  Payload.Add('reason', Reason);
  Result := EncodeMonitorWith(mmkApprovalClosed, Id, Payload);
End;

Function DecodeStateApprovalClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorApprovalClosed): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Closed.ToolId := '';
  Closed.Reason := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'tool_id', True, Closed.ToolId) And ReadMonitorString(Obj, 'reason', True, Closed.Reason) And
      MonitorApprovalCloseReasonIsKnown(Closed.Reason);
  Finally
    Data.Free;
  End;
End;

Procedure StateClearView(Out View: TAssistantMonitorView);
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
  View.StartedAt := '';
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
  Obj.Add('started_at', View.StartedAt);
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

Function StateReadStatusFields(Obj: TJSONObject; Var View: TAssistantMonitorView): Boolean;
Begin
  Result := ReadMonitorBool(Obj, 'available', True, View.Available) And ReadMonitorBool(Obj, 'busy', True, View.Busy) And
    ReadMonitorBool(Obj, 'sending', True, View.Sending) And ReadMonitorBool(Obj, 'mode_locked', True, View.ModeLocked) And
    ReadMonitorBool(Obj, 'plan_running', True, View.PlanRunning) And ReadMonitorString(Obj, 'phase', True, View.Phase) And
    ReadMonitorString(Obj, 'status_text', True, View.StatusText) And ReadMonitorString(Obj, 'model', True, View.Model) And
    ReadMonitorString(Obj, 'backend', True, View.Backend) And ReadMonitorBool(Obj, 'signed_in', True, View.SignedIn) And
    ReadMonitorString(Obj, 'approval_caption', True, View.ApprovalCaption) And ReadMonitorString(Obj, 'effort', True, View.Effort) And
    ReadMonitorString(Obj, 'skill', True, View.Skill) And ReadMonitorString(Obj, 'context_text', True, View.ContextText) And
    ReadMonitorBool(Obj, 'can_send', True, View.CanSend) And ReadMonitorBool(Obj, 'can_steer', True, View.CanSteer) And
    ReadMonitorBool(Obj, 'can_stop', True, View.CanStop) And ReadMonitorBool(Obj, 'can_change_mode', True, View.CanChangeMode) And
    ReadMonitorBool(Obj, 'remote_approval', True, View.RemoteApproval) And ReadMonitorString(Obj, 'error_text', True, View.ErrorText);
  If Result Then
    Begin
      View.ElapsedMs := 0;
      If Not ReadMonitorInt(Obj, 'elapsed_ms', False, View.ElapsedMs) Then
        Result := False;
      If View.ElapsedMs < 0 Then
        View.ElapsedMs := 0;
      View.StartedAt := '';
      If Not ReadMonitorString(Obj, 'started_at', False, View.StartedAt) Then
        Result := False;
      If Not ReadMonitorString(Obj, 'usage_caption', False, View.UsageCaption) Then
        Result := False;
      If Not ReadMonitorString(Obj, 'usage_hint', False, View.UsageHint) Then
        Result := False;
    End;
End;

Function StateStatusToJson(Const View: TAssistantMonitorView): TJSONObject;
Begin
  Result := TJSONObject.Create;
  AddStatusFields(Result, View);
End;

Function TryStateStatusFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Begin
  StateClearView(View);
  Result := Assigned(Obj) And StateReadStatusFields(Obj, View);
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

Function TryStatePlanRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorPlanRow): Boolean;
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
  Result := ReadMonitorInt(Obj, 'index', True, Row.Index) And ReadMonitorInt(Obj, 'level', True, Row.Level) And
    ReadMonitorString(Obj, 'title', True, Row.Title) And ReadMonitorString(Obj, 'parent_title', True, Row.ParentTitle) And
    ReadMonitorString(Obj, 'status', True, Row.Status) And ReadMonitorBool(Obj, 'actionable', True, Row.Actionable);
End;

Function StatePlanRowsToJson(Const Rows: Array Of TAssistantMonitorPlanRow): TJSONArray;
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

Function TryStateTaskRowFromJson(Obj: TJSONObject; Out Row: TAssistantMonitorTaskRow): Boolean;
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
  Result := ReadMonitorString(Obj, 'id', True, Row.Id) And ReadMonitorString(Obj, 'title', True, Row.Title) And
    ReadMonitorString(Obj, 'summary', True, Row.Summary) And ReadMonitorString(Obj, 'mode', True, Row.Mode) And
    ReadMonitorString(Obj, 'kind', True, Row.Kind) And ReadMonitorString(Obj, 'scope', True, Row.Scope) And
    ReadMonitorBool(Obj, 'compile_first', True, Row.CompileFirst) And ReadMonitorBool(Obj, 'enabled', True, Row.Enabled) And
    ReadMonitorBool(Obj, 'needs_note', True, Row.NeedsNote);
End;

Function StateTaskRowsToJson(Const Rows: Array Of TAssistantMonitorTaskRow): TJSONArray;
Var
  I: Integer;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Rows) Do
    Result.Add(TaskRowToJson(Rows[I]));
End;

Function PlanPayload(Const Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings;
  Const Epoch: String; Cursor: Int64; Const Body: String; Complete: Boolean): TJSONObject;
Var
  Choice: TJSONObject;
  Choices: TJSONArray;
  I: Integer;
Begin
  Result := TJSONObject.Create;
  Result.Add('path', Path);
  Result.Add('title', Title);
  Result.Add('running', Running);
  Result.Add('rows', StatePlanRowsToJson(Rows));
  { Absent means this frame has no document text. An empty string is not sent. }
  If Body <> '' Then
    Result.Add('body', Body);
  { Present even when the document is empty, so the phone can clear a deleted file. }
  If Complete Then
    Result.Add('complete', True);
  If Epoch <> '' Then
    Begin
      Result.Add('epoch', Epoch);
      Result.Add('cursor', Cursor);
    End;
  If Assigned(Paths) And Assigned(Captions) Then
    Begin
      Choices := TJSONArray.Create;
      Result.Add('choices', Choices);
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
End;

Function EncodeStatePlan(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths: TStrings; Captions: TStrings;
  Const Epoch: String; Cursor: Int64; Const Body: String; Complete: Boolean): String;
Begin
  Result := EncodeMonitorWith(mmkPlan, Id, PlanPayload(Path, Title, Running, Rows, Paths, Captions, Epoch, Cursor, Body,
    Complete));
End;

Function PackStatePlanFrames(Const Id, Path, Title: String; Running: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow; Paths, Captions: TStrings; Const Body: String; Complete: Boolean;
  Out Frames: TStringArray): Boolean;
Var
  Payload: TJSONObject;
  PayloadJson, Envelope: String;
Begin
  Result := False;
  SetLength(Frames, 0);
  Payload := PlanPayload(Path, Title, Running, Rows, Paths, Captions, '', 0, Body, Complete);
  Try
    PayloadJson := Payload.AsJSON;
    Envelope := EncodeMonitorEnvelope(mmkPlan, Id, Payload);
  Finally
    Payload.Free;
  End;
  If Envelope <> '' Then
    Begin
      SetLength(Frames, 1);
      Frames[0] := Envelope;
      Exit(True);
    End;
  { The plan lane replaces this set, so a later edit is not stuck behind the previous chunks. }
  Result := PackMonitorBulkItem(Id, 'plan', PayloadJson, Frames);
End;

Function DecodeStatePlan(Const PayloadJson: TMonitorPayload; Out Path, Title: String; Out Running: Boolean;
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
  Rows.PlanComplete := False;
  SetLength(Rows.PlanRows, 0);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadMonitorString(Obj, 'path', True, Path) And ReadMonitorString(Obj, 'title', True, Title) And
      ReadMonitorBool(Obj, 'running', True, Running)) Then
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
        If Not TryStatePlanRowFromJson(TJSONObject(Arr[I]), Rows.PlanRows[I]) Then
          Exit;
      End;
    Rows.PlanPath := Path;
    Rows.PlanTitle := Title;
    Rows.PlanRunning := Running;
    If Not ReadMonitorString(Obj, 'body', False, Rows.PlanBody) Then
      Exit;
    If Assigned(Obj.Find('complete')) And (Not ReadMonitorBool(Obj, 'complete', True, Rows.PlanComplete)) Then
      Exit;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function EncodeStateTasks(Const Id: String; Const Rows: Array Of TAssistantMonitorTaskRow): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('rows', StateTaskRowsToJson(Rows));
  Result := EncodeMonitorWith(mmkTasks, Id, Payload);
End;

Function StateApprovalToJson(Const Notice: TAssistantApprovalNotice): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('active', Notice.Active);
  Result.Add('tool_id', Notice.ToolId);
  Result.Add('tool_name', Notice.ToolName);
  Result.Add('summary', Notice.Summary);
  Result.Add('mode_caption', Notice.ModeCaption);
  Result.Add('decisions_accepted', Notice.DecisionsAccepted);
End;

Function TryStateApprovalFromJson(Obj: TJSONObject; Out Notice: TAssistantApprovalNotice): Boolean;
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
  Result := ReadMonitorBool(Obj, 'active', True, Notice.Active) And ReadMonitorString(Obj, 'tool_id', True, Notice.ToolId) And
    ReadMonitorString(Obj, 'tool_name', True, Notice.ToolName) And ReadMonitorString(Obj, 'summary', True, Notice.Summary) And
    ReadMonitorString(Obj, 'mode_caption', True, Notice.ModeCaption) And
    ReadMonitorBool(Obj, 'decisions_accepted', True, Notice.DecisionsAccepted);
End;

Function EncodeStateConversationClosed(Const Id, Epoch: String; Cursor: Int64;
  Const ConversationId, Title: String): String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('epoch', Epoch);
  Payload.Add('cursor', Cursor);
  Payload.Add('conversation_id', ConversationId);
  Payload.Add('title', Title);
  Result := EncodeMonitorWith(mmkConversationClosed, Id, Payload);
End;

Function DecodeStateConversationClosed(Const PayloadJson: TMonitorPayload; Out Closed: TMonitorConversationClosed): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Closed.Epoch := '';
  Closed.Cursor := 0;
  Closed.ConversationId := '';
  Closed.Title := '';
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := ReadMonitorString(Obj, 'epoch', True, Closed.Epoch) And ReadMonitorInt64(Obj, 'cursor', Closed.Cursor) And
      ReadMonitorString(Obj, 'conversation_id', True, Closed.ConversationId) And ReadMonitorString(Obj, 'title', True, Closed.Title);
  Finally
    Data.Free;
  End;
End;


End.
