#!/usr/bin/env instantfpc
Program QualifyCodexRuntime;

{ Offline qualification using exactly the IDE's contract evaluator.
  Compile with Source/LazAssistantTools, Source/LazWorkflowCommon and the
  Lazarus lazutils unit directory on the FPC unit search path.
  Never signs in or starts a turn. (c) 2026 Michell Computing. }

{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, AssistantCodexQualification;
Function ArgumentValue(Const Name: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = Name Then Exit(ParamStr(I + 1));
End;
Var
  Evidence: TCodexCompatibility;
  Runtime, Directory, Reason: String;
  Lines: TStringList;
Begin
  Runtime := ArgumentValue('--runtime');
  Directory := ArgumentValue('--output-dir');
  If (Runtime = '') Or (Directory = '') Then
    Begin
      WriteLn(StdErr, 'Usage: QualifyCodexRuntime --runtime <codex> --output-dir <directory>');
      Halt(2);
    End;
  If Not InspectCodexRuntime(Runtime, Nil, Evidence, Reason) Then
    Begin
      WriteLn(StdErr, Reason);
      Halt(1);
    End;
  If Not ForceDirectories(Directory) Then Halt(1);
  Lines := TStringList.Create;
  Try
    Lines.Text := CodexCompatibilityJson(Evidence);
    Lines.SaveToFile(IncludeTrailingPathDelimiter(Directory) + 'qualification.json');
    WriteLn(Lines.Text);
  Finally
    Lines.Free;
  End;
  If Evidence.Support[ccRun] <> csSupported Then Halt(1);
End.
