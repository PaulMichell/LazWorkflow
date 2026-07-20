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
  WorkflowLog, WorkflowEvents, GrokChatForm, GrokService;

Var
  CmdGrokChat: TIDECommand;
  CmdGrokNewChat: TIDECommand;
  CmdGrokOpenMarkdown: TIDECommand;
  CmdGrokBuild: TIDECommand;

Procedure ShowGrokChatWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(GrokChatWindowCreator.FormName, True);
End;

Procedure DoGrokNewChat(Sender: TObject);
Begin
  WorkflowLogger.Info('GrokChat', 'New chat requested');
  ShowGrokChatWindow(Sender);
  { TODO: tell form to start new conversation }
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
  Parent: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
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

  Parent := RegisterIDEMenuSection(itmSecondaryTools, 'GrokSection');
  Parent.Caption := 'Grok';
  RegisterIDEMenuCommand(Parent, 'GrokChat', 'Grok Chat', Nil, Nil, CmdGrokChat);
  RegisterIDEMenuCommand(Parent, 'GrokNewChat', 'New Chat', Nil, Nil, CmdGrokNewChat);
  RegisterIDEMenuCommand(Parent, 'GrokOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdGrokOpenMarkdown);
  RegisterIDEMenuSection(Parent, 'GrokSep1');
  RegisterIDEMenuCommand(Parent, 'GrokBuild', 'Build Project', Nil, Nil, CmdGrokBuild);

  GrokChatWindowCreator := IDEWindowCreators.Add('GrokChat', @CreateGrokChatForm, Nil,
    '120', '80', '800', '650');

  WorkflowLogger.Info('GrokChat', 'LazGrokChat registered successfully');
End;

End.
