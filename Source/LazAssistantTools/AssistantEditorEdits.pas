Unit AssistantEditorEdits;

{ Version-checked, undoable source-editor updates. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, Types, SrcEditorIntf;

  { Call on the IDE thread. ExpectedText is the exact source snapshot read by the
  caller. A failed precondition makes no changes. Does not save to disk. }
Function ApplyAssistantEditorText(Editor: TSourceEditorInterface;
    Const ExpectedText, NewText: String; Out ErrorText: String): Boolean;

Implementation

Function IsBoundary(Const S: String; Offset: Integer): Boolean;
Begin
  Result := True;
  If (Offset <= 1) Or (Offset > Length(S)) Then Exit;
  Result := ((Ord(S[Offset]) And $C0) <> $80) And
    Not ((S[Offset - 1] = #13) And (S[Offset] = #10));
End;

Function TextPosition(Const S: String; Offset: Integer): TPoint;
Var
  I: Integer;
Begin
  Result := Point(1, 1);
  I := 1;
  While I < Offset Do
    Begin
      If S[I] In [#10, #13] Then
        Begin
          If (S[I] = #13) And (I + 1 < Offset) And (S[I + 1] = #10) Then Inc(I);
          Inc(Result.Y);
          Result.X := 1;
        End
          Else
            Inc(Result.X);
      Inc(I);
    End;
End;

Function ApplyAssistantEditorText(Editor: TSourceEditorInterface;
    Const ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Var
  Prefix, Suffix, OldLength, NewLength: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(Editor) Then
    Begin
      ErrorText := 'Source editor is no longer available.';
      Exit;
    End;
  If Editor.ReadOnly Then
    Begin
      ErrorText := 'Source editor is read-only.';
      Exit;
    End;
  If Editor.SourceText <> ExpectedText Then
    Begin
      ErrorText := 'Source buffer changed after it was read; read it again before editing.';
      Exit;
    End;
  If ExpectedText = NewText Then Exit(True);
  OldLength := Length(ExpectedText);
  NewLength := Length(NewText);
  Prefix := 0;
  While (Prefix < OldLength) And (Prefix < NewLength) And
    (ExpectedText[Prefix + 1] = NewText[Prefix + 1]) Do Inc(Prefix);
  While Not IsBoundary(ExpectedText, Prefix + 1) Or
    Not IsBoundary(NewText, Prefix + 1) Do Dec(Prefix);
  Suffix := 0;
  While (Suffix < OldLength - Prefix) And (Suffix < NewLength - Prefix) And
    (ExpectedText[OldLength - Suffix] = NewText[NewLength - Suffix]) Do Inc(Suffix);
  While Not IsBoundary(ExpectedText, OldLength - Suffix + 1) Or
    Not IsBoundary(NewText, NewLength - Suffix + 1) Do Dec(Suffix);
  Try
    { ReplaceText performs Begin/EndUpdate and Begin/EndUndoBlock internally.
      SourceText assignment would clear the user's entire Undo history. }
    Editor.ReplaceText(TextPosition(ExpectedText, Prefix + 1),
      TextPosition(ExpectedText, OldLength - Suffix + 1),
      Copy(NewText, Prefix + 1, NewLength - Prefix - Suffix));
    Result := True;
  Except
    On E: Exception Do
      ErrorText := 'Editor update failed; inspect the buffer before retrying: ' + E.Message;
  End;
End;

End.
