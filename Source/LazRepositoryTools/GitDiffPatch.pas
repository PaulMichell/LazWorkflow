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
  TGitLineNumberList = specialize TFPGList<Integer>;

Function LineIsDiffAdded(Const Line: String): Boolean;
Function LineIsDiffRemoved(Const Line: String): Boolean;
Function LineIsDiffContext(Const Line: String): Boolean;
Function LineIsHunkHeader(Const Line: String): Boolean;
Function LineIsDiffFileMeta(Const Line: String): Boolean;
{ Build a git-apply patch from a unified diff. SelectedFullLines is 1-based in Lines;
  when it is empty or Nil, FirstLine..LastLine (inclusive) is the selection. }
Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList): String;

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

Function BuildGitPartialPatch(Lines: TStrings; FirstLine, LastLine: Integer;
  SelectedFullLines: TGitLineNumberList): String;
Var
  OutLines, FileHeader, HunkBody: TStringList;
  I, LineNo, OldCount, NewCount, OldStart, NewStart: Integer;
  Line, HeaderRest: String;
  InHunk, HunkHasChange, FileHasChange: Boolean;
  Selected: Boolean;
  SpacePos: Integer;
  LastHunkLineKept: Boolean;

  Procedure FlushHunk;
  Var
    J: Integer;
    NewHeader: String;
  Begin
    If Not InHunk Then
      Exit;
    InHunk := False;
    If Not HunkHasChange Or (HunkBody.Count = 0) Then
      Begin
        HunkBody.Clear;
        Exit;
      End;
    NewHeader := Format('@@ -%d,%d +%d,%d @@', [OldStart, OldCount, NewStart, NewCount]);
    If HeaderRest <> '' Then
      NewHeader := NewHeader + HeaderRest;
    If Not FileHasChange Then
      Begin
        For J := 0 To FileHeader.Count - 1 Do
          OutLines.Add(FileHeader[J]);
        FileHasChange := True;
      End;
    OutLines.Add(NewHeader);
    For J := 0 To HunkBody.Count - 1 Do
      OutLines.Add(HunkBody[J]);
    HunkBody.Clear;
  End;

  Procedure StartHunk(Const HeaderLine: String);
  Var
    S, Part: String;
    C: Integer;
  Begin
    FlushHunk;
    InHunk := True;
    HunkHasChange := False;
    LastHunkLineKept := False;
    HunkBody.Clear;
    OldCount := 0;
    NewCount := 0;
    OldStart := 1;
    NewStart := 1;
    HeaderRest := '';
    S := HeaderLine;
    If Copy(S, 1, 3) = '@@ ' Then
      Delete(S, 1, 3);
    SpacePos := Pos('@@', S);
    If SpacePos > 0 Then
      Begin
        HeaderRest := Copy(S, SpacePos + 2, MaxInt);
        S := Trim(Copy(S, 1, SpacePos - 1));
      End;
    C := Pos('+', S);
    If C > 0 Then
      Begin
        Part := Trim(Copy(S, 1, C - 1));
        If (Length(Part) > 0) And (Part[1] = '-') Then
          Delete(Part, 1, 1);
        SpacePos := Pos(',', Part);
        If SpacePos > 0 Then
          OldStart := StrToIntDef(Copy(Part, 1, SpacePos - 1), 1)
        Else
          OldStart := StrToIntDef(Part, 1);
        Part := Trim(Copy(S, C + 1, MaxInt));
        SpacePos := Pos(',', Part);
        If SpacePos > 0 Then
          NewStart := StrToIntDef(Copy(Part, 1, SpacePos - 1), 1)
        Else
          NewStart := StrToIntDef(Part, 1);
      End;
  End;

Begin
  Result := '';
  If (Lines = Nil) Or (Lines.Count = 0) Then
    Exit;
  If (Not Assigned(SelectedFullLines) Or (SelectedFullLines.Count = 0)) And
     ((FirstLine < 1) Or (LastLine < FirstLine)) Then
    Exit;

  OutLines := TStringList.Create;
  FileHeader := TStringList.Create;
  HunkBody := TStringList.Create;
  Try
    InHunk := False;
    HunkHasChange := False;
    LastHunkLineKept := False;
    FileHasChange := False;

    For I := 0 To Lines.Count - 1 Do
      Begin
        LineNo := I + 1;
        Line := Lines[I];

        If Copy(Line, 1, 11) = 'diff --git ' Then
          Begin
            FlushHunk;
            FileHeader.Clear;
            FileHeader.Add(Line);
            FileHasChange := False;
          End
        Else If (Copy(Line, 1, 6) = 'index ') Or (Copy(Line, 1, 4) = '--- ') Or
                (Copy(Line, 1, 4) = '+++ ') Or (Copy(Line, 1, 8) = 'new file') Or
                (Copy(Line, 1, 12) = 'deleted file') Or (Copy(Line, 1, 8) = 'old mode') Or
                (Copy(Line, 1, 8) = 'new mode') Or (Copy(Line, 1, 10) = 'similarity') Or
                (Copy(Line, 1, 7) = 'rename ') Then
          Begin
            FlushHunk;
            FileHeader.Add(Line);
          End
        Else If Copy(Line, 1, 2) = '@@' Then
          StartHunk(Line)
        Else If InHunk Then
          Begin
            Selected := LineIsSelectedInPatch(LineNo, FirstLine, LastLine, SelectedFullLines);
            If (Length(Line) = 0) Or (Line[1] = ' ') Then
              Begin
                HunkBody.Add(Line);
                Inc(OldCount);
                Inc(NewCount);
                LastHunkLineKept := True;
              End
            Else If (Line[1] = '-') And (Copy(Line, 1, 3) <> '---') Then
              Begin
                If Selected Then
                  Begin
                    HunkBody.Add(Line);
                    Inc(OldCount);
                    HunkHasChange := True;
                  End
                Else
                  Begin
                    HunkBody.Add(' ' + Copy(Line, 2, MaxInt));
                    Inc(OldCount);
                    Inc(NewCount);
                  End;
                LastHunkLineKept := True;
              End
            Else If (Line[1] = '+') And (Copy(Line, 1, 3) <> '+++') Then
              Begin
                If Selected Then
                  Begin
                    HunkBody.Add(Line);
                    Inc(NewCount);
                    HunkHasChange := True;
                    LastHunkLineKept := True;
                  End
                Else
                  LastHunkLineKept := False;
              End
            Else If Line[1] = '\' Then
              Begin
                If LastHunkLineKept Then
                  HunkBody.Add(Line);
              End
            Else
              Begin
                HunkBody.Add(Line);
                Inc(OldCount);
                Inc(NewCount);
                LastHunkLineKept := True;
              End;
          End;
      End;
    FlushHunk;
    If OutLines.Count = 0 Then
      Exit;
    Result := OutLines.Text;
  Finally
    HunkBody.Free;
    FileHeader.Free;
    OutLines.Free;
  End;
End;

End.
