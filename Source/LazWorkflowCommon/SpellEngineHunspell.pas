Unit SpellEngineHunspell;

{ Dynload Hunspell backend (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SpellEngine;

Type
  THunspellEngine = Class(TSpellEngine)
  Private
    FLanguage: String;
    FLibraryFileName: String;
    FDictionaryDirectory: String;
    FHandle: Pointer;
    FEncoding: String;
    Function ConvertWord(Const WordText: String): RawByteString;
    Function ConvertFromDict(Const DictText: PChar): String;
    Function OpenDictionary(Const AffFile, DicFile, LanguageCode: String): Boolean;
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

Function FindHunspellLibrary(Out FullName: String): Boolean;
Function HunspellDictionaryDirectories: TStringArray;
Function FindHunspellDictionary(Const Language, DictionaryDirectory: String; Out AffFile, DicFile, LanguageCode: String): Boolean;
Procedure ListHunspellLanguages(List: TStrings; Const DictionaryDirectory: String = '');
/// Locate a Hunspell DLL and aff/dic directories on Windows, preferring LibreOffice.
/// Other platforms return false. True means both a library file and a dictionary directory were found.
Function ConfigureWindowsHunspell(Out LibraryFileName: String; Out DictionaryDirectories: TStringArray): Boolean;
Function HunspellDiscoveryNote: String;
Procedure ResetHunspellDiscovery;

Implementation

Uses
  DynLibs, LazFileUtils, LazUTF8, LConvEncoding, SpellCheckerOptions, WorkflowLog, SpellHunspellWindows,
  DirectoryListing;

Type
  THunspellCreate = Function(AffPath, DicPath: PChar): Pointer; CDecl;
  THunspellDestroy = Procedure(SpellHandle: Pointer); CDecl;
  THunspellSpell = Function(SpellHandle: Pointer; WordText: PChar): Integer; CDecl;
  THunspellSuggest = Function(SpellHandle: Pointer; Var Slst: PPChar; WordText: PChar): Integer; CDecl;
  THunspellFreeList = Procedure(SpellHandle: Pointer; Var Slst: PPChar; Count: Integer); CDecl;
  THunspellAdd = Function(SpellHandle: Pointer; WordText: PChar): Integer; CDecl;
  THunspellGetDicEncoding = Function(SpellHandle: Pointer): PChar; CDecl;

Var
  HunLibHandle: TLibHandle = NilHandle;
  HunLibPath: String = '';
  HunspellCreate: THunspellCreate = Nil;
  HunspellDestroy: THunspellDestroy = Nil;
  HunspellSpellFn: THunspellSpell = Nil;
  HunspellSuggest: THunspellSuggest = Nil;
  HunspellFreeList: THunspellFreeList = Nil;
  HunspellAddFn: THunspellAdd = Nil;
  HunspellGetDicEncoding: THunspellGetDicEncoding = Nil;

Function HunspellLibraryCandidates: TStringArray;
Begin
  Result := Nil;
  {$IFDEF WINDOWS}
  SetLength(Result, 4);
  Result[0] := 'libhunspell-1.7.dll';
  Result[1] := 'libhunspell.dll';
  Result[2] := 'hunspell.dll';
  Result[3] := 'libhunspell-1.6.dll';
  {$ELSE}
    {$IFDEF DARWIN}
    SetLength(Result, 5);
    Result[0] := 'libhunspell-1.7.dylib';
    Result[1] := 'libhunspell-1.6.dylib';
    Result[2] := 'libhunspell.dylib';
    Result[3] := 'libhunspell-1.7.0.dylib';
    Result[4] := 'libhunspell-1.6.0.dylib';
    {$ELSE}
    SetLength(Result, 4);
    Result[0] := 'libhunspell-1.7.so.0';
    Result[1] := 'libhunspell-1.6.so.0';
    Result[2] := 'libhunspell.so.0';
    Result[3] := 'libhunspell.so';
    {$ENDIF}
  {$ENDIF}
End;

Var
  BindingLock: TRTLCriticalSection;

Procedure AppendUniqueDirectory(Var Dirs: TStringArray; Const Dir: String);
Var
  Index: Integer;
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Dir);
  If (Clean = '') Or (Not DirectoryExistsUTF8(Clean)) Then
    Exit;
  For Index := 0 To High(Dirs) Do
    If CompareFilenames(Dirs[Index], Clean) = 0 Then
      Exit;
  SetLength(Dirs, Length(Dirs) + 1);
  Dirs[High(Dirs)] := Clean;
End;

Procedure AppendConfiguredDictionaries(Var Dirs: TStringArray);
Var
  Configured: TStringArray;
  Index: Integer;
Begin
  Configured := WindowsHunspellDictionaryDirectories;
  For Index := 0 To High(Configured) Do
    AppendUniqueDirectory(Dirs, Configured[Index]);
End;

Function ConfigureWindowsHunspell(Out LibraryFileName: String; Out DictionaryDirectories: TStringArray): Boolean;
Var
  Libraries: TStringArray;
Begin
  Libraries := WindowsHunspellLibraryFiles;
  DictionaryDirectories := WindowsHunspellDictionaryDirectories;
  LibraryFileName := '';
  If Length(Libraries) > 0 Then
    LibraryFileName := Libraries[0];
  Result := (LibraryFileName <> '') And (Length(DictionaryDirectories) > 0);
End;

Function HunspellDiscoveryNote: String;
Begin
  Result := WindowsHunspellDiscoveryNote;
End;

Procedure ResetHunspellDiscovery;
Begin
  ResetWindowsHunspellDiscovery;
End;

Function LoadSpellLibrary(Const FileName: String): TLibHandle;
Var
  ErrorText: String;
Begin
  { A full path on Windows must not use the default search order. DynLibs loads every other name. }
  If TryLoadHunspellAlteredSearch(FileName, Result, ErrorText) Then
    Begin
      If (Result = NilHandle) And (ErrorText <> '') And Assigned(WorkflowLogger) Then
        WorkflowLogger.Warning('Spell', ErrorText);
      Exit;
    End;
  Result := LoadLibrary(FileName);
End;

Function BindHunspell(Const FullName: String): Boolean;
Begin
  EnterCriticalSection(BindingLock);
  Try
  Result := False;
  If HunLibHandle <> NilHandle Then
    Begin
      If FullName <> HunLibPath Then Exit;
      Result := Assigned(HunspellCreate) And Assigned(HunspellSpellFn);
      Exit;
    End;
  HunLibHandle := LoadSpellLibrary(FullName);
  If HunLibHandle = NilHandle Then
    Exit;
  Pointer(HunspellCreate) := GetProcedureAddress(HunLibHandle, 'Hunspell_create');
  Pointer(HunspellDestroy) := GetProcedureAddress(HunLibHandle, 'Hunspell_destroy');
  Pointer(HunspellSpellFn) := GetProcedureAddress(HunLibHandle, 'Hunspell_spell');
  Pointer(HunspellSuggest) := GetProcedureAddress(HunLibHandle, 'Hunspell_suggest');
  Pointer(HunspellFreeList) := GetProcedureAddress(HunLibHandle, 'Hunspell_free_list');
  Pointer(HunspellAddFn) := GetProcedureAddress(HunLibHandle, 'Hunspell_add');
  Pointer(HunspellGetDicEncoding) := GetProcedureAddress(HunLibHandle, 'Hunspell_get_dic_encoding');
  Result := Assigned(HunspellCreate) And Assigned(HunspellDestroy) And Assigned(HunspellSpellFn) And
    Assigned(HunspellSuggest) And Assigned(HunspellFreeList);
  If Not Result Then
    Begin
      UnloadLibrary(HunLibHandle);
      HunLibHandle := NilHandle;
      HunspellCreate := Nil;
    End
  Else
    HunLibPath := FullName;
  Finally LeaveCriticalSection(BindingLock); End;
End;

Function FindHunspellLibrary(Out FullName: String): Boolean;
Var
  Names, Configured: TStringArray;
  Index: Integer;
  {$IFDEF DARWIN}
  Prefixes: Array[0..3] Of String;
  PrefixIndex: Integer;
  {$ENDIF}
Begin
  EnterCriticalSection(BindingLock);
  Try
  Result := False;
  FullName := '';
  If HunLibHandle <> NilHandle Then
    Begin
      FullName := HunLibPath;
      Result := FullName <> '';
      Exit;
    End;
  Names := HunspellLibraryCandidates;
  For Index := 0 To High(Names) Do
    If BindHunspell(Names[Index]) Then
      Begin
        FullName := HunLibPath;
        Result := True;
        Exit;
      End;
  Configured := WindowsHunspellLibraryFiles;
  For Index := 0 To High(Configured) Do
    If BindHunspell(Configured[Index]) Then
      Begin
        FullName := HunLibPath;
        Result := True;
        Exit;
      End;
  {$IFDEF DARWIN}
  Prefixes[0] := '/opt/homebrew/lib/';
  Prefixes[1] := '/usr/local/lib/';
  Prefixes[2] := '/opt/local/lib/';
  Prefixes[3] := '/usr/lib/';
  For PrefixIndex := 0 To High(Prefixes) Do
    For Index := 0 To High(Names) Do
      If BindHunspell(Prefixes[PrefixIndex] + Names[Index]) Then
        Begin
          FullName := HunLibPath;
          Result := True;
          Exit;
        End;
  {$ENDIF}
  Finally LeaveCriticalSection(BindingLock); End;
End;

Function HunspellDictionaryDirectories: TStringArray;
Begin
  Result := Nil;
  SetLength(Result, 0);
  {$IFDEF UNIX}
  AppendUniqueDirectory(Result, '/usr/share/hunspell');
  AppendUniqueDirectory(Result, '/usr/share/myspell');
  AppendUniqueDirectory(Result, '/usr/share/myspell/dicts');
  AppendUniqueDirectory(Result, '/usr/local/share/hunspell');
  AppendUniqueDirectory(Result, GetUserDir + '.openoffice.org/3/user/wordbook');
  {$ENDIF}
  AppendConfiguredDictionaries(Result);
  {$IFDEF DARWIN}
  AppendUniqueDirectory(Result, '/Library/Spelling');
  AppendUniqueDirectory(Result, GetUserDir + 'Library/Spelling');
  AppendUniqueDirectory(Result, '/Applications/LibreOffice.app/Contents/Resources/extensions');
  {$ENDIF}
End;

Function HunspellSearchDirectories(Const DictionaryDirectory: String): TStringArray;
{$IFDEF WINDOWS}
Var
  Index, Limit: Integer;
  HasPair: Boolean;
{$ENDIF}
Begin
  Result := Nil;
  If Trim(DictionaryDirectory) <> '' Then
    Begin
      SetLength(Result, 1);
      Result[0] := ExcludeTrailingPathDelimiter(Trim(DictionaryDirectory));
    End
  Else
    Result := HunspellDictionaryDirectories;
  {$IFDEF WINDOWS}
  If Trim(DictionaryDirectory) = '' Then
    Exit;
  Limit := Length(Result);
  Index := 0;
  While Index < Limit Do
    Begin
      AppendWindowsChildDictionaries(Result, Result[Index]);
      Inc(Index);
    End;
  HasPair := False;
  For Index := 0 To High(Result) Do
    If WindowsDirectoryHasAffDicPair(Result[Index]) Then
      HasPair := True;
  If Not HasPair Then
    AppendConfiguredDictionaries(Result);
  {$ENDIF}
End;

Procedure ListHunspellLanguages(List: TStrings; Const DictionaryDirectory: String);
Var
  Dirs: TStringArray;
  DirIndex, InfoResult: Integer;
  Info: TDirectoryScan;
  DicName, AffName, Code: String;
Begin
  If Not Assigned(List) Then
    Exit;
  Dirs := HunspellSearchDirectories(DictionaryDirectory);
  For DirIndex := 0 To High(Dirs) Do
    Begin
      InfoResult := StartDirectoryScan(IncludeTrailingPathDelimiter(Dirs[DirIndex]) + '*.dic', faAnyFile, Info);
      Try
        While InfoResult = 0 Do
          Begin
            If (Info.Attr And faDirectory) = 0 Then
              Begin
                DicName := IncludeTrailingPathDelimiter(Dirs[DirIndex]) + Info.Name;
                AffName := ChangeFileExt(DicName, '.aff');
                If FileExistsUTF8(AffName) Then
                  Begin
                    Code := ChangeFileExt(Info.Name, '');
                    If (Code <> '') And (List.IndexOf(Code) < 0) Then
                      List.Add(Code);
                  End;
              End;
            InfoResult := AdvanceDirectoryScan(Info);
          End;
      Finally
        CloseDirectoryScan(Info);
      End;
    End;
End;

Function NormalizeLanguageTag(Const Value: String): String;
Var
  Lang: String;
  DashPos: Integer;
Begin
  Lang := Trim(Value);
  DashPos := Pos('.', Lang);
  If DashPos > 0 Then
    Lang := Copy(Lang, 1, DashPos - 1);
  DashPos := Pos('@', Lang);
  If DashPos > 0 Then
    Lang := Copy(Lang, 1, DashPos - 1);
  Lang := StringReplace(Lang, '-', '_', [rfReplaceAll]);
  Result := Lang;
End;

Function FindHunspellDictionary(Const Language, DictionaryDirectory: String; Out AffFile, DicFile, LanguageCode: String): Boolean;
Var
  Wanted, Dirs: TStringArray;
  Lang, Dir, Candidate: String;
  Index, DirIndex: Integer;
  Info: TDirectoryScan;
Begin
  Result := False;
  AffFile := '';
  DicFile := '';
  LanguageCode := '';
  Lang := NormalizeLanguageTag(Language);
  Wanted := Nil;
  SetLength(Wanted, 0);
  If Lang <> '' Then
    Begin
      SetLength(Wanted, Length(Wanted) + 1);
      Wanted[High(Wanted)] := Lang;
      If Pos('_', Lang) > 0 Then
        Begin
          SetLength(Wanted, Length(Wanted) + 1);
          Wanted[High(Wanted)] := Copy(Lang, 1, Pos('_', Lang) - 1);
        End;
    End
  Else
    Begin
      SetLength(Wanted, 3);
      Wanted[0] := 'en_GB';
      Wanted[1] := 'en_US';
      Wanted[2] := 'en';
    End;
  Dirs := HunspellSearchDirectories(DictionaryDirectory);
  For Index := 0 To High(Wanted) Do
    For DirIndex := 0 To High(Dirs) Do
      Begin
        Dir := IncludeTrailingPathDelimiter(Dirs[DirIndex]);
        Candidate := Dir + Wanted[Index] + '.dic';
        If FileExistsUTF8(Candidate) And FileExistsUTF8(Dir + Wanted[Index] + '.aff') Then
          Begin
            DicFile := Candidate;
            AffFile := Dir + Wanted[Index] + '.aff';
            LanguageCode := Wanted[Index];
            Result := True;
            Exit;
          End;
      End;
  { Short tags such as de should match de_DE / de_AT / de_CH. }
  If (Lang <> '') And (Pos('_', Lang) = 0) Then
    For DirIndex := 0 To High(Dirs) Do
      Begin
        Candidate := IncludeTrailingPathDelimiter(Dirs[DirIndex]);
        If StartDirectoryScan(Candidate + Lang + '_*.dic', faAnyFile, Info) = 0 Then
          Try
            Repeat
              If (Info.Attr And faDirectory) = 0 Then
                Begin
                  LanguageCode := ChangeFileExt(Info.Name, '');
                  If FileExistsUTF8(Candidate + LanguageCode + '.aff') Then
                    Begin
                      DicFile := Candidate + LanguageCode + '.dic';
                      AffFile := Candidate + LanguageCode + '.aff';
                      Result := True;
                      Exit;
                    End;
                End;
            Until AdvanceDirectoryScan(Info) <> 0;
          Finally
            CloseDirectoryScan(Info);
          End;
      End;
  If Lang <> '' Then
    Exit;
  { Last resort when no language was requested: first aff/dic pair in the search path. }
  For DirIndex := 0 To High(Dirs) Do
    Begin
      Candidate := IncludeTrailingPathDelimiter(Dirs[DirIndex]);
      If StartDirectoryScan(Candidate + '*.dic', faAnyFile, Info) = 0 Then
        Try
          Repeat
            If (Info.Attr And faDirectory) = 0 Then
              Begin
                LanguageCode := ChangeFileExt(Info.Name, '');
                If FileExistsUTF8(Candidate + LanguageCode + '.aff') Then
                  Begin
                    DicFile := Candidate + LanguageCode + '.dic';
                    AffFile := Candidate + LanguageCode + '.aff';
                    Result := True;
                    Exit;
                  End;
              End;
          Until AdvanceDirectoryScan(Info) <> 0;
        Finally
          CloseDirectoryScan(Info);
        End;
    End;
End;

Constructor THunspellEngine.Create;
Begin
  Inherited Create;
  FLanguage := '';
  FLibraryFileName := '';
  FDictionaryDirectory := '';
  FHandle := Nil;
  FEncoding := 'UTF-8';
End;

Constructor THunspellEngine.Create(Const NewLanguage, NewLibraryFileName, NewDictionaryDirectory: String);
Begin
  Create;
  FLanguage := NewLanguage;
  FLibraryFileName := NewLibraryFileName;
  FDictionaryDirectory := NewDictionaryDirectory;
End;

Function THunspellEngine.EngineKind: TSpellEngineKind;
Begin
  Result := sekHunspell;
End;

Function THunspellEngine.Features: TSpellEngineFeatures;
Begin
  Result := [sefSuggest];
End;

Function THunspellEngine.IsReady: Boolean;
Begin
  Result := Assigned(FHandle);
End;

Function THunspellEngine.ConvertWord(Const WordText: String): RawByteString;
Begin
  If (FEncoding = '') Or SameText(FEncoding, 'UTF-8') Or SameText(FEncoding, 'UTF8') Then
    Result := WordText
  Else
    Result := ConvertEncoding(WordText, EncodingUTF8, FEncoding);
End;

Function THunspellEngine.ConvertFromDict(Const DictText: PChar): String;
Begin
  If DictText = Nil Then
    Result := ''
  Else If (FEncoding = '') Or SameText(FEncoding, 'UTF-8') Or SameText(FEncoding, 'UTF8') Then
    Result := String(DictText)
  Else
    Result := ConvertEncoding(String(DictText), FEncoding, EncodingUTF8);
End;

Function THunspellEngine.OpenDictionary(Const AffFile, DicFile, LanguageCode: String): Boolean;
Var
  Enc: PChar;
Begin
  Result := False;
  FHandle := HunspellCreate(PChar(AffFile), PChar(DicFile));
  If Not Assigned(FHandle) Then
    Begin
      FLastError := 'Hunspell could not open ' + DicFile;
      Exit;
    End;
  FResolvedLanguage := LanguageCode;
  FEncoding := 'UTF-8';
  If Assigned(HunspellGetDicEncoding) Then
    Begin
      Enc := HunspellGetDicEncoding(FHandle);
      If Enc <> Nil Then
        FEncoding := String(Enc);
    End;
  Result := True;
End;

Function THunspellEngine.Load: Boolean;
Var
  LibName, AffFile, DicFile, LanguageCode: String;
Begin
  Result := False;
  Unload;
  FLastError := '';
  LibName := Trim(FLibraryFileName);
  If LibName <> '' Then
    Begin
      If Not BindHunspell(LibName) Then
        Begin
          FLastError := 'Unable to load Hunspell library ' + LibName +
            '. If a different library is already loaded, restart the IDE to change it.';
          Exit;
        End;
    End
  Else If Not FindHunspellLibrary(LibName) Then
    Begin
      FLastError := 'Hunspell library not found';
      Exit;
    End;
  FLibraryPath := HunLibPath;
  If Trim(FLanguage) = '' Then
    FLanguage := DefaultSpellLanguage;
  If Not FindHunspellDictionary(FLanguage, FDictionaryDirectory, AffFile, DicFile, LanguageCode) Then
    Begin
      FLastError := 'No Hunspell dictionary found';
      Exit;
    End;
  Result := OpenDictionary(AffFile, DicFile, LanguageCode);
End;

Procedure THunspellEngine.Unload;
Begin
  If Assigned(FHandle) And Assigned(HunspellDestroy) Then
    HunspellDestroy(FHandle);
  FHandle := Nil;
  FResolvedLanguage := '';
End;

Function THunspellEngine.CheckWord(Const WordText: String): Boolean;
Var
  Converted: RawByteString;
Begin
  Result := True;
  If Not Assigned(FHandle) Then
    Exit;
  Converted := ConvertWord(WordText);
  Result := HunspellSpellFn(FHandle, PChar(Converted)) <> 0;
End;

Function THunspellEngine.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
Var
  Converted: RawByteString;
  Slst: PPChar;
  Count, Index, Limit: Integer;
  Walk: PPChar;
Begin
  Result := EmptySpellSuggestions;
  If Not Assigned(FHandle) Or (MaxCount <= 0) Then
    Exit;
  Converted := ConvertWord(WordText);
  Slst := Nil;
  Count := HunspellSuggest(FHandle, Slst, PChar(Converted));
  If (Count <= 0) Or (Slst = Nil) Then
    Exit;
  Try
    Limit := Count;
    If Limit > MaxCount Then
      Limit := MaxCount;
    SetLength(Result, Limit);
    Walk := Slst;
    For Index := 0 To Limit - 1 Do
      Begin
        Result[Index] := ConvertFromDict(Walk^);
        Inc(Walk);
      End;
  Finally
    HunspellFreeList(FHandle, Slst, Count);
  End;
End;

Procedure THunspellEngine.AddToSession(Const WordText: String);
Var
  Converted: RawByteString;
Begin
  If Not Assigned(FHandle) Or Not Assigned(HunspellAddFn) Then
    Exit;
  Converted := ConvertWord(WordText);
  HunspellAddFn(FHandle, PChar(Converted));
End;

Initialization
  InitCriticalSection(BindingLock);
Finalization
  DoneCriticalSection(BindingLock);
End.
