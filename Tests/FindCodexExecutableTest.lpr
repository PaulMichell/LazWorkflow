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
  Else
    WriteLn('ok   macOS Codex auto-detect');
  {$ELSE}
  WriteLn('ok   non-Darwin host (presence optional)');
  {$ENDIF}
  If Failed Then
    Halt(1);
End.
