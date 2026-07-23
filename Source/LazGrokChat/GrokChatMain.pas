Unit GrokChatMain;

{ Core registration, menus, commands and window creation for LazGrokChat (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf;

Procedure RegisterGrokChat;

Var
  GrokChatWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GrokChatForm, GrokService, GrokSettingsForm;

Var
  CmdGrokChat: TIDECommand;
  CmdGrokOpenMarkdown: TIDECommand;
  CmdGrokReviewCompile: TIDECommand;
  CmdGrokReviewBuild: TIDECommand;
  CmdGrokSettings: TIDECommand;

Procedure ShowGrokChatWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(GrokChatWindowCreator.FormName, True);
End;

Function GetGrokChatForm(ShowWindow: Boolean = True): TGrokChatForm;
Var
  Form: TCustomForm;
Begin
  Result := Nil;
  If ShowWindow Then
    ShowGrokChatWindow(Nil);
  Form := IDEWindowCreators.GetForm(GrokChatWindowCreator.FormName, True);
  If Form Is TGrokChatForm Then
    Result := TGrokChatForm(Form);
End;

Procedure DoGrokSettings(Sender: TObject);
Begin
  ShowGrokSettingsForm;
End;

Procedure DoGrokOpenMarkdown(Sender: TObject);
Begin
  WorkflowLogger.Info('GrokChat', 'Open Markdown document requested');
  { TODO: show open dialog and create Markdown window }
End;

Procedure DoGrokReviewCompile(Sender: TObject);
Var
  Form: TGrokChatForm;
Begin
  Form := GetGrokChatForm(True);
  If Assigned(Form) Then
    Form.ReviewCompile;
End;

Procedure DoGrokReviewBuild(Sender: TObject);
Var
  Form: TGrokChatForm;
Begin
  Form := GetGrokChatForm(True);
  If Assigned(Form) Then
    Form.ReviewBuild;
End;

Procedure CreateGrokChatForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(AForm, TGrokChatForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  AForm.Name := AFormName;
End;

Procedure RegisterGrokChat;
Var
  AssistantMenu, MainSec, SetSec: TIDEMenuSection;
  AfterItem: TIDEMenuItem;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
  InsertAt: Integer;
Begin
  WorkflowLogger.Info('GrokChat', 'Registering LazGrokChat');

  Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Grok', 'Grok');

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdGrokChat := RegisterIDECommand(Cat, 'GrokChat', 'Project Chat', Key, Nil, @ShowGrokChatWindow);
  CmdGrokOpenMarkdown := RegisterIDECommand(Cat, 'GrokOpenMarkdown', 'Open Markdown Document', Key, Nil, @DoGrokOpenMarkdown);
  CmdGrokReviewCompile := RegisterIDECommand(Cat, 'GrokReviewCompile', 'Review Compile',
    Key, Nil, @DoGrokReviewCompile);
  CmdGrokReviewBuild := RegisterIDECommand(Cat, 'GrokReviewBuild', 'Review Build',
    Key, Nil, @DoGrokReviewBuild);
  CmdGrokSettings := RegisterIDECommand(Cat, 'GrokSettings', 'Project Chat Settings', Key, Nil, @DoGrokSettings);

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
  RegisterIDEMenuCommand(MainSec, 'GrokChat', 'Project Chat', Nil, Nil, CmdGrokChat);
  RegisterIDEMenuCommand(MainSec, 'GrokOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdGrokOpenMarkdown);
  RegisterIDEMenuCommand(MainSec, 'GrokReviewCompile', 'Review Compile', Nil, Nil, CmdGrokReviewCompile);
  RegisterIDEMenuCommand(MainSec, 'GrokReviewBuild', 'Review Build', Nil, Nil, CmdGrokReviewBuild);
  SetSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantSettingsCmds');
  RegisterIDEMenuCommand(SetSec, 'GrokSettings', 'Settings…', Nil, Nil, CmdGrokSettings);

  GrokChatWindowCreator := IDEWindowCreators.Add('GrokChat', @CreateGrokChatForm, Nil,
    '120', '80', '800', '650');

  WorkflowLogger.Info('GrokChat', 'LazGrokChat registered successfully');
End;

End.
