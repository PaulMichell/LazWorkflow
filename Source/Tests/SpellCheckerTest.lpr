Program SpellCheckerTest;

{ Console checks for spell engines and the word breaker (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, SpellEngine, SpellWordBreaker, SpellCheckerOptions, SpellEngineHunspell,
  SpellEngineAspell;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TestBreaker;
Var
  Tokens: TSpellTokenArray;
  Token: TSpellToken;
Begin
  Tokens := SpellBreakWords('Fix the recieve path in src/GitService.pas a1b2c3d');
  Check('breaker finds prose words', Length(Tokens) >= 3);
  Check('breaker skips path', Length(SpellBreakWords('src/GitService.pas')) = 0);
  Check('breaker keeps contraction', SpellTokenAt('don''t break this', 2, Token) And (Token.Text = 'don''t'));
  Tokens := SpellBreakWords('hello '' recieve world');
  Check('straight apostrophe does not end scan', (Length(Tokens) = 3) And (Tokens[1].Text = 'recieve'));
  Tokens := SpellBreakWords('’ hello ’ recieve world');
  Check('curly apostrophes do not end scan', Length(Tokens) = 3);
  Tokens := SpellBreakWords('''quoted'' don''t');
  Check('quoted words and contractions', (Length(Tokens) = 2) And (Tokens[0].Text = 'quoted') And (Tokens[1].Text = 'don''t'));
  Tokens := SpellBreakWords('lookoing');
  Check('open word at caret is incomplete', (Length(Tokens) = 1) And
    (Not SpellWordIsComplete('lookoing', Tokens[0], Length('lookoing') + 1)));
  Tokens := SpellBreakWords('xx lookoing');
  Check('open word is complete after leaving', (Length(Tokens) = 2) And
    SpellWordIsComplete('xx lookoing', Tokens[1], 1));
  Tokens := SpellBreakWords('lookoing ');
  Check('word followed by space is complete', (Length(Tokens) = 1) And
    SpellWordIsComplete('lookoing ', Tokens[0], Length('lookoing ') + 1));
End;

{$IFDEF WINDOWS}
Function StandardLibreOfficePresent: Boolean;
Var
  Parents: Array[0..3] Of String;
  Index: Integer;
  Info: TSearchRec;
  Parent, Child: String;
Begin
  Result := False;
  Parents[0] := GetEnvironmentVariable('ProgramW6432');
  Parents[1] := GetEnvironmentVariable('ProgramFiles');
  Parents[2] := GetEnvironmentVariable('ProgramFiles(x86)');
  Parents[3] := 'C:\Program Files';
  For Index := 0 To High(Parents) Do
    Begin
      Parent := ExcludeTrailingPathDelimiter(Parents[Index]);
      If Parent = '' Then
        Continue;
      If DirectoryExists(Parent + '\LibreOffice\program') Then
        Begin
          Result := True;
          Exit;
        End;
      If FindFirst(Parent + '\LibreOffice*', faDirectory, Info) <> 0 Then
        Continue;
      Try
        Repeat
          If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
            Begin
              Child := Parent + '\' + Info.Name + '\program';
              If DirectoryExists(Child) Then
                Begin
                  Result := True;
                  Exit;
                End;
            End;
        Until FindNext(Info) <> 0;
      Finally
        FindClose(Info);
      End;
    End;
End;
{$ENDIF}

{$IFDEF WINDOWS}
Procedure TestWindowsConfigure;
Var
  LibraryFileName, AffFile, DicFile, LanguageCode, Loaded: String;
  Dirs: TStringArray;
  Index: Integer;
Begin
  If Not ConfigureWindowsHunspell(LibraryFileName, Dirs) Then
    Begin
      Check('installed LibreOffice is configured', Not StandardLibreOfficePresent);
      WriteLn('skip Windows Hunspell configure (LibreOffice not found)');
      Exit;
    End;
  WriteLn('Windows Hunspell library: ', LibraryFileName);
  For Index := 0 To High(Dirs) Do
    WriteLn('Windows Hunspell dictionary: ', Dirs[Index]);
  Check('configured library exists', (LibraryFileName <> '') And FileExists(LibraryFileName));
  Check('configured dictionary directory exists', (Length(Dirs) > 0) And DirectoryExists(Dirs[0]));
  Check('configured library loads', FindHunspellLibrary(Loaded) And (Loaded <> ''));
  Check('configured files open a dictionary', FindHunspellDictionary('', '', AffFile, DicFile, LanguageCode));
End;
{$ELSE}
Procedure TestWindowsConfigure;
Var
  LibraryFileName: String;
  Dirs: TStringArray;
Begin
  Check('windows configure is inert off Windows', Not ConfigureWindowsHunspell(LibraryFileName, Dirs));
End;
{$ENDIF}

Procedure TestHunspell;
Var
  Engine: THunspellEngine;
  LibName: String;
  Suggestions: TSpellStringArray;
Begin
  If Not FindHunspellLibrary(LibName) Then
    Begin
      WriteLn('skip Hunspell (library not found)');
      Exit;
    End;
  Engine := THunspellEngine.Create;
  Try
    Engine.Language := 'en_GB';
    If Not Engine.Load Then
      Begin
        WriteLn('skip Hunspell load: ', Engine.LastError);
        Exit;
      End;
    Check('Hunspell ready', Engine.IsReady);
    Check('Hunspell accepts the', Engine.CheckWord('the'));
    Check('Hunspell rejects recieve', Not Engine.CheckWord('recieve'));
    Engine.LibraryFileName := LibName;
    Check('Hunspell same library reloads', Engine.Load);
    Engine.LibraryFileName := '/does/not/exist-spell-library';
    Check('Hunspell changed library rejected', Not Engine.Load);
    Check('Hunspell restart diagnostic', Pos('restart', Engine.LastError) > 0);
    Engine.LibraryFileName := LibName;
    Check('Hunspell original binding remains usable', Engine.Load);
    Suggestions := Engine.GetSuggestions('recieve', 8);
    Check('Hunspell suggests for recieve', Length(Suggestions) > 0);
  Finally
    Engine.Free;
  End;
End;

Procedure TestAspell;
Var
  Engine: TAspellEngine;
  LibName: String;
Begin
  If Not FindAspellLibrary(LibName) Then
    Begin
      WriteLn('skip ASpell (library not found)');
      Exit;
    End;
  Engine := TAspellEngine.Create;
  Try
    Engine.Language := 'en_GB';
    If Not Engine.Load Then
      Begin
        WriteLn('skip ASpell load: ', Engine.LastError);
        Exit;
      End;
    Check('ASpell ready', Engine.IsReady);
    Check('ASpell accepts the', Engine.CheckWord('the'));
    Check('ASpell rejects recieve', Not Engine.CheckWord('recieve'));
    Engine.LibraryFileName := LibName;
    Check('ASpell same library reloads', Engine.Load);
    Engine.LibraryFileName := '/does/not/exist-spell-library';
    Check('ASpell changed library rejected', Not Engine.Load);
    Check('ASpell restart diagnostic', Pos('restart', Engine.LastError) > 0);
    Engine.LibraryFileName := LibName;
    Check('ASpell original binding remains usable', Engine.Load);
  Finally
    Engine.Free;
  End;
End;

Procedure TestNone;
Begin
  Check('none kind text', SpellEngineKindToText(sekNone) = 'none');
  Check('auto kind parse', TextToSpellEngineKind('auto') = sekAuto);
End;

Procedure TestLocale;
Begin
  Check('C locale is not a dictionary', SpellLanguageFromLocale('C') = '');
  Check('POSIX locale is not a dictionary', SpellLanguageFromLocale('POSIX') = '');
  Check('C.UTF-8 is not a dictionary', SpellLanguageFromLocale('C.UTF-8') = '');
  Check('C.utf8 is not a dictionary', SpellLanguageFromLocale('C.utf8') = '');
  Check('en_GB.UTF-8 strips encoding', SpellLanguageFromLocale('en_GB.UTF-8') = 'en_GB');
  Check('en-US becomes underscore', SpellLanguageFromLocale('en-US') = 'en_US');
  Check('empty locale is empty', SpellLanguageFromLocale('') = '');
End;

Begin
  FailCount := 0;
  TestNone;
  TestLocale;
  TestBreaker;
  TestWindowsConfigure;
  TestHunspell;
  TestAspell;
  If FailCount = 0 Then
    Begin
      WriteLn('All checks passed.');
      ExitCode := 0;
    End
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed.');
      ExitCode := 1;
    End;
End.
