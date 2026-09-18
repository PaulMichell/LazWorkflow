Unit PascalStyleFormat;

{ Michell Computing Pascal source formatter (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The tokenizer lives in
  PascalStyleTokens; this unit is the remaining header rewrite, packed-statement
  splitter and indent engine, which form one formatter with no useful split.
  Reviewed 2026-09: no hidden sibling material identified. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, PascalStyleTokens;

Function FormatPascalSource(Const Source: String): String;
Procedure CollectTokenFingerprint(Const Source: String; Names: TStrings);
Function TokenFingerprintsEqual(Const Left, Right: String): Boolean;

Implementation

Uses
  SysUtils, StrUtils, Types;

Type
  TRawLine = Record
    BlankBefore: Boolean;
    Tokens: TStyleTokenArray;
  End;
  TRawLineArray = Array Of TRawLine;

  TBlockFrame = Record
    Kind: String;
    Indent: Integer;
  End;
  TBlockArray = Array Of TBlockFrame;

Function CopyTokens(Const Tokens: TStyleTokenArray; StartIndex, Count: Integer): TStyleTokenArray;
Var
  Index: Integer;
Begin
  Result := Nil;
  SetLength(Result, Count);
  For Index := 0 To Count - 1 Do
    Result[Index] := Tokens[StartIndex + Index];
End;

Function FirstIdent(Const Tokens: TStyleTokenArray): String;
Var
  Index: Integer;
Begin
  Result := '';
  For Index := 0 To High(Tokens) Do
    Begin
      If Tokens[Index].Kind = tkIdent Then
        Begin
          Result := LowerCase(Tokens[Index].Value);
          Exit;
        End;
      If Not (Tokens[Index].Kind In [tkComment, tkDirective]) Then
        Exit;
    End;
End;

Function LastIdent(Const Tokens: TStyleTokenArray): String;
Var
  Index: Integer;
Begin
  Result := '';
  For Index := High(Tokens) DownTo 0 Do
    Begin
      If Tokens[Index].Kind = tkIdent Then
        Begin
          Result := LowerCase(Tokens[Index].Value);
          Exit;
        End;
      If Not (Tokens[Index].Kind In [tkComment, tkDirective]) Then
        Exit;
    End;
End;

Function LineHasIdent(Const Tokens: TStyleTokenArray; Const Name: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 0 To High(Tokens) Do
    If IsIdentNamed(Tokens[Index], Name) Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function CodeTokensOf(Const Tokens: TStyleTokenArray): TStyleTokenArray;
Var
  Index, Count: Integer;
Begin
  Result := Nil;
  SetLength(Result, Length(Tokens));
  Count := 0;
  For Index := 0 To High(Tokens) Do
    If Not (Tokens[Index].Kind In [tkComment, tkDirective]) Then
      Begin
        Result[Count] := Tokens[Index];
        Inc(Count);
      End;
  SetLength(Result, Count);
End;

Function LastNonBlank(Lines: TStrings): String;
Var
  Index: Integer;
Begin
  Result := '';
  For Index := Lines.Count - 1 DownTo 0 Do
    If Trim(Lines[Index]) <> '' Then
      Begin
        Result := Lines[Index];
        Exit;
      End;
End;

Procedure PushBlock(Var Stack: TBlockArray; Const Kind: String; Indent: Integer);
Var
  Count: Integer;
Begin
  Count := Length(Stack);
  SetLength(Stack, Count + 1);
  Stack[Count].Kind := Kind;
  Stack[Count].Indent := Indent;
End;

Procedure PushInt(Var Values: TIntegerDynArray; Var Count: Integer; Value: Integer);
Begin
  If Count >= Length(Values) Then
    Begin
      If Length(Values) = 0 Then
        SetLength(Values, 16)
      Else
        SetLength(Values, Length(Values) * 2);
    End;
  Values[Count] := Value;
  Inc(Count);
End;

Function InsertPackedBreaks(Const Tokens: TStyleTokenArray): TStyleTokenArray;
Var
  OutTokens: TStyleTokenArray;
  OutCount, Index, NextIndex, PrevIndex, Paren, Bracket: Integer;
  InHeader: Boolean;
  Token, Prev, NextToken: TStyleToken;
  LowName: String;

  Procedure Put(Const Item: TStyleToken);
  Begin
    AppendTokenCount(OutTokens, OutCount, Item);
  End;

  Procedure PutNL(Line, Column: Integer);
  Begin
    If (OutCount > 0) And (OutTokens[OutCount - 1].Kind = tkNewline) Then
      Exit;
    Put(MakeToken(tkNewline, #10, Line, Column));
  End;

Begin
  SetLength(OutTokens, 0);
  OutCount := 0;
  Paren := 0;
  Bracket := 0;
  InHeader := False;
  Index := 0;
  While Index <= High(Tokens) Do
    Begin
      Token := Tokens[Index];
      If Token.Kind = tkNewline Then
        Begin
          Put(Token);
          Inc(Index);
          Continue;
        End;
      LowName := TokenLower(Token);

      If IsIdentOneOf(Token, ['function', 'procedure', 'constructor', 'destructor', 'operator']) And (Paren = 0) Then
        Begin
          InHeader := True;
          Put(Token);
          Inc(Index);
          Continue;
        End;

      If IsIdentOneOf(Token, ['begin', 'try', 'repeat']) And (Paren = 0) Then
        Begin
          InHeader := False;
          PrevIndex := LastCodeIn(OutTokens, OutCount);
          If PrevIndex >= 0 Then
            Begin
              Prev := OutTokens[PrevIndex];
              If Prev.Line = Token.Line Then
                PutNL(Token.Line, Token.Column);
            End;
          Put(Token);
          NextIndex := NextCodeIndex(Tokens, Index + 1);
          If NextIndex >= 0 Then
            Begin
              NextToken := Tokens[NextIndex];
              If (NextToken.Line = Token.Line) And (Not IsIdentNamed(NextToken, 'End')) Then
                PutNL(Token.Line, Token.Column);
            End;
          Inc(Index);
          Continue;
        End;

      If IsIdentOneOf(Token, ['end', 'until', 'except', 'finally', 'else']) And (Paren = 0) Then
        Begin
          PrevIndex := LastCodeIn(OutTokens, OutCount);
          If PrevIndex >= 0 Then
            Begin
              Prev := OutTokens[PrevIndex];
              If Prev.Line = Token.Line Then
                PutNL(Token.Line, Token.Column);
            End;
          Put(Token);
          If IsIdentOneOf(Token, ['except', 'finally']) Then
            Begin
              NextIndex := NextCodeIndex(Tokens, Index + 1);
              If NextIndex >= 0 Then
                Begin
                  NextToken := Tokens[NextIndex];
                  If (NextToken.Line = Token.Line) And (Not IsIdentOneOf(NextToken, ['end', 'on'])) Then
                    PutNL(Token.Line, Token.Column);
                End;
            End;
          Inc(Index);
          Continue;
        End;

      If IsVisibilityName(LowName) Or IsIdentNamed(Token, 'strict') Then
        Begin
          PrevIndex := LastCodeIn(OutTokens, OutCount);
          If PrevIndex >= 0 Then
            Begin
              Prev := OutTokens[PrevIndex];
              If Prev.Line = Token.Line Then
                PutNL(Token.Line, Token.Column);
            End;
          Put(Token);
          NextIndex := NextCodeIndex(Tokens, Index + 1);
          If NextIndex >= 0 Then
            Begin
              NextToken := Tokens[NextIndex];
              If (NextToken.Line = Token.Line) And (Not IsIdentOneOf(NextToken, ['private', 'public', 'protected', 'published'])) Then
                PutNL(Token.Line, Token.Column);
            End;
          Inc(Index);
          Continue;
        End;

      If IsIdentOneOf(Token, ['type', 'const', 'uses', 'var', 'label', 'resourcestring', 'threadvar'])
        And (Paren = 0) And (Not InHeader) Then
        Begin
          PrevIndex := LastCodeIn(OutTokens, OutCount);
          If PrevIndex >= 0 Then
            Begin
              Prev := OutTokens[PrevIndex];
              If Prev.Line = Token.Line Then
                PutNL(Token.Line, Token.Column);
            End;
          Put(Token);
          NextIndex := NextCodeIndex(Tokens, Index + 1);
          If (NextIndex >= 0) And (Tokens[NextIndex].Line = Token.Line)
            And (Not ((Tokens[NextIndex].Kind = tkOp) And (Tokens[NextIndex].Value = ';'))) Then
            PutNL(Token.Line, Token.Column);
          Inc(Index);
          Continue;
        End;

      If IsIdentNamed(Token, 'class') And (Paren = 0) Then
        Begin
          Put(Token);
          NextIndex := NextCodeIndex(Tokens, Index + 1);
          If NextIndex >= 0 Then
            Begin
              NextToken := Tokens[NextIndex];
              If IsIdentOneOf(NextToken, ['of', 'helper', 'procedure', 'function', 'var', 'property',
                'operator', 'sealed', 'abstract']) Then
                Begin
                  Inc(Index);
                  Continue;
                End;
              If (NextToken.Kind = tkOp) And ((NextToken.Value = ';') Or (NextToken.Value = '(')) Then
                Begin
                  Inc(Index);
                  Continue;
                End;
              If NextToken.Line = Token.Line Then
                PutNL(Token.Line, Token.Column);
            End;
          Inc(Index);
          Continue;
        End;

      If IsIdentNamed(Token, 'record') And (Paren = 0) Then
        Begin
          Put(Token);
          NextIndex := NextCodeIndex(Tokens, Index + 1);
          If NextIndex >= 0 Then
            Begin
              NextToken := Tokens[NextIndex];
              If (Not ((NextToken.Kind = tkOp) And (NextToken.Value = ';'))) And (NextToken.Line = Token.Line) Then
                PutNL(Token.Line, Token.Column);
            End;
          Inc(Index);
          Continue;
        End;

      If Token.Kind = tkOp Then
        Begin
          If Token.Value = '(' Then
            Inc(Paren)
          Else If Token.Value = ')' Then
            Begin
              If Paren > 0 Then
                Dec(Paren);
            End
          Else If Token.Value = '[' Then
            Inc(Bracket)
          Else If Token.Value = ']' Then
            Begin
              If Bracket > 0 Then
                Dec(Bracket);
            End
          Else If Token.Value = ';' Then
            Begin
              Put(Token);
              NextIndex := NextCodeIndex(Tokens, Index + 1);
              If InHeader And (Paren = 0) Then
                Begin
                  If NextIndex >= 0 Then
                    Begin
                      NextToken := Tokens[NextIndex];
                      If ((NextToken.Kind = tkIdent) And IsMethodDirectiveName(NextToken.Value))
                        Or ((NextToken.Kind = tkOp) And (NextToken.Value = '[')) Then
                        Begin
                          Inc(Index);
                          Continue;
                        End;
                    End;
                  InHeader := False;
                End;
              If (Paren = 0) And (Bracket = 0) And (NextIndex >= 0) Then
                Begin
                  NextToken := Tokens[NextIndex];
                  If (NextToken.Kind = tkIdent) And (IsMethodDirectiveName(NextToken.Value)
                    Or IsPropertyDirectiveName(NextToken.Value)) Then
                    Begin
                      Inc(Index);
                      Continue;
                    End;
                  If (NextToken.Line = Token.Line) And (Not IsIdentOneOf(NextToken,
                    ['end', 'else', 'until', 'finally', 'except'])) Then
                    PutNL(Token.Line, Token.Column);
                End;
              Inc(Index);
              Continue;
            End;
          Put(Token);
          Inc(Index);
          Continue;
        End;

      Put(Token);
      Inc(Index);
    End;
  SetLength(OutTokens, OutCount);
  Result := OutTokens;
End;

Function TokensToRawLines(Const Tokens: TStyleTokenArray): TRawLineArray;
Var
  LineCount, Index, Run, Blank, TokenCount: Integer;
  Current: TStyleTokenArray;
  PendingBlank: Boolean;
Begin
  Result := Nil;
  LineCount := 0;
  SetLength(Current, 0);
  TokenCount := 0;
  PendingBlank := False;
  Index := 0;
  While Index <= High(Tokens) Do
    Begin
      If Tokens[Index].Kind = tkNewline Then
        Begin
          Blank := 0;
          Run := Index;
          While (Run <= High(Tokens)) And (Tokens[Run].Kind = tkNewline) Do
            Begin
              Inc(Blank);
              Inc(Run);
            End;
          If TokenCount > 0 Then
            Begin
              SetLength(Result, LineCount + 1);
              Result[LineCount].BlankBefore := PendingBlank;
              Result[LineCount].Tokens := CopyTokens(Current, 0, TokenCount);
              Inc(LineCount);
              TokenCount := 0;
              PendingBlank := Blank >= 2;
            End
          Else If Blank >= 2 Then
            PendingBlank := True;
          Index := Run;
          Continue;
        End;
      If TokenCount >= Length(Current) Then
        Begin
          If Length(Current) = 0 Then
            SetLength(Current, 32)
          Else
            SetLength(Current, Length(Current) * 2);
        End;
      Current[TokenCount] := Tokens[Index];
      Inc(TokenCount);
      Inc(Index);
    End;
  If TokenCount > 0 Then
    Begin
      SetLength(Result, LineCount + 1);
      Result[LineCount].BlankBefore := PendingBlank;
      Result[LineCount].Tokens := CopyTokens(Current, 0, TokenCount);
    End;
End;

Function IndentLines(Const Raw: TRawLineArray): String;
Var
  OutLines: TStringList;
  Stack: TBlockArray;
  Hang, Routine: TIntegerDynArray;
  HangCount, RoutineCount, LineIndex, Ind, Index, IdxClass, Delta: Integer;
  Where: String;
  InLocal, Continued, OnlyDir, NeedBlank, IsForward, IsElseIf: Boolean;
  LastIfIndent, ParenDepth: Integer;
  Kw, Text, Prev, PrevLine, Kind: String;
  LastTok: TStyleToken;
  HasLast: Boolean;
  Vals, After, AfterN: TStyleTokenArray;
  Line: TRawLine;

  Procedure Emit(Const LineText: String; Indent: Integer; Blank: Boolean; Const LineToks: TStyleTokenArray);
  Var
    LastT: TStyleToken;
    HasLastT: Boolean;
    TokIndex, Change: Integer;
  Begin
    If Blank And (OutLines.Count > 0) And (OutLines[OutLines.Count - 1] <> '') Then
      OutLines.Add('');
    If LineText = '' Then
      OutLines.Add('')
    Else If Indent > 0 Then
      OutLines.Add(StringOfChar(' ', Indent * 2) + LineText)
    Else
      OutLines.Add(LineText);
    Change := 0;
    HasLastT := False;
    For TokIndex := 0 To High(LineToks) Do
      Begin
        If LineToks[TokIndex].Kind = tkOp Then
          Begin
            If LineToks[TokIndex].Value = '(' Then
              Inc(Change)
            Else If LineToks[TokIndex].Value = ')' Then
              Dec(Change);
          End;
        If Not (LineToks[TokIndex].Kind In [tkComment, tkDirective]) Then
          Begin
            LastT := LineToks[TokIndex];
            HasLastT := True;
          End;
      End;
    ParenDepth := ParenDepth + Change;
    If ParenDepth < 0 Then
      ParenDepth := 0;
    Continued := HasLastT And (Not (
      ((LastT.Kind = tkOp) And ((LastT.Value = ';') Or (LastT.Value = '.') Or (LastT.Value = ',')))
      Or IsIdentOneOf(LastT, ['then', 'do', 'else', 'begin', 'try', 'repeat', 'of', 'private', 'public',
        'protected', 'published', 'var', 'type', 'const', 'uses', 'interface', 'implementation', 'end',
        'except', 'finally', 'until', 'initialization', 'finalization', 'class', 'record', 'object',
        'interface', 'threadvar', 'resourcestring'])
    ));
  End;

  Function TopKind: String;
  Begin
    If Length(Stack) = 0 Then
      Result := ''
    Else
      Result := Stack[High(Stack)].Kind;
  End;

  Function TopIndent: Integer;
  Begin
    If Length(Stack) = 0 Then
      Result := 0
    Else
      Result := Stack[High(Stack)].Indent;
  End;

  Function InClassLike: Boolean;
  Begin
    Result := (TopKind = 'class') Or (TopKind = 'record') Or (TopKind = 'object') Or (TopKind = 'intf');
  End;

Begin
  OutLines := TStringList.Create;
  Try
    SetLength(Stack, 0);
    SetLength(Hang, 0);
    SetLength(Routine, 0);
    HangCount := 0;
    RoutineCount := 0;
    Where := '';
    InLocal := False;
    LastIfIndent := 0;
    ParenDepth := 0;
    Continued := False;
    For LineIndex := 0 To High(Raw) Do
      Begin
        Line := Raw[LineIndex];
        Kw := FirstIdent(Line.Tokens);
        OnlyDir := True;
        For Index := 0 To High(Line.Tokens) Do
          If Not (Line.Tokens[Index].Kind In [tkDirective, tkComment]) Then
            OnlyDir := False;
        Text := JoinTokenLine(Line.Tokens);
        Index := LastCodeIndex(Line.Tokens);
        HasLast := Index >= 0;
        If HasLast Then
          LastTok := Line.Tokens[Index];

        If OnlyDir Then
          Begin
            If Length(Stack) > 0 Then
              Ind := TopIndent + 1
            Else If InLocal And (RoutineCount > 0) Then
              Ind := Routine[RoutineCount - 1] + 1
            Else If (Length(Line.Tokens) > 0) And (Line.Tokens[0].Kind = tkDirective) Then
              Ind := 0
            Else If (Where = 'interface') Or (Where = 'implementation') Then
              Begin
                Prev := Trim(LastNonBlank(OutLines));
                If (Prev = 'Type') Or (Prev = 'Const') Or (Prev = 'Var') Or (Prev = 'Uses')
                  Or (Prev = 'ThreadVar') Or (Prev = 'ResourceString')
                  Or ((Copy(LastNonBlank(OutLines), 1, 2) = '  ') And (Not (
                    AnsiStartsText('Function ', TrimLeft(LastNonBlank(OutLines)))
                    Or AnsiStartsText('Procedure ', TrimLeft(LastNonBlank(OutLines)))
                    Or AnsiStartsText('Constructor ', TrimLeft(LastNonBlank(OutLines)))
                    Or AnsiStartsText('Destructor ', TrimLeft(LastNonBlank(OutLines)))
                    Or AnsiStartsText('Property ', TrimLeft(LastNonBlank(OutLines)))
                  ))) Then
                  Ind := 1
                Else
                  Ind := 0;
              End
            Else
              Ind := 0;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            Continue;
          End;

        If IsIdentOneOf(MakeToken(tkIdent, Kw, 0, 0), ['interface', 'implementation', 'initialization', 'finalization'])
          And (ParenDepth = 0) Then
          Begin
            If OutLines.Count > 0 Then
              PrevLine := Trim(OutLines[OutLines.Count - 1])
            Else
              PrevLine := '';
            If Not ((Length(PrevLine) > 0) And (PrevLine[Length(PrevLine)] = '=')) Then
              Begin
                Where := Kw;
                SetLength(Stack, 0);
                HangCount := 0;
                RoutineCount := 0;
                InLocal := False;
                ParenDepth := 0;
                Continued := False;
                Emit(Text, 0, True, Line.Tokens);
                Continue;
              End;
          End;

        If IsIdentOneOf(MakeToken(tkIdent, Kw, 0, 0), ['type', 'const', 'uses', 'label', 'resourcestring', 'threadvar', 'var'])
          And (ParenDepth = 0) And (Not Continued) Then
          Begin
            HangCount := 0;
            If InClassLike Then
              Ind := TopIndent + 1
            Else If InLocal And (RoutineCount > 0) Then
              Ind := Routine[RoutineCount - 1]
            Else
              Ind := 0;
            Emit(Text, Ind, Not (InLocal And ((Kw = 'var') Or (Kw = 'const') Or (Kw = 'type'))), Line.Tokens);
            Continue;
          End;

        If IsVisibilityName(Kw) Or (Kw = 'strict') Then
          Begin
            HangCount := 0;
            If InClassLike Then
              Ind := TopIndent
            Else
              Ind := 0;
            Emit(Text, Ind, False, Line.Tokens);
            Continue;
          End;

        If (Kw = 'function') Or (Kw = 'procedure') Or (Kw = 'constructor') Or (Kw = 'destructor') Or (Kw = 'operator') Then
          Begin
            HangCount := 0;
            If InClassLike Then
              Begin
                Ind := TopIndent + 1;
                Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
              End
            Else If InLocal And (RoutineCount > 0) Then
              Begin
                Ind := Routine[RoutineCount - 1] + 1;
                PushInt(Routine, RoutineCount, Ind);
                Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
              End
            Else
              Begin
                If OutLines.Count > 0 Then
                  Prev := Trim(OutLines[OutLines.Count - 1])
                Else
                  Prev := '';
                NeedBlank := (Where = 'implementation') And (Copy(Prev, 1, 2) <> '{$');
                Emit(Text, 0, NeedBlank Or Line.BlankBefore Or AnsiStartsStr('End', Prev), Line.Tokens);
                PushInt(Routine, RoutineCount, 0);
                If Where = 'implementation' Then
                  InLocal := True;
              End;
            Continue;
          End;

        If (Kw = 'begin') Or (Kw = 'try') Or (Kw = 'repeat') Then
          Begin
            If InLocal And (RoutineCount > 0) And (Kw = 'begin') And (HangCount = 0) Then
              Begin
                Ind := Routine[RoutineCount - 1];
                InLocal := False;
              End
            Else If HangCount > 0 Then
              Begin
                Ind := Hang[HangCount - 1] + 1;
                Dec(HangCount);
              End
            Else If Length(Stack) > 0 Then
              Ind := TopIndent + 1
            Else
              Ind := 0;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            PushBlock(Stack, Kw, Ind);
            Continue;
          End;

        If (Kw = 'except') Or (Kw = 'finally') Then
          Begin
            HangCount := 0;
            Ind := 0;
            For Index := High(Stack) DownTo 0 Do
              If Stack[Index].Kind = 'try' Then
                Begin
                  Ind := Stack[Index].Indent;
                  Break;
                End;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            Continue;
          End;

        If Kw = 'until' Then
          Begin
            HangCount := 0;
            Ind := 0;
            If (Length(Stack) > 0) And (TopKind = 'repeat') Then
              Begin
                Ind := TopIndent;
                SetLength(Stack, Length(Stack) - 1);
              End;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            HangCount := 0;
            Continue;
          End;

        If Kw = 'else' Then
          Begin
            HangCount := 0;
            If (Length(Stack) > 0) And (TopKind = 'case') Then
              Ind := TopIndent
            Else
              Ind := LastIfIndent;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            IsElseIf := False;
            For Index := 1 To High(Line.Tokens) Do
              If IsIdentNamed(Line.Tokens[Index], 'If') Then
                IsElseIf := True;
            If IsElseIf Then
              Begin
                LastIfIndent := Ind;
                If HasLast And IsIdentNamed(LastTok, 'Then') Then
                  PushInt(Hang, HangCount, Ind);
              End
            Else If HasLast And IsIdentNamed(LastTok, 'Else') Then
              PushInt(Hang, HangCount, Ind);
            Continue;
          End;

        If Kw = 'end' Then
          Begin
            HangCount := 0;
            If Length(Stack) > 0 Then
              Begin
                Ind := TopIndent;
                Kind := TopKind;
                SetLength(Stack, Length(Stack) - 1);
              End
            Else
              Begin
                Ind := 0;
                Kind := '';
              End;
            Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
            If (Kind = 'begin') And (RoutineCount > 0) And (Ind = Routine[RoutineCount - 1]) Then
              Begin
                Dec(RoutineCount);
                InLocal := RoutineCount > 0;
              End;
            Continue;
          End;

        If (HangCount > 0) And ((Length(Stack) = 0) Or (Hang[HangCount - 1] >= TopIndent)) Then
          Ind := Hang[HangCount - 1] + 1
        Else If Length(Stack) > 0 Then
          Ind := TopIndent + 1
        Else If InLocal And (RoutineCount > 0) Then
          Ind := Routine[RoutineCount - 1] + 1
        Else If (Where = 'interface') Or (Where = 'implementation') Then
          Ind := 1
        Else
          Ind := 0;

        If ParenDepth > 0 Then
          Begin
            HasLast := False;
            For Index := 0 To High(Line.Tokens) Do
              If Not (Line.Tokens[Index].Kind In [tkComment, tkDirective]) Then
                Begin
                  LastTok := Line.Tokens[Index];
                  HasLast := True;
                  Break;
                End;
            If Not (HasLast And (LastTok.Kind = tkOp) And (LastTok.Value = ')')) Then
              Inc(Ind);
          End
        Else If Continued And (Kw <> 'begin') And (Kw <> 'end') And (Kw <> 'else') And (Kw <> 'until')
          And (Kw <> 'except') And (Kw <> 'finally') And (Kw <> 'private') And (Kw <> 'public')
          And (Kw <> 'protected') And (Kw <> 'published') Then
          Inc(Ind);

        Emit(Text, Ind, Line.BlankBefore, Line.Tokens);
        If Kw = 'if' Then
          LastIfIndent := Ind;

        Vals := CodeTokensOf(Line.Tokens);
        If LineHasIdent(Vals, 'Class') Then
          Begin
            IdxClass := 0;
            For Index := 0 To High(Vals) Do
              If IsIdentNamed(Vals[Index], 'Class') Then
                IdxClass := Index;
            After := CopyTokens(Vals, IdxClass + 1, Length(Vals) - IdxClass - 1);
            SetLength(AfterN, 0);
            Delta := 0;
            For Index := 0 To High(After) Do
              If Not ((After[Index].Kind = tkOp) And (After[Index].Value = ';')) Then
                Begin
                  SetLength(AfterN, Delta + 1);
                  AfterN[Delta] := After[Index];
                  Inc(Delta);
                End;
            IsForward := HasLast And (LastTok.Kind = tkOp) And (LastTok.Value = ';') And (
              (Length(AfterN) = 0) Or ((Length(After) = 1) And (After[0].Kind = tkOp) And (After[0].Value = ';'))
            );
            If (Length(AfterN) > 0) And IsIdentOneOf(AfterN[0], ['of', 'helper', 'procedure', 'function', 'var',
              'property', 'operator', 'sealed', 'abstract']) Then
              { not a class body }
            Else If IsForward Then
              { forward }
            Else
              PushBlock(Stack, 'class', Ind);
          End;
        If LineHasIdent(Vals, 'Record') And HasLast And IsIdentNamed(LastTok, 'Record') Then
          PushBlock(Stack, 'record', Ind);
        If LineHasIdent(Vals, 'Object') And HasLast And IsIdentNamed(LastTok, 'Object') Then
          PushBlock(Stack, 'object', Ind);
        If LineHasIdent(Vals, 'Interface') And (Kw <> 'interface') And HasLast
          And (Not ((LastTok.Kind = tkOp) And (LastTok.Value = ';'))) Then
          If IsIdentNamed(LastTok, 'Interface') Or ((LastTok.Kind = tkOp) And (LastTok.Value = ']')) Then
            PushBlock(Stack, 'intf', Ind);
        If LineHasIdent(Vals, 'Case') And LineHasIdent(Vals, 'Of') Then
          PushBlock(Stack, 'case', Ind);

        If HasLast And IsIdentOneOf(LastTok, ['then', 'do']) Then
          PushInt(Hang, HangCount, Ind)
        Else If HasLast And IsIdentNamed(LastTok, 'Else') Then
          PushInt(Hang, HangCount, Ind)
        Else If HasLast And (LastTok.Kind = tkOp) And (LastTok.Value = ';') And (HangCount > 0)
          And (Ind = Hang[HangCount - 1] + 1) Then
          Dec(HangCount);
      End;

    While (OutLines.Count > 0) And (OutLines[0] = '') Do
      OutLines.Delete(0);
    While (OutLines.Count > 0) And (OutLines[OutLines.Count - 1] = '') Do
      OutLines.Delete(OutLines.Count - 1);
    Result := '';
    For Index := 0 To OutLines.Count - 1 Do
      Begin
        If (Index > 0) And (OutLines[Index] = '') And (OutLines[Index - 1] = '') Then
          Continue;
        If Result <> '' Then
          Result := Result + #10;
        Result := Result + OutLines[Index];
      End;
    Result := Result + #10;
  Finally
    OutLines.Free;
  End;
End;

Function SkipWhite(Const S: String; Pos: Integer): Integer;
Begin
  Result := Pos;
  While (Result <= Length(S)) And (S[Result] In [' ', #9, #10, #13]) Do
    Inc(Result);
End;

Function StartsWord(Const S: String; Pos: Integer; Const Word: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  If Pos + Length(Word) - 1 > Length(S) Then
    Exit;
  For Index := 1 To Length(Word) Do
    If UpCase(S[Pos + Index - 1]) <> UpCase(Word[Index]) Then
      Exit;
  If Pos + Length(Word) <= Length(S) Then
    If S[Pos + Length(Word)] In ['A'..'Z', 'a'..'z', '0'..'9', '_'] Then
      Exit;
  Result := True;
End;

Procedure ExtractHeader(Const Source: String; Out UnitName, Description: String; Extras: TStrings; Out Remainder: String);
Var
  Pos, EndPos, Depth, NameStart: Integer;
  Inner, UpInner: String;
Begin
  UnitName := '';
  Description := '';
  Remainder := Source;
  Extras.Clear;
  Pos := SkipWhite(Source, 1);
  If Not StartsWord(Source, Pos, 'Unit') Then
    Exit;
  Pos := SkipWhite(Source, Pos + 4);
  NameStart := Pos;
  While (Pos <= Length(Source)) And (Source[Pos] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Do
    Inc(Pos);
  UnitName := Copy(Source, NameStart, Pos - NameStart);
  Pos := SkipWhite(Source, Pos);
  If (Pos > Length(Source)) Or (Source[Pos] <> ';') Then
    Begin
      UnitName := '';
      Remainder := Source;
      Exit;
    End;
  Inc(Pos);
  While True Do
    Begin
      Pos := SkipWhite(Source, Pos);
      If Pos > Length(Source) Then
        Break;
      If StartsWord(Source, Pos, 'Interface') Then
        Begin
          Description := Trim(Description);
          Remainder := Copy(Source, Pos, MaxInt);
          Exit;
        End;
      If (Source[Pos] = '{') And (Pos < Length(Source)) And (Source[Pos + 1] = '$') Then
        Begin
          EndPos := PosEx('}', Source, Pos);
          If EndPos < 1 Then
            Break;
          Inner := Trim(Copy(Source, Pos + 2, EndPos - Pos - 2));
          UpInner := UpperCase(Inner);
          If AnsiStartsStr('IFDEF FPC', UpInner) Then
            Begin
              Pos := EndPos + 1;
              Depth := 1;
              While (Pos <= Length(Source)) And (Depth > 0) Do
                Begin
                  Pos := SkipWhite(Source, Pos);
                  If (Pos <= Length(Source)) And (Source[Pos] = '{') And (Pos < Length(Source)) And (Source[Pos + 1] = '$') Then
                    Begin
                      EndPos := PosEx('}', Source, Pos);
                      If EndPos < 1 Then
                        Break;
                      Inner := Trim(Copy(Source, Pos + 2, EndPos - Pos - 2));
                      UpInner := UpperCase(Inner);
                      If AnsiStartsStr('ENDIF', UpInner) Or AnsiStartsStr('IFEND', UpInner) Then
                        Begin
                          Dec(Depth);
                          Pos := EndPos + 1;
                          Continue;
                        End;
                      If AnsiStartsStr('IFDEF', UpInner) Or AnsiStartsStr('IFNDEF', UpInner) Or AnsiStartsStr('IF ', UpInner) Then
                        Begin
                          Inc(Depth);
                          Pos := EndPos + 1;
                          Continue;
                        End;
                      If AnsiStartsStr('ELSE', UpInner) Then
                        Begin
                          Pos := EndPos + 1;
                          Continue;
                        End;
                      If AnsiStartsStr('MODE', UpInner) Or AnsiStartsStr('LONGSTRINGS', UpInner) Or AnsiStartsStr('H+', UpInner) Then
                        Begin
                          Pos := EndPos + 1;
                          Continue;
                        End;
                      Extras.Add('{$' + Inner + '}');
                      Pos := EndPos + 1;
                      Continue;
                    End;
                  Break;
                End;
              Continue;
            End;
          If AnsiStartsStr('MODE', UpInner) Or AnsiStartsStr('LONGSTRINGS', UpInner) Or AnsiStartsStr('H+', UpInner) Then
            Begin
              Pos := EndPos + 1;
              Continue;
            End;
          If AnsiStartsStr('CODEPAGE', UpInner) Or AnsiStartsStr('MODESWITCH', UpInner) Then
            Begin
              Extras.Add(Copy(Source, Pos, EndPos - Pos + 1));
              Pos := EndPos + 1;
              Continue;
            End;
          Break;
        End;
      If Source[Pos] = '{' Then
        Begin
          EndPos := PosEx('}', Source, Pos);
          If EndPos < 1 Then
            Break;
          Description := Description + Copy(Source, Pos, EndPos - Pos + 1);
          Pos := EndPos + 1;
          Continue;
        End;
      If Copy(Source, Pos, 2) = '(*' Then
        Begin
          EndPos := PosEx('*)', Source, Pos);
          If EndPos < 1 Then
            Break;
          Description := Description + Copy(Source, Pos, EndPos - Pos + 2);
          Pos := EndPos + 2;
          Continue;
        End;
      Break;
    End;
  Description := Trim(Description);
  Remainder := Copy(Source, Pos, MaxInt);
End;

Function NormalizeDescription(Const Desc, UnitName: String): String;
Var
  Body, Inner: String;
  BraceOpen, BraceClose, Index: Integer;
  Parts: TStringList;
Begin
  If Trim(Desc) = '' Then
    Begin
      Result := '{ ' + UnitName + ' (c) 2026 Michell Computing. }';
      Exit;
    End;
  BraceOpen := Pos('{', Desc);
  BraceClose := 0;
  If BraceOpen > 0 Then
    BraceClose := PosEx('}', Desc, BraceOpen + 1);
  If (BraceOpen = 1) Or ((BraceOpen > 0) And (Trim(Copy(Desc, 1, BraceOpen - 1)) = '')) Then
    If BraceClose > BraceOpen Then
      Begin
        Inner := Copy(Desc, BraceOpen + 1, BraceClose - BraceOpen - 1);
        Body := Trim(Inner);
        Body := Trim(StringReplace(Body, #13, '', [rfReplaceAll]));
        If (Pos('(c)', LowerCase(Body)) < 1) And (Pos('michell computing', LowerCase(Body)) < 1) Then
          Begin
            If (Body <> '') And (Body[Length(Body)] = '.') Then
              Body := Body + ' (c) 2026 Michell Computing.'
            Else
              Body := Body + ' (c) 2026 Michell Computing.';
          End;
        If Pos(#10, Inner) > 0 Then
          Begin
            Parts := TStringList.Create;
            Try
              Parts.Text := Body;
              If Parts.Count > 0 Then
                Result := '{ ' + TrimLeft(Parts[0])
              Else
                Result := '{ ';
              For Index := 1 To Parts.Count - 1 Do
                If Trim(Parts[Index]) = '' Then
                  Result := Result + #10
                Else
                  Result := Result + #10 + '  ' + Trim(Parts[Index]);
              If (Result = '') Or (Result[Length(Result)] <> '}') Then
                Result := Result + ' }';
            Finally
              Parts.Free;
            End;
            Exit;
          End;
        Result := '{ ' + Body + ' }';
        Exit;
      End;
  If Pos('(c)', LowerCase(Desc)) < 1 Then
    Result := Desc + #10 + '{ (c) 2026 Michell Computing. }'
  Else
    Result := Desc;
End;

Function BuildHeader(Const UnitName, Desc: String; Extras: TStrings): String;
Var
  Index: Integer;
  Inner, Key, UpInner, ExtraLines, Rest: String;
  Seen: TStringList;
  SpaceAt: Integer;
Begin
  ExtraLines := '';
  Seen := TStringList.Create;
  Try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    For Index := 0 To Extras.Count - 1 Do
      Begin
        Inner := Trim(Extras[Index]);
        Key := UpperCase(Inner);
        If Seen.IndexOf(Key) >= 0 Then
          Continue;
        Seen.Add(Key);
        If Copy(Inner, 1, 2) <> '{$' Then
          Inner := '{$' + TrimSet(Inner, ['{', '}']) + '}';
        UpInner := UpperCase(Trim(Copy(Inner, 3, Length(Inner) - 3)));
        If AnsiStartsStr('CODEPAGE', UpInner) Then
          Inner := '{$CODEPAGE UTF8}'
        Else If AnsiStartsStr('MODESWITCH', UpInner) Then
          Begin
            Rest := Trim(Copy(Inner, 3, Length(Inner) - 3));
            SpaceAt := Pos(' ', Rest);
            If SpaceAt > 0 Then
              Inner := '{$MODESWITCH ' + UpperCase(Trim(Copy(Rest, SpaceAt + 1, MaxInt))) + '}'
            Else
              Inner := '{$MODESWITCH}';
          End;
        ExtraLines := ExtraLines + '  ' + Inner + #10;
      End;
  Finally
    Seen.Free;
  End;
  Result := 'Unit ' + UnitName + ';' + #10 + #10
    + NormalizeDescription(Desc, UnitName) + #10 + #10
    + '{$IFDEF FPC}' + #10
    + '  {$MODE ObjFPC}' + #10
    + '  {$LONGSTRINGS ON}' + #10
    + ExtraLines
    + '{$ENDIF}' + #10 + #10;
End;

Function FormatPascalSource(Const Source: String): String;
Var
  Text, UnitName, Description, Remainder, Header, Body: String;
  Extras: TStringList;
  Tokens: TStyleTokenArray;
Begin
  Text := Source;
  If (Length(Text) >= 3) And (Text[1] = #$EF) And (Text[2] = #$BB) And (Text[3] = #$BF) Then
    Delete(Text, 1, 3);
  Extras := TStringList.Create;
  Try
    ExtractHeader(Text, UnitName, Description, Extras, Remainder);
    If UnitName = '' Then
      Begin
        Tokens := InsertPackedBreaks(TokenizePascal(Text));
        Result := IndentLines(TokensToRawLines(Tokens));
        Exit;
      End;
    Header := BuildHeader(UnitName, Description, Extras);
    Tokens := InsertPackedBreaks(TokenizePascal(Remainder));
    Body := IndentLines(TokensToRawLines(Tokens));
    While (Length(Body) > 0) And (Body[1] = #10) Do
      Delete(Body, 1, 1);
    Result := Header + Body;
    If (Result = '') Or (Result[Length(Result)] <> #10) Then
      Result := Result + #10;
  Finally
    Extras.Free;
  End;
End;

Procedure CollectTokenFingerprint(Const Source: String; Names: TStrings);
Var
  Tokens: TStyleTokenArray;
  Index: Integer;
  Inner: String;
Begin
  Names.Clear;
  Tokens := TokenizePascal(Source);
  For Index := 0 To High(Tokens) Do
    Begin
      If Tokens[Index].Kind = tkNewline Then
        Continue;
      If Tokens[Index].Kind = tkDirective Then
        Begin
          Inner := UpperCase(Trim(Copy(Tokens[Index].Value, 3, Length(Tokens[Index].Value) - 3)));
          Inner := StringReplace(Inner, ' ', '', [rfReplaceAll]);
          If AnsiStartsStr('IFDEF', Inner) Or AnsiStartsStr('ENDIF', Inner) Or AnsiStartsStr('MODE', Inner)
            Or AnsiStartsStr('LONGSTRINGS', Inner) Or AnsiStartsStr('H+', Inner) Then
            Continue;
          Names.Add('DIR:' + Inner);
          Continue;
        End;
      If Tokens[Index].Kind = tkComment Then
        Continue;
      If Tokens[Index].Kind = tkIdent Then
        Names.Add(LowerCase(Tokens[Index].Value))
      Else
        Names.Add(Tokens[Index].Value);
    End;
End;

Function TokenFingerprintsEqual(Const Left, Right: String): Boolean;
Var
  A, B: TStringList;
  Index: Integer;
Begin
  Result := False;
  A := TStringList.Create;
  B := TStringList.Create;
  Try
    CollectTokenFingerprint(Left, A);
    CollectTokenFingerprint(Right, B);
    If A.Count <> B.Count Then
      Exit;
    For Index := 0 To A.Count - 1 Do
      If A[Index] <> B[Index] Then
        Exit;
    Result := True;
  Finally
    A.Free;
    B.Free;
  End;
End;

End.
