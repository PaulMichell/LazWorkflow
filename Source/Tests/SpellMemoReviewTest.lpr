Program SpellMemoReviewTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils, Controls, Menus, LCLType,
  SpellMemo, SpellEngine, SpellCheckerConfig, SpellCheckerOptions;
Type
  TReviewMemo=Class(TSpellMemo)
    Procedure Press(Key:Word);
    Procedure HookMenu;
  End;
Procedure TReviewMemo.Press(Key:Word);
Begin KeyDown(Key,[]); End;
Procedure TReviewMemo.HookMenu;
Var Handled:Boolean;
Begin Handled:=False; DoContextPopup(Point(-1,-1),Handled); End;
Procedure Check(Const Title:String; Condition:Boolean);
Begin If Not Condition Then Raise Exception.Create(Title); WriteLn('ok ',Title); End;
Var Host:TForm; Memo:TReviewMemo; A,B:TPopupMenu; Item:TMenuItem; Started:QWord;
Begin
 Application.Initialize;
 WorkflowSpellConfig.Options.EngineKind:=sekHunspell;
 WorkflowSpellConfig.Options.Language:='en_GB'; WorkflowSpellConfig.Apply;
 Started:=GetTickCount64;
 While Not WorkflowSpellConfig.IsReady And (GetTickCount64-Started<10000) Do CheckSynchronize(10);
 Check('dictionary ready',WorkflowSpellConfig.IsReady);
 Host:=TForm.CreateNew(Nil); Memo:=TReviewMemo.Create(Nil); A:=TPopupMenu.Create(Nil); B:=TPopupMenu.Create(Nil);
 Try
  Memo.Parent:=Host; Host.HandleNeeded; Memo.HandleNeeded; Memo.Width:=500;
  Memo.Text:='abc'+#10+'def'+#10+#10+'last';
  Memo.SelStart:=1; Memo.Press(VK_END); Check('End reaches hard newline',Memo.SelStart=3);
  Memo.Press(VK_DOWN); Check('Down from hard newline',Memo.SelStart=7);
  Memo.Press(VK_DOWN); Check('Down reaches blank paragraph',Memo.SelStart=8);
  Memo.Press(VK_HOME); Check('Home stays on blank paragraph',Memo.SelStart=8);
  Memo.Press(VK_UP); Check('Up from blank paragraph',Memo.SelStart=4);
  Memo.Text:='recieve '; Memo.SelStart:=3;
  Item:=TMenuItem.Create(A); Item.Caption:='Host A'; A.Items.Add(Item);
  Item:=TMenuItem.Create(B); Item.Caption:='Host B'; B.Items.Add(Item);
  Memo.PopupMenu:=A; Memo.HookMenu; A.OnPopup(A);
  Check('spell menu injected',A.Items.Count>1);
  Memo.PopupMenu:=B; Memo.HookMenu;
  Check('switch preserves old host items', (A.Items.Count=1) And (A.Items[0].Caption='Host A'));
  B.OnPopup(B); Check('new spell menu injected',B.Items.Count>1);
  FreeAndNil(Memo);
  Check('memo destruction removes callbacks/items', (B.Items.Count=1) And Not Assigned(B.OnPopup));
  Memo:=TReviewMemo.Create(Nil); Memo.Parent:=Host; Memo.PopupMenu:=A; Memo.HookMenu;
  FreeAndNil(A); FreeAndNil(Memo);
  WriteLn('ok menu destruction before memo');
 Finally Memo.Free; A.Free; B.Free; Host.Free; End;
End.
