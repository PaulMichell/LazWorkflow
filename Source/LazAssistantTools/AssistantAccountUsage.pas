Unit AssistantAccountUsage;

{ Account allowance for the status footer. Not the per-turn usage log.

  grok stays unregistered: the desktop OAuth token is not a team billing
  credential, and xAI's balance routes need a team id this program does not store.
  claude stays unregistered: plan quota is an interactive screen, not a JSON
  result this program owns. A custom openai-compatible base stays unregistered:
  it has no standard balance route. A missing registration is unknown, not an
  error, and does not open a socket.

  OpenRouter and Codex response parsers are plain functions so a fixture can
  fill a snapshot without a socket or a process. Caption and hint never receive
  a key, token, Authorization header, or account email.

  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantConnections;

Type
  TAccountUsageSnapshot = Record
    Known: Boolean;
    ConnectionId: String;
    Caption: String;
    Hint: String;
    FetchedAt: TDateTime;
  End;

  { HTTP backends ignore RuntimePath and ProfileDir. Codex uses them so this unit does not reach into the form. }
  TAccountUsageQuery = Function(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
    Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;

Procedure ClearAccountUsageSnapshot(Out Snapshot: TAccountUsageSnapshot);
Procedure RegisterAccountUsageQuery(Const BackendId: String; Query: TAccountUsageQuery);
/// Does not append a turn-usage line and does not change the Settings usage sentence.
Function QueryAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Function AccountUsageApplies(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): Boolean;
Function AccountUsageCaption(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Function AccountUsageHint(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Function ParseOpenRouterAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Function ParseCodexAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;

Implementation

Uses
  DateUtils, fpjson, jsonparser;

Type
  TAccountUsageRegistration = Record
    BackendId: String;
    Query: TAccountUsageQuery;
  End;

  TUsageWindow = Record
    Present: Boolean;
    UsedPercent: Double;
    Minutes: Integer;
    ResetsAt: Int64;
    HasReset: Boolean;
  End;

Const
  { Secondary window joins the caption only while the whole line stays this short. }
  AccountUsageCaptionLimit = 32;

Var
  Registry: Array Of TAccountUsageRegistration;
  RegistryLock: TRTLCriticalSection;
  RegistryReady: Boolean;

Procedure ClearAccountUsageSnapshot(Out Snapshot: TAccountUsageSnapshot);
Begin
  Snapshot.Known := False;
  Snapshot.ConnectionId := '';
  Snapshot.Caption := '';
  Snapshot.Hint := '';
  Snapshot.FetchedAt := 0;
End;

Function FindQuery(Const BackendId: String): TAccountUsageQuery;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not RegistryReady Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].BackendId = BackendId Then
        Exit(Registry[I].Query);
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Procedure RegisterAccountUsageQuery(Const BackendId: String; Query: TAccountUsageQuery);
Var
  I, Count: Integer;
Begin
  If (BackendId = '') Or (Not Assigned(Query)) Or (Not RegistryReady) Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].BackendId = BackendId Then
        Begin
          Registry[I].Query := Query;
          Exit;
        End;
    Count := Length(Registry);
    SetLength(Registry, Count + 1);
    Registry[Count].BackendId := BackendId;
    Registry[Count].Query := Query;
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Function QueryAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  Query: TAccountUsageQuery;
Begin
  ClearAccountUsageSnapshot(Snapshot);
  ErrorText := '';
  Result := True;
  If Not Assigned(Connection) Or (Connection.Backend = '') Then
    Exit;
  Snapshot.ConnectionId := Connection.Id;
  Query := FindQuery(Connection.Backend);
  If Not Assigned(Query) Then
    Exit;
  Try
    Result := Query(Connection, RuntimePath, ProfileDir, Snapshot, ErrorText);
  Except
    On E: Exception Do
      Begin
        ClearAccountUsageSnapshot(Snapshot);
        Snapshot.ConnectionId := Connection.Id;
        ErrorText := 'Account usage query failed.';
        Result := False;
        Exit;
      End;
  End;
  If Snapshot.ConnectionId = '' Then
    Snapshot.ConnectionId := Connection.Id;
  If (Not Result) And (ErrorText = '') Then
    ErrorText := 'Account usage query failed.';
End;

Function AccountUsageApplies(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): Boolean;
Begin
  Result := Snapshot.Known And (Snapshot.Caption <> '') And (Snapshot.ConnectionId <> '') And
    (Snapshot.ConnectionId = ActiveConnectionId);
End;

Function AccountUsageCaption(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Begin
  If AccountUsageApplies(Snapshot, ActiveConnectionId) Then
    Result := Snapshot.Caption
  Else
    Result := '';
End;

Function AccountUsageHint(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Begin
  If AccountUsageApplies(Snapshot, ActiveConnectionId) Then
    Result := Snapshot.Hint
  Else
    Result := '';
End;

Function DotDecimal(Const Text: String): String;
Begin
  Result := StringReplace(Text, ',', '.', []);
End;

Function FormatCredits(Value: Double): String;
Var
  Text: String;
  DotAt: Integer;
Begin
  Text := DotDecimal(FormatFloat('0.00####', Value));
  DotAt := Pos('.', Text);
  While (DotAt > 0) And (Length(Text) > DotAt + 2) And (Text[Length(Text)] = '0') Do
    Delete(Text, Length(Text), 1);
  Result := 'Left $' + Text;
End;

Function FormatAmount(Value: Double): String;
Var
  Text: String;
  DotAt: Integer;
Begin
  Text := DotDecimal(FormatFloat('0.####', Value));
  DotAt := Pos('.', Text);
  If DotAt = Length(Text) Then
    Delete(Text, DotAt, 1);
  Result := Text;
End;

Function PercentText(Value: Double): String;
Begin
  If Abs(Value - Round(Value)) < 0.05 Then
    Result := IntToStr(Round(Value))
  Else
    Result := DotDecimal(FormatFloat('0.0', Value));
  Result := Result + '%';
End;

Function WindowTag(Minutes: Integer): String;
Begin
  If Minutes = 300 Then
    Result := '5h'
  Else If Minutes = 10080 Then
    Result := '7d'
  Else
    Result := IntToStr(Minutes) + 'm';
End;

Function SafeToken(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := '';
  If (Value = '') Or (Length(Value) > 32) Then
    Exit;
  For I := 1 To Length(Value) Do
    If Not (Value[I] In ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) Then
      Exit;
  Result := Value;
End;

Function JsonObject(Data: TJSONData): TJSONObject;
Begin
  If Data Is TJSONObject Then
    Result := TJSONObject(Data)
  Else
    Result := Nil;
End;

Function NumberValue(Node: TJSONData; Out Value: Double): Boolean;
Begin
  Result := Assigned(Node) And (Node.JSONType = jtNumber);
  If Result Then
    Value := Node.AsFloat
  Else
    Value := 0;
End;

Procedure NoteFetched(Var Snapshot: TAccountUsageSnapshot);
Begin
  Snapshot.FetchedAt := Now;
End;

Function OpenRouterHint(Payload: TJSONObject): String;
Var
  Daily: Double;
Begin
  Result := 'Fetched ' + FormatDateTime('yyyy-mm-dd hh:nn', Now);
  If NumberValue(Payload.Find('usage_daily'), Daily) Then
    Result := 'Daily ' + FormatAmount(Daily) + '. ' + Result;
End;

Function ParseOpenRouterAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Payload, FreeRequests: TJSONObject;
  LimitNode, RemainNode: TJSONData;
  Amount, Remaining: Double;
Begin
  Result := False;
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot.ConnectionId := ConnectionId;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'OpenRouter key usage was not JSON.';
          Exit;
        End;
    End;
    Root := JsonObject(Data);
    If Not Assigned(Root) Then
      Begin
        ErrorText := 'OpenRouter key usage was not an object.';
        Exit;
      End;
    Payload := JsonObject(Root.Find('data'));
    If Not Assigned(Payload) Then
      Begin
        ErrorText := 'OpenRouter key usage had no data object.';
        Exit;
      End;
    LimitNode := Payload.Find('limit_remaining');
    If NumberValue(LimitNode, Amount) Then
      Begin
        Snapshot.Known := True;
        Snapshot.Caption := FormatCredits(Amount);
        Snapshot.Hint := OpenRouterHint(Payload);
        NoteFetched(Snapshot);
        Result := True;
        Exit;
      End;
    If Assigned(LimitNode) And (LimitNode.JSONType = jtNull) Then
      Begin
        FreeRequests := JsonObject(Payload.Find('free_model_daily_requests'));
        RemainNode := Nil;
        If Assigned(FreeRequests) Then
          RemainNode := FreeRequests.Find('remaining');
        If NumberValue(RemainNode, Remaining) Then
          Begin
            Snapshot.Known := True;
            Snapshot.Caption := Format('Free %d left', [Round(Remaining)]);
            Snapshot.Hint := OpenRouterHint(Payload);
            NoteFetched(Snapshot);
            Result := True;
            Exit;
          End;
        { Explicit null limit and no free-request counter: unlimited, nothing to show. }
        NoteFetched(Snapshot);
        Result := True;
        Exit;
      End;
    ErrorText := 'OpenRouter key usage did not include a balance.';
  Finally
    Data.Free;
  End;
End;

Function ResetText(ResetsAt: Int64): String;
Begin
  If ResetsAt <= 0 Then
    Result := ''
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(ResetsAt));
End;

Function ReadWindow(Node: TJSONData; Out Window: TUsageWindow; Out ErrorText: String): Boolean;
Var
  Obj: TJSONObject;
  Used: Double;
  Minutes: Double;
  ResetAt: Double;
Begin
  Result := False;
  ErrorText := '';
  Window.Present := False;
  Window.UsedPercent := 0;
  Window.Minutes := 0;
  Window.ResetsAt := 0;
  Window.HasReset := False;
  If (Node = Nil) Or (Node.JSONType = jtNull) Then
    Begin
      Result := True;
      Exit;
    End;
  Obj := JsonObject(Node);
  If Not Assigned(Obj) Then
    Begin
      ErrorText := 'Codex rate-limit window was not an object.';
      Exit;
    End;
  If Not NumberValue(Obj.Find('usedPercent'), Used) Then
    Begin
      ErrorText := 'Codex rate-limit window had no used percent.';
      Exit;
    End;
  If Not NumberValue(Obj.Find('windowDurationMins'), Minutes) Then
    Begin
      ErrorText := 'Codex rate-limit window had no duration.';
      Exit;
    End;
  If Minutes < 0 Then
    Begin
      ErrorText := 'Codex rate-limit window had no duration.';
      Exit;
    End;
  Window.Present := True;
  Window.UsedPercent := Used;
  Window.Minutes := Round(Minutes);
  If NumberValue(Obj.Find('resetsAt'), ResetAt) And (ResetAt > 0) Then
    Begin
      Window.ResetsAt := Round(ResetAt);
      Window.HasReset := Window.ResetsAt > 0;
    End;
  Result := True;
End;

Function WindowCaption(Const Window: TUsageWindow): String;
Begin
  Result := WindowTag(Window.Minutes) + ' ' + PercentText(Window.UsedPercent);
End;

Function WindowHint(Const Window: TUsageWindow): String;
Var
  When: String;
Begin
  Result := PercentText(Window.UsedPercent) + ' of the ' + WindowTag(Window.Minutes) + ' window used';
  When := ResetText(Window.ResetsAt);
  If When <> '' Then
    Result := Result + ', resets ' + When;
End;

Function SelectCodexLimits(Root: TJSONObject): TJSONObject;
Var
  Node: TJSONData;
  ById: TJSONObject;
Begin
  Result := Nil;
  If Not Assigned(Root) Then
    Exit;
  Node := Root.Find('result');
  If Node Is TJSONObject Then
    Root := TJSONObject(Node);
  Node := Root.Find('rateLimitsByLimitId');
  If Node Is TJSONObject Then
    Begin
      ById := TJSONObject(Node);
      If ById.Find('codex') Is TJSONObject Then
        Exit(TJSONObject(ById.Find('codex')));
    End;
  If Root.Find('rateLimits') Is TJSONObject Then
    Exit(TJSONObject(Root.Find('rateLimits')));
  If Root.Find('primary') Is TJSONObject Then
    Result := Root;
End;

Function LimitReachedName(Limits: TJSONObject; Out Name: String): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Name := '';
  If Not Assigned(Limits) Then
    Exit;
  Node := Limits.Find('rateLimitReachedType');
  If (Node = Nil) Or (Node.JSONType = jtNull) Then
    Exit;
  If Node.JSONType = jtString Then
    Begin
      Name := SafeToken(Node.AsString);
      Result := Name <> '';
    End
  Else If Node.JSONType = jtBoolean Then
    Result := Node.AsBoolean;
End;

Function ParseCodexAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Limits: TJSONObject;
  Primary, Secondary: TUsageWindow;
  Caption, Hint, ReachedName: String;
  Reached: Boolean;
Begin
  Result := False;
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot.ConnectionId := ConnectionId;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Codex rate limits were not JSON.';
          Exit;
        End;
    End;
    Limits := SelectCodexLimits(JsonObject(Data));
    If Not Assigned(Limits) Then
      Begin
        ErrorText := 'Codex rate limits were not in the result.';
        Exit;
      End;
    If Not ReadWindow(Limits.Find('primary'), Primary, ErrorText) Then
      Exit;
    If Not Primary.Present Then
      Begin
        ErrorText := 'Codex rate limits had no primary window.';
        Exit;
      End;
    If Not ReadWindow(Limits.Find('secondary'), Secondary, ErrorText) Then
      Exit;
    Caption := WindowCaption(Primary);
    Hint := WindowHint(Primary);
    If Secondary.Present Then
      Begin
        If Length(Caption + ' · ' + WindowCaption(Secondary)) <= AccountUsageCaptionLimit Then
          Caption := Caption + ' · ' + WindowCaption(Secondary);
        Hint := Hint + '. ' + WindowHint(Secondary);
      End;
    Reached := LimitReachedName(Limits, ReachedName);
    If Reached Then
      Begin
        Caption := 'Limit';
        If ReachedName <> '' Then
          Hint := 'Rate limit reached (' + ReachedName + '). ' + Hint
        Else
          Hint := 'Rate limit reached. ' + Hint;
      End;
    Snapshot.Known := True;
    Snapshot.Caption := Caption;
    Snapshot.Hint := Hint;
    NoteFetched(Snapshot);
    Result := True;
  Finally
    Data.Free;
  End;
End;

Initialization

InitCriticalSection(RegistryLock);
RegistryReady := True;

Finalization

RegistryReady := False;
DoneCriticalSection(RegistryLock);

End.
