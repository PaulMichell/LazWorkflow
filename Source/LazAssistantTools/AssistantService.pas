Unit AssistantService;

{ Assistant LLM service with OAuth Bearer auth and SSE streaming (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The service owns history, prompt
  assembly, model listing, and actor lifetime in one place; splitting would
  separate the only callers of the private trim/export helpers.
  Reviewed 2026-08: unused TAssistantStreamThread/TAssistantSSEStream removed. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, WorkflowLog, WorkflowEvents, AssistantConfig, AssistantConversation,
  AssistantProtocol, AssistantEvents, AssistantModelProvider, AssistantImages;

Type
  TAssistantMessageRole = (amrSystem, amrUser, amrAssistant, amrTool);

  TAssistantMessage = Record
    Role: TAssistantMessageRole;
    Content: String;
    ToolCallId: String;
    { When set on an assistant message, raw OpenAI tool_calls JSON array. }
    ToolCallsJson: String;
    { Opaque ordered Responses output for an in-memory tool round. Never display it. }
    ResponsesOutputJson: String;
    { Cached JSON-escaped fields so request rebuild is not O(n) re-escape every send. }
    ContentEscaped: String;
    ToolCallIdEscaped: String;
    { Image refs for amrUser only. Paths, never pixel bytes. }
    ImageRefs: TAssistantImageRefArray;
  End;

  TAssistantToolCall = Record
    Id: String;
    Name: String;
    Arguments: String;
  End;
  TAssistantToolCallArray = Array Of TAssistantToolCall;

  TAssistantContextBreakdown = Record
    SystemTokens: Integer;
    ToolsTokens: Integer;
    HistoryTokens: Integer;
    ImageTokens: Integer;
    ImageCount: Integer;
    TotalTokens: Integer;
    LimitTokens: Integer;
    MessageCount: Integer;
  End;

  { Called on the main thread. ContentSnapshot / ThinkingSnapshot are full text so
    far (not raw deltas). IsFinished ends the stream. Thinking is reasoning_content
    when the model streams it; Content is the final answer channel only. }
  TAssistantStreamEvent = Procedure(Const ContentSnapshot, ThinkingSnapshot: String;
    IsFinished: Boolean; Const ErrorText: String) Of Object;

  TAssistantService = Class
  Private
    FProvider: IAssistantModelProvider;
    FApiBase: String;
    FModel: String;
    FBaseSystemPrompt: String;
    FSystemPrompt: String;
    FActiveSkill: String;
    FMessages: Array Of TAssistantMessage;
    FLastError: String;
    FStreamThread: TThread;
    FBusy: Boolean;
    FActiveMode: TAssistantMode;
    FSystemPromptEscaped: String;
    FToolsJsonCache: String;
    FToolsJsonMode: TAssistantMode;
    FToolsJsonValid: Boolean;
    FToolsEnabled: Boolean;
    FMaxPromptTokens: Integer;
    FLastTrimNotice: String;
    FReasoningEffort: String;
    FAnswerVerbosity: String;
    FMaxOutputTokens: Integer;
    FSearchMode: String;
    FSearchCitations: Boolean;
    FOnTrace: TAssistantTraceNotify;
    FOrphanThreads: TFPList;
    FIsSubagent: Boolean;
    FSubagentKindName: String;
    FLastEventsFile: String;
    FStoredMessageCount: Integer;
    FSubagents: TObjectList;
    FSubagentsLock: TRTLCriticalSection;
    FDeferredSubagents: TFPList;
    Procedure FlushDeferredSubagents;
    Function FindSubagentLocked(Const RunId: String): TObject;
    Procedure ReapOrphanThreads(WaitMs: QWord);
    Procedure AbandonStreamThread;
    Procedure ClearStreamThread;
    Procedure RebuildSystemPrompt;
    Function EscapedContent(Var Msg: TAssistantMessage): String;
    Function EscapedToolCallId(Var Msg: TAssistantMessage): String;
    Function ToolsJsonCached: String;
    Function MessagePayloadChars(Const Msg: TAssistantMessage): Integer;
    Function CountRequestImages: Integer;
    Function EstimatePromptTokens: Integer;
    Procedure OmitMessageImages(Var Msg: TAssistantMessage);
    Procedure InvalidateMessageEscape(Var Msg: TAssistantMessage);
    Procedure TruncateMessageContent(Var Msg: TAssistantMessage; MaxChars: Integer; Const LabelText: String);
    Procedure DropMessageRange(FromIndex, Count: Integer);
    { Shrink/drop old messages so the next request fits the model limit. }
    Procedure TrimMessagesForBudget;
    Function BuildRequestJson: String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure ApplyConfig(Config: TAssistantConfig);
    { Only replace a native provider while idle; managed runtimes need their own backend. }
    Procedure SetModelProvider(Const Provider: IAssistantModelProvider);
    Procedure SetEndpoint(Const ApiBase, Model: String);
    Procedure SetActiveSkill(Const SkillName: String);
    Procedure SetActiveMode(Mode: TAssistantMode);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TAssistantMessageRole; Const Content: String);
    { User turn entry. Image refs are not accepted on tool results or subagent prompts. }
    Procedure AddUserMessage(Const Content: String; Const ImageRefs: TAssistantImageRefArray);
    { Drop image refs on the latest user message so a rejected upload is not resent. }
    Procedure DropLastUserImageRefs;
    { False only when the last model list has an explicit input-modality list without images. }
    Function ImagesAttachAllowed(Out Reason: String): Boolean;
    Function ExportUnstoredMessagesJson: String;
    Procedure RestoreMessagesJson(Const JsonText: String);
    Procedure NoteMessagesStored;
    Function LastUserAttachmentsJson: String;
    { Opening user message of the unstored turn. Later steer refs are not this field. }
    Function OpeningUserAttachmentsJson: String;
    Procedure EnsureLastUserImageRefs(Const AttachmentsJson: String);
    { Fill the first user message at or after FromIndex when it has no refs yet. }
    Procedure EnsureUserImageRefsFrom(FromIndex: Integer; Const AttachmentsJson: String);
    Procedure AddAssistantToolCalls(Const Content, ToolCallsJson: String;
      Const ResponsesOutputJson: String = '');
    Procedure AddToolResult(Const ToolCallId, Content: String);
    { Restore a previously persisted message without store-time truncation. }
    Procedure RestoreMessage(Role: TAssistantMessageRole; Const Content, ToolCallId, ToolCallsJson: String);
    Function MessageCount: Integer;
    Function GetMessage(Index: Integer; Out Role: TAssistantMessageRole; Out Content, ToolCallId, ToolCallsJson: String): Boolean;
    Function IsBusy: Boolean;
    Function IsSignedIn: Boolean;
    { Rough prompt size (messages + system + tools) for UI / guards. }
    Function EstimatedPromptTokens: Integer;
    Function GetContextBreakdown: TAssistantContextBreakdown;
    { Shrink older turns/tool payloads. Returns estimated tokens removed. }
    Function CompactOlderHistory: Integer;
    { Starts background SSE stream; OnToken is Synchronized to the main thread. }
    Function StartStream(OnToken: TAssistantStreamEvent): Boolean;
    Procedure CancelStream;
    Procedure DetachStreamCallbacks;
    { Call from the stream callback when IsFinished is True (main thread). }
    Procedure MarkStreamComplete;
    { One-shot non-streaming completion; does not touch chat history or tools.
      Intended for short side tasks (e.g. commit message suggestion). }
    Function CompleteOnce(Const SystemPrompt, UserPrompt: String;
      Out AnswerText, ErrorText: String): Boolean;
    { GET /v1/language-models (fallback /v1/models). Fills ModelIds sorted, chat-oriented. }
    Function ListAvailableModels(ModelIds: TStrings; Out ErrorText: String): Boolean;
    { Rebuilds the next chat/completions body (used after a tool round). }
    Function BuildNextRequestJson: String;
    { Mid-turn steer. Does not change mode or tool permissions. No-op if no actor is running.
      Image refs are injected at the next gap as user-message parts. A subagent session drops them. }
    Procedure EnqueueSteer(Const Text: String); Overload;
    Function EnqueueSteer(Const Text: String; Const ImageRefs: TAssistantImageRefArray): Boolean; Overload;
    { Depth-1 children. Parent only; Start fails if live count is already MaxLiveSubagents. }
    Function IsSubagentSession: Boolean;
    Function StartSubagent(Const ArgumentsJson: String; Out RunId: String; Out ErrorText: String): Boolean;
    Function LiveSubagentCount: Integer;
    Function SubagentIsRunning(Const RunId: String): Boolean;
    Function TakeSubagentResult(Const RunId: String; Out ResultText, ErrorText: String): Boolean;
    Procedure AbandonSubagent(Const RunId, Reason: String);
    Procedure AbandonTimedOutSubagents;
    Procedure CancelSubagents;
    { Terminate the actor without waiting — safe from a worker thread. }
    Procedure StopActorNoWait;
    Function HasUnfinishedActor: Boolean;
    Procedure ConfigureAsSubagent(Const KindName: String);
    { Sampler items for the session actor (Responses / Completions). }
    Function ExportSamplerItems(ForResponses: Boolean = False): TSamplerInputItemArray;
    Property OnTrace: TAssistantTraceNotify Read FOnTrace Write FOnTrace;
    Property Model: String Read FModel;
    Property ApiBase: String Read FApiBase;
    Property ActiveSkill: String Read FActiveSkill;
    Property ActiveMode: TAssistantMode Read FActiveMode;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
    Property LastError: String Read FLastError;
    { Absolute events JSONL written by the last StartStream (empty if none). }
    Property LastEventsFile: String Read FLastEventsFile;
    { When False, chat/completions is sent without tools (single-shot answer). }
    Property ToolsEnabled: Boolean Read FToolsEnabled Write FToolsEnabled;
    { Soft cap for chat/completions prompt (default leaves headroom under 500k models). }
    Property MaxPromptTokens: Integer Read FMaxPromptTokens Write FMaxPromptTokens;
    Property LastTrimNotice: String Read FLastTrimNotice;
    { low | medium | high | xhigh — sent as reasoning_effort when non-empty. }
    Property ReasoningEffort: String Read FReasoningEffort Write FReasoningEffort;
    Property AnswerVerbosity: String Read FAnswerVerbosity Write FAnswerVerbosity;
    Property MaxOutputTokens: Integer Read FMaxOutputTokens Write FMaxOutputTokens;
    Property SearchMode: String Read FSearchMode Write FSearchMode;
    Property SearchCitations: Boolean Read FSearchCitations Write FSearchCitations;
  End;

{ Free finished abandoned actors/child services left after cancel. }
Procedure ReapAbandonedAssistantWorkers;

Var
  AssistantClient: TAssistantService;

Implementation

Uses
  fpjson, jsonparser, AssistantXaiProvider, AssistantSkills, AssistantTools, AssistantActor,
  AssistantHarness, AssistantSubagents, AssistantPlan;

Function RoleToJson(Role: TAssistantMessageRole): String;
Begin
  Case Role Of
    amrSystem: Result := 'system';
    amrUser: Result := 'user';
    amrAssistant: Result := 'assistant';
    amrTool: Result := 'tool';
  Else
    Result := 'user';
  End;
End;

Function JsonStringField(Obj: TJSONObject; Const FieldName: String): String;
Var
  Node: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(FieldName);
  If Not Assigned(Node) Then
    Exit;
  If Node.JSONType = jtNull Then
    Exit;
  Result := Node.AsString;
End;

Type
  TChildSubagentState = Record
    Finished: Boolean;
    Ok: Boolean;
    FailText: String;
    Answer: String;
  End;

  TChildSubagent = Class
  Private
    FOwner: TAssistantService;
    FChild: TAssistantService;
    FLock: TRTLCriticalSection;
    Procedure HandleToken(Const ContentSnapshot, ThinkingSnapshot: String;
      IsFinished: Boolean; Const ErrorText: String);
    Procedure HandleChildTrace(Const Event: TAssistantEvent);
    Procedure ForwardProgress(Const Phase: String);
  Strict Private
    Answer: String;
    FailText: String;
    Finished: Boolean;
    Ok: Boolean;
  Public
    Id: String;
    KindName: String;
    Title: String;
    StartedTick: QWord;
    Constructor Create(OwnerService: TAssistantService);
    Destructor Destroy; Override;
    Function BindAndStart(Const Request: TSubagentRequest; ParentMode: TAssistantMode;
      Const Provider: IAssistantModelProvider;
      Const ApiBase, Model, Skill, Effort, CompileLog: String; Out ErrorText: String): Boolean;
    Procedure Cancel;
    Procedure Abandon(Const Reason: String);
    Function IsFinished: Boolean;
    Function SnapshotState: TChildSubagentState;
  End;

Var
  GSubagentSeq: Integer;
  GAbandonedLock: TRTLCriticalSection;
  GAbandonedThreads: TFPList;
  GAbandonedServices: TFPList;

Procedure StealOrphanThreads(List: TFPList);
Var
  I: Integer;
Begin
  If (Not Assigned(List)) Or (List.Count < 1) Then
    Exit;
  EnterCriticalSection(GAbandonedLock);
  Try
    If Not Assigned(GAbandonedThreads) Then
      GAbandonedThreads := TFPList.Create;
    For I := 0 To List.Count - 1 Do
      If Assigned(List[I]) Then
        GAbandonedThreads.Add(List[I]);
  Finally
    LeaveCriticalSection(GAbandonedLock);
  End;
  List.Clear;
End;

Procedure RegisterAbandonedService(Service: TAssistantService);
Begin
  If Not Assigned(Service) Then
    Exit;
  EnterCriticalSection(GAbandonedLock);
  Try
    If Not Assigned(GAbandonedServices) Then
      GAbandonedServices := TFPList.Create;
    If GAbandonedServices.IndexOf(Service) < 0 Then
      GAbandonedServices.Add(Service);
  Finally
    LeaveCriticalSection(GAbandonedLock);
  End;
End;

Procedure ReapAbandonedAssistantWorkers;
Var
  I: Integer;
  Thread: TThread;
  Service: TAssistantService;
  FinishedThreads, FinishedServices: TFPList;
Begin
  FinishedThreads := TFPList.Create;
  FinishedServices := TFPList.Create;
  Try
    EnterCriticalSection(GAbandonedLock);
    Try
      If Assigned(GAbandonedThreads) Then
        Begin
          I := 0;
          While I < GAbandonedThreads.Count Do
            Begin
              Thread := TThread(GAbandonedThreads[I]);
              If Not Assigned(Thread) Then
                GAbandonedThreads.Delete(I)
              Else If Thread.Finished Then
                Begin
                  FinishedThreads.Add(Thread);
                  GAbandonedThreads.Delete(I);
                End
              Else
                Inc(I);
            End;
        End;
    Finally
      LeaveCriticalSection(GAbandonedLock);
    End;
    For I := 0 To FinishedThreads.Count - 1 Do
      Begin
        Thread := TThread(FinishedThreads[I]);
        Try
          Thread.WaitFor;
        Except
        End;
        Thread.Free;
      End;
    EnterCriticalSection(GAbandonedLock);
    Try
      If Assigned(GAbandonedServices) Then
        Begin
          I := 0;
          While I < GAbandonedServices.Count Do
            Begin
              Service := TAssistantService(GAbandonedServices[I]);
              If Not Assigned(Service) Then
                GAbandonedServices.Delete(I)
              Else
                Inc(I);
            End;
        End;
    Finally
      LeaveCriticalSection(GAbandonedLock);
    End;
    I := 0;
    While True Do
      Begin
        Service := Nil;
        EnterCriticalSection(GAbandonedLock);
        Try
          If (Not Assigned(GAbandonedServices)) Or (I >= GAbandonedServices.Count) Then
            Break;
          Service := TAssistantService(GAbandonedServices[I]);
        Finally
          LeaveCriticalSection(GAbandonedLock);
        End;
        If Not Assigned(Service) Then
          Begin
            Inc(I);
            Continue;
          End;
        Service.ReapOrphanThreads(0);
        If Service.HasUnfinishedActor Then
          Inc(I)
        Else
          Begin
            EnterCriticalSection(GAbandonedLock);
            Try
              GAbandonedServices.Remove(Service);
            Finally
              LeaveCriticalSection(GAbandonedLock);
            End;
            FinishedServices.Add(Service);
          End;
      End;
    For I := 0 To FinishedServices.Count - 1 Do
      TAssistantService(FinishedServices[I]).Free;
  Finally
    FinishedThreads.Free;
    FinishedServices.Free;
  End;
End;

Constructor TChildSubagent.Create(OwnerService: TAssistantService);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FOwner := OwnerService;
  FChild := Nil;
  Finished := False;
  Ok := False;
  StartedTick := GetTickCount64;
End;

Destructor TChildSubagent.Destroy;
Begin
  If Assigned(FChild) Then
    Begin
      Try
        { Never CancelStream/CheckSynchronize off the main thread — that deadlocks
          a child stuck in Queue/Synchronize and freezes the parent actor. }
        FChild.OnTrace := Nil;
        FChild.StopActorNoWait;
      Except
      End;
      If FChild.HasUnfinishedActor Then
        Begin
          { Keep the child service until its actor finishes; a local TAssistantService
            pointer in RunOneTool must not dangle. }
          RegisterAbandonedService(FChild);
          FChild := Nil;
        End
      Else
        FreeAndNil(FChild);
    End;
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TChildSubagent.HandleChildTrace(Const Event: TAssistantEvent);
Begin
  If Event.Kind = aekToolStarted Then
    Begin
      If Trim(Event.ToolName) <> '' Then
        ForwardProgress(Event.ToolName)
      Else
        ForwardProgress('Running tools…');
    End;
End;

Procedure TChildSubagent.ForwardProgress(Const Phase: String);
Var
  Event: TAssistantEvent;
  Cb: TAssistantTraceNotify;
Begin
  If (Not Assigned(FOwner)) Or (Trim(Phase) = '') Then
    Exit;
  Cb := FOwner.OnTrace;
  If Not Assigned(Cb) Then
    Exit;
  Event := Default(TAssistantEvent);
  Event.Kind := aekSubagentProgress;
  Event.ToolId := Id;
  Event.ToolName := KindName;
  Event.Text := Phase;
  Event.Ok := True;
  Try
    Cb(Event);
  Except
  End;
End;

Procedure TChildSubagent.HandleToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Begin
  EnterCriticalSection(FLock);
  Try
    If Trim(ContentSnapshot) <> '' Then
      Answer := ContentSnapshot;
    If IsFinished Then
      Begin
        If (ErrorText <> '') And (Not IsAssistantProgressStatus(ErrorText)) Then
          Begin
            FailText := ErrorText;
            Ok := False;
          End
        Else
          Ok := FailText = '';
        Finished := True;
      End;
  Finally
    LeaveCriticalSection(FLock);
  End;
  If IsFinished Then
    Begin
      If Assigned(FChild) Then
        FChild.MarkStreamComplete;
    End
  Else If ErrorText <> '' Then
    ForwardProgress(ErrorText);
End;

Function TChildSubagent.IsFinished: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := Finished;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TChildSubagent.SnapshotState: TChildSubagentState;
Begin
  Result := Default(TChildSubagentState);
  EnterCriticalSection(FLock);
  Try
    Result.Finished := Finished;
    Result.Ok := Ok;
    Result.FailText := FailText;
    Result.Answer := Answer;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TChildSubagent.Cancel;
Begin
  Abandon('Cancelled.');
End;

Procedure TChildSubagent.Abandon(Const Reason: String);
Begin
  { Do not WaitFor the child actor — this may run on the parent actor thread. }
  If Assigned(FChild) Then
    FChild.StopActorNoWait;
  EnterCriticalSection(FLock);
  Try
    If Not Finished Then
      Begin
        If Trim(Reason) <> '' Then
          FailText := Reason
        Else If FailText = '' Then
          FailText := 'Cancelled.';
        Ok := False;
        Finished := True;
      End;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TChildSubagent.BindAndStart(Const Request: TSubagentRequest; ParentMode: TAssistantMode;
      Const Provider: IAssistantModelProvider;
  Const ApiBase, Model, Skill, Effort, CompileLog: String; Out ErrorText: String): Boolean;
Var
  UserPrompt: String;
Begin
  Result := False;
  ErrorText := '';
  FChild := TAssistantService.Create;
  FChild.SetModelProvider(Provider);
  FChild.SetEndpoint(ApiBase, Model);
  FChild.SetActiveSkill(Skill);
  FChild.ReasoningEffort := SubagentReasoningEffort(Effort);
  If Assigned(AssistantChatConfig) Then
    Begin
      FChild.AnswerVerbosity := AssistantChatConfig.AnswerVerbosity;
      FChild.MaxOutputTokens := AssistantChatConfig.MaxOutputTokens;
      FChild.SearchMode := AssistantChatConfig.SearchMode;
      FChild.SearchCitations := AssistantChatConfig.SearchCitations;
    End;
  FChild.SetActiveMode(SubagentModeForKind(Request.Kind, ParentMode));
  FChild.ConfigureAsSubagent(SubagentKindName(Request.Kind));
  UserPrompt := BuildSubagentUserPrompt(Request, CompileLog);
  FChild.AddMessage(amrUser, UserPrompt);
  FChild.OnTrace := @HandleChildTrace;
  If Not FChild.StartStream(@HandleToken) Then
    Begin
      ErrorText := FChild.LastError;
      If ErrorText = '' Then
        ErrorText := 'Subagent failed to start.';
      FreeAndNil(FChild);
      Exit;
    End;
  Result := True;
End;

{ TAssistantService }

Function ModeSystemPromptBase(Mode: TAssistantMode): String;
Var
  PlanPath: String;
Begin
  Case Mode Of
    amChat:
      Result :=
        'You are a helpful assistant in a general chat. ' +
        'You have no project tools, no IDE access, and no attached skill. ' +
        'Answer directly. Do not claim you can read, search, or edit files. ' +
        'If the question needs the Lazarus project, say the user can switch to Inspect, Document, Plan, or Build.';
    amPlan:
      Begin
        PlanPath := GetActivePlanRelativePath;
        If PlanPath = '' Then
          PlanPath := 'Documents/Plan.md';
        Result :=
          'You are the Project Assistant in **Plan mode** for Free Pascal / Lazarus. ' +
          'Your job is to write durable plan Markdown into project files via tools — NOT only into the chat. ' +
          LineEnding +
          '**Hard rules:**' + LineEnding +
          '1. When the user asks for a plan or implementation plan, you MUST call `write_markdown` ' +
          '(full rewrite) or `update_markdown` (surgical edit) so the plan file on disk is updated. ' +
          '2. Do NOT put the full plan body only in the chat reply. Chat should be a short summary ' +
          '(what changed, which file, next steps). The Markdown file is the source of truth. ' +
          '3. Default / active plan path: **' + PlanPath + '**. Use that path unless the user names another. ' +
          '4. ' + AssistantPlanAuthoringRules + LineEnding +
          '5. Prefer `update_markdown` for Status: lines or a single section; `write_markdown` for new files or full plans. ' +
          '6. After writing, you may call `set_active_plan` and `open_markdown` if helpful. ' +
          '7. Never edit source (.pas/.lfm) in Plan mode. ' +
          LineEnding +
          'Tools: read_file, read_image, list_directory, open_markdown, get_project_info, write_markdown, ' +
          'update_markdown, list_plans, get_active_plan, set_active_plan.';
      End;
    amDocument:
      Result :=
        'You are the Project Assistant in **Document mode** for Free Pascal / Lazarus. ' +
        'Write free-form Markdown reports and notes with write_markdown or update_markdown. ' +
        'The user prompt decides the layout. Do not use the assistant plan format, the plan identity line, or Status lines. ' +
        'Do not call set_active_plan. Do not write the active plan. Do not edit source files. ' +
        'Chat is a short summary. The Markdown file is the source of truth when you produce or revise a document. ' +
        'You may read and search the project first. ' +
        'Tools: read_file, read_image, list_directory, grep, search_in_project, open_file, open_markdown, ' +
        'get_project_info, write_markdown, update_markdown.';
    amBuild:
      Result :=
        'You are the Project Assistant in **Build mode** for Free Pascal / Lazarus. ' +
        'You implement changes by calling tools — do not only describe patches.' + LineEnding +
        LineEnding +
        '**Source tools (prefer these):**' + LineEnding +
        '- `search_in_project` — find symbols/strings before bulk reads' + LineEnding +
        '- `read_file` — page large files with start_line/end_line' + LineEnding +
        '- `read_image` — copy a project image into the next model turn. The result is the name, dimensions, and id only.' + LineEnding +
        '- `replace_in_file` — exact surgical edit (small unique old_text)' + LineEnding +
        '- `write_file` — real project files only (never empty, never ApiProbe/scratch/temp units)' + LineEnding +
        '- `replace_in_file` — exact surgical edit' + LineEnding +
        '- `ensure_form_component` — add/update a component in BOTH .pas and .lfm (TTimer, TButton, events). ' +
        'Required for form wiring; do not claim LFM changes without calling this or editing the .lfm.' + LineEnding +
        '- `add_unit_to_project` — register an existing .pas with the .lpi' + LineEnding +
        '- `open_file` — open in the IDE editor' + LineEnding +
        '- `run_compile` — **prefer quiet** (default): non-visual lazbuild, no Messages UI. ' +
        'Use `ui=true` only for a final IDE Messages check.' + LineEnding +
        '- `run_project` — start the built executable directly. No shell and no debugger.' + LineEnding +
        '- `run_tests` — run the enabled test command for this target. Arguments are not passed through a shell.' + LineEnding +
        '- `delete_path` / `rename_path` — one path inside the project root. Refuses the root, Git metadata, and the project file.' + LineEnding +
        LineEnding +
        '**Forms / LFM (critical — compile success is not enough):**' + LineEnding +
        '- Declaring a field in .pas does **not** create or wire the component. Events fire only when the ' +
        'matching .lfm has `object Name: TClass` and `OnEvent = MethodName`.' + LineEnding +
        '- Prefer `ensure_form_component` for timers, buttons, actions, etc. It patches .pas **and** .lfm.' + LineEnding +
        '- Example: ensure_form_component path=unit1.pas name=ColorTimer class_name=TTimer ' +
        'properties={"Interval":1000,"Enabled":true,"OnTimer":"ColorTimerTimer"} ' +
        'event_method=ColorTimerTimer uses_unit=ExtCtrls' + LineEnding +
        '- Then `replace_in_file` the handler body (ColorTimerTimer) with real logic.' + LineEnding +
        '- TTimer.Interval is **milliseconds** (1000 = once per second, not 100).' + LineEnding +
        '- Never claim the form works until the .lfm was actually edited in this turn.' + LineEnding +
        LineEnding +
        '**Plan tools:** update_markdown / write_markdown only for plan Status: or short plan notes — ' +
        'not for dumping code deliverables into the plan.' + LineEnding +
        LineEnding +
        '**Do not** create temporary probe units (ApiProbe.pas, _ApiProbe, Scratch*) or empty files to test compiles. ' +
        'Discover symbols with `search_in_project` / `list_directory` / `read_file` only.' + LineEnding +
        LineEnding +
        '**Workflow:** search → read → edit (.pas and .lfm) → run_compile → fix until clean. ' +
        AssistantPlanCompletionRules + ' ' +
        'Stay on the active work package. Actionable plan items are `###` headings with a `Status:` line; ' +
        '`##` headings are context and must not receive a Status line. Prefer Michell Free Pascal conventions.' + LineEnding +
        LineEnding +
        '`read_file` returns the open editor buffer when the file is open — use that text for ' +
        '`replace_in_file` old_text. Prefer `search_in_project`/`grep` before paging huge files. ' +
        'If a turn hits the tool-round limit, continue from existing tool results instead of re-reading.';
  Else
    Result :=
      'You are a helpful Free Pascal / Lazarus expert working inside the IDE (Inspect mode). ' +
      'You may call read_file, read_image, list_directory, grep, search_in_project, open_file, open_markdown, and get_project_info. ' +
      'read_image copies a project image into the next model turn and returns the name, dimensions, and id only. ' +
      'open_file opens a source tab and does not modify it. search_in_project searches project text. ' +
      'For large files use read_file start_line/end_line to page; if a result says truncated, continue from the suggested start_line instead of re-reading from line 1. ' +
      'Prefer the active editor context already in the user message when it includes the code under discussion. ' +
      'You cannot call write_file, replace_in_file, write_markdown, run_compile, or run_git in Inspect mode — ' +
      'ask the user to switch to Document for a report, Plan for a build plan, or Build for source edits. ' +
      'The house skill is attached only when the user pins it.';
  End;
End;

Constructor TAssistantService.Create;
Begin
  Inherited Create;
  FProvider := CreateXaiModelProvider;
  FApiBase := AssistantConfigDefaultApiBase;
  FModel := AssistantConfigDefaultModel;
  FBaseSystemPrompt := ModeSystemPromptBase(amChat);
  FActiveSkill := '';
  FActiveMode := amChat;
  FSystemPrompt := FBaseSystemPrompt;
  FSystemPromptEscaped := JsonEscapeText(FSystemPrompt);
  FToolsJsonCache := '';
  FToolsJsonMode := amChat;
  FToolsJsonValid := False;
  FToolsEnabled := True;
  { Grok / xAI chat models often hard-cap near 500k tokens; stay under with margin. }
  FMaxPromptTokens := 420000;
  FLastTrimNotice := '';
  FReasoningEffort := 'high';
  FAnswerVerbosity := 'medium';
  FMaxOutputTokens := 0;
  FSearchMode := 'off';
  FSearchCitations := False;
  SetLength(FMessages, 0);
  FStreamThread := Nil;
  FOrphanThreads := Nil;
  FBusy := False;
  FLastError := '';
  FIsSubagent := False;
  FSubagentKindName := '';
  FLastEventsFile := '';
  InitCriticalSection(FSubagentsLock);
  FSubagents := TObjectList.Create(True);
  FDeferredSubagents := TFPList.Create;
End;

Procedure TAssistantService.ConfigureAsSubagent(Const KindName: String);
Begin
  FIsSubagent := True;
  FSubagentKindName := Trim(KindName);
  FToolsJsonValid := False;
  RebuildSystemPrompt;
End;

Procedure TAssistantService.SetActiveMode(Mode: TAssistantMode);
Begin
  If FActiveMode <> Mode Then
    Begin
      FToolsJsonValid := False;
      FActiveMode := Mode;
      FBaseSystemPrompt := ModeSystemPromptBase(Mode);
      RebuildSystemPrompt;
      WorkflowLogger.Info('AssistantService', 'Active mode set to ' + AssistantModeToStr(Mode));
    End
  Else
    FActiveMode := Mode;
End;

Procedure TAssistantService.RebuildSystemPrompt;
Var
  Root, PlanRel: String;
  Names: TStringList;
  I: Integer;
Begin
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Root = '' Then
    Root := ProjectRootPath;
  PlanRel := GetActivePlanRelativePath;
  Names := TStringList.Create;
  Try
    If Assigned(AssistantChatConfig) Then
      AssistantChatConfig.CollectSkillsForMode(AssistantModeToStr(FActiveMode), Names);
    If Assigned(WorkflowAssistantHarness) Then
      FSystemPrompt := WorkflowAssistantHarness.BuildSystemPrompt(FActiveMode, Names, Root, PlanRel)
    Else If FActiveMode = amChat Then
      Begin
        FSystemPrompt := ModeSystemPromptBase(amChat);
        For I := 0 To Names.Count - 1 Do
          FSystemPrompt := BuildSystemPromptWithSkill(FSystemPrompt, Names[I]);
      End
    Else
      Begin
        FBaseSystemPrompt := ModeSystemPromptBase(FActiveMode);
        FSystemPrompt := FBaseSystemPrompt;
        For I := 0 To Names.Count - 1 Do
          FSystemPrompt := BuildSystemPromptWithSkill(FSystemPrompt, Names[I]);
      End;
  Finally
    Names.Free;
  End;
  If FIsSubagent Then
    FSystemPrompt := FSystemPrompt + LineEnding + LineEnding +
      SubagentPersonaPrompt(ParseSubagentKind(FSubagentKindName))
  Else
    FSystemPrompt := FSystemPrompt + LineEnding + AssistantImageSystemSentence;
  FBaseSystemPrompt := FSystemPrompt;
  FSystemPromptEscaped := JsonEscapeText(FSystemPrompt);
End;

Function TAssistantService.EscapedContent(Var Msg: TAssistantMessage): String;
Begin
  If Msg.ContentEscaped = '' Then
    Msg.ContentEscaped := JsonEscapeText(Msg.Content);
  Result := Msg.ContentEscaped;
End;

Function TAssistantService.EscapedToolCallId(Var Msg: TAssistantMessage): String;
Begin
  If Msg.ToolCallIdEscaped = '' Then
    Msg.ToolCallIdEscaped := JsonEscapeText(Msg.ToolCallId);
  Result := Msg.ToolCallIdEscaped;
End;

Function TAssistantService.ToolsJsonCached: String;
Begin
  If (Not FToolsJsonValid) Or (FToolsJsonMode <> FActiveMode) Then
    Begin
      FToolsJsonCache := BuildAssistantToolsJsonForSession(FActiveMode, Not FIsSubagent);
      FToolsJsonMode := FActiveMode;
      FToolsJsonValid := True;
    End;
  Result := FToolsJsonCache;
End;

Function TAssistantService.BuildRequestJson: String;
Var
  I, PartCount, TotalLen, P, J, L: Integer;
  Parts: Array Of String;
  HasSystem: Boolean;
  MsgJson, Joined: String;
Begin
  { Pre-size and single-copy join — avoids quadratic string growth on long chats.
    Message bodies use cached JSON escapes filled on first use. }
  SetLength(Parts, Length(FMessages) + 2);
  PartCount := 0;
  HasSystem := False;
  If Trim(FSystemPrompt) <> '' Then
    Begin
      If FSystemPromptEscaped = '' Then
        FSystemPromptEscaped := JsonEscapeText(FSystemPrompt);
      Parts[PartCount] := '{"role":"system","content":"' + FSystemPromptEscaped + '"}';
      Inc(PartCount);
      HasSystem := True;
    End;
  For I := 0 To High(FMessages) Do
    Begin
      If (FMessages[I].Role = amrSystem) And HasSystem Then
        Continue;
      If FMessages[I].Role = amrTool Then
        MsgJson := '{"role":"tool","tool_call_id":"' + EscapedToolCallId(FMessages[I]) +
          '","content":"' + EscapedContent(FMessages[I]) + '"}'
      Else If FMessages[I].ToolCallsJson <> '' Then
        MsgJson := '{"role":"assistant","content":"' + EscapedContent(FMessages[I]) +
          '","tool_calls":' + FMessages[I].ToolCallsJson + '}'
      Else
        MsgJson := '{"role":"' + RoleToJson(FMessages[I].Role) + '","content":"' +
          EscapedContent(FMessages[I]) + '"}';
      Parts[PartCount] := MsgJson;
      Inc(PartCount);
    End;
  TotalLen := 0;
  For J := 0 To PartCount - 1 Do
    Begin
      Inc(TotalLen, Length(Parts[J]));
      If J > 0 Then
        Inc(TotalLen);
    End;
  SetLength(Joined, TotalLen);
  P := 1;
  For J := 0 To PartCount - 1 Do
    Begin
      If J > 0 Then
        Begin
          Joined[P] := ',';
          Inc(P);
        End;
      L := Length(Parts[J]);
      If L > 0 Then
        Move(Parts[J][1], Joined[P], L);
      Inc(P, L);
    End;
  If FToolsEnabled And (Trim(ToolsJsonCached) <> '') Then
    Result := '{"model":"' + JsonEscapeText(FModel) + '","stream":true,"messages":[' + Joined +
      '],"tools":' + ToolsJsonCached
  Else
    Result := '{"model":"' + JsonEscapeText(FModel) + '","stream":true,"messages":[' + Joined + ']';
  { Reasoning effort (thinking level): low | medium | high | xhigh. }
  If Trim(FReasoningEffort) <> '' Then
    Result := Result + ',"reasoning_effort":"' + JsonEscapeText(LowerCase(Trim(FReasoningEffort))) + '"';
  Result := Result + '}';
End;

Function RunningOnMainThread: Boolean;
Begin
  Result := GetCurrentThreadId = MainThreadID;
End;

Destructor TAssistantService.Destroy;
Begin
  DetachStreamCallbacks;
  CancelSubagents;
  If RunningOnMainThread Then
    Begin
      CancelStream;
      ReapOrphanThreads(1500);
    End
  Else
    Begin
      StopActorNoWait;
      ReapOrphanThreads(0);
    End;
  If Assigned(FOrphanThreads) Then
    Begin
      If FOrphanThreads.Count > 0 Then
        StealOrphanThreads(FOrphanThreads);
      FreeAndNil(FOrphanThreads);
    End;
  SetLength(FMessages, 0);
  TThread.RemoveQueuedEvents(Nil, @FlushDeferredSubagents);
  FlushDeferredSubagents;
  FreeAndNil(FDeferredSubagents);
  FreeAndNil(FSubagents);
  DoneCriticalSection(FSubagentsLock);
  Inherited Destroy;
End;

Function TAssistantService.HasUnfinishedActor: Boolean;
Var
  I: Integer;
  Thread: TThread;
Begin
  Result := Assigned(FStreamThread) And (Not FStreamThread.Finished);
  If Result Then
    Exit;
  If Not Assigned(FOrphanThreads) Then
    Exit;
  For I := 0 To FOrphanThreads.Count - 1 Do
    Begin
      Thread := TThread(FOrphanThreads[I]);
      If Assigned(Thread) And (Not Thread.Finished) Then
        Begin
          Result := True;
          Exit;
        End;
    End;
End;

Procedure TAssistantService.ReapOrphanThreads(WaitMs: QWord);
Var
  I: Integer;
  Thread: TThread;
  StartTick: QWord;
  Remaining: Boolean;
Begin
  If Not Assigned(FOrphanThreads) Then
    Exit;
  StartTick := GetTickCount64;
  Repeat
    Remaining := False;
    I := 0;
    While I < FOrphanThreads.Count Do
      Begin
        Thread := TThread(FOrphanThreads[I]);
        If Not Assigned(Thread) Then
          Begin
            FOrphanThreads.Delete(I);
            Continue;
          End;
        If Thread.Finished Then
          Begin
            Try
              Thread.WaitFor;
            Except
            End;
            Thread.Free;
            FOrphanThreads.Delete(I);
          End
        Else
          Begin
            Remaining := True;
            Inc(I);
          End;
      End;
    If (Not Remaining) Or (GetTickCount64 - StartTick >= WaitMs) Then
      Break;
    If RunningOnMainThread Then
      CheckSynchronize(15)
    Else
      Sleep(15);
    Sleep(5);
  Until False;
End;

Procedure TAssistantService.AbandonStreamThread;
Begin
  If Not Assigned(FStreamThread) Then
    Exit;
  If FStreamThread Is TAssistantActor Then
    TAssistantActor(FStreamThread).Detach;
  If Not Assigned(FOrphanThreads) Then
    FOrphanThreads := TFPList.Create;
  FOrphanThreads.Add(FStreamThread);
  FStreamThread := Nil;
End;

Procedure TAssistantService.ClearStreamThread;
Var
  StartTick: QWord;
  Actor: TAssistantActor;
Begin
  ReapOrphanThreads(0);
  If Not Assigned(FStreamThread) Then
    Begin
      FBusy := False;
      Exit;
    End;
  If FStreamThread Is TAssistantActor Then
    Begin
      Actor := TAssistantActor(FStreamThread);
      Actor.Cancel;
    End
  Else
    FStreamThread.Terminate;
  { Pump Queue/Synchronize only on the main thread. Workers must not call
    CheckSynchronize — it deadlocks a child waiting in Queue/Synchronize. }
  StartTick := GetTickCount64;
  While (Not FStreamThread.Finished) And (GetTickCount64 - StartTick < 1500) Do
    Begin
      If RunningOnMainThread Then
        CheckSynchronize(15);
      Sleep(5);
    End;
  Try
    If FStreamThread.Finished Then
      Begin
        FStreamThread.WaitFor;
        FreeAndNil(FStreamThread);
      End
    Else
      Begin
        WorkflowLogger.Warning('AssistantService', 'Actor did not finish within 1.5s; detaching');
        AbandonStreamThread;
      End;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Warning('AssistantService', 'ClearStreamThread: ' + E.Message);
        AbandonStreamThread;
      End;
  End;
  FBusy := False;
End;

Procedure TAssistantService.ApplyConfig(Config: TAssistantConfig);
Begin
  If Not Assigned(Config) Then
    Exit;
  SetEndpoint(Config.ApiBase, Config.Model);
  SetActiveSkill(Config.ActiveSkill);
  FReasoningEffort := ThinkingLevelToStr(Config.GetThinkingLevel);
  FAnswerVerbosity := Config.AnswerVerbosity;
  FMaxOutputTokens := Config.MaxOutputTokens;
  FSearchMode := Config.SearchMode;
  FSearchCitations := Config.SearchCitations;
  If FProvider.BackendId = 'xai-subscription' Then
    RestoreXaiCredentials(Config);
End;

Procedure TAssistantService.SetEndpoint(Const ApiBase, Model: String);
Begin
  If ApiBase <> '' Then
    FApiBase := ApiBase;
  If Model <> '' Then
    FModel := Model;
  WorkflowLogger.Info('AssistantService', 'Endpoint updated – model=' + FModel);
End;

Procedure TAssistantService.SetActiveSkill(Const SkillName: String);
Var
  NewName: String;
Begin
  NewName := Trim(SkillName);
  If SameText(FActiveSkill, NewName) And (FSystemPrompt <> '') Then
    Begin
      { Rebuild only if skill file may have changed (cache checks mtime). }
      RebuildSystemPrompt;
      Exit;
    End;
  FActiveSkill := NewName;
  RebuildSystemPrompt;
  If FActiveSkill <> '' Then
    WorkflowLogger.Info('AssistantService', 'Active skill set to ' + FActiveSkill)
  Else
    WorkflowLogger.Info('AssistantService', 'Active skill cleared');
End;

Procedure TAssistantService.ClearHistory;
Begin
  SetLength(FMessages, 0);
  FStoredMessageCount := 0;
  FLastTrimNotice := '';
End;

Procedure TAssistantService.InvalidateMessageEscape(Var Msg: TAssistantMessage);
Begin
  Msg.ContentEscaped := '';
  Msg.ToolCallIdEscaped := '';
End;

Procedure TAssistantService.TruncateMessageContent(Var Msg: TAssistantMessage; MaxChars: Integer;
  Const LabelText: String);
Var
  KeepHead, KeepTail: Integer;
  Body: String;
Begin
  If MaxChars < 64 Then
    MaxChars := 64;
  If Length(Msg.Content) <= MaxChars Then
    Exit;
  KeepHead := (MaxChars * 2) Div 3;
  KeepTail := MaxChars - KeepHead - 80;
  If KeepTail < 40 Then
    KeepTail := 40;
  Body := Copy(Msg.Content, 1, KeepHead) + LineEnding +
    Format('[… %s truncated from %d chars for context budget …]',
      [LabelText, Length(Msg.Content)]) + LineEnding +
    Copy(Msg.Content, Length(Msg.Content) - KeepTail + 1, KeepTail);
  Msg.Content := Body;
  InvalidateMessageEscape(Msg);
End;

Function TAssistantService.MessagePayloadChars(Const Msg: TAssistantMessage): Integer;
Begin
  { Text only. Image refs are paths; file bytes and data URIs are not in the message. }
  Result := Length(Msg.Content) + Length(Msg.ToolCallsJson) + Length(Msg.ToolCallId);
  If Length(Msg.ResponsesOutputJson) > Result Then
    Result := Length(Msg.ResponsesOutputJson);
End;

Function TAssistantService.CountRequestImages: Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 0 To High(FMessages) Do
    Inc(Result, Length(FMessages[I].ImageRefs));
End;

Function TAssistantService.EstimatePromptTokens: Integer;
Var
  I, Chars: Integer;
Begin
  Chars := Length(FSystemPrompt) + Length(ToolsJsonCached) + 256;
  For I := 0 To High(FMessages) Do
    Inc(Chars, MessagePayloadChars(FMessages[I]));
  { ~4 characters per token is a common rough estimate for mixed code/text.
    Each image still on the next request adds a flat token charge, not its bytes. }
  Result := (Chars + 3) Div 4 + CountRequestImages * AssistantImageContextTokens;
  If Result < 1 Then
    Result := 1;
End;

Function TAssistantService.EstimatedPromptTokens: Integer;
Begin
  Result := EstimatePromptTokens;
End;

Function TokenEstimateFromChars(Chars: Integer): Integer;
Begin
  Result := (Chars + 3) Div 4;
  If Result < 0 Then
    Result := 0;
End;

Function TAssistantService.GetContextBreakdown: TAssistantContextBreakdown;
Var
  I, SysChars, ToolChars, HistChars: Integer;
Begin
  SysChars := Length(FSystemPrompt) + 256;
  ToolChars := Length(ToolsJsonCached);
  HistChars := 0;
  For I := 0 To High(FMessages) Do
    Inc(HistChars, MessagePayloadChars(FMessages[I]));
  Result.SystemTokens := TokenEstimateFromChars(SysChars);
  Result.ToolsTokens := TokenEstimateFromChars(ToolChars);
  Result.HistoryTokens := TokenEstimateFromChars(HistChars);
  Result.ImageCount := CountRequestImages;
  Result.ImageTokens := Result.ImageCount * AssistantImageContextTokens;
  Result.TotalTokens := TokenEstimateFromChars(SysChars + ToolChars + HistChars) + Result.ImageTokens;
  If Result.TotalTokens < 1 Then
    Result.TotalTokens := 1;
  Result.LimitTokens := FMaxPromptTokens;
  Result.MessageCount := Length(FMessages);
End;

Function TAssistantService.CompactOlderHistory: Integer;
Var
  Before, SavedMax, Target: Integer;
Begin
  Before := EstimatePromptTokens;
  SavedMax := FMaxPromptTokens;
  Target := (Before * 6) Div 10;
  If Target < 40000 Then
    Target := 40000;
  If Target >= Before Then
    Target := Before - 1;
  If Target < 1 Then
    Target := 1;
  FMaxPromptTokens := Target;
  Try
    TrimMessagesForBudget;
  Finally
    FMaxPromptTokens := SavedMax;
  End;
  Result := Before - EstimatePromptTokens;
  If Result < 0 Then
    Result := 0;
End;

Procedure TAssistantService.DropMessageRange(FromIndex, Count: Integer);
Var
  I, N: Integer;
Begin
  N := Length(FMessages);
  If (Count < 1) Or (FromIndex < 0) Or (FromIndex >= N) Then
    Exit;
  If FromIndex + Count > N Then
    Count := N - FromIndex;
  For I := FromIndex To N - Count - 1 Do
    FMessages[I] := FMessages[I + Count];
  SetLength(FMessages, N - Count);
  If FromIndex < FStoredMessageCount Then
    FStoredMessageCount := FStoredMessageCount - Count;
  If FStoredMessageCount < 0 Then FStoredMessageCount := 0;
  If FStoredMessageCount > Length(FMessages) Then FStoredMessageCount := Length(FMessages);
End;

Procedure TAssistantService.OmitMessageImages(Var Msg: TAssistantMessage);
Var
  I: Integer;
  Note: String;
Begin
  If Length(Msg.ImageRefs) = 0 Then Exit;
  Note := '';
  For I := 0 To High(Msg.ImageRefs) Do
    Begin
      If Note <> '' Then Note := Note + LineEnding;
      Note := Note + AssistantImageOmittedNote(Msg.ImageRefs[I]);
    End;
  { Display files stay in the store. Clearing the refs keeps them off the next request. }
  SetLength(Msg.ImageRefs, 0);
  If Trim(Msg.Content) = '' Then
    Msg.Content := Note
  Else
    Msg.Content := Msg.Content + LineEnding + Note;
  InvalidateMessageEscape(Msg);
End;

Procedure TAssistantService.TrimMessagesForBudget;
Const
  MinMessagesToKeep = 6;
  RecentProtectCount = 14;
  OldToolMaxChars = 2500;
  OldUserMaxChars = 12000;
  RecentToolMaxChars = 48000;
Var
  Budget, Est, I, DropCount, ProtectFrom, UserTurns, StartDrop: Integer;
  Notice: String;
  Changed: Boolean;
Begin
  If FMaxPromptTokens < 50000 Then
    FMaxPromptTokens := 50000;
  Budget := FMaxPromptTokens;
  Changed := False;
  Est := EstimatePromptTokens;
  If Est <= Budget Then
    Exit;

  { Phase 1: aggressively shrink older tool results and huge user/assistant blobs.
    Use a While loop: dropping tool results shortens FMessages, so a For-to-High
    bound captured at entry would walk off the end. }
  ProtectFrom := Length(FMessages) - RecentProtectCount;
  If ProtectFrom < 0 Then
    ProtectFrom := 0;
  I := 0;
  While I <= High(FMessages) Do
    Begin
      If I >= ProtectFrom Then
        Begin
          If (FMessages[I].Role = amrTool) And (Length(FMessages[I].Content) > RecentToolMaxChars) Then
            Begin
              TruncateMessageContent(FMessages[I], RecentToolMaxChars, 'tool result');
              Changed := True;
            End;
          Inc(I);
          Continue;
        End;
      If Length(FMessages[I].ImageRefs) > 0 Then
        Begin
          OmitMessageImages(FMessages[I]);
          Changed := True;
        End;
      If FMessages[I].Role = amrTool Then
        Begin
          If Length(FMessages[I].Content) > OldToolMaxChars Then
            Begin
              TruncateMessageContent(FMessages[I], OldToolMaxChars, 'older tool result');
              Changed := True;
            End;
        End
      Else If Length(FMessages[I].Content) > OldUserMaxChars Then
        Begin
          TruncateMessageContent(FMessages[I], OldUserMaxChars, 'older message');
          Changed := True;
        End;
      { ToolCallsJson arguments can also be large (write_file content).
        Strip tool_calls entirely and drop following tool results so ids stay valid. }
      If Length(FMessages[I].ToolCallsJson) > 12000 Then
        Begin
          FMessages[I].ToolCallsJson := '';
          FMessages[I].ResponsesOutputJson := '';
          If Trim(FMessages[I].Content) = '' Then
            FMessages[I].Content :=
              '[Earlier assistant tool_calls were removed to fit the context window.]';
          InvalidateMessageEscape(FMessages[I]);
          While (I + 1 <= High(FMessages)) And (FMessages[I + 1].Role = amrTool) Do
            DropMessageRange(I + 1, 1);
          Changed := True;
          ProtectFrom := Length(FMessages) - RecentProtectCount;
          If ProtectFrom < 0 Then
            ProtectFrom := 0;
        End;
      Inc(I);
    End;

  Est := EstimatePromptTokens;
  { Phase 2: drop oldest complete turns (from the start through a user boundary). }
  While (Est > Budget) And (Length(FMessages) > MinMessagesToKeep) Do
    Begin
      { Prefer dropping from the start up to (not including) a later user message
        so we keep recent user→assistant→tool chains intact. }
      StartDrop := 0;
      DropCount := 1;
      UserTurns := 0;
      For I := High(FMessages) DownTo 0 Do
        If FMessages[I].Role = amrUser Then
          Begin
            Inc(UserTurns);
            If UserTurns >= 3 Then
              Begin
                { Keep from this user message onward; drop [0 .. I-1]. }
                DropCount := I;
                Break;
              End;
          End;
      If DropCount < 1 Then
        DropCount := 1;
      If DropCount >= Length(FMessages) - MinMessagesToKeep + 1 Then
        DropCount := Length(FMessages) - MinMessagesToKeep;
      If DropCount < 1 Then
        Break;
      DropMessageRange(StartDrop, DropCount);
      Changed := True;
      Est := EstimatePromptTokens;
      { After one large drop, re-loop; if still over, drop more from start one-by-one. }
      If (Est > Budget) And (Length(FMessages) > MinMessagesToKeep) Then
        Begin
          { Drop a leading assistant/tool orphan or single message. }
          DropCount := 1;
          If (Length(FMessages) > 1) And (FMessages[0].Role = amrAssistant) And
            (FMessages[0].ToolCallsJson <> '') Then
            Begin
              DropCount := 1;
              While (DropCount < Length(FMessages)) And (FMessages[DropCount].Role = amrTool) Do
                Inc(DropCount);
            End;
          If DropCount > Length(FMessages) - MinMessagesToKeep Then
            DropCount := Length(FMessages) - MinMessagesToKeep;
          If DropCount > 0 Then
            Begin
              DropMessageRange(0, DropCount);
              Est := EstimatePromptTokens;
            End
          Else
            Break;
        End;
    End;

  { Phase 3: last-resort truncate remaining tool results. }
  If Est > Budget Then
    For I := 0 To High(FMessages) Do
      If (FMessages[I].Role = amrTool) And (Length(FMessages[I].Content) > 1200) Then
        Begin
          TruncateMessageContent(FMessages[I], 1200, 'tool result');
          Changed := True;
        End;

  Est := EstimatePromptTokens;
  If Changed Then
    Begin
      Notice := Format(
        '[Context trimmed to fit the model limit: ~%d estimated tokens remain (budget %d). ' +
        'Older tool results and turns may be shortened or dropped. Re-read files if needed.]',
        [Est, Budget]);
      FLastTrimNotice := Notice;
      If (Length(FMessages) = 0) Or (Pos('[Context trimmed', FMessages[0].Content) < 1) Then
        Begin
          SetLength(FMessages, Length(FMessages) + 1);
          For I := High(FMessages) DownTo 1 Do
            FMessages[I] := FMessages[I - 1];
          FMessages[0].Role := amrUser;
          FMessages[0].Content := Notice;
          FMessages[0].ToolCallId := '';
          FMessages[0].ToolCallsJson := '';
          FMessages[0].ResponsesOutputJson := '';
          SetLength(FMessages[0].ImageRefs, 0);
          InvalidateMessageEscape(FMessages[0]);
        End
      Else
        Begin
          FMessages[0].Content := Notice;
          InvalidateMessageEscape(FMessages[0]);
        End;
      WorkflowLogger.Info('AssistantService',
        Format('Trimmed chat context to ~%d tokens (budget %d, messages=%d)',
          [EstimatePromptTokens, Budget, Length(FMessages)]));
    End;
End;

Procedure TAssistantService.AddUserMessage(Const Content: String; Const ImageRefs: TAssistantImageRefArray);
Var
  Refs: TAssistantImageRefArray;
Begin
  Refs := LimitAssistantImageRefs(ImageRefs);
  AddMessage(amrUser, AssistantImageModelText(Content, Length(Refs)));
  If Length(FMessages) < 1 Then Exit;
  FMessages[High(FMessages)].ImageRefs := Refs;
End;

Procedure TAssistantService.DropLastUserImageRefs;
Var
  I: Integer;
Begin
  For I := High(FMessages) DownTo 0 Do
    If FMessages[I].Role = amrUser Then
      Begin
        SetLength(FMessages[I].ImageRefs, 0);
        Exit;
      End;
End;

Function TAssistantService.ImagesAttachAllowed(Out Reason: String): Boolean;
Begin
  Reason := '';
  Result := True;
  { Missing list allows attach. Do not infer vision support from the model name. }
  If XaiModelImageInput(FModel) <> xiiAbsent Then Exit;
  Result := False;
  Reason := 'This model lists no image input. Attach is disabled.';
End;

Function TAssistantService.ExportUnstoredMessagesJson: String;
Var
  Arr: TJSONArray;
  Obj: TJSONObject;
  Node: TJSONData;
  I: Integer;
  RefsJson: String;
Begin
  Result := '';
  If FStoredMessageCount < 0 Then FStoredMessageCount := 0;
  If FStoredMessageCount > Length(FMessages) Then FStoredMessageCount := Length(FMessages);
  If FStoredMessageCount >= Length(FMessages) Then Exit;
  Arr := TJSONArray.Create;
  Try
    For I := FStoredMessageCount To High(FMessages) Do
      Begin
        Obj := TJSONObject.Create;
        Obj.Add('role', RoleToJson(FMessages[I].Role));
        Obj.Add('content', FMessages[I].Content);
        If FMessages[I].ToolCallId <> '' Then Obj.Add('tool_call_id', FMessages[I].ToolCallId);
        If Trim(FMessages[I].ToolCallsJson) <> '' Then
          Begin
            Node := Nil;
            Try
              Node := GetJSON(FMessages[I].ToolCallsJson);
            Except
              Node := Nil;
            End;
            If Assigned(Node) Then Obj.Add('tool_calls', Node) Else Node.Free;
          End;
        If Trim(FMessages[I].ResponsesOutputJson) <> '' Then
          Begin
            Node := Nil;
            Try
              Node := GetJSON(FMessages[I].ResponsesOutputJson);
            Except
              Node := Nil;
            End;
            If Assigned(Node) Then Obj.Add('responses_output', Node);
          End;
        If (FMessages[I].Role = amrUser) And (Length(FMessages[I].ImageRefs) > 0) Then
          Begin
            RefsJson := AssistantImageRefsToJson(FMessages[I].ImageRefs);
            If RefsJson <> '' Then
              Begin
                Node := Nil;
                Try
                  Node := GetJSON(RefsJson);
                Except
                  Node := Nil;
                End;
                If Assigned(Node) Then Obj.Add('attachments', Node);
              End;
          End;
        Arr.Add(Obj);
      End;
    If Arr.Count > 0 Then Result := Arr.AsJSON;
  Finally
    Arr.Free;
  End;
End;

Procedure TAssistantService.RestoreMessagesJson(Const JsonText: String);
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  RoleName, Content, ToolId, ToolCalls, Responses: String;
  Role: TAssistantMessageRole;
  Refs: TAssistantImageRefArray;
Begin
  If Trim(JsonText) = '' Then Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonText);
    Except
      Exit;
    End;
    If Not (Data Is TJSONArray) Then Exit;
    Arr := TJSONArray(Data);
    For I := 0 To Arr.Count - 1 Do
      If Arr.Items[I] Is TJSONObject Then
        Begin
          Obj := TJSONObject(Arr.Items[I]);
          RoleName := Obj.Get('role', 'user');
          Content := Obj.Get('content', '');
          ToolId := Obj.Get('tool_call_id', '');
          ToolCalls := '';
          Responses := '';
          If Assigned(Obj.Find('tool_calls')) Then ToolCalls := Obj.Find('tool_calls').AsJSON;
          If Assigned(Obj.Find('responses_output')) Then Responses := Obj.Find('responses_output').AsJSON;
          If RoleName = 'assistant' Then Role := amrAssistant
          Else If RoleName = 'tool' Then Role := amrTool
          Else If RoleName = 'system' Then Role := amrSystem
          Else Role := amrUser;
          If Role = amrTool Then
            AddToolResult(ToolId, Content)
          Else If (Role = amrAssistant) And (ToolCalls <> '') Then
            AddAssistantToolCalls(Content, ToolCalls, Responses)
          Else If Role = amrUser Then
            Begin
              SetLength(Refs, 0);
              If (Pos(AssistantImageOmittedPrefix, Content) < 1) And Assigned(Obj.Find('attachments')) Then
                ParseAssistantImageRefs(Obj.Find('attachments').AsJSON, Refs);
              AddUserMessage(Content, Refs);
            End
          Else
            AddMessage(Role, Content);
        End;
  Finally
    Data.Free;
  End;
End;

Procedure TAssistantService.NoteMessagesStored;
Begin
  FStoredMessageCount := Length(FMessages);
End;

Function TAssistantService.LastUserAttachmentsJson: String;
Var
  I: Integer;
Begin
  Result := '';
  For I := High(FMessages) DownTo 0 Do
    If FMessages[I].Role = amrUser Then
      Begin
        Result := AssistantImageRefsToJson(FMessages[I].ImageRefs);
        Exit;
      End;
End;

Function TAssistantService.OpeningUserAttachmentsJson: String;
Var
  I, Start: Integer;
Begin
  Result := '';
  Start := FStoredMessageCount;
  If Start < 0 Then Start := 0;
  If Start > Length(FMessages) Then Exit;
  For I := Start To High(FMessages) Do
    If FMessages[I].Role = amrUser Then
      Begin
        Result := AssistantImageRefsToJson(FMessages[I].ImageRefs);
        Exit;
      End;
End;

Procedure TAssistantService.EnsureUserImageRefsFrom(FromIndex: Integer; Const AttachmentsJson: String);
Var
  I: Integer;
  Refs: TAssistantImageRefArray;
Begin
  If FromIndex < 0 Then FromIndex := 0;
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Or (Length(Refs) = 0) Then Exit;
  For I := FromIndex To High(FMessages) Do
    If FMessages[I].Role = amrUser Then
      Begin
        If Pos(AssistantImageOmittedPrefix, FMessages[I].Content) > 0 Then Exit;
        If Length(FMessages[I].ImageRefs) = 0 Then
          FMessages[I].ImageRefs := LimitAssistantImageRefs(Refs);
        Exit;
      End;
End;

Procedure TAssistantService.EnsureLastUserImageRefs(Const AttachmentsJson: String);
Var
  I: Integer;
  Refs: TAssistantImageRefArray;
Begin
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Or (Length(Refs) = 0) Then Exit;
  For I := High(FMessages) DownTo 0 Do
    If FMessages[I].Role = amrUser Then
      Begin
        If Pos(AssistantImageOmittedPrefix, FMessages[I].Content) > 0 Then Exit;
        If Length(FMessages[I].ImageRefs) = 0 Then
          FMessages[I].ImageRefs := LimitAssistantImageRefs(Refs);
        Exit;
      End;
  AddUserMessage('', Refs);
End;

Procedure TAssistantService.AddMessage(Role: TAssistantMessageRole; Const Content: String);
Var
  Idx: Integer;
  Body: String;
Begin
  Body := Content;
  { Cap very large user payloads (e.g. repeated IDE dumps). }
  If (Role = amrUser) And (Length(Body) > 100000) Then
    Body := Copy(Body, 1, 90000) + LineEnding +
      Format('[… user message truncated from %d chars …]', [Length(Content)]);
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Body;
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := '';
  FMessages[Idx].ResponsesOutputJson := '';
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
  SetLength(FMessages[Idx].ImageRefs, 0);
End;

Procedure TAssistantService.AddAssistantToolCalls(Const Content, ToolCallsJson: String;
  Const ResponsesOutputJson: String);
Var
  Idx: Integer;
Begin
  { Never replace real call IDs with a synthetic truncated call: the following
    tool outputs still refer to the original IDs. Budget trimming removes groups. }
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrAssistant;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := ToolCallsJson;
  FMessages[Idx].ResponsesOutputJson := ResponsesOutputJson;
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Procedure TAssistantService.AddToolResult(Const ToolCallId, Content: String);
Const
  MaxToolChars = 40000;
Var
  Idx: Integer;
  Body: String;
Begin
  Body := Content;
  If Length(Body) > MaxToolChars Then
    Body := Copy(Body, 1, MaxToolChars - 120) + LineEnding +
      Format('[… tool result truncated from %d chars at store time; re-read with start_line if needed …]',
        [Length(Content)]);
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrTool;
  FMessages[Idx].Content := Body;
  FMessages[Idx].ToolCallId := ToolCallId;
  FMessages[Idx].ToolCallsJson := '';
  FMessages[Idx].ResponsesOutputJson := '';
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Function TAssistantService.BuildNextRequestJson: String;
Begin
  TrimMessagesForBudget;
  Result := BuildRequestJson;
End;

Procedure AppendSamplerItem(Var Items: TSamplerInputItemArray; Var Count: Integer; Const Item: TSamplerInputItem);
Begin
  If Count >= Length(Items) Then
    Begin
      If Length(Items) = 0 Then
        SetLength(Items, 16)
      Else
        SetLength(Items, Length(Items) * 2);
    End;
  Items[Count] := Item;
  Inc(Count);
End;

Function TAssistantService.ExportSamplerItems(ForResponses: Boolean): TSamplerInputItemArray;
Var
  I, C, CallIndex, J: Integer;
  Data: TJSONData;
  Item: TSamplerInputItem;
  Calls: TSamplerToolCallArray;
  RoleName: String;
Begin
  Result := Nil;
  TrimMessagesForBudget;
  SetLength(Result, 0);
  C := 0;
  If Trim(FSystemPrompt) <> '' Then
    AppendSamplerItem(Result, C, SamplerInputMessage('system', FSystemPrompt));
  For I := 0 To High(FMessages) Do
    Begin
      If FMessages[I].Role = amrTool Then
        AppendSamplerItem(Result, C, SamplerInputFunctionOutput(FMessages[I].ToolCallId, FMessages[I].Content))
      Else If ForResponses And (FMessages[I].ResponsesOutputJson <> '') Then
        Begin
          Data := GetJSON(FMessages[I].ResponsesOutputJson);
          Try
            If Not (Data Is TJSONArray) Then
              Raise Exception.Create('Invalid stored Responses output.');
            For J := 0 To Data.Count - 1 Do
              Begin
                Item := Default(TSamplerInputItem);
                Item.Kind := sikProviderOutput;
                Item.ProviderJson := Data.Items[J].AsJSON;
                AppendSamplerItem(Result, C, Item);
              End;
          Finally
            Data.Free;
          End;
        End
      Else If FMessages[I].ToolCallsJson <> '' Then
        Begin
          If Trim(FMessages[I].Content) <> '' Then
            AppendSamplerItem(Result, C, SamplerInputMessage('assistant', FMessages[I].Content));
          If ParseOpenAiToolCallsJson(FMessages[I].ToolCallsJson, Calls) Then
            For CallIndex := 0 To High(Calls) Do
              If Calls[CallIndex].Name <> '' Then
                AppendSamplerItem(Result, C,
                  SamplerInputFunctionCall(Calls[CallIndex].Id, Calls[CallIndex].Name, Calls[CallIndex].Arguments));
        End
      Else
        Begin
          RoleName := RoleToJson(FMessages[I].Role);
          Item := SamplerInputMessage(RoleName, FMessages[I].Content);
          If FMessages[I].Role = amrUser Then
            Item.ImageRefs := LimitAssistantImageRefs(FMessages[I].ImageRefs);
          AppendSamplerItem(Result, C, Item);
        End;
    End;
  SetLength(Result, C);
End;

Procedure TAssistantService.EnqueueSteer(Const Text: String);
Var
  Refs: TAssistantImageRefArray;
Begin
  SetLength(Refs, 0);
  EnqueueSteer(Text, Refs);
End;

Function TAssistantService.EnqueueSteer(Const Text: String; Const ImageRefs: TAssistantImageRefArray): Boolean;
Begin
  Result := False;
  { Mode and tool permissions stay as they were when the turn started. }
  If Assigned(FStreamThread) And (FStreamThread Is TAssistantActor) Then
    Result := TAssistantActor(FStreamThread).EnqueueSteer(Text, ImageRefs);
End;

Function TAssistantService.IsSubagentSession: Boolean;
Begin
  Result := FIsSubagent;
End;

Function TAssistantService.FindSubagentLocked(Const RunId: String): TObject;
Var
  I: Integer;
  Child: TChildSubagent;
Begin
  Result := Nil;
  If (Not Assigned(FSubagents)) Or (RunId = '') Then
    Exit;
  For I := 0 To FSubagents.Count - 1 Do
    Begin
      Child := TChildSubagent(FSubagents[I]);
      If Assigned(Child) And (Child.Id = RunId) Then
        Begin
          Result := Child;
          Exit;
        End;
    End;
End;

Function TAssistantService.LiveSubagentCount: Integer;
Var
  I: Integer;
  Child: TChildSubagent;
Begin
  Result := 0;
  EnterCriticalSection(FSubagentsLock);
  Try
    If Not Assigned(FSubagents) Then
      Exit;
    For I := 0 To FSubagents.Count - 1 Do
      Begin
        Child := TChildSubagent(FSubagents[I]);
        If Assigned(Child) And (Not Child.IsFinished) Then
          Inc(Result);
      End;
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
End;

Function TAssistantService.StartSubagent(Const ArgumentsJson: String; Out RunId: String;
  Out ErrorText: String): Boolean;
Var
  Request: TSubagentRequest;
  Child: TChildSubagent;
  Live, Index: Integer;
  CompileLog: String;
Begin
  Result := False;
  RunId := '';
  ErrorText := '';
  If Not ParseSpawnSubagentArguments(ArgumentsJson, Request, ErrorText) Then
    Exit;
  EnterCriticalSection(FSubagentsLock);
  Try
    Live := 0;
    If Assigned(FSubagents) Then
      For Index := 0 To FSubagents.Count - 1 Do
        Begin
          Child := TChildSubagent(FSubagents[Index]);
          If Assigned(Child) And (Not Child.IsFinished) Then
            Inc(Live);
        End;
    If Not CanSpawnSubagent(Not FIsSubagent, Live, ErrorText) Then
      Exit;
    Child := TChildSubagent.Create(Self);
    Child.Id := 'sub_' + IntToStr(InterlockedIncrement(GSubagentSeq));
    Child.KindName := SubagentKindName(Request.Kind);
    Child.Title := Request.Title;
    FSubagents.Add(Child);
    RunId := Child.Id;
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
  If RunId = '' Then
    Exit;
  CompileLog := '';
  If Request.Kind = sakPascalReview Then
    CompileLog := AssistantLastCompileLog;
  If Not Child.BindAndStart(Request, FActiveMode, FProvider, FApiBase, FModel, FActiveSkill, FReasoningEffort,
    CompileLog, ErrorText) Then
    Begin
      EnterCriticalSection(FSubagentsLock);
      Try
        FSubagents.Remove(Child);
      Finally
        LeaveCriticalSection(FSubagentsLock);
      End;
      RunId := '';
      Exit;
    End;
  Result := True;
  WorkflowLogger.Info('AssistantService', 'Subagent started ' + RunId + ' kind=' + Child.KindName);
End;

Function TAssistantService.SubagentIsRunning(Const RunId: String): Boolean;
Var
  Child: TChildSubagent;
Begin
  Result := False;
  EnterCriticalSection(FSubagentsLock);
  Try
    Child := TChildSubagent(FindSubagentLocked(RunId));
    If Not Assigned(Child) Then
      Exit;
    Result := Not Child.IsFinished;
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
End;

Procedure TAssistantService.StopActorNoWait;
Var
  Actor: TAssistantActor;
Begin
  If Not Assigned(FStreamThread) Then
    Begin
      FBusy := False;
      Exit;
    End;
  If FStreamThread Is TAssistantActor Then
    Begin
      Actor := TAssistantActor(FStreamThread);
      Actor.Cancel;
      Actor.Detach;
    End
  Else
    FStreamThread.Terminate;
  AbandonStreamThread;
  FBusy := False;
End;

Procedure TAssistantService.AbandonSubagent(Const RunId, Reason: String);
Var
  Child: TChildSubagent;
Begin
  EnterCriticalSection(FSubagentsLock);
  Try
    Child := TChildSubagent(FindSubagentLocked(RunId));
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
  If Assigned(Child) Then
    Child.Abandon(Reason);
End;

Procedure TAssistantService.FlushDeferredSubagents;
Var
  Obj: TObject;
Begin
  Repeat
    Obj := Nil;
    EnterCriticalSection(FSubagentsLock);
    Try
      If Assigned(FDeferredSubagents) And (FDeferredSubagents.Count > 0) Then
        Begin
          Obj := TObject(FDeferredSubagents[0]);
          FDeferredSubagents.Delete(0);
        End;
    Finally
      LeaveCriticalSection(FSubagentsLock);
    End;
    If Not Assigned(Obj) Then Exit;
    { Destruction can pump callbacks; never hold the list lock here. }
    Obj.Free;
  Until False;
End;

Procedure TAssistantService.AbandonTimedOutSubagents;
Var
  I: Integer;
  NowTick: QWord;
  Child: TChildSubagent;
  Snapshot: Array Of TChildSubagent;
Begin
  NowTick := GetTickCount64;
  EnterCriticalSection(FSubagentsLock);
  Try
    SetLength(Snapshot, 0);
    If Assigned(FSubagents) Then
      Begin
        SetLength(Snapshot, FSubagents.Count);
        For I := 0 To FSubagents.Count - 1 Do
          Begin
            Child := TChildSubagent(FSubagents[I]);
            If Assigned(Child) And (Not Child.IsFinished) And
              SubagentRunTimedOut(Child.StartedTick, NowTick) Then
              Snapshot[I] := Child
            Else
              Snapshot[I] := Nil;
          End;
      End;
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
  For I := 0 To High(Snapshot) Do
    If Assigned(Snapshot[I]) Then
      Snapshot[I].Abandon(Format('Timed out after %d s (still waiting on the model).',
        [MaxSubagentRuntimeMs Div 1000]));
End;

Function TAssistantService.TakeSubagentResult(Const RunId: String; Out ResultText, ErrorText: String): Boolean;
Var
  Child: TChildSubagent;
  State: TChildSubagentState;
  Summary: String;
  DurationMs: Integer;
  KindName, Title: String;
  Ok: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Child := Nil;
  EnterCriticalSection(FSubagentsLock);
  Try
    Child := TChildSubagent(FindSubagentLocked(RunId));
    If Assigned(Child) Then
      FSubagents.Extract(Child);
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
  If Not Assigned(Child) Then
    Begin
      ErrorText := 'Unknown subagent id.';
      Exit;
    End;
  Try
    State := Child.SnapshotState;
    If Not State.Finished Then
      Begin
        Child.Abandon('Cancelled.');
        State := Child.SnapshotState;
      End;
    ErrorText := State.FailText;
    Summary := State.Answer;
    Ok := State.Ok And (ErrorText = '');
    If (Not Ok) And (Summary = '') Then
      Summary := ErrorText;
    KindName := Child.KindName;
    Title := Child.Title;
    DurationMs := Integer(GetTickCount64 - Child.StartedTick);
    ResultText := FormatSubagentToolResult(KindName, Title, Summary, Ok, DurationMs);
    Result := Ok;
  Finally
    If RunningOnMainThread Then
      Child.Free
    Else If Assigned(FDeferredSubagents) Then
      Begin
        EnterCriticalSection(FSubagentsLock);
        Try
          FDeferredSubagents.Add(Child);
        Finally
          LeaveCriticalSection(FSubagentsLock);
        End;
        TThread.Queue(Nil, @FlushDeferredSubagents);
      End
    Else
      Child.Free;
  End;
End;

Procedure TAssistantService.CancelSubagents;
Var
  I: Integer;
  Snapshot: Array Of TChildSubagent;
Begin
  EnterCriticalSection(FSubagentsLock);
  Try
    SetLength(Snapshot, 0);
    If Assigned(FSubagents) Then
      Begin
        SetLength(Snapshot, FSubagents.Count);
        For I := 0 To FSubagents.Count - 1 Do
          Snapshot[I] := TChildSubagent(FSubagents[I]);
      End;
  Finally
    LeaveCriticalSection(FSubagentsLock);
  End;
  For I := 0 To High(Snapshot) Do
    If Assigned(Snapshot[I]) Then
      Snapshot[I].Abandon('Cancelled.');
End;

Function TAssistantService.MessageCount: Integer;
Begin
  Result := Length(FMessages);
End;

Procedure TAssistantService.RestoreMessage(Role: TAssistantMessageRole; Const Content, ToolCallId, ToolCallsJson: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := ToolCallId;
  FMessages[Idx].ToolCallsJson := ToolCallsJson;
  FMessages[Idx].ResponsesOutputJson := '';
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Function TAssistantService.GetMessage(Index: Integer; Out Role: TAssistantMessageRole;
  Out Content, ToolCallId, ToolCallsJson: String): Boolean;
Begin
  Result := False;
  Role := amrUser;
  Content := '';
  ToolCallId := '';
  ToolCallsJson := '';
  If (Index < 0) Or (Index >= Length(FMessages)) Then
    Exit;
  Role := FMessages[Index].Role;
  Content := FMessages[Index].Content;
  ToolCallId := FMessages[Index].ToolCallId;
  ToolCallsJson := FMessages[Index].ToolCallsJson;
  Result := True;
End;

Function TAssistantService.IsBusy: Boolean;
Begin
  Result := FBusy;
End;

Function TAssistantService.IsSignedIn: Boolean;
Var ErrorText: String;
Begin
  Result := RequireSubscriptionProvider(FProvider, ErrorText) And FProvider.IsSignedIn;
End;

Procedure TAssistantService.SetModelProvider(Const Provider: IAssistantModelProvider);
Var ErrorText: String;
Begin
  If FBusy Then Raise Exception.Create('Cannot change provider during a request.');
  If Not RequireSubscriptionProvider(Provider, ErrorText) Then
    Raise Exception.Create(ErrorText);
  If FProvider <> Provider Then
    Begin
      CancelSubagents;
      ClearHistory;
    End;
  FProvider := Provider;
End;

Function TAssistantService.ListAvailableModels(ModelIds: TStrings; Out ErrorText: String): Boolean;
Begin
  Result := RequireSubscriptionProvider(FProvider, ErrorText);
  If Result Then
    Result := FProvider.ListModels(FApiBase, ModelIds, Not FIsSubagent, ErrorText);
End;

Function TAssistantService.StartStream(OnToken: TAssistantStreamEvent): Boolean;
Var
  AccessToken, EventsFile, ToolsJson: String;
Begin
  Result := False;
  FLastError := '';
  If FBusy Then
    Begin
      FLastError := 'A request is already in progress.';
      Exit;
    End;
  If Not RequireSubscriptionProvider(FProvider, FLastError) Then Exit;
  If Not FProvider.GetAccessToken(Not FIsSubagent, AccessToken, FLastError) Then Exit;
  If Not Assigned(OnToken) Then
    Begin
      FLastError := 'No stream callback.';
      Exit;
    End;

  ClearStreamThread;
  If (Not FIsSubagent) And Assigned(WorkflowAssistantHarness) Then
    WorkflowAssistantHarness.ClearTurnTodos;
  { Refresh mode/plan-path wording and tool list before every request. }
  RebuildSystemPrompt;
  FToolsJsonValid := False;
  TrimMessagesForBudget;
  EventsFile := '';
  If (Not FIsSubagent) And Assigned(ProjectAssistantConversation) And
    (ProjectAssistantConversation.ProjectRoot <> '') Then
    EventsFile := CreateAssistantEventsFilePath(ProjectAssistantConversation.ProjectRoot);
  FLastEventsFile := EventsFile;
  If FToolsEnabled Then
    ToolsJson := ToolsJsonCached
  Else
    ToolsJson := '';
  FStreamThread := TAssistantActor.Create(Self, FApiBase, AccessToken, FModel, FReasoningEffort,
    ToolsJson, EventsFile, OnToken);
  TAssistantActor(FStreamThread).OnTrace := FOnTrace;
  FBusy := True;
  FStreamThread.Start;
  Result := True;
  WorkflowLogger.Info('AssistantService', 'Actor started – model=' + FModel + ' wire=responses');
End;

Procedure TAssistantService.DetachStreamCallbacks;
Begin
  { Closing a view must disconnect it before CancelStream pumps queued calls. }
  FOnTrace := Nil;
  If FStreamThread Is TAssistantActor Then
    TAssistantActor(FStreamThread).DetachCallbacks;
End;

Procedure TAssistantService.CancelStream;
Begin
  CancelSubagents;
  If Assigned(FStreamThread) Then
    Begin
      WorkflowLogger.Info('AssistantService', 'Stream cancel requested');
      ClearStreamThread;
    End
  Else
    FBusy := False;
End;

Function TAssistantService.CompleteOnce(Const SystemPrompt, UserPrompt: String;
  Out AnswerText, ErrorText: String): Boolean;
Begin
  Result := False;
  AnswerText := '';
  ErrorText := '';
  If FBusy Then
    ErrorText := 'A request is already in progress.'
  Else If RequireSubscriptionProvider(FProvider, ErrorText) Then
    Begin
      FBusy := True;
      Try
        Result := FProvider.CompleteOnce(FApiBase, FModel, SystemPrompt, UserPrompt,
          Not FIsSubagent, AnswerText, ErrorText);
      Finally
        FBusy := False;
      End;
    End;
  FLastError := ErrorText;
End;

Procedure TAssistantService.MarkStreamComplete;
Begin
  FBusy := False;
End;

Initialization

InitCriticalSection(GAbandonedLock);
GAbandonedThreads := TFPList.Create;
GAbandonedServices := TFPList.Create;
AssistantClient := TAssistantService.Create;
If Assigned(AssistantChatConfig) Then
  AssistantClient.ApplyConfig(AssistantChatConfig);

Finalization

FreeAndNil(AssistantClient);
ReapAbandonedAssistantWorkers;
FreeAndNil(GAbandonedThreads);
FreeAndNil(GAbandonedServices);
DoneCriticalSection(GAbandonedLock);

End.
