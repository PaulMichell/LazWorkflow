Unit AssistantSaveBeforeTurn;

{ Unsaved work a turn could edit, and saving it before the turn starts. Build may change any project file, so open
  editors, the project, open packages and Markdown windows all count. Plan and Document write only Markdown, so only
  Markdown windows count. Chat and Inspect edit nothing. Call on the IDE thread. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantConversation;

Type
  { Where the unsaved work is. The IDE comes first, since it is what a Build turn edits. }
  TAssistantUnsavedWork = (auwNone, auwIDE, auwMarkdown);

Const
  AssistantSaveBeforeTurnQuestion = 'Do you want to save all edits and continue?';
  { Sent to the phone when a prompt is refused for unsaved work, so it can ask the question itself. }
  AssistantUnsavedEditsReason = 'unsaved_edits';
  AssistantUnsavedEditsRefusal = 'The desktop has unsaved edits. Save them before this prompt runs.';

{ True for the modes whose turns edit files: Build, Plan and Document. }
Function AssistantModeSavesFirst(Mode: TAssistantMode): Boolean;
{ The unsaved work a turn in Mode could edit. auwNone when the mode edits nothing. }
Function AssistantUnsavedWork(Mode: TAssistantMode): TAssistantUnsavedWork;
{ Saves what AssistantUnsavedWork found: the IDE's Save All (editors, project, packages) in Build, and the Markdown
  windows in every editing mode. False, with the reason, when anything is still unsaved afterwards. }
Function SaveAssistantUnsavedWork(Mode: TAssistantMode; Out ErrorText: String): Boolean;
{ Brings the unsaved work forward and gives it the keyboard: the source editor, or the Markdown window. }
Procedure ShowAssistantUnsavedWork(Work: TAssistantUnsavedWork);

Implementation

Uses
  Forms, Controls, LazIDEIntf, ProjectIntf, PackageIntf, SrcEditorIntf, AssistantMarkdownForm;

Function AssistantModeSavesFirst(Mode: TAssistantMode): Boolean;
Begin
  Result := Mode In [amBuild, amPlan, amDocument];
End;

Function IDEHasUnsavedWork: Boolean;
Var
  I: Integer;
  Editor: TSourceEditorInterface;
  Package: TIDEPackage;
Begin
  Result := True;
  If Assigned(SourceEditorManagerIntf) Then
    For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
      Begin
        Editor := SourceEditorManagerIntf.SourceEditors[I];
        If Assigned(Editor) And (Editor.Modified Or Editor.ModifiedDesign) Then Exit;
      End;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) And LazarusIDE.ActiveProject.Modified Then Exit;
  If Assigned(PackageEditingInterface) Then
    For I := 0 To PackageEditingInterface.GetPackageCount - 1 Do
      Begin
        Package := PackageEditingInterface.GetPackages(I);
        If Assigned(Package) And Package.Modified And (Not Package.ReadOnly) Then Exit;
      End;
  Result := False;
End;

Function PackagesHaveUnsavedWork: Boolean;
Var
  I: Integer;
  Package: TIDEPackage;
Begin
  Result := False;
  If Not Assigned(PackageEditingInterface) Then Exit;
  For I := 0 To PackageEditingInterface.GetPackageCount - 1 Do
    Begin
      Package := PackageEditingInterface.GetPackages(I);
      If Assigned(Package) And Package.Modified And (Not Package.ReadOnly) Then Exit(True);
    End;
End;

Function AssistantUnsavedWork(Mode: TAssistantMode): TAssistantUnsavedWork;
Begin
  Result := auwNone;
  If Not AssistantModeSavesFirst(Mode) Then Exit;
  If (Mode = amBuild) And IDEHasUnsavedWork Then Exit(auwIDE);
  If Assigned(FirstUnsavedMarkdownDocument) Then Result := auwMarkdown;
End;

Function SaveAssistantUnsavedWork(Mode: TAssistantMode; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not AssistantModeSavesFirst(Mode) Then Exit(True);
  If (Mode = amBuild) And IDEHasUnsavedWork Then
    Begin
      If Not Assigned(LazarusIDE) Then
        Begin
          ErrorText := 'The Lazarus IDE is not available to save.';
          Exit;
        End;
      { The IDE's own Save All: every editor, the project and its session. A new unit asks for its name here. }
      If LazarusIDE.DoSaveAll([sfCheckAmbiguousFiles]) <> mrOk Then
        Begin
          ErrorText := 'Save All did not complete.';
          Exit;
        End;
      If PackagesHaveUnsavedWork And Assigned(PackageEditingInterface) And
        (PackageEditingInterface.DoSaveAllPackages([]) <> mrOk) Then
        Begin
          ErrorText := 'An open package could not be saved.';
          Exit;
        End;
      If IDEHasUnsavedWork Then
        Begin
          ErrorText := 'Some files in the IDE still have unsaved changes.';
          Exit;
        End;
    End;
  Result := SaveUnsavedMarkdownDocuments(ErrorText);
End;

Procedure ShowAssistantUnsavedWork(Work: TAssistantUnsavedWork);
Var
  Form: TAssistantMarkdownForm;
Begin
  Case Work Of
    auwIDE:
      If Assigned(SourceEditorManagerIntf) Then
        SourceEditorManagerIntf.ShowActiveWindowOnTop(True);
    auwMarkdown:
      Begin
        Form := FirstUnsavedMarkdownDocument;
        If Assigned(Form) Then
          Begin
            Form.ShowOnTop;
            If Form.SourceMemo.CanFocus Then Form.SourceMemo.SetFocus;
          End;
      End;
  Else
  End;
End;

End.
