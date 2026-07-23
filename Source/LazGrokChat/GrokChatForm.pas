Unit GrokChatForm;

{ Main Grok chat window with history, input and status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, WorkflowEvents, StatusFooterFrame, CompOptsIntf,
  IDEExternToolIntf;

Type
  TGrokChatForm = Class(TForm, IWorkflowListener, ICompilerFinished, IMarkdownDocumentChanged)
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FStopAction: TAction;
    FReviewCompileAction: TAction;
    FReviewBuildAction: TAction;
    FFixErrorAction: TAction;
    FSettingsAction: TAction;
    FToolBar: TToolBar;
    ToolButtonNewChat: TToolButton;
    ToolButtonSep: TToolButton;
    ToolButtonReviewCompile: TToolButton;
    ToolButtonReviewBuild: TToolButton;
    ToolButtonFixError: TToolButton;
    ToolButtonSep2: TToolButton;
    ToolButtonSettings: TToolButton;
    FStatusFooter: TStatusFooterFrame;
    FInputPanel: TPanel;
    FSendButton: TButton;
    FStopButton: TButton;
    FInputEdit: TMemo;
    FChatHost: TPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure ReviewCompileActionExecute(Sender: TObject);
    Procedure ReviewBuildActionExecute(Sender: TObject);
    Procedure FixErrorActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
  Private
    FElapsedTimer: TTimer;
    FChatView: TControl; { TMarkDownControl created at runtime. }
    FTranscript: TStringList; { Finished messages as Markdown source. }
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingActive: Boolean; { True while assistant reply is streaming. }
    FUserCancelled: Boolean;
    FAssistantContent: String; { Final answer channel (history). }
    FAssistantThinking: String; { Reasoning stream (display only). }
    FReviewInProgress: Boolean;
    FStreamStart: TDateTime;
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
    FLastChatPaintTick: QWord;
    FSessionProjectKey: String; { ProjectInfoFile used for last save/load. }
    Procedure UpdateStatusFooter;
    Function FormatElapsedStatus(Const Phase: String): String;
    Procedure SetStreamPhase(Const Phase: String);
    Procedure SetSending(IsSending: Boolean);
    Procedure ElapsedTimerTimer(Sender: TObject);
    Procedure EnsureChatView;
    Procedure ScrollChatToEnd;
    Procedure RefreshChatDisplay(Force: Boolean);
    Function RoleHeading(Const Role: String): String;
    Function QuoteMarkdownLines(Const TextValue: String): String;
    Function FormatAssistantMarkdown(Const Thinking, Content: String): String;
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Procedure ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
    Procedure FinishAssistantReply(Const ErrorText: String);
    Procedure StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
      IsFinished: Boolean; Const ErrorText: String);
    Procedure RefreshFromConfig;
    Procedure PersistSession;
    Procedure RestoreSessionIfNeeded;
    Function CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
    Procedure ReviewProject(Reason: TCompileReason; Const KindLabel: String);
    Function BuildReviewPrompt(Const KindLabel, OutputText: String;
      ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
    Function BuildFixErrorPromptForLine(Line: TMessageLine): String;
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
    Procedure FixSelectedError;
    Procedure StopStream;
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GrokService, GrokConfig, GrokSettingsForm, GrokIDEContext, GrokSession,
  LazIDEIntf, IDEMsgIntf, MarkDown.Control, SrcEditorIntf, ProjectIntf;

Const
  ChatViewMargin = 4;
  ChatPaintMinIntervalMs = 80;

Constructor TGrokChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := GrokConfigDefaultModel;
  FContextUsed := 0;
  FContextLimit := 128000;
  FSending := False;
  FStreamingActive := False;
  FUserCancelled := False;
  FAssistantContent := '';
  FAssistantThinking := '';
  FReviewInProgress := False;
  FStreamStart := 0;
  FStatusPhase := '';
  FLastChatPaintTick := 0;
  FSessionProjectKey := '';
  FChatView := Nil;
  FTranscript := TStringList.Create;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGrokChatForm.Destroy;
Begin
  If Assigned(GrokClient) Then
    GrokClient.CancelStream;
  PersistSession;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FTranscript);
  Inherited Destroy;
End;

Procedure TGrokChatForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Chat';
  EnsureChatView;
  If Not Assigned(FElapsedTimer) Then
    Begin
      FElapsedTimer := TTimer.Create(Self);
      FElapsedTimer.Enabled := False;
      FElapsedTimer.Interval := 250;
      FElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  RefreshFromConfig;
  UpdateStatusFooter;
  RestoreSessionIfNeeded;
  If FTranscript.Count = 0 Then
    Begin
      If Assigned(GrokChatConfig) And GrokChatConfig.IsSignedIn Then
        AppendMessage('system', 'Project Chat ready. Signed in with SuperGrok / X Premium — send a message.')
      Else
        AppendMessage('system', 'Project Chat ready. Open Settings and sign in with SuperGrok / X Premium, then send a message.');
    End
  Else
    RefreshChatDisplay(True);
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
  FStopAction.Enabled := IsSending;
  FNewChatAction.Enabled := Not IsSending;
  FReviewCompileAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FReviewBuildAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FFixErrorAction.Enabled := Not IsSending;
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

Procedure TGrokChatForm.PersistSession;
Var
  Key: String;
Begin
  If FSending Then
    Exit;
  Key := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Key := LazarusIDE.ActiveProject.ProjectInfoFile;
  If Key = '' Then
    Exit;
  FSessionProjectKey := Key;
  SaveProjectChatSession(FTranscript, FContextUsed);
End;

Procedure TGrokChatForm.RestoreSessionIfNeeded;
Var
  Key: String;
  LoadedContext: Integer;
Begin
  Key := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Key := LazarusIDE.ActiveProject.ProjectInfoFile;
  If Key = '' Then
    Exit;
  If SameText(Key, FSessionProjectKey) And (FTranscript.Count > 0) Then
    Exit;
  FSessionProjectKey := Key;
  If LoadProjectChatSession(FTranscript, LoadedContext) Then
    Begin
      FContextUsed := LoadedContext;
      RefreshChatDisplay(True);
      UpdateStatusFooter;
    End;
End;

Procedure TGrokChatForm.EnsureChatView;
Var
  View: TMarkDownControl;
Begin
  If Assigned(FChatView) Then
    Exit;
  FChatHost.Color := clWhite;
  FChatHost.ParentColor := False;
  FChatHost.ParentBackground := False;
  View := TMarkDownControl.Create(Self);
  View.Parent := FChatHost;
  View.Align := alClient;
  View.BorderSpacing.Around := ChatViewMargin;
  View.Color := clWhite;
  View.ParentColor := False;
  View.ParentBackground := False;
  View.ScrollBars := ssAutoBoth;
  View.MonoFontName := 'Monospace';
  View.FontName := 'default';
  View.Visible := True;
  FChatView := View;
End;

Procedure TGrokChatForm.ScrollChatToEnd;
Var
  View: TMarkDownControl;
Begin
  If Not Assigned(FChatView) Then
    Exit;
  View := TMarkDownControl(FChatView);
  { Setter clamps to max scroll. }
  View.ScrolledTop := High(Integer) Div 4;
End;

Procedure TGrokChatForm.RefreshChatDisplay(Force: Boolean);
Var
  View: TMarkDownControl;
  Body: String;
  NowTick: QWord;
Begin
  EnsureChatView;
  NowTick := GetTickCount64;
  If (Not Force) And FStreamingActive And (FLastChatPaintTick > 0) And
    (NowTick - FLastChatPaintTick < ChatPaintMinIntervalMs) Then
    Exit;
  FLastChatPaintTick := NowTick;

  Body := FTranscript.Text;
  If FStreamingActive Then
    Begin
      If Body <> '' Then
        Body := Body + LineEnding + LineEnding;
      Body := Body + '### Assistant' + LineEnding + LineEnding +
        FormatAssistantMarkdown(FAssistantThinking, FAssistantContent);
    End;

  View := TMarkDownControl(FChatView);
  Try
    View.MarkDown.BeginUpdate;
    Try
      View.MarkDown.Text := Body;
    Finally
      View.MarkDown.EndUpdate;
    End;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GrokChat', 'Chat Markdown render failed: ' + E.Message);
  End;
  ScrollChatToEnd;
End;

Function TGrokChatForm.RoleHeading(Const Role: String): String;
Var
  R: String;
Begin
  R := LowerCase(Trim(Role));
  If R = 'user' Then
    Result := 'User'
  Else If R = 'assistant' Then
    Result := 'Assistant'
  Else If R = 'system' Then
    Result := 'System'
  Else If R = 'tool' Then
    Result := 'Tool'
  Else
    Result := Role;
End;

Function TGrokChatForm.QuoteMarkdownLines(Const TextValue: String): String;
Var
  SL: TStringList;
  I: Integer;
  Line: String;
Begin
  { Blockquote each line so thinking reads as a secondary section. }
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(TextValue, #13#10, #10, [rfReplaceAll]);
    SL.Text := StringReplace(SL.Text, #13, #10, [rfReplaceAll]);
    Result := '';
    For I := 0 To SL.Count - 1 Do
      Begin
        Line := SL[I];
        If Result <> '' Then
          Result := Result + LineEnding;
        If Line = '' Then
          Result := Result + '>'
        Else
          Result := Result + '> ' + Line;
      End;
    If Result = '' Then
      Result := '>';
  Finally
    SL.Free;
  End;
End;

Function TGrokChatForm.FormatAssistantMarkdown(Const Thinking, Content: String): String;
Begin
  { Thinking is display-only; Content is the final answer (API history). }
  If (Thinking = '') And (Content = '') Then
    Begin
      Result := '*Waiting for model…*';
      Exit;
    End;
  If Thinking <> '' Then
    Begin
      Result := '> **Thinking**' + LineEnding + '>' + LineEnding + QuoteMarkdownLines(Thinking);
      If Content <> '' Then
        Result := Result + LineEnding + LineEnding + Content
      Else
        Result := Result + LineEnding + LineEnding + '*Waiting for answer…*';
    End
  Else
    Result := Content;
End;

Procedure TGrokChatForm.AppendMessage(Const Role, Content: String);
Begin
  If FTranscript.Count > 0 Then
    FTranscript.Add('');
  FTranscript.Add('### ' + RoleHeading(Role));
  FTranscript.Add('');
  If Content <> '' Then
    FTranscript.Add(Content)
  Else
    FTranscript.Add('');
  RefreshChatDisplay(True);
End;

Procedure TGrokChatForm.BeginAssistantReply;
Begin
  FAssistantContent := '';
  FAssistantThinking := '';
  FUserCancelled := False;
  FStreamingActive := True;
  FLastChatPaintTick := 0;
  RefreshChatDisplay(True);
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
  RefreshChatDisplay(False);
End;

Procedure TGrokChatForm.FinishAssistantReply(Const ErrorText: String);
Var
  DisplayBody: String;
Begin
  If FUserCancelled Then
    Begin
      { StopStream already cleaned UI and cancelled the worker. }
      FUserCancelled := False;
      If Assigned(GrokClient) Then
        GrokClient.MarkStreamComplete;
      SetSending(False);
      Exit;
    End;
  If FStreamingActive Then
    Begin
      If (ErrorText <> '') And (FAssistantContent = '') And (FAssistantThinking = '') Then
        DisplayBody := '*(error)*'
      Else
        DisplayBody := FormatAssistantMarkdown(FAssistantThinking, FAssistantContent);
      If FTranscript.Count > 0 Then
        FTranscript.Add('');
      FTranscript.Add('### Assistant');
      FTranscript.Add('');
      FTranscript.Add(DisplayBody);
    End
  Else If (ErrorText <> '') And (FAssistantContent = '') Then
    AppendMessage('assistant', '*(error)*');

  If ErrorText <> '' Then
    Begin
      AppendMessage('system', '**Error:** ' + ErrorText);
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
  FAssistantContent := '';
  FAssistantThinking := '';
  RefreshChatDisplay(True);
  If Assigned(GrokClient) Then
    GrokClient.MarkStreamComplete;
  SetSending(False);
  PersistSession;
End;

Procedure TGrokChatForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Begin
  { Invoked on the main thread via Synchronize from the stream worker.
    Thinking streams first on reasoning models; content is the final answer. }
  If FUserCancelled Then
    Begin
      If IsFinished Then
        Begin
          FUserCancelled := False;
          If Assigned(GrokClient) Then
            GrokClient.MarkStreamComplete;
          SetSending(False);
        End;
      Exit;
    End;
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

Procedure TGrokChatForm.StopStream;
Var
  DisplayBody: String;
Begin
  If Not FSending Then
    Exit;
  FUserCancelled := True;
  If Assigned(GrokClient) Then
    GrokClient.CancelStream;
  If FStreamingActive Then
    Begin
      If (FAssistantContent <> '') Or (FAssistantThinking <> '') Then
        Begin
          DisplayBody := FormatAssistantMarkdown(FAssistantThinking, FAssistantContent) +
            LineEnding + LineEnding + '*[stream cancelled]*';
          If FTranscript.Count > 0 Then
            FTranscript.Add('');
          FTranscript.Add('### Assistant');
          FTranscript.Add('');
          FTranscript.Add(DisplayBody);
          If Assigned(GrokClient) And (FAssistantContent <> '') Then
            GrokClient.AddMessage(gmrAssistant, FAssistantContent);
          FContextUsed := FContextUsed + Length(FAssistantContent) Div 4 + 20;
        End
      Else
        AppendMessage('system', '*Stream cancelled before the first token.*');
    End
  Else
    AppendMessage('system', '*Stream cancelled.*');
  FStreamingActive := False;
  FAssistantContent := '';
  FAssistantThinking := '';
  RefreshChatDisplay(True);
  SetSending(False);
  FStatusFooter.SetRightText('Cancelled');
  PersistSession;
  WorkflowLogger.Info('GrokChat', 'Stream cancelled by user');
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

Procedure TGrokChatForm.StopActionExecute(Sender: TObject);
Begin
  StopStream;
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
  If FSending Then
    StopStream;
  SetSending(False);
  FTranscript.Clear;
  FContextUsed := 0;
  FStreamingActive := False;
  FUserCancelled := False;
  FAssistantContent := '';
  FAssistantThinking := '';
  FLastChatPaintTick := 0;
  If Assigned(GrokClient) Then
    GrokClient.ClearHistory;
  ClearProjectChatSession;
  AppendMessage('system', 'New conversation started.');
  PersistSession;
  UpdateStatusFooter;
End;

Function ExtractSourceSnippet(Const FileName: String; LineNo, Radius: Integer): String;
Var
  SL: TStringList;
  First, Last, I: Integer;
  Path: String;
Begin
  Result := '';
  Path := Trim(FileName);
  If (Path = '') Or (Not FileExists(Path)) Then
    Exit;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Path);
    Except
      Exit;
    End;
    If SL.Count = 0 Then
      Exit;
    If LineNo < 1 Then
      LineNo := 1;
    First := LineNo - Radius;
    If First < 1 Then
      First := 1;
    Last := LineNo + Radius;
    If Last > SL.Count Then
      Last := SL.Count;
    Result := Format('Source context (%s lines %d–%d):', [ExtractFileName(Path), First, Last]) +
      LineEnding + '```pascal' + LineEnding;
    For I := First To Last Do
      Begin
        If I = LineNo Then
          Result := Result + Format('%5d > %s', [I, SL[I - 1]]) + LineEnding
        Else
          Result := Result + Format('%5d | %s', [I, SL[I - 1]]) + LineEnding;
      End;
    Result := Result + '```';
  Finally
    SL.Free;
  End;
End;

Function TGrokChatForm.BuildFixErrorPromptForLine(Line: TMessageLine): String;
Var
  MsgText, FileName, Snippet: String;
  LineNo, Col: Integer;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  MsgText := FormatMessageLine(Line);
  FileName := '';
  LineNo := Line.Line;
  Col := Line.Column;
  If Line.Filename <> '' Then
    FileName := Line.GetFullFilename;
  Snippet := '';
  If (FileName <> '') And (LineNo > 0) Then
    Snippet := ExtractSourceSnippet(FileName, LineNo, 18);
  Result :=
    'Please fix this Free Pascal / Lazarus compiler message.' + LineEnding +
    LineEnding +
    'Message: ' + MsgText + LineEnding;
  If FileName <> '' Then
    Result := Result + 'File: ' + FileName + LineEnding;
  If LineNo > 0 Then
    Result := Result + Format('Location: line %d, column %d', [LineNo, Col]) + LineEnding;
  Result := Result + LineEnding;
  If Snippet <> '' Then
    Result := Result + Snippet + LineEnding + LineEnding;
  Result := Result +
    'Explain the error briefly, then propose a concrete fix (show the corrected code snippet).' + LineEnding +
    'Prefer the smallest change that resolves the issue.';
End;

Procedure TGrokChatForm.FixSelectedError;
Var
  Line: TMessageLine;
  Prompt: String;
  Col, TopLine: Integer;
Begin
  If FSending Then
    Exit;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      MessageDlg('The IDE Messages window is not available.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Line := IDEMessagesWindow.GetSelectedLine;
  If Not Assigned(Line) Then
    Begin
      MessageDlg('Select a compiler message in the Messages window first, then choose Fix Error.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildFixErrorPromptForLine(Line);
  If Prompt = '' Then
    Exit;
  If (Line.Filename <> '') And (Line.Line > 0) And Assigned(LazarusIDE) Then
    Begin
      Col := Line.Column;
      If Col < 1 Then
        Col := 1;
      TopLine := Line.Line - 8;
      If TopLine < 1 Then
        TopLine := 1;
      LazarusIDE.DoOpenFileAndJumpToPos(Line.GetFullFilename,
        Point(Col, Line.Line), TopLine, -1, -1, [ofOnlyIfExists, ofRegularFile]);
    End;
  SubmitUserText(Prompt, True);
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

Procedure TGrokChatForm.FixErrorActionExecute(Sender: TObject);
Begin
  FixSelectedError;
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
