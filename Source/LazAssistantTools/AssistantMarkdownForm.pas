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
    PreviewControl: TStyledMemo;
    PreviewLoader: TStyledMarkdown;
    Procedure EnsurePreview;
    Procedure ApplyViewMode;
    Procedure UpdateCaption;
    Procedure UpdateStatus;
    Procedure RefreshActionState;
    Procedure SetDirty(IsDirty: Boolean);
    Function ConfirmDiscardEdits: Boolean;
    Function LoadFromDisk: Boolean;
    Function SaveToDisk: Boolean;
    Procedure ApplyPreviewText(Const Body: String);
    Procedure NotifyDocumentChanged;
    Procedure NotifyDocumentSaved;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Function OpenFile(Const FileName: String): Boolean;
    Function PromptOpen: Boolean;
    { Re-read from disk (e.g. after LLM write_markdown). Skips if dirty unless Force. }
    Function ReloadFromDisk(Force: Boolean = False): Boolean;
    Property FileName: String Read FFileName;
    Property Dirty: Boolean Read FDirty;
    Property ViewMode: TMarkdownViewMode Read FViewMode;
  End;

{ Opens an existing viewer for FileName, or creates one. Empty FileName shows the open dialog.
  When the viewer is already open, reloads content from disk. }
Function OpenMarkdownDocument(Const FileName: String = ''): TAssistantMarkdownForm;
Function FindMarkdownDocument(Const FileName: String): TAssistantMarkdownForm;
{ Force-reload any open viewer for this path (no-op if none open). }
Function ReloadMarkdownDocument(Const FileName: String; Force: Boolean = True): Boolean;

Implementation

{$R *.lfm}

Uses
  LazFileUtils, WorkflowLog, WorkflowEvents, LazIDEIntf, ProjectIntf;

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

Function ReloadMarkdownDocument(Const FileName: String; Force: Boolean): Boolean;
Var
  Form: TAssistantMarkdownForm;
Begin
  Result := False;
  Form := FindMarkdownDocument(FileName);
  If Not Assigned(Form) Then
    Exit;
  Result := Form.ReloadFromDisk(Force);
  If Result Then
    Begin
      Form.Show;
      Form.BringToFront;
    End;
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

Procedure TAssistantMarkdownForm.UpdateCaption;
Var
  Title: String;
Begin
  If FFileName = '' Then
    Title := 'Markdown'
  Else
    Title := ExtractFileName(FFileName);
  If FDirty Then
    Title := Title + ' *';
  Caption := Title;
End;

Procedure TAssistantMarkdownForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
Begin
  If FFileName = '' Then
    LeftText := 'No file'
  Else
    LeftText := FFileName;
  If FViewMode = mvmPreview Then
    CentreText := 'Preview'
  Else
    CentreText := 'Source';
  If FDirty Then
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
  SaveAction.Enabled := (FFileName <> '') And FDirty;
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
  If Not FDirty Then
    Exit;
  Case MessageDlg('Save changes to ' + ExtractFileName(FFileName) + ' before closing?',
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

Function TAssistantMarkdownForm.SaveToDisk: Boolean;
Begin
  Result := False;
  If FFileName = '' Then
    Exit;
  Try
    SourceMemo.Lines.SaveToFile(FFileName);
    FDiskAge := FileAge(FFileName);
    FPendingDiskReload := False;
    SetDirty(False);
    ApplyPreviewText(SourceMemo.Text);
    NotifyDocumentSaved;
    NotifyDocumentChanged;
    Result := True;
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
Begin
  Result := False;
  Expanded := ExpandFileName(Trim(FileName));
  If Expanded = '' Then
    Exit;
  If FDirty And (Not ConfirmDiscardEdits) Then
    Exit;
  FFileName := Expanded;
  Result := LoadFromDisk;
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

Procedure TAssistantMarkdownForm.SourceMemoChange(Sender: TObject);
Begin
  If FLoading Then
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
