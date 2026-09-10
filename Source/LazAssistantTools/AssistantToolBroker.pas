Unit AssistantToolBroker;

{ Backend-neutral, IDE-thread tool broker. Owns run identity and model-visible
  revisions. The adapter resolves project paths and uses the actual IDE buffers.
  This initial registry exposes bounded buffer operations; execution and build
  operations must not be smuggled through a generic unvalidated tool fallback. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, fpjson;
Type
  TAssistantWriteScope = (awsReadOnly, awsMarkdown, awsProject);
  TAssistantWorkspaceAdapter = Class
  Public
    Function Identity: String; Virtual; Abstract;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Virtual; Abstract;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Virtual; Abstract;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Virtual; Abstract;
    Function Describe: String; Virtual; Abstract;
    Function IsMarkdownPath(Const Path: String): Boolean; Virtual;
    Function CanInspectFiles: Boolean; Virtual;
    Function ReadFile(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function ListDirectory(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function OpenBuffer(Const Path: String; Out ErrorText: String): Boolean; Virtual;
    Function CanCreateFiles: Boolean; Virtual;
    Function CheckNewFile(Const Path: String; Out CanonicalPath, ErrorText: String): Boolean; Virtual;
    Function CreateFile(Const Path, Text: String; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function CanFindDeclaration: Boolean; Virtual;
    Function CanInspectSymbols: Boolean; Virtual;
    Function CanPreviewRename: Boolean; Virtual;
    Function PreviewLocalRename(Const Path: String; Line, Column: Integer; Const NewName: String;
      Out NewText, PreviewText, ErrorText: String): Boolean; Virtual;
    Function SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function CanBuild: Boolean; Virtual;
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Virtual;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Virtual;
    Procedure CancelBuild; Virtual;
  End;
  TBrokerSnapshot = Record
    Path, Text, Revision: String;
  End;
  TLocalRenamePreview = Record
    Id, Path, Text, NewText, Details, NewName: String;
    Line, Column: Integer;
  End;
  TAssistantToolApproval = Function(Const Tool, Path, OldText, NewText: String): Boolean Of Object;
  TAssistantToolBroker = Class
  Private
    FAdapter: TAssistantWorkspaceAdapter; { borrowed; broker must be destroyed first }
    FOwner: TThreadID;
    FRunId, FIdentity: String;
    FCancelled: Boolean;
    FWriteScope: TAssistantWriteScope;
    FRevision: Integer;
    FSnapshots: Array Of TBrokerSnapshot;
    FOnApproval: TAssistantToolApproval;
    FRenamePreview: TLocalRenamePreview;
    Function ExecuteRename(Const RunId, Tool: String; Args: TJSONObject;
      Out ResultText, ErrorText: String): Boolean;
    Function CommitBuffer(Const Path, Text, NewText: String; Out ResultText, ErrorText: String): Boolean;
    Function Approve(Const RunId, Tool, Path, OldText, NewText: String; Out ErrorText: String): Boolean;
    Function CanWritePath(Const Path: String): Boolean;
    Function Remember(Const Path, Text: String): String;
  Public
    Constructor Create(Adapter: TAssistantWorkspaceAdapter);
    Function BeginRun(WriteScope: TAssistantWriteScope): String;
    Procedure Cancel;
    Function Execute(Const RunId, Tool, Arguments: String;
      Out ResultText, ErrorText: String): Boolean;
    Function ToolsJson: String;
    Property OnApproval: TAssistantToolApproval Read FOnApproval Write FOnApproval;
    Property RunId: String Read FRunId;
  End;
Implementation
Uses jsonparser, AssistantProtocol;
Const MaxBufferBytes = 1048576; MaxSnapshotBytes = 8388608; MaxSnapshots = 64;
Function Quoted(Const S: String): String;
Begin Result := '"' + JsonEscapeText(S) + '"'; End;
Function TAssistantWorkspaceAdapter.IsMarkdownPath(Const Path: String): Boolean;
Var Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.md') Or (Ext = '.markdown') Or (Ext = '.mdown');
End;
Function TAssistantToolBroker.CanWritePath(Const Path: String): Boolean;
Begin
  Result := (FWriteScope = awsProject) Or
    ((FWriteScope = awsMarkdown) And FAdapter.IsMarkdownPath(Path));
End;
Function TAssistantWorkspaceAdapter.CanInspectFiles: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.ReadFile(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'File inspection unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.ListDirectory(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'Directory inspection unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.OpenBuffer(Const Path: String; Out ErrorText: String): Boolean;
Begin ErrorText := 'Opening buffers unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.CanCreateFiles: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.CheckNewFile(Const Path: String; Out CanonicalPath, ErrorText: String): Boolean;
Begin CanonicalPath := ''; ErrorText := 'New file creation unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.CreateFile(Const Path, Text: String; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'New file creation unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.CanPreviewRename: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.PreviewLocalRename(Const Path: String; Line, Column: Integer;
  Const NewName: String; Out NewText, PreviewText, ErrorText: String): Boolean;
Begin NewText := ''; PreviewText := ''; ErrorText := 'Local rename preview is unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.CanInspectSymbols: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'Symbol context is unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'Reference lookup is unavailable.'; Result := False; End;
Function TAssistantWorkspaceAdapter.CanFindDeclaration: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'CodeTools symbol lookup is unavailable.'; Result := False; End;
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
Function TAssistantToolBroker.BeginRun(WriteScope: TAssistantWriteScope): String;
Var Id: TGuid;
Begin
  If GetCurrentThreadID <> FOwner Then Raise Exception.Create('Broker requires IDE thread');
  If Not Assigned(FAdapter) Then Raise Exception.Create('Workspace adapter required');
  If CreateGUID(Id) <> 0 Then Raise Exception.Create('Unable to create run identity');
  FAdapter.CancelBuild;
  FRunId := GUIDToString(Id);
  FIdentity := FAdapter.Identity;
  FCancelled := False;
  FWriteScope := WriteScope;
  FRevision := 0;
  SetLength(FSnapshots, 0); FRenamePreview := Default(TLocalRenamePreview);
  Result := FRunId;
End;
Procedure TAssistantToolBroker.Cancel;
Begin
  If GetCurrentThreadID <> FOwner Then Raise Exception.Create('Broker requires IDE thread');
  FCancelled := True;
  FAdapter.CancelBuild;
  SetLength(FSnapshots, 0); FRenamePreview := Default(TLocalRenamePreview);
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
Function TAssistantToolBroker.Approve(Const RunId, Tool, Path, OldText, NewText: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  If Assigned(FOnApproval) And Not FOnApproval(Tool, Path, OldText, NewText) Then
    Begin ErrorText := 'User declined this tool operation.'; Exit; End;
  { A modal approval can dispatch IDE events. Revalidate the run before any
    effect; adapters also compare the approved buffer text at mutation time. }
  If FCancelled Or (FRunId <> RunId) Or (FAdapter.Identity <> FIdentity) Then
    Begin ErrorText := 'Workspace/run changed or was cancelled during approval.'; Exit; End;
  If (Path <> '') And Not CanWritePath(Path) Then
    Begin ErrorText := 'Plan mode can only change Markdown files; Ask is read-only.'; Exit; End;
  Result := True;
End;
Function TAssistantToolBroker.ExecuteRename(Const RunId, Tool: String; Args: TJSONObject;
  Out ResultText, ErrorText: String): Boolean;
Var Pending: TLocalRenamePreview; Node: TJSONData; Id: TGuid;
  ActualPath, ActualText, Revision, RecheckedText, RecheckedDetails: String;
  I: Integer; Fresh: Boolean;
  Function StillCurrent: Boolean;
  Begin
    Result := Not FCancelled And (FRunId = RunId) And (FAdapter.Identity = FIdentity);
    If Not Result Then Begin ErrorText := 'Workspace/run changed during rename; prepare a new preview.'; Exit; End;
    Result := FAdapter.ReadBuffer(Pending.Path, ActualPath, ActualText, ErrorText) And
      (ActualPath = Pending.Path) And (ActualText = Pending.Text);
    If Not Result Then ErrorText := 'Source changed since rename preview; read it again and prepare a new preview.';
  End;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  If Not FAdapter.CanPreviewRename Then Begin ErrorText := 'Local rename is unavailable.'; Exit; End;
  If Tool = 'lazarus_apply_local_rename' Then
    Begin
      If FWriteScope <> awsProject Then Begin ErrorText := 'Applying a source rename requires Build mode.'; Exit; End;
      Node := Args.Find('preview_id');
      If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Node.AsString = '') Or
        (Node.AsString <> FRenamePreview.Id) Then
        Begin ErrorText := 'Unknown, expired or already consumed rename preview.'; Exit; End;
      Pending := FRenamePreview; FRenamePreview := Default(TLocalRenamePreview);
      If Not StillCurrent Then Exit;
      If Not Approve(RunId, Tool, Pending.Path, Pending.Text, Pending.NewText, ErrorText) Then Exit;
      If Not StillCurrent Then Exit;
      { Recompute against current CodeTools configuration after modal approval. }
      If Not FAdapter.PreviewLocalRename(Pending.Path, Pending.Line, Pending.Column, Pending.NewName,
        RecheckedText, RecheckedDetails, ErrorText) Then Exit;
      If Not StillCurrent Then Exit;
      If (RecheckedText <> Pending.NewText) Or (RecheckedDetails <> Pending.Details) Then
        Begin ErrorText := 'Semantic rename changed since preview; prepare a new preview.'; Exit; End;
      Result := CommitBuffer(Pending.Path, Pending.Text, Pending.NewText, ResultText, ErrorText);
      If Result Then ResultText := '{"preview_id":' + Quoted(Pending.Id) + ',"applied":true,' + Copy(ResultText, 2, MaxInt);
      Exit;
    End;
  FRenamePreview := Default(TLocalRenamePreview); Pending := Default(TLocalRenamePreview);
  Node := Args.Find('path');
  If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Trim(Node.AsString) = '') Then
    Begin ErrorText := 'A source buffer path is required.'; Exit; End;
  If Not FAdapter.ReadBuffer(Node.AsString, Pending.Path, Pending.Text, ErrorText) Then Exit;
  Revision := Args.Get('revision', ''); Fresh := False;
  For I := 0 To High(FSnapshots) Do
    If (FSnapshots[I].Path = Pending.Path) And (FSnapshots[I].Revision = Revision) And
      (FSnapshots[I].Text = Pending.Text) Then Fresh := True;
  If Not Fresh Then Begin ErrorText := 'Stale buffer revision; read the buffer before preparing a rename.'; Exit; End;
  Node := Args.Find('line');
  If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or Not TryStrToInt(Node.AsJSON, Pending.Line) Or
    (Pending.Line < 1) Or (Pending.Line > MaxBufferBytes) Then
    Begin ErrorText := 'line must be a positive integer within the buffer limit.'; Exit; End;
  Node := Args.Find('column');
  If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or Not TryStrToInt(Node.AsJSON, Pending.Column) Or
    (Pending.Column < 1) Or (Pending.Column > MaxBufferBytes) Then
    Begin ErrorText := 'column must be a positive UTF-8 byte column within the buffer limit.'; Exit; End;
  Node := Args.Find('new_name');
  If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Length(Node.AsString) > 127) Then
    Begin ErrorText := 'new_name must be a Pascal identifier of at most 127 characters.'; Exit; End;
  Pending.NewName := Node.AsString;
  If Not FAdapter.PreviewLocalRename(Pending.Path, Pending.Line, Pending.Column, Pending.NewName,
    Pending.NewText, Pending.Details, ErrorText) Then Exit;
  If Not StillCurrent Then Exit;
  If (Length(Pending.NewText) > MaxBufferBytes) Or (Length(Pending.Details) > 65536) Then
    Begin ErrorText := 'Rename exceeds the preview size limit.'; Exit; End;
  If CreateGUID(Id) <> 0 Then Begin ErrorText := 'Cannot create rename preview identity.'; Exit; End;
  Pending.Id := GUIDToString(Id); FRenamePreview := Pending;
  ResultText := '{"preview_id":' + Quoted(Pending.Id) + ',"path":' + Quoted(Pending.Path) +
    ',"sourceRevision":' + Quoted(Revision) + ',"applied":false,"saved":false,"rename":' + Pending.Details + '}';
  Result := True;
End;
Function TAssistantToolBroker.CommitBuffer(Const Path, Text, NewText: String;
  Out ResultText, ErrorText: String): Boolean;
Var Revision, ActualPath, ActualText, CommitRun: String;
  Procedure Invalidate;
  Var I: Integer;
  Begin
    If FRunId <> CommitRun Then Exit;
    For I := 0 To High(FSnapshots) Do If FSnapshots[I].Path = Path Then
      Begin FSnapshots[I].Revision := ''; FSnapshots[I].Text := ''; End;
  End;
Begin
  Result := False; ResultText := ''; CommitRun := FRunId;
  { Reserve before mutation; a budget failure must have no effects. }
  Revision := Remember(Path, NewText);
  If Revision = '' Then Begin ErrorText := 'Snapshot budget exhausted.'; Exit; End;
  Try
    If Not FAdapter.ReplaceBuffer(Path, Text, NewText, ErrorText) Then
      Begin Invalidate; Exit; End;
    If FCancelled Or (FRunId <> CommitRun) Or (FAdapter.Identity <> FIdentity) Then
      Begin Invalidate; ErrorText := 'Buffer was edited but the workspace/run changed; inspect and reread it.'; Exit; End;
    { SynEdit can normalize line endings; return a revision of the actual text. }
    If Not FAdapter.ReadBuffer(Path, ActualPath, ActualText, ErrorText) Or (ActualPath <> Path) Then
      Begin Invalidate; ErrorText := 'Buffer was edited but could not be read back; inspect and reread it.'; Exit; End;
    If FCancelled Or (FRunId <> CommitRun) Or (FAdapter.Identity <> FIdentity) Then
      Begin Invalidate; ErrorText := 'Buffer was edited but the workspace/run changed; inspect and reread it.'; Exit; End;
    Revision := Remember(Path, ActualText);
    If Revision = '' Then
      Begin Invalidate; ErrorText := 'Buffer was edited but its normalized text exceeds the snapshot budget.'; Exit; End;
    ResultText := '{"bufferUpdated":true,"saved":false,"revision":' + Quoted(Revision) +
      ',"text":' + Quoted(ActualText) + '}';
    Result := True;
  Except
    On E: Exception Do
      Begin Invalidate; ErrorText := 'Editor commit failed; inspect and reread the buffer before retrying: ' + E.Message; End;
  End;
End;
Function TAssistantToolBroker.Execute(Const RunId, Tool, Arguments: String;
  Out ResultText, ErrorText: String): Boolean;
Var Data, Node: TJSONData; Args: TJSONObject; Path, Text, Revision, NewText, ActualPath, ActualText: String;
  I, Index, Line, Column, MaxResults: Integer; SearchPaths: TStringList; ResultField: String; Semantic: Boolean;
Begin
  Result := False; ResultText := ''; ErrorText := '';
  Semantic := (Tool = 'lazarus_find_declaration') Or (Tool = 'lazarus_find_references') Or (Tool = 'lazarus_symbol_context');
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
      If (Tool = 'lazarus_preview_local_rename') Or (Tool = 'lazarus_apply_local_rename') Then
        Begin Result := ExecuteRename(RunId, Tool, Args, ResultText, ErrorText); Exit; End;
      If Tool = 'lazarus_create_file' Then
        Begin
          If (FWriteScope = awsReadOnly) Or Not FAdapter.CanCreateFiles Then
            Begin ErrorText := 'New file creation requires Plan or Build mode and a supported workspace.'; Exit; End;
          Node := Args.Find('path');
          If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Trim(Node.AsString) = '') Then
            Begin ErrorText := 'A new project file path is required.'; Exit; End;
          If Not CanWritePath(Node.AsString) Then
            Begin ErrorText := 'Plan mode can only create Markdown files.'; Exit; End;
          If Not FAdapter.CheckNewFile(Node.AsString, Path, ErrorText) Then Exit;
          If Not CanWritePath(Path) Then
            Begin ErrorText := 'Plan mode can only create Markdown files.'; Exit; End;
          Node := Args.Find('text');
          If Not Assigned(Node) Or (Node.JSONType <> jtString) Then
            Begin ErrorText := 'File text is required.'; Exit; End;
          NewText := Node.AsString;
          If (Length(NewText) > MaxBufferBytes) Or (Pos(#0, NewText) > 0) Then
            Begin ErrorText := 'File must contain at most 1 MiB of text without NUL bytes.'; Exit; End;
          If Not Approve(RunId, Tool, Path, '', NewText, ErrorText) Then Exit;
          Result := FAdapter.CreateFile(Path, NewText, ResultText, ErrorText); Exit;
        End;
      If (Tool = 'lazarus_start_build') Or (Tool = 'lazarus_build_status') Then
        Begin
          If (FWriteScope <> awsProject) Or Not FAdapter.CanBuild Then
            Begin ErrorText := 'Build tools are unavailable in this mode.'; Exit; End;
          If Tool = 'lazarus_start_build' Then
            Begin
              If Not Approve(RunId, Tool, '', '', '', ErrorText) Then Exit;
              Result := FAdapter.StartBuild(ResultText, ErrorText);
            End
          Else Result := FAdapter.BuildStatus(ResultText, ErrorText);
          Exit;
        End;
      If Tool = 'lazarus_project_info' Then
        Begin ResultText := FAdapter.Describe; Exit(True); End;
      If (Tool = 'lazarus_read_file') Or (Tool = 'lazarus_list_directory') Or
        (Tool = 'lazarus_open_buffer') Then
        Begin
          If Not FAdapter.CanInspectFiles Then
            Begin ErrorText := 'Project file inspection unavailable.'; Exit; End;
          Node := Args.Find('path');
          If Not Assigned(Node) Or (Node.JSONType <> jtString) Or
            ((Tool <> 'lazarus_list_directory') And (Trim(Node.AsString) = '')) Then
            Begin ErrorText := 'A project path is required.'; Exit; End;
          If Tool = 'lazarus_read_file' Then
            Begin Result := FAdapter.ReadFile(Arguments, ResultText, ErrorText); Exit; End;
          If Tool = 'lazarus_list_directory' Then
            Begin Result := FAdapter.ListDirectory(Arguments, ResultText, ErrorText); Exit; End;
          If Not FAdapter.OpenBuffer(Node.AsString, ErrorText) Then Exit;
        End;
      If (Tool <> 'lazarus_read_buffer') And (Tool <> 'lazarus_replace_buffer') And
        (Tool <> 'lazarus_save_buffer') And (Tool <> 'lazarus_open_buffer') And
        (Not Semantic) Then
        Begin ErrorText := 'Tool is not registered with the IDE broker.'; Exit; End;
      Node := Args.Find('path');
      If Not Assigned(Node) Or (Node.JSONType <> jtString) Or (Node.AsString = '') Then
        Begin ErrorText := 'A buffer path is required.'; Exit; End;
      If Not FAdapter.ReadBuffer(Node.AsString, Path, Text, ErrorText) Then Exit;
      If Length(Text) > MaxBufferBytes Then
        Begin ErrorText := 'Buffer exceeds the supported size.'; Exit; End;
      If (Tool = 'lazarus_read_buffer') Or (Tool = 'lazarus_open_buffer') Then
        Begin
          Revision := Remember(Path, Text);
          If Revision = '' Then Begin ErrorText := 'Snapshot budget exhausted.'; Exit; End;
          ResultText := '{"path":' + Quoted(Path) + ',"revision":' + Quoted(Revision) + ',"text":' + Quoted(Text) + '}';
          Exit(True);
        End;
      If (Not Semantic) And
        (Not CanWritePath(Node.AsString) Or Not CanWritePath(Path)) Then
        Begin ErrorText := 'Plan mode can only change Markdown files; Ask is read-only.'; Exit; End;
      Revision := Args.Get('revision', ''); Index := -1;
      For I := 0 To High(FSnapshots) Do
        If (FSnapshots[I].Path = Path) And (FSnapshots[I].Revision = Revision) Then Index := I;
      If (Index < 0) Or (FSnapshots[Index].Text <> Text) Then
        Begin ErrorText := 'Stale buffer revision; read the buffer again before using this request.'; Exit; End;
      If Semantic Then
        Begin
          If ((Tool = 'lazarus_find_declaration') And Not FAdapter.CanFindDeclaration) Or
            ((Tool <> 'lazarus_find_declaration') And Not FAdapter.CanInspectSymbols) Then
            Begin ErrorText := 'CodeTools symbol lookup is unavailable.'; Exit; End;
          Node := Args.Find('line');
          If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or
            Not TryStrToInt(Node.AsJSON, Line) Or (Line < 1) Or (Line > MaxBufferBytes) Then
            Begin ErrorText := 'line must be a positive integer within the buffer limit.'; Exit; End;
          Node := Args.Find('column');
          If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or
            Not TryStrToInt(Node.AsJSON, Column) Or (Column < 1) Or (Column > MaxBufferBytes) Then
            Begin ErrorText := 'column must be a positive UTF-8 byte column within the buffer limit.'; Exit; End;
          ResultField := 'declaration';
          If Tool = 'lazarus_find_declaration' Then
            Begin If Not FAdapter.FindDeclaration(Path, Line, Column, ResultText, ErrorText) Then Exit; End
          Else If Tool = 'lazarus_symbol_context' Then
            Begin
              ResultField := 'symbol';
              If Not FAdapter.SymbolContext(Path, Line, Column, ResultText, ErrorText) Then Exit;
            End
          Else
            Begin
              ResultField := 'references'; MaxResults := 100;
              Node := Args.Find('max_results');
              If Assigned(Node) And ((Node.JSONType <> jtNumber) Or Not TryStrToInt(Node.AsJSON, MaxResults) Or
                (MaxResults < 1) Or (MaxResults > 200)) Then
                Begin ErrorText := 'max_results must be an integer from 1 to 200.'; Exit; End;
              Node := Args.Find('search_paths');
              If Not (Node Is TJSONArray) Or (Node.Count < 1) Or (Node.Count > 32) Then
                Begin ErrorText := 'search_paths must list 1 to 32 project source files.'; Exit; End;
              SearchPaths := TStringList.Create;
              Try
                For I := 0 To Node.Count - 1 Do
                  Begin
                    If (Node.Items[I].JSONType <> jtString) Or (Trim(Node.Items[I].AsString) = '') Then
                      Begin ErrorText := 'Each search path must be a nonempty string.'; Exit; End;
                    SearchPaths.Add(Node.Items[I].AsString);
                  End;
                If Not FAdapter.FindReferences(Path, Line, Column, SearchPaths, MaxResults, ResultText, ErrorText) Then Exit;
              Finally SearchPaths.Free; End;
            End;
          { CodeTools can invoke IDE callbacks. Do not return coordinates from
            a request whose workspace or source changed while it was running. }
          If FCancelled Or (RunId <> FRunId) Or (FAdapter.Identity <> FIdentity) Then
            Begin ResultText := ''; ErrorText := 'Workspace/run changed during symbol lookup.'; Exit; End;
          If Not FAdapter.ReadBuffer(Path, ActualPath, ActualText, ErrorText) Or
            (ActualPath <> Path) Or (ActualText <> Text) Then
            Begin ResultText := ''; ErrorText := 'Source changed during symbol lookup; read it again.'; Exit; End;
          ResultText := '{"sourceRevision":' + Quoted(Revision) + ',' + Quoted(ResultField) + ':' + ResultText + '}';
          Exit(True);
        End;
      If Tool = 'lazarus_save_buffer' Then
        Begin
          If Not Approve(RunId, Tool, Path, Text, '', ErrorText) Then Exit;
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
      If Not Approve(RunId, Tool, Path, Text, NewText, ErrorText) Then Exit;
      Result := CommitBuffer(Path, Text, NewText, ResultText, ErrorText);
    Except
      On E: Exception Do ErrorText := 'IDE tool failed: ' + E.Message;
    End;
  Finally Data.Free; End;
End;
Function TAssistantToolBroker.ToolsJson: String;
Const ReadSchema = '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}';
  FileSchema = '{"type":"object","properties":{"path":{"type":"string"},"start_line":{"type":"integer","minimum":1},"end_line":{"type":"integer","minimum":1},"max_chars":{"type":"integer","minimum":1,"maximum":48000}},"required":["path"],"additionalProperties":false}';
  ChangeSchema = '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"text":{"type":"string"}},"required":["path","revision","text"],"additionalProperties":false}';
  SaveSchema = '{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"}},"required":["path","revision"],"additionalProperties":false}';
Var WriteNote: String;
Begin
  WriteNote := '';
  If FWriteScope = awsMarkdown Then WriteNote := ' Plan mode: only .md, .markdown and .mdown files are writable.';
  Result := '[{"type":"function","name":"lazarus_project_info","description":"Describe the active Lazarus project and open buffers.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_read_buffer","description":"Read current IDE text including unsaved changes and get a revision token.","inputSchema":' + ReadSchema + '}';
  If FAdapter.CanInspectFiles Then Result := Result +
    ',{"type":"function","name":"lazarus_list_directory","description":"List a project directory, capped at 400 entries. Use path dot for the project root.","inputSchema":' + ReadSchema + '},' +
    '{"type":"function","name":"lazarus_read_file","description":"Read project text, preferring unsaved IDE buffers over disk. Supports line ranges and capped output. Does not open or save files; does not issue edit revisions.","inputSchema":' + FileSchema + '},' +
    '{"type":"function","name":"lazarus_open_buffer","description":"Open an existing project text file in a background editor tab, or reuse its unsaved buffer. Return current text and an edit revision; does not create or save files.","inputSchema":' + ReadSchema + '}';
  If FAdapter.CanFindDeclaration Then Result := Result +
    ',{"type":"function","name":"lazarus_find_declaration","description":"Resolve a Pascal identifier using Lazarus CodeTools and the current project configuration. First read/open the source buffer and supply its revision. Coordinates are 1-based lines and UTF-8 byte columns, including tabs as one byte. Returns a declaration location without moving the editor, changing files or issuing an edit revision for the target.","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1}},"required":["path","revision","line","column"],"additionalProperties":false}}';
  If FAdapter.CanInspectSymbols Then Result := Result +
    ',{"type":"function","name":"lazarus_symbol_context","description":"Get a CodeTools hint and bounded source/declaration context for a Pascal symbol, using the current buffer revision. Read-only; positions are 1-based UTF-8 byte columns. External declarations expose location only.","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1}},"required":["path","revision","line","column"],"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_find_references","description":"Find semantic Pascal references to the symbol at this revision and location. Supply an explicit search_paths list of 1-32 project source files. Prefers unsaved IDE buffers. Returns searched files, failures and truncation; never assume whole-project coverage. Comments, strings, inactive branches and unrelated same-name symbols are excluded. Read-only; columns are 1-based UTF-8 bytes.","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1},"search_paths":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":32},"max_results":{"type":"integer","minimum":1,"maximum":200,"default":100}},"required":["path","revision","line","column","search_paths"],"additionalProperties":false}}';
  If FAdapter.CanPreviewRename Then
    Begin
      Result := Result + ',{"type":"function","name":"lazarus_preview_local_rename","description":"Preview a routine-local var rename using CodeTools. Requires a current buffer revision; coordinates are 1-based UTF-8 bytes. Returns exact changes and a one-use preview_id without editing. Supports one editor only; rejects parameters, globals, fields, directives/includes/assembly and names already present. Preview is valid only in this run; no partial renames.","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"revision":{"type":"string"},"line":{"type":"integer","minimum":1},"column":{"type":"integer","minimum":1},"new_name":{"type":"string"}},"required":["path","revision","line","column","new_name"],"additionalProperties":false}}';
      If FWriteScope = awsProject Then Result := Result + ',{"type":"function","name":"lazarus_apply_local_rename","description":"Apply the exact previously reviewed local rename preview in Build mode. Revalidates source and CodeTools results after approval. Consumes preview_id, preserves editor Undo and returns a fresh buffer revision. Does not save or compile; never supply replacement text.","inputSchema":{"type":"object","properties":{"preview_id":{"type":"string"}},"required":["preview_id"],"additionalProperties":false}}';
    End;
  If FWriteScope <> awsReadOnly Then Result := Result +
    ',{"type":"function","name":"lazarus_replace_buffer","description":"Replace a previously read buffer at its exact revision, preserving Undo. Does not save.' + WriteNote + '","inputSchema":' + ChangeSchema + '},' +
    '{"type":"function","name":"lazarus_save_buffer","description":"Explicitly save the exact previously read or edited revision.' + WriteNote + '","inputSchema":' + SaveSchema + '}';
  If (FWriteScope <> awsReadOnly) And FAdapter.CanCreateFiles Then Result := Result +
    ',{"type":"function","name":"lazarus_create_file","description":"Create a new project text file (for example Documents/BugReport.md) and missing parent directories. Never overwrites an existing file or editor buffer. Writes to disk without opening a tab, adding a project member or compiling. To edit existing files, use buffer revision tools.' + WriteNote + '","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"text":{"type":"string"}},"required":["path","text"],"additionalProperties":false}}';
  If (FWriteScope = awsProject) And FAdapter.CanBuild Then Result := Result +
    ',{"type":"function","name":"lazarus_start_build","description":"Start an asynchronous build of saved project inputs. Refuses dirty buffers. Does not save anything.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_build_status","description":"Get asynchronous build diagnostics and observed-input manifest. A compiler exit code is not test or full-source validation.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}}';
  Result := Result + ']';
End;
End.
