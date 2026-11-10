Unit AssistantMain;

{ Core registration, menus, commands and window creation for LazAssistantTools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf, ProjectIntf;

Procedure RegisterAssistantTools;

Var
  ProjectAssistantWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, WorkflowSettings, ProjectAssistantForm, AssistantService, AssistantSettingsForm,
  AssistantMarkdownForm, AssistantConfig, GrokOAuth, IDEMsgIntf, IDEExternToolIntf;

Type
  { Context menu on IDE Messages: Ask Assistant to fix the selected line. }
  TAssistantFixMessageQuickFix = Class(TMsgQuickFix)
  Public
    Procedure CreateMenuItems(Fixes: TMsgQuickFixes); Override;
    Procedure QuickFix(Fixes: TMsgQuickFixes; Msg: TMessageLine); Override;
  End;

  TAssistantIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; LazProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; LazProject: TLazProject): TModalResult;
    Procedure AssistantMenuShow(Sender: TObject);
  End;

Var
  CmdAssistantChat: TIDECommand;
  CmdAssistantNewMarkdown: TIDECommand;
  CmdAssistantOpenMarkdown: TIDECommand;
  CmdAssistantReviewCompile: TIDECommand;
  CmdAssistantReviewBuild: TIDECommand;
  CmdAssistantFixError: TIDECommand;
  CmdAssistantTasks: TIDECommand;
  CmdAssistantSettings: TIDECommand;
  AssistantFixQuickFix: TAssistantFixMessageQuickFix;
  AssistantIDEHooks: TAssistantIDEHooks;
  AssistantMenuRoot: TIDEMenuSection;
  AssistantTasksMenuItem: TIDEMenuItem;

Procedure ShowProjectAssistantWindow(Sender: TObject);
Begin
  Try
    If Assigned(IDEWindowCreators) And Assigned(ProjectAssistantWindowCreator) Then
      IDEWindowCreators.ShowForm(ProjectAssistantWindowCreator.FormName, True);
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'ShowProjectAssistantWindow: ' + E.Message);
      End;
  End;
End;

Function GetProjectAssistantForm(ShowWindow: Boolean = True): TProjectAssistantForm;
Var
  Form: TCustomForm;
Begin
  Result := Nil;
  If Not Assigned(IDEWindowCreators) Or Not Assigned(ProjectAssistantWindowCreator) Then Exit;
  If ShowWindow Then
    ShowProjectAssistantWindow(Nil);
  Form := IDEWindowCreators.GetForm(ProjectAssistantWindowCreator.FormName, True);
  If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
    Result := TProjectAssistantForm(Form);
End;

Procedure SyncAssistantTasksMenu;
Begin
  If Assigned(AssistantTasksMenuItem) Then
    AssistantTasksMenuItem.Visible := AssistantTasksActionVisible;
End;

Procedure DoAssistantTasks(Sender: TObject);
Var
  Form: TProjectAssistantForm;
Begin
  If Not AssistantTasksActionVisible Then
    Exit;
  Form := GetProjectAssistantForm(True);
  If Assigned(Form) Then
    Form.TasksActionExecute(Sender);
End;

Procedure DoAssistantSettings(Sender: TObject);
Begin
  ShowAssistantSettingsForm;
End;

Procedure DoAssistantNewMarkdown(Sender: TObject);
Begin
  WorkflowLogger.Info('ProjectAssistant', 'New Markdown document requested');
  OpenNewMarkdownDocument;
End;

Procedure DoAssistantOpenMarkdown(Sender: TObject);
Begin
  WorkflowLogger.Info('ProjectAssistant', 'Open Markdown document requested');
  OpenMarkdownDocument('');
End;

Procedure DoAssistantReviewCompile(Sender: TObject);
Var
  Form: TProjectAssistantForm;
Begin
  Form := GetProjectAssistantForm(True);
  If Assigned(Form) Then
    Form.ReviewCompile;
End;

Procedure DoAssistantReviewBuild(Sender: TObject);
Var
  Form: TProjectAssistantForm;
Begin
  Form := GetProjectAssistantForm(True);
  If Assigned(Form) Then
    Form.ReviewBuild;
End;

Procedure DoAssistantFixError(Sender: TObject);
Var
  Form: TProjectAssistantForm;
Begin
  Form := GetProjectAssistantForm(True);
  If Assigned(Form) Then
    Form.FixTopError;
End;

Procedure TAssistantFixMessageQuickFix.CreateMenuItems(Fixes: TMsgQuickFixes);
Var
  I: Integer;
  Msg: TMessageLine;
Begin
  For I := 0 To Fixes.LineCount - 1 Do
    Begin
      Msg := Fixes.Lines[I];
      If Not Assigned(Msg) Then
        Continue;
      If Msg.Urgency < mluHint Then
        Continue;
      Fixes.AddMenuItem(Self, Msg, 'Ask Assistant to Fix...');
      Exit;
    End;
End;

Procedure TAssistantFixMessageQuickFix.QuickFix(Fixes: TMsgQuickFixes; Msg: TMessageLine);
Var
  Form: TProjectAssistantForm;
Begin
  If Assigned(Msg) And Assigned(IDEMessagesWindow) Then
    IDEMessagesWindow.SelectMsgLine(Msg);
  Form := GetProjectAssistantForm(True);
  If Assigned(Form) Then
    Form.FixTopError;
End;

Procedure CreateProjectAssistantForm(Sender: TObject; FormName: String;
  Var Form: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  Form := Nil;
  If Not Assigned(LazarusIDE) Then Exit;
  Try
    { A failed constructor frees its instance: do not expose it before success. }
    Form := TProjectAssistantForm.Create(LazarusIDE.OwningComponent);
    Form.Name := FormName;
    If DoDisableAutoSizing Then
      Form.DisableAutoSizing{$IFDEF DebugDisableAutoSizing}('TAnchorDockMaster Delayed'){$ENDIF};
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('ProjectAssistant', 'CreateProjectAssistantForm: ' + E.Message);
        FreeAndNil(Form);
      End;
  End;
End;

Procedure TAssistantIDEHooks.AssistantMenuShow(Sender: TObject);
Begin
  SyncAssistantTasksMenu;
End;

Function TAssistantIDEHooks.ProjectOpened(Sender: TObject; LazProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  Try
    If Assigned(LazProject) Then
      WorkflowLogger.Info('ProjectAssistant', 'Project opened: ' + LazProject.ProjectInfoFile)
    Else
      WorkflowLogger.Info('ProjectAssistant', 'Project opened (nil)');
    { New project create and load both fire this; rebind open Project Assistant windows. }
    NotifyOpenProjectAssistantFormsProjectChanged;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'TAssistantIDEHooks.ProjectOpened: ' + E.Message);
      End;
  End;
End;

Function TAssistantIDEHooks.ProjectClose(Sender: TObject; LazProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  Try
    { Do not rebind from ActiveProject here – it is half-torn-down during close.
      Clear open forms; ProjectOpened rebinds when the next project is ready. }
    WorkflowLogger.Info('ProjectAssistant', 'Project closing');
    NotifyOpenProjectAssistantFormsProjectCleared;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'TAssistantIDEHooks.ProjectClose: ' + E.Message);
      End;
  End;
End;

Function SuggestCommitMessageHandler(Const DiffText, StatusSummary: String;
  Out MessageText, ErrorText: String): Boolean;
Const
  MaxDiffChars = 48000;
Var
  SystemPrompt, UserPrompt, DiffBody, Raw: String;
  SL: TStringList;
Begin
  Result := False;
  MessageText := '';
  ErrorText := '';
  If Not Assigned(AssistantClient) Then
    Begin
      ErrorText := 'Assistant service is not available.';
      Exit;
    End;
  If Assigned(AssistantChatConfig) Then
    AssistantClient.ApplyConfig(AssistantChatConfig);
  DiffBody := DiffText;
  If Length(DiffBody) > MaxDiffChars Then
    DiffBody := Copy(DiffBody, 1, MaxDiffChars) + LineEnding +
      LineEnding + '… [diff truncated for prompt size]';
  SystemPrompt :=
    'You write concise Git commit messages for Free Pascal / Lazarus projects. ' +
    'Output ONLY the commit message text: a short subject line (imperative, ~50–72 chars), ' +
    'optionally a blank line and a short body. No markdown fences, no quotes, no preamble.';
  UserPrompt :=
    'Write a commit message for the staged changes below.' + LineEnding + LineEnding;
  If Trim(StatusSummary) <> '' Then
    UserPrompt := UserPrompt + 'Status:' + LineEnding + StatusSummary + LineEnding + LineEnding;
  UserPrompt := UserPrompt + 'Diff:' + LineEnding + DiffBody;
  If Not AssistantClient.CompleteOnce(SystemPrompt, UserPrompt, Raw, ErrorText) Then
    Exit;
  { Strip accidental fences / surrounding quotes. }
  Raw := Trim(Raw);
  If Copy(Raw, 1, 3) = '```' Then
    Begin
      SL := TStringList.Create;
      Try
        SL.Text := Raw;
        If SL.Count > 0 Then
          SL.Delete(0);
        If (SL.Count > 0) And (Copy(Trim(SL[SL.Count - 1]), 1, 3) = '```') Then
          SL.Delete(SL.Count - 1);
        Raw := Trim(SL.Text);
      Finally
        SL.Free;
      End;
    End;
  If (Length(Raw) >= 2) And (Raw[1] = '"') And (Raw[Length(Raw)] = '"') Then
    Raw := Copy(Raw, 2, Length(Raw) - 2);
  MessageText := Trim(Raw);
  Result := MessageText <> '';
  If Not Result Then
    ErrorText := 'Model returned an empty commit message.';
End;

Procedure RegisterAssistantTools;
Var
  AssistantMenu, MainSec, WorkSec, SetSec: TIDEMenuSection;
  AfterItem: TIDEMenuItem;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
  InsertAt: Integer;
Begin
  Try
    WorkflowLogger.Info('ProjectAssistant', 'Registering LazAssistantTools');

    If AssistantIDEHooks = Nil Then
      AssistantIDEHooks := TAssistantIDEHooks.Create;

    If Assigned(LazarusIDE) Then
      SetWorkflowSettingsDirectory(LazarusIDE.GetPrimaryConfigPath);
    If Assigned(AssistantChatConfig) Then
      Try
        AssistantChatConfig.Load;
        If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
          GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);
      Except
        On E: Exception Do
          WorkflowLogger.Warning('ProjectAssistant', 'Config load failed: ' + E.Message);
      End;

    SuggestCommitMessageFunc := @SuggestCommitMessageHandler;

    Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
    If Cat = Nil Then
      Cat := IDECommandList.CreateCategory(Nil, 'Assistant', 'Assistant');

    Key := IDEShortCut(VK_UNKNOWN, []);
    CmdAssistantChat := RegisterIDECommand(Cat, 'ProjectAssistant', 'Project Assistant', Key, Nil, @ShowProjectAssistantWindow);
    CmdAssistantNewMarkdown := RegisterIDECommand(Cat, 'AssistantNewMarkdown', 'New Markdown Document', Key, Nil, @DoAssistantNewMarkdown);
    CmdAssistantOpenMarkdown := RegisterIDECommand(Cat, 'AssistantOpenMarkdown', 'Open Markdown Document', Key, Nil, @DoAssistantOpenMarkdown);
    CmdAssistantReviewCompile := RegisterIDECommand(Cat, 'AssistantReviewCompile', 'Review Compile',
      Key, Nil, @DoAssistantReviewCompile);
    CmdAssistantReviewBuild := RegisterIDECommand(Cat, 'AssistantReviewBuild', 'Review Build',
      Key, Nil, @DoAssistantReviewBuild);
    CmdAssistantFixError := RegisterIDECommand(Cat, 'AssistantFixError', 'Fix Selected Message with Assistant',
      Key, Nil, @DoAssistantFixError);
    CmdAssistantTasks := RegisterIDECommand(Cat, 'AssistantTasks', 'Tasks…', Key, Nil, @DoAssistantTasks);
    CmdAssistantSettings := RegisterIDECommand(Cat, 'AssistantSettings', 'Project Assistant Settings', Key, Nil, @DoAssistantSettings);

    { Top-level Assistant menu, placed immediately after Repository (fallback: after Run).
      Separate sections so Lazarus draws a separator after Project Assistant and before Settings. }
    AssistantMenu := RegisterIDESubMenu(mnuMain, 'Assistant', '&Assistant');
    If Assigned(mnuMain) And Assigned(AssistantMenu) Then
      Begin
        mnuMain.Remove(AssistantMenu);
        AfterItem := mnuMain.FindByName('Repository');
        If Not Assigned(AfterItem) Then
          AfterItem := mnuRun;
        If Assigned(AfterItem) And (AfterItem.SectionIndex >= 0) Then
          InsertAt := AfterItem.SectionIndex + 1
        Else
          InsertAt := mnuMain.Count;
        If InsertAt > mnuMain.Count Then
          InsertAt := mnuMain.Count;
        mnuMain.Insert(InsertAt, AssistantMenu);
      End;
    MainSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantMainCmds');
    RegisterIDEMenuCommand(MainSec, 'ProjectAssistant', 'Project Assistant', Nil, Nil, CmdAssistantChat);
    WorkSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantWorkCmds');
    RegisterIDEMenuCommand(WorkSec, 'AssistantNewMarkdown', 'New Markdown', Nil, Nil, CmdAssistantNewMarkdown);
    RegisterIDEMenuCommand(WorkSec, 'AssistantOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdAssistantOpenMarkdown);
    RegisterIDEMenuCommand(WorkSec, 'AssistantReviewCompile', 'Review Compile', Nil, Nil, CmdAssistantReviewCompile);
    RegisterIDEMenuCommand(WorkSec, 'AssistantReviewBuild', 'Review Build', Nil, Nil, CmdAssistantReviewBuild);
    RegisterIDEMenuCommand(WorkSec, 'AssistantFixError', 'Fix Error In Build Mode…', Nil, Nil, CmdAssistantFixError);
    SetSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantSettingsCmds');
    AssistantTasksMenuItem := RegisterIDEMenuCommand(SetSec, 'AssistantTasks', 'Tasks…', Nil, Nil, CmdAssistantTasks);
    RegisterIDEMenuCommand(SetSec, 'AssistantSettings', 'Settings…', Nil, Nil, CmdAssistantSettings);
    AssistantMenuRoot := AssistantMenu;
    OnAssistantTasksVisibilityChanged := @SyncAssistantTasksMenu;
    If Assigned(AssistantMenuRoot) And Assigned(AssistantIDEHooks) Then
      AssistantMenuRoot.AddHandlerOnShow(@AssistantIDEHooks.AssistantMenuShow);
    SyncAssistantTasksMenu;

    ProjectAssistantWindowCreator := IDEWindowCreators.Add('ProjectAssistant', @CreateProjectAssistantForm, Nil,
      '10%', '8%', '90%', '90%');

    If Not Assigned(AssistantFixQuickFix) Then
      Begin
        AssistantFixQuickFix := TAssistantFixMessageQuickFix.Create;
        RegisterIDEMsgQuickFix(AssistantFixQuickFix);
      End;

    If Assigned(LazarusIDE) Then
      Begin
        LazarusIDE.AddHandlerOnProjectOpened(@AssistantIDEHooks.ProjectOpened);
        LazarusIDE.AddHandlerOnProjectClose(@AssistantIDEHooks.ProjectClose);
      End;

    WorkflowLogger.Info('ProjectAssistant', 'LazAssistantTools registered successfully');
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'RegisterAssistantTools: ' + E.Message);
      End;
  End;
End;

Initialization

AssistantIDEHooks := Nil;

Finalization

OnAssistantTasksVisibilityChanged := Nil;
If Assigned(AssistantMenuRoot) And Assigned(AssistantIDEHooks) Then
  AssistantMenuRoot.RemoveHandlerOnShow(@AssistantIDEHooks.AssistantMenuShow);
If Assigned(LazarusIDE) And Assigned(AssistantIDEHooks) Then
  Begin
    LazarusIDE.RemoveHandlerOnProjectOpened(@AssistantIDEHooks.ProjectOpened);
    LazarusIDE.RemoveHandlerOnProjectClose(@AssistantIDEHooks.ProjectClose);
  End;
SuggestCommitMessageFunc := Nil;
FreeAndNil(AssistantIDEHooks);
If Assigned(AssistantFixQuickFix) And Assigned(MsgQuickFixes) Then
  MsgQuickFixes.UnregisterQuickFix(AssistantFixQuickFix);
{ The registry owns registered quick fixes. UnregisterQuickFix destroys the
  instance too; if the registry has already gone, it freed the instance during
  IDE shutdown. This is only a borrowed reference in either case. }
AssistantFixQuickFix := Nil;

End.
