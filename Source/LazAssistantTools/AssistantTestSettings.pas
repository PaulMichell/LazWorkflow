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

{ Append --only pairs and a private --output-dir when OnlyJSON names tests. An empty list leaves CommandJSON unchanged.
  Only the repository runner Tests/RunAssistantTests.pas accepts names, and each name must be an existing Tests/<name>.lpr. }
Function ApplyTestOnly(Const CommandJSON, ProjectRoot, OnlyJSON: String; Out NewCommand, ErrorText: String): Boolean;

Implementation

Uses
  fpjson, jsonparser, LazFileUtils, AssistantProjectPaths;

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

Function ApplyTestOnly(Const CommandJSON, ProjectRoot, OnlyJSON: String; Out NewCommand, ErrorText: String): Boolean;
Var
  Data, OnlyData, Args: TJSONData;
  Only: TJSONArray;
  I: Integer;
  Name, TestFile, OutputDir, Token: String;
Begin
  Result := False;
  NewCommand := '';
  ErrorText := '';
  If (Trim(OnlyJSON) = '') Or (Trim(OnlyJSON) = '[]') Then
    Begin
      NewCommand := CommandJSON;
      Exit(True);
    End;
  OnlyData := Nil;
  Data := Nil;
  Try
    Try
      OnlyData := GetJSON(OnlyJSON);
    Except
      ErrorText := 'only must be a list of test program names.';
      Exit;
    End;
    If Not (OnlyData Is TJSONArray) Then
      Begin
        ErrorText := 'only must be a list of test program names.';
        Exit;
      End;
    Only := TJSONArray(OnlyData);
    If Only.Count = 0 Then
      Begin
        NewCommand := CommandJSON;
        Exit(True);
      End;
    If Only.Count > 32 Then
      Begin
        ErrorText := 'only accepts at most 32 test program names.';
        Exit;
      End;
    If Trim(ProjectRoot) = '' Then
      Begin
        ErrorText := 'The project root is required to select named tests.';
        Exit;
      End;
    For I := 0 To Only.Count - 1 Do
      Begin
        If Only.Items[I].JSONType <> jtString Then
          Begin
            ErrorText := 'Each only name must be a string.';
            Exit;
          End;
        Name := Only.Items[I].AsString;
        If Not ValidTestProgramName(Name) Then
          Begin
            ErrorText := 'Test name must match ^[A-Za-z][A-Za-z0-9]*$: ' + Name;
            Exit;
          End;
        TestFile := IncludeTrailingPathDelimiter(ProjectRoot) + 'Tests' + PathDelim + Name + '.lpr';
        If Not FileExistsUTF8(TestFile) Then
          Begin
            ErrorText := 'Test program was not found: Tests/' + Name + '.lpr';
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
        ErrorText := 'only applies only when the configured command is Tests/RunAssistantTests.pas.';
        Exit;
      End;
    Token := SafeDirToken(TJSONObject(Data).Get('build_job_id', ''));
    For I := 0 To Only.Count - 1 Do
      Token := Token + '-' + Only.Items[I].AsString;
    OutputDir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-assistant-tests-' + Token;
    If Not ForceDirectories(OutputDir) Then
      Begin
        ErrorText := 'Could not create a temporary test output directory.';
        Exit;
      End;
    For I := 0 To Only.Count - 1 Do
      Begin
        TJSONArray(Args).Add('--only');
        TJSONArray(Args).Add(Only.Items[I].AsString);
      End;
    TJSONArray(Args).Add('--output-dir');
    TJSONArray(Args).Add(ExcludeTrailingPathDelimiter(OutputDir));
    NewCommand := Data.AsJSON;
    Result := True;
  Finally
    OnlyData.Free;
    Data.Free;
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
