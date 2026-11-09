Unit AssistantTestSettings;

{ User-owned per-target test commands in the target config.json. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TAssistantTestSettings = Class
  Private
    FRoot, FProject: String;
  Public
    Enabled: Boolean;
    Executable: String;
    Arguments: TStringList;
    TimeoutSeconds, MinimumTests: Integer;
    ReportFormat: String;
    Constructor Create(Const ConfigRoot, ProjectFile: String);
    Destructor Destroy; Override;
    Procedure Load;
    Procedure Save;
    Function Validate(Out ErrorText: String): Boolean;
    Function CommandJSON: String;
    Function ResolvedExecutable: String;
    Function WorkingDirectory: String;
    Function StorageFilename: String;
  End;

{ Append runner options and a private --output-dir to a test command. OptionsJSON is an object with only (test program
  names, each an existing Tests/<name>.lpr), memory_check ('none', 'heaptrc' or 'valgrind', which needs a non-empty
  only) and defines (at most 8 names, each passed as --define). With no options CommandJSON comes back unchanged; any
  option needs the repository runner Tests/RunAssistantTests.pas. The output directory names the build, the memory
  check, the sorted defines and the tests, so a run never reuses units compiled with other flags. }
Function ApplyTestOptions(Const CommandJSON, ProjectRoot, OptionsJSON: String; Out NewCommand, ErrorText: String): Boolean;

Implementation

Uses
  fpjson, jsonparser, LazFileUtils, AssistantProjectPaths;

Const
  MaxTestOnlyNames = 32;
  { The runner's MaxDefines. }
  MaxTestDefines = 8;

Function ValidTestProgramName(Const Name: String): Boolean;
Var
  I: Integer;
Begin
  Result := (Name <> '') And (Name[1] In ['A'..'Z', 'a'..'z']);
  If Not Result Then Exit;
  For I := 2 To Length(Name) Do
    If Not (Name[I] In ['A'..'Z', 'a'..'z', '0'..'9']) Then Exit(False);
End;

Function SafeDirToken(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To Length(Value) Do
    If Value[I] In ['A'..'Z', 'a'..'z', '0'..'9'] Then
      Result := Result + Value[I];
  If Result = '' Then
    Result := 'run';
End;

{ One path component holds 255 bytes. A token for many --only names is cut and given an FNV-1a hash of the whole,
  so it stays one name per selection. }
Function ShortDirToken(Const Token: String): String;
Const
  KeptChars = 80;
Var
  Hash: LongWord;
  I: Integer;
Begin
  If Length(Token) <= 2 * KeptChars Then
    Exit(Token);
  Hash := 2166136261;
  For I := 1 To Length(Token) Do
    Hash := LongWord((Hash Xor Ord(Token[I])) * QWord(16777619));
  Result := Copy(Token, 1, KeptChars) + '-' + IntToHex(Hash, 8);
End;

Function IsRepositoryRunner(Const Executable, ProjectRoot: String; Arguments: TJSONArray): Boolean;
Var
  I: Integer;
  Runner, Value: String;
Begin
  Runner := ExpandFileName(IncludeTrailingPathDelimiter(ProjectRoot) + 'Tests' + PathDelim + 'RunAssistantTests.pas');
  Result := CompareFilenames(ExpandFileName(Executable), Runner) = 0;
  If Result Or Not Assigned(Arguments) Then Exit;
  For I := 0 To Arguments.Count - 1 Do
    Begin
      If Arguments.Items[I].JSONType <> jtString Then Continue;
      Value := StringReplace(Arguments.Items[I].AsString, '\', '/', [rfReplaceAll]);
      If (Value = 'Tests/RunAssistantTests.pas') Or
        (CompareFilenames(ExpandFileName(Arguments.Items[I].AsString), Runner) = 0) Then
          Exit(True);
    End;
End;

{ The name rule and limit of the runner's --define. }
Function ValidDefineName(Const Name: String): Boolean;
Var
  I: Integer;
Begin
  Result := (Name <> '') And (Name[1] In ['A'..'Z', 'a'..'z', '_']);
  If Not Result Then Exit;
  For I := 2 To Length(Name) Do
    If Not (Name[I] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Then Exit(False);
End;

{ Read and check OptionsJSON. Only keeps the given order; Defines is sorted, and like the runner it drops repeats
  without regard to case before counting them against the limit. }
Function ReadTestOptions(Const OptionsJSON: String; Only, Defines: TStringList; Out MemoryCheck, ErrorText: String): Boolean;
Var
  Data, Node: TJSONData;
  Options: TJSONObject;
  I: Integer;
  Name: String;
Begin
  Result := False;
  MemoryCheck := 'none';
  ErrorText := '';
  If Trim(OptionsJSON) = '' Then Exit(True);
  Try
    Data := GetJSON(OptionsJSON);
  Except
    ErrorText := 'Test options must be a JSON object.';
    Exit;
  End;
  Try
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Test options must be a JSON object.';
        Exit;
      End;
    Options := TJSONObject(Data);
    For I := 0 To Options.Count - 1 Do
      If (Options.Names[I] <> 'only') And (Options.Names[I] <> 'memory_check') And (Options.Names[I] <> 'defines') Then
        Begin
          ErrorText := 'Unknown test option: ' + Options.Names[I];
          Exit;
        End;
    Node := Options.Find('only');
    If Assigned(Node) Then
      Begin
        If Not (Node Is TJSONArray) Then
          Begin
            ErrorText := 'only must be a list of test program names.';
            Exit;
          End;
        If Node.Count > MaxTestOnlyNames Then
          Begin
            ErrorText := 'only accepts at most ' + IntToStr(MaxTestOnlyNames) + ' test program names.';
            Exit;
          End;
        For I := 0 To Node.Count - 1 Do
          Begin
            If Node.Items[I].JSONType <> jtString Then
              Begin
                ErrorText := 'Each only name must be a string.';
                Exit;
              End;
            Name := Node.Items[I].AsString;
            If Not ValidTestProgramName(Name) Then
              Begin
                ErrorText := 'Test name must match ^[A-Za-z][A-Za-z0-9]*$: ' + Name;
                Exit;
              End;
            Only.Add(Name);
          End;
      End;
    Node := Options.Find('memory_check');
    If Assigned(Node) Then
      Begin
        If (Node.JSONType <> jtString) Or
          Not ((Node.AsString = 'none') Or (Node.AsString = 'heaptrc') Or (Node.AsString = 'valgrind')) Then
            Begin
              ErrorText := 'memory_check must be "none", "heaptrc" or "valgrind".';
              Exit;
            End;
        MemoryCheck := Node.AsString;
      End;
    Node := Options.Find('defines');
    If Assigned(Node) Then
      Begin
        If Not (Node Is TJSONArray) Then
          Begin
            ErrorText := 'defines must be a list of define names.';
            Exit;
          End;
        For I := 0 To Node.Count - 1 Do
          Begin
            If Node.Items[I].JSONType <> jtString Then
              Begin
                ErrorText := 'Each defines name must be a string.';
                Exit;
              End;
            Name := Node.Items[I].AsString;
            If Not ValidDefineName(Name) Then
              Begin
                ErrorText := 'Define name must match ^[A-Za-z_][A-Za-z0-9_]*$: ' + Name;
                Exit;
              End;
            If Defines.IndexOf(Name) < 0 Then
              Begin
                If Defines.Count >= MaxTestDefines Then
                  Begin
                    ErrorText := 'defines accepts at most ' + IntToStr(MaxTestDefines) + ' names.';
                    Exit;
                  End;
                Defines.Add(Name);
              End;
          End;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function ApplyTestOptions(Const CommandJSON, ProjectRoot, OptionsJSON: String; Out NewCommand, ErrorText: String): Boolean;
Var
  Data, Args: TJSONData;
  Only, Defines: TStringList;
  I: Integer;
  MemoryCheck, OptionName, TestFile, OutputDir, Token: String;
Begin
  Result := False;
  NewCommand := '';
  ErrorText := '';
  Data := Nil;
  Only := TStringList.Create;
  Defines := TStringList.Create;
  Try
    Defines.Sorted := True;
    Defines.CaseSensitive := False;
    If Not ReadTestOptions(OptionsJSON, Only, Defines, MemoryCheck, ErrorText) Then Exit;
    If (Only.Count = 0) And (MemoryCheck = 'none') And (Defines.Count = 0) Then
      Begin
        NewCommand := CommandJSON;
        Exit(True);
      End;
    If (MemoryCheck <> 'none') And (Only.Count = 0) Then
      Begin
        ErrorText := 'memory_check ' + MemoryCheck + ' needs at least one only name.';
        Exit;
      End;
    { Name the option the caller gave in the errors below; only comes first because it is the usual one. }
    If Only.Count > 0 Then
      OptionName := 'only'
    Else If MemoryCheck <> 'none' Then
      OptionName := 'memory_check'
    Else
      OptionName := 'defines';
    If Trim(ProjectRoot) = '' Then
      Begin
        ErrorText := 'The project root is required to apply ' + OptionName + '.';
        Exit;
      End;
    For I := 0 To Only.Count - 1 Do
      Begin
        TestFile := IncludeTrailingPathDelimiter(ProjectRoot) + 'Tests' + PathDelim + Only[I] + '.lpr';
        If Not FileExistsUTF8(TestFile) Then
          Begin
            ErrorText := 'Test program was not found: Tests/' + Only[I] + '.lpr';
            Exit;
          End;
      End;
    Try
      Data := GetJSON(CommandJSON);
    Except
      ErrorText := 'Test command is not valid JSON.';
      Exit;
    End;
    If Not (Data Is TJSONObject) Or Not (TJSONObject(Data).Find('arguments') Is TJSONArray) Then
      Begin
        ErrorText := 'Test command has no argument list.';
        Exit;
      End;
    Args := TJSONObject(Data).Find('arguments');
    If Not IsRepositoryRunner(TJSONObject(Data).Get('executable', ''), ProjectRoot, TJSONArray(Args)) Then
      Begin
        ErrorText := OptionName + ' applies only when the configured command is Tests/RunAssistantTests.pas.';
        Exit;
      End;
    { FPC does not recompile a unit when only the defines or debug flags change, so every distinct set of flags needs
      its own output directory. }
    Token := SafeDirToken(TJSONObject(Data).Get('build_job_id', ''));
    If MemoryCheck <> 'none' Then
      Token := Token + '-' + MemoryCheck;
    For I := 0 To Defines.Count - 1 Do
      Token := Token + '-d' + Defines[I];
    For I := 0 To Only.Count - 1 Do
      Token := Token + '-' + Only[I];
    OutputDir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-assistant-tests-' + ShortDirToken(Token);
    If Not ForceDirectories(OutputDir) Then
      Begin
        ErrorText := 'Could not create a temporary test output directory.';
        Exit;
      End;
    For I := 0 To Only.Count - 1 Do
      Begin
        TJSONArray(Args).Add('--only');
        TJSONArray(Args).Add(Only[I]);
      End;
    For I := 0 To Defines.Count - 1 Do
      Begin
        TJSONArray(Args).Add('--define');
        TJSONArray(Args).Add(Defines[I]);
      End;
    If MemoryCheck <> 'none' Then
      TJSONArray(Args).Add('--' + MemoryCheck);
    TJSONArray(Args).Add('--output-dir');
    TJSONArray(Args).Add(ExcludeTrailingPathDelimiter(OutputDir));
    NewCommand := Data.AsJSON;
    Result := True;
  Finally
    Data.Free;
    Only.Free;
    Defines.Free;
  End;
End;

Constructor TAssistantTestSettings.Create(Const ConfigRoot, ProjectFile: String);
Begin
  Inherited Create;
  FRoot := ConfigRoot;
  FProject := ProjectFile;
  If FProject <> '' Then FProject := ExpandFileName(FProject);
  Arguments := TStringList.Create;
  TimeoutSeconds := 600;
  MinimumTests := 1;
  ReportFormat := 'exit-code';
End;

Destructor TAssistantTestSettings.Destroy;
Begin
  Arguments.Free;
  Inherited Destroy;
End;

Function TAssistantTestSettings.StorageFilename: String;
Begin
  Result := '';
  If Trim(FRoot) = '' Then
    Exit;
  Result := IncludeTrailingPathDelimiter(FRoot) + AssistantTargetConfigFileName;
End;

Function TAssistantTestSettings.WorkingDirectory: String;
Begin
  { A folder target's manifest is the folder itself, with no trailing delimiter. ExtractFilePath would give its
    parent, so the command would start one level up and a relative executable would resolve there. }
  If (FProject <> '') And DirectoryExists(FProject) Then
    Result := IncludeTrailingPathDelimiter(FProject)
  Else
    Result := ExtractFilePath(FProject);
End;

Function TAssistantTestSettings.ResolvedExecutable: String;
Begin
  Result := Executable;
  If (Result <> '') And Not (Result[1] = PathDelim) Then Result := WorkingDirectory + Result;
  If Result <> '' Then Result := ExpandFileName(Result);
End;

Procedure TAssistantTestSettings.Load;
Var
  Document, Tests: TJSONObject;
  Node: TJSONData;
  I: Integer;
Begin
  Enabled := False;
  Executable := '';
  TimeoutSeconds := 600;
  MinimumTests := 1;
  ReportFormat := 'exit-code';
  Arguments.Clear;
  If (FProject = '') Or (FRoot = '') Then
    Exit;
  Document := LoadTargetConfig(FRoot);
  Try
    If Not (Document.Find('tests') Is TJSONObject) Then
      Exit;
    Tests := TJSONObject(Document.Find('tests'));
    Executable := Tests.Get('executable', '');
    TimeoutSeconds := Tests.Get('timeout_seconds', 600);
    ReportFormat := Tests.Get('report_format', 'exit-code');
    MinimumTests := Tests.Get('minimum_tests', 1);
    Node := Tests.Find('arguments');
    If (Node Is TJSONArray) And (TJSONArray(Node).Count <= 128) Then
      For I := 0 To TJSONArray(Node).Count - 1 Do
        Begin
          If TJSONArray(Node).Items[I].JSONType <> jtString Then
            Exit;
          Arguments.Add(TJSONArray(Node).Items[I].AsString);
        End;
    Enabled := Tests.Get('enabled', False);
  Finally
    Document.Free;
  End;
End;

Function TAssistantTestSettings.Validate(Out ErrorText: String): Boolean;
Var
  I, Bytes: Integer;
Begin
  Result := False;
  ErrorText := '';
  If FProject = '' Then
    Begin
      ErrorText := 'Select a saved project or package before configuring tests.';
      Exit;
    End;
  If Not Enabled Then Exit(True);
  If Not ((ReportFormat = 'exit-code') Or (ReportFormat = 'fpcunit-xml')) Or (MinimumTests < 1) Or (MinimumTests > 1000000) Then
    Begin
      ErrorText := 'Choose a supported test report and a minimum count from 1 to 1000000.';
      Exit;
    End;
  If (Trim(Executable) = '') Or (Length(Executable) > 4096) Or (Pos(#0, Executable) > 0) Or
    (Pos(#10, Executable) > 0) Or (Pos(#13, Executable) > 0) Then
      Begin
        ErrorText := 'Choose a test executable path without control characters.';
        Exit;
      End;
  If (TimeoutSeconds < 1) Or (TimeoutSeconds > 3600) Then
    Begin
      ErrorText := 'Test timeout must be 1–3600 seconds.';
      Exit;
    End;
  If Arguments.Count > 128 Then
    Begin
      ErrorText := 'At most 128 test arguments are supported.';
      Exit;
    End;
  Bytes := 0;
  For I := 0 To Arguments.Count - 1 Do
    Begin
      If Arguments[I] = '' Then
        Begin
          ErrorText := 'Remove blank argument lines; this process launcher cannot preserve empty arguments.';
          Exit;
        End;
      Inc(Bytes, Length(Arguments[I]));
      If (Pos(#0, Arguments[I]) > 0) Or (Pos(#10, Arguments[I]) > 0) Or (Pos(#13, Arguments[I]) > 0) Or (Bytes > 32768) Then
        Begin
          ErrorText := 'Test arguments must fit 32 KiB and contain no line breaks or NUL bytes.';
          Exit;
        End;
    End;
  Result := True;
End;

Procedure TAssistantTestSettings.Save;
Var
  Document, Tests: TJSONObject;
  Args: TJSONArray;
  I: Integer;
  Note: String;
Begin
  If FRoot = '' Then
    Exit;
  If Not Validate(Note) Then
    Raise Exception.Create(Note);
  Document := LoadTargetConfig(FRoot);
  Try
    If Assigned(Document.Find('tests')) Then
      Document.Delete('tests');
    Tests := TJSONObject.Create;
    Document.Add('tests', Tests);
    Tests.Add('enabled', Enabled);
    Tests.Add('executable', Executable);
    Tests.Add('timeout_seconds', TimeoutSeconds);
    Tests.Add('report_format', ReportFormat);
    Tests.Add('minimum_tests', MinimumTests);
    Args := TJSONArray.Create;
    Tests.Add('arguments', Args);
    For I := 0 To Arguments.Count - 1 Do
      Args.Add(Arguments[I]);
    If Not SaveTargetConfig(FRoot, Document, Note) Then
      Raise Exception.Create(Note);
  Finally
    Document.Free;
  End;
End;

Function TAssistantTestSettings.CommandJSON: String;
Var
  Root: TJSONObject;
  Args: TJSONArray;
  I: Integer;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('enabled', Enabled);
    Root.Add('executable', ResolvedExecutable);
    Root.Add('workingDirectory', WorkingDirectory);
    Root.Add('reportFormat', ReportFormat);
    Root.Add('minimumTests', MinimumTests);
    Root.Add('timeoutSeconds', TimeoutSeconds);
    Args := TJSONArray.Create;
    Root.Add('arguments', Args);
    For I := 0 To Arguments.Count - 1 Do Args.Add(Arguments[I]);
    Result := Root.AsJSON;
  Finally
    Root.Free;
  End;
End;
End.
