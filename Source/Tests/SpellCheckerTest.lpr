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
