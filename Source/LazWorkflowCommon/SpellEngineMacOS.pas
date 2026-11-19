Unit SpellEngineMacOS;

{$mode objfpc}{$H+}{$modeswitch objectivec1}

Interface

Uses
  Classes, SysUtils, CocoaAll, SpellEngine;

Type
  TMacSpellEngine = Class(TSpellEngine)
  Private
    FLanguage: String;
  Public
    Constructor Create(Const Language: String); Reintroduce;
    Function Load: Boolean; Override;
    Procedure Unload; Override;
    Function IsReady: Boolean; Override;
    Function CheckWord(Const WordText: String): Boolean; Override;
    Function GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray; Override;
    Function EngineKind: TSpellEngineKind; Override;
    Function Features: TSpellEngineFeatures; Override;
  End;

Procedure ListMacSpellLanguages(List: TStrings);

Implementation

Procedure ListMacSpellLanguages(List: TStrings);
Var
  Languages: NSArray;
  Index: PtrInt;
Begin
  Languages := NSSpellChecker.sharedSpellChecker.availableLanguages;
  For Index := 0 To PtrInt(Languages.count) - 1 Do
    List.Add(NSString(Languages.objectAtIndex(Index)).UTF8String);
End;

Constructor TMacSpellEngine.Create(Const Language: String);
Begin
  Inherited Create;
  FLanguage := Language;
End;

Function TMacSpellEngine.Load: Boolean;
Var
  Pool: NSAutoreleasePool;
  Languages: TStringList;
  Index: Integer;
  Requested: String;
Begin
  Pool := NSAutoreleasePool.alloc.init;
  Languages := TStringList.Create;
  Try
    Unload;
    If FLanguage = '' Then
      Begin
        If NSSpellChecker.sharedSpellChecker.language <> Nil Then
          FResolvedLanguage := NSSpellChecker.sharedSpellChecker.language.UTF8String;
      End
    Else
      Begin
        Requested := StringReplace(FLanguage, '-', '_', [rfReplaceAll]);
        ListMacSpellLanguages(Languages);
        For Index := 0 To Languages.Count - 1 Do
          If SameText(Requested, StringReplace(Languages[Index], '-', '_', [rfReplaceAll])) Then
            Begin
              FResolvedLanguage := Languages[Index];
              Break;
            End;
        If (FResolvedLanguage = '') And (Pos('_', Requested) > 0) Then
          Begin
            Index := Languages.IndexOf(Copy(Requested, 1, Pos('_', Requested) - 1));
            If Index >= 0 Then FResolvedLanguage := Languages[Index];
          End;
      End;
    Result := IsReady;
    If Not Result Then FLastError := 'macOS spelling language unavailable: ' + FLanguage;
  Finally
    Languages.Free;
    Pool.drain;
  End;
End;

Procedure TMacSpellEngine.Unload;
Begin
  FResolvedLanguage := '';
End;

Function TMacSpellEngine.IsReady: Boolean;
Begin
  Result := FResolvedLanguage <> '';
End;

Function TMacSpellEngine.CheckWord(Const WordText: String): Boolean;
Var
  Misspelled: NSRange;
Begin
  If (WordText = '') Or Not IsReady Then Exit(True);
  Misspelled := NSSpellChecker.sharedSpellChecker.checkSpellingOfString_startingAt_language_wrap_inSpellDocumentWithTag_wordCount(
    NSString(NSString.stringWithUTF8String(PChar(WordText))), 0, NSString(NSString.stringWithUTF8String(PChar(FResolvedLanguage))), False, 0, Nil);
  Result := Misspelled.length = 0;
End;

Function TMacSpellEngine.GetSuggestions(Const WordText: String; MaxCount: Integer): TSpellStringArray;
Var
  WordString: NSString;
  Suggestions: NSArray;
  Count, Index: PtrInt;
Begin
  Result := Nil;
  If (WordText = '') Or (MaxCount <= 0) Or Not IsReady Then Exit;
  WordString := NSString(NSString.stringWithUTF8String(PChar(WordText)));
  Suggestions := NSSpellChecker.sharedSpellChecker.guessesForWordRange_inString_language_inSpellDocumentWithTag(
    NSMakeRange(0, WordString.length), WordString, NSString(NSString.stringWithUTF8String(PChar(FResolvedLanguage))), 0);
  Count := Suggestions.count;
  If Count > MaxCount Then Count := MaxCount;
  SetLength(Result, Count);
  For Index := 0 To Count - 1 Do
    Result[Index] := NSString(Suggestions.objectAtIndex(Index)).UTF8String;
End;

Function TMacSpellEngine.EngineKind: TSpellEngineKind;
Begin
  Result := sekMacOS;
End;

Function TMacSpellEngine.Features: TSpellEngineFeatures;
Begin
  Result := [sefSuggest];
End;

Initialization
  RegisterSpellEngineKind(sekMacOS, Nil);
End.
