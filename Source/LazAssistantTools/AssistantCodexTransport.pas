Unit AssistantCodexTransport;

{ Single-owner, nonblocking JSONL process transport. Use from a worker, never
  the IDE thread. Cancel is the only method callable from another thread.
  Linux preview: other platforms fail closed until their pipe handling is tested. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Process;

Const
  CodexMaxFrameBytes = 1048576;
  CodexMaxQueueBytes = 4194304;
  CodexMaxQueueFrames = 256;

Type
  TAssistantCodexTransport = Class
  Private
    FProcess: TProcess;
    FIncoming, FOutgoing: TStringList;
    FBuffer, FError: String;
    FReadBytes, FWriteBytes, FWriteOffset: Integer;
    FCancel: LongInt;
    FCancelReason: String;
    FWriteStarted: QWord;
    FWriteTimeout: Cardinal;
    FOwner: TThreadID;
    FExitCode: Integer;
    Procedure CheckOwner;
    Procedure Fail(Const Reason: String);
    Procedure AcceptBytes(Const Bytes: String);
    Procedure Drain;
    Procedure Flush;
  Public
    Constructor Create(WriteTimeoutMs: Cardinal = 10000);
    Destructor Destroy; Override;
    Function Start(Const Executable, WorkingDirectory: String; Args: TStrings;
      Environment: TStrings = Nil): Boolean;
    Function Queue(Const JsonLine: String): Boolean;
    Procedure Poll;
    Function TakeFrame(Out Frame: String): Boolean;
    { Reason is used when this owner calls Cancel. An empty reason stays the user-cancel text. }
    Procedure Cancel(Const Reason: String = '');
    Procedure Stop;
    Function Running: Boolean;
    Property LastError: String Read FError;
    Property ExitCode: Integer Read FExitCode;
  End;

Implementation

Uses
  ProcessSession;

Constructor TAssistantCodexTransport.Create(WriteTimeoutMs: Cardinal);
Begin
  Inherited Create;
  FOwner := GetCurrentThreadID;
  FIncoming := TStringList.Create;
  FOutgoing := TStringList.Create;
  FWriteTimeout := WriteTimeoutMs;
  FExitCode := -1;
End;

Destructor TAssistantCodexTransport.Destroy;
Begin
  Stop;
  FIncoming.Free;
  FOutgoing.Free;
  Inherited Destroy;
End;

Procedure TAssistantCodexTransport.CheckOwner;
Begin
  If GetCurrentThreadID <> FOwner Then
    Raise Exception.Create('Codex transport must be used by its owning worker.');
End;

Function TAssistantCodexTransport.Start(Const Executable, WorkingDirectory: String;
    Args: TStrings; Environment: TStrings): Boolean;
Begin
  CheckOwner;
  Stop;
  FError := '';
  FExitCode := -1;
  InterlockedExchange(FCancel, 0);
  FIncoming.Clear;
  FOutgoing.Clear;
  FBuffer := '';
  FReadBytes := 0;
  FWriteBytes := 0;
  FWriteOffset := 1;
  Result := False;
  {$IFNDEF LINUX}
  FError := 'Codex process transport is currently qualified for Linux only.';
  Exit;
  {$ENDIF}
  Try
    FProcess := TProcess.Create(Nil);
    FProcess.Executable := Executable;
    FProcess.CurrentDirectory := WorkingDirectory;
    FProcess.Parameters.Assign(Args);
    If Assigned(Environment) Then FProcess.Environment.Assign(Environment);
    FProcess.Options := [poUsePipes];
    If Not StartInOwnSession(FProcess) Then
      Raise Exception.Create('Unable to start the Codex runtime or configure its pipes.');
    FProcess.Execute;
    If Not SetPipeNonBlocking(FProcess.Input.Handle) Then
      Raise Exception.Create('Nonblocking pipe setup failed');
    Result := True;
  Except
    { Never expose environment or process output in errors. }
    On E: Exception Do Fail('Unable to start the Codex runtime or configure its pipes.');
  End;
End;

Procedure TAssistantCodexTransport.Stop;
Begin
  CheckOwner;
  If Assigned(FProcess) Then
    Begin
      TerminateSession(FProcess);
      If Not FProcess.Running Then FExitCode := FProcess.ExitCode;
      FreeAndNil(FProcess);
    End;
  FOutgoing.Clear;
  FWriteBytes := 0;
  FWriteOffset := 1;
End;

Procedure TAssistantCodexTransport.Fail(Const Reason: String);
Begin
  FError := Reason;
  Stop;
End;

Procedure TAssistantCodexTransport.Cancel(Const Reason: String);
Begin
  { The owner thread sets the reason before the flag. Poll reads both. }
  If Reason <> '' Then FCancelReason := Reason;
  InterlockedExchange(FCancel, 1);
End;

Function TAssistantCodexTransport.Running: Boolean;
Begin
  CheckOwner;
  Result := Assigned(FProcess) And FProcess.Running;
End;

Function TAssistantCodexTransport.Queue(Const JsonLine: String): Boolean;
Begin
  CheckOwner;
  Result := False;
  If (FError <> '') Or Not Running Then Exit;
  If (Length(JsonLine) > CodexMaxFrameBytes) Or (Pos(#10, JsonLine) > 0) Or
    (Pos(#13, JsonLine) > 0) Or (JsonLine = '') Then
      Begin
        Fail('Invalid or oversized outgoing Codex frame.');
        Exit;
      End;
  If (FOutgoing.Count >= CodexMaxQueueFrames) Or
    (Length(JsonLine) + 1 > CodexMaxQueueBytes - FWriteBytes) Then
      Begin
        Fail('Codex outgoing queue limit exceeded.');
        Exit;
      End;
  If FOutgoing.Count = 0 Then FWriteStarted := GetTickCount64;
  FOutgoing.Add(JsonLine + #10);
  Inc(FWriteBytes, Length(JsonLine) + 1);
  Result := True;
End;

Procedure TAssistantCodexTransport.AcceptBytes(Const Bytes: String);
Var
  I: Integer;
Begin
  For I := 1 To Length(Bytes) Do
    If Bytes[I] = #10 Then
      Begin
        If (Length(FBuffer) > 0) And (FBuffer[Length(FBuffer)] = #13) Then
          Delete(FBuffer, Length(FBuffer), 1);
        If FBuffer <> '' Then
          Begin
            If (FIncoming.Count >= CodexMaxQueueFrames) Or
              (Length(FBuffer) > CodexMaxQueueBytes - FReadBytes) Then
                Begin
                  Fail('Codex incoming queue limit exceeded.');
                  Exit;
                End;
            FIncoming.Add(FBuffer);
            Inc(FReadBytes, Length(FBuffer));
          End;
        FBuffer := '';
      End
            Else
              Begin
                If Length(FBuffer) >= CodexMaxFrameBytes Then
                  Begin
                    Fail('Oversized incoming Codex frame.');
                    Exit;
                  End;
                FBuffer := FBuffer + Bytes[I];
              End;
End;

Procedure TAssistantCodexTransport.Drain;
Var
  Buf: Array[0..8191] Of Char;
  N, Budget: Integer;
  Bytes: String;
Begin
  Budget := 65536;
  While Assigned(FProcess) And (FProcess.Output.NumBytesAvailable > 0) And (Budget > 0) Do
    Begin
      N := FProcess.Output.NumBytesAvailable;
      If N > SizeOf(Buf) Then N := SizeOf(Buf);
      N := FProcess.Output.Read(Buf, N);
      If N <= 0 Then Break;
      SetString(Bytes, PChar(@Buf[0]), N);
      AcceptBytes(Bytes);
      Dec(Budget, N);
    End;
  { Drain stderr separately; do not retain account details or flood the UI. }
  Budget := 65536;
  While Assigned(FProcess) And (FProcess.Stderr.NumBytesAvailable > 0) And (Budget > 0) Do
    Begin
      N := FProcess.Stderr.NumBytesAvailable;
      If N > SizeOf(Buf) Then N := SizeOf(Buf);
      N := FProcess.Stderr.Read(Buf, N);
      If N <= 0 Then Break;
      Dec(Budget, N);
    End;
End;

Procedure TAssistantCodexTransport.Flush;
Var
  N: Integer;
  Frame, PipeError: String;
  Closed, Again: Boolean;
Begin
  If (FOutgoing.Count = 0) Or Not Assigned(FProcess) Then Exit;
  If GetTickCount64 - FWriteStarted >= FWriteTimeout Then
    Begin
      Fail('Codex stdin write timed out.');
      Exit;
    End;
  Frame := FOutgoing[0];
  { A dead child's pipe must not deliver SIGPIPE to the Lazarus process. }
  If Not WritePipeNoSignal(FProcess.Input.Handle, Frame[FWriteOffset], Length(Frame) - FWriteOffset + 1, N, Closed,
    Again, PipeError) Then
    Begin
      If PipeError = 'Unable to inspect pending pipe signals.' Then
        Fail('Unable to inspect pending pipe signals.')
      Else
        Fail('Unable to protect Codex pipe write.');
      Exit;
    End;
  If Again Then
    Exit;
  If N > 0 Then
    Begin
      Inc(FWriteOffset, N);
      If FWriteOffset > Length(Frame) Then
        Begin
          Dec(FWriteBytes, Length(Frame));
          FOutgoing.Delete(0);
          FWriteOffset := 1;
          FWriteStarted := GetTickCount64;
        End;
    End
  Else If Closed Then
    Fail('Codex stdin closed unexpectedly.');
End;

Procedure TAssistantCodexTransport.Poll;
Begin
  CheckOwner;
  If InterlockedCompareExchange(FCancel, 0, 0) <> 0 Then
    Begin
      If FCancelReason <> '' Then Fail(FCancelReason)
      Else Fail('Codex connection cancelled.');
      Exit;
    End;
  If Not Assigned(FProcess) Then Exit;
  Drain;
  If Not Assigned(FProcess) Then Exit;
  If Not FProcess.Running Then
    Begin
      { Drain remaining bytes over bounded polls before reporting EOF. }
      If FProcess.Output.NumBytesAvailable > 0 Then Exit;
      If FBuffer <> '' Then Fail('Codex exited with a truncated protocol frame.')
      Else Fail('Codex runtime exited.');
      Exit;
    End;
  Flush;
End;

Function TAssistantCodexTransport.TakeFrame(Out Frame: String): Boolean;
Begin
  CheckOwner;
  Frame := '';
  Result := FIncoming.Count > 0;
  If Not Result Then Exit;
  Frame := FIncoming[0];
  Dec(FReadBytes, Length(Frame));
  FIncoming.Delete(0);
End;
End.
