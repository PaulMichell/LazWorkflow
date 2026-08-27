Unit AssistantSearchUtil;

{ Grep glob / regex detection and read_file line-range helpers (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

{ True when the pattern is almost certainly a regex (unescaped | is the usual case). }
Function PatternLooksLikeRegex(Const Pattern: String): Boolean;
{ Empty glob matches every name. Supports .pas, pas, *.pas, and brace lists. }
Function FileMatchesSearchGlob(Const FileName, Glob: String): Boolean;
{ start_line is 1-based. limit is a line count. If limit is 0 and end_line < start_line,
  end_line is treated as a line count (Grok Build habit). }
Procedure ResolveReadLineRange(Var StartLine, EndLine: Integer; Limit: Integer);

Implementation

Uses
  SysUtils;

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

End.
