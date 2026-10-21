Unit AssistantCodexQualification;

{ Runtime evidence, independent of release channel. Account discovery remains
  available when an optional execution contract changes. Cached evidence never
  represents authentication or entitlement. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TCodexCancelled = Function: Boolean Of Object;
  TCodexSupport = (csUnknown, csSupported, csUnsupported);
  TCodexCapability = (ccAccount, ccLogin, ccDeviceLogin, ccModels, ccRun, ccSteer, ccSummary, ccImages, ccUsage);
  TCodexCompatibility = Record
    Executable, Version, Identity, SchemaIdentity, Adapter, Warning: String;
    Support: Array[TCodexCapability] Of TCodexSupport;
    Reason: Array[TCodexCapability] Of String;
  End;

Const
  CodexCapabilityNames: Array[TCodexCapability] Of String =
    ('account', 'browser_login', 'device_login', 'models', 'ide_execution', 'steering', 'summary', 'images', 'usage');
  CodexCompatibilityRevision = 1;

  /// Release shape is informational only. Prereleases are qualified by contract.
Function CodexVersionIsRelease(Const Line: String): Boolean;
Function CodexVersionReportLine(Const Line: String): String;
Function ReadCodexVersion(Const Executable: String; Environment: TStrings; Out VersionLine, ErrorText: String;
    Cancelled: TCodexCancelled = Nil): Boolean;
Function InspectCodexRuntime(Const Executable: String; Environment: TStrings; Out Evidence: TCodexCompatibility;
    Out ErrorText: String; Cancelled: TCodexCancelled = Nil): Boolean;
  /// Shared offline evaluator. It does not initialize a server or read credentials.
Procedure InspectCodexSchema(Const Directory: String; Var Evidence: TCodexCompatibility);
Function CodexCompatibilityJson(Const Evidence: TCodexCompatibility): String;
Function CodexRuntimeUnchanged(Const Evidence: TCodexCompatibility; Out ErrorText: String;
    Cancelled: TCodexCancelled = Nil): Boolean;
  /// Compatibility wrapper for callers requiring the complete IDE adapter.
Function QualifyCodexRuntime(Const Executable, VersionLine: String; Environment: TStrings; Out ErrorText: String): Boolean;
Procedure ClearCodexQualificationCache;

Implementation

Uses
  Process, fpjson, jsonparser, sha1, FileUtil, LazFileUtils, DirectoryListing,
  SafeFileAccess, ProcessSession, AssistantCodexSchema, AssistantCodexWire, AssistantCodexDiagnostics;

Const
  ProbeTimeoutMs = 15000;
  MaximumProbeOutput = 65536;

Function IsCancelled(Callback: TCodexCancelled): Boolean;
Begin
  Result := Assigned(Callback) And Callback();
End;

Function UniqueName: String;
Var
  Id: TGuid;
Begin
  CreateGUID(Id);
  Result := GUIDToString(Id);
End;

Function CacheDirectory: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'codex-capabilities';
End;

Function RuntimeIdentity(Const Path: String; Out Identity: String; Out Native: Boolean;
    Out ErrorText: String; Cancelled: TCodexCancelled): Boolean;
Var
  Stream: TFileStream;
  Context: TSHA1Context;
  Digest: TSHA1Digest;
  Buffer: Array[0..65535] Of Byte;
  Count: Integer;
  First: Boolean;
Begin
  Result := False;
  Identity := '';
  ErrorText := '';
  Native := False;
  If Not FileIsExecutable(Path) Then
    Begin
      ErrorText := 'The Codex executable is missing or is not executable.';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
    Try
      SHA1Init(Context);
      First := True;
      Repeat
        If IsCancelled(Cancelled) Then
          Begin
            ErrorText := 'Codex connection cancelled.';
            Exit;
          End;
        Count := Stream.Read(Buffer, SizeOf(Buffer));
        If First Then
          Begin
            Native := (Count >= 4) And (Buffer[0] = $7F) And (Buffer[1] = Ord('E')) And
              (Buffer[2] = Ord('L')) And (Buffer[3] = Ord('F'));
            First := False;
          End;
        If Count > 0 Then SHA1Update(Context, Buffer, Count);
      Until Count = 0;
      SHA1Final(Context, Digest);
      Identity := SHA1Print(Digest);
      Result := True;
    Finally
      Stream.Free;
    End;
  Except
    ErrorText := 'Cannot read the Codex executable identity.';
  End;
End;

Function RunProbe(Const Executable: String; Const Arguments: Array Of String; Environment: TStrings;
    Out Output, ErrorText: String; Cancelled: TCodexCancelled): Boolean;
Var
  Proc: TProcess;
  Buffer: Array[0..4095] Of Char;
  Deadline: QWord;
  I, Count, Budget: Integer;
  Chunk, StderrText: String;
Begin
  Result := False;
  Output := '';
  ErrorText := '';
  StderrText := '';
  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := Executable;
    Proc.CurrentDirectory := GetTempDir;
    Proc.Options := [poUsePipes, poNoConsole];
    For I := Low(Arguments) To High(Arguments) Do Proc.Parameters.Add(Arguments[I]);
    If Assigned(Environment) Then Proc.Environment.Assign(Environment);
    Try
      If Not StartInOwnSession(Proc) Then Raise Exception.Create('session');
      Proc.Execute;
      Deadline := GetTickCount64 + ProbeTimeoutMs;
      Repeat
        Budget := MaximumProbeOutput;
        While (Proc.Output.NumBytesAvailable > 0) And (Budget > 0) Do
          Begin
            Count := Proc.Output.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then Break;
            Dec(Budget, Count);
            SetString(Chunk, PChar(@Buffer[0]), Count);
            If Length(Output) + Count > MaximumProbeOutput Then
              Begin
                ErrorText := 'Codex probe output limit exceeded.';
                Exit;
              End;
            Output := Output + Chunk;
          End;
        Budget := MaximumProbeOutput;
        While (Proc.Stderr.NumBytesAvailable > 0) And (Budget > 0) Do
          Begin
            Count := Proc.Stderr.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then Break;
            Dec(Budget, Count);
            SetString(Chunk, PChar(@Buffer[0]), Count);
            StderrText := Copy(StderrText + Chunk, 1, MaximumProbeOutput);
          End;
        If IsCancelled(Cancelled) Then
          Begin
            ErrorText := 'Codex connection cancelled.';
            Exit;
          End;
        If GetTickCount64 >= Deadline Then
          Begin
            ErrorText := 'Codex probe timed out.';
            Exit;
          End;
        If Not Proc.Running And (Proc.Output.NumBytesAvailable = 0) And
          (Proc.Stderr.NumBytesAvailable = 0) Then Break;
        Sleep(5);
      Until False;
      Result := Proc.ExitStatus = 0;
      If Not Result Then ErrorText := 'Codex probe exited with status ' + IntToStr(Proc.ExitStatus) +
        ': ' + CodexDiagnosticCategory(StderrText) + '.';
    Except
      ErrorText := 'Unable to start the Codex probe.';
    End;
  Finally
    TerminateSession(Proc);
    Proc.Free;
  End;
End;

Function ReadCodexVersion(Const Executable: String; Environment: TStrings; Out VersionLine, ErrorText: String;
    Cancelled: TCodexCancelled): Boolean;
Var
  Output: String;
  Lines: TStringList;
  I: Integer;
Begin
  VersionLine := '';
  Result := RunProbe(Executable, ['--version'], Environment, Output, ErrorText, Cancelled);
  If Not Result Then Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := Output;
    For I := 0 To Lines.Count - 1 Do
      If CodexVersionReportLine(Lines[I]) <> '' Then VersionLine := CodexVersionReportLine(Lines[I]);
    { Unknown presentation is not a compatibility decision. The schema and live
      handshake must still identify a supported app-server contract. }
    If VersionLine = '' Then VersionLine := 'unknown';
  Finally
    Lines.Free;
  End;
End;

Function CodexCompatibilityJson(Const Evidence: TCodexCompatibility): String;
Var
  Root, Caps, Item: TJSONObject;
  Capability: TCodexCapability;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('revision', CodexCompatibilityRevision);
    Root.Add('executable', Evidence.Executable);
    Root.Add('version', Evidence.Version);
    Root.Add('identity', Evidence.Identity);
    Root.Add('schema_identity', Evidence.SchemaIdentity);
    Root.Add('adapter', Evidence.Adapter);
    Root.Add('warning', Evidence.Warning);
    Caps := TJSONObject.Create;
    Root.Add('capabilities', Caps);
    For Capability := Low(TCodexCapability) To High(TCodexCapability) Do
      Begin
        Item := TJSONObject.Create;
        Item.Add('state', Ord(Evidence.Support[Capability]));
        Item.Add('reason', Evidence.Reason[Capability]);
        Caps.Add(CodexCapabilityNames[Capability], Item);
      End;
    Result := Root.AsJSON;
  Finally
    Root.Free;
  End;
End;

Procedure InspectCodexSchema(Const Directory: String; Var Evidence: TCodexCompatibility);
Var
  Capability: TCodexCapability;
  SchemaHashes: String;
  Function Accept(Feature: TCodexCapability; Const FileName, Sample: String; Outgoing: Boolean = True): Boolean;
  Var
    Document, Schema, Value: TJSONData;
    Reason: String;
  Begin
    Result := False;
    Document := Nil;
    Schema := Nil;
    Value := Nil;
    Try
      If Not ReadCodexSchema(Directory, FileName, Document, Schema, Reason) Then
        Begin
          If Evidence.Support[Feature] = csSupported Then Evidence.Reason[Feature] := Reason;
          Evidence.Support[Feature] := csUnsupported;
          Exit;
        End;
      SchemaHashes := SchemaHashes + FileName + ':' + SHA1Print(SHA1String(Document.AsJSON)) + #10;
      Value := GetJSON(Sample);
      Result := CodexSchemaAccepts(Document, Schema, Value, Outgoing, Reason);
      If Not Result Then
        Begin
          If Evidence.Support[Feature] = csSupported Then Evidence.Reason[Feature] := FileName + ': ' + Reason;
          Evidence.Support[Feature] := csUnsupported;
        End;
    Finally
      Value.Free;
      Document.Free;
    End;
  End;
  Function ApprovalResult(Const Method: String): String;
  Var
    Data: TJSONData;
  Begin
    Data := GetJSON(CodexNativeApprovalReply(Method, '1'));
    Try
      Result := Data.FindPath('result').AsJSON;
    Finally
      Data.Free;
    End;
  End;
Var
  Turn, Input: String;
Begin
  SchemaHashes := '';
  Evidence.Warning := '';
  For Capability := Low(TCodexCapability) To High(TCodexCapability) Do
    Begin
      Evidence.Support[Capability] := csSupported;
      Evidence.Reason[Capability] := '';
    End;
  Accept(ccAccount, 'InitializeParams.json', '{"clientInfo":{"name":"lazworkflow","title":"Lazarus Project Assistant","version":"0.1.0"}}');
  Accept(ccAccount, 'v2/GetAccountParams.json', '{"refreshToken":false}');
  Accept(ccAccount, 'v2/GetAccountResponse.json', '{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}', False);
  Accept(ccLogin, 'v2/LoginAccountParams.json', '{"type":"chatgpt"}');
  Accept(ccLogin, 'v2/LoginAccountResponse.json', '{"type":"chatgpt","loginId":"id","authUrl":"https://auth.openai.com/"}', False);
  Accept(ccDeviceLogin, 'v2/LoginAccountParams.json', '{"type":"chatgptDeviceCode"}');
  Accept(ccDeviceLogin, 'v2/LoginAccountResponse.json', '{"type":"chatgptDeviceCode","loginId":"id","verificationUrl":"https://auth.openai.com/","userCode":"ABCD"}', False);
  Accept(ccModels, 'v2/ModelListParams.json', '{"includeHidden":false,"limit":100,"cursor":"cursor"}');
  Accept(ccModels, 'v2/ModelListResponse.json', '{"data":[],"nextCursor":null}', False);
  Evidence.Adapter := 'named-permissions-tagged-v1';
  If Not Accept(ccRun, 'v2/ThreadStartParams.json', CodexThreadStartParams('/tmp', 'model',
    '[{"name":"diagnostic","description":"Contract probe","inputSchema":{"type":"object","properties":{}}}]', 'Contract probe')) Then
  Begin
    Evidence.Support[ccRun] := csSupported;
    Evidence.Reason[ccRun] := '';
    Evidence.Adapter := 'named-permissions-v1';
    Accept(ccRun, 'v2/ThreadStartParams.json', CodexThreadStartParams('/tmp', 'model',
      '[{"name":"diagnostic","description":"Contract probe","inputSchema":{"type":"object","properties":{}}}]', 'Contract probe', False));
  End;
  Accept(ccRun, 'InitializeParams.json', '{"clientInfo":{"name":"lazworkflow","title":"Lazarus Project Assistant","version":"0.1.0"},"capabilities":{"experimentalApi":true}}');
  Accept(ccRun, 'v2/ThreadStartResponse.json', '{"modelProvider":"openai","approvalPolicy":"on-request",' +
    '"sandbox":{"type":"readOnly","networkAccess":false},"thread":{"id":"thread"}}', False);
  Input := '[{"type":"text","text":"probe"}]';
  Turn := CodexTurnBody('thread', '', Input, '', True, False);
  Accept(ccRun, 'v2/TurnStartParams.json', Turn);
  Accept(ccRun, 'v2/TurnInterruptParams.json', '{"threadId":"thread","turnId":"turn"}');
  Accept(ccRun, 'v2/ListMcpServerStatusParams.json', '{"limit":100}');
  Accept(ccRun, 'v2/ListMcpServerStatusResponse.json', '{"data":[],"nextCursor":null}', False);
  Accept(ccRun, 'DynamicToolCallParams.json', '{"threadId":"thread","turnId":"turn","callId":"call","tool":"diagnostic","arguments":{}}', False);
  Accept(ccRun, 'DynamicToolCallResponse.json', '{"contentItems":[{"type":"inputText","text":"probe"}],"success":true}');
  Accept(ccRun, 'PermissionsRequestApprovalResponse.json', ApprovalResult('item/permissions/requestApproval'));
  Accept(ccRun, 'CommandExecutionRequestApprovalResponse.json', ApprovalResult('item/commandExecution/requestApproval'));
  Accept(ccRun, 'FileChangeRequestApprovalResponse.json', ApprovalResult('item/fileChange/requestApproval'));
  Accept(ccRun, 'v2/AgentMessageDeltaNotification.json', '{"threadId":"thread","turnId":"turn","itemId":"item","delta":"text"}', False);
  Accept(ccRun, 'v2/TurnCompletedNotification.json', '{"threadId":"thread","turn":{"id":"turn","status":"completed"}}', False);
  Accept(ccSteer, 'v2/TurnSteerParams.json', CodexTurnBody('thread', 'turn', Input, '', False));
  Accept(ccSummary, 'v2/TurnStartParams.json', CodexTurnBody('thread', '', Input, '', True));
  Accept(ccImages, 'v2/TurnStartParams.json', CodexTurnBody('thread', '', '[{"type":"localImage","path":"/tmp/image.png"}]', '', True, False));
  Accept(ccImages, 'DynamicToolCallResponse.json', '{"contentItems":[{"type":"inputImage","imageUrl":"data:image/png;base64,AAAA"}],"success":true}');
  Accept(ccUsage, 'v2/GetAccountRateLimitsResponse.json', '{"rateLimits":{}}', False);
  Evidence.SchemaIdentity := SHA1Print(SHA1String(SchemaHashes));
  If Evidence.Support[ccRun] <> csSupported Then Evidence.Adapter := 'account-only';
End;

Function CachePath(Const Evidence: TCodexCompatibility): String;
Begin
  Result := IncludeTrailingPathDelimiter(CacheDirectory) + SHA1Print(SHA1String(Evidence.Executable + #1 +
    Evidence.Identity + #1 + Evidence.Version + #1 + IntToStr(CodexCompatibilityRevision))) + '.json';
End;

Function ReadCache(Var Evidence: TCodexCompatibility): Boolean;
Var
  Stream: TFileStream;
  Body, Path: String;
  Data, Caps, Item: TJSONData;
  Root: TJSONObject;
  Capability: TCodexCapability;
  State: Integer;
  Cached: TCodexCompatibility;
Begin
  Result := False;
  Path := CachePath(Evidence);
  If FileIsSymlink(CacheDirectory) Or FileIsSymlink(Path) Or Not FileExists(Path) Then Exit;
  Data := Nil;
  Try
    Try
      Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
      Try
        If Stream.Size > MaximumProbeOutput Then Exit;
        SetLength(Body, Stream.Size);
        If Body <> '' Then Stream.ReadBuffer(Body[1], Length(Body));
      Finally
        Stream.Free;
      End;
      Data := GetJSON(Body);
      If Not (Data Is TJSONObject) Then Exit;
      Root := TJSONObject(Data);
      If (Root.Get('revision', 0) <> CodexCompatibilityRevision) Or
        (Root.Get('executable', '') <> Evidence.Executable) Or (Root.Get('identity', '') <> Evidence.Identity) Or
        (Root.Get('version', '') <> Evidence.Version) Then Exit;
      Cached := Evidence;
      Cached.SchemaIdentity := Root.Get('schema_identity', '');
      Cached.Adapter := Root.Get('adapter', '');
      If (Cached.SchemaIdentity = '') Or (Cached.Adapter = '') Then Exit;
      Caps := Root.Find('capabilities');
      If Not (Caps Is TJSONObject) Then Exit;
      For Capability := Low(TCodexCapability) To High(TCodexCapability) Do
        Begin
          Item := TJSONObject(Caps).Find(CodexCapabilityNames[Capability]);
          If Not (Item Is TJSONObject) Then Exit;
          State := TJSONObject(Item).Get('state', -1);
          If Not (State In [Ord(csSupported), Ord(csUnsupported)]) Then Exit;
          Cached.Support[Capability] := TCodexSupport(State);
          Cached.Reason[Capability] := TJSONObject(Item).Get('reason', '');
        End;
      Evidence := Cached;
      Result := True;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Procedure WriteCache(Const Evidence: TCodexCompatibility);
Var
  Path, Temporary, Body, ErrorText: String;
  Data: TBytes;
Begin
  { A cache write is an optimization, never a reason to refuse a connection. }
  Try
    If FileIsSymlink(CacheDirectory) Or Not ForceDirectories(CacheDirectory) Then Exit;
    If Not ProtectOwnerOnlyDirectory(CacheDirectory) Then Exit;
    Path := CachePath(Evidence);
    Temporary := Path + '.' + UniqueName + '.tmp';
    Body := CodexCompatibilityJson(Evidence);
    SetLength(Data, Length(Body));
    If Body <> '' Then Move(Body[1], Data[0], Length(Body));
    If Not CreateExclusiveNoFollow(Temporary, Data, ErrorText) Then Exit;
    If Not ReplaceWithExclusiveFile(Temporary, Path, ErrorText) Then DeleteFile(Temporary);
  Except
    { A read-only cache still permits fresh qualification. }
  End;
End;

Procedure ClearCodexQualificationCache;
Var
  Scan: TDirectoryScan;
  Path: String;
Begin
  If FileIsSymlink(CacheDirectory) Then Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(CacheDirectory) + '*.json', faAnyFile, Scan) <> 0 Then Exit;
  Try
    Repeat
      Path := IncludeTrailingPathDelimiter(CacheDirectory) + Scan.Name;
      If Not FileIsSymlink(Path) Then DeleteFile(Path);
    Until AdvanceDirectoryScan(Scan) <> 0;
  Finally
    CloseDirectoryScan(Scan);
  End;
End;

Function CodexRuntimeUnchanged(Const Evidence: TCodexCompatibility; Out ErrorText: String;
    Cancelled: TCodexCancelled): Boolean;
Var
  Identity: String;
  Native: Boolean;
Begin
  Result := RuntimeIdentity(Evidence.Executable, Identity, Native, ErrorText, Cancelled);
  If Result And (Identity <> Evidence.Identity) Then
    Begin
      Result := False;
      ErrorText := 'The Codex executable changed during qualification. Check the connection again.';
    End;
End;

Function InspectCodexRuntime(Const Executable: String; Environment: TStrings; Out Evidence: TCodexCompatibility;
    Out ErrorText: String; Cancelled: TCodexCancelled): Boolean;
Var
  Directory, SchemaDirectory, Output: String;
  Env: TStringList;
  Native: Boolean;
  Capability: TCodexCapability;
  I, At: Integer;
  Name: String;
Begin
  Result := False;
  Evidence := Default(TCodexCompatibility);
  Evidence.Executable := ExpandFileName(Executable);
  ErrorText := '';
  If Not RuntimeIdentity(Evidence.Executable, Evidence.Identity, Native, ErrorText, Cancelled) Then Exit;
  If Not ReadCodexVersion(Evidence.Executable, Environment, Evidence.Version, ErrorText, Cancelled) Then Exit;
  { Shell/npm launchers can replace their payload without changing the launcher. }
  If Native And ReadCache(Evidence) Then Exit(True);
  Directory := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-codex-schema-' + UniqueName;
  If Not CreateDir(Directory) Or Not ProtectOwnerOnlyDirectory(Directory) Then
    Begin
      ErrorText := 'Cannot create a private Codex schema directory.';
      Exit;
    End;
  SchemaDirectory := IncludeTrailingPathDelimiter(Directory) + 'schema';
  Env := TStringList.Create;
  Try
    If Assigned(Environment) Then Env.Assign(Environment)
    Else For I := 1 To GetEnvironmentVariableCount Do Env.Add(GetEnvironmentString(I));
    For I := Env.Count - 1 DownTo 0 Do
      Begin
        At := Pos('=', Env[I]);
        Name := Copy(Env[I], 1, At - 1);
        If (Name = 'CODEX_HOME') Or (Name = 'OPENAI_API_KEY') Or (Name = 'CODEX_API_KEY') Or
          (Name = 'OPENAI_BASE_URL') Or (Name = 'CODEX_ACCESS_TOKEN') Then Env.Delete(I);
      End;
    Env.Values['CODEX_HOME'] := Directory;
    If Not RunProbe(Evidence.Executable, ['app-server', 'generate-json-schema', '--experimental', '--out', SchemaDirectory],
      Env, Output, ErrorText, Cancelled) Then
    Begin
      If IsCancelled(Cancelled) Then Exit;
      Evidence.Warning := 'Schema qualification unavailable. ' + ErrorText;
      For Capability := Low(TCodexCapability) To High(TCodexCapability) Do
        Evidence.Reason[Capability] := Evidence.Warning;
      ErrorText := '';
      Exit(True);
    End;
    InspectCodexSchema(SchemaDirectory, Evidence);
    If Not CodexRuntimeUnchanged(Evidence, ErrorText, Cancelled) Then Exit;
    If Native Then WriteCache(Evidence);
    Result := True;
  Finally
    Env.Free;
    { Only our unique private directory is removed. Never a connection profile. }
    DeleteDirectory(Directory, False);
  End;
End;

Function QualifyCodexRuntime(Const Executable, VersionLine: String; Environment: TStrings; Out ErrorText: String): Boolean;
Var
  Evidence: TCodexCompatibility;
Begin
  Result := InspectCodexRuntime(Executable, Environment, Evidence, ErrorText);
  If Not Result Then Exit;
  Result := Evidence.Support[ccRun] = csSupported;
  If Not Result Then ErrorText := 'Codex IDE execution is unavailable: ' + Evidence.Reason[ccRun];
End;

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

End.
