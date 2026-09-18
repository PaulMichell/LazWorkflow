Unit PascalStyleTokens;

{ Michell Computing Pascal tokenizer and line joiner (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Type
  TTokenKind = (tkIdent, tkNumber, tkString, tkChar, tkOp, tkComment, tkDirective, tkNewline);

  TStyleToken = Record
    Kind: TTokenKind;
    Value: String;
    Line, Column: Integer;
  End;

  TStyleTokenArray = Array Of TStyleToken;

Function TokenizePascal(Const Source: String): TStyleTokenArray;
Function RecaseIdent(Const Ident: String): String;
Function IsIdentToken(Const Token: TStyleToken): Boolean;
Function IsIdentNamed(Const Token: TStyleToken; Const Name: String): Boolean;
Function IsIdentOneOf(Const Token: TStyleToken; Const Names: Array Of String): Boolean;
Function TokenLower(Const Token: TStyleToken): String;
Function NextCodeIndex(Const Tokens: TStyleTokenArray; FromIndex: Integer): Integer;
Function LastCodeIndex(Const Tokens: TStyleTokenArray): Integer;
Function LastCodeIn(Const Tokens: TStyleTokenArray; Count: Integer): Integer;
Function IsMethodDirectiveName(Const Name: String): Boolean;
Function IsPropertyDirectiveName(Const Name: String): Boolean;
Function IsVisibilityName(Const Name: String): Boolean;
Function IsSpaceKwParenName(Const Name: String): Boolean;
Function IsSpaceAroundOp(Const Op: String): Boolean;
Function JoinTokenLine(Const LineTokens: TStyleTokenArray): String;
Function MakeToken(Kind: TTokenKind; Const Value: String; Line, Column: Integer): TStyleToken;
Procedure AppendToken(Var Tokens: TStyleTokenArray; Const Token: TStyleToken);
Procedure AppendTokenCount(Var Tokens: TStyleTokenArray; Var Count: Integer; Const Token: TStyleToken);

Implementation

Uses
  SysUtils, StrUtils;

Function IsInNames(Const Name: String; Const Names: Array Of String): Boolean;
Var
  Index: Integer;
  Lower: String;
Begin
  Result := False;
  Lower := LowerCase(Name);
  For Index := Low(Names) To High(Names) Do
    If Lower = LowerCase(Names[Index]) Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function RecaseIdent(Const Ident: String): String;
Var
  Lower: String;
Begin
  Lower := LowerCase(Ident);
  Case Lower Of
    'and': Result := 'And';
    'array': Result := 'Array';
    'as': Result := 'As';
    'asm': Result := 'Asm';
    'begin': Result := 'Begin';
    'case': Result := 'Case';
    'class': Result := 'Class';
    'const': Result := 'Const';
    'constructor': Result := 'Constructor';
    'destructor': Result := 'Destructor';
    'div': Result := 'Div';
    'do': Result := 'Do';
    'downto': Result := 'DownTo';
    'else': Result := 'Else';
    'end': Result := 'End';
    'except': Result := 'Except';
    'exports': Result := 'Exports';
    'file': Result := 'File';
    'finalization': Result := 'Finalization';
    'finally': Result := 'Finally';
    'for': Result := 'For';
    'function': Result := 'Function';
    'goto': Result := 'Goto';
    'if': Result := 'If';
    'implementation': Result := 'Implementation';
    'in': Result := 'In';
    'inherited': Result := 'Inherited';
    'initialization': Result := 'Initialization';
    'interface': Result := 'Interface';
    'is': Result := 'Is';
    'label': Result := 'Label';
    'library': Result := 'Library';
    'mod': Result := 'Mod';
    'nil': Result := 'Nil';
    'not': Result := 'Not';
    'object': Result := 'Object';
    'of': Result := 'Of';
    'operator': Result := 'Operator';
    'or': Result := 'Or';
    'packed': Result := 'Packed';
    'procedure': Result := 'Procedure';
    'program': Result := 'Program';
    'property': Result := 'Property';
    'raise': Result := 'Raise';
    'record': Result := 'Record';
    'repeat': Result := 'Repeat';
    'resourcestring': Result := 'ResourceString';
    'set': Result := 'Set';
    'shl': Result := 'Shl';
    'shr': Result := 'Shr';
    'string': Result := 'String';
    'then': Result := 'Then';
    'threadvar': Result := 'ThreadVar';
    'to': Result := 'To';
    'try': Result := 'Try';
    'type': Result := 'Type';
    'unit': Result := 'Unit';
    'until': Result := 'Until';
    'uses': Result := 'Uses';
    'var': Result := 'Var';
    'while': Result := 'While';
    'with': Result := 'With';
    'xor': Result := 'Xor';
    'out': Result := 'Out';
    'override': Result := 'Override';
    'virtual': Result := 'Virtual';
    'abstract': Result := 'Abstract';
    'overload': Result := 'Overload';
    'reintroduce': Result := 'Reintroduce';
    'dynamic': Result := 'Dynamic';
    'private': Result := 'Private';
    'protected': Result := 'Protected';
    'public': Result := 'Public';
    'published': Result := 'Published';
    'strict': Result := 'Strict';
    'read': Result := 'Read';
    'write': Result := 'Write';
    'default': Result := 'Default';
    'nodefault': Result := 'Nodefault';
    'stored': Result := 'Stored';
    'index': Result := 'Index';
    'implements': Result := 'Implements';
    'cdecl': Result := 'Cdecl';
    'stdcall': Result := 'StdCall';
    'register': Result := 'Register';
    'safecall': Result := 'Safecall';
    'pascal': Result := 'Pascal';
    'inline': Result := 'Inline';
    'forward': Result := 'Forward';
    'external': Result := 'External';
    'message': Result := 'Message';
    'static': Result := 'Static';
    'helper': Result := 'Helper';
    'sealed': Result := 'Sealed';
    'experimental': Result := 'Experimental';
    'deprecated': Result := 'Deprecated';
    'platform': Result := 'Platform';
    'generic': Result := 'Generic';
    'specialize': Result := 'Specialize';
    'absolute': Result := 'Absolute';
    'on': Result := 'On';
    'at': Result := 'At';
    'true': Result := 'True';
    'false': Result := 'False';
    'result': Result := 'Result';
    'break': Result := 'Break';
    'continue': Result := 'Continue';
    'exit': Result := 'Exit';
    'assembler': Result := 'Assembler';
    'noreturn': Result := 'Noreturn';
  Else
    Result := Ident;
  End;
End;

Function IsMethodDirectiveName(Const Name: String): Boolean;
Begin
  Result := IsInNames(Name, ['override', 'virtual', 'abstract', 'overload', 'reintroduce', 'dynamic',
    'cdecl', 'stdcall', 'register', 'safecall', 'pascal', 'inline', 'forward', 'external', 'message',
    'static', 'deprecated', 'platform', 'experimental', 'assembler', 'noreturn']);
End;

Function IsPropertyDirectiveName(Const Name: String): Boolean;
Begin
  Result := IsInNames(Name, ['default', 'nodefault', 'stored', 'implements']);
End;

Function IsVisibilityName(Const Name: String): Boolean;
Begin
  Result := IsInNames(Name, ['private', 'protected', 'public', 'published']);
End;

Function IsSpaceKwParenName(Const Name: String): Boolean;
Begin
  Result := IsInNames(Name, ['and', 'or', 'xor', 'not', 'if', 'while', 'until', 'case', 'for', 'with',
    'in', 'is', 'as', 'div', 'mod', 'shl', 'shr', 'of', 'on', 'to', 'downto', 'then', 'else', 'do']);
End;

Function IsSpaceAroundOp(Const Op: String): Boolean;
Begin
  Result := (Op = ':=') Or (Op = '+=') Or (Op = '-=') Or (Op = '*=') Or (Op = '/=') Or (Op = '=')
    Or (Op = '<>') Or (Op = '<=') Or (Op = '>=') Or (Op = '<') Or (Op = '>') Or (Op = '+')
    Or (Op = '-') Or (Op = '*') Or (Op = '/');
End;

Function IsTwoCharOpAt(Const Source: String; Index: Integer): Boolean;
Var
  Pair: String;
Begin
  Result := False;
  If Index >= Length(Source) Then
    Exit;
  Pair := Copy(Source, Index, 2);
  Result := (Pair = ':=') Or (Pair = '+=') Or (Pair = '-=') Or (Pair = '*=') Or (Pair = '/=')
    Or (Pair = '<=') Or (Pair = '>=') Or (Pair = '<>') Or (Pair = '..');
End;

Function IsIdentToken(Const Token: TStyleToken): Boolean;
Begin
  Result := Token.Kind = tkIdent;
End;

Function IsIdentNamed(Const Token: TStyleToken; Const Name: String): Boolean;
Begin
  Result := (Token.Kind = tkIdent) And (LowerCase(Token.Value) = LowerCase(Name));
End;

Function IsIdentOneOf(Const Token: TStyleToken; Const Names: Array Of String): Boolean;
Begin
  Result := (Token.Kind = tkIdent) And IsInNames(Token.Value, Names);
End;

Function TokenLower(Const Token: TStyleToken): String;
Begin
  If Token.Kind = tkIdent Then
    Result := LowerCase(Token.Value)
  Else
    Result := '';
End;

Function NextCodeIndex(Const Tokens: TStyleTokenArray; FromIndex: Integer): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := FromIndex To High(Tokens) Do
    If Not (Tokens[Index].Kind In [tkNewline, tkComment, tkDirective]) Then
      Begin
        Result := Index;
        Exit;
      End;
End;

Function LastCodeIndex(Const Tokens: TStyleTokenArray): Integer;
Begin
  Result := LastCodeIn(Tokens, Length(Tokens));
End;

Function LastCodeIn(Const Tokens: TStyleTokenArray; Count: Integer): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := Count - 1 DownTo 0 Do
    If Not (Tokens[Index].Kind In [tkNewline, tkComment, tkDirective]) Then
      Begin
        Result := Index;
        Exit;
      End;
End;

Function MakeToken(Kind: TTokenKind; Const Value: String; Line, Column: Integer): TStyleToken;
Begin
  Result.Kind := Kind;
  Result.Value := Value;
  Result.Line := Line;
  Result.Column := Column;
End;

Procedure AppendToken(Var Tokens: TStyleTokenArray; Const Token: TStyleToken);
Var
  Count: Integer;
Begin
  Count := Length(Tokens);
  SetLength(Tokens, Count + 1);
  Tokens[Count] := Token;
End;

Procedure AppendTokenCount(Var Tokens: TStyleTokenArray; Var Count: Integer; Const Token: TStyleToken);
Begin
  If Count >= Length(Tokens) Then
    Begin
      If Length(Tokens) = 0 Then
        SetLength(Tokens, 256)
      Else
        SetLength(Tokens, Length(Tokens) * 2);
    End;
  Tokens[Count] := Token;
  Inc(Count);
End;

Function CountChar(Const S: String; Ch: Char): Integer;
Var
  Index: Integer;
Begin
  Result := 0;
  For Index := 1 To Length(S) Do
    If S[Index] = Ch Then
      Inc(Result);
End;

Function LastLineLength(Const S: String): Integer;
Var
  Index: Integer;
Begin
  Result := 0;
  For Index := Length(S) DownTo 1 Do
    If S[Index] = #10 Then
      Begin
        Result := Length(S) - Index;
        Exit;
      End;
  Result := Length(S);
End;

Function TokenizePascal(Const Source: String): TStyleTokenArray;
Var
  Index, Count, Finish, Line, Column, StartLine, StartCol, NewLines: Integer;
  Ch: Char;
  Raw, Ident: String;
  Kind: TTokenKind;
Begin
  Result := Nil;
  Count := 0;
  Index := 1;
  Line := 1;
  Column := 1;
  While Index <= Length(Source) Do
    Begin
      Ch := Source[Index];
      If Ch = #13 Then
        Begin
          Inc(Index);
          Continue;
        End;
      If Ch = #10 Then
        Begin
          AppendTokenCount(Result, Count, MakeToken(tkNewline, #10, Line, Column));
          Inc(Index);
          Inc(Line);
          Column := 1;
          Continue;
        End;
      If (Ch = ' ') Or (Ch = #9) Then
        Begin
          Inc(Index);
          Inc(Column);
          Continue;
        End;
      StartLine := Line;
      StartCol := Column;
      If Ch = '{' Then
        Begin
          Finish := PosEx('}', Source, Index);
          If Finish < 1 Then
            Finish := Length(Source);
          Raw := Copy(Source, Index, Finish - Index + 1);
          If (Length(Raw) > 1) And (Raw[2] = '$') Then
            Kind := tkDirective
          Else
            Kind := tkComment;
          AppendTokenCount(Result, Count, MakeToken(Kind, Raw, StartLine, StartCol));
          NewLines := CountChar(Raw, #10);
          If NewLines > 0 Then
            Begin
              Inc(Line, NewLines);
              Column := LastLineLength(Raw) + 1;
            End
          Else
            Inc(Column, Length(Raw));
          Index := Finish + 1;
          Continue;
        End;
      If (Ch = '(') And (Index < Length(Source)) And (Source[Index + 1] = '*') Then
        Begin
          Finish := PosEx('*)', Source, Index + 2);
          If Finish < 1 Then
            Finish := Length(Source) - 1;
          Raw := Copy(Source, Index, Finish - Index + 2);
          AppendTokenCount(Result, Count, MakeToken(tkComment, Raw, StartLine, StartCol));
          NewLines := CountChar(Raw, #10);
          If NewLines > 0 Then
            Begin
              Inc(Line, NewLines);
              Column := LastLineLength(Raw) + 1;
            End
          Else
            Inc(Column, Length(Raw));
          Index := Finish + 2;
          Continue;
        End;
      If (Ch = '/') And (Index < Length(Source)) And (Source[Index + 1] = '/') Then
        Begin
          Finish := Index;
          While (Finish <= Length(Source)) And (Not (Source[Finish] In [#10, #13])) Do
            Inc(Finish);
          Raw := Copy(Source, Index, Finish - Index);
          AppendTokenCount(Result, Count, MakeToken(tkComment, Raw, StartLine, StartCol));
          Inc(Column, Length(Raw));
          Index := Finish;
          Continue;
        End;
      If Ch = '''' Then
        Begin
          Finish := Index + 1;
          While Finish <= Length(Source) Do
            Begin
              If Source[Finish] = '''' Then
                Begin
                  If (Finish < Length(Source)) And (Source[Finish + 1] = '''') Then
                    Begin
                      Inc(Finish, 2);
                      Continue;
                    End;
                  Inc(Finish);
                  Break;
                End;
              Inc(Finish);
            End;
          Raw := Copy(Source, Index, Finish - Index);
          AppendTokenCount(Result, Count, MakeToken(tkString, Raw, StartLine, StartCol));
          Inc(Column, Length(Raw));
          Index := Finish;
          Continue;
        End;
      If Ch = '#' Then
        Begin
          Finish := Index + 1;
          While (Finish <= Length(Source)) And (Source[Finish] In ['0'..'9']) Do
            Inc(Finish);
          Raw := Copy(Source, Index, Finish - Index);
          AppendTokenCount(Result, Count, MakeToken(tkChar, Raw, StartLine, StartCol));
          Inc(Column, Length(Raw));
          Index := Finish;
          Continue;
        End;
      If (Ch In ['0'..'9']) Or ((Ch = '$') And (Index < Length(Source)) And (Source[Index + 1] In ['0'..'9', 'A'..'F', 'a'..'f']))
        Or ((Ch In ['%', '&']) And (Index < Length(Source)) And (Source[Index + 1] In ['0'..'9', 'A'..'Z', 'a'..'z'])) Then
        Begin
          Finish := Index + 1;
          While Finish <= Length(Source) Do
            Begin
              If (Source[Finish] = '.') And (Finish < Length(Source)) And (Source[Finish + 1] = '.') Then
                Break;
              If Source[Finish] In ['0'..'9', 'A'..'Z', 'a'..'z', '_', '.', '$'] Then
                Inc(Finish)
              Else
                Break;
            End;
          If (Finish <= Length(Source)) And (Source[Finish] In ['e', 'E']) And (Finish < Length(Source))
            And (Source[Finish + 1] In ['0'..'9', '+', '-']) Then
            Begin
              Inc(Finish);
              If Source[Finish] In ['+', '-'] Then
                Inc(Finish);
              While (Finish <= Length(Source)) And (Source[Finish] In ['0'..'9']) Do
                Inc(Finish);
            End;
          Raw := Copy(Source, Index, Finish - Index);
          AppendTokenCount(Result, Count, MakeToken(tkNumber, Raw, StartLine, StartCol));
          Inc(Column, Length(Raw));
          Index := Finish;
          Continue;
        End;
      If (Ch In ['A'..'Z', 'a'..'z']) Or (Ch = '_') Then
        Begin
          Finish := Index + 1;
          While (Finish <= Length(Source)) And (Source[Finish] In ['A'..'Z', 'a'..'z', '0'..'9', '_']) Do
            Inc(Finish);
          Ident := RecaseIdent(Copy(Source, Index, Finish - Index));
          AppendTokenCount(Result, Count, MakeToken(tkIdent, Ident, StartLine, StartCol));
          Inc(Column, Finish - Index);
          Index := Finish;
          Continue;
        End;
      If IsTwoCharOpAt(Source, Index) Then
        Begin
          AppendTokenCount(Result, Count, MakeToken(tkOp, Copy(Source, Index, 2), StartLine, StartCol));
          Inc(Index, 2);
          Inc(Column, 2);
          Continue;
        End;
      AppendTokenCount(Result, Count, MakeToken(tkOp, Ch, StartLine, StartCol));
      Inc(Index);
      Inc(Column);
    End;
  SetLength(Result, Count);
End;

Function UnaryMinusAfter(Const Prev: TStyleToken; HasPrev: Boolean): Boolean;
Begin
  Result := True;
  If Not HasPrev Then
    Exit;
  If Prev.Kind = tkOp Then
    Begin
      Result := IsInNames(Prev.Value, ['(', '[', ',', ':', '=', ':=', '+=', '-=', '*=', '/=',
        '+', '-', '*', '/', '<', '>', '<=', '>=', '<>', '@']);
      Exit;
    End;
  If Prev.Kind = tkIdent Then
    Begin
      Result := IsSpaceKwParenName(Prev.Value) Or IsIdentOneOf(Prev,
        ['begin', 'try', 'finally', 'except', 'repeat', 'until', 'raise', 'const', 'var', 'out']);
      Exit;
    End;
  Result := False;
End;

Function JoinTokenLine(Const LineTokens: TStyleTokenArray): String;
Var
  Index: Integer;
  Prev: TStyleToken;
  HasPrev, PendingUnary, SpecializeRecent: Boolean;
  GenericDepth: Integer;
  Space, PrevValue, CurValue: String;
Begin
  Result := '';
  If Length(LineTokens) = 0 Then
    Exit;
  HasPrev := False;
  PendingUnary := False;
  SpecializeRecent := False;
  GenericDepth := 0;
  For Index := 0 To High(LineTokens) Do
    Begin
      If Not HasPrev Then
        Begin
          Result := LineTokens[Index].Value;
          Prev := LineTokens[Index];
          HasPrev := True;
          SpecializeRecent := IsIdentNamed(LineTokens[Index], 'Specialize');
          Continue;
        End;
      PrevValue := Prev.Value;
      CurValue := LineTokens[Index].Value;
      Space := ' ';
      If PendingUnary And (LineTokens[Index].Kind In [tkNumber, tkIdent]) Then
        Begin
          Space := '';
          PendingUnary := False;
        End
      Else If PendingUnary And (CurValue = '(') Then
        Begin
          Space := '';
          PendingUnary := False;
        End
      Else If (CurValue = ';') Or (CurValue = ',') Or (CurValue = ')') Or (CurValue = ']') Then
        Space := ''
      Else If (CurValue = '-') And UnaryMinusAfter(Prev, True) Then
        Begin
          If (PrevValue = '(') Or (PrevValue = '[') Or (PrevValue = '@') Then
            Space := ''
          Else
            Space := ' ';
          PendingUnary := True;
        End
      Else If (PrevValue = '(') Or (PrevValue = '[') Then
        Space := ''
      Else If (CurValue = '.') Or (PrevValue = '.') Then
        Space := ''
      Else If PrevValue = '@' Then
        Space := ''
      Else If (CurValue = '^') Or ((PrevValue = '^') And Not IsSpaceAroundOp(CurValue)) Then
        Space := ''
      Else If (CurValue = ':') And (CurValue <> ':=') Then
        Space := ''
      Else If (PrevValue = ':') And (CurValue <> '=') Then
        Space := ' '
      Else If (CurValue = '..') Or (PrevValue = '..') Then
        Space := ''
      Else If CurValue = '(' Then
        Begin
          If (Prev.Kind = tkIdent) And IsSpaceKwParenName(Prev.Value) Then
            Space := ' '
          Else If Prev.Kind = tkIdent Then
            Space := ''
          Else If (Prev.Kind = tkOp) And (IsSpaceAroundOp(PrevValue) Or (PrevValue = ',') Or (PrevValue = ';')) Then
            Space := ' '
          Else If (PrevValue = ')') Or (PrevValue = ']') Then
            Space := ''
          Else If Prev.Kind = tkOp Then
            Space := ' '
          Else
            Space := '';
        End
      Else If CurValue = '[' Then
        Begin
          If (Prev.Kind = tkIdent) And IsIdentOneOf(Prev, ['in', 'of', 'to', 'downto']) Then
            Space := ' '
          Else If Prev.Kind = tkIdent Then
            Space := ''
          Else If (PrevValue = ')') Or (PrevValue = ']') Or (PrevValue = '^') Then
            Space := ''
          Else
            Space := ' ';
        End
      Else If (CurValue = '<') And (SpecializeRecent Or IsIdentNamed(Prev, 'Specialize') Or (GenericDepth > 0)) Then
        Begin
          Space := '';
          Inc(GenericDepth);
        End
      Else If (CurValue = '>') And (GenericDepth > 0) Then
        Begin
          Space := '';
          Dec(GenericDepth);
        End
      Else If ((PrevValue = '<') Or (PrevValue = '>')) And (GenericDepth > 0) Then
        Space := ''
      Else If IsSpaceAroundOp(CurValue) Or IsSpaceAroundOp(PrevValue) Then
        Space := ' '
      Else If (Prev.Kind = tkIdent) And (LineTokens[Index].Kind = tkIdent) Then
        Space := ' '
      Else If (PrevValue = ',') Or (PrevValue = ';') Then
        Space := ' '
      Else If LineTokens[Index].Kind = tkDirective Then
        Space := ''
      Else If (Prev.Kind = tkDirective) And (LineTokens[Index].Kind <> tkComment) Then
        Space := ''
      Else If LineTokens[Index].Kind = tkComment Then
        Space := ' '
      Else If Prev.Kind = tkComment Then
        Space := ' '
      Else
        Space := ' ';
      Result := Result + Space + CurValue;
      Prev := LineTokens[Index];
      If IsIdentNamed(LineTokens[Index], 'Specialize') Then
        SpecializeRecent := True
      Else If Not (LineTokens[Index].Kind In [tkComment, tkDirective]) Then
        Begin
          If Not IsIdentNamed(LineTokens[Index], 'Specialize') Then
            Begin
              If (CurValue <> '<') And (CurValue <> ',') And (CurValue <> '>') Then
                SpecializeRecent := SpecializeRecent And (LineTokens[Index].Kind = tkIdent);
            End;
        End;
    End;
  Result := TrimRight(Result);
End;

End.
