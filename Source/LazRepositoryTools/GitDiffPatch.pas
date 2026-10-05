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
    If C = 0 Then
      Begin
        Start := StrToIntDef(Value, 0);
        Count := 1;
      End
    Else
      Begin
        Start := StrToIntDef(Copy(Value, 1, C - 1), 0);
        Count := StrToIntDef(Copy(Value, C + 1, MaxInt), 0);
      End;
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
            Begin
              Result[I].Kind := dlAdded;
              Dec(NewLeft);
            End
          Else If Copy(S, 1, 1) = '-' Then
            Begin
              Result[I].Kind := dlRemoved;
              Dec(OldLeft);
            End
          Else If (S = '') Or (S[1] = ' ') Then
            Begin
              Result[I].Kind := dlContext;
              Dec(OldLeft);
              Dec(NewLeft);
            End
          Else
            Begin
              OldLeft := 0;
              NewLeft := 0;
            End;
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

Function BeforeTab(Const Value: String): String;
Var
  TabAt: Integer;
Begin
  TabAt := Pos(#9, Value);
  If TabAt = 0 Then Result := Value Else Result := Copy(Value, 1, TabAt - 1);
End;

Function StripGitSide(Const Token: String): String;
Begin
  If Copy(Token, 1, 2) = 'a/' Then Result := Copy(Token, 3, MaxInt)
  Else If Copy(Token, 1, 2) = 'b/' Then Result := Copy(Token, 3, MaxInt)
  Else Result := Token;
End;

Function NextGitToken(Var Rest: String): String;
Var
  SplitAt: Integer;
Begin
  Result := '';
  Rest := TrimLeft(Rest);
  If Rest = '' Then Exit;
  If Rest[1] = '"' Then
    Begin
      SplitAt := 2;
      While (SplitAt <= Length(Rest)) And (Rest[SplitAt] <> '"') Do Inc(SplitAt);
      Result := Copy(Rest, 2, SplitAt - 2);
      If SplitAt < Length(Rest) Then Rest := Copy(Rest, SplitAt + 1, MaxInt) Else Rest := '';
    End
  Else
    Begin
      SplitAt := Pos(' ', Rest);
      If SplitAt = 0 Then
        Begin
          Result := Rest;
          Rest := '';
        End
      Else
        Begin
          Result := Copy(Rest, 1, SplitAt - 1);
          Rest := Copy(Rest, SplitAt + 1, MaxInt);
        End;
    End;
End;

Procedure ParseDiffGitPaths(Const Line: String; Out OldPath, NewPath: String);
Var
  Rest: String;
Begin
  OldPath := '';
  NewPath := '';
  If Copy(Line, 1, 11) <> 'diff --git ' Then Exit;
  Rest := Copy(Line, 12, MaxInt);
  OldPath := StripGitSide(NextGitToken(Rest));
  NewPath := StripGitSide(NextGitToken(Rest));
End;

{ A partial selection can leave lines on a side the original headers called
  /dev/null. Keep create or delete headers only for a whole-file result. }
Procedure WritePartialFileHeaders(Headers, Output: TStrings; Const OldPath, NewPath: String;
  HasOld, HasNew, OmittedRemoval: Boolean);
Var
  I: Integer;
  Line, OldSide, NewSide: String;
  RewriteOld, RewriteNew: Boolean;
Begin
  If (Headers = Nil) Or (Output = Nil) Then Exit;
  RewriteOld := False;
  RewriteNew := False;
  OldSide := OldPath;
  NewSide := NewPath;
  For I := 0 To Headers.Count - 1 Do
    Begin
      Line := Headers[I];
      If Copy(Line, 1, 13) = '--- /dev/null' Then RewriteOld := HasOld
      Else If Copy(Line, 1, 13) = '+++ /dev/null' Then RewriteNew := HasNew Or OmittedRemoval
      Else If (OldSide = '') And (Copy(Line, 1, 6) = '--- a/') Then OldSide := BeforeTab(Copy(Line, 7, MaxInt))
      Else If (NewSide = '') And (Copy(Line, 1, 6) = '+++ b/') Then NewSide := BeforeTab(Copy(Line, 7, MaxInt));
    End;
  If (OldSide = '') Or (OldSide = '/dev/null') Then OldSide := NewSide;
  If (NewSide = '') Or (NewSide = '/dev/null') Then NewSide := OldSide;
  If OldSide = '/dev/null' Then OldSide := '';
  If NewSide = '/dev/null' Then NewSide := '';
  If OldSide = '' Then RewriteOld := False;
  If NewSide = '' Then RewriteNew := False;
  For I := 0 To Headers.Count - 1 Do
    Begin
      Line := Headers[I];
      If RewriteOld And (Copy(Line, 1, 9) = 'new file ') Then Continue;
      If RewriteNew And (Copy(Line, 1, 13) = 'deleted file ') Then Continue;
      If RewriteOld And (Copy(Line, 1, 13) = '--- /dev/null') Then Line := '--- a/' + OldSide
      Else If RewriteNew And (Copy(Line, 1, 13) = '+++ /dev/null') Then Line := '+++ b/' + NewSide;
      Output.Add(Line);
    End;
End;

Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList; Reverse: Boolean): String;
Var
  Parsed: TGitDiffLines;
  Headers, Body, Hunks, Output: TStringList;
  I, OldCount, NewCount, OldBase, NewBase, Delta: Integer;
  Selected, Changed, Kept, HasOld, HasNew, OmittedRemoval: Boolean;
  FileOld, FileNew, S: String;

  Procedure NoteEmitted(Const Emitted: String);
  Begin
    If (Emitted = '') Or ((Length(Emitted) > 0) And (Emitted[1] = ' ')) Then
      Begin
        HasOld := True;
        HasNew := True;
      End
    Else If Emitted[1] = '+' Then HasNew := True
    Else If Emitted[1] = '-' Then HasOld := True;
  End;

  Procedure FlushFile;
  Begin
    If Hunks.Count = 0 Then Exit;
    WritePartialFileHeaders(Headers, Output, FileOld, FileNew, HasOld, HasNew, OmittedRemoval);
    Output.AddStrings(Hunks);
    Hunks.Clear;
  End;

Begin
  Result := '';
  If (Lines = Nil) Or (Lines.Count = 0) Then Exit;
  Parsed := ParseGitDiff(Lines);
  Headers := TStringList.Create;
  Body := TStringList.Create;
  Hunks := TStringList.Create;
  Output := TStringList.Create;
  Try
    I := 0;
    Delta := 0;
    HasOld := False;
    HasNew := False;
    OmittedRemoval := False;
    FileOld := '';
    FileNew := '';
    While I < Lines.Count Do
      Begin
        If Parsed[I].Kind = dlMeta Then
          Begin
            If Copy(Lines[I], 1, 11) = 'diff --git ' Then
              Begin
                FlushFile;
                Headers.Clear;
                Delta := 0;
                HasOld := False;
                HasNew := False;
                OmittedRemoval := False;
                ParseDiffGitPaths(Lines[I], FileOld, FileNew);
              End;
            Headers.Add(Lines[I]);
            Inc(I);
            Continue;
          End;
        If Parsed[I].Kind <> dlHunk Then
          Begin
            Inc(I);
            Continue;
          End;
        OldBase := Parsed[I].OldStart - Ord(Parsed[I].OldCount > 0);
        NewBase := Parsed[I].NewStart - Ord(Parsed[I].NewCount > 0);
        If Reverse Then OldBase := NewBase - Delta Else NewBase := OldBase + Delta;
        Body.Clear;
        Changed := False;
        Kept := False;
        OldCount := 0;
        NewCount := 0;
        Inc(I);
        While (I < Lines.Count) And (Parsed[I].Kind In [dlAdded, dlRemoved, dlContext, dlNoNewline]) Do
          Begin
            S := Lines[I];
            Selected := LineIsSelectedInPatch(I + 1, FirstLine, LastLine, SelectedFullLines);
            Case Parsed[I].Kind Of
              dlContext:
                Begin
                  Body.Add(S);
                  NoteEmitted(S);
                  Inc(OldCount);
                  Inc(NewCount);
                  Kept := True;
                End;
              dlAdded, dlRemoved:
                Begin
                  Kept := Selected Or ((Parsed[I].Kind = dlAdded) = Reverse);
                  If Selected Then
                    Begin
                      Body.Add(S);
                      NoteEmitted(S);
                      Changed := True;
                      If Parsed[I].Kind = dlAdded Then Inc(NewCount) Else Inc(OldCount);
                    End
                  Else If Kept Then
                    Begin
                      Body.Add(' ' + Copy(S, 2, MaxInt));
                      NoteEmitted(' ' + Copy(S, 2, MaxInt));
                      Inc(OldCount);
                      Inc(NewCount);
                    End
                  Else If Parsed[I].Kind = dlRemoved Then OmittedRemoval := True;
                End;
              dlNoNewline: If Kept Then Body.Add(S);
            Else
            End;
            Inc(I);
          End;
        If Not Changed Then Continue;
        Hunks.Add(Format('@@ -%d,%d +%d,%d @@',
          [OldBase + Ord(OldCount > 0), OldCount, NewBase + Ord(NewCount > 0), NewCount]));
        Hunks.AddStrings(Body);
        Inc(Delta, NewCount - OldCount);
      End;
    FlushFile;
    Result := Output.Text;
  Finally
    Output.Free;
    Hunks.Free;
    Body.Free;
    Headers.Free;
  End;
End;

End.
