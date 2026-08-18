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
    Procedure NotifyChanged;
    Procedure UnloadEngine;
    Function CreateEngine(Kind: TSpellEngineKind): TSpellEngine;
    Function PersonalPath: String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure SetStorageFileName(Const FileName: String);
    Procedure Load;
    Procedure Save;
    Procedure Apply;
    Procedure AssignOptions(Source: TSpellCheckerOptions);
    Function IsReady: Boolean;
    Function ResolvedKind: TSpellEngineKind;
    Function IsWordCorrect(Const WordText: String): Boolean;
    Function GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
    Procedure AddToPersonal(Const WordText: String);
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
  Laz2_XMLCfg, LazFileUtils, SpellEngineHunspell, SpellEngineAspell, WorkflowLog;

Constructor TSpellCheckerConfig.Create;
Begin
  Inherited Create;
  FOptions := TSpellCheckerOptions.Create;
  FPersonal := TSpellWordSet.Create;
  FSessionIgnore := TSpellWordSet.Create;
  FListeners := TMethodList.Create;
  FEngine := Nil;
  FStorageFileName := '';
  FLastStatus := 'No engine loaded — memo only';
End;

Destructor TSpellCheckerConfig.Destroy;
Begin
  UnloadEngine;
  FreeAndNil(FListeners);
  FreeAndNil(FSessionIgnore);
  FreeAndNil(FPersonal);
  FreeAndNil(FOptions);
  Inherited Destroy;
End;

Procedure TSpellCheckerConfig.NotifyChanged;
Begin
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
  FreeAndNil(FEngine);
End;

Function TSpellCheckerConfig.CreateEngine(Kind: TSpellEngineKind): TSpellEngine;
Begin
  Result := Nil;
  Case Kind Of
    sekHunspell:
      Result := THunspellEngine.Create(FOptions.Language, FOptions.LibraryFileName, FOptions.DictionaryDirectory);
    sekAspell:
      Result := TAspellEngine.Create(FOptions.Language, FOptions.LibraryFileName, FOptions.DictionaryDirectory);
  Else
    Result := Nil;
  End;
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

Procedure TSpellCheckerConfig.Load;
Var
  XML: TXMLConfig;
Begin
  If (FStorageFileName = '') Or (Not FileExistsUTF8(FStorageFileName)) Then
    Begin
      Apply;
      Exit;
    End;
  XML := TXMLConfig.Create(FStorageFileName);
  Try
    FOptions.EngineKind := TextToSpellEngineKind(XML.GetValue('Spell/Engine', 'auto'));
    FOptions.Language := XML.GetValue('Spell/Language', '');
    FOptions.LibraryFileName := XML.GetValue('Spell/LibraryFileName', '');
    FOptions.DictionaryDirectory := XML.GetValue('Spell/DictionaryDirectory', '');
    FOptions.PersonalFileName := XML.GetValue('Spell/PersonalFileName', '');
  Finally
    XML.Free;
  End;
  Apply;
End;

Procedure TSpellCheckerConfig.Save;
Var
  XML: TXMLConfig;
Begin
  If FStorageFileName = '' Then
    Exit;
  XML := TXMLConfig.Create(FStorageFileName);
  Try
    XML.SetValue('Spell/Engine', SpellEngineKindToText(FOptions.EngineKind));
    XML.SetValue('Spell/Language', FOptions.Language);
    XML.SetValue('Spell/LibraryFileName', FOptions.LibraryFileName);
    XML.SetValue('Spell/DictionaryDirectory', FOptions.DictionaryDirectory);
    XML.SetValue('Spell/PersonalFileName', FOptions.PersonalFileName);
    XML.Flush;
  Finally
    XML.Free;
  End;
End;

Procedure TSpellCheckerConfig.Apply;
Var
  Kind: TSpellEngineKind;
  Candidate: TSpellEngine;
Begin
  UnloadEngine;
  FSessionIgnore.Clear;
  FPersonal.LoadFromFile(PersonalPath);
  FLastStatus := 'No engine loaded — memo only';
  Kind := FOptions.EngineKind;
  If Kind = sekNone Then
    Begin
      NotifyChanged;
      Exit;
    End;
  If Kind = sekAuto Then
    Begin
      Candidate := CreateEngine(sekHunspell);
      If Assigned(Candidate) Then
        Begin
          If Candidate.Load Then
            FEngine := Candidate
          Else
            Begin
              Candidate.Free;
              Candidate := CreateEngine(sekAspell);
              If Assigned(Candidate) Then
                If Candidate.Load Then
                  FEngine := Candidate
                Else
                  Begin
                    FLastStatus := Candidate.LastError;
                    FreeAndNil(Candidate);
                  End;
            End;
        End;
    End
  Else
    Begin
      Candidate := CreateEngine(Kind);
      If Assigned(Candidate) Then
        If Candidate.Load Then
          FEngine := Candidate
        Else
          Begin
            FLastStatus := Candidate.LastError;
            FreeAndNil(Candidate);
          End;
    End;
  If Assigned(FEngine) And FEngine.IsReady Then
    FLastStatus := SpellEngineKindToText(FEngine.EngineKind) + ' ready (' + FEngine.ResolvedLanguage + ')'
  Else If FLastStatus = '' Then
    FLastStatus := 'No engine loaded — memo only';
  If Assigned(WorkflowLogger) Then
    WorkflowLogger.Info('Spell', FLastStatus);
  NotifyChanged;
End;

Procedure TSpellCheckerConfig.AssignOptions(Source: TSpellCheckerOptions);
Begin
  FOptions.Assign(Source);
  Apply;
End;

Function TSpellCheckerConfig.IsReady: Boolean;
Begin
  Result := Assigned(FEngine) And FEngine.IsReady;
End;

Function TSpellCheckerConfig.ResolvedKind: TSpellEngineKind;
Begin
  If Assigned(FEngine) Then
    Result := FEngine.EngineKind
  Else
    Result := sekNone;
End;

Function TSpellCheckerConfig.IsWordCorrect(Const WordText: String): Boolean;
Begin
  Result := True;
  If Trim(WordText) = '' Then
    Exit;
  If FPersonal.Contains(WordText) Or FSessionIgnore.Contains(WordText) Then
    Exit;
  If Not IsReady Then
    Exit;
  Result := FEngine.CheckWord(WordText);
End;

Function TSpellCheckerConfig.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
Begin
  If IsReady Then
    Result := FEngine.GetSuggestions(WordText, MaxCount)
  Else
    Result := EmptySpellSuggestions;
End;

Procedure TSpellCheckerConfig.AddToPersonal(Const WordText: String);
Begin
  FPersonal.Add(WordText);
  FPersonal.SaveToFile(PersonalPath);
  If IsReady Then
    FEngine.AddToSession(WordText);
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
  Index: Integer;
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
  { Keep the unused Index warning away from empty arrays. }
  Index := Length(Languages);
  If Index < 0 Then
    Languages := Nil;
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
  WorkflowSpellConfig.SetStorageFileName(IncludeTrailingPathDelimiter(Dir) + 'LazWorkflowSpell.xml');
  WorkflowSpellConfig.Load;
End;

Initialization

WorkflowSpellConfig := TSpellCheckerConfig.Create;

Finalization

FreeAndNil(WorkflowSpellConfig);

End.
