Unit WorkflowLog;

{ Simple logging façade for LazWorkflow packages (c) 2026 Michell Computing.

  Add-in failures must not lock the IDE. TThread.Queue callbacks that raise are
  re-raised by CheckSynchronize on the IDE thread. The Qt event filter that
  pumps that queue does not catch Pascal exceptions, so the exception leaves
  Application.Run, Lazarus Halts, and the form designer can then show a modal
  Read error dialog while destroying a JIT component. Report the failure and
  do not let it escape a queued method. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, LazLoggerBase;

Type
  TWorkflowLogLevel = (wllDebug, wllInfo, wllWarning, wllError);

  TWorkflowLogEvent = Procedure(Level: TWorkflowLogLevel; Const Area, Message: String) Of Object;

  TWorkflowLogger = Class
  Private
    FOnLog: TWorkflowLogEvent;
    FMinLevel: TWorkflowLogLevel;
    Procedure DoLog(Level: TWorkflowLogLevel; Const Area, Message: String);
  Public
    Constructor Create;
    Procedure Debug(Const Area, Message: String);
    Procedure Info(Const Area, Message: String);
    Procedure Warning(Const Area, Message: String);
    Procedure Error(Const Area, Message: String);
    Property OnLog: TWorkflowLogEvent Read FOnLog Write FOnLog;
    Property MinLevel: TWorkflowLogLevel Read FMinLevel Write FMinLevel;
  End;

{ Log a caught add-in exception. Never raises. Call from the except block so the address is available. }
Procedure ReportPluginException(Const Area: String; E: Exception);

{ Drop pending Queue callbacks before freeing Thread. A callback on a freed thread is re-raised on the IDE thread. }
Procedure DiscardQueuedThreadMethods(Thread: TThread);

{ Main-thread queue pump. A queued failure is logged and swallowed so it cannot escape into the IDE. }
Procedure PumpPluginSynchronize(TimeoutMs: Integer);

Var
  WorkflowLogger: TWorkflowLogger;

Implementation

Constructor TWorkflowLogger.Create;
Begin
  Inherited Create;
  FMinLevel := wllInfo;
End;

Procedure TWorkflowLogger.DoLog(Level: TWorkflowLogLevel; Const Area, Message: String);
Begin
  If Level < FMinLevel Then
    Exit;
  If Assigned(FOnLog) Then
    Try
      FOnLog(Level, Area, Message);
    Except
      { Never let logging take down the IDE. }
    End;
  { DebugLn is safe in the IDE. Start Lazarus from a terminal to see it, or
    enable a debug log file (--debug-log=...). }
  DebugLn('[', Area, '] ', Message);
End;

Procedure TWorkflowLogger.Debug(Const Area, Message: String);
Begin
  DoLog(wllDebug, Area, Message);
End;

Procedure TWorkflowLogger.Info(Const Area, Message: String);
Begin
  DoLog(wllInfo, Area, Message);
End;

Procedure TWorkflowLogger.Warning(Const Area, Message: String);
Begin
  DoLog(wllWarning, Area, Message);
End;

Procedure TWorkflowLogger.Error(Const Area, Message: String);
Begin
  DoLog(wllError, Area, Message);
End;

Procedure ReportPluginException(Const Area: String; E: Exception);
Var
  Detail: String;
  FrameIndex, FrameLimit: Integer;
  Frames: PPointer;
Begin
  Try
    Detail := Area + ': ';
    If Assigned(E) Then
      Detail := Detail + E.ClassName + ': ' + E.Message
    Else
      Detail := Detail + 'unknown exception';
    If Assigned(BackTraceStrFunc) And (ExceptAddr <> Nil) Then
      Detail := Detail + ' at ' + BackTraceStrFunc(ExceptAddr);
    FrameLimit := ExceptFrameCount;
    If FrameLimit > 8 Then
      FrameLimit := 8;
    If (FrameLimit > 0) And Assigned(BackTraceStrFunc) Then
      Begin
        Frames := ExceptFrames;
        If Assigned(Frames) Then
          For FrameIndex := 0 To FrameLimit - 1 Do
            Detail := Detail + LineEnding + '  ' + BackTraceStrFunc(Frames[FrameIndex]);
      End;
    If Assigned(WorkflowLogger) Then
      WorkflowLogger.Error('PluginBoundary', Detail)
    Else
      DebugLn('[PluginBoundary] ', Detail);
  Except
    { Logging must not become the next unhandled exception. }
  End;
End;

Procedure DiscardQueuedThreadMethods(Thread: TThread);
Begin
  If Not Assigned(Thread) Then
    Exit;
  Try
    TThread.RemoveQueuedEvents(Thread);
  Except
    On E: Exception Do
      ReportPluginException('DiscardQueuedThreadMethods', E);
  End;
End;

Procedure PumpPluginSynchronize(TimeoutMs: Integer);
Begin
  If GetCurrentThreadId <> MainThreadID Then
    Exit;
  Try
    CheckSynchronize(TimeoutMs);
  Except
    On E: Exception Do
      ReportPluginException('CheckSynchronize', E);
  End;
End;

Initialization

WorkflowLogger := TWorkflowLogger.Create;

Finalization

FreeAndNil(WorkflowLogger);

End.
