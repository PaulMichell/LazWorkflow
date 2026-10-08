Unit AssistantUsage;

{ Appends one usage line per completed turn. Counts and cost are copied only
  when the provider sent them. A line never contains a key or a prompt body.
  Account allowance is not stored here. A quota query must not append a line,
  and a missing quota must not change UsageUnavailableText.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  UsageStateReported = 'reported';
  UsageStateUnavailable = 'unavailable';
  UsageUnavailableText = 'This connection did not report usage.';

Type
  TAssistantUsageRecord = Record
    TimeText: String;
    ConnectionId: String;
    Backend: String;
    Model: String;
    State: String;
    InputTokens: Integer;
    OutputTokens: Integer;
    HasReasoning: Boolean;
    ReasoningTokens: Integer;
    HasCost: Boolean;
    Cost: Double;
    Currency: String;
  End;

Function UsageFilePath(Const ProjectRoot: String): String;
Function AppendUsageRecord(Const ProjectRoot: String; Const Item: TAssistantUsageRecord;
  Out ErrorText: String): Boolean;
Function LatestUsageRecord(Const ProjectRoot, ConnectionId: String; Out Item: TAssistantUsageRecord): Boolean;
Function UsageDetailText(Found: Boolean; Const Item: TAssistantUsageRecord): String;
Function ReportedUsageRecord(Const ConnectionId, Backend, Model: String; InputTokens, OutputTokens: Integer;
  HasReasoning: Boolean; ReasoningTokens: Integer; HasCost: Boolean; Cost: Double;
  Const Currency: String): TAssistantUsageRecord;
Function UnavailableUsageRecord(Const ConnectionId, Backend, Model: String): TAssistantUsageRecord;

Implementation

Uses
  Classes, fpjson, jsonparser, LazFileUtils;

Function UsageFilePath(Const ProjectRoot: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(ProjectRoot) + '.assistant' + PathDelim + 'usage.jsonl';
End;

Procedure ClearUsageRecord(Out Item: TAssistantUsageRecord);
Begin
  Item.TimeText := '';
  Item.ConnectionId := '';
  Item.Backend := '';
  Item.Model := '';
  Item.State := '';
  Item.InputTokens := 0;
  Item.OutputTokens := 0;
  Item.HasReasoning := False;
  Item.ReasoningTokens := 0;
  Item.HasCost := False;
  Item.Cost := 0;
  Item.Currency := '';
End;

Function ReportedUsageRecord(Const ConnectionId, Backend, Model: String; InputTokens, OutputTokens: Integer;
  HasReasoning: Boolean; ReasoningTokens: Integer; HasCost: Boolean; Cost: Double;
  Const Currency: String): TAssistantUsageRecord;
Begin
  ClearUsageRecord(Result);
  Result.ConnectionId := ConnectionId;
  Result.Backend := Backend;
  Result.Model := Model;
  Result.State := UsageStateReported;
  Result.InputTokens := InputTokens;
  Result.OutputTokens := OutputTokens;
  Result.HasReasoning := HasReasoning;
  Result.ReasoningTokens := ReasoningTokens;
  Result.HasCost := HasCost;
  Result.Cost := Cost;
  Result.Currency := Currency;
End;

Function UnavailableUsageRecord(Const ConnectionId, Backend, Model: String): TAssistantUsageRecord;
Begin
  ClearUsageRecord(Result);
  Result.ConnectionId := ConnectionId;
  Result.Backend := Backend;
  Result.Model := Model;
  Result.State := UsageStateUnavailable;
End;

Function UsageLine(Const Item: TAssistantUsageRecord): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Try
    Obj.Add('time', Item.TimeText);
    Obj.Add('connection_id', Item.ConnectionId);
    Obj.Add('backend', Item.Backend);
    Obj.Add('model', Item.Model);
    Obj.Add('state', Item.State);
    If Item.State = UsageStateReported Then
      Begin
        Obj.Add('input_tokens', Item.InputTokens);
        Obj.Add('output_tokens', Item.OutputTokens);
        If Item.HasReasoning Then
          Obj.Add('reasoning_tokens', Item.ReasoningTokens);
        If Item.HasCost Then
          Obj.Add('cost', Item.Cost);
        If Item.Currency <> '' Then
          Obj.Add('currency', Item.Currency);
      End;
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function AppendUsageRecord(Const ProjectRoot: String; Const Item: TAssistantUsageRecord;
  Out ErrorText: String): Boolean;
Var
  Stored: TAssistantUsageRecord;
  Path, Dir, Line: String;
  Stream: TFileStream;
Begin
  Result := False;
  ErrorText := '';
  If Trim(ProjectRoot) = '' Then
    Begin
      ErrorText := 'No project root for the usage file.';
      Exit;
    End;
  If (Item.State <> UsageStateReported) And (Item.State <> UsageStateUnavailable) Then
    Begin
      ErrorText := 'Usage state must be reported or unavailable.';
      Exit;
    End;
  Stored := Item;
  If Stored.TimeText = '' Then
    Stored.TimeText := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now);
  Path := UsageFilePath(ProjectRoot);
  Dir := ExtractFilePath(Path);
  If (Dir <> '') And (Not DirectoryExistsUTF8(Dir)) Then
    ForceDirectoriesUTF8(Dir);
  Line := UsageLine(Stored) + LineEnding;
  If FileExistsUTF8(Path) Then
    Stream := TFileStream.Create(Path, fmOpenReadWrite Or fmShareDenyWrite)
  Else
    Stream := TFileStream.Create(Path, fmCreate);
  Try
    Stream.Seek(0, soEnd);
    If Line <> '' Then
      Stream.WriteBuffer(Line[1], Length(Line));
    Result := True;
  Finally
    Stream.Free;
  End;
End;

Function RecordFromJson(Const Line: String; Out Item: TAssistantUsageRecord): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  CostNode: TJSONData;
Begin
  Result := False;
  ClearUsageRecord(Item);
  Data := Nil;
  Try
    Data := GetJSON(Line);
    If Not (Data Is TJSONObject) Then
      Exit;
    Obj := TJSONObject(Data);
    Item.TimeText := Obj.Get('time', '');
    Item.ConnectionId := Obj.Get('connection_id', '');
    Item.Backend := Obj.Get('backend', '');
    Item.Model := Obj.Get('model', '');
    Item.State := Obj.Get('state', '');
    If Item.State = '' Then
      Exit;
    If Obj.Find('input_tokens') <> Nil Then
      Item.InputTokens := Obj.Get('input_tokens', 0);
    If Obj.Find('output_tokens') <> Nil Then
      Item.OutputTokens := Obj.Get('output_tokens', 0);
    If Obj.Find('reasoning_tokens') <> Nil Then
      Begin
        Item.HasReasoning := True;
        Item.ReasoningTokens := Obj.Get('reasoning_tokens', 0);
      End;
    CostNode := Obj.Find('cost');
    If Assigned(CostNode) And (CostNode.JSONType = jtNumber) Then
      Begin
        Item.HasCost := True;
        Item.Cost := CostNode.AsFloat;
      End;
    Item.Currency := Obj.Get('currency', '');
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function LatestUsageRecord(Const ProjectRoot, ConnectionId: String; Out Item: TAssistantUsageRecord): Boolean;
Var
  Path: String;
  Lines: TStringList;
  I: Integer;
  Parsed: TAssistantUsageRecord;
Begin
  Result := False;
  ClearUsageRecord(Item);
  If (Trim(ProjectRoot) = '') Or (Trim(ConnectionId) = '') Then
    Exit;
  Path := UsageFilePath(ProjectRoot);
  If Not FileExistsUTF8(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    For I := 0 To Lines.Count - 1 Do
      If RecordFromJson(Lines[I], Parsed) And (Parsed.ConnectionId = ConnectionId) Then
        Begin
          Item := Parsed;
          Result := True;
        End;
  Finally
    Lines.Free;
  End;
End;

Function FormatCost(Value: Double): String;
Var
  Text: String;
Begin
  Text := FormatFloat('0.########', Value);
  Result := StringReplace(Text, ',', '.', []);
End;

Function UsageDetailText(Found: Boolean; Const Item: TAssistantUsageRecord): String;
Begin
  If (Not Found) Or (Item.State <> UsageStateReported) Then
    Begin
      Result := UsageUnavailableText;
      Exit;
    End;
  Result := Format('%d in, %d out', [Item.InputTokens, Item.OutputTokens]);
  If Item.HasReasoning Then
    Result := Result + Format(', %d reasoning', [Item.ReasoningTokens]);
  If Item.HasCost Then
    Begin
      Result := Result + ', cost ' + FormatCost(Item.Cost);
      If Item.Currency <> '' Then
        Result := Result + ' ' + Item.Currency;
    End;
End;

End.
