Unit ProcessSession;

{ Process session control the LCL process class does not provide (c) 2026 Michell Computing.

  Unix and Darwin share one arm. Windows uses TProcess options and Terminate,
  and an overlapped named-pipe write so a poll does not block. TProcess.ExitCode
  on FPC 3.3.1 is already wexitstatus, and is 0 when the child was signalled, so
  only the signal test is wrapped. SpawnDetached stays here because poDetached
  does not orphan a Unix child and conflicts with a new Windows console. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, Process;

/// Installs setsid on Unix, or poNewProcessGroup on Windows, before Execute.
Function StartInOwnSession(Process: TProcess): Boolean;
/// Term, a short wait, then kill. Unix signals the process group. Callers do not kill again.
Procedure TerminateSession(Process: TProcess);
/// True when the child died by signal. ExitCode is then 0 and is not a status.
Function ProcessWasSignalled(Process: TProcess): Boolean;
/// Sets O_NONBLOCK on a Unix pipe handle. Other hosts return false.
Function SetPipeNonBlocking(Handle: THandle): Boolean;
/// Asks Darwin not to raise SIGPIPE for writes to a pipe this process created. Other hosts return false.
Function SetPipeNoSignal(Handle: THandle): Boolean;
/// Writes without delivering SIGPIPE to this process. False means the mask could not be set.
Function WritePipeNoSignal(Handle: THandle; Const Buf; Count: Integer; Out Written: Integer; Out Closed, Again: Boolean; Out ErrorText: String): Boolean;

Type
  { One outstanding nonblocking write. Unix leaves it empty. Windows keeps the overlapped operation here so the
    caller's buffer must stay alive until Pending is false. }
  TPipeWriteSlot = Record
    Event: THandle;
    Pending: Boolean;
    State: Pointer;
  End;

/// Windows: an inheritable blocking read end for the child, and an overlapped write end for the parent.
/// Anonymous pipes cannot set overlapped mode on one end only, and PIPE_NOWAIT would make the child reads return
/// immediately. Other hosts return false.
Function CreateChildInputPipe(Out WriteHandle, ReadHandle: THandle; BufferBytes: Cardinal; Out ErrorText: String): Boolean;
/// Prepares Slot for WritePipeNoBlock. Unix does nothing.
Procedure PreparePipeWrite(Var Slot: TPipeWriteSlot);
/// Cancels a pending write and releases Slot. Handle may be 0.
Procedure ReleasePipeWrite(Handle: THandle; Var Slot: TPipeWriteSlot);
/// Closes Handle when it is not 0.
Procedure ClosePipeHandle(Var Handle: THandle);
/// Nonblocking write. Unix is WritePipeNoSignal. Windows uses Slot and never waits for the child to read.
Function WritePipeNoBlock(Handle: THandle; Const Buf; Count: Integer; Var Slot: TPipeWriteSlot; Out Written: Integer;
  Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;

Implementation

{$IFDEF WINDOWS}
Uses
  Windows, UTF8Process;
{$ENDIF}
{$IFDEF UNIX}
Uses
  BaseUnix, Unix{$IFDEF LINUX}, Syscall{$ENDIF};
{$ENDIF}

{$IFDEF DARWIN}
{ macOS has no sigtimedwait. BaseUnix imports sigpending without Darwin's leading
  underscore, so these libc imports are used instead. The set is sigset_t. }
Function DarwinSigPending(SigSet: PSigSet): cint; CDecl; External 'c' Name 'sigpending';
Function DarwinSigWait(SigSet: PSigSet; Var Signo: cint): cint; CDecl; External 'c' Name 'sigwait';

{ macOS 10.13 and later: a write to a descriptor with this flag returns EPIPE and raises no signal. }
Const
  DarwinSetNoSigPipe = 73;
  DarwinGetNoSigPipe = 74;
{$ENDIF}

{$IFDEF UNIX}
Type
  TSessionStarter = Class
    Procedure ChildFork(Sender: TObject);
  End;

Var
  SessionStarter: TSessionStarter;

Procedure TSessionStarter.ChildFork(Sender: TObject);
Begin
  If Sender = Nil Then
    Exit;
  If fpSetsid < 0 Then
    fpExit(126);
End;
{$ENDIF}

{$IFDEF WINDOWS}
Var
  PipeSerial: Integer;
{$ENDIF}

Function StartInOwnSession(Process: TProcess): Boolean;
Begin
  Result := False;
  If Not Assigned(Process) Then
    Exit;
  {$IFDEF UNIX}
  If Not Assigned(SessionStarter) Then
    SessionStarter := TSessionStarter.Create;
  Process.OnForkEvent := @SessionStarter.ChildFork;
  Result := True;
  {$ELSE}
    {$IFDEF WINDOWS}
    Process.Options := Process.Options + [poNewProcessGroup];
    Result := True;
    {$ENDIF}
  {$ENDIF}
End;

Procedure TerminateSession(Process: TProcess);
{$IFDEF UNIX}
Var
  Deadline: QWord;
  Pid: Integer;
{$ENDIF}
Begin
  If Not Assigned(Process) Then
    Exit;
  {$IFDEF UNIX}
  Pid := Process.ProcessID;
  If Pid <= 0 Then
    Exit;
  If Process.Running Then
    Begin
      If fpKill(-Pid, SIGTERM) <> 0 Then
        fpKill(Pid, SIGTERM);
      Deadline := GetTickCount64 + 100;
      While Process.Running And (GetTickCount64 < Deadline) Do
        Sleep(1);
      fpKill(-Pid, SIGKILL);
      If Process.Running Then
        fpKill(Pid, SIGKILL);
      { Do not call TProcess.Terminate: it waits without a bound and misses the group. }
      Process.WaitOnExit(500);
    End;
  fpKill(-Pid, SIGKILL);
  {$ELSE}
    {$IFDEF WINDOWS}
    If Process.Running Then
      Process.Terminate(1);
    {$ENDIF}
  {$ENDIF}
End;

Function ProcessWasSignalled(Process: TProcess): Boolean;
Begin
  Result := False;
  If Not Assigned(Process) Or Process.Running Then
    Exit;
  {$IFDEF UNIX}
  Result := Not WIFEXITED(Process.ExitStatus);
  {$ENDIF}
End;

Function SetPipeNonBlocking(Handle: THandle): Boolean;
{$IFDEF UNIX}
Var
  Flags: cint;
{$ENDIF}
Begin
  Result := False;
  {$IFDEF UNIX}
  Flags := fpFcntl(cint(Handle), F_GETFL);
  If Flags < 0 Then
    Exit;
  Result := fpFcntl(cint(Handle), F_SETFL, Flags Or O_NONBLOCK) >= 0;
  {$ENDIF}
End;

Function SetPipeNoSignal(Handle: THandle): Boolean;
Begin
  Result := False;
  {$IFDEF DARWIN}
  Result := fpFcntl(cint(Handle), DarwinSetNoSigPipe, 1) >= 0;
  {$ENDIF}
End;

Function WritePipeNoSignal(Handle: THandle; Const Buf; Count: Integer; Out Written: Integer; Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Blocked, Previous, Pending: TSigSet;
  {$IFNDEF DARWIN}
  WaitTime: TTimespec;
  {$ENDIF}
  HadPending: Boolean;
  Err: cint;
  {$IFDEF DARWIN}
  Signo: cint;
  {$ENDIF}
{$ENDIF}
Begin
  Written := -1;
  Closed := False;
  Again := False;
  ErrorText := '';
  Result := False;
  {$IFDEF DARWIN}
  { One fcntl in place of the mask, pending check and sigwait. The flag is read rather than remembered, so a
    reused descriptor number, or a handle that SetPipeNoSignal did not mark, still takes the masked path. }
  If fpFcntl(cint(Handle), DarwinGetNoSigPipe) > 0 Then
    Begin
      Written := fpWrite(cint(Handle), Buf, Count);
      Err := fpGetErrno;
      Closed := (Written < 0) And Not (Err In [ESysEAGAIN, ESysEINTR]);
      Again := (Written < 0) And (Err In [ESysEAGAIN, ESysEINTR]);
      Result := True;
      Exit;
    End;
  {$ENDIF}
  {$IFDEF UNIX}
  fpSigEmptySet(Blocked);
  fpSigAddSet(Blocked, SIGPIPE);
  If fpSigProcMask(SIG_BLOCK, @Blocked, @Previous) <> 0 Then
    Begin
      ErrorText := 'Unable to protect the pipe write.';
      Exit;
    End;
  fpSigEmptySet(Pending);
  {$IFDEF LINUX}
  { fpSigPending omits Linux's required sigset-size argument. }
  If do_syscall(syscall_nr_rt_sigpending, TSysParam(@Pending), TSysParam(8)) <> 0 Then
  {$ELSEIF DEFINED(DARWIN)}
  If DarwinSigPending(@Pending) <> 0 Then
  {$ELSE}
  If fpSigPending(Pending) <> 0 Then
  {$ENDIF}
    Begin
      fpSigProcMask(SIG_SETMASK, @Previous, Nil);
      ErrorText := 'Unable to inspect pending pipe signals.';
      Exit;
    End;
  HadPending := fpSigIsMember(Pending, SIGPIPE) = 1;
  Written := fpWrite(cint(Handle), Buf, Count);
  Err := fpGetErrno;
  If (Written < 0) And (Err = ESysEPIPE) And Not HadPending Then
    Begin
      {$IFDEF DARWIN}
      { sigwait returns at once when SIGPIPE is already pending, and would block if it is not. }
      Signo := 0;
      If (DarwinSigPending(@Pending) = 0) And (fpSigIsMember(Pending, SIGPIPE) = 1) Then
        DarwinSigWait(@Blocked, Signo);
      {$ELSE}
      WaitTime.tv_sec := 0;
      WaitTime.tv_nsec := 0;
      fpSigTimedWait(Blocked, Nil, @WaitTime);
      {$ENDIF}
    End;
  fpSigProcMask(SIG_SETMASK, @Previous, Nil);
  Closed := (Written < 0) And Not (Err In [ESysEAGAIN, ESysEINTR]);
  Again := (Written < 0) And (Err In [ESysEAGAIN, ESysEINTR]);
  Result := True;
  {$ELSE}
  ErrorText := 'Pipe write is not available on this host.';
  {$ENDIF}
End;

Procedure ClosePipeHandle(Var Handle: THandle);
Begin
  If Handle = 0 Then Exit;
  FileClose(Handle);
  Handle := 0;
End;

{$IFDEF WINDOWS}
Type
  PPipeOverlapped = ^TOverlapped;

Function PipeIsClosed(Err: DWORD): Boolean;
Begin
  Result := (Err = ERROR_BROKEN_PIPE) Or (Err = ERROR_NO_DATA) Or (Err = ERROR_PIPE_NOT_CONNECTED);
End;

Function CreateChildInputPipe(Out WriteHandle, ReadHandle: THandle; BufferBytes: Cardinal; Out ErrorText: String): Boolean;
Var
  PipeName: UnicodeString;
  Inherit: TSecurityAttributes;
  Connect: TOverlapped;
  ConnectEvent: THandle;
  Err: DWORD;
Begin
  Result := False;
  WriteHandle := 0;
  ReadHandle := 0;
  ErrorText := '';
  ConnectEvent := 0;
  If BufferBytes < 4096 Then BufferBytes := 4096;
  Inc(PipeSerial);
  PipeName := '\\.\pipe\lazworkflow-codex-' + IntToStr(GetCurrentProcessId) + '-' + IntToStr(PipeSerial);
  WriteHandle := CreateNamedPipeW(PWideChar(PipeName), PIPE_ACCESS_OUTBOUND Or FILE_FLAG_OVERLAPPED,
    PIPE_TYPE_BYTE Or PIPE_READMODE_BYTE Or PIPE_WAIT, 1, BufferBytes, BufferBytes, 0, Nil);
  If WriteHandle = INVALID_HANDLE_VALUE Then
    Begin
      WriteHandle := 0;
      ErrorText := 'Unable to create the Codex input pipe.';
      Exit;
    End;
  FillChar(Inherit, SizeOf(Inherit), 0);
  Inherit.nLength := SizeOf(Inherit);
  Inherit.bInheritHandle := True;
  ReadHandle := CreateFileW(PWideChar(PipeName), GENERIC_READ, 0, @Inherit, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  If ReadHandle = INVALID_HANDLE_VALUE Then
    Begin
      ClosePipeHandle(WriteHandle);
      ReadHandle := 0;
      ErrorText := 'Unable to open the Codex input pipe.';
      Exit;
    End;
  { The client CreateFile already connected the pipe. ConnectNamedPipe records that on an overlapped server. }
  ConnectEvent := CreateEvent(Nil, True, False, Nil);
  If ConnectEvent = 0 Then
    Begin
      ClosePipeHandle(ReadHandle);
      ClosePipeHandle(WriteHandle);
      ErrorText := 'Unable to create the Codex input pipe.';
      Exit;
    End;
  FillChar(Connect, SizeOf(Connect), 0);
  Connect.hEvent := ConnectEvent;
  If Not ConnectNamedPipe(WriteHandle, @Connect) Then
    Begin
      Err := GetLastError;
      If Err = ERROR_IO_PENDING Then
        Begin
          If WaitForSingleObject(ConnectEvent, 1000) <> WAIT_OBJECT_0 Then
            Begin
              CancelIo(WriteHandle);
              WaitForSingleObject(ConnectEvent, 1000);
              CloseHandle(ConnectEvent);
              ClosePipeHandle(ReadHandle);
              ClosePipeHandle(WriteHandle);
              ErrorText := 'Unable to connect the Codex input pipe.';
              Exit;
            End;
        End
      Else If Err <> ERROR_PIPE_CONNECTED Then
        Begin
          CloseHandle(ConnectEvent);
          ClosePipeHandle(ReadHandle);
          ClosePipeHandle(WriteHandle);
          ErrorText := 'Unable to connect the Codex input pipe.';
          Exit;
        End;
    End;
  CloseHandle(ConnectEvent);
  Result := True;
End;

Procedure PreparePipeWrite(Var Slot: TPipeWriteSlot);
Var
  Overlapped: PPipeOverlapped;
Begin
  If Slot.Event <> 0 Then Exit;
  Slot.Event := CreateEvent(Nil, True, False, Nil);
  If Slot.Event = 0 Then Exit;
  New(Overlapped);
  FillChar(Overlapped^, SizeOf(TOverlapped), 0);
  Slot.State := Overlapped;
  Slot.Pending := False;
End;

Procedure ReleasePipeWrite(Handle: THandle; Var Slot: TPipeWriteSlot);
Var
  Overlapped: PPipeOverlapped;
Begin
  If Slot.Pending And (Handle <> 0) And (Slot.Event <> 0) Then
    Begin
      CancelIo(Handle);
      WaitForSingleObject(Slot.Event, 5000);
      Slot.Pending := False;
    End;
  If Slot.Event <> 0 Then
    Begin
      CloseHandle(Slot.Event);
      Slot.Event := 0;
    End;
  If Assigned(Slot.State) Then
    Begin
      Overlapped := PPipeOverlapped(Slot.State);
      Dispose(Overlapped);
      Slot.State := Nil;
    End;
End;

Function WritePipeNoBlock(Handle: THandle; Const Buf; Count: Integer; Var Slot: TPipeWriteSlot; Out Written: Integer;
  Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
Var
  Overlapped: PPipeOverlapped;
  Transferred: DWORD;
  Err: DWORD;
Begin
  Written := 0;
  Closed := False;
  Again := False;
  ErrorText := '';
  Result := False;
  If (Handle = 0) Or (Count < 1) Or (Slot.Event = 0) Or Not Assigned(Slot.State) Then
    Begin
      ErrorText := 'Unable to write the Codex pipe.';
      Exit;
    End;
  Overlapped := PPipeOverlapped(Slot.State);
  If Slot.Pending Then
    Begin
      If WaitForSingleObject(Slot.Event, 0) <> WAIT_OBJECT_0 Then
        Begin
          Again := True;
          Result := True;
          Exit;
        End;
      If Not GetOverlappedResult(Handle, Overlapped^, Transferred, False) Then
        Begin
          Err := GetLastError;
          Slot.Pending := False;
          Closed := PipeIsClosed(Err);
          If Not Closed Then ErrorText := 'Unable to write the Codex pipe.';
          Result := Closed;
          Exit;
        End;
      Slot.Pending := False;
      Written := Transferred;
      Result := True;
      Exit;
    End;
  ResetEvent(Slot.Event);
  FillChar(Overlapped^, SizeOf(TOverlapped), 0);
  Overlapped^.hEvent := Slot.Event;
  If WriteFile(Handle, Buf, DWORD(Count), Transferred, POverlapped(Overlapped)) Then
    Begin
      Written := Transferred;
      Result := True;
      Exit;
    End;
  Err := GetLastError;
  If Err = ERROR_IO_PENDING Then
    Begin
      Slot.Pending := True;
      Again := True;
      Result := True;
      Exit;
    End;
  Closed := PipeIsClosed(Err);
  If Not Closed Then ErrorText := 'Unable to write the Codex pipe.';
  Result := Closed;
End;
{$ELSE}
Function CreateChildInputPipe(Out WriteHandle, ReadHandle: THandle; BufferBytes: Cardinal; Out ErrorText: String): Boolean;
Begin
  WriteHandle := 0;
  ReadHandle := 0;
  ErrorText := '';
  Result := False;
  If BufferBytes = 0 Then Exit;
End;

Procedure PreparePipeWrite(Var Slot: TPipeWriteSlot);
Begin
  Slot.Event := 0;
  Slot.Pending := False;
  Slot.State := Nil;
End;

Procedure ReleasePipeWrite(Handle: THandle; Var Slot: TPipeWriteSlot);
Begin
  If Handle = 0 Then Slot.Pending := False;
  Slot.Event := 0;
  Slot.Pending := False;
  Slot.State := Nil;
End;

Function WritePipeNoBlock(Handle: THandle; Const Buf; Count: Integer; Var Slot: TPipeWriteSlot; Out Written: Integer;
  Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
Begin
  Result := WritePipeNoSignal(Handle, Buf, Count, Written, Closed, Again, ErrorText);
  If Slot.Pending Then Slot.Pending := False;
End;
{$ENDIF}

{$IFDEF WINDOWS}
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;
Var
  Proc: TProcessUTF8;
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  Proc := TProcessUTF8.Create(Nil);
  Try
    Proc.Executable := Executable;
    Proc.InheritHandles := False;
    Proc.Options := [poNewConsole];
    For I := 0 To High(Args) Do
      Proc.Parameters.Add(Args[I]);
    Try
      Proc.Execute;
      Result := True;
    Except
      On E: Exception Do
        ErrorText := 'Could not start Claude Code sign-in.';
    End;
  Finally
    Proc.Free;
  End;
End;
{$ENDIF}

{$IFDEF UNIX}
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;
Var
  Pid: TPid;
  Status: cint;
  Argv: PPChar;
  Owned: Array Of AnsiString;
  I, Count: Integer;
Begin
  Result := False;
  ErrorText := '';
  Status := 0;
  Owned := Nil;
  Pid := FpFork;
  If Pid < 0 Then
    Begin
      ErrorText := 'Could not start Claude Code sign-in.';
      Exit;
    End;
  If Pid = 0 Then
    Begin
      If FpFork = 0 Then
        Begin
          Count := Length(Args) + 2;
          SetLength(Owned, Count - 1);
          GetMem(Argv, Count * SizeOf(PChar));
          Owned[0] := Executable;
          Argv[0] := PChar(Owned[0]);
          For I := 0 To High(Args) Do
            Begin
              Owned[I + 1] := Args[I];
              Argv[I + 1] := PChar(Owned[I + 1]);
            End;
          Argv[Count - 1] := Nil;
          FpExecv(PChar(Executable), Argv);
          FpExit(127);
        End;
      FpExit(0);
    End;
  FpWaitPid(Pid, Status, 0);
  Result := True;
End;
{$ENDIF}

{$IF NOT DEFINED(UNIX) AND NOT DEFINED(WINDOWS)}
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := 'Could not start Claude Code sign-in.';
End;
{$ENDIF}

{$IFDEF UNIX}
Finalization
FreeAndNil(SessionStarter);
{$ENDIF}

End.
