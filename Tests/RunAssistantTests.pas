#!/usr/bin/env instantfpc
Program RunAssistantTests;

{ Repeatable assistant regression runner (c) 2026 Michell Computing.

  Invoke with InstantFPC. Python is not used:
    instantfpc Tests/RunAssistantTests.pas --lazarus-root <Lazarus checkout>
  Compiled test programs and logs are written to Temporary/Tests-<pid>-<n> at the repository root, not beside these
  sources and not in the system temporary directory; --output-dir chooses another directory. Everything under
  Temporary/ can be deleted between sessions. Test programs get the output directory in LAZ_TEST_OUTPUT_DIR for files
  someone will look at, such as screenshots. Their own scratch fixtures stay in the system temporary directory, because
  a fixture inside this repository would find its .git and .assistant folders when it searches upwards for a root.

  --define NAME passes -dNAME to every fpc build and to the monitor package build. --heaptrc and --valgrind
  build and run only the named test programs, so each needs at least one --only. They cannot be combined, and
  neither may be used with --independent, --package-check or --gui. Valgrind multiplies the run timeout by 20,
  capped at 3600 seconds, and runs far slower than heaptrc. A valgrind build omits -gl and then
  objcopy --strip-debug, because Valgrind 3.24 aborts in its DWARF reader on these binaries.
  Tests/FpcTimezone.supp hides the RTL timezone init reports.

  Size note (2026-11-07): over 1000 lines once the memory-check probes of plan item 2.4 (Documents/Plan-20261107-025146.md)
  were added. Plan item 2.3 names Tests/RunAssistantTestsOptions.inc as the place to move the option handling when the
  memory-check settings have settled. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils, Process;

Const
  CoreTestNames: Array[0..57] Of String = (
    'AssistantUtf8StreamTest', 'AssistantClaudeClientTest', 'AssistantMCPProtocolTest', 'AssistantMCPListenerTest',
    'AssistantMCPBridgeTest', 'AssistantMCPApprovalTest',
    'WorkflowEventsLifetimeTest', 'GitStatusParseTest', 'CommitAttributesParseTest', 'RepositorySafetyTest', 'WasteBinArgsTest',
    'AssistantArchiveRollbackTest', 'AssistantConversationIdentityTest', 'AssistantMonitorMirrorTest', 'AssistantPlanEolTest', 'AssistantAcceptanceTest', 'AssistantEventsTest',
    'AssistantLfmTest', 'AssistantImagesTest', 'AssistantProjectPathsTest', 'AssistantSamplerTest',
    'AssistantSearchUtilTest', 'AssistantTraceTest', 'AssistantConnectionsTest', 'AssistantAccountUsageTest',
    'AssistantFileCreationTest', 'AssistantCodexHandshakeTest', 'AssistantTestRunnerTest',
    'AssistantCodexTransportTest', 'AssistantCodexClientTest', 'AssistantCodexSchemaTest', 'AssistantWorkTargetTest',
    'AssistantGeneratedImageTest', 'AssistantWriteImageTest', 'AssistantBuildJobTest', 'AssistantGitTest',
    'IndependentInstallTest', 'RepositoryOnlyInstall', 'AssistantOnlyInstall', 'AssistantRecoveryTest',
    'AssistantTurnFinishTest', 'AssistantPlanRunTest', 'AssistantRecoverySettingsTest',
    'AssistantTasksTest', 'AssistantMonitorAbsent', 'AssistantMonitorCodecTest', 'AssistantMonitorSessionTest',
    'AssistantMonitorEscapeTest', 'AssistantMonitorLockupTest', 'AssistantMonitorOutboxTest',
    'AssistantMonitorCommandIntakeTest', 'AssistantMonitorProtocolV3Test', 'AssistantMonitorSocketTest',
    'AssistantMonitorLinkTest', 'AssistantMonitorGrainTest', 'AssistantMonitorPlanFetchTest',
    'AssistantMonitorChaosTest', 'AssistantMonitorAcceptance');
  GuiTestNames: Array[0..19] Of String = (
    'PluginFormLifetimeTest', 'SpellMemoInputTest', 'AssistantSubagentsTest', 'AssistantHarnessTest',
    'AssistantEditorEditsTest', 'AssistantBuildWorkspaceTest', 'AssistantBuildDependenciesTest',
    'AssistantChangeSetsTest', 'AssistantWorkspaceTest', 'AssistantCodeToolsTest', 'AssistantSettingsTest',
    'AssistantProviderTest', 'AssistantReconnectTest', 'MarkdownLayoutTest', 'AssistantTraceViewTest',
    'AssistantConversationSurfaceTest', 'AssistantMarkdownAsyncTest', 'AssistantConversationStressTest',
    'AssistantMonitorFormLoadTest', 'AssistantMonitorBridgeTest');
  { Planted-fault probes run only when named with --only. Each runs twice: with ProbeCleanArg it must pass, and with
    no argument, under --heaptrc or --valgrind, the memory check must report the planted fault. }
  ProbeTestNames: Array[0..1] Of String = ('MemoryCheckProbeLeak', 'MemoryCheckProbeUseAfterFree');
  ProbeCleanArg = '--clean';
  ProbeTimeoutSec = 15;
  { How each probe's planted run must fail: the start of the heaptrc problem, or a line in the valgrind log. }
  ProbeHeaptrcExpect: Array[0..1] Of String = ('heaptrc reported unfreed blocks', 'heaptrc reported a heap error');
  ProbeValgrindExpect: Array[0..1, 0..1] Of String = (
    ('definitely lost in loss record', 'definitely lost in loss record'), ('Invalid read', 'Invalid write'));

Type
  TMemoryCheck = (mcNone, mcHeaptrc, mcValgrind);
  { One child process run. Ran is False when it could not be started or raised an exception; Problem then says why.
    Otherwise Problem holds what heaptrc or valgrind reported, if anything. }
  TRunResult = Record
    Ran, Passed, TimedOut: Boolean;
    ExitCode: Integer;
    Problem, OutputText, LogPath: String;
  End;

Var
  Repo, LazarusRoot, OutputDir, ValgrindExe: String;
  LibraryDirs, OnlyNames, Defines, Failures: TStringList;
  Gui, PackageCheck, CompileOnly, Independent: Boolean;
  MemoryCheck: TMemoryCheck;

Const
  MaxDefines = 8;
  { Memory-check settings. Confirmed 2026-11-07 against FPC 3.3.1 and Valgrind 3.24.0.
    -gh with HEAPTRC=keepreleased reports leaks and a freed-block write. -gv loads cmem; -Facmem is not added.
    A global leak is still reachable, not definitely lost, so valgrind is the use-after-free check. }
  HeaptrcBuildFlags: Array[0..0] Of String = ('-gh');
  HeaptrcEnvironment = 'HEAPTRC=keepreleased';
  HeapReportMarker = 'unfreed memory blocks';
  HeapCleanLine = '0 unfreed memory blocks : 0';
  HeapFaultMarkers: Array[0..5] Of String = (
    'Marked memory at $', 'Wrong signature $', 'Wrong release size', 'Wrong size at dealloc', 'Memory error detected',
    'freed again');
  ValgrindBuildFlags: Array[0..0] Of String = ('-gv');
  ValgrindErrorExit = 99;
  ValgrindSlowdown = 20;
  MaxRunTimeoutSec = 3600;

Procedure FailUsage(Const Message: String);
Begin
  WriteLn(StdErr, Message);
  WriteLn(StdErr, 'instantfpc Tests/RunAssistantTests.pas --lazarus-root <Lazarus checkout> [--only ProgramName]...');
  WriteLn(StdErr, '  [--output-dir Dir] [--library-dir Dir]... [--define NAME]... [--gui] [--compile-only]');
  WriteLn(StdErr, '  [--package-check] [--independent] [--heaptrc | --valgrind]');
  WriteLn(StdErr, 'Without --output-dir, output goes to a new Temporary/Tests-<pid>-<n> at the repository root.');
  WriteLn(StdErr, '--define NAME passes -dNAME to every fpc build and to the monitor package build;');
  WriteLn(StdErr, '  NAME matches [A-Za-z_][A-Za-z0-9_]*, at most ' + IntToStr(MaxDefines) + ' names.');
  WriteLn(StdErr, '--heaptrc builds the test programs (not the packages) with ' + HeaptrcBuildFlags[0] + ' and runs them with ' +
    HeaptrcEnvironment + ';');
  WriteLn(StdErr, '  an unfreed block or a heap error reported by heaptrc fails the test.');
  WriteLn(StdErr, '--valgrind builds the test programs (not the packages) with ' + ValgrindBuildFlags[0] +
    ' and runs them under valgrind memcheck;');
  WriteLn(StdErr, '  a memcheck error or definite leak fails the test. The run timeout is multiplied by ' +
    IntToStr(ValgrindSlowdown) + ', capped at ' + IntToStr(MaxRunTimeoutSec) + ' s.');
  WriteLn(StdErr, '--heaptrc and --valgrind cannot be combined, each needs at least one --only, and neither may be used');
  WriteLn(StdErr, '  with --independent, --package-check or --gui.');
  WriteLn(StdErr, '--only ' + ProbeTestNames[0] + ' or --only ' + ProbeTestNames[1] + ' runs a planted-fault probe, which is not');
  WriteLn(StdErr, '  in the default run. Its ' + ProbeCleanArg + ' run must pass; under --heaptrc or --valgrind its planted run must');
  WriteLn(StdErr, '  be reported by the memory check. Without a memory check the planted run is skipped.');
  Halt(2);
End;

Procedure Say(Const Text: String);
Begin
  WriteLn(Text);
  Flush(Output);
End;

Function RepoFile(Const Relative: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Repo) + StringReplace(Relative, '/', PathDelim, [rfReplaceAll]);
End;

Function PathIsAbsolute(Const Name: String): Boolean;
Begin
  { SysUtils on this compiler has no FilenameIsAbsolute. }
  Result := (Name <> '') And ((Name[1] = PathDelim) Or ((Length(Name) > 1) And (Name[2] = ':')));
End;

Function ResolveExecutable(Const Name: String): String;
Begin
  Result := Name;
  If (Pos(PathDelim, Name) = 0) And Not PathIsAbsolute(Name) Then
    Result := ExeSearch(Name, GetEnvironmentVariable('PATH'));
  If (Result = '') Or Not FileExists(Result) Then
    Result := '';
End;

Function OutputBinary(Const Directory, Stem: String): String;
Begin
  { FPC 3.3.1 SysUtils has no ExeExt, and InstantFPC cannot see LazUtils.GetExeExt. }
  Result := IncludeTrailingPathDelimiter(Directory) + Stem;
  If Copy({$I %FPCTARGETOS%}, 1, 3) = 'win' Then
    Result := Result + '.exe';
End;

Procedure WriteTextFile(Const Path, Text: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Text <> '' Then
      Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Function ReadTextFile(Const Path: String): String;
Var
  Stream: TFileStream;
Begin
  Result := '';
  If Not FileExists(Path) Then
    Exit;
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Try
    SetLength(Result, Stream.Size);
    If Result <> '' Then
      Stream.ReadBuffer(Result[1], Length(Result));
  Finally
    Stream.Free;
  End;
End;

{ Returns '' when the heaptrc exit report shows no unfreed blocks and no heap error, or else a message naming the line. }
Function CheckHeapReport(Const LogText: String): String;
Var
  Lines: TStringList;
  I, J: Integer;
  Line: String;
  Found: Boolean;
Begin
  Result := '';
  Found := False;
  Lines := TStringList.Create;
  Try
    Lines.Text := LogText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        For J := 0 To High(HeapFaultMarkers) Do
          If Pos(HeapFaultMarkers[J], Line) > 0 Then
            Exit('heaptrc reported a heap error: ' + Line);
        If Pos(HeapReportMarker, Line) > 0 Then
          Begin
            Found := True;
            If Line <> HeapCleanLine Then
              Exit('heaptrc reported unfreed blocks: ' + Line);
          End;
      End;
  Finally
    Lines.Free;
  End;
  If Not Found Then
    Result := 'heaptrc report missing: no "' + HeapReportMarker + '" line in the output';
End;

{ Runs Command and writes its output to <LabelName>.log without reporting. Environment entries, when given, are added
  to a copy of this process's environment. AppendLog names a file whose text is added to the log after the run.
  CheckHeap applies CheckHeapReport to the output. }
Procedure ExecuteCommand(Const LabelName: String; Command: TStrings; TimeoutSec: Integer; Environment: TStrings;
  Const AppendLog: String; CheckHeap: Boolean; Out Run: TRunResult);
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Exe: String;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;
Begin
  Run.Ran := False;
  Run.Passed := False;
  Run.TimedOut := False;
  Run.ExitCode := -1;
  Run.Problem := '';
  Run.OutputText := '';
  Run.LogPath := IncludeTrailingPathDelimiter(OutputDir) + LabelName + '.log';
  Exe := ResolveExecutable(Command[0]);
  If Exe = '' Then
    Begin
      WriteTextFile(Run.LogPath, 'Executable not found: ' + Command[0] + LineEnding);
      Run.Problem := 'executable not found: ' + Command[0];
      Exit;
    End;
  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := Exe;
    Proc.CurrentDirectory := Repo;
    Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    For I := 1 To Command.Count - 1 Do
      Proc.Parameters.Add(Command[I]);
    If Assigned(Environment) Then
      Begin
        For I := 1 To GetEnvironmentVariableCount Do
          Proc.Environment.Add(GetEnvironmentString(I));
        For I := 0 To Environment.Count - 1 Do
          Proc.Environment.Values[Environment.Names[I]] := Environment.ValueFromIndex[I];
      End;
    Try
      Proc.Execute;
      Run.Ran := True;
      StartTick := GetTickCount64;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
          If GetTickCount64 - StartTick >= QWord(TimeoutSec) * 1000 Then
            Begin
              Run.TimedOut := True;
              Try
                Proc.Terminate(1);
              Except
              End;
              Break;
            End;
          If Proc.Output.NumBytesAvailable > 0 Then
            Begin
              BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
              If BytesRead > 0 Then
                Mem.WriteBuffer(Buf[0], BytesRead);
            End
          Else If Proc.Running Then
            Sleep(5);
        End;
      While Proc.Output.NumBytesAvailable > 0 Do
        Begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          If BytesRead > 0 Then
            Mem.WriteBuffer(Buf[0], BytesRead)
          Else
            Break;
        End;
      SetLength(Run.OutputText, Mem.Size);
      If Mem.Size > 0 Then
        Move(Mem.Memory^, Run.OutputText[1], Mem.Size);
      If Run.TimedOut Then
        Run.OutputText := Run.OutputText + LineEnding + 'Timed out.' + LineEnding;
      If AppendLog <> '' Then
        Run.OutputText := Run.OutputText + LineEnding + '----- ' + AppendLog + ' -----' + LineEnding + ReadTextFile(AppendLog);
      WriteTextFile(Run.LogPath, Run.OutputText);
      Run.ExitCode := Proc.ExitStatus;
      If CheckHeap And Not Run.TimedOut Then
        Run.Problem := CheckHeapReport(Run.OutputText);
      If (AppendLog <> '') And Not Run.TimedOut And (Run.ExitCode = ValgrindErrorExit) Then
        Run.Problem := 'valgrind reported errors (exit ' + IntToStr(ValgrindErrorExit) + ')';
      Run.Passed := Not Run.TimedOut And (Run.ExitCode = 0) And (Run.Problem = '');
    Except
      On E: Exception Do
        Begin
          WriteTextFile(Run.LogPath, E.Message + LineEnding);
          Run.Ran := False;
          Run.Passed := False;
          Run.Problem := E.Message;
        End;
    End;
  Finally
    Mem.Free;
    Proc.Free;
  End;
End;

Procedure SayTail(Const Text: String);
Var
  Tail: String;
Begin
  Tail := Text;
  If Length(Tail) > 4000 Then
    Tail := Copy(Tail, Length(Tail) - 3999, 4000);
  If Tail <> '' Then
    Say(Tail);
End;

{ Prints PASS or FAIL for Run, with the end of its output on failure, and counts a failure. }
Function ReportRun(Const LabelName: String; Const Run: TRunResult): Boolean;
Begin
  Result := Run.Passed;
  If Run.Passed Then
    Begin
      Say('PASS ' + LabelName);
      Exit;
    End;
  Failures.Add(LabelName);
  If Not Run.Ran Then
    Say('FAIL ' + LabelName + ': ' + Run.Problem)
  Else
    Begin
      If Run.Problem <> '' Then
        Say('FAIL ' + LabelName + ': ' + Run.Problem + '; see ' + Run.LogPath)
      Else
        Say('FAIL ' + LabelName + ': see ' + Run.LogPath);
      SayTail(Run.OutputText);
    End;
End;

Function RunCommand(Const LabelName: String; Command: TStrings; TimeoutSec: Integer): Boolean;
Var
  Run: TRunResult;
Begin
  ExecuteCommand(LabelName, Command, TimeoutSec, Nil, '', False, Run);
  Result := ReportRun(LabelName, Run);
End;

Function RunArgs(Const LabelName: String; Const Args: Array Of String; TimeoutSec: Integer): Boolean;
Var
  Command: TStringList;
  I: Integer;
Begin
  Command := TStringList.Create;
  Try
    For I := 0 To High(Args) Do
      Command.Add(Args[I]);
    Result := RunCommand(LabelName, Command, TimeoutSec);
  Finally
    Command.Free;
  End;
End;

Procedure CollectPpuDirs(Const Root: String; Excluded, Dirs: TStrings);
Var
  RootPrefix: String;

  Procedure Walk(Const Directory: String; Depth: Integer);
  Var
    Info: TSearchRec;
    Child, Rel, Rest, Part: String;
    Skip: Boolean;
  Begin
    If Depth > 40 Then
      Exit;
    If FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info) <> 0 Then
      Exit;
    Try
      Repeat
        If (Info.Name = '.') Or (Info.Name = '..') Then
          Continue;
        Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
        If DirectoryExists(Child) Then
          Walk(Child, Depth + 1)
        Else If LowerCase(ExtractFileExt(Info.Name)) = '.ppu' Then
          Begin
            Rel := Copy(Child, Length(RootPrefix) + 1, MaxInt);
            Rest := Rel;
            Skip := False;
            While Rest <> '' Do
              Begin
                If Pos(PathDelim, Rest) > 0 Then
                  Begin
                    Part := Copy(Rest, 1, Pos(PathDelim, Rest) - 1);
                    Delete(Rest, 1, Length(Part) + 1);
                  End
                Else
                  Begin
                    Part := Rest;
                    Rest := '';
                  End;
                If Excluded.IndexOf(Part) >= 0 Then
                  Begin
                    Skip := True;
                    Break;
                  End;
              End;
            If Not Skip Then
              Dirs.Add(ExcludeTrailingPathDelimiter(ExtractFilePath(Child)));
          End;
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  End;

Begin
  RootPrefix := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  Walk(Root, 0);
End;

Function HasInterfaces(Dirs: TStrings): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To Dirs.Count - 1 Do
    If FileExists(IncludeTrailingPathDelimiter(Dirs[I]) + 'interfaces.ppu') Then
      Exit(True);
End;

Procedure FillExcluded(List: TStrings; Const SkipWidget: String);
Const
  Names: Array[0..6] Of String = ('qt5', 'qt6', 'gtk2', 'gtk3', 'nogui', 'win32', 'cocoa');
Var
  I: Integer;
Begin
  List.Clear;
  For I := 0 To High(Names) Do
    If Names[I] <> SkipWidget Then
      List.Add(Names[I]);
End;

Function AssistantUnitDirs: TStringList;
Var
  Excluded: TStringList;
  Widget: String;
  I: Integer;
Begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.CaseSensitive := True;
  Excluded := TStringList.Create;
  Try
    { gtk3 is the project widgetset. gtk2 units can exist without the gtk2 libraries. }
    FillExcluded(Excluded, 'gtk3');
    CollectPpuDirs(LazarusRoot, Excluded, Result);
    If HasInterfaces(Result) Then
      Exit;
    For I := 0 To 2 Do
      Begin
        Case I Of
          0: Widget := 'gtk2';
          1: Widget := 'qt5';
        Else
          Widget := 'qt6';
        End;
        Result.Clear;
        FillExcluded(Excluded, Widget);
        CollectPpuDirs(LazarusRoot, Excluded, Result);
        If HasInterfaces(Result) Then
          Exit;
      End;
  Finally
    Excluded.Free;
  End;
End;

Procedure AddUnitFlags(Command: TStrings; UnitDirs: TStrings);
Const
  SourceNames: Array[0..5] Of String = (
    'LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText', 'LazRepositoryTools', 'Tools', 'LazAssistantMonitor');
Var
  I: Integer;
Begin
  For I := 0 To High(SourceNames) Do
    Command.Add('-Fu' + RepoFile('Source/' + SourceNames[I]));
  For I := 0 To UnitDirs.Count - 1 Do
    Command.Add('-Fu' + UnitDirs[I]);
  For I := 0 To LibraryDirs.Count - 1 Do
    Command.Add('-Fl' + ExpandFileName(LibraryDirs[I]));
End;

{ The default output directory is a new Temporary/Tests-<pid>-<n> at the repository root. Temporary/ gets a .gitignore
  that ignores everything in it; one that cannot be written leaves the folder untracked but does not stop the run. }
Function NewOutputDirectory(Const Requested: String): String;
Var
  I: Integer;
  Base, IgnoreFile: String;
Begin
  If Requested <> '' Then
    Begin
      Result := ExpandFileName(Requested);
      If Not ForceDirectories(Result) Then
        FailUsage('Could not create output directory: ' + Result);
      Exit;
    End;
  Base := RepoFile('Temporary');
  If Not ForceDirectories(Base) Then
    FailUsage('Could not create ' + Base);
  IgnoreFile := IncludeTrailingPathDelimiter(Base) + '.gitignore';
  If Not FileExists(IgnoreFile) Then
    Try
      WriteTextFile(IgnoreFile, '*' + LineEnding);
    Except
      On EStreamError Do ;
    End;
  For I := 0 To 100 Do
    Begin
      Result := IncludeTrailingPathDelimiter(Base) + 'Tests-' + IntToStr(GetProcessID) + '-' + IntToStr(I);
      If Not DirectoryExists(Result) And CreateDir(Result) Then
        Exit;
    End;
  FailUsage('Could not create an output directory under ' + Base);
End;

Function RepositoryRoot: String;
Var
  I: Integer;
  Probe, Dir: String;
Begin
  Result := '';
  Probe := ParamStr(0);
  If (ExtractFileExt(Probe) = '.pas') Or (ExtractFileExt(Probe) = '.lpr') Then
    Begin
      Dir := ExpandFileName(ExtractFilePath(Probe) + '..');
      If DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
    End;
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'RunAssistantTests.pas') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
End;

Function ValidDefineName(Const Name: String): Boolean;
Var
  I: Integer;
Begin
  Result := (Name <> '') And (Name[1] In ['A'..'Z', 'a'..'z', '_']);
  For I := 2 To Length(Name) Do
    If Not (Name[I] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Then
      Exit(False);
End;

Procedure ParseArguments;
Var
  I: Integer;
  Arg: String;
Begin
  I := 1;
  While I <= ParamCount Do
    Begin
      Arg := ParamStr(I);
      If Arg = '--help' Then
        FailUsage('Build and run the assistant regression programs.')
      Else If Arg = '--lazarus-root' Then
        Begin
          Inc(I);
          If I > ParamCount Then
            FailUsage('--lazarus-root needs a path.');
          LazarusRoot := ExpandFileName(ParamStr(I));
        End
      Else If Arg = '--output-dir' Then
        Begin
          Inc(I);
          If I > ParamCount Then
            FailUsage('--output-dir needs a path.');
          OutputDir := ParamStr(I);
        End
      Else If Arg = '--library-dir' Then
        Begin
          Inc(I);
          If I > ParamCount Then
            FailUsage('--library-dir needs a path.');
          LibraryDirs.Add(ParamStr(I));
        End
      Else If Arg = '--gui' Then
        Gui := True
      Else If Arg = '--package-check' Then
        PackageCheck := True
      Else If Arg = '--compile-only' Then
        CompileOnly := True
      Else If Arg = '--independent' Then
        Independent := True
      Else If Arg = '--only' Then
        Begin
          Inc(I);
          If I > ParamCount Then
            FailUsage('--only needs a program name.');
          OnlyNames.Add(ParamStr(I));
        End
      Else If Arg = '--define' Then
        Begin
          Inc(I);
          If I > ParamCount Then
            FailUsage('--define needs a name.');
          If Not ValidDefineName(ParamStr(I)) Then
            FailUsage('Bad --define name: ''' + ParamStr(I) + '''');
          If Defines.IndexOf(ParamStr(I)) < 0 Then
            Begin
              If Defines.Count >= MaxDefines Then
                FailUsage('At most ' + IntToStr(MaxDefines) + ' --define names are allowed.');
              Defines.Add(ParamStr(I));
            End;
        End
      Else If (Arg = '--heaptrc') Or (Arg = '--valgrind') Then
        Begin
          If ((Arg = '--heaptrc') And (MemoryCheck = mcValgrind)) Or ((Arg = '--valgrind') And (MemoryCheck = mcHeaptrc)) Then
            FailUsage('--heaptrc and --valgrind cannot be combined.');
          If Arg = '--heaptrc' Then
            MemoryCheck := mcHeaptrc
          Else
            MemoryCheck := mcValgrind;
        End
      Else
        FailUsage('Unknown argument: ' + Arg);
      Inc(I);
    End;
  If LazarusRoot = '' Then
    FailUsage('--lazarus-root is required.');
  If Not DirectoryExists(LazarusRoot) Then
    FailUsage('Lazarus root was not found: ' + LazarusRoot);
  If MemoryCheck <> mcNone Then
    Begin
      If MemoryCheck = mcHeaptrc Then
        Arg := '--heaptrc'
      Else
        Arg := '--valgrind';
      If OnlyNames.Count = 0 Then
        FailUsage(Arg + ' needs at least one --only.');
      If Independent Then
        FailUsage(Arg + ' cannot be used with --independent.');
      If PackageCheck Then
        FailUsage(Arg + ' cannot be used with --package-check.');
      If Gui Then
        FailUsage(Arg + ' cannot be used with --gui.');
    End;
  If MemoryCheck = mcValgrind Then
    Begin
      ValgrindExe := ResolveExecutable('valgrind');
      If ValgrindExe = '' Then
        Begin
          WriteLn(StdErr, 'valgrind is not installed.');
          Halt(1);
        End;
    End;
End;

Function SelectedTests: TStringList;
Var
  I: Integer;
  Missing: String;
Begin
  Result := TStringList.Create;
  For I := 0 To High(CoreTestNames) Do
    Result.Add(CoreTestNames[I]);
  If Gui Then
    For I := 0 To High(GuiTestNames) Do
      Result.Add(GuiTestNames[I]);
  If OnlyNames.Count = 0 Then
    Exit;
  { Probes are selectable by name only, never part of the default run. }
  For I := 0 To High(ProbeTestNames) Do
    Result.Add(ProbeTestNames[I]);
  Missing := '';
  For I := 0 To OnlyNames.Count - 1 Do
    If Result.IndexOf(OnlyNames[I]) < 0 Then
      Begin
        If Missing <> '' Then
          Missing := Missing + ', ';
        Missing := Missing + OnlyNames[I];
      End;
  If Missing <> '' Then
    Begin
      Result.Free;
      FailUsage('Unknown test: ' + Missing);
    End;
  For I := Result.Count - 1 DownTo 0 Do
    If OnlyNames.IndexOf(Result[I]) < 0 Then
      Result.Delete(I);
End;

Procedure AddBuildFlags(Command: TStrings);
Var
  I: Integer;
Begin
  For I := 0 To Defines.Count - 1 Do
    Command.Add('-d' + Defines[I]);
End;

Function BuildFlagsText: String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 0 To Defines.Count - 1 Do
    Result := Result + ' -d' + Defines[I];
End;

{ Memory-check flags go on the test program builds only, never on the package builds. }
Procedure AddMemoryCheckFlags(Command: TStrings);
Var
  I: Integer;
Begin
  Case MemoryCheck Of
    mcHeaptrc:
      For I := 0 To High(HeaptrcBuildFlags) Do
        Command.Add(HeaptrcBuildFlags[I]);
    mcValgrind:
      For I := 0 To High(ValgrindBuildFlags) Do
        Command.Add(ValgrindBuildFlags[I]);
  End;
End;

Function MemoryCheckText: String;
Var
  Command: TStringList;
Begin
  Result := '';
  If MemoryCheck = mcNone Then
    Exit;
  Command := TStringList.Create;
  Try
    Command.Delimiter := ' ';
    AddMemoryCheckFlags(Command);
    If MemoryCheck = mcHeaptrc Then
      Result := '; mode: heaptrc, test programs add ' + Command.DelimitedText + ' and run with ' + HeaptrcEnvironment
    Else
      Result := '; mode: valgrind, test programs add ' + Command.DelimitedText + ' and run under ' + ValgrindExe;
  Finally
    Command.Free;
  End;
End;

{ Runs the built program TestName as LabelName under the selected memory check, passing Arg when it is not empty. }
Procedure ExecuteTest(Const TestName, LabelName, Arg: String; TimeoutSec: Integer; Out Run: TRunResult);
Var
  Command, Environment: TStringList;
  ValgrindLog: String;
Begin
  Command := TStringList.Create;
  Environment := TStringList.Create;
  Try
    { A test saves files someone will look at, such as screenshots, in the output directory. }
    Environment.Add('LAZ_TEST_OUTPUT_DIR=' + ExcludeTrailingPathDelimiter(OutputDir));
    ValgrindLog := '';
    If MemoryCheck = mcHeaptrc Then
      Environment.Add(HeaptrcEnvironment)
    Else If MemoryCheck = mcValgrind Then
      Begin
        ValgrindLog := IncludeTrailingPathDelimiter(OutputDir) + LabelName + '.valgrind.log';
        If FileExists(ValgrindLog) Then
          DeleteFile(ValgrindLog);
        Command.Add(ValgrindExe);
        Command.Add('--error-exitcode=' + IntToStr(ValgrindErrorExit));
        Command.Add('--leak-check=full');
        Command.Add('--errors-for-leak-kinds=definite');
        { FPC string compares report uninitialised padding under cmem. Invalid reads and writes still count.
          --track-origins cannot be combined with this switch. }
        Command.Add('--undef-value-errors=no');
        { FPC 3.3.1 timezone init reports on every program. See Tests/FpcTimezone.supp. }
        Command.Add('--suppressions=' + RepoFile('Tests/FpcTimezone.supp'));
        Command.Add('--log-file=' + ValgrindLog);
        If TimeoutSec > MaxRunTimeoutSec Div ValgrindSlowdown Then
          TimeoutSec := MaxRunTimeoutSec
        Else
          TimeoutSec := TimeoutSec * ValgrindSlowdown;
      End;
    Command.Add(OutputBinary(OutputDir, TestName));
    If Arg <> '' Then
      Command.Add(Arg);
    ExecuteCommand(LabelName, Command, TimeoutSec, Environment, ValgrindLog, MemoryCheck = mcHeaptrc, Run);
  Finally
    Environment.Free;
    Command.Free;
  End;
End;

Function ProbeIndex(Const TestName: String): Integer;
Var
  I: Integer;
Begin
  Result := -1;
  For I := 0 To High(ProbeTestNames) Do
    If ProbeTestNames[I] = TestName Then
      Exit(I);
End;

{ Returns the report line that shows the memory check caught the planted fault of probe Index, or ''. A crash, a hang
  or a non-zero exit without that report does not count: the point is to prove the memory check sees the fault. }
Function PlantedFaultSeen(Index: Integer; Const Run: TRunResult): String;
Var
  Lines: TStringList;
  I, J: Integer;
Begin
  Result := '';
  If Run.Passed Or Not Run.Ran Then
    Exit;
  If MemoryCheck = mcHeaptrc Then
    Begin
      If Pos(ProbeHeaptrcExpect[Index], Run.Problem) = 1 Then
        Result := Run.Problem;
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    Lines.Text := Run.OutputText;
    For I := 0 To Lines.Count - 1 Do
      For J := 0 To High(ProbeValgrindExpect[Index]) Do
        If Pos(ProbeValgrindExpect[Index, J], Lines[I]) > 0 Then
          Exit('memcheck reported: ' + Trim(Lines[I]));
  Finally
    Lines.Free;
  End;
End;

{ The probe passes only when its clean run passes and, under a memory check, its planted run is caught. }
Procedure RunProbe(Const TestName: String; Index: Integer);
Var
  Run: TRunResult;
  Seen, Reason: String;
Begin
  ExecuteTest(TestName, TestName + '-clean', ProbeCleanArg, ProbeTimeoutSec, Run);
  If Not ReportRun(TestName + '-clean', Run) Then
    Begin
      Say('FAIL ' + TestName + ': the ' + ProbeCleanArg + ' run must pass');
      Exit;
    End;
  If MemoryCheck = mcNone Then
    Begin
      Say('SKIP ' + TestName + '-planted: the planted fault is only seen under --heaptrc or --valgrind');
      Exit;
    End;
  ExecuteTest(TestName, TestName + '-planted', '', ProbeTimeoutSec, Run);
  Seen := PlantedFaultSeen(Index, Run);
  If Seen <> '' Then
    Begin
      Say('PASS ' + TestName + ': the planted run failed as expected; ' + Seen + '; see ' + Run.LogPath);
      Exit;
    End;
  If Run.Passed Then
    Reason := 'the planted run passed'
  Else If Run.TimedOut Then
    Reason := 'the planted run timed out before any report'
  Else If Run.Problem <> '' Then
    Reason := Run.Problem
  Else
    Reason := 'the planted run exited ' + IntToStr(Run.ExitCode) + ' without the expected report';
  Say('FAIL ' + TestName + ': the planted fault was not caught (' + Reason + '); see ' + Run.LogPath);
  SayTail(Run.OutputText);
  Failures.Add(TestName);
End;

Procedure RunTest(Const TestName: String; TimeoutSec: Integer);
Var
  Run: TRunResult;
  Index: Integer;
Begin
  Index := ProbeIndex(TestName);
  If Index >= 0 Then
    RunProbe(TestName, Index)
  Else
    Begin
      ExecuteTest(TestName, TestName, '', TimeoutSec, Run);
      ReportRun(TestName, Run);
    End;
End;

Function Restricted(Const LabelName: String; Const Sources: Array Of String; Const Target: String;
  Execute: Boolean; TimeoutSec: Integer; UnitDirs: TStrings): Boolean;
Var
  Command: TStringList;
  OutDir: String;
  I: Integer;
Begin
  OutDir := IncludeTrailingPathDelimiter(OutputDir) + LabelName;
  ForceDirectories(OutDir);
  Command := TStringList.Create;
  Try
    Command.Add('fpc');
    Command.Add('-v0');
    Command.Add('-gl');
    Command.Add('-Cr');
    Command.Add('-Co');
    Command.Add('-MObjFPC');
    Command.Add('-FU' + OutDir);
    Command.Add('-FE' + OutDir);
    For I := 0 To High(Sources) Do
      Command.Add('-Fu' + RepoFile('Source/' + Sources[I]));
    For I := 0 To UnitDirs.Count - 1 Do
      Command.Add('-Fu' + UnitDirs[I]);
    AddBuildFlags(Command);
    Command.Add(Target);
    Result := RunCommand(LabelName + '-build', Command, TimeoutSec);
  Finally
    Command.Free;
  End;
  If Result And Execute And Not CompileOnly Then
    Result := RunArgs(LabelName, [OutputBinary(OutDir, ChangeFileExt(ExtractFileName(Target), ''))], TimeoutSec);
End;

Procedure RunMonitorPackage;
Var
  Lazbuild, ConfigDir, PackageOut, Opt: String;
  Links: Array[0..3] Of String;
  I: Integer;
Begin
  Lazbuild := IncludeTrailingPathDelimiter(LazarusRoot) + 'lazbuild';
  {$IFDEF WINDOWS}
  If Not FileExists(Lazbuild) And FileExists(Lazbuild + '.exe') Then
    Lazbuild := Lazbuild + '.exe';
  {$ENDIF}
  { Disposable config. Never the IDE primary config. }
  ConfigDir := IncludeTrailingPathDelimiter(OutputDir) + 'monitor-package-config';
  PackageOut := IncludeTrailingPathDelimiter(OutputDir) + 'monitor-package';
  If SameFileName(ExcludeTrailingPathDelimiter(ConfigDir), ExpandFileName('/home/paul/.lazarus')) Then
    FailUsage('Monitor package build must not use /home/paul/.lazarus.');
  ForceDirectories(ConfigDir);
  ForceDirectories(PackageOut);
  Links[0] := 'LazWorkflowCommon';
  Links[1] := 'LazStyledText';
  Links[2] := 'LazAssistantTools';
  Links[3] := 'LazAssistantMonitor';
  For I := 0 To High(Links) Do
    If Not RunArgs(Links[I] + '-monitor-link',
      [Lazbuild, '--pcp=' + ConfigDir, '--lazarusdir=' + LazarusRoot, '--ws=gtk3', '--add-package-link',
      RepoFile('Packages/' + Links[I] + '.lpk')], 120) Then
      Exit;
  Opt := '-FU' + ExcludeTrailingPathDelimiter(PackageOut) + ' -FE' + ExcludeTrailingPathDelimiter(PackageOut) + BuildFlagsText;
  RunArgs('LazAssistantMonitor-lazbuild',
    [Lazbuild, '--pcp=' + ConfigDir, '--lazarusdir=' + LazarusRoot, '--ws=gtk3', '--build-all', '--opt=' + Opt,
    RepoFile('Packages/LazAssistantMonitor.lpk')], 600);
End;

Function RunIndependent(UnitDirs: TStrings): Boolean;
Begin
  Result := Restricted('common-package', ['LazWorkflowCommon'], RepoFile('Packages/LazWorkflowCommon.pas'), False, 180, UnitDirs);
  Result := Restricted('styled-package', ['LazStyledText'], RepoFile('Packages/LazStyledText.pas'), False, 180, UnitDirs) And Result;
  Result := Restricted('repository-package', ['LazRepositoryTools', 'LazWorkflowCommon'],
    RepoFile('Packages/LazRepositoryTools.pas'), False, 300, UnitDirs) And Result;
  { Assistant package stub only. The monitor package is a later, separate lazbuild. }
  Result := Restricted('assistant-package', ['LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
    RepoFile('Packages/LazAssistantTools.pas'), False, 300, UnitDirs) And Result;
  RunMonitorPackage;
  Result := Restricted('AssistantMonitorAbsent', ['LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText', 'Tools'],
    RepoFile('Tests/AssistantMonitorAbsent.lpr'), True, 240, UnitDirs) And Result;
  Result := Restricted('RepositoryOnlyInstall', ['LazRepositoryTools', 'LazWorkflowCommon'],
    RepoFile('Tests/RepositoryOnlyInstall.lpr'), True, 240, UnitDirs) And Result;
  Result := Restricted('AssistantOnlyInstall', ['LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
    RepoFile('Tests/AssistantOnlyInstall.lpr'), True, 240, UnitDirs) And Result;
  Result := Restricted('IndependentInstallTest',
    ['LazRepositoryTools', 'LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
    RepoFile('Tests/IndependentInstallTest.lpr'), True, 240, UnitDirs) And Result;
End;

Procedure RunPackageCheck;
Var
  Lazbuild, Pcp: String;
  Names: Array[0..2] Of String;
  Command: TStringList;
  I: Integer;
  Linked: Boolean;
Begin
  Names[0] := 'LazWorkflowCommon';
  Names[1] := 'LazStyledText';
  Names[2] := 'LazAssistantTools';
  Lazbuild := IncludeTrailingPathDelimiter(LazarusRoot) + 'lazbuild';
  {$IFDEF WINDOWS}
  If Not FileExists(Lazbuild) And FileExists(Lazbuild + '.exe') Then
    Lazbuild := Lazbuild + '.exe';
  {$ENDIF}
  Pcp := IncludeTrailingPathDelimiter(OutputDir) + 'package-config';
  ForceDirectories(Pcp);
  Linked := True;
  For I := 0 To High(Names) Do
    Linked := RunArgs(Names[I] + '-package-link',
      [Lazbuild, '--pcp=' + Pcp, '--lazarusdir=' + LazarusRoot, '--ws=gtk3', '--add-package-link',
      RepoFile('Packages/' + Names[I] + '.lpk')], 90) And Linked;
  If Not Linked Then
    Exit;
  For I := 0 To High(Names) Do
    If Not RunArgs(Names[I] + '-lazbuild-package',
      [Lazbuild, '--pcp=' + Pcp, '--lazarusdir=' + LazarusRoot, '--ws=gtk3', '--skip-dependencies', '--build-all',
      RepoFile('Packages/' + Names[I] + '.lpk')], 90) Then
      Break;
End;

Function RunSuite: Boolean;
Var
  UnitDirs, Tests, Command: TStringList;
  I, BuildTimeout: Integer;
Begin
  Result := False;
  UnitDirs := AssistantUnitDirs;
  Try
    If UnitDirs.Count = 0 Then
      FailUsage('No compiled Lazarus units found; build Lazarus/gtk3 first.');
    If Independent Then
      Begin
        Result := RunIndependent(UnitDirs);
        Say('Logs: ' + OutputDir);
        Exit;
      End;
    Tests := SelectedTests;
    Command := TStringList.Create;
    Try
      If OnlyNames.Count > 0 Then
        BuildTimeout := 300
      Else
        BuildTimeout := 90;
      For I := 0 To Tests.Count - 1 Do
        Begin
          Command.Clear;
          Command.Add('fpc');
          Command.Add('-v0');
          { Valgrind 3.24 aborts in its DWARF reader on an FPC -gl binary. Symbols remain without -gl. }
          If MemoryCheck <> mcValgrind Then
            Command.Add('-gl');
          Command.Add('-Cr');
          Command.Add('-Co');
          Command.Add('-FU' + OutputDir);
          Command.Add('-FE' + OutputDir);
          AddUnitFlags(Command, UnitDirs);
          AddBuildFlags(Command);
          AddMemoryCheckFlags(Command);
          Command.Add(RepoFile('Tests/' + Tests[I] + '.lpr'));
          If RunCommand(Tests[I] + '-build', Command, BuildTimeout) And Not CompileOnly Then
            Begin
              { Valgrind 3.24 aborts in readelf on the debug sections of these binaries. }
              If MemoryCheck = mcValgrind Then
                If Not RunArgs('strip-debug-' + Tests[I], ['objcopy', '--strip-debug', OutputBinary(OutputDir, Tests[I])], 60) Then
                  Continue;
              RunTest(Tests[I], BuildTimeout);
            End;
        End;
      Command.Clear;
      Command.Add('fpc');
      Command.Add('-v0');
      Command.Add('-gl');
      Command.Add('-Cr');
      Command.Add('-Co');
      Command.Add('-FU' + OutputDir);
      Command.Add('-FE' + OutputDir);
      AddUnitFlags(Command, UnitDirs);
      AddBuildFlags(Command);
      Command.Add(RepoFile('Packages/LazAssistantTools.pas'));
      RunCommand('assistant-package-build', Command, 90);
      RunMonitorPackage;
      Command[Command.Count - 1] := RepoFile('Packages/LazRepositoryTools.pas');
      RunCommand('repository-package-build', Command, 90);
      If PackageCheck Then
        RunPackageCheck;
    Finally
      Command.Free;
      Tests.Free;
    End;
    Say('Logs: ' + OutputDir);
    Result := Failures.Count = 0;
  Finally
    UnitDirs.Free;
  End;
End;

Begin
  LibraryDirs := TStringList.Create;
  OnlyNames := TStringList.Create;
  Defines := TStringList.Create;
  Failures := TStringList.Create;
  Try
    Repo := RepositoryRoot;
    If Repo = '' Then
      FailUsage('Could not find the repository root. Start in the project directory.');
    ParseArguments;
    OutputDir := NewOutputDirectory(OutputDir);
    If Defines.Count = 0 Then
      Say('Build flags: (none)' + MemoryCheckText)
    Else
      Say('Build flags:' + BuildFlagsText + MemoryCheckText);
    If Not RunSuite Then
      Halt(1);
  Finally
    Failures.Free;
    Defines.Free;
    OnlyNames.Free;
    LibraryDirs.Free;
  End;
End.
