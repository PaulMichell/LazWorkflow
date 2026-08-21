Unit AssistantActor;

{ Session actor thread: Responses stream, tool rounds, steer drain, cancel (c) 2026 Michell Computing.

  Named Actor because AssistantSession.pas already holds the legacy transcript file. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantProtocol, AssistantEvents, AssistantService;

Type
  TAssistantActor = Class(TThread)
  Private
    FService: TAssistantService;
    FApiBase: String;
    FAccessToken: String;
    FModel: String;
    FReasoningEffort: String;
    FToolsJson: String;
    FOnToken: TAssistantStreamEvent;
    FEventsFile: String;
    FSteer: TAssistantSteerBuffer;
    FParser: TAssistantSseParser;
    FHttpControl: TObject;
    FSnapLock: TRTLCriticalSection;
    FContent: String;
    FThinking: String;
    FPhase: TAssistantPhase;
    FErrorText: String;
    FFinishEmitted: Boolean;
    FWrotePlan: Boolean;
    FUseResponses: Boolean;
    FTriedResponses: Boolean;
    FEncryptedId: String;
    FEncryptedContent: String;
    FLoopIndex: Integer;
    FLastSnapTick: QWord;
    FPendingFinish: Boolean;
    FToolCalls: TSamplerToolCallArray;
    Procedure LogEvent(Kind: TAssistantEventKind; Const Text: String = '';
      Const ToolName: String = ''; Const ToolId: String = '');
    Procedure EmitSnapshot(IsDone: Boolean; Const ErrorText: String; Force: Boolean);
    Procedure NotifyMain;
    Procedure SetPhase(Phase: TAssistantPhase);
    Procedure ApplyParserEvents(FromIndex: Integer);
    Procedure AppendThinking(Const Delta: String);
    Procedure AppendToolLine(Const Name, Args: String);
    Function DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
    Procedure HttpsChunk(Const Chunk: String);
    Function HttpsShouldStop: Boolean;
    Procedure AbortHttp;
    Procedure RunToolsOnMain;
    Function DrainSteerIntoHistory: Boolean;
    Function BuildRoundJson(Out Url: String): String;
    Function ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Service: TAssistantService; Const ApiBase, AccessToken, Model,
      ReasoningEffort, ToolsJson, EventsFile: String; OnToken: TAssistantStreamEvent);
    Destructor Destroy; Override;
    Procedure Cancel;
    Procedure EnqueueSteer(Const Text: String);
    Procedure Detach;
  End;

Implementation

Uses
  AssistantHttps, AssistantTools, WorkflowLog;

Const
  MaxToolRounds = 20;
  SnapIntervalMs = 50;
  CancelWaitHint = 'Cancelled.';

Function IsTransientNetworkError(Const ErrorText: String): Boolean;
Var
  E: String;
Begin
  E := LowerCase(ErrorText);
  Result :=
    (Pos('host name resolution', E) > 0) Or
    (Pos('could not resolve', E) > 0) Or
    (Pos('name or service not known', E) > 0) Or
    (Pos('temporary failure in name resolution', E) > 0) Or
    (Pos('network is unreachable', E) > 0) Or
    (Pos('connection refused', E) > 0) Or
    (Pos('connection reset', E) > 0) Or
    (Pos('timed out', E) > 0) Or
    (Pos('timeout', E) > 0) Or
    (Pos('socket error', E) > 0);
End;

Function TrimSlash(Const Url: String): String;
Begin
  Result := Trim(Url);
  While (Length(Result) > 0) And (Result[Length(Result)] = '/') Do
    SetLength(Result, Length(Result) - 1);
End;

Constructor TAssistantActor.Create(Service: TAssistantService; Const ApiBase, AccessToken, Model,
  ReasoningEffort, ToolsJson, EventsFile: String; OnToken: TAssistantStreamEvent);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FSnapLock);
  FService := Service;
  FApiBase := ApiBase;
  FAccessToken := AccessToken;
  FModel := Model;
  FReasoningEffort := ReasoningEffort;
  FToolsJson := ToolsJson;
  FEventsFile := EventsFile;
  FOnToken := OnToken;
  FSteer := TAssistantSteerBuffer.Create;
  FParser := TAssistantSseParser.Create;
  FHttpControl := Nil;
  FContent := '';
  FThinking := '';
  FPhase := apWaiting;
  FErrorText := '';
  FFinishEmitted := False;
  FWrotePlan := False;
  FUseResponses := True;
  FTriedResponses := False;
  FEncryptedId := '';
  FEncryptedContent := '';
  FLoopIndex := 0;
  FLastSnapTick := 0;
  FPendingFinish := False;
  SetLength(FToolCalls, 0);
End;

Destructor TAssistantActor.Destroy;
Begin
  AbortHttp;
  FreeAndNil(FParser);
  FreeAndNil(FSteer);
  DoneCriticalSection(FSnapLock);
  Inherited Destroy;
End;

Procedure TAssistantActor.Cancel;
Begin
  Terminate;
  AbortHttp;
End;

Procedure TAssistantActor.EnqueueSteer(Const Text: String);
Begin
  If Trim(Text) = '' Then
    Exit;
  FSteer.Enqueue(Text);
  LogEvent(aekSteerQueued, Trim(Text));
End;

Procedure TAssistantActor.Detach;
Begin
  FOnToken := Nil;
  FService := Nil;
  AbortHttp;
End;

Procedure TAssistantActor.AbortHttp;
Var
  Control: THttpsStreamControl;
Begin
  If Not Assigned(FHttpControl) Then
    Exit;
  Control := THttpsStreamControl(FHttpControl);
  Try
    Control.Abort;
  Except
  End;
End;

Procedure TAssistantActor.LogEvent(Kind: TAssistantEventKind; Const Text: String;
  Const ToolName: String; Const ToolId: String);
Var
  Event: TAssistantEvent;
Begin
  Event := Default(TAssistantEvent);
  Event.Kind := Kind;
  Event.Phase := FPhase;
  Event.Text := Text;
  Event.ToolName := ToolName;
  Event.ToolId := ToolId;
  Event.LoopIndex := FLoopIndex;
  Event.Ok := True;
  AppendAssistantEvent(FEventsFile, Event);
End;

Procedure TAssistantActor.NotifyMain;
Var
  Content, Thinking, Err: String;
  Done: Boolean;
  Cb: TAssistantStreamEvent;
Begin
  EnterCriticalSection(FSnapLock);
  Try
    Content := FContent;
    Thinking := FThinking;
    Err := FErrorText;
    Done := FPendingFinish;
    FPendingFinish := False;
    Cb := FOnToken;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  If Assigned(Cb) Then
    Try
      Cb(Content, Thinking, Done, Err);
    Except
      On E: Exception Do
        WorkflowLogger.Warning('AssistantActor', 'UI snapshot failed: ' + E.Message);
    End;
End;

Procedure TAssistantActor.EmitSnapshot(IsDone: Boolean; Const ErrorText: String; Force: Boolean);
Var
  NowTick: QWord;
Begin
  If Terminated And (Not IsDone) Then
    Exit;
  If IsDone Then
    Begin
      If FFinishEmitted Then
        Exit;
      FFinishEmitted := True;
    End
  Else If Not Force Then
    Begin
      NowTick := GetTickCount64;
      If (FLastSnapTick > 0) And (NowTick - FLastSnapTick < SnapIntervalMs) Then
        Exit;
      FLastSnapTick := NowTick;
    End;
  EnterCriticalSection(FSnapLock);
  Try
    If ErrorText <> '' Then
      FErrorText := ErrorText;
    FPendingFinish := FPendingFinish Or IsDone;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  Queue(@NotifyMain);
End;

Procedure TAssistantActor.SetPhase(Phase: TAssistantPhase);
Begin
  If FPhase = Phase Then
    Exit;
  FPhase := Phase;
  LogEvent(aekPhaseChanged, AssistantPhaseName(Phase));
End;

Procedure TAssistantActor.AppendThinking(Const Delta: String);
Begin
  If Delta = '' Then
    Exit;
  MergeSamplerText(FThinking, Delta);
  If FPhase = apWaiting Then
    SetPhase(apThinking);
  EmitSnapshot(False, '', False);
End;

Procedure TAssistantActor.AppendToolLine(Const Name, Args: String);
Var
  Preview, Line: String;
Begin
  Preview := Trim(Args);
  If Length(Preview) > 120 Then
    Preview := Copy(Preview, 1, 117) + '…';
  Line := LineEnding + '> *' + Name + '*';
  If Preview <> '' Then
    Line := Line + ' `' + Preview + '`';
  MergeSamplerText(FThinking, Line);
End;

Procedure TAssistantActor.ApplyParserEvents(FromIndex: Integer);
Var
  I: Integer;
  Event: TSamplerEvent;
Begin
  For I := FromIndex To FParser.EventCount - 1 Do
    Begin
      Event := FParser.GetEvent(I);
      Case Event.Kind Of
        sekThoughtDelta:
          Begin
            SetPhase(apThinking);
            AppendThinking(Event.Text);
            LogEvent(aekThoughtDelta, Event.Text);
          End;
        sekContentDelta:
          Begin
            SetPhase(apStreaming);
            MergeSamplerText(FContent, Event.Text);
            EmitSnapshot(False, '', False);
            LogEvent(aekContentDelta, Event.Text);
          End;
      Else
        { Started / tool deltas / completed handled from parser accumulators. }
      End;
    End;
End;

Procedure TAssistantActor.HttpsChunk(Const Chunk: String);
Var
  FromIndex: Integer;
Begin
  If Terminated Then
    Exit;
  FromIndex := FParser.EventCount;
  FParser.Feed(Chunk);
  ApplyParserEvents(FromIndex);
End;

Function TAssistantActor.HttpsShouldStop: Boolean;
Begin
  Result := Terminated;
End;

Function TAssistantActor.DoHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
Const
  MaxAttempts = 3;
Var
  Code, Attempt: Integer;
  Headers, LastErr: String;
  Control: THttpsStreamControl;
Begin
  Result := False;
  ErrorText := '';
  LastErr := '';
  Headers := 'Authorization: Bearer ' + FAccessToken;
  For Attempt := 1 To MaxAttempts Do
    Begin
      If Terminated Then
        Begin
          ErrorText := CancelWaitHint;
          Exit;
        End;
      FParser.Reset;
      Control := THttpsStreamControl.Create;
      FHttpControl := Control;
      Try
        Try
          If Not HttpsPostJsonStream(Url, RequestJson, Headers, @HttpsChunk, @HttpsShouldStop,
            Control, Code, ErrorText) Then
            Begin
              If Terminated And (ErrorText = '') Then
                ErrorText := CancelWaitHint;
            End
          Else If Terminated Then
            ErrorText := CancelWaitHint
          Else If (Code < 200) Or (Code >= 300) Then
            Begin
              If ErrorText = '' Then
                ErrorText := Format('HTTP %d', [Code])
              Else
                ErrorText := Format('HTTP %d: %s', [Code, Copy(Trim(ErrorText), 1, 400)]);
            End
          Else
            Begin
              If (FParser.Thinking <> '') And (Pos(FParser.Thinking, FThinking) = 0) Then
                AppendThinking(FParser.Thinking);
              If (FParser.Content <> '') And (FContent = '') Then
                FContent := FParser.Content;
              If FParser.EncryptedContent <> '' Then
                Begin
                  FEncryptedContent := FParser.EncryptedContent;
                  FEncryptedId := FParser.EncryptedId;
                End;
              FToolCalls := FParser.ToolCalls;
              Result := True;
              Exit;
            End;
        Except
          On E: Exception Do
            If Terminated Then
              ErrorText := CancelWaitHint
            Else
              ErrorText := E.Message;
        End;
      Finally
        FHttpControl := Nil;
        Control.Free;
      End;
      LastErr := ErrorText;
      If Terminated Or (ErrorText = CancelWaitHint) Then
        Exit;
      If (Not IsTransientNetworkError(ErrorText)) Then
        Exit;
      If Attempt < MaxAttempts Then
        Begin
          WorkflowLogger.Warning('AssistantActor',
            Format('Transient network error (attempt %d/%d): %s', [Attempt, MaxAttempts, ErrorText]));
          Sleep(200 * Attempt);
        End;
    End;
  ErrorText := LastErr;
End;

Function TAssistantActor.ShouldFallbackFromResponses(Const ErrorText: String): Boolean;
Var
  E: String;
Begin
  E := LowerCase(ErrorText);
  Result := (Pos('http 404', E) > 0) Or (Pos('http 405', E) > 0) Or
    (Pos('http 400', E) > 0) Or (Pos('not found', E) > 0) Or
    (Pos('unknown', E) > 0) Or (Pos('not supported', E) > 0);
End;

Procedure TAssistantActor.RunToolsOnMain;
Var
  I: Integer;
  StartTick: QWord;
  ResultText, ErrorText, Content, ToolCallsJson: String;
  Ok: Boolean;
  Call: TSamplerToolCall;
Begin
  If Not Assigned(FService) Then
    Exit;
  ToolCallsJson := '[';
  For I := 0 To High(FToolCalls) Do
    Begin
      Call := FToolCalls[I];
      If Call.Name = '' Then
        Continue;
      If Length(ToolCallsJson) > 1 Then
        ToolCallsJson := ToolCallsJson + ',';
      If Call.Id = '' Then
        Begin
          Call.Id := Format('call_%d_%d', [FLoopIndex, I]);
          FToolCalls[I].Id := Call.Id;
        End;
      ToolCallsJson := ToolCallsJson + '{"id":"' + JsonEscapeText(Call.Id) +
        '","type":"function","function":{"name":"' + JsonEscapeText(Call.Name) +
        '","arguments":"' + JsonEscapeText(Call.Arguments) + '"}}';
    End;
  ToolCallsJson := ToolCallsJson + ']';
  FService.AddAssistantToolCalls(FContent, ToolCallsJson);
  For I := 0 To High(FToolCalls) Do
    Begin
      If Terminated Then
        Exit;
      Call := FToolCalls[I];
      If Call.Name = '' Then
        Continue;
      AppendToolLine(Call.Name, Call.Arguments);
      LogEvent(aekToolStarted, Call.Arguments, Call.Name, Call.Id);
      EmitSnapshot(False, 'Running tools…', True);
      StartTick := GetTickCount64;
      ResultText := '';
      ErrorText := '';
      Try
        Ok := ExecuteAssistantToolForMode(Call.Name, Call.Arguments, FService.ActiveMode,
          ResultText, ErrorText);
      Except
        On E: Exception Do
          Begin
            Ok := False;
            ErrorText := 'Tool raised: ' + E.Message;
            ResultText := '';
          End;
      End;
      If Ok Then
        Content := ResultText
      Else
        Content := 'Error: ' + ErrorText;
      FService.AddToolResult(Call.Id, Content);
      LogEvent(aekToolCompleted, Copy(Content, 1, 240), Call.Name, Call.Id);
      If Ok And (SameText(Call.Name, 'write_markdown') Or SameText(Call.Name, 'update_markdown')) Then
        FWrotePlan := True;
      WorkflowLogger.Info('AssistantActor',
        Format('tool %s ok=%s ms=%d', [Call.Name, BoolToStr(Ok, True), GetTickCount64 - StartTick]));
    End;
End;

Function TAssistantActor.DrainSteerIntoHistory: Boolean;
Var
  Note, Wrapped: String;
Begin
  Result := False;
  If Terminated Or (Not Assigned(FService)) Then
    Exit;
  Note := FSteer.DrainConcat;
  If Note = '' Then
    Exit;
  Wrapped := FormatSteerEnvelope(Note);
  FService.AddMessage(amrUser, Wrapped);
  LogEvent(aekInterjected, Note);
  MergeSamplerText(FThinking, LineEnding + '> **Steer** ' + Copy(Note, 1, 160));
  EmitSnapshot(False, 'Steering at next model gap…', True);
  Result := True;
End;

Function TAssistantActor.BuildRoundJson(Out Url: String): String;
Var
  Items: TSamplerInputItemArray;
  Options: TSamplerRequestOptions;
  Base: String;
  I, InsertAt: Integer;
  Shifted: TSamplerInputItemArray;
Begin
  Base := TrimSlash(FApiBase);
  Items := FService.ExportSamplerItems;
  If (FEncryptedContent <> '') And FUseResponses Then
    Begin
      InsertAt := Length(Items);
      SetLength(Shifted, Length(Items) + 1);
      For I := 0 To High(Items) Do
        Shifted[I] := Items[I];
      Shifted[InsertAt] := SamplerInputReasoning(FEncryptedId, FEncryptedContent);
      Items := Shifted;
    End;
  Options := DefaultSamplerRequestOptions;
  Options.Model := FModel;
  Options.ReasoningEffort := FReasoningEffort;
  If FUseResponses Then
    Begin
      Options.ToolsJson := CompletionsToolsToResponsesTools(FToolsJson);
      Options.IncludeEncryptedReasoning := True;
      Url := Base + '/responses';
      Result := BuildResponsesRequestJson(Items, Options);
    End
  Else
    Begin
      Options.ToolsJson := FToolsJson;
      Options.IncludeEncryptedReasoning := False;
      Url := Base + '/chat/completions';
      Result := BuildChatCompletionsRequestJson(Items, Options);
    End;
End;

Procedure TAssistantActor.Execute;
Var
  Url, RequestJson, ErrorText: String;
  RoundNo, I: Integer;
  HasTools: Boolean;
  WroteBefore: Boolean;
Begin
  LogEvent(aekTurnStarted, FModel);
  SetPhase(apWaiting);
  EmitSnapshot(False, 'Waiting for first token…', True);
  Try
  For RoundNo := 0 To MaxToolRounds Do
    Begin
      If Terminated Or (Not Assigned(FService)) Then
        Break;
      FLoopIndex := RoundNo;
      If RoundNo > 0 Then
        Begin
          LogEvent(aekLoopStarted, IntToStr(RoundNo));
          If FThinking <> '' Then
            MergeSamplerText(FThinking, LineEnding + LineEnding);
        End;
      SetLength(FToolCalls, 0);
      { Fresh answer channel per model loop; thinking is kept. }
      FContent := '';
      RequestJson := BuildRoundJson(Url);
      If FUseResponses Then
        FTriedResponses := True;
      If Not DoHttpRound(Url, RequestJson, ErrorText) Then
        Begin
          If FUseResponses And FTriedResponses And ShouldFallbackFromResponses(ErrorText) And
            (Not Terminated) Then
            Begin
              WorkflowLogger.Warning('AssistantActor', 'Responses failed, falling back to Chat Completions: ' +
                ErrorText);
              FUseResponses := False;
              RequestJson := BuildRoundJson(Url);
              If DoHttpRound(Url, RequestJson, ErrorText) Then
                ErrorText := ''
              Else
                Begin
                  EmitSnapshot(True, ErrorText, True);
                  LogEvent(aekError, ErrorText);
                  Exit;
                End;
            End
          Else
            Begin
              If Terminated Then
                ErrorText := CancelWaitHint;
              EmitSnapshot(True, ErrorText, True);
              If ErrorText <> CancelWaitHint Then
                LogEvent(aekError, ErrorText);
              Exit;
            End;
        End;
      If Terminated Then
        Break;
      HasTools := False;
      For I := 0 To High(FToolCalls) Do
        If Trim(FToolCalls[I].Name) <> '' Then
          Begin
            HasTools := True;
            Break;
          End;
      If HasTools Then
        Begin
          SetPhase(apTools);
          WroteBefore := FWrotePlan;
          Synchronize(@RunToolsOnMain);
          If Terminated Then
            Break;
          If FWrotePlan And WroteBefore Then
            Begin
              EmitSnapshot(True, '', True);
              LogEvent(aekTurnEnded, 'plan_write');
              Exit;
            End;
          DrainSteerIntoHistory;
          Continue;
        End;
      If DrainSteerIntoHistory Then
        Continue;
      EmitSnapshot(True, '', True);
      LogEvent(aekTurnEnded, '');
      Exit;
    End;
  If Terminated Then
    EmitSnapshot(True, CancelWaitHint, True)
  Else
    Begin
      If FContent = '' Then
        FContent :=
          '*(Tool-round limit reached after ' + IntToStr(FLoopIndex) +
          ' rounds. Send a follow-up to continue.)*';
      EmitSnapshot(True, '', True);
      LogEvent(aekTurnEnded, 'round_cap');
    End;
  Finally
    If Assigned(FService) And FSteer.HasPending Then
      FService.AddMessage(amrUser, FormatSteerEnvelope(FSteer.DrainConcat));
  End;
End;

End.
