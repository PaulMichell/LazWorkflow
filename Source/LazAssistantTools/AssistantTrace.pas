Unit AssistantTrace;

{ In-memory current-turn block list for the Project Assistant trace (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Type
  TTraceBlockKind = (tbkUser, tbkThinking, tbkTool, tbkAnswer, tbkNote, tbkSteer);

  TTraceBlock = Class
  Public
    Kind: TTraceBlockKind;
    Title: String;
    Body: String;
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
    Frame: TObject; { TControl created by AssistantTraceView; untyped to keep this unit LCL-free. }
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
    Procedure NilFrames;
    Function AddUser(Const Text: String): TTraceBlock;
    Function EnsureUser(Const Text: String): TTraceBlock;
    Function AddNote(Const Text: String): TTraceBlock;
    Function AddSteer(Const Text: String): TTraceBlock;
    Function StartThinking(LoopIndex: Integer): TTraceBlock;
    Function CurrentThinking: TTraceBlock;
    Function CurrentRunningThinking: TTraceBlock;
    Function AddTool(Const ToolId, ToolName, Args: String): TTraceBlock;
    Function FindTool(Const ToolId: String): TTraceBlock;
    { Reuse the last block when it is already an answer; otherwise append a new one. }
    Function EnsureAnswer: TTraceBlock;
    Procedure FinishCurrentThinking;
    Procedure CollapseThinking(HideBody: Boolean = True);
    Procedure TickElapsed;
    Procedure ApplyWorkedFooter(DurationMs: Integer);
    Function ThinkingDurationMs: Integer;
    Property Count: Integer Read GetCount;
    Property Blocks[Index: Integer]: TTraceBlock Read GetBlock; Default;
  End;

{ Slice LiveText from 1-based StartAt. Past-the-end yields '' and leaves StartAt
  so the same loop cannot reopen an answer under a tool. The next loop must set
  StartAt := 1 (aekLoopStarted). }
Function SliceLiveChannel(Const LiveText: String; Var StartAt: Integer): String;

Function FormatThoughtElapsed(DurationMs: Integer): String;
Function FormatThinkingClock(DurationMs: Integer): String;
Function FormatThoughtFooter(DurationMs: Integer): String;
Function FormatWorkedFooter(DurationMs: Integer): String;
Function ThinkingCardTitle(DurationMs: Integer; Running: Boolean): String;
Function ToolCardCaption(Const ToolName, Args: String): String;

Implementation

Uses
  DateUtils, fpjson, jsonparser;

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

Procedure TAssistantTrace.NilFrames;
Var
  I: Integer;
Begin
  For I := 0 To FBlocks.Count - 1 Do
    TTraceBlock(FBlocks[I]).Frame := Nil;
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
  Result.Frame := Nil;
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
  Result.Collapsed := False;
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

Function TAssistantTrace.AddTool(Const ToolId, ToolName, Args: String): TTraceBlock;
Begin
  FinishCurrentThinking;
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
  Result.StartedAt := Now;
  Result.Title := ToolCardCaption(ToolName, Args);
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
Var
  Last: TTraceBlock;
Begin
  If FBlocks.Count > 0 Then
    Begin
      Last := TTraceBlock(FBlocks[FBlocks.Count - 1]);
      If Last.Kind = tbkAnswer Then
        Begin
          Result := Last;
          Exit;
        End;
    End;
  FinishCurrentThinking;
  Result := AddBlock(tbkAnswer);
  Result.Title := 'Assistant';
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
      If (Block.Kind = tbkTool) And Block.Running And (Block.StartedAt > 0) Then
        Block.DurationMs := MilliSecondsBetween(Now, Block.StartedAt);
    End;
End;

Procedure TAssistantTrace.ApplyWorkedFooter(DurationMs: Integer);
Var
  I: Integer;
  Block: TTraceBlock;
Begin
  For I := FBlocks.Count - 1 DownTo 0 Do
    Begin
      Block := TTraceBlock(FBlocks[I]);
      If (Block.Kind = tbkAnswer) Or (Block.Kind = tbkNote) Then
        Begin
          Block.Footer := FormatWorkedFooter(DurationMs);
          Exit;
        End;
    End;
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

Function SliceLiveChannel(Const LiveText: String; Var StartAt: Integer): String;
Begin
  If StartAt < 1 Then
    StartAt := 1;
  If Length(LiveText) >= StartAt Then
    Result := Copy(LiveText, StartAt, MaxInt)
  Else
    Result := '';
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

Function ToolCardCaption(Const ToolName, Args: String): String;
Var
  Path, Pattern, Preview: String;
Begin
  Path := JsonStringHint(Args, 'path');
  If Path = '' Then
    Path := JsonStringHint(Args, 'file');
  Pattern := JsonStringHint(Args, 'query');
  If Pattern = '' Then
    Pattern := JsonStringHint(Args, 'pattern');
  If Pattern = '' Then
    Pattern := JsonStringHint(Args, 'old_text');
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
