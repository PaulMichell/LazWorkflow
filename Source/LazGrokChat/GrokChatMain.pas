Unit GrokChatMain;

{ Core registration, menus, commands and window creation for LazGrokChat (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf, CompOptsIntf;

Procedure RegisterGrokChat;

Var
  GrokChatWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GrokChatForm, GrokService, GrokSettingsForm;

Var
  CmdGrokChat: TIDECommand;
  CmdGrokNewChat: TIDECommand;
  CmdGrokOpenMarkdown: TIDECommand;
  CmdGrokBuild: TIDECommand;
  CmdGrokSettings: TIDECommand;

Procedure ShowGrokChatWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(GrokChatWindowCreator.FormName, True);
End;

Procedure DoGrokNewChat(Sender: TObject);
Var
  Form: TCustomForm;
Begin
  WorkflowLogger.Info('GrokChat', 'New chat requested');
  ShowGrokChatWindow(Sender);
  Form := IDEWindowCreators.GetForm(GrokChatWindowCreator.FormName, True);
  If Form Is TGrokChatForm Then
    TGrokChatForm(Form).StartNewChat;
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

Procedure DoGrokBuild(Sender: TObject);
Begin
  WorkflowLogger.Info('GrokChat', 'Build project requested from Grok');
  If Assigned(LazarusIDE) Then
    LazarusIDE.DoBuildProject(crCompile, []);
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
  CmdGrokChat := RegisterIDECommand(Cat, 'GrokChat', 'Show Grok Chat', Key, Nil, @ShowGrokChatWindow);
  CmdGrokNewChat := RegisterIDECommand(Cat, 'GrokNewChat', 'New Grok Chat', Key, Nil, @DoGrokNewChat);
  CmdGrokOpenMarkdown := RegisterIDECommand(Cat, 'GrokOpenMarkdown', 'Open Markdown Document', Key, Nil, @DoGrokOpenMarkdown);
  CmdGrokBuild := RegisterIDECommand(Cat, 'GrokBuild', 'Build Project (Grok)', Key, Nil, @DoGrokBuild);
  CmdGrokSettings := RegisterIDECommand(Cat, 'GrokSettings', 'Grok Chat Settings', Key, Nil, @DoGrokSettings);

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
  RegisterIDEMenuCommand(MainSec, 'GrokChat', 'Grok Chat', Nil, Nil, CmdGrokChat);
  RegisterIDEMenuCommand(MainSec, 'GrokNewChat', 'New Chat', Nil, Nil, CmdGrokNewChat);
  RegisterIDEMenuCommand(MainSec, 'GrokOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdGrokOpenMarkdown);
  RegisterIDEMenuCommand(MainSec, 'GrokBuild', 'Build Project', Nil, Nil, CmdGrokBuild);
  SetSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantSettingsCmds');
  RegisterIDEMenuCommand(SetSec, 'GrokSettings', 'Settings…', Nil, Nil, CmdGrokSettings);

  GrokChatWindowCreator := IDEWindowCreators.Add('GrokChat', @CreateGrokChatForm, Nil,
    '120', '80', '800', '650');

  WorkflowLogger.Info('GrokChat', 'LazGrokChat registered successfully');
End;

End.
