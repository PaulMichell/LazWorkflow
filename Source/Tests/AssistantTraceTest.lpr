Program AssistantTraceTest;

{ Console checks for the current-turn trace model (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, AssistantTrace;

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

Procedure TestBlocks;
Var
  Trace: TAssistantTrace;
  Think, Tool, Answer: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Think := Trace.StartThinking(0);
    Think.Body := 'Looking at Foo.pas';
    Tool := Trace.AddTool('call_1', 'read_file', '{"path":"Source/Foo.pas"}');
    Check('user first', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('thinking running', Assigned(Think) And Think.Running);
    Check('tool caption has file', Pos('Foo.pas', Tool.Title) > 0);
    Trace.CollapseThinking;
    Check('thinking collapsed', Think.Collapsed And (Not Think.Running));
    Check('thought title', Pos('Thought', Think.Title) > 0);
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'Looks fine.';
    Check('same answer', Trace.EnsureAnswer = Answer);
    Tool := Trace.FindTool('call_1');
    Check('find tool', Assigned(Tool) And (Tool.ToolName = 'read_file'));
    Trace.AddTool('call_1', 'read_file', '{"path":"Source/Foo.pas"}');
    Check('reuse tool id', Trace.Count = 4);
  Finally
    Trace.Free;
  End;
End;

Procedure TestElapsed;
Begin
  Check('subsecond', Pos('s', FormatThoughtElapsed(4200)) > 0);
  Check('zero', FormatThoughtElapsed(0) = '0.0s');
End;

Begin
  FailCount := 0;
  TestBlocks;
  TestElapsed;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantTrace tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantTrace test(s) failed.');
      Halt(1);
    End;
End.
