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
    FElapsedTimer: TTimer;
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingActive: Boolean; { True while assistant reply is streaming. }
    FChatPreamble: String; { Frozen chat text through [ASSISTANT] header. }
    FAssistantContent: String; { Final answer channel (history). }
    FAssistantThinking: String; { Reasoning stream (display only). }
    FReviewInProgress: Boolean;
    FStreamStart: TDateTime;
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
    Procedure UpdateStatusFooter;
    Function FormatElapsedStatus(Const Phase: String): String;
    Procedure SetStreamPhase(Const Phase: String);
    Procedure SetSending(IsSending: Boolean);
    Procedure ElapsedTimerTimer(Sender: TObject);
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Function FormatAssistantBody(Const Thinking, Content: String): String;
    Procedure RefreshAssistantStreamingDisplay;
    Procedure ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
    Procedure FinishAssistantReply(Const ErrorText: String);
    Procedure StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
      IsFinished: Boolean; Const ErrorText: String);
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
  WorkflowLog, GrokService, GrokConfig, GrokSettingsForm, GrokIDEContext, LazIDEIntf,
  IDEMsgIntf, IDEExternToolIntf;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := GrokConfigDefaultModel;
  FContextUsed := 0;
  FContextLimit := 128000;
  FSending := False;
  FStreamingActive := False;
  FChatPreamble := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  FReviewInProgress := False;
  FStreamStart := 0;
  FStatusPhase := '';
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
  Caption := 'Project Chat';
  { WordWrap + Lines[] is a classic corruption source while streaming. }
  FChatMemo.WordWrap := False;
  FChatMemo.ScrollBars := ssAutoBoth;
  If Not Assigned(FElapsedTimer) Then
    Begin
      FElapsedTimer := TTimer.Create(Self);
      FElapsedTimer.Enabled := False;
      FElapsedTimer.Interval := 250;
      FElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  RefreshFromConfig;
  UpdateStatusFooter;
  If Assigned(GrokChatConfig) And GrokChatConfig.IsSignedIn Then
    AppendMessage('system', 'Project Chat ready. Signed in with SuperGrok / X Premium — send a message.')
  Else
    AppendMessage('system', 'Project Chat ready. Open Settings and sign in with SuperGrok / X Premium, then send a message.');
  WorkflowLogger.Info('GrokChat', 'Project Chat window created');
End;

Procedure TGrokChatForm.FormDestroy(Sender: TObject);
Begin
  If Assigned(FElapsedTimer) Then
    FElapsedTimer.Enabled := False;
  WorkflowLogger.Info('GrokChat', 'Project Chat window destroyed');
End;

Function TGrokChatForm.FormatElapsedStatus(Const Phase: String): String;
Var
  Secs, Mins, Rem: Integer;
Begin
  If FStreamStart <= 0 Then
    Begin
      Result := Phase;
      Exit;
    End;
  Secs := Round((Now - FStreamStart) * 24 * 60 * 60);
  If Secs < 0 Then
    Secs := 0;
  Mins := Secs Div 60;
  Rem := Secs Mod 60;
  Result := Format('%s %d:%2.2d', [Phase, Mins, Rem]);
End;

Procedure TGrokChatForm.SetStreamPhase(Const Phase: String);
Begin
  FStatusPhase := Phase;
  FStatusFooter.SetRightText(FormatElapsedStatus(Phase));
End;

Procedure TGrokChatForm.ElapsedTimerTimer(Sender: TObject);
Begin
  If FSending And (FStatusPhase <> '') Then
    FStatusFooter.SetRightText(FormatElapsedStatus(FStatusPhase));
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
    Begin
      If FStatusPhase = '' Then
        FStatusPhase := 'Waiting for first token…';
      StatusText := FormatElapsedStatus(FStatusPhase);
    End
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
  If IsSending Then
    Begin
      FStreamStart := Now;
      If FStatusPhase = '' Then
        FStatusPhase := 'Waiting for first token…';
      If Assigned(FElapsedTimer) Then
        FElapsedTimer.Enabled := True;
    End
  Else
    Begin
      If Assigned(FElapsedTimer) Then
        FElapsedTimer.Enabled := False;
      FStatusPhase := '';
      FStreamStart := 0;
    End;
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
  FAssistantContent := '';
  FAssistantThinking := '';
  { Freeze everything up to and including the [ASSISTANT] header. Streaming
    updates replace the whole memo as preamble + body — no Lines[] surgery. }
  FChatMemo.Lines.Add('');
  FChatMemo.Lines.Add('[ASSISTANT]');
  FChatPreamble := FChatMemo.Text;
  If (FChatPreamble <> '') And
    (FChatPreamble[Length(FChatPreamble)] <> #10) And
    (FChatPreamble[Length(FChatPreamble)] <> #13) Then
    FChatPreamble := FChatPreamble + LineEnding;
  FStreamingActive := True;
  FChatMemo.Text := FChatPreamble + '(waiting for model…)';
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Function TGrokChatForm.FormatAssistantBody(Const Thinking, Content: String): String;
Begin
  { Thinking is shown above the answer while (and after) streaming. Only Content
    is stored in conversation history for follow-up turns. }
  If (Thinking = '') And (Content = '') Then
    Begin
      Result := '(waiting for model…)';
      Exit;
    End;
  If Thinking <> '' Then
    Begin
      Result := '[thinking]' + LineEnding + Thinking;
      If Content <> '' Then
        Result := Result + LineEnding + LineEnding + Content
      Else
        Result := Result + LineEnding + LineEnding + '(waiting for answer…)';
    End
  Else
    Result := Content;
End;

Procedure TGrokChatForm.RefreshAssistantStreamingDisplay;
Begin
  { Atomic rewrite: frozen preamble + full assistant body so far. }
  If Not FStreamingActive Then
    Exit;
  FChatMemo.Text := FChatPreamble + FormatAssistantBody(FAssistantThinking, FAssistantContent);
  FChatMemo.SelStart := Length(FChatMemo.Text);
End;

Procedure TGrokChatForm.ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
Begin
  If Not FStreamingActive Then
    BeginAssistantReply;
  FAssistantContent := ContentSnapshot;
  FAssistantThinking := ThinkingSnapshot;
  If FAssistantContent <> '' Then
    SetStreamPhase('Streaming…')
  Else If FAssistantThinking <> '' Then
    SetStreamPhase('Thinking…')
  Else
    SetStreamPhase('Waiting for first token…');
  RefreshAssistantStreamingDisplay;
End;

Procedure TGrokChatForm.FinishAssistantReply(Const ErrorText: String);
Begin
  If FStreamingActive Then
    Begin
      If (ErrorText <> '') And (FAssistantContent = '') And (FAssistantThinking = '') Then
        FChatMemo.Text := FChatPreamble + '(error)'
      Else
        RefreshAssistantStreamingDisplay;
    End
  Else If (ErrorText <> '') And (FAssistantContent = '') Then
    AppendMessage('assistant', '(error)');

  If ErrorText <> '' Then
    Begin
      AppendMessage('system', 'Error: ' + ErrorText);
      FStatusFooter.SetRightText('Error');
    End
  Else
    Begin
      { History stores the final answer only — not the thinking trace. }
      If Assigned(GrokClient) And (FAssistantContent <> '') Then
        GrokClient.AddMessage(gmrAssistant, FAssistantContent);
      FContextUsed := FContextUsed + Length(FAssistantContent) Div 4 + 20;
      If FAssistantThinking <> '' Then
        FContextUsed := FContextUsed + Length(FAssistantThinking) Div 4;
      FStatusFooter.SetRightText('Ready');
    End;
  FStreamingActive := False;
  FChatPreamble := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  If Assigned(GrokClient) Then
    GrokClient.MarkStreamComplete;
  SetSending(False);
End;

Procedure TGrokChatForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Begin
  { Invoked on the main thread via Synchronize from the stream worker.
    Thinking streams first on reasoning models; content is the final answer. }
  If Not IsFinished Then
    Begin
      ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
      Exit;
    End;
  { Final empty emit may still carry last snapshots already applied. }
  If (ContentSnapshot <> '') Or (ThinkingSnapshot <> '') Then
    ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
  FinishAssistantReply(ErrorText);
End;

Procedure TGrokChatForm.SubmitUserText(Const UserText: String; AutoSend: Boolean);
Var
  ApiText, ContextBlock: String;
  WithContext: Boolean;
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
      ApiText := UserText;
      WithContext := Assigned(GrokChatConfig) And GrokChatConfig.IncludeIDEContext;
      If WithContext Then
        Begin
          ContextBlock := BuildIDEContextBlock;
          ApiText := UserText + LineEnding + LineEnding + ContextBlock;
          AppendMessage('user', UserText + LineEnding + '(IDE context attached: active editor + project files)');
        End
      Else
        AppendMessage('user', UserText);
      GrokClient.AddMessage(gmrUser, ApiText);
      FContextUsed := FContextUsed + Length(ApiText) Div 4 + 8;
      BeginAssistantReply;
      FStatusPhase := 'Waiting for first token…';
      SetSending(True);
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
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
  FStreamingActive := False;
  FChatPreamble := '';
  FAssistantContent := '';
  FAssistantThinking := '';
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
