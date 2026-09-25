Program AssistantTestRunnerTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, BaseUnix, fpjson, jsonparser, AssistantTestSettings, AssistantBuildJob, AssistantTestReport, fpcunit, xmltestreport, XMLWrite;
Type TFixture = Class(TTestCase)
  Protected Procedure RunTest; Override;
End;
Procedure TFixture.RunTest;
Begin If ParamStr(1) = 'xml-fail' Then Fail('fixture failure'); End;
Function RealReport: String;
Var Fixture: TFixture; Results: TTestResult; Writer: TXMLResultsWriter; Stream: TStringStream;
Begin
  Fixture := TFixture.Create; Results := TTestResult.Create; Writer := TXMLResultsWriter.Create(Nil); Stream := TStringStream.Create('');
  Try
    Writer.FileName := 'null'; Results.AddListener(Writer); Fixture.Run(Results); Writer.WriteResult(Results);
    WriteXMLFile(Writer.Document, Stream); Result := Stream.DataString;
  Finally Stream.Free; Results.Free; Writer.Free; Fixture.Free; End;
End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok ', Name); End;
Procedure WriteFile(Const Path, Text: String);
Var Stream: TFileStream;
Begin Stream := TFileStream.Create(Path, fmCreate); Try If Text <> '' Then Stream.WriteBuffer(Text[1], Length(Text)); Finally Stream.Free; End; End;
Var Root, Note, OldFingerprint: String; Id: TGuid; Settings, Reloaded: TAssistantTestSettings;
  Job: IAssistantBuildJob; Value: TBuildJobSnapshot; Inputs: TBuildInputs; Deadline: QWord; Args, Lines: TStringList; Data: TJSONData; Rejected: Boolean;
Procedure WaitDone;
Begin
  Deadline := GetTickCount64 + 4000;
  Repeat Value := Job.Snapshot; Sleep(2); Until Value.Done Or (GetTickCount64 >= Deadline);
  Check('configured process terminates', Value.Done);
End;
Begin
  If ParamCount > 0 Then
    Begin
      If Copy(ParamStr(1), 1, 3) = 'xml' Then Begin Write(RealReport); Halt(0); End;
      If ParamStr(1) = 'fail' Then Begin WriteLn('1 failed test'); Halt(3); End;
      If ParamStr(1) = 'hang' Then Sleep(10000);
      If ParamStr(1) = 'arguments' Then
        Begin
          If (ParamCount <> 4) Or (ParamStr(2) <> 'two words') Or (ParamStr(3) <> '$(touch never-created)') Or
            (ParamStr(4) <> '  spaces  ') Then Halt(7);
        End;
      If ParamStr(1) = 'changed' Then Begin WriteFile(ParamStr(2), 'edited during test'); Halt(0); End;
      WriteLn('configured tests completed'); Halt(0);
    End;
  CreateGUID(Id); Root := GetTempDir + 'laz-tests-' + GUIDToString(Id); ForceDirectories(Root);
  Settings := TAssistantTestSettings.Create(Root + '/.assistant/', Root + '/project.lpi');
  Reloaded := TAssistantTestSettings.Create(Root + '/other/.assistant/', Root + '/other/project.lpi'); Args := TStringList.Create;
  Try
    Settings.Load; Check('test runner is disabled by default', Not Settings.Enabled);
    Settings.Enabled := True; Settings.Executable := './test runner'; Settings.Arguments.Add('  spaces  ');
    Settings.Arguments.Add('"quoted"'); Settings.Arguments.Add('  second  '); Settings.Arguments.Add('$(touch never-created)');
    Settings.ReportFormat := 'fpcunit-xml'; Settings.MinimumTests := 2;
    Settings.TimeoutSeconds := 3; Settings.Save; Settings.Load;
    Check('configuration preserves exact arguments', (Settings.Arguments.Count = 4) And
      (Settings.Arguments[0] = '  spaces  ') And (Settings.Arguments[1] = '"quoted"') And (Settings.Arguments[2] = '  second  '));
    Check('report configuration roundtrips', (Settings.ReportFormat = 'fpcunit-xml') And (Settings.MinimumTests = 2));
    Check('relative executable resolves from project directory', Settings.ResolvedExecutable = Root + '/test runner');
    Reloaded.Load; Check('test commands belong to one target document', Not Reloaded.Enabled And (Settings.StorageFilename <> Reloaded.StorageFilename)
      And (ExtractFileName(Settings.StorageFilename) = 'config.json'));
    Settings.Arguments.Add(''); Check('empty argument rejected explicitly', Not Settings.Validate(Note));
    Settings.Arguments.Delete(Settings.Arguments.Count - 1);
    Settings.Arguments.Add('bad' + #0 + 'argument'); Check('NUL argument rejected', Not Settings.Validate(Note));
    Settings.Arguments.Delete(Settings.Arguments.Count - 1); Settings.TimeoutSeconds := 0;
    Check('invalid timeout rejected', Not Settings.Validate(Note)); Settings.TimeoutSeconds := 3;
    Lines := TStringList.Create;
    Try
      Lines.Text := '{"show_thinking":true,"tests":{"enabled":true,"executable":"./test runner","arguments":[1]}}';
      Lines.SaveToFile(Settings.StorageFilename);
    Finally Lines.Free; End;
    Settings.Load; Check('malformed saved arguments disable execution', Not Settings.Enabled);
    WriteFile(Root + '/input.pas', 'saved source'); SetLength(Inputs, 1); Inputs[0].Path := Root + '/input.pas'; Inputs[0].Text := 'saved source';
    Args.Add('arguments'); Args.Add('two words'); Args.Add('$(touch never-created)'); Args.Add('  spaces  ');
    Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000); WaitDone;
    Data := GetJSON(AssistantBuildStatusJSON(Value, False));
    Try Check('test process uses literal argument array without shell expansion', (Data.FindPath('outcome').AsString = 'test_command_passed')
      And Data.FindPath('testsRun').AsBoolean And (Data.FindPath('build_job_id').AsString = 'build-1')
      And Not FileExists(Root + '/never-created'));
    Finally Data.Free; End;
    Args.Clear; Args.Add('fail'); Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000); WaitDone;
    Data := GetJSON(AssistantBuildStatusJSON(Value, False));
    Try Check('test failure stays distinct from successful compilation', (Value.ExitCode = 3)
      And (Data.FindPath('outcome').AsString = 'test_command_failed')); Finally Data.Free; End;
    Args.Clear; Args.Add('xml');
    Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000, '', 'fpcunit-xml', 1); WaitDone;
    Data := GetJSON(AssistantBuildStatusJSON(Value, False));
    Try Check('real FPCUnit report passes with executed test count', Data.FindPath('testReport.passed').AsBoolean And
      (Data.FindPath('testReport.executed').AsInteger = 1) And (Data.FindPath('outcome').AsString = 'test_command_passed'));
    Finally Data.Free; End;
    Data := GetJSON(ParseFPCUnitReport(Value.OutputText, False, 2));
    Try Check('minimum test count enforced', Not Data.FindPath('passed').AsBoolean); Finally Data.Free; End;
    Data := GetJSON(ParseFPCUnitReport(Value.OutputText, True, 1));
    Try Check('truncated XML never passes', Not Data.FindPath('valid').AsBoolean); Finally Data.Free; End;
    Data := GetJSON(ParseFPCUnitReport('<!DOCTYPE TestResults [<!ENTITY e SYSTEM "file:///no-read">]><TestResults/>', False, 1));
    Try Check('XML entities rejected before parsing', Not Data.FindPath('valid').AsBoolean); Finally Data.Free; End;
    Data := GetJSON(ParseFPCUnitReport('<TestResults/>', False, 1));
    Try Check('missing counts rejected', Not Data.FindPath('valid').AsBoolean); Finally Data.Free; End;
    Args.Clear; Args.Add('xml-fail');
    Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000, '', 'fpcunit-xml', 1); WaitDone;
    Data := GetJSON(AssistantBuildStatusJSON(Value, False));
    Try Check('report failure overrides zero process exit', (Value.ExitCode = 0) And
      (Data.FindPath('outcome').AsString = 'test_report_failed') And (Data.FindPath('testReport.failures').AsInteger = 1));
    Finally Data.Free; End;
    Args.Clear; Args.Add('hang'); Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 30); WaitDone;
    Check('test timeout bounded', Pos('timed out', Value.ErrorText) > 0);
    Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000); Job.Cancel; WaitDone;
    Check('test cancellation reported', Value.Cancelled);
    Args.Clear; Args.Add('changed'); Args.Add(Root + '/input.pas');
    Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000); WaitDone;
    Check('test mutation invalidates evidence even with zero exit', (Value.ExitCode = 0) And Not Value.InputsUnchanged);
    Check('runner fingerprint can be captured', ExecutableFingerprint(ParamStr(0), OldFingerprint, Note));
    Rejected := False;
    Try Job := StartAssistantTest(ParamStr(0), Root, 'build-1', Args, Inputs, 2000, 'different');
    Except On E: Exception Do Rejected := Pos('changed after approval', E.Message) > 0; End;
    Check('changed reviewed executable prevents launch', Rejected);
    WriteFile(Root + '/not-executable', 'text');
    Check('non-executable test path rejected', Not ExecutableFingerprint(Root + '/not-executable', OldFingerprint, Note));
  Finally
    Job := Nil; Args.Free; DeleteFile(Settings.StorageFilename); DeleteFile(Reloaded.StorageFilename); Settings.Free; Reloaded.Free;
    RemoveDir(Root + '/.assistant'); RemoveDir(Root + '/other/.assistant'); RemoveDir(Root + '/other');
    DeleteFile(Root + '/input.pas'); DeleteFile(Root + '/not-executable'); RemoveDir(Root);
  End;
End.
