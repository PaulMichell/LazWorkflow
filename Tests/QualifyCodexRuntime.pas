#!/usr/bin/env instantfpc
Program QualifyCodexRuntime;

{ Offline Codex version and schema qualification. Never signs in or starts a turn.
  (c) 2026 Michell Computing.

  instantfpc Tests/QualifyCodexRuntime.pas --runtime <codex> --output-dir <dir> }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  Classes, SysUtils, Process, fpjson, jsonparser, fpsha256;

Function ArgumentValue(Const Name: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = Name Then
      Exit(ParamStr(I + 1));
End;

Function ReleaseVersion(Const Text: String): Boolean;
Var
  Rest, Part: String;
  I, J: Integer;
Begin
  Result := False;
  If Copy(Text, 1, 10) <> 'codex-cli ' Then
    Exit;
  Rest := Copy(Text, 11, MaxInt);
  If (Rest = '') Or (Pos(' ', Rest) > 0) Then
    Exit;
  For I := 1 To 3 Do
    Begin
      If I < 3 Then
        Begin
          J := Pos('.', Rest);
          If J < 2 Then
            Exit;
          Part := Copy(Rest, 1, J - 1);
          Rest := Copy(Rest, J + 1, MaxInt);
        End
      Else
        Begin
          If Pos('.', Rest) > 0 Then
            Exit;
          Part := Rest;
        End;
      If (Part = '') Or ((Length(Part) > 1) And (Part[1] = '0')) Then
        Exit;
      For J := 1 To Length(Part) Do
        If Not (Part[J] In ['0'..'9']) Then
          Exit;
    End;
  Result := True;
End;

Function RunRuntime(Const Runtime: String; Const Args: Array Of String; Const WorkDir: String): String;
Var
  Proc: TProcess;
  Mem: TMemoryStream;
  Buf: Array[0..4095] Of Byte;
  I, Bytes: Integer;
  StartTick: QWord;
Begin
  Result := '';
  Proc := TProcess.Create(Nil);
  Mem := TMemoryStream.Create;
  Try
    Proc.Executable := Runtime;
    Proc.CurrentDirectory := WorkDir;
    Proc.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);
    Proc.Execute;
    StartTick := GetTickCount64;
    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Do
      Begin
        If GetTickCount64 - StartTick >= 60000 Then
          Begin
            Proc.Terminate(1);
            WriteLn(StdErr, 'Runtime qualification command timed out.');
            Halt(1);
          End;
        If Proc.Output.NumBytesAvailable > 0 Then
          Begin
            Bytes := Proc.Output.Read(Buf[0], SizeOf(Buf));
            If Bytes > 0 Then
              Mem.WriteBuffer(Buf[0], Bytes);
          End
        Else
          Sleep(5);
      End;
    If Proc.ExitStatus <> 0 Then
      Begin
        WriteLn(StdErr, 'Runtime qualification command failed with exit ' + IntToStr(Proc.ExitStatus));
        Halt(1);
      End;
    SetLength(Result, Mem.Size);
    If Mem.Size > 0 Then
      Move(Mem.Memory^, Result[1], Mem.Size);
    Result := Trim(Result);
  Finally
    Mem.Free;
    Proc.Free;
  End;
End;

Procedure CollectProperties(Node: TJSONData; Found: TStringList);
Var
  I: Integer;
  Obj: TJSONObject;
  Props: TJSONData;
Begin
  If Node Is TJSONObject Then
    Begin
      Obj := TJSONObject(Node);
      Props := Obj.Find('properties');
      If Props Is TJSONObject Then
        For I := 0 To TJSONObject(Props).Count - 1 Do
          Found.Add(TJSONObject(Props).Names[I]);
      For I := 0 To Obj.Count - 1 Do
        CollectProperties(Obj.Items[I], Found);
    End
  Else If Node Is TJSONArray Then
    For I := 0 To TJSONArray(Node).Count - 1 Do
      CollectProperties(TJSONArray(Node).Items[I], Found);
End;

Function Sha256File(Const Path: String): String;
Var
  Stream: TFileStream;
  Hex: AnsiString;
Begin
  Hex := '';
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
  Try
    TSHA256.StreamHexa(Stream, Hex);
  Finally
    Stream.Free;
  End;
  Result := String(Hex);
End;

Const
  RequiredNames: Array[0..10] Of String = (
    'v2/LoginAccountParams.json', 'v2/LoginAccountResponse.json', 'v2/GetAccountResponse.json',
    'v2/ThreadStartParams.json', 'v2/ThreadStartResponse.json', 'v2/TurnStartParams.json',
    'v2/TurnInterruptParams.json', 'v2/TurnSteerParams.json', 'DynamicToolCallParams.json',
    'DynamicToolCallResponse.json', 'v2/AgentMessageDeltaNotification.json');
  RequiredFields: Array[0..10] Of String = (
    'type', 'type,loginId,authUrl', 'account,requiresOpenaiAuth',
    'dynamicTools,modelProvider,permissions,approvalPolicy',
    'modelProvider,sandbox,approvalPolicy,thread', 'threadId,input,permissions,summary',
    'threadId,turnId', 'threadId,expectedTurnId,input', 'threadId,turnId,callId,tool,arguments',
    'contentItems,success', 'threadId,turnId,itemId,delta');

Var
  Runtime, Output, Version, SchemaDir, Field, Fields, Name: String;
  Manifest, Hashes: TJSONObject;
  Schema: TJSONData;
  Found: TStringList;
  I, J: Integer;
  Stream: TFileStream;
  Body: String;
Begin
  Runtime := ArgumentValue('--runtime');
  Output := ArgumentValue('--output-dir');
  If (Runtime = '') Or (Output = '') Then
    Begin
      WriteLn(StdErr, 'Usage: instantfpc Tests/QualifyCodexRuntime.pas --runtime <codex> --output-dir <dir>');
      Halt(2);
    End;
  Runtime := ExpandFileName(Runtime);
  Output := ExpandFileName(Output);
  If Not FileExists(Runtime) Then
    Begin
      WriteLn(StdErr, 'Runtime was not found: ' + Runtime);
      Halt(2);
    End;
  If Not ForceDirectories(Output) Then
    Begin
      WriteLn(StdErr, 'Could not create ' + Output);
      Halt(1);
    End;
  Version := RunRuntime(Runtime, ['--version'], Output);
  If Not ReleaseVersion(Version) Then
    Begin
      WriteLn(StdErr, 'Unsupported runtime version; expected a codex-cli release such as codex-cli 0.160.0');
      Halt(1);
    End;
  SchemaDir := IncludeTrailingPathDelimiter(Output) + 'schema';
  RunRuntime(Runtime, ['app-server', 'generate-json-schema', '--experimental', '--out', SchemaDir], Output);
  Hashes := TJSONObject.Create;
  Found := TStringList.Create;
  Try
    For I := 0 To High(RequiredNames) Do
      Begin
        Name := IncludeTrailingPathDelimiter(SchemaDir) + RequiredNames[I];
        If Not FileExists(Name) Then
          Begin
            WriteLn(StdErr, 'Required schema missing: ' + RequiredNames[I]);
            Halt(1);
          End;
        Found.Clear;
        Stream := TFileStream.Create(Name, fmOpenRead Or fmShareDenyWrite);
        Try
          SetLength(Body, Stream.Size);
          If Stream.Size > 0 Then
            Stream.ReadBuffer(Body[1], Stream.Size);
        Finally
          Stream.Free;
        End;
        Schema := GetJSON(Body);
        Try
          CollectProperties(Schema, Found);
        Finally
          Schema.Free;
        End;
        Fields := RequiredFields[I];
        While Fields <> '' Do
          Begin
            J := Pos(',', Fields);
            If J = 0 Then
              Begin
                Field := Fields;
                Fields := '';
              End
            Else
              Begin
                Field := Copy(Fields, 1, J - 1);
                Delete(Fields, 1, J);
              End;
            If Found.IndexOf(Field) < 0 Then
              Begin
                WriteLn(StdErr, 'Required protocol field missing from ' + RequiredNames[I] + ': ' + Field);
                Halt(1);
              End;
          End;
        Hashes.Add(RequiredNames[I], Sha256File(Name));
      End;
    Manifest := TJSONObject.Create;
    Try
      Manifest.Add('version', Version);
      Manifest.Add('runtime_sha256', Sha256File(Runtime));
      Manifest.Add('experimental_schema_sha256', Hashes);
      Hashes := Nil;
      Manifest.Add('scope', 'Offline schema shape only; not account entitlement, model inference or tool isolation');
      Body := Manifest.AsJSON + LineEnding;
    Finally
      Manifest.Free;
    End;
  Finally
    Hashes.Free;
    Found.Free;
  End;
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(Output) + 'qualification.json', fmCreate);
  Try
    Stream.WriteBuffer(Body[1], Length(Body));
  Finally
    Stream.Free;
  End;
  WriteLn('Qualified ' + Version + ': ' + IncludeTrailingPathDelimiter(Output) + 'qualification.json');
End.
