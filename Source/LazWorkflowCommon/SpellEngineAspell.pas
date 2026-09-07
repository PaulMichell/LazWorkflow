Unit SpellEngineAspell;

{ Dynload ASpell backend (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SpellEngine;

Type
  TAspellEngine = Class(TSpellEngine)
  Private
    FLanguage: String;
    FLibraryFileName: String;
    FDictionaryDirectory: String;
    FSpeller: Pointer;
  Public
    Constructor Create; Override;
    Constructor Create(Const NewLanguage, NewLibraryFileName, NewDictionaryDirectory: String);
    Function Load: Boolean; Override;
    Procedure Unload; Override;
    Function IsReady: Boolean; Override;
    Function CheckWord(Const WordText: String): Boolean; Override;
    Function GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray; Override;
    Procedure AddToSession(Const WordText: String); Override;
    Function Features: TSpellEngineFeatures; Override;
    Function EngineKind: TSpellEngineKind; Override;
    Property Language: String Read FLanguage Write FLanguage;
    Property LibraryFileName: String Read FLibraryFileName Write FLibraryFileName;
    Property DictionaryDirectory: String Read FDictionaryDirectory Write FDictionaryDirectory;
  End;

Function FindAspellLibrary(Out FullName: String): Boolean;
Procedure ListAspellLanguages(List: TStrings);

Implementation

Uses
  DynLibs, Process, LazUTF8, SpellCheckerOptions;

Type
  TAspellNewConfig = Function: Pointer; CDecl;
  TAspellDeleteConfig = Procedure(Config: Pointer); CDecl;
  TAspellConfigReplace = Function(Config: Pointer; Key, Value: PChar): Integer; CDecl;
  TAspellNewSpeller = Function(Config: Pointer): Pointer; CDecl;
  TAspellErrorNumber = Function(Obj: Pointer): Cardinal; CDecl;
  TAspellErrorMessage = Function(Obj: Pointer): PChar; CDecl;
  TAspellDeleteCanHaveError = Procedure(Obj: Pointer); CDecl;
  TAspellToSpeller = Function(Obj: Pointer): Pointer; CDecl;
  TAspellDeleteSpeller = Procedure(Speller: Pointer); CDecl;
  TAspellSpellerCheck = Function(Speller: Pointer; WordText: PChar; WordSize: Integer): Integer; CDecl;
  TAspellSpellerSuggest = Function(Speller: Pointer; WordText: PChar; WordSize: Integer): Pointer; CDecl;
  TAspellWordListElements = Function(WordList: Pointer): Pointer; CDecl;
  TAspellEnumNext = Function(EnumHandle: Pointer): PChar; CDecl;
  TAspellDeleteEnum = Procedure(EnumHandle: Pointer); CDecl;
  TAspellAddToSession = Function(Speller: Pointer; WordText: PChar; WordSize: Integer): Integer; CDecl;

Var
  AspLibHandle: TLibHandle = NilHandle;
  AspLibPath: String = '';
  NewAspellConfig: TAspellNewConfig = Nil;
  DeleteAspellConfig: TAspellDeleteConfig = Nil;
  AspellConfigReplace: TAspellConfigReplace = Nil;
  NewAspellSpeller: TAspellNewSpeller = Nil;
  AspellErrorNumber: TAspellErrorNumber = Nil;
  AspellErrorMessage: TAspellErrorMessage = Nil;
  DeleteAspellCanHaveError: TAspellDeleteCanHaveError = Nil;
  ToAspellSpeller: TAspellToSpeller = Nil;
  DeleteAspellSpeller: TAspellDeleteSpeller = Nil;
  AspellSpellerCheck: TAspellSpellerCheck = Nil;
  AspellSpellerSuggest: TAspellSpellerSuggest = Nil;
  AspellWordListElements: TAspellWordListElements = Nil;
  AspellEnumNext: TAspellEnumNext = Nil;
  DeleteAspellEnum: TAspellDeleteEnum = Nil;
  AspellAddToSession: TAspellAddToSession = Nil;

Function AspellLibraryCandidates: TStringArray;
Begin
  Result := Nil;
  {$IFDEF WINDOWS}
  SetLength(Result, 3);
  Result[0] := 'aspell-15.dll';
  Result[1] := 'libaspell-15.dll';
  Result[2] := 'libaspell.dll';
  {$ELSE}
    {$IFDEF DARWIN}
    SetLength(Result, 2);
    Result[0] := 'libaspell.dylib';
    Result[1] := 'libaspell.15.dylib';
    {$ELSE}
    SetLength(Result, 3);
    Result[0] := 'libaspell.so.15';
    Result[1] := 'libaspell.so';
    Result[2] := 'libaspell.so.15.2';
    {$ENDIF}
  {$ENDIF}
End;

Var
  BindingLock: TRTLCriticalSection;

Function BindAspell(Const FullName: String): Boolean;
Begin
  EnterCriticalSection(BindingLock);
  Try
  Result := False;
  If AspLibHandle <> NilHandle Then
    Begin
      If FullName <> AspLibPath Then Exit;
      Result := Assigned(NewAspellSpeller);
      Exit;
    End;
  AspLibHandle := LoadLibrary(FullName);
  If AspLibHandle = NilHandle Then
    Exit;
  Pointer(NewAspellConfig) := GetProcedureAddress(AspLibHandle, 'new_aspell_config');
  Pointer(DeleteAspellConfig) := GetProcedureAddress(AspLibHandle, 'delete_aspell_config');
  Pointer(AspellConfigReplace) := GetProcedureAddress(AspLibHandle, 'aspell_config_replace');
  Pointer(NewAspellSpeller) := GetProcedureAddress(AspLibHandle, 'new_aspell_speller');
  Pointer(AspellErrorNumber) := GetProcedureAddress(AspLibHandle, 'aspell_error_number');
  Pointer(AspellErrorMessage) := GetProcedureAddress(AspLibHandle, 'aspell_error_message');
  Pointer(DeleteAspellCanHaveError) := GetProcedureAddress(AspLibHandle, 'delete_aspell_can_have_error');
  Pointer(ToAspellSpeller) := GetProcedureAddress(AspLibHandle, 'to_aspell_speller');
  Pointer(DeleteAspellSpeller) := GetProcedureAddress(AspLibHandle, 'delete_aspell_speller');
  Pointer(AspellSpellerCheck) := GetProcedureAddress(AspLibHandle, 'aspell_speller_check');
  Pointer(AspellSpellerSuggest) := GetProcedureAddress(AspLibHandle, 'aspell_speller_suggest');
  Pointer(AspellWordListElements) := GetProcedureAddress(AspLibHandle, 'aspell_word_list_elements');
  Pointer(AspellEnumNext) := GetProcedureAddress(AspLibHandle, 'aspell_string_enumeration_next');
  Pointer(DeleteAspellEnum) := GetProcedureAddress(AspLibHandle, 'delete_aspell_string_enumeration');
  Pointer(AspellAddToSession) := GetProcedureAddress(AspLibHandle, 'aspell_speller_add_to_session');
  Result := Assigned(NewAspellConfig) And Assigned(NewAspellSpeller) And Assigned(ToAspellSpeller) And
    Assigned(AspellSpellerCheck) And Assigned(AspellSpellerSuggest);
  If Not Result Then
    Begin
      UnloadLibrary(AspLibHandle);
      AspLibHandle := NilHandle;
      NewAspellSpeller := Nil;
    End
  Else
    AspLibPath := FullName;
  Finally LeaveCriticalSection(BindingLock); End;
End;

Function FindAspellLibrary(Out FullName: String): Boolean;
Var
  Names: TStringArray;
  Index: Integer;
Begin
  EnterCriticalSection(BindingLock);
  Try
  Result := False;
  FullName := '';
  If AspLibHandle <> NilHandle Then
    Begin
      FullName := AspLibPath;
      Result := FullName <> '';
      Exit;
    End;
  Names := AspellLibraryCandidates;
  For Index := 0 To High(Names) Do
    If BindAspell(Names[Index]) Then
      Begin
        FullName := AspLibPath;
        Result := True;
        Exit;
      End;
  Finally LeaveCriticalSection(BindingLock); End;
End;

Procedure ListAspellLanguages(List: TStrings);
Var
  Proc: TProcess;
  OutputText, Line: String;
  Lines: TStringList;
  Index: Integer;
Begin
  If Not Assigned(List) Then
    Exit;
  Proc := TProcess.Create(Nil);
  Lines := TStringList.Create;
  Try
    Proc.Executable := 'aspell';
    Proc.Parameters.Add('dump');
    Proc.Parameters.Add('dicts');
    Proc.Options := [poUsePipes, poWaitOnExit, poNoConsole];
    Try
      Proc.Execute;
      OutputText := '';
      SetLength(OutputText, 65536);
      Index := Proc.Output.Read(OutputText[1], Length(OutputText));
      SetLength(OutputText, Index);
    Except
      Exit;
    End;
    Lines.Text := OutputText;
    For Index := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[Index]);
        If (Line <> '') And (List.IndexOf(Line) < 0) Then
          List.Add(Line);
      End;
  Finally
    Lines.Free;
    Proc.Free;
  End;
End;

Constructor TAspellEngine.Create;
Begin
  Inherited Create;
  FLanguage := '';
  FLibraryFileName := '';
  FDictionaryDirectory := '';
  FSpeller := Nil;
End;

Constructor TAspellEngine.Create(Const NewLanguage, NewLibraryFileName, NewDictionaryDirectory: String);
Begin
  Create;
  FLanguage := NewLanguage;
  FLibraryFileName := NewLibraryFileName;
  FDictionaryDirectory := NewDictionaryDirectory;
End;

Function TAspellEngine.EngineKind: TSpellEngineKind;
Begin
  Result := sekAspell;
End;

Function TAspellEngine.Features: TSpellEngineFeatures;
Begin
  Result := [sefSuggest];
End;

Function TAspellEngine.IsReady: Boolean;
Begin
  Result := Assigned(FSpeller);
End;

Function TAspellEngine.Load: Boolean;
Var
  LibName, Lang: String;
  Config, ErrObj: Pointer;
  DashPos: Integer;
Begin
  Result := False;
  Unload;
  FLastError := '';
  LibName := Trim(FLibraryFileName);
  If LibName <> '' Then
    Begin
      If Not BindAspell(LibName) Then
        Begin
          FLastError := 'Unable to load ASpell library ' + LibName +
            '. If a different library is already loaded, restart the IDE to change it.';
          Exit;
        End;
    End
  Else If Not FindAspellLibrary(LibName) Then
    Begin
      FLastError := 'ASpell library not found';
      Exit;
    End;
  FLibraryPath := AspLibPath;
  Config := NewAspellConfig();
  If Not Assigned(Config) Then
    Begin
      FLastError := 'ASpell config could not be created';
      Exit;
    End;
  Try
    AspellConfigReplace(Config, 'encoding', 'utf-8');
    AspellConfigReplace(Config, 'ignore-case', 'true');
    If Trim(FDictionaryDirectory) <> '' Then
      AspellConfigReplace(Config, 'dict-dir', PChar(FDictionaryDirectory));
    Lang := Trim(FLanguage);
    If Lang = '' Then
      Lang := DefaultSpellLanguage;
    DashPos := Pos('.', Lang);
    If DashPos > 0 Then
      Lang := Copy(Lang, 1, DashPos - 1);
    Lang := StringReplace(Lang, '-', '_', [rfReplaceAll]);
    If Lang <> '' Then
      AspellConfigReplace(Config, 'lang', PChar(Lang));
    ErrObj := NewAspellSpeller(Config);
  Finally
    DeleteAspellConfig(Config);
  End;
  If Not Assigned(ErrObj) Then
    Begin
      FLastError := 'ASpell speller could not be created';
      Exit;
    End;
  If Assigned(AspellErrorNumber) And (AspellErrorNumber(ErrObj) <> 0) Then
    Begin
      If Assigned(AspellErrorMessage) Then
        FLastError := String(AspellErrorMessage(ErrObj));
      If FLastError = '' Then
        FLastError := 'ASpell failed to open a dictionary';
      If Assigned(DeleteAspellCanHaveError) Then
        DeleteAspellCanHaveError(ErrObj);
      Exit;
    End;
  FSpeller := ToAspellSpeller(ErrObj);
  If Not Assigned(FSpeller) Then
    Begin
      FLastError := 'ASpell returned no speller';
      If Assigned(DeleteAspellCanHaveError) Then
        DeleteAspellCanHaveError(ErrObj);
      Exit;
    End;
  If Lang <> '' Then
    FResolvedLanguage := Lang
  Else
    FResolvedLanguage := 'default';
  Result := True;
End;

Procedure TAspellEngine.Unload;
Begin
  If Assigned(FSpeller) And Assigned(DeleteAspellSpeller) Then
    DeleteAspellSpeller(FSpeller);
  FSpeller := Nil;
  FResolvedLanguage := '';
End;

Function TAspellEngine.CheckWord(Const WordText: String): Boolean;
Begin
  Result := True;
  If Not Assigned(FSpeller) Then
    Exit;
  Result := AspellSpellerCheck(FSpeller, PChar(WordText), Length(WordText)) <> 0;
End;

Function TAspellEngine.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
Var
  WordList, EnumHandle: Pointer;
  NextWord: PChar;
  Count: Integer;
Begin
  Result := EmptySpellSuggestions;
  If Not Assigned(FSpeller) Or (MaxCount <= 0) Then
    Exit;
  WordList := AspellSpellerSuggest(FSpeller, PChar(WordText), Length(WordText));
  If Not Assigned(WordList) Then
    Exit;
  EnumHandle := AspellWordListElements(WordList);
  If Not Assigned(EnumHandle) Then
    Exit;
  Try
    Count := 0;
    SetLength(Result, MaxCount);
    NextWord := AspellEnumNext(EnumHandle);
    While Assigned(NextWord) And (Count < MaxCount) Do
      Begin
        Result[Count] := String(NextWord);
        Inc(Count);
        NextWord := AspellEnumNext(EnumHandle);
      End;
    SetLength(Result, Count);
  Finally
    If Assigned(DeleteAspellEnum) Then
      DeleteAspellEnum(EnumHandle);
  End;
End;

Procedure TAspellEngine.AddToSession(Const WordText: String);
Begin
  If Not Assigned(FSpeller) Or Not Assigned(AspellAddToSession) Then
    Exit;
  AspellAddToSession(FSpeller, PChar(WordText), Length(WordText));
End;

Initialization
  InitCriticalSection(BindingLock);
Finalization
  DoneCriticalSection(BindingLock);
End.
