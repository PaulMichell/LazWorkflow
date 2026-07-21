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
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FBuildAction: TAction;
    FToolBar: TToolBar;
    ToolButtonNewChat: TToolButton;
    ToolButtonSep: TToolButton;
    ToolButtonBuild: TToolButton;
    FStatusFooter: TStatusFooterFrame;
    FInputPanel: TPanel;
    FSendButton: TButton;
    FInputEdit: TMemo;
    FChatMemo: TMemo;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure BuildActionExecute(Sender: TObject);
  Private
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
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
  WorkflowLog, GrokService, LazIDEIntf, CompOptsIntf;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := 'grok-4';
  FContextUsed := 0;
  FContextLimit := 128000;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGrokChatForm.Destroy;
Begin
  WorkflowEventBus.RemoveListener(Self);
  Inherited Destroy;
End;

Procedure TGrokChatForm.FormCreate(Sender: TObject);
Begin
  UpdateStatusFooter;
  AppendMessage('system', 'Grok Chat ready. Type a message and press Send.');
  WorkflowLogger.Info('GrokChat', 'Grok Chat window created');
End;

Procedure TGrokChatForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('GrokChat', 'Grok Chat window destroyed');
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
  { TODO: call GrokClient.SendAndStream asynchronously and stream reply }
  AppendMessage('assistant', '(Streaming reply will appear here – Phase 2)');
  FContextUsed := FContextUsed + Length(UserText) Div 4 + 50;
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
  Else
    { }
  End;
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.DocumentChanged(Const FileName: String; Const NewContent: String);
Begin
  WorkflowLogger.Debug('GrokChat', 'Document changed: ' + FileName);
End;

Procedure TGrokChatForm.DocumentSaved(Const FileName: String);
Begin
  WorkflowLogger.Debug('GrokChat', 'Document saved: ' + FileName);
End;

End.
