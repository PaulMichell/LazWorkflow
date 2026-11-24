Program AssistantEditorEditsTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Controls, Classes, SysUtils, Types, AssistantFormSave,
  SynEdit, SrcEditorIntf, AssistantConversation, AssistantEditorEdits, AssistantToolBroker, AssistantProtocol, fpjson,
  jsonparser;
Type
  { Exercise the real IDE interface's ReplaceText with a real SynEdit Undo stack.
    Only the editor methods used by that operation are implemented. }
  TTestEditor = Class(TSourceEditorInterface)
  Protected
    Function GetSourceText: String; Override;
    Function GetReadOnly: Boolean; Override;
    Function GetModified: Boolean; Override;
    Procedure SetModified(Const NewValue: Boolean); Override;
    Function GetEditorControl: TWinControl; Override;
    Procedure SetSourceText(Const Value: String); Override;
    Procedure SetCursorTextXY(Const Value: TPoint); Override;
    Procedure SetSelection(Const Value: String); Override;
  Public
    Syn: TSynEdit;
    Procedure SelectText(Const StartPos, EndPos: TPoint); Override;
    Procedure BeginUndoBlock; Override;
    Procedure EndUndoBlock; Override;
    Procedure BeginUpdate; Override;
    Procedure EndUpdate; Override;
  End;
Type
  TBrokerWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Editor: TTestEditor;
    ProjectId: String;
    ApprovalAction, ApprovalCalls, Builds, MutationAction: Integer;
    SaveSucceeds: Boolean;
    SavedText: String;
    ApprovalBroker: TAssistantToolBroker;
    Function Approve(Const Tool, Path, OldText, NewText: String): Boolean;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function CanBuild: Boolean; Override;
    Function StartBuild(Const PackagePath: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function BuildStatus(Out ResultText, ErrorText: String; Const Detail: String = ''): Boolean; Override;
  End;
Function TBrokerWorkspace.Approve(Const Tool, Path, OldText, NewText: String): Boolean;
Begin
  Inc(ApprovalCalls);
  Result := ApprovalAction <> 0;
  Case ApprovalAction Of
    2: ProjectId := 'switched-during-approval';
    3: ApprovalBroker.Cancel;
    4: Editor.Syn.Text := 'user edit during approval';
  End;
End;
Function TBrokerWorkspace.Identity: String;
Begin Result := ProjectId; End;
Function TBrokerWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin CanonicalPath := Path; Text := Editor.SourceText; ErrorText := ''; Result := True; End;
Function TBrokerWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  Result := ApplyAssistantEditorText(Editor, ExpectedText, NewText, ErrorText);
  If Result Then Case MutationAction Of
    1: ApprovalBroker.Cancel;
    2: Raise Exception.Create('Injected callback failure after mutation');
    3: ApprovalBroker.BeginRun(awsProject);
  End;
End;
Function TBrokerWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  Result := SaveSucceeds; ErrorText := '';
  If Result Then SavedText := ExpectedText Else ErrorText := 'Injected save failure';
End;
Function TBrokerWorkspace.CanBuild: Boolean;
Begin Result := True; End;
Function TBrokerWorkspace.StartBuild(Const PackagePath: String; Out ResultText, ErrorText: String): Boolean;
Begin Inc(Builds); ResultText := '{"started":true}'; ErrorText := ''; Result := True; End;
Function TBrokerWorkspace.BuildStatus(Out ResultText, ErrorText: String; Const Detail: String): Boolean;
Begin ResultText := '{"done":true}'; ErrorText := ''; Result := True; End;
Function TBrokerWorkspace.Describe: String;
Begin Result := 'Test project'; End;
Function TTestEditor.GetSourceText: String;
Begin Result := Syn.Text; End;
Function TTestEditor.GetModified: Boolean;
Begin Result := Syn.Modified; End;
Procedure TTestEditor.SetModified(Const NewValue: Boolean);
Begin Syn.Modified := NewValue; End;
Function TTestEditor.GetEditorControl: TWinControl;
Begin Result := Syn; End;
Function TTestEditor.GetReadOnly: Boolean;
Begin Result := Syn.ReadOnly; End;
Procedure TTestEditor.SetSourceText(Const Value: String);
Begin Raise Exception.Create('SourceText assignment must never be used'); End;
Procedure TTestEditor.SetCursorTextXY(Const Value: TPoint);
Begin Syn.LogicalCaretXY := Value; End;
Procedure TTestEditor.SetSelection(Const Value: String);
Begin Syn.SelText := Value; End;
Procedure TTestEditor.SelectText(Const StartPos, EndPos: TPoint);
Begin Syn.BlockBegin := StartPos; Syn.BlockEnd := EndPos; End;
Procedure TTestEditor.BeginUndoBlock;
Begin Syn.BeginUndoBlock; End;
Procedure TTestEditor.EndUndoBlock;
Begin Syn.EndUndoBlock; End;
Procedure TTestEditor.BeginUpdate;
Begin Syn.BeginUpdate; End;
Procedure TTestEditor.EndUpdate;
Begin Syn.EndUpdate; End;
Procedure Check(Const Title: String; Value: Boolean);
Begin
  If Not Value Then Begin WriteLn(StdErr, 'FAIL ', Title); Halt(1); End;
  WriteLn('ok ', Title);
End;
Procedure TestBroker(Editor: TTestEditor);
Var Workspace: TBrokerWorkspace; Broker: TAssistantToolBroker;
  Run, OldRun, Reply, Err, Revision, Original, Changed, Args: String; Data: TJSONData; I: Integer;
Begin
  Workspace := TBrokerWorkspace.Create;
  Workspace.Editor := Editor; Workspace.ProjectId := 'project-1';
  Broker := TAssistantToolBroker.Create(Workspace);
  Try
    Original := Editor.SourceText;
    Changed := StringReplace(Original, 'b', 'broker edit', []);
    Run := Broker.BeginRun(awsProject);
    Check('broker reads unsaved IDE text', Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err));
    Data := GetJSON(Reply);
    Try
      Revision := TJSONObject(Data).Get('revision', '');
      Check('broker returns exact unsaved text', TJSONObject(Data).Get('text', '') = Original);
    Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalBroker := Broker; Broker.OnApproval := @Workspace.Approve;
    Check('declined edit has no side effect', Not Broker.Execute(Run, 'write_file', Args, Reply, Err)
      And (Editor.SourceText = Original) And (Pos('declined', Err) > 0));
    Check('declined save never reaches adapter', Not Broker.Execute(Run, 'save_file', Args, Reply, Err)
      And (Pos('declined', Err) > 0));
    Workspace.ApprovalAction := 1;
    Check('broker applies revision-checked edit', Broker.Execute(Run, 'write_file', Args, Reply, Err));
    Check('broker updated live editor', Editor.SourceText = Changed);
    Check('replayed revision rejected', Not Broker.Execute(Run, 'write_file', Args, Reply, Err));
    Editor.Syn.Undo;
    Check('broker edit is one Undo operation', Editor.SourceText = Original);
    Check('Undo invalidates model revision', Not Broker.Execute(Run, 'write_file', Args, Reply, Err));
    OldRun := Run; Run := Broker.BeginRun(awsReadOnly);
    Check('old run rejected', Not Broker.Execute(OldRun, 'get_project_info', '{}', Reply, Err));
    Check('Inspect mode advertises no mutation tool', Pos('"name":"write_file"', Broker.ToolsJson) = 0);
    Check('Inspect mode rejects mutation', Not Broker.Execute(Run, 'write_file', Args, Reply, Err));
    Check('Inspect mode rejects edits without requesting approval', Workspace.ApprovalCalls = 3);
    Workspace.ProjectId := 'project-2';
    Check('project switch rejects tools', Not Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err));
    Run := Broker.BeginRun(awsProject); Broker.Cancel;
    Check('cancelled run rejects tools', Not Broker.Execute(Run, 'get_project_info', '{}', Reply, Err));
    Run := Broker.BeginRun(awsProject);
    Check('unknown tool has no fallback', Not Broker.Execute(Run, 'write_file', '{}', Reply, Err));
    Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply);
    Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Check('save failure reported', Not Broker.Execute(Run, 'save_file',
      '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '"}', Reply, Err));
    Check('failed save has no success result', (Reply = '') And (Pos('save failure', Err) > 0));
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalAction := 4;
    Check('user buffer change during approval rejects replacement',
      Not Broker.Execute(Run, 'write_file', Args, Reply, Err)
      And (Pos('user edit during approval', Editor.SourceText) = 1));
    Editor.Syn.Text := Original;
    Run := Broker.BeginRun(awsProject);
    Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalAction := 2;
    Check('project change during approval blocks edit',
      Not Broker.Execute(Run, 'write_file', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Workspace.ApprovalAction := 3;
    Run := Broker.BeginRun(awsProject);
    Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Check('cancellation during approval blocks edit',
      Not Broker.Execute(Run, 'write_file', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Run := Broker.BeginRun(awsProject); Workspace.ApprovalCalls := 0; Workspace.ApprovalAction := 0;
    Check('declined build does not launch compiler', Not Broker.Execute(Run, 'run_compile', '{}', Reply, Err) And (Workspace.Builds = 0));
    Workspace.ApprovalAction := 1;
    Check('approved build launches once', Broker.Execute(Run, 'run_compile', '{}', Reply, Err) And (Workspace.Builds = 1));
    Check('polling build status needs no new approval', Broker.Execute(Run, 'run_compile', '{}', Reply, Err) And (Workspace.ApprovalCalls = 2));
    Run := Broker.BeginRun(awsReadOnly); Broker.OnApproval := Nil;
    Check('automatic approval cannot enable builds in Inspect mode', Not Broker.Execute(Run, 'run_compile', '{}', Reply, Err) And (Workspace.Builds = 1));
    Run := Broker.BeginRun(awsMarkdown); Broker.OnApproval := @Workspace.Approve;
    Workspace.ApprovalAction := 0; Workspace.ApprovalCalls := 0;
    Check('Plan advertises Markdown edits and saves', (Pos('write_file', Broker.ToolsJson) > 0)
      And (Pos('save_file', Broker.ToolsJson) > 0) And (Pos('other document files', Broker.ToolsJson) > 0));
    Check('Plan does not advertise builds', Pos('"name":"run_compile"', Broker.ToolsJson) = 0);
    Broker.Execute(Run, 'read_file', '{"path":"Plan.MD"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"Plan.MD","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Check('Plan Markdown edit still needs approval', Not Broker.Execute(Run, 'write_file', Args, Reply, Err)
      And (Editor.SourceText = Original) And (Workspace.ApprovalCalls = 1));
    Workspace.ApprovalAction := 1;
    Check('Plan edits Markdown with exact revision', Broker.Execute(Run, 'write_file', Args, Reply, Err) And (Editor.SourceText = Changed));
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Check('Plan rejects replayed Markdown revision', Not Broker.Execute(Run, 'write_file', Args, Reply, Err));
    Workspace.SaveSucceeds := True;
    Check('Plan explicitly saves changed Markdown', Broker.Execute(Run, 'save_file',
      '{"path":"Plan.MD","revision":"' + JsonEscapeText(Revision) + '"}', Reply, Err) And (Workspace.SavedText = Changed));
    Editor.Syn.Undo; Check('Plan Markdown edit retains Undo', Editor.SourceText = Original);
    Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Broker.OnApproval := Nil;
    Check('Plan rejects source edit even with valid revision and automatic approval', Not Broker.Execute(Run, 'write_file', Args, Reply, Err) And (Editor.SourceText = Original));
    Check('Plan rejects source save even with valid revision', Not Broker.Execute(Run, 'save_file', Args, Reply, Err));
    Check('Plan rejects builds under automatic approval', Not Broker.Execute(Run, 'run_compile', '{}', Reply, Err) And (Workspace.Builds = 1));
    Check('Markdown extensions match native Plan tools', Workspace.IsMarkdownPath('plan.markdown') And Workspace.IsMarkdownPath('plan.mdown') And Not Workspace.IsMarkdownPath('plan.md.pas'));

    For I := 1 To 3 Do
      Begin
        Editor.Syn.Text := Original; Workspace.MutationAction := I;
        Run := Broker.BeginRun(awsProject);
        Broker.Execute(Run, 'read_file', '{"path":"unit.pas"}', Reply, Err);
        Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
        Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
        Check('mutation callback invalidation reports changed buffer ' + IntToStr(I),
          Not Broker.Execute(Run, 'write_file', Args, Reply, Err)
          And (Editor.SourceText = Changed) And (Reply = '') And (Pos('reread', Err) > 0));
        Editor.Syn.Undo;
        Check('failed commit report retains native Undo ' + IntToStr(I), Editor.SourceText = Original);
      End;
  Finally Broker.Free; Workspace.Free; End;
End;
Var
  FormBuffers: Array[0..1] Of TTestEditor;
  FailLfm: Boolean;

Function SaveTestForm(Const Path, Content: String; OpenAfter: Boolean;
  Out Note, ErrorText: String): Boolean;
Var I: Integer; Stream: TFileStream;
Begin
  I := Ord(ExtractFileExt(Path) = '.lfm');
  Result := ApplyAssistantEditorText(FormBuffers[I], FormBuffers[I].SourceText, Content, ErrorText);
  If Not Result Then Exit;
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If FailLfm And (I = 1) Then
      Begin
        Stream.WriteByte(0);
        ErrorText := 'Injected LFM save failure';
        Exit(False);
      End;
    Stream.WriteBuffer(Content[1], Length(Content));
    FormBuffers[I].Modified := False;
  Finally Stream.Free; End;
End;

Procedure TestFormPair(Host: TForm);
Var
  Paths, Disk, Buffers, Changed: Array[0..1] Of String;
  I: Integer; Err, Directory: String; Files: TStringList;

  Function Save: Boolean;
  Begin
    Result := SaveFormPair(Paths[0], Paths[1], Changed[0], Changed[1], True, True,
      [FormBuffers[0]], [FormBuffers[1]], @SaveTestForm, Err);
  End;

  Function ReadBytes(Const Path: String): String;
  Var Stream: TFileStream;
  Begin
    Stream := TFileStream.Create(Path, fmOpenRead);
    Try
      SetLength(Result, Stream.Size);
      If Result <> '' Then Stream.ReadBuffer(Result[1], Length(Result));
    Finally Stream.Free; End;
  End;

Begin
  Directory := GetEnvironmentVariable('LAZ_TEST_OUTPUT_DIR');
  If Directory = '' Then Directory := 'Temporary';
  ForceDirectories(Directory);
  Paths[0] := IncludeTrailingPathDelimiter(Directory) + 'RollbackForm.pas';
  Paths[1] := ChangeFileExt(Paths[0], '.lfm');
  Files := TStringList.Create;
  Try
    For I := 0 To 1 Do
      Begin
        Files.Text := 'disk ' + IntToStr(I);
        Files.SaveToFile(Paths[I]);
        Disk[I] := ReadBytes(Paths[I]);
        FormBuffers[I] := TTestEditor.Create;
        FormBuffers[I].Syn := TSynEdit.Create(Host);
        FormBuffers[I].Syn.Parent := Host;
        FormBuffers[I].Syn.Text := Disk[I];
        If I = 0 Then FormBuffers[I].Syn.Text := 'unsaved Pascal edit';
        FormBuffers[I].Modified := I = 0;
        Buffers[I] := FormBuffers[I].SourceText;
        Changed[I] := 'changed ' + Buffers[I];
      End;
    FailLfm := True;
    Check('second save fails', Not Save And (Pos('Injected LFM save failure', Err) = 1) And
      (Pos('Rollback restored', Err) > 0));
    For I := 0 To 1 Do
      Begin
        Check('restored disk ' + Paths[I], ReadBytes(Paths[I]) = Disk[I]);
        Check('restored editor ' + Paths[I], FormBuffers[I].SourceText = Buffers[I]);
        Check('restored modified flag ' + Paths[I], FormBuffers[I].Modified = (I = 0));
      End;
    FailLfm := False;
    Check('form save retry succeeds', Save);
    For I := 0 To 1 Do
      Check('retry persisted ' + Paths[I], (ReadBytes(Paths[I]) = Changed[I]) And
        (FormBuffers[I].SourceText = Changed[I]) And Not FormBuffers[I].Modified);
  Finally
    Files.Free;
    For I := 0 To 1 Do FormBuffers[I].Free;
  End;
End;

Var Ed: TTestEditor; Host: TForm; Before, UserText, Changed, Err: String;
Begin
  Application.Initialize;
  Host := TForm.CreateNew(Nil);
  Ed := TTestEditor.Create;
  Ed.Syn := TSynEdit.Create(Host);
  Try
    Ed.Syn.Parent := Host;
    Host.HandleNeeded;
    Ed.Syn.HandleNeeded;
    Ed.Syn.Text := 'unit Example;' + LineEnding + 'end.';
    Before := Ed.SourceText;
    Ed.ReplaceText(Point(6, 1), Point(13, 1), 'UserName');
    UserText := Ed.SourceText;
    Changed := StringReplace(UserText, 'UserName', 'AssistantName', []);
    Check('apply assistant edit', ApplyAssistantEditorText(Ed, UserText, Changed, Err));
    Check('text updated', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('Undo restores user edit', Ed.SourceText = UserText);
    Ed.Syn.Undo;
    Check('earlier user Undo survives', Ed.SourceText = Before);
    Check('stale snapshot rejected', Not ApplyAssistantEditorText(Ed, UserText, Changed, Err));
    Check('stale edit leaves source alone', Ed.SourceText = Before);
    Ed.Syn.ReadOnly := True;
    Check('read-only rejected', Not ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Ed.Syn.ReadOnly := False;
    Ed.Syn.Text := 'a' + #$C3#$A9 + 'z' + LineEnding + 'tail';
    Before := Ed.SourceText;
    Changed := StringReplace(Before, #$C3#$A9, #$C3#$AA, []);
    Check('UTF8 shared prefix edit', ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Check('UTF8 content preserved', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('UTF8 Undo', Ed.SourceText = Before);
    Ed.Syn.Text := '';
    Before := Ed.SourceText;
    Check('empty buffer insertion', ApplyAssistantEditorText(Ed, Before, 'hello', Err));
    Check('empty buffer content', TrimRight(Ed.SourceText) = 'hello');
    Check('no-op succeeds', ApplyAssistantEditorText(Ed, Ed.SourceText, Ed.SourceText, Err));
    Ed.Syn.Undo;
    Check('no-op adds no Undo entry', (TrimRight(Ed.SourceText) = TrimRight(Before)) And Not Ed.Syn.CanUndo);
    Ed.Syn.Text := 'a' + #13#10 + 'b';
    Before := Ed.SourceText;
    Changed := StringReplace(Before, 'b', 'new', []);
    Check('CRLF edit', ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Check('CRLF text', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('CRLF Undo', Ed.SourceText = Before);
    TestFormPair(Host);
    TestBroker(Ed);
  Finally
    Ed.Free;
    Host.Free;
  End;
End.
