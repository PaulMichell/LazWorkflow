Unit AssistantHistory;

{ Project-local .assistant history: JSONL on disk, full turns cached in memory (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Type
  TAssistantMode = (amChat, amPlan, amCode);

  { Lightweight row for the history list (also lives in FIndex). }
  THistoryIndexEntry = Class
  Public
    Id: String;
    Mode: String;
    CreatedAt: String;
    DurationMs: Integer;
    PromptPreview: String;
    ResponsePreview: String;
    HasThinking: Boolean;
    ErrorText: String;
    FileOffset: Int64;
    TurnIndex: Integer; { index into the in-memory FTurns array }
  End;

  { Display payload for a turn — only these fields are needed when stepping history. }
  THistoryTurn = Record
    Id: String;
    Mode: String;
    Prompt: String;
    Thinking: String;
    Response: String;
    CreatedAt: String;
    StartedAt: String;
    FinishedAt: String;
    DurationMs: Integer;
    Model: String;
    Skill: String;
    TokenEstimate: Integer;
    ErrorText: String;
    PlanFile: String;
    TodoId: String;
  End;

  TAssistantHistoryStore = Class
  Private
    FProjectRoot: String;
    FIndex: TObjectList; { of THistoryIndexEntry }
    FTurns: Array Of THistoryTurn; { full prompt/thinking/response cache }
    FLastError: String;
    FLoaded: Boolean;
    Function AssistantDir: String;
    Function HistoryPath: String;
    Function IndexPath: String;
    Function ConfigPath: String;
    Function EnsureDir: Boolean;
    Procedure ClearAll;
    Function ParseTurnLine(Const Line: String; Out Turn: THistoryTurn): Boolean;
    Function BuildTurnJson(Const Turn: THistoryTurn): String;
    Function BuildIndexLine(Const Entry: THistoryIndexEntry; TurnIndex: Integer): String;
    Function PreviewOf(Const TextValue: String; MaxLen: Integer): String;
    Function EntryFromTurn(Const Turn: THistoryTurn; FileOffset: Int64; TurnIndex: Integer): THistoryIndexEntry;
    Function LoadHistoryFileIntoMemory: Boolean;
    Procedure RewriteIndexFile;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetProjectRoot(Const RootPath: String);
    { Load index + full turns into memory once (disk I/O only here / on append). }
    Function Load: Boolean;
    Function AppendTurn(Const Turn: THistoryTurn; Out Entry: THistoryIndexEntry): Boolean;
    { O(1) memory access — no disk, no JSON parse. }
    Function GetTurn(TurnIndex: Integer; Out Turn: THistoryTurn): Boolean;
    Function GetTurnDisplay(TurnIndex: Integer; Out Prompt, Response, Thinking, ErrorText: String): Boolean;
    Function TurnCount: Integer;
    Function IndexCount: Integer;
    Function IndexEntry(Index: Integer): THistoryIndexEntry;
    Function SaveShowThinking(ShowThinking: Boolean): Boolean;
    Function LoadShowThinking(Out ShowThinking: Boolean): Boolean;
    Property ProjectRoot: String Read FProjectRoot;
    Property LastError: String Read FLastError;
    Property Loaded: Boolean Read FLoaded;
  End;

Function AssistantModeToStr(Mode: TAssistantMode): String;
Function StrToAssistantMode(Const S: String): TAssistantMode;
Function NewHistoryTurnId: String;
Function IsoNowUtc: String;
Function ProjectAssistantRoot: String;

Var
  ProjectAssistantHistory: TAssistantHistoryStore;

Implementation

Uses
  LazFileUtils, LazIDEIntf, ProjectIntf, WorkflowLog, DateUtils, fpjson, jsonparser;

Const
  PreviewMaxChars = 160;
  AssistantDirName = '.assistant';
  HistoryFileName = 'history.jsonl';
  IndexFileName = 'history.index.jsonl';
  ConfigFileName = 'config.json';

Function JsonEscape(Const S: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(S) Do
    Begin
      C := S[I];
      Case C Of
        '"': Result := Result + '\"';
        '\': Result := Result + '\\';
        #8: Result := Result + '\b';
        #9: Result := Result + '\t';
        #10: Result := Result + '\n';
        #12: Result := Result + '\f';
        #13: Result := Result + '\r';
      Else
        If Ord(C) < 32 Then
          Result := Result + '\u' + IntToHex(Ord(C), 4)
        Else
          Result := Result + C;
      End;
    End;
End;

Function AssistantModeToStr(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amPlan: Result := 'plan';
    amCode: Result := 'code';
  Else
    Result := 'chat';
  End;
End;

Function StrToAssistantMode(Const S: String): TAssistantMode;
Var
  T: String;
Begin
  T := LowerCase(Trim(S));
  If T = 'plan' Then
    Result := amPlan
  Else If T = 'code' Then
    Result := amCode
  Else
    Result := amChat;
End;

Function NewHistoryTurnId: String;
Begin
  Result := FormatDateTime('yyyymmdd"T"hhnnsszzz', Now) + '-' +
    IntToHex(Random($FFFF), 4) + IntToHex(Random($FFFF), 4);
End;

Function IsoNowUtc: String;
Begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', LocalTimeToUniversal(Now)) + 'Z';
End;

Function NormalizeAssistantProjectRoot(Const Dir: String): String;
Var
  Base, ParentDir: String;
Begin
  Result := IncludeTrailingPathDelimiter(ExpandFileName(Dir));
  Base := ExtractFileName(ExcludeTrailingPathDelimiter(Result));
  If SameText(Base, 'Source') Or SameText(Base, 'src') Or SameText(Base, 'Units') Then
    Begin
      ParentDir := ExpandFileName(Result + '..');
      If (ParentDir <> '') And DirectoryExistsUTF8(ParentDir) Then
        Result := IncludeTrailingPathDelimiter(ParentDir);
    End;
End;

Function ProjectAssistantRoot: String;
Var
  Proj: TLazProject;
  Dir: String;
Begin
  Result := '';
  If Not Assigned(LazarusIDE) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  If Not Assigned(Proj) Then
    Exit;
  Dir := '';
  If Proj.ProjectInfoFile <> '' Then
    Dir := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  If Dir = '' Then
    If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
      Dir := ExtractFilePath(ExpandFileName(Proj.MainFile.Filename));
  If Dir = '' Then
    Exit;
  Result := NormalizeAssistantProjectRoot(Dir);
End;

Constructor TAssistantHistoryStore.Create;
Begin
  Inherited Create;
  FProjectRoot := '';
  FLastError := '';
  FLoaded := False;
  FIndex := TObjectList.Create(True);
  SetLength(FTurns, 0);
End;

Destructor TAssistantHistoryStore.Destroy;
Begin
  FreeAndNil(FIndex);
  SetLength(FTurns, 0);
  Inherited Destroy;
End;

Procedure TAssistantHistoryStore.SetProjectRoot(Const RootPath: String);
Begin
  FProjectRoot := IncludeTrailingPathDelimiter(ExpandFileName(RootPath));
  ClearAll;
  FLoaded := False;
End;

Function TAssistantHistoryStore.AssistantDir: String;
Begin
  If FProjectRoot = '' Then
    Result := ''
  Else
    Result := FProjectRoot + AssistantDirName + PathDelim;
End;

Function TAssistantHistoryStore.HistoryPath: String;
Begin
  Result := AssistantDir + HistoryFileName;
End;

Function TAssistantHistoryStore.IndexPath: String;
Begin
  Result := AssistantDir + IndexFileName;
End;

Function TAssistantHistoryStore.ConfigPath: String;
Begin
  Result := AssistantDir + ConfigFileName;
End;

Function TAssistantHistoryStore.EnsureDir: Boolean;
Var
  Dir, Readme: String;
  SL: TStringList;
Begin
  Result := False;
  FLastError := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root for assistant history.';
      Exit;
    End;
  Dir := ExcludeTrailingPathDelimiter(AssistantDir);
  If Not DirectoryExistsUTF8(Dir) Then
    If Not ForceDirectoriesUTF8(Dir) Then
      Begin
        FLastError := 'Could not create ' + Dir;
        Exit;
      End;
  Readme := AssistantDir + 'README.txt';
  If Not FileExistsUTF8(Readme) Then
    Begin
      SL := TStringList.Create;
      Try
        SL.Add('Managed by LazAssistantTools (Project Assistant).');
        SL.Add('Safe to exclude from version control.');
        Try
          SL.SaveToFile(Readme);
        Except
        End;
      Finally
        SL.Free;
      End;
    End;
  Result := True;
End;

Procedure TAssistantHistoryStore.ClearAll;
Begin
  FIndex.Clear;
  SetLength(FTurns, 0);
End;

Function TAssistantHistoryStore.PreviewOf(Const TextValue: String; MaxLen: Integer): String;
Var
  S: String;
Begin
  S := StringReplace(TextValue, #13#10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #13, ' ', [rfReplaceAll]);
  S := Trim(S);
  If Length(S) <= MaxLen Then
    Result := S
  Else
    Result := Copy(S, 1, MaxLen - 1) + '…';
End;

Function TAssistantHistoryStore.BuildTurnJson(Const Turn: THistoryTurn): String;
Begin
  Result := '{' +
    '"id":"' + JsonEscape(Turn.Id) + '",' +
    '"mode":"' + JsonEscape(Turn.Mode) + '",' +
    '"prompt":"' + JsonEscape(Turn.Prompt) + '",' +
    '"thinking":"' + JsonEscape(Turn.Thinking) + '",' +
    '"response":"' + JsonEscape(Turn.Response) + '",' +
    '"created_at":"' + JsonEscape(Turn.CreatedAt) + '",' +
    '"started_at":"' + JsonEscape(Turn.StartedAt) + '",' +
    '"finished_at":"' + JsonEscape(Turn.FinishedAt) + '",' +
    '"duration_ms":' + IntToStr(Turn.DurationMs) + ',' +
    '"model":"' + JsonEscape(Turn.Model) + '",' +
    '"skill":"' + JsonEscape(Turn.Skill) + '",' +
    '"token_estimate":' + IntToStr(Turn.TokenEstimate) + ',' +
    '"error":"' + JsonEscape(Turn.ErrorText) + '",' +
    '"plan_file":"' + JsonEscape(Turn.PlanFile) + '",' +
    '"todo_id":"' + JsonEscape(Turn.TodoId) + '"' +
    '}';
End;

Function TAssistantHistoryStore.BuildIndexLine(Const Entry: THistoryIndexEntry; TurnIndex: Integer): String;
Begin
  Result := '{' +
    '"id":"' + JsonEscape(Entry.Id) + '",' +
    '"mode":"' + JsonEscape(Entry.Mode) + '",' +
    '"created_at":"' + JsonEscape(Entry.CreatedAt) + '",' +
    '"duration_ms":' + IntToStr(Entry.DurationMs) + ',' +
    '"prompt_preview":"' + JsonEscape(Entry.PromptPreview) + '",' +
    '"response_preview":"' + JsonEscape(Entry.ResponsePreview) + '",' +
    '"has_thinking":' + LowerCase(BoolToStr(Entry.HasThinking, True)) + ',' +
    '"error":"' + JsonEscape(Entry.ErrorText) + '",' +
    '"file_offset":' + IntToStr(Entry.FileOffset) + ',' +
    '"turn_index":' + IntToStr(TurnIndex) +
    '}';
End;

Function TAssistantHistoryStore.EntryFromTurn(Const Turn: THistoryTurn; FileOffset: Int64;
  TurnIndex: Integer): THistoryIndexEntry;
Begin
  Result := THistoryIndexEntry.Create;
  Result.Id := Turn.Id;
  Result.Mode := Turn.Mode;
  Result.CreatedAt := Turn.CreatedAt;
  Result.DurationMs := Turn.DurationMs;
  Result.PromptPreview := PreviewOf(Turn.Prompt, PreviewMaxChars);
  Result.ResponsePreview := PreviewOf(Turn.Response, PreviewMaxChars);
  Result.HasThinking := Turn.Thinking <> '';
  Result.ErrorText := PreviewOf(Turn.ErrorText, 80);
  Result.FileOffset := FileOffset;
  Result.TurnIndex := TurnIndex;
End;

Function TAssistantHistoryStore.ParseTurnLine(Const Line: String; Out Turn: THistoryTurn): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Turn.Id := '';
  Turn.Mode := 'chat';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.CreatedAt := '';
  Turn.StartedAt := '';
  Turn.FinishedAt := '';
  Turn.DurationMs := 0;
  Turn.Model := '';
  Turn.Skill := '';
  Turn.TokenEstimate := 0;
  Turn.ErrorText := '';
  Turn.PlanFile := '';
  Turn.TodoId := '';
  If Trim(Line) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Line);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      { Only fields needed for UI stepping + minimal metadata. }
      Turn.Id := Obj.Get('id', '');
      Turn.Mode := Obj.Get('mode', 'chat');
      Turn.Prompt := Obj.Get('prompt', '');
      Turn.Thinking := Obj.Get('thinking', '');
      Turn.Response := Obj.Get('response', '');
      Turn.CreatedAt := Obj.Get('created_at', '');
      Turn.StartedAt := Obj.Get('started_at', '');
      Turn.FinishedAt := Obj.Get('finished_at', '');
      Turn.DurationMs := Obj.Get('duration_ms', 0);
      Turn.Model := Obj.Get('model', '');
      Turn.Skill := Obj.Get('skill', '');
      Turn.TokenEstimate := Obj.Get('token_estimate', 0);
      Turn.ErrorText := Obj.Get('error', '');
      Turn.PlanFile := Obj.Get('plan_file', '');
      Turn.TodoId := Obj.Get('todo_id', '');
      Result := Turn.Id <> '';
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function TAssistantHistoryStore.LoadHistoryFileIntoMemory: Boolean;
Var
  SL: TStringList;
  I, N: Integer;
  Turn: THistoryTurn;
  Offset: Int64;
  Line: String;
  Entry: THistoryIndexEntry;
Begin
  Result := False;
  ClearAll;
  If Not FileExistsUTF8(HistoryPath) Then
    Begin
      Result := True;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      { One bulk read + line split — far faster than per-byte seek. }
      SL.LoadFromFile(HistoryPath);
      Offset := 0;
      N := 0;
      SetLength(FTurns, SL.Count); { upper bound; trim later }
      For I := 0 To SL.Count - 1 Do
        Begin
          Line := SL[I];
          If ParseTurnLine(Line, Turn) Then
            Begin
              FTurns[N] := Turn;
              Entry := EntryFromTurn(Turn, Offset, N);
              FIndex.Add(Entry);
              Inc(N);
            End;
          { Byte length of line + LF (TStringList drops terminators; file uses #10). }
          Inc(Offset, Length(Line) + 1);
        End;
      SetLength(FTurns, N);
      Result := True;
      WorkflowLogger.Info('AssistantHistory', Format('Cached %d turns in memory for %s',
        [N, FProjectRoot]));
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          ClearAll;
        End;
    End;
  Finally
    SL.Free;
  End;
End;

Procedure TAssistantHistoryStore.RewriteIndexFile;
Var
  SL: TStringList;
  I: Integer;
  Entry: THistoryIndexEntry;
Begin
  If Not EnsureDir Then
    Exit;
  SL := TStringList.Create;
  Try
    For I := 0 To FIndex.Count - 1 Do
      Begin
        Entry := THistoryIndexEntry(FIndex[I]);
        SL.Add(BuildIndexLine(Entry, Entry.TurnIndex));
      End;
    Try
      SL.SaveToFile(IndexPath);
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function TAssistantHistoryStore.Load: Boolean;
Begin
  Result := False;
  FLastError := '';
  FLoaded := False;
  If FProjectRoot = '' Then
    Exit;
  If Not EnsureDir Then
    Exit;
  Result := LoadHistoryFileIntoMemory;
  If Result Then
    Begin
      RewriteIndexFile;
      FLoaded := True;
    End;
End;

Function TAssistantHistoryStore.AppendTurn(Const Turn: THistoryTurn; Out Entry: THistoryIndexEntry): Boolean;
Var
  FS: TFileStream;
  Line: String;
  Offset: Int64;
  Idx: Integer;
Begin
  Result := False;
  Entry := Nil;
  FLastError := '';
  If Not EnsureDir Then
    Exit;
  If Not FLoaded Then
    Load;
  Line := BuildTurnJson(Turn) + #10;
  FS := Nil;
  Try
    Try
      If FileExistsUTF8(HistoryPath) Then
        FS := TFileStream.Create(HistoryPath, fmOpenReadWrite Or fmShareDenyWrite)
      Else
        FS := TFileStream.Create(HistoryPath, fmCreate);
      FS.Seek(0, soEnd);
      Offset := FS.Position;
      If Length(Line) > 0 Then
        FS.WriteBuffer(Line[1], Length(Line));
      Idx := Length(FTurns);
      SetLength(FTurns, Idx + 1);
      FTurns[Idx] := Turn;
      Entry := EntryFromTurn(Turn, Offset, Idx);
      FIndex.Add(Entry);
      { Append one index line (previews only) — list UI uses memory. }
      FreeAndNil(FS);
      Line := BuildIndexLine(Entry, Idx) + #10;
      If FileExistsUTF8(IndexPath) Then
        FS := TFileStream.Create(IndexPath, fmOpenReadWrite Or fmShareDenyWrite)
      Else
        FS := TFileStream.Create(IndexPath, fmCreate);
      FS.Seek(0, soEnd);
      If Length(Line) > 0 Then
        FS.WriteBuffer(Line[1], Length(Line));
      FLoaded := True;
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          If Assigned(Entry) And (FIndex.IndexOf(Entry) >= 0) Then
            Begin
              FIndex.Remove(Entry);
              Entry := Nil;
            End
          Else
            FreeAndNil(Entry);
          If Length(FTurns) > 0 Then
            SetLength(FTurns, Length(FTurns) - 1);
        End;
    End;
  Finally
    FS.Free;
  End;
End;

Function TAssistantHistoryStore.GetTurn(TurnIndex: Integer; Out Turn: THistoryTurn): Boolean;
Begin
  Result := False;
  Turn.Id := '';
  Turn.Mode := 'chat';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.CreatedAt := '';
  Turn.StartedAt := '';
  Turn.FinishedAt := '';
  Turn.DurationMs := 0;
  Turn.Model := '';
  Turn.Skill := '';
  Turn.TokenEstimate := 0;
  Turn.ErrorText := '';
  Turn.PlanFile := '';
  Turn.TodoId := '';
  If (TurnIndex < 0) Or (TurnIndex >= Length(FTurns)) Then
    Begin
      FLastError := 'Turn index out of range.';
      Exit;
    End;
  Turn := FTurns[TurnIndex];
  Result := True;
End;

Function TAssistantHistoryStore.GetTurnDisplay(TurnIndex: Integer;
  Out Prompt, Response, Thinking, ErrorText: String): Boolean;
Var
  Turn: THistoryTurn;
Begin
  Result := GetTurn(TurnIndex, Turn);
  If Not Result Then
    Begin
      Prompt := '';
      Response := '';
      Thinking := '';
      ErrorText := '';
      Exit;
    End;
  Prompt := Turn.Prompt;
  Response := Turn.Response;
  Thinking := Turn.Thinking;
  ErrorText := Turn.ErrorText;
End;

Function TAssistantHistoryStore.TurnCount: Integer;
Begin
  Result := Length(FTurns);
End;

Function TAssistantHistoryStore.IndexCount: Integer;
Begin
  Result := FIndex.Count;
End;

Function TAssistantHistoryStore.IndexEntry(Index: Integer): THistoryIndexEntry;
Begin
  If (Index < 0) Or (Index >= FIndex.Count) Then
    Result := Nil
  Else
    Result := THistoryIndexEntry(FIndex[Index]);
End;

Function TAssistantHistoryStore.SaveShowThinking(ShowThinking: Boolean): Boolean;
Var
  SL: TStringList;
Begin
  Result := False;
  If Not EnsureDir Then
    Exit;
  SL := TStringList.Create;
  Try
    SL.Add('{');
    SL.Add('  "show_thinking": ' + LowerCase(BoolToStr(ShowThinking, True)));
    SL.Add('}');
    Try
      SL.SaveToFile(ConfigPath);
      Result := True;
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    SL.Free;
  End;
End;

Function TAssistantHistoryStore.LoadShowThinking(Out ShowThinking: Boolean): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  SL: TStringList;
Begin
  Result := False;
  ShowThinking := True;
  If Not FileExistsUTF8(ConfigPath) Then
    Exit;
  SL := TStringList.Create;
  Data := Nil;
  Try
    Try
      SL.LoadFromFile(ConfigPath);
      Data := GetJSON(SL.Text);
      If Data Is TJSONObject Then
        Begin
          Obj := TJSONObject(Data);
          ShowThinking := Obj.Get('show_thinking', True);
          Result := True;
        End;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
    SL.Free;
  End;
End;

Initialization

Randomize;
ProjectAssistantHistory := TAssistantHistoryStore.Create;

Finalization

FreeAndNil(ProjectAssistantHistory);

End.
