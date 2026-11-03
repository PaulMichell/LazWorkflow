Unit AssistantMonitorContent;

{ Tested catalogue 2 content tables (c) 2026 Michell Computing.

  The live path does not send these frames. They remain because the codec and
  session tests still assert them. Deleting them would change those assertions.

  Size note: exceeds the 1000 line preference. What remains is the tested
  snapshot, transcript, patch, and catchup tables. Splitting them would be a
  second copy of the same catalogue, not a smaller idea.
  Reviewed 2026-11-03: no socket, form, or sync policy in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantMonitorCodec, AssistantSessionObserve;

Function MonitorToolBodyForWire(Const Body: String; Out Truncated: Boolean): String;
Function Utf8Boundary(Const Body: String; Index: Integer): Integer;
Function ImageToJson(Const Image: TAssistantMonitorImage): TJSONObject;
Function TryImageFromJson(Obj: TJSONObject; Out Image: TAssistantMonitorImage): Boolean;
Function ImagesToJson(Const Images: Array Of TAssistantMonitorImage): TJSONArray;
Function ContentBlockToJson(Const Block: TAssistantMonitorBlock; Part, PartCount, Revision: Integer): TJSONObject;
Function TryContentBlockFromJson(Obj: TJSONObject; Out Block: TAssistantMonitorBlock; Out Truncated: Boolean): Boolean;
Function ContentViewToJson(Const View: TAssistantMonitorView): TJSONObject;
Function TryContentViewFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Procedure ClearTurn(Out Turn: TAssistantMonitorTurn);
Function ContentTurnToJson(Const Turn: TAssistantMonitorTurn; IndexOnly: Boolean): TJSONObject;
Function TryReadImages(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Function TryReadBlocks(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Function TryContentTurnFromJson(Obj: TJSONObject; IndexOnly: Boolean; Out Turn: TAssistantMonitorTurn): Boolean;
Function DecodeContentTurnData(Const PayloadJson: String; Out Turn: TAssistantMonitorTurn): Boolean;
Function StoredTurnIsLive(Const Turn: TAssistantMonitorTurn): Boolean;
Function EncodeContentSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Function DecodeContentSnapshot(Const PayloadJson: String; Out Snapshot: TMonitorSnapshot): Boolean;
Function DecodeContentTranscript(Const PayloadJson: String; Out Transcript: TMonitorTranscript): Boolean;
Procedure ClearPatch(Out Patch: TMonitorPatch);
Function PatchPayload(Const Patch: TMonitorPatch): TJSONObject;
Function EncodeContentPatch(Const Id: String; Const Patch: TMonitorPatch): String;
Function DecodeContentPatch(Const PayloadJson: String; Out Patch: TMonitorPatch): Boolean;
Function SelectContentDirtyBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;
Function PackContentPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Function TryAssembleContentPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Function EncodeContentCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Function EncodeContentResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Function DecodeContentCatchup(Const PayloadJson: String; Out Catchup: TMonitorCatchup): Boolean;

Implementation

Uses
  AssistantMonitorState;

Function MonitorToolBodyForWire(Const Body: String; Out Truncated: Boolean): String;
Begin
  Truncated := Length(Body) > MonitorMaxToolBodyChars;
  If Truncated Then
    Result := Copy(Body, 1, MonitorMaxToolBodyChars)
  Else
    Result := Body;
End;

Function Utf8Boundary(Const Body: String; Index: Integer): Integer;
Begin
  Result := Index;
  While (Result > 1) And (Result <= Length(Body)) And ((Ord(Body[Result]) And $C0) = $80) Do
    Dec(Result);
  If Result < 1 Then
    Result := 1;
End;

Function ImageToJson(Const Image: TAssistantMonitorImage): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Image.Id);
  Result.Add('name', Image.Name);
  Result.Add('mime', Image.Mime);
  Result.Add('width', Image.Width);
  Result.Add('height', Image.Height);
  Result.Add('display_path', Image.DisplayPath);
  Result.Add('missing', Image.Missing);
End;

Function TryImageFromJson(Obj: TJSONObject; Out Image: TAssistantMonitorImage): Boolean;
Begin
  Result := False;
  Image.Id := '';
  Image.Name := '';
  Image.Mime := '';
  Image.Width := 0;
  Image.Height := 0;
  Image.DisplayPath := '';
  Image.Missing := False;
  If Not Assigned(Obj) Then
    Exit;
  Result := ReadMonitorString(Obj, 'id', True, Image.Id) And ReadMonitorString(Obj, 'name', True, Image.Name) And
    ReadMonitorString(Obj, 'mime', True, Image.Mime) And ReadMonitorInt(Obj, 'width', True, Image.Width) And
    ReadMonitorInt(Obj, 'height', True, Image.Height) And ReadMonitorString(Obj, 'display_path', True, Image.DisplayPath) And
    ReadMonitorBool(Obj, 'missing', True, Image.Missing);
End;

Function ImagesToJson(Const Images: Array Of TAssistantMonitorImage): TJSONArray;
Var
  I: Integer;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Images) Do
    Result.Add(ImageToJson(Images[I]));
End;

Function ContentBlockToJson(Const Block: TAssistantMonitorBlock; Part, PartCount, Revision: Integer): TJSONObject;
Var
  Truncated: Boolean;
  Body: String;
Begin
  Result := TJSONObject.Create;
  Result.Add('kind', Block.Kind);
  Result.Add('block_id', Block.BlockId);
  Result.Add('title', Block.Title);
  Result.Add('tool_name', Block.ToolName);
  Result.Add('tool_id', Block.ToolId);
  If Block.Kind = 'tool' Then
    Begin
      Body := MonitorToolBodyForWire(Block.Body, Truncated);
      Result.Add('body', Body);
      If Truncated Then
        Result.Add('truncated', True);
    End
  Else
    Result.Add('body', Block.Body);
  Result.Add('running', Block.Running);
  Result.Add('ok', Block.Ok);
  Result.Add('duration_ms', Block.DurationMs);
  Result.Add('images', ImagesToJson(Block.Images));
  If PartCount > 1 Then
    Begin
      Result.Add('part', Part);
      Result.Add('part_count', PartCount);
      Result.Add('revision', Revision);
    End;
End;

Function TryContentBlockFromJson(Obj: TJSONObject; Out Block: TAssistantMonitorBlock; Out Truncated: Boolean): Boolean;
Var
  Node: TJSONData;
  Images: TJSONArray;
  I: Integer;
  Image: TAssistantMonitorImage;
Begin
  Result := False;
  Truncated := False;
  Block.Kind := '';
  Block.BlockId := '';
  Block.Title := '';
  Block.ToolName := '';
  Block.ToolId := '';
  Block.Body := '';
  Block.Running := False;
  Block.Ok := False;
  Block.DurationMs := 0;
  SetLength(Block.Images, 0);
  If Not Assigned(Obj) Then
    Exit;
  If Not (ReadMonitorString(Obj, 'kind', True, Block.Kind) And ReadMonitorString(Obj, 'block_id', True, Block.BlockId) And
    ReadMonitorString(Obj, 'title', True, Block.Title) And ReadMonitorString(Obj, 'tool_name', True, Block.ToolName) And
    ReadMonitorString(Obj, 'tool_id', True, Block.ToolId) And ReadMonitorString(Obj, 'body', True, Block.Body) And
    ReadMonitorBool(Obj, 'running', True, Block.Running) And ReadMonitorBool(Obj, 'ok', True, Block.Ok) And
    ReadMonitorInt(Obj, 'duration_ms', True, Block.DurationMs)) Then
    Exit;
  If Block.Kind = 'tool' Then
    Begin
      If Not ReadMonitorBool(Obj, 'truncated', False, Truncated) Then
        Exit;
      If Length(Block.Body) > MonitorMaxToolBodyChars Then
        Exit;
    End;
  Node := Obj.Find('images');
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Images := TJSONArray(Node);
  SetLength(Block.Images, Images.Count);
  For I := 0 To Images.Count - 1 Do
    Begin
      If Not (Images[I] Is TJSONObject) Then
        Exit;
      If Not TryImageFromJson(TJSONObject(Images[I]), Image) Then
        Exit;
      Block.Images[I] := Image;
    End;
  Result := True;
End;

Function ContentViewToJson(Const View: TAssistantMonitorView): TJSONObject;
Begin
  Result := StateStatusToJson(View);
  Result.Add('mode', View.Mode);
  Result.Add('target_kind', View.TargetKind);
  Result.Add('target_display', View.TargetDisplay);
  Result.Add('target_root', View.TargetRoot);
  Result.Add('plan_path', View.PlanPath);
  Result.Add('plan_title', View.PlanTitle);
End;

Function TryContentViewFromJson(Obj: TJSONObject; Out View: TAssistantMonitorView): Boolean;
Begin
  Result := False;
  StateClearView(View);
  If Not Assigned(Obj) Then
    Exit;
  Result := StateReadStatusFields(Obj, View) And ReadMonitorString(Obj, 'mode', True, View.Mode) And
    ReadMonitorString(Obj, 'target_kind', True, View.TargetKind) And ReadMonitorString(Obj, 'target_display', True, View.TargetDisplay) And
    ReadMonitorString(Obj, 'target_root', True, View.TargetRoot) And ReadMonitorString(Obj, 'plan_path', True, View.PlanPath) And
    ReadMonitorString(Obj, 'plan_title', True, View.PlanTitle);
End;

Procedure ClearTurn(Out Turn: TAssistantMonitorTurn);
Begin
  Turn.TurnIndex := 0;
  Turn.Id := '';
  Turn.Mode := '';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.ErrorText := '';
  Turn.CreatedAt := '';
  Turn.DurationMs := 0;
  Turn.PromptPreview := '';
  Turn.Live := False;
  SetLength(Turn.Blocks, 0);
  SetLength(Turn.Images, 0);
End;

Function ContentTurnToJson(Const Turn: TAssistantMonitorTurn; IndexOnly: Boolean): TJSONObject;
Var
  I: Integer;
  Blocks, Images: TJSONArray;
Begin
  Result := TJSONObject.Create;
  Result.Add('turn_index', Turn.TurnIndex);
  Result.Add('id', Turn.Id);
  Result.Add('mode', Turn.Mode);
  Result.Add('created_at', Turn.CreatedAt);
  Result.Add('prompt_preview', Turn.PromptPreview);
  Result.Add('error_text', Turn.ErrorText);
  If IndexOnly Then
    Exit;
  Result.Add('prompt', Turn.Prompt);
  Result.Add('thinking', Turn.Thinking);
  Result.Add('response', Turn.Response);
  Result.Add('duration_ms', Turn.DurationMs);
  Result.Add('live', Turn.Live);
  Blocks := TJSONArray.Create;
  For I := 0 To High(Turn.Blocks) Do
    Blocks.Add(ContentBlockToJson(Turn.Blocks[I], 1, 1, 0));
  Result.Add('blocks', Blocks);
  Images := ImagesToJson(Turn.Images);
  Result.Add('images', Images);
End;

Function TryReadImages(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Var
  Images: TJSONArray;
  I: Integer;
  Image: TAssistantMonitorImage;
Begin
  Result := False;
  SetLength(Turn.Images, 0);
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Images := TJSONArray(Node);
  SetLength(Turn.Images, Images.Count);
  For I := 0 To Images.Count - 1 Do
    Begin
      If Not (Images[I] Is TJSONObject) Then
        Exit;
      If Not TryImageFromJson(TJSONObject(Images[I]), Image) Then
        Exit;
      Turn.Images[I] := Image;
    End;
  Result := True;
End;

Function TryReadBlocks(Node: TJSONData; Var Turn: TAssistantMonitorTurn): Boolean;
Var
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  SetLength(Turn.Blocks, 0);
  If Not Assigned(Node) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not (Node Is TJSONArray) Then
    Exit;
  Blocks := TJSONArray(Node);
  SetLength(Turn.Blocks, Blocks.Count);
  For I := 0 To Blocks.Count - 1 Do
    Begin
      If Not (Blocks[I] Is TJSONObject) Then
        Exit;
      If Not TryContentBlockFromJson(TJSONObject(Blocks[I]), Turn.Blocks[I], Truncated) Then
        Exit;
    End;
  Result := True;
End;

Function TryContentTurnFromJson(Obj: TJSONObject; IndexOnly: Boolean; Out Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := False;
  ClearTurn(Turn);
  If Not Assigned(Obj) Then
    Exit;
  If Not (ReadMonitorInt(Obj, 'turn_index', True, Turn.TurnIndex) And ReadMonitorString(Obj, 'id', True, Turn.Id) And
    ReadMonitorString(Obj, 'mode', True, Turn.Mode) And ReadMonitorString(Obj, 'created_at', True, Turn.CreatedAt) And
    ReadMonitorString(Obj, 'prompt_preview', True, Turn.PromptPreview) And ReadMonitorString(Obj, 'error_text', True, Turn.ErrorText)) Then
    Exit;
  If IndexOnly Then
    Begin
      Result := True;
      Exit;
    End;
  Result := ReadMonitorString(Obj, 'prompt', True, Turn.Prompt) And ReadMonitorString(Obj, 'thinking', True, Turn.Thinking) And
    ReadMonitorString(Obj, 'response', True, Turn.Response) And ReadMonitorInt(Obj, 'duration_ms', True, Turn.DurationMs) And
    ReadMonitorBool(Obj, 'live', True, Turn.Live) And TryReadBlocks(Obj.Find('blocks'), Turn) And TryReadImages(Obj.Find('images'), Turn);
End;

Function DecodeContentTurnData(Const PayloadJson: String; Out Turn: TAssistantMonitorTurn): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  ClearTurn(Turn);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    Result := TryContentTurnFromJson(Obj, False, Turn);
  Finally
    Data.Free;
  End;
End;

Function StoredTurnIsLive(Const Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := Turn.Live;
End;

Function EncodeContentSnapshot(Const Id: String; Const Snapshot: TMonitorSnapshot): String;
Var
  Payload, PlanObj, Tasks: TJSONObject;
  TurnRows: TJSONArray;
  Kept: Array Of TAssistantMonitorTurn;
  I, Count, StartAt: Integer;
Begin
  Result := '';
  Kept := Nil;
  TurnRows := Nil;
  Count := 0;
  For I := 0 To High(Snapshot.StoredTurns) Do
    If Not StoredTurnIsLive(Snapshot.StoredTurns[I]) Then
      Inc(Count);
  SetLength(Kept, Count);
  Count := 0;
  For I := 0 To High(Snapshot.StoredTurns) Do
    If Not StoredTurnIsLive(Snapshot.StoredTurns[I]) Then
      Begin
        Kept[Count] := Snapshot.StoredTurns[I];
        Inc(Count);
      End;
  StartAt := 0;
  If Count > MonitorSnapshotStoredTurns Then
    StartAt := Count - MonitorSnapshotStoredTurns;
  TurnRows := TJSONArray.Create;
  For I := StartAt To Count - 1 Do
    TurnRows.Add(ContentTurnToJson(Kept[I], True));
  Payload := TJSONObject.Create;
  Try
    Payload.Add('view', ContentViewToJson(Snapshot.View));
    Payload.Add('turns', TurnRows);
    TurnRows := Nil;
    If Snapshot.HasLive Then
      Payload.Add('live', ContentTurnToJson(Snapshot.Live, False))
    Else
      Payload.Add('live', TJSONNull.Create);
    PlanObj := TJSONObject.Create;
    PlanObj.Add('path', Snapshot.PlanPath);
    PlanObj.Add('title', Snapshot.PlanTitle);
    PlanObj.Add('running', Snapshot.PlanRunning);
    PlanObj.Add('rows', StatePlanRowsToJson(Snapshot.PlanRows));
    Payload.Add('plan', PlanObj);
    Tasks := TJSONObject.Create;
    Tasks.Add('rows', StateTaskRowsToJson(Snapshot.TaskRows));
    Payload.Add('tasks', Tasks);
    Payload.Add('approval', StateApprovalToJson(Snapshot.Approval));
    Result := EncodeMonitorEnvelope(mmkSnapshot, Id, Payload);
  Finally
    TurnRows.Free;
    Payload.Free;
  End;
End;

Function DecodeContentSnapshot(Const PayloadJson: String; Out Snapshot: TMonitorSnapshot): Boolean;
Var
  Data: TJSONData;
  Obj, Child: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := False;
  StateClearView(Snapshot.View);
  SetLength(Snapshot.StoredTurns, 0);
  ClearTurn(Snapshot.Live);
  Snapshot.HasLive := False;
  Snapshot.PlanPath := '';
  Snapshot.PlanTitle := '';
  Snapshot.PlanRunning := False;
  Snapshot.PlanBody := '';
  Snapshot.PlanComplete := False;
  SetLength(Snapshot.PlanRows, 0);
  SetLength(Snapshot.TaskRows, 0);
  Snapshot.Approval.Active := False;
  Snapshot.Approval.ToolId := '';
  Snapshot.Approval.ToolName := '';
  Snapshot.Approval.Summary := '';
  Snapshot.Approval.ModeCaption := '';
  Snapshot.Approval.DecisionsAccepted := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (Obj.Find('view') Is TJSONObject) Then
      Exit;
    If Not TryContentViewFromJson(TJSONObject(Obj.Find('view')), Snapshot.View) Then
      Exit;
    Node := Obj.Find('turns');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    If Arr.Count > MonitorSnapshotStoredTurns Then
      Exit;
    SetLength(Snapshot.StoredTurns, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryContentTurnFromJson(TJSONObject(Arr[I]), True, Snapshot.StoredTurns[I]) Then
          Exit;
      End;
    Node := Obj.Find('live');
    If Not Assigned(Node) Or (Node Is TJSONNull) Then
      Snapshot.HasLive := False
    Else If Node Is TJSONObject Then
      Begin
        If Not TryContentTurnFromJson(TJSONObject(Node), False, Snapshot.Live) Then
          Exit;
        Snapshot.HasLive := True;
      End
    Else
      Exit;
    If Not (Obj.Find('plan') Is TJSONObject) Then
      Exit;
    Child := TJSONObject(Obj.Find('plan'));
    If Not (ReadMonitorString(Child, 'path', True, Snapshot.PlanPath) And ReadMonitorString(Child, 'title', True, Snapshot.PlanTitle) And
      ReadMonitorBool(Child, 'running', True, Snapshot.PlanRunning)) Then
      Exit;
    Node := Child.Find('rows');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Snapshot.PlanRows, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryStatePlanRowFromJson(TJSONObject(Arr[I]), Snapshot.PlanRows[I]) Then
          Exit;
      End;
    If Not (Obj.Find('tasks') Is TJSONObject) Then
      Exit;
    Child := TJSONObject(Obj.Find('tasks'));
    Node := Child.Find('rows');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    SetLength(Snapshot.TaskRows, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr[I] Is TJSONObject) Then
          Exit;
        If Not TryStateTaskRowFromJson(TJSONObject(Arr[I]), Snapshot.TaskRows[I]) Then
          Exit;
      End;
    If Not (Obj.Find('approval') Is TJSONObject) Then
      Exit;
    Result := TryStateApprovalFromJson(TJSONObject(Obj.Find('approval')), Snapshot.Approval);
  Finally
    Data.Free;
  End;
End;

Function DecodeContentTranscript(Const PayloadJson: String; Out Transcript: TMonitorTranscript): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  Transcript.TurnIndex := 0;
  Transcript.Revision := 0;
  Transcript.Phase := '';
  Transcript.StatusText := '';
  Transcript.DurationMs := 0;
  Transcript.Part := 1;
  Transcript.PartCount := 1;
  SetLength(Transcript.Blocks, 0);
  SetLength(Transcript.BlockPart, 0);
  SetLength(Transcript.BlockPartCount, 0);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadMonitorInt(Obj, 'turn_index', True, Transcript.TurnIndex) And ReadMonitorInt(Obj, 'revision', True, Transcript.Revision) And
      ReadMonitorString(Obj, 'phase', True, Transcript.Phase) And ReadMonitorString(Obj, 'status_text', True, Transcript.StatusText)) Then
      Exit;
    If Not ReadMonitorInt(Obj, 'part', False, Transcript.Part) Then
      Exit;
    If Transcript.Part < 1 Then
      Transcript.Part := 1;
    If Not ReadMonitorInt(Obj, 'part_count', False, Transcript.PartCount) Then
      Exit;
    If Transcript.PartCount < 1 Then
      Transcript.PartCount := 1;
    If Not ReadMonitorInt(Obj, 'duration_ms', False, Transcript.DurationMs) Then
      Exit;
    If Transcript.DurationMs < 0 Then
      Transcript.DurationMs := 0;
    Node := Obj.Find('blocks');
    If Not (Node Is TJSONArray) Then
      Exit;
    Blocks := TJSONArray(Node);
    SetLength(Transcript.Blocks, Blocks.Count);
    SetLength(Transcript.BlockPart, Blocks.Count);
    SetLength(Transcript.BlockPartCount, Blocks.Count);
    For I := 0 To Blocks.Count - 1 Do
      Begin
        If Not (Blocks[I] Is TJSONObject) Then
          Exit;
        If Not TryContentBlockFromJson(TJSONObject(Blocks[I]), Transcript.Blocks[I], Truncated) Then
          Exit;
        Transcript.BlockPart[I] := 1;
        Transcript.BlockPartCount[I] := 1;
        If Not ReadMonitorInt(TJSONObject(Blocks[I]), 'part', False, Transcript.BlockPart[I]) Then
          Exit;
        If Not ReadMonitorInt(TJSONObject(Blocks[I]), 'part_count', False, Transcript.BlockPartCount[I]) Then
          Exit;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Procedure ClearPatch(Out Patch: TMonitorPatch);
Begin
  Patch.Epoch := '';
  Patch.Cursor := 0;
  Patch.TurnIndex := 0;
  Patch.TurnId := '';
  SetLength(Patch.Blocks, 0);
  SetLength(Patch.AppendOffsets, 0);
  Patch.Busy := False;
  Patch.Sending := False;
  Patch.PlanRunning := False;
  Patch.Phase := '';
  Patch.CanSend := False;
  Patch.CanSteer := False;
  Patch.CanStop := False;
  Patch.ElapsedMs := 0;
  Patch.Part := 0;
  Patch.PartCount := 0;
  Patch.HasView := False;
  Patch.Model := '';
  Patch.SignedIn := False;
  Patch.StatusText := '';
End;

Function PatchPayload(Const Patch: TMonitorPatch): TJSONObject;
Var
  Blocks: TJSONArray;
  Node: TJSONObject;
  I: Integer;
Begin
  Result := TJSONObject.Create;
  Result.Add('epoch', Patch.Epoch);
  Result.Add('cursor', Patch.Cursor);
  Result.Add('turn_index', Patch.TurnIndex);
  Result.Add('turn_id', Patch.TurnId);
  Result.Add('part', Patch.Part);
  Result.Add('part_count', Patch.PartCount);
  Result.Add('busy', Patch.Busy);
  Result.Add('sending', Patch.Sending);
  Result.Add('plan_running', Patch.PlanRunning);
  Result.Add('phase', Patch.Phase);
  Result.Add('can_send', Patch.CanSend);
  Result.Add('can_steer', Patch.CanSteer);
  Result.Add('can_stop', Patch.CanStop);
  Result.Add('elapsed_ms', Patch.ElapsedMs);
  Result.Add('model', Patch.Model);
  Result.Add('signed_in', Patch.SignedIn);
  Result.Add('status_text', Patch.StatusText);
  Blocks := TJSONArray.Create;
  For I := 0 To High(Patch.Blocks) Do
    Begin
      Node := ContentBlockToJson(Patch.Blocks[I], 1, 1, 0);
      If (I <= High(Patch.AppendOffsets)) And (Patch.AppendOffsets[I] >= 0) Then
        Node.Add('offset', Patch.AppendOffsets[I]);
      Blocks.Add(Node);
    End;
  Result.Add('blocks', Blocks);
End;

Function EncodeContentPatch(Const Id: String; Const Patch: TMonitorPatch): String;
Begin
  Result := EncodeMonitorWith(mmkPatch, Id, PatchPayload(Patch));
End;

Function DecodeContentPatch(Const PayloadJson: String; Out Patch: TMonitorPatch): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
  Blocks: TJSONArray;
  I: Integer;
  Truncated: Boolean;
Begin
  Result := False;
  ClearPatch(Patch);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  Try
    If Not (ReadMonitorString(Obj, 'epoch', True, Patch.Epoch) And ReadMonitorInt64(Obj, 'cursor', Patch.Cursor) And
      ReadMonitorInt(Obj, 'turn_index', True, Patch.TurnIndex) And ReadMonitorString(Obj, 'turn_id', True, Patch.TurnId) And
      ReadMonitorInt(Obj, 'part', True, Patch.Part) And ReadMonitorInt(Obj, 'part_count', True, Patch.PartCount) And
      ReadMonitorBool(Obj, 'busy', True, Patch.Busy) And ReadMonitorBool(Obj, 'sending', True, Patch.Sending) And
      ReadMonitorBool(Obj, 'plan_running', True, Patch.PlanRunning) And ReadMonitorString(Obj, 'phase', True, Patch.Phase) And
      ReadMonitorBool(Obj, 'can_send', True, Patch.CanSend) And ReadMonitorBool(Obj, 'can_steer', True, Patch.CanSteer) And
      ReadMonitorBool(Obj, 'can_stop', True, Patch.CanStop) And ReadMonitorInt(Obj, 'elapsed_ms', True, Patch.ElapsedMs)) Then
      Exit;
    { Older ring records omit the status bar. A missing field must not wipe a model the phone already has. }
    Patch.HasView := Assigned(Obj.Find('model')) Or Assigned(Obj.Find('signed_in'));
    If Patch.HasView And (Not (ReadMonitorString(Obj, 'model', True, Patch.Model) And
      ReadMonitorBool(Obj, 'signed_in', True, Patch.SignedIn) And ReadMonitorString(Obj, 'status_text', True, Patch.StatusText))) Then
      Exit;
    { A v1 transcript has revision and status_text, not epoch. Missing epoch already failed above. }
    If (Patch.Part < 1) Or (Patch.PartCount < 1) Or (Patch.Part > Patch.PartCount) Then
      Exit;
    Node := Obj.Find('blocks');
    If Not (Node Is TJSONArray) Then
      Exit;
    Blocks := TJSONArray(Node);
    SetLength(Patch.Blocks, Blocks.Count);
    For I := 0 To Blocks.Count - 1 Do
      Begin
        If Not (Blocks[I] Is TJSONObject) Then
          Exit;
        If Not TryContentBlockFromJson(TJSONObject(Blocks[I]), Patch.Blocks[I], Truncated) Then
          Exit;
        SetLength(Patch.AppendOffsets, I + 1);
        If Assigned(TJSONObject(Blocks[I]).Find('offset')) And (TJSONObject(Blocks[I]).Find('offset').JSONType = jtNumber) Then
          Patch.AppendOffsets[I] := TJSONObject(Blocks[I]).Find('offset').AsInteger
        Else
          Patch.AppendOffsets[I] := -1;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function SelectContentDirtyBlocks(Const Previous, Current: Array Of TAssistantMonitorBlock;
  FirstPatch: Boolean): TAssistantMonitorBlockArray;

  Function FaceSame(Const Left, Right: TAssistantMonitorBlock): Boolean;
  Begin
    Result := (Left.Title = Right.Title) And (Left.Body = Right.Body) And (Left.Running = Right.Running) And
      (Left.Ok = Right.Ok);
  End;

Var
  I, J, N: Integer;
  Seen: Boolean;
Begin
  SetLength(Result, 0);
  If FirstPatch Then
    Begin
      SetLength(Result, Length(Current));
      For I := 0 To High(Current) Do
        Result[I] := Current[I];
      Exit;
    End;
  N := 0;
  For I := 0 To High(Current) Do
    Begin
      Seen := False;
      For J := 0 To High(Previous) Do
        If Previous[J].BlockId = Current[I].BlockId Then
          Begin
            Seen := True;
            If Not FaceSame(Previous[J], Current[I]) Then
              Begin
                SetLength(Result, N + 1);
                Result[N] := Current[I];
                Inc(N);
              End;
            Break;
          End;
      If Not Seen Then
        Begin
          SetLength(Result, N + 1);
          Result[N] := Current[I];
          Inc(N);
        End;
    End;
End;

Function PackContentPatch(Const Id: String; Const Patch: TMonitorPatch): TStringArray;
Type
  TPatchBlockArray = Array Of TAssistantMonitorBlock;

  Function Utf8Prefix(Const Text: String; MaxBytes: Integer): String;
  Var
    Count: Integer;
  Begin
    If (MaxBytes < 1) Or (Text = '') Then
      Exit('');
    If Length(Text) <= MaxBytes Then
      Exit(Text);
    Count := MaxBytes;
    While (Count > 0) And ((Ord(Text[Count]) And $C0) = $80) Do
      Dec(Count);
    If Count < 1 Then
      Count := 1;
    Result := Copy(Text, 1, Count);
  End;

  Function EncodeBlocks(Const Blocks: Array Of TAssistantMonitorBlock; Part, PartCount: Integer): String;
  Var
    Trial: TMonitorPatch;
    I: Integer;
  Begin
    Trial := Patch;
    Trial.Part := Part;
    Trial.PartCount := PartCount;
    { A split piece is a body fragment, not an append suffix. }
    SetLength(Trial.AppendOffsets, 0);
    SetLength(Trial.Blocks, Length(Blocks));
    For I := 0 To High(Blocks) Do
      Trial.Blocks[I] := Blocks[I];
    Result := EncodeContentPatch(Id, Trial);
  End;

  Function PieceFits(Const Block: TAssistantMonitorBlock): Boolean;
  Begin
    Result := EncodeBlocks([Block], 1, 1) <> '';
  End;

  Procedure AddPiece(Var Pieces: TPatchBlockArray; Const Block: TAssistantMonitorBlock);
  Begin
    SetLength(Pieces, Length(Pieces) + 1);
    Pieces[High(Pieces)] := Block;
  End;

  Function SplitBlock(Const Block: TAssistantMonitorBlock; Var Pieces: TPatchBlockArray): Boolean;
  Var
    Rest, Prefix: String;
    Trial: TAssistantMonitorBlock;
    LowN, HighN, Mid, Best: Integer;
  Begin
    Result := False;
    Rest := Block.Body;
    Repeat
      Trial := Block;
      Trial.Body := Rest;
      If PieceFits(Trial) Then
        Begin
          AddPiece(Pieces, Trial);
          Exit(True);
        End;
      If Rest = '' Then
        Exit;
      LowN := 1;
      HighN := Length(Rest) - 1;
      Best := 0;
      While LowN <= HighN Do
        Begin
          Mid := (LowN + HighN) Div 2;
          Prefix := Utf8Prefix(Rest, Mid);
          Trial.Body := Prefix;
          If PieceFits(Trial) Then
            Begin
              Best := Length(Prefix);
              LowN := Best + 1;
            End
          Else
            HighN := Mid - 1;
        End;
      If Best < 1 Then
        Exit;
      Trial.Body := Copy(Rest, 1, Best);
      AddPiece(Pieces, Trial);
      Delete(Rest, 1, Best);
    Until Rest = '';
    Result := True;
  End;

Var
  Whole: TMonitorPatch;
  Pieces, Group: TPatchBlockArray;
  Starts, Ends: Array Of Integer;
  I, StartAt, LastFit, PartNo, PartCount: Integer;
  Json: String;
Begin
  Result := Nil;
  SetLength(Result, 0);
  Pieces := Nil;
  Group := Nil;
  Whole := Patch;
  If Whole.Part < 1 Then
    Whole.Part := 1;
  If Whole.PartCount < 1 Then
    Whole.PartCount := 1;
  Json := EncodeContentPatch(Id, Whole);
  If Json <> '' Then
    Begin
      SetLength(Result, 1);
      Result[0] := Json;
      Exit;
    End;
  SetLength(Pieces, 0);
  For I := 0 To High(Patch.Blocks) Do
    If Not SplitBlock(Patch.Blocks[I], Pieces) Then
      Exit;
  If Length(Pieces) = 0 Then
    Exit;
  SetLength(Starts, 0);
  SetLength(Ends, 0);
  StartAt := 0;
  While StartAt <= High(Pieces) Do
    Begin
      LastFit := StartAt - 1;
      For I := StartAt To High(Pieces) Do
        Begin
          SetLength(Group, I - StartAt + 1);
          Group[I - StartAt] := Pieces[I];
          If EncodeBlocks(Group, 1, 1) = '' Then
            Break;
          LastFit := I;
        End;
      If LastFit < StartAt Then
        Exit;
      SetLength(Starts, Length(Starts) + 1);
      SetLength(Ends, Length(Starts));
      Starts[High(Starts)] := StartAt;
      Ends[High(Ends)] := LastFit;
      StartAt := LastFit + 1;
    End;
  PartCount := Length(Starts);
  SetLength(Result, PartCount);
  For PartNo := 0 To PartCount - 1 Do
    Begin
      SetLength(Group, Ends[PartNo] - Starts[PartNo] + 1);
      For I := Starts[PartNo] To Ends[PartNo] Do
        Group[I - Starts[PartNo]] := Pieces[I];
      Json := EncodeBlocks(Group, PartNo + 1, PartCount);
      If Json = '' Then
        Begin
          SetLength(Result, 0);
          Exit;
        End;
      Result[PartNo] := Json;
    End;
End;

Function TryAssembleContentPatch(Const Messages: TStringArray; Out Patch: TMonitorPatch): Boolean;
Var
  I, PartCount, Index: Integer;
  Message: TMonitorMessage;
  ErrorText: String;
  Decoded: TMonitorPatch;
  Slots: TMonitorPatchArray;
  Have: Array Of Boolean;
  Epoch: String;
  Cursor: Int64;

  Procedure AppendBlock(Const Block: TAssistantMonitorBlock);
  Begin
    If (Length(Patch.Blocks) > 0) And (Patch.Blocks[High(Patch.Blocks)].BlockId = Block.BlockId) And
      (Patch.Blocks[High(Patch.Blocks)].Kind = Block.Kind) Then
      Patch.Blocks[High(Patch.Blocks)].Body := Patch.Blocks[High(Patch.Blocks)].Body + Block.Body
    Else
      Begin
        SetLength(Patch.Blocks, Length(Patch.Blocks) + 1);
        Patch.Blocks[High(Patch.Blocks)] := Block;
      End;
  End;

Begin
  Result := False;
  ClearPatch(Patch);
  If Length(Messages) = 0 Then
    Exit;
  If Not TryDecodeMonitorEnvelope(Messages[0], Message, ErrorText) Or (Message.Kind <> mmkPatch) Then
    Exit;
  If Not DecodeContentPatch(Message.PayloadJson, Decoded) Then
    Exit;
  PartCount := Decoded.PartCount;
  Epoch := Decoded.Epoch;
  Cursor := Decoded.Cursor;
  If (PartCount < 1) Or (Length(Messages) <> PartCount) Then
    Exit;
  SetLength(Slots, PartCount);
  SetLength(Have, PartCount);
  For I := 0 To High(Messages) Do
    Begin
      If Not TryDecodeMonitorEnvelope(Messages[I], Message, ErrorText) Or (Message.Kind <> mmkPatch) Then
        Exit;
      If Not DecodeContentPatch(Message.PayloadJson, Decoded) Then
        Exit;
      If (Decoded.PartCount <> PartCount) Or (Decoded.Epoch <> Epoch) Or (Decoded.Cursor <> Cursor) Then
        Exit;
      If (Decoded.Part < 1) Or (Decoded.Part > PartCount) Or Have[Decoded.Part - 1] Then
        Exit;
      Slots[Decoded.Part - 1] := Decoded;
      Have[Decoded.Part - 1] := True;
    End;
  For I := 0 To PartCount - 1 Do
    If Not Have[I] Then
      Exit;
  Patch := Slots[0];
  SetLength(Patch.Blocks, 0);
  For I := 0 To PartCount - 1 Do
    For Index := 0 To High(Slots[I].Blocks) Do
      AppendBlock(Slots[I].Blocks[Index]);
  Patch.Part := 1;
  Patch.PartCount := 1;
  Result := True;
End;

Function EncodeContentCatchup(Const Id: String; Const Catchup: TMonitorCatchup): String;
Var
  Payload: TJSONObject;
  Patches: TJSONArray;
  SnapJson, ErrorText: String;
  Message: TMonitorMessage;
  Data: TJSONData;
  SnapObj: TJSONObject;
  I: Integer;
  ModeText: String;
Begin
  Result := '';
  If Catchup.Mode = mcmSnapshot Then
    ModeText := 'snapshot'
  Else If Catchup.Mode = mcmEvents Then
    ModeText := 'events'
  Else
    Exit;
  Payload := TJSONObject.Create;
  Data := Nil;
  Try
    Payload.Add('mode', ModeText);
    Payload.Add('epoch', Catchup.Epoch);
    Payload.Add('cursor', Catchup.Cursor);
    Payload.Add('conversation_id', Catchup.ConversationId);
    Payload.Add('project_root', Catchup.ProjectRoot);
    Payload.Add('title', Catchup.Title);
    If Catchup.Mode = mcmSnapshot Then
      Begin
        If Not Catchup.HasSnapshot Then
          Exit;
        SnapJson := EncodeContentSnapshot('catchup-snap', Catchup.Snapshot);
        If Not TryDecodeMonitorEnvelope(SnapJson, Message, ErrorText) Then
          Exit;
        If Not ParseMonitorObject(Message.PayloadJson, Data, SnapObj) Then
          Exit;
        Payload.Add('snapshot', SnapObj);
        Data := Nil;
      End
    Else
      Begin
        Patches := TJSONArray.Create;
        For I := 0 To High(Catchup.Patches) Do
          Patches.Add(PatchPayload(Catchup.Patches[I]));
        Payload.Add('patches', Patches);
      End;
    Result := EncodeMonitorEnvelope(mmkCatchup, Id, Payload);
  Finally
    Data.Free;
    Payload.Free;
  End;
End;

Function EncodeContentResumeSnapshot(Const RefId: String; Cursor: Int64; Const Epoch, ConversationId, ProjectRoot, Title: String;
  Const Snapshot: TMonitorSnapshot): String;
Var
  Catchup: TMonitorCatchup;
Begin
  Catchup := Default(TMonitorCatchup);
  Catchup.Mode := mcmSnapshot;
  Catchup.Epoch := Epoch;
  Catchup.Cursor := Cursor;
  Catchup.ConversationId := ConversationId;
  Catchup.ProjectRoot := ProjectRoot;
  Catchup.Title := Title;
  Catchup.Snapshot := Snapshot;
  Catchup.HasSnapshot := True;
  SetLength(Catchup.Patches, 0);
  Result := EncodeContentCatchup(RefId, Catchup);
End;

Function DecodeContentCatchup(Const PayloadJson: String; Out Catchup: TMonitorCatchup): Boolean;
Var
  Data, SnapData: TJSONData;
  Obj, SnapObj: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  ModeText: String;
  I: Integer;
Begin
  Result := False;
  Catchup.Mode := mcmUnknown;
  Catchup.Epoch := '';
  Catchup.Cursor := 0;
  Catchup.ConversationId := '';
  Catchup.ProjectRoot := '';
  Catchup.Title := '';
  Catchup.HasSnapshot := False;
  SetLength(Catchup.Patches, 0);
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Exit;
  SnapData := Nil;
  Try
    If Not (ReadMonitorString(Obj, 'mode', True, ModeText) And ReadMonitorString(Obj, 'epoch', True, Catchup.Epoch) And
      ReadMonitorInt64(Obj, 'cursor', Catchup.Cursor) And ReadMonitorString(Obj, 'conversation_id', True, Catchup.ConversationId) And
      ReadMonitorString(Obj, 'project_root', True, Catchup.ProjectRoot) And ReadMonitorString(Obj, 'title', True, Catchup.Title)) Then
      Exit;
    If ModeText = 'snapshot' Then
      Catchup.Mode := mcmSnapshot
    Else If ModeText = 'events' Then
      Catchup.Mode := mcmEvents
    Else
      Exit;
    If Catchup.Mode = mcmSnapshot Then
      Begin
        Node := Obj.Find('snapshot');
        If Not (Node Is TJSONObject) Then
          Exit;
        If Not DecodeContentSnapshot(TJSONObject(Node).AsJSON, Catchup.Snapshot) Then
          Exit;
        Catchup.HasSnapshot := True;
        Result := True;
      End
    Else
      Begin
        Node := Obj.Find('patches');
        If Not (Node Is TJSONArray) Then
          Exit;
        Arr := TJSONArray(Node);
        SetLength(Catchup.Patches, Arr.Count);
        For I := 0 To Arr.Count - 1 Do
          Begin
            If Not (Arr[I] Is TJSONObject) Then
              Exit;
            If Not DecodeContentPatch(TJSONObject(Arr[I]).AsJSON, Catchup.Patches[I]) Then
              Exit;
          End;
        Result := True;
      End;
  Finally
    SnapData.Free;
    Data.Free;
  End;
End;


End.
