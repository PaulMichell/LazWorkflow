Unit AssistantIDEContext;

{ Collect active editor and project context for LazAssistantTools prompts (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  { Keep the default context modest so first-token latency stays reasonable.
    Selection is preferred; full-file attach is capped. }
  AssistantContextMaxActiveChars = 48000;
  { After several turns, only attach a light summary so history stays under the
    model token limit (full file can be re-read via tools). }
  AssistantContextMaxActiveCharsLight = 8000;
  AssistantContextMaxProjectFiles = 250;

Function BuildIDEContextBlock: String;
{ Smaller attach for long conversations (cursor + selection or short head of file). }
Function BuildIDEContextBlockLight: String;

Implementation

Uses
  LazIDEIntf, SrcEditorIntf, ProjectIntf, WorkflowLog, AssistantWorkTarget;

Function CapText(Const TextValue: String; MaxChars: Integer): String;
Begin
  If Length(TextValue) <= MaxChars Then
    Result := TextValue
  Else
    Result := Copy(TextValue, 1, MaxChars) + LineEnding +
      '[… truncated at ' + IntToStr(MaxChars) + ' characters …]';
End;

Function BuildActiveEditorSection: String;
Var
  Ed: TSourceEditorInterface;
  Sel, Src: String;
  CursorPos: TPoint;
Begin
  Result := '';
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      Result := 'Active editor: (source editor manager unavailable)';
      Exit;
    End;
  Ed := SourceEditorManagerIntf.ActiveEditor;
  If Not Assigned(Ed) Then
    Begin
      Result := 'Active editor: (none)';
      Exit;
    End;
  If (AssistantTarget.Kind<>atkProject) And Not AssistantTarget.ContainsFile(Ed.FileName) Then
    Begin
      Result := 'Active editor is outside the selected package; its text is not attached.';
      Exit;
    End;
  CursorPos := Ed.CursorTextXY;
  Result :=
    'Active editor: ' + Ed.FileName + LineEnding +
    Format('Cursor: line %d, column %d', [CursorPos.Y, CursorPos.X]) + LineEnding +
    'Modified: ' + BoolToStr(Ed.Modified, True);
  Sel := Ed.Selection;
  If Trim(Sel) <> '' Then
    Result := Result + LineEnding + LineEnding +
      'Selected text:' + LineEnding +
      CapText(Sel, AssistantContextMaxActiveChars)
  Else
    Begin
      Src := Ed.SourceText;
      If Src = '' Then
        Src := Ed.Lines.Text;
      Result := Result + LineEnding + LineEnding +
        'Full source of active editor:' + LineEnding +
        CapText(Src, AssistantContextMaxActiveChars);
    End;
End;

Function BuildProjectFilesSection: String;
Begin
  Result := AssistantTarget.Describe;
End;

Function BuildIDEContextBlock: String;
Begin
  Result :=
    '----- begin IDE context -----' + LineEnding +
    'The following is live context from the Lazarus IDE. Prefer it when answering about the code or project.' + LineEnding +
    LineEnding +
    TrimRight(BuildActiveEditorSection) + LineEnding +
    LineEnding +
    TrimRight(BuildProjectFilesSection) + LineEnding +
    '----- end IDE context -----';
  WorkflowLogger.Debug('AssistantIDEContext', 'Built IDE context block (' + IntToStr(Length(Result)) + ' chars)');
End;

Function BuildIDEContextBlockLight: String;
Var
  Ed: TSourceEditorInterface;
  Sel: String;
  CursorPos: TPoint;
  Head: String;
Begin
  Result :=
    '----- begin IDE context (light) -----' + LineEnding +
    AssistantTarget.Describe + LineEnding +
    'Long conversation: only a short editor summary is attached. Use read_file for full sources.' +
    LineEnding;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      Result := Result + 'Active editor: (unavailable)' + LineEnding +
        '----- end IDE context -----';
      Exit;
    End;
  Ed := SourceEditorManagerIntf.ActiveEditor;
  If Not Assigned(Ed) Then
    Begin
      Result := Result + 'Active editor: (none)' + LineEnding +
        '----- end IDE context -----';
      Exit;
    End;
  If (AssistantTarget.Kind<>atkProject) And Not AssistantTarget.ContainsFile(Ed.FileName) Then
    Begin
      Result := Result + 'Active editor is outside the selected package; its text is not attached.' + LineEnding + '----- end IDE context -----';
      Exit;
    End;
  CursorPos := Ed.CursorTextXY;
  Result := Result +
    'Active editor: ' + Ed.FileName + LineEnding +
    Format('Cursor: line %d, column %d', [CursorPos.Y, CursorPos.X]) + LineEnding +
    'Modified: ' + BoolToStr(Ed.Modified, True) + LineEnding;
  Sel := Ed.Selection;
  If Trim(Sel) <> '' Then
    Result := Result + LineEnding + 'Selected text:' + LineEnding +
      CapText(Sel, AssistantContextMaxActiveCharsLight)
  Else
    Begin
      Head := Ed.SourceText;
      If Head = '' Then
        Head := Ed.Lines.Text;
      Result := Result + LineEnding + 'Start of active file (truncated):' + LineEnding +
        CapText(Head, AssistantContextMaxActiveCharsLight);
    End;
  Result := Result + LineEnding + '----- end IDE context -----';
  WorkflowLogger.Debug('AssistantIDEContext',
    'Built light IDE context block (' + IntToStr(Length(Result)) + ' chars)');
End;

End.
