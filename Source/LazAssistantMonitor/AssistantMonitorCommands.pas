Unit AssistantMonitorCommands;

{ POST /v4/commands. Ordinary commands wait on the IDE thread. Stop, steer,
  stop_plan and approval are decided at once. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, Classes;

Const
  MonitorCommandWaitMs = 5000;
  MonitorCommandTableLimit = 256;

Type
  TMonitorHostAnswer = Record
    Ok: Boolean;
    Reason: String;
    Message: String;
    TurnId: String;
  End;

  TMonitorCommandHost = Class
  Public
    Function KnownTurn(Const CommandId: String; Out TurnId: String): Boolean; Virtual;
    Function Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer; Virtual;
    Function Steer(Const Text: String): TMonitorHostAnswer; Virtual;
    Function Stop: TMonitorHostAnswer; Virtual;
    Function StopPlan: TMonitorHostAnswer; Virtual;
    Function SetMode(Const ModeText: String): TMonitorHostAnswer; Virtual;
    Function NewConversation: TMonitorHostAnswer; Virtual;
    Function SelectConversation(Const ConversationId: String): TMonitorHostAnswer; Virtual;
    Function SelectPlan(Const Path: String): TMonitorHostAnswer; Virtual;
    Function NewPlan(Const Title: String): TMonitorHostAnswer; Virtual;
    Function ClosePlan: TMonitorHostAnswer; Virtual;
    Function RunPlan(SaveFirst: Boolean): TMonitorHostAnswer; Virtual;
    Function WorkOnPlan(SectionIndex: Integer): TMonitorHostAnswer; Virtual;
    Function RunTask(Const TaskId, Note: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer; Virtual;
    Function InsertTask(Const TaskId, Note: String): TMonitorHostAnswer; Virtual;
  End;

Procedure SetMonitorCommandHost(Host: TMonitorCommandHost);
Function MonitorCommandStopPending: Boolean;
Procedure ResetMonitorCommands;
Procedure AddMonitorCommandCapabilities(List: TStrings);
Function ServeMonitorCommand(Const RequestBody: String; Out Status: Integer; Out Answer: String): Boolean;

Implementation

Uses
  SyncObjs, fpjson, jsonparser, AssistantSessionObserve, AssistantMonitorPulse;

Type
  TCommandRecord = Record
    Id: String;
    Status: Integer;
    Answer: String;
    Used: Boolean;
  End;

  TCommandJob = Class
    Kind, CommandId, Text, ConversationId, PlanPath, Title, TaskId, Note, ModeText, ToolId, Decision: String;
    SaveFirst: Boolean;
    SectionIndex: Integer;
    Priority: Boolean;
    Event: PRTLEvent;
    Refs: Integer;
    Procedure Execute;
    Procedure Release;
  End;

Var
  CommandLock: TRTLCriticalSection;
  CommandHost: TMonitorCommandHost;
  CommandStopPending: Boolean;
  CommandTable: Array[0..MonitorCommandTableLimit - 1] Of TCommandRecord;
  CommandTableNext: Integer;

Function BusyAnswer(Const MessageText: String): TMonitorHostAnswer;
Begin
  Result.Ok := False;
  Result.Reason := 'busy';
  Result.Message := MessageText;
  Result.TurnId := '';
End;

Function TMonitorCommandHost.KnownTurn(Const CommandId: String; Out TurnId: String): Boolean;
Begin
  TurnId := '';
  Result := False;
End;

Function TMonitorCommandHost.Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.Steer(Const Text: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.Stop: TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.StopPlan: TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.SetMode(Const ModeText: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.NewConversation: TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.SelectConversation(Const ConversationId: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.SelectPlan(Const Path: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.NewPlan(Const Title: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.ClosePlan: TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.RunPlan(SaveFirst: Boolean): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.WorkOnPlan(SectionIndex: Integer): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.RunTask(Const TaskId, Note: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function TMonitorCommandHost.InsertTask(Const TaskId, Note: String): TMonitorHostAnswer;
Begin
  Result := BusyAnswer('That command is not available.');
End;

Function ErrorJson(Const Reason, MessageText: String): String;
Begin
  Result := '{"reason":"' + Reason + '","message":"' + MessageText + '"}';
End;

Function DoneJson(Const State, TurnId: String): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Try
    Obj.Add('state', State);
    If TurnId <> '' Then
      Obj.Add('turn_id', TurnId);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function AnswerFromHost(Const HostAnswer: TMonitorHostAnswer; Out Status: Integer): String;
Begin
  If HostAnswer.Ok Then
    Begin
      Status := 200;
      Result := DoneJson('done', HostAnswer.TurnId);
    End
  Else If HostAnswer.Reason = 'unsaved_edits' Then
    Begin
      Status := 409;
      Result := ErrorJson('unsaved_edits', HostAnswer.Message);
    End
  Else
    Begin
      Status := 409;
      If HostAnswer.Reason = '' Then
        Result := ErrorJson('busy', HostAnswer.Message)
      Else
        Result := ErrorJson(HostAnswer.Reason, HostAnswer.Message);
    End;
End;

Function IsPriority(Const Kind: String): Boolean;
Begin
  Result := (Kind = 'stop') Or (Kind = 'steer') Or (Kind = 'stop_plan') Or (Kind = 'approval');
End;

Function IsIdempotent(Const Kind: String): Boolean;
Begin
  Result := (Kind = 'stop') Or (Kind = 'stop_plan') Or (Kind = 'approval');
End;

Function UsesStoreIdentity(Const Kind: String): Boolean;
Begin
  Result := (Kind = 'send') Or (Kind = 'run_task');
End;

Procedure Remember(Const CommandId: String; Status: Integer; Const Answer: String);
Var
  Index: Integer;
Begin
  If CommandId = '' Then
    Exit;
  For Index := 0 To MonitorCommandTableLimit - 1 Do
    If CommandTable[Index].Used And (CommandTable[Index].Id = CommandId) Then
      Begin
        CommandTable[Index].Status := Status;
        CommandTable[Index].Answer := Answer;
        Exit;
      End;
  Index := CommandTableNext;
  CommandTable[Index].Used := True;
  CommandTable[Index].Id := CommandId;
  CommandTable[Index].Status := Status;
  CommandTable[Index].Answer := Answer;
  CommandTableNext := (CommandTableNext + 1) Mod MonitorCommandTableLimit;
End;

Function Recall(Const CommandId: String; Out Status: Integer; Out Answer: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  Status := 0;
  Answer := '';
  If CommandId = '' Then
    Exit;
  For Index := 0 To MonitorCommandTableLimit - 1 Do
    If CommandTable[Index].Used And (CommandTable[Index].Id = CommandId) Then
      Begin
        Status := CommandTable[Index].Status;
        Answer := CommandTable[Index].Answer;
        Exit(True);
      End;
End;

Procedure SetStopPending(Value: Boolean);
Var
  Changed: Boolean;
Begin
  Changed := CommandStopPending <> Value;
  CommandStopPending := Value;
  If Changed Then
    WakeMonitorPulse;
End;

Function MonitorCommandStopPending: Boolean;
Begin
  Result := CommandStopPending;
End;

Procedure TCommandJob.Release;
Begin
  If InterlockedDecrement(Refs) = 0 Then
    Free;
End;

Procedure TCommandJob.Execute;
Var
  Host: TMonitorCommandHost;
  HostAnswer: TMonitorHostAnswer;
  Status: Integer;
  Answer: String;
Begin
  If AssistantModalDepth > 0 Then
    Begin
      TThread.Queue(Nil, @Execute);
      Exit;
    End;
  Host := CommandHost;
  HostAnswer := Default(TMonitorHostAnswer);
  If Not Assigned(Host) Then
    Begin
      Status := 503;
      Answer := ErrorJson('no_session', 'The assistant window is closed.');
    End
  Else
    Case Kind Of
      'send': HostAnswer := Host.Send(Text, SaveFirst, CommandId);
      'steer': HostAnswer := Host.Steer(Text);
      'stop': HostAnswer := Host.Stop;
      'stop_plan': HostAnswer := Host.StopPlan;
      'set_mode': HostAnswer := Host.SetMode(ModeText);
      'new_conversation': HostAnswer := Host.NewConversation;
      'select_conversation': HostAnswer := Host.SelectConversation(ConversationId);
      'select_plan': HostAnswer := Host.SelectPlan(PlanPath);
      'new_plan': HostAnswer := Host.NewPlan(Title);
      'close_plan': HostAnswer := Host.ClosePlan;
      'run_plan': HostAnswer := Host.RunPlan(SaveFirst);
      'work_on_plan': HostAnswer := Host.WorkOnPlan(SectionIndex);
      'run_task': HostAnswer := Host.RunTask(TaskId, Note, SaveFirst, CommandId);
      'insert_task': HostAnswer := Host.InsertTask(TaskId, Note);
    Else
      HostAnswer := BusyAnswer('That command is not available.');
    End;
  If Assigned(Host) Then
    Answer := AnswerFromHost(HostAnswer, Status);
  If (Kind = 'stop') Or (Kind = 'stop_plan') Then
    SetStopPending(False);
  EnterCriticalSection(CommandLock);
  Try
    If Not IsIdempotent(Kind) Then
      Remember(CommandId, Status, Answer);
    If Assigned(Event) Then
      RTLEventSetEvent(Event);
  Finally
    LeaveCriticalSection(CommandLock);
  End;
  Release;
End;

Function JsonText(Obj: TJSONObject; Const Name: String): String;
Begin
  If Assigned(Obj) And Assigned(Obj.Find(Name)) Then
    Result := Obj.Get(Name, '')
  Else
    Result := '';
End;

Function JsonBool(Obj: TJSONObject; Const Name: String): Boolean;
Begin
  Result := Assigned(Obj) And Assigned(Obj.Find(Name)) And Obj.Get(Name, False);
End;

Function KnownCapability(Const Kind: String): Boolean;
Const
  Names: Array[0..14] Of String = (
    'send', 'steer', 'stop', 'approval', 'set_mode', 'new_conversation', 'select_conversation', 'select_plan',
    'new_plan', 'close_plan', 'run_plan', 'stop_plan', 'work_on_plan', 'run_task', 'insert_task');
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 0 To High(Names) Do
    If Names[Index] = Kind Then
      Exit(True);
End;

Procedure AddMonitorCommandCapabilities(List: TStrings);
Const
  Names: Array[0..14] Of String = (
    'send', 'steer', 'stop', 'approval', 'set_mode', 'new_conversation', 'select_conversation', 'select_plan',
    'new_plan', 'close_plan', 'run_plan', 'stop_plan', 'work_on_plan', 'run_task', 'insert_task');
Var
  Index: Integer;
Begin
  If Not Assigned(List) Then
    Exit;
  For Index := 0 To High(Names) Do
    List.Add(Names[Index]);
End;

Function ServeMonitorCommand(Const RequestBody: String; Out Status: Integer; Out Answer: String): Boolean;
Var
  Data: TJSONData;
  Root, Args: TJSONObject;
  Kind, CommandId, TurnId, Decision: String;
  Job: TCommandJob;
  Host: TMonitorCommandHost;
  Wake: PRTLEvent;
Begin
  Result := True;
  Status := 400;
  Answer := ErrorJson('protocol', 'The command was not understood.');
  Data := Nil;
  Try
    Data := GetJSON(RequestBody);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Root := TJSONObject(Data);
  Try
    CommandId := Trim(JsonText(Root, 'id'));
    Kind := LowerCase(Trim(JsonText(Root, 'type')));
    If Root.Find('args') Is TJSONObject Then
      Args := TJSONObject(Root.Find('args'))
    Else
      Args := Nil;
    If (CommandId = '') Or (Kind = '') Or (Not KnownCapability(Kind)) Then
      Begin
        Answer := ErrorJson('protocol', 'That command type is not available.');
        Exit;
      End;
    If Kind = 'approval' Then
      Begin
        Decision := LowerCase(Trim(JsonText(Args, 'decision')));
        If (Decision <> 'allow') And (Decision <> 'deny') Then
          Begin
            Answer := ErrorJson('protocol', 'The approval decision was not understood.');
            Exit;
          End;
        If Decision = 'allow' Then
          StoreAssistantApprovalDecision(aadAllow)
        Else
          StoreAssistantApprovalDecision(aadDeny);
        SignalAssistantApprovalWait;
      End;
    Host := CommandHost;
    If UsesStoreIdentity(Kind) And Assigned(Host) And Host.KnownTurn(CommandId, TurnId) Then
      Begin
        Status := 200;
        Answer := DoneJson('done', TurnId);
        EnterCriticalSection(CommandLock);
        Try
          Remember(CommandId, Status, Answer);
        Finally
          LeaveCriticalSection(CommandLock);
        End;
        Exit;
      End;
    If Not IsIdempotent(Kind) Then
      Begin
        EnterCriticalSection(CommandLock);
        Try
          If Recall(CommandId, Status, Answer) Then
            Exit;
          Remember(CommandId, 200, DoneJson('accepted', ''));
        Finally
          LeaveCriticalSection(CommandLock);
        End;
      End;
    If Not Assigned(Host) And (Kind <> 'approval') Then
      Begin
        Status := 503;
        Answer := ErrorJson('no_session', 'The assistant window is closed.');
        Exit;
      End;
    Job := TCommandJob.Create;
    Job.Kind := Kind;
    Job.CommandId := CommandId;
    Job.Text := JsonText(Args, 'text');
    Job.SaveFirst := JsonBool(Args, 'save_first');
    Job.ConversationId := JsonText(Args, 'id');
    Job.PlanPath := JsonText(Args, 'path');
    Job.Title := JsonText(Args, 'title');
    Job.TaskId := JsonText(Args, 'task_id');
    Job.Note := JsonText(Args, 'note');
    Job.ModeText := JsonText(Args, 'mode');
    Job.ToolId := JsonText(Args, 'tool_id');
    Job.Decision := Decision;
    Job.SectionIndex := 0;
    If Assigned(Args) And Assigned(Args.Find('section')) Then
      Job.SectionIndex := Args.Get('section', 0);
    Job.Priority := IsPriority(Kind);
    Job.Refs := 1;
    If (Kind = 'stop') Or (Kind = 'stop_plan') Then
      SetStopPending(True);
    If Job.Priority Then
      Begin
        TThread.Queue(Nil, @Job.Execute);
        Status := 200;
        Answer := DoneJson('accepted', '');
        Exit;
      End;
    Job.Event := RTLEventCreate;
    InterlockedIncrement(Job.Refs);
    TThread.Queue(Nil, @Job.Execute);
    RTLEventWaitFor(Job.Event, MonitorCommandWaitMs);
    EnterCriticalSection(CommandLock);
    Try
      If Not Recall(CommandId, Status, Answer) Then
        Begin
          Status := 200;
          Answer := DoneJson('accepted', '');
        End;
      Wake := Job.Event;
      Job.Event := Nil;
    Finally
      LeaveCriticalSection(CommandLock);
    End;
    If Assigned(Wake) Then
      RTLEventDestroy(Wake);
    Job.Release;
  Finally
    Root.Free;
  End;
End;

Procedure SetMonitorCommandHost(Host: TMonitorCommandHost);
Begin
  CommandHost := Host;
End;

Procedure ResetMonitorCommands;
Var
  Index: Integer;
Begin
  EnterCriticalSection(CommandLock);
  Try
    CommandStopPending := False;
    CommandTableNext := 0;
    For Index := 0 To MonitorCommandTableLimit - 1 Do
      CommandTable[Index].Used := False;
  Finally
    LeaveCriticalSection(CommandLock);
  End;
End;

Initialization
  InitCriticalSection(CommandLock);

Finalization
  DoneCriticalSection(CommandLock);

End.
