Unit AssistantTrace;

{ In-memory current-turn block list for the Project Assistant trace (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Replay, markdown export, and
  JSON load/save are one trace surface. Reviewed 2026-09-23: user-block image
  ids and the shared display-slot metrics stay here so export and the
  conversation layout share one formula without a second trace unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, AssistantEvents;

Type
  TTraceBlockKind = (tbkUser, tbkThinking, tbkTool, tbkAnswer, tbkNote, tbkSteer, tbkSubagent, tbkWorked);

  { Id, name, and display path. Never pixel bytes. Meaningful on tbkUser. }
  TTraceImageRef = Record
    Id: String;
    Name: String;
    DisplayPath: String;
    Width: Integer;
    Height: Integer;
    Missing: Boolean;
  End;
  TTraceImageRefArray = Array Of TTraceImageRef;

  TTraceBlock = Class
  Private
    FBody: String;
    FRevision: QWord;
    Procedure SetBody(Const Value: String);
  Public
    ID: String;
    Kind: TTraceBlockKind;
    Title: String;
    ToolName: String;
    ToolId: String;
    ToolArgs: String;
    LoopIndex: Integer;
    Running: Boolean;
    Ok: Boolean;
    Collapsed: Boolean;
    StartedAt: TDateTime;
    FinishedAt: TDateTime;
    DurationMs: Integer;
    Footer: String;
    ImageRefs: TTraceImageRefArray;
    Constructor Create;
    Property Revision: QWord Read FRevision;
    Property Body: String Read FBody Write SetBody;
  End;

  TAssistantTrace = Class
  Private
    FBlocks: TObjectList;
    Function GetCount: Integer;
    Function GetBlock(Index: Integer): TTraceBlock;
    Function AddBlock(Kind: TTraceBlockKind): TTraceBlock;
    Procedure FinishThinkingBlock(Block: TTraceBlock);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    Function AddUser(Const Text: String): TTraceBlock;
    Function EnsureUser(Const Text: String): TTraceBlock;
    { Store ids and names on the user block, creating that block when the prompt is empty. }
    Procedure SetUserImages(Const Ids, Names: Array Of String);
    Procedure SetUserImageRefs(Const Refs: TTraceImageRefArray);
    { A later user block for an image a tool just stored. Empty words; the picture is the content. }
    Procedure AppendUserImages(Const ImagesJson: String);
    { Fill a user block that has no refs. Does not replace refs the trace already stored. }
    Procedure KeepUserImageRefs(Const Refs: TTraceImageRefArray);
    Function AddNote(Const Text: String): TTraceBlock;
    Function AddSteer(Const Text: String): TTraceBlock;
    Function StartThinking(LoopIndex: Integer): TTraceBlock;
    Function CurrentThinking: TTraceBlock;
    Function CurrentRunningThinking: TTraceBlock;
    { Latest block of Kind after the last tool (or from the start). Nil if a tool is newer. }
    Function LatestBlockSinceLastTool(Kind: TTraceBlockKind): TTraceBlock;
    Function AddTool(Const ToolId, ToolName, Args: String): TTraceBlock;
    Function FindTool(Const ToolId: String): TTraceBlock;
    Function AddSubagent(Const SubId, KindName, Title: String): TTraceBlock;
    Function FindSubagent(Const SubId: String): TTraceBlock;
    Function FindRunningSubagentByKind(Const KindName: String): TTraceBlock;
    Function HasRunningSubagentOlderThan(BudgetMs: Integer): Boolean;
    { Reuse this sample's answer (after the last tool). Growing snapshots update it in place. }
    Function EnsureAnswer: TTraceBlock;
    Procedure FinishCurrentThinking;
    Procedure FinishCurrentAnswer;
    Procedure CollapseThinking(HideBody: Boolean = True);
    Procedure TickElapsed;
    Procedure ApplyWorkedFooter(DurationMs: Integer);
    Function ThinkingDurationMs: Integer;
    Function JoinedThinking: String;
    Function JoinedAnswers: String;
    { Markdown for export. IncludeUser False when the caller already wrote ### User. }
    Function FormatMarkdown(IncludeUser: Boolean): String;
    Function SaveToJson: String;
    Procedure LoadFromJson(Const Json: String);
    Procedure ApplyEvent(Const Event: TAssistantEvent);
    Procedure FinishReplay;
    Function ReplayEvents(Const Prompt: String; Const Events: TAssistantEventArray;
      Const ThinkingText, ResponseText: String): Boolean;
    Function ReplayFromEventsFile(Const FileName, Prompt, ThinkingText, ResponseText: String): Boolean;
    Property Count: Integer Read GetCount;
    Property Blocks[Index: Integer]: TTraceBlock Read GetBlock; Default;
  End;

{ True when Slice contains a letter or digit — reject a lone "." after a tool. }
Function SliceLooksLikeAnswer(Const Slice: String): Boolean;
{ Slice LiveText from 1-based StartAt. Past-the-end yields '' and leaves StartAt
  so the same loop cannot reopen an answer under a tool. After a tool, set
  StartAt to High(Integer); the next loop must set StartAt := 1. }
Function SliceLiveChannel(Const LiveText: String; Var StartAt: Integer): String;

Function MissingImageTileHeight(PixelsPerInch: Integer): Integer;
Function MissingImageTileCaption(Const Ref: TTraceImageRef): String;
{ Device-pixel size inside the bubble. Not enlarged past 1:1 at PixelsPerInch.
  False when the source size is unknown. }
Function ScaledImageExtent(ImageWidth, ImageHeight, ContentWidth, PixelsPerInch: Integer;
  Out DisplayWidth, DisplayHeight: Integer): Boolean;
{ One picture slot, including the gap before the next slot or the words.
  A missing file, or a present file with no known size, uses the fixed tile height. }
Function UserImageSlotHeight(Const Ref: TTraceImageRef; ContentWidth, PixelsPerInch: Integer): Integer;
Function UserImageRowHeight(Const Refs: TTraceImageRefArray; ContentWidth, PixelsPerInch: Integer): Integer;
{ LocalY is measured from the top of the image row. -1 when it is not in a slot. }
Function ImageIndexInRow(Const Refs: TTraceImageRefArray; ContentWidth, PixelsPerInch: Integer; LocalY: Int64): Integer;
Function FormatThoughtElapsed(DurationMs: Integer): String;
Function FormatThinkingClock(DurationMs: Integer): String;
Function FormatThoughtFooter(DurationMs: Integer): String;
Function FormatWorkedFooter(DurationMs: Integer): String;
Function ThinkingCardTitle(DurationMs: Integer; Running: Boolean): String;
Function ToolCardCaption(Const ToolName, Args: String): String;
{ True when the viewport is following the tail: everything fits, or Position is
  within Slop of max (ContentHeight - Page). Live updates should then keep the
  tail in view; otherwise they must not move Position. }
Function ScrollShouldFollowTail(Position, ContentHeight, Page: Integer; Slop: Integer = 24): Boolean;

Implementation

Uses
  DateUtils, Math, fpjson, jsonparser;

Function BlockKindName(Kind: TTraceBlockKind): String;
Begin
  Case Kind Of
    tbkThinking: Result := 'thinking';
    tbkTool: Result := 'tool';
    tbkAnswer: Result := 'answer';
    tbkNote: Result := 'note';
    tbkSteer: Result := 'steer';
    tbkSubagent: Result := 'subagent';
    tbkWorked: Result := 'worked';
  Else
    Result := 'user';
  End;
End;

Function NameToBlockKind(Const Name: String): TTraceBlockKind;
Var
  N: String;
Begin
  N := LowerCase(Trim(Name));
  If N = 'thinking' Then
    Result := tbkThinking
  Else If N = 'tool' Then
    Result := tbkTool
  Else If N = 'answer' Then
    Result := tbkAnswer
  Else If N = 'note' Then
    Result := tbkNote
  Else If N = 'steer' Then
    Result := tbkSteer
  Else If N = 'subagent' Then
    Result := tbkSubagent
  Else If N = 'worked' Then
    Result := tbkWorked
  Else
    Result := tbkUser;
End;

Constructor TTraceBlock.Create;
Var Guid: TGuid;
Begin
  Inherited Create;
  CreateGUID(Guid);
  ID := GUIDToString(Guid);
End;
Procedure TTraceBlock.SetBody(Const Value: String);
Begin
  If FBody = Value Then Exit;
  FBody := Value;
  Inc(FRevision);
End;

Constructor TAssistantTrace.Create;
Begin
  Inherited Create;
  FBlocks := TObjectList.Create(True);
End;

Destructor TAssistantTrace.Destroy;
Begin
  FreeAndNil(FBlocks);
  Inherited Destroy;
End;

Procedure TAssistantTrace.Clear;
Begin
  FBlocks.Clear;
End;



Function TAssistantTrace.GetCount: Integer;
Begin
  Result := FBlocks.Count;
End;

Function TAssistantTrace.GetBlock(Index: Integer): TTraceBlock;
Begin
  Result := Nil;
  If (Index < 0) Or (Index >= FBlocks.Count) Then
    Exit;
  Result := TTraceBlock(FBlocks[Index]);
End;

Function TAssistantTrace.AddBlock(Kind: TTraceBlockKind): TTraceBlock;
Var
  InsertAt: Integer;
Begin
  Result := TTraceBlock.Create;
  Result.Kind := Kind;
  Result.LoopIndex := 0;
  Result.Running := False;
  Result.Ok := True;
  Result.Collapsed := False;
  Result.StartedAt := 0;
  Result.FinishedAt := 0;
  Result.DurationMs := 0;
  Result.Footer := '';
  InsertAt := FBlocks.Count;
  If (Kind <> tbkWorked) And (InsertAt > 0) And (TTraceBlock(FBlocks[InsertAt - 1]).Kind = tbkWorked) Then
    FBlocks.Insert(InsertAt - 1, Result)
  Else
    FBlocks.Add(Result);
End;

Function TAssistantTrace.AddUser(Const Text: String): TTraceBlock;
Begin
  Result := AddBlock(tbkUser);
  Result.Title := 'User';
  Result.Body := Text;
End;

Function TAssistantTrace.EnsureUser(Const Text: String): TTraceBlock;
Var
  First: TTraceBlock;
Begin
  If FBlocks.Count > 0 Then
    Begin
      First := TTraceBlock(FBlocks[0]);
      If First.Kind = tbkUser Then
        Begin
          Result := First;
          If Text <> '' Then
            Result.Body := Text;
          Exit;
        End;
    End;
  If Text = '' Then
    Begin
      Result := Nil;
      Exit;
    End;
  Result := AddBlock(tbkUser);
  Result.Title := 'User';
  Result.Body := Text;
  If FBlocks.Count > 1 Then
    FBlocks.Move(FBlocks.Count - 1, 0);
End;

Function CleanTraceLabel(Const Value: String): String;
Var
  Lower: String;
Begin
  Result := Trim(Value);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Lower := LowerCase(Result);
  If (Length(Result) > 240) Or (Pos('data:', Lower) > 0) Or (Pos('base64', Lower) > 0) Then
    Result := '';
End;

Function TraceImageFileName(Const Ref: TTraceImageRef): String;
Begin
  Result := CleanTraceLabel(Ref.Name);
  If Result = '' Then Result := CleanTraceLabel(Ref.Id);
  If Result = '' Then Result := 'Image';
End;

Function TraceImagesToJson(Const Refs: TTraceImageRefArray): TJSONArray;
Var
  I: Integer;
  Obj: TJSONObject;
Begin
  Result := TJSONArray.Create;
  For I := 0 To High(Refs) Do
    Begin
      Obj := TJSONObject.Create;
      Obj.Add('id', CleanTraceLabel(Refs[I].Id));
      Obj.Add('name', CleanTraceLabel(Refs[I].Name));
      Obj.Add('display', CleanTraceLabel(Refs[I].DisplayPath));
      Obj.Add('width', Refs[I].Width);
      Obj.Add('height', Refs[I].Height);
      Result.Add(Obj);
    End;
End;

Function TraceImagesFromJson(Data: TJSONData): TTraceImageRefArray;
Var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, Kept: Integer;
Begin
  Result := Nil;
  SetLength(Result, 0);
  If Not (Data Is TJSONArray) Then Exit;
  Arr := TJSONArray(Data);
  SetLength(Result, Arr.Count);
  Kept := 0;
  For I := 0 To Arr.Count - 1 Do
    If Arr.Items[I] Is TJSONObject Then
      Begin
        Obj := TJSONObject(Arr.Items[I]);
        Result[Kept].Id := CleanTraceLabel(Obj.Get('id', ''));
        Result[Kept].Name := CleanTraceLabel(Obj.Get('name', ''));
        Result[Kept].DisplayPath := CleanTraceLabel(Obj.Get('display', ''));
        Result[Kept].Width := Obj.Get('width', 0);
        Result[Kept].Height := Obj.Get('height', 0);
        Result[Kept].Missing := False;
        If (Result[Kept].Id <> '') Or (Result[Kept].Name <> '') Or (Result[Kept].DisplayPath <> '') Then Inc(Kept);
      End;
  SetLength(Result, Kept);
End;

Procedure TAssistantTrace.SetUserImages(Const Ids, Names: Array Of String);
Var
  Block: TTraceBlock;
  I, RefCount: Integer;
Begin
  RefCount := Length(Ids);
  If Length(Names) > RefCount Then RefCount := Length(Names);
  If RefCount < 1 Then Exit;
  Block := EnsureUser('');
  If Not Assigned(Block) Then
    Begin
      Block := AddBlock(tbkUser);
      Block.Title := 'User';
      If FBlocks.Count > 1 Then FBlocks.Move(FBlocks.Count - 1, 0);
    End;
  SetLength(Block.ImageRefs, RefCount);
  For I := 0 To RefCount - 1 Do
    Begin
      If I < Length(Ids) Then Block.ImageRefs[I].Id := CleanTraceLabel(Ids[I]) Else Block.ImageRefs[I].Id := '';
      If I < Length(Names) Then Block.ImageRefs[I].Name := CleanTraceLabel(Names[I]) Else Block.ImageRefs[I].Name := '';
      Block.ImageRefs[I].DisplayPath := '';
      Block.ImageRefs[I].Width := 0;
      Block.ImageRefs[I].Height := 0;
      Block.ImageRefs[I].Missing := False;
    End;
End;

Procedure TAssistantTrace.SetUserImageRefs(Const Refs: TTraceImageRefArray);
Var
  Block: TTraceBlock;
  I: Integer;
Begin
  If Length(Refs) < 1 Then Exit;
  Block := EnsureUser('');
  If Not Assigned(Block) Then
    Begin
      Block := AddBlock(tbkUser);
      Block.Title := 'User';
      If FBlocks.Count > 1 Then FBlocks.Move(FBlocks.Count - 1, 0);
    End;
  SetLength(Block.ImageRefs, Length(Refs));
  For I := 0 To High(Refs) Do
    Begin
      Block.ImageRefs[I].Id := CleanTraceLabel(Refs[I].Id);
      Block.ImageRefs[I].Name := CleanTraceLabel(Refs[I].Name);
      Block.ImageRefs[I].DisplayPath := CleanTraceLabel(Refs[I].DisplayPath);
      Block.ImageRefs[I].Width := Refs[I].Width;
      Block.ImageRefs[I].Height := Refs[I].Height;
      If (Block.ImageRefs[I].Width < 0) Or (Block.ImageRefs[I].Width > 16384) Then Block.ImageRefs[I].Width := 0;
      If (Block.ImageRefs[I].Height < 0) Or (Block.ImageRefs[I].Height > 16384) Then Block.ImageRefs[I].Height := 0;
      Block.ImageRefs[I].Missing := Refs[I].Missing;
    End;
End;

Procedure TAssistantTrace.AppendUserImages(Const ImagesJson: String);
Var
  Data: TJSONData;
  Block: TTraceBlock;
  Refs: TTraceImageRefArray;
Begin
  If Trim(ImagesJson) = '' Then Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ImagesJson);
    Except
      Exit;
    End;
    Refs := TraceImagesFromJson(Data);
  Finally
    Data.Free;
  End;
  If Length(Refs) = 0 Then Exit;
  Block := AddUser('');
  If Assigned(Block) Then Block.ImageRefs := Refs;
End;

Procedure TAssistantTrace.KeepUserImageRefs(Const Refs: TTraceImageRefArray);
Var
  Block: TTraceBlock;
  I, J: Integer;
Begin
  If Length(Refs) < 1 Then Exit;
  Block := EnsureUser('');
  If Not Assigned(Block) Then
    Begin
      SetUserImageRefs(Refs);
      Exit;
    End;
  If Length(Block.ImageRefs) = 0 Then
    Begin
      SetUserImageRefs(Refs);
      Exit;
    End;
  For I := 0 To High(Block.ImageRefs) Do
    For J := 0 To High(Refs) Do
      If (Block.ImageRefs[I].Id <> '') And (Block.ImageRefs[I].Id = CleanTraceLabel(Refs[J].Id)) Then
        Begin
          If Block.ImageRefs[I].Name = '' Then Block.ImageRefs[I].Name := CleanTraceLabel(Refs[J].Name);
          If Block.ImageRefs[I].DisplayPath = '' Then Block.ImageRefs[I].DisplayPath := CleanTraceLabel(Refs[J].DisplayPath);
          If Block.ImageRefs[I].Width < 1 Then Block.ImageRefs[I].Width := Refs[J].Width;
          If Block.ImageRefs[I].Height < 1 Then Block.ImageRefs[I].Height := Refs[J].Height;
        End;
End;

Function TAssistantTrace.AddNote(Const Text: String): TTraceBlock;
Begin
  Result := AddBlock(tbkNote);
  Result.Title := 'Note';
  Result.Body := Text;
End;

Function TAssistantTrace.AddSteer(Const Text: String): TTraceBlock;
Begin
  Result := AddBlock(tbkSteer);
  Result.Title := 'Steer';
  Result.Body := Text;
  Result.Running := True;
End;

Function TAssistantTrace.StartThinking(LoopIndex: Integer): TTraceBlock;
Begin
  FinishCurrentThinking;
  Result := AddBlock(tbkThinking);
  Result.Title := ThinkingCardTitle(0, True);
  Result.LoopIndex := LoopIndex;
  Result.Running := True;
  Result.StartedAt := Now;
  Result.Collapsed := True;
End;

Function TAssistantTrace.CurrentThinking: TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Block.Kind = tbkThinking Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.CurrentRunningThinking: TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkThinking) And Block.Running Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.LatestBlockSinceLastTool(Kind: TTraceBlockKind): TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Block.Kind = tbkTool Then
        Exit;
      If Block.Kind = Kind Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.AddTool(Const ToolId, ToolName, Args: String): TTraceBlock;
Begin
  FinishCurrentThinking;
  FinishCurrentAnswer;
  Result := FindTool(ToolId);
  If Assigned(Result) Then
    Begin
      Result.ToolName := ToolName;
      Result.ToolArgs := Args;
      Result.Running := True;
      Result.Title := ToolCardCaption(ToolName, Args);
      Exit;
    End;
  Result := AddBlock(tbkTool);
  Result.ToolId := ToolId;
  Result.ToolName := ToolName;
  Result.ToolArgs := Args;
  Result.Running := True;
  Result.Collapsed := True;
  Result.StartedAt := Now;
  Result.Title := ToolCardCaption(ToolName, Args);
End;

Function TAssistantTrace.AddSubagent(Const SubId, KindName, Title: String): TTraceBlock;
Begin
  Result := FindSubagent(SubId);
  If Assigned(Result) Then
    Begin
      If KindName <> '' Then
        Result.ToolName := KindName;
      If Title <> '' Then
        Result.Title := Title;
      Result.Running := True;
      Exit;
    End;
  Result := AddBlock(tbkSubagent);
  Result.ToolId := SubId;
  Result.ToolName := KindName;
  Result.Title := Title;
  Result.Running := True;
  Result.StartedAt := Now;
End;

Function TAssistantTrace.FindSubagent(Const SubId: String): TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  If SubId = '' Then
    Exit;
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkSubagent) And (Block.ToolId = SubId) Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.HasRunningSubagentOlderThan(BudgetMs: Integer): Boolean;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := False;
  If BudgetMs < 0 Then
    Exit;
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Assigned(Block) And (Block.Kind = tbkSubagent) And Block.Running And
        (Block.DurationMs >= BudgetMs) Then
        Begin
          Result := True;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.FindRunningSubagentByKind(Const KindName: String): TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  If Trim(KindName) = '' Then
    Exit;
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkSubagent) And Block.Running And SameText(Block.ToolName, KindName) Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.FindTool(Const ToolId: String): TTraceBlock;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := Nil;
  If ToolId = '' Then
    Exit;
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkTool) And (Block.ToolId = ToolId) Then
        Begin
          Result := Block;
          Exit;
        End;
    End;
End;

Function TAssistantTrace.EnsureAnswer: TTraceBlock;
Begin
  { Same sample: update the existing answer. A new card only after a tool (new model loop).
    Do not finish thinking here — grok-4.6 still streams CoT while the message grows. }
  Result := LatestBlockSinceLastTool(tbkAnswer);
  If Assigned(Result) Then
    Exit;
  Result := AddBlock(tbkAnswer);
  Result.Title := 'Assistant';
  Result.Running := True;
End;

Procedure TAssistantTrace.FinishThinkingBlock(Block: TTraceBlock);
Begin
  If Not Assigned(Block) Then
    Exit;
  Block.Running := False;
  If (Block.StartedAt > 0) And (Block.DurationMs = 0) Then
    Block.DurationMs := MilliSecondsBetween(Now, Block.StartedAt);
  Block.FinishedAt := Now;
  Block.Title := ThinkingCardTitle(Block.DurationMs, False);
  If Block.DurationMs > 0 Then
    Block.Footer := FormatThoughtFooter(Block.DurationMs)
  Else
    Block.Footer := '';
End;

Procedure TAssistantTrace.FinishCurrentThinking;
Begin
  FinishThinkingBlock(CurrentRunningThinking);
End;

Procedure TAssistantTrace.FinishCurrentAnswer;
Var
  Block: TTraceBlock;
Begin
  Block := LatestBlockSinceLastTool(tbkAnswer);
  If Assigned(Block) Then
    Block.Running := False;
End;

Procedure TAssistantTrace.CollapseThinking(HideBody: Boolean);
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Block.Kind = tbkThinking Then
        Begin
          Block.Collapsed := HideBody;
          FinishThinkingBlock(Block);
        End;
    End;
End;

Procedure TAssistantTrace.TickElapsed;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkThinking) And Block.Running And (Block.StartedAt > 0) Then
        Begin
          Block.DurationMs := MilliSecondsBetween(Now, Block.StartedAt);
          Block.Title := ThinkingCardTitle(Block.DurationMs, True);
        End;
      If ((Block.Kind = tbkTool) Or (Block.Kind = tbkSubagent)) And Block.Running And
        (Block.StartedAt > 0) Then
        Block.DurationMs := MilliSecondsBetween(Now, Block.StartedAt);
    End;
End;

Procedure TAssistantTrace.ApplyWorkedFooter(DurationMs: Integer);
Var
  I, Index: Integer;
  Block, Worked: TTraceBlock;
Begin
  Worked := Nil;
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Block.Kind = tbkWorked Then
        Begin
          Worked := Block;
          Break;
        End;
      If (Copy(Block.Footer, 1, 10) = 'Worked for') Then
        Block.Footer := '';
    End;
  If DurationMs <= 0 Then
    Begin
      If Assigned(Worked) Then
        FBlocks.Remove(Worked);
      Exit;
    End;
  If Not Assigned(Worked) Then
    Begin
      Worked := AddBlock(tbkWorked);
      Worked.Title := '';
    End;
  Worked.Body := FormatWorkedFooter(DurationMs);
  Worked.DurationMs := DurationMs;
  Worked.Running := False;
  Index := FBlocks.IndexOf(Worked);
  If (Index >= 0) And (Index <> FBlocks.Count - 1) Then
    FBlocks.Move(Index, FBlocks.Count - 1);
End;

Function TAssistantTrace.ThinkingDurationMs: Integer;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := 0;
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If Block.Kind = tbkThinking Then
        Result := Result + Block.DurationMs;
    End;
End;

Function TAssistantTrace.JoinedThinking: String;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := '';
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkThinking) And (Trim(Block.Body) <> '') Then
        Begin
          If Result <> '' Then
            Result := Result + LineEnding + LineEnding;
          Result := Result + Block.Body;
        End;
    End;
End;

Function TAssistantTrace.FormatMarkdown(IncludeUser: Boolean): String;
Var
  I: Integer;
  Block: TTraceBlock;
  Parts: TStringList;
  Heading, Body: String;
  J: Integer;
Begin
  Parts := TStringList.Create;
  Try
    For I := 0 To FBlocks.Count - 1 Do
      Begin
        Block := TTraceBlock(FBlocks[I]);
        If Not Assigned(Block) Then
          Continue;
        Heading := '';
        Body := Trim(Block.Body);
        Case Block.Kind Of
          tbkUser:
            If IncludeUser Then
              Heading := '### User';
          tbkThinking:
            If Body <> '' Then
              Heading := '### Thinking';
          tbkTool:
            Begin
              Heading := '### Tool';
              If Trim(Block.Title) <> '' Then
                Heading := Heading + ': ' + Trim(Block.Title);
            End;
          tbkSubagent:
            Begin
              If Trim(Block.Title) <> '' Then
                Heading := '### ' + Trim(Block.Title)
              Else
                Heading := '### Subagent';
            End;
          tbkAnswer:
            If SliceLooksLikeAnswer(Body) Or (Block.Footer <> '') Then
              Heading := '### Assistant';
          tbkSteer:
            Heading := '### Steer';
          tbkNote:
            Heading := '### Note';
          tbkWorked:
            Begin
              If Body <> '' Then
                Begin
                  If Parts.Count > 0 Then
                    Parts.Add('');
                  Parts.Add('*' + Body + '*');
                End;
              Continue;
            End;
        End;
        If Heading = '' Then
          Continue;
        If Parts.Count > 0 Then
          Parts.Add('');
        Parts.Add(Heading);
        Parts.Add('');
        If Body <> '' Then
          Parts.Add(Body)
        Else If Block.Kind = tbkTool Then
          Parts.Add('*(no result)*')
        Else If Block.Kind = tbkSubagent Then
          Parts.Add('*(no summary)*');
        If (Block.Kind = tbkUser) And IncludeUser Then
          For J := 0 To High(Block.ImageRefs) Do
            Parts.Add(TraceImageFileName(Block.ImageRefs[J]));
        If (Block.Footer <> '') And (Block.Kind In [tbkSubagent, tbkAnswer, tbkNote, tbkThinking]) Then
          Begin
            Parts.Add('');
            Parts.Add('*' + Block.Footer + '*');
          End;
      End;
    Result := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function TAssistantTrace.JoinedAnswers: String;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Result := '';
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkAnswer) And SliceLooksLikeAnswer(Block.Body) Then
        Begin
          If Result <> '' Then
            Result := Result + LineEnding + LineEnding;
          Result := Result + Block.Body;
        End;
    End;
End;

Function TAssistantTrace.SaveToJson: String;
Var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Block: TTraceBlock;
Begin
  Arr := TJSONArray.Create;
  Try
    For I := 0 To FBlocks.Count - 1 Do
      Begin
        Block := TTraceBlock(FBlocks[I]);
        If (Block.Kind = tbkThinking) And (Trim(Block.Body) = '') Then Continue;
        Obj := TJSONObject.Create;
        Obj.Add('id', Block.ID);
        Obj.Add('kind', BlockKindName(Block.Kind));
        Obj.Add('title', Block.Title);
        Obj.Add('body', Block.Body);
        Obj.Add('footer', Block.Footer);
        Obj.Add('tool', Block.ToolName);
        Obj.Add('tool_id', Block.ToolId);
        Obj.Add('tool_args', Block.ToolArgs);
        Obj.Add('loop', Block.LoopIndex);
        Obj.Add('ok', Block.Ok);
        Obj.Add('duration_ms', Block.DurationMs);
        If (Block.Kind = tbkUser) And (Length(Block.ImageRefs) > 0) Then
          Obj.Add('images', TraceImagesToJson(Block.ImageRefs));
        Arr.Add(Obj);
      End;
    Result := StringReplace(Arr.AsJSON, #13#10, '', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '', [rfReplaceAll]);
    Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Finally
    Arr.Free;
  End;
End;

Procedure TAssistantTrace.ApplyEvent(Const Event: TAssistantEvent);
Var
  Block: TTraceBlock;
Begin
  Case Event.Kind Of
    aekLoopStarted:
      Begin
        FinishCurrentThinking;
        FinishCurrentAnswer;
        StartThinking(Event.LoopIndex);
      End;
    aekToolStarted:
      AddTool(Event.ToolId, Event.ToolName, Event.Text);
    aekToolCompleted:
      Begin
        Block := FindTool(Event.ToolId);
        If Not Assigned(Block) Then
          Block := AddTool(Event.ToolId, Event.ToolName, '');
        Block.Running := False;
        Block.Ok := Event.Ok;
        If Event.DurationMs > 0 Then
          Block.DurationMs := Event.DurationMs;
        If Event.Text <> '' Then
          Block.Body := Event.Text;
        If Event.AttachmentsJson <> '' Then
          AppendUserImages(Event.AttachmentsJson);
        If Not Event.Ok Then
          Begin
            Block.Collapsed := False;
            If Pos('failed', LowerCase(Block.Title)) < 1 Then
              Block.Title := Block.Title + '  failed';
          End;
      End;
    aekSubagentStarted:
      Begin
        Block := AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
        Block.Running := True;
        Block.Ok := Event.Ok;
        If Event.Text <> '' Then
          Block.Title := Event.Text
        Else If Event.ToolName <> '' Then
          Block.Title := 'Subagent · ' + Event.ToolName;
      End;
    aekSubagentProgress:
      Begin
        Block := FindSubagent(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FindRunningSubagentByKind(Event.ToolName);
        If Not Assigned(Block) Then
          Begin
            If Event.ToolId = '' Then
              Exit;
            Block := AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
          End;
        Block.Running := True;
        If Event.Text <> '' Then
          Block.Title := Event.Text;
      End;
    aekSubagentCompleted:
      Begin
        Block := FindSubagent(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FindRunningSubagentByKind(Event.ToolName);
        If Not Assigned(Block) Then
          Begin
            If Event.ToolId = '' Then
              Exit;
            Block := AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
          End;
        Block.Running := False;
        Block.Ok := Event.Ok;
        If Event.DurationMs > 0 Then
          Block.DurationMs := Event.DurationMs;
        If Event.Text <> '' Then
          Block.Body := Event.Text;
        If Event.ToolName <> '' Then
          Block.Title := 'Subagent · ' + Event.ToolName;
        If Not Event.Ok Then
          Block.Footer := 'failed'
        Else If Event.DurationMs > 0 Then
          Block.Footer := FormatThoughtElapsed(Event.DurationMs);
      End;
    aekSteerQueued:
      AddSteer(Event.Text);
    aekInterjected:
      Begin
        Block := Nil;
        If FBlocks.Count > 0 Then
          Block := TTraceBlock(FBlocks[FBlocks.Count - 1]);
        If Assigned(Block) And (Block.Kind = tbkSteer) Then
          Begin
            Block.Running := False;
            Block.Title := 'Steer · applied';
            If Event.Text <> '' Then
              Block.Body := Event.Text;
          End
        Else
          Begin
            Block := AddSteer(Event.Text);
            Block.Running := False;
            Block.Title := 'Steer · applied';
          End;
      End;
    aekError:
      If Trim(Event.Text) <> '' Then
        AddNote('**Error:** ' + Event.Text);
    aekTurnEnded:
      Begin
        FinishCurrentThinking;
        FinishCurrentAnswer;
      End;
  Else
    { turn_started / phase / deltas are structure-only or live snapshots. }
  End;
End;

Procedure TAssistantTrace.FinishReplay;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  FinishCurrentThinking;
  FinishCurrentAnswer;
  For I := 0 To FBlocks.Count - 1 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      Block.Running := False;
    End;
End;

Function TAssistantTrace.ReplayEvents(Const Prompt: String; Const Events: TAssistantEventArray;
  Const ThinkingText, ResponseText: String): Boolean;
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  Clear;
  If Trim(Prompt) <> '' Then
    AddUser(Prompt);
  StartThinking(0);
  For I := 0 To High(Events) Do
    ApplyEvent(Events[I]);
  FinishReplay;
  If (Trim(ThinkingText) <> '') And (JoinedThinking = '') Then
    Begin
      Block := CurrentThinking;
      If Not Assigned(Block) Then
        Block := StartThinking(0);
      Block.Body := ThinkingText;
      FinishReplay;
    End;
  If (Trim(ResponseText) <> '') And (JoinedAnswers = '') Then
    EnsureAnswer.Body := ResponseText;
  FinishReplay;
  Result := Count > 0;
End;

Function TAssistantTrace.ReplayFromEventsFile(Const FileName, Prompt, ThinkingText, ResponseText: String): Boolean;
Var
  Events: TAssistantEventArray;
Begin
  Result := False;
  If Not LoadAssistantEventsFile(FileName, Events) Then
    Exit;
  Result := ReplayEvents(Prompt, Events, ThinkingText, ResponseText);
End;

Procedure TAssistantTrace.LoadFromJson(Const Json: String);
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Block: TTraceBlock;
Begin
  Clear;
  If Trim(Json) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Json);
    Except
      Exit;
    End;
    If Not (Data Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Data);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Obj := TJSONObject(Arr.Items[I]);
        Block := AddBlock(NameToBlockKind(Obj.Get('kind', 'user')));
        Block.ID := Obj.Get('id', Block.ID);
        Block.Title := Obj.Get('title', '');
        Block.Body := Obj.Get('body', '');
        Block.Footer := Obj.Get('footer', '');
        Block.ToolName := Obj.Get('tool', '');
        Block.ToolId := Obj.Get('tool_id', '');
        Block.ToolArgs := Obj.Get('tool_args', '');
        Block.LoopIndex := Obj.Get('loop', 0);
        Block.Ok := Obj.Get('ok', True);
        Block.DurationMs := Obj.Get('duration_ms', 0);
        Block.Running := False;
        If Block.Kind = tbkUser Then
          Block.ImageRefs := TraceImagesFromJson(Obj.Find('images'));
      End;
  Finally
    Data.Free;
  End;
End;

Function SliceLooksLikeAnswer(Const Slice: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 1 To Length(Slice) Do
    If Slice[I] In ['A'..'Z', 'a'..'z', '0'..'9'] Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function SliceLiveChannel(Const LiveText: String; Var StartAt: Integer): String;
Begin
  If StartAt < 1 Then
    StartAt := 1;
  If Length(LiveText) >= StartAt Then
    Result := Copy(LiveText, StartAt, MaxInt)
  Else
    Result := '';
End;

Function MissingImageTileHeight(PixelsPerInch: Integer): Integer;
Begin
  If PixelsPerInch < 1 Then PixelsPerInch := 96;
  Result := Round(32 * PixelsPerInch / 96);
  If Result < 24 Then Result := 24;
End;

Function MissingImageTileCaption(Const Ref: TTraceImageRef): String;
Begin
  Result := Trim(Ref.Name);
  If Result = '' Then Result := Trim(Ref.Id);
  If Result = '' Then Result := 'Image';
  If (Ref.Width > 0) And (Ref.Height > 0) Then
    Result := Result + ', ' + IntToStr(Ref.Width) + ' x ' + IntToStr(Ref.Height);
  Result := Result + ', unavailable';
End;

Function ImageSlotGap(PixelsPerInch: Integer): Integer;
Begin
  If PixelsPerInch < 1 Then PixelsPerInch := 96;
  Result := Round(6 * PixelsPerInch / 96);
  If Result < 4 Then Result := 4;
End;

Function ScaledImageExtent(ImageWidth, ImageHeight, ContentWidth, PixelsPerInch: Integer;
  Out DisplayWidth, DisplayHeight: Integer): Boolean;
Var
  NativeW, NativeH: Integer;
Begin
  DisplayWidth := 0;
  DisplayHeight := 0;
  Result := False;
  If PixelsPerInch < 1 Then PixelsPerInch := 96;
  If ContentWidth < 1 Then ContentWidth := 1;
  If (ImageWidth < 1) Or (ImageHeight < 1) Then Exit;
  { 1:1 is one image pixel per logical pixel. Device pixels follow the surface DPI. }
  NativeW := Round(Int64(ImageWidth) * PixelsPerInch / 96);
  NativeH := Round(Int64(ImageHeight) * PixelsPerInch / 96);
  If NativeW < 1 Then NativeW := 1;
  If NativeH < 1 Then NativeH := 1;
  If NativeW > ContentWidth Then
    Begin
      DisplayWidth := ContentWidth;
      DisplayHeight := Max(1, Round(Int64(NativeH) * ContentWidth / NativeW));
    End
  Else
    Begin
      DisplayWidth := NativeW;
      DisplayHeight := NativeH;
    End;
  Result := True;
End;

Function UserImageSlotHeight(Const Ref: TTraceImageRef; ContentWidth, PixelsPerInch: Integer): Integer;
Var
  DisplayWidth, DisplayHeight: Integer;
Begin
  If PixelsPerInch < 1 Then PixelsPerInch := 96;
  If Ref.Missing Or Not ScaledImageExtent(Ref.Width, Ref.Height, ContentWidth, PixelsPerInch, DisplayWidth, DisplayHeight) Then
    Result := MissingImageTileHeight(PixelsPerInch)
  Else
    Result := DisplayHeight + ImageSlotGap(PixelsPerInch);
End;

Function UserImageRowHeight(Const Refs: TTraceImageRefArray; ContentWidth, PixelsPerInch: Integer): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 0 To High(Refs) Do
    Inc(Result, UserImageSlotHeight(Refs[I], ContentWidth, PixelsPerInch));
End;

Function ImageIndexInRow(Const Refs: TTraceImageRefArray; ContentWidth, PixelsPerInch: Integer; LocalY: Int64): Integer;
Var
  I: Integer;
  TopY, SlotH: Int64;
Begin
  Result := -1;
  If LocalY < 0 Then Exit;
  TopY := 0;
  For I := 0 To High(Refs) Do
    Begin
      SlotH := UserImageSlotHeight(Refs[I], ContentWidth, PixelsPerInch);
      If LocalY < TopY + SlotH Then Exit(I);
      Inc(TopY, SlotH);
    End;
End;

Function FormatThoughtElapsed(DurationMs: Integer): String;
Var
  Secs: Double;
Begin
  If DurationMs < 0 Then
    DurationMs := 0;
  Secs := DurationMs / 1000.0;
  If DurationMs < 60000 Then
    Result := Format('%.1fs', [Secs])
  Else
    Result := Format('%d:%2.2d', [DurationMs Div 60000, (DurationMs Div 1000) Mod 60]);
End;

Function FormatThinkingClock(DurationMs: Integer): String;
Var
  TotalSec: Integer;
Begin
  If DurationMs < 0 Then
    DurationMs := 0;
  TotalSec := DurationMs Div 1000;
  Result := Format('%d:%2.2d', [TotalSec Div 60, TotalSec Mod 60]);
End;

Function FormatThoughtFooter(DurationMs: Integer): String;
Begin
  Result := 'Thought for ' + FormatThinkingClock(DurationMs);
End;

Function FormatWorkedFooter(DurationMs: Integer): String;
Var
  TotalSec, Hours, Mins, Secs: Integer;
Begin
  If DurationMs < 0 Then
    DurationMs := 0;
  TotalSec := DurationMs Div 1000;
  Hours := TotalSec Div 3600;
  Mins := (TotalSec Div 60) Mod 60;
  Secs := TotalSec Mod 60;
  If Hours > 0 Then
    Result := Format('Worked for %d:%2.2d:%2.2d', [Hours, Mins, Secs])
  Else
    Result := Format('Worked for %d:%2.2d', [Mins, Secs]);
End;

Function ThinkingCardTitle(DurationMs: Integer; Running: Boolean): String;
Begin
  If Running Then
    Result := 'Thinking… ' + FormatThinkingClock(DurationMs)
  Else
    Result := 'Thinking';
End;

Function JsonStringHint(Const Args, FieldName: String): String;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := '';
  If (Args = '') Or (Args[1] <> '{') Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Args);
      If Data Is TJSONObject Then
        Begin
          Obj := TJSONObject(Data);
          Result := Trim(Obj.Get(FieldName, ''));
        End;
    Except
      Result := '';
    End;
  Finally
    Data.Free;
  End;
End;

Function ScrollShouldFollowTail(Position, ContentHeight, Page: Integer; Slop: Integer): Boolean;
Var
  MaxPos: Integer;
Begin
  If Page < 1 Then
    Page := 1;
  If Slop < 0 Then
    Slop := 0;
  MaxPos := ContentHeight - Page;
  If MaxPos < 0 Then
    MaxPos := 0;
  If Position < 0 Then
    Position := 0;
  If MaxPos = 0 Then
    Result := True
  Else
    Result := Position >= MaxPos - Slop;
End;

Function ToolCardCaption(Const ToolName, Args: String): String;
Var
  Path, Pattern, Preview, Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  Path := JsonStringHint(Args, 'path');
  If Path = '' Then
    Path := JsonStringHint(Args, 'file');
  { grep/search need the query on the one-line card. replace_in_file old_text
    used to dump a source snippet into the title and made the row unreadable. }
  Pattern := '';
  If (Name = 'grep') Or (Name = 'search_in_project') Then
    Begin
      Pattern := JsonStringHint(Args, 'query');
      If Pattern = '' Then
        Pattern := JsonStringHint(Args, 'pattern');
    End;
  Result := ToolName;
  If Path <> '' Then
    Result := Result + '  ' + ExtractFileName(Path);
  If Pattern <> '' Then
    Begin
      Preview := Pattern;
      If Length(Preview) > 40 Then
        Preview := Copy(Preview, 1, 37) + '…';
      Result := Result + '  ' + Preview;
    End;
End;

End.
