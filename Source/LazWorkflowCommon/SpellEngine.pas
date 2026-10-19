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
  TSpellEngineKind = (sekNone, sekAuto, sekHunspell, sekAspell, sekWindows);

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

Type
  TSpellEngineKindArray = Array Of TSpellEngineKind;
  { True when this kind can be offered. Nil means always available. }
  TSpellEngineAvailable = Function: Boolean;

/// Registered kinds are listed first, then Hunspell and ASpell. A kind whose check returns false is omitted.
Procedure RegisterSpellEngineKind(Kind: TSpellEngineKind; Available: TSpellEngineAvailable);
Function AvailableEngineKinds: TSpellEngineKindArray;
Function SpellEngineKindAvailable(Kind: TSpellEngineKind): Boolean;

Implementation

Const
  MaxRegisteredEngines = 8;

Var
  RegisteredKinds: Array[0..MaxRegisteredEngines - 1] Of TSpellEngineKind;
  RegisteredChecks: Array[0..MaxRegisteredEngines - 1] Of TSpellEngineAvailable;
  RegisteredCount: Integer = 0;

Procedure RegisterSpellEngineKind(Kind: TSpellEngineKind; Available: TSpellEngineAvailable);
Var
  Index: Integer;
Begin
  If Kind In [sekNone, sekAuto] Then
    Exit;
  For Index := 0 To RegisteredCount - 1 Do
    If RegisteredKinds[Index] = Kind Then
      Begin
        RegisteredChecks[Index] := Available;
        Exit;
      End;
  If RegisteredCount > High(RegisteredKinds) Then
    Exit;
  RegisteredKinds[RegisteredCount] := Kind;
  RegisteredChecks[RegisteredCount] := Available;
  Inc(RegisteredCount);
End;

Function AvailableEngineKinds: TSpellEngineKindArray;
Var
  Index, Count: Integer;
Begin
  Result := Nil;
  Count := 0;
  For Index := 0 To RegisteredCount - 1 Do
    If (Not Assigned(RegisteredChecks[Index])) Or RegisteredChecks[Index]() Then
      Begin
        SetLength(Result, Count + 1);
        Result[Count] := RegisteredKinds[Index];
        Inc(Count);
      End;
  SetLength(Result, Count + 2);
  Result[Count] := sekHunspell;
  Result[Count + 1] := sekAspell;
End;

Function SpellEngineKindAvailable(Kind: TSpellEngineKind): Boolean;
Var
  Kinds: TSpellEngineKindArray;
  Index: Integer;
Begin
  Kinds := AvailableEngineKinds;
  Result := False;
  For Index := 0 To High(Kinds) Do
    If Kinds[Index] = Kind Then
      Exit(True);
End;

Function SpellEngineKindToText(Kind: TSpellEngineKind): String;
Begin
  Case Kind Of
    sekNone: Result := 'none';
    sekAuto: Result := 'auto';
    sekHunspell: Result := 'hunspell';
    sekAspell: Result := 'aspell';
    sekWindows: Result := 'windows';
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
  Else If (KindText = 'windows') Or (KindText = 'win') Then
    Result := sekWindows
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
