Unit AssistantRenamePreview;
{ Pure change preparation from CodeTools locations. Caller owns the shared
  CodeTools guard and has synchronized the IDE cache. Never changes source text. }
{$mode objfpc}{$H+}
Interface
Uses CodeCache, fpjson;
Function IsVariableDeclaration(Code: TCodeBuffer; Var X, Y: Integer): Boolean;
Function PrepareLocalRename(Code, Declaration: TCodeBuffer; X, Y: Integer;
  Const NewName: String; Out Preview: TJSONObject; Out ErrorText: String): Boolean;
Implementation
Uses Classes, SysUtils, CodeToolManager, CodeTree, CTUnitGraph, KeywordFuncLists;
Function IsVariableDeclaration(Code: TCodeBuffer; Var X, Y: Integer): Boolean;
Var Node: TCodeTreeNode; Name: String; Tool: TCodeTool;
  Position: TCodePosition; CleanPos: Integer;
Begin
  Result := False;
  If Not CodeToolBoss.GetIdentifierAt(Code, X, Y, Name, Node) Then Exit;
  If Assigned(Node) And (Node.Desc = ctnIdentifier) Then Node := Node.Parent;
  If Not Assigned(Node) Or (Node.Desc <> ctnVarDefinition) Then Exit;
  Tool := CodeToolBoss.FindCodeToolForSource(Code);
  If Not Assigned(Tool) Then Exit;
  Position.Code := Code; Code.LineColToPosition(Y, X, Position.P);
  Result := (Tool.CodePosToCleanPos(Position, CleanPos) = 0) And (Node.StartPos = CleanPos);
End;
Function IdentChar(C: Char): Boolean;
Begin Result := C In ['a'..'z', 'A'..'Z', '0'..'9', '_', #128..#255]; End;
Function PlainIdentifier(Const S: String): Boolean;
Var I: Integer;
Begin
  Result := False;
  If (Length(S) < 1) Or (Length(S) > 127) Then Exit;
  If Not (S[1] In ['a'..'z', 'A'..'Z', '_']) Then Exit;
  For I := 2 To Length(S) Do If Not (S[I] In ['a'..'z', 'A'..'Z', '0'..'9', '_']) Then Exit;
  Result := Not WordIsKeyWord.DoItCaseInsensitive(PChar(S)) And
    Not SameText(S, 'Self') And Not SameText(S, 'Result');
End;
Function HasWord(Const Text, Word: String): Boolean;
Var I, Start: Integer;
Begin
  Result := False; I := 1;
  While I <= Length(Text) Do
    If IdentChar(Text[I]) Then
      Begin
        Start := I;
        Repeat Inc(I); Until (I > Length(Text)) Or Not IdentChar(Text[I]);
        If SameText(Copy(Text, Start, I - Start), Word) Then Exit(True);
      End
    Else Inc(I);
End;
Function SupportedDirectives(Const Text: String): Boolean;
Var I, Start: Integer; Directive, Closing: String;
Begin
  { Deliberately conservative even for directive-looking comment/string text.
    Only declarations unaffected by conditional/macro/include expansion qualify. }
  Result := False; I := 1;
  While I <= Length(Text) Do
    Begin
      Start := 0;
      If Copy(Text, I, 2) = '{$' Then Begin Start := I + 2; Closing := '}'; End
      Else If Copy(Text, I, 3) = '(*$' Then Begin Start := I + 3; Closing := '*)'; End;
      If Start > 0 Then
        Begin
          I := Start;
          While (I <= Length(Text)) And (Copy(Text, I, Length(Closing)) <> Closing) Do Inc(I);
          Directive := UpperCase(Trim(Copy(Text, Start, I - Start)));
          If Not ((Pos('MODE ', Directive) = 1) Or (Directive = 'H+') Or (Directive = 'H-') Or
            (Directive = 'R+') Or (Directive = 'R-') Or (Pos('R ', Directive) = 1) Or
            (Pos('CODEPAGE ', Directive) = 1)) Then Exit;
        End;
      Inc(I);
    End;
  Result := True;
End;
Function PrepareLocalRename(Code, Declaration: TCodeBuffer; X, Y: Integer;
  Const NewName: String; Out Preview: TJSONObject; Out ErrorText: String): Boolean;
Var Node: TCodeTreeNode; OldName, NewText, Key: String; Tool: TCodeTool;
  Refs: TFPList; Cache: TFindIdentifierReferenceCache; Positions: TStringList;
  Ref: PCodeXYPosition; I, J, Offset, Swap, DeclOffset: Integer;
  Offsets: Array Of Integer; Changes: TJSONArray; Entry: TJSONObject;
  Function AddPosition(Buffer: TCodeBuffer; Col, Row: Integer): Boolean;
  Begin
    Result := False;
    If Buffer <> Code Then Begin ErrorText := 'Rename crosses a source/include boundary; this preview supports one editor only.'; Exit; End;
    Buffer.LineColToPosition(Row, Col, Offset);
    If (Offset < 1) Or (Offset + Length(OldName) - 1 > Length(Code.Source)) Or
      Not SameText(Copy(Code.Source, Offset, Length(OldName)), OldName) Then
      Begin ErrorText := 'CodeTools returned a rename location that does not match the source.'; Exit; End;
    If ((Offset > 1) And (IdentChar(Code.Source[Offset - 1]) Or (Code.Source[Offset - 1] = '&'))) Or
      ((Offset + Length(OldName) <= Length(Code.Source)) And IdentChar(Code.Source[Offset + Length(OldName)])) Then
      Begin ErrorText := 'Escaped or overlapping identifier locations are unsupported.'; Exit; End;
    Key := IntToStr(Offset);
    If Positions.IndexOf(Key) < 0 Then
      Begin
        If Positions.Count >= 200 Then Begin ErrorText := 'Rename exceeds 200 occurrences; no partial preview is produced.'; Exit; End;
        Positions.Add(Key); SetLength(Offsets, Length(Offsets) + 1); Offsets[High(Offsets)] := Offset;
      End;
    Result := True;
  End;
Begin
  Result := False; Preview := Nil; ErrorText := ''; Refs := Nil; Cache := Nil; Positions := Nil;
  If (Code <> Declaration) Or SameText(ExtractFileExt(Code.Filename), '.inc') Then
    Begin ErrorText := 'Local rename requires a standalone Pascal source editor containing the declaration.'; Exit; End;
  If Not PlainIdentifier(NewName) Then Begin ErrorText := 'Use a non-keyword ASCII Pascal identifier of 1-127 characters.'; Exit; End;
  If Not SupportedDirectives(Code.Source) Or HasWord(Code.Source, 'asm') Then
    Begin ErrorText := 'Local rename does not yet support conditional/include/macro directives or assembly in the source.'; Exit; End;
  If Not CodeToolBoss.GetIdentifierAt(Declaration, X, Y, OldName, Node) Then
    Begin ErrorText := 'Cannot inspect the declaration identifier.'; Exit; End;
  Tool := CodeToolBoss.FindCodeToolForSource(Code);
  If Not Assigned(Tool) Or (Tool.Scanner.MainCode <> Code) Then
    Begin ErrorText := 'Included sources are unsupported by local rename.'; Exit; End;
  If Assigned(Node) And (Node.Desc = ctnIdentifier) Then Node := Node.Parent;
  If Not Assigned(Node) Or (Node.Desc <> ctnVarDefinition) Or Not Assigned(Node.Parent) Or
    (Node.Parent.Desc <> ctnVarSection) Or Not Assigned(Node.Parent.Parent) Or
    (Node.Parent.Parent.Desc <> ctnProcedure) Then
    Begin ErrorText := 'This preview supports routine-local var declarations only; parameters, fields and global symbols are unsupported.'; Exit; End;
  If Not PlainIdentifier(OldName) Or SameText(OldName, NewName) Then
    Begin ErrorText := 'Use a different identifier; escaped identifiers and case-only renames are unsupported.'; Exit; End;
  If HasWord(Code.Source, NewName) Then
    Begin ErrorText := 'The new name already occurs in this source; choose an unused name to avoid capture or collisions.'; Exit; End;
  Try
    Positions := TStringList.Create;
    If Not AddPosition(Declaration, X, Y) Then Exit;
    DeclOffset := Offset;
    If Not CodeToolBoss.FindReferences(Declaration, X, Y, Code, True, Refs, Cache, []) Or
      (CodeToolBoss.ErrorMessage <> '') Then
      Begin ErrorText := 'CodeTools could not complete the local reference search: ' + CodeToolBoss.ErrorMessage; Exit; End;
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
          Begin Swap := Offsets[J - 1]; Offsets[J - 1] := Offsets[J]; Offsets[J] := Swap; Dec(J); End;
      End;
    NewText := Code.Source;
    For I := High(Offsets) Downto 0 Do
      Begin Delete(NewText, Offsets[I], Length(OldName)); Insert(NewName, NewText, Offsets[I]); End;
    If Length(NewText) > 1048576 Then Begin ErrorText := 'Renamed source exceeds the 1 MiB limit.'; Exit; End;
    Preview := TJSONObject.Create;
    Preview.Add('oldName', OldName); Preview.Add('newName', NewName);
    Preview.Add('scope', 'one routine-local variable in one editor; no save');
    Preview.Add('text', NewText);
    Changes := TJSONArray.Create; Preview.Add('changes', Changes);
    For I := 0 To High(Offsets) Do
      Begin
        Code.AbsoluteToLineCol(Offsets[I], Y, X);
        Entry := TJSONObject.Create; Entry.Add('line', Y); Entry.Add('column', X);
        Entry.Add('oldText', Copy(Code.Source, Offsets[I], Length(OldName))); Entry.Add('newText', NewName);
        Entry.Add('declaration', Offsets[I] = DeclOffset); Changes.Add(Entry);
      End;
    Result := True;
  Finally Positions.Free; CodeToolBoss.FreeListOfPCodeXYPosition(Refs); Cache.Free; End;
End;
End.
