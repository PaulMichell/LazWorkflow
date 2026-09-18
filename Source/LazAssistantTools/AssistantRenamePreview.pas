Unit AssistantRenamePreview;

{ Pure change preparation from CodeTools locations. Caller owns the shared
  CodeTools guard and has synchronized the IDE cache. Never changes source text. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  CodeCache, fpjson;
Function IsLocalRenameDeclaration(Code: TCodeBuffer; Var X, Y: Integer): Boolean;
Function PrepareLocalRename(Code, Declaration: TCodeBuffer; X, Y: Integer;
    Const NewName: String; Out Preview: TJSONObject; Out ErrorText: String): Boolean;

Implementation

Uses
  Classes, SysUtils, CodeToolManager, CodeTree, CTUnitGraph, KeywordFuncLists, BasicCodeTools;

Function IsLocalRenameDeclaration(Code: TCodeBuffer; Var X, Y: Integer): Boolean;
Var
  Node: TCodeTreeNode;
  Name: String;
  Tool: TCodeTool;
  Position: TCodePosition;
  CleanPos: Integer;
Begin
  Result := False;
  If Not CodeToolBoss.GetIdentifierAt(Code, X, Y, Name, Node) Then Exit;
  If Assigned(Node) And (Node.Desc = ctnIdentifier) Then Node := Node.Parent;
  If Not Assigned(Node) Or Not (Node.Desc In [ctnVarDefinition, ctnConstDefinition]) Then Exit;
  Tool := CodeToolBoss.FindCodeToolForSource(Code);
  If Not Assigned(Tool) Then Exit;
  Position.Code := Code;
  Code.LineColToPosition(Y, X, Position.P);
  Result := (Tool.CodePosToCleanPos(Position, CleanPos) = 0) And (Node.StartPos = CleanPos);
End;

Function IdentChar(C: Char): Boolean;
Begin
  Result := C In ['a'..'z', 'A'..'Z', '0'..'9', '_', #128..#255];
End;

Function PlainIdentifier(Const S: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If (Length(S) < 1) Or (Length(S) > 127) Then Exit;
  If Not (S[1] In ['a'..'z', 'A'..'Z', '_']) Then Exit;
  For I := 2 To Length(S) Do If Not (S[I] In ['a'..'z', 'A'..'Z', '0'..'9', '_']) Then Exit;
  Result := Not WordIsKeyWord.DoItCaseInsensitive(PChar(S)) And
    Not SameText(S, 'Self') And Not SameText(S, 'Result');
End;

Function CheckRenameContext(Code: TCodeBuffer; Tool: TCodeTool;
    Routine: TCodeTreeNode; Const NewName: String; Out ErrorText: String): Boolean;
Var
  First, Last: TCodePosition;
  P, Start, Prev, N, Depth: Integer;
  Token, Name, Value: String;
  Conditional: Boolean;
Begin
  Result := False;
  If (Routine.EndPos <= Routine.StartPos) Or
    Not Tool.CleanPosToCodePos(Routine.StartPos, First) Or
    Not Tool.CleanPosToCodePos(Routine.EndPos - 1, Last) Or
    (First.Code <> Code) Or (Last.Code <> Code) Then
      Begin
        ErrorText := 'Cannot establish the complete routine source boundary.';
        Exit;
      End;
  { CodeTools tokenization distinguishes directives from quoted text and real
    comments. Inspect raw source too: inactive directives inside the routine
    must not disappear merely because this configuration skips them. }
  P := 1;
  Depth := 0;
  While P <= Length(Code.Source) Do
    Begin
      Prev := P;
      Token := ReadNextPascalAtom(Code.Source, P, Start, Tool.Scanner.NestedComments, False);
      If P <= Prev Then
        Begin
          ErrorText := 'Cannot scan source directives completely.';
          Exit;
        End;
      If Copy(Token, 1, 2) = '{$' Then Token := Copy(Token, 3, Length(Token) - 3)
      Else If Copy(Token, 1, 3) = '(*$' Then Token := Copy(Token, 4, Length(Token) - 5)
      Else Continue;
      Token := Trim(Token);
      N := 1;
      While (N <= Length(Token)) And (Token[N] In ['A'..'Z', 'a'..'z', '_']) Do Inc(N);
      Name := UpperCase(Copy(Token, 1, N - 1));
      Value := UpperCase(Trim(Copy(Token, N, MaxInt)));
      Conditional := (Name = 'IF') Or (Name = 'IFDEF') Or (Name = 'IFNDEF') Or
        (Name = 'IFOPT') Or (Name = 'ELSE') Or (Name = 'ELSEIF') Or (Name = 'ENDIF') Or (Name = 'IFEND');
      If Conditional Then
        Begin
          If (Start >= First.P) And (Start <= Last.P) Then
            Begin
              ErrorText := 'Conditional directives inside the selected routine are unsupported; no partial rename is produced.';
              Exit;
            End;
          If (Name = 'IF') Or (Name = 'IFDEF') Or (Name = 'IFNDEF') Or (Name = 'IFOPT') Then Inc(Depth)
          Else
            Begin
              If Depth = 0 Then
                Begin
                  ErrorText := 'Unbalanced conditional directives in source.';
                  Exit;
                End;
              If (Name = 'ENDIF') Or (Name = 'IFEND') Then Dec(Depth);
            End;
          Continue;
        End;
      If ((Name = 'MODE') Or (Name = 'CODEPAGE')) And (Value <> '') Then Continue;
      If (Name = 'R') And (Value <> '') And Not (Value[1] In ['+', '-']) Then Continue;
      If ((Name = 'H') Or (Name = 'R') Or (Name = 'Q') Or (Name = 'B')) And
        ((Value = '+') Or (Value = '-')) Then Continue;
      If ((Name = 'RANGECHECKS') Or (Name = 'OVERFLOWCHECKS') Or (Name = 'BOOLEVAL') Or
        (Name = 'LONGSTRINGS') Or (Name = 'WARNINGS') Or (Name = 'HINTS') Or (Name = 'NOTES')) And
        ((Value = 'ON') Or (Value = 'OFF')) Then Continue;
      ErrorText := 'Unsupported rename directive: $' + Name + '. Includes, defines and macros still require wider dependency handling.';
      Exit;
    End;
  If Depth <> 0 Then
    Begin
      ErrorText := 'Cannot account for all conditional directives in source.';
      Exit;
    End;
  { Scan actual, configured Pascal tokens for collisions. Comments, strings and
    inactive branches do not introduce bindings. Keep code-wide checks until
    narrower name-resolution/capture analysis is qualified. }
  Tool.MoveCursorToCleanPos(1);
  Repeat
    Tool.ReadNextAtom;
    Token := Tool.GetAtom;
    If Token = '' Then Break;
    If SameText(Token, 'asm') Then
      Begin
        ErrorText := 'Assembly in active source is unsupported by local rename.';
        Exit;
      End;
    If (Token[1] = '&') Then Delete(Token, 1, 1);
    If SameText(Token, NewName) Then
      Begin
        ErrorText := 'The new name occurs in active Pascal code; choose another name to avoid capture or collisions.';
        Exit;
      End;
  Until Tool.CurPos.EndPos > Tool.SrcLen;
  Result := True;
End;

Function PrepareLocalRename(Code, Declaration: TCodeBuffer; X, Y: Integer;
    Const NewName: String; Out Preview: TJSONObject; Out ErrorText: String): Boolean;
Var
  Node: TCodeTreeNode;
  OldName, NewText, Key, SymbolKind: String;
  Tool: TCodeTool;
  Refs: TFPList;
  Cache: TFindIdentifierReferenceCache;
  Positions: TStringList;
  Ref: PCodeXYPosition;
  I, J, Offset, Swap, DeclOffset: Integer;
  Offsets: Array Of Integer;
  Changes: TJSONArray;
  Entry: TJSONObject;
  Function AddPosition(Buffer: TCodeBuffer; Col, Row: Integer): Boolean;
  Begin
    Result := False;
    If Buffer <> Code Then
      Begin
        ErrorText := 'Rename crosses a source/include boundary; this preview supports one editor only.';
        Exit;
      End;
    Buffer.LineColToPosition(Row, Col, Offset);
    If (Offset < 1) Or (Offset + Length(OldName) - 1 > Length(Code.Source)) Or
      Not SameText(Copy(Code.Source, Offset, Length(OldName)), OldName) Then
        Begin
          ErrorText := 'CodeTools returned a rename location that does not match the source.';
          Exit;
        End;
    If ((Offset > 1) And (IdentChar(Code.Source[Offset - 1]) Or (Code.Source[Offset - 1] = '&'))) Or
      ((Offset + Length(OldName) <= Length(Code.Source)) And IdentChar(Code.Source[Offset + Length(OldName)])) Then
        Begin
          ErrorText := 'Escaped or overlapping identifier locations are unsupported.';
          Exit;
        End;
    Key := IntToStr(Offset);
    If Positions.IndexOf(Key) < 0 Then
      Begin
        If Positions.Count >= 200 Then
          Begin
            ErrorText := 'Rename exceeds 200 occurrences; no partial preview is produced.';
            Exit;
          End;
        Positions.Add(Key);
        SetLength(Offsets, Length(Offsets) + 1);
        Offsets[High(Offsets)] := Offset;
      End;
    Result := True;
  End;
Begin
  Result := False;
  Preview := Nil;
  ErrorText := '';
  Refs := Nil;
  Cache := Nil;
  Positions := Nil;
  If (Code <> Declaration) Or SameText(ExtractFileExt(Code.Filename), '.inc') Then
    Begin
      ErrorText := 'Local rename requires a standalone Pascal source editor containing the declaration.';
      Exit;
    End;
  If Not PlainIdentifier(NewName) Then
    Begin
      ErrorText := 'Use a non-keyword ASCII Pascal identifier of 1-127 characters.';
      Exit;
    End;
  If Not CodeToolBoss.GetIdentifierAt(Declaration, X, Y, OldName, Node) Then
    Begin
      ErrorText := 'Cannot inspect the declaration identifier.';
      Exit;
    End;
  Tool := CodeToolBoss.FindCodeToolForSource(Code);
  If Not Assigned(Tool) Or (Tool.Scanner.MainCode <> Code) Then
    Begin
      ErrorText := 'Included sources are unsupported by local rename.';
      Exit;
    End;
  If Assigned(Node) And (Node.Desc = ctnIdentifier) Then Node := Node.Parent;
  If Not Assigned(Node) Or Not (Node.Desc In [ctnVarDefinition, ctnConstDefinition]) Or Not Assigned(Node.Parent) Or
    Not (((Node.Desc = ctnVarDefinition) And (Node.Parent.Desc = ctnVarSection)) Or
    ((Node.Desc = ctnConstDefinition) And (Node.Parent.Desc = ctnConstSection))) Or Not Assigned(Node.Parent.Parent) Or
    (Node.Parent.Parent.Desc <> ctnProcedure) Then
      Begin
        ErrorText := 'This preview supports routine-local var/const declarations only; parameters, fields and global symbols are unsupported.';
        Exit;
      End;
  If Not PlainIdentifier(OldName) Or SameText(OldName, NewName) Then
    Begin
      ErrorText := 'Use a different identifier; escaped identifiers and case-only renames are unsupported.';
      Exit;
    End;
  If Node.Desc = ctnConstDefinition Then SymbolKind := 'constant'
  Else SymbolKind := 'variable';
  If Not CheckRenameContext(Code, Tool, Node.Parent.Parent, NewName, ErrorText) Then Exit;
  Try
    Positions := TStringList.Create;
    If Not AddPosition(Declaration, X, Y) Then Exit;
    DeclOffset := Offset;
    If Not CodeToolBoss.FindReferences(Declaration, X, Y, Code, True, Refs, Cache, []) Or
      (CodeToolBoss.ErrorMessage <> '') Then
        Begin
          ErrorText := 'CodeTools could not complete the local reference search: ' + CodeToolBoss.ErrorMessage;
          Exit;
        End;
    If Assigned(Refs) Then For I := 0 To Refs.Count - 1 Do
      Begin
        Ref := PCodeXYPosition(Refs[I]);
        If Not AddPosition(Ref^.Code, Ref^.X, Ref^.Y) Then Exit;
      End;
    { Sort byte offsets, then substitute from the end without moving locations. }
    For I := 1 To High(Offsets) Do
      Begin
        J := I;
        While (J > 0) And (Offsets[J - 1] > Offsets[J]) Do
          Begin
            Swap := Offsets[J - 1];
            Offsets[J - 1] := Offsets[J];
            Offsets[J] := Swap;
            Dec(J);
          End;
      End;
    NewText := Code.Source;
    For I := High(Offsets) DownTo 0 Do
      Begin
        Delete(NewText, Offsets[I], Length(OldName));
        Insert(NewName, NewText, Offsets[I]);
      End;
    If Length(NewText) > 1048576 Then
      Begin
        ErrorText := 'Renamed source exceeds the 1 MiB limit.';
        Exit;
      End;
    Preview := TJSONObject.Create;
    Preview.Add('oldName', OldName);
    Preview.Add('newName', NewName);
    Preview.Add('symbolKind', SymbolKind);
    Preview.Add('scope', 'one routine-local variable or constant under current IDE defines; other conditional routines unchanged; no save');
    Preview.Add('text', NewText);
    Changes := TJSONArray.Create;
    Preview.Add('changes', Changes);
    For I := 0 To High(Offsets) Do
      Begin
        Code.AbsoluteToLineCol(Offsets[I], Y, X);
        Entry := TJSONObject.Create;
        Entry.Add('line', Y);
        Entry.Add('column', X);
        Entry.Add('oldText', Copy(Code.Source, Offsets[I], Length(OldName)));
        Entry.Add('newText', NewName);
        Entry.Add('declaration', Offsets[I] = DeclOffset);
        Changes.Add(Entry);
      End;
    Result := True;
  Finally
    Positions.Free;
    CodeToolBoss.FreeListOfPCodeXYPosition(Refs);
    Cache.Free;
  End;
End;
End.
