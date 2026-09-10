Unit AssistantToolBroker;

{ Backend-neutral, IDE-thread tool broker. Owns run identity and model-visible
  revisions. The adapter resolves project paths and uses the actual IDE buffers.
  This initial registry exposes bounded buffer operations; execution and build
  operations must not be smuggled through a generic unvalidated tool fallback. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
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
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Virtual;
    Function CanBuild: Boolean; Virtual;
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Virtual;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Virtual;
    Procedure CancelBuild; Virtual;
  End;
  TBrokerSnapshot = Record
    Path, Text, Revision: String;
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
Uses fpjson, jsonparser, AssistantProtocol;
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
Function TAssistantWorkspaceAdapter.CanFindDeclaration: Boolean;
Begin Result := False; End;
Function TAssistantWorkspaceAdapter.FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin ResultText := ''; ErrorText := 'CodeTools declaration lookup is unavailable.'; Result := False; End;
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
Function TAssistantToolBroker.Execute(Const RunId, Tool, Arguments: String;
  Out ResultText, ErrorText: String): Boolean;
Var Data, Node: TJSONData; Args: TJSONObject; Path, Text, Revision, NewText, ActualPath, ActualText: String;
  I, Index, Line, Column: Integer;
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
        (Tool <> 'lazarus_find_declaration') Then
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
      If (Tool <> 'lazarus_find_declaration') And
        (Not CanWritePath(Node.AsString) Or Not CanWritePath(Path)) Then
        Begin ErrorText := 'Plan mode can only change Markdown files; Ask is read-only.'; Exit; End;
      Revision := Args.Get('revision', ''); Index := -1;
      For I := 0 To High(FSnapshots) Do
        If (FSnapshots[I].Path = Path) And (FSnapshots[I].Revision = Revision) Then Index := I;
      If (Index < 0) Or (FSnapshots[Index].Text <> Text) Then
        Begin ErrorText := 'Stale buffer revision; read the buffer again before changing or saving it.'; Exit; End;
      If Tool = 'lazarus_find_declaration' Then
        Begin
          If Not FAdapter.CanFindDeclaration Then
            Begin ErrorText := 'CodeTools declaration lookup is unavailable.'; Exit; End;
          Node := Args.Find('line');
          If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or
            Not TryStrToInt(Node.AsJSON, Line) Or (Line < 1) Or (Line > MaxBufferBytes) Then
            Begin ErrorText := 'line must be a positive integer within the buffer limit.'; Exit; End;
          Node := Args.Find('column');
          If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Or
            Not TryStrToInt(Node.AsJSON, Column) Or (Column < 1) Or (Column > MaxBufferBytes) Then
            Begin ErrorText := 'column must be a positive UTF-8 byte column within the buffer limit.'; Exit; End;
          If Not FAdapter.FindDeclaration(Path, Line, Column, ResultText, ErrorText) Then Exit;
          { CodeTools can invoke IDE callbacks. Do not return coordinates from
            a request whose workspace or source changed while it was running. }
          If FCancelled Or (RunId <> FRunId) Or (FAdapter.Identity <> FIdentity) Then
            Begin ResultText := ''; ErrorText := 'Workspace/run changed during declaration lookup.'; Exit; End;
          If Not FAdapter.ReadBuffer(Path, ActualPath, ActualText, ErrorText) Or
            (ActualPath <> Path) Or (ActualText <> Text) Then
            Begin ResultText := ''; ErrorText := 'Source changed during declaration lookup; read it again.'; Exit; End;
          ResultText := '{"sourceRevision":' + Quoted(Revision) + ',"declaration":' + ResultText + '}';
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
