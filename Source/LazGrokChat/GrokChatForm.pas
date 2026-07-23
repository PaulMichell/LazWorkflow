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
    FSettingsAction: TAction;
    FToolBar: TToolBar;
    ToolButtonNewChat: TToolButton;
    ToolButtonSep: TToolButton;
    ToolButtonBuild: TToolButton;
    ToolButtonSep2: TToolButton;
    ToolButtonSettings: TToolButton;
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
    Procedure SettingsActionExecute(Sender: TObject);
  Private
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingLineIndex: Integer;
    FAssistantAccum: String;
    Procedure UpdateStatusFooter;
    Procedure SetSending(IsSending: Boolean);
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Procedure AppendAssistantToken(Const Token: String);
    Procedure FinishAssistantReply(Const ErrorText: String);
    Procedure StreamToken(Const Token: String; IsFinished: Boolean; Const ErrorText: String);
    Procedure RefreshFromConfig;
    { ICompilerFinished }
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    { IMarkdownDocumentChanged }
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure StartNewChat;
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GrokService, GrokConfig, GrokSettingsForm, LazIDEIntf, CompOptsIntf;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := 'grok-4';
  FContextUsed := 0;
  FContextLimit := 128000;
  FSending := False;
  FStreamingLineIndex := -1;
  FAssistantAccum := '';
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGrokChatForm.Destroy;
Begin
  If Assigned(GrokClient) Then
    GrokClient.CancelStream;
  WorkflowEventBus.RemoveListener(Self);
  Inherited Destroy;
End;

Procedure TGrokChatForm.FormCreate(Sender: TObject);
Begin
  RefreshFromConfig;
  UpdateStatusFooter;
  If Assigned(GrokChatConfig) And GrokChatConfig.IsSignedIn Then
    AppendMessage('system', 'Grok Chat ready. Signed in with SuperGrok / X Premium — send a message.')
  Else
    AppendMessage('system', 'Grok Chat ready. Open Settings and sign in with SuperGrok / X Premium, then send a message.');
  WorkflowLogger.Info('GrokChat', 'Grok Chat window created');
End;

Procedure TGrokChatForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('GrokChat', 'Grok Chat window destroyed');
End;

Procedure TGrokChatForm.RefreshFromConfig;
Begin
  If Assigned(GrokChatConfig) And Assigned(GrokClient) Then
    Begin
      GrokClient.ApplyConfig(GrokChatConfig);
      FModelName := GrokChatConfig.Model;
    End
  Else If Assigned(GrokClient) Then
    FModelName := GrokClient.Model;
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.UpdateStatusFooter;
Var
  Pct: Integer;
  StatusText: String;
Begin
  If FContextLimit > 0 Then
    Pct := (FContextUsed * 100) Div FContextLimit
  Else
    Pct := 0;
  If FSending Then
    StatusText := 'Streaming…'
  Else If Assigned(GrokChatConfig) And GrokChatConfig.IsSignedIn Then
    StatusText := 'Ready'
  Else
    StatusText := 'Not signed in';
  FStatusFooter.SetAll(
    Format('Model: %s', [FModelName]),
    Format('Context: ~%d / %d (%d%%)', [FContextUsed, FContextLimit, Pct]),
    StatusText);
End;

Procedure TGrokChatForm.SetSending(IsSending: Boolean);
Begin
  FSending := IsSending;
  FSendAction.Enabled := Not IsSending;
  FNewChatAction.Enabled := Not IsSending;
  FInputEdit.ReadOnly := IsSending;
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.AppendMessage(Const Role, Content: String);
Begin
  FChatMemo.Lines.Add('');
  FChatMemo.Lines.Add('[' + UpperCase(Role) + ']');
  FChatMemo.Lines.Add(Content);
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.BeginAssistantReply;
Begin
  FAssistantAccum := '';
  FChatMemo.Lines.Add('');
  FChatMemo.Lines.Add('[ASSISTANT]');
  FChatMemo.Lines.Add('');
  FStreamingLineIndex := FChatMemo.Lines.Count - 1;
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.AppendAssistantToken(Const Token: String);
Var
  I: Integer;
  Parts: TStringList;
Begin
  If FStreamingLineIndex < 0 Then
    BeginAssistantReply;
  If Pos(#10, Token) > 0 Then
    Begin
      Parts := TStringList.Create;
      Try
        Parts.Text := StringReplace(Token, #13#10, #10, [rfReplaceAll]);
        If Parts.Count = 0 Then
          Exit;
        FChatMemo.Lines[FStreamingLineIndex] := FChatMemo.Lines[FStreamingLineIndex] + Parts[0];
        For I := 1 To Parts.Count - 1 Do
          Begin
            FChatMemo.Lines.Add(Parts[I]);
            FStreamingLineIndex := FChatMemo.Lines.Count - 1;
          End;
      Finally
        Parts.Free;
      End;
    End
  Else
    FChatMemo.Lines[FStreamingLineIndex] := FChatMemo.Lines[FStreamingLineIndex] + Token;
  FAssistantAccum := FAssistantAccum + Token;
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.FinishAssistantReply(Const ErrorText: String);
Begin
  If ErrorText <> '' Then
    Begin
      If FAssistantAccum = '' Then
        Begin
          If FStreamingLineIndex >= 0 Then
            FChatMemo.Lines[FStreamingLineIndex] := '(error)'
          Else
            AppendMessage('assistant', '(error)');
        End;
      AppendMessage('system', 'Error: ' + ErrorText);
      FStatusFooter.SetRightText('Error');
    End
  Else
    Begin
      If Assigned(GrokClient) And (FAssistantAccum <> '') Then
        GrokClient.AddMessage(gmrAssistant, FAssistantAccum);
      FContextUsed := FContextUsed + Length(FAssistantAccum) Div 4 + 20;
      FStatusFooter.SetRightText('Ready');
    End;
  FStreamingLineIndex := -1;
  FAssistantAccum := '';
  If Assigned(GrokClient) Then
    GrokClient.MarkStreamComplete;
  SetSending(False);
End;

Procedure TGrokChatForm.StreamToken(Const Token: String; IsFinished: Boolean;
  Const ErrorText: String);
Begin
  { Invoked on the main thread via Synchronize from the stream worker. }
  If Not IsFinished Then
    Begin
      If Token <> '' Then
        AppendAssistantToken(Token);
      Exit;
    End;
  FinishAssistantReply(ErrorText);
End;

Procedure TGrokChatForm.SendActionExecute(Sender: TObject);
Var
  UserText: String;
Begin
  If FSending Then
    Exit;
  UserText := Trim(FInputEdit.Text);
  If UserText = '' Then
    Exit;
  If (Not Assigned(GrokChatConfig)) Or (Not GrokChatConfig.IsSignedIn) Then
    Begin
      MessageDlg('Sign in with SuperGrok / X Premium in Settings before sending.', mtInformation, [mbOK], 0);
      SettingsActionExecute(Nil);
      Exit;
    End;
  If Not Assigned(GrokClient) Then
    Exit;

  RefreshFromConfig;
  AppendMessage('user', UserText);
  FInputEdit.Clear;
  GrokClient.AddMessage(gmrUser, UserText);
  FContextUsed := FContextUsed + Length(UserText) Div 4 + 8;
  BeginAssistantReply;
  SetSending(True);
  FStatusFooter.SetRightText('Streaming…');

  If Not GrokClient.StartStream(@StreamToken) Then
    Begin
      FinishAssistantReply(GrokClient.LastError);
      Exit;
    End;
End;

Procedure TGrokChatForm.StartNewChat;
Begin
  If FSending And Assigned(GrokClient) Then
    GrokClient.CancelStream;
  SetSending(False);
  FChatMemo.Clear;
  FContextUsed := 0;
  FStreamingLineIndex := -1;
  FAssistantAccum := '';
  If Assigned(GrokClient) Then
    GrokClient.ClearHistory;
  AppendMessage('system', 'New conversation started.');
  UpdateStatusFooter;
End;

Procedure TGrokChatForm.NewChatActionExecute(Sender: TObject);
Begin
  StartNewChat;
End;

Procedure TGrokChatForm.BuildActionExecute(Sender: TObject);
Begin
  FStatusFooter.SetRightText('Building…');
  If Assigned(LazarusIDE) Then
    LazarusIDE.DoBuildProject(crCompile, [])
  Else
    Begin
      AppendMessage('system', 'LazarusIDE not available – cannot build.');
      FStatusFooter.SetRightText('Ready');
    End;
End;

Procedure TGrokChatForm.SettingsActionExecute(Sender: TObject);
Begin
  ShowGrokSettingsForm;
  RefreshFromConfig;
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
