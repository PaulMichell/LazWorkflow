Program AssistantEditorEditsTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, SysUtils, Types,
  SynEdit, SrcEditorIntf, AssistantEditorEdits, AssistantToolBroker, AssistantProtocol, fpjson, jsonparser;
Type
  { Exercise the real IDE interface's ReplaceText with a real SynEdit Undo stack.
    Only the editor methods used by that operation are implemented. }
  TTestEditor = Class(TSourceEditorInterface)
  Protected
    Function GetSourceText: String; Override;
    Function GetReadOnly: Boolean; Override;
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
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Override;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Override;
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
Function TBrokerWorkspace.StartBuild(Out ResultText, ErrorText: String): Boolean;
Begin Inc(Builds); ResultText := '{"started":true}'; ErrorText := ''; Result := True; End;
Function TBrokerWorkspace.BuildStatus(Out ResultText, ErrorText: String): Boolean;
Begin ResultText := '{"done":true}'; ErrorText := ''; Result := True; End;
Function TBrokerWorkspace.Describe: String;
Begin Result := 'Test project'; End;
Function TTestEditor.GetSourceText: String;
Begin Result := Syn.Text; End;
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
    Check('broker reads unsaved IDE text', Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err));
    Data := GetJSON(Reply);
    Try
      Revision := TJSONObject(Data).Get('revision', '');
      Check('broker returns exact unsaved text', TJSONObject(Data).Get('text', '') = Original);
    Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalBroker := Broker; Broker.OnApproval := @Workspace.Approve;
    Check('declined edit has no side effect', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err)
      And (Editor.SourceText = Original) And (Pos('declined', Err) > 0));
    Check('declined save never reaches adapter', Not Broker.Execute(Run, 'lazarus_save_buffer', Args, Reply, Err)
      And (Pos('declined', Err) > 0));
    Workspace.ApprovalAction := 1;
    Check('broker applies revision-checked edit', Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    Check('broker updated live editor', Editor.SourceText = Changed);
    Check('replayed revision rejected', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    Editor.Syn.Undo;
    Check('broker edit is one Undo operation', Editor.SourceText = Original);
    Check('Undo invalidates model revision', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    OldRun := Run; Run := Broker.BeginRun(awsReadOnly);
    Check('old run rejected', Not Broker.Execute(OldRun, 'lazarus_project_info', '{}', Reply, Err));
    Check('Ask mode advertises no mutation tool', Pos('lazarus_replace_buffer', Broker.ToolsJson) = 0);
    Check('Ask mode rejects mutation', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    Check('Ask mode rejects edits without requesting approval', Workspace.ApprovalCalls = 3);
    Workspace.ProjectId := 'project-2';
    Check('project switch rejects tools', Not Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err));
    Run := Broker.BeginRun(awsProject); Broker.Cancel;
    Check('cancelled run rejects tools', Not Broker.Execute(Run, 'lazarus_project_info', '{}', Reply, Err));
    Run := Broker.BeginRun(awsProject);
    Check('unknown tool has no fallback', Not Broker.Execute(Run, 'write_file', '{}', Reply, Err));
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply);
    Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Check('save failure reported', Not Broker.Execute(Run, 'lazarus_save_buffer',
      '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '"}', Reply, Err));
    Check('failed save has no success result', (Reply = '') And (Pos('save failure', Err) > 0));
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalAction := 4;
    Check('user buffer change during approval rejects replacement',
      Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err)
      And (Pos('user edit during approval', Editor.SourceText) = 1));
    Editor.Syn.Text := Original;
    Run := Broker.BeginRun(awsProject);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalAction := 2;
    Check('project change during approval blocks edit',
      Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Workspace.ApprovalAction := 3;
    Run := Broker.BeginRun(awsProject);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Check('cancellation during approval blocks edit',
      Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Run := Broker.BeginRun(awsProject); Workspace.ApprovalCalls := 0; Workspace.ApprovalAction := 0;
    Check('declined build does not launch compiler', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 0));
    Workspace.ApprovalAction := 1;
    Check('approved build launches once', Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 1));
    Check('polling build status needs no new approval', Broker.Execute(Run, 'lazarus_build_status', '{}', Reply, Err) And (Workspace.ApprovalCalls = 2));
    Run := Broker.BeginRun(awsReadOnly); Broker.OnApproval := Nil;
    Check('automatic approval cannot enable builds in Ask mode', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 1));
    Run := Broker.BeginRun(awsMarkdown); Broker.OnApproval := @Workspace.Approve;
    Workspace.ApprovalAction := 0; Workspace.ApprovalCalls := 0;
    Check('Plan advertises Markdown edits and saves', (Pos('lazarus_replace_buffer', Broker.ToolsJson) > 0)
      And (Pos('lazarus_save_buffer', Broker.ToolsJson) > 0) And (Pos('Plan mode: only .md', Broker.ToolsJson) > 0));
    Check('Plan does not advertise builds', Pos('lazarus_start_build', Broker.ToolsJson) = 0);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"Plan.MD"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"Plan.MD","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Check('Plan Markdown edit still needs approval', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err)
      And (Editor.SourceText = Original) And (Workspace.ApprovalCalls = 1));
    Workspace.ApprovalAction := 1;
    Check('Plan edits Markdown with exact revision', Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Changed));
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Check('Plan rejects replayed Markdown revision', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    Workspace.SaveSucceeds := True;
    Check('Plan explicitly saves changed Markdown', Broker.Execute(Run, 'lazarus_save_buffer',
      '{"path":"Plan.MD","revision":"' + JsonEscapeText(Revision) + '"}', Reply, Err) And (Workspace.SavedText = Changed));
    Editor.Syn.Undo; Check('Plan Markdown edit retains Undo', Editor.SourceText = Original);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Broker.OnApproval := Nil;
    Check('Plan rejects source edit even with valid revision and automatic approval', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Original));
    Check('Plan rejects source save even with valid revision', Not Broker.Execute(Run, 'lazarus_save_buffer', Args, Reply, Err));
    Check('Plan rejects builds under automatic approval', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 1));
    Check('Markdown extensions match native Plan tools', Workspace.IsMarkdownPath('plan.markdown') And Workspace.IsMarkdownPath('plan.mdown') And Not Workspace.IsMarkdownPath('plan.md.pas'));

    For I := 1 To 3 Do
      Begin
        Editor.Syn.Text := Original; Workspace.MutationAction := I;
        Run := Broker.BeginRun(awsProject);
        Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
        Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
        Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
        Check('mutation callback invalidation reports changed buffer ' + IntToStr(I),
          Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err)
          And (Editor.SourceText = Changed) And (Reply = '') And (Pos('reread', Err) > 0));
        Editor.Syn.Undo;
        Check('failed commit report retains native Undo ' + IntToStr(I), Editor.SourceText = Original);
      End;
  Finally Broker.Free; Workspace.Free; End;
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
    TestBroker(Ed);
  Finally
    Ed.Free;
    Host.Free;
  End;
End.
