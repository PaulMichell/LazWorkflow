Unit ClaudeCaptureProgram;

{ The Claude Code image capture program (c) 2026 Michell Computing.

  Tests/Fixtures/Claude/CaptureClaudeImages.lpr calls RunCaptureProgram. It starts the installed claude program on
  the user's subscription and writes the raw output and a summary to --output-dir, which belongs under Temporary/.
  It never reads Claude sign-in files: the account is checked through ReadClaudeAccount, which runs claude auth
  status, and every turn gets BuildClaudeEnvironment's environment. It never passes --bare, --max-budget-usd or
  --betas. Each turn runs in an empty scratch directory in the system temporary directory, so Claude Code finds no
  project instructions above it. Started with --mcp-server <log file>, the same program is the stdio MCP server. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

/// The whole capture program. Returns the process exit code.
Function RunCaptureProgram: Integer;

Implementation

Uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  Classes, SysUtils, base64, AssistantClaudeClient, ClaudeCaptureSupport;

Const
  DefaultModel = 'haiku';
  DefaultTimeoutSeconds = 300;
  StdinOpenWaitMs = 15000;
  ImageInputPrompt = 'Describe the attached picture in one sentence: name the shape, its colour and the background colour.';
  ImageResumePrompt = 'No new picture is attached. What shape and colours were in the picture I sent in my previous message? ' +
    'Answer in one sentence. If you cannot see an earlier picture, say so.';
  MCPImagePrompt = 'Call the ' + CaptureToolName + ' tool once. Then describe the picture it returned in one sentence: ' +
    'name the shape, its colour and the background colour. If the tool gave you no picture, say so.';
  StdinOpenPrompt = 'Reply with the single word ready.';
  LimitsPrompt = 'Describe the attached picture in one sentence.';
  UsageText = 'Usage: CaptureClaudeImages --output-dir <directory> [--claude <path>] [--model <name>] [--timeout <seconds>]' +
    LineEnding + '         [--case image-input|image-resume|mcp-image|stdin-open|limits-large|limits-format]...';

Type
  TCaptureSettings = Record
    Executable, Model, OutputDir, WorkDir: String;
    TimeoutMs: Integer;
    Cases: TCaptureCases;
  End;

Function OptionValue(Const OptionName: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = OptionName Then
      Result := ParamStr(I + 1);
End;

Function OptionGiven(Const OptionName: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = OptionName Then
      Exit(True);
End;

Function ReadCaseOptions(Var Settings: TCaptureSettings; Out ErrorText: String): Boolean;
Var
  I: Integer;
  CaseName: String;
  CaptureCase: TCaptureCase;
  Known: Boolean;
Begin
  Result := False;
  ErrorText := '';
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = '--case' Then
      Begin
        CaseName := ParamStr(I + 1);
        Known := False;
        For CaptureCase := Low(TCaptureCase) To High(TCaptureCase) Do
          If CaptureCaseNames[CaptureCase] = CaseName Then
            Begin
              Include(Settings.Cases, CaptureCase);
              Known := True;
            End;
        If Not Known Then
          Begin
            ErrorText := 'Unknown case: ' + CaseName;
            Exit;
          End;
      End;
  If Settings.Cases = [] Then
    Settings.Cases := [Low(TCaptureCase)..High(TCaptureCase)];
  { The resume turn needs the session the image turn starts. }
  If ccImageResume In Settings.Cases Then
    Include(Settings.Cases, ccImageInput);
  Result := True;
End;

Function ReadCaptureSettings(Out Settings: TCaptureSettings; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  Settings := Default(TCaptureSettings);
  Settings.OutputDir := OptionValue('--output-dir');
  If Settings.OutputDir = '' Then
    Begin
      ErrorText := '--output-dir is required. Use a directory under Temporary/.';
      Exit;
    End;
  Settings.OutputDir := IncludeTrailingPathDelimiter(ExpandFileName(Settings.OutputDir));
  Settings.Executable := OptionValue('--claude');
  If Settings.Executable = '' Then
    Settings.Executable := DetectClaudeExecutable
  Else
    Settings.Executable := ClaudeRuntimeFromBrowsedPath(Settings.Executable);
  If Settings.Executable = '' Then
    Begin
      ErrorText := 'Claude Code was not found. Pass --claude <path>.';
      Exit;
    End;
  { --model '' leaves the model to Claude Code. }
  If OptionGiven('--model') Then
    Settings.Model := OptionValue('--model')
  Else
    Settings.Model := DefaultModel;
  Settings.TimeoutMs := StrToIntDef(OptionValue('--timeout'), DefaultTimeoutSeconds) * 1000;
  If Not ReadCaseOptions(Settings, ErrorText) Then
    Exit;
  Settings.WorkDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'LazWorkflowClaudeCapture-' + IntToStr(GetProcessID);
  Result := True;
End;

Procedure SaveText(Const FileName, Text: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    If Text <> '' Then
      Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Function LoadText(Const FileName: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExists(FileName) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(FileName);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Function CommandText(Args: TStrings): String;
Var
  I: Integer;
Begin
  Result := 'claude';
  For I := 0 To Args.Count - 1 Do
    If (Args[I] = '') Or (Pos(' ', Args[I]) > 0) Then
      Result := Result + ' ''' + Args[I] + ''''
    Else
      Result := Result + ' ' + Args[I];
End;

Function WordsText(Const Words: Array Of String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := Low(Words) To High(Words) Do
    If Result = '' Then
      Result := Words[I]
    Else
      Result := Result + ' and ' + Words[I];
End;

Function SecondsText(Seconds: Double): String;
Begin
  If Seconds < 0 Then
    Result := 'never'
  Else
    Result := FormatFloat('0.0', Seconds) + ' s';
End;

Procedure AddRunLines(Const Run: TCaptureRun; KeepInputOpen: Boolean; Summary: TStrings; Const Words: Array Of String);
Var
  ResultText: String;
  IsError, HasResult: Boolean;
Begin
  If KeepInputOpen Then
    Summary.Add('- stdin was kept open after the message and closed ' + IntToStr(StdinOpenWaitMs Div 1000) +
      ' s after the result event, unless the process had already ended');
  Summary.Add('- started: ' + BoolToStr(Run.Started, 'yes', 'no ' + Run.ErrorText) + '; exit code ' + IntToStr(Run.ExitCode) +
    BoolToStr(Run.TimedOut, ' (timed out and stopped)', ''));
  If Run.Started And (Run.ErrorText <> '') Then
    Summary.Add('- input: ' + Run.ErrorText);
  Summary.Add('- result event at ' + SecondsText(Run.ResultSeconds) + '; stdin closed at ' + SecondsText(Run.InputClosedSeconds) +
    '; exit at ' + SecondsText(Run.ExitSeconds) + BoolToStr(Run.ExitedWithInputOpen, '; ended with stdin still open', ''));
  HasResult := CaptureStreamResult(Run.StdoutText, ResultText, IsError);
  If Not HasResult Then
    Summary.Add('- **no result event**')
  Else
    Summary.Add('- result is_error: ' + BoolToStr(IsError, 'true', 'false'));
  If HasResult And (Length(Words) > 0) Then
    Summary.Add('- answer names ' + WordsText(Words) + ': ' + BoolToStr(CaptureAnswerMentions(ResultText, Words), 'yes', 'NO'));
  Summary.Add('');
  Summary.Add('Stream:');
  Summary.Add('');
  Summary.Add(CaptureStreamSummary(Run.StdoutText));
  If Trim(Run.StderrText) = '' Then
    Exit;
  Summary.Add('Stderr:');
  Summary.Add('');
  Summary.Add('```');
  Summary.Add(Copy(Trim(Run.StderrText), 1, 2000));
  Summary.Add('```');
  Summary.Add('');
End;

{ Runs one case, saves its stdin, stdout and stderr under FileStem in the output directory, and adds its section to
  Summary. Words are the ones a correct answer names; empty skips that check. }
Function RunCase(Const Settings: TCaptureSettings; CaptureCase: TCaptureCase; Const FileStem, SessionId, MCPConfigFile,
  InputText: String; KeepInputOpen: Boolean; Environment, Summary: TStrings; Const Words: Array Of String): TCaptureRun;
Var
  Args: TStringList;
  Stem: String;
Begin
  WriteLn('Running ', FileStem, ' ...');
  Stem := Settings.OutputDir + FileStem;
  Args := TStringList.Create;
  Try
    AppendCaptureArguments(CaptureCase, Settings.Model, SessionId, MCPConfigFile, Args);
    If Not CaptureArgumentsAllowed(Args) Then
      Raise Exception.Create('A forbidden claude flag reached ' + FileStem + '.');
    SaveText(Stem + '.input.txt', InputText);
    Result := RunCaptureProcess(Settings.Executable, Settings.WorkDir, Args, Environment, InputText, KeepInputOpen,
      StdinOpenWaitMs, Settings.TimeoutMs);
    SaveText(Stem + '.jsonl', Result.StdoutText);
    SaveText(Stem + '.stderr.txt', Result.StderrText);
    Summary.Add('## ' + FileStem);
    Summary.Add('');
    Summary.Add('- command: `' + CommandText(Args) + '`');
    Summary.Add('- stdin: `' + Copy(CaptureShortenedJson(Trim(InputText)), 1, 600) + '`');
    AddRunLines(Result, KeepInputOpen, Summary, Words);
  Finally
    Args.Free;
  End;
End;

Function Accepted(Const Run: TCaptureRun): Boolean;
Var
  ResultText: String;
  IsError: Boolean;
Begin
  Result := CaptureStreamResult(Run.StdoutText, ResultText, IsError) And Not IsError;
End;

Procedure AddPicture(Const Settings: TCaptureSettings; Picture: TCapturePicture; Const FileName: String; Summary: TStrings;
  Out Base64Data: String);
Var
  Bytes: String;
Begin
  Bytes := CapturePicturePNG(Picture);
  Base64Data := EncodeStringBase64(Bytes);
  SaveText(Settings.OutputDir + FileName, Bytes);
  Summary.Add('- `' + FileName + '`: ' + IntToStr(Length(Bytes)) + ' bytes PNG, ' + IntToStr(Length(Base64Data)) +
    ' base64 characters');
End;

{ The image turn, then the resume turn on its session. A plain message with no successful result is tried once more
  in the Agent SDK shape; the resume turn uses whichever shape succeeded. }
Procedure RunImageCases(Const Settings: TCaptureSettings; Const InputData: String; Environment, Summary: TStrings;
  Out Shape: TCaptureMessageShape);
Var
  SessionId: String;
  ImageAccepted: Boolean;
Begin
  Shape := cmsPlain;
  ImageAccepted := False;
  SessionId := '';
  If ccImageInput In Settings.Cases Then
    Begin
      SessionId := NewClaudeSessionId;
      ImageAccepted := Accepted(RunCase(Settings, ccImageInput, 'image-input', SessionId, '',
        CaptureImageMessage(ImageInputPrompt, 'image/png', InputData, cmsPlain) + #10, False, Environment, Summary,
        CaptureInputWords));
      If Not ImageAccepted Then
        Begin
          Summary.Add('The plain message shape had no successful result, so the Agent SDK shape is tried next.');
          Summary.Add('');
          Shape := cmsSDK;
          SessionId := NewClaudeSessionId;
          ImageAccepted := Accepted(RunCase(Settings, ccImageInput, 'image-input-sdk', SessionId, '',
            CaptureImageMessage(ImageInputPrompt, 'image/png', InputData, cmsSDK) + #10, False, Environment, Summary,
            CaptureInputWords));
        End;
    End;
  If Not (ccImageResume In Settings.Cases) Then
    Exit;
  If ImageAccepted Then
    RunCase(Settings, ccImageResume, 'image-resume', SessionId, '', CaptureTextMessage(ImageResumePrompt, Shape) + #10, False,
      Environment, Summary, CaptureInputWords)
  Else
    Begin
      Summary.Add('## image-resume');
      Summary.Add('');
      Summary.Add('Skipped: no image turn succeeded, so there is no session to resume.');
      Summary.Add('');
    End;
End;

Procedure RunMCPCase(Const Settings: TCaptureSettings; Environment, Summary: TStrings);
Var
  ConfigFile, LogFile: String;
Begin
  ConfigFile := Settings.OutputDir + 'mcp-config.json';
  LogFile := Settings.OutputDir + 'mcp-server.log';
  If FileExists(LogFile) Then
    DeleteFile(LogFile);
  SaveText(ConfigFile, CaptureMCPConfig(ExpandFileName(ParamStr(0)), LogFile));
  RunCase(Settings, ccMCPImage, 'mcp-image', '', ConfigFile, MCPImagePrompt + #10, False, Environment, Summary, CaptureToolWords);
  Summary.Add('MCP server log (`mcp-server.log`):');
  Summary.Add('');
  Summary.Add('```');
  Summary.Add(TrimRight(LoadText(LogFile)));
  Summary.Add('```');
  Summary.Add('');
End;

Procedure RunCases(Const Settings: TCaptureSettings; Environment, Summary: TStrings);
Var
  InputData, ToolData, LargeData: String;
  Shape: TCaptureMessageShape;
Begin
  Summary.Add('Pictures:');
  Summary.Add('');
  AddPicture(Settings, cpInputCircle, 'input-picture.png', Summary, InputData);
  AddPicture(Settings, cpToolTriangle, 'tool-picture.png', Summary, ToolData);
  LargeData := '';
  If ccLimitsLarge In Settings.Cases Then
    AddPicture(Settings, cpLargeNoise, 'large-picture.png', Summary, LargeData);
  Summary.Add('');
  RunImageCases(Settings, InputData, Environment, Summary, Shape);
  If ccMCPImage In Settings.Cases Then
    RunMCPCase(Settings, Environment, Summary);
  If ccStdinOpen In Settings.Cases Then
    RunCase(Settings, ccStdinOpen, 'stdin-open', '', '', CaptureTextMessage(StdinOpenPrompt, Shape) + #10, True, Environment,
      Summary, []);
  If ccLimitsLarge In Settings.Cases Then
    RunCase(Settings, ccLimitsLarge, 'limits-large', '', '', CaptureImageMessage(LimitsPrompt, 'image/png', LargeData, Shape) + #10,
      False, Environment, Summary, []);
  If ccLimitsFormat In Settings.Cases Then
    RunCase(Settings, ccLimitsFormat, 'limits-format', '', '', CaptureImageMessage(LimitsPrompt, 'image/bmp', InputData, Shape) + #10,
      False, Environment, Summary, []);
End;

Function CheckAccount(Const Settings: TCaptureSettings; Out Account: TClaudeAccount): Boolean;
Var
  ErrorText: String;
Begin
  Result := False;
  If Not ReadClaudeAccount(Settings.Executable, Account, ErrorText) Then
    Begin
      WriteLn(StdErr, ErrorText);
      Exit;
    End;
  If Not ClaudeAccountIsSubscription(Account) Then
    Begin
      WriteLn(StdErr, ClaudeAccountText(Account));
      Exit;
    End;
  Result := True;
End;

Function RunCaptureProgram: Integer;
Var
  Settings: TCaptureSettings;
  Account: TClaudeAccount;
  Environment, Summary, Args: TStringList;
  ErrorText: String;
  Version: TCaptureRun;
Begin
  Result := 1;
  If OptionGiven('--mcp-server') Then
    Begin
      RunCaptureMCPServer(OptionValue('--mcp-server'));
      Exit(0);
    End;
  If Not ReadCaptureSettings(Settings, ErrorText) Then
    Begin
      WriteLn(StdErr, ErrorText);
      WriteLn(StdErr, UsageText);
      Exit(2);
    End;
  {$IFDEF UNIX}
  { A child that refuses its input closes stdin early. The write then fails instead of ending this program. }
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  If Not CheckAccount(Settings, Account) Then
    Exit;
  If Not ForceDirectories(Settings.OutputDir) Or Not ForceDirectories(Settings.WorkDir) Then
    Begin
      WriteLn(StdErr, 'Could not create ', Settings.OutputDir, ' or ', Settings.WorkDir);
      Exit;
    End;
  Environment := TStringList.Create;
  Summary := TStringList.Create;
  Args := TStringList.Create;
  Try
    BuildClaudeEnvironment(Environment);
    Args.Add('--version');
    Version := RunCaptureProcess(Settings.Executable, Settings.WorkDir, Args, Environment, '', False, 0, 30000);
    Summary.Add('# Claude Code image capture');
    Summary.Add('');
    Summary.Add('- date: ' + FormatDateTime('yyyy-mm-dd hh:nn', Now));
    Summary.Add('- claude --version: ' + Trim(Version.StdoutText));
    Summary.Add('- account: ' + ClaudeAccountText(Account));
    Summary.Add('- model: ' + Settings.Model);
    Summary.Add('- working directory: an empty scratch directory, shown in the streams as ' + Settings.WorkDir);
    Summary.Add('');
    RunCases(Settings, Environment, Summary);
    Summary.SaveToFile(Settings.OutputDir + 'summary.md');
    WriteLn('Wrote ', Settings.OutputDir, 'summary.md');
    Result := 0;
  Finally
    Args.Free;
    Summary.Free;
    Environment.Free;
    If Not RemoveDir(Settings.WorkDir) Then
      WriteLn(StdErr, 'The scratch directory was not empty and was kept: ', Settings.WorkDir);
  End;
End;

End.
