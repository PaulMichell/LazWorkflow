Unit AssistantHistoryTrace;

{ History list and trace replay for the project assistant (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Controls, Graphics, StdCtrls, ProjectAssistantForm;

Procedure Seam_FinishLiveTrace(Form: TProjectAssistantForm; Const SystemNote: String; DurationMs: Integer);
Function Seam_CurrentStreamDurationMs(Form: TProjectAssistantForm): Integer;
Function Seam_MonitorLiveTurnId(Form: TProjectAssistantForm): String;
Function Seam_InFlightTurnId(Form: TProjectAssistantForm): String;
Procedure Seam_RecordCurrentTurn(Form: TProjectAssistantForm; Const ErrorText: String);
Procedure Seam_EnsureFinalAssistantSummary(Form: TProjectAssistantForm);
Procedure Seam_ConversationListSelectionChange(Form: TProjectAssistantForm; Sender: TObject; User: Boolean);
Procedure Seam_ConversationListClick(Form: TProjectAssistantForm; Sender: TObject);
Procedure Seam_ApplyLoadedConversationToUi(Form: TProjectAssistantForm; Const StatusNote: String);
Procedure Seam_RebuildClientFromConversation(Form: TProjectAssistantForm);
Function Seam_BuildConversationMarkdownExport(Form: TProjectAssistantForm): String;
Function Seam_DefaultExportFileName(Form: TProjectAssistantForm): String;
Procedure Seam_UpdateHistoryActions(Form: TProjectAssistantForm);
Procedure Seam_RefreshHistoryCombo(Form: TProjectAssistantForm);
Procedure Seam_RefreshConversationList(Form: TProjectAssistantForm);
Procedure Seam_ShowLastConversationTurn(Form: TProjectAssistantForm);
Procedure Seam_ShowConversationTurn(Form: TProjectAssistantForm; TurnIndex: Integer; Navigate: Boolean);
Function Seam_ConversationListTurnIndex(Form: TProjectAssistantForm; ListIndex: Integer): Integer;
Procedure Seam_EnsureConversationStore(Form: TProjectAssistantForm);

Implementation

Uses
  SysUtils, DateUtils, Contnrs, ComCtrls, Dialogs, ExtCtrls, Forms, Clipbrd,
  WorkflowLog, AssistantConversation, AssistantTrace, AssistantTraceView, AssistantEvents, AssistantImages,
  AssistantPlan, AssistantTools, AssistantService, AssistantTurnFinish, AssistantConfig, AssistantSessionObserve,
  AssistantCodexContext, AssistantWorkTarget, LazFileUtils, FileUtil, LCLType;

Procedure ApplyTurnAttachmentsToTrace(Trace: TAssistantTrace; Const AttachmentsJson: String);
Var
  Refs: TAssistantImageRefArray;
  TraceRefs: TTraceImageRefArray;
  I: Integer;
Begin
  If Not Assigned(Trace) Then Exit;
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Or (Length(Refs) = 0) Then Exit;
  SetLength(TraceRefs, Length(Refs));
  For I := 0 To High(Refs) Do
    Begin
      TraceRefs[I].Id := Refs[I].Id;
      TraceRefs[I].Name := Refs[I].Name;
      TraceRefs[I].DisplayPath := Refs[I].DisplayPath;
      TraceRefs[I].Width := Refs[I].Width;
      TraceRefs[I].Height := Refs[I].Height;
      TraceRefs[I].Missing := False;
    End;
  Trace.SetUserImageRefs(TraceRefs);
End;

Procedure Seam_FinishLiveTrace(Form: TProjectAssistantForm; Const SystemNote: String; DurationMs: Integer);
Var
  Last: TTraceBlock;
Begin
  With Form Do
    Begin
    If Not Assigned(FTrace) Then
      Exit;
    FTrace.EnsureUser(FDisplayUser);
    ApplyLiveAnswerSlice;
    FTrace.FinishCurrentThinking;
    FTrace.FinishCurrentAnswer;
    If SystemNote <> '' Then
      Begin
        Last := Nil;
        If FTrace.Count > 0 Then
          Last := FTrace[FTrace.Count - 1];
        If (Not Assigned(Last)) Or (Last.Kind <> tbkNote) Or (Last.Body <> SystemNote) Then
          FTrace.AddNote(SystemNote);
      End;
    FTrace.ApplyWorkedFooter(DurationMs);
    End;
End;

Function Seam_CurrentStreamDurationMs(Form: TProjectAssistantForm): Integer;
Begin
  With Form Do
    Begin
    Result := 0;
    If FTurnStartTick = 0 Then
      Exit;
    Result := Integer(GetTickCount64 - FTurnStartTick);
    If Result < 0 Then
      Result := 0;
    End;
End;

Function Seam_MonitorLiveTurnId(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    If FSending Or (Assigned(FTrace) And (FTrace.Count > 0)) Then
      Result := InFlightTurnId
    Else
      Result := 'live';
    End;
End;

Function Seam_InFlightTurnId(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    { Every path that starts a turn clears FTurnRecorded. A plan run keeps the recorded id for its notes until then. }
    If (LiveTurnId = '') Or ((LiveTurnId = StoredTurnId) And (Not FTurnRecorded)) Then
      LiveTurnId := NewConversationTurnId;
    Result := LiveTurnId;
    End;
End;

Procedure Seam_RecordCurrentTurn(Form: TProjectAssistantForm; Const ErrorText: String);
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  DurationMs: Integer;
Begin
  With Form Do
    Begin
    { One stream → one conversation row (guard against double IsFinished / Stop+Finish). }
    If FTurnRecorded Then
      Exit;
    If Not Assigned(ProjectAssistantConversation) Then
      Exit;
    EnsureConversationStore;
    If ProjectAssistantConversation.ProjectRoot = '' Then
      Exit;
    If Assigned(AssistantClient) Then
      Begin
        Turn.MessagesJson := AssistantClient.ExportUnstoredMessagesJson;
        Turn.AttachmentsJson := AssistantClient.OpeningUserAttachmentsJson;
      End;
    If (Trim(Turn.AttachmentsJson) = '') And (Trim(FPendingTurnAttachments) <> '') Then
      Turn.AttachmentsJson := FPendingTurnAttachments;
    If Trim(ErrorText) = '' Then
      EnsureFinalAssistantSummary;
    FPendingTurnAttachments := '';
    If (Trim(FLiveUser) = '') And (Trim(FDisplayUser) = '') And
      (Trim(FLiveContent) = '') And (Trim(FAssistantContent) = '') And (Trim(ErrorText) = '') And
      (Trim(Turn.AttachmentsJson) = '') Then
      Exit;
    DurationMs := CurrentStreamDurationMs;
    { The phone already holds this turn under the id the monitor sent while it streamed. }
    Turn.Id := InFlightTurnId;
    Turn.Mode := AssistantModeToStr(ActiveMode);
    If FLiveUser <> '' Then
      Turn.Prompt := FLiveUser
    Else
      Turn.Prompt := FDisplayUser;
    If Assigned(FTrace) And (Trim(Turn.AttachmentsJson) <> '') Then
      ApplyTurnAttachmentsToTrace(FTrace, Turn.AttachmentsJson);
    If Assigned(FTrace) And (FTrace.Count > 0) Then
      Begin
        Turn.TraceJson := FTrace.SaveToJson;
        Turn.Thinking := FTrace.JoinedThinking;
        Turn.Response := FTrace.JoinedAnswers;
        If Turn.Response = '' Then
          If FLiveContent <> '' Then
            Turn.Response := FLiveContent
          Else
            Turn.Response := FAssistantContent;
      End
    Else
      Begin
        Turn.TraceJson := '';
        If FLiveThinking <> '' Then
          Turn.Thinking := FLiveThinking
        Else
          Turn.Thinking := FAssistantThinking;
        If FLiveContent <> '' Then
          Turn.Response := FLiveContent
        Else
          Turn.Response := FAssistantContent;
      End;
    Turn.CreatedAt := IsoNowUtc;
    Turn.StartedAt := FTurnStartedAt;
    If Turn.StartedAt = '' Then
      Turn.StartedAt := Turn.CreatedAt;
    Turn.FinishedAt := IsoNowUtc;
    Turn.DurationMs := DurationMs;
    If Assigned(FTrace) Then
      Turn.ThinkingMs := FTrace.ThinkingDurationMs
    Else
      Turn.ThinkingMs := 0;
    Turn.Model := FModelName;
    If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
      Turn.Skill := AssistantClient.ActiveSkill
    Else
      Turn.Skill := '';
    Turn.TokenEstimate := Length(Turn.Prompt + Turn.Response + Turn.Thinking) Div 4;
    Turn.ErrorText := ErrorText;
    If Not AssistantMayStoreTurn(Turn.ErrorText, Turn.Response) Then
      Begin
        WorkflowLogger.Warning('ProjectAssistant', 'Skipped an empty successful turn.');
        Exit;
      End;
    Turn.PlanFile := GetActivePlanRelativePath;
    Turn.TodoId := '';
    Turn.EventsFile := '';
    If FTurnEventsFile <> '' Then
      Turn.EventsFile := AssistantEventsRelativePath(FTurnEventsFile, ProjectAssistantConversation.ProjectRoot)
    Else If Assigned(AssistantClient) And (AssistantClient.LastEventsFile <> '') Then
      Turn.EventsFile := AssistantEventsRelativePath(AssistantClient.LastEventsFile,
        ProjectAssistantConversation.ProjectRoot);
    If ProjectAssistantConversation.AppendTurn(Turn, Entry) Then
      Begin
        FTurnRecorded := True;
        StoredTurnId := Turn.Id;
        If (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
          AssistantClient.NoteMessagesStored;
        RefreshHistoryCombo;
      End
    Else
      WorkflowLogger.Warning('ProjectAssistant', 'Conversation append failed: ' + ProjectAssistantConversation.LastError);
    End;
End;

Procedure Seam_EnsureFinalAssistantSummary(Form: TProjectAssistantForm);
Var
  Existing, Summary, Asked: String;
  Tools: TAssistantSummaryToolArray;

  Procedure ShowAnswer(Const Text: String);
  Var
    Block: TTraceBlock;
  Begin
    With Form Do
    Begin
    If Trim(Text) = '' Then
      Exit;
    FLiveContent := Text;
    FAnswerSliceStart := 1;
    If Assigned(FTrace) Then
      Begin
        FTrace.FinishCurrentThinking;
        Block := FTrace.EnsureAnswer;
        If (Trim(Block.Body) = '') Or (Not SliceLooksLikeAnswer(Block.Body)) Or (Trim(Block.Body) = Trim(Text)) Then
          Block.Body := Text;
        Block.Running := False;
      End;
    FAssistantContent := Text;
    If FViewingLive Or FSending Or FStreamingActive Then
      RefreshChatDisplay(True, True);
    End;
  End;

  Function CollectTools: TAssistantSummaryToolArray;
  Var
    I, N: Integer;
    Block: TTraceBlock;
  Begin
    With Form Do
    Begin
    Result := Nil;
    If Not Assigned(FTrace) Then
      Exit;
    For I := 0 To FTrace.Count - 1 Do
      Begin
        Block := FTrace[I];
        If (Not Assigned(Block)) Or (Not (Block.Kind In [tbkTool, tbkSubagent])) Then
          Continue;
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N].Name := Trim(Block.ToolName);
        If Result[N].Name = '' Then
          Result[N].Name := Trim(Block.Title);
        Result[N].Ok := Block.Ok And (Not Block.Running);
        If Block.Running And (Trim(Block.Body) = '') Then
          Result[N].Detail := 'did not finish'
        Else If Not Result[N].Ok Then
          Result[N].Detail := Copy(Block.Body, 1, 500)
        Else
          Result[N].Detail := '';
      End;
    End;
  End;

  Function AskedText: String;
  Begin
    With Form Do
    Begin
    If Trim(FLiveUser) <> '' Then
      Result := Trim(FLiveUser)
    Else
      Result := Trim(FDisplayUser);
    If Result <> '' Then
      Exit;
    If (Trim(FPendingTurnAttachments) <> '') Or
      (Assigned(AssistantClient) And (Trim(AssistantClient.OpeningUserAttachmentsJson) <> '')) Then
      Result := 'an image';
    End;
  End;

Begin
  With Form Do
    Begin
    Existing := Trim(FLiveContent);
    If (Existing = '') And Assigned(FTrace) Then
      Existing := Trim(FTrace.JoinedAnswers);
    If Not AssistantNeedsFinalSummary(Existing) Then
      Begin
        { The model already wrote the reply. Keep it, and do not append another summary. }
        If (Trim(FLiveContent) <> '') And ((Not Assigned(FTrace)) Or (Trim(FTrace.JoinedAnswers) = '')) Then
          ShowAnswer(FLiveContent);
        Exit;
      End;
    Asked := AskedText;
    Tools := CollectTools;
    If (Asked = '') And (Length(Tools) = 0) Then
      Exit;
    Summary := AssistantFinalSummary(Asked, Tools);
    ShowAnswer(Summary);
    End;
End;

Procedure Seam_ConversationListSelectionChange(Form: TProjectAssistantForm; Sender: TObject; User: Boolean);
Var
  TurnIndex: Integer;
Begin
  With Form Do
    Begin
    If FIgnoreConversationListChange Then
      Exit;
    { Allow browsing past turns while a stream continues in the background. }
    If Not Assigned(ConversationList) Or (ConversationList.ItemIndex < 0) Then
      Exit;
    TurnIndex := ConversationListTurnIndex(ConversationList.ItemIndex);
    If TurnIndex < LiveConversationMarker Then
      Exit;
    { Marker is -2; completed turns are >= 0. Decode already applied +1 offset. }
    If (TurnIndex < 0) And (TurnIndex <> LiveConversationMarker) Then
      Exit;
    ShowConversationTurn(TurnIndex);
    End;
End;

Procedure Seam_ConversationListClick(Form: TProjectAssistantForm; Sender: TObject);
Begin
  With Form Do
    Begin
    ConversationListSelectionChange(Sender, True);
    End;
End;

Procedure Seam_ApplyLoadedConversationToUi(Form: TProjectAssistantForm; Const StatusNote: String);
Begin
  With Form Do
    Begin
    FUserCancelled := False;
    FTurnRecorded := False;
    FLastChatPaintTick := 0;
    ClearCurrentTurnDisplay;
    RebuildClientFromConversation;
    RefreshHistoryCombo;
    RefreshConversationList;
    ShowLastConversationTurn;
    If StatusNote <> '' Then
      SetCurrentSystemNote(StatusNote);
    UpdateStatusFooter;
    End;
End;

Procedure Seam_RebuildClientFromConversation(Form: TProjectAssistantForm);
Var
  I, Before: Integer;
  Turn: TConversationTurn;
  Refs: TAssistantImageRefArray;
Begin
  With Form Do
    Begin
    If Assigned(AssistantClient) Then
      AssistantClient.ClearHistory;
    FContextUsed := 0;
    FCodexContextUsage := EmptyCodexContextUsage;
    If Not Assigned(ProjectAssistantConversation) Or Not Assigned(AssistantClient) Then
      Exit;
    For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
      Begin
        If Not ProjectAssistantConversation.GetTurn(I, Turn) Then
          Continue;
        Before := AssistantClient.MessageCount;
        If Trim(Turn.MessagesJson) <> '' Then
          AssistantClient.RestoreMessagesJson(Turn.MessagesJson)
        Else
          Begin
            { AddMessage would keep an empty prompt and drop the look sentence.
              An image-only turn must still send that sentence with the picture. }
            SetLength(Refs, 0);
            ParseAssistantImageRefs(Turn.AttachmentsJson, Refs);
            If Length(Refs) > 0 Then
              AssistantClient.AddUserMessage(Turn.Prompt, Refs)
            Else If Trim(Turn.Prompt) <> '' Then
              AssistantClient.AddMessage(amrUser, Turn.Prompt);
            If Trim(Turn.Response) <> '' Then
              AssistantClient.AddMessage(amrAssistant, Turn.Response);
          End;
        If Trim(Turn.AttachmentsJson) <> '' Then
          AssistantClient.EnsureUserImageRefsFrom(Before, Turn.AttachmentsJson);
        FContextUsed := FContextUsed + Length(Turn.Prompt) Div 4 + Length(Turn.Response) Div 4 + 8;
      End;
    AssistantClient.NoteMessagesStored;
    FContextUsed := AssistantClient.EstimatedPromptTokens;
    End;
End;

Function Seam_BuildConversationMarkdownExport(Form: TProjectAssistantForm): String;
Var
  SL: TStringList;
  I: Integer;
  Turn: TConversationTurn;
  ProjectName, MetaLine, TraceMd: String;
  Trace: TAssistantTrace;
Begin
  With Form Do
    Begin
    SL := TStringList.Create;
    Try
      ProjectName := AssistantTarget.DisplayName;
      SL.Add('# Project Assistant conversation');
      SL.Add('');
      SL.Add('- **Exported:** ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
      SL.Add('- **Project:** ' + ProjectName);
      If Assigned(AssistantChatConfig) Then
        SL.Add('- **Model:** ' + AssistantChatConfig.Model)
      Else
        SL.Add('- **Model:** ' + FModelName);
      SL.Add('- **Turns:** ' + IntToStr(ProjectAssistantConversation.TurnCount));
      SL.Add('');
      SL.Add('---');
      SL.Add('');
      For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
        Begin
          If Not ProjectAssistantConversation.GetTurn(I, Turn) Then
            Continue;
          SL.Add('## Turn ' + IntToStr(I + 1));
          If Turn.CreatedAt <> '' Then
            Begin
              SL.Add('');
              MetaLine := '*' + Turn.CreatedAt;
              If Turn.Mode <> '' Then
                MetaLine := MetaLine + ' · mode ' + Turn.Mode;
              If Turn.Model <> '' Then
                MetaLine := MetaLine + ' · ' + Turn.Model;
              SL.Add(MetaLine + '*');
            End;
          { No user heading unless the person sent text or a picture. }
          If (Trim(Turn.Prompt) <> '') Or (Trim(Turn.AttachmentsJson) <> '') Then
            Begin
              SL.Add('');
              SL.Add('### User');
              SL.Add('');
              If Trim(Turn.Prompt) <> '' Then
                SL.Add(Turn.Prompt);
              If Trim(Turn.AttachmentsJson) <> '' Then
                AppendAssistantImageFileNames(Turn.AttachmentsJson, SL);
              SL.Add('');
            End
          Else
            SL.Add('');
          If Trim(Turn.TraceJson) <> '' Then
            Begin
              Trace := TAssistantTrace.Create;
              Try
                Trace.LoadFromJson(Turn.TraceJson);
                TraceMd := Trace.FormatMarkdown(False);
                If Trim(TraceMd) <> '' Then
                  SL.Add(TraceMd)
                Else
                  Begin
                    SL.Add('### Assistant');
                    SL.Add('');
                    If Trim(Turn.Response) <> '' Then
                      SL.Add(Turn.Response)
                    Else
                      SL.Add('*(empty)*');
                  End;
              Finally
                Trace.Free;
              End;
            End
          Else
            Begin
              If Trim(Turn.Thinking) <> '' Then
                Begin
                  SL.Add('### Thinking');
                  SL.Add('');
                  SL.Add(Turn.Thinking);
                  SL.Add('');
                End;
              SL.Add('### Assistant');
              SL.Add('');
              If Trim(Turn.Response) <> '' Then
                SL.Add(Turn.Response)
              Else If Trim(Turn.ErrorText) <> '' Then
                SL.Add('*(no response)*')
              Else
                SL.Add('*(empty)*');
            End;
          If Trim(Turn.ErrorText) <> '' Then
            Begin
              SL.Add('');
              SL.Add('**Error:** ' + Turn.ErrorText);
            End;
          SL.Add('');
          SL.Add('---');
          SL.Add('');
        End;
      Result := SL.Text;
    Finally
      SL.Free;
    End;
    End;
End;

Function Seam_DefaultExportFileName(Form: TProjectAssistantForm): String;
Begin
  With Form Do
    Begin
    Result := 'Conversation ' + FormatDateTime('yyyymmdd"-"hhnnss', Now) + '.md';
    End;
End;

Procedure Seam_UpdateHistoryActions(Form: TProjectAssistantForm);
Begin
  With Form Do
    Begin
    If Assigned(ExportHistoryAction) Then
      ExportHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
        ProjectAssistantConversation.HasTurns;
    If Assigned(DeleteHistoryAction) Then
      DeleteHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
        (ProjectAssistantConversation.ProjectRoot <> '');
    End;
End;

Procedure Seam_RefreshHistoryCombo(Form: TProjectAssistantForm);
Var
  Items: TObjectList;
  I, SelectIdx: Integer;
  Hist: TConversationHistoryItem;
  PrevId: String;
Begin
  With Form Do
    Begin
    If Not Assigned(HistoryCombo) Or Not Assigned(HistoryIds) Then
      Exit;
    PrevId := '';
    If (HistoryCombo.ItemIndex >= 0) And (HistoryCombo.ItemIndex < HistoryIds.Count) Then
      PrevId := HistoryIds[HistoryCombo.ItemIndex];
    FHistoryUpdating := True;
    Items := TObjectList.Create(True);
    Try
      HistoryCombo.Items.BeginUpdate;
      Try
        HistoryCombo.Items.Clear;
        HistoryIds.Clear;
        If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
          ProjectAssistantConversation.ListHistory(Items);
        SelectIdx := 0;
        For I := 0 To Items.Count - 1 Do
          Begin
            Hist := TConversationHistoryItem(Items[I]);
            If Not Assigned(Hist) Then
              Continue;
            HistoryCombo.Items.Add(Hist.Title);
            HistoryIds.Add(Hist.ArchiveId);
            If SameText(Hist.ArchiveId, PrevId) Then
              SelectIdx := HistoryCombo.Items.Count - 1;
            If Hist.IsCurrent Then
              SelectIdx := HistoryCombo.Items.Count - 1;
          End;
        If HistoryCombo.Items.Count = 0 Then
          Begin
            HistoryCombo.Items.Add('Current (empty)');
            HistoryIds.Add('');
            SelectIdx := 0;
          End;
        If SelectIdx >= HistoryCombo.Items.Count Then
          SelectIdx := 0;
        HistoryCombo.ItemIndex := SelectIdx;
      Finally
        HistoryCombo.Items.EndUpdate;
      End;
    Finally
      Items.Free;
      FHistoryUpdating := False;
    End;
    UpdateHistoryActions;
    End;
End;

Procedure Seam_RefreshConversationList(Form: TProjectAssistantForm);
Var
  I, SeqNo, KeepTurnIndex: Integer;
  Entry: TConversationIndexEntry;
  Line, Preview: String;
  SelectIdx: Integer;
Begin
  With Form Do
    Begin
    If Not Assigned(ConversationList) Or Not Assigned(ProjectAssistantConversation) Then
      Exit;
    EnsureConversationStore;
    KeepTurnIndex := FSelectedTurnIndex;
    If KeepTurnIndex < 0 Then
      KeepTurnIndex := ConversationListTurnIndex(ConversationList.ItemIndex);
    SelectIdx := -1;
    FIgnoreConversationListChange := True;
    ConversationList.Items.BeginUpdate;
    Try
      ConversationList.Clear;
      { Oldest first so new turns append at the bottom (grow down).
        Objects store TurnIndex+1 (never 0/Nil) for O(1) memory retrieval. }
      For I := 0 To ProjectAssistantConversation.IndexCount - 1 Do
        Begin
          Entry := ProjectAssistantConversation.IndexEntry(I);
          If Not Assigned(Entry) Then
            Continue;
          SeqNo := I + 1;
          If Trim(Entry.PromptPreview) <> '' Then
            Line := IntToStr(SeqNo) + ' - ' + Entry.PromptPreview
          Else
            Line := IntToStr(SeqNo) + ' - ' + Entry.ResponsePreview;
          If Entry.ErrorText <> '' Then
            Line := Line + ' [err]';
          ConversationList.Items.AddObject(Line, TObject(PtrUInt(Entry.TurnIndex + 1)));
          If Entry.TurnIndex = KeepTurnIndex Then
            SelectIdx := ConversationList.Items.Count - 1;
        End;
      { In-flight prompt at the bottom while the model runs — omit once the turn
        is recorded so the list never shows live + completed duplicates. }
      If FSending And (Not FTurnRecorded) And (FLiveUser <> '') Then
        Begin
          Preview := FLiveUser;
          Preview := StringReplace(Preview, #13#10, ' ', [rfReplaceAll]);
          Preview := StringReplace(Preview, #10, ' ', [rfReplaceAll]);
          If Length(Preview) > 120 Then
            Preview := Copy(Preview, 1, 119) + '…';
          SeqNo := ProjectAssistantConversation.IndexCount + 1;
          Line := IntToStr(SeqNo) + ' - ' + Preview + ' …';
          ConversationList.Items.AddObject(Line, TObject(PtrUInt(LiveConversationMarker + 1)));
          If (KeepTurnIndex = LiveConversationMarker) Or FViewingLive Then
            SelectIdx := ConversationList.Items.Count - 1;
        End;
    Finally
      ConversationList.Items.EndUpdate;
      FIgnoreConversationListChange := False;
    End;
    If ConversationList.Items.Count > 0 Then
      Begin
        If SelectIdx < 0 Then
          SelectIdx := ConversationList.Items.Count - 1;
        FIgnoreConversationListChange := True;
        Try
          ConversationList.ItemIndex := SelectIdx;
          ConversationList.TopIndex := SelectIdx;
        Finally
          FIgnoreConversationListChange := False;
        End;
        FSelectedTurnIndex := ConversationListTurnIndex(SelectIdx);
      End;
    End;
End;

Procedure Seam_ShowLastConversationTurn(Form: TProjectAssistantForm);
Var
  N: Integer;
Begin
  With Form Do
    Begin
    If Not Assigned(ProjectAssistantConversation) Then
      Begin
        RefreshChatDisplay(True, False);
        Exit;
      End;
    N := ProjectAssistantConversation.TurnCount;
    If N > 0 Then
      ShowConversationTurn(N - 1, False)
    Else
      Begin
        ClearCurrentTurnDisplay;
        RefreshChatDisplay(True, False);
      End;
    { Resume may already have answered from an empty mirror. The phone needs this screen. }
    AssistantSessionObserve.AssistantSessionObserve(asnSnapshot);
    End;
End;

Procedure Seam_ShowConversationTurn(Form: TProjectAssistantForm; TurnIndex: Integer; Navigate: Boolean);
Var
  Turn: TConversationTurn;
Begin
  With Form Do
    Begin
    FSelectedTurnIndex := TurnIndex;
    If TurnIndex = LiveConversationMarker Then
      Begin
        { Follow the in-flight turn (background stream may still be running). }
        FViewingLive := True;
        FDisplayUser := FLiveUser;
        FAssistantContent := FLiveContent;
        FAssistantThinking := FLiveThinking;
        FDisplayTraceJson := '';
        FDisplayEventsFile := '';
        FDisplaySystemNote := '';
        FDisplayDurationMs := 0;
        FDisplayThinkingMs := 0;
        RefreshChatDisplay(True, FSending);
        If Assigned(FTraceView) Then FTraceView.ScrollToEnd;
        Exit;
      End;
    FViewingLive := False;
    If Not Assigned(ProjectAssistantConversation) Then
      Exit;
    If Not ProjectAssistantConversation.GetTurn(TurnIndex, Turn) Then
      Begin
        WorkflowLogger.Warning('ProjectAssistant', 'ShowConversationTurn failed idx=' + IntToStr(TurnIndex) +
          ' ' + ProjectAssistantConversation.LastError);
        Exit;
      End;
    FDisplayUser := Turn.Prompt;
    FAssistantContent := Turn.Response;
    FAssistantThinking := Turn.Thinking;
    FDisplayTraceJson := Turn.TraceJson;
    FDisplayEventsFile := Turn.EventsFile;
    FDisplayDurationMs := Turn.DurationMs;
    FDisplayThinkingMs := Turn.ThinkingMs;
    If Turn.ErrorText <> '' Then
      FDisplaySystemNote := '**Error:** ' + Turn.ErrorText
    Else
      FDisplaySystemNote := '';
    RefreshChatDisplay(True, False);
    If Navigate And Assigned(FTraceView) Then FTraceView.NavigateTurn(Turn.Id);
    End;
End;

Function Seam_ConversationListTurnIndex(Form: TProjectAssistantForm; ListIndex: Integer): Integer;
Var
  Encoded: Integer;
Begin
  With Form Do
    Begin
    { Objects store TurnIndex+1 so index 0 is never stored as Nil.
      Live in-flight row uses LiveConversationMarker+1. }
    Result := -1;
    If Not Assigned(ConversationList) Or (ListIndex < 0) Or (ListIndex >= ConversationList.Items.Count) Then
      Exit;
    Encoded := Integer(PtrUInt(ConversationList.Items.Objects[ListIndex]));
    If Encoded = 0 Then
      Exit;
    Result := Encoded - 1; { may be LiveConversationMarker (-2) }
    End;
End;

Procedure Seam_EnsureConversationStore(Form: TProjectAssistantForm);
Var
  Root: String;
  RootChanged: Boolean;
Begin
  With Form Do
    Begin
    If Not Assigned(ProjectAssistantConversation) Then
      Exit;
    Root := ProjectAssistantRoot;
    If Root = '' Then
      Exit;
    RootChanged := Not SameFileName(ExcludeTrailingPathDelimiter(ProjectAssistantConversation.ProjectRoot),
      ExcludeTrailingPathDelimiter(Root)) Or (ProjectAssistantConversation.TargetStoreKey <> AssistantTarget.StoreKey);
    If RootChanged Then
      Begin
        ProjectAssistantConversation.SetProjectRoot(Root, AssistantTarget.StoreKey);
        ProjectAssistantConversation.Load; { one bulk parse into memory }
        ApplyShellConfigFromStore;
      End
    Else If Not ProjectAssistantConversation.Loaded Then
      Begin
        ProjectAssistantConversation.Load;
        ApplyShellConfigFromStore;
      End;
    End;
End;

End.
