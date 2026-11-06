Unit AssistantGit;

{ Shared direct Git execution. Inspect may read; Build may also stage and commit.
  stage_patch applies a unified diff to the index only. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation;

Const
  AssistantGitSchema = '{"type":"object","properties":{"arguments":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":256}},"required":["arguments"],"additionalProperties":false}';
  AssistantGitDescription =
    'Run Git in the active project directory. Supply an argument array starting with status, diff, log, ' +
    'show, rev-parse, ls-files, add or commit, without git or shell syntax. ' +
    'Inspect may use status, diff, log, show, rev-parse, and ls-files only. Build may also stage and commit. ' +
    'Stage using ["add","--","path"]. ' +
    'Commit using ["commit","-m","message"]. Put the subject and body in that one message, or pass several -m arguments; ' +
    'Git joins them with a blank line. End with -- and project-relative paths to commit only those files. ' +
    'A package target can stage and commit only that package and Documents/. ' +
    'The refusal names the target. Global options, history rewriting, destructive commands and remote operations are not supported. ' +
    'Operates on saved files; save authorized edits first. Inspect status and staged diff before committing; stage only requested files. ' +
    'Follow explicit commit instructions in the conversation or active plan, including automatic commits after completed work. ' +
    'Do not commit unrelated changes. Output includes exit_code and truncation; only exit_code zero is success.';
  AssistantStagePatchSchema = '{"type":"object","properties":{"patch":{"type":"string"}},"required":["patch"],"additionalProperties":false}';
  AssistantStagePatchDescription =
    'Stage selected hunks from a unified diff into the index. Build mode only; approval mode Ask requires confirmation. ' +
    'Every path must stay inside the target and out of .git. ' +
    'Runs git apply --cached --check, then git apply --cached, and never changes the working tree. ' +
    'The diff must apply to the index, such as one hunk from git diff, so other edits in the same file stay unstaged. ' +
    'Returns git diff --cached --stat. ' +
    'Then commit with commit -m and no paths, so Git records the index. ' +
    'Do not pass that file after --: a path records the working tree and would include the unstaged hunks.';
Function WorkingRootHasGitRepository(Const Root: String): Boolean;
{ True only for the six read commands Inspect may run. Add, commit, and every other command are false. }
Function AssistantGitInspectReadCommand(Const Command: String): Boolean;
{ True when this mode may run Command. Build does not restrict the subcommand.
  Inspect allows only the six read commands. Plan, Document and Chat refuse Git,
  the same as the broker's Markdown and none scopes. }
Function AssistantGitAllowedInMode(Mode: TAssistantMode; Const Command: String): Boolean;
Procedure ResetAssistantGitTurn;
Function AssistantGitTurnCommitted: Boolean;
Function RunAssistantGit(Const ProjectRoot, ArgumentsJSON: String; Out ResultText, ErrorText: String): Boolean;
{ Paths a unified diff would apply, after the same -p1 strip as git apply.
  Absolute paths, .., .git and unreadable headers set ErrorText and return false. }
Function AssistantGitPatchPaths(Const Patch: String; Paths: TStrings; Out ErrorText: String): Boolean;
{ Apply Patch to the index only. Root is the target: every path must stay inside it and out of .git.
  Never runs git apply without --cached. On success, ResultText is git diff --cached --stat. }
Function StageAssistantGitPatch(Const ProjectRoot, Patch: String; Out ResultText, ErrorText: String): Boolean;

Implementation

Uses
  Process, fpjson, jsonparser, LazFileUtils;

Var
  TurnCommitted: Boolean;

Function AssistantGitInspectReadCommand(Const Command: String): Boolean;
Begin
  Result := (Command = 'status') Or (Command = 'diff') Or (Command = 'log') Or
    (Command = 'show') Or (Command = 'rev-parse') Or (Command = 'ls-files');
End;

Function AssistantGitAllowedInMode(Mode: TAssistantMode; Const Command: String): Boolean;
Begin
  Case Mode Of
    amBuild: Result := True;
    amInspect: Result := AssistantGitInspectReadCommand(Command);
  Else
    Result := False;
  End;
End;

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

Const
  MaxPatchBytes = 1048576;
  MaxPatchPaths = 64;
  { git apply defaults to -p1. The path check uses the same strip. }
  GitApplyStripCount = 1;

Function DecodeGitQuoted(Const Value: String): String;
Var
  I, Digit, Octal: Integer;
Begin
  Result := '';
  I := 1;
  While I <= Length(Value) Do
    Begin
      If (Value[I] = '\') And (I < Length(Value)) Then
        Begin
          Inc(I);
          Case Value[I] Of
            '\', '"': Result := Result + Value[I];
            't': Result := Result + #9;
            'n': Result := Result + #10;
            'r': Result := Result + #13;
            '0'..'7':
              Begin
                Octal := Ord(Value[I]) - Ord('0');
                Digit := 1;
                While (Digit < 3) And (I < Length(Value)) And (Value[I + 1] In ['0'..'7']) Do
                  Begin
                    Inc(I);
                    Octal := Octal * 8 + (Ord(Value[I]) - Ord('0'));
                    Inc(Digit);
                  End;
                If Octal <= 255 Then Result := Result + Chr(Octal);
              End;
          Else
            Result := Result + Value[I];
          End;
        End
      Else
        Result := Result + Value[I];
      Inc(I);
    End;
End;

Function NextPatchToken(Var Rest: String; Out Token: String): Boolean;
Var
  SplitAt: Integer;
Begin
  Token := '';
  Result := False;
  Rest := TrimLeft(Rest);
  If Rest = '' Then Exit;
  If Rest[1] <> '"' Then
    Begin
      SplitAt := Pos(' ', Rest);
      If SplitAt = 0 Then
        Begin
          Token := Rest;
          Rest := '';
        End
      Else
        Begin
          Token := Copy(Rest, 1, SplitAt - 1);
          Rest := Copy(Rest, SplitAt + 1, MaxInt);
        End;
      Result := Token <> '';
      Exit;
    End;
  SplitAt := 2;
  While SplitAt <= Length(Rest) Do
    Begin
      If Rest[SplitAt] = '\' Then
        Begin
          If SplitAt >= Length(Rest) Then Exit;
          Inc(SplitAt, 2);
        End
      Else If Rest[SplitAt] = '"' Then
        Break
      Else
        Inc(SplitAt);
    End;
  If (SplitAt > Length(Rest)) Or (Rest[SplitAt] <> '"') Then Exit;
  Token := DecodeGitQuoted(Copy(Rest, 2, SplitAt - 2));
  Inc(SplitAt);
  If SplitAt <= Length(Rest) Then Rest := Copy(Rest, SplitAt, MaxInt)
  Else Rest := '';
  Result := True;
End;

Function BeforeTab(Const Value: String): String;
Var
  TabAt: Integer;
Begin
  TabAt := Pos(#9, Value);
  If TabAt = 0 Then Result := Value
  Else Result := Copy(Value, 1, TabAt - 1);
End;

Function ReadPatchPath(Const Text: String; Out Path: String): Boolean;
Var
  Rest: String;
Begin
  Path := '';
  Result := False;
  Rest := Text;
  If Rest = '' Then Exit;
  If Rest[1] = '"' Then Result := NextPatchToken(Rest, Path) And (Path <> '')
  Else
    Begin
      Path := Rest;
      Result := True;
    End;
End;

Function IsNullDevice(Const Path: String): Boolean;
Begin
  Result := (Path = '/dev/null') Or (Path = 'NUL') Or (Path = 'nul');
End;

Function PathIsAbsolutePatch(Const Path: String): Boolean;
Begin
  Result := (Path <> '') And ((Path[1] = '/') Or (Path[1] = '\') Or ((Length(Path) > 1) And (Path[2] = ':')));
End;

Function RejectPatchPath(Const Path: String; Out ErrorText: String): Boolean;
Var
  Rest, Part: String;
  SplitAt: Integer;
Begin
  Result := True;
  ErrorText := '';
  If (Path = '') Or (Length(Path) > 4096) Or (Pos(#0, Path) > 0) Then
    Begin
      ErrorText := 'Could not read a path from the patch.';
      Exit;
    End;
  If PathIsAbsolutePatch(Path) Or (Pos('\', Path) > 0) Or (Pos(':', Path) > 0) Then
    Begin
      ErrorText := 'Patch path is outside the target: ' + Path;
      Exit;
    End;
  Rest := Path;
  While Rest <> '' Do
    Begin
      SplitAt := Pos('/', Rest);
      If SplitAt = 0 Then
        Begin
          Part := Rest;
          Rest := '';
        End
      Else
        Begin
          Part := Copy(Rest, 1, SplitAt - 1);
          Rest := Copy(Rest, SplitAt + 1, MaxInt);
        End;
      If (Part = '') Or (Part = '.') Or (Part = '..') Then
        Begin
          ErrorText := 'Patch path is outside the target: ' + Path;
          Exit;
        End;
      If LowerCase(Part) = '.git' Then
        Begin
          ErrorText := 'Patch path is under .git: ' + Path;
          Exit;
        End;
    End;
  Result := False;
End;

Function StripComponents(Const Path: String; Count: Integer): String;
Var
  I, Slash: Integer;
Begin
  Result := Path;
  For I := 1 To Count Do
    Begin
      Slash := Pos('/', Result);
      If Slash = 0 Then Exit;
      Result := Copy(Result, Slash + 1, MaxInt);
    End;
End;

Function SplitMarkedPair(Const Rest, LeftMark, RightMark: String; Out OldPath, NewPath: String): Boolean;
Var
  SplitAt: Integer;
Begin
  Result := False;
  OldPath := '';
  NewPath := '';
  If Copy(Rest, 1, Length(LeftMark)) <> LeftMark Then Exit;
  SplitAt := Pos(RightMark, Rest);
  If SplitAt <= Length(LeftMark) Then Exit;
  OldPath := Copy(Rest, Length(LeftMark) + 1, SplitAt - Length(LeftMark) - 1);
  NewPath := Copy(Rest, SplitAt + Length(RightMark), MaxInt);
  Result := (OldPath <> '') And (NewPath <> '');
End;

Function AssistantGitPatchPaths(Const Patch: String; Paths: TStrings; Out ErrorText: String): Boolean;
Var
  Lines: TStringList;
  I: Integer;
  Line, Rest, Side: String;

  Function AcceptPath(Const Raw: String; DoStrip: Boolean): Boolean;
  Var
    Applied: String;
  Begin
    Result := False;
    If IsNullDevice(Raw) Then Exit(True);
    If RejectPatchPath(Raw, ErrorText) Then Exit;
    If DoStrip Then Applied := StripComponents(Raw, GitApplyStripCount)
    Else Applied := Raw;
    If RejectPatchPath(Applied, ErrorText) Then Exit;
    If Paths.Count >= MaxPatchPaths Then
      Begin
        ErrorText := 'The patch touches too many paths.';
        Exit;
      End;
    If Paths.IndexOf(Applied) < 0 Then Paths.Add(Applied);
    Result := True;
  End;

  Function AcceptGitHeader(Const Header: String): Boolean;
  Var
    HeaderRest, LeftPath, RightPath: String;
  Begin
    Result := False;
    If Copy(Header, 1, 11) <> 'diff --git ' Then Exit;
    HeaderRest := Copy(Header, 12, MaxInt);
    If (HeaderRest <> '') And (HeaderRest[1] = '"') Then
      Begin
        If Not NextPatchToken(HeaderRest, LeftPath) Or Not NextPatchToken(HeaderRest, RightPath) Then
          Begin
            ErrorText := 'Could not read a path from the patch.';
            Exit;
          End;
      End
    Else If SplitMarkedPair(HeaderRest, 'a/', ' b/', LeftPath, RightPath) Then
      Begin
        LeftPath := 'a/' + LeftPath;
        RightPath := 'b/' + RightPath;
      End
    Else If SplitMarkedPair(HeaderRest, 'i/', ' w/', LeftPath, RightPath) Then
      Begin
        LeftPath := 'i/' + LeftPath;
        RightPath := 'w/' + RightPath;
      End
    Else If Not NextPatchToken(HeaderRest, LeftPath) Or Not NextPatchToken(HeaderRest, RightPath) Then
      Begin
        ErrorText := 'Could not read a path from the patch.';
        Exit;
      End;
    Result := AcceptPath(LeftPath, True) And AcceptPath(RightPath, True);
  End;

Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(Paths) Then
    Begin
      ErrorText := 'Could not read a path from the patch.';
      Exit;
    End;
  Paths.Clear;
  If Trim(Patch) = '' Then
    Begin
      ErrorText := 'A unified diff is required.';
      Exit;
    End;
  If (Length(Patch) > MaxPatchBytes) Or (Pos(#0, Patch) > 0) Then
    Begin
      ErrorText := 'Patch must contain at most 1 MiB of text without NUL bytes.';
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    Lines.Text := Patch;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Copy(Line, 1, 11) = 'diff --git ' Then
          Begin
            If Not AcceptGitHeader(Line) Then Exit;
          End
        Else If (Copy(Line, 1, 4) = '--- ') Or (Copy(Line, 1, 4) = '+++ ') Then
          Begin
            If Not ReadPatchPath(BeforeTab(Copy(Line, 5, MaxInt)), Side) Or Not AcceptPath(Side, True) Then
              Begin
                If ErrorText = '' Then ErrorText := 'Could not read a path from the patch.';
                Exit;
              End;
          End
        Else If (Copy(Line, 1, 12) = 'rename from ') Or (Copy(Line, 1, 10) = 'rename to ') Or
          (Copy(Line, 1, 10) = 'copy from ') Or (Copy(Line, 1, 8) = 'copy to ') Then
          Begin
            If Copy(Line, 1, 12) = 'rename from ' Then Rest := Copy(Line, 13, MaxInt)
            Else If Copy(Line, 1, 10) = 'rename to ' Then Rest := Copy(Line, 11, MaxInt)
            Else If Copy(Line, 1, 10) = 'copy from ' Then Rest := Copy(Line, 11, MaxInt)
            Else Rest := Copy(Line, 9, MaxInt);
            If Not ReadPatchPath(Rest, Side) Or Not AcceptPath(Side, False) Then
              Begin
                If ErrorText = '' Then ErrorText := 'Could not read a path from the patch.';
                Exit;
              End;
          End;
      End;
  Finally
    Lines.Free;
  End;
  If Paths.Count = 0 Then
    Begin
      ErrorText := 'The patch has no file path to check.';
      Exit;
    End;
  Result := True;
End;

Function PatchPathInsideRoot(Const Root, RelativePath: String; Out ErrorText: String): Boolean;
Var
  Base, Full, Probe, PhysRoot, Phys, Relative: String;
Begin
  Result := False;
  ErrorText := '';
  Relative := StringReplace(RelativePath, '/', PathDelim, [rfReplaceAll]);
  Base := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  Full := ExpandFileName(Base + Relative);
  If (Full = '') Or ((CompareFilenames(Copy(Full, 1, Length(Base)), Base) <> 0) And
    (CompareFilenames(Full, ExcludeTrailingPathDelimiter(Base)) <> 0)) Then
    Begin
      ErrorText := 'Patch path is outside the target: ' + RelativePath;
      Exit;
    End;
  PhysRoot := GetPhysicalFilename(ExcludeTrailingPathDelimiter(Base), pfeOriginal);
  If PhysRoot = '' Then PhysRoot := ExcludeTrailingPathDelimiter(Base);
  PhysRoot := IncludeTrailingPathDelimiter(ExpandFileName(PhysRoot));
  Probe := Full;
  While (Probe <> '') And (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Do
    Begin
      If ExtractFileDir(Probe) = Probe Then Break;
      Probe := ExcludeTrailingPathDelimiter(ExtractFileDir(Probe));
    End;
  If (Not FileExistsUTF8(Probe)) And (Not DirectoryExistsUTF8(Probe)) Then Exit(True);
  Phys := GetPhysicalFilename(Probe, pfeEmpty);
  If Phys = '' Then
    Begin
      ErrorText := 'Patch path is outside the target: ' + RelativePath;
      Exit;
    End;
  Phys := ExpandFileName(Phys);
  If (CompareFilenames(Copy(Phys, 1, Length(PhysRoot)), PhysRoot) <> 0) And
    (CompareFilenames(ExcludeTrailingPathDelimiter(Phys), ExcludeTrailingPathDelimiter(PhysRoot)) <> 0) Then
    Begin
      ErrorText := 'Patch path is outside the target: ' + RelativePath;
      Exit;
    End;
  Result := True;
End;

Function RunFixedGit(Const ProjectRoot: String; Const Args: Array Of String; Out Output, ErrorText: String): Boolean;
Const
  MaxOutput = 48000;
  TimeoutMs = 60000;
Var
  P: TProcess;
  I, N, Keep: Integer;
  Started: QWord;
  Buffer: Array[0..4095] Of Byte;
  Part, Env: String;
  Truncated, TimedOut: Boolean;
Begin
  Result := False;
  Output := '';
  ErrorText := '';
  P := TProcess.Create(Nil);
  Try
    Try
      P.Executable := 'git';
      P.CurrentDirectory := ProjectRoot;
      P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
      For I := 1 To GetEnvironmentVariableCount Do
        Begin
          Env := GetEnvironmentString(I);
          If Copy(UpperCase(Env), 1, 4) <> 'GIT_' Then P.Environment.Add(Env);
        End;
      P.Environment.Add('GIT_TERMINAL_PROMPT=0');
      For I := 0 To High(Args) Do P.Parameters.Add(Args[I]);
      P.Execute;
      P.CloseInput;
      Started := GetTickCount64;
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
      If TimedOut Then ErrorText := 'Git timed out; inspect repository status before retrying.'
      Else If Truncated Then ErrorText := 'Git output was truncated.'
      Else Result := P.ExitCode = 0;
    Except
      On E: Exception Do ErrorText := 'Git execution failed: ' + E.Message;
    End;
  Finally
    P.Free;
  End;
End;

Function WriteTempPatch(Const Patch: String; Out PatchFile, ErrorText: String): Boolean;
Var
  Id: TGuid;
  Stream: TFileStream;
Begin
  Result := False;
  PatchFile := '';
  ErrorText := '';
  If CreateGUID(Id) <> 0 Then
    Begin
      ErrorText := 'Could not create a temporary patch file.';
      Exit;
    End;
  PatchFile := IncludeTrailingPathDelimiter(GetTempDir) + 'assistant-stage-' + GUIDToString(Id) + '.diff';
  Stream := TFileStream.Create(PatchFile, fmCreate);
  Try
    If Patch <> '' Then Stream.WriteBuffer(Patch[1], Length(Patch));
  Finally
    Stream.Free;
  End;
  Result := True;
End;

Function CachedDiffStat(Const ProjectRoot: String; Out StatText, ErrorText: String): Boolean;
Var
  Reply: String;
  Data: TJSONData;
Begin
  Result := False;
  StatText := '';
  ErrorText := '';
  If Not RunAssistantGit(ProjectRoot, '{"arguments":["diff","--cached","--stat"]}', Reply, ErrorText) Then Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Reply);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Could not read the staged diff stat.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Could not read the staged diff stat.';
        Exit;
      End;
    If TJSONObject(Data).Get('truncated', False) Then
      Begin
        ErrorText := 'Staged diff stat was truncated.';
        Exit;
      End;
    StatText := TJSONObject(Data).Get('output', '');
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function StageAssistantGitPatch(Const ProjectRoot, Patch: String; Out ResultText, ErrorText: String): Boolean;
Var
  Paths: TStringList;
  I: Integer;
  PatchFile, Output: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  PatchFile := '';
  Paths := TStringList.Create;
  Try
    Try
      If (Trim(ProjectRoot) = '') Or Not DirectoryExists(ProjectRoot) Then
        Begin
          ErrorText := 'No active project directory.';
          Exit;
        End;
      If Not WorkingRootHasGitRepository(ProjectRoot) Then
        Begin
          ErrorText := 'Partial staging requires a Git repository.';
          Exit;
        End;
      If Not AssistantGitPatchPaths(Patch, Paths, ErrorText) Then Exit;
      For I := 0 To Paths.Count - 1 Do
        If Not PatchPathInsideRoot(ProjectRoot, Paths[I], ErrorText) Then Exit;
      If Not WriteTempPatch(Patch, PatchFile, ErrorText) Then Exit;
      { --cached is fixed. git apply without it would change the working tree. }
      If Not RunFixedGit(ProjectRoot, ['--no-pager', 'apply', '--cached', '--check', '-p1', '--', PatchFile],
        Output, ErrorText) Then
        Begin
          If Pos('timed out', ErrorText) = 0 Then
            ErrorText := 'git apply --cached --check failed; the index is unchanged. ' + Trim(Output);
          Exit;
        End;
      If Not RunFixedGit(ProjectRoot, ['--no-pager', 'apply', '--cached', '-p1', '--', PatchFile],
        Output, ErrorText) Then
        Begin
          If Pos('timed out', ErrorText) = 0 Then
            ErrorText := 'git apply --cached failed. ' + Trim(Output);
          Exit;
        End;
      Result := CachedDiffStat(ProjectRoot, ResultText, ErrorText);
    Except
      On E: Exception Do
        If ErrorText = '' Then ErrorText := 'Git execution failed: ' + E.Message;
    End;
  Finally
    If PatchFile <> '' Then DeleteFile(PatchFile);
    Paths.Free;
  End;
End;
End.
