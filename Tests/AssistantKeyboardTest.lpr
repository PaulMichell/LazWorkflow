Program AssistantKeyboardTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, Interfaces, Forms, Controls, ExtCtrls, StdCtrls, SysUtils, LCLType,
  AssistantTestIDEHost, AssistantTrace, AssistantConversationSurface,
  AssistantMarkdownForm, StyledControls, Menus, LazIDEIntf, ProjectIntf,
  ProjectAssistantForm, BaseIDEIntf, LazConfigStorage;
Type
  TKeyboardConfig=Class(TConfigMemStorage)
    Procedure WriteToDisk; Override;
  End;
  TKeyboardIDE=Class(TLazIDEInterface)
    Function GetActiveProject:TLazProject; Override;
    Class Function GetPrimaryConfigPath:String; Override;
  End;
  TKeyboardMemo=Class(TStyledMemo)
    Procedure Press(Key:Word; Shift:TShiftState=[]);
  End;
  TKeyboardSurface=Class(TAssistantConversationSurface)
    Procedure Press(Key:Word; Shift:TShiftState=[]);
  End;
Var ConfigRoot:String;
Procedure TKeyboardConfig.WriteToDisk;
Begin End;
Function KeyboardConfig(Const Filename:String; LoadFromDisk:Boolean):TConfigStorage;
Begin Result:=TKeyboardConfig.Create('',False); End;
Function TKeyboardIDE.GetActiveProject:TLazProject;
Begin Result:=Nil; End;
Class Function TKeyboardIDE.GetPrimaryConfigPath:String;
Begin Result:=ConfigRoot; End;
Procedure TKeyboardMemo.Press(Key:Word; Shift:TShiftState);
Begin KeyDown(Key,Shift); End;
Procedure TKeyboardSurface.Press(Key:Word; Shift:TShiftState);
Begin KeyDown(Key,Shift); End;
Var Host:TForm; Container:TPanel; BeforeButton,AfterButton:TButton;
  View:TKeyboardSurface; Trace:TAssistantTrace; I,Failures:Integer;
Procedure Check(Const Name:String; OK:Boolean);
Begin
  If OK Then WriteLn('ok ',Name) Else Begin WriteLn('FAIL ',Name);Inc(Failures);End;
End;
Procedure CheckMarkdown;
Var Dialog:TAssistantMarkdownForm; Memo:TKeyboardMemo; Lines:TStringList; Path:String;
Begin
  Path:=GetTempFileName;Lines:=TStringList.Create;Dialog:=Nil;
  Try
    Lines.Text:='# Heading'+LineEnding+LineEnding+'Keyboard selection';Lines.SaveToFile(Path);
    Dialog:=TAssistantMarkdownForm.Create(Nil);Check('open keyboard Markdown fixture',Dialog.OpenFile(Path));
    Dialog.Show;Application.ProcessMessages;
    Check('viewer starts in Preview',Dialog.ViewMode=mvmPreview);
    Check('Open and Save have conventional shortcuts',
      (Dialog.OpenAction.ShortCut=ShortCut(VK_O,[ssCtrl])) And
      (Dialog.SaveAction.ShortCut=ShortCut(VK_S,[ssCtrl])));
    Check('both modes have distinct keyboard shortcuts',
      (Dialog.PreviewModeAction.ShortCut=ShortCut(VK_1,[ssCtrl])) And
      (Dialog.SourceModeAction.ShortCut=ShortCut(VK_2,[ssCtrl])));
    Dialog.SourceModeAction.Execute;
    Check('Source action focuses the editor',(Dialog.ViewMode=mvmSource) And (Dialog.ActiveControl=Dialog.SourceMemo));
    Dialog.SourceMemo.Text:='# Changed'+LineEnding+LineEnding+'Keyboard selection';Dialog.SaveAction.Execute;
    Lines.LoadFromFile(Path);Check('Save persists source edits',Pos('# Changed',Lines.Text)=1);
    Dialog.PreviewModeAction.Execute;
    Memo:=TKeyboardMemo(Dialog.PreviewHost.Controls[0]);
    Check('Preview action focuses selectable readonly content',
      (Dialog.ActiveControl=Memo) And Memo.ReadOnly And Not Memo.ShowCaret);
    Memo.Press(VK_HOME,[ssCtrl]);Memo.Press(VK_RIGHT,[ssShift]);
    Check('Shift+Right selects preview text',Memo.SelectedText='C');
    Memo.Press(VK_DELETE);Memo.Press(VK_A,[ssCtrl]);
    Check('preview deletion cannot change content',Pos('Changed',Memo.SelectedText)=1);
  Finally Dialog.Free;Lines.Free;DeleteFile(Path);End;
End;
Procedure CheckNewChat;
Var IDE:TKeyboardIDE; Dialog:TProjectAssistantForm; Guid:TGuid;
Begin
  CreateGUID(Guid);ConfigRoot:=GetTempDir+'laz-keyboard-'+GUIDToString(Guid);
  GetIDEConfigStorage:=@KeyboardConfig;
  ForceDirectories(ConfigRoot);IDE:=TKeyboardIDE.Create(Nil);LazarusIDE:=IDE;
  Dialog:=Nil;
  Try
    Dialog:=TProjectAssistantForm.Create(Nil);Dialog.Show;Application.ProcessMessages;
    Dialog.NewChatAction.Execute;
    Check('New Chat focuses the prompt',Dialog.ActiveControl=Dialog.InputMemo);
  Finally Dialog.Free;LazarusIDE:=Nil;IDE.Free;End;
End;
Begin
  Application.Initialize; Host:=TForm.CreateNew(Nil);Trace:=TAssistantTrace.Create;
  Try
    Host.SetBounds(0,0,700,500);
    BeforeButton:=TButton.Create(Host);BeforeButton.Parent:=Host;BeforeButton.Caption:='Before';BeforeButton.TabOrder:=0;
    Container:=TPanel.Create(Host);Container.Parent:=Host;Container.SetBounds(0,40,650,400);Container.TabOrder:=1;
    View:=TKeyboardSurface.Create(Host);View.Parent:=Container;View.Align:=alClient;
    AfterButton:=TButton.Create(Host);AfterButton.Parent:=Host;AfterButton.Caption:='After';AfterButton.Top:=450;AfterButton.TabOrder:=2;
    Trace.AddUser('Keyboard user');Trace.AddTool('tool','read_file','{}').Body:='Tool detail';
    Trace.EnsureAnswer.Body:='Keyboard **answer**';
    Host.Show;Application.ProcessMessages;
    View.BeginDocument;For I:=0 To Trace.Count-1 Do View.AddBlock(Trace[I].ID,Trace[I]);View.EndDocument;View.CompleteLayout;
    View.SetFocus;View.Press(VK_TAB,[ssCtrl]);
    Check('Ctrl+Tab escapes a nested conversation',Host.ActiveControl=AfterButton);
    View.SetFocus;View.Press(VK_TAB,[ssCtrl,ssShift]);
    Check('Ctrl+Shift+Tab leaves in reverse',Host.ActiveControl=BeforeButton);
    View.SetFocus;View.Press(VK_TAB);View.Press(VK_TAB);View.Press(VK_RETURN);
    Check('Tab selects a tool and Enter opens it',Not View.Layout[1].Collapsed);
    View.Press(VK_SPACE);Check('Space closes the focused tool',View.Layout[1].Collapsed);
    View.Press(VK_TAB);View.Press(VK_TAB);
    Check('Tab after last item leaves conversation',Host.ActiveControl=AfterButton);
    View.SetFocus;View.Press(VK_A,[ssCtrl]);
    Check('keyboard Select All includes rendered answers',Pos('Keyboard answer',View.SelectedText)>0);
    View.ShowToolUse:=False;View.CompleteLayout;
    View.Press(VK_TAB,[ssShift]);View.Press(VK_SPACE);
    Check('hidden tool skipped during reverse navigation',View.Layout[1].Collapsed);
    View.Clear;View.SetFocus;View.Press(VK_TAB);
    Check('empty conversation does not trap Tab',Host.ActiveControl=AfterButton);
  Finally Trace.Free;Host.Free;End;
  CheckMarkdown;
  CheckNewChat;
  If Failures>0 Then Halt(1);
End.
