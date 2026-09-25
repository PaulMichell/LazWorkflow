Unit SpellCheckerConfig;

{ Shared spell-checker config, discovery, and engine factory (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, LazMethodList, SpellEngine, SpellCheckerOptions;

Type
  TSpellDiscoveredLanguage = Record
    Code: String;
    SourceKind: TSpellEngineKind;
  End;
  TSpellDiscoveredLanguageArray = Array Of TSpellDiscoveredLanguage;

  TSpellCheckerConfig = Class
  Private
    FOptions: TSpellCheckerOptions;
    FEngine: TSpellEngine;
    FPersonal: TSpellWordSet;
    FSessionIgnore: TSpellWordSet;
    FStorageFileName: String;
    FListeners: TMethodList;
    FLastStatus: String;
    FEngineLock: TRTLCriticalSection;
    FPreloadThread: TThread;
    FRetiredPreloads: TFPList;
    FWordCache: TStringList;
    FPreloadSeq: Integer;
    FIssuedValid: Boolean;
    FIssuedKind: TSpellEngineKind;
    FIssuedLanguage: String;
    FIssuedLibrary: String;
    FIssuedDict: String;
    Procedure NotifyChanged;
    Procedure UnloadEngine;
    Function PersonalPath: String;
    Function IssuedMatchesOptions: Boolean;
    Procedure RememberIssuedOptions;
    Procedure StopPreload;
    Procedure AcceptPreloadEngine(Engine: TSpellEngine; Const Status: String; Seq: Integer);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetStorageFileName(Const FileName: String);
    Procedure Load;
    Procedure Save;
    Procedure Apply;
    { Start Hunspell/Aspell on a worker so IDE forms do not stall. Safe to call more than once. }
    Procedure EnsurePreloaded;
    Procedure AssignOptions(Source: TSpellCheckerOptions);
    Function IsReady: Boolean;
    Function ResolvedKind: TSpellEngineKind;
    Function IsWordCorrect(Const WordText: String): Boolean;
    Function GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
    Function AddToPersonal(Const WordText: String): Boolean;
    Procedure IgnoreWord(Const WordText: String);
    Procedure DiscoverLanguages(Out Languages: TSpellDiscoveredLanguageArray);
    Function HunspellAvailable: Boolean;
    Function AspellAvailable: Boolean;
    Procedure RegisterChangedHandler(Handler: TNotifyEvent);
    Procedure UnregisterChangedHandler(Handler: TNotifyEvent);
    Property Options: TSpellCheckerOptions Read FOptions;
    Property Engine: TSpellEngine Read FEngine;
    Property StorageFileName: String Read FStorageFileName;
    Property LastStatus: String Read FLastStatus;
  End;

Var
  WorkflowSpellConfig: TSpellCheckerConfig;

Procedure InitializeSpellCheckerStorage(Const ConfigDirectory: String);

Implementation

Uses
  LazFileUtils, fpjson, WorkflowSettings, SpellEngineHunspell, SpellEngineAspell, WorkflowLog;

Type
  TSpellPreloadThread = Class(TThread)
  Private
    FOwner: TSpellCheckerConfig;
    FSeq: Integer;
    FKind: TSpellEngineKind;
    FLanguage: String;
    FLibraryFileName: String;
    FDictionaryDirectory: String;
    FEngine: TSpellEngine;
    FStatus: String;
    Procedure CommitResult;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Owner: TSpellCheckerConfig; Seq: Integer; Kind: TSpellEngineKind;
      Const Language, LibraryFileName, DictionaryDirectory: String);
    Destructor Destroy; Override;
  End;

Constructor TSpellPreloadThread.Create(Owner: TSpellCheckerConfig; Seq: Integer; Kind: TSpellEngineKind;
  Const Language, LibraryFileName, DictionaryDirectory: String);
Begin
  FOwner := Owner;
  FSeq := Seq;
  FKind := Kind;
  FLanguage := Language;
  FLibraryFileName := LibraryFileName;
  FDictionaryDirectory := DictionaryDirectory;
  FEngine := Nil;
  FStatus := '';
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Destructor TSpellPreloadThread.Destroy;
Begin
  TThread.RemoveQueuedEvents(Self);
  FreeAndNil(FEngine);
  Inherited Destroy;
End;

Procedure TSpellPreloadThread.CommitResult;
Begin
  If Assigned(FOwner) Then
    FOwner.AcceptPreloadEngine(FEngine, FStatus, FSeq);
  FEngine := Nil;
End;

Procedure TSpellPreloadThread.Execute;
Var
  Candidate: TSpellEngine;

  Function TryKind(LoadKind: TSpellEngineKind): TSpellEngine;
  Begin
    Result := Nil;
    Case LoadKind Of
      sekHunspell:
        Result := THunspellEngine.Create(FLanguage, FLibraryFileName, FDictionaryDirectory);
      sekAspell:
        Result := TAspellEngine.Create(FLanguage, FLibraryFileName, FDictionaryDirectory);
    Else
      Exit;
    End;
    If Result.Load Then
      Exit;
    FStatus := Result.LastError;
    FreeAndNil(Result);
  End;

Begin
  If Terminated Or (Not Assigned(FOwner)) Then
    Exit;
  Candidate := Nil;
  If FKind = sekNone Then
    FStatus := 'No engine loaded — memo only'
  Else If FKind = sekAuto Then
    Begin
      Candidate := TryKind(sekHunspell);
      If Not Assigned(Candidate) Then
        Candidate := TryKind(sekAspell);
    End
  Else
    Candidate := TryKind(FKind);
  FEngine := Candidate;
  If Assigned(FEngine) And FEngine.IsReady Then
    FStatus := SpellEngineKindToText(FEngine.EngineKind) + ' ready (' + FEngine.ResolvedLanguage + ')'
  Else If FStatus = '' Then
    FStatus := 'No engine loaded — memo only';
  If Terminated Then
    Begin
      FreeAndNil(FEngine);
      Exit;
    End;
  Queue(@CommitResult);
End;

Constructor TSpellCheckerConfig.Create;
Begin
  Inherited Create;
  InitCriticalSection(FEngineLock);
  FOptions := TSpellCheckerOptions.Create;
  FPersonal := TSpellWordSet.Create;
  FSessionIgnore := TSpellWordSet.Create;
  FListeners := TMethodList.Create;
  FEngine := Nil;
  FPreloadThread := Nil;
  FRetiredPreloads := TFPList.Create;
  FWordCache := TStringList.Create;
  FWordCache.Sorted := True; FWordCache.CaseSensitive := True;
  FPreloadSeq := 0;
  FIssuedValid := False;
  FIssuedKind := sekNone;
  FIssuedLanguage := '';
  FIssuedLibrary := '';
  FIssuedDict := '';
  FStorageFileName := '';
  FLastStatus := 'No engine loaded — memo only';
End;

Destructor TSpellCheckerConfig.Destroy;
Begin
  StopPreload;
  While FRetiredPreloads.Count > 0 Do
    Begin
      TThread(FRetiredPreloads.Last).WaitFor;
      TThread(FRetiredPreloads.Last).Free;
      FRetiredPreloads.Delete(FRetiredPreloads.Count - 1);
    End;
  FreeAndNil(FRetiredPreloads);
  UnloadEngine;
  FreeAndNil(FWordCache);
  FreeAndNil(FListeners);
  FreeAndNil(FSessionIgnore);
  FreeAndNil(FPersonal);
  FreeAndNil(FOptions);
  DoneCriticalSection(FEngineLock);
  Inherited Destroy;
End;

Procedure TSpellCheckerConfig.NotifyChanged;
Begin
  EnterCriticalSection(FEngineLock);
  Try FWordCache.Clear; Finally LeaveCriticalSection(FEngineLock); End;
  FListeners.CallNotifyEvents(Self);
End;

Procedure TSpellCheckerConfig.RegisterChangedHandler(Handler: TNotifyEvent);
Begin
  FListeners.Add(TMethod(Handler));
End;

Procedure TSpellCheckerConfig.UnregisterChangedHandler(Handler: TNotifyEvent);
Begin
  FListeners.Remove(TMethod(Handler));
End;

Procedure TSpellCheckerConfig.UnloadEngine;
Begin
  EnterCriticalSection(FEngineLock);
  Try
    FreeAndNil(FEngine);
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
End;

Procedure TSpellCheckerConfig.StopPreload;
Begin
  If Not Assigned(FPreloadThread) Then
    Exit;
  Inc(FPreloadSeq);
  FPreloadThread.Terminate;
  FPreloadThread.WaitFor;
  TThread.RemoveQueuedEvents(FPreloadThread);
  FreeAndNil(FPreloadThread);
End;

Procedure TSpellCheckerConfig.AcceptPreloadEngine(Engine: TSpellEngine; Const Status: String; Seq: Integer);
Begin
  If Seq <> FPreloadSeq Then
    Begin
      Engine.Free;
      Exit;
    End;
  EnterCriticalSection(FEngineLock);
  Try
    FreeAndNil(FEngine);
    FEngine := Engine;
    FLastStatus := Status;
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
  If Assigned(WorkflowLogger) Then
    WorkflowLogger.Info('Spell', FLastStatus);
  NotifyChanged;
End;

Function TSpellCheckerConfig.IssuedMatchesOptions: Boolean;
Begin
  Result := FIssuedValid And (FIssuedKind = FOptions.EngineKind) And (FIssuedLanguage = FOptions.Language) And
    (FIssuedLibrary = FOptions.LibraryFileName) And (FIssuedDict = FOptions.DictionaryDirectory);
End;

Procedure TSpellCheckerConfig.RememberIssuedOptions;
Begin
  FIssuedKind := FOptions.EngineKind;
  FIssuedLanguage := FOptions.Language;
  FIssuedLibrary := FOptions.LibraryFileName;
  FIssuedDict := FOptions.DictionaryDirectory;
  FIssuedValid := True;
End;

Procedure TSpellCheckerConfig.EnsurePreloaded;
Var I: Integer;
Begin
  For I := FRetiredPreloads.Count - 1 DownTo 0 Do
    If TThread(FRetiredPreloads[I]).Finished Then
      Begin
        TThread(FRetiredPreloads[I]).Free;
        FRetiredPreloads.Delete(I);
      End;
  If FOptions.EngineKind = sekNone Then
    Exit;
  If Assigned(FPreloadThread) And IssuedMatchesOptions Then
    Exit;
  EnterCriticalSection(FEngineLock);
  Try
    If Assigned(FEngine) And FEngine.IsReady And IssuedMatchesOptions Then
      Exit;
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
  If Assigned(FPreloadThread) Then
    Begin
      FPreloadThread.Terminate;
      FRetiredPreloads.Add(FPreloadThread);
      FPreloadThread := Nil;
    End;
  If Not IssuedMatchesOptions Then
    UnloadEngine;
  RememberIssuedOptions;
  Inc(FPreloadSeq);
  FPreloadThread := TSpellPreloadThread.Create(Self, FPreloadSeq, FIssuedKind, FIssuedLanguage, FIssuedLibrary, FIssuedDict);
End;

Function TSpellCheckerConfig.PersonalPath: String;
Begin
  Result := Trim(FOptions.PersonalFileName);
  If Result <> '' Then
    Exit;
  If FStorageFileName <> '' Then
    Result := ExtractFilePath(FStorageFileName) + 'LazWorkflowPersonal.dic'
  Else
    Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'LazWorkflowPersonal.dic';
End;

Procedure TSpellCheckerConfig.SetStorageFileName(Const FileName: String);
Begin
  FStorageFileName := FileName;
End;

Procedure ReadPersonalWords(Section: TJSONObject; Words: TSpellWordSet);
Var
  Node, Item: TJSONData;
  List: TStringList;
  I: Integer;
Begin
  List := TStringList.Create;
  Try
    Node := Nil;
    If Assigned(Section) Then
      Node := Section.Find('personal_words');
    If Node Is TJSONArray Then
      For I := 0 To TJSONArray(Node).Count - 1 Do
        Begin
          Item := TJSONArray(Node).Items[I];
          If Item.JSONType = jtString Then
            List.Add(Item.AsString);
        End;
    Words.ReplaceFromStrings(List);
  Finally
    List.Free;
  End;
End;

Procedure WritePersonalWords(Section: TJSONObject; Words: TSpellWordSet);
Var
  List: TStringList;
  Arr: TJSONArray;
  I: Integer;
Begin
  List := TStringList.Create;
  Arr := TJSONArray.Create;
  Try
    Words.CopyToStrings(List);
    For I := 0 To List.Count - 1 Do
      Arr.Add(List[I]);
    Section.Add('personal_words', Arr);
    Arr := Nil;
  Finally
    Arr.Free;
    List.Free;
  End;
End;

Procedure TSpellCheckerConfig.Load;
Var
  Section: TJSONObject;
Begin
  If FStorageFileName = '' Then
    Begin
      EnsurePreloaded;
      Exit;
    End;
  Section := ReadWorkflowSection('spell');
  Try
    If Assigned(Section) Then
      Begin
        FOptions.EngineKind := TextToSpellEngineKind(Section.Get('engine', 'auto'));
        FOptions.Language := Section.Get('language', '');
        FOptions.LibraryFileName := Section.Get('library', '');
        FOptions.DictionaryDirectory := Section.Get('dictionary_directory', '');
        FOptions.PersonalFileName := Section.Get('personal_file', '');
        ReadPersonalWords(Section, FPersonal);
      End
    Else
      FPersonal.ReplaceFromStrings(Nil);
  Finally
    Section.Free;
  End;
  If FOptions.EngineKind = sekNone Then
    Begin
      StopPreload;
      UnloadEngine;
      FIssuedValid := False;
      FLastStatus := 'No engine loaded — memo only';
      Exit;
    End;
  EnsurePreloaded;
End;

Procedure TSpellCheckerConfig.Save;
Var
  Section: TJSONObject;
  ErrorText: String;
Begin
  If FStorageFileName = '' Then
    Exit;
  FLastStatus := '';
  Section := TJSONObject.Create;
  Try
    Section.Add('engine', SpellEngineKindToText(FOptions.EngineKind));
    Section.Add('language', FOptions.Language);
    Section.Add('library', FOptions.LibraryFileName);
    Section.Add('dictionary_directory', FOptions.DictionaryDirectory);
    Section.Add('personal_file', FOptions.PersonalFileName);
    WritePersonalWords(Section, FPersonal);
    If Not WriteWorkflowSection('spell', Section, ErrorText) Then
      FLastStatus := ErrorText;
  Finally
    Section.Free;
  End;
End;

Procedure TSpellCheckerConfig.Apply;
Var
  CacheError: String;
Begin
  { personal_words in LazWorkflow.json is the source of truth. The engine file is a cache. }
  If Trim(FOptions.PersonalFileName) <> '' Then
    FPersonal.SaveToFile(PersonalPath, CacheError);
  If FOptions.EngineKind = sekNone Then
    Begin
      Inc(FPreloadSeq);
      If Assigned(FPreloadThread) Then
        Begin
          FPreloadThread.Terminate; FRetiredPreloads.Add(FPreloadThread); FPreloadThread := Nil;
        End;
      UnloadEngine;
      FIssuedValid := False;
      FLastStatus := 'No engine loaded — memo only';
    End
  Else EnsurePreloaded;
  NotifyChanged;
End;

Procedure TSpellCheckerConfig.AssignOptions(Source: TSpellCheckerOptions);
Begin
  If Source = Nil Then Exit;
  If (FOptions.EngineKind = Source.EngineKind) And (FOptions.Language = Source.Language) And
    (FOptions.LibraryFileName = Source.LibraryFileName) And
    (FOptions.DictionaryDirectory = Source.DictionaryDirectory) And
    (FOptions.PersonalFileName = Source.PersonalFileName) Then Exit;
  FOptions.Assign(Source);
  Apply;
End;

Function TSpellCheckerConfig.IsReady: Boolean;
Begin
  EnterCriticalSection(FEngineLock);
  Try
    Result := Assigned(FEngine) And FEngine.IsReady;
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
End;

Function TSpellCheckerConfig.ResolvedKind: TSpellEngineKind;
Begin
  EnterCriticalSection(FEngineLock);
  Try
    If Assigned(FEngine) Then
      Result := FEngine.EngineKind
    Else
      Result := sekNone;
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
End;

Function TSpellCheckerConfig.IsWordCorrect(Const WordText: String): Boolean;
Var Index: Integer;
Begin
  Result := True;
  If Trim(WordText) = '' Then
    Exit;
  If FPersonal.Contains(WordText) Or FSessionIgnore.Contains(WordText) Then
    Exit;
  EnterCriticalSection(FEngineLock);
  Try
    If FWordCache.Find(WordText, Index) Then
      Exit(PtrInt(FWordCache.Objects[Index]) = 1);
    If Assigned(FEngine) And FEngine.IsReady Then
      Begin
        Result := FEngine.CheckWord(WordText);
        If FWordCache.Count >= 8192 Then FWordCache.Clear;
        FWordCache.AddObject(WordText, TObject(PtrInt(Ord(Result))));
      End;
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
End;

Function TSpellCheckerConfig.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
Begin
  Result := EmptySpellSuggestions;
  EnterCriticalSection(FEngineLock);
  Try
    If Assigned(FEngine) And FEngine.IsReady Then
      Result := FEngine.GetSuggestions(WordText, MaxCount);
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
End;

Function TSpellCheckerConfig.AddToPersonal(Const WordText: String): Boolean;
Var ErrorText: String;
Begin
  Result := True;
  If FPersonal.Contains(WordText) Then Exit;
  FPersonal.Add(WordText);
  If (Trim(FOptions.PersonalFileName) <> '') And (Not FPersonal.SaveToFile(PersonalPath, ErrorText)) Then
    Begin
      FPersonal.Remove(WordText);
      FLastStatus := 'Could not save personal dictionary: ' + ErrorText;
      Exit(False);
    End;
  Save;
  If (FStorageFileName <> '') And (FLastStatus <> '') Then
    Begin
      FPersonal.Remove(WordText);
      Exit(False);
    End;
  EnterCriticalSection(FEngineLock);
  Try
    If Assigned(FEngine) And FEngine.IsReady Then
      FEngine.AddToSession(WordText);
  Finally
    LeaveCriticalSection(FEngineLock);
  End;
  NotifyChanged;
End;

Procedure TSpellCheckerConfig.IgnoreWord(Const WordText: String);
Begin
  FSessionIgnore.Add(WordText);
  NotifyChanged;
End;

Procedure TSpellCheckerConfig.DiscoverLanguages(Out Languages: TSpellDiscoveredLanguageArray);
Var
  Names: TStringList;
  Procedure AppendKind(List: TStrings; Kind: TSpellEngineKind);
  Var
    I, J: Integer;
    Exists: Boolean;
  Begin
    For I := 0 To List.Count - 1 Do
      Begin
        Exists := False;
        For J := 0 To High(Languages) Do
          If SameText(Languages[J].Code, List[I]) And (Languages[J].SourceKind = Kind) Then
            Begin
              Exists := True;
              Break;
            End;
        If Exists Then
          Continue;
        SetLength(Languages, Length(Languages) + 1);
        Languages[High(Languages)].Code := List[I];
        Languages[High(Languages)].SourceKind := Kind;
      End;
  End;
Begin
  Languages := Nil;
  Names := TStringList.Create;
  Try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    ListHunspellLanguages(Names, FOptions.DictionaryDirectory);
    AppendKind(Names, sekHunspell);
    Names.Clear;
    ListAspellLanguages(Names);
    AppendKind(Names, sekAspell);
  Finally
    Names.Free;
  End;
End;

Function TSpellCheckerConfig.HunspellAvailable: Boolean;
Var
  LibName: String;
Begin
  Result := FindHunspellLibrary(LibName);
End;

Function TSpellCheckerConfig.AspellAvailable: Boolean;
Var
  LibName: String;
Begin
  Result := FindAspellLibrary(LibName);
End;

Procedure InitializeSpellCheckerStorage(Const ConfigDirectory: String);
Var
  Dir: String;
Begin
  If Not Assigned(WorkflowSpellConfig) Then
    Exit;
  Dir := Trim(ConfigDirectory);
  If Dir = '' Then
    Exit;
  SetWorkflowSettingsDirectory(Dir);
  WorkflowSpellConfig.SetStorageFileName(WorkflowSettingsPath);
  WorkflowSpellConfig.Load;
  WorkflowLogger.Info('Spell', 'Preloading spell engine in the background');
End;

Initialization

WorkflowSpellConfig := TSpellCheckerConfig.Create;

Finalization

FreeAndNil(WorkflowSpellConfig);

End.
