Program AssistantEditorEditsTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, SysUtils, Types,
  SynEdit, SrcEditorIntf, AssistantEditorEdits;
Type
  { Exercise the real IDE interface's ReplaceText with a real SynEdit Undo stack.
    Only the editor methods used by that operation are implemented. }
  TTestEditor = Class(TSourceEditorInterface)
  Protected
    Function GetSourceText: String; Override;
    Function GetReadOnly: Boolean; Override;
    Procedure SetSourceText(Const Value: String); Override;
    Procedure SetCursorTextXY(Const Value: TPoint); Override;
    Procedure SetSelection(Const Value: String); Override;
  Public
    Syn: TSynEdit;
    Procedure SelectText(Const StartPos, EndPos: TPoint); Override;
    Procedure BeginUndoBlock; Override;
    Procedure EndUndoBlock; Override;
    Procedure BeginUpdate; Override;
    Procedure EndUpdate; Override;
  End;
Function TTestEditor.GetSourceText: String;
Begin Result := Syn.Text; End;
Function TTestEditor.GetReadOnly: Boolean;
Begin Result := Syn.ReadOnly; End;
Procedure TTestEditor.SetSourceText(Const Value: String);
Begin Raise Exception.Create('SourceText assignment must never be used'); End;
Procedure TTestEditor.SetCursorTextXY(Const Value: TPoint);
Begin Syn.LogicalCaretXY := Value; End;
Procedure TTestEditor.SetSelection(Const Value: String);
Begin Syn.SelText := Value; End;
Procedure TTestEditor.SelectText(Const StartPos, EndPos: TPoint);
Begin Syn.BlockBegin := StartPos; Syn.BlockEnd := EndPos; End;
Procedure TTestEditor.BeginUndoBlock;
Begin Syn.BeginUndoBlock; End;
Procedure TTestEditor.EndUndoBlock;
Begin Syn.EndUndoBlock; End;
Procedure TTestEditor.BeginUpdate;
Begin Syn.BeginUpdate; End;
Procedure TTestEditor.EndUpdate;
Begin Syn.EndUpdate; End;
Procedure Check(Const Title: String; Value: Boolean);
Begin
  If Not Value Then Begin WriteLn(StdErr, 'FAIL ', Title); Halt(1); End;
  WriteLn('ok ', Title);
End;
Var Ed: TTestEditor; Host: TForm; Before, UserText, Changed, Err: String;
Begin
  Application.Initialize;
  Host := TForm.CreateNew(Nil);
  Ed := TTestEditor.Create;
  Ed.Syn := TSynEdit.Create(Host);
  Try
    Ed.Syn.Parent := Host;
    Host.HandleNeeded;
    Ed.Syn.HandleNeeded;
    Ed.Syn.Text := 'unit Example;' + LineEnding + 'end.';
    Before := Ed.SourceText;
    Ed.ReplaceText(Point(6, 1), Point(13, 1), 'UserName');
    UserText := Ed.SourceText;
    Changed := StringReplace(UserText, 'UserName', 'AssistantName', []);
    Check('apply assistant edit', ApplyAssistantEditorText(Ed, UserText, Changed, Err));
    Check('text updated', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('Undo restores user edit', Ed.SourceText = UserText);
    Ed.Syn.Undo;
    Check('earlier user Undo survives', Ed.SourceText = Before);
    Check('stale snapshot rejected', Not ApplyAssistantEditorText(Ed, UserText, Changed, Err));
    Check('stale edit leaves source alone', Ed.SourceText = Before);
    Ed.Syn.ReadOnly := True;
    Check('read-only rejected', Not ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Ed.Syn.ReadOnly := False;
    Ed.Syn.Text := 'a' + #$C3#$A9 + 'z' + LineEnding + 'tail';
    Before := Ed.SourceText;
    Changed := StringReplace(Before, #$C3#$A9, #$C3#$AA, []);
    Check('UTF8 shared prefix edit', ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Check('UTF8 content preserved', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('UTF8 Undo', Ed.SourceText = Before);
    Ed.Syn.Text := '';
    Before := Ed.SourceText;
    Check('empty buffer insertion', ApplyAssistantEditorText(Ed, Before, 'hello', Err));
    Check('empty buffer content', TrimRight(Ed.SourceText) = 'hello');
    Check('no-op succeeds', ApplyAssistantEditorText(Ed, Ed.SourceText, Ed.SourceText, Err));
    Ed.Syn.Undo;
    Check('no-op adds no Undo entry', (TrimRight(Ed.SourceText) = TrimRight(Before)) And Not Ed.Syn.CanUndo);
    Ed.Syn.Text := 'a' + #13#10 + 'b';
    Before := Ed.SourceText;
    Changed := StringReplace(Before, 'b', 'new', []);
    Check('CRLF edit', ApplyAssistantEditorText(Ed, Before, Changed, Err));
    Check('CRLF text', Ed.SourceText = Changed);
    Ed.Syn.Undo;
    Check('CRLF Undo', Ed.SourceText = Before);
  Finally
    Ed.Free;
    Host.Free;
  End;
End.
