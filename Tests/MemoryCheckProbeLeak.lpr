Program MemoryCheckProbeLeak;

{ Planted leak for the memory-check runner modes (c) 2026 Michell Computing.

  Plan item 2.1 of Documents/Plan-20261107-025146.md. With no switch the probe
  leaves one TStringList unfreed, so heaptrc and memcheck have a known leak to
  report. With --clean it frees the list and must report nothing.

  Not in CoreTestNames. Item 2.4 runs it through the runner. No Interfaces unit. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils;

Var
  Clean: Boolean;
  Lines: TStringList;

Begin
  Clean := (ParamCount = 1) And (ParamStr(1) = '--clean');
  If (ParamCount > 1) Or ((ParamCount = 1) And (Not Clean)) Then
    Begin
      WriteLn(StdErr, 'usage: MemoryCheckProbeLeak [--clean]');
      Halt(2);
    End;
  Lines := TStringList.Create;
  Lines.Add('planted leak');
  If Clean Then
    Begin
      Lines.Free;
      WriteLn('ok   clean run frees its list');
    End
  Else
    WriteLn('ok   planted run leaves one TStringList unfreed');
End.
