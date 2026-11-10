Program AssistantChangeSetsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Types, SynEdit,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, AssistantTestIDEHost,
  AssistantIDEWorkspace, AssistantToolBroker, AssistantProtocol, fpjson, jsonparser;
Type
  TEditor = Class(TSourceEditorInterface)
  Public
    Path: String; Syn: TSynEdit;
    Function GetSourceText: String; Override;
    Function GetEditorControl: TWinControl; Override;
    Function GetReadOnly: Boolean; Override;
    Procedure SetCursorTextXY(Const Value: TPoint); Override;
    Procedure SetSelection(Const Value: String); Override;
    Procedure SelectText(Const StartPos, EndPos: TPoint); Override;
    Procedure BeginUndoBlock; Override;
    Procedure EndUndoBlock; Override;
    Procedure BeginUpdate; Override;
    Procedure EndUpdate; Override;
  End;
  TManager = Class(TSourceEditorManagerInterface)
  Public
    Editors: Array[0..1] Of TEditor;
    Function SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface; Override;
  End;
  TProject = Class(TLazProject)
  Public
    Path: String;
    Function GetProjectInfoFile: String; Override;
    Function GetMainFile: TLazProjectFile; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Project: TProject;
    Function GetActiveProject: TLazProject; Override;
  End;
  TWorkspace = Class(TAssistantIDEWorkspace)
  Public
    Manager: TManager; Project: TProject; Broker: TAssistantToolBroker;
    Failure, ApprovalAction, Calls, Approvals, Saves: Integer;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    { The fake IDE cannot save; this counts each save an edit asks for, and writes nothing. }
    Function SaveEditor(Editor: TObject; Out ErrorText: String): Boolean; Override;
    Function Approve(Const Tool, Path, OldText, NewText: String): Boolean;
  End;
Function TEditor.GetSourceText: String;
Begin Result := Syn.Text; End;
Function TEditor.GetEditorControl: TWinControl;
Begin Result := Syn; End;
Function TEditor.GetReadOnly: Boolean;
Begin Result := Syn.ReadOnly; End;
Procedure TEditor.SetCursorTextXY(Const Value: TPoint);
Begin Syn.LogicalCaretXY := Value; End;
Procedure TEditor.SetSelection(Const Value: String);
Begin Syn.SelText := Value; End;
Procedure TEditor.SelectText(Const StartPos, EndPos: TPoint);
Begin Syn.BlockBegin := StartPos; Syn.BlockEnd := EndPos; End;
Procedure TEditor.BeginUndoBlock;
Begin Syn.BeginUndoBlock; End;
Procedure TEditor.EndUndoBlock;
Begin Syn.EndUndoBlock; End;
Procedure TEditor.BeginUpdate;
Begin Syn.BeginUpdate; End;
Procedure TEditor.EndUpdate;
Begin Syn.EndUpdate; End;
Function TManager.SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface;
Var I: Integer;
Begin Result := Nil; For I := 0 To 1 Do If Editors[I].Path = Filename Then Exit(Editors[I]); End;
Function TProject.GetProjectInfoFile: String;
Begin Result := Path; End;
Function TProject.GetMainFile: TLazProjectFile;
Begin Result := Nil; End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Project; End;
Function TWorkspace.Approve(Const Tool, Path, OldText, NewText: String): Boolean;
Begin
  Inc(Approvals); Result := ApprovalAction <> 1;
  If (Pos(Manager.Editors[0].Path, OldText) = 0) Or (Pos(Manager.Editors[1].Path, NewText) = 0) Then
    Raise Exception.Create('Approval must contain both files');
  Case ApprovalAction Of
    2: Manager.Editors[1].Syn.Text := 'user edit' + LineEnding;
    3: Broker.Cancel;
    4: Project.Path := Project.Path + '.changed';
  End;
End;
Function TWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  Inc(Calls);
  If (Calls = 3) And (Failure = 7) Then Raise Exception.Create('Injected recovery failure');
  If (Calls = 2) And (Failure In [1, 7]) Then Begin ErrorText := 'Injected pre-write failure'; Exit(False); End;
  If (Calls = 2) And (Failure = 3) Then
    Begin Manager.Editors[0].Syn.Text := 'later user edit' + LineEnding; ErrorText := 'Injected conflict'; Exit(False); End;
  If (Calls = 2) And (Failure = 4) Then Begin Broker.Cancel; ErrorText := 'Cancelled'; Exit(False); End;
  If (Calls = 2) And (Failure = 5) Then Begin Project.Path := Project.Path + '.changed'; ErrorText := 'Switched'; Exit(False); End;
  Result := Inherited ReplaceBuffer(Path, ExpectedText, NewText, ErrorText);
  If (Calls = 1) And (Failure = 6) Then Manager.Editors[1].Syn.Text := 'edit during apply' + LineEnding;
  If (Calls = 2) And (Failure = 2) Then Raise Exception.Create('Injected failure after mutation');
End;
Function TWorkspace.SaveEditor(Editor: TObject; Out ErrorText: String): Boolean;
Begin ErrorText := ''; Inc(Saves); Result := True; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Function Field(Const Text, Name: String): String;
Var Data: TJSONData;
Begin Data := GetJSON(Text); Try Result := Data.FindPath(Name).AsString; Finally Data.Free; End; End;
Var Root, Run, Reply, Err, IDArgs, Args, RevA, RevB, OriginalA, OriginalB, NewA, NewB: String;
  Manager: TManager; IDE: TIDE; Project: TProject; Workspace: TWorkspace; Broker: TAssistantToolBroker;
  Guid: TGuid; I, Mode: Integer; FileText: TStringList;
Procedure Reset(WriteScope: TAssistantWriteScope = awsProject);
Begin
  Project.Path := Root + '/project.lpi'; Workspace.Calls := 0; Workspace.Failure := 0; Workspace.ApprovalAction := 0;
  Manager.Editors[0].Syn.ReadOnly := False; Manager.Editors[1].Syn.ReadOnly := False;
  Manager.Editors[0].Syn.Text := OriginalA; Manager.Editors[1].Syn.Text := OriginalB;
  Run := Broker.BeginRun(WriteScope);
  Check('read first editor', Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"a.pas"}', Reply, Err)); RevA := Field(Reply, 'revision');
  Check('read second editor', Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"b.pas"}', Reply, Err)); RevB := Field(Reply, 'revision');
  Args := '{"changes":[{"path":"a.pas","revision":"' + JsonEscapeText(RevA) + '","text":"' + JsonEscapeText(NewA) + '"},' +
    '{"path":"b.pas","revision":"' + JsonEscapeText(RevB) + '","text":"' + JsonEscapeText(NewB) + '"}]}';
End;
Procedure Prepare;
Begin
  If Not Broker.Execute(Run, 'lazarus_prepare_changes', Args, Reply, Err) Then Begin WriteLn(Err); Check('prepare set', False); End;
  IDArgs := '{"change_set_id":"' + JsonEscapeText(Field(Reply, 'change_set_id')) + '"}';
End;
Begin
  Application.Initialize;
  CreateGUID(Guid); Root := GetTempDir + 'laz-change-sets-' + GUIDToString(Guid); ForceDirectories(Root);
  OriginalA := 'unit A;' + LineEnding + 'end.' + LineEnding;
  OriginalB := 'unit B;' + LineEnding + 'end.' + LineEnding;
  NewA := 'unit A; // é' + LineEnding + 'end.' + LineEnding;
  NewB := 'unit B; // changed' + LineEnding + 'end.' + LineEnding;
  Manager := TManager.Create(Nil); Project := TProject.Create(Nil); IDE := TIDE.Create(Nil);
  FileText := TStringList.Create;
  For I := 0 To 1 Do
    Begin
      Manager.Editors[I] := TEditor.Create; Manager.Editors[I].Syn := TSynEdit.Create(Nil);
      If I = 0 Then Manager.Editors[I].Path := Root + '/a.pas' Else Manager.Editors[I].Path := Root + '/b.pas';
      FileText.Text := 'disk unchanged'; FileText.SaveToFile(Manager.Editors[I].Path);
    End;
  Project.Path := Root + '/project.lpi'; FileText.SaveToFile(Project.Path); IDE.Project := Project;
  LazarusIDE := IDE; SourceEditorManagerIntf := Manager;
  Workspace := TWorkspace.Create; Workspace.Manager := Manager; Workspace.Project := Project;
  Broker := TAssistantToolBroker.Create(Workspace); Workspace.Broker := Broker; Broker.OnApproval := @Workspace.Approve;
  Try
    Reset; Prepare;
    Check('preparation changes no editor', (Workspace.Calls = 0) And (Manager.Editors[0].Syn.Text = OriginalA));
    Workspace.Saves := 0;
    Check('apply both buffers', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err)
      And (Field(Reply, 'state') = 'applied') And (Manager.Editors[0].Syn.Text = NewA) And (Manager.Editors[1].Syn.Text = NewB));
    Check('apply saves each changed editor', Workspace.Saves = 2);
    Check('apply receipt cannot replay', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Check('apply invalidates old save revision', Not Broker.Execute(Run, 'lazarus_save_buffer',
      '{"path":"a.pas","revision":"' + JsonEscapeText(RevA) + '"}', Reply, Err));
    Check('revert both confirmed edits', Broker.Execute(Run, 'lazarus_revert_changes', IDArgs, Reply, Err)
      And (Manager.Editors[0].Syn.Text = OriginalA) And (Manager.Editors[1].Syn.Text = OriginalB));
    Check('empty save revision rejected after restoration', Not Broker.Execute(Run, 'lazarus_save_buffer',
      '{"path":"a.pas","revision":""}', Reply, Err) And (Pos('Stale buffer revision', Err) > 0));
    Manager.Editors[0].Syn.Undo;
    Check('recovery itself preserves native Undo', Manager.Editors[0].Syn.Text = NewA);
    Reset; Prepare;
    Check('apply for native Undo test', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Manager.Editors[0].Syn.Undo; Manager.Editors[1].Syn.Undo;
    Check('native Undo restores each complete editor change', (Manager.Editors[0].Syn.Text = OriginalA) And (Manager.Editors[1].Syn.Text = OriginalB));
    For Mode := 0 To 1 Do
      Begin
        If Mode = 0 Then Reset(awsReadOnly) Else Reset(awsMarkdown);
        Prepare;
        Check('preview cannot enable writes outside Build', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err) And (Workspace.Calls = 0));
      End;
    Reset; Prepare; Manager.Editors[1].Syn.ReadOnly := True;
    Check('all editor preconditions checked before first mutation', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err) And (Workspace.Calls = 0));
    For Mode := 1 To 4 Do
      Begin
        Reset; Prepare; Workspace.ApprovalAction := Mode;
        Check('approval denial/change/cancel/project switch prevents all writes ' + IntToStr(Mode),
          Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err) And (Workspace.Calls = 0));
      End;
    For Mode := 1 To 5 Do
      Begin
        Reset; Prepare; Workspace.Failure := Mode;
        Check('injected partial failure reported ' + IntToStr(Mode), Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
        If Mode = 1 Then Check('pre-write failure restores earlier confirmed edit',
          (Field(Reply, 'state') = 'rolled_back') And (Manager.Editors[0].Syn.Text = OriginalA) And (Manager.Editors[1].Syn.Text = OriginalB));
        If Mode = 2 Then Check('uncertain mutation is not automatically overwritten',
          (Field(Reply, 'state') = 'partial') And (Field(Reply, 'files[1].state') = 'unknown')
          And (Manager.Editors[0].Syn.Text = OriginalA) And (Manager.Editors[1].Syn.Text = NewB));
        If Mode = 3 Then Check('later user edit survives recovery', (Field(Reply, 'state') = 'partial')
          And (Manager.Editors[0].Syn.Text = 'later user edit' + LineEnding));
        If Mode >= 4 Then
          Begin
            Check('interrupted run does not continue rollback', (Workspace.Calls = 2) And (Manager.Editors[0].Syn.Text = NewA));
            Project.Path := Root + '/project.lpi'; Run := Broker.BeginRun(awsProject); Workspace.Failure := 0;
            Check('receipt survives a new run', Broker.Execute(Run, 'lazarus_change_status', IDArgs, Reply, Err));
            Broker.Execute(Run, 'lazarus_revert_changes', IDArgs, Reply, Err);
            Check('new run can restore earlier confirmed edit', Manager.Editors[0].Syn.Text = OriginalA);
          End;
      End;
    Reset; Prepare; Check('apply for stamp test', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Manager.Editors[0].Syn.Text := OriginalA; Manager.Editors[0].Syn.Text := NewA;
    Check('same bytes with changed stamp are not owned for recovery', Not Broker.Execute(Run, 'lazarus_revert_changes', IDArgs, Reply, Err)
      And (Field(Reply, 'files[0].state') = 'conflict') And (Manager.Editors[0].Syn.Text = NewA) And (Manager.Editors[1].Syn.Text = OriginalB));
    Reset; Prepare; Manager.Editors[0].Syn.Text := NewA; Manager.Editors[0].Syn.Text := OriginalA;
    Check('same bytes with changed stamp invalidate preparation', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err) And (Workspace.Calls = 0));
    Reset; Prepare; Workspace.Failure := 6;
    Check('later buffer change stops next write and restores first', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err)
      And (Workspace.Calls = 2) And (Manager.Editors[0].Syn.Text = OriginalA) And (Manager.Editors[1].Syn.Text = 'edit during apply' + LineEnding));
    Reset; Prepare; Workspace.Failure := 7;
    Check('recovery exception retains uncertain outcome', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err)
      And (Field(Reply, 'state') = 'partial') And (Field(Reply, 'files[0].state') = 'unknown') And (Manager.Editors[0].Syn.Text = NewA));
    Reset; Prepare; Check('apply for project isolation test', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Project.Path := Project.Path + '.changed'; Run := Broker.BeginRun(awsProject);
    Check('receipt hidden from another project', Not Broker.Execute(Run, 'lazarus_change_status', IDArgs, Reply, Err));
    Reset; Prepare; Check('apply for missing revision test', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Args := '{"changes":[{"path":"a.pas","revision":"","text":"x"}]}';
    Check('invalidated empty revision cannot prepare edits', Not Broker.Execute(Run, 'lazarus_prepare_changes', Args, Reply, Err));
    Reset; Args := StringReplace(Args, JsonEscapeText(NewA), JsonEscapeText(OriginalA), []); Prepare;
    Check('no-op buffer is not claimed for recovery', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err)
      And (Workspace.Calls = 1) And (Field(Reply, 'files[0].state') = 'unchanged') And (Field(Reply, 'files[0].hasRecoverySnapshot') = 'false'));
    Reset; Prepare; Check('apply for editor lifetime test', Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Manager.Editors[0].Syn.Free; Manager.Editors[0].Syn := TSynEdit.Create(Nil); Manager.Editors[0].Syn.Text := NewA;
    Check('reopened editor is not owned by earlier receipt', Not Broker.Execute(Run, 'lazarus_revert_changes', IDArgs, Reply, Err)
      And (Field(Reply, 'files[0].state') = 'conflict') And (Manager.Editors[0].Syn.Text = NewA));
    Reset; Prepare; Run := Broker.BeginRun(awsProject);
    Check('unapplied preview expires across runs', Not Broker.Execute(Run, 'lazarus_apply_changes', IDArgs, Reply, Err));
    Reset; Args := StringReplace(Args, 'b.pas', './a.pas', []);
    Check('duplicate canonical editor rejected', Not Broker.Execute(Run, 'lazarus_prepare_changes', Args, Reply, Err));
    Reset; Manager.Editors[1].Syn.Text := 'changed';
    Check('stale preparation revision rejected', Not Broker.Execute(Run, 'lazarus_prepare_changes', Args, Reply, Err));
    For I := 0 To 1 Do
      Begin FileText.LoadFromFile(Manager.Editors[I].Path); Check('disk source untouched', Trim(FileText.Text) = 'disk unchanged'); End;
  Finally
    Broker.Free; Workspace.Free; LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    IDE.Free; Project.Free;
    For I := 0 To 1 Do Begin DeleteFile(Manager.Editors[I].Path); Manager.Editors[I].Syn.Free; Manager.Editors[I].Free; End;
    Manager.Free; FileText.Free; DeleteFile(Root + '/project.lpi'); RemoveDir(Root);
  End;
End.
