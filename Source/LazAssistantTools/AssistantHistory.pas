Unit AssistantHistory;

{ Project-local .assistant history: JSONL turns + sidecar index (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Type
  TAssistantMode = (amChat, amPlan, amCode);

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
  End;

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
    FLastError: String;
    Function AssistantDir: String;
    Function HistoryPath: String;
    Function IndexPath: String;
    Function ConfigPath: String;
    Function EnsureDir: Boolean;
    Procedure ClearIndex;
    Function ParseIndexLine(Const Line: String; Out Entry: THistoryIndexEntry): Boolean;
    Function ParseTurnLine(Const Line: String; Out Turn: THistoryTurn): Boolean;
    Function BuildTurnJson(Const Turn: THistoryTurn): String;
    Function BuildIndexLine(Const Entry: THistoryIndexEntry): String;
    Function PreviewOf(Const TextValue: String; MaxLen: Integer): String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetProjectRoot(Const RootPath: String);
    Function LoadIndex: Boolean;
    Function RebuildIndexFromHistory: Boolean;
    Function AppendTurn(Const Turn: THistoryTurn; Out Entry: THistoryIndexEntry): Boolean;
    Function LoadTurnByOffset(FileOffset: Int64; Out Turn: THistoryTurn): Boolean;
    Function LoadTurnById(Const TurnId: String; Out Turn: THistoryTurn): Boolean;
    Function IndexCount: Integer;
    Function IndexEntry(Index: Integer): THistoryIndexEntry;
    Function SaveShowThinking(ShowThinking: Boolean): Boolean;
    Function LoadShowThinking(Out ShowThinking: Boolean): Boolean;
    Property ProjectRoot: String Read FProjectRoot;
    Property LastError: String Read FLastError;
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
  { Compact unique-enough id without external UUID units. }
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
  { Prefer repository/project root, not a nested Source/ (or src/) folder. }
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
  { Prefer .lpi directory, then main file directory; then lift out of Source/. }
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
  FIndex := TObjectList.Create(True);
End;

Destructor TAssistantHistoryStore.Destroy;
Begin
  FreeAndNil(FIndex);
  Inherited Destroy;
End;

Procedure TAssistantHistoryStore.SetProjectRoot(Const RootPath: String);
Begin
  FProjectRoot := IncludeTrailingPathDelimiter(ExpandFileName(RootPath));
  ClearIndex;
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
          { non-fatal }
        End;
      Finally
        SL.Free;
      End;
    End;
  Result := True;
End;

Procedure TAssistantHistoryStore.ClearIndex;
Begin
  FIndex.Clear;
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

Function TAssistantHistoryStore.BuildIndexLine(Const Entry: THistoryIndexEntry): String;
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
    '"file_offset":' + IntToStr(Entry.FileOffset) +
    '}';
End;

Function TAssistantHistoryStore.ParseIndexLine(Const Line: String; Out Entry: THistoryIndexEntry): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Entry := Nil;
  If Trim(Line) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Line);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Entry := THistoryIndexEntry.Create;
      Entry.Id := Obj.Get('id', '');
      Entry.Mode := Obj.Get('mode', 'chat');
      Entry.CreatedAt := Obj.Get('created_at', '');
      Entry.DurationMs := Obj.Get('duration_ms', 0);
      Entry.PromptPreview := Obj.Get('prompt_preview', '');
      Entry.ResponsePreview := Obj.Get('response_preview', '');
      Entry.HasThinking := Obj.Get('has_thinking', False);
      Entry.ErrorText := Obj.Get('error', '');
      Entry.FileOffset := Obj.Get('file_offset', Int64(0));
      Result := Entry.Id <> '';
      If Not Result Then
        FreeAndNil(Entry);
    Except
      FreeAndNil(Entry);
      Result := False;
    End;
  Finally
    Data.Free;
  End;
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

Function TAssistantHistoryStore.LoadIndex: Boolean;
Var
  SL: TStringList;
  I: Integer;
  Entry: THistoryIndexEntry;
Begin
  Result := False;
  FLastError := '';
  ClearIndex;
  If FProjectRoot = '' Then
    Exit;
  If Not FileExistsUTF8(IndexPath) Then
    Begin
      If FileExistsUTF8(HistoryPath) Then
        Result := RebuildIndexFromHistory
      Else
        Result := True;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(IndexPath);
      For I := 0 To SL.Count - 1 Do
        If ParseIndexLine(SL[I], Entry) Then
          FIndex.Add(Entry);
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          Result := RebuildIndexFromHistory;
        End;
    End;
  Finally
    SL.Free;
  End;
End;

Function TAssistantHistoryStore.RebuildIndexFromHistory: Boolean;
Var
  FS: TFileStream;
  IndexSL: TStringList;
  Line: String;
  Offset: Int64;
  Ch: Byte;
  Turn: THistoryTurn;
  Entry: THistoryIndexEntry;
  LineStart: Int64;
Begin
  Result := False;
  FLastError := '';
  ClearIndex;
  If Not EnsureDir Then
    Exit;
  If Not FileExistsUTF8(HistoryPath) Then
    Begin
      Result := True;
      Exit;
    End;
  IndexSL := TStringList.Create;
  FS := Nil;
  Try
    Try
      FS := TFileStream.Create(HistoryPath, fmOpenRead Or fmShareDenyNone);
      Offset := 0;
      LineStart := 0;
      Line := '';
      While Offset < FS.Size Do
        Begin
          FS.ReadBuffer(Ch, 1);
          Inc(Offset);
          If Ch = 10 Then
            Begin
              If (Line <> '') And (Line[Length(Line)] = #13) Then
                SetLength(Line, Length(Line) - 1);
              If ParseTurnLine(Line, Turn) Then
                Begin
                  Entry := THistoryIndexEntry.Create;
                  Entry.Id := Turn.Id;
                  Entry.Mode := Turn.Mode;
                  Entry.CreatedAt := Turn.CreatedAt;
                  Entry.DurationMs := Turn.DurationMs;
                  Entry.PromptPreview := PreviewOf(Turn.Prompt, PreviewMaxChars);
                  Entry.ResponsePreview := PreviewOf(Turn.Response, PreviewMaxChars);
                  Entry.HasThinking := Turn.Thinking <> '';
                  Entry.ErrorText := PreviewOf(Turn.ErrorText, 80);
                  Entry.FileOffset := LineStart;
                  FIndex.Add(Entry);
                  IndexSL.Add(BuildIndexLine(Entry));
                End;
              Line := '';
              LineStart := Offset;
            End
          Else
            Line := Line + Char(Ch);
        End;
      If Trim(Line) <> '' Then
        If ParseTurnLine(Line, Turn) Then
          Begin
            Entry := THistoryIndexEntry.Create;
            Entry.Id := Turn.Id;
            Entry.Mode := Turn.Mode;
            Entry.CreatedAt := Turn.CreatedAt;
            Entry.DurationMs := Turn.DurationMs;
            Entry.PromptPreview := PreviewOf(Turn.Prompt, PreviewMaxChars);
            Entry.ResponsePreview := PreviewOf(Turn.Response, PreviewMaxChars);
            Entry.HasThinking := Turn.Thinking <> '';
            Entry.ErrorText := PreviewOf(Turn.ErrorText, 80);
            Entry.FileOffset := LineStart;
            FIndex.Add(Entry);
            IndexSL.Add(BuildIndexLine(Entry));
          End;
      IndexSL.SaveToFile(IndexPath);
      Result := True;
      WorkflowLogger.Info('AssistantHistory', Format('Rebuilt index (%d turns) for %s',
        [FIndex.Count, FProjectRoot]));
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    FS.Free;
    IndexSL.Free;
  End;
End;

Function TAssistantHistoryStore.AppendTurn(Const Turn: THistoryTurn; Out Entry: THistoryIndexEntry): Boolean;
Var
  FS: TFileStream;
  Line, IndexLine: String;
  Offset: Int64;
Begin
  Result := False;
  Entry := Nil;
  FLastError := '';
  If Not EnsureDir Then
    Exit;
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
      Entry := THistoryIndexEntry.Create;
      Entry.Id := Turn.Id;
      Entry.Mode := Turn.Mode;
      Entry.CreatedAt := Turn.CreatedAt;
      Entry.DurationMs := Turn.DurationMs;
      Entry.PromptPreview := PreviewOf(Turn.Prompt, PreviewMaxChars);
      Entry.ResponsePreview := PreviewOf(Turn.Response, PreviewMaxChars);
      Entry.HasThinking := Turn.Thinking <> '';
      Entry.ErrorText := PreviewOf(Turn.ErrorText, 80);
      Entry.FileOffset := Offset;
      FIndex.Add(Entry);
      IndexLine := BuildIndexLine(Entry) + #10;
      FreeAndNil(FS);
      If FileExistsUTF8(IndexPath) Then
        FS := TFileStream.Create(IndexPath, fmOpenReadWrite Or fmShareDenyWrite)
      Else
        FS := TFileStream.Create(IndexPath, fmCreate);
      FS.Seek(0, soEnd);
      If Length(IndexLine) > 0 Then
        FS.WriteBuffer(IndexLine[1], Length(IndexLine));
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          If Assigned(Entry) And (FIndex.IndexOf(Entry) >= 0) Then
            FIndex.Remove(Entry)
          Else
            FreeAndNil(Entry);
        End;
    End;
  Finally
    FS.Free;
  End;
End;

Function TAssistantHistoryStore.LoadTurnByOffset(FileOffset: Int64; Out Turn: THistoryTurn): Boolean;
Var
  FS: TFileStream;
  Line: String;
  Ch: Byte;
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
  If Not FileExistsUTF8(HistoryPath) Then
    Begin
      FLastError := 'History file missing.';
      Exit;
    End;
  FS := TFileStream.Create(HistoryPath, fmOpenRead Or fmShareDenyNone);
  Try
    Try
      If FileOffset >= FS.Size Then
        Begin
          FLastError := 'Invalid history offset.';
          Exit;
        End;
      FS.Position := FileOffset;
      Line := '';
      While FS.Position < FS.Size Do
        Begin
          FS.ReadBuffer(Ch, 1);
          If Ch = 10 Then
            Break;
          If Ch <> 13 Then
            Line := Line + Char(Ch);
        End;
      Result := ParseTurnLine(Line, Turn);
      If Not Result Then
        FLastError := 'Could not parse history record.';
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    FS.Free;
  End;
End;

Function TAssistantHistoryStore.LoadTurnById(Const TurnId: String; Out Turn: THistoryTurn): Boolean;
Var
  I: Integer;
  E: THistoryIndexEntry;
Begin
  Result := False;
  For I := 0 To FIndex.Count - 1 Do
    Begin
      E := THistoryIndexEntry(FIndex[I]);
      If SameText(E.Id, TurnId) Then
        Begin
          Result := LoadTurnByOffset(E.FileOffset, Turn);
          Exit;
        End;
    End;
  FLastError := 'Turn not found: ' + TurnId;
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
