Program AssistantTraceViewTest;

{$MODE OBJFPC}{$H+}

Uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Controls, SysUtils, FileUtil,
  AssistantTrace, AssistantTraceView, AssistantConversation;

Procedure Check(Const Name: String; Passed: Boolean);
Begin
  If Not Passed Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Procedure TestVisibility;
Var
  Host: TForm;
  View: TAssistantTraceView;
  Trace: TAssistantTrace;
  Tool, Answer, Thought: TTraceBlock;
Begin
  Host := TForm.CreateNew(Nil);
  Trace := TAssistantTrace.Create;
  Try
    Host.SetBounds(0, 0, 800, 600);
    View := TAssistantTraceView.Create(Host);
    View.Parent := Host;
    View.Align := alClient;
    Thought := Trace.StartThinking(0);
    View.Sync(Trace, False);
    Check('empty running thought creates no card', Thought.Frame = Nil);
    Check('empty thought omitted from history', Pos('thinking', Trace.SaveToJson) = 0);
    Thought.Body := 'Summary arrived'; View.Sync(Trace, False);
    Check('thought card appears when text arrives', Assigned(Thought.Frame));
    Thought.Body := ''; View.Sync(Trace, False);
    Check('empty thought card removed', Thought.Frame = Nil);
    Tool := Trace.AddTool('call_1', 'read_file', '{}');
    Tool.Body := 'saved result';
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'The answer stays visible.';
    View.Sync(Trace, False);
    Check('tool use visible by default', Assigned(Tool.Frame) And TControl(Tool.Frame).Visible);
    View.ShowToolUse := False;
    View.Sync(Trace, False);
    Check('tool row hidden', Not TControl(Tool.Frame).Visible);
    Check('answer stays visible', TControl(Answer.Frame).Visible);
    View.RefreshElapsed(Trace);
    Check('elapsed refresh keeps tools hidden', Not TControl(Tool.Frame).Visible);
    Tool := Trace.AddTool('call_2', 'get_project_info', '{}');
    View.Sync(Trace, False);
    Check('new tool row stays hidden', Not TControl(Tool.Frame).Visible);
    View.ShowToolUse := True;
    View.Sync(Trace, False);
    Check('tool rows restored', TControl(Tool.Frame).Visible And
      TControl(Trace.FindTool('call_1').Frame).Visible);
    Check('tool result retained', Trace.FindTool('call_1').Body = 'saved result');
  Finally
    Host.Free;
    Trace.Free;
  End;
End;

Procedure TestPreference;
Var
  Store: TAssistantConversationStore;
  Root, Plan: String;
  Thinking, Tools: Boolean;
  Mode: TAssistantMode;
Begin
  Root := GetTempFileName(GetTempDir, 'trace-prefs-');
  DeleteFile(Root);
  ForceDirectories(Root);
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(Root);
    Tools := False;
    Store.LoadShellConfig(Thinking, Mode, Plan, @Tools);
    Check('missing configuration shows tools', Tools);
    Tools := False;
    Check('save hidden preference', Store.SaveShellConfig(True, amChat, '', @Tools));
    Check('legacy plan update', Store.SaveShellConfig(False, amPlan, 'plan.md'));
    Tools := True;
    Check('load preferences', Store.LoadShellConfig(Thinking, Mode, Plan, @Tools));
    Check('plan updates preserve hidden preference', Not Tools);
    Check('other preferences retained', (Not Thinking) And (Mode = amPlan) And (Plan = 'plan.md'));
  Finally
    Store.Free;
    DeleteDirectory(Root, False);
  End;
End;

Begin
  Application.Initialize;
  TestVisibility;
  TestPreference;
  WriteLn('All AssistantTraceView tests passed.');
End.
