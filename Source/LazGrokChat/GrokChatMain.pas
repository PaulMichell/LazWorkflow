Unit GrokChatMain;

{ Core registration, menus, commands and window creation for LazGrokChat (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  SrcEditorIntf, ProjectIntf, LazIDEIntf;

Procedure RegisterGrokChat;

Var
  GrokChatWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GrokChatForm, GrokService, ProjectIntf;

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
  WorkflowLog.Info('GrokChat', 'New chat requested');
  ShowGrokChatWindow(Sender);
  { TODO: tell form to start new conversation }
End;

Procedure DoGrokOpenMarkdown(Sender: TObject);
Begin
  WorkflowLog.Info('GrokChat', 'Open Markdown document requested');
  { TODO: show open dialog and create Markdown window }
End;

Procedure DoGrokBuild(Sender: TObject);
Begin
  WorkflowLog.Info('GrokChat', 'Build project requested from Grok');
  If Assigned(LazarusIDE) Then
    LazarusIDE.DoBuildProject(crCompile, []);
End;

Procedure CreateGrokChatForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  If DoDisableAutoSizing Then
    Begin
      AForm := TGrokChatForm.Create(Nil);
      AForm.DisableAutoSizing;
    End
  Else
    AForm := TGrokChatForm.Create(Nil);
End;

Procedure RegisterGrokChat;
Var
  Parent, Item: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLog.Info('GrokChat', 'Registering LazGrokChat');

  Cat := IDECommandList.CreateCategory(Nil, 'Grok', 'Grok', IDEListEditorCategory);

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdGrokChat := RegisterIDECommand(Cat, 'GrokChat', 'Show Grok Chat', Key, Nil, @ShowGrokChatWindow);
  CmdGrokNewChat := RegisterIDECommand(Cat, 'GrokNewChat', 'New Grok Chat', Key, Nil, @DoGrokNewChat);
  CmdGrokOpenMarkdown := RegisterIDECommand(Cat, 'GrokOpenMarkdown', 'Open Markdown Document', Key, Nil, @DoGrokOpenMarkdown);
  CmdGrokBuild := RegisterIDECommand(Cat, 'GrokBuild', 'Build Project (Grok)', Key, Nil, @DoGrokBuild);

  Parent := RegisterIDEMenuSection(itmTools, 'GrokSection');
  Parent.Caption := 'Grok';
  Item := RegisterIDEMenuCommand(Parent, 'GrokChat', 'Grok Chat', Nil, Nil, CmdGrokChat);
  Item := RegisterIDEMenuCommand(Parent, 'GrokNewChat', 'New Chat', Nil, Nil, CmdGrokNewChat);
  Item := RegisterIDEMenuCommand(Parent, 'GrokOpenMarkdown', 'Open Markdown...', Nil, Nil, CmdGrokOpenMarkdown);
  RegisterIDEMenuSection(Parent, 'GrokSep1');
  Item := RegisterIDEMenuCommand(Parent, 'GrokBuild', 'Build Project', Nil, Nil, CmdGrokBuild);

  GrokChatWindowCreator := IDEWindowCreators.Add('GrokChat', @CreateGrokChatForm, Nil,
    '120', '80', '800', '650');
  GrokChatWindowCreator.CreateLayout := True;

  WorkflowLog.Info('GrokChat', 'LazGrokChat registered successfully');
End;

End.
