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
  AssistantChatWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, AssistantChatForm, AssistantService, AssistantSettingsForm, AssistantMarkdownForm,
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
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
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

Procedure ShowAssistantChatWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(AssistantChatWindowCreator.FormName, True);
End;

Function GetAssistantChatForm(ShowWindow: Boolean = True): TAssistantChatForm;
Var
  Form: TCustomForm;
Begin
  Result := Nil;
  If ShowWindow Then
    ShowAssistantChatWindow(Nil);
  Form := IDEWindowCreators.GetForm(AssistantChatWindowCreator.FormName, True);
  If Form Is TAssistantChatForm Then
    Result := TAssistantChatForm(Form);
End;

Procedure DoAssistantSettings(Sender: TObject);
Begin
  ShowAssistantSettingsForm;
End;

Procedure DoAssistantOpenMarkdown(Sender: TObject);
Begin
  WorkflowLogger.Info('AssistantChat', 'Open Markdown document requested');
  OpenMarkdownDocument('');
End;

Procedure DoAssistantReviewCompile(Sender: TObject);
Var
  Form: TAssistantChatForm;
Begin
  Form := GetAssistantChatForm(True);
  If Assigned(Form) Then
    Form.ReviewCompile;
End;

Procedure DoAssistantReviewBuild(Sender: TObject);
Var
  Form: TAssistantChatForm;
Begin
  Form := GetAssistantChatForm(True);
  If Assigned(Form) Then
    Form.ReviewBuild;
End;

Procedure DoAssistantFixError(Sender: TObject);
Var
  Form: TAssistantChatForm;
Begin
  Form := GetAssistantChatForm(True);
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
  Form: TAssistantChatForm;
Begin
  If Assigned(Msg) And Assigned(IDEMessagesWindow) Then
    IDEMessagesWindow.SelectMsgLine(Msg);
  Form := GetAssistantChatForm(True);
  If Assigned(Form) Then
    Form.FixSelectedError;
End;

Procedure CreateAssistantChatForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(AForm, TAssistantChatForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  AForm.Name := AFormName;
End;

Function TAssistantIDEHooks.ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  If Assigned(AProject) Then
    WorkflowLogger.Info('AssistantChat', 'Project opened: ' + AProject.ProjectInfoFile)
  Else
    WorkflowLogger.Info('AssistantChat', 'Project opened (nil)');
  { New project create and load both fire this; rebind open Project Assistant windows. }
  NotifyOpenAssistantFormsProjectChanged;
End;

Function TAssistantIDEHooks.ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  { Do not rebind from ActiveProject here – it is half-torn-down during close.
    Clear open forms; ProjectOpened rebinds when the next project is ready. }
  WorkflowLogger.Info('AssistantChat', 'Project closing');
  NotifyOpenAssistantFormsProjectCleared;
End;

Procedure RegisterAssistantTools;
Var
  AssistantMenu, MainSec, SetSec: TIDEMenuSection;
  AfterItem: TIDEMenuItem;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
  InsertAt: Integer;
Begin
  WorkflowLogger.Info('AssistantChat', 'Registering LazAssistantTools');

  If AssistantIDEHooks = Nil Then
    AssistantIDEHooks := TAssistantIDEHooks.Create;

  Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Assistant', 'Assistant');

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdAssistantChat := RegisterIDECommand(Cat, 'AssistantChat', 'Project Assistant', Key, Nil, @ShowAssistantChatWindow);
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
  RegisterIDEMenuCommand(MainSec, 'AssistantChat', 'Project Assistant', Nil, Nil, CmdAssistantChat);
  RegisterIDEMenuCommand(MainSec, 'AssistantOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdAssistantOpenMarkdown);
  RegisterIDEMenuCommand(MainSec, 'AssistantReviewCompile', 'Review Compile', Nil, Nil, CmdAssistantReviewCompile);
  RegisterIDEMenuCommand(MainSec, 'AssistantReviewBuild', 'Review Build', Nil, Nil, CmdAssistantReviewBuild);
  RegisterIDEMenuCommand(MainSec, 'AssistantFixError', 'Fix Selected Message…', Nil, Nil, CmdAssistantFixError);
  SetSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantSettingsCmds');
  RegisterIDEMenuCommand(SetSec, 'AssistantSettings', 'Settings…', Nil, Nil, CmdAssistantSettings);

  AssistantChatWindowCreator := IDEWindowCreators.Add('AssistantChat', @CreateAssistantChatForm, Nil,
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

  WorkflowLogger.Info('AssistantChat', 'LazAssistantTools registered successfully');
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
