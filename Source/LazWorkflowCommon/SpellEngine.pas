Unit SpellEngine;

{ Abstract spell-check engine (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TSpellEngineKind = (sekNone, sekAuto, sekHunspell, sekAspell);

  TSpellEngineFeature = (sefSuggest);
  TSpellEngineFeatures = Set Of TSpellEngineFeature;

  TSpellStringArray = Array Of String;

  { One loaded backend. Personal words live in TSpellCheckerConfig, not here. }
  TSpellEngine = Class
  Protected
    FLastError: String;
    FResolvedLanguage: String;
    FLibraryPath: String;
  Public
    Constructor Create; Virtual;
    Destructor Destroy; Override;
    Function Load: Boolean; Virtual; Abstract;
    Procedure Unload; Virtual; Abstract;
    Function IsReady: Boolean; Virtual; Abstract;
    Function CheckWord(Const WordText: String): Boolean; Virtual; Abstract;
    Function GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray; Virtual; Abstract;
    Procedure AddToSession(Const WordText: String); Virtual;
    Function Features: TSpellEngineFeatures; Virtual;
    Function EngineKind: TSpellEngineKind; Virtual; Abstract;
    Property LastError: String Read FLastError;
    Property ResolvedLanguage: String Read FResolvedLanguage;
    Property LibraryPath: String Read FLibraryPath;
  End;

  TSpellEngineClass = Class Of TSpellEngine;

Function SpellEngineKindToText(Kind: TSpellEngineKind): String;
Function TextToSpellEngineKind(Const Value: String): TSpellEngineKind;
Function EmptySpellSuggestions: TSpellStringArray;

Implementation

Function SpellEngineKindToText(Kind: TSpellEngineKind): String;
Begin
  Case Kind Of
    sekNone: Result := 'none';
    sekAuto: Result := 'auto';
    sekHunspell: Result := 'hunspell';
    sekAspell: Result := 'aspell';
  Else
    Result := 'none';
  End;
End;

Function TextToSpellEngineKind(Const Value: String): TSpellEngineKind;
Var
  KindText: String;
Begin
  KindText := LowerCase(Trim(Value));
  If KindText = 'auto' Then
    Result := sekAuto
  Else If (KindText = 'hunspell') Or (KindText = 'hun') Then
    Result := sekHunspell
  Else If (KindText = 'aspell') Or (KindText = 'asp') Then
    Result := sekAspell
  Else
    Result := sekNone;
End;

Function EmptySpellSuggestions: TSpellStringArray;
Begin
  Result := Nil;
End;

Constructor TSpellEngine.Create;
Begin
  Inherited Create;
  FLastError := '';
  FResolvedLanguage := '';
  FLibraryPath := '';
End;

Destructor TSpellEngine.Destroy;
Begin
  Unload;
  Inherited Destroy;
End;

{$PUSH}{$HINTS OFF}
Procedure TSpellEngine.AddToSession(Const WordText: String);
Begin
End;
{$POP}

Function TSpellEngine.Features: TSpellEngineFeatures;
Begin
  Result := [];
End;

End.
