Unit AssistantBuildJob;

{ Asynchronous saved-input build pilot. A detached worker owns the process;
  an interface snapshot keeps its state alive without IDE callbacks or joins.
  Diagnostics describe observed inputs, not proof of an immutable full build. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Type
  TBuildInput = Record Path, Text: String; End;
  TBuildInputs = Array Of TBuildInput;
  TBuildJobSnapshot = Record
    Done, Cancelled, InputsUnchanged, OutputTruncated, ProcessStarted: Boolean;
    ExitCode: Integer;
    OutputText, ErrorText, Manifest, JobId, Command, Kind, ParentJobId, ExecutableFingerprint, ReportFormat, ReportJSON: String;
    MinimumTests: Integer;
  End;
  IAssistantBuildJob = Interface
    ['{60D8C4B7-37B3-4B1C-89A5-F62B824BF6C8}']
    Procedure Cancel;
    Function Snapshot: TBuildJobSnapshot;
  End;
Function ReadBuildInput(Const Path: String; Out Text, ErrorText: String): Boolean;
Function BuildInputsMatch(Const Inputs: TBuildInputs; Out ErrorText: String): Boolean;
Function AddBuildInput(Var Inputs: TBuildInputs; Const Path: String; Out ErrorText: String): Boolean;
Function AssistantBuildStatusJSON(Const Value: TBuildJobSnapshot; Stale: Boolean): String;
Function ExecutableFingerprint(Const Path: String; Out Fingerprint, ErrorText: String): Boolean;
Function StartAssistantTest(Const Executable, Directory, BuildId: String; Arguments: TStrings;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal; Const ExpectedFingerprint: String = ''; Const ReportFormat: String = 'exit-code'; MinimumTests: Integer = 1): IAssistantBuildJob;
Function StartAssistantBuild(Const Executable, ProjectFile, BuildMode: String;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal = 600000; Const IDEProfile: String = ''; Const WidgetSet: String = ''): IAssistantBuildJob;
Implementation
Uses Process, Pipes, sha1, AssistantProtocol, AssistantBuildDiagnostics, AssistantTestReport, fpjson, jsonparser {$IFDEF LINUX}, BaseUnix{$ENDIF};
Type
  TBuildState = Class(TInterfacedObject, IAssistantBuildJob)
  Public
    Lock: TRTLCriticalSection;
    Cancelled: LongInt;
    Value: TBuildJobSnapshot;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Snapshot: TBuildJobSnapshot;
  End;
  TBuildWorker = Class(TThread)
  Private
    FState: TBuildState;
    FKeepAlive: IAssistantBuildJob;
    FExecutable, FDirectory: String;
    FArguments: TStringList;
    FInputs: TBuildInputs;
    FTimeout: Cardinal;
    FInitial: TBuildJobSnapshot;
    {$IFDEF LINUX}
    Procedure ChildFork(Sender: TObject);
    {$ENDIF}
    Function InputsMatch: Boolean;
  Public
    Destructor Destroy; Override;
  Protected
    Procedure Execute; Override;
  End;
Destructor TBuildWorker.Destroy;
Begin FArguments.Free; Inherited Destroy; End;
Function ExecutableFingerprint(Const Path: String; Out Fingerprint, ErrorText: String): Boolean;
{$IFDEF LINUX}Var Info: Stat;{$ENDIF}
Begin
  Result := False; Fingerprint := ''; ErrorText := '';
  Try
    {$IFDEF LINUX}
    If (fpStat(Path, Info) <> 0) Or Not FPS_ISREG(Info.st_mode) Or (Info.st_size > 67108864) Or
      (fpAccess(Path, X_OK) <> 0) Then
      Begin ErrorText := 'Test runner must be an executable regular file of at most 64 MiB.'; Exit; End;
    {$ENDIF}
    Fingerprint := SHA1Print(SHA1File(Path)); Result := True;
  Except On E: Exception Do ErrorText := 'Cannot fingerprint test executable: ' + E.Message; End;
End;
Constructor TBuildState.Create;
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  Value.ExitCode := -1;
End;
Destructor TBuildState.Destroy;
Begin DoneCriticalSection(Lock); Inherited Destroy; End;
Procedure TBuildState.Cancel;
Begin InterlockedExchange(Cancelled, 1); End;
Function TBuildState.Snapshot: TBuildJobSnapshot;
Begin
  EnterCriticalSection(Lock);
  Try Result := Value; Finally LeaveCriticalSection(Lock); End;
End;
{$IFDEF LINUX}
Procedure TBuildWorker.ChildFork(Sender: TObject);
Begin If fpSetsid < 0 Then fpExit(126); End;
{$ENDIF}
Function ReadBuildInput(Const Path: String; Out Text, ErrorText: String): Boolean;
Var Stream: TFileStream;
  {$IFDEF LINUX}Info: Stat;{$ENDIF}
Begin
  Result := False; Text := ''; ErrorText := '';
  Try
    {$IFDEF LINUX}
    If (fpStat(Path, Info) <> 0) Or Not FPS_ISREG(Info.st_mode) Then
      Begin ErrorText := 'Build input is missing or not a regular file: ' + Path; Exit; End;
    {$ENDIF}
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
    Try
      If Stream.Size > 1048576 Then Begin ErrorText := 'Build input exceeds 1 MiB: ' + Path; Exit; End;
      SetLength(Text, Stream.Size);
      If Text <> '' Then Stream.ReadBuffer(Text[1], Length(Text));
    Finally Stream.Free; End;
    Result := True;
  Except On E: Exception Do ErrorText := 'Cannot read build input ' + Path + ': ' + E.Message; End;
End;
Function BuildInputsMatch(Const Inputs: TBuildInputs; Out ErrorText: String): Boolean;
Var I: Integer; Text: String;
Begin
  Result := False; ErrorText := '';
  For I := 0 To High(Inputs) Do
    Begin
      If Not ReadBuildInput(Inputs[I].Path, Text, ErrorText) Then Exit;
      If Text <> Inputs[I].Text Then
        Begin ErrorText := 'Observed build input changed: ' + Inputs[I].Path; Exit; End;
    End;
  Result := True;
End;
Function AddBuildInput(Var Inputs: TBuildInputs; Const Path: String; Out ErrorText: String): Boolean;
Var I, Bytes, N: Integer; Canonical, Text: String;
Begin
  Result := False; ErrorText := ''; Canonical := ExpandFileName(Path); Bytes := 0;
  For I := 0 To High(Inputs) Do
    Begin
      If Inputs[I].Path = Canonical Then Exit(True);
      Inc(Bytes, Length(Inputs[I].Text));
    End;
  If Length(Inputs) >= 512 Then Begin ErrorText := 'Build snapshot exceeds 512 files.'; Exit; End;
  If Not ReadBuildInput(Canonical, Text, ErrorText) Then Exit;
  If Bytes + Length(Text) > 33554432 Then Begin ErrorText := 'Build snapshot exceeds 32 MiB.'; Exit; End;
  N := Length(Inputs); SetLength(Inputs, N + 1); Inputs[N].Path := Canonical; Inputs[N].Text := Text;
  Result := True;
End;
Function AssistantBuildStatusJSON(Const Value: TBuildJobSnapshot; Stale: Boolean): String;
Var Root: TJSONObject; Diagnostics, Manifest: TJSONArray; Data: TJSONData;
  Truncated: Boolean; Outcome, Excerpt: String; I, Bytes: Integer;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('job_id', Value.JobId); Root.Add('done', Value.Done);
    Root.Add('exitCode', Value.ExitCode); Root.Add('cancelled', Value.Cancelled);
    Root.Add('stale', Stale); Root.Add('verified', False); Root.Add('testsRun', (Value.Kind = 'test') And Value.ProcessStarted);
    Root.Add('kind', Value.Kind); Root.Add('build_job_id', Value.ParentJobId);
    Root.Add('executableFingerprint', Value.ExecutableFingerprint);
    If Not Value.Done Then Outcome := 'running'
    Else If Value.Cancelled Then Outcome := 'cancelled'
    Else If Stale Then Outcome := 'stale'
    Else If Value.ErrorText <> '' Then Outcome := 'failed'
    Else If Value.Kind = 'test' Then
      Begin If Value.ExitCode = 0 Then Outcome := 'test_command_passed' Else Outcome := 'test_command_failed'; End
    Else If Value.ExitCode <> 0 Then Outcome := 'compile_failed'
    Else Outcome := 'compile_passed';
    If Value.ReportJSON <> '' Then
      Begin
        Data := GetJSON(Value.ReportJSON);
        If (Outcome = 'test_command_passed') And Not Data.FindPath('passed').AsBoolean Then Outcome := 'test_report_failed';
        Root.Add('testReport', Data);
      End;
    Root.Add('outcome', Outcome);
    If Value.Kind = 'test' Then
      Root.Add('validationScope', 'Configured process and observed saved inputs/executable. Check testReport when XML reporting is configured; test relevance and compiler/runtime environment are not verified.')
    Else Root.Add('validationScope', 'Observed saved input manifest; check dependencies for CodeTools source coverage. Compiler/linker environment is not frozen. Compilation is not test validation.');
    Manifest := TJSONArray.Create; Root.Add('manifest', Manifest); Truncated := False; Bytes := 0;
    If Value.Manifest <> '' Then
      Begin
        Data := GetJSON(Value.Manifest);
        Try
          For I := 0 To Data.Count - 1 Do
            Begin
              Inc(Bytes, Length(Data.Items[I].AsJSON));
              If Bytes > 65536 Then Begin Truncated := True; Break; End;
              Manifest.Add(Data.Items[I].Clone);
            End;
        Finally Data.Free; End;
      End;
    Root.Add('manifestTruncated', Truncated);
    If (Value.Command <> '') And (Length(Value.Command) <= 65536) Then Root.Add('command', GetJSON(Value.Command));
    Root.Add('commandTruncated', Length(Value.Command) > 65536);
    Diagnostics := ParseBuildDiagnostics(Value.OutputText, Value.JobId, Truncated);
    Root.Add('items', Diagnostics); Root.Add('diagnosticsTruncated', Truncated);
    Root.Add('outputTruncated', Value.OutputTruncated);
    Excerpt := Value.OutputText;
    If Length(Excerpt) > 48000 Then
      Begin
        Excerpt := Copy(Excerpt, Length(Excerpt) - 47999, 48000);
        While (Excerpt <> '') And ((Byte(Excerpt[1]) And $C0) = $80) Do Delete(Excerpt, 1, 1);
      End;
    Root.Add('logExcerptTruncated', Length(Value.OutputText) > 48000);
    Root.Add('diagnostics', Excerpt);
    Root.Add('error', Value.ErrorText); Result := Root.AsJSON;
  Finally Root.Free; End;
End;
Function TBuildWorker.InputsMatch: Boolean;
Var Note, Fingerprint: String;
Begin
  Result := (InterlockedCompareExchange(FState.Cancelled, 0, 0) = 0) And BuildInputsMatch(FInputs, Note);
  If Result And (FInitial.Kind = 'test') Then
    Result := ExecutableFingerprint(FExecutable, Fingerprint, Note) And (Fingerprint = FInitial.ExecutableFingerprint);
End;
Procedure TBuildWorker.Execute;
Var P: TProcess; Value: TBuildJobSnapshot; Deadline, LastPublish: QWord;
  I, N, Budget: Integer; Buf: Array[0..8191] Of Char; Part: String;
  Procedure Publish;
  Begin
    EnterCriticalSection(FState.Lock);
    Try FState.Value := Value; Finally LeaveCriticalSection(FState.Lock); End;
    LastPublish := GetTickCount64;
  End;
  Procedure Drain(Pipe: TInputPipeStream);
  Begin
    Budget := 65536;
    While (Pipe.NumBytesAvailable > 0) And (Budget > 0) Do
      Begin
        N := Pipe.NumBytesAvailable; If N > SizeOf(Buf) Then N := SizeOf(Buf);
        N := Pipe.Read(Buf, N); If N <= 0 Then Break;
        Dec(Budget, N);
        If Length(Value.OutputText) + N > 1048576 Then Value.OutputTruncated := True;
        If Length(Value.OutputText) < 1048576 Then
          Begin
            SetString(Part, PChar(@Buf[0]), N);
            Value.OutputText := Value.OutputText + Copy(Part, 1, 1048576 - Length(Value.OutputText));
          End;
      End;
  End;
Begin
  P := Nil; Value := FInitial; LastPublish := 0;
  Try
    Try
      {$IFNDEF LINUX}
      Raise Exception.Create('Asynchronous build pilot currently supports Linux only.');
      {$ENDIF}
      Value.Manifest := '[';
      For I := 0 To High(FInputs) Do
        Begin
          If I > 0 Then Value.Manifest := Value.Manifest + ',';
          Value.Manifest := Value.Manifest + '{"path":"' + JsonEscapeText(FInputs[I].Path) +
            '","sha1":"' + SHA1Print(SHA1String(FInputs[I].Text)) + '"}';
        End;
      Value.Manifest := Value.Manifest + ']'; Publish;
      If Not InputsMatch Then Raise Exception.Create('Build inputs changed or are not saved; build not started.');
      P := TProcess.Create(Nil);
      P.Executable := FExecutable; P.CurrentDirectory := FDirectory;
      P.Parameters.Assign(FArguments);
      P.Options := [poUsePipes, poStderrToOutPut];
      {$IFDEF LINUX}
      P.OnForkEvent := @ChildFork;
      {$ENDIF}
      P.Execute; Value.ProcessStarted := True; Publish;
      Deadline := GetTickCount64 + FTimeout;
      Repeat
        Drain(P.Output);
        If GetTickCount64 - LastPublish >= 100 Then Publish;
        Value.Cancelled := InterlockedCompareExchange(FState.Cancelled, 0, 0) <> 0;
        If Value.Cancelled Then Break;
        If GetTickCount64 >= Deadline Then
          Begin Value.ErrorText := 'Build/test command timed out.'; Break; End;
        If Not P.Running And (P.Output.NumBytesAvailable = 0) Then Break;
        Sleep(5);
      Until False;
      If Not P.Running Then Value.ExitCode := P.ExitCode;
      Value.InputsUnchanged := InputsMatch;
      If Not Value.InputsUnchanged And (Value.ErrorText = '') And Not Value.Cancelled Then
        Value.ErrorText := 'Observed inputs or test executable changed during execution; results are stale.';
    Except
      On E: Exception Do Value.ErrorText := E.Message;
    End;
  Finally
    If Assigned(P) Then
      Begin
        {$IFDEF LINUX}
        { Kill the owned group even if the compiler parent has already exited. }
        If P.ProcessID > 0 Then
          Begin
            fpKill(-P.ProcessID, SIGKILL);
            If P.Running Then Begin fpKill(P.ProcessID, SIGKILL); P.WaitOnExit(500); End;
          End;
        {$ENDIF}
        P.Free;
      End;
    Value.Cancelled := InterlockedCompareExchange(FState.Cancelled, 0, 0) <> 0;
    If (Value.Kind = 'test') And (Value.ReportFormat = 'fpcunit-xml') Then
      Value.ReportJSON := ParseFPCUnitReport(Value.OutputText, Value.OutputTruncated, Value.MinimumTests);
    Value.Done := True;
    EnterCriticalSection(FState.Lock);
    Try FState.Value := Value; Finally LeaveCriticalSection(FState.Lock); End;
    FKeepAlive := Nil;
  End;
End;
Function StartCommand(Const Executable, Directory, Kind, ParentJobId, ExpectedFingerprint, ReportFormat: String; MinimumTests: Integer; Arguments: TStrings;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal): IAssistantBuildJob;
Var State: TBuildState; Worker: TBuildWorker; Id: TGuid; Command: TJSONObject; Args: TJSONArray; I: Integer; Note: String;
Begin
  For I := 0 To Arguments.Count - 1 Do
    If (Arguments[I] = '') Or (Pos(#0, Arguments[I]) > 0) Then
      Raise Exception.Create('Empty or NUL-containing process arguments are unsupported.');
  If CreateGUID(Id) <> 0 Then Raise Exception.Create('Cannot create job identity.');
  State := TBuildState.Create; Result := State;
  State.Value.JobId := GUIDToString(Id); State.Value.ReportFormat := ReportFormat; State.Value.MinimumTests := MinimumTests; State.Value.Kind := Kind; State.Value.ParentJobId := ParentJobId;
  If (Kind = 'test') And Not ExecutableFingerprint(Executable, State.Value.ExecutableFingerprint, Note) Then
    Raise Exception.Create(Note);
  If (ExpectedFingerprint <> '') And (State.Value.ExecutableFingerprint <> ExpectedFingerprint) Then
    Raise Exception.Create('Test executable changed after approval.');
  Command := TJSONObject.Create;
  Try
    Command.Add('executable', Executable); Command.Add('workingDirectory', Directory);
    Args := TJSONArray.Create;
    For I := 0 To Arguments.Count - 1 Do Args.Add(Arguments[I]);
    Command.Add('arguments', Args); State.Value.Command := Command.AsJSON;
  Finally Command.Free; End;
  Worker := TBuildWorker.Create(True);
  Worker.FreeOnTerminate := True;
  Worker.FState := State; Worker.FKeepAlive := Result; Worker.FInitial := State.Value;
  Worker.FExecutable := Executable; Worker.FDirectory := Directory;
  Worker.FArguments := TStringList.Create; Worker.FArguments.Assign(Arguments);
  Worker.FInputs := Copy(Inputs); Worker.FTimeout := TimeoutMs; Worker.Start;
End;
Function StartAssistantTest(Const Executable, Directory, BuildId: String; Arguments: TStrings;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal; Const ExpectedFingerprint, ReportFormat: String; MinimumTests: Integer): IAssistantBuildJob;
Begin Result := StartCommand(Executable, Directory, 'test', BuildId, ExpectedFingerprint, ReportFormat, MinimumTests, Arguments, Inputs, TimeoutMs); End;
Function StartAssistantBuild(Const Executable, ProjectFile, BuildMode: String;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal; Const IDEProfile, WidgetSet: String): IAssistantBuildJob;
Var Arguments: TStringList;
Begin
  Arguments := TStringList.Create;
  Try
    If IDEProfile <> '' Then Arguments.Add('--pcp=' + IDEProfile);
    If WidgetSet <> '' Then Arguments.Add('--widgetset=' + WidgetSet);
    If BuildMode <> '' Then Arguments.Add('--build-mode=' + BuildMode);
    Arguments.Add(ProjectFile);
    Result := StartCommand(Executable, ExtractFilePath(ProjectFile), 'build', '', '', 'exit-code', 1, Arguments, Inputs, TimeoutMs);
  Finally Arguments.Free; End;
End;
End.
