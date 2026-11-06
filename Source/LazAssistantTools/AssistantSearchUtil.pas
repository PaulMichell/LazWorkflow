Unit AssistantSearchUtil;

{ Grep glob / regex detection and read_file line-range helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes;

{ True when the pattern is almost certainly a regex (unescaped | is the usual case). }
Function PatternLooksLikeRegex(Const Pattern: String): Boolean;
{ Empty glob matches every name. Supports .pas, pas, *.pas, and brace lists. }
Function FileMatchesSearchGlob(Const FileName, Glob: String): Boolean;
{ start_line is 1-based. limit is a line count. If limit is 0 and end_line < start_line,
  end_line is treated as a line count (Grok Build habit). }
Procedure ResolveReadLineRange(Var StartLine, EndLine: Integer; Limit: Integer);
{ Empty when the query can be searched. Explicit regex, or a pattern that looks like one, is compiled. }
Function SearchPatternError(Const Query: String; ExplicitRegex: Boolean): String;
{ Case-insensitive line search used by search_in_project and lazarus_search_in_project.
  files_only emits the path once. Capped is true when MaxResults is reached; the cap notice is already appended. }
Function MatchSearchLines(Const Query, RelativePath: String; Lines: TStrings; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
{ Search one text with those rules. MaxResults must be 1..200. }
Function SearchTextMatches(Const Query, RelativePath, Text: String; FilesOnly: Boolean; MaxResults: Integer;
  Out ResultText, ErrorText: String): Boolean;

Implementation

Uses
  SysUtils, RegExpr;

Const
  SearchMatchLineChars = 512;

Function PatternLooksLikeRegex(Const Pattern: String): Boolean;
Begin
  Result := Pos('|', Pattern) > 0;
End;

Function FileMatchesSearchGlob(Const FileName, Glob: String): Boolean;
Var
  G, Ext, Prefix, Suffix, Alts, Alt, Combined: String;
  BraceOpen, BraceClose, CommaAt: Integer;
Begin
  G := Trim(Glob);
  If (G = '') Or (G = '*') Or (G = '*.*') Then
    Begin
      Result := True;
      Exit;
    End;
  BraceOpen := Pos('{', G);
  BraceClose := 0;
  If BraceOpen > 0 Then
    BraceClose := Pos('}', G);
  If (BraceOpen > 0) And (BraceClose > BraceOpen) Then
    Begin
      Prefix := Copy(G, 1, BraceOpen - 1);
      Suffix := Copy(G, BraceClose + 1, MaxInt);
      Alts := Copy(G, BraceOpen + 1, BraceClose - BraceOpen - 1);
      Result := False;
      While Alts <> '' Do
        Begin
          CommaAt := Pos(',', Alts);
          If CommaAt < 1 Then
            Begin
              Alt := Trim(Alts);
              Alts := '';
            End
          Else
            Begin
              Alt := Trim(Copy(Alts, 1, CommaAt - 1));
              Delete(Alts, 1, CommaAt);
            End;
          If Alt = '' Then
            Continue;
          Combined := Prefix + Alt + Suffix;
          If FileMatchesSearchGlob(FileName, Combined) Then
            Begin
              Result := True;
              Exit;
            End;
        End;
      Exit;
    End;
  Ext := LowerCase(ExtractFileExt(FileName));
  G := LowerCase(G);
  If (Length(G) >= 2) And (G[1] = '*') And (G[2] = '.') Then
    G := Copy(G, 2, MaxInt)
  Else If (Length(G) > 0) And (G[1] <> '.') And (Pos('.', G) < 1) Then
    G := '.' + G;
  Result := Ext = G;
  If Not Result Then
    Result := LowerCase(ExtractFileName(FileName)) = LowerCase(Trim(Glob));
End;

Procedure ResolveReadLineRange(Var StartLine, EndLine: Integer; Limit: Integer);
Begin
  If StartLine < 1 Then
    StartLine := 1;
  If Limit > 0 Then
    EndLine := StartLine + Limit - 1
  Else If (EndLine > 0) And (EndLine < StartLine) Then
    EndLine := StartLine + EndLine - 1;
End;

Function SearchPatternError(Const Query: String; ExplicitRegex: Boolean): String;
Var
  Re: TRegExpr;
Begin
  Result := '';
  If Not (ExplicitRegex Or PatternLooksLikeRegex(Query)) Then
    Exit;
  Re := TRegExpr.Create;
  Try
    Try
      Re.ModifierI := True;
      Re.Expression := Query;
    Except
      On E: Exception Do
        Result := 'Invalid regular expression: ' + E.Message;
    End;
  Finally
    Re.Free;
  End;
End;

Function MatchSearchLines(Const Query, RelativePath: String; Lines: TStrings; UseRegex, FilesOnly: Boolean;
  MaxResults, MaxLineChars: Integer; Var MatchCount: Integer; Var ResultText: String; Out Capped: Boolean;
  Out ErrorText: String): Boolean;
Var
  Re: TRegExpr;
  LineNo: Integer;
  LineText, LowerQuery: String;
  Hit, Emitted: Boolean;
Begin
  Result := False;
  Capped := False;
  ErrorText := '';
  Re := Nil;
  If Not Assigned(Lines) Then
    Begin
      ErrorText := 'Search text is unavailable.';
      Exit;
    End;
  If UseRegex Or PatternLooksLikeRegex(Query) Then
    Begin
      Re := TRegExpr.Create;
      Try
        Re.ModifierI := True;
        Re.Expression := Query;
      Except
        On E: Exception Do
          Begin
            ErrorText := 'Invalid regular expression: ' + E.Message;
            FreeAndNil(Re);
            Exit;
          End;
      End;
    End;
  Try
    LowerQuery := LowerCase(Query);
    Emitted := False;
    For LineNo := 0 To Lines.Count - 1 Do
      Begin
        LineText := Lines[LineNo];
        If Assigned(Re) Then
          Begin
            If Length(LineText) > MaxLineChars Then
              Continue;
            Hit := Re.Exec(LineText);
          End
        Else
          Hit := Pos(LowerQuery, LowerCase(LineText)) > 0;
        If Not Hit Then
          Continue;
        If FilesOnly Then
          Begin
            If Emitted Then
              Continue;
            Emitted := True;
            Inc(MatchCount);
            ResultText := ResultText + RelativePath + LineEnding;
          End
        Else
          Begin
            Inc(MatchCount);
            ResultText := ResultText + Format('%s:%d: %s', [RelativePath, LineNo + 1, Trim(LineText)]) + LineEnding;
          End;
        If MatchCount >= MaxResults Then
          Begin
            ResultText := ResultText + Format('[… capped at %d matches …]', [MaxResults]);
            Capped := True;
            Result := True;
            Exit;
          End;
      End;
    Result := True;
  Finally
    Re.Free;
  End;
End;

Function SearchTextMatches(Const Query, RelativePath, Text: String; FilesOnly: Boolean; MaxResults: Integer;
  Out ResultText, ErrorText: String): Boolean;
Var
  Lines: TStringList;
  MatchCount: Integer;
  Capped: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Trim(Query) = '' Then
    Begin
      ErrorText := 'grep/search_in_project requires pattern or query.';
      Exit;
    End;
  If (MaxResults < 1) Or (MaxResults > 200) Then
    Begin
      ErrorText := 'max_results must be an integer from 1 to 200.';
      Exit;
    End;
  Lines := TStringList.Create;
  Try
    Lines.Text := Text;
    MatchCount := 0;
    Result := MatchSearchLines(Query, RelativePath, Lines, False, FilesOnly, MaxResults, SearchMatchLineChars,
      MatchCount, ResultText, Capped, ErrorText);
  Finally
    Lines.Free;
  End;
End;

End.
