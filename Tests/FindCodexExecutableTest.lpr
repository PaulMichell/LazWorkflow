Program FindCodexExecutableTest;
{ Smoke check for Codex auto-detect (c) 2026 Michell Computing. }

{$MODE ObjFPC}
{$H+}

Uses
  SysUtils, LazFileUtils, AssistantCodexProfile;

Var
  Found: String;
  Failed: Boolean;
Begin
  Failed := False;
  Found := FindCodexExecutable;
  WriteLn('FindCodexExecutable=', Found);
  {$IFDEF DARWIN}
  If Found = '' Then
    Begin
      WriteLn('FAIL expected a Codex path on macOS when ChatGPT.app or PATH provides one');
      Failed := True;
    End
  Else If Not FileIsExecutable(Found) Then
    Begin
      WriteLn('FAIL path is not executable: ', Found);
      Failed := True;
    End
  Else If (Pos('ChatGPT.app', Found) = 0) And (Pos('/codex', Found) = 0) And
    (ExtractFileName(Found) <> 'codex') Then
    Begin
      WriteLn('FAIL unexpected path shape: ', Found);
      Failed := True;
    End
  Else If ((Pos('.vscode/extensions/openai.chatgpt-', Found) > 0) Or
    (Pos('.vscode-insiders/extensions/openai.chatgpt-', Found) > 0) Or
    (Pos('.cursor/extensions/openai.chatgpt-', Found) > 0)) And
    (DirectoryExists('/Applications/ChatGPT.app') Or
    DirectoryExists(IncludeTrailingPathDelimiter(GetUserDir) + 'Applications/ChatGPT.app') Or
    DirectoryExists('/Applications/ChatGPT Desktop.app') Or
    DirectoryExists(IncludeTrailingPathDelimiter(GetUserDir) + 'Applications/ChatGPT Desktop.app')) Then
    Begin
      WriteLn('FAIL official ChatGPT app is installed but auto-detect returned the editor extension: ', Found);
      Failed := True;
    End
  Else
    WriteLn('ok   macOS Codex auto-detect');
  {$ELSE}
  {$IFDEF LINUX}
  If FileIsExecutable('/usr/lib/chatgpt/resources/codex') And (Pos('/chatgpt/resources/codex', Found) = 0) Then
    Begin
      WriteLn('FAIL Linux ChatGPT app is installed but auto-detect returned ', Found);
      Failed := True;
    End
  Else
    WriteLn('ok   Linux Codex auto-detect');
  {$ELSE}
  WriteLn('ok   non-Darwin host (presence optional)');
  {$ENDIF}
  {$ENDIF}
  If Failed Then
    Halt(1);
End.
