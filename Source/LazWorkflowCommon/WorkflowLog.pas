Unit WorkflowLog;

{ Simple logging façade for LazWorkflow packages (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

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
  { No WriteLn fallback: GUI Lazarus processes often have no console, and
    WriteLn during package load/register has caused hard failures on Windows. }
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

Initialization

WorkflowLogger := TWorkflowLogger.Create;

Finalization

FreeAndNil(WorkflowLogger);

End.
