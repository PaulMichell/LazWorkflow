Unit AssistantCodexDiagnostics;

{ Diagnostic categories never include credentials, URLs, account identifiers or
  arbitrary server text. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Function CodexDiagnosticCategory(Const Text: String): String;
Function CodexRequestError(Const Method: String; Code: Int64; Const Text: String): String;

Implementation

Function CodexDiagnosticCategory(Const Text: String): String;
Var
  Lower: String;
Begin
  Lower := LowerCase(Text);
  If Pos('workspace routing', Lower) > 0 Then Result := 'workspace routing discovery failed'
  Else If Pos('refresh', Lower) > 0 Then Result := 'authentication refresh failed'
  Else If (Pos('unauthorized', Lower) > 0) Or (Pos('401', Lower) > 0) Then Result := 'authentication was rejected'
  Else If (Pos('quota', Lower) > 0) Or (Pos('usage limit', Lower) > 0) Then Result := 'account allowance is unavailable'
  Else If Pos('429', Lower) > 0 Then Result := 'request rate limit reached'
  Else If (Pos('certificate', Lower) > 0) Or (Pos('tls', Lower) > 0) Then Result := 'TLS verification failed'
  Else If (Pos('dns', Lower) > 0) Or (Pos('connect', Lower) > 0) Then Result := 'network connection failed'
  Else If (Pos('timeout', Lower) > 0) Or (Pos('timed out', Lower) > 0) Then Result := 'request timed out'
  Else If Pos('config', Lower) > 0 Then Result := 'runtime configuration was rejected'
  Else If Pos('model', Lower) > 0 Then Result := 'selected model or model access was rejected'
  Else If (Pos('unsupported', Lower) > 0) Or (Pos('unknown variant', Lower) > 0) Then Result := 'unsupported protocol option'
  Else If Pos('permission', Lower) > 0 Then Result := 'runtime permission policy was rejected'
  Else Result := 'runtime rejected the request';
End;

Function CodexRequestError(Const Method: String; Code: Int64; Const Text: String): String;
Begin
  Result := 'Codex ' + Method + ' failed (RPC ' + IntToStr(Code) + '): ' + CodexDiagnosticCategory(Text) + '.';
End;

End.
