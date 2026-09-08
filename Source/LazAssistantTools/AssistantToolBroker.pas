Unit AssistantToolBroker;

{ Backend-neutral, IDE-thread tool broker. Owns run identity and model-visible
  revisions. The adapter resolves project paths and uses the actual IDE buffers.
  This initial registry exposes bounded buffer operations; execution and build
  operations must not be smuggled through a generic unvalidated tool fallback. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Type
  TAssistantWorkspaceAdapter = Class
  Public
    Function Identity: String; Virtual; Abstract;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Virtual; Abstract;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Virtual; Abstract;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Virtual; Abstract;
    Function Describe: String; Virtual; Abstract;
    Function CanBuild: Boolean; Virtual;
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Virtual;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Virtual;
    Procedure CancelBuild; Virtual;
  End;
  TBrokerSnapshot = Record
    Path, Text, Revision: String;
  End;
  TAssistantToolBroker = Class
  Private
    FAdapter: TAssistantWorkspaceAdapter; { borrowed; broker must be destroyed first }
    FOwner: TThreadID;
    FRunId, FIdentity: String;
    FCancelled, FAllowEdits: Boolean;
    FRevision: Integer;
    FSnapshots: Array Of TBrokerSnapshot;
    Function Remember(Const Path, Text: String): String;
  Public
    Constructor Create(Adapter: TAssistantWorkspaceAdapter);
    Function BeginRun(AllowEdits: Boolean): String;
    Procedure Cancel;
    Function Execute(Const RunId, Tool, Arguments: String;
      Out ResultText, ErrorText: String): Boolean;
    Function ToolsJson: String;
    Property RunId: String Read FRunId;
  End;
Implementation
Uses fpjson, jsonparser, AssistantProtocol;
Const MaxBufferBytes = 1048576; MaxSnapshotBytes = 8388608; MaxSnapshots = 64;
Function Quoted(Const S: String): String;
Begin Result := '"' + JsonEscapeText(S) + '"'; End;
Function TAssistantWorkspaceAdapter.CanBuild: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.StartBuild(Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'Build adapter unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.BuildStatus(Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'Build adapter unavailable.'; Result := False; End;
Procedure TAssistantWorkspaceAdapter.CancelBuild;
Begin End;
Constructor TAssistantToolBroker.Create(Adapter: TAssistantWorkspaceAdapter);
Begin
  Inherited Create;
  FAdapter := Adapter;
  FOwner := GetCurrentThreadID;
  FCancelled := True;
End;
Function TAssistantToolBroker.BeginRun(AllowEdits: Boolean): String;
Var Id: TGuid;
Begin
  If GetCurrentThreadID <> FOwner Then Raise Exception.Create('Broker requires IDE thread');
  If Not Assigned(FAdapter) Then Raise Exception.Create('Workspace adapter required');
  If CreateGUID(Id) <> 0 Then Raise Exception.Create('Unable to create run identity');
  FAdapter.CancelBuild;
  FRunId := GUIDToString(Id);
  FIdentity := FAdapter.Identity;
  FCancelled := False;
  FAllowEdits := AllowEdits;
  FRevision := 0;
  SetLength(FSnapshots, 0);
  Result := FRunId;
End;
Procedure TAssistantToolBroker.Cancel;
Begin
  If GetCurrentThreadID <> FOwner Then Raise Exception.Create('Broker requires IDE thread');
  FCancelled := True;
  FAdapter.CancelBuild;
  SetLength(FSnapshots, 0);
End;
Function TAssistantToolBroker.Remember(Const Path, Text: String): String;
Var I, Index, Bytes: Integer;
Begin
  Result := '';
  Index := -1; Bytes := 0;
  For I := 0 To High(FSnapshots) Do
    If FSnapshots[I].Path = Path Then Index := I
    Else Inc(Bytes, Length(FSnapshots[I].Text));
  If (Length(Text) > MaxBufferBytes) Or (Bytes + Length(Text) > MaxSnapshotBytes) Then Exit;
  If Index < 0 Then
    Begin
      If Length(FSnapshots) >= MaxSnapshots Then Exit;
      Index := Length(FSnapshots); SetLength(FSnapshots, Index + 1);
    End;
  Inc(FRevision);
  Result := FRunId + ':' + IntToStr(FRevision);
  FSnapshots[Index].Path := Path;
  FSnapshots[Index].Text := Text;
  FSnapshots[Index].Revision := Result;
End;
Function TAssistantToolBroker.Execute(Const RunId, Tool, Arguments: String;
  Out ResultText, ErrorText: String): Boolean;
Var Data, Node: TJSONData; Args: TJSONObject; Path, Text, Revision, NewText, ActualPath, ActualText: String;
  I, Index: Integer;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  If GetCurrentThreadID <> FOwner Then
    Begin ErrorText := 'IDE tool dispatched on the wrong thread.'; Exit; End;
  If FCancelled Or (RunId = '') Or (RunId <> FRunId) Or (FAdapter.Identity <> FIdentity) Then
    Begin ErrorText := 'Workspace/run changed or was cancelled; start a new run.'; Exit; End;
  If Length(Arguments) > MaxBufferBytes + 65536 Then
    Begin ErrorText := 'Tool arguments exceed the buffer limit.'; Exit; End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Arguments);
      If Not (Data Is TJSONObject) Then
        Begin ErrorText := 'Expected object arguments.'; Exit; End;
      Args := TJSONObject(Data);
      If (Tool = 'lazarus_start_build') Or (Tool = 'lazarus_build_status') Then
        Begin
          If Not FAllowEdits Or Not FAdapter.CanBuild Then
            Begin ErrorText := 'Build tools are unavailable in this mode.'; Exit; End;
          If Tool = 'lazarus_start_build' Then Result := FAdapter.StartBuild(ResultText, ErrorText)
          Else Result := FAdapter.BuildStatus(ResultText, ErrorText);
          Exit;
        End;
      If Tool = 'lazarus_project_info' Then
        Begin ResultText := FAdapter.Describe; Exit(True); End;
      If (Tool <> 'lazarus_read_buffer') And (Tool <> 'lazarus_replace_buffer') And
        (Tool <> 'lazarus_save_buffer') Then
        Begin ErrorText := 'Tool is not registered with the IDE broker.'; Exit; End;
      Node := Args.Find('path');
      If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Node.AsString = '') Then
        Begin ErrorText := 'A buffer path is required.'; Exit; End;
      If Not FAdapter.ReadBuffer(Node.AsString, Path, Text, ErrorText) Then Exit;
      If Length(Text) > MaxBufferBytes Then
        Begin ErrorText := 'Buffer exceeds the supported size.'; Exit; End;
      If Tool = 'lazarus_read_buffer' Then
        Begin
          Revision := Remember(Path, Text);
          If Revision = '' Then Begin ErrorText := 'Snapshot budget exhausted.'; Exit; End;
          ResultText := '{"path":' + Quoted(Path) + ',"revision":' + Quoted(Revision) + ',"text":' + Quoted(Text) + '}';
          Exit(True);
        End;
      If Not FAllowEdits Then
        Begin ErrorText := 'Buffer changes and saves require Build mode.'; Exit; End;
      Revision := Args.Get('revision', ''); Index := -1;
      For I := 0 To High(FSnapshots) Do
        If (FSnapshots[I].Path = Path) And (FSnapshots[I].Revision = Revision) Then Index := I;
      If (Index < 0) Or (FSnapshots[Index].Text <> Text) Then
        Begin ErrorText := 'Stale buffer revision; read the buffer again before changing or saving it.'; Exit; End;
      If Tool = 'lazarus_save_buffer' Then
        Begin
          Result := FAdapter.SaveBuffer(Path, Text, ErrorText);
          If Result Then ResultText := '{"saved":true,"revision":' + Quoted(Revision) + '}';
          Exit;
        End;
      Node := Args.Find('text');
      If Not Assigned(Node) Or (Node.JSONType <> jtString) Then
        Begin ErrorText := 'Replacement text is required.'; Exit; End;
      NewText := Node.AsString;
      If Length(NewText) > MaxBufferBytes Then
        Begin ErrorText := 'Replacement exceeds the buffer limit.'; Exit; End;
      { Reserve a revision before mutation; a budget failure must have no effects. }
      Revision := Remember(Path, NewText);
      If Revision = '' Then Begin ErrorText := 'Snapshot budget exhausted.'; Exit; End;
      Result := FAdapter.ReplaceBuffer(Path, Text, NewText, ErrorText);
      If Not Result Then
        Begin FSnapshots[Index].Revision := ''; FSnapshots[Index].Text := ''; Exit; End;
      { SynEdit can normalize line endings. Revision tokens must refer to the
        actual buffer, not the requested bytes. Read back without saving. }
      If Not FAdapter.ReadBuffer(Path, ActualPath, ActualText, ErrorText) Or (ActualPath <> Path) Then
        Begin
          FSnapshots[Index].Revision := '';
          ErrorText := 'Buffer was edited but could not be read back; inspect and reread it.';
          Exit(False);
        End;
      Revision := Remember(Path, ActualText);
      If Revision = '' Then
        Begin
          FSnapshots[Index].Revision := '';
          ErrorText := 'Buffer was edited but its normalized text exceeds the snapshot budget.';
          Exit(False);
        End;
      ResultText := '{"bufferUpdated":true,"saved":false,"revision":' + Quoted(Revision) +
        ',"text":' + Quoted(ActualText) + '}';
    Except
      On E: Exception Do ErrorText := 'IDE tool failed: ' + E.Message;
    End;
  Finally Data.Free; End;
End;
Function TAssistantToolBroker.ToolsJson: String;
Const ReadSchema = '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}';
  ChangeSchema = '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"text":{"type":"string"}},"required":["path","revision","text"],"additionalProperties":false}';
  SaveSchema = '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"}},"required":["path","revision"],"additionalProperties":false}';
Begin
  Result := '[{"type":"function","name":"lazarus_project_info","description":"Describe the active Lazarus project and open buffers.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_read_buffer","description":"Read current IDE text including unsaved changes and get a revision token.","inputSchema":' + ReadSchema + '}';
  If FAllowEdits Then Result := Result +
    ',{"type":"function","name":"lazarus_replace_buffer","description":"Replace a previously read buffer at its exact revision, preserving Undo. Does not save.","inputSchema":' + ChangeSchema + '},' +
    '{"type":"function","name":"lazarus_save_buffer","description":"Explicitly save the exact previously read or edited revision.","inputSchema":' + SaveSchema + '}';
  If FAllowEdits And FAdapter.CanBuild Then Result := Result +
    ',{"type":"function","name":"lazarus_start_build","description":"Start an asynchronous build of saved project inputs. Refuses dirty buffers. Does not save anything.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_build_status","description":"Get asynchronous build diagnostics and observed-input manifest. A compiler exit code is not test or full-source validation.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}}';
  Result := Result + ']';
End;
End.
