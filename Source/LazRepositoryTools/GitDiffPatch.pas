Unit GitDiffPatch;

{ Unified-diff line tests and partial-hunk patch construction (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fgl;

Type
  TGitDiffLineKind = (dlOther, dlMeta, dlHunk, dlContext, dlAdded, dlRemoved, dlNoNewline);
  TGitDiffLine = Record
    Kind: TGitDiffLineKind;
    OldStart, NewStart, OldCount, NewCount: Integer;
  End;
  TGitDiffLines = Array Of TGitDiffLine;
  TGitLineNumberList = specialize TFPGList<Integer>;

Function ParseGitDiff(Lines: TStrings): TGitDiffLines;
Function LineIsDiffAdded(Const Line: String): Boolean;
Function LineIsDiffRemoved(Const Line: String): Boolean;
Function LineIsDiffContext(Const Line: String): Boolean;
Function LineIsHunkHeader(Const Line: String): Boolean;
Function LineIsDiffFileMeta(Const Line: String): Boolean;
{ Build a git-apply patch from a unified diff. SelectedFullLines is 1-based in Lines;
  when it is empty or Nil, FirstLine..LastLine (inclusive) is the selection. }
Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList; Reverse: Boolean = False): String;

Implementation

Function LineIsDiffAdded(Const Line: String): Boolean;
Begin
  Result := (Length(Line) > 0) And (Line[1] = '+') And (Copy(Line, 1, 3) <> '+++');
End;

Function LineIsDiffRemoved(Const Line: String): Boolean;
Begin
  Result := (Length(Line) > 0) And (Line[1] = '-') And (Copy(Line, 1, 3) <> '---');
End;

Function LineIsDiffContext(Const Line: String): Boolean;
Begin
  Result := (Line = '') Or ((Length(Line) > 0) And (Line[1] = ' '));
End;

Function LineIsHunkHeader(Const Line: String): Boolean;
Begin
  Result := Copy(Line, 1, 2) = '@@';
End;

Function LineIsDiffFileMeta(Const Line: String): Boolean;
Begin
  Result := (Copy(Line, 1, 11) = 'diff --git ') Or (Copy(Line, 1, 6) = 'index ') Or
    (Copy(Line, 1, 4) = '--- ') Or (Copy(Line, 1, 4) = '+++ ') Or
    (Copy(Line, 1, 9) = 'new file ') Or (Copy(Line, 1, 13) = 'deleted file ') Or
    (Copy(Line, 1, 9) = 'old mode ') Or (Copy(Line, 1, 9) = 'new mode ') Or
    (Copy(Line, 1, 11) = 'similarity ') Or (Copy(Line, 1, 14) = 'dissimilarity ') Or
    (Copy(Line, 1, 12) = 'rename from ') Or (Copy(Line, 1, 10) = 'rename to ') Or
    (Copy(Line, 1, 10) = 'copy from ') Or (Copy(Line, 1, 8) = 'copy to ') Or
    (Copy(Line, 1, 13) = 'Binary files ') Or (Copy(Line, 1, 7) = 'GIT binary');
End;

Function LineIsSelectedInPatch(LineNo, FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList): Boolean;
Begin
  If Assigned(SelectedFullLines) And (SelectedFullLines.Count > 0) Then
    Result := SelectedFullLines.IndexOf(LineNo) >= 0
  Else
    Result := (LineNo >= FirstLine) And (LineNo <= LastLine);
End;

Function ParseGitDiff(Lines: TStrings): TGitDiffLines;
Var
  I, P, Q, OldLeft, NewLeft: Integer;
  S, Part: String;
  Procedure ParseRange(Const Value: String; Out Start, Count: Integer);
  Var C: Integer;
  Begin
    C := Pos(',', Value);
    If C = 0 Then Begin Start := StrToIntDef(Value, 0); Count := 1; End
    Else Begin Start := StrToIntDef(Copy(Value, 1, C - 1), 0);
      Count := StrToIntDef(Copy(Value, C + 1, MaxInt), 0); End;
  End;
Begin
  Result := Nil;
  If Lines = Nil Then Exit;
  SetLength(Result, Lines.Count);
  OldLeft := 0; NewLeft := 0;
  For I := 0 To Lines.Count - 1 Do
    Begin
      S := Lines[I];
      If (Copy(S, 1, 1) = '\') And (I > 0) And
        (Result[I-1].Kind In [dlAdded, dlRemoved, dlContext]) Then
        Result[I].Kind := dlNoNewline
      Else If (OldLeft > 0) Or (NewLeft > 0) Then
        Begin
          If Copy(S, 1, 1) = '+' Then
            Begin Result[I].Kind := dlAdded; Dec(NewLeft); End
          Else If Copy(S, 1, 1) = '-' Then
            Begin Result[I].Kind := dlRemoved; Dec(OldLeft); End
          Else If (S = '') Or (S[1] = ' ') Then
            Begin Result[I].Kind := dlContext; Dec(OldLeft); Dec(NewLeft); End
          Else Begin OldLeft := 0; NewLeft := 0; End;
        End
      Else If Copy(S, 1, 3) = '@@ ' Then
        Begin
          P := Pos(' +', S); Q := Pos(' @@', S);
          If (P > 4) And (Q > P) Then
            Begin
              Result[I].Kind := dlHunk;
              Part := Copy(S, 5, P - 5);
              ParseRange(Part, Result[I].OldStart, Result[I].OldCount);
              Part := Copy(S, P + 2, Q - P - 2);
              ParseRange(Part, Result[I].NewStart, Result[I].NewCount);
              OldLeft := Result[I].OldCount; NewLeft := Result[I].NewCount;
            End;
        End
      Else If LineIsDiffFileMeta(S) Then Result[I].Kind := dlMeta;
    End;
End;

Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList; Reverse: Boolean): String;
Var
  Parsed: TGitDiffLines;
  Headers, Body, Output: TStringList;
  I, J, OldCount, NewCount, OldBase, NewBase, Delta: Integer;
  Selected, Changed, Kept, FileWritten: Boolean;
  S: String;
Begin
  Result := '';
  If (Lines = Nil) Or (Lines.Count = 0) Then Exit;
  Parsed := ParseGitDiff(Lines);
  Headers := TStringList.Create; Body := TStringList.Create; Output := TStringList.Create;
  Try
    I := 0; Delta := 0; FileWritten := False;
    While I < Lines.Count Do
      Begin
        If Parsed[I].Kind = dlMeta Then
          Begin
            If Copy(Lines[I], 1, 11) = 'diff --git ' Then
              Begin Headers.Clear; Delta := 0; FileWritten := False; End;
            Headers.Add(Lines[I]); Inc(I); Continue;
          End;
        If Parsed[I].Kind <> dlHunk Then Begin Inc(I); Continue; End;
        OldBase := Parsed[I].OldStart - Ord(Parsed[I].OldCount > 0);
        NewBase := Parsed[I].NewStart - Ord(Parsed[I].NewCount > 0);
        If Reverse Then OldBase := NewBase - Delta Else NewBase := OldBase + Delta;
        Body.Clear; Changed := False; Kept := False; OldCount := 0; NewCount := 0;
        Inc(I);
        While (I < Lines.Count) And (Parsed[I].Kind In [dlAdded, dlRemoved, dlContext, dlNoNewline]) Do
          Begin
            S := Lines[I];
            Selected := LineIsSelectedInPatch(I + 1, FirstLine, LastLine, SelectedFullLines);
            Case Parsed[I].Kind Of
              dlContext: Begin Body.Add(S); Inc(OldCount); Inc(NewCount); Kept := True; End;
              dlAdded, dlRemoved:
                Begin
                  Kept := Selected Or ((Parsed[I].Kind = dlAdded) = Reverse);
                  If Selected Then
                    Begin
                      Body.Add(S); Changed := True;
                      If Parsed[I].Kind = dlAdded Then Inc(NewCount) Else Inc(OldCount);
                    End
                  Else If Kept Then
                    Begin Body.Add(' ' + Copy(S, 2, MaxInt)); Inc(OldCount); Inc(NewCount); End;
                End;
              dlNoNewline: If Kept Then Body.Add(S);
            End;
            Inc(I);
          End;
        If Not Changed Then Continue;
        If Not FileWritten Then
          Begin
            For J := 0 To Headers.Count - 1 Do Output.Add(Headers[J]);
            FileWritten := True;
          End;
        Output.Add(Format('@@ -%d,%d +%d,%d @@',
          [OldBase + Ord(OldCount > 0), OldCount, NewBase + Ord(NewCount > 0), NewCount]));
        Output.AddStrings(Body);
        Inc(Delta, NewCount - OldCount);
      End;
    Result := Output.Text;
  Finally Output.Free; Body.Free; Headers.Free; End;
End;

End.
