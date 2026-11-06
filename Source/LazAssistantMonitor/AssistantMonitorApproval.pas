Unit AssistantMonitorApproval;

{ Remote approval waiter. Does not send frames. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantTools;

Const
  MonitorApprovalWaitMs = 120000;
  MonitorApprovalSliceMs = 200;

Function AssistantMonitorApprovalWait(Const ToolName, ToolId, ArgumentsJson: String;
  Aborting: TAssistantApprovalAbort; Out ErrorText: String; Out Handled: Boolean): Boolean;
/// In-memory flag. A settings save updates the next tool prompt and does not touch the socket.
Procedure ApplyMonitorRemoteApproval(Enabled: Boolean);
Function MonitorRemoteApprovalEnabled: Boolean;

Implementation

Uses
  Classes, SyncObjs, AssistantConfig, AssistantSessionObserve;

Var
  ApprovalLock: TRTLCriticalSection;
  RemoteApproval: Boolean;

Function RunningOnMainThread: Boolean;
Begin
  Result := GetCurrentThreadID = MainThreadID;
End;

Function ApprovalSummary(Const ArgumentsJson: String): String;
Begin
  Result := Copy(Trim(ArgumentsJson), 1, 240);
  If Length(Trim(ArgumentsJson)) > 240 Then
    Result := Result + '…';
End;

Function AssistantMonitorApprovalWait(Const ToolName, ToolId, ArgumentsJson: String;
  Aborting: TAssistantApprovalAbort; Out ErrorText: String; Out Handled: Boolean): Boolean;
Var
  Mode: TAssistantApprovalMode;
  Event: PRTLEvent;
  Notice: TAssistantApprovalNotice;
  Decision: TAssistantApprovalDecision;
  Deadline: QWord;
  Aborted: Boolean;
  Reason: String;
Begin
  Result := False;
  Handled := False;
  ErrorText := '';
  If (ToolId = '') Or (Not MonitorRemoteApprovalEnabled) Then
    Exit;
  Mode := aamAsk;
  If Assigned(AssistantChatConfig) Then
    Mode := AssistantChatConfig.GetApprovalMode;
  If (Mode <> aamAsk) Or RunningOnMainThread Then
    Exit;
  Event := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Event);
    Notice := Default(TAssistantApprovalNotice);
    Notice.Active := True;
    Notice.ToolId := ToolId;
    Notice.ToolName := ToolName;
    Notice.Summary := ApprovalSummary(ArgumentsJson);
    Notice.ModeCaption := ApprovalModeCaption(Mode);
    Notice.DecisionsAccepted := True;
    Notice.Reason := '';
    PublishAssistantApproval(Notice);
    Deadline := GetTickCount64 + MonitorApprovalWaitMs;
    Reason := 'denied';
    Repeat
      RTLEventWaitFor(Event, MonitorApprovalSliceMs);
      Decision := ReadAssistantApprovalDecision;
      Aborted := Assigned(Aborting) And Aborting();
      If Aborted Or (Decision = aadStopped) Then
        Begin
          Reason := 'stopped';
          Break;
        End;
      If Decision = aadAllow Then
        Begin
          Result := True;
          Reason := 'allowed';
          Break;
        End;
      If Decision = aadDeny Then
        Begin
          Reason := 'denied';
          ErrorText := 'User denied tool "' + ToolName + '" (approval mode: Ask).';
          Break;
        End;
      If GetTickCount64 >= Deadline Then
        Begin
          Reason := 'timeout';
          ErrorText := 'Approval timed out.';
          Break;
        End;
    Until False;
    Handled := True;
    If (Not Result) And (ErrorText = '') And (Reason = 'stopped') Then
      ErrorText := 'stopped';
    ClearAssistantApproval(ToolId, Reason);
  Finally
    { Disarm first. A later cancel, decision or desktop stop then signals nothing, not this freed event. }
    DisarmAssistantApprovalWait(Event);
    RTLEventDestroy(Event);
  End;
End;

Procedure ApplyMonitorRemoteApproval(Enabled: Boolean);
Begin
  EnterCriticalSection(ApprovalLock);
  Try
    RemoteApproval := Enabled;
  Finally
    LeaveCriticalSection(ApprovalLock);
  End;
End;

Function MonitorRemoteApprovalEnabled: Boolean;
Begin
  EnterCriticalSection(ApprovalLock);
  Try
    Result := RemoteApproval;
  Finally
    LeaveCriticalSection(ApprovalLock);
  End;
End;

Initialization

InitCriticalSection(ApprovalLock);
RemoteApproval := False;

Finalization

DoneCriticalSection(ApprovalLock);

End.
