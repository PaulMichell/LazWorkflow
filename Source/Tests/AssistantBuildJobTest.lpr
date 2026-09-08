Program AssistantBuildJobTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, AssistantBuildJob;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok ', Name); End;
Procedure WriteFile(Const Path, Text: String);
Var Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try If Text <> '' Then Stream.WriteBuffer(Text[1], Length(Text)); Finally Stream.Free; End;
End;
Var Job: IAssistantBuildJob; Value: TBuildJobSnapshot; Inputs: TBuildInputs;
  Path: String; Deadline, Started: QWord;
Procedure WaitDone;
Begin
  Deadline := GetTickCount64 + 3000;
  Repeat Value := Job.Snapshot; Sleep(1); Until Value.Done Or (GetTickCount64 >= Deadline);
  Check('build completes within deadline', Value.Done);
End;
Begin
  If ParamCount > 0 Then
    Begin
      If ParamStr(1) = '--build-mode=hang' Then Sleep(10000);
      If ParamStr(1) = '--build-mode=bad' Then
        Begin WriteLn('unit.pas(3,1) Error: test diagnostic'); Halt(1); End;
      WriteLn('build fixture completed'); Halt(0);
    End;
  Path := GetTempFileName(GetTempDir, 'laz-build-');
  Try
    WriteFile(Path, 'saved source');
    SetLength(Inputs, 1); Inputs[0].Path := Path; Inputs[0].Text := 'saved source';
    Started := GetTickCount64;
    Job := StartAssistantBuild(ParamStr(0), Path, 'good', Inputs);
    Check('launch does not block', GetTickCount64 - Started < 500);
    WaitDone;
    Check('successful exit and observed inputs', (Value.ExitCode = 0) And Value.InputsUnchanged);
    Check('manifest and log retained', (Pos('sha1', Value.Manifest) > 0) And (Pos('fixture completed', Value.OutputText) > 0));
    Job := StartAssistantBuild(ParamStr(0), Path, 'bad', Inputs); WaitDone;
    Check('compiler error returned', (Value.ExitCode = 1) And (Pos('unit.pas(3,1)', Value.OutputText) > 0));
    WriteFile(Path, 'user changed source');
    Job := StartAssistantBuild(ParamStr(0), Path, 'good', Inputs); WaitDone;
    Check('stale input prevents compiler launch', (Value.ExitCode = -1) And (Value.OutputText = '') And (Value.ErrorText <> ''));
    WriteFile(Path, 'saved source');
    Job := StartAssistantBuild(ParamStr(0), Path, 'hang', Inputs, 50); WaitDone;
    Check('timeout bounded', Pos('timed out', Value.ErrorText) > 0);
    Job := StartAssistantBuild(ParamStr(0), Path, 'hang', Inputs); Job.Cancel; WaitDone;
    Check('cancel reported', Value.Cancelled);
    Job := StartAssistantBuild('/no/such/compiler', Path, 'good', Inputs); WaitDone;
    Check('missing compiler fails without killing host', Value.ErrorText <> '');
  Finally Job := Nil; DeleteFile(Path); End;
  WriteLn('All build job tests passed.');
End.
