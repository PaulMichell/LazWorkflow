Program MemoryCheckProbeUseAfterFree;

{ Planted use-after-free for the memory-check runner modes (c) 2026 Michell Computing.

  Plan item 2.1 of Documents/Plan-20261107-025146.md. With no switch the probe
  writes into a freed GetMem block, then signals an RTLEvent after destroying
  it, the fault AssistantMonitorApprovalWait must never commit. With --clean it
  does the same work in the right order.

  The planted run may crash or hang in pthread code: the destroyed event's mutex
  lives in a freed block. That is the fault being probed.

  Not in CoreTestNames. Item 2.4 runs it through the runner. No Interfaces unit. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils;

Const
  BlockBytes = 64;

Var
  Clean: Boolean;
  Block: PByte;
  Event: PRTLEvent;

Begin
  Clean := (ParamCount = 1) And (ParamStr(1) = '--clean');
  If (ParamCount > 1) Or ((ParamCount = 1) And (Not Clean)) Then
    Begin
      WriteLn(StdErr, 'usage: MemoryCheckProbeUseAfterFree [--clean]');
      Halt(2);
    End;

  GetMem(Block, BlockBytes);
  If Clean Then
    Begin
      FillChar(Block^, BlockBytes, $5A);
      FreeMem(Block);
    End
  Else
    Begin
      FreeMem(Block);
      FillChar(Block^, BlockBytes, $5A);
    End;
  WriteLn('ok   GetMem block written ', BoolToStr(Clean, 'before', 'after'), ' free');

  { Created as AssistantMonitorApprovalWait creates its wait event. }
  Event := RTLEventCreate;
  If Clean Then
    Begin
      RTLEventSetEvent(Event);
      RTLEventDestroy(Event);
    End
  Else
    Begin
      RTLEventDestroy(Event);
      RTLEventSetEvent(Event);
    End;
  WriteLn('ok   RTLEvent signalled ', BoolToStr(Clean, 'before', 'after'), ' destroy');
End.
