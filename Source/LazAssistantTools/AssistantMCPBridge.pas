Unit AssistantMCPBridge;

{ Runs MCP tool calls from the listener's threads on the IDE thread through the tool broker (c) 2026 Michell Computing.

  The broker refuses any thread but the one that made it, and its adapter touches IDE buffers. Execute is the
  listener's executor: it queues the call to the main thread with TThread.Queue and waits for the answer. Cancel,
  for Stop or the end of the run, releases every waiting call with an error at once, without waiting for the IDE
  thread; a queued call it released is then skipped when it comes up, so it never reaches the broker.

  The broker's write scope comes from the turn's Claude tool scope, so a mode maps onto permissions in one place. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantToolBroker, AssistantClaudeClient, AssistantConversation;

Const
  MCPRunCancelledText = 'The Claude run was stopped before this tool ran.';

Type
  TMCPBrokerBridge = Class
  Private
    FBroker: TAssistantToolBroker;
    FRunId: String;
    Lock: TRTLCriticalSection;
    Pending: TList;
    Cancelled: Boolean;
    Function GetPendingCount: Integer;
  Public
    { The broker is borrowed and must outlive the bridge. Create, BeginRun, Cancel and ToolsJSON run on the IDE thread. }
    Constructor Create(ToolBroker: TAssistantToolBroker);
    Destructor Destroy; Override;
    /// Starts a broker run with the write scope for this Claude tool scope, cancelling any run still open.
    Function BeginRun(Scope: TClaudeToolScope): String; Overload;
    /// Same run, with the turn's mode so Plan and Document are not collapsed.
    Function BeginRun(Scope: TClaudeToolScope; Mode: TAssistantMode): String; Overload;
    /// Ends the run: every waiting call returns MCPRunCancelledText and later calls are refused until BeginRun.
    Procedure Cancel;
    /// The broker's catalogue for this run's scope, to hand to TMCPListener.
    Function ToolsJSON: String;
    /// A TMCPToolExecutor. Safe from any thread; blocks until the IDE thread has run the call or the run is cancelled.
    Function Execute(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
    Property Broker: TAssistantToolBroker Read FBroker;
    Property RunId: String Read FRunId;
    /// Calls waiting for the IDE thread.
    Property PendingCount: Integer Read GetPendingCount;
  End;

/// The broker write scope for a Claude tool scope: the same permissions the Codex launch gives each mode.
Function ClaudeBrokerWriteScope(Scope: TClaudeToolScope): TAssistantWriteScope;
/// What an approval names for a broker write: the path, the changed line range and the start of the new lines,
/// short enough for the confirmation's 240 characters. Without a path, the start of NewText (git arguments).
Function MCPApprovalSummary(Const Path, OldText, NewText: String): String;

Implementation

Uses
  fpjson;

Type
  { One queued call, shared by the waiting listener thread and the queued Run. The last Release frees it. }
  TMCPPendingCall = Class
  Private
    CallLock: TRTLCriticalSection;
    References: Integer;
    Abandoned: Boolean;
    Done: Boolean;
  Public
    Broker: TAssistantToolBroker;
    RunId, Tool, Arguments: String;
    Succeeded: Boolean;
    ResultText, ErrorText: String;
    Finished: PRTLEvent;
    Constructor Create(CallBroker: TAssistantToolBroker; Const CallRunId, CallTool, CallArguments: String);
    Destructor Destroy; Override;
    Procedure Release;
    { False when the call had already run, so its result stands. }
    Function Abandon: Boolean;
    Function HasRun: Boolean;
    Procedure Run;
  End;

Function ClaudeBrokerWriteScope(Scope: TClaudeToolScope): TAssistantWriteScope;
Begin
  Case Scope Of
    ctsNone: Result := awsNone;
    ctsMarkdown: Result := awsMarkdown;
    ctsProject: Result := awsProject;
  Else
    Result := awsReadOnly;
  End;
End;

Function MCPApprovalSummary(Const Path, OldText, NewText: String): String;
Const
  SnippetChars = 100;
Var
  OldLines, NewLines: TStringList;
  First, OldLast, NewLast, I: Integer;
  Change, Snippet: String;
Begin
  If Path = '' Then
    Begin
      Result := Copy(NewText, 1, 240);
      Exit;
    End;
  OldLines := TStringList.Create;
  NewLines := TStringList.Create;
  Try
    OldLines.Text := OldText;
    NewLines.Text := NewText;
    First := 0;
    While (First < OldLines.Count) And (First < NewLines.Count) And (OldLines[First] = NewLines[First]) Do
      Inc(First);
    OldLast := OldLines.Count - 1;
    NewLast := NewLines.Count - 1;
    While (OldLast >= First) And (NewLast >= First) And (OldLines[OldLast] = NewLines[NewLast]) Do
      Begin
        Dec(OldLast);
        Dec(NewLast);
      End;
    If OldText = NewText Then
      Change := 'no change'
    Else If OldText = '' Then
      Change := 'new text, ' + IntToStr(NewLines.Count) + ' lines'
    Else If OldLast < First Then
      Change := IntToStr(NewLast - First + 1) + ' lines inserted after line ' + IntToStr(First) + ' of ' +
        IntToStr(OldLines.Count)
    Else
      Change := 'lines ' + IntToStr(First + 1) + '-' + IntToStr(OldLast + 1) + ' of ' + IntToStr(OldLines.Count) +
        ' replaced by ' + IntToStr(NewLast - First + 1);
    Snippet := '';
    For I := First To NewLast Do
      Begin
        If Snippet <> '' Then
          Snippet := Snippet + ' / ';
        Snippet := Snippet + Trim(NewLines[I]);
        If Length(Snippet) >= SnippetChars Then
          Break;
      End;
    If Length(Snippet) > SnippetChars Then
      Snippet := Copy(Snippet, 1, SnippetChars) + '…';
    Result := '{"path":"' + StringToJSONString(Path) + '","change":"' + Change + '"';
    If Snippet <> '' Then
      Result := Result + ',"new":"' + StringToJSONString(Snippet) + '"';
    Result := Result + '}';
  Finally
    NewLines.Free;
    OldLines.Free;
  End;
End;

{ TMCPPendingCall }

Constructor TMCPPendingCall.Create(CallBroker: TAssistantToolBroker; Const CallRunId, CallTool, CallArguments: String);
Begin
  Inherited Create;
  InitCriticalSection(CallLock);
  { The waiter and the queued Run. }
  References := 2;
  Abandoned := False;
  Done := False;
  Broker := CallBroker;
  RunId := CallRunId;
  Tool := CallTool;
  Arguments := CallArguments;
  Succeeded := False;
  ResultText := '';
  ErrorText := '';
  Finished := RTLEventCreate;
End;

Destructor TMCPPendingCall.Destroy;
Begin
  RTLEventDestroy(Finished);
  DoneCriticalSection(CallLock);
  Inherited Destroy;
End;

Procedure TMCPPendingCall.Release;
Var
  Last: Boolean;
Begin
  EnterCriticalSection(CallLock);
  Try
    Dec(References);
    Last := References <= 0;
  Finally
    LeaveCriticalSection(CallLock);
  End;
  If Last Then
    Free;
End;

Function TMCPPendingCall.Abandon: Boolean;
Begin
  EnterCriticalSection(CallLock);
  Try
    Result := Not Done;
    If Result Then
      Abandoned := True;
  Finally
    LeaveCriticalSection(CallLock);
  End;
  RTLEventSetEvent(Finished);
End;

Function TMCPPendingCall.HasRun: Boolean;
Begin
  EnterCriticalSection(CallLock);
  Try
    Result := Done;
  Finally
    LeaveCriticalSection(CallLock);
  End;
End;

{ On the IDE thread. A call abandoned while it waited in the queue is skipped: the bridge and the broker may be gone. }
Procedure TMCPPendingCall.Run;
Var
  Skip: Boolean;
  CallSucceeded: Boolean;
  CallResult, CallError: String;
Begin
  Try
    EnterCriticalSection(CallLock);
    Try
      Skip := Abandoned;
    Finally
      LeaveCriticalSection(CallLock);
    End;
    If Skip Then
      Exit;
    CallResult := '';
    CallError := '';
    Try
      CallSucceeded := Broker.Execute(RunId, Tool, Arguments, CallResult, CallError);
    Except
      On E: Exception Do
        Begin
          CallSucceeded := False;
          CallError := 'The tool raised ' + E.ClassName + ': ' + E.Message;
        End;
    End;
    EnterCriticalSection(CallLock);
    Try
      { An approval dialog can let Cancel in while the broker runs; the waiter has then gone with the cancel error. }
      If Not Abandoned Then
        Begin
          Succeeded := CallSucceeded;
          ResultText := CallResult;
          ErrorText := CallError;
          Done := True;
        End;
    Finally
      LeaveCriticalSection(CallLock);
    End;
    RTLEventSetEvent(Finished);
  Finally
    Release;
  End;
End;

{ TMCPBrokerBridge }

Constructor TMCPBrokerBridge.Create(ToolBroker: TAssistantToolBroker);
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  Pending := TList.Create;
  FBroker := ToolBroker;
  FRunId := '';
  Cancelled := True;
End;

Destructor TMCPBrokerBridge.Destroy;
Begin
  Cancel;
  FreeAndNil(Pending);
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

Function TMCPBrokerBridge.GetPendingCount: Integer;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := Pending.Count;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TMCPBrokerBridge.BeginRun(Scope: TClaudeToolScope): String;
Var
  NewRunId: String;
Begin
  Cancel;
  { One-argument broker start. Markdown becomes Plan; a live turn passes ActiveMode instead. }
  NewRunId := FBroker.BeginRun(ClaudeBrokerWriteScope(Scope));
  EnterCriticalSection(Lock);
  Try
    FRunId := NewRunId;
    Cancelled := False;
  Finally
    LeaveCriticalSection(Lock);
  End;
  Result := NewRunId;
End;

Function TMCPBrokerBridge.BeginRun(Scope: TClaudeToolScope; Mode: TAssistantMode): String;
Var
  NewRunId: String;
Begin
  Cancel;
  NewRunId := FBroker.BeginRun(ClaudeBrokerWriteScope(Scope), Mode);
  EnterCriticalSection(Lock);
  Try
    FRunId := NewRunId;
    Cancelled := False;
  Finally
    LeaveCriticalSection(Lock);
  End;
  Result := NewRunId;
End;

Procedure TMCPBrokerBridge.Cancel;
Var
  I: Integer;
  EndedRun: String;
Begin
  EnterCriticalSection(Lock);
  Try
    Cancelled := True;
    EndedRun := FRunId;
    { Each waiter takes its own call out of the list once it wakes. }
    For I := 0 To Pending.Count - 1 Do
      TMCPPendingCall(Pending[I]).Abandon;
  Finally
    LeaveCriticalSection(Lock);
  End;
  { Leave the broker alone if something else has started a newer run on it. }
  If Assigned(FBroker) And (EndedRun <> '') And (FBroker.RunId = EndedRun) Then
    FBroker.Cancel;
End;

Function TMCPBrokerBridge.ToolsJSON: String;
Begin
  Result := FBroker.ToolsJson;
End;

Function TMCPBrokerBridge.Execute(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
Var
  Call: TMCPPendingCall;
  CallRunId: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If GetCurrentThreadId = MainThreadID Then
    Begin
      EnterCriticalSection(Lock);
      Try
        CallRunId := FRunId;
        If Cancelled Then
          CallRunId := '';
      Finally
        LeaveCriticalSection(Lock);
      End;
      If CallRunId = '' Then
        ErrorText := MCPRunCancelledText
      Else
        Result := FBroker.Execute(CallRunId, Tool, Arguments, ResultText, ErrorText);
      Exit;
    End;
  EnterCriticalSection(Lock);
  Try
    If Cancelled Then
      Begin
        ErrorText := MCPRunCancelledText;
        Exit;
      End;
    Call := TMCPPendingCall.Create(FBroker, FRunId, Tool, Arguments);
    Pending.Add(Call);
    { Queued under the lock, so Cancel either sees this call in the list or ran before it was made. }
    TThread.Queue(Nil, @Call.Run);
  Finally
    LeaveCriticalSection(Lock);
  End;
  RTLEventWaitFor(Call.Finished);
  EnterCriticalSection(Lock);
  Try
    Pending.Remove(Call);
  Finally
    LeaveCriticalSection(Lock);
  End;
  If Call.HasRun Then
    Begin
      Result := Call.Succeeded;
      ResultText := Call.ResultText;
      ErrorText := Call.ErrorText;
    End
  Else
    ErrorText := MCPRunCancelledText;
  Call.Release;
End;

End.
