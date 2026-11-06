#!/usr/bin/env instantfpc
Program RunAssistantTests;

{ Repeatable assistant regression runner (c) 2026 Michell Computing.

  Invoke with InstantFPC. Python is not used:
    instantfpc Tests/RunAssistantTests.pas --lazarus-root <Lazarus checkout>
  Compiled test programs are written to a temporary directory, not beside these sources. }

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
  GuiTestNames: Array[0..18] Of String = (
    'PluginFormLifetimeTest', 'SpellMemoInputTest', 'AssistantSubagentsTest', 'AssistantHarnessTest',
    'AssistantEditorEditsTest', 'AssistantBuildWorkspaceTest', 'AssistantBuildDependenciesTest',
    'AssistantChangeSetsTest', 'AssistantWorkspaceTest', 'AssistantCodeToolsTest', 'AssistantSettingsTest',
    'AssistantProviderTest', 'AssistantReconnectTest', 'MarkdownLayoutTest', 'AssistantTraceViewTest',
    'AssistantConversationSurfaceTest', 'AssistantMarkdownAsyncTest', 'AssistantConversationStressTest',
    'AssistantMonitorFormLoadTest');

Var
  Repo, LazarusRoot, OutputDir: String;
  LibraryDirs, OnlyNames, Failures: TStringList;
  Gui, PackageCheck, CompileOnly, Independent: Boolean;

Procedure FailUsage(Const Message: String);
Begin
  WriteLn(StdErr, Message);
  WriteLn(StdErr, 'instantfpc Tests/RunAssistantTests.pas --lazarus-root <Lazarus checkout> [--only ProgramName]');
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

Function RunCommand(Const LabelName: String; Command: TStrings; TimeoutSec: Integer): Boolean;
Var
  Proc: TProcess;
  I, BytesRead: Integer;
  Exe, LogPath, OutputText, Tail: String;
  Mem: TMemoryStream;
  Buf: Array[0..8191] Of Byte;
  StartTick: QWord;
  TimedOut: Boolean;
Begin
  Result := False;
  OutputText := '';
  TimedOut := False;
  Exe := ResolveExecutable(Command[0]);
  LogPath := IncludeTrailingPathDelimiter(OutputDir) + LabelName + '.log';
  If Exe = '' Then
    Begin
      WriteTextFile(LogPath, 'Executable not found: ' + Command[0] + LineEnding);
      Say('FAIL ' + LabelName + ': executable not found: ' + Command[0]);
      Failures.Add(LabelName);
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
    Try
      Proc.Execute;
      StartTick := GetTickCount64;
      While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
        Begin
          If GetTickCount64 - StartTick >= QWord(TimeoutSec) * 1000 Then
            Begin
              TimedOut := True;
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
      SetLength(OutputText, Mem.Size);
      If Mem.Size > 0 Then
        Move(Mem.Memory^, OutputText[1], Mem.Size);
      If TimedOut Then
        OutputText := OutputText + LineEnding + 'Timed out.' + LineEnding;
      WriteTextFile(LogPath, OutputText);
      If TimedOut Or (Proc.ExitStatus <> 0) Then
        Begin
          Say('FAIL ' + LabelName + ': see ' + LogPath);
          Tail := OutputText;
          If Length(Tail) > 4000 Then
            Tail := Copy(Tail, Length(Tail) - 3999, 4000);
          If Tail <> '' Then
            Say(Tail);
          Failures.Add(LabelName);
          Exit;
        End;
      Say('PASS ' + LabelName);
      Result := True;
    Except
      On E: Exception Do
        Begin
          WriteTextFile(LogPath, E.Message + LineEnding);
          Say('FAIL ' + LabelName + ': ' + E.Message);
          Failures.Add(LabelName);
        End;
    End;
  Finally
    Mem.Free;
    Proc.Free;
  End;
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

Function NewOutputDirectory(Const Requested: String): String;
Var
  I: Integer;
Begin
  If Requested <> '' Then
    Begin
      Result := ExpandFileName(Requested);
      If Not ForceDirectories(Result) Then
        FailUsage('Could not create output directory: ' + Result);
      Exit;
    End;
  For I := 0 To 100 Do
    Begin
      Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-assistant-tests-' + IntToStr(GetProcessID) + '-' + IntToStr(I);
      If Not DirectoryExists(Result) And CreateDir(Result) Then
        Exit;
    End;
  FailUsage('Could not create a temporary output directory.');
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
      Else
        FailUsage('Unknown argument: ' + Arg);
      Inc(I);
    End;
  If LazarusRoot = '' Then
    FailUsage('--lazarus-root is required.');
  If Not DirectoryExists(LazarusRoot) Then
    FailUsage('Lazarus root was not found: ' + LazarusRoot);
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
  Opt := '-FU' + ExcludeTrailingPathDelimiter(PackageOut) + ' -FE' + ExcludeTrailingPathDelimiter(PackageOut);
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
          Command.Add('-gl');
          Command.Add('-Cr');
          Command.Add('-Co');
          Command.Add('-FU' + OutputDir);
          Command.Add('-FE' + OutputDir);
          AddUnitFlags(Command, UnitDirs);
          Command.Add(RepoFile('Tests/' + Tests[I] + '.lpr'));
          If RunCommand(Tests[I] + '-build', Command, BuildTimeout) And Not CompileOnly Then
            RunArgs(Tests[I], [OutputBinary(OutputDir, Tests[I])], BuildTimeout);
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
  Failures := TStringList.Create;
  Try
    Repo := RepositoryRoot;
    If Repo = '' Then
      FailUsage('Could not find the repository root. Start in the project directory.');
    ParseArguments;
    OutputDir := NewOutputDirectory(OutputDir);
    If Not RunSuite Then
      Halt(1);
  Finally
    Failures.Free;
    OnlyNames.Free;
    LibraryDirs.Free;
  End;
End.
