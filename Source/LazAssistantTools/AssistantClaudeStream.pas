Unit AssistantClaudeStream;

{ Claude Code print-mode output, folded into one turn (c) 2026 Michell Computing.

  Pure text and JSON: no processes and no IDE units, so the stream-json rules can be tested against captured
  output. AssistantClaudeClient runs the program and feeds each line here. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes;

Type
  TClaudeTurnResult = Record
    Text: String;
    UsageState: String;
    { Prompt tokens including cached ones, summed over every model call in the turn. }
    InputTokens: Int64;
    OutputTokens: Int64;
  End;

  { One turn's stream-json events, folded. }
  TClaudeStreamState = Record
    SessionId: String;
    { apiKeySource from the init event. 'none' is the subscription. }
    KeySource: String;
    Model: String;
    { Every assistant text block so far, in order. }
    Text: String;
    ToolCalls: Integer;
    Denials: Integer;
    { The latest rate_limit_info object, as JSON, and its status. }
    RateLimitJson: String;
    RateLimitStatus: String;
    { Prompt size of the latest model call, including cached tokens. }
    ContextTokens: Int64;
    Finished: Boolean;
    IsError: Boolean;
    ResultSubtype: String;
    ErrorText: String;
    Turn: TClaudeTurnResult;
  End;

Const
  ClaudeUsageReported = 'reported';
  ClaudeUsageUnavailable = 'unavailable';
  { The model value that leaves the choice to Claude Code. }
  ClaudeDefaultModel = 'default';
  { The documented aliases, offered before the program has been asked for its list. }
  ClaudeModelAliases: Array[0..4] Of String = ('default', 'opus', 'sonnet', 'fable', 'haiku');

/// An empty stream with usage marked unavailable.
Procedure ClearClaudeStream(Out State: TClaudeStreamState);
/// The text from the first opening brace to the last closing brace, for output with stray lines around one object.
Function JsonObjectText(Const Output: String): String;
/// True when Claude Code's stderr says it rejected the --permission-mode argument.
Function PermissionFlagRefused(Const ErrorOutput: String): Boolean;
/// Folds one stream-json line into State. False when the line is not a JSON object.
Function ApplyClaudeStreamLine(Const Line: String; Var State: TClaudeStreamState): Boolean;
/// The finished turn from its stream, exit code and stderr. False with ErrorText when it is not an answer.
Function ClaudeTurnOutcome(Const State: TClaudeStreamState; ExitCode: Integer; Const ErrorOutput: String;
  Out ErrorText: String): Boolean;
/// The models array from an initialize control response in OutputText, as JSON. Nothing else is kept.
Function ClaudeModelsFromControlResponse(Const OutputText, RequestId: String; Out ModelsJson: String): Boolean;
/// Model values in the order Claude Code lists them. Falls back to ClaudeModelAliases for an empty or bad list.
Procedure CollectClaudeModels(Const ModelsJson: String; Values: TStrings);
/// Display name and description of one model value, for a hint line. Empty when it is not in the list.
Function ClaudeModelDescription(Const ModelsJson, Value: String): String;
/// The effort levels one model accepts. False when the model is not listed or takes no effort level.
Function CollectClaudeEffortLevels(Const ModelsJson, Value: String; Levels: TStrings): Boolean;
/// One single-result JSON object (--output-format json), read as a finished stream.
Function ParseClaudeTurnResult(Const JsonText: String; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;

Implementation

Uses
  SysUtils, fpjson, jsonparser;

Const
  ClaudeNoJsonText = 'Claude Code did not return a JSON result.';

Procedure ClearTurn(Out Turn: TClaudeTurnResult);
Begin
  Turn.Text := '';
  Turn.UsageState := ClaudeUsageUnavailable;
  Turn.InputTokens := 0;
  Turn.OutputTokens := 0;
End;

Procedure ClearClaudeStream(Out State: TClaudeStreamState);
Begin
  State := Default(TClaudeStreamState);
  ClearTurn(State.Turn);
End;

Function BoundText(Const Value: String): String;
Begin
  Result := Trim(Value);
  If Length(Result) > 1000 Then
    Result := Copy(Result, 1, 1000);
End;

Function PermissionFlagRefused(Const ErrorOutput: String): Boolean;
Var
  Lowered: String;
Begin
  { Commander's wording: option '--permission-mode <mode>' argument 'x' is invalid. }
  Lowered := LowerCase(ErrorOutput);
  Result := (Pos('--permission-mode', Lowered) > 0) And
    ((Pos('is invalid', Lowered) > 0) Or (Pos('unknown option', Lowered) > 0));
End;

Function JsonObjectText(Const Output: String): String;
Var
  StartAt, EndAt, I: Integer;
Begin
  Result := Trim(Output);
  { The object starts a line. A warning line before it may itself contain a brace. }
  StartAt := 0;
  I := 1;
  While (StartAt = 0) And (I <= Length(Result)) Do
    Begin
      While (I <= Length(Result)) And (Result[I] In [' ', #9]) Do
        Inc(I);
      If (I <= Length(Result)) And (Result[I] = '{') Then
        StartAt := I
      Else
        Begin
          While (I <= Length(Result)) And (Result[I] <> #10) Do
            Inc(I);
          Inc(I);
        End;
    End;
  EndAt := 0;
  For I := Length(Result) DownTo 1 Do
    If Result[I] = '}' Then
      Begin
        EndAt := I;
        Break;
      End;
  If (StartAt > 0) And (EndAt >= StartAt) Then
    Result := Copy(Result, StartAt, EndAt - StartAt + 1);
End;

Function JsonNumber(Node: TJSONData): Int64;
Begin
  If Node Is TJSONNumber Then
    Result := Node.AsInt64
  Else
    Result := 0;
End;

{ Prompt tokens including the cached part. Without the cache a resumed turn looks almost empty. }
Function PromptTokens(Usage: TJSONObject): Int64;
Begin
  Result := JsonNumber(Usage.Find('input_tokens')) + JsonNumber(Usage.Find('cache_read_input_tokens')) +
    JsonNumber(Usage.Find('cache_creation_input_tokens'));
End;

Procedure ReadAssistantMessage(Event: TJSONObject; Var State: TClaudeStreamState);
Var
  MessageNode, Block: TJSONObject;
  Content: TJSONArray;
  I: Integer;
  Piece: String;
Begin
  If Not (Event.Find('message') Is TJSONObject) Then
    Exit;
  MessageNode := TJSONObject(Event.Find('message'));
  If MessageNode.Find('usage') Is TJSONObject Then
    State.ContextTokens := PromptTokens(TJSONObject(MessageNode.Find('usage')));
  If Not (MessageNode.Find('content') Is TJSONArray) Then
    Exit;
  Content := TJSONArray(MessageNode.Find('content'));
  Piece := '';
  For I := 0 To Content.Count - 1 Do
    If Content.Items[I] Is TJSONObject Then
      Begin
        Block := TJSONObject(Content.Items[I]);
        If (Block.Get('type', '') = 'text') And (Block.Find('text') Is TJSONString) Then
          Piece := Piece + Block.Get('text', '')
        Else If Block.Get('type', '') = 'tool_use' Then
          Inc(State.ToolCalls);
      End;
  If Piece = '' Then
    Exit;
  If State.Text <> '' Then
    State.Text := State.Text + LineEnding + LineEnding;
  State.Text := State.Text + Piece;
End;

Procedure ReadResult(Event: TJSONObject; Var State: TClaudeStreamState);
Var
  Errors: TJSONArray;
  Usage: TJSONObject;
  I: Integer;
Begin
  State.Finished := True;
  State.ResultSubtype := Event.Get('subtype', '');
  State.IsError := (Event.Find('is_error') Is TJSONBoolean) And Event.Get('is_error', False);
  If Event.Find('result') Is TJSONString Then
    State.Turn.Text := Event.Get('result', '');
  If Event.Find('permission_denials') Is TJSONArray Then
    State.Denials := TJSONArray(Event.Find('permission_denials')).Count;
  State.ErrorText := '';
  If Event.Find('errors') Is TJSONArray Then
    Begin
      Errors := TJSONArray(Event.Find('errors'));
      For I := 0 To Errors.Count - 1 Do
        If Errors.Items[I] Is TJSONString Then
          Begin
            If State.ErrorText <> '' Then
              State.ErrorText := State.ErrorText + ' ';
            State.ErrorText := State.ErrorText + Errors.Items[I].AsString;
          End;
    End;
  If Not (Event.Find('usage') Is TJSONObject) Then
    Exit;
  Usage := TJSONObject(Event.Find('usage'));
  If (Usage.Find('input_tokens') Is TJSONNumber) And (Usage.Find('output_tokens') Is TJSONNumber) Then
    Begin
      State.Turn.UsageState := ClaudeUsageReported;
      State.Turn.InputTokens := PromptTokens(Usage);
      State.Turn.OutputTokens := JsonNumber(Usage.Find('output_tokens'));
    End;
End;

Function ApplyClaudeStreamLine(Const Line: String; Var State: TClaudeStreamState): Boolean;
Var
  Data: TJSONData;
  Event, RateLimit: TJSONObject;
  EventType, Subtype: String;
Begin
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Line);
    Except
      On EParserError Do
        Exit;
    End;
    If Not (Data Is TJSONObject) Then
      Exit;
    Event := TJSONObject(Data);
    EventType := Event.Get('type', '');
    Subtype := Event.Get('subtype', '');
    { A single --output-format json result has the same fields and sometimes no type. }
    If (EventType = '') And ((Event.Find('result') <> Nil) Or (Event.Find('is_error') <> Nil)) Then
      EventType := 'result';
    If Event.Find('session_id') Is TJSONString Then
      State.SessionId := Event.Get('session_id', '');
    If (EventType = 'system') And (Subtype = 'init') Then
      Begin
        State.KeySource := Event.Get('apiKeySource', '');
        State.Model := Event.Get('model', '');
      End
    Else If (EventType = 'system') And (Subtype = 'permission_denied') Then
      Inc(State.Denials)
    Else If EventType = 'assistant' Then
      ReadAssistantMessage(Event, State)
    Else If (EventType = 'rate_limit_event') And (Event.Find('rate_limit_info') Is TJSONObject) Then
      Begin
        RateLimit := TJSONObject(Event.Find('rate_limit_info'));
        State.RateLimitJson := RateLimit.AsJSON;
        State.RateLimitStatus := RateLimit.Get('status', '');
      End
    Else If EventType = 'result' Then
      ReadResult(Event, State);
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function ClaudeTurnOutcome(Const State: TClaudeStreamState; ExitCode: Integer; Const ErrorOutput: String;
  Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If State.Finished And (Not State.IsError) Then
    Exit(True);
  If State.Finished Then
    Begin
      { The wording 'quota' lets recovery wait for the subscription window to reset. }
      If (State.RateLimitStatus <> '') And (State.RateLimitStatus <> 'allowed') Then
        ErrorText := 'Claude subscription quota reached. ' + BoundText(State.ErrorText + ' ' + State.Turn.Text)
      Else If State.ResultSubtype = 'error_max_turns' Then
        ErrorText := 'Claude Code stopped at its turn limit.'
      Else If State.ErrorText <> '' Then
        ErrorText := BoundText(State.ErrorText)
      Else If State.Turn.Text <> '' Then
        ErrorText := BoundText(State.Turn.Text)
      Else
        ErrorText := 'Claude Code did not complete the turn.';
      ErrorText := Trim(ErrorText);
      Exit;
    End;
  { No result event: the program stopped before it could report one. Only stderr says why. }
  If (ExitCode <> 0) And PermissionFlagRefused(ErrorOutput) Then
    ErrorText := 'Claude Code refused the permission mode flag. ' + BoundText(ErrorOutput)
  Else If Trim(ErrorOutput) <> '' Then
    ErrorText := BoundText(ErrorOutput)
  Else
    ErrorText := 'Claude Code did not complete the turn.';
End;

Function ClaudeModelsFromControlResponse(Const OutputText, RequestId: String; Out ModelsJson: String): Boolean;
Var
  Lines: TStringList;
  Data: TJSONData;
  Reply, Body: TJSONObject;
  I: Integer;
Begin
  Result := False;
  ModelsJson := '';
  Lines := TStringList.Create;
  Try
    Lines.Text := OutputText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        If Pos('"control_response"', Lines[I]) = 0 Then
          Continue;
        Data := Nil;
        Try
          Try
            Data := GetJSON(Lines[I]);
          Except
            On EParserError Do
              Continue;
          End;
          If Not (Data Is TJSONObject) Or Not (TJSONObject(Data).Find('response') Is TJSONObject) Then
            Continue;
          Reply := TJSONObject(TJSONObject(Data).Find('response'));
          If (Reply.Get('request_id', '') <> RequestId) Or (Reply.Get('subtype', '') <> 'success') Or
            Not (Reply.Find('response') Is TJSONObject) Then
            Continue;
          { The same response carries account details. Only the model list is copied out. }
          Body := TJSONObject(Reply.Find('response'));
          If Body.Find('models') Is TJSONArray Then
            Begin
              ModelsJson := Body.Find('models').AsJSON;
              Exit(True);
            End;
        Finally
          Data.Free;
        End;
      End;
  Finally
    Lines.Free;
  End;
End;

{ The model objects, or Nil for text that is not a list. The caller frees the result. }
Function ParseModels(Const ModelsJson: String): TJSONArray;
Var
  Data: TJSONData;
Begin
  Result := Nil;
  If Trim(ModelsJson) = '' Then
    Exit;
  Try
    Data := GetJSON(ModelsJson);
  Except
    On EParserError Do
      Exit;
  End;
  If Data Is TJSONArray Then
    Result := TJSONArray(Data)
  Else
    Data.Free;
End;

Function FindModel(Models: TJSONArray; Const Value: String): TJSONObject;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not Assigned(Models) Then
    Exit;
  For I := 0 To Models.Count - 1 Do
    If (Models.Items[I] Is TJSONObject) And (TJSONObject(Models.Items[I]).Get('value', '') = Value) Then
      Exit(TJSONObject(Models.Items[I]));
End;

Procedure CollectClaudeModels(Const ModelsJson: String; Values: TStrings);
Var
  Models: TJSONArray;
  Value: String;
  I: Integer;
Begin
  If Not Assigned(Values) Then
    Exit;
  Values.Clear;
  Models := ParseModels(ModelsJson);
  Try
    If Assigned(Models) Then
      For I := 0 To Models.Count - 1 Do
        If Models.Items[I] Is TJSONObject Then
          Begin
            Value := Trim(TJSONObject(Models.Items[I]).Get('value', ''));
            If (Value <> '') And (Values.IndexOf(Value) < 0) Then
              Values.Add(Value);
          End;
  Finally
    Models.Free;
  End;
  If Values.Count > 0 Then
    Exit;
  For I := Low(ClaudeModelAliases) To High(ClaudeModelAliases) Do
    Values.Add(ClaudeModelAliases[I]);
End;

Function ClaudeModelDescription(Const ModelsJson, Value: String): String;
Var
  Models: TJSONArray;
  Model: TJSONObject;
Begin
  Result := '';
  Models := ParseModels(ModelsJson);
  Try
    Model := FindModel(Models, Value);
    If Not Assigned(Model) Then
      Exit;
    Result := Model.Get('displayName', '');
    If Model.Get('description', '') <> '' Then
      Begin
        If Result <> '' Then
          Result := Result + ' — ';
        Result := Result + Model.Get('description', '');
      End;
  Finally
    Models.Free;
  End;
End;

Function CollectClaudeEffortLevels(Const ModelsJson, Value: String; Levels: TStrings): Boolean;
Var
  Models, Supported: TJSONArray;
  Model: TJSONObject;
  I: Integer;
Begin
  Result := False;
  If Not Assigned(Levels) Then
    Exit;
  Levels.Clear;
  Models := ParseModels(ModelsJson);
  Try
    Model := FindModel(Models, Value);
    If (Not Assigned(Model)) Or (Not (Model.Find('supportedEffortLevels') Is TJSONArray)) Then
      Exit;
    Supported := TJSONArray(Model.Find('supportedEffortLevels'));
    For I := 0 To Supported.Count - 1 Do
      If Supported.Items[I] Is TJSONString Then
        Levels.Add(Supported.Items[I].AsString);
    Result := Levels.Count > 0;
  Finally
    Models.Free;
  End;
End;

Function ParseClaudeTurnResult(Const JsonText: String; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Var
  State: TClaudeStreamState;
Begin
  ClearClaudeStream(State);
  ClearTurn(Turn);
  If Not ApplyClaudeStreamLine(JsonObjectText(JsonText), State) Then
    Begin
      ErrorText := ClaudeNoJsonText;
      Exit(False);
    End;
  Result := State.Finished And ClaudeTurnOutcome(State, 0, '', ErrorText);
  If Result Then
    Turn := State.Turn
  Else If ErrorText = '' Then
    ErrorText := ClaudeNoJsonText;
End;

End.
