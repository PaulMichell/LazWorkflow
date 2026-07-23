Unit GrokMarkdownForm;

{ Live Markdown document loader/viewer windows for LazGrokChat (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, ActnList, StatusFooterFrame;

Type
  TMarkdownViewMode = (mvmPreview, mvmSource, mvmSplit);

  TGrokMarkdownForm = Class(TForm)
    FActionList: TActionList;
    FOpenAction: TAction;
    FReloadAction: TAction;
    FSaveAction: TAction;
    FPreviewModeAction: TAction;
    FSourceModeAction: TAction;
    FSplitModeAction: TAction;
    FRevealAction: TAction;
    FOpenDialog: TOpenDialog;
    FToolBar: TToolBar;
    ToolButtonOpen: TToolButton;
    ToolButtonReload: TToolButton;
    ToolButtonSave: TToolButton;
    ToolButtonSep1: TToolButton;
    ToolButtonPreview: TToolButton;
    ToolButtonSource: TToolButton;
    ToolButtonSplit: TToolButton;
    ToolButtonSep2: TToolButton;
    ToolButtonReveal: TToolButton;
    FStatusFooter: TStatusFooterFrame;
    FContentPanel: TPanel;
    FSourceMemo: TMemo;
    FSplitter: TSplitter;
    FPreviewHost: TPanel;
    FWatchTimer: TTimer;
    FDebounceTimer: TTimer;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormClose(Sender: TObject; Var CloseAction: TCloseAction);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure OpenActionExecute(Sender: TObject);
    Procedure ReloadActionExecute(Sender: TObject);
    Procedure SaveActionExecute(Sender: TObject);
    Procedure PreviewModeActionExecute(Sender: TObject);
    Procedure SourceModeActionExecute(Sender: TObject);
    Procedure SplitModeActionExecute(Sender: TObject);
    Procedure RevealActionExecute(Sender: TObject);
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
    FPreview: TControl; { TMarkDownControl created at runtime. }
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
    Procedure HandlePreviewOpenURL(Sender: TObject; AUrl: String);
    Procedure HandlePreviewGetImage(Sender: TObject; Const AUrl: String; Var AImage: TPicture);
    Procedure NotifyDocumentChanged;
    Procedure NotifyDocumentSaved;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Function OpenFile(Const FileName: String): Boolean;
    Function PromptOpen: Boolean;
    Property FileName: String Read FFileName;
    Property Dirty: Boolean Read FDirty;
    Property ViewMode: TMarkdownViewMode Read FViewMode;
  End;

{ Opens an existing viewer for FileName, or creates one. Empty FileName shows the open dialog. }
Function OpenMarkdownDocument(Const FileName: String = ''): TGrokMarkdownForm;
Function FindMarkdownDocument(Const FileName: String): TGrokMarkdownForm;

Implementation

{$R *.lfm}

Uses
  LCLIntf, FileUtil, LazFileUtils, MarkDown.Control, WorkflowLog, WorkflowEvents, LazIDEIntf,
  ProjectIntf;

Var
  MarkdownForms: TList;

Function SameFilePath(Const A, B: String): Boolean;
Begin
  Result := SameFileName(ExpandFileName(A), ExpandFileName(B));
End;

Function FindMarkdownDocument(Const FileName: String): TGrokMarkdownForm;
Var
  I: Integer;
  Form: TGrokMarkdownForm;
Begin
  Result := Nil;
  If (FileName = '') Or (Not Assigned(MarkdownForms)) Then
    Exit;
  For I := 0 To MarkdownForms.Count - 1 Do
    Begin
      Form := TGrokMarkdownForm(MarkdownForms[I]);
      If Assigned(Form) And SameFilePath(Form.FileName, FileName) Then
        Begin
          Result := Form;
          Exit;
        End;
    End;
End;

Function OpenMarkdownDocument(Const FileName: String): TGrokMarkdownForm;
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
          Result.Show;
          Result.BringToFront;
          Exit;
        End;
    End;

  OwnerComp := Application;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.OwningComponent) Then
    OwnerComp := LazarusIDE.OwningComponent;

  Result := TGrokMarkdownForm.Create(OwnerComp);
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

Constructor TGrokMarkdownForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FFileName := '';
  FDirty := False;
  FLoading := False;
  FViewMode := mvmSplit;
  FDiskAge := -1;
  FPendingDiskReload := False;
  FPreview := Nil;
End;

Procedure TGrokMarkdownForm.FormCreate(Sender: TObject);
Begin
  EnsurePreview;
  ApplyViewMode;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
  If Assigned(MarkdownForms) Then
    MarkdownForms.Add(Self);
  WorkflowLogger.Info('GrokMarkdown', 'Markdown window created');
End;

Procedure TGrokMarkdownForm.FormDestroy(Sender: TObject);
Var
  I: Integer;
Begin
  FWatchTimer.Enabled := False;
  FDebounceTimer.Enabled := False;
  If Assigned(MarkdownForms) Then
    Begin
      I := MarkdownForms.IndexOf(Self);
      If I >= 0 Then
        MarkdownForms.Delete(I);
    End;
  WorkflowLogger.Info('GrokMarkdown', 'Markdown window destroyed');
End;

Procedure TGrokMarkdownForm.FormClose(Sender: TObject; Var CloseAction: TCloseAction);
Begin
  CloseAction := caFree;
End;

Procedure TGrokMarkdownForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := ConfirmDiscardEdits;
End;

Procedure TGrokMarkdownForm.EnsurePreview;
Var
  Preview: TMarkDownControl;
Begin
  If Assigned(FPreview) Then
    Exit;
  Preview := TMarkDownControl.Create(Self);
  Preview.Parent := FPreviewHost;
  Preview.Align := alClient;
  Preview.ScrollBars := ssAutoBoth;
  Preview.MonoFontName := 'Monospace';
  Preview.FontName := 'default';
  Preview.OnOpenURL := @HandlePreviewOpenURL;
  Preview.OnGetImage := @HandlePreviewGetImage;
  Preview.Visible := True;
  FPreview := Preview;
End;

Procedure TGrokMarkdownForm.ApplyViewMode;
Begin
  Case FViewMode Of
    mvmPreview:
      Begin
        FSourceMemo.Visible := False;
        FSplitter.Visible := False;
        FPreviewHost.Visible := True;
        FPreviewHost.Align := alClient;
      End;
    mvmSource:
      Begin
        FPreviewHost.Visible := False;
        FSplitter.Visible := False;
        FSourceMemo.Visible := True;
        FSourceMemo.Align := alClient;
      End;
  Else
    { Split: source left, preview right. }
    FSourceMemo.Visible := True;
    FSplitter.Visible := True;
    FPreviewHost.Visible := True;
    FSourceMemo.Align := alLeft;
    If FSourceMemo.Width < 120 Then
      Begin
        If FContentPanel.ClientWidth Div 2 > 200 Then
          FSourceMemo.Width := FContentPanel.ClientWidth Div 2
        Else
          FSourceMemo.Width := 200;
      End;
    FSplitter.Align := alLeft;
    FPreviewHost.Align := alClient;
  End;
End;

Procedure TGrokMarkdownForm.UpdateCaption;
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

Procedure TGrokMarkdownForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
Begin
  If FFileName = '' Then
    LeftText := 'No file'
  Else
    LeftText := FFileName;
  Case FViewMode Of
    mvmPreview: CentreText := 'Preview';
    mvmSource: CentreText := 'Source';
  Else
    CentreText := 'Split';
  End;
  If FDirty Then
    RightText := 'Modified'
  Else If FPendingDiskReload Then
    RightText := 'Disk changed (local edits kept)'
  Else If FFileName <> '' Then
    RightText := 'Live'
  Else
    RightText := 'Ready';
  FStatusFooter.SetAll(LeftText, CentreText, RightText);
End;

Procedure TGrokMarkdownForm.RefreshActionState;
Var
  HasFile: Boolean;
Begin
  HasFile := FFileName <> '';
  FReloadAction.Enabled := HasFile;
  FSaveAction.Enabled := HasFile And FDirty;
  FRevealAction.Enabled := HasFile;
End;

Procedure TGrokMarkdownForm.SetDirty(IsDirty: Boolean);
Begin
  If FDirty = IsDirty Then
    Exit;
  FDirty := IsDirty;
  UpdateCaption;
  UpdateStatus;
  RefreshActionState;
End;

Function TGrokMarkdownForm.ConfirmDiscardEdits: Boolean;
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

Procedure TGrokMarkdownForm.ApplyPreviewText(Const Body: String);
Var
  Preview: TMarkDownControl;
Begin
  EnsurePreview;
  Preview := TMarkDownControl(FPreview);
  Preview.MarkDown.BeginUpdate;
  Try
    Preview.MarkDown.Text := Body;
  Finally
    Preview.MarkDown.EndUpdate;
  End;
End;

Function TGrokMarkdownForm.LoadFromDisk: Boolean;
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
      FSourceMemo.Lines.Assign(SL);
      ApplyPreviewText(Body);
      FDiskAge := FileAge(FFileName);
      FPendingDiskReload := False;
      SetDirty(False);
      FWatchTimer.Enabled := True;
      Result := True;
      UpdateCaption;
      UpdateStatus;
      RefreshActionState;
      NotifyDocumentChanged;
      WorkflowLogger.Info('GrokMarkdown', 'Loaded ' + FFileName);
    Except
      On E: Exception Do
        MessageDlg('Failed to load Markdown: ' + E.Message, mtError, [mbOK], 0);
    End;
  Finally
    FLoading := False;
    SL.Free;
  End;
End;

Function TGrokMarkdownForm.SaveToDisk: Boolean;
Begin
  Result := False;
  If FFileName = '' Then
    Exit;
  Try
    FSourceMemo.Lines.SaveToFile(FFileName);
    FDiskAge := FileAge(FFileName);
    FPendingDiskReload := False;
    SetDirty(False);
    ApplyPreviewText(FSourceMemo.Text);
    NotifyDocumentSaved;
    NotifyDocumentChanged;
    Result := True;
    UpdateStatus;
    WorkflowLogger.Info('GrokMarkdown', 'Saved ' + FFileName);
  Except
    On E: Exception Do
      MessageDlg('Failed to save Markdown: ' + E.Message, mtError, [mbOK], 0);
  End;
End;

Function TGrokMarkdownForm.OpenFile(Const FileName: String): Boolean;
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

Function TGrokMarkdownForm.PromptOpen: Boolean;
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
    FOpenDialog.InitialDir := InitialDir;
  If Not FOpenDialog.Execute Then
    Exit;
  Result := OpenFile(FOpenDialog.FileName);
End;

Procedure TGrokMarkdownForm.NotifyDocumentChanged;
Begin
  If Assigned(WorkflowEventBus) And (FFileName <> '') Then
    WorkflowEventBus.NotifyDocumentChanged(FFileName, FSourceMemo.Text);
End;

Procedure TGrokMarkdownForm.NotifyDocumentSaved;
Begin
  If Assigned(WorkflowEventBus) And (FFileName <> '') Then
    WorkflowEventBus.NotifyDocumentSaved(FFileName);
End;

Procedure TGrokMarkdownForm.HandlePreviewOpenURL(Sender: TObject; AUrl: String);
Var
  Target: String;
Begin
  Target := Trim(AUrl);
  If Target = '' Then
    Exit;
  { Relative links resolve against the document directory. }
  If (Pos('://', Target) = 0) And (FFileName <> '') Then
    Begin
      If Target[1] <> PathDelim Then
        Target := ExpandFileName(ExtractFilePath(FFileName) + Target);
    End;
  If FileExists(Target) And
    ((CompareText(ExtractFileExt(Target), '.md') = 0) Or
     (CompareText(ExtractFileExt(Target), '.markdown') = 0) Or
     (CompareText(ExtractFileExt(Target), '.mdown') = 0)) Then
    OpenMarkdownDocument(Target)
  Else
    OpenURL(AUrl);
End;

Procedure TGrokMarkdownForm.HandlePreviewGetImage(Sender: TObject; Const AUrl: String;
  Var AImage: TPicture);
Var
  Path: String;
Begin
  Path := Trim(AUrl);
  If Path = '' Then
    Exit;
  If (Pos('://', Path) = 0) And (FFileName <> '') Then
    Path := ExpandFileName(ExtractFilePath(FFileName) + Path);
  If FileExists(Path) Then
    Begin
      AImage := TPicture.Create;
      Try
        AImage.LoadFromFile(Path);
      Except
        FreeAndNil(AImage);
      End;
    End;
End;

Procedure TGrokMarkdownForm.OpenActionExecute(Sender: TObject);
Begin
  PromptOpen;
End;

Procedure TGrokMarkdownForm.ReloadActionExecute(Sender: TObject);
Begin
  If FFileName = '' Then
    Exit;
  If FDirty And (Not ConfirmDiscardEdits) Then
    Exit;
  LoadFromDisk;
End;

Procedure TGrokMarkdownForm.SaveActionExecute(Sender: TObject);
Begin
  SaveToDisk;
End;

Procedure TGrokMarkdownForm.PreviewModeActionExecute(Sender: TObject);
Begin
  FViewMode := mvmPreview;
  ApplyViewMode;
  UpdateStatus;
End;

Procedure TGrokMarkdownForm.SourceModeActionExecute(Sender: TObject);
Begin
  FViewMode := mvmSource;
  ApplyViewMode;
  UpdateStatus;
End;

Procedure TGrokMarkdownForm.SplitModeActionExecute(Sender: TObject);
Begin
  FViewMode := mvmSplit;
  ApplyViewMode;
  UpdateStatus;
End;

Procedure TGrokMarkdownForm.RevealActionExecute(Sender: TObject);
Var
  Dir: String;
Begin
  If FFileName = '' Then
    Exit;
  Dir := ExtractFilePath(FFileName);
  If DirectoryExists(Dir) Then
    OpenDocument(Dir)
  Else
    OpenDocument(FFileName);
End;

Procedure TGrokMarkdownForm.SourceMemoChange(Sender: TObject);
Begin
  If FLoading Then
    Exit;
  SetDirty(True);
  { Live-update preview while typing in source/split modes. }
  If FViewMode <> mvmSource Then
    ApplyPreviewText(FSourceMemo.Text);
End;

Procedure TGrokMarkdownForm.WatchTimerTimer(Sender: TObject);
Var
  Age: LongInt;
Begin
  If (FFileName = '') Or (Not FileExists(FFileName)) Then
    Exit;
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
  FDebounceTimer.Enabled := False;
  FDebounceTimer.Enabled := True;
End;

Procedure TGrokMarkdownForm.DebounceTimerTimer(Sender: TObject);
Begin
  FDebounceTimer.Enabled := False;
  If FDirty Then
    Begin
      FPendingDiskReload := True;
      UpdateStatus;
      Exit;
    End;
  If FFileName = '' Then
    Exit;
  LoadFromDisk;
  FStatusFooter.SetRightText('Reloaded ' + FormatDateTime('hh:nn:ss', Now));
End;

Initialization

MarkdownForms := TList.Create;

Finalization

FreeAndNil(MarkdownForms);

End.
