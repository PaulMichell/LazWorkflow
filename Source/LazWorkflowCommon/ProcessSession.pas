Unit ProcessSession;

{ Process session control the LCL process class does not provide (c) 2026 Michell Computing.

  Unix and Darwin share one arm. Windows uses TProcess options and Terminate.
  TProcess.ExitCode on FPC 3.3.1 is already wexitstatus, and is 0 when the
  child was signalled, so only the signal test is wrapped. SpawnDetached stays
  here because poDetached does not orphan a Unix child and conflicts with a
  new Windows console. }

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
/// Writes without delivering SIGPIPE to this process. False means the mask could not be set.
Function WritePipeNoSignal(Handle: THandle; Const Buf; Count: Integer; Out Written: Integer; Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;

Implementation

{$IFDEF WINDOWS}
Uses
  UTF8Process;
{$ENDIF}
{$IFDEF UNIX}
Uses
  BaseUnix, Unix{$IFDEF LINUX}, Syscall{$ENDIF};
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

Function WritePipeNoSignal(Handle: THandle; Const Buf; Count: Integer; Out Written: Integer; Out Closed, Again: Boolean; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Blocked, Previous, Pending: TSigSet;
  WaitTime: TTimespec;
  HadPending: Boolean;
  Err: cint;
{$ENDIF}
Begin
  Written := -1;
  Closed := False;
  Again := False;
  ErrorText := '';
  Result := False;
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
      WaitTime.tv_sec := 0;
      WaitTime.tv_nsec := 0;
      fpSigTimedWait(Blocked, Nil, @WaitTime);
    End;
  fpSigProcMask(SIG_SETMASK, @Previous, Nil);
  Closed := (Written < 0) And Not (Err In [ESysEAGAIN, ESysEINTR]);
  Again := (Written < 0) And (Err In [ESysEAGAIN, ESysEINTR]);
  Result := True;
  {$ELSE}
  ErrorText := 'Pipe write is not available on this host.';
  {$ENDIF}
End;

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
