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
    Check('user first', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('thinking running', Assigned(Think) And Think.Running);
    Tool := Trace.AddTool('call_1', 'read_file', '{"path":"Source/Foo.pas"}');
    Check('thinking finished for tool', Not Think.Running);
    Check('tool caption has file', Pos('Foo.pas', Tool.Title) > 0);
    Trace.CollapseThinking;
    Check('thinking collapsed', Think.Collapsed And (Not Think.Running));
    Check('thinking title', Pos('Thinking', Think.Title) > 0);
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

Procedure TestEnsureUser;
Var
  Trace: TAssistantTrace;
  User: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Check('empty ensure skips', Trace.EnsureUser('') = Nil);
    Trace.StartThinking(0);
    User := Trace.EnsureUser('please review');
    Check('ensure user first', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('ensure user body', User.Body = 'please review');
    Check('ensure user reuse', Trace.EnsureUser('please review') = User);
    Trace.NilFrames;
    Check('nil frames', Trace[0].Frame = Nil);
  Finally
    Trace.Free;
  End;
End;

Procedure TestEventOrder;
Var
  Trace: TAssistantTrace;
  FirstAnswer, FinalAnswer: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('what does this project do?');
    Trace.StartThinking(0);
    FirstAnswer := Trace.EnsureAnswer;
    FirstAnswer.Body := 'early content';
    Trace.AddTool('call_1', 'get_project_info', '{}');
    Trace.StartThinking(1);
    Trace.AddTool('call_2', 'read_file', '{"path":"Main.pas"}');
    FinalAnswer := Trace.EnsureAnswer;
    FinalAnswer.Body := 'final answer';
    Check('user first', Trace[0].Kind = tbkUser);
    Check('think then answer', (Trace[1].Kind = tbkThinking) And (Trace[2].Kind = tbkAnswer));
    Check('intermediate stays put', Trace[2] = FirstAnswer);
    Check('tool after intermediate', Trace[3].Kind = tbkTool);
    Check('new answer after later tools', FinalAnswer <> FirstAnswer);
    Check('final answer last', Trace[Trace.Count - 1] = FinalAnswer);
    Check('reuse last answer', Trace.EnsureAnswer = FinalAnswer);
    Check('thinking finished before tool', Not Trace[1].Running);
  Finally
    Trace.Free;
  End;
End;

Procedure TestElapsed;
Begin
  Check('subsecond', Pos('s', FormatThoughtElapsed(4200)) > 0);
  Check('zero', FormatThoughtElapsed(0) = '0.0s');
  Check('clock under a minute', FormatThinkingClock(12000) = '0:12');
  Check('clock one minute', FormatThinkingClock(60000) = '1:00');
End;

Begin
  FailCount := 0;
  TestBlocks;
  TestEnsureUser;
  TestEventOrder;
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
