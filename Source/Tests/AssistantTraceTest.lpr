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
  Check('thought footer', FormatThoughtFooter(12000) = 'Thought for 0:12');
  Check('worked under an hour', FormatWorkedFooter(125000) = 'Worked for 2:05');
  Check('worked over an hour', FormatWorkedFooter(3723000) = 'Worked for 1:02:03');
End;

Procedure TestFooters;
Var
  Trace: TAssistantTrace;
  Think, Answer, Note: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Think := Trace.StartThinking(0);
    Think.Body := 'Looking at Foo.pas';
    Think.DurationMs := 45000;
    Trace.FinishCurrentThinking;
    Check('completed title has no clock', Think.Title = 'Thinking');
    Check('thought footer on completed think', Think.Footer = 'Thought for 0:45');
    Check('thinking not running', Not Think.Running);
    Check('running title still clocks', Pos('Thinking…', ThinkingCardTitle(12000, True)) = 1);
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'Looks fine.';
    Trace.ApplyWorkedFooter(125000);
    Check('worked footer on answer', Answer.Footer = 'Worked for 2:05');
    Note := Trace.AddNote('*Stream cancelled.*');
    Trace.ApplyWorkedFooter(3661000);
    Check('worked footer moves to note', Note.Footer = 'Worked for 1:01:01');
    Check('answer footer stays', Answer.Footer = 'Worked for 2:05');
    Check('thinking duration sum', Trace.ThinkingDurationMs = 45000);
  Finally
    Trace.Free;
  End;
End;

Procedure TestGrowingSnapshotReusesCards;
Var
  Trace: TAssistantTrace;
  Think, Answer, Think2, Answer2: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('Please review this project for bugs?');
    Think := Trace.StartThinking(0);
    Think.Body := 'The user wants me to review the project for bugs. Looking at the IDE context:';
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'I''ll start from';
    Check('ensure answer reuses', Trace.EnsureAnswer = Answer);
    Check('thinking stays this sample', Trace.LatestBlockSinceLastTool(tbkThinking) = Think);
    Answer.Body := 'I''ll start from the active project tree and walk';
    Check('second snapshot still one answer', Trace.EnsureAnswer = Answer);
    Check('user+think+answer only', Trace.Count = 3);
    Check('thinking stays open while message grows', Think.Running);
    Trace.AddTool('call_1', 'read_file', '{"path":"A.pas"}');
    Check('thinking closed on tool', Not Think.Running);
    Check('answer closed on tool', Not Answer.Running);
    Think2 := Trace.StartThinking(1);
    Answer2 := Trace.EnsureAnswer;
    Answer2.Body := 'Here is the review.';
    Check('new thinking after tool', Think2 <> Think);
    Check('new answer after tool', Answer2 <> Answer);
    Check('six cards after next sample', Trace.Count = 6);
  Finally
    Trace.Free;
  End;
End;

Procedure TestLiveChannelSlice;
Var
  StartAt: Integer;
Begin
  StartAt := 1;
  Check('first loop whole', SliceLiveChannel('hello', StartAt) = 'hello');
  StartAt := Length('I will review this project.') + 1;
  Check('same loop after tool is empty', SliceLiveChannel('I will review this project.', StartAt) = '');
  Check('start stays past end when empty', StartAt > Length('I will review this project.'));
  { New loop must reset StartAt; slicing alone must not reopen the previous body. }
  Check('stale start does not steal a shorter loop', SliceLiveChannel('Here is the review.', StartAt) = '');
  StartAt := 1;
  Check('new loop after reset', SliceLiveChannel('Here is the review.', StartAt) = 'Here is the review.');
  StartAt := 0;
  Check('zero start', SliceLiveChannel('ab', StartAt) = 'ab');
  StartAt := High(Integer);
  Check('frozen after tool ignores period', SliceLiveChannel('hello.', StartAt) = '');
  Check('period is not an answer', Not SliceLooksLikeAnswer('.'));
  Check('real answer', SliceLooksLikeAnswer('Gathering the main sources'));
End;

Procedure TestTraceJsonRoundTrip;
Var
  Trace: TAssistantTrace;
  Json: String;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Trace.StartThinking(0).Body := 'Looking at Foo.pas';
    Trace.FinishCurrentThinking;
    Trace.AddTool('call_1', 'get_project_info', '{}');
    Trace.StartThinking(1).Body := 'Now read the units.';
    Trace.FinishCurrentThinking;
    Trace.EnsureAnswer.Body := 'Looks fine.';
    Json := Trace.SaveToJson;
    Check('json is array', (Length(Json) > 0) And (Json[1] = '['));
    Check('json one line', Pos(#10, Json) < 1);
    Trace.LoadFromJson(Json);
    Check('roundtrip count', Trace.Count = 5);
    Check('roundtrip user', Trace[0].Kind = tbkUser);
    Check('roundtrip think 0', (Trace[1].Kind = tbkThinking) And (Pos('Foo.pas', Trace[1].Body) > 0));
    Check('roundtrip tool', (Trace[2].Kind = tbkTool) And (Trace[2].ToolName = 'get_project_info'));
    Check('roundtrip think 1', (Trace[3].Kind = tbkThinking) And (Pos('units', Trace[3].Body) > 0));
    Check('roundtrip answer', (Trace[4].Kind = tbkAnswer) And (Pos('Looks fine', Trace[4].Body) > 0));
    Check('joined answers', Pos('Looks fine', Trace.JoinedAnswers) > 0);
  Finally
    Trace.Free;
  End;
End;

Begin
  FailCount := 0;
  TestBlocks;
  TestEnsureUser;
  TestEventOrder;
  TestElapsed;
  TestFooters;
  TestGrowingSnapshotReusesCards;
  TestLiveChannelSlice;
  TestTraceJsonRoundTrip;
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
