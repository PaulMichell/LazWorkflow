Unit AssistantExactReplace;

{ Exact buffer replacement and the native read-revision store (c) 2026 Michell Computing.

  ApplyExactReplace is the one matcher. The broker and the native tools both call it,
  so a repeated old_text fails with the broker's sentence and changes nothing.
  Native revisions are the text last read for a path. They are not a second wording. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Const
  { Same ceiling as the broker's MaxBufferBytes. A larger replacement is refused before any write. }
  ExactReplaceMaxBytes = 1048576;
  StaleBufferRevisionMessage = 'Stale buffer revision; read the buffer again before using this request.';
  SnapshotBudgetMessage = 'Snapshot budget exhausted.';
  EditorOwnsPathMessage = 'An editor buffer already owns this path; use its revision tools.';
  DestinationExistsMessage = 'Destination already exists; new-file creation never overwrites.';

/// Exact match. Fails with Updated unused when old_text is missing or is not unique and ReplaceAll is false.
Function ApplyExactReplace(Const Source, OldText, NewText: String; ReplaceAll: Boolean;
  Out Updated, ErrorText: String): Boolean;
/// Records the full text last read for Path and returns its revision. Empty when Path is empty, the text
/// exceeds ExactReplaceMaxBytes, or the session snapshot budget is exhausted.
Function RememberNativeRead(Const Path, Text: String): String;
/// True when Revision is the revision last issued for Path and CurrentText is still that text.
Function NativeRevisionCurrent(Const Path, Revision, CurrentText: String; Out ErrorText: String): Boolean;
/// write_file gate. An empty revision may create a path that is neither on disk nor open. Anything else
/// must match the text last read. Does not write.
Function AcceptNativeWrite(Const Path, Revision, CurrentText: String; Exists, EditorOpen: Boolean;
  Out ErrorText: String): Boolean;
/// replace_in_file gate. Checks the revision, then ApplyExactReplace. On failure Updated is empty and the
/// caller must not write.
Function PrepareNativeReplace(Const Path, Revision, CurrentText, OldText, NewText: String; ReplaceAll: Boolean;
  Out Updated, ErrorText: String): Boolean;
/// Drops the session snapshots. A test uses this so one process can start from an empty store.
Procedure ResetNativeReads;

Implementation

Uses
  SysUtils;

Const
  ExactReplaceMaxSnapshotBytes = 8388608;

Type
  TNativeSnapshot = Record
    Path, Text, Revision: String;
  End;

Var
  NativeSnapshots: Array Of TNativeSnapshot;
  NativeRevisionCounter: Integer;

Function ApplyExactReplace(Const Source, OldText, NewText: String; ReplaceAll: Boolean;
  Out Updated, ErrorText: String): Boolean;
Var
  Count, P: Integer;
Begin
  Result := False;
  Updated := '';
  ErrorText := '';
  If OldText = '' Then
    Begin
      ErrorText := 'old_text must not be empty.';
      Exit;
    End;
  Count := 0;
  P := 1;
  While P <= Length(Source) - Length(OldText) + 1 Do
    If Copy(Source, P, Length(OldText)) = OldText Then
      Begin
        Inc(Count);
        Inc(P, Length(OldText));
        If (Count > 1) And Not ReplaceAll Then
          Begin
            ErrorText := 'old_text occurs more than once; set replace_all to replace every match.';
            Exit;
          End;
      End
    Else
      Inc(P);
  If Count = 0 Then
    Begin
      ErrorText := 'old_text not found in the buffer.';
      Exit;
    End;
  If ReplaceAll Then
    Updated := StringReplace(Source, OldText, NewText, [rfReplaceAll])
  Else
    Begin
      P := Pos(OldText, Source);
      Updated := Copy(Source, 1, P - 1) + NewText + Copy(Source, P + Length(OldText), MaxInt);
    End;
  If Length(Updated) > ExactReplaceMaxBytes Then
    Begin
      Updated := '';
      ErrorText := 'Replacement exceeds the buffer limit.';
      Exit;
    End;
  Result := True;
End;

Function RememberNativeRead(Const Path, Text: String): String;
Var
  I, Index, Bytes: Integer;
Begin
  Result := '';
  If (Path = '') Or (Length(Text) > ExactReplaceMaxBytes) Then Exit;
  Index := -1;
  Bytes := 0;
  For I := 0 To High(NativeSnapshots) Do
    If NativeSnapshots[I].Path = Path Then
      Index := I
    Else
      Inc(Bytes, Length(NativeSnapshots[I].Text));
  If Bytes + Length(Text) > ExactReplaceMaxSnapshotBytes Then Exit;
  If Index < 0 Then
    Begin
      Index := Length(NativeSnapshots);
      SetLength(NativeSnapshots, Index + 1);
    End;
  Inc(NativeRevisionCounter);
  Result := 'native:' + IntToStr(NativeRevisionCounter);
  NativeSnapshots[Index].Path := Path;
  NativeSnapshots[Index].Text := Text;
  NativeSnapshots[Index].Revision := Result;
End;

Function NativeRevisionCurrent(Const Path, Revision, CurrentText: String; Out ErrorText: String): Boolean;
Var
  I, Index: Integer;
Begin
  Result := False;
  ErrorText := StaleBufferRevisionMessage;
  Index := -1;
  For I := 0 To High(NativeSnapshots) Do
    If (Revision <> '') And (NativeSnapshots[I].Path = Path) And (NativeSnapshots[I].Revision = Revision) Then
      Index := I;
  If (Index < 0) Or (NativeSnapshots[Index].Text <> CurrentText) Then Exit;
  ErrorText := '';
  Result := True;
End;

Function AcceptNativeWrite(Const Path, Revision, CurrentText: String; Exists, EditorOpen: Boolean;
  Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  { Same fork as the broker: an empty revision is the create path, never an overwrite. }
  If Revision = '' Then
    Begin
      If EditorOpen Then
        ErrorText := EditorOwnsPathMessage
      Else If Exists Then
        ErrorText := DestinationExistsMessage
      Else
        Result := True;
      Exit;
    End;
  Result := NativeRevisionCurrent(Path, Revision, CurrentText, ErrorText);
End;

Function PrepareNativeReplace(Const Path, Revision, CurrentText, OldText, NewText: String; ReplaceAll: Boolean;
  Out Updated, ErrorText: String): Boolean;
Begin
  Result := False;
  Updated := '';
  ErrorText := '';
  If Not NativeRevisionCurrent(Path, Revision, CurrentText, ErrorText) Then Exit;
  Result := ApplyExactReplace(CurrentText, OldText, NewText, ReplaceAll, Updated, ErrorText);
  If Not Result Then Updated := '';
End;

Procedure ResetNativeReads;
Begin
  SetLength(NativeSnapshots, 0);
End;

End.
