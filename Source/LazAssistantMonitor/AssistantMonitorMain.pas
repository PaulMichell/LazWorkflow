Unit AssistantMonitorMain;

{ IDE menu for the remote monitor (c) 2026 Michell Computing.

  Looks up the Assistant menu registered by LazAssistantTools. Does not create a
  second top-level Assistant menu, and does not edit that package. Catalogue 3
  is removed. The menu and the dialog start and stop the HTTPS listener.
  Unregister the menu commands before stopping the listener. Shutdown WaitFor
  pumps the main thread, and a command that still points here could re-enter stop. }

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
  Classes, Contnrs, Dialogs, LCLType, MenuIntf, IDECommands, WorkflowLog, AssistantMonitorForm, AssistantMonitorSettings,
  AssistantMonitorServer, AssistantMonitorSnapshot, AssistantSessionObserve, AssistantConversation, AssistantPlan,
  AssistantPlanDocument, AssistantTasks, ProjectAssistantForm, AssistantMonitorStore;

Type
  TIdeSnapshotSource = Class(TMonitorSnapshotSource)
    Function Fill(Snap: TMonitorSnapshot): Boolean; Override;
  End;

Var
  RemoteMonitorCommand, StartCommand, StopCommand: TIDECommand;
  StoppingListener: Boolean;

Function HashText(Const Text: String): String;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If Text <> '' Then
    AssistantPlanHashFold(Hash, Text[1], Length(Text));
  Result := AssistantPlanHashHex(Hash);
End;

Function TIdeSnapshotSource.Fill(Snap: TMonitorSnapshot): Boolean;
Var
  Form: TProjectAssistantForm;
  View: TAssistantMonitorView;
  Turn: TAssistantMonitorTurn;
  ErrorText, Joined: String;
  History: TObjectList;
  Item: TConversationHistoryItem;
  Paths: TStringList;
  Tasks: TAssistantTaskArray;
  Index: Integer;
  FromCatalog: Boolean;
  Resolved: String;
Begin
  Result := True;
  SetLength(Tasks, 0);
  Form := OpenProjectAssistantForm;
  If Assigned(Form) Then
    Begin
      Form.FillMonitorView(View);
      Snap.Available := View.Available;
      Snap.Busy := View.Busy;
      Snap.Sending := View.Sending;
      Snap.PlanRunning := View.PlanRunning;
      Snap.SignedIn := View.SignedIn;
      Snap.CanSend := View.CanSend;
      Snap.CanSteer := View.CanSteer;
      Snap.CanStop := View.CanStop;
      Snap.CanChangeMode := View.CanChangeMode;
      Snap.RemoteApproval := View.RemoteApproval;
      Snap.StopPending := View.Sending And Form.FUserCancelled;
      Snap.Mode := View.Mode;
      Snap.Phase := View.Phase;
      Snap.StatusText := View.StatusText;
      Snap.Activity := View.StatusText;
      Snap.TurnStartedAt := View.StartedAt;
      If View.Sending Then
        Snap.ActivitySince := View.StartedAt;
      Snap.ElapsedMs := View.ElapsedMs;
      Snap.ErrorText := View.ErrorText;
      Snap.UsageCaption := View.UsageCaption;
      Snap.UsageHint := View.UsageHint;
      Snap.PlanPath := View.PlanPath;
      Snap.PlanItemRunning := View.PlanRunning;
      If View.PlanRunning Then
        Snap.PlanItem := Form.FBuildWorkSectionTitle;
      If Form.FillMonitorTurn(MonitorLiveTurnIndex, Turn, ErrorText) Then
        Begin
          Snap.HasLive := Turn.Id <> '';
          Snap.LiveTurnId := Turn.Id;
          Snap.LiveTurnIndex := Turn.TurnIndex;
          CopyMonitorTurn(Turn, Snap);
        End;
    End;
  If Assigned(ProjectAssistantConversation) Then
    Begin
      Snap.ConversationId := ProjectAssistantConversation.MonitorConversationId;
      Snap.ConversationTitle := ProjectAssistantConversation.MonitorTitle;
      Snap.TurnCount := ProjectAssistantConversation.TurnCount;
      Snap.ConversationEtag := HashText(Snap.ConversationId + '#' + IntToStr(Snap.TurnCount));
      History := TObjectList.Create(True);
      Paths := TStringList.Create;
      Try
        Joined := '';
        If ProjectAssistantConversation.ListHistory(History) Then
          For Index := 0 To History.Count - 1 Do
            Begin
              Item := TConversationHistoryItem(History[Index]);
              Joined := Joined + Item.ArchiveId + '|' + Item.Title + '|' + IntToStr(Item.TurnCount) + #10;
            End;
        Snap.ListConversations := HashText(Joined);
        Joined := '';
        If ProjectAssistantConversation.LoadAvailablePlanPaths(Paths) Then
          For Index := 0 To Paths.Count - 1 Do
            Joined := Joined + Paths[Index] + #10;
        Snap.ListPlans := HashText(Joined);
      Finally
        Paths.Free;
        History.Free;
      End;
    End;
  If (Snap.PlanPath <> '') And ResolvePlanPath(Snap.PlanPath, Resolved, ErrorText) Then
    Snap.PlanEtag := AssistantPlanHashFile(Resolved);
  If LoadAssistantTasks(Tasks, FromCatalog, ErrorText) Then
    Begin
      Joined := '';
      For Index := 0 To High(Tasks) Do
        Joined := Joined + Tasks[Index].Id + '|' + Tasks[Index].Title + #10;
      Snap.ListTasks := HashText(Joined);
    End;
End;

Function AssistantMonitorListenerRunning: Boolean;
Begin
  Result := MonitorHttpsRunning;
End;

Procedure UnregisterMonitorCommands;
Begin
  If Assigned(RemoteMonitorCommand) Then
    RemoteMonitorCommand.OnExecute := Nil;
  If Assigned(StartCommand) Then
    StartCommand.OnExecute := Nil;
  If Assigned(StopCommand) Then
    StopCommand.OnExecute := Nil;
End;

Procedure StopAssistantMonitorListener;
Begin
  { WaitFor pumps the main thread. A second entry must not join the listen thread again. }
  If StoppingListener Then
    Exit;
  StoppingListener := True;
  Try
    StopMonitorHttps;
    StopMonitorSnapshot;
  Finally
    StoppingListener := False;
  End;
End;

Function StartAssistantMonitorListener(Out ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
  Address: String;
Begin
  Result := False;
  ErrorText := '';
  If AssistantMonitorListenerRunning Then
    Begin
      Result := True;
      Exit;
    End;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  If Not ResolveMonitorBind(Settings, Address, ErrorText) Then
    Exit;
  If (Settings.Port <= 0) Or (Settings.Port > 65535) Then
    Begin
      ErrorText := 'The monitor port is not valid.';
      Exit;
    End;
  If Assigned(ProjectAssistantConversation) Then
    SetMonitorStoreRoot(ProjectAssistantConversation.ProjectRoot);
  StartMonitorSnapshot(TIdeSnapshotSource.Create);
  Result := StartMonitorHttps(Address, Settings.Port, ErrorText);
  If Not Result Then
    StopMonitorSnapshot;
End;

Procedure ShowRemoteMonitor(Sender: TObject);
Begin
  ShowAssistantMonitorForm;
End;

Procedure StartFromMenu(Sender: TObject);
Var
  ErrorText: String;
Begin
  If AssistantMonitorListenerRunning Then
    Exit;
  If Not StartAssistantMonitorListener(ErrorText) Then
    MessageDlg('Remote Monitor', ErrorText, mtError, [mbOK], 0);
End;

Procedure StopFromMenu(Sender: TObject);
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  StopAssistantMonitorListener;
  If LoadMonitorSettings(Settings, ErrorText) Then
    Begin
      Settings.Enabled := False;
      If Not SaveMonitorSettings(Settings, ErrorText) Then
        WorkflowLogger.Warning('AssistantMonitor', 'listen disabled was not stored: ' + ErrorText);
    End;
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
  If Not Assigned(StartCommand) Then
    StartCommand := RegisterIDECommand(Cat, 'AssistantRemoteMonitorStart', 'Start Remote Monitor', Key, Nil, @StartFromMenu);
  If Not Assigned(StopCommand) Then
    StopCommand := RegisterIDECommand(Cat, 'AssistantRemoteMonitorStop', 'Stop Remote Monitor', Key, Nil, @StopFromMenu);
  RegisterIDEMenuCommand(MonitorSec, 'AssistantRemoteMonitorStart', 'Start Remote Monitor', Nil, Nil, StartCommand);
  RegisterIDEMenuCommand(MonitorSec, 'AssistantRemoteMonitorStop', 'Stop Remote Monitor', Nil, Nil, StopCommand);
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

UnregisterMonitorCommands;
StopAssistantMonitorListener;

End.
