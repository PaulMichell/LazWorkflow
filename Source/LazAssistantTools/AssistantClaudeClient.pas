Unit AssistantClaudeClient;

{ Process wrapper for the installed Claude Code program. Not an HTTP client
  and not an OAuth client. The assistant does not parse or copy sign-in files.
  A Claude row does not receive this assistant's tool list, skill bodies, or
  transcript compactor. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConnections;

Const
  ClaudeUsageReported = 'reported';
  ClaudeUsageUnavailable = 'unavailable';
  { Status text for a Claude connection row. }
  ClaudeKeepsSessionText = 'Claude Code keeps the session.';

Type
  TClaudeTurnResult = Record
    Text: String;
    UsageState: String;
    InputTokens: Integer;
    OutputTokens: Integer;
    { Always empty. This path does not record a cost. }
    Cost: String;
  End;

Function DetectClaudeExecutable: String;
Function ClaudeRuntimeFromBrowsedPath(Const BrowsedPath: String): String;
Function ApplyClaudeRuntime(Connection: TAssistantConnection; Const ExecutablePath: String;
  Out ErrorText: String): Boolean;
Function ClaudePermissionMode(Const HelpText, ApprovalMode: String): String;
Function PermissionFlagRefused(Const ProgramText: String): Boolean;
Procedure AppendClaudeTurnArguments(Const Model, PermissionMode: String; Args: TStrings);
Function ParseClaudeTurnResult(Const JsonText: String; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Function StartClaudeSignIn(Const Executable: String; Out ErrorText: String): Boolean;
/// One captured turn. The form passes the shared user text. This path does not
/// receive this assistant's tool list, skill bodies, or transcript compactor.
Function RunClaudeTurn(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
  Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;

Type
  TClaudeRunSnapshot = Record
    Content, ErrorText: String;
    Done: Boolean;
  End;

  { Worker for one Claude Code turn. The IDE timer reads Snapshot. Stop sets Cancel. }
  TAssistantClaudeRun = Class(TThread)
  Private
    FLock: TRTLCriticalSection;
    FExecutable, FModel, FApproval, FPrompt, FDirectory: String;
    FTimeoutMs: Integer;
    FSnapshot: TClaudeRunSnapshot;
    FCancelled: LongInt;
    Function Cancelled: Boolean;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
      TimeoutMs: Integer = 0);
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Snapshot: TClaudeRunSnapshot;
  End;

Implementation

Uses
  Process, FileUtil, LazFileUtils, fpjson
  {$IFDEF UNIX}, BaseUnix, Unix{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

Const
  ClaudeHelpTimeoutMs = 8000;
  ClaudeTurnTimeoutMs = 120000;

Procedure ClearTurn(Out Turn: TClaudeTurnResult);
Begin
  Turn.Text := '';
  Turn.UsageState := ClaudeUsageUnavailable;
  Turn.InputTokens := 0;
  Turn.OutputTokens := 0;
  Turn.Cost := '';
End;

Function BoundText(Const Value: String): String;
Begin
  Result := Trim(Value);
  If Length(Result) > 1000 Then
    Result := Copy(Result, 1, 1000);
End;

Function ContainsToken(Const Text, Token: String): Boolean;
Var
  StartAt, Found, TokenLen: Integer;
  Before, After: Char;
Begin
  Result := False;
  TokenLen := Length(Token);
  If (TokenLen = 0) Or (Text = '') Then
    Exit;
  StartAt := 1;
  While StartAt <= Length(Text) - TokenLen + 1 Do
    Begin
      Found := Pos(Token, Copy(Text, StartAt, MaxInt));
      If Found = 0 Then
        Exit;
      Found := StartAt + Found - 1;
      If Found = 1 Then
        Before := ' '
      Else
        Before := Text[Found - 1];
      If Found + TokenLen > Length(Text) Then
        After := ' '
      Else
        After := Text[Found + TokenLen];
      If Not (Before In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) And
        Not (After In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) Then
        Exit(True);
      StartAt := Found + 1;
    End;
End;

Function DetectClaudeExecutable: String;
Begin
  Result := FindDefaultExecutablePath('claude');
End;

Function ClaudeRuntimeFromBrowsedPath(Const BrowsedPath: String): String;
Var
  Path: String;
Begin
  Result := '';
  Path := Trim(BrowsedPath);
  If Path = '' Then
    Exit;
  Path := ExpandFileName(Path);
  If FileIsExecutable(Path) Then
    Result := Path;
End;

Function ApplyClaudeRuntime(Connection: TAssistantConnection; Const ExecutablePath: String;
  Out ErrorText: String): Boolean;
Var
  Stored: String;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(Connection) Then
    Begin
      ErrorText := 'A connection is required.';
      Exit;
    End;
  Stored := ClaudeRuntimeFromBrowsedPath(ExecutablePath);
  If Stored = '' Then
    Begin
      ErrorText := 'The selected file is not an executable.';
      Exit;
    End;
  Connection.Runtime := Stored;
  Result := True;
End;

Function ClaudePermissionMode(Const HelpText, ApprovalMode: String): String;
Var
  Approval: String;
Begin
  Result := '';
  If Pos('permission-mode', LowerCase(HelpText)) = 0 Then
    Exit;
  Approval := LowerCase(Trim(ApprovalMode));
  If Approval = 'auto' Then
    Begin
      If ContainsToken(HelpText, 'acceptEdits') Then
        Result := 'acceptEdits'
      Else If ContainsToken(HelpText, 'accept-edits') Then
        Result := 'accept-edits';
    End
  Else If Approval = 'always' Then
    Begin
      If ContainsToken(HelpText, 'bypassPermissions') Then
        Result := 'bypassPermissions'
      Else If ContainsToken(HelpText, 'bypass') Then
        Result := 'bypass';
    End
  Else
    Begin
      If ContainsToken(HelpText, 'ask') Then
        Result := 'ask'
      Else If ContainsToken(HelpText, 'default') Then
        Result := 'default';
    End;
End;

Function PermissionFlagRefused(Const ProgramText: String): Boolean;
Var
  Lower: String;
Begin
  Lower := LowerCase(ProgramText);
  Result := (Pos('permission-mode', Lower) > 0) And
    ((Pos('unknown', Lower) > 0) Or (Pos('unrecognized', Lower) > 0) Or
    (Pos('unexpected', Lower) > 0) Or (Pos('invalid', Lower) > 0) Or (Pos('refused', Lower) > 0));
End;

Procedure AppendClaudeTurnArguments(Const Model, PermissionMode: String; Args: TStrings);
Begin
  If Not Assigned(Args) Then
    Exit;
  Args.Add('-p');
  Args.Add('--output-format');
  Args.Add('json');
  Args.Add('--model');
  Args.Add(Model);
  If PermissionMode <> '' Then
    Begin
      Args.Add('--permission-mode');
      Args.Add(PermissionMode);
    End;
End;

Function JsonObjectText(Const Output: String): String;
Var
  StartAt, EndAt, I: Integer;
Begin
  Result := Trim(Output);
  StartAt := Pos('{', Result);
  EndAt := 0;
  For I := Length(Result) DownTo 1 Do
    If Result[I] = '}' Then
      Begin
        EndAt := I;
        Break;
      End;
  If (StartAt > 0) And (EndAt >= StartAt) Then
    Result := Copy(Result, StartAt, EndAt - StartAt + 1);
End;

Function ParseClaudeTurnResult(Const JsonText: String; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Usage: TJSONObject;
  InputNode, OutputNode: TJSONData;
Begin
  Result := False;
  ErrorText := '';
  ClearTurn(Turn);
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonObjectText(JsonText));
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Claude Code did not return a JSON result.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Claude Code did not return a JSON result.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Root.Find('result') Is TJSONString Then
      Turn.Text := Root.Get('result', '')
    Else If Root.Find('text') Is TJSONString Then
      Turn.Text := Root.Get('text', '');
    { An error result is not an assistant answer. The form classifies that text. }
    If Root.Get('is_error', False) Then
      Begin
        ErrorText := BoundText(Turn.Text);
        If ErrorText = '' Then
          ErrorText := BoundText(JsonText);
        If ErrorText = '' Then
          ErrorText := 'Claude Code did not complete the turn.';
        ClearTurn(Turn);
        Exit;
      End;
    Turn.Cost := '';
    Usage := Nil;
    If Root.Find('usage') Is TJSONObject Then
      Usage := TJSONObject(Root.Find('usage'));
    If Assigned(Usage) Then
      Begin
        InputNode := Usage.Find('input_tokens');
        OutputNode := Usage.Find('output_tokens');
        If Assigned(InputNode) And Assigned(OutputNode) And (InputNode.JSONType = jtNumber) And
          (OutputNode.JSONType = jtNumber) Then
          Begin
            Turn.UsageState := ClaudeUsageReported;
            Turn.InputTokens := InputNode.AsInteger;
            Turn.OutputTokens := OutputNode.AsInteger;
          End;
      End;
    Turn.Cost := '';
    Result := True;
  Finally
    Data.Free;
  End;
End;

Type
  TClaudeStopQuery = Function: Boolean Of Object;

Function RunCaptured(Const Executable, WorkingDirectory: String; Args: TStrings; Const InputText: String;
  TimeoutMs: Integer; Out StdoutText, StderrText: String; Out ExitCode: Integer; Out ErrorText: String;
  StopQuery: TClaudeStopQuery = Nil): Boolean;
Var
  Proc: TProcess;
  Buffer: Array[0..4095] Of Byte;
  Started: QWord;
  Count, Wrote, Offset: Integer;
  Piece: String;
Begin
  Result := False;
  StdoutText := '';
  StderrText := '';
  ExitCode := -1;
  ErrorText := '';
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'Claude Code was not found. Browse to the installed executable.';
      Exit;
    End;
  FillChar(Buffer, SizeOf(Buffer), 0);
  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := Executable;
    If WorkingDirectory <> '' Then
      Proc.CurrentDirectory := WorkingDirectory;
    Proc.Options := [poUsePipes, poNoConsole];
    If Assigned(Args) Then
      Proc.Parameters.Assign(Args);
    Try
      Proc.Execute;
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Could not start Claude Code.';
          Exit;
        End;
    End;
    Offset := 1;
    While Offset <= Length(InputText) Do
      Begin
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            If Proc.Running Then
              Proc.Terminate(1);
            Proc.WaitOnExit(2000);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        Wrote := Proc.Input.Write(InputText[Offset], Length(InputText) - Offset + 1);
        If Wrote <= 0 Then
          Break;
        Inc(Offset, Wrote);
      End;
    Proc.CloseInput;
    Started := GetTickCount64;
    While Proc.Running Or (Proc.Output.NumBytesAvailable > 0) Or (Proc.Stderr.NumBytesAvailable > 0) Do
      Begin
        If Proc.Output.NumBytesAvailable > 0 Then
          Begin
            Count := Proc.Output.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then
              Break;
            SetString(Piece, PAnsiChar(@Buffer[0]), Count);
            StdoutText := StdoutText + Piece;
          End;
        If Proc.Stderr.NumBytesAvailable > 0 Then
          Begin
            Count := Proc.Stderr.Read(Buffer, SizeOf(Buffer));
            If Count <= 0 Then
              Break;
            SetString(Piece, PAnsiChar(@Buffer[0]), Count);
            StderrText := StderrText + Piece;
          End;
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            If Proc.Running Then
              Proc.Terminate(1);
            Proc.WaitOnExit(2000);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        If GetTickCount64 - Started >= TimeoutMs Then
          Begin
            If Proc.Running Then
              Proc.Terminate(1);
            Proc.WaitOnExit(2000);
            ErrorText := 'Claude Code timed out.';
            Exit;
          End;
        If Proc.Running And (Proc.Output.NumBytesAvailable = 0) And (Proc.Stderr.NumBytesAvailable = 0) Then
          Sleep(5);
      End;
    ExitCode := Proc.ExitStatus;
    Result := True;
  Finally
    Proc.Free;
  End;
End;

Function ProbeHelp(Const Executable: String; StopQuery: TClaudeStopQuery = Nil): String;
Var
  Args: TStringList;
  StdoutText, StderrText, ErrorText: String;
  ExitCode: Integer;
Begin
  Result := '';
  If Assigned(StopQuery) And StopQuery() Then
    Exit;
  Args := TStringList.Create;
  Try
    Args.Add('--help');
    If RunCaptured(Executable, '', Args, '', ClaudeHelpTimeoutMs, StdoutText, StderrText, ExitCode, ErrorText,
      StopQuery) Then
      Result := StdoutText + LineEnding + StderrText;
  Finally
    Args.Free;
  End;
End;

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
  SetLength(Owned, 0);
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

{$IFDEF WINDOWS}
Function SpawnDetached(Const Executable: String; Const Args: Array Of String; Out ErrorText: String): Boolean;
Var
  Startup: TStartupInfo;
  ProcessInfo: TProcessInformation;
  Command: String;
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  FillChar(Startup, SizeOf(Startup), 0);
  Startup.cb := SizeOf(Startup);
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  Command := '"' + Executable + '"';
  For I := 0 To High(Args) Do
    Command := Command + ' "' + Args[I] + '"';
  If Not CreateProcess(Nil, PChar(Command), Nil, Nil, False, CREATE_NEW_CONSOLE, Nil, Nil, Startup, ProcessInfo) Then
    Begin
      ErrorText := 'Could not start Claude Code sign-in.';
      Exit;
    End;
  CloseHandle(ProcessInfo.hProcess);
  CloseHandle(ProcessInfo.hThread);
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

Function StartClaudeSignIn(Const Executable: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'Claude Code was not found. Browse to the installed executable.';
      Exit;
    End;
  { Start the program's own login. Do not read its output or account files. }
  Result := SpawnDetached(Executable, ['auth', 'login'], ErrorText);
End;

Function RunClaudeTurnStopped(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
  TimeoutMs: Integer; StopQuery: TClaudeStopQuery; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Var
  Args: TStringList;
  Mode, HelpText, StdoutText, StderrText, ProgramText: String;
  ExitCode: Integer;
Begin
  Result := False;
  ErrorText := '';
  ClearTurn(Turn);
  If Assigned(StopQuery) And StopQuery() Then
    Begin
      ErrorText := 'Cancelled.';
      Exit;
    End;
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'Claude Code was not found. Browse to the installed executable.';
      Exit;
    End;
  If (WorkingDirectory <> '') And (Not DirectoryExists(WorkingDirectory)) Then
    Begin
      ErrorText := 'The working directory does not exist.';
      Exit;
    End;
  If Trim(Model) = '' Then
    Begin
      ErrorText := 'This connection has no model.';
      Exit;
    End;
  If TimeoutMs < 1 Then
    TimeoutMs := ClaudeTurnTimeoutMs;
  HelpText := ProbeHelp(Executable, StopQuery);
  If Assigned(StopQuery) And StopQuery() Then
    Begin
      ErrorText := 'Cancelled.';
      Exit;
    End;
  Mode := ClaudePermissionMode(HelpText, ApprovalMode);
  Args := TStringList.Create;
  Try
    AppendClaudeTurnArguments(Model, Mode, Args);
    If Not RunCaptured(Executable, WorkingDirectory, Args, Prompt, TimeoutMs, StdoutText, StderrText,
      ExitCode, ErrorText, StopQuery) Then
      Exit;
  Finally
    Args.Free;
  End;
  ProgramText := StderrText;
  If Trim(ProgramText) = '' Then
    ProgramText := StdoutText;
  { One attempt. A refused permission flag is reported and not tried again. }
  If PermissionFlagRefused(StderrText + LineEnding + StdoutText) Then
    Begin
      ErrorText := BoundText(ProgramText);
      If ErrorText = '' Then
        ErrorText := 'Claude Code refused the permission mode flag.';
      Exit;
    End;
  If ExitCode <> 0 Then
    Begin
      ErrorText := BoundText(ProgramText);
      If ErrorText = '' Then
        ErrorText := 'Claude Code did not complete the turn.';
      Exit;
    End;
  If Not ParseClaudeTurnResult(StdoutText, Turn, ErrorText) Then
    Exit;
  Result := True;
End;

Function RunClaudeTurn(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
  Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Begin
  Result := RunClaudeTurnStopped(Executable, Model, ApprovalMode, Prompt, WorkingDirectory, ClaudeTurnTimeoutMs, Nil,
    Turn, ErrorText);
End;

Function TAssistantClaudeRun.Cancelled: Boolean;
Begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
End;

Constructor TAssistantClaudeRun.Create(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
  TimeoutMs: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FExecutable := Executable;
  FModel := Model;
  FApproval := ApprovalMode;
  FPrompt := Prompt;
  FDirectory := WorkingDirectory;
  If TimeoutMs < 1 Then
    FTimeoutMs := ClaudeTurnTimeoutMs
  Else
    FTimeoutMs := TimeoutMs;
  FCancelled := 0;
  FSnapshot.Content := '';
  FSnapshot.ErrorText := '';
  FSnapshot.Done := False;
End;

Destructor TAssistantClaudeRun.Destroy;
Begin
  Cancel;
  { A suspended thread must be started before WaitFor, or Destroy hangs.
    Execute exits immediately once Cancel has been set. }
  If Suspended Then
    Start;
  WaitFor;
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TAssistantClaudeRun.Cancel;
Begin
  InterlockedExchange(FCancelled, 1);
End;

Function TAssistantClaudeRun.Snapshot: TClaudeRunSnapshot;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FSnapshot;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAssistantClaudeRun.Execute;
Var
  Turn: TClaudeTurnResult;
  ErrorText: String;
Begin
  ErrorText := '';
  ClearTurn(Turn);
  Try
    If Cancelled Or Terminated Then
      ErrorText := 'Cancelled.'
    Else If Not RunClaudeTurnStopped(FExecutable, FModel, FApproval, FPrompt, FDirectory, FTimeoutMs, @Cancelled,
      Turn, ErrorText) Then
      Begin
        If ErrorText = '' Then
          ErrorText := 'Claude Code did not complete the turn.';
      End
    Else If Cancelled Or Terminated Then
      ErrorText := 'Cancelled.';
  Except
    On E: Exception Do
      Begin
        If Cancelled Or Terminated Then
          ErrorText := 'Cancelled.'
        Else If E.Message <> '' Then
          ErrorText := E.Message
        Else
          ErrorText := E.ClassName;
      End;
  End;
  EnterCriticalSection(FLock);
  Try
    If ErrorText = '' Then
      FSnapshot.Content := Turn.Text
    Else
      FSnapshot.ErrorText := ErrorText;
    FSnapshot.Done := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

End.
