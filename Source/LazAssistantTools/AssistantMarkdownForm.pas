Unit AssistantMarkdownForm;

{ Live Markdown document loader/viewer windows for LazAssistantTools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, ActnList, StatusFooterFrame, StyledControls, StyledMarkdown;

Type
  TMarkdownViewMode = (mvmPreview, mvmSource);

  TAssistantMarkdownForm = Class(TForm)
    ActionList: TActionList;
    OpenAction: TAction;
    SaveAction: TAction;
    PreviewModeAction: TAction;
    SourceModeAction: TAction;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    ToolBar: TToolBar;
    ToolButtonOpen: TToolButton;
    ToolButtonSave: TToolButton;
    ToolButtonSep1: TToolButton;
    ToolButtonPreview: TToolButton;
    ToolButtonSource: TToolButton;
    StatusFooter: TStatusFooterFrame;
    ContentPanel: TPanel;
    SourceMemo: TMemo;
    PreviewHost: TPanel;
    WatchTimer: TTimer;
    DebounceTimer: TTimer;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormClose(Sender: TObject; Var CloseAction: TCloseAction);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure OpenActionExecute(Sender: TObject);
    Procedure SaveActionExecute(Sender: TObject);
    Procedure PreviewModeActionExecute(Sender: TObject);
    Procedure SourceModeActionExecute(Sender: TObject);
    Procedure SourceMemoChange(Sender: TObject);
    Procedure WatchTimerTimer(Sender: TObject);
    Procedure DebounceTimerTimer(Sender: TObject);
  Private
    FFileName: String;
    FDirty: Boolean;
    FLoading: Boolean;
    FViewMode: TMarkdownViewMode;
    FDiskAge: LongInt;
    FPendingDiskReload: Boolean;
    FSnippet: Boolean;
    FSnippetKey: String;
    FSnippetTitle: String;
    FNewDocument: Boolean;
    PreviewControl: TStyledMemo;
    PreviewLoader: TStyledMarkdown;
    Function DocumentTitle: String;
    Function PromptSaveAs(Out Target: String): Boolean;
    Procedure EnsurePreview;
    Procedure ApplyViewMode;
    Procedure UpdateCaption;
    Procedure UpdateStatus;
    Procedure RefreshActionState;
    Procedure SetDirty(IsDirty: Boolean);
    Function ConfirmDiscardEdits: Boolean;
    Function DiskCopyIsNewer: Boolean;
    Function ConfirmNewerDiskCopy: TModalResult;
    Function LoadFromDisk: Boolean;
    Function SaveToDisk: Boolean;
    Procedure ApplyPreviewText(Const Body: String);
    Procedure NotifyDocumentChanged;
    Procedure NotifyDocumentSaved;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Function OpenFile(Const FileName: String): Boolean;
    Function PromptOpen: Boolean;
    { Read-only preview of one section. Not a project file, so Save and reload stay off. }
    Procedure LoadSnippet(Const Key, Title, Body: String);
    { Empty, untitled document in Source view. The first Save asks where to write it. }
    Procedure StartNewDocument;
    { Re-read from disk (e.g. after LLM write_markdown). Skips if dirty unless Force. }
    Function ReloadFromDisk(Force: Boolean = False): Boolean;
    Property FileName: String Read FFileName;
    Property SnippetKey: String Read FSnippetKey;
    Property Dirty: Boolean Read FDirty;
    Property IsNewDocument: Boolean Read FNewDocument;
    Property ViewMode: TMarkdownViewMode Read FViewMode;
  End;

Const
  NewMarkdownDocumentTitle = '<New Markdown>';

{ Opens an existing viewer for FileName, or creates one. Empty FileName shows the open dialog.
  When the viewer is already open, reloads content from disk. }
Function OpenMarkdownDocument(Const FileName: String = ''): TAssistantMarkdownForm;
{ Always opens a new window holding an untitled, unsaved document. }
Function OpenNewMarkdownDocument: TAssistantMarkdownForm;
{ Where Save puts a new document first: the project's Documents folder, or the project root without one. }
Function NewMarkdownDocumentFolder: String;
Function FindMarkdownDocument(Const FileName: String): TAssistantMarkdownForm;
{ Same preview as a plan file, limited to one section. Reuses the window for Key. }
Function OpenMarkdownSnippet(Const Key, Title, Body: String): TAssistantMarkdownForm;
{ Force-reload any open viewer for this path (no-op if none open). }
Function ReloadMarkdownDocument(Const FileName: String; Force: Boolean = True;
  BringForward: Boolean = True): Boolean;

Implementation

{$R *.lfm}

Uses
  LazFileUtils, WorkflowLog, WorkflowEvents, LazIDEIntf, ProjectIntf, AssistantProjectPaths, AssistantPlan;

Const
  PreviewContentMargin = 4;

Var
  MarkdownForms: TList;

Function SameFilePath(Const PathA, PathB: String): Boolean;
Begin
  Result := SameFileName(ExpandFileName(PathA), ExpandFileName(PathB));
End;

Function FindMarkdownDocument(Const FileName: String): TAssistantMarkdownForm;
Var
  I: Integer;
  Form: TAssistantMarkdownForm;
Begin
  Result := Nil;
  If (FileName = '') Or (Not Assigned(MarkdownForms)) Then
    Exit;
  For I := 0 To MarkdownForms.Count - 1 Do
    Begin
      Form := TAssistantMarkdownForm(MarkdownForms[I]);
      If Assigned(Form) And SameFilePath(Form.FileName, FileName) Then
        Begin
          Result := Form;
          Exit;
        End;
    End;
End;

Function ReloadMarkdownDocument(Const FileName: String; Force: Boolean; BringForward: Boolean): Boolean;
Var
  Form: TAssistantMarkdownForm;
Begin
  Result := False;
  Form := FindMarkdownDocument(FileName);
  If Not Assigned(Form) Then
    Exit;
  Result := Form.ReloadFromDisk(Force);
  If Result And BringForward Then
    Begin
      Form.Show;
      Form.BringToFront;
    End;
End;

Function FindMarkdownSnippet(Const Key: String): TAssistantMarkdownForm;
Var
  I: Integer;
  Form: TAssistantMarkdownForm;
Begin
  Result := Nil;
  If (Key = '') Or (Not Assigned(MarkdownForms)) Then
    Exit;
  For I := 0 To MarkdownForms.Count - 1 Do
    Begin
      Form := TAssistantMarkdownForm(MarkdownForms[I]);
      If Assigned(Form) And (Key <> '') And (Form.SnippetKey = Key) Then
        Begin
          Result := Form;
          Exit;
        End;
    End;
End;

Function OpenMarkdownSnippet(Const Key, Title, Body: String): TAssistantMarkdownForm;
Var
  OwnerComp: TComponent;
Begin
  Result := FindMarkdownSnippet(Key);
  If Assigned(Result) Then
    Begin
      Result.LoadSnippet(Key, Title, Body);
      Result.Show;
      Result.BringToFront;
      Exit;
    End;
  OwnerComp := Application;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.OwningComponent) Then
    OwnerComp := LazarusIDE.OwningComponent;
  Result := TAssistantMarkdownForm.Create(OwnerComp);
  Result.LoadSnippet(Key, Title, Body);
  Result.Show;
End;

Function OpenMarkdownDocument(Const FileName: String): TAssistantMarkdownForm;
Var
  OwnerComp: TComponent;
  Target: String;
Begin
  Result := Nil;
  Target := Trim(FileName);
  If Target <> '' Then
    Begin
      Result := FindMarkdownDocument(Target);
      If Assigned(Result) Then
        Begin
          { Re-read if clean. Dirty windows keep edits and note a pending reload. }
          Result.ReloadFromDisk(False);
          Result.Show;
          Result.BringToFront;
          Exit;
        End;
    End;

  OwnerComp := Application;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.OwningComponent) Then
    OwnerComp := LazarusIDE.OwningComponent;

  Result := TAssistantMarkdownForm.Create(OwnerComp);
  If Target = '' Then
    Begin
      If Not Result.PromptOpen Then
        Begin
          Result.Free;
          Result := Nil;
          Exit;
        End;
    End
  Else If Not Result.OpenFile(Target) Then
    Begin
      Result.Free;
      Result := Nil;
      Exit;
    End;
  Result.Show;
End;

Function OpenNewMarkdownDocument: TAssistantMarkdownForm;
Var
  OwnerComp: TComponent;
Begin
  OwnerComp := Application;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.OwningComponent) Then
    OwnerComp := LazarusIDE.OwningComponent;
  Result := TAssistantMarkdownForm.Create(OwnerComp);
  Result.StartNewDocument;
  Result.Show;
  Result.BringToFront;
  If Result.SourceMemo.CanFocus Then
    Result.SourceMemo.SetFocus;
End;

Function NewMarkdownDocumentFolder: String;
Var
  Project: TLazProject;
  MainName, Root: String;
Begin
  Result := '';
  If (Not Assigned(LazarusIDE)) Or (Not Assigned(LazarusIDE.ActiveProject)) Then
    Exit;
  Project := LazarusIDE.ActiveProject;
  MainName := '';
  If Assigned(Project.MainFile) Then
    MainName := Project.MainFile.Filename;
  Root := ResolveAssistantProjectRoot(Project.ProjectInfoFile, MainName);
  If Root = '' Then
    Root := ExtractFilePath(Project.ProjectInfoFile);
  If Root = '' Then
    Exit;
  Root := IncludeTrailingPathDelimiter(Root);
  If DirectoryExistsUTF8(Root + AssistantDocumentsDirName) Then
    Result := Root + AssistantDocumentsDirName
  Else
    Result := ExcludeTrailingPathDelimiter(Root);
End;

Function TAssistantMarkdownForm.ReloadFromDisk(Force: Boolean): Boolean;
Begin
  Result := False;
  If FFileName = '' Then
    Exit;
  If FDirty Then
    Begin
      If (Not Force) Or (MessageDlg('Reload "' + ExtractFileName(FFileName) +
        '" from disk and discard unsaved edits?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) Then
        Begin
          FPendingDiskReload := True;
          UpdateStatus;
          Exit;
        End;
    End;
  Result := LoadFromDisk;
  If Result Then
    StatusFooter.SetRightText('Reloaded ' + FormatDateTime('hh:nn:ss', Now));
End;

Constructor TAssistantMarkdownForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FFileName := '';
  FDirty := False;
  FLoading := False;
  FViewMode := mvmPreview;
  FDiskAge := -1;
  FPendingDiskReload := False;
  FSnippet := False;
  FSnippetKey := '';
  FSnippetTitle := '';
  FNewDocument := False;
  PreviewControl := Nil;
  PreviewLoader := Nil;
End;

Procedure TAssistantMarkdownForm.FormCreate(Sender: TObject);
Begin
  EnsurePreview;
  ApplyViewMode;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
  If Assigned(MarkdownForms) Then
    MarkdownForms.Add(Self);
  WorkflowLogger.Info('AssistantMarkdown', 'Markdown window created');
End;

Procedure TAssistantMarkdownForm.FormDestroy(Sender: TObject);
Var
  I: Integer;
Begin
  WatchTimer.Enabled := False;
  DebounceTimer.Enabled := False;
  FreeAndNil(PreviewLoader);
  If Assigned(MarkdownForms) Then
    Begin
      I := MarkdownForms.IndexOf(Self);
      If I >= 0 Then
        MarkdownForms.Delete(I);
    End;
  WorkflowLogger.Info('AssistantMarkdown', 'Markdown window destroyed');
End;

Procedure TAssistantMarkdownForm.FormClose(Sender: TObject; Var CloseAction: TCloseAction);
Begin
  CloseAction := caFree;
End;

Procedure TAssistantMarkdownForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := ConfirmDiscardEdits;
End;

Procedure TAssistantMarkdownForm.EnsurePreview;
Begin
  If Assigned(PreviewControl) Then
    Exit;
  PreviewHost.Color := clWhite;
  PreviewHost.ParentColor := False;
  PreviewHost.ParentBackground := False;
  PreviewControl := TStyledMemo.Create(Self);
  PreviewControl.Parent := PreviewHost;
  PreviewControl.Align := alClient;
  PreviewControl.BorderSpacing.Around := PreviewContentMargin;
  PreviewControl.Color := clWhite;
  PreviewControl.ParentColor := False;
  PreviewControl.ReadOnly := True;
  PreviewControl.ShowCaret := False;
  PreviewControl.WordWrap := True;
  { Hide the bar when the preview fits. Word wrap is already on, so this is vertical only. }
  PreviewControl.ScrollBars := ssAutoVertical;
  PreviewControl.ParentFont := False;
  PreviewControl.Visible := True;
  PreviewLoader := TStyledMarkdown.Create(PreviewControl);
End;

Procedure TAssistantMarkdownForm.ApplyViewMode;
Begin
  PreviewModeAction.Checked := FViewMode = mvmPreview;
  SourceModeAction.Checked := FViewMode = mvmSource;
  If FViewMode = mvmPreview Then
    Begin
      SourceMemo.Visible := False;
      PreviewHost.Visible := True;
      PreviewHost.Align := alClient;
      { Keep preview content in sync when returning from source edits. }
      If Not FLoading Then
        ApplyPreviewText(SourceMemo.Text);
    End
  Else
    Begin
      PreviewHost.Visible := False;
      SourceMemo.Visible := True;
      SourceMemo.Align := alClient;
    End;
End;

Function TAssistantMarkdownForm.DocumentTitle: String;
Begin
  If FSnippet And (FSnippetTitle <> '') Then
    Result := FSnippetTitle
  Else If FNewDocument Then
    Result := NewMarkdownDocumentTitle
  Else If FFileName = '' Then
    Result := 'Markdown'
  Else
    Result := ExtractFileName(FFileName);
End;

Procedure TAssistantMarkdownForm.UpdateCaption;
Var
  Title: String;
Begin
  Title := DocumentTitle;
  If FDirty And (Not FSnippet) Then
    Title := Title + ' *';
  Caption := Title;
End;

Procedure TAssistantMarkdownForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
Begin
  If FSnippet Then
    LeftText := 'Review'
  Else If FNewDocument Then
    LeftText := 'Not saved yet'
  Else If FFileName = '' Then
    LeftText := 'No file'
  Else
    LeftText := FFileName;
  If FViewMode = mvmPreview Then
    CentreText := 'Preview'
  Else
    CentreText := 'Source';
  If FSnippet Then
    RightText := 'Read only'
  Else If (FFileName <> '') And FPendingDiskReload And (Not FileExists(FFileName)) Then
    RightText := 'Deleted on disk'
  Else If FDirty And DiskCopyIsNewer Then
    RightText := 'Modified; disk changed (local edits kept)'
  Else If FDirty Then
    RightText := 'Modified'
  Else If FPendingDiskReload Then
    RightText := 'Disk changed (local edits kept)'
  Else If FFileName <> '' Then
    RightText := 'Live'
  Else
    RightText := 'Ready';
  StatusFooter.SetAll(LeftText, CentreText, RightText);
End;

Procedure TAssistantMarkdownForm.RefreshActionState;
Begin
  If FSnippet Then
    Begin
      OpenAction.Enabled := False;
      SaveAction.Enabled := False;
      Exit;
    End;
  OpenAction.Enabled := True;
  { A new document can be saved before any typing, to create an empty file. }
  SaveAction.Enabled := FNewDocument Or ((FFileName <> '') And FDirty);
End;

Procedure TAssistantMarkdownForm.SetDirty(IsDirty: Boolean);
Begin
  If FDirty = IsDirty Then
    Exit;
  FDirty := IsDirty;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
End;

Function TAssistantMarkdownForm.ConfirmDiscardEdits: Boolean;
Begin
  Result := True;
  If FSnippet Or (Not FDirty) Then
    Exit;
  Case MessageDlg('Save changes to ' + DocumentTitle + ' before closing?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) Of
    mrYes:
      Result := SaveToDisk;
    mrNo: Result := True;
  Else
    Result := False;
  End;
End;

Procedure TAssistantMarkdownForm.ApplyPreviewText(Const Body: String);
Begin
  EnsurePreview;
  Try
    PreviewLoader.LoadFromString(Body);
  Except
    { Leave an empty preview rather than a half-laid-out control. }
    PreviewLoader.LoadFromString('');
    Raise;
  End;
End;

Function TAssistantMarkdownForm.LoadFromDisk: Boolean;
Var
  Body: String;
  SL: TStringList;
Begin
  Result := False;
  If (FFileName = '') Or (Not FileExists(FFileName)) Then
    Begin
      MessageDlg('File not found: ' + FFileName, mtError, [mbOK], 0);
      Exit;
    End;
  SL := TStringList.Create;
  FLoading := True;
  Try
    Try
      SL.LoadFromFile(FFileName);
      Body := SL.Text;
      SourceMemo.Lines.Assign(SL);
      Try
        ApplyPreviewText(Body);
      Except
        On E: Exception Do
          Begin
            { Keep source text so Source view still works; preview may stay empty. }
            WorkflowLogger.Warning('AssistantMarkdown', 'Preview failed for ' + FFileName + ': ' + E.Message);
            MessageDlg('Failed to render Markdown preview: ' + E.Message + LineEnding + LineEnding +
              'The source text is still available under the Source tab.', mtError, [mbOK], 0);
          End;
      End;
      FDiskAge := FileAge(FFileName);
      FPendingDiskReload := False;
      SetDirty(False);
      WatchTimer.Enabled := True;
      Result := True;
      UpdateCaption;
      UpdateStatus;
      RefreshActionState;
      NotifyDocumentChanged;
      WorkflowLogger.Info('AssistantMarkdown', 'Loaded ' + FFileName);
    Except
      On E: Exception Do
        MessageDlg('Failed to load Markdown: ' + E.Message, mtError, [mbOK], 0);
    End;
  Finally
    FLoading := False;
    SL.Free;
  End;
End;

Function TAssistantMarkdownForm.DiskCopyIsNewer: Boolean;
Var
  Age: LongInt;
Begin
  Result := False;
  If (FFileName = '') Or (Not FPendingDiskReload) Or (Not FileExists(FFileName)) Then
    Exit;
  Age := FileAge(FFileName);
  Result := Age <> FDiskAge;
End;

Function TAssistantMarkdownForm.ConfirmNewerDiskCopy: TModalResult;
Var
  Dlg: TForm;
  I: Integer;
  Button: TCustomButton;
Begin
  Dlg := CreateMessageDialog('"' + ExtractFileName(FFileName) + '" changed on disk while this window has local edits.' +
    LineEnding + LineEnding +
    'Overwrite replaces the newer disk copy with your edits. Reload discards your edits and loads the disk copy.',
    mtWarning, [mbYes, mbNo, mbCancel]);
  Try
    Dlg.Caption := 'File changed on disk';
    For I := 0 To Dlg.ComponentCount - 1 Do
      If Dlg.Components[I] Is TCustomButton Then
        Begin
          Button := TCustomButton(Dlg.Components[I]);
          Button.Default := False;
          Case Button.ModalResult Of
            mrYes: Button.Caption := 'Overwrite';
            mrNo: Button.Caption := 'Reload';
            mrCancel:
              Begin
                Button.Caption := 'Cancel';
                Button.Default := True;
                Dlg.ActiveControl := Button;
              End;
          Else
          End;
        End;
    Result := Dlg.ShowModal;
  Finally
    Dlg.Free;
  End;
End;

Function TAssistantMarkdownForm.PromptSaveAs(Out Target: String): Boolean;
Var
  InitialDir: String;
  Existing: TAssistantMarkdownForm;
Begin
  Result := False;
  Target := '';
  InitialDir := NewMarkdownDocumentFolder;
  If InitialDir <> '' Then
    SaveDialog.InitialDir := InitialDir;
  SaveDialog.FileName := '';
  If Not SaveDialog.Execute Then
    Exit;
  Target := ExpandFileName(Trim(SaveDialog.FileName));
  If Target = '' Then
    Exit;
  { Not every widgetset applies DefaultExt, and its overwrite prompt only saw the name as typed. }
  If ExtractFileExt(Target) = '' Then
    Begin
      Target := Target + '.md';
      If FileExists(Target) And (MessageDlg('"' + ExtractFileName(Target) + '" already exists. Replace it?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes) Then
        Begin
          Target := '';
          Exit;
        End;
    End;
  { Two live windows on one file would each overwrite the other's edits. }
  Existing := FindMarkdownDocument(Target);
  If Assigned(Existing) And (Existing <> Self) Then
    Begin
      MessageDlg('"' + ExtractFileName(Target) + '" is already open in another Markdown window. ' +
        'Close that window or choose another name.', mtWarning, [mbOK], 0);
      Target := '';
      Exit;
    End;
  Result := True;
End;

Function TAssistantMarkdownForm.SaveToDisk: Boolean;
Var
  Target: String;
Begin
  Result := False;
  If FSnippet Then
    Exit;
  If FNewDocument Then
    Begin
      If Not PromptSaveAs(Target) Then
        Exit;
    End
  Else
    Begin
      Target := FFileName;
      If Target = '' Then
        Exit;
      If DiskCopyIsNewer Then
        Begin
          UpdateStatus;
          Case ConfirmNewerDiskCopy Of
            mrYes: { Explicit overwrite of the newer disk copy. };
            mrNo:
              Begin
                Result := LoadFromDisk;
                If Result And Assigned(StatusFooter) Then
                  StatusFooter.SetRightText('Reloaded ' + FormatDateTime('hh:nn:ss', Now));
                Exit;
              End;
          Else
            Exit;
          End;
        End;
    End;
  Try
    SourceMemo.Lines.SaveToFile(Target);
    { The document only takes the name once the file is written, so a failed write leaves it new. }
    If FNewDocument Then
      Begin
        FFileName := Target;
        FNewDocument := False;
        WatchTimer.Enabled := True;
      End;
    FDiskAge := FileAge(FFileName);
    FPendingDiskReload := False;
    SetDirty(False);
    ApplyPreviewText(SourceMemo.Text);
    NotifyDocumentSaved;
    NotifyDocumentChanged;
    Result := True;
    UpdateCaption;
    RefreshActionState;
    UpdateStatus;
    WorkflowLogger.Info('AssistantMarkdown', 'Saved ' + FFileName);
  Except
    On E: Exception Do
      MessageDlg('Failed to save Markdown: ' + E.Message, mtError, [mbOK], 0);
  End;
End;

Function TAssistantMarkdownForm.OpenFile(Const FileName: String): Boolean;
Var
  Expanded: String;
  WasNew: Boolean;
Begin
  Result := False;
  Expanded := ExpandFileName(Trim(FileName));
  If Expanded = '' Then
    Exit;
  If FDirty And (Not ConfirmDiscardEdits) Then
    Exit;
  WasNew := FNewDocument;
  FFileName := Expanded;
  FNewDocument := False;
  Result := LoadFromDisk;
  If (Not Result) And WasNew Then
    Begin
      FFileName := '';
      FNewDocument := True;
      UpdateCaption;
      UpdateStatus;
      RefreshActionState;
    End;
  If Result Then
    Begin
      Show;
      BringToFront;
    End;
End;

Function TAssistantMarkdownForm.PromptOpen: Boolean;
Var
  InitialDir: String;
Begin
  Result := False;
  InitialDir := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) And
    Assigned(LazarusIDE.ActiveProject.MainFile) Then
    InitialDir := ExtractFilePath(LazarusIDE.ActiveProject.MainFile.Filename);
  If (InitialDir = '') And (FFileName <> '') Then
    InitialDir := ExtractFilePath(FFileName);
  If InitialDir <> '' Then
    OpenDialog.InitialDir := InitialDir;
  If Not OpenDialog.Execute Then
    Exit;
  Result := OpenFile(OpenDialog.FileName);
End;

Procedure TAssistantMarkdownForm.NotifyDocumentChanged;
Begin
  If Assigned(WorkflowEventBus) And (FFileName <> '') Then
    WorkflowEventBus.NotifyDocumentChanged(FFileName, SourceMemo.Text);
End;

Procedure TAssistantMarkdownForm.NotifyDocumentSaved;
Begin
  If Assigned(WorkflowEventBus) And (FFileName <> '') Then
    WorkflowEventBus.NotifyDocumentSaved(FFileName);
End;

Procedure TAssistantMarkdownForm.OpenActionExecute(Sender: TObject);
Begin
  PromptOpen;
End;

Procedure TAssistantMarkdownForm.SaveActionExecute(Sender: TObject);
Begin
  SaveToDisk;
End;

Procedure TAssistantMarkdownForm.PreviewModeActionExecute(Sender: TObject);
Begin
  FViewMode := mvmPreview;
  ApplyViewMode;
  If PreviewControl.CanFocus Then PreviewControl.SetFocus;
  UpdateStatus;
End;

Procedure TAssistantMarkdownForm.SourceModeActionExecute(Sender: TObject);
Begin
  FViewMode := mvmSource;
  ApplyViewMode;
  If SourceMemo.CanFocus Then SourceMemo.SetFocus;
  UpdateStatus;
End;

Procedure TAssistantMarkdownForm.StartNewDocument;
Begin
  FSnippet := False;
  FSnippetKey := '';
  FSnippetTitle := '';
  FNewDocument := True;
  FFileName := '';
  FPendingDiskReload := False;
  FDiskAge := -1;
  WatchTimer.Enabled := False;
  DebounceTimer.Enabled := False;
  FLoading := True;
  Try
    SourceMemo.ReadOnly := False;
    SourceMemo.Clear;
    ApplyPreviewText('');
    { An empty preview has nowhere to type, so a new document starts in Source view. }
    FViewMode := mvmSource;
    ApplyViewMode;
    FDirty := False;
  Finally
    FLoading := False;
  End;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
End;

Procedure TAssistantMarkdownForm.LoadSnippet(Const Key, Title, Body: String);
Begin
  FSnippet := True;
  FNewDocument := False;
  FSnippetKey := Key;
  FSnippetTitle := Title;
  FFileName := '';
  FPendingDiskReload := False;
  FDiskAge := -1;
  WatchTimer.Enabled := False;
  DebounceTimer.Enabled := False;
  FLoading := True;
  Try
    SourceMemo.ReadOnly := True;
    SourceMemo.Text := Body;
    FViewMode := mvmPreview;
    Try
      ApplyPreviewText(Body);
    Except
      On E: Exception Do
        Begin
          WorkflowLogger.Warning('AssistantMarkdown', 'Snippet preview failed: ' + E.Message);
          ApplyPreviewText('');
        End;
    End;
    ApplyViewMode;
    FDirty := False;
  Finally
    FLoading := False;
  End;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
End;

Procedure TAssistantMarkdownForm.SourceMemoChange(Sender: TObject);
Begin
  If FLoading Or FSnippet Then
    Exit;
  SetDirty(True);
End;

Procedure TAssistantMarkdownForm.WatchTimerTimer(Sender: TObject);
Var
  Age: LongInt;
Begin
  If FFileName = '' Then
    Exit;
  If Not FileExists(FFileName) Then
    Begin
      FPendingDiskReload := True;
      UpdateStatus;
      If Assigned(StatusFooter) Then
        StatusFooter.SetRightText('Deleted on disk');
      Exit;
    End;
  Age := FileAge(FFileName);
  If Age = FDiskAge Then
    Exit;
  If FDirty Then
    Begin
      FPendingDiskReload := True;
      UpdateStatus;
      Exit;
    End;
  { Debounce rapid successive writes (e.g. editor save + LLM rewrite). }
  DebounceTimer.Enabled := False;
  DebounceTimer.Enabled := True;
End;

Procedure TAssistantMarkdownForm.DebounceTimerTimer(Sender: TObject);
Begin
  DebounceTimer.Enabled := False;
  If FDirty Then
    Begin
      FPendingDiskReload := True;
      UpdateStatus;
      Exit;
    End;
  If FFileName = '' Then
    Exit;
  LoadFromDisk;
  StatusFooter.SetRightText('Reloaded ' + FormatDateTime('hh:nn:ss', Now));
End;

Initialization

MarkdownForms := TList.Create;

Finalization

FreeAndNil(MarkdownForms);

End.
