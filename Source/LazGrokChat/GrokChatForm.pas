Unit GrokChatForm;

{ Main Grok chat window with history, input and status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, WorkflowEvents, StatusFooterFrame;

Type
  TGrokChatForm = Class(TForm, IWorkflowListener, ICompilerFinished, IMarkdownDocumentChanged)
  Private
    FToolBar: TToolBar;
    FChatMemo: TMemo;
    FInputPanel: TPanel;
    FInputEdit: TMemo;
    FSendButton: TButton;
    FStatusFooter: TStatusFooterFrame;
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FBuildAction: TAction;
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    Procedure CreateUI;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure BuildActionExecute(Sender: TObject);
    Procedure UpdateStatusFooter;
    Procedure AppendMessage(Const Role, Content: String);
    { ICompilerFinished }
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    { IMarkdownDocumentChanged }
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GrokService, LazIDEIntf, ProjectIntf;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := 'grok-4';
  FContextUsed := 0;
  FContextLimit := 128000;
  CreateUI;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGrokChatForm.Destroy;
Begin
  WorkflowEventBus.RemoveListener(Self);
  Inherited Destroy;
End;

Procedure TGrokChatForm.CreateUI;
Begin
  Caption := 'Grok Chat';
  Width := 800;
  Height := 650;
  Position := poDefaultPosOnly;

  FActionList := TActionList.Create(Self);

  FNewChatAction := TAction.Create(Self);
  FNewChatAction.Caption := 'New Chat';
  FNewChatAction.OnExecute := @NewChatActionExecute;
  FNewChatAction.ActionList := FActionList;

  FSendAction := TAction.Create(Self);
  FSendAction.Caption := 'Send';
  FSendAction.OnExecute := @SendActionExecute;
  FSendAction.ActionList := FActionList;

  FBuildAction := TAction.Create(Self);
  FBuildAction.Caption := 'Build';
  FBuildAction.OnExecute := @BuildActionExecute;
  FBuildAction.ActionList := FActionList;

  FToolBar := TToolBar.Create(Self);
  With FToolBar Do
    Begin
      Parent := Self;
      Align := alTop;
      Height := 28;
      EdgeBorders := [];
      ShowCaptions := True;
    End;

  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Action := FNewChatAction;
      Style := tbsButton;
    End;
  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Style := tbsSeparator;
    End;
  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Action := FBuildAction;
      Style := tbsButton;
    End;

  FStatusFooter := TStatusFooterFrame.Create(Self);
  FStatusFooter.Parent := Self;
  FStatusFooter.Align := alBottom;

  FInputPanel := TPanel.Create(Self);
  With FInputPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 90;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FSendButton := TButton.Create(Self);
  With FSendButton Do
    Begin
      Parent := FInputPanel;
      Align := alRight;
      Width := 80;
      Caption := 'Send';
      BorderSpacing.Around := 6;
      Action := FSendAction;
    End;

  FInputEdit := TMemo.Create(Self);
  With FInputEdit Do
    Begin
      Parent := FInputPanel;
      Align := alClient;
      BorderSpacing.Around := 6;
      ScrollBars := ssAutoVertical;
      WantTabs := False;
      OnKeyDown := Nil; { TODO: Ctrl+Enter to send }
    End;

  FChatMemo := TMemo.Create(Self);
  With FChatMemo Do
    Begin
      Parent := Self;
      Align := alClient;
      ReadOnly := True;
      ScrollBars := ssAutoBoth;
      BorderSpacing.Around := 4;
      Font.Name := 'Monospace';
      Font.Size := 10;
    End;

  OnCreate := @FormCreate;
  OnDestroy := @FormDestroy;
End;

Procedure TGrokChatForm.FormCreate(Sender: TObject);
Begin
  UpdateStatusFooter;
  AppendMessage('system', 'Grok Chat ready. Type a message and press Send.');
  WorkflowLog.Info('GrokChat', 'Grok Chat window created');
End;

Procedure TGrokChatForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLog.Info('GrokChat', 'Grok Chat window destroyed');
End;

Procedure TGrokChatForm.UpdateStatusFooter;
Var
  Pct: Integer;
Begin
  If FContextLimit > 0 Then
    Pct := (FContextUsed * 100) Div FContextLimit
  Else
    Pct := 0;
  FStatusFooter.SetAll(
    Format('Model: %s', [FModelName]),
    Format('Context: %d / %d (%d%%)', [FContextUsed, FContextLimit, Pct]),
    'Ready');
End;

Procedure TGrokChatForm.AppendMessage(Const Role, Content: String);
Begin
  FChatMemo.Lines.Add('');
  FChatMemo.Lines.Add('[' + UpperCase(Role) + ']');
  FChatMemo.Lines.Add(Content);
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.SendActionExecute(Sender: TObject);
Var
  UserText: String;
Begin
  UserText := Trim(FInputEdit.Text);
  If UserText = '' Then
    Exit;
  AppendMessage('user', UserText);
  FInputEdit.Clear;
  FStatusFooter.SetRightText('Thinking...');
  { TODO: call GrokService.SendMessage asynchronously and stream reply }
  AppendMessage('assistant', '(Streaming reply will appear here – Phase 2)');
  FContextUsed := FContextUsed + Length(UserText) Div 4 + 50; { rough token estimate }
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.NewChatActionExecute(Sender: TObject);
Begin
  FChatMemo.Clear;
  FContextUsed := 0;
  AppendMessage('system', 'New conversation started.');
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.BuildActionExecute(Sender: TObject);
Begin
  FStatusFooter.SetRightText('Building...');
  If Assigned(LazarusIDE) Then
    LazarusIDE.DoBuildProject(crCompile, [])
  Else
    Begin
      AppendMessage('system', 'LazarusIDE not available – cannot build.');
      FStatusFooter.SetRightText('Ready');
    End;
End;

Procedure TGrokChatForm.CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
  Const OutputText: String; ErrorCount, WarningCount: Integer);
Begin
  Case Result Of
    crSuccess:
      Begin
        AppendMessage('system', Format('Build succeeded (%d warnings).', [WarningCount]));
        FStatusFooter.SetRightText('Build OK');
      End;
    crFailed:
      Begin
        AppendMessage('system', Format('Build failed – %d errors, %d warnings.', [ErrorCount, WarningCount]));
        AppendMessage('compiler', OutputText);
        FStatusFooter.SetRightText('Build failed');
      End;
    crCancelled:
      Begin
        AppendMessage('system', 'Build cancelled.');
        FStatusFooter.SetRightText('Cancelled');
      End;
  End;
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.DocumentChanged(Const FileName: String; Const NewContent: String);
Begin
  { Future: if this document is open in a Markdown window, refresh it. }
  WorkflowLog.Debug('GrokChat', 'Document changed: ' + FileName);
End;

Procedure TGrokChatForm.DocumentSaved(Const FileName: String);
Begin
  WorkflowLog.Debug('GrokChat', 'Document saved: ' + FileName);
End;

End.
