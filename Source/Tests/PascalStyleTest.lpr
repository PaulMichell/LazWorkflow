Program PascalStyleTest;

{ Console checks for the Michell Computing Pascal formatter (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  CWString,
  {$ENDIF}
  SysUtils, PascalStyleFormat;

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

Const
  CompactSource =
    'Unit Sample;' + #10 +
    '{ Compact helper. }' + #10 +
    '{$mode objfpc}{$H+}' + #10 +
    'Interface' + #10 +
    'Function EnterSample: Boolean;' + #10 +
    'Implementation' + #10 +
    'Var Busy: Boolean = False;' + #10 +
    'Function EnterSample: Boolean;' + #10 +
    'Begin Result := Not Busy; If Result Then Busy := True; End;' + #10 +
    'End.' + #10;

Procedure TestHeaderAndKeywords;
Var
  Formatted: String;
Begin
  Formatted := FormatPascalSource(CompactSource);
  Check('mode block', Pos('{$MODE ObjFPC}', Formatted) > 0);
  Check('longstrings', Pos('{$LONGSTRINGS ON}', Formatted) > 0);
  Check('ifdef fpc', Pos('{$IFDEF FPC}', Formatted) > 0);
  Check('copyright', Pos('Michell Computing', Formatted) > 0);
  Check('recase begin', Pos('Begin', Formatted) > 0);
  Check('no compact mode', Pos('{$mode objfpc}', Formatted) < 1);
  Check('fingerprint', TokenFingerprintsEqual(CompactSource, Formatted));
End;

Procedure TestIdempotent;
Var
  Once, Twice: String;
Begin
  Once := FormatPascalSource(CompactSource);
  Twice := FormatPascalSource(Once);
  Check('idempotent', Once = Twice);
End;

Procedure TestPackedBegin;
Var
  Formatted: String;
Begin
  Formatted := FormatPascalSource(CompactSource);
  Check('begin own line', Pos('Begin' + #10, Formatted) > 0);
  Check('result assignment', Pos('Result := Not Busy;', Formatted) > 0);
End;

Begin
  FailCount := 0;
  TestHeaderAndKeywords;
  TestIdempotent;
  TestPackedBegin;
  If FailCount = 0 Then
    Begin
      WriteLn('All PascalStyle tests passed.');
      Halt(0);
    End;
  WriteLn(FailCount, ' PascalStyle test(s) failed.');
  Halt(1);
End.
