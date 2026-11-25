Unit AssistantMonitorMain;

{ IDE menu for the remote monitor (c) 2026 Michell Computing.

  Looks up the Assistant menu registered by LazAssistantTools. Does not create a
  second top-level Assistant menu, and does not edit that package. Catalogue 3
  is removed. Start reports that the monitor is being rebuilt and does not open
  a socket. The old listener unregistered its bridge before stopping, because
  shutdown WaitFor pumps the main thread. The new listener must keep that order. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Procedure RegisterAssistantMonitor;
Procedure StopAssistantMonitorListener;
Function StartAssistantMonitorListener(Out ErrorText: String): Boolean;
Function AssistantMonitorListenerRunning: Boolean;

Implementation

Uses
  LCLType, MenuIntf, IDECommands, WorkflowLog, AssistantMonitorForm, AssistantMonitorSettings;

Var
  RemoteMonitorCommand: TIDECommand;

Function AssistantMonitorListenerRunning: Boolean;
Begin
  Result := False;
End;

Procedure StopAssistantMonitorListener;
Begin
End;

Function StartAssistantMonitorListener(Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := 'Remote monitor is being rebuilt';
End;

Procedure ShowRemoteMonitor(Sender: TObject);
Begin
  ShowAssistantMonitorForm;
End;

Procedure RegisterRemoteMonitorMenu;
Var
  Item: TIDEMenuItem;
  AssistantMenu, MonitorSec: TIDEMenuSection;
  Cat: TIDECommandCategory;
  Key: TIDEShortCut;
Begin
  If Not Assigned(mnuMain) Then
    Exit;
  Item := mnuMain.FindByName('Assistant');
  If Not (Item Is TIDEMenuSection) Then
    Begin
      WorkflowLogger.Warning('AssistantMonitor', 'Assistant menu is not registered. Remote Monitor was not added.');
      Exit;
    End;
  AssistantMenu := TIDEMenuSection(Item);
  Cat := IDECommandList.FindCategoryByName('Assistant');
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Assistant', 'Assistant');
  Key := IDEShortCut(VK_UNKNOWN, []);
  If Not Assigned(RemoteMonitorCommand) Then
    RemoteMonitorCommand := RegisterIDECommand(Cat, 'AssistantRemoteMonitor', 'Remote Monitor', Key, Nil,
      @ShowRemoteMonitor);
  MonitorSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantMonitorCmds');
  RegisterIDEMenuCommand(MonitorSec, 'AssistantRemoteMonitor', 'Remote Monitor…', Nil, Nil, RemoteMonitorCommand);
End;

Procedure RegisterAssistantMonitor;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  RegisterRemoteMonitorMenu;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  If Not Settings.Enabled Then
    Exit;
  If Not StartAssistantMonitorListener(ErrorText) Then
    WorkflowLogger.Warning('AssistantMonitor', 'enabled listener did not start: ' + ErrorText);
End;

Initialization

Finalization

StopAssistantMonitorListener;

End.
