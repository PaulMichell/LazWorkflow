Unit AssistantFormMembers;

{$mode objfpc}{$H+}

Interface

Uses SysUtils, Classes, CodeCache;

Function BindFormMembers(Code: TCodeBuffer; Const LfmBody, CompName, ClassName,
  MethodName: String; Var Body: String; Out FormClass, ErrorText: String): Boolean;

Implementation

Uses CodeToolManager, CodeTree, PascalParserTool;

Function RootClassName(Const LfmBody: String): String;
Var
  Stream: TStringStream;
  Parser: TParser;
Begin
  Stream := TStringStream.Create(LfmBody);
  Try
    Parser := TParser.Create(Stream);
    Try
      If Not (Parser.TokenSymbolIs('object') Or Parser.TokenSymbolIs('inherited') Or
        Parser.TokenSymbolIs('inline')) Then Exit('');
      Parser.NextToken;
      Parser.CheckToken(toSymbol);
      Parser.NextToken;
      Parser.CheckToken(':');
      Parser.NextToken;
      Parser.CheckToken(toSymbol);
      Result := Parser.TokenString;
    Finally
      Parser.Free;
    End;
  Finally
    Stream.Free;
  End;
End;

Function BindFormMembers(Code: TCodeBuffer; Const LfmBody, CompName, ClassName,
  MethodName: String; Var Body: String; Out FormClass, ErrorText: String): Boolean;
Var
  Tool: TCodeTool;
  Owner, Section, Impl, Node: TCodeTreeNode;
  Members, Stub: String;
  MemberPos, StubPos: Integer;

  Procedure CheckHandler(Handler: TCodeTreeNode);
  Var
    Header: String;
  Begin
    If Handler.Desc = ctnProcedure Then
      Begin
        Header := Tool.ExtractProcHead(Handler, [phpWithStart, phpWithoutClassName,
          phpWithoutName, phpWithVarModifiers, phpWithResultType, phpWithCallingSpecs,
          phpWithoutSemicolon]);
        If SameText(Trim(Header), 'procedure(TObject)') Then Exit;
      End;
    Raise Exception.CreateFmt('%s.%s must be an instance procedure with one TObject parameter.',
      [FormClass, MethodName]);
  End;

  Function SourceOffset(CleanPos: Integer): Integer;
  Var
    Location: TCodePosition;
  Begin
    If Not Tool.CleanPosToCodePos(CleanPos, Location) Or (Location.Code <> Code) Then
      Raise Exception.Create('Insertion point is outside the form unit.');
    Result := Location.P;
  End;

Begin
  Result := False;
  Try
    FormClass := RootClassName(LfmBody);
    If FormClass = '' Then Raise Exception.Create('Missing LFM root class.');
    If (Code = Nil) Or (Code.Source <> Body) Then
      Raise Exception.Create('Form source differs from the CodeTools buffer.');
    If Not CodeToolBoss.Explore(Code, Tool, False) Then
      Raise Exception.Create(CodeToolBoss.ErrorMessage);
    Owner := Tool.FindClassNodeInUnit(FormClass, True, False, False, False);
    If (Owner = Nil) Or (Owner.Desc <> ctnClass) Then
      Raise Exception.CreateFmt('Cannot resolve LFM class %s in the form unit.', [FormClass]);
    Tool.BuildSubTreeAndFindDeepestNodeAtPos(Owner.StartPos, False);
    Members := '';
    If Tool.FindClassMember(Owner, CompName, False).Node = Nil Then
      Members := '    ' + CompName + ': ' + ClassName + ';' + LineEnding;
    Stub := '';
    StubPos := 0;
    If MethodName <> '' Then
      Begin
        Node := Tool.FindClassMember(Owner, MethodName, False).Node;
        If Node <> Nil Then CheckHandler(Node)
        Else
          Members := Members + '    Procedure ' + MethodName + '(Sender: TObject);' + LineEnding;
        Impl := Tool.FindImplementationNode;
        If Impl = Nil Then Raise Exception.Create('Missing implementation section.');
        Node := Impl.FirstChild;
        While Node <> Nil Do
          Begin
            If (Node.Desc = ctnProcedure) And
              SameText(Tool.ExtractProcName(Node, []), FormClass + '.' + MethodName) Then
              Begin
                CheckHandler(Node);
                Break;
              End;
            Node := Node.NextBrother;
          End;
        If Node = Nil Then
          Begin
            Node := Tool.FindInitializationNode;
            If Node = Nil Then Node := Tool.FindFinalizationNode;
            If Node <> Nil Then StubPos := SourceOffset(Node.StartPos)
            Else StubPos := SourceOffset(Impl.EndPos);
            Stub := LineEnding + 'Procedure ' + FormClass + '.' + MethodName +
              '(Sender: TObject);' + LineEnding + 'Begin' + LineEnding + 'End;' + LineEnding;
          End;
      End;
    MemberPos := 0;
    If Members <> '' Then
      Begin
        Section := Owner.LastChild;
        If (Section = Nil) Or Not (Section.Desc In AllClassSections) Then
          Raise Exception.Create('Cannot locate the end of the form declaration.');
        MemberPos := SourceOffset(Section.EndPos);
        Members := LineEnding + '  published' + LineEnding + Members;
        If Copy(Body, MemberPos, 1) = ';' Then Members := Members + '  end';
      End;
    If Stub <> '' Then Insert(Stub, Body, StubPos);
    If Members <> '' Then Insert(Members, Body, MemberPos);
    Result := True;
  Except
    On E: Exception Do ErrorText := E.Message;
  End;
End;

End.
