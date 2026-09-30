Unit SpellEngineWindows;

{ Windows spell-checking API backend (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SpellEngine;

Type
  TWindowsSpellEngine = Class(TSpellEngine)
  Private
    FLanguage: String;
    FChecker: IInterface;
    FCheckerThread: TThreadID;
    FComOwned: Boolean;
    FAvailable: Boolean;
    Function EnsureChecker: Boolean;
    Procedure ReleaseChecker;
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
  End;

Function WindowsSpellAvailable(Out LanguageCode: String): Boolean;
Procedure ListWindowsSpellLanguages(List: TStrings);

Implementation

Uses
  {$IFDEF WINDOWS}
  Windows, ActiveX,
  {$ENDIF}
  LazUTF8;

{$IFDEF WINDOWS}
Const
  ComChangedMode = HRESULT($80010106);
  SpellFactoryId: TGUID = '{7AB36653-1796-484B-BDFA-E74F1DB7C1DC}';
  SpellFactoryIid: TGUID = '{8E018A9D-2415-4677-BF08-794EA61F94BB}';

Type
  ISpellStringList = Interface(IUnknown)
    ['{00000101-0000-0000-C000-000000000046}']
    Function Next(Celt: LongWord; Out Item: PWideChar; Out Fetched: LongWord): HRESULT; StdCall;
    Function Skip(Celt: LongWord): HRESULT; StdCall;
    Function Reset: HRESULT; StdCall;
    Function Clone(Out Enum: ISpellStringList): HRESULT; StdCall;
  End;

  ISpellingError = Interface(IUnknown)
    ['{B7C82D61-FBE8-4B47-9B27-6C0D2E0DE0A3}']
  End;

  IEnumSpellingError = Interface(IUnknown)
    ['{803E3BD4-2828-4410-8290-418D1D73C762}']
    Function Next(Out Error: ISpellingError): HRESULT; StdCall;
  End;

  ISpellChecker = Interface(IUnknown)
    ['{B6FD0B71-E2BC-4653-8D05-F197E412770B}']
    Function GetLanguageTag(Out Value: PWideChar): HRESULT; StdCall;
    Function Check(Text: PWideChar; Out Errors: IEnumSpellingError): HRESULT; StdCall;
    Function Suggest(Word: PWideChar; Out Suggestions: ISpellStringList): HRESULT; StdCall;
    Function Add(Word: PWideChar): HRESULT; StdCall;
    Function Ignore(Word: PWideChar): HRESULT; StdCall;
  End;

  ISpellCheckerFactory = Interface(IUnknown)
    ['{8E018A9D-2415-4677-BF08-794EA61F94BB}']
    Function GetSupportedLanguages(Out Value: ISpellStringList): HRESULT; StdCall;
    Function IsSupported(LanguageTag: PWideChar; Out Value: BOOL): HRESULT; StdCall;
    Function CreateSpellChecker(LanguageTag: PWideChar; Out Checker: ISpellChecker): HRESULT; StdCall;
  End;

Function GetUserDefaultLocaleName(LocaleName: PWideChar; NameSize: Integer): Integer; StdCall; External 'kernel32';

Function ComOk(Hr: HRESULT): Boolean;
Begin
  Result := Hr >= 0;
End;

Function StartCom(Out Hr: HRESULT): Boolean;
Begin
  Hr := CoInitializeEx(Nil, COINIT_APARTMENTTHREADED);
  Result := (Hr = S_OK) Or (Hr = S_FALSE) Or (Hr = ComChangedMode);
End;

Procedure BalanceExtraComInit(Hr: HRESULT);
Begin
  { S_FALSE incremented an existing count. Put that increment back. }
  If Hr = S_FALSE Then
    CoUninitialize;
End;

Function TagFromLanguage(Const Language: String): UnicodeString;
Begin
  Result := UTF8Decode(StringReplace(Trim(Language), '_', '-', [rfReplaceAll]));
End;

Function LanguageFromTag(Const Tag: UnicodeString): String;
Begin
  Result := StringReplace(UTF8Encode(Tag), '-', '_', [rfReplaceAll]);
End;

Function FactorySupports(Factory: ISpellCheckerFactory; Const Tag: UnicodeString): Boolean;
Var
  Supported: BOOL;
Begin
  Result := False;
  If (Factory = Nil) Or (Tag = '') Then
    Exit;
  Supported := False;
  If ComOk(Factory.IsSupported(PWideChar(Tag), Supported)) Then
    Result := Supported;
End;

Function ChooseSpellTag(Factory: ISpellCheckerFactory; Const Requested: String): UnicodeString;
Var
  RequestedTag, UserTag, ParentTag: UnicodeString;
  UserName: Array[0..84] Of WideChar;
  Languages: ISpellStringList;
  Item: PWideChar;
  Fetched: LongWord;
  CutPos: Integer;
Begin
  Result := '';
  If Factory = Nil Then
    Exit;
  RequestedTag := TagFromLanguage(Requested);
  If FactorySupports(Factory, RequestedTag) Then
    Begin
      Result := RequestedTag;
      Exit;
    End;
  UserTag := '';
  If GetUserDefaultLocaleName(@UserName[0], 85) > 0 Then
    UserTag := UnicodeString(PWideChar(@UserName[0]));
  If FactorySupports(Factory, UserTag) Then
    Begin
      Result := UserTag;
      Exit;
    End;
  If FactorySupports(Factory, 'en-GB') Then
    Begin
      Result := 'en-GB';
      Exit;
    End;
  If FactorySupports(Factory, 'en-US') Then
    Begin
      Result := 'en-US';
      Exit;
    End;
  If FactorySupports(Factory, 'en') Then
    Begin
      Result := 'en';
      Exit;
    End;
  CutPos := Pos('-', String(RequestedTag));
  If CutPos > 1 Then
    Begin
      ParentTag := Copy(RequestedTag, 1, CutPos - 1);
      If FactorySupports(Factory, ParentTag) Then
        Begin
          Result := ParentTag;
          Exit;
        End;
    End;
  Item := Nil;
  Fetched := 0;
  If ComOk(Factory.GetSupportedLanguages(Languages)) And Assigned(Languages) Then
    If Languages.Next(1, Item, Fetched) = S_OK Then
      Begin
        Result := UnicodeString(Item);
        CoTaskMemFree(Item);
      End;
End;

Function OpenFactory(Out Factory: ISpellCheckerFactory; Out ErrorText: String): Boolean;
Var
  Hr: HRESULT;
Begin
  Result := False;
  Factory := Nil;
  ErrorText := '';
  Hr := CoCreateInstance(SpellFactoryId, Nil, CLSCTX_INPROC_SERVER, SpellFactoryIid, Factory);
  If (Not ComOk(Hr)) Or (Factory = Nil) Then
    Begin
      ErrorText := 'Windows spell checker is not available';
      Factory := Nil;
      Exit;
    End;
  Result := True;
End;

Function ProbeWindowsSpell(Const Requested: String; Out LanguageCode, ErrorText: String): Boolean;
Var
  Hr: HRESULT;
  Factory: ISpellCheckerFactory;
  Checker: ISpellChecker;
  Tag: UnicodeString;
Begin
  Result := False;
  LanguageCode := '';
  ErrorText := '';
  If Not StartCom(Hr) Then
    Begin
      ErrorText := 'COM is not available';
      Exit;
    End;
  Try
    If Not OpenFactory(Factory, ErrorText) Then
      Exit;
    Tag := ChooseSpellTag(Factory, Requested);
    If Tag = '' Then
      Begin
        ErrorText := 'Windows spell checker has no supported language. Add one in Windows language settings.';
        Exit;
      End;
    Checker := Nil;
    If (Not ComOk(Factory.CreateSpellChecker(PWideChar(Tag), Checker))) Or (Checker = Nil) Then
      Begin
        ErrorText := 'Windows spell checker could not open ' + LanguageFromTag(Tag);
        Exit;
      End;
    LanguageCode := LanguageFromTag(Tag);
    Result := True;
  Finally
    Checker := Nil;
    Factory := Nil;
    BalanceExtraComInit(Hr);
    If Hr = S_OK Then
      CoUninitialize;
  End;
End;

Procedure CollectWindowsLanguages(List: TStrings);
Var
  Hr: HRESULT;
  Factory: ISpellCheckerFactory;
  Languages: ISpellStringList;
  Item: PWideChar;
  Fetched: LongWord;
  Code: String;
Begin
  If Not Assigned(List) Then
    Exit;
  If Not StartCom(Hr) Then
    Exit;
  Try
    If Not OpenFactory(Factory, Code) Then
      Exit;
    If Not ComOk(Factory.GetSupportedLanguages(Languages)) Or (Languages = Nil) Then
      Exit;
    Repeat
      Item := Nil;
      Fetched := 0;
      If Languages.Next(1, Item, Fetched) <> S_OK Then
        Break;
      Code := LanguageFromTag(UnicodeString(Item));
      CoTaskMemFree(Item);
      If (Code <> '') And (List.IndexOf(Code) < 0) Then
        List.Add(Code);
    Until False;
  Finally
    Languages := Nil;
    Factory := Nil;
    BalanceExtraComInit(Hr);
    If Hr = S_OK Then
      CoUninitialize;
  End;
End;
{$ENDIF}

Function WindowsSpellAvailable(Out LanguageCode: String): Boolean;
{$IFDEF WINDOWS}
Var
  ErrorText: String;
{$ENDIF}
Begin
  LanguageCode := '';
  {$IFDEF WINDOWS}
  Result := ProbeWindowsSpell('', LanguageCode, ErrorText);
  {$ELSE}
  Result := False;
  {$ENDIF}
End;

Procedure ListWindowsSpellLanguages(List: TStrings);
Begin
  {$IFDEF WINDOWS}
  CollectWindowsLanguages(List);
  {$ELSE}
  If Assigned(List) Then
    List.Clear;
  {$ENDIF}
End;

Constructor TWindowsSpellEngine.Create;
Begin
  Inherited Create;
  FLanguage := '';
  FChecker := Nil;
  FCheckerThread := 0;
  FComOwned := False;
  FAvailable := False;
End;

{$PUSH}{$HINTS OFF}
Constructor TWindowsSpellEngine.Create(Const NewLanguage, NewLibraryFileName, NewDictionaryDirectory: String);
Begin
  Create;
  FLanguage := NewLanguage;
End;
{$POP}

Procedure TWindowsSpellEngine.ReleaseChecker;
Begin
  FChecker := Nil;
  {$IFDEF WINDOWS}
  If FComOwned And (FCheckerThread = GetCurrentThreadId) Then
    Begin
      CoUninitialize;
      FComOwned := False;
    End;
  {$ENDIF}
  FCheckerThread := 0;
End;

Function TWindowsSpellEngine.EnsureChecker: Boolean;
{$IFDEF WINDOWS}
Var
  Hr: HRESULT;
  Factory: ISpellCheckerFactory;
  Checker: ISpellChecker;
  Tag: UnicodeString;
  ErrorText: String;
{$ENDIF}
Begin
  Result := FAvailable And (FChecker <> Nil) And (FCheckerThread = GetCurrentThreadId);
  If Result Then
    Exit;
  ReleaseChecker;
  Result := False;
  If Not FAvailable Then
    Exit;
  {$IFDEF WINDOWS}
  If Not StartCom(Hr) Then
    Exit;
  If Hr = S_OK Then
    FComOwned := True
  Else
    BalanceExtraComInit(Hr);
  If Not OpenFactory(Factory, ErrorText) Then
    Exit;
  Tag := ChooseSpellTag(Factory, FLanguage);
  If Tag = '' Then
    Tag := TagFromLanguage(FResolvedLanguage);
  If (Tag = '') Or (Not ComOk(Factory.CreateSpellChecker(PWideChar(Tag), Checker))) Or (Checker = Nil) Then
    Exit;
  FChecker := Checker;
  FCheckerThread := GetCurrentThreadId;
  Result := True;
  {$ENDIF}
End;

Function TWindowsSpellEngine.Load: Boolean;
Var
  LanguageCode, ErrorText: String;
Begin
  Unload;
  FLastError := '';
  {$IFDEF WINDOWS}
  Result := ProbeWindowsSpell(FLanguage, LanguageCode, ErrorText);
  If Result Then
    Begin
      FResolvedLanguage := LanguageCode;
      FLibraryPath := 'Windows';
      FAvailable := True;
    End
  Else
    Begin
      FLastError := ErrorText;
      FAvailable := False;
    End;
  {$ELSE}
  LanguageCode := '';
  FLastError := 'Windows spell checker is only available on Windows';
  FAvailable := False;
  Result := False;
  {$ENDIF}
End;

Procedure TWindowsSpellEngine.Unload;
Begin
  ReleaseChecker;
  FAvailable := False;
  FResolvedLanguage := '';
  FLibraryPath := '';
End;

Function TWindowsSpellEngine.IsReady: Boolean;
Begin
  Result := FAvailable;
End;

Function TWindowsSpellEngine.CheckWord(Const WordText: String): Boolean;
{$IFDEF WINDOWS}
Var
  Checker: ISpellChecker;
  Errors: IEnumSpellingError;
  ErrorItem: ISpellingError;
  Wide: UnicodeString;
{$ENDIF}
Begin
  Result := True;
  If Trim(WordText) = '' Then
    Exit;
  If Not EnsureChecker Then
    Exit;
  {$IFDEF WINDOWS}
  Checker := FChecker As ISpellChecker;
  Wide := UTF8Decode(WordText);
  Errors := Nil;
  ErrorItem := Nil;
  If Not ComOk(Checker.Check(PWideChar(Wide), Errors)) Or (Errors = Nil) Then
    Exit;
  { S_OK means a spelling error. S_FALSE means the word is correct. }
  Result := Errors.Next(ErrorItem) <> S_OK;
  {$ENDIF}
End;

Function TWindowsSpellEngine.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
{$IFDEF WINDOWS}
Var
  Checker: ISpellChecker;
  Suggestions: ISpellStringList;
  Item: PWideChar;
  Fetched: LongWord;
  Wide: UnicodeString;
{$ENDIF}
Begin
  Result := EmptySpellSuggestions;
  If (Trim(WordText) = '') Or (MaxCount <= 0) Or (Not EnsureChecker) Then
    Exit;
  {$IFDEF WINDOWS}
  Checker := FChecker As ISpellChecker;
  Wide := UTF8Decode(WordText);
  Suggestions := Nil;
  If Not ComOk(Checker.Suggest(PWideChar(Wide), Suggestions)) Or (Suggestions = Nil) Then
    Exit;
  While Length(Result) < MaxCount Do
    Begin
      Item := Nil;
      Fetched := 0;
      If Suggestions.Next(1, Item, Fetched) <> S_OK Then
        Break;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := UTF8Encode(UnicodeString(Item));
      CoTaskMemFree(Item);
    End;
  {$ENDIF}
End;

Procedure TWindowsSpellEngine.AddToSession(Const WordText: String);
{$IFDEF WINDOWS}
Var
  Checker: ISpellChecker;
  Wide: UnicodeString;
{$ENDIF}
Begin
  If (Trim(WordText) = '') Or (Not EnsureChecker) Then
    Exit;
  {$IFDEF WINDOWS}
  Checker := FChecker As ISpellChecker;
  Wide := UTF8Decode(WordText);
  Checker.Ignore(PWideChar(Wide));
  {$ENDIF}
End;

Function TWindowsSpellEngine.Features: TSpellEngineFeatures;
Begin
  Result := [sefSuggest];
End;

Function TWindowsSpellEngine.EngineKind: TSpellEngineKind;
Begin
  Result := sekWindows;
End;

End.
