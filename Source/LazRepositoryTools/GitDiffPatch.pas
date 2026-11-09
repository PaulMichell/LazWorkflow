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
  TGitNewFileLines = Array Of Integer;
  TGitLineNumberList = specialize TFPGList<Integer>;

Function ParseGitDiff(Lines: TStrings): TGitDiffLines;
{ New-file line for each unified-diff line. Context and added lines use their
  new-file number. A removed line uses the new-file line it sits in front of.
  Headers and "\ No newline" are 0. }
Function GitDiffNewFileLines(Lines: TStrings): TGitNewFileLines;
Function LineIsDiffAdded(Const Line: String): Boolean;
Function LineIsDiffRemoved(Const Line: String): Boolean;
Function LineIsDiffContext(Const Line: String): Boolean;
Function LineIsHunkHeader(Const Line: String): Boolean;
Function LineIsDiffFileMeta(Const Line: String): Boolean;
{ Build a git-apply patch from a unified diff. SelectedFullLines is 1-based in Lines;
  when it is empty or Nil, FirstLine..LastLine (inclusive) is the selection. }
Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList; Reverse: Boolean = False): String;
{ 1 when the patch uses a synthetic a/, b/, i/ or w/ prefix; 0 when it does not.
  git apply defaults to -p1, which deletes a real directory from an unprefixed path. }
Function GitPatchStripCount(Const PatchText: String): Integer;

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

Function GitDiffNewFileLines(Lines: TStrings): TGitNewFileLines;
Var
  Parsed: TGitDiffLines;
  I, NewLine, Anchor: Integer;
Begin
  Result := Nil;
  If Lines = Nil Then
    Exit;
  SetLength(Result, Lines.Count);
  Parsed := ParseGitDiff(Lines);
  NewLine := 0;
  Anchor := 0;
  For I := 0 To Lines.Count - 1 Do
    Begin
      Result[I] := 0;
      If I > High(Parsed) Then
        Continue;
      Case Parsed[I].Kind Of
        dlHunk:
          Begin
            Anchor := Parsed[I].NewStart;
            If Anchor < 0 Then
              Anchor := 0;
            { A zero-count hunk has no new lines; removed lines use the anchor. }
            If Parsed[I].NewCount > 0 Then
              NewLine := Anchor
            Else
              NewLine := 0;
          End;
        dlAdded, dlContext:
          Begin
            If NewLine < 1 Then
              Begin
                If Anchor > 0 Then
                  NewLine := Anchor
                Else
                  NewLine := 1;
              End;
            Result[I] := NewLine;
            Inc(NewLine);
          End;
        dlRemoved:
          Begin
            If NewLine > 0 Then
              Result[I] := NewLine
            Else If Anchor > 0 Then
              Result[I] := Anchor
            Else
              Result[I] := 1;
          End;
      Else
        Result[I] := 0;
      End;
    End;
End;

Function BeforeTab(Const Value: String): String;
Var
  TabAt: Integer;
Begin
  TabAt := Pos(#9, Value);
  If TabAt = 0 Then Result := Value Else Result := Copy(Value, 1, TabAt - 1);
End;

Function IsSyntheticGitPrefix(Const Prefix: String): Boolean;
Begin
  Result := (Prefix = 'a') Or (Prefix = 'b') Or (Prefix = 'i') Or (Prefix = 'w');
End;

Function StripKnownGitPrefix(Const Token: String): String;
Var
  Slash: Integer;
Begin
  Slash := Pos('/', Token);
  If (Slash > 1) And IsSyntheticGitPrefix(Copy(Token, 1, Slash - 1)) Then
    Result := Copy(Token, Slash + 1, MaxInt)
  Else
    Result := Token;
End;

Function DecodeGitEscapes(Const Value: String): String;
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
                If Octal <= 255 Then
                  Result := Result + Chr(Octal);
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
      While SplitAt <= Length(Rest) Do
        Begin
          If Rest[SplitAt] = '\' Then
            Inc(SplitAt, 2)
          Else If Rest[SplitAt] = '"' Then
            Break
          Else
            Inc(SplitAt);
        End;
      Result := DecodeGitEscapes(Copy(Rest, 2, SplitAt - 2));
      If (SplitAt <= Length(Rest)) And (Rest[SplitAt] = '"') Then
        Inc(SplitAt);
      If SplitAt <= Length(Rest) Then
        Rest := Copy(Rest, SplitAt, MaxInt)
      Else
        Rest := '';
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

Procedure ParseDiffGitPaths(Const Line: String; Out OldPath, NewPath: String);
Var
  Rest: String;
Begin
  OldPath := '';
  NewPath := '';
  If Copy(Line, 1, 11) <> 'diff --git ' Then Exit;
  Rest := Copy(Line, 12, MaxInt);
  If (Rest <> '') And (Rest[1] = '"') Then
    Begin
      OldPath := StripKnownGitPrefix(NextGitToken(Rest));
      NewPath := StripKnownGitPrefix(NextGitToken(Rest));
      Exit;
    End;
  { Unquoted names may contain spaces. The prefix pair is the reliable split. }
  If SplitMarkedPair(Rest, 'a/', ' b/', OldPath, NewPath) Then Exit;
  If SplitMarkedPair(Rest, 'i/', ' w/', OldPath, NewPath) Then Exit;
  OldPath := StripKnownGitPrefix(NextGitToken(Rest));
  NewPath := StripKnownGitPrefix(NextGitToken(Rest));
End;

Function IsNullDiffSide(Const Line, Marker: String): Boolean;
Var
  Rest: String;
Begin
  Result := False;
  If Copy(Line, 1, Length(Marker)) <> Marker Then Exit;
  Rest := BeforeTab(Copy(Line, Length(Marker) + 1, MaxInt));
  Result := (Rest = '/dev/null') Or (Rest = 'NUL') Or (Rest = '"/dev/null"') Or (Rest = '"NUL"');
End;

Function HeaderSidePath(Const Line, Marker: String): String;
Var
  Rest: String;
Begin
  Result := '';
  If Copy(Line, 1, Length(Marker)) <> Marker Then Exit;
  If IsNullDiffSide(Line, Marker) Then Exit;
  Rest := BeforeTab(Copy(Line, Length(Marker) + 1, MaxInt));
  If (Rest <> '') And (Rest[1] = '"') Then
    Result := StripKnownGitPrefix(NextGitToken(Rest))
  Else
    Result := StripKnownGitPrefix(Rest);
End;

Function PathNeedsGitQuotes(Const Path: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 1 To Length(Path) Do
    If (Path[I] <= ' ') Or (Path[I] = '"') Or (Path[I] = '\') Or (Ord(Path[I]) >= 127) Then
      Exit(True);
End;

Function EscapeGitPath(Const Path: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To Length(Path) Do
    Case Path[I] Of
      '\', '"': Result := Result + '\' + Path[I];
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
    Else
      Result := Result + Path[I];
    End;
End;

Function FormatGitSideLine(Const Marker, Prefix, Path: String): String;
Var
  FullPath: String;
Begin
  FullPath := Prefix + Path;
  If PathNeedsGitQuotes(FullPath) Then
    Result := Marker + '"' + EscapeGitPath(FullPath) + '"'
  Else
    Result := Marker + FullPath;
End;

{ A partial selection can leave lines on a side the original headers called
  /dev/null. Keep create or delete headers only when that side is still empty.
  A reverse unstage of a deletion has an empty new side and must stay a
  deletion, or git apply looks for a file the index has already removed. }
Procedure WritePartialFileHeaders(Headers, Output: TStrings; Const OldPath, NewPath: String;
  HasOld, HasNew: Boolean);
Var
  I: Integer;
  Line, Parsed, OldSide, NewSide: String;
  RewriteOld, RewriteNew: Boolean;
Begin
  If (Headers = Nil) Or (Output = Nil) Then Exit;
  RewriteOld := False;
  RewriteNew := False;
  OldSide := '';
  NewSide := '';
  For I := 0 To Headers.Count - 1 Do
    Begin
      Line := Headers[I];
      If IsNullDiffSide(Line, '--- ') Then RewriteOld := HasOld
      Else If IsNullDiffSide(Line, '+++ ') Then RewriteNew := HasNew
      Else If Copy(Line, 1, 4) = '--- ' Then
        Begin
          Parsed := HeaderSidePath(Line, '--- ');
          If Parsed <> '' Then OldSide := Parsed;
        End
      Else If Copy(Line, 1, 4) = '+++ ' Then
        Begin
          Parsed := HeaderSidePath(Line, '+++ ');
          If Parsed <> '' Then NewSide := Parsed;
        End;
    End;
  If OldSide = '' Then OldSide := OldPath;
  If NewSide = '' Then NewSide := NewPath;
  If (OldSide = '') Or (OldSide = '/dev/null') Or (OldSide = 'NUL') Then OldSide := NewSide;
  If (NewSide = '') Or (NewSide = '/dev/null') Or (NewSide = 'NUL') Then NewSide := OldSide;
  If (OldSide = '/dev/null') Or (OldSide = 'NUL') Then OldSide := '';
  If (NewSide = '/dev/null') Or (NewSide = 'NUL') Then NewSide := '';
  If OldSide = '' Then RewriteOld := False;
  If NewSide = '' Then RewriteNew := False;
  For I := 0 To Headers.Count - 1 Do
    Begin
      Line := Headers[I];
      If RewriteOld And (Copy(Line, 1, 9) = 'new file ') Then Continue;
      If RewriteNew And (Copy(Line, 1, 13) = 'deleted file ') Then Continue;
      If RewriteOld And IsNullDiffSide(Line, '--- ') Then Line := FormatGitSideLine('--- ', 'a/', OldSide)
      Else If RewriteNew And IsNullDiffSide(Line, '+++ ') Then Line := FormatGitSideLine('+++ ', 'b/', NewSide);
      Output.Add(Line);
    End;
End;

Function GitPatchStripCount(Const PatchText: String): Integer;
Var
  Lines: TStringList;
  I: Integer;
  Line, Rest, OldToken, NewToken, OldHead, NewHead: String;
  Slash: Integer;
Begin
  { git apply -p1 is the default. Use it unless the diff has no synthetic prefix. }
  Result := 1;
  Lines := TStringList.Create;
  Try
    Lines.Text := PatchText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Copy(Line, 1, 11) <> 'diff --git ' Then Continue;
        Rest := Copy(Line, 12, MaxInt);
        If (Rest <> '') And (Rest[1] = '"') Then
          Begin
            OldToken := NextGitToken(Rest);
            NewToken := NextGitToken(Rest);
          End
        Else If SplitMarkedPair(Rest, 'a/', ' b/', OldToken, NewToken) Then
          Begin
            OldToken := 'a/' + OldToken;
            NewToken := 'b/' + NewToken;
          End
        Else If SplitMarkedPair(Rest, 'i/', ' w/', OldToken, NewToken) Then
          Begin
            OldToken := 'i/' + OldToken;
            NewToken := 'w/' + NewToken;
          End
        Else
          Begin
            OldToken := NextGitToken(Rest);
            NewToken := NextGitToken(Rest);
          End;
        If OldToken = NewToken Then
          Exit(0);
        Slash := Pos('/', OldToken);
        If Slash <= 1 Then Exit(0);
        OldHead := Copy(OldToken, 1, Slash - 1);
        Slash := Pos('/', NewToken);
        If Slash <= 1 Then Exit(0);
        NewHead := Copy(NewToken, 1, Slash - 1);
        If IsSyntheticGitPrefix(OldHead) And IsSyntheticGitPrefix(NewHead) And (OldHead <> NewHead) Then
          Result := 1
        Else
          Result := 0;
        Exit;
      End;
  Finally
    Lines.Free;
  End;
End;

Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList; Reverse: Boolean): String;
Var
  Parsed: TGitDiffLines;
  Headers, Body, Hunks, Output: TStringList;
  I, OldCount, NewCount, OldBase, NewBase, Delta: Integer;
  Selected, Changed, Kept, HasOld, HasNew: Boolean;
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
    WritePartialFileHeaders(Headers, Output, FileOld, FileNew, HasOld, HasNew);
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
                    End;
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
