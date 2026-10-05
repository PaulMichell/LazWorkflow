Unit AssistantGit;

{ Shared direct Git execution for Build-mode inspection, staging and commits. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  AssistantGitSchema = '{"type":"object","properties":{"arguments":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":256}},"required":["arguments"],"additionalProperties":false}';
  AssistantGitDescription =
    'Run Git in the active project directory in Build mode. Supply an argument array starting with status, diff, log, ' +
    'show, rev-parse, ls-files, add or commit, without git or shell syntax. Stage using ["add","--","path"]. ' +
    'Commit using ["commit","-m","message"]. Put the subject and body in that one message, or pass several -m arguments; ' +
    'Git joins them with a blank line. End with -- and project-relative paths to commit only those files. ' +
    'A package target can stage and commit only that package and Documents/. ' +
    'The refusal names the target. Global options, history rewriting, destructive commands and remote operations are not supported. ' +
    'Operates on saved files; save authorized edits first. Inspect status and staged diff before committing; stage only requested files. ' +
    'Follow explicit commit instructions in the conversation or active plan, including automatic commits after completed work. ' +
    'Do not commit unrelated changes. Output includes exit_code and truncation; only exit_code zero is success.';
Function WorkingRootHasGitRepository(Const Root: String): Boolean;
Procedure ResetAssistantGitTurn;
Function AssistantGitTurnCommitted: Boolean;
Function RunAssistantGit(Const ProjectRoot, ArgumentsJSON: String; Out ResultText, ErrorText: String): Boolean;

Implementation

Uses
  Process, fpjson, jsonparser;

Var
  TurnCommitted: Boolean;

Function WorkingRootHasGitRepository(Const Root: String): Boolean;
Var
  GitPath: String;
Begin
  Result := False;
  If Trim(Root) = '' Then Exit;
  GitPath := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Trim(Root))) + '.git';
  Result := DirectoryExists(GitPath) Or FileExists(GitPath);
End;

Procedure ResetAssistantGitTurn;
Begin
  TurnCommitted := False;
End;

Function AssistantGitTurnCommitted: Boolean;
Begin
  Result := TurnCommitted;
End;

Function CommitMessagesAccepted(Args: TJSONArray; Out ErrorText: String): Boolean;
Var
  Index: Integer;
  SawMessage: Boolean;
Begin
  Result := False;
  ErrorText := '';
  SawMessage := False;
  Index := 1;
  While Index < Args.Count Do
    Begin
      If Args.Items[Index].AsString = '--' Then
        Break;
      If Args.Items[Index].AsString <> '-m' Then
        Begin
          ErrorText := 'Use commit with -m and a nonempty message. Put the subject and body in one -m string, ' +
            'or pass several -m arguments. Git joins them with a blank line. ' +
            'To commit only some files, end with -- and those paths. Other commit options are not allowed.';
          Exit;
        End;
      If (Index + 1 >= Args.Count) Or (Trim(Args.Items[Index + 1].AsString) = '') Then
        Begin
          ErrorText := 'Each -m needs a nonempty message. Put the subject and body in one -m string, ' +
            'or pass several -m arguments. Git joins them with a blank line.';
          Exit;
        End;
      SawMessage := True;
      Inc(Index, 2);
    End;
  If Not SawMessage Then
    Begin
      ErrorText := 'Use commit with -m and a nonempty message. Put the subject and body in one -m string, ' +
        'or pass several -m arguments. Git joins them with a blank line.';
      Exit;
    End;
  Result := True;
End;

Function CommitPathsAccepted(Const Root: String; Args: TJSONArray; Out ErrorText: String): Boolean;
Var
  Index: Integer;
  Path: String;
Begin
  Result := False;
  ErrorText := '';
  Index := 1;
  While Index < Args.Count Do
    Begin
      If Args.Items[Index].AsString = '--' Then
        Break;
      Inc(Index, 2);
    End;
  If Index >= Args.Count Then
    Exit(True);
  Inc(Index);
  If Index >= Args.Count Then
    Begin
      ErrorText := 'After --, pass the project-relative files to commit.';
      Exit;
    End;
  While Index < Args.Count Do
    Begin
      Path := Args.Items[Index].AsString;
      If (Path = '') Or (Path[1] In ['-', '/', '\', ':']) Or (Pos(':', Path) > 0) Or
        (Pos('..', Path) > 0) Or (Pos('*', Path) > 0) Or (Pos('?', Path) > 0) Or (Path = '.') Or
        DirectoryExists(IncludeTrailingPathDelimiter(Root) + Path) Then
        Begin
          ErrorText := 'Commit explicit project-relative file paths without traversal or wildcards.';
          Exit;
        End;
      Inc(Index);
    End;
  Result := True;
End;

Function RunAssistantGit(Const ProjectRoot, ArgumentsJSON: String; Out ResultText, ErrorText: String): Boolean;
Const
  MaxOutput = 48000;
  TimeoutMs = 60000;
Var
  Data, Args: TJSONData;
  P: TProcess;
  Reply: TJSONObject;
  I, N, Keep: Integer;
  Started: QWord;
  Buffer: Array[0..4095] Of Byte;
  Output, Part, Command, Env, Arg: String;
  Truncated, TimedOut: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Data := Nil;
  P := Nil;
  Try
    Try
      If (Trim(ProjectRoot) = '') Or Not DirectoryExists(ProjectRoot) Then
        Begin
          ErrorText := 'No active project directory.';
          Exit;
        End;
      Data := GetJSON(ArgumentsJSON);
      If Not (Data Is TJSONObject) Then
        Begin
          ErrorText := 'Git arguments must be a JSON object.';
          Exit;
        End;
      Args := TJSONObject(Data).Find('arguments');
      If Not (Args Is TJSONArray) Then
        Begin
          ErrorText := 'arguments must be an array of strings.';
          Exit;
        End;
      If (Args.Count < 1) Or (Args.Count > 256) Then
        Begin
          ErrorText := 'Supply 1-256 Git arguments.';
          Exit;
        End;
      For I := 0 To Args.Count - 1 Do
        If (Args.Items[I].JSONType <> jtString) Or (Pos(#0, Args.Items[I].AsString) > 0) Or
          (Length(Args.Items[I].AsString) > 32000) Then
            Begin
              ErrorText := 'Each Git argument must be a string without NUL, at most 32000 bytes.';
              Exit;
            End;
      Command := Args.Items[0].AsString;
      If (Command = '') Or (Pos('|' + Command + '|',
        '|status|diff|log|show|rev-parse|ls-files|add|commit|') = 0) Or (Pos('|', Command) > 0) Then
          Begin
            ErrorText := 'Supported Git commands: status, diff, log, show, rev-parse, ls-files, add, commit. Global options are not allowed.';
            Exit;
          End;
      { Commits use explicit messages and the reviewed index, without rewrites. }
      If (Command = 'commit') And (Not CommitMessagesAccepted(TJSONArray(Args), ErrorText)) Then
        Exit;
      If (Command = 'commit') And (Not CommitPathsAccepted(ProjectRoot, TJSONArray(Args), ErrorText)) Then
        Exit;
      For I := 1 To Args.Count - 1 Do
        Begin
          Arg := Args.Items[I].AsString;
          If (Command <> 'commit') And
            ((Pos('--out', Arg) = 1) Or (Pos('--ext-diff', Arg) = 1) Or
            (Pos('--textconv', Arg) = 1) Or (Pos('--exec', Arg) = 1)) Then
              Begin
                ErrorText := 'External commands and output file options are not supported.';
                Exit;
              End;
          If (Command = 'add') And (I = 1) And (Arg <> '--') Then
            Begin
              ErrorText := 'Use add followed by -- and explicit project-relative paths.';
              Exit;
            End;
          If (Command = 'add') And (I > 1) And
            ((Arg = '') Or (Arg[1] In ['/', '\', ':']) Or (Pos(':', Arg) > 0) Or
            (Pos('..', Arg) > 0) Or (Pos('*', Arg) > 0) Or (Pos('?', Arg) > 0) Or (Arg = '.') Or DirectoryExists(IncludeTrailingPathDelimiter(ProjectRoot) + Arg)) Then
              Begin
                ErrorText := 'Stage explicit project-relative file paths without traversal or wildcards.';
                Exit;
              End;
        End;
      If (Command = 'add') And (Args.Count < 3) Then
        Begin
          ErrorText := 'Supply explicit paths after add --.';
          Exit;
        End;
      P := TProcess.Create(Nil);
      P.Executable := 'git';
      P.CurrentDirectory := ProjectRoot;
      P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
      For I := 1 To GetEnvironmentVariableCount Do
        Begin
          Env := GetEnvironmentString(I);
          If Copy(UpperCase(Env), 1, 4) <> 'GIT_' Then P.Environment.Add(Env);
        End;
      P.Environment.Add('GIT_TERMINAL_PROMPT=0');
      P.Parameters.Add('--no-pager');
      { Bracketed names are globs unless pathspecs are literal. * and ? stay refused. }
      If (Command = 'add') Or (Command = 'commit') Then
        P.Parameters.Add('--literal-pathspecs');
      For I := 0 To Args.Count - 1 Do P.Parameters.Add(Args.Items[I].AsString);
      If (Command = 'diff') Or (Command = 'log') Or (Command = 'show') Then
        Begin
          P.Parameters.Insert(2, '--no-ext-diff');
          P.Parameters.Insert(3, '--no-textconv');
        End;
      P.Execute;
      P.CloseInput;
      Started := GetTickCount64;
      Output := '';
      Truncated := False;
      TimedOut := False;
      Repeat
        N := P.Output.NumBytesAvailable;
        If N > 0 Then
          Begin
            If N > SizeOf(Buffer) Then N := SizeOf(Buffer);
            N := P.Output.Read(Buffer, N);
            Keep := MaxOutput - Length(Output);
            If Keep > N Then Keep := N;
            If Keep > 0 Then
              Begin
                SetString(Part, PAnsiChar(@Buffer[0]), Keep);
                Output := Output + Part;
              End;
            If Keep < N Then Truncated := True;
          End;
        If GetTickCount64 - Started >= TimeoutMs Then
          Begin
            TimedOut := True;
            If P.Running Then P.Terminate(1);
            Break;
          End;
        If Not P.Running And (P.Output.NumBytesAvailable = 0) Then Break;
        If N = 0 Then Sleep(5);
      Until False;
      Reply := TJSONObject.Create;
      Try
        Reply.Add('output', Output);
        Reply.Add('truncated', Truncated);
        Reply.Add('timed_out', TimedOut);
        If TimedOut Then Reply.Add('exit_code', -1)
        Else Reply.Add('exit_code', P.ExitCode);
        ResultText := Reply.AsJSON;
      Finally
        Reply.Free;
      End;
      Result := Not TimedOut And (P.ExitCode = 0);
      If Result And (Command = 'commit') Then
        TurnCommitted := True;
      If TimedOut Then ErrorText := 'Git timed out; inspect repository status before retrying.'
      Else If Not Result Then ErrorText := 'Git failed with exit code ' + IntToStr(P.ExitCode) + ': ' + Output;
    Except On E: Exception Do ErrorText := 'Git execution failed: ' + E.Message;
    End;
  Finally
    P.Free;
    Data.Free;
  End;
End;
End.
