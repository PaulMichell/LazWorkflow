Unit SpellCheckerOptions;

{ Spell-checker options and personal word list (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SpellEngine;

Type
  TSpellCheckerOptions = Class
  Private
    FEngineKind: TSpellEngineKind;
    FLanguage: String;
    FLibraryFileName: String;
    FDictionaryDirectory: String;
    FPersonalFileName: String;
  Public
    Constructor Create;
    Procedure Assign(Source: TSpellCheckerOptions);
    Procedure ResetDefaults;
    Property EngineKind: TSpellEngineKind Read FEngineKind Write FEngineKind;
    Property Language: String Read FLanguage Write FLanguage;
    Property LibraryFileName: String Read FLibraryFileName Write FLibraryFileName;
    Property DictionaryDirectory: String Read FDictionaryDirectory Write FDictionaryDirectory;
    Property PersonalFileName: String Read FPersonalFileName Write FPersonalFileName;
  End;

  TSpellWordSet = Class
  Private
    FList: TStringList;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    Function Contains(Const WordText: String): Boolean;
    Procedure Add(Const WordText: String);
    Procedure Remove(Const WordText: String);
    Procedure LoadFromFile(Const FileName: String);
    Procedure ReplaceFromStrings(Words: TStrings);
    Procedure CopyToStrings(Words: TStrings);
    Procedure SaveToFile(Const FileName: String); Overload;
    Function SaveToFile(Const FileName: String; Out ErrorText: String): Boolean; Overload;
    Function Count: Integer;
  End;

Function SpellLanguageFromLocale(Const LocaleValue: String): String;
Function DefaultSpellLanguage: String;

Implementation

Constructor TSpellCheckerOptions.Create;
Begin
  Inherited Create;
  ResetDefaults;
End;

Procedure TSpellCheckerOptions.ResetDefaults;
Begin
  FEngineKind := sekAuto;
  FLanguage := '';
  FLibraryFileName := '';
  FDictionaryDirectory := '';
  FPersonalFileName := '';
End;

Procedure TSpellCheckerOptions.Assign(Source: TSpellCheckerOptions);
Begin
  If Not Assigned(Source) Then
    Exit;
  FEngineKind := Source.EngineKind;
  FLanguage := Source.Language;
  FLibraryFileName := Source.LibraryFileName;
  FDictionaryDirectory := Source.DictionaryDirectory;
  FPersonalFileName := Source.PersonalFileName;
End;

Function SpellLanguageFromLocale(Const LocaleValue: String): String;
Var
  Lang: String;
  CutPos: Integer;
Begin
  Lang := Trim(LocaleValue);
  If Lang = '' Then
    Begin
      Result := '';
      Exit;
    End;
  CutPos := Pos('.', Lang);
  If CutPos > 0 Then
    Lang := Copy(Lang, 1, CutPos - 1);
  CutPos := Pos('@', Lang);
  If CutPos > 0 Then
    Lang := Copy(Lang, 1, CutPos - 1);
  If (Lang = '') Or SameText(Lang, 'C') Or SameText(Lang, 'POSIX') Then
    Begin
      Result := '';
      Exit;
    End;
  Result := StringReplace(Lang, '-', '_', [rfReplaceAll]);
End;

Function DefaultSpellLanguage: String;
Var
  Lang: String;
Begin
  Lang := GetEnvironmentVariable('LC_ALL');
  If Lang = '' Then
    Lang := GetEnvironmentVariable('LC_MESSAGES');
  If Lang = '' Then
    Lang := GetEnvironmentVariable('LANG');
  Result := SpellLanguageFromLocale(Lang);
End;

Constructor TSpellWordSet.Create;
Begin
  Inherited Create;
  FList := TStringList.Create;
  FList.Sorted := True;
  FList.Duplicates := dupIgnore;
  FList.CaseSensitive := False;
End;

Destructor TSpellWordSet.Destroy;
Begin
  FreeAndNil(FList);
  Inherited Destroy;
End;

Procedure TSpellWordSet.Clear;
Begin
  FList.Clear;
End;

Function TSpellWordSet.Contains(Const WordText: String): Boolean;
Begin
  Result := FList.IndexOf(Trim(WordText)) >= 0;
End;

Procedure TSpellWordSet.Add(Const WordText: String);
Var
  Clean: String;
Begin
  Clean := Trim(WordText);
  If Clean <> '' Then
    FList.Add(Clean);
End;

Procedure TSpellWordSet.ReplaceFromStrings(Words: TStrings);
Var
  I: Integer;
Begin
  FList.Clear;
  If Not Assigned(Words) Then
    Exit;
  For I := 0 To Words.Count - 1 Do
    Add(Words[I]);
End;

Procedure TSpellWordSet.CopyToStrings(Words: TStrings);
Begin
  If Assigned(Words) Then
    Words.Assign(FList);
End;

Procedure TSpellWordSet.LoadFromFile(Const FileName: String);
Begin
  FList.Clear;
  If (FileName <> '') And FileExists(FileName) Then
    Try
      FList.LoadFromFile(FileName);
    Except
      FList.Clear;
    End;
End;

Procedure TSpellWordSet.Remove(Const WordText: String);
Var I: Integer;
Begin
  I := FList.IndexOf(Trim(WordText));
  If I >= 0 Then FList.Delete(I);
End;

Procedure TSpellWordSet.SaveToFile(Const FileName: String);
Var ErrorText: String;
Begin
  If Not SaveToFile(FileName, ErrorText) Then Raise EWriteError.Create(ErrorText);
End;

Function TSpellWordSet.SaveToFile(Const FileName: String; Out ErrorText: String): Boolean;
Var Dir: String;
Begin
  Result := False; ErrorText := '';
  Try
    If FileName = '' Then Raise Exception.Create('Dictionary filename is empty');
    Dir := ExtractFilePath(FileName);
    If (Dir <> '') And Not DirectoryExists(Dir) Then ForceDirectories(Dir);
    FList.SaveToFile(FileName);
    Result := True;
  Except On E: Exception Do ErrorText := E.Message; End;
End;

Function TSpellWordSet.Count: Integer;
Begin
  Result := FList.Count;
End;

End.
