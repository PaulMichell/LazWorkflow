Unit AssistantTraceView;

{ Compatibility shell for the single StyledText conversation canvas. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Contnrs, AssistantTrace, AssistantConversation,
  AssistantConversationSurface;

Type
  TAssistantTraceView = Class(TFrame)
  Private
    FSurface: TAssistantConversationSurface;
    Saved: TObjectList;
    TurnIDs: TStringList;
    SavedRoot, FirstTurn, ActiveKey, PendingKey: String;
    Positions: TStringList;
    FBoundTrace: TAssistantTrace;
    Procedure RememberPosition;
    Function GetShowThinking: Boolean;
    Function GetShowTools: Boolean;
    Procedure SetShowThinking(Value: Boolean);
    Procedure SetShowTools(Value: Boolean);
    Procedure AddTrace(Trace: TAssistantTrace);
    Procedure LoadSaved(Store: TAssistantConversationStore);
    Procedure ApplyTurnImages(Trace: TAssistantTrace; Const Turn: TConversationTurn; Const StoreDirectory: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure ResetContent;
    Procedure Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
    Procedure SyncConversation(Store: TAssistantConversationStore; Live: TAssistantTrace; IncludeLive: Boolean);
    Procedure NavigateTurn(Const TurnID: String);
    Procedure ScrollToStart;
    Procedure ScrollToEnd;
    Procedure RefreshElapsed(Trace: TAssistantTrace);
    Property Surface: TAssistantConversationSurface Read FSurface;
    Property ShowThinking: Boolean Read GetShowThinking Write SetShowThinking;
    Property ShowToolUse: Boolean Read GetShowTools Write SetShowTools;
  End;

Implementation

{$R *.lfm}

Uses
  AssistantImages;
Constructor TAssistantTraceView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  Align := alClient;
  Saved := TObjectList.Create(True);
  TurnIDs := TStringList.Create;
  Positions := TStringList.Create;
  FSurface := TAssistantConversationSurface.Create(Self);
  FSurface.Parent := Self;
  FSurface.Align := alClient;
End;

Destructor TAssistantTraceView.Destroy;
Var
  I: Integer;
Begin
  FBoundTrace := Nil;
  Saved.Free;
  TurnIDs.Free;
  If Assigned(Positions) Then
    For I := 0 To Positions.Count - 1 Do Positions.Objects[I].Free;
  Positions.Free;
  Inherited Destroy;
End;

Procedure TAssistantTraceView.ResetContent;
Begin
  RememberPosition;
  ActiveKey := '';
  FBoundTrace := Nil;
  Saved.Clear;
  TurnIDs.Clear;
  FirstTurn := '';
  SavedRoot := '';
  FSurface.Clear;
End;

Procedure TAssistantTraceView.RememberPosition;
Var
  I: Integer;
Begin
  If ActiveKey = '' Then Exit;
  I := Positions.IndexOf(ActiveKey);
  If I >= 0 Then
    Begin
      Positions.Objects[I].Free;
      Positions.Objects[I] := FSurface.SaveViewState;
    End
  Else Positions.AddObject(ActiveKey, FSurface.SaveViewState);
  If Positions.Count > 32 Then
    Begin
      Positions.Objects[0].Free;
      Positions.Delete(0);
    End;
End;

Function TAssistantTraceView.GetShowThinking: Boolean;
Begin
  Result := FSurface.ShowThinking;
End;

Function TAssistantTraceView.GetShowTools: Boolean;
Begin
  Result := FSurface.ShowToolUse;
End;

Procedure TAssistantTraceView.SetShowThinking(Value: Boolean);
Begin
  FSurface.ShowThinking := Value;
End;

Procedure TAssistantTraceView.SetShowTools(Value: Boolean);
Begin
  FSurface.ShowToolUse := Value;
End;

Procedure TAssistantTraceView.AddTrace(Trace: TAssistantTrace);
Var
  I: Integer;
Begin
  If Assigned(Trace) Then For I := 0 To Trace.Count - 1 Do FSurface.AddBlock(Trace[I].ID, Trace[I]);
End;

Procedure TAssistantTraceView.Sync(Trace: TAssistantTrace; ScrollBottom: Boolean);
Var
  I: Integer;
Begin
  { Legacy refresh callers update the live fragment without discarding history.
    ScrollBottom is a follow-tail hint, never an instruction to move a reader. }
  FBoundTrace := Trace;
  FSurface.BeginDocument;
  For I := 0 To Saved.Count - 1 Do AddTrace(TAssistantTrace(Saved[I]));
  AddTrace(Trace);
  FSurface.EndDocument;
End;

Procedure TAssistantTraceView.ApplyTurnImages(Trace: TAssistantTrace; Const Turn: TConversationTurn;
  Const StoreDirectory: String);
Var
  Refs: TAssistantImageRefArray;
  TraceRefs: TTraceImageRefArray;
  I, J: Integer;
  Block: TTraceBlock;
Begin
  If Not Assigned(Trace) Then Exit;
  If ParseAssistantImageRefs(Turn.AttachmentsJson, Refs) And (Length(Refs) > 0) Then
    Begin
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
      Trace.KeepUserImageRefs(TraceRefs);
    End;
  For I := 0 To Trace.Count - 1 Do
    Begin
      Block := Trace[I];
      If Not Assigned(Block) Or (Block.Kind <> tbkUser) Then Continue;
      For J := 0 To High(Block.ImageRefs) Do
        Block.ImageRefs[J].Missing := Not AssistantImageDisplayPresent(StoreDirectory, Block.ImageRefs[J].Id,
          Block.ImageRefs[J].DisplayPath);
    End;
End;

Procedure TAssistantTraceView.LoadSaved(Store: TAssistantConversationStore);
Var
  Turn: TConversationTurn;
  Trace: TAssistantTrace;
  I: Integer;
  FirstID: String;
Begin
  If Not Assigned(Store) Then Exit;
  FirstID := '';
  If (Store.TurnCount > 0) And Store.GetTurn(0, Turn) Then FirstID := Turn.Id;
  PendingKey := '';
  If FirstID <> '' Then PendingKey := Store.ProjectRoot + ':' + FirstID;
  If (ActiveKey <> '') And (ActiveKey <> PendingKey) Then RememberPosition;
  If (SavedRoot <> Store.ProjectRoot) Or ((FirstTurn <> '') And (FirstTurn <> FirstID)) Or (Saved.Count > Store.TurnCount) Then
    Begin
      Saved.Clear;
      TurnIDs.Clear;
      FSurface.Clear;
    End;
  SavedRoot := Store.ProjectRoot;
  FirstTurn := FirstID;
  While Saved.Count < Store.TurnCount Do
    Begin
      If Not Store.GetTurn(Saved.Count, Turn) Then Break;
      Trace := TAssistantTrace.Create;
      Try
        If Turn.TraceJson <> '' Then Trace.LoadFromJson(Turn.TraceJson);
        If (Trace.Count = 0) And (Turn.EventsFile <> '') Then
          Trace.ReplayFromEventsFile(IncludeTrailingPathDelimiter(Store.ProjectRoot) + Turn.EventsFile, Turn.Prompt, Turn.Thinking, Turn.Response);
        If Trace.Count = 0 Then
          Begin
            Trace.EnsureUser(Turn.Prompt);
            If Trim(Turn.Thinking) <> '' Then
              Begin
                Trace.StartThinking(0).Body := Turn.Thinking;
                Trace.FinishCurrentThinking;
              End;
            If Turn.Response <> '' Then Trace.EnsureAnswer.Body := Turn.Response;
            If Turn.ErrorText <> '' Then Trace.AddNote('**Error:** ' + Turn.ErrorText);
          End;
        If Turn.DurationMs > 0 Then Trace.ApplyWorkedFooter(Turn.DurationMs);
        ApplyTurnImages(Trace, Turn, Store.AssistantDirectory);
        { Legacy generated IDs must also be stable across history reloads. New
          archives carry block IDs that survive the live-to-saved transition. }
        If Pos('"id"', Turn.TraceJson) = 0 Then
          For I := 0 To Trace.Count - 1 Do Trace[I].ID := Turn.Id + ':' + IntToStr(I);
        Saved.Add(Trace);
        TurnIDs.Add(Turn.Id);
        Trace := Nil;
      Finally
        Trace.Free;
      End;
    End;
End;

Procedure TAssistantTraceView.SyncConversation(Store: TAssistantConversationStore; Live: TAssistantTrace; IncludeLive: Boolean);
Var
  I, PositionIndex: Integer;
  ChangedConversation: Boolean;
Begin
  LoadSaved(Store);
  If IncludeLive And Assigned(Live) And Assigned(Store) Then
    ApplyTurnImages(Live, Default(TConversationTurn), Store.AssistantDirectory);
  ChangedConversation := ActiveKey <> PendingKey;
  FBoundTrace := Nil;
  If IncludeLive Then FBoundTrace := Live;
  FSurface.BeginDocument;
  For I := 0 To Saved.Count - 1 Do AddTrace(TAssistantTrace(Saved[I]));
  If IncludeLive Then AddTrace(Live);
  FSurface.EndDocument;
  ActiveKey := PendingKey;
  If ChangedConversation Then
    Begin
      PositionIndex := Positions.IndexOf(ActiveKey);
      If PositionIndex >= 0 Then FSurface.RestoreViewState(TConversationViewState(Positions.Objects[PositionIndex]));
    End;
End;

Procedure TAssistantTraceView.NavigateTurn(Const TurnID: String);
Var
  I: Integer;
  Trace: TAssistantTrace;
Begin
  I := TurnIDs.IndexOf(TurnID);
  If I < 0 Then Exit;
  Trace := TAssistantTrace(Saved[I]);
  If Trace.Count > 0 Then FSurface.NavigateTo(Trace[0].ID);
End;

Procedure TAssistantTraceView.ScrollToStart;
Begin
  FSurface.JumpToStart;
End;

Procedure TAssistantTraceView.ScrollToEnd;
Begin
  FSurface.JumpToEnd;
End;

Procedure TAssistantTraceView.RefreshElapsed(Trace: TAssistantTrace);
Begin
  If Not Assigned(Trace) Then Exit;
  Trace.TickElapsed;
  If FBoundTrace = Trace Then Sync(Trace, False);
End;

Initialization
RegisterClass(TAssistantTraceView);
End.
