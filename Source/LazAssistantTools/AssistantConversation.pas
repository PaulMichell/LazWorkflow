Unit AssistantConversation;

{ Project-local .assistant conversation turns: JSONL on disk, full turns cached in memory (c) 2026 Michell Computing.

  Each conversation has a GUID in conversation.identity.json, including a new unsaved one.
  Archiving renames that file with the jsonl. `current` is not an identity.
  The same file keeps the monitor log position (epoch and cursor) for that conversation.

  Size note: exceeds the 1000 line preference. The turn cache, shell config, and
  archive swap are one store. The identity sidecar is part of that swap.
  Reviewed 2026-10-29: no separate archive unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Type
  TAssistantMode = (amInspect, amDocument, amPlan, amBuild, amChat);

  { Lightweight row for the conversation turn list (also lives in FIndex). }
  TConversationIndexEntry = Class
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

  { One archived (or current) conversation for the History combobox. }
  TConversationHistoryItem = Class
  Public
    ArchiveId: String; { '' = current conversation.jsonl; else conversation-YYYYMMDD... stem }
    Title: String;
    CreatedAt: String;
    TurnCount: Integer;
    IsCurrent: Boolean;
  End;

  { Display payload for a turn — only these fields are needed when stepping the conversation list. }
  TConversationTurn = Record
    Id: String;
    Mode: String;
    Prompt: String;
    Thinking: String;
    Response: String;
    CreatedAt: String;
    StartedAt: String;
    FinishedAt: String;
    DurationMs: Integer;
    ThinkingMs: Integer;
    Model: String;
    Skill: String;
    TokenEstimate: Integer;
    ErrorText: String;
    PlanFile: String;
    TodoId: String;
    { JSON array of live trace cards; empty on turns saved before this field. }
    TraceJson: String;
    { Project-relative .assistant/events/*.jsonl for replay when TraceJson is empty. }
    EventsFile: String;
    { JSON array of this turn's model messages. Empty on older lines. }
    MessagesJson: String;
    { JSON array of image refs. Empty on older lines. No pixel bytes. }
    AttachmentsJson: String;
  End;

  TAssistantConversationStore = Class
  Private
    FProjectRoot, FTargetStoreKey, FMonitorId, FMonitorEpoch: String;
    FMonitorCursor: Int64;
    FIndex: TObjectList; { of TConversationIndexEntry }
    FTurns: Array Of TConversationTurn; { full prompt/thinking/response cache }
    FLastError: String;
    FLoaded: Boolean;
    Function AssistantDir: String;
    Function ConversationPath: String;
    Function IndexPath: String;
    Function ConfigPath: String;
    Function EnsureDir: Boolean;
    Procedure ClearAll;
    Function ParseTurnLine(Const Line: String; Out Turn: TConversationTurn): Boolean;
    Function BuildTurnJson(Const Turn: TConversationTurn): String;
    Function BuildIndexLine(Const Entry: TConversationIndexEntry; TurnIndex: Integer): String;
    Function PreviewOf(Const TextValue: String; MaxLen: Integer): String;
    Function EntryFromTurn(Const Turn: TConversationTurn; FileOffset: Int64; TurnIndex: Integer): TConversationIndexEntry;
    Function LoadConversationFileIntoMemory: Boolean;
    Procedure RewriteIndexFile;
    Function ArchivePathsForId(Const ArchiveId: String; Out ConvPath, IdxPath: String): Boolean;
    Function IdentityPath: String;
    Function ArchiveIdentityPath(Const ArchiveId: String): String;
    Function ReadIdentityAt(Const Path: String; Out Id, Epoch: String; Out Cursor: Int64): Boolean;
    Function WriteIdentityAt(Const Path, Id, Epoch: String; Cursor: Int64): Boolean;
    Function MoveIdentityFile(Const FromPath, ToPath: String): Boolean;
    Function TitleFromIndexFile(Const IdxFile: String): String;
    Procedure CollectConversationFiles(Files: TStrings);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetProjectRoot(Const RootPath: String; Const TargetStoreKey: String = '');
    { Load index + full turns into memory once (disk I/O only here / on append). }
    Function Load: Boolean;
    Function AppendTurn(Const Turn: TConversationTurn; Out Entry: TConversationIndexEntry): Boolean;
    { O(1) memory access — no disk, no JSON parse. }
    Function GetTurn(TurnIndex: Integer; Out Turn: TConversationTurn): Boolean;
    Function TurnCount: Integer;
    Function IndexCount: Integer;
    Function IndexEntry(Index: Integer): TConversationIndexEntry;
    { Project shell prefs in .assistant/config.json (mode, thinking, active plan, …). }
    Function LoadShellConfig(Out ShowThinking: Boolean; Out ActiveMode: TAssistantMode;
      Out PlanFile: String; ShowToolUse: PBoolean = Nil; DocumentFile: PString = Nil): Boolean;
    Function SaveShellConfig(ShowThinking: Boolean; ActiveMode: TAssistantMode;
      Const PlanFile: String; ShowToolUse: PBoolean = Nil; DocumentFile: PString = Nil): Boolean;
    { Writes only document_file. Other shell keys are left as they are. }
    Function SaveDocumentFile(Const RelativePath: String): Boolean;
    { Registered plan paths in available_plans. A missing key is an empty list. }
    Function LoadAvailablePlanPaths(Paths: TStrings): Boolean;
    Function SaveAvailablePlanPaths(Paths: TStrings): Boolean;
    { Multi-conversation: current files are conversation.jsonl + conversation.index.jsonl;
      archives are conversation-YYYYMMDDTHHMMSSMMM.jsonl (+ matching .index.jsonl). }
    Function HasTurns: Boolean;
    Function ArchiveCurrent(Out ArchiveId: String): Boolean;
    Function StartNewConversation: Boolean;
    Function ListHistory(Items: TObjectList): Boolean; { of TConversationHistoryItem; caller owns }
    Function ActivateArchive(Const ArchiveId: String): Boolean;
    Function DeleteConversation(Const ArchiveId: String): Boolean; { '' deletes current }
    Function HistoryTitleForCurrent: String;
    { Stable GUID for the open conversation. Never `current`. Minted and stored if missing. }
    Function OpenConversationId: String;
    { Same GUID as OpenConversationId. Writes the sidecar when the conversation has none. }
    Function MonitorConversationId: String;
    { Remembers this conversation's monitor log position. No write when nothing changed. }
    Procedure NoteMonitorLogPosition(Const Epoch: String; Cursor: Int64);
    Procedure ReadMonitorLogPosition(Out Epoch: String; Out Cursor: Int64);
    { Writes a closed conversation's position into its sidecar, open or archived. }
    Function SaveClosedLogPosition(Const ConversationId, Epoch: String; Cursor: Int64): Boolean;
    { History title, or the first prompt preview when that title is empty. }
    Function MonitorTitle: String;
    { Directory that contains conversation.jsonl, including a package target store. }
    Function AssistantDirectory: String;
    Property ProjectRoot: String Read FProjectRoot;
    Property TargetStoreKey: String Read FTargetStoreKey;
    Property LastError: String Read FLastError;
    Property Loaded: Boolean Read FLoaded;
  End;

Function AssistantModeToStr(Mode: TAssistantMode): String;
Function StrToAssistantMode(Const ModeText: String): TAssistantMode;
Function NewConversationTurnId: String;
Function NewMonitorConversationId: String;
Function MonitorConversationIdIsValid(Const ConversationId: String): Boolean;
Function IsoNowUtc: String;
Function ProjectAssistantRoot: String;
/// Test hook. The next generated archive id uses this value once, then the clock. Empty clears it.
Procedure SetNextArchiveIdForTest(Const ArchiveId: String);

Var
  ProjectAssistantConversation: TAssistantConversationStore;

Implementation

Uses
  LazFileUtils, DirectoryListing, LazIDEIntf, ProjectIntf, WorkflowLog, DateUtils, fpjson, jsonparser, AssistantProjectPaths,
  AssistantWorkTarget, AssistantImages, AssistantProtocol;

Const
  PreviewMaxChars = 160;
  ConversationFileName = AssistantConversationFileName;
  IndexFileName = 'conversation.index.jsonl';
  ConfigFileName = 'config.json';
  ConversationArchivePrefix = 'conversation-';
  ConversationArchiveSuffix = '.jsonl';
  ConversationArchiveIndexSuffix = '.index.jsonl';
  IdentityFileName = 'conversation.identity.json';
  IdentityArchiveSuffix = '.identity.json';

Var
  ForcedArchiveId: String;

Function AssistantModeToStr(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amChat: Result := 'chat';
    amInspect: Result := 'inspect';
    amDocument: Result := 'document';
    amPlan: Result := 'plan';
    amBuild: Result := 'build';
  Else
    Result := 'chat';
  End;
End;

Function StrToAssistantMode(Const ModeText: String): TAssistantMode;
Var
  T: String;
Begin
  T := LowerCase(Trim(ModeText));
  If T = 'chat' Then
    Result := amChat
  Else If T = 'inspect' Then
    Result := amInspect
  Else If (T = 'document') Or (T = 'doc') Or (T = 'report') Then
    Result := amDocument
  Else If T = 'plan' Then
    Result := amPlan
  Else If T = 'build' Then
    Result := amBuild
  Else
    Result := amInspect;
End;

Function NewConversationTurnId: String;
Begin
  Result := FormatDateTime('yyyymmdd"T"hhnnsszzz', Now) + '-' +
    IntToHex(Random($FFFF), 4) + IntToHex(Random($FFFF), 4);
End;

Function MonitorConversationIdIsValid(Const ConversationId: String): Boolean;
Var
  Index: Integer;
  C: Char;
Begin
  Result := Length(ConversationId) = 36;
  If Not Result Then
    Exit;
  For Index := 1 To 36 Do
    Begin
      C := ConversationId[Index];
      If (Index = 9) Or (Index = 14) Or (Index = 19) Or (Index = 24) Then
        Begin
          If C <> '-' Then
            Exit(False);
        End
      Else If Not (((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'f'))) Then
        Exit(False);
    End;
End;

Function NewMonitorConversationId: String;
Var
  Guid: TGuid;
Begin
  Result := '';
  If CreateGUID(Guid) <> 0 Then
    Exit;
  Result := LowerCase(Copy(GUIDToString(Guid), 2, 36));
  If Not MonitorConversationIdIsValid(Result) Then
    Result := '';
End;

Function IsoNowUtc: String;
Begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', LocalTimeToUniversal(Now)) + 'Z';
End;

Function ProjectAssistantRoot: String;
Begin
  Result := AssistantTarget.Root;
End;

Constructor TAssistantConversationStore.Create;
Begin
  Inherited Create;
  FProjectRoot := '';
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  FLastError := '';
  FLoaded := False;
  FIndex := TObjectList.Create(True);
  SetLength(FTurns, 0);
End;

Destructor TAssistantConversationStore.Destroy;
Begin
  FreeAndNil(FIndex);
  SetLength(FTurns, 0);
  Inherited Destroy;
End;

Procedure TAssistantConversationStore.SetProjectRoot(Const RootPath: String; Const TargetStoreKey: String);
Begin
  FTargetStoreKey := TargetStoreKey;
  If Trim(RootPath) = '' Then
    FProjectRoot := ''
  Else
    FProjectRoot := IncludeTrailingPathDelimiter(ExpandFileName(RootPath));
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  ClearAll;
  FLoaded := False;
End;

Function TAssistantConversationStore.AssistantDir: String;
Begin
  If FProjectRoot = '' Then
    Result := ''
  Else
    Begin
      Result := FProjectRoot + AssistantStoreFolderName + PathDelim;
      If FTargetStoreKey <> '' Then Result := Result + 'targets' + PathDelim + FTargetStoreKey + PathDelim;
    End;
End;

Function TAssistantConversationStore.AssistantDirectory: String;
Begin
  Result := AssistantDir;
End;

Procedure TAssistantConversationStore.CollectConversationFiles(Files: TStrings);
Var
  Rec: TDirectoryScan;
  Code: Integer;
Begin
  If Not Assigned(Files) Then Exit;
  If (ConversationPath <> '') And FileExistsUTF8(ConversationPath) And Not FileIsSymlink(ConversationPath) Then
    Files.Add(ConversationPath);
  If AssistantDir = '' Then Exit;
  Code := StartDirectoryScan(AssistantDir + ConversationArchivePrefix + '*' + ConversationArchiveSuffix, faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        If (Pos('.index.', LowerCase(Rec.Name)) = 0) And ((Rec.Attr And faDirectory) = 0) And
          (Not FileIsSymlink(AssistantDir + Rec.Name)) Then
          Files.Add(AssistantDir + Rec.Name);
        Code := AdvanceDirectoryScan(Rec);
      End;
  Finally
    CloseDirectoryScan(Rec);
  End;
End;

Function TAssistantConversationStore.ConversationPath: String;
Begin
  Result := AssistantDir + ConversationFileName;
End;

Function TAssistantConversationStore.IndexPath: String;
Begin
  Result := AssistantDir + IndexFileName;
End;

Function TAssistantConversationStore.ConfigPath: String;
Begin
  Result := AssistantDir + ConfigFileName;
End;

Function TAssistantConversationStore.EnsureDir: Boolean;
Var
  Dir: String;
Begin
  Result := False;
  FLastError := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root for assistant conversation store.';
      Exit;
    End;
  If Not DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(FProjectRoot)) Then
    Begin
      FLastError := 'Project root does not exist: ' + FProjectRoot;
      Exit;
    End;
  Dir := ExcludeTrailingPathDelimiter(AssistantDir);
  If Not DirectoryExistsUTF8(Dir) Then
    If Not ForceDirectoriesUTF8(Dir) Then
      Begin
        FLastError := 'Could not create ' + Dir;
        Exit;
      End;
  Result := True;
End;

Procedure TAssistantConversationStore.ClearAll;
Begin
  FIndex.Clear;
  SetLength(FTurns, 0);
End;

Function TAssistantConversationStore.PreviewOf(Const TextValue: String; MaxLen: Integer): String;
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

Function TAssistantConversationStore.BuildTurnJson(Const Turn: TConversationTurn): String;
Begin
  Result := '{' +
    '"id":"' + JsonEscapeText(Turn.Id) + '",' +
    '"mode":"' + JsonEscapeText(Turn.Mode) + '",' +
    '"prompt":"' + JsonEscapeText(Turn.Prompt) + '",' +
    '"thinking":"' + JsonEscapeText(Turn.Thinking) + '",' +
    '"response":"' + JsonEscapeText(Turn.Response) + '",' +
    '"created_at":"' + JsonEscapeText(Turn.CreatedAt) + '",' +
    '"started_at":"' + JsonEscapeText(Turn.StartedAt) + '",' +
    '"finished_at":"' + JsonEscapeText(Turn.FinishedAt) + '",' +
    '"duration_ms":' + IntToStr(Turn.DurationMs) + ',' +
    '"thinking_ms":' + IntToStr(Turn.ThinkingMs) + ',' +
    '"model":"' + JsonEscapeText(Turn.Model) + '",' +
    '"skill":"' + JsonEscapeText(Turn.Skill) + '",' +
    '"token_estimate":' + IntToStr(Turn.TokenEstimate) + ',' +
    '"error":"' + JsonEscapeText(Turn.ErrorText) + '",' +
    '"plan_file":"' + JsonEscapeText(Turn.PlanFile) + '",' +
    '"todo_id":"' + JsonEscapeText(Turn.TodoId) + '"';
  If Trim(Turn.EventsFile) <> '' Then
    Result := Result + ',"events_file":"' + JsonEscapeText(Turn.EventsFile) + '"';
  If (Trim(Turn.MessagesJson) <> '') And (Trim(Turn.MessagesJson)[1] = '[') Then
    Result := Result + ',"messages":' + Trim(Turn.MessagesJson);
  If Trim(Turn.TraceJson) <> '' Then
    Result := Result + ',"trace":' + Turn.TraceJson;
  If (Trim(Turn.AttachmentsJson) <> '') And (Trim(Turn.AttachmentsJson)[1] = '[') Then
    Result := Result + ',"attachments":' + Trim(Turn.AttachmentsJson);
  Result := Result + '}';
End;

Function TAssistantConversationStore.BuildIndexLine(Const Entry: TConversationIndexEntry; TurnIndex: Integer): String;
Begin
  Result := '{' +
    '"id":"' + JsonEscapeText(Entry.Id) + '",' +
    '"mode":"' + JsonEscapeText(Entry.Mode) + '",' +
    '"created_at":"' + JsonEscapeText(Entry.CreatedAt) + '",' +
    '"duration_ms":' + IntToStr(Entry.DurationMs) + ',' +
    '"prompt_preview":"' + JsonEscapeText(Entry.PromptPreview) + '",' +
    '"response_preview":"' + JsonEscapeText(Entry.ResponsePreview) + '",' +
    '"has_thinking":' + LowerCase(BoolToStr(Entry.HasThinking, True)) + ',' +
    '"error":"' + JsonEscapeText(Entry.ErrorText) + '",' +
    '"file_offset":' + IntToStr(Entry.FileOffset) + ',' +
    '"turn_index":' + IntToStr(TurnIndex) +
    '}';
End;

Function TAssistantConversationStore.EntryFromTurn(Const Turn: TConversationTurn; FileOffset: Int64;
  TurnIndex: Integer): TConversationIndexEntry;
Begin
  Result := TConversationIndexEntry.Create;
  Result.Id := Turn.Id;
  Result.Mode := Turn.Mode;
  Result.CreatedAt := Turn.CreatedAt;
  Result.DurationMs := Turn.DurationMs;
  If Trim(Turn.Prompt) <> '' Then
    Result.PromptPreview := PreviewOf(Turn.Prompt, PreviewMaxChars)
  Else
    Result.PromptPreview := PreviewOf(AssistantImageHistoryPreview(Turn.AttachmentsJson), PreviewMaxChars);
  Result.ResponsePreview := PreviewOf(Turn.Response, PreviewMaxChars);
  Result.HasThinking := Turn.Thinking <> '';
  Result.ErrorText := PreviewOf(Turn.ErrorText, 80);
  Result.FileOffset := FileOffset;
  Result.TurnIndex := TurnIndex;
End;

Function TAssistantConversationStore.ParseTurnLine(Const Line: String; Out Turn: TConversationTurn): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Turn.Id := '';
  Turn.Mode := 'inspect';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.CreatedAt := '';
  Turn.StartedAt := '';
  Turn.FinishedAt := '';
  Turn.DurationMs := 0;
  Turn.ThinkingMs := 0;
  Turn.Model := '';
  Turn.Skill := '';
  Turn.TokenEstimate := 0;
  Turn.ErrorText := '';
  Turn.PlanFile := '';
  Turn.TodoId := '';
  Turn.TraceJson := '';
  Turn.EventsFile := '';
  Turn.MessagesJson := '';
  Turn.AttachmentsJson := '';
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
      Turn.Mode := Obj.Get('mode', 'inspect');
      Turn.Prompt := Obj.Get('prompt', '');
      Turn.Thinking := Obj.Get('thinking', '');
      Turn.Response := Obj.Get('response', '');
      Turn.CreatedAt := Obj.Get('created_at', '');
      Turn.StartedAt := Obj.Get('started_at', '');
      Turn.FinishedAt := Obj.Get('finished_at', '');
      Turn.DurationMs := Obj.Get('duration_ms', 0);
      Turn.ThinkingMs := Obj.Get('thinking_ms', 0);
      Turn.Model := Obj.Get('model', '');
      Turn.Skill := Obj.Get('skill', '');
      Turn.TokenEstimate := Obj.Get('token_estimate', 0);
      Turn.ErrorText := Obj.Get('error', '');
      Turn.PlanFile := Obj.Get('plan_file', '');
      Turn.TodoId := Obj.Get('todo_id', '');
      Turn.EventsFile := Obj.Get('events_file', '');
      If Obj.Find('messages') Is TJSONArray Then
        Turn.MessagesJson := Obj.Find('messages').AsJSON;
      If Obj.Find('attachments') Is TJSONArray Then
        Turn.AttachmentsJson := Obj.Find('attachments').AsJSON;
      If Assigned(Obj.Find('trace')) Then
        Turn.TraceJson := Obj.Find('trace').AsJSON;
      Result := Turn.Id <> '';
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function TAssistantConversationStore.LoadConversationFileIntoMemory: Boolean;
Var
  SL: TStringList;
  I, N: Integer;
  Turn: TConversationTurn;
  Offset: Int64;
  Line: String;
  Entry: TConversationIndexEntry;
Begin
  Result := False;
  ClearAll;
  If Not FileExistsUTF8(ConversationPath) Then
    Begin
      Result := True;
      Exit;
    End;
  SL := TStringList.Create;
  Try
    Try
      { One bulk read + line split — far faster than per-byte seek. }
      SL.LoadFromFile(ConversationPath);
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
      WorkflowLogger.Info('AssistantConversation', Format('Cached %d turns in memory for %s',
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

Procedure TAssistantConversationStore.RewriteIndexFile;
Var
  SL: TStringList;
  I: Integer;
  Entry: TConversationIndexEntry;
Begin
  If Not EnsureDir Then
    Exit;
  SL := TStringList.Create;
  Try
    For I := 0 To FIndex.Count - 1 Do
      Begin
        Entry := TConversationIndexEntry(FIndex[I]);
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

Function TAssistantConversationStore.Load: Boolean;
Begin
  Result := False;
  FLastError := '';
  FLoaded := False;
  If FProjectRoot = '' Then
    Exit;
  If Not EnsureDir Then
    Exit;
  Result := LoadConversationFileIntoMemory;
  If Result Then
    Begin
      RewriteIndexFile;
      FLoaded := True;
    End;
End;

Function TAssistantConversationStore.AppendTurn(Const Turn: TConversationTurn; Out Entry: TConversationIndexEntry): Boolean;
Var
  ConvFS, IdxFS: TFileStream;
  ConvLine, IdxLine: String;
  ConvOffset: Int64;
  Idx: Integer;
Begin
  Result := False;
  Entry := Nil;
  FLastError := '';
  If Not EnsureDir Then
    Exit;
  If Not FLoaded Then
    Load;
  Idx := Length(FTurns);
  ConvLine := BuildTurnJson(Turn) + #10;
  ConvFS := Nil;
  IdxFS := Nil;
  Try
    Try
      If FileExistsUTF8(ConversationPath) Then
        ConvFS := TFileStream.Create(ConversationPath, fmOpenReadWrite Or fmShareDenyWrite)
      Else
        ConvFS := TFileStream.Create(ConversationPath, fmCreate);
      ConvFS.Seek(0, soEnd);
      ConvOffset := ConvFS.Position;
      If Length(ConvLine) > 0 Then
        ConvFS.WriteBuffer(ConvLine[1], Length(ConvLine));
      { Build the index line before touching memory so a failed index write can
        truncate the conversation file with no in-memory commit. }
      Entry := EntryFromTurn(Turn, ConvOffset, Idx);
      IdxLine := BuildIndexLine(Entry, Idx) + #10;
      Try
        If FileExistsUTF8(IndexPath) Then
          IdxFS := TFileStream.Create(IndexPath, fmOpenReadWrite Or fmShareDenyWrite)
        Else
          IdxFS := TFileStream.Create(IndexPath, fmCreate);
        IdxFS.Seek(0, soEnd);
        If Length(IdxLine) > 0 Then
          IdxFS.WriteBuffer(IdxLine[1], Length(IdxLine));
      Except
        On E: Exception Do
          Begin
            ConvFS.Size := ConvOffset;
            FreeAndNil(Entry);
            FLastError := E.Message;
            Exit;
          End;
      End;
      SetLength(FTurns, Idx + 1);
      FTurns[Idx] := Turn;
      FIndex.Add(Entry);
      FLoaded := True;
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          If Assigned(ConvFS) And (ConvFS.Size > 0) Then
            Try
              If Assigned(Entry) Then
                ConvFS.Size := Entry.FileOffset;
            Except
            End;
          If Assigned(Entry) And (FIndex.IndexOf(Entry) >= 0) Then
            Begin
              FIndex.Remove(Entry);
              Entry := Nil;
            End
          Else
            FreeAndNil(Entry);
          If Length(FTurns) > Idx Then
            SetLength(FTurns, Idx);
        End;
    End;
  Finally
    IdxFS.Free;
    ConvFS.Free;
  End;
End;

Function TAssistantConversationStore.GetTurn(TurnIndex: Integer; Out Turn: TConversationTurn): Boolean;
Begin
  Result := False;
  Turn.Id := '';
  Turn.Mode := 'inspect';
  Turn.Prompt := '';
  Turn.Thinking := '';
  Turn.Response := '';
  Turn.CreatedAt := '';
  Turn.StartedAt := '';
  Turn.FinishedAt := '';
  Turn.DurationMs := 0;
  Turn.ThinkingMs := 0;
  Turn.Model := '';
  Turn.Skill := '';
  Turn.TokenEstimate := 0;
  Turn.ErrorText := '';
  Turn.PlanFile := '';
  Turn.TodoId := '';
  Turn.TraceJson := '';
  Turn.EventsFile := '';
  Turn.MessagesJson := '';
  Turn.AttachmentsJson := '';
  If (TurnIndex < 0) Or (TurnIndex >= Length(FTurns)) Then
    Begin
      FLastError := 'Turn index out of range.';
      Exit;
    End;
  Turn := FTurns[TurnIndex];
  Result := True;
End;

Function TAssistantConversationStore.TurnCount: Integer;
Begin
  Result := Length(FTurns);
End;

Function TAssistantConversationStore.IndexCount: Integer;
Begin
  Result := FIndex.Count;
End;

Function TAssistantConversationStore.IndexEntry(Index: Integer): TConversationIndexEntry;
Begin
  If (Index < 0) Or (Index >= FIndex.Count) Then
    Result := Nil
  Else
    Result := TConversationIndexEntry(FIndex[Index]);
End;

Function TAssistantConversationStore.LoadShellConfig(Out ShowThinking: Boolean;
  Out ActiveMode: TAssistantMode; Out PlanFile: String; ShowToolUse: PBoolean;
  DocumentFile: PString): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  SL: TStringList;
  ModeText: String;
Begin
  Result := False;
  ShowThinking := True;
  If Assigned(ShowToolUse) Then ShowToolUse^ := True;
  ActiveMode := amChat;
  PlanFile := '';
  If Not FileExistsUTF8(ConfigPath) Then
    Exit;
  SL := TStringList.Create;
  Data := Nil;
  Try
    Try
      SL.LoadFromFile(ConfigPath);
      Data := GetJSON(SL.Text);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      ShowThinking := Obj.Get('show_thinking', True);
      If Assigned(ShowToolUse) Then ShowToolUse^ := Obj.Get('show_tool_use', True);
      ModeText := Obj.Get('active_mode', 'chat');
      ActiveMode := StrToAssistantMode(ModeText);
      PlanFile := Obj.Get('plan_file', '');
      PlanFile := StringReplace(Trim(PlanFile), '\', '/', [rfReplaceAll]);
      If Assigned(DocumentFile) Then
        Begin
          DocumentFile^ := Obj.Get('document_file', '');
          DocumentFile^ := StringReplace(Trim(DocumentFile^), '\', '/', [rfReplaceAll]);
        End;
      Result := True;
    Except
      On E: Exception Do
        Begin
          FLastError := E.Message;
          Result := False;
        End;
    End;
  Finally
    Data.Free;
    SL.Free;
  End;
End;

Function TAssistantConversationStore.SaveShellConfig(ShowThinking: Boolean;
  ActiveMode: TAssistantMode; Const PlanFile: String; ShowToolUse: PBoolean;
  DocumentFile: PString): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  SL: TStringList;
  OwnsObj: Boolean;
  PlanNorm: String;
Begin
  Result := False;
  If Not EnsureDir Then
    Exit;
  Data := Nil;
  Obj := Nil;
  OwnsObj := False;
  PlanNorm := StringReplace(Trim(PlanFile), '\', '/', [rfReplaceAll]);
  SL := TStringList.Create;
  Try
    If FileExistsUTF8(ConfigPath) Then
      Begin
        Try
          SL.LoadFromFile(ConfigPath);
          Data := GetJSON(SL.Text);
          If Data Is TJSONObject Then
            Obj := TJSONObject(Data)
          Else
            FreeAndNil(Data);
        Except
          FreeAndNil(Data);
          Obj := Nil;
        End;
      End;
    If Obj = Nil Then
      Begin
        Obj := TJSONObject.Create;
        OwnsObj := True;
      End;
    Obj.Booleans['show_thinking'] := ShowThinking;
    If Assigned(ShowToolUse) Then Obj.Booleans['show_tool_use'] := ShowToolUse^;
    Obj.Strings['active_mode'] := AssistantModeToStr(ActiveMode);
    Obj.Strings['plan_file'] := PlanNorm;
    If Assigned(DocumentFile) Then
      Obj.Strings['document_file'] := StringReplace(Trim(DocumentFile^), '\', '/', [rfReplaceAll]);
    Try
      SL.Text := Obj.FormatJSON;
      SL.SaveToFile(ConfigPath);
      Result := True;
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    If OwnsObj Then
      Obj.Free
    Else
      Data.Free;
    SL.Free;
  End;
End;

Function TAssistantConversationStore.SaveDocumentFile(Const RelativePath: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  SL: TStringList;
  OwnsObj: Boolean;
  DocumentPath: String;
Begin
  Result := False;
  If Not EnsureDir Then
    Exit;
  DocumentPath := StringReplace(Trim(RelativePath), '\', '/', [rfReplaceAll]);
  Data := Nil;
  Obj := Nil;
  OwnsObj := False;
  SL := TStringList.Create;
  Try
    If FileExistsUTF8(ConfigPath) Then
      Begin
        Try
          SL.LoadFromFile(ConfigPath);
          Data := GetJSON(SL.Text);
          If Data Is TJSONObject Then
            Obj := TJSONObject(Data)
          Else
            FreeAndNil(Data);
        Except
          FreeAndNil(Data);
          Obj := Nil;
        End;
      End;
    If Obj = Nil Then
      Begin
        Obj := TJSONObject.Create;
        OwnsObj := True;
      End;
    Obj.Strings['document_file'] := DocumentPath;
    Try
      SL.Text := Obj.FormatJSON;
      SL.SaveToFile(ConfigPath);
      Result := True;
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    If OwnsObj Then
      Obj.Free
    Else
      Data.Free;
    SL.Free;
  End;
End;

Function LoadAssistantConfigObject(Const ConfigFile: String): TJSONObject;
Var
  SL: TStringList;
  Data: TJSONData;
Begin
  Result := TJSONObject.Create;
  If (ConfigFile = '') Or (Not FileExistsUTF8(ConfigFile)) Then
    Exit;
  SL := TStringList.Create;
  Data := Nil;
  Try
    Try
      SL.LoadFromFile(ConfigFile);
      Data := GetJSON(SL.Text);
      If Data Is TJSONObject Then
        Begin
          Result.Free;
          Result := TJSONObject(Data);
          Data := Nil;
        End;
    Except
      { Invalid settings: callers keep the other keys they can still write. }
    End;
  Finally
    Data.Free;
    SL.Free;
  End;
End;

Function TAssistantConversationStore.LoadAvailablePlanPaths(Paths: TStrings): Boolean;
Var
  Obj: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Item: String;
Begin
  Result := False;
  If Not Assigned(Paths) Then
    Exit;
  Paths.Clear;
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root for assistant plan list.';
      Exit;
    End;
  Obj := LoadAssistantConfigObject(ConfigPath);
  Try
    Node := Obj.Find('available_plans');
    If Assigned(Node) And (Node Is TJSONArray) Then
      Begin
        Arr := TJSONArray(Node);
        For I := 0 To Arr.Count - 1 Do
          Begin
            If Arr.Items[I].JSONType <> jtString Then
              Continue;
            Item := StringReplace(Trim(Arr.Items[I].AsString), '\', '/', [rfReplaceAll]);
            If Item <> '' Then
              Paths.Add(Item);
          End;
      End;
    Result := True;
  Finally
    Obj.Free;
  End;
End;

Function TAssistantConversationStore.SaveAvailablePlanPaths(Paths: TStrings): Boolean;
Var
  Obj: TJSONObject;
  Arr: TJSONArray;
  I, NameIndex: Integer;
  Item: String;
  SL: TStringList;
Begin
  Result := False;
  If Not Assigned(Paths) Then
    Exit;
  If Not EnsureDir Then
    Exit;
  Obj := LoadAssistantConfigObject(ConfigPath);
  Try
    Arr := TJSONArray.Create;
    Try
      For I := 0 To Paths.Count - 1 Do
        Begin
          Item := StringReplace(Trim(Paths[I]), '\', '/', [rfReplaceAll]);
          If Item <> '' Then
            Arr.Add(Item);
        End;
      NameIndex := Obj.IndexOfName('available_plans');
      If NameIndex >= 0 Then
        Obj.Delete(NameIndex);
      Obj.Add('available_plans', Arr);
      Arr := Nil;
    Finally
      Arr.Free;
    End;
    SL := TStringList.Create;
    Try
      Try
        SL.Text := Obj.FormatJSON;
        SL.SaveToFile(ConfigPath);
        Result := True;
      Except
        On E: Exception Do
          FLastError := E.Message;
      End;
    Finally
      SL.Free;
    End;
  Finally
    Obj.Free;
  End;
End;

Function NewArchiveId: String;
Begin
  { Filesystem-safe timestamp id (no colons). A test may force the next id once. }
  If ForcedArchiveId <> '' Then
    Begin
      Result := ForcedArchiveId;
      ForcedArchiveId := '';
    End
  Else
    Result := FormatDateTime('yyyymmdd"T"hhnnsszzz', Now);
End;

Procedure SetNextArchiveIdForTest(Const ArchiveId: String);
Begin
  ForcedArchiveId := ArchiveId;
End;

Function ArchiveIdIsSafe(Const ArchiveId: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := False;
  If (ArchiveId = '') Or (Length(ArchiveId) > 24) Then
    Exit;
  For I := 1 To Length(ArchiveId) Do
    Begin
      C := ArchiveId[I];
      If Not (((C >= '0') And (C <= '9')) Or (C = 'T') Or (C = 't') Or (C = 'x') Or (C = 'X')) Then
        Exit;
    End;
  Result := True;
End;

Function TAssistantConversationStore.ArchivePathsForId(Const ArchiveId: String;
  Out ConvPath, IdxPath: String): Boolean;
Var
  Root, Full: String;
Begin
  Result := False;
  ConvPath := '';
  IdxPath := '';
  If (FProjectRoot = '') Or (Trim(ArchiveId) = '') Then
    Exit;
  If Not ArchiveIdIsSafe(ArchiveId) Then
    Begin
      FLastError := 'Invalid archive id.';
      Exit;
    End;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(AssistantDir));
  Full := ExpandFileName(Root + ConversationArchivePrefix + ArchiveId + ConversationArchiveSuffix);
  If CompareFilenames(Copy(Full, 1, Length(Root)), Root) <> 0 Then
    Begin
      FLastError := 'Invalid archive id.';
      Exit;
    End;
  ConvPath := AssistantDir + ConversationArchivePrefix + ArchiveId + ConversationArchiveSuffix;
  IdxPath := AssistantDir + ConversationArchivePrefix + ArchiveId + ConversationArchiveIndexSuffix;
  Result := True;
End;

Function TAssistantConversationStore.IdentityPath: String;
Begin
  Result := AssistantDir + IdentityFileName;
End;

Function TAssistantConversationStore.ArchiveIdentityPath(Const ArchiveId: String): String;
Begin
  Result := '';
  If (AssistantDir = '') Or (Not ArchiveIdIsSafe(ArchiveId)) Then
    Exit;
  Result := AssistantDir + ConversationArchivePrefix + ArchiveId + IdentityArchiveSuffix;
End;

Function TAssistantConversationStore.ReadIdentityAt(Const Path: String; Out Id, Epoch: String; Out Cursor: Int64): Boolean;
Var
  Lines: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  Node: TJSONData;
Begin
  Result := False;
  Id := '';
  Epoch := '';
  Cursor := 0;
  If (Path = '') Or (Not FileExistsUTF8(Path)) Or FileIsSymlink(Path) Then
    Exit;
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Try
      Lines.LoadFromFile(Path);
      Data := GetJSON(Lines.Text);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Id := LowerCase(Trim(Obj.Get('id', '')));
      If Not MonitorConversationIdIsValid(Id) Then
        Begin
          Id := '';
          Exit;
        End;
      Epoch := LowerCase(Trim(Obj.Get('epoch', '')));
      Node := Obj.Find('cursor');
      If Assigned(Node) And (Node.JSONType = jtNumber) Then
        Cursor := Node.AsInt64;
      If Cursor < 0 Then
        Cursor := 0;
      Result := True;
    Except
      Result := False;
      Id := '';
      Epoch := '';
      Cursor := 0;
    End;
  Finally
    Data.Free;
    Lines.Free;
  End;
End;

Function TAssistantConversationStore.WriteIdentityAt(Const Path, Id, Epoch: String; Cursor: Int64): Boolean;
Var
  Obj: TJSONObject;
  Lines: TStringList;
Begin
  Result := False;
  If (Path = '') Or (Not MonitorConversationIdIsValid(Id)) Or (Cursor < 0) Then
    Exit;
  If FileExistsUTF8(Path) And FileIsSymlink(Path) Then
    Begin
      FLastError := 'Refusing to write a symbolic link.';
      Exit;
    End;
  If Not EnsureDir Then
    Exit;
  Obj := TJSONObject.Create;
  Lines := TStringList.Create;
  Try
    Obj.Add('id', Id);
    Obj.Add('epoch', Epoch);
    Obj.Add('cursor', Cursor);
    Lines.Text := Obj.FormatJSON;
    Try
      Lines.SaveToFile(Path);
      Result := True;
    Except
      On E: Exception Do
        FLastError := E.Message;
    End;
  Finally
    Lines.Free;
    Obj.Free;
  End;
End;

Function TAssistantConversationStore.MoveIdentityFile(Const FromPath, ToPath: String): Boolean;
Begin
  Result := True;
  If (FromPath = '') Or (Not FileExistsUTF8(FromPath)) Then
    Exit;
  If FileIsSymlink(FromPath) Or ((ToPath <> '') And FileExistsUTF8(ToPath)) Then
    Begin
      FLastError := 'Could not move the conversation identity.';
      Result := False;
      Exit;
    End;
  Result := RenameFileUTF8(FromPath, ToPath);
  If Not Result Then
    FLastError := 'Could not move the conversation identity.';
End;

Function TAssistantConversationStore.TitleFromIndexFile(Const IdxFile: String): String;
Var
  SL: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  Preview, Created: String;
Begin
  Result := '';
  If (IdxFile = '') Or (Not FileExistsUTF8(IdxFile)) Then
    Exit;
  SL := TStringList.Create;
  Data := Nil;
  Try
    Try
      SL.LoadFromFile(IdxFile);
      If SL.Count < 1 Then
        Exit;
      Data := GetJSON(SL[0]);
      If Data Is TJSONObject Then
        Begin
          Obj := TJSONObject(Data);
          Preview := Trim(Obj.Get('prompt_preview', ''));
          Created := Trim(Obj.Get('created_at', ''));
          If Preview <> '' Then
            Result := Preview
          Else If Created <> '' Then
            Result := Created
          Else
            Result := ExtractFileName(IdxFile);
        End;
    Except
      Result := '';
    End;
  Finally
    Data.Free;
    SL.Free;
  End;
End;

Function TAssistantConversationStore.HasTurns: Boolean;
Begin
  If Not FLoaded Then
    If FProjectRoot <> '' Then
      Load;
  Result := TurnCount > 0;
End;

Function TAssistantConversationStore.HistoryTitleForCurrent: String;
Var
  Entry: TConversationIndexEntry;
Begin
  Result := 'Current';
  If Not FLoaded Then
    Load;
  If IndexCount < 1 Then
    Begin
      Result := 'Current (empty)';
      Exit;
    End;
  Entry := IndexEntry(0);
  If Assigned(Entry) And (Entry.PromptPreview <> '') Then
    Result := 'Current — ' + Entry.PromptPreview
  Else
    Result := Format('Current — %d turn(s)', [TurnCount]);
End;

Function TAssistantConversationStore.MonitorConversationId: String;
Var
  Id, Epoch: String;
  Cursor: Int64;
Begin
  Result := '';
  If FProjectRoot = '' Then
    Exit;
  If MonitorConversationIdIsValid(FMonitorId) And FileExistsUTF8(IdentityPath) And (Not FileIsSymlink(IdentityPath)) Then
    Begin
      Result := FMonitorId;
      Exit;
    End;
  If ReadIdentityAt(IdentityPath, Id, Epoch, Cursor) Then
    Begin
      FMonitorId := Id;
      FMonitorEpoch := Epoch;
      FMonitorCursor := Cursor;
      Result := FMonitorId;
      Exit;
    End;
  Id := NewMonitorConversationId;
  If Id = '' Then
    Begin
      FLastError := 'Could not mint a conversation id.';
      Exit;
    End;
  If Not WriteIdentityAt(IdentityPath, Id, '', 0) Then
    Exit;
  FMonitorId := Id;
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  Result := FMonitorId;
End;

Function TAssistantConversationStore.OpenConversationId: String;
Begin
  Result := MonitorConversationId;
End;

Procedure TAssistantConversationStore.NoteMonitorLogPosition(Const Epoch: String; Cursor: Int64);
Begin
  If Cursor < 0 Then
    Exit;
  If MonitorConversationId = '' Then
    Exit;
  If (Epoch = FMonitorEpoch) And (Cursor = FMonitorCursor) Then
    Exit;
  If Not WriteIdentityAt(IdentityPath, FMonitorId, Epoch, Cursor) Then
    Exit;
  FMonitorEpoch := Epoch;
  FMonitorCursor := Cursor;
End;

Procedure TAssistantConversationStore.ReadMonitorLogPosition(Out Epoch: String; Out Cursor: Int64);
Begin
  Epoch := '';
  Cursor := 0;
  If MonitorConversationId = '' Then
    Exit;
  Epoch := FMonitorEpoch;
  Cursor := FMonitorCursor;
End;

Function TAssistantConversationStore.SaveClosedLogPosition(Const ConversationId, Epoch: String; Cursor: Int64): Boolean;
Var
  Rec: TDirectoryScan;
  Code: LongInt;
  Path, Id, StoredEpoch: String;
  StoredCursor: Int64;
Begin
  Result := False;
  If (Not MonitorConversationIdIsValid(ConversationId)) Or (Cursor < 0) Then
    Exit;
  If FMonitorId = ConversationId Then
    Begin
      NoteMonitorLogPosition(Epoch, Cursor);
      Result := (FMonitorEpoch = Epoch) And (FMonitorCursor = Cursor);
      Exit;
    End;
  If AssistantDir = '' Then
    Exit;
  Code := StartDirectoryScan(AssistantDir + ConversationArchivePrefix + '*' + IdentityArchiveSuffix, faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        Path := AssistantDir + Rec.Name;
        If ((Rec.Attr And faDirectory) = 0) And (Not FileIsSymlink(Path)) And
          ReadIdentityAt(Path, Id, StoredEpoch, StoredCursor) And (Id = ConversationId) Then
          Begin
            Result := WriteIdentityAt(Path, ConversationId, Epoch, Cursor);
            Exit;
          End;
        Code := AdvanceDirectoryScan(Rec);
      End;
  Finally
    CloseDirectoryScan(Rec);
  End;
End;

Function TAssistantConversationStore.MonitorTitle: String;
Var
  Entry: TConversationIndexEntry;
Begin
  Result := HistoryTitleForCurrent;
  If Trim(Result) <> '' Then
    Exit;
  If Not FLoaded Then
    Load;
  If IndexCount < 1 Then
    Exit;
  Entry := IndexEntry(0);
  If Assigned(Entry) Then
    Result := Entry.PromptPreview;
End;

Function TAssistantConversationStore.ArchiveCurrent(Out ArchiveId: String): Boolean;
Var
  ConvPath, IdxPath, ArchConv, ArchIdx, ArchIdent, ImageError: String;
  MovedIdentity: Boolean;
Begin
  Result := False;
  ArchiveId := '';
  MovedIdentity := False;
  FLastError := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root.';
      Exit;
    End;
  If Not EnsureDir Then
    Exit;
  If Not HasTurns Then
    Begin
      { Nothing to archive — treat as success so StartNew can proceed. }
      Result := True;
      Exit;
    End;
  { Ensure index is on disk for History titles before rename. }
  If Not FLoaded Then
    Load;
  RewriteIndexFile;
  If MonitorConversationId = '' Then
    Exit;
  ArchiveId := NewArchiveId;
  If Not ArchivePathsForId(ArchiveId, ArchConv, ArchIdx) Then
    Begin
      ArchiveId := '';
      Exit;
    End;
  ConvPath := ConversationPath;
  IdxPath := IndexPath;
  If FileExistsUTF8(ConvPath) Then
    Begin
      If Not RenameFileUTF8(ConvPath, ArchConv) Then
        Begin
          FLastError := 'Could not archive ' + ConvPath;
          ArchiveId := '';
          Exit;
        End;
    End;
  If FileExistsUTF8(IdxPath) And (Not RenameFileUTF8(IdxPath, ArchIdx)) Then
    Begin
      { Put the conversation back. A missing index would list this archive with no turns. }
      If FileExistsUTF8(ArchConv) And (Not RenameFileUTF8(ArchConv, ConvPath)) Then
        FLastError := 'Could not archive ' + IdxPath + ' and could not restore ' + ConvPath
      Else
        FLastError := 'Could not archive ' + IdxPath;
      ArchiveId := '';
      Exit;
    End;
  ArchIdent := ArchiveIdentityPath(ArchiveId);
  If Not MoveIdentityFile(IdentityPath, ArchIdent) Then
    Begin
      If FileExistsUTF8(ArchConv) And (Not FileExistsUTF8(ConvPath)) Then
        RenameFileUTF8(ArchConv, ConvPath);
      If (ArchIdx <> '') And FileExistsUTF8(ArchIdx) And (Not FileExistsUTF8(IdxPath)) Then
        RenameFileUTF8(ArchIdx, IdxPath);
      ArchiveId := '';
      Exit;
    End;
  MovedIdentity := FileExistsUTF8(ArchIdent);
  If Not PreserveAssistantImages(AssistantDir, ArchiveId, ArchConv, ImageError) Then
    Begin
      If MovedIdentity Then
        RenameFileUTF8(ArchIdent, IdentityPath);
      If FileExistsUTF8(ArchConv) Then RenameFileUTF8(ArchConv, ConvPath);
      If (ArchIdx <> '') And FileExistsUTF8(ArchIdx) And (Not FileExistsUTF8(IdxPath)) Then
        RenameFileUTF8(ArchIdx, IdxPath);
      FLastError := ImageError;
      ArchiveId := '';
      Exit;
    End;
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  ClearAll;
  FLoaded := False;
  Result := True;
  WorkflowLogger.Info('AssistantConversation', 'Archived conversation as ' + ArchiveId);
End;

Function TAssistantConversationStore.StartNewConversation: Boolean;
Var
  ArchiveId: String;
Begin
  Result := False;
  FLastError := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root.';
      Exit;
    End;
  If Not ArchiveCurrent(ArchiveId) Then
    Exit;
  If FileExistsUTF8(IdentityPath) And (Not FileIsSymlink(IdentityPath)) Then
    DeleteFileUTF8(IdentityPath);
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  ClearAll;
  FLoaded := True;
  If FileExistsUTF8(ConversationPath) Then
    DeleteFileUTF8(ConversationPath);
  If FileExistsUTF8(IndexPath) Then
    DeleteFileUTF8(IndexPath);
  If MonitorConversationId = '' Then
    Exit;
  Result := True;
End;

Function TAssistantConversationStore.ListHistory(Items: TObjectList): Boolean;
Var
  Rec: TDirectoryScan;
  Code: LongInt;
  Name, Stem, ArchId, ConvPath, IdxPath, Title: String;
  Item: TConversationHistoryItem;
  I: Integer;
  Sorted: TStringList;
  Lines: TStringList;
Begin
  Result := False;
  FLastError := '';
  If Not Assigned(Items) Then
    Exit;
  Items.Clear;
  If FProjectRoot = '' Then
    Exit;
  If Not EnsureDir Then
    Exit;

  If Not FLoaded Then
    Load;

  Item := TConversationHistoryItem.Create;
  Item.ArchiveId := '';
  Item.IsCurrent := True;
  Item.TurnCount := TurnCount;
  Item.Title := HistoryTitleForCurrent;
  If IndexCount > 0 Then
    Item.CreatedAt := IndexEntry(0).CreatedAt
  Else
    Item.CreatedAt := '';
  Items.Add(Item);

  Sorted := TStringList.Create;
  Try
    Sorted.Sorted := True;
    Sorted.Duplicates := dupIgnore;
    Code := StartDirectoryScan(AssistantDir + ConversationArchivePrefix + '*' + ConversationArchiveSuffix,
      faAnyFile, Rec);
    Try
      While Code = 0 Do
        Begin
          Name := Rec.Name;
          If Pos('.index.', LowerCase(Name)) > 0 Then
            Begin
              Code := AdvanceDirectoryScan(Rec);
              Continue;
            End;
          If (Rec.Attr And faDirectory) <> 0 Then
            Begin
              Code := AdvanceDirectoryScan(Rec);
              Continue;
            End;
          Stem := ChangeFileExt(Name, '');
          If SameText(Copy(Stem, 1, Length(ConversationArchivePrefix)), ConversationArchivePrefix) Then
            ArchId := Copy(Stem, Length(ConversationArchivePrefix) + 1, MaxInt)
          Else
            ArchId := Stem;
          If ArchId <> '' Then
            Sorted.Add(ArchId);
          Code := AdvanceDirectoryScan(Rec);
        End;
    Finally
      CloseDirectoryScan(Rec);
    End;

    For I := Sorted.Count - 1 DownTo 0 Do
      Begin
        ArchId := Sorted[I];
        If Not ArchivePathsForId(ArchId, ConvPath, IdxPath) Then
          Continue;
        Item := TConversationHistoryItem.Create;
        Item.ArchiveId := ArchId;
        Item.IsCurrent := False;
        Title := TitleFromIndexFile(IdxPath);
        If Title = '' Then
          Title := ArchId;
        Item.Title := Title;
        Item.CreatedAt := ArchId;
        Item.TurnCount := 0;
        If FileExistsUTF8(IdxPath) Then
          Begin
            Lines := TStringList.Create;
            Try
              Try
                Lines.LoadFromFile(IdxPath);
                Item.TurnCount := Lines.Count;
              Except
                Item.TurnCount := 0;
              End;
            Finally
              Lines.Free;
            End;
          End;
        If Item.TurnCount > 0 Then
          Item.Title := Format('%s (%d)', [Item.Title, Item.TurnCount]);
        Items.Add(Item);
      End;
  Finally
    Sorted.Free;
  End;
  Result := True;
End;

Function TAssistantConversationStore.ActivateArchive(Const ArchiveId: String): Boolean;
Var
  ArchConv, ArchIdx, ArchIdent, CurConv, CurIdx, CurIdent, TmpId, TmpConv, TmpIdx, TmpIdent, ImageError: String;
  ParkedConv, ParkedIdx, ParkedIdent: Boolean;

  Procedure RestorePark;
  Begin
    If ParkedIdent And (TmpIdent <> '') And FileExistsUTF8(TmpIdent) And (Not FileExistsUTF8(CurIdent)) Then
      RenameFileUTF8(TmpIdent, CurIdent);
    If ParkedConv And (TmpConv <> '') And FileExistsUTF8(TmpConv) And (Not FileExistsUTF8(CurConv)) Then
      RenameFileUTF8(TmpConv, CurConv);
    If ParkedIdx And (TmpIdx <> '') And FileExistsUTF8(TmpIdx) And (Not FileExistsUTF8(CurIdx)) Then
      RenameFileUTF8(TmpIdx, CurIdx);
  End;

Begin
  Result := False;
  FLastError := '';
  ParkedConv := False;
  ParkedIdx := False;
  ParkedIdent := False;
  TmpConv := '';
  TmpIdx := '';
  TmpIdent := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root.';
      Exit;
    End;
  If Trim(ArchiveId) = '' Then
    Begin
      If Not FLoaded Then
        Load;
      Result := MonitorConversationId <> '';
      If Not Result And (FLastError = '') Then
        FLastError := 'Could not mint a conversation id.';
      Exit;
    End;
  If Not ArchivePathsForId(ArchiveId, ArchConv, ArchIdx) Then
    Exit;
  If Not FileExistsUTF8(ArchConv) Then
    Begin
      FLastError := 'Archive not found: ' + ArchiveId;
      Exit;
    End;
  If Not EnsureDir Then
    Exit;

  CurConv := ConversationPath;
  CurIdx := IndexPath;
  CurIdent := IdentityPath;
  ArchIdent := ArchiveIdentityPath(ArchiveId);

  If HasTurns Or FileExistsUTF8(CurConv) Then
    Begin
      If Not FLoaded Then
        Load;
      If HasTurns Then
        RewriteIndexFile;
      If MonitorConversationId = '' Then
        Exit;
      TmpId := NewArchiveId;
      While SameText(TmpId, ArchiveId) Do
        TmpId := NewArchiveId + 'x';
      If Not ArchivePathsForId(TmpId, TmpConv, TmpIdx) Then
        Exit;
      TmpIdent := ArchiveIdentityPath(TmpId);
      If FileExistsUTF8(CurConv) Then
        If Not RenameFileUTF8(CurConv, TmpConv) Then
          Begin
            FLastError := 'Could not park current conversation.';
            Exit;
          End
        Else
          ParkedConv := True;
      If FileExistsUTF8(CurIdx) Then
        If Not RenameFileUTF8(CurIdx, TmpIdx) Then
          Begin
            RestorePark;
            If ParkedConv And FileExistsUTF8(TmpConv) Then
              FLastError := 'Could not park current index and could not restore the conversation.'
            Else
              FLastError := 'Could not park current index.';
            Exit;
          End
        Else
          ParkedIdx := True;
      If Not MoveIdentityFile(CurIdent, TmpIdent) Then
        Begin
          RestorePark;
          Exit;
        End;
      ParkedIdent := FileExistsUTF8(TmpIdent);
      If ParkedConv And (Not PreserveAssistantImages(AssistantDir, TmpId, TmpConv, ImageError)) Then
        Begin
          RestorePark;
          FLastError := ImageError;
          Exit;
        End;
    End
  Else If FileExistsUTF8(CurIdent) And (Not FileIsSymlink(CurIdent)) Then
    DeleteFileUTF8(CurIdent);
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;

  If Not RenameFileUTF8(ArchConv, CurConv) Then
    Begin
      FLastError := 'Could not activate archive ' + ArchiveId;
      RestorePark;
      Exit;
    End;
  If FileExistsUTF8(ArchIdx) And (Not RenameFileUTF8(ArchIdx, CurIdx)) Then
    Begin
      { The archive conversation is already at the current path. Move it back before restoring the park,
        or a Linux rename would overwrite the archive with the parked file. }
      If FileExistsUTF8(CurConv) And (Not FileExistsUTF8(ArchConv)) Then
        If Not RenameFileUTF8(CurConv, ArchConv) Then
          Begin
            FLastError := 'Could not activate archive ' + ArchiveId + ' and could not restore it.';
            Exit;
          End;
      RestorePark;
      FLastError := 'Could not activate archive ' + ArchiveId;
      Exit;
    End;
  If (ArchIdent <> '') And FileExistsUTF8(ArchIdent) And (Not MoveIdentityFile(ArchIdent, CurIdent)) Then
    Begin
      If FileExistsUTF8(CurConv) And (Not FileExistsUTF8(ArchConv)) Then
        RenameFileUTF8(CurConv, ArchConv);
      If FileExistsUTF8(CurIdx) And (ArchIdx <> '') And (Not FileExistsUTF8(ArchIdx)) Then
        RenameFileUTF8(CurIdx, ArchIdx);
      RestorePark;
      Exit;
    End;

  ClearAll;
  FLoaded := False;
  FMonitorId := '';
  FMonitorEpoch := '';
  FMonitorCursor := 0;
  Result := Load;
  If Result Then
    MonitorConversationId;
  If Result And (Not RestoreAssistantImages(AssistantDir, ArchiveId, CurConv, ImageError)) Then
    WorkflowLogger.Warning('AssistantConversation', 'Could not restore images for ' + ArchiveId + ': ' + ImageError);
  WorkflowLogger.Info('AssistantConversation', 'Activated archive ' + ArchiveId);
End;

Function TAssistantConversationStore.DeleteConversation(Const ArchiveId: String): Boolean;
Var
  ConvPath, IdxPath, ImageError: String;
  Files: TStringList;
Begin
  Result := False;
  FLastError := '';
  If FProjectRoot = '' Then
    Begin
      FLastError := 'No project root.';
      Exit;
    End;
  If Trim(ArchiveId) = '' Then
    Begin
      If FileExistsUTF8(ConversationPath) Then
        DeleteFileUTF8(ConversationPath);
      If FileExistsUTF8(IndexPath) Then
        DeleteFileUTF8(IndexPath);
      If FileExistsUTF8(IdentityPath) And (Not FileIsSymlink(IdentityPath)) Then
        DeleteFileUTF8(IdentityPath);
      FMonitorId := '';
      FMonitorEpoch := '';
      FMonitorCursor := 0;
      ClearAll;
      FLoaded := True;
    End
  Else
    Begin
      If Not ArchivePathsForId(ArchiveId, ConvPath, IdxPath) Then
        Exit;
      If FileExistsUTF8(ConvPath) Then
        Begin
          If Not DeleteFileUTF8(ConvPath) Then
            Begin
              FLastError := 'Could not delete ' + ConvPath;
              Exit;
            End;
        End;
      If FileExistsUTF8(IdxPath) Then
        DeleteFileUTF8(IdxPath);
      If (ArchiveIdentityPath(ArchiveId) <> '') And FileExistsUTF8(ArchiveIdentityPath(ArchiveId)) And
        (Not FileIsSymlink(ArchiveIdentityPath(ArchiveId))) Then
        DeleteFileUTF8(ArchiveIdentityPath(ArchiveId));
      If Not DeleteAssistantImageArchive(AssistantDir, ArchiveId, ImageError) Then
        Begin
          FLastError := ImageError;
          Exit;
        End;
    End;
  Files := TStringList.Create;
  Try
    CollectConversationFiles(Files);
    If Not ReleaseUnreferencedAssistantImages(AssistantDir, Files, ImageError) Then
      Begin
        FLastError := ImageError;
        Exit;
      End;
    If Not ReleaseOrphanAssistantImageArchives(AssistantDir, Files, ImageError) Then
      Begin
        FLastError := ImageError;
        Exit;
      End;
  Finally
    Files.Free;
  End;
  Result := True;
  WorkflowLogger.Info('AssistantConversation', 'Deleted conversation ' + ArchiveId);
End;

Initialization

Randomize;
ProjectAssistantConversation := TAssistantConversationStore.Create;

Finalization

FreeAndNil(ProjectAssistantConversation);

End.
