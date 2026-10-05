Unit AssistantCodexQualification;

{ Accept a release Codex CLI when its generated app-server schema still contains
  the fields this client uses. The result is cached by executable path and a
  bounded content identity. ChatGPT subscription access stays inside Codex; this
  unit does not call a metered API. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

/// True for an exact `codex-cli N.N.N` release line. Alpha, beta and other suffixes are rejected.
Function CodexVersionIsRelease(Const Line: String): Boolean;
/// A safe `codex-cli ...` line to show in an error, or empty when the text is not one.
Function CodexVersionReportLine(Const Line: String): String;
/// Read `codex --version` from stdout. Does not use the JSONL transport, which treats process exit as a protocol error.
Function ReadCodexVersion(Const Executable: String; Environment: TStrings; Out VersionLine, ErrorText: String): Boolean;
/// Release shape, then a cached or freshly generated schema check. Does not start a turn or sign-in.
Function QualifyCodexRuntime(Const Executable, VersionLine: String; Environment: TStrings; Out ErrorText: String): Boolean;
/// Drop cached qualification results for this host. The next check generates the schema again.
Procedure ClearCodexQualificationCache;

Implementation

Uses
  Process, fpjson, jsonparser, sha1, FileUtil, LazFileUtils{$IFDEF UNIX}, BaseUnix{$ENDIF};

Const
  SchemaGenerationTimeoutMs = 15000;
  { Head and tail sample. A 256 MiB cap rejected current ChatGPT extension builds.
    A full-file hash of those binaries stalled the account thread. }
  CodexIdentitySampleBytes = 1048576;

Type
  TSchemaField = Record
    RelativeName, FieldName: String;
  End;

Const
  RequiredSchemaFields: Array[0..33] Of TSchemaField = (
    (RelativeName: 'v2/LoginAccountParams.json'; FieldName: 'type'),
    (RelativeName: 'v2/LoginAccountResponse.json'; FieldName: 'type'),
    (RelativeName: 'v2/LoginAccountResponse.json'; FieldName: 'loginId'),
    (RelativeName: 'v2/LoginAccountResponse.json'; FieldName: 'authUrl'),
    (RelativeName: 'v2/GetAccountResponse.json'; FieldName: 'account'),
    (RelativeName: 'v2/GetAccountResponse.json'; FieldName: 'requiresOpenaiAuth'),
    (RelativeName: 'v2/ThreadStartParams.json'; FieldName: 'dynamicTools'),
    (RelativeName: 'v2/ThreadStartParams.json'; FieldName: 'modelProvider'),
    (RelativeName: 'v2/ThreadStartParams.json'; FieldName: 'permissions'),
    (RelativeName: 'v2/ThreadStartParams.json'; FieldName: 'approvalPolicy'),
    (RelativeName: 'v2/ThreadStartResponse.json'; FieldName: 'modelProvider'),
    (RelativeName: 'v2/ThreadStartResponse.json'; FieldName: 'sandbox'),
    (RelativeName: 'v2/ThreadStartResponse.json'; FieldName: 'approvalPolicy'),
    (RelativeName: 'v2/ThreadStartResponse.json'; FieldName: 'thread'),
    (RelativeName: 'v2/TurnStartParams.json'; FieldName: 'threadId'),
    (RelativeName: 'v2/TurnStartParams.json'; FieldName: 'input'),
    (RelativeName: 'v2/TurnStartParams.json'; FieldName: 'permissions'),
    (RelativeName: 'v2/TurnStartParams.json'; FieldName: 'summary'),
    (RelativeName: 'v2/TurnInterruptParams.json'; FieldName: 'threadId'),
    (RelativeName: 'v2/TurnInterruptParams.json'; FieldName: 'turnId'),
    (RelativeName: 'v2/TurnSteerParams.json'; FieldName: 'threadId'),
    (RelativeName: 'v2/TurnSteerParams.json'; FieldName: 'expectedTurnId'),
    (RelativeName: 'v2/TurnSteerParams.json'; FieldName: 'input'),
    (RelativeName: 'DynamicToolCallParams.json'; FieldName: 'threadId'),
    (RelativeName: 'DynamicToolCallParams.json'; FieldName: 'turnId'),
    (RelativeName: 'DynamicToolCallParams.json'; FieldName: 'callId'),
    (RelativeName: 'DynamicToolCallParams.json'; FieldName: 'tool'),
    (RelativeName: 'DynamicToolCallParams.json'; FieldName: 'arguments'),
    (RelativeName: 'DynamicToolCallResponse.json'; FieldName: 'contentItems'),
    (RelativeName: 'DynamicToolCallResponse.json'; FieldName: 'success'),
    (RelativeName: 'v2/AgentMessageDeltaNotification.json'; FieldName: 'threadId'),
    (RelativeName: 'v2/AgentMessageDeltaNotification.json'; FieldName: 'turnId'),
    (RelativeName: 'v2/AgentMessageDeltaNotification.json'; FieldName: 'itemId'),
    (RelativeName: 'v2/AgentMessageDeltaNotification.json'; FieldName: 'delta'));

Function CodexVersionIsRelease(Const Line: String): Boolean;
Var
  Rest: String;
  Index, Component, StartAt: Integer;
Begin
  Result := False;
  If Copy(Line, 1, 10) <> 'codex-cli ' Then Exit;
  Rest := Copy(Line, 11, MaxInt);
  Component := 0;
  Index := 1;
  While Component < 3 Do
    Begin
      If (Index > Length(Rest)) Or Not (Rest[Index] In ['0'..'9']) Then Exit;
      StartAt := Index;
      While (Index <= Length(Rest)) And (Rest[Index] In ['0'..'9']) Do Inc(Index);
      If (Index - StartAt > 1) And (Rest[StartAt] = '0') Then Exit;
      If Index - StartAt > 8 Then Exit;
      Inc(Component);
      If Component < 3 Then
        Begin
          If (Index > Length(Rest)) Or (Rest[Index] <> '.') Then Exit;
          Inc(Index);
        End;
    End;
  Result := Index > Length(Rest);
End;

Function CodexVersionReportLine(Const Line: String): String;
Var
  I: Integer;
Begin
  Result := Trim(Line);
  If (Length(Result) > 80) Or (Copy(Result, 1, 10) <> 'codex-cli ') Then
    Begin
      Result := '';
      Exit;
    End;
  For I := 1 To Length(Result) Do
    If Result[I] < ' ' Then
      Begin
        Result := '';
        Exit;
      End;
End;

Function CacheDirectory: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'codex-qualification';
End;

Function IsSymbolicLink(Const Path: String): Boolean;
{$IFDEF UNIX}
Var
  Info: Stat;
Begin
  FillChar(Info, SizeOf(Info), 0);
  Result := (FpLstat(PChar(Path), Info) = 0) And ((Info.st_mode And S_IFMT) = S_IFLNK);
End;
{$ELSE}
Begin
  Result := FileIsSymlink(Path);
End;
{$ENDIF}

Function IsCacheFileName(Const Name: String): Boolean;
Var
  I: Integer;
Begin
  Result := (Length(Name) = 45) And (Copy(Name, 41, 5) = '.json');
  If Not Result Then Exit;
  For I := 1 To 40 Do
    If Not (Name[I] In ['0'..'9', 'a'..'f']) Then Exit(False);
End;

Procedure ClearCodexQualificationCache;
Var
  Directory, Child: String;
  Info: TSearchRec;
Begin
  Directory := CacheDirectory;
  If (Not DirectoryExists(Directory)) Or IsSymbolicLink(Directory) Then Exit;
  If FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info) <> 0 Then Exit;
  Try
    Repeat
      If (Info.Name = '.') Or (Info.Name = '..') Or Not IsCacheFileName(Info.Name) Then Continue;
      Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
      If Not IsSymbolicLink(Child) Then DeleteFile(Child);
    Until FindNext(Info) <> 0;
  Finally
    FindClose(Info);
  End;
End;

Function ContentHash(Const Path: String; Out Hash, ErrorText: String): Boolean;
Var
  Stream: TFileStream;
  Context: TSHA1Context;
  Digest: TSHA1Digest;
  SizeValue, Remaining: Int64;
  SizeText: String;
  Function UpdateSample(Count: Int64): Boolean;
  Var
    Buffer: Array[0..65535] Of Byte;
    Got, Wanted: Integer;
  Begin
    Result := False;
    FillChar(Buffer, SizeOf(Buffer), 0);
    While Count > 0 Do
      Begin
        Wanted := SizeOf(Buffer);
        If Count < Wanted Then Wanted := Integer(Count);
        Got := Stream.Read(Buffer, Wanted);
        If Got <= 0 Then Exit;
        SHA1Update(Context, Buffer, Got);
        Dec(Count, Got);
      End;
    Result := True;
  End;
Begin
  Result := False;
  Hash := '';
  ErrorText := '';
  Try
    If Not FileIsExecutable(Path) Then
      Begin
        ErrorText := 'The Codex executable is missing or is not executable.';
        Exit;
      End;
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
    Try
      SizeValue := Stream.Size;
      If SizeValue < 0 Then
        Begin
          ErrorText := 'Cannot read the Codex executable.';
          Exit;
        End;
      SHA1Init(Context);
      SizeText := IntToStr(SizeValue) + #1;
      SHA1Update(Context, SizeText[1], Length(SizeText));
      Remaining := SizeValue;
      If Remaining > CodexIdentitySampleBytes Then Remaining := CodexIdentitySampleBytes;
      If Not UpdateSample(Remaining) Then
        Begin
          ErrorText := 'Cannot read the Codex executable.';
          Exit;
        End;
      If SizeValue > CodexIdentitySampleBytes Then
        Begin
          If Stream.Seek(SizeValue - CodexIdentitySampleBytes, soBeginning) < 0 Then
            Begin
              ErrorText := 'Cannot read the Codex executable.';
              Exit;
            End;
          SizeText := #2;
          SHA1Update(Context, SizeText[1], Length(SizeText));
          If Not UpdateSample(CodexIdentitySampleBytes) Then
            Begin
              ErrorText := 'Cannot read the Codex executable.';
              Exit;
            End;
        End;
      SHA1Final(Context, Digest);
    Finally
      Stream.Free;
    End;
    Hash := SHA1Print(Digest);
    Result := Hash <> '';
    If Not Result Then ErrorText := 'Cannot read the Codex executable.';
  Except
    On E: Exception Do ErrorText := 'Cannot read the Codex executable.';
  End;
End;

Function CacheFileName(Const Path, Hash: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(CacheDirectory) + SHA1Print(SHA1String(Path + #1 + Hash)) + '.json';
End;

Function CachedQualification(Const Path, Hash, VersionLine: String): Boolean;
Var
  Data: TJSONData;
  Root: TJSONObject;
  Lines: TStringList;
  FileName: String;
Begin
  Result := False;
  FileName := CacheFileName(Path, Hash);
  If (Not FileExists(FileName)) Or IsSymbolicLink(FileName) Then Exit;
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Try
      Lines.LoadFromFile(FileName);
      Data := GetJSON(Lines.Text);
      If Not (Data Is TJSONObject) Then Exit;
      Root := TJSONObject(Data);
      Result := Root.Get('qualified', False) And (Root.Get('sha1', '') = Hash) And
        (Root.Get('version', '') = VersionLine) And
        (CompareFilenames(Root.Get('path', ''), Path) = 0);
    Except
      Result := False;
    End;
  Finally
    Data.Free;
    Lines.Free;
  End;
End;

Procedure StoreQualification(Const Path, Hash, VersionLine: String);
Var
  Root: TJSONObject;
  Lines: TStringList;
  Directory, FileName, Temporary: String;
Begin
  Directory := CacheDirectory;
  If Not ForceDirectories(Directory) Then Exit;
  {$IFDEF UNIX}
  fpChmod(Directory, &700);
  {$ENDIF}
  If IsSymbolicLink(Directory) Then Exit;
  FileName := CacheFileName(Path, Hash);
  Temporary := FileName + '.tmp';
  Root := TJSONObject.Create;
  Lines := TStringList.Create;
  Try
    Root.Add('path', Path);
    Root.Add('sha1', Hash);
    Root.Add('version', VersionLine);
    Root.Add('qualified', True);
    Lines.Text := Root.AsJSON;
    Lines.SaveToFile(Temporary);
    {$IFDEF UNIX}
    fpChmod(Temporary, &600);
    {$ENDIF}
    If FileExists(FileName) And Not IsSymbolicLink(FileName) Then DeleteFile(FileName);
    If IsSymbolicLink(FileName) Or Not RenameFile(Temporary, FileName) Then DeleteFile(Temporary);
  Finally
    Lines.Free;
    Root.Free;
  End;
End;

Function RemoveTree(Const Directory: String): Boolean;
Var
  Info: TSearchRec;
  Child: String;
Begin
  Result := False;
  If (Directory = '') Or IsSymbolicLink(Directory) Or (Pos('laz-codex-schema-', Directory) = 0) Then Exit;
  If FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info) = 0 Then
    Try
      Repeat
        If (Info.Name = '.') Or (Info.Name = '..') Then Continue;
        Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
        If IsSymbolicLink(Child) Then
          Begin
            If Not DeleteFile(Child) Then Exit;
          End
        Else If (Info.Attr And faDirectory) <> 0 Then
          Begin
            If Not RemoveTree(Child) Then Exit;
          End
        Else If Not DeleteFile(Child) Then Exit;
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  Result := RemoveDir(Directory);
End;

Procedure CollectPropertyNames(Data: TJSONData; Names: TStringList);
Var
  Obj: TJSONObject;
  Props: TJSONData;
  I: Integer;
Begin
  If Data = Nil Then Exit;
  If Data Is TJSONObject Then
    Begin
      Obj := TJSONObject(Data);
      Props := Obj.Find('properties');
      If Props Is TJSONObject Then
        For I := 0 To TJSONObject(Props).Count - 1 Do
          Names.Add(TJSONObject(Props).Names[I]);
      For I := 0 To Obj.Count - 1 Do
        CollectPropertyNames(Obj.Items[I], Names);
    End
  Else If Data Is TJSONArray Then
    For I := 0 To TJSONArray(Data).Count - 1 Do
      CollectPropertyNames(TJSONArray(Data).Items[I], Names);
End;

Function SchemaFile(Const Root, RelativeName: String): String;
Var
  Wanted: String;
  Function Search(Const Directory: String): String;
  Var
    Info: TSearchRec;
    Child: String;
    Found: Integer;
  Begin
    Result := '';
    Found := FindFirst(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Info);
    If Found <> 0 Then Exit;
    Try
      Repeat
        If (Info.Name = '.') Or (Info.Name = '..') Then Continue;
        Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
        If IsSymbolicLink(Child) Then Continue;
        If (Info.Attr And faDirectory) <> 0 Then
          Begin
            Result := Search(Child);
            If Result <> '' Then Exit;
          End
        Else If Info.Name = Wanted Then
          Exit(Child);
      Until FindNext(Info) <> 0;
    Finally
      FindClose(Info);
    End;
  End;
Begin
  Result := IncludeTrailingPathDelimiter(Root) + RelativeName;
  If FileExists(Result) And Not IsSymbolicLink(Result) Then Exit;
  Wanted := ExtractFileName(RelativeName);
  Result := Search(Root);
End;

Function SchemaHasField(Const SchemaRoot, RelativeName, FieldName: String; Out ErrorText: String): Boolean;
Var
  FileName: String;
  Data: TJSONData;
  Lines: TStringList;
  Names: TStringList;
Begin
  Result := False;
  ErrorText := '';
  FileName := SchemaFile(SchemaRoot, RelativeName);
  If FileName = '' Then
    Begin
      ErrorText := 'Codex schema is missing ' + RelativeName + '.';
      Exit;
    End;
  Lines := TStringList.Create;
  Names := TStringList.Create;
  Data := Nil;
  Try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    Try
      Lines.LoadFromFile(FileName);
      Data := GetJSON(Lines.Text);
    Except
      ErrorText := 'Codex schema file ' + RelativeName + ' is not valid JSON.';
      Exit;
    End;
    CollectPropertyNames(Data, Names);
    Result := Names.IndexOf(FieldName) >= 0;
    If Not Result Then ErrorText := 'Codex schema is missing ' + FieldName + ' in ' + RelativeName + '.';
  Finally
    Data.Free;
    Names.Free;
    Lines.Free;
  End;
End;

Procedure SchemaEnvironment(Source, Dest: TStrings);
Var
  I, SplitAt: Integer;
  Line, Name: String;
Begin
  Dest.Clear;
  If Not Assigned(Source) Then Exit;
  For I := 0 To Source.Count - 1 Do
    Begin
      Line := Source[I];
      SplitAt := Pos('=', Line);
      If SplitAt <= 1 Then Continue;
      Name := Copy(Line, 1, SplitAt - 1);
      { Schema generation must not use the managed profile or a metered credential. }
      If (Name = 'CODEX_HOME') Or (Name = 'OPENAI_API_KEY') Or (Name = 'CODEX_API_KEY') Or
        (Name = 'OPENAI_BASE_URL') Then Continue;
      Dest.Add(Line);
    End;
End;

Function GenerateSchema(Const Executable, SchemaRoot: String; Environment: TStrings; Out ErrorText: String): Boolean;
Var
  Proc: TProcess;
  Buffer: Array[0..4095] Of Byte;
  Deadline: QWord;
  ExitCode: Integer;
  Filtered: TStringList;
Begin
  Result := False;
  ErrorText := '';
  Proc := TProcess.Create(Nil);
  Filtered := TStringList.Create;
  Try
    Proc.Executable := Executable;
    Proc.CurrentDirectory := GetTempDir;
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.Parameters.Add('app-server');
    Proc.Parameters.Add('generate-json-schema');
    Proc.Parameters.Add('--experimental');
    Proc.Parameters.Add('--out');
    Proc.Parameters.Add(SchemaRoot);
    If Assigned(Environment) Then
      Begin
        SchemaEnvironment(Environment, Filtered);
        Proc.Environment.Assign(Filtered);
      End;
    Try
      Proc.Execute;
    Except
      ErrorText := 'Codex schema generation failed. A release build was found, but its app-server schema could not be checked.';
      Exit;
    End;
    Deadline := GetTickCount64 + SchemaGenerationTimeoutMs;
    FillChar(Buffer, SizeOf(Buffer), 0);
    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Or (Proc.Stderr.NumBytesAvailable > 0) Do
      Begin
        While Proc.Output.NumBytesAvailable > 0 Do
          If Proc.Output.Read(Buffer, SizeOf(Buffer)) <= 0 Then Break;
        While Proc.Stderr.NumBytesAvailable > 0 Do
          If Proc.Stderr.Read(Buffer, SizeOf(Buffer)) <= 0 Then Break;
        If GetTickCount64 >= Deadline Then
          Begin
            Proc.Terminate(1);
            Proc.WaitOnExit(2000);
            ErrorText := 'Codex schema generation timed out.';
            Exit;
          End;
        If Proc.Running Then Sleep(5);
      End;
    ExitCode := Proc.ExitStatus;
    Result := ExitCode = 0;
    If Not Result Then
      ErrorText := 'Codex schema generation failed. A release build was found, but its app-server schema could not be checked.';
  Finally
    Filtered.Free;
    Proc.Free;
  End;
End;

Function QualifyGeneratedSchema(Const SchemaRoot: String; Out ErrorText: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  For I := Low(RequiredSchemaFields) To High(RequiredSchemaFields) Do
    If Not SchemaHasField(SchemaRoot, RequiredSchemaFields[I].RelativeName, RequiredSchemaFields[I].FieldName, ErrorText) Then
      Exit;
  Result := True;
End;

Function QualifyCodexRuntime(Const Executable, VersionLine: String; Environment: TStrings; Out ErrorText: String): Boolean;
Var
  Path, Hash, SchemaRoot: String;
Begin
  Result := False;
  ErrorText := '';
  If Not CodexVersionIsRelease(VersionLine) Then
    Begin
      If VersionLine = '' Then
        ErrorText := 'Codex did not report a release version. Use a release codex-cli build, not an alpha or prerelease.'
      Else
        ErrorText := 'Codex is not a release build (found ' + VersionLine + '). Alpha and prerelease builds are not used.';
      Exit;
    End;
  Path := ExpandFileName(Executable);
  If Not ContentHash(Path, Hash, ErrorText) Then Exit;
  If CachedQualification(Path, Hash, VersionLine) Then Exit(True);
  SchemaRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-codex-schema-' + Hash;
  If DirectoryExists(SchemaRoot) And Not RemoveTree(SchemaRoot) Then
    Begin
      ErrorText := 'Cannot prepare a directory for the Codex schema check.';
      Exit;
    End;
  If Not ForceDirectories(SchemaRoot) Then
    Begin
      ErrorText := 'Cannot prepare a directory for the Codex schema check.';
      Exit;
    End;
  {$IFDEF UNIX}
  fpChmod(SchemaRoot, &700);
  {$ENDIF}
  Try
    { A release build whose schema tool cannot be run is still allowed. The live
      handshake remains the fail-closed gate for account type and sandbox. A schema
      that is produced and is missing a required field is still rejected. }
    If Not GenerateSchema(Path, SchemaRoot, Environment, ErrorText) Then
      Begin
        ErrorText := '';
        Result := True;
        Exit;
      End;
    If Not QualifyGeneratedSchema(SchemaRoot, ErrorText) Then Exit;
    StoreQualification(Path, Hash, VersionLine);
    Result := True;
  Finally
    RemoveTree(SchemaRoot);
  End;
End;

Function ReadCodexVersion(Const Executable: String; Environment: TStrings; Out VersionLine, ErrorText: String): Boolean;
Var
  Proc: TProcess;
  Buffer: Array[0..1023] Of Byte;
  Output: String;
  Count, SplitAt: Integer;
  Deadline: QWord;
  Line: String;
Begin
  Result := False;
  VersionLine := '';
  ErrorText := '';
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'The Codex executable is missing or is not executable.';
      Exit;
    End;
  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := Executable;
    Proc.CurrentDirectory := GetTempDir;
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.Parameters.Add('--version');
    If Assigned(Environment) Then Proc.Environment.Assign(Environment);
    Try
      Proc.Execute;
    Except
      ErrorText := 'Unable to start the Codex runtime.';
      Exit;
    End;
    Deadline := GetTickCount64 + 15000;
    Output := '';
    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Or (Proc.Stderr.NumBytesAvailable > 0) Do
      Begin
        While Proc.Output.NumBytesAvailable > 0 Do
          Begin
            Count := Proc.Output.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then Break;
            If Length(Output) < 4000 Then
              Begin
                SetString(Line, PAnsiChar(@Buffer[0]), Count);
                Output := Output + Line;
              End;
          End;
        While Proc.Stderr.NumBytesAvailable > 0 Do
          Begin
            Count := Proc.Stderr.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then Break;
            If Length(Output) < 4000 Then
              Begin
                SetString(Line, PAnsiChar(@Buffer[0]), Count);
                Output := Output + Line;
              End;
          End;
        If GetTickCount64 >= Deadline Then
          Begin
            Proc.Terminate(1);
            ErrorText := 'Codex did not report a version.';
            Exit;
          End;
        If Proc.Running Then Sleep(5);
      End;
    While Output <> '' Do
      Begin
        SplitAt := Pos(#10, Output);
        If SplitAt = 0 Then
          Begin
            Line := Output;
            Output := '';
          End
        Else
          Begin
            Line := Copy(Output, 1, SplitAt - 1);
            Delete(Output, 1, SplitAt);
          End;
        Line := CodexVersionReportLine(Trim(Line));
        If Line <> '' Then VersionLine := Line;
      End;
    Result := True;
    If VersionLine = '' Then ErrorText := 'Codex did not report a release version.';
  Finally
    Proc.Free;
  End;
End;

End.
