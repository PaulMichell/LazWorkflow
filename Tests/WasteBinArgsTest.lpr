Program WasteBinArgsTest;

{ Argument-list checks for the Darwin waste-bin fallback. Does not run osascript.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, WasteBin;

Var
  Failures: Integer;

Procedure Check(Const Name: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Name)
  Else
    Begin
      Inc(Failures);
      WriteLn('FAIL ', Name);
    End;
End;

Function ScriptText(Args: TStrings): String;
Var
  I: Integer;
Begin
  Result := '';
  If Args = Nil Then
    Exit;
  I := 0;
  While I < Args.Count Do
    Begin
      If (Args[I] = '-e') And (I + 1 < Args.Count) Then
        Begin
          Result := Result + Args[I + 1];
          Inc(I);
        End;
      Inc(I);
    End;
End;

Function QuoteCount(Const Value: String): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 1 To Length(Value) Do
    If Value[I] = '"' Then
      Inc(Result);
End;

Procedure TestQuotedPath(Const QuotedPath: String);
Var
  Args: TStringList;
  EndOfOptions: Integer;
  Script: String;
Begin
  Args := TStringList.Create;
  Try
    AppendFinderWasteBinArguments(Args, QuotedPath);
    EndOfOptions := Args.IndexOf('--');
    Script := ScriptText(Args);
    Check('end of options present', EndOfOptions >= 0);
    Check('path is its own parameter', (EndOfOptions >= 0) And (EndOfOptions < Args.Count - 1) And
      (Args[EndOfOptions + 1] = QuotedPath));
    Check('path is not repeated', Args.IndexOf(QuotedPath) = EndOfOptions + 1);
    { "Finder" is the only quoted text. A path quote must not be added to -e. }
    Check('path quote does not appear inside -e', (Pos(QuotedPath, Script) = 0) And (QuoteCount(Script) = 2));
    Check('script reads argv', Pos('item 1 of argv', Script) > 0);
  Finally
    Args.Free;
  End;
End;

Begin
  Failures := 0;
  TestQuotedPath('/Users/test/file"name.txt');
  TestQuotedPath('-quote"name.txt');
  {$IFNDEF DARWIN}
  WriteLn('skip osascript execution: not Darwin');
  {$ENDIF}
  WriteLn(Failures, ' failure(s).');
  If Failures <> 0 Then
    Halt(1);
End.
