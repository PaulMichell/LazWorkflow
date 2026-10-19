Unit ProcessSession;

{ Start a program the IDE must not wait for or reap (c) 2026 Michell Computing.

  Windows uses TProcessUTF8 with poNewConsole, which is CREATE_NEW_CONSOLE.
  poDetached is DETACHED_PROCESS and Windows rejects it together with a new
  console. Unix TProcess does not implement poDetached, and freeing the
  process object does not wait, so the child would become an IDE zombie.
  The Unix arm is the existing double fork. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;

Implementation

{$IFDEF WINDOWS}
Uses
  Process, UTF8Process;
{$ENDIF}
{$IFDEF UNIX}
Uses
  BaseUnix;
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

End.
