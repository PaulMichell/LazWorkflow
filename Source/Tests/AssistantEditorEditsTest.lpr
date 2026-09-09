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
    ApprovalAction, ApprovalCalls, Builds: Integer;
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
Begin Result := ApplyAssistantEditorText(Editor, ExpectedText, NewText, ErrorText); End;
Function TBrokerWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin ErrorText := 'Injected save failure'; Result := False; End;
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
  Run, OldRun, Reply, Err, Revision, Original, Changed, Args: String; Data: TJSONData;
Begin
  Workspace := TBrokerWorkspace.Create;
  Workspace.Editor := Editor; Workspace.ProjectId := 'project-1';
  Broker := TAssistantToolBroker.Create(Workspace);
  Try
    Original := Editor.SourceText;
    Changed := StringReplace(Original, 'b', 'broker edit', []);
    Run := Broker.BeginRun(True);
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
    OldRun := Run; Run := Broker.BeginRun(False);
    Check('old run rejected', Not Broker.Execute(OldRun, 'lazarus_project_info', '{}', Reply, Err));
    Check('Ask mode advertises no mutation tool', Pos('lazarus_replace_buffer', Broker.ToolsJson) = 0);
    Check('Ask mode rejects mutation', Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err));
    Check('Ask mode rejects edits without requesting approval', Workspace.ApprovalCalls = 3);
    Workspace.ProjectId := 'project-2';
    Check('project switch rejects tools', Not Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err));
    Run := Broker.BeginRun(True); Broker.Cancel;
    Check('cancelled run rejects tools', Not Broker.Execute(Run, 'lazarus_project_info', '{}', Reply, Err));
    Run := Broker.BeginRun(True);
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
    Run := Broker.BeginRun(True);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Workspace.ApprovalAction := 2;
    Check('project change during approval blocks edit',
      Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Workspace.ApprovalAction := 3;
    Run := Broker.BeginRun(True);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"unit.pas"}', Reply, Err);
    Data := GetJSON(Reply); Try Revision := TJSONObject(Data).Get('revision', ''); Finally Data.Free; End;
    Args := '{"path":"unit.pas","revision":"' + JsonEscapeText(Revision) + '","text":"' + JsonEscapeText(Changed) + '"}';
    Check('cancellation during approval blocks edit',
      Not Broker.Execute(Run, 'lazarus_replace_buffer', Args, Reply, Err) And (Editor.SourceText = Original)
      And (Pos('during approval', Err) > 0));
    Run := Broker.BeginRun(True); Workspace.ApprovalCalls := 0; Workspace.ApprovalAction := 0;
    Check('declined build does not launch compiler', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 0));
    Workspace.ApprovalAction := 1;
    Check('approved build launches once', Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 1));
    Check('polling build status needs no new approval', Broker.Execute(Run, 'lazarus_build_status', '{}', Reply, Err) And (Workspace.ApprovalCalls = 2));
    Run := Broker.BeginRun(False); Broker.OnApproval := Nil;
    Check('automatic approval cannot enable builds in Ask mode', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) And (Workspace.Builds = 1));
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
