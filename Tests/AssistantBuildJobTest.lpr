Program AssistantBuildJobTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, fpjson, jsonparser, AssistantBuildDiagnostics, AssistantBuildJob, AssistantProtocol,
  AssistantAcceptance, BaseUnix;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok ', Name); End;
Procedure WriteFile(Const Path, Text: String);
Var Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try If Text <> '' Then Stream.WriteBuffer(Text[1], Length(Text)); Finally Stream.Free; End;
End;
Var Job: IAssistantBuildJob; Value: TBuildJobSnapshot; Inputs, FolderInputs: TBuildInputs;
  Path, Note, ID, Folder, Outside, EmptyDir: String; Deadline, Started: QWord; Data: TJSONData; Diagnostics: TJSONArray;
  Truncated: Boolean; I: Integer; Packages: TStringList;
Procedure WaitDone;
Begin
  Deadline := GetTickCount64 + 3000;
  Repeat Value := Job.Snapshot; Sleep(1); Until Value.Done Or (GetTickCount64 >= Deadline);
  Check('build completes within deadline', Value.Done);
End;
Begin
  If ParamCount > 0 Then
    Begin
      If ParamStr(1) = '--build-mode=live' Then Begin WriteLn('unit.pas(7,2) Warning: still running'); Flush(Output); Sleep(700); End;
      If ParamStr(1) = '--build-mode=flood' Then For I := 1 To 18000 Do WriteLn(StringOfChar('x', 80));
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
    ID := Job.Snapshot.JobId; Check('job identity available at launch', ID <> '');
    WaitDone;
    Check('same identity after completion', Value.JobId = ID);
    Check('successful exit and observed inputs', (Value.ExitCode = 0) And Value.InputsUnchanged);
    Check('manifest and log retained', (Pos('sha1', Value.Manifest) > 0) And (Pos('fixture completed', Value.OutputText) > 0));
    Job := StartAssistantBuild(ParamStr(0), Path, 'bad', Inputs); WaitDone;
    Check('compiler error returned', (Value.ExitCode = 1) And (Pos('unit.pas(3,1)', Value.OutputText) > 0));
    Data := GetJSON(AssistantBuildStatusJSON(Value, False));
    Try
      Check('compiler failure yields located diagnostics', (Data.FindPath('outcome').AsString = 'compile_failed')
        And (Data.FindPath('items[0].line').AsInteger = 3) And (Data.FindPath('items[0].column').AsInteger = 1)
        And (Data.FindPath('items[0].job_id').AsString = Value.JobId));
    Finally Data.Free; End;
    Diagnostics := ParseBuildDiagnostics('path with spaces/u.pas(9,12) Error: bad: value' + LineEnding +
      'u.inc(4) Hint: note' + LineEnding + 'broken(0,1) Error: ignored' + LineEnding +
      'broken(1,x) Error: ignored' + LineEnding + 'status text', ID, Truncated);
    Try Check('parser preserves paths, severities and unknown columns', (Diagnostics.Count = 2)
      And (Diagnostics.Items[0].FindPath('path').AsString = 'path with spaces/u.pas')
      And (Diagnostics.Items[0].FindPath('message').AsString = 'bad: value')
      And (Diagnostics.Items[1].FindPath('column').AsInteger = 0)); Finally Diagnostics.Free; End;
    Note := ''; For I := 1 To 201 Do Note := Note + 'u.pas(1,1) Error: repeated' + LineEnding;
    Diagnostics := ParseBuildDiagnostics(Note, ID, Truncated);
    Try Check('diagnostic limit is explicit', (Diagnostics.Count = 200) And Truncated); Finally Diagnostics.Free; End;
    Job := StartAssistantBuild(ParamStr(0), Path, 'live', Inputs);
    Deadline := GetTickCount64 + 2000;
    Repeat Value := Job.Snapshot; Sleep(1); Until (Value.OutputText <> '') Or Value.Done Or (GetTickCount64 >= Deadline);
    Check('output is published before process exits', Not Value.Done And (Pos('still running', Value.OutputText) > 0)); WaitDone;
    Job := StartAssistantBuild(ParamStr(0), Path, 'flood', Inputs); WaitDone;
    Check('bounded output reports truncation', Value.OutputTruncated And (Length(Value.OutputText) = 1048576));
    Note := AssistantBuildStatusJSON(Value, False);
    Check('large logs fit managed tool transport', Length(JsonEscapeText(Note)) < 1048000);
    Check('quote becomes a backslash escape', JsonEscapeText('"') = '\"');
    Check('a valid e acute is unchanged', JsonEscapeText(#$C3#$A9) = #$C3#$A9);
    Check('a lone FF byte is replaced', JsonEscapeText(#$FF) = #$EF#$BF#$BD);
    Check('a long quote string doubles', Length(JsonEscapeText(StringOfChar('"', 100000))) = 200000);
    Data := GetJSON(Note);
    Try Check('raw log excerpt truncation is explicit', Data.FindPath('logExcerptTruncated').AsBoolean);
    Finally Data.Free; End;
    WriteFile(Path, 'user changed source');
    Check('completed evidence rejects later saved changes', Not BuildInputsMatch(Inputs, Note));
    Data := GetJSON(AssistantBuildStatusJSON(Value, True));
    Try Check('stale compile is not a passing result', (Data.FindPath('outcome').AsString = 'stale')
      And Not Data.FindPath('verified').AsBoolean And Not Data.FindPath('testsRun').AsBoolean); Finally Data.Free; End;

    Job := StartAssistantBuild(ParamStr(0), Path, 'good', Inputs); WaitDone;
    Check('stale input prevents compiler launch', (Value.ExitCode = -1) And (Value.OutputText = '') And (Value.ErrorText <> ''));
    WriteFile(Path, 'saved source');
    Job := StartAssistantBuild(ParamStr(0), Path, 'hang', Inputs, 50); WaitDone;
    Check('timeout bounded', Pos('timed out', Value.ErrorText) > 0);
    Job := StartAssistantBuild(ParamStr(0), Path, 'hang', Inputs); Job.Cancel; WaitDone;
    Check('cancel reported', Value.Cancelled);
    Check('input deduplication retains one snapshot', AddBuildInput(Inputs, Path, Note) And (Length(Inputs) = 1));
    Job := StartAssistantBuild('/no/such/compiler', Path, 'good', Inputs); WaitDone;
    Check('missing compiler fails without killing host', Value.ErrorText <> '');
    Folder := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-folder-' + IntToStr(GetProcessID);
    Outside := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-outside-' + IntToStr(GetProcessID);
    EmptyDir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-empty-' + IntToStr(GetProcessID);
    ForceDirectories(Folder); ForceDirectories(Outside); ForceDirectories(EmptyDir);
    Packages := TStringList.Create;
    Try
      WriteFile(IncludeTrailingPathDelimiter(Folder) + 'A.lpk', 'package a');
      WriteFile(IncludeTrailingPathDelimiter(Folder) + 'B.lpk', 'package b');
      WriteFile(IncludeTrailingPathDelimiter(Outside) + 'Z.lpk', 'package z');
      WriteFile(IncludeTrailingPathDelimiter(EmptyDir) + 'Only.lpi', 'project');
      Check('folder resolves both packages', ResolveFolderPackages(Folder, '', Packages, Note) And (Packages.Count = 2)
        And (Pos('A.lpk', Packages[0]) > 0) And (Pos('B.lpk', Packages[1]) > 0));
      FolderInputs := Nil;
      Job := StartAssistantFolderBuild(ParamStr(0), Folder, Packages, FolderInputs); WaitDone;
      Data := GetJSON(AssistantBuildStatusJSON(Value, False));
      Try
        Check('folder build reports both packages', (Data.FindPath('items').Count = 2)
          And (Pos('A.lpk', Data.FindPath('items[0].path').AsString) > 0)
          And (Pos('B.lpk', Data.FindPath('items[1].path').AsString) > 0)
          And (Data.FindPath('items[0].outcome').AsString = 'compile_passed')
          And (Data.FindPath('items[1].outcome').AsString = 'compile_passed'));
        Check('both packages were passed to the compiler', (Pos('A.lpk', Value.Command) > 0) And (Pos('B.lpk', Value.Command) > 0));
      Finally Data.Free; End;
      Check('package selects one', ResolveFolderPackages(Folder, 'A.lpk', Packages, Note) And (Packages.Count = 1)
        And (Pos('A.lpk', Packages[0]) > 0));
      Job := StartAssistantFolderBuild(ParamStr(0), Folder, Packages, FolderInputs); WaitDone;
      Data := GetJSON(AssistantBuildStatusJSON(Value, False));
      Try
        Check('package builds one', (Data.FindPath('items').Count = 1)
          And (Pos('A.lpk', Data.FindPath('items[0].path').AsString) > 0) And (Pos('B.lpk', Value.Command) = 0));
      Finally Data.Free; End;
      Check('a path outside the target is refused', Not ResolveFolderPackages(Folder, IncludeTrailingPathDelimiter(Outside) + 'Z.lpk', Packages, Note)
        And (Pos('outside', Note) > 0) And (Pos('not a regular file', Note) = 0));
      Check('a folder with no package is a clear error', Not ResolveFolderPackages(EmptyDir, '', Packages, Note)
        And (Pos('No Lazarus package', Note) > 0) And (Pos('not a regular file', Note) = 0));
    Finally
      Packages.Free;
      DeleteFile(IncludeTrailingPathDelimiter(Folder) + 'A.lpk');
      DeleteFile(IncludeTrailingPathDelimiter(Folder) + 'B.lpk');
      RemoveDir(ExcludeTrailingPathDelimiter(Folder));
      DeleteFile(IncludeTrailingPathDelimiter(Outside) + 'Z.lpk');
      RemoveDir(ExcludeTrailingPathDelimiter(Outside));
      DeleteFile(IncludeTrailingPathDelimiter(EmptyDir) + 'Only.lpi');
      RemoveDir(ExcludeTrailingPathDelimiter(EmptyDir));
    End;
    DeleteFile(Path); fpMkFifo(PChar(Path), &600);
    Check('special input is rejected without blocking', Not ReadBuildInput(Path, Note, ID));
    Value := Default(TBuildJobSnapshot);
    Value.JobId := 'job-summary';
    Value.Done := True;
    Value.ExitCode := 1;
    Value.Kind := 'build';
    Value.OutputText := 'unit.pas(2,1) Error: alpha missing' + LineEnding +
      'unit.pas(3,1) Error: beta missing' + LineEnding + 'unit.pas(4,1) Error: gamma missing' + LineEnding;
    Note := '[';
    For I := 1 To 2000 Do
      Begin
        If I > 1 Then Note := Note + ',';
        Note := Note + '{"path":"/usr/lib/lazarus/lcl/include/input-' + IntToStr(I) +
          '.inc","sha1":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';
      End;
    Value.Manifest := Note + ']';
    Note := AssistantBuildStatusJSON(Value, True, 'Editor text differs from the saved build input.');
    Check('default status stays within the tool-result limit', Length(Note) < 16384);
    Check('default status omits the manifest paths', Pos('input-2000.inc', Note) = 0);
    Data := GetJSON(Note);
    Try
      Check('summary names the stale reason',
        Data.FindPath('staleReason').AsString = 'Editor text differs from the saved build input.');
      Check('summary counts the manifest', Data.FindPath('manifestCount').AsInteger = 2000);
      Check('summary keeps every error diagnostic', (Data.FindPath('items').Count = 3) And
        (Pos('alpha missing', Note) > 0) And (Pos('beta missing', Note) > 0) And (Pos('gamma missing', Note) > 0));
    Finally
      Data.Free;
    End;
    Note := AssistantBuildStatusJSON(Value, True, 'Editor text differs from the saved build input.', 'manifest');
    Check('detail manifest includes the observed inputs', (Pos('input-1.inc', Note) > 0) And (Pos('input-2000.inc', Note) > 0));
    Value.ExitCode := 0;
    Value.OutputText := '';
    Note := AssistantBuildStatusJSON(Value, False);
    Data := GetJSON(Note);
    Try
      TJSONObject(Data).Add('dependencies', GetJSON('{"sourceClosureComplete":true,"addedInputs":3}'));
      Check('completion check accepts the summary', CheckAssistantAcceptance('Validation: build', Data.AsJSON, '', ID) And
        (Data.FindPath('outcome').AsString = 'compile_passed') And (Data.FindPath('job_id').AsString = 'job-summary'));
    Finally
      Data.Free;
    End;
  Finally Job := Nil; DeleteFile(Path); End;
  WriteLn('All build job tests passed.');
End.
