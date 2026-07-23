Unit GrokChatForm;

{ Main Grok chat window with history, input and status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, WorkflowEvents, StatusFooterFrame, CompOptsIntf;

Type
  TGrokChatForm = Class(TForm, IWorkflowListener, ICompilerFinished, IMarkdownDocumentChanged)
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FReviewCompileAction: TAction;
    FReviewBuildAction: TAction;
    FSettingsAction: TAction;
    FToolBar: TToolBar;
    ToolButtonNewChat: TToolButton;
    ToolButtonSep: TToolButton;
    ToolButtonReviewCompile: TToolButton;
    ToolButtonReviewBuild: TToolButton;
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
    Procedure ReviewCompileActionExecute(Sender: TObject);
    Procedure ReviewBuildActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
  Private
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingHeaderIndex: Integer; { Line index of [ASSISTANT]; content follows. }
    FAssistantAccum: String;
    FReviewInProgress: Boolean;
    Procedure UpdateStatusFooter;
    Procedure SetSending(IsSending: Boolean);
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Procedure RefreshAssistantStreamingDisplay;
    Procedure AppendAssistantToken(Const Token: String);
    Procedure FinishAssistantReply(Const ErrorText: String);
    Procedure StreamToken(Const Token: String; IsFinished: Boolean; Const ErrorText: String);
    Procedure RefreshFromConfig;
    Function CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
    Procedure ReviewProject(Reason: TCompileReason; Const KindLabel: String);
    Function BuildReviewPrompt(Const KindLabel, OutputText: String;
      ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
    Procedure SubmitUserText(Const UserText: String; AutoSend: Boolean);
    { ICompilerFinished – reserved for external bus notifications; review uses IDE API directly. }
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    { IMarkdownDocumentChanged }
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure StartNewChat;
    Procedure ReviewCompile;
    Procedure ReviewBuild;
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GrokService, GrokConfig, GrokSettingsForm, LazIDEIntf, IDEMsgIntf,
  IDEExternToolIntf;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := 'grok-4';
  FContextUsed := 0;
  FContextLimit := 128000;
  FSending := False;
  FStreamingHeaderIndex := -1;
  FAssistantAccum := '';
  FReviewInProgress := False;
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
  Else If FReviewInProgress Then
    StatusText := 'Reviewing…'
  Else If Assigned(GrokChatConfig) And GrokChatConfig.IsSignedIn Then
    StatusText := 'Ready'
  Else
    StatusText := 'Not signed in';
  If Assigned(GrokChatConfig) And (GrokChatConfig.ActiveSkill <> '') Then
    FStatusFooter.SetAll(
      Format('Model: %s | Skill: %s', [FModelName, GrokChatConfig.ActiveSkill]),
      Format('Context: ~%d / %d (%d%%)', [FContextUsed, FContextLimit, Pct]),
      StatusText)
  Else
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
  FReviewCompileAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FReviewBuildAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
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
  FStreamingHeaderIndex := FChatMemo.Lines.Count - 1;
  FChatMemo.Lines.Add('');
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.RefreshAssistantStreamingDisplay;
Var
  Content, Line: String;
  StartIdx, I, P: Integer;
Begin
  { Rebuild the assistant body from FAssistantAccum. Incremental Lines[i] += token
    mishandles newlines (TStringList.Text drops trailing breaks) and can leave a
    trail of partial rewrites when multi-line deltas arrive. }
  If FStreamingHeaderIndex < 0 Then
    Exit;
  StartIdx := FStreamingHeaderIndex + 1;
  While FChatMemo.Lines.Count > StartIdx Do
    FChatMemo.Lines.Delete(FChatMemo.Lines.Count - 1);

  Content := StringReplace(FAssistantAccum, #13#10, #10, [rfReplaceAll]);
  Content := StringReplace(Content, #13, #10, [rfReplaceAll]);
  If Content = '' Then
    Begin
      FChatMemo.Lines.Add('');
      Exit;
    End;

  I := 1;
  While I <= Length(Content) Do
    Begin
      P := Pos(#10, Copy(Content, I, MaxInt));
      If P = 0 Then
        Begin
          Line := Copy(Content, I, MaxInt);
          FChatMemo.Lines.Add(Line);
          Break;
        End;
      Line := Copy(Content, I, P - 1);
      FChatMemo.Lines.Add(Line);
      I := I + P;
      { Preserve a trailing newline as an extra empty line. }
      If I > Length(Content) Then
        FChatMemo.Lines.Add('');
    End;
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.AppendAssistantToken(Const Token: String);
Begin
  If Token = '' Then
    Exit;
  If FStreamingHeaderIndex < 0 Then
    BeginAssistantReply;
  FAssistantAccum := FAssistantAccum + Token;
  RefreshAssistantStreamingDisplay;
End;

Procedure TGrokChatForm.FinishAssistantReply(Const ErrorText: String);
Begin
  If FStreamingHeaderIndex >= 0 Then
    RefreshAssistantStreamingDisplay;
  If ErrorText <> '' Then
    Begin
      If FAssistantAccum = '' Then
        Begin
          If FStreamingHeaderIndex >= 0 Then
            Begin
              While FChatMemo.Lines.Count > FStreamingHeaderIndex + 1 Do
                FChatMemo.Lines.Delete(FChatMemo.Lines.Count - 1);
              FChatMemo.Lines.Add('(error)');
            End
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
  FStreamingHeaderIndex := -1;
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

Procedure TGrokChatForm.SubmitUserText(Const UserText: String; AutoSend: Boolean);
Begin
  If Trim(UserText) = '' Then
    Exit;
  If FSending Then
    Exit;
  If AutoSend Then
    Begin
      If (Not Assigned(GrokChatConfig)) Or (Not GrokChatConfig.IsSignedIn) Then
        Begin
          AppendMessage('user', UserText);
          AppendMessage('system', 'Sign in under Settings to send this review to Grok.');
          Exit;
        End;
      If Not Assigned(GrokClient) Then
        Exit;
      RefreshFromConfig;
      AppendMessage('user', UserText);
      GrokClient.AddMessage(gmrUser, UserText);
      FContextUsed := FContextUsed + Length(UserText) Div 4 + 8;
      BeginAssistantReply;
      SetSending(True);
      FStatusFooter.SetRightText('Streaming…');
      If Not GrokClient.StartStream(@StreamToken) Then
        FinishAssistantReply(GrokClient.LastError);
    End
  Else
    AppendMessage('user', UserText);
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
  FInputEdit.Clear;
  SubmitUserText(UserText, True);
End;

Function FormatMessageLine(Line: TMessageLine): String;
Var
  Loc: String;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  If Trim(Line.OriginalLine) <> '' Then
    Begin
      Result := Line.OriginalLine;
      Exit;
    End;
  Loc := '';
  If Line.Filename <> '' Then
    Begin
      Loc := Line.GetFullFilename;
      If Line.Line > 0 Then
        Begin
          Loc := Loc + '(' + IntToStr(Line.Line);
          If Line.Column > 0 Then
            Loc := Loc + ',' + IntToStr(Line.Column);
          Loc := Loc + ')';
        End;
    End;
  If Loc <> '' Then
    Result := Loc + ' '
  Else
    Result := '';
  If Line.Urgency In [mluHint..mluPanic] Then
    Result := Result + MessageLineUrgencyNames[Line.Urgency] + ': ';
  If Line.TranslatedMsg <> '' Then
    Result := Result + Line.TranslatedMsg
  Else
    Result := Result + Line.Msg;
  Result := Trim(Result);
End;

Function TGrokChatForm.CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
Var
  ViewIndex, LineIndex: Integer;
  View: TExtToolView;
  Line: TMessageLine;
  Parts: TStringList;
  Formatted: String;
Begin
  Result := '';
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      Result := '(IDE Messages window is not available.)';
      Exit;
    End;
  Parts := TStringList.Create;
  Try
    For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
      Begin
        View := IDEMessagesWindow.Views[ViewIndex];
        If Not Assigned(View) Then
          Continue;
        If View.Caption <> '' Then
          Parts.Add('--- ' + View.Caption + ' ---');
        View.Lines.EnterCriticalSection;
        Try
          For LineIndex := 0 To View.Lines.Count - 1 Do
            Begin
              Line := View.Lines.Items[LineIndex];
              If Not Assigned(Line) Then
                Continue;
              Case Line.Urgency Of
                mluError, mluFatal, mluPanic: Inc(ErrorCount);
                mluWarning: Inc(WarningCount);
                mluHint, mluNote: Inc(HintCount);
              Else
                { }
              End;
              Formatted := FormatMessageLine(Line);
              If Formatted <> '' Then
                Parts.Add(Formatted);
            End;
        Finally
          View.Lines.LeaveCriticalSection;
        End;
        If View.SummaryMsg <> '' Then
          Parts.Add(View.SummaryMsg);
      End;
    If Parts.Count = 0 Then
      Parts.Add('(No messages were recorded in the IDE Messages window.)');
    Result := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function TGrokChatForm.BuildReviewPrompt(Const KindLabel, OutputText: String;
  ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
Var
  Outcome, ProjectName: String;
Begin
  If BuildOk And (ErrorCount = 0) Then
    Outcome := 'clean (no errors)'
  Else If ErrorCount > 0 Then
    Outcome := Format('failed with %d error(s)', [ErrorCount])
  Else
    Outcome := 'completed with warnings/notes';
  ProjectName := '(unknown)';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Begin
      If Assigned(LazarusIDE.ActiveProject.MainFile) Then
        ProjectName := LazarusIDE.ActiveProject.MainFile.Filename
      Else
        ProjectName := LazarusIDE.ActiveProject.ProjectInfoFile;
    End;
  Result :=
    KindLabel + ' output for review:' + LineEnding +
    LineEnding +
    'Project: ' + ProjectName + LineEnding +
    'Outcome: ' + Outcome +
      Format(' — errors=%d, warnings=%d, hints/notes=%d', [ErrorCount, WarningCount, HintCount]) +
      LineEnding +
    LineEnding +
    '----- begin compiler/messages output -----' + LineEnding +
    OutputText + LineEnding +
    '----- end compiler/messages output -----' + LineEnding +
    LineEnding +
    'You are reviewing Free Pascal / Lazarus IDE ' + LowerCase(KindLabel) +
    ' output from my local machine (same text as the Messages window).' + LineEnding +
    'If there are errors: explain them briefly and propose concrete fixes (file, location, and change).' + LineEnding +
    'If there are warnings or hints: address only those that are practical and useful; ignore pure noise.' + LineEnding +
    'If the ' + LowerCase(KindLabel) + ' is clean (no errors and no actionable warnings), say so briefly — no further action is required.';
End;

Procedure TGrokChatForm.ReviewProject(Reason: TCompileReason; Const KindLabel: String);
Var
  BuildResult: TModalResult;
  OutputText, PromptText: String;
  ErrorCount, WarningCount, HintCount: Integer;
  BuildOk: Boolean;
Begin
  If FSending Or FReviewInProgress Then
    Exit;
  If Not Assigned(LazarusIDE) Then
    Begin
      AppendMessage('system', 'LazarusIDE not available – cannot run ' + KindLabel + '.');
      Exit;
    End;
  If Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      MessageDlg('Open a project before using Review ' + KindLabel + '.', mtInformation, [mbOK], 0);
      Exit;
    End;

  FReviewInProgress := True;
  FReviewCompileAction.Enabled := False;
  FReviewBuildAction.Enabled := False;
  FStatusFooter.SetRightText(KindLabel + '…');
  Application.ProcessMessages;
  WorkflowLogger.Info('GrokChat', 'Review ' + KindLabel + ' started');

  Try
    BuildResult := LazarusIDE.DoBuildProject(Reason, []);
    BuildOk := BuildResult = mrOk;
    OutputText := CollectIDEMessagesText(ErrorCount, WarningCount, HintCount);
    PromptText := BuildReviewPrompt(KindLabel, OutputText, ErrorCount, WarningCount, HintCount, BuildOk);

    If BuildOk And (ErrorCount = 0) Then
      FStatusFooter.SetRightText(KindLabel + ' OK')
    Else If ErrorCount > 0 Then
      FStatusFooter.SetRightText(KindLabel + ' failed')
    Else
      FStatusFooter.SetRightText(KindLabel + ' done');

    SubmitUserText(PromptText, True);
  Finally
    FReviewInProgress := False;
    If Not FSending Then
      Begin
        FReviewCompileAction.Enabled := True;
        FReviewBuildAction.Enabled := True;
        UpdateStatusFooter;
      End;
  End;
End;

Procedure TGrokChatForm.ReviewCompile;
Begin
  ReviewProject(crCompile, 'Compile');
End;

Procedure TGrokChatForm.ReviewBuild;
Begin
  ReviewProject(crBuild, 'Build');
End;

Procedure TGrokChatForm.StartNewChat;
Begin
  If FSending And Assigned(GrokClient) Then
    GrokClient.CancelStream;
  SetSending(False);
  FChatMemo.Clear;
  FContextUsed := 0;
  FStreamingHeaderIndex := -1;
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

Procedure TGrokChatForm.ReviewCompileActionExecute(Sender: TObject);
Begin
  ReviewCompile;
End;

Procedure TGrokChatForm.ReviewBuildActionExecute(Sender: TObject);
Begin
  ReviewBuild;
End;

Procedure TGrokChatForm.SettingsActionExecute(Sender: TObject);
Begin
  ShowGrokSettingsForm;
  RefreshFromConfig;
End;

Procedure TGrokChatForm.CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
  Const OutputText: String; ErrorCount, WarningCount: Integer);
Begin
  { Review Compile/Build captures Messages via the IDE API after DoBuildProject.
    This bus hook remains for future external publishers. }
  If FReviewInProgress Then
    Exit;
  Case Result Of
    crSuccess:
      FStatusFooter.SetRightText(Format('Compile OK (%d warn)', [WarningCount]));
    crFailed:
      FStatusFooter.SetRightText(Format('Compile failed (%d err)', [ErrorCount]));
    crCancelled:
      FStatusFooter.SetRightText('Cancelled');
  Else
    { }
  End;
  If OutputText <> '' Then
    WorkflowLogger.Debug('GrokChat', 'CompilerFinished for ' + ProjectFile);
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
