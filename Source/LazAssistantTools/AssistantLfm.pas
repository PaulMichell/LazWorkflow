Unit AssistantLfm;

{ LFM property quoting and component upsert for ensure_form_component (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Function BuildLfmPropertyLines(Const PropsJson: String; Out Lines: String; Out EventMethod: String): Boolean;
Function UpsertLfmComponent(Var LfmBody: String; Const CompName, ClassName, PropLines: String): Boolean;

Implementation

Uses
  fpjson, jsonparser;

Function LooksLikeLfmEnumIdent(Const Val: String): Boolean;
Var
  I, Prefix: Integer;
Begin
  Result := False;
  If (Val = 'True') Or (Val = 'False') Then
    Begin
      Result := True;
      Exit;
    End;
  If Val = '' Then
    Exit;
  I := 1;
  While (I <= Length(Val)) And (Val[I] In ['a'..'z']) Do
    Inc(I);
  Prefix := I - 1;
  If (Prefix < 1) Or (Prefix > 4) Then
    Exit;
  If I > Length(Val) Then
    Exit;
  If Not (Val[I] In ['A'..'Z']) Then
    Exit;
  While I <= Length(Val) Do
    Begin
      If Not (Val[I] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Then
        Exit;
      Inc(I);
    End;
  Result := True;
End;

Function LooksLikeLfmSet(Const Val: String): Boolean;
Begin
  Result := (Length(Val) >= 2) And (Val[1] = '[') And (Val[Length(Val)] = ']');
End;

Function QuoteLfmString(Const Val: String): String;
Begin
  Result := '''' + StringReplace(Val, '''', '''''', [rfReplaceAll]) + '''';
End;

Function BuildLfmPropertyLines(Const PropsJson: String; Out Lines: String; Out EventMethod: String): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  I: Integer;
  Key, Val: String;
  Node: TJSONData;
  IsEvent: Boolean;
Begin
  Result := False;
  Lines := '';
  EventMethod := '';
  If Trim(PropsJson) = '' Then
    Begin
      Result := True;
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(PropsJson);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      For I := 0 To Obj.Count - 1 Do
        Begin
          Key := Obj.Names[I];
          Node := Obj.Items[I];
          If Not Assigned(Node) Then
            Continue;
          If Node.JSONType = jtString Then
            Begin
              Val := Node.AsString;
              IsEvent := (Length(Key) >= 2) And (LowerCase(Copy(Key, 1, 2)) = 'on');
              If IsEvent And (EventMethod = '') Then
                EventMethod := Val;
              If SameText(Val, 'True') Or SameText(Val, 'False') Then
                Lines := Lines + '    ' + Key + ' = ' + BoolToStr(SameText(Val, 'True'), True) + LineEnding
              Else If IsEvent Or LooksLikeLfmSet(Val) Or LooksLikeLfmEnumIdent(Val) Then
                Lines := Lines + '    ' + Key + ' = ' + Val + LineEnding
              Else
                Lines := Lines + '    ' + Key + ' = ' + QuoteLfmString(Val) + LineEnding;
            End
          Else If Node.JSONType = jtBoolean Then
            Lines := Lines + '    ' + Key + ' = ' + BoolToStr(Node.AsBoolean, True) + LineEnding
          Else If Node.JSONType = jtNumber Then
            Lines := Lines + '    ' + Key + ' = ' + Node.AsString + LineEnding
          Else
            Lines := Lines + '    ' + Key + ' = ' + QuoteLfmString(Node.AsString) + LineEnding;
        End;
      Result := True;
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function LineIndent(Const Line: String): Integer;
Var
  I: Integer;
Begin
  I := 1;
  While (I <= Length(Line)) And (Line[I] In [' ', #9]) Do
    Inc(I);
  Result := I - 1;
End;

Function TrimmedLine(Const Line: String): String;
Begin
  Result := Trim(Line);
End;

Function LfmKeyword(Const Line: String): String;
Var
  T: String;
Begin
  Result := '';
  T := TrimmedLine(Line);
  If T = '' Then
    Exit;
  If (LowerCase(Copy(T, 1, 6)) = 'object') And
    ((Length(T) = 6) Or (T[7] In [' ', #9])) Then
    Result := 'object'
  Else If (LowerCase(Copy(T, 1, 9)) = 'inherited') And
    ((Length(T) = 9) Or (T[10] In [' ', #9])) Then
    Result := 'inherited'
  Else If (LowerCase(Copy(T, 1, 3)) = 'end') And
    ((Length(T) = 3) Or (T[4] In [' ', #9, ';'])) Then
    Result := 'end';
End;

Function ParseObjectName(Const Line: String): String;
Var
  T, Rest: String;
  ColonPos: Integer;
Begin
  Result := '';
  T := TrimmedLine(Line);
  If LfmKeyword(Line) = 'object' Then
    Rest := Trim(Copy(T, 7, MaxInt))
  Else If LfmKeyword(Line) = 'inherited' Then
    Rest := Trim(Copy(T, 10, MaxInt))
  Else
    Exit;
  ColonPos := Pos(':', Rest);
  If ColonPos > 0 Then
    Result := Trim(Copy(Rest, 1, ColonPos - 1))
  Else
    Result := Trim(Rest);
End;

Function PropertyKeyOf(Const Line: String): String;
Var
  T: String;
  EqPos: Integer;
Begin
  Result := '';
  If LfmKeyword(Line) <> '' Then
    Exit;
  T := TrimmedLine(Line);
  EqPos := Pos('=', T);
  If EqPos < 2 Then
    Exit;
  Result := LowerCase(Trim(Copy(T, 1, EqPos - 1)));
End;

Procedure SplitLinesKeepEnds(Const Body: String; Lines, Ends: TStringList);
Var
  I, StartPos: Integer;
  Line: String;
Begin
  Lines.Clear;
  Ends.Clear;
  I := 1;
  While I <= Length(Body) Do
    Begin
      StartPos := I;
      While (I <= Length(Body)) And (Not (Body[I] In [#10, #13])) Do
        Inc(I);
      Line := Copy(Body, StartPos, I - StartPos);
      Lines.Add(Line);
      If (I <= Length(Body)) And (Body[I] = #13) Then
        Inc(I);
      If (I <= Length(Body)) And (Body[I] = #10) Then
        Inc(I);
      If I > StartPos + Length(Line) Then
        Ends.Add(Copy(Body, StartPos + Length(Line), I - (StartPos + Length(Line))))
      Else
        Ends.Add('');
    End;
End;

Function JoinLinesKeepEnds(Lines, Ends: TStringList): String;
Var
  I, Total, P, L: Integer;
Begin
  Result := '';
  Total := 0;
  For I := 0 To Lines.Count - 1 Do
    Begin
      Inc(Total, Length(Lines[I]));
      If I < Ends.Count Then
        Inc(Total, Length(Ends[I]));
    End;
  SetLength(Result, Total);
  P := 1;
  For I := 0 To Lines.Count - 1 Do
    Begin
      L := Length(Lines[I]);
      If L > 0 Then
        Move(Lines[I][1], Result[P], L);
      Inc(P, L);
      If I < Ends.Count Then
        Begin
          L := Length(Ends[I]);
          If L > 0 Then
            Move(Ends[I][1], Result[P], L);
          Inc(P, L);
        End;
    End;
End;

Function FindObjectRange(Lines: TStringList; Const CompName: String; Out StartIndex, EndIndex: Integer): Boolean;
Var
  I, Depth: Integer;
  Key: String;
Begin
  Result := False;
  StartIndex := -1;
  EndIndex := -1;
  I := 0;
  While I < Lines.Count Do
    Begin
      Key := LfmKeyword(Lines[I]);
      If ((Key = 'object') Or (Key = 'inherited')) And SameText(ParseObjectName(Lines[I]), CompName) Then
        Begin
          StartIndex := I;
          Depth := 1;
          Inc(I);
          While I < Lines.Count Do
            Begin
              Key := LfmKeyword(Lines[I]);
              If (Key = 'object') Or (Key = 'inherited') Then
                Inc(Depth)
              Else If Key = 'end' Then
                Begin
                  Dec(Depth);
                  If Depth = 0 Then
                    Begin
                      EndIndex := I;
                      Result := True;
                      Exit;
                    End;
                End;
              Inc(I);
            End;
          Exit;
        End;
      Inc(I);
    End;
End;

Function FindRootEndIndex(Lines: TStringList): Integer;
Var
  I: Integer;
Begin
  Result := Lines.Count;
  For I := Lines.Count - 1 DownTo 0 Do
    If (LfmKeyword(Lines[I]) = 'end') And (LineIndent(Lines[I]) = 0) Then
      Begin
        Result := I;
        Exit;
      End;
  For I := Lines.Count - 1 DownTo 0 Do
    If LfmKeyword(Lines[I]) = 'end' Then
      Begin
        Result := I;
        Exit;
      End;
End;

Function PropIndentFor(Const HeaderLine: String): String;
Var
  N, I: Integer;
Begin
  Result := '';
  N := LineIndent(HeaderLine) + 2;
  SetLength(Result, N);
  For I := 1 To N Do
    Result[I] := ' ';
End;

Function HeaderIndentOf(Const HeaderLine: String): String;
Var
  N, I: Integer;
Begin
  Result := '';
  N := LineIndent(HeaderLine);
  SetLength(Result, N);
  For I := 1 To N Do
    Result[I] := ' ';
End;

Procedure CollectNewProperties(Const PropLines: String; Keys, Vals: TStringList);
Var
  SL: TStringList;
  I: Integer;
  Key: String;
Begin
  SL := TStringList.Create;
  Try
    SL.Text := PropLines;
    For I := 0 To SL.Count - 1 Do
      Begin
        Key := PropertyKeyOf(SL[I]);
        If Key = '' Then
          Continue;
        If Keys.IndexOf(Key) >= 0 Then
          Begin
            Vals[Keys.IndexOf(Key)] := Trim(SL[I]);
          End
        Else
          Begin
            Keys.Add(Key);
            Vals.Add(Trim(SL[I]));
          End;
      End;
  Finally
    SL.Free;
  End;
End;

Function RewriteExistingBlock(Lines, Ends: TStringList; StartIndex, EndIndex: Integer; Const PropLines: String): Boolean;
Var
  I, ChildrenStart, KeyIndex: Integer;
  RelDepth: Integer;
  Key: String;
  NewKeys, NewVals: TStringList;
  Used: Array Of Boolean;
  Indent: String;
  HeaderLine: String;
Begin
  Result := False;
  HeaderLine := Lines[StartIndex];
  Indent := PropIndentFor(HeaderLine);
  NewKeys := TStringList.Create;
  NewVals := TStringList.Create;
  Try
    CollectNewProperties(PropLines, NewKeys, NewVals);
    SetLength(Used, 0);
    SetLength(Used, NewKeys.Count);
    For I := 0 To High(Used) Do
      Used[I] := False;
    ChildrenStart := EndIndex;
    RelDepth := 0;
    I := StartIndex + 1;
    While I < EndIndex Do
      Begin
        Key := LfmKeyword(Lines[I]);
        If (Key = 'object') Or (Key = 'inherited') Then
          Begin
            If RelDepth = 0 Then
              Begin
                ChildrenStart := I;
                Break;
              End;
            Inc(RelDepth);
          End
        Else If Key = 'end' Then
          Begin
            If RelDepth > 0 Then
              Dec(RelDepth);
          End
        Else
          Begin
            Key := PropertyKeyOf(Lines[I]);
            If Key <> '' Then
              Begin
                KeyIndex := NewKeys.IndexOf(Key);
                If KeyIndex >= 0 Then
                  Begin
                    Lines[I] := Indent + NewVals[KeyIndex];
                    Used[KeyIndex] := True;
                    Result := True;
                  End;
              End;
          End;
        Inc(I);
      End;
    For I := 0 To NewKeys.Count - 1 Do
      If Not Used[I] Then
        Begin
          Lines.Insert(ChildrenStart, Indent + NewVals[I]);
          Ends.Insert(ChildrenStart, LineEnding);
          Inc(ChildrenStart);
          Inc(EndIndex);
          Result := True;
        End;
  Finally
    NewKeys.Free;
    NewVals.Free;
  End;
End;

Function BuildNewBlock(Const CompName, ClassName, PropLines, ObjectIndent: String): TStringList;
Var
  SL: TStringList;
  I: Integer;
  HasLeft, HasTop: Boolean;
  PropIndent, Line: String;
Begin
  Result := TStringList.Create;
  PropIndent := ObjectIndent + '  ';
  Result.Add(ObjectIndent + 'object ' + CompName + ': ' + ClassName);
  SL := TStringList.Create;
  Try
    SL.Text := PropLines;
    HasLeft := False;
    HasTop := False;
    For I := 0 To SL.Count - 1 Do
      Begin
        Line := Trim(SL[I]);
        If Line = '' Then
          Continue;
        If PropertyKeyOf(Line) = 'left' Then
          HasLeft := True;
        If PropertyKeyOf(Line) = 'top' Then
          HasTop := True;
        Result.Add(PropIndent + Line);
      End;
    If Not HasLeft Then
      Result.Add(PropIndent + 'Left = 40');
    If Not HasTop Then
      Result.Add(PropIndent + 'Top = 40');
  Finally
    SL.Free;
  End;
  Result.Add(ObjectIndent + 'end');
End;

Function UpsertLfmComponent(Var LfmBody: String; Const CompName, ClassName, PropLines: String): Boolean;
Var
  Lines, Ends: TStringList;
  StartIndex, EndIndex, InsertAt, I: Integer;
  Original, ObjectIndent: String;
  NewBlock: TStringList;
Begin
  Result := False;
  If (Trim(CompName) = '') Or (Trim(ClassName) = '') Then
    Exit;
  Original := LfmBody;
  Lines := TStringList.Create;
  Ends := TStringList.Create;
  Try
    SplitLinesKeepEnds(LfmBody, Lines, Ends);
    If FindObjectRange(Lines, CompName, StartIndex, EndIndex) Then
      RewriteExistingBlock(Lines, Ends, StartIndex, EndIndex, PropLines)
    Else
      Begin
        InsertAt := FindRootEndIndex(Lines);
        If InsertAt < Lines.Count Then
          ObjectIndent := HeaderIndentOf(Lines[InsertAt]) + '  '
        Else
          ObjectIndent := '  ';
        NewBlock := BuildNewBlock(CompName, ClassName, PropLines, ObjectIndent);
        Try
          For I := 0 To NewBlock.Count - 1 Do
            Begin
              Lines.Insert(InsertAt + I, NewBlock[I]);
              Ends.Insert(InsertAt + I, LineEnding);
            End;
        Finally
          NewBlock.Free;
        End;
      End;
    LfmBody := JoinLinesKeepEnds(Lines, Ends);
    Result := LfmBody <> Original;
  Finally
    Lines.Free;
    Ends.Free;
  End;
End;

End.
