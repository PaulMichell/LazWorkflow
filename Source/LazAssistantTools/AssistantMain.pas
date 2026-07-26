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
  WorkflowLog, WorkflowEvents, ProjectAssistantForm, AssistantService, AssistantSettingsForm, AssistantMarkdownForm,
  IDEMsgIntf, IDEExternToolIntf;

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
  End;

Var
  CmdAssistantChat: TIDECommand;
  CmdAssistantOpenMarkdown: TIDECommand;
  CmdAssistantReviewCompile: TIDECommand;
  CmdAssistantReviewBuild: TIDECommand;
  CmdAssistantFixError: TIDECommand;
  CmdAssistantSettings: TIDECommand;
  AssistantFixQuickFix: TAssistantFixMessageQuickFix;
  AssistantIDEHooks: TAssistantIDEHooks;

Procedure ShowProjectAssistantWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(ProjectAssistantWindowCreator.FormName, True);
End;

Function GetProjectAssistantForm(ShowWindow: Boolean = True): TProjectAssistantForm;
Var
  Form: TCustomForm;
Begin
  Result := Nil;
  If ShowWindow Then
    ShowProjectAssistantWindow(Nil);
  Form := IDEWindowCreators.GetForm(ProjectAssistantWindowCreator.FormName, True);
  If Form Is TProjectAssistantForm Then
    Result := TProjectAssistantForm(Form);
End;

Procedure DoAssistantSettings(Sender: TObject);
Begin
  ShowAssistantSettingsForm;
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
    Form.FixSelectedError;
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
    Form.FixSelectedError;
End;

Procedure CreateProjectAssistantForm(Sender: TObject; FormName: String;
  Var Form: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(Form, TProjectAssistantForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  Form.Name := FormName;
End;

Function TAssistantIDEHooks.ProjectOpened(Sender: TObject; LazProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  If Assigned(LazProject) Then
    WorkflowLogger.Info('ProjectAssistant', 'Project opened: ' + LazProject.ProjectInfoFile)
  Else
    WorkflowLogger.Info('ProjectAssistant', 'Project opened (nil)');
  { New project create and load both fire this; rebind open Project Assistant windows. }
  NotifyOpenProjectAssistantFormsProjectChanged;
End;

Function TAssistantIDEHooks.ProjectClose(Sender: TObject; LazProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  { Do not rebind from ActiveProject here – it is half-torn-down during close.
    Clear open forms; ProjectOpened rebinds when the next project is ready. }
  WorkflowLogger.Info('ProjectAssistant', 'Project closing');
  NotifyOpenProjectAssistantFormsProjectCleared;
End;

Procedure RegisterAssistantTools;
Var
  AssistantMenu, MainSec, SetSec: TIDEMenuSection;
  AfterItem: TIDEMenuItem;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
  InsertAt: Integer;
Begin
  WorkflowLogger.Info('ProjectAssistant', 'Registering LazAssistantTools');

  If AssistantIDEHooks = Nil Then
    AssistantIDEHooks := TAssistantIDEHooks.Create;

  Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Assistant', 'Assistant');

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdAssistantChat := RegisterIDECommand(Cat, 'ProjectAssistant', 'Project Assistant', Key, Nil, @ShowProjectAssistantWindow);
  CmdAssistantOpenMarkdown := RegisterIDECommand(Cat, 'AssistantOpenMarkdown', 'Open Markdown Document', Key, Nil, @DoAssistantOpenMarkdown);
  CmdAssistantReviewCompile := RegisterIDECommand(Cat, 'AssistantReviewCompile', 'Review Compile',
    Key, Nil, @DoAssistantReviewCompile);
  CmdAssistantReviewBuild := RegisterIDECommand(Cat, 'AssistantReviewBuild', 'Review Build',
    Key, Nil, @DoAssistantReviewBuild);
  CmdAssistantFixError := RegisterIDECommand(Cat, 'AssistantFixError', 'Fix Selected Message with Assistant',
    Key, Nil, @DoAssistantFixError);
  CmdAssistantSettings := RegisterIDECommand(Cat, 'AssistantSettings', 'Project Assistant Settings', Key, Nil, @DoAssistantSettings);

  { Top-level Assistant menu, placed immediately after Repository (fallback: after Run).
    Two logical sections so Lazarus draws a separator before Settings, matching Repository. }
  AssistantMenu := RegisterIDESubMenu(mnuMain, 'Assistant', 'Assistant');
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
  RegisterIDEMenuCommand(MainSec, 'AssistantOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdAssistantOpenMarkdown);
  RegisterIDEMenuCommand(MainSec, 'AssistantReviewCompile', 'Review Compile', Nil, Nil, CmdAssistantReviewCompile);
  RegisterIDEMenuCommand(MainSec, 'AssistantReviewBuild', 'Review Build', Nil, Nil, CmdAssistantReviewBuild);
  RegisterIDEMenuCommand(MainSec, 'AssistantFixError', 'Fix Selected Message…', Nil, Nil, CmdAssistantFixError);
  SetSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantSettingsCmds');
  RegisterIDEMenuCommand(SetSec, 'AssistantSettings', 'Settings…', Nil, Nil, CmdAssistantSettings);

  ProjectAssistantWindowCreator := IDEWindowCreators.Add('ProjectAssistant', @CreateProjectAssistantForm, Nil,
    '120', '80', '800', '650');

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
End;

Initialization

AssistantIDEHooks := Nil;

Finalization

If Assigned(LazarusIDE) And Assigned(AssistantIDEHooks) Then
  Begin
    LazarusIDE.RemoveHandlerOnProjectOpened(@AssistantIDEHooks.ProjectOpened);
    LazarusIDE.RemoveHandlerOnProjectClose(@AssistantIDEHooks.ProjectClose);
  End;
FreeAndNil(AssistantIDEHooks);
If Assigned(AssistantFixQuickFix) And Assigned(MsgQuickFixes) Then
  MsgQuickFixes.UnregisterQuickFix(AssistantFixQuickFix);
FreeAndNil(AssistantFixQuickFix);

End.
