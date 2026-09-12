Program AssistantBuildDependenciesTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Classes, SysUtils, fpjson, jsonparser,
  LazIDEIntf, CodeToolManager, CodeCache, AssistantBuildDependencies, AssistantBuildJob, AssistantCodeToolsGuard;
Type TIDE = Class(TLazIDEInterface)
  Public Ready: Boolean;
    Function BeginCodeTools: Boolean; Override;
End;
Function TIDE.BeginCodeTools: Boolean;
Begin Result := Ready; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok ', Name); End;
Procedure WriteFile(Const Path, Text: String);
Var Stream: TFileStream;
Begin Stream := TFileStream.Create(Path, fmCreate); Try Stream.WriteBuffer(Text[1], Length(Text)); Finally Stream.Free; End; End;
Var Root, Reply, Note: String; ID: TGuid; IDE: TIDE; Inputs: TBuildInputs; Step, I: Integer; Data: TJSONData; Code: TCodeBuffer;
Function HasInput(Const Name: String): Boolean;
Var J: Integer;
Begin Result := False; For J := 0 To High(Inputs) Do If Inputs[J].Path = Root + '/' + Name Then Exit(True); End;
Procedure Capture;
Begin
  Inputs := Nil; Check('capture root', AddBuildInput(Inputs, Root + '/main.pas', Note));
  CaptureAssistantDependencies(Inputs, Reply, Step); WriteLn(Reply);
End;
Function Complete: Boolean;
Begin Data := GetJSON(Reply); Try Result := Data.FindPath('sourceClosureComplete').AsBoolean; Finally Data.Free; End; End;
Begin
  Application.Initialize; CreateGUID(ID); Root := GetTempDir + 'laz-dependencies-' + GUIDToString(ID); ForceDirectories(Root);
  IDE := TIDE.Create(Nil); IDE.Ready := True; LazarusIDE := IDE;
  Try
    WriteFile(Root + '/main.pas', 'unit Main; interface uses Direct; implementation uses Indirect; procedure Work; begin {$i body.inc} end; end.');
    WriteFile(Root + '/direct.pas', 'unit Direct; interface uses Indirect; implementation end.');
    WriteFile(Root + '/indirect.pas', 'unit Indirect; interface implementation end.');
    WriteFile(Root + '/system.pp', 'unit System; interface implementation end.');
    WriteFile(Root + '/body.inc', '{$i nested.inc}'); WriteFile(Root + '/nested.inc', ';');
    Capture;
    Check('real CodeTools captures transitive uses and implicit System', Complete And HasInput('direct.pas') And HasInput('indirect.pas') And HasInput('system.pp'));
    Check('implementation body and nested includes captured', HasInput('body.inc') And HasInput('nested.inc'));
    Check('unchanged source manifest matches disk', BuildInputsMatch(Inputs, Note));
    WriteFile(Root + '/nested.inc', '// changed include');
    Check('closed nested include edit invalidates evidence', Not BuildInputsMatch(Inputs, Note));
    WriteFile(Root + '/nested.inc', ';');
    Code := CodeToolBoss.LoadFile(Root + '/direct.pas', True, False); Code.LockAutoDiskRevert;
    Code.Source := 'unit Direct; interface const Unsaved = 1; implementation end.';
    Capture; Check('unsaved CodeTools dependency cannot claim saved closure', Not Complete);
    Code.UnlockAutoDiskRevert; Code.Source := 'unit Direct; interface uses Indirect; implementation end.';
    WriteFile(Root + '/main.pas', 'unit Main; interface uses MissingUnit; implementation end.');
    CodeToolBoss.LoadFile(Root + '/main.pas', True, False).Source := 'unit Main; interface uses MissingUnit; implementation end.';
    Capture; Check('unresolved unit leaves explicit coverage gap', Not Complete And (Pos('MissingUnit', Reply) > 0));
    Check('guard acquired', EnterAssistantCodeTools);
    Try Capture; Check('reentrant discovery refused', Not Complete And (Pos('busy', Reply) > 0)); Finally LeaveAssistantCodeTools; End;
    IDE.Ready := False; Capture; Check('busy IDE leaves incomplete evidence', Not Complete);
  Finally
    LazarusIDE := Nil; IDE.Free;
    DeleteFile(Root + '/main.pas'); DeleteFile(Root + '/direct.pas'); DeleteFile(Root + '/indirect.pas');
    DeleteFile(Root + '/system.pp'); DeleteFile(Root + '/body.inc'); DeleteFile(Root + '/nested.inc'); RemoveDir(Root);
  End;
End.
