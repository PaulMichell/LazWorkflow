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
  Classes;

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
/// Claude Code permission mode for an approval setting. Empty means the program default, which refuses
/// anything that needs approval in print mode.
Function ClaudePermissionMode(Const ApprovalMode: String): String;
/// True when Claude Code's stderr says it rejected the --permission-mode argument.
Function PermissionFlagRefused(Const ErrorOutput: String): Boolean;
Procedure AppendClaudeTurnArguments(Const Model, PermissionMode: String; Args: TStrings);
Function ParseClaudeTurnResult(Const JsonText: String; Out Turn: TClaudeTurnResult; Out ErrorText: String): Boolean;
Function StartClaudeSignIn(Const Executable: String; Out ErrorText: String): Boolean;

Type
  { The billing fields of claude auth status. Email and organisation are never read. }
  TClaudeAccount = Record
    SignedIn: Boolean;
    AuthMethod: String;
    ApiProvider: String;
    KeySource: String;
    SubscriptionType: String;
  End;

/// Copies NAME=VALUE lines from Source without the variables that move Claude Code onto metered billing.
Procedure FilterClaudeEnvironment(Source, Environment: TStrings);
/// FilterClaudeEnvironment applied to this process environment.
Procedure BuildClaudeEnvironment(Environment: TStrings);
/// Reads the billing fields from claude auth status --json output. False when the text is not that report.
Function ParseClaudeAccount(Const JsonText: String; Out Account: TClaudeAccount): Boolean;
/// Runs the program's own status report in the scrubbed environment.
Function ReadClaudeAccount(Const Executable: String; Out Account: TClaudeAccount; Out ErrorText: String): Boolean;
/// True only for a signed-in claude.ai subscription on the first-party service.
Function ClaudeAccountIsSubscription(Const Account: TClaudeAccount): Boolean;
/// One sentence for the settings page, or the reason a turn was refused.
Function ClaudeAccountText(Const Account: TClaudeAccount): String;
/// The next turn checks the account again. Call after saving settings or starting a sign-in.
Procedure ForgetClaudeAccounts;

Type
  TClaudeRunSnapshot = Record
    Content, ErrorText: String;
    { The claude process was started. A failure after that may follow edits or commands, so it is not replayed. }
    Started: Boolean;
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
    Procedure ProcessStarted;
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
  SysUtils, Process, Pipes, FileUtil, LazFileUtils, fpjson, jsonparser, ProcessSession;

Const
  ClaudeTurnTimeoutMs = 120000;
  ClaudeStatusTimeoutMs = 15000;
  { Each of these selects an API key, a gateway, or a cloud provider instead of the subscription. }
  ClaudeMeteredVariables: Array[0..5] Of String = ('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL',
    'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY');

Var
  { Executables whose account was confirmed as a subscription in this IDE session. }
  ConfirmedExecutables: TStringList;
  AccountLock: TRTLCriticalSection;

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

Function ClaudePermissionMode(Const ApprovalMode: String): String;
Var
  Approval: String;
Begin
  { Fixed values from the documented choices. The local 'auto' is not Claude Code's own auto mode. }
  Approval := LowerCase(Trim(ApprovalMode));
  If Approval = 'auto' Then
    Result := 'acceptEdits'
  Else If Approval = 'always' Then
    Result := 'bypassPermissions'
  Else If Approval = 'plan' Then
    Result := 'plan'
  Else
    Result := '';
End;

Function PermissionFlagRefused(Const ErrorOutput: String): Boolean;
Var
  Lowered: String;
Begin
  { Commander's wording: option '--permission-mode <mode>' argument 'x' is invalid. }
  Lowered := LowerCase(ErrorOutput);
  Result := (Pos('--permission-mode', Lowered) > 0) And
    ((Pos('is invalid', Lowered) > 0) Or (Pos('unknown option', Lowered) > 0));
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
  TClaudeStartedEvent = Procedure Of Object;

Procedure DrainPipe(Pipe: TInputPipeStream; Buffer: TStream);
Var
  Chunk: Array[0..4095] Of Byte;
  Count: Integer;
Begin
  While Pipe.NumBytesAvailable > 0 Do
    Begin
      Count := Pipe.Read(Chunk, SizeOf(Chunk));
      If Count <= 0 Then
        Exit;
      Buffer.WriteBuffer(Chunk, Count);
    End;
End;

Function StreamText(Buffer: TMemoryStream): String;
Begin
  SetString(Result, PAnsiChar(Buffer.Memory), Buffer.Size);
End;

{$IF FPC_FULLVERSION >= 30301}
{ FPC 3.3.1 TProcess: once Input has been used, its stream owns the pipe and CloseInput no longer closes it, so
  claude would wait for the end of the prompt until the turn limit. A file as standard input needs no close,
  cannot block on a full pipe, and cannot raise SIGPIPE. }
Function WritePromptFile(Const InputText: String; Out PromptFile, ErrorText: String): Boolean;
Var
  Identifier: TGUID;
  Handle: THandle;
  Offset, Written: Integer;
Begin
  Result := False;
  PromptFile := '';
  ErrorText := '';
  If CreateGUID(Identifier) <> 0 Then
    Begin
      ErrorText := 'Could not prepare the prompt for Claude Code.';
      Exit;
    End;
  PromptFile := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'lazarus-claude-' +
    LowerCase(Copy(GUIDToString(Identifier), 2, 36)) + '.txt';
  { Owner-only. The prompt can hold project source. }
  Handle := FileCreate(PromptFile, fmShareExclusive, &600);
  If Handle = THandle(-1) Then
    Begin
      ErrorText := 'Could not prepare the prompt for Claude Code.';
      PromptFile := '';
      Exit;
    End;
  Try
    Offset := 1;
    While Offset <= Length(InputText) Do
      Begin
        Written := FileWrite(Handle, InputText[Offset], Length(InputText) - Offset + 1);
        If Written <= 0 Then
          Begin
            ErrorText := 'Could not prepare the prompt for Claude Code.';
            Exit;
          End;
        Inc(Offset, Written);
      End;
    Result := True;
  Finally
    FileClose(Handle);
    If Not Result Then
      Begin
        DeleteFile(PromptFile);
        PromptFile := '';
      End;
  End;
End;
{$ELSE}
{ False when the pipe is closed. An early exit closes it; the reason is then read from stderr. }
Function WriteInput(ClaudeProcess: TProcess; Const InputText: String; Offset: Integer; Out Written: Integer): Boolean;
{$IFDEF UNIX}
Var
  Closed, Again: Boolean;
  WriteError: String;
{$ENDIF}
Begin
  Result := False;
  Written := 0;
  {$IFDEF UNIX}
  { A plain write to a pipe whose reader has exited raises SIGPIPE in the IDE process. }
  Repeat
    If Not WritePipeNoSignal(ClaudeProcess.Input.Handle, InputText[Offset], Length(InputText) - Offset + 1, Written,
      Closed, Again, WriteError) Then
      Exit;
  Until Not Again;
  Result := (Not Closed) And (Written > 0);
  {$ELSE}
  Written := ClaudeProcess.Input.Write(InputText[Offset], Length(InputText) - Offset + 1);
  Result := Written > 0;
  {$ENDIF}
End;
{$ENDIF}

Function RunCaptured(Const Executable, WorkingDirectory: String; Args, Environment: TStrings; Const InputText: String;
  TimeoutMs: Integer; Out StdoutText, StderrText: String; Out ExitCode: Integer; Out ErrorText: String;
  StopQuery: TClaudeStopQuery = Nil; OnStarted: TClaudeStartedEvent = Nil): Boolean;
Var
  ClaudeProcess: TProcess;
  StdoutBuffer, StderrBuffer: TMemoryStream;
  Started: QWord;
  {$IF FPC_FULLVERSION >= 30301}
  PromptFile: String;
  {$ELSE}
  Offset, Written: Integer;
  {$ENDIF}
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
  {$IF FPC_FULLVERSION >= 30301}
  PromptFile := '';
  If (InputText <> '') And (Not WritePromptFile(InputText, PromptFile, ErrorText)) Then
    Exit;
  {$ENDIF}
  StdoutBuffer := TMemoryStream.Create;
  StderrBuffer := TMemoryStream.Create;
  ClaudeProcess := TProcess.Create(Nil);
  Try
    ClaudeProcess.Executable := Executable;
    If WorkingDirectory <> '' Then
      ClaudeProcess.CurrentDirectory := WorkingDirectory;
    ClaudeProcess.Options := [poUsePipes, poNoConsole];
    {$IF FPC_FULLVERSION >= 30301}
    { After Options: poUsePipes resets every descriptor to a pipe. }
    If PromptFile <> '' Then
      Begin
        ClaudeProcess.InputDescriptor.IOType := iotFile;
        ClaudeProcess.InputDescriptor.FileName := PromptFile;
      End
    Else
      ClaudeProcess.InputDescriptor.IOType := iotNull;
    {$ENDIF}
    If Assigned(Args) Then
      ClaudeProcess.Parameters.Assign(Args);
    If Assigned(Environment) Then
      ClaudeProcess.Environment.Assign(Environment);
    { Own process group, so a stop also ends the commands and servers Claude Code started. }
    StartInOwnSession(ClaudeProcess);
    Try
      ClaudeProcess.Execute;
    Except
      On EProcess Do
        Begin
          ErrorText := 'Could not start Claude Code.';
          Exit;
        End;
    End;
    If Assigned(OnStarted) Then
      OnStarted();
    {$IF FPC_FULLVERSION < 30301}
    Offset := 1;
    While Offset <= Length(InputText) Do
      Begin
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            TerminateSession(ClaudeProcess);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        If Not WriteInput(ClaudeProcess, InputText, Offset, Written) Then
          Break;
        Inc(Offset, Written);
      End;
    ClaudeProcess.CloseInput;
    {$ENDIF}
    Started := GetTickCount64;
    While ClaudeProcess.Running Or (ClaudeProcess.Output.NumBytesAvailable > 0) Or
      (ClaudeProcess.Stderr.NumBytesAvailable > 0) Do
      Begin
        DrainPipe(ClaudeProcess.Output, StdoutBuffer);
        DrainPipe(ClaudeProcess.Stderr, StderrBuffer);
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            TerminateSession(ClaudeProcess);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        If GetTickCount64 - Started >= QWord(TimeoutMs) Then
          Begin
            TerminateSession(ClaudeProcess);
            { Not a network timeout. Recovery must not replay a turn that may have changed files. }
            ErrorText := 'Claude Code did not finish within the turn limit.';
            Exit;
          End;
        If ClaudeProcess.Running And (ClaudeProcess.Output.NumBytesAvailable = 0) And
          (ClaudeProcess.Stderr.NumBytesAvailable = 0) Then
          Sleep(5);
      End;
    StdoutText := StreamText(StdoutBuffer);
    StderrText := StreamText(StderrBuffer);
    If ProcessWasSignalled(ClaudeProcess) Then
      Begin
        ErrorText := 'Claude Code was stopped by a signal.';
        Exit;
      End;
    ExitCode := ClaudeProcess.ExitCode;
    Result := True;
  Finally
    ClaudeProcess.Free;
    StderrBuffer.Free;
    StdoutBuffer.Free;
    {$IF FPC_FULLVERSION >= 30301}
    If PromptFile <> '' Then
      DeleteFile(PromptFile);
    {$ENDIF}
  End;
End;

Function StartClaudeSignIn(Const Executable: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'Claude Code was not found. Browse to the installed executable.';
      Exit;
    End;
  { Start the program's own login on the subscription. Do not read its output or account files. }
  ForgetClaudeAccounts;
  Result := SpawnDetached(Executable, ['auth', 'login', '--claudeai'], ErrorText);
End;

Procedure FilterClaudeEnvironment(Source, Environment: TStrings);
Var
  I, J: Integer;
  VariableName: String;
  Metered: Boolean;
Begin
  If (Not Assigned(Source)) Or (Not Assigned(Environment)) Then
    Exit;
  Environment.Clear;
  For I := 0 To Source.Count - 1 Do
    Begin
      VariableName := Copy(Source[I], 1, Pos('=', Source[I]) - 1);
      Metered := False;
      For J := Low(ClaudeMeteredVariables) To High(ClaudeMeteredVariables) Do
        If CompareText(VariableName, ClaudeMeteredVariables[J]) = 0 Then
          Metered := True;
      If Not Metered Then
        Environment.Add(Source[I]);
    End;
End;

Procedure BuildClaudeEnvironment(Environment: TStrings);
Var
  Source: TStringList;
  I: Integer;
Begin
  If Not Assigned(Environment) Then
    Exit;
  Source := TStringList.Create;
  Try
    For I := 1 To GetEnvironmentVariableCount Do
      Source.Add(GetEnvironmentString(I));
    FilterClaudeEnvironment(Source, Environment);
  Finally
    Source.Free;
  End;
End;

Function JsonStringField(Root: TJSONObject; Const Key: String): String;
Begin
  { A missing subscription is a JSON null, not a string. }
  If Root.Find(Key) Is TJSONString Then
    Result := Root.Get(Key, '')
  Else
    Result := '';
End;

Function ParseClaudeAccount(Const JsonText: String; Out Account: TClaudeAccount): Boolean;
Var
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Result := False;
  Account := Default(TClaudeAccount);
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonObjectText(JsonText));
    Except
      On EParserError Do
        Exit;
    End;
    If Not (Data Is TJSONObject) Then
      Exit;
    Root := TJSONObject(Data);
    If Not (Root.Find('loggedIn') Is TJSONBoolean) Then
      Exit;
    Account.SignedIn := Root.Get('loggedIn', False);
    Account.AuthMethod := JsonStringField(Root, 'authMethod');
    Account.ApiProvider := JsonStringField(Root, 'apiProvider');
    Account.KeySource := JsonStringField(Root, 'apiKeySource');
    Account.SubscriptionType := JsonStringField(Root, 'subscriptionType');
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function ReadClaudeAccount(Const Executable: String; Out Account: TClaudeAccount; Out ErrorText: String): Boolean;
Var
  Args, Environment: TStringList;
  StdoutText, StderrText: String;
  ExitCode: Integer;
Begin
  Result := False;
  Account := Default(TClaudeAccount);
  ErrorText := '';
  Args := TStringList.Create;
  Environment := TStringList.Create;
  Try
    Args.Add('auth');
    Args.Add('status');
    Args.Add('--json');
    BuildClaudeEnvironment(Environment);
    If Not RunCaptured(Executable, '', Args, Environment, '', ClaudeStatusTimeoutMs, StdoutText, StderrText, ExitCode,
      ErrorText) Then
      Exit;
    If Not ParseClaudeAccount(StdoutText, Account) Then
      Begin
        ErrorText := 'Claude Code did not report its sign-in state.';
        Exit;
      End;
    Result := True;
  Finally
    Environment.Free;
    Args.Free;
  End;
End;

Function ClaudeAccountIsSubscription(Const Account: TClaudeAccount): Boolean;
Begin
  Result := Account.SignedIn And (Account.AuthMethod = 'claude.ai') And (Account.ApiProvider = 'firstParty') And
    (Account.SubscriptionType <> '');
End;

Function ClaudeAccountText(Const Account: TClaudeAccount): String;
Begin
  If ClaudeAccountIsSubscription(Account) Then
    Result := 'Signed in with a Claude ' + UpperCase(Copy(Account.SubscriptionType, 1, 1)) +
      Copy(Account.SubscriptionType, 2, MaxInt) + ' subscription.'
  Else If Not Account.SignedIn Then
    Result := 'Claude Code is not signed in. Use Sign in with Claude.'
  Else If Account.ApiProvider <> 'firstParty' Then
    Result := 'Claude Code is set to use ' + Account.ApiProvider + ', not a Claude subscription. ' +
      'This assistant does not send Claude turns that are billed per use.'
  Else If Account.KeySource <> '' Then
    Result := 'Claude Code is using an API key from ' + Account.KeySource + ', which is billed per use. ' +
      'Remove it from Claude Code settings, or sign in with Claude.'
  Else
    Result := 'Claude Code is not using a Claude subscription (found ' + Account.AuthMethod + '). ' +
      'Use Sign in with Claude.';
End;

Procedure ForgetClaudeAccounts;
Begin
  EnterCriticalSection(AccountLock);
  Try
    ConfirmedExecutables.Clear;
  Finally
    LeaveCriticalSection(AccountLock);
  End;
End;

Function ClaudeAccountConfirmed(Const Executable: String): Boolean;
Begin
  EnterCriticalSection(AccountLock);
  Try
    Result := ConfirmedExecutables.IndexOf(Executable) >= 0;
  Finally
    LeaveCriticalSection(AccountLock);
  End;
End;

Procedure ConfirmClaudeAccount(Const Executable: String);
Begin
  EnterCriticalSection(AccountLock);
  Try
    If ConfirmedExecutables.IndexOf(Executable) < 0 Then
      ConfirmedExecutables.Add(Executable);
  Finally
    LeaveCriticalSection(AccountLock);
  End;
End;

{ Checked once per executable per IDE session, then trusted. The turn itself runs in the same scrubbed environment. }
Function EnsureClaudeSubscription(Const Executable: String; Out ErrorText: String): Boolean;
Var
  Account: TClaudeAccount;
Begin
  Result := ClaudeAccountConfirmed(Executable);
  ErrorText := '';
  If Result Then
    Exit;
  If Not ReadClaudeAccount(Executable, Account, ErrorText) Then
    Exit;
  If Not ClaudeAccountIsSubscription(Account) Then
    Begin
      ErrorText := ClaudeAccountText(Account);
      Exit;
    End;
  ConfirmClaudeAccount(Executable);
  Result := True;
End;

Function RunClaudeTurnStopped(Const Executable, Model, ApprovalMode, Prompt, WorkingDirectory: String;
  TimeoutMs: Integer; StopQuery: TClaudeStopQuery; OnStarted: TClaudeStartedEvent; Out Turn: TClaudeTurnResult;
  Out ErrorText: String): Boolean;
Var
  Args, Environment: TStringList;
  StdoutText, StderrText, ProgramText, ResultError: String;
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
  If Not EnsureClaudeSubscription(Executable, ErrorText) Then
    Exit;
  If Assigned(StopQuery) And StopQuery() Then
    Begin
      ErrorText := 'Cancelled.';
      Exit;
    End;
  Args := TStringList.Create;
  Environment := TStringList.Create;
  Try
    AppendClaudeTurnArguments(Model, ClaudePermissionMode(ApprovalMode), Args);
    BuildClaudeEnvironment(Environment);
    If Not RunCaptured(Executable, WorkingDirectory, Args, Environment, Prompt, TimeoutMs, StdoutText, StderrText,
      ExitCode, ErrorText, StopQuery, OnStarted) Then
      Exit;
  Finally
    Environment.Free;
    Args.Free;
  End;
  If ExitCode <> 0 Then
    Begin
      { The answer on stdout is never searched for flag errors. Only stderr says why the program refused. }
      If PermissionFlagRefused(StderrText) Then
        Begin
          ErrorText := 'Claude Code refused the permission mode flag. ' + BoundText(StderrText);
          Exit;
        End;
      { An error result on stdout says more than the exit code. }
      If (Not ParseClaudeTurnResult(StdoutText, Turn, ResultError)) And (ResultError <> '') And
        (ResultError <> 'Claude Code did not return a JSON result.') Then
        Begin
          ErrorText := ResultError;
          Exit;
        End;
      ProgramText := StderrText;
      If Trim(ProgramText) = '' Then
        ProgramText := StdoutText;
      ErrorText := BoundText(ProgramText);
      If ErrorText = '' Then
        ErrorText := 'Claude Code did not complete the turn.';
      ClearTurn(Turn);
      Exit;
    End;
  If Not ParseClaudeTurnResult(StdoutText, Turn, ErrorText) Then
    Exit;
  Result := True;
End;

Function TAssistantClaudeRun.Cancelled: Boolean;
Begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
End;

Procedure TAssistantClaudeRun.ProcessStarted;
Begin
  EnterCriticalSection(FLock);
  Try
    FSnapshot.Started := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
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
  FSnapshot.Started := False;
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
      @ProcessStarted, Turn, ErrorText) Then
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

Initialization

InitCriticalSection(AccountLock);
ConfirmedExecutables := TStringList.Create;

Finalization

FreeAndNil(ConfirmedExecutables);
DoneCriticalSection(AccountLock);

End.
