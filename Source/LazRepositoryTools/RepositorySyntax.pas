Unit RepositorySyntax;

{ Language highlighters for Manage Repository SynEdits (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  LazEditHighlighter;

/// Caller owns the result. Nil when the extension has no highlighter.
/// Colours follow the IDE source-editor scheme for that language.
Function CreateRepositoryLanguageHighlighter(Const SourceFileName: String): TLazEditCustomHighlighter;

Implementation

Uses
  Classes, SysUtils, Graphics, SynEditStrConst, LazEditTextAttributes,
  SynHighlighterPas, SynHighlighterXML, SynHighlighterLFM, SynHighlighterSQL, SynHighlighterJScript,
  EditorOptionsIntf, EditorSyntaxHighlighterDef;

Type
  TJSONRange = (jrNone, jrString, jrBlockComment);
  TJSONToken = (jtNone, jtSpace, jtString, jtKey, jtNumber, jtLiteral, jtSymbol, jtBracket, jtComment, jtUnknown);

  { Lazarus SynEdit has no JSON highlighter. Scan JSON here and copy colours from the
    IDE JavaScript scheme, which already styles strings, numbers, keywords, and brackets. }
  TRepositoryJSONHighlighter = Class(TLazEditCustomRangesHighlighter)
  Private
    ScanPos: Integer;
    TokenPos: Integer;
    TokenID: TJSONToken;
    RangeState: TJSONRange;
    StringAttri: TLazEditHighlighterAttributes;
    KeyAttri: TLazEditHighlighterAttributes;
    LiteralAttri: TLazEditHighlighterAttributes;
    NumberAttri: TLazEditHighlighterAttributes;
    SymbolAttri: TLazEditHighlighterAttributes;
    BracketAttri: TLazEditHighlighterAttributes;
    CommentAttri: TLazEditHighlighterAttributes;
    SpaceAttri: TLazEditHighlighterAttributes;
    UnknownAttri: TLazEditHighlighterAttributes;
    Function TokenEquals(Const Expected: String): Boolean;
    Function PeekColon: Boolean;
    Procedure ScanSpace;
    Procedure ScanString(Const Opening: Boolean);
    Procedure ScanNumber;
    Procedure ScanWord;
    Procedure ScanSlash;
    Procedure ScanBlockComment(Const Opening: Boolean);
    Procedure ScanUnknown;
  Public
    Constructor Create(AOwner: TComponent); Override;
    Class Function GetLanguageName: String; Override;
    Procedure InitForScanningLine; Override;
    Procedure Next; Override;
    Function GetEol: Boolean; Override;
    Function GetToken: String; Override;
    Function GetTokenPos: Integer; Override;
    Function GetTokenKind: Integer; Override;
    Procedure GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer); Override;
    Function GetTokenAttribute: TLazEditTextAttribute; Override;
    Function GetTokenClass: TLazEditTokenClass; Override;
    Function GetRange: Pointer; Override;
    Procedure SetRange(Value: Pointer); Override;
    Procedure ResetRange; Override;
  End;

Function NormalizeExt(Const Ext: String): String;
Begin
  Result := LowerCase(Ext);
  If (Result <> '') And (Result[1] <> '.') Then
    Result := '.' + Result;
End;

Function ExtIs(Const Ext: String; Const Names: Array Of String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := Low(Names) To High(Names) Do
    If Ext = Names[I] Then
      Exit(True);
End;

Procedure ApplyIDESettings(HL: TLazEditCustomHighlighter);
Begin
  If Not Assigned(HL) Or Not Assigned(IDEEditorOptions) Then
    Exit;
  Try
    IDEEditorOptions.GetHighlighterSettings(HL);
  Except
  End;
End;

Procedure CopyAttributesByStoredName(Target, Source: TLazEditCustomHighlighter);
Var
  I, J: Integer;
Begin
  If Not Assigned(Target) Or Not Assigned(Source) Then
    Exit;
  For I := 0 To Target.AttrCount - 1 Do
    For J := 0 To Source.AttrCount - 1 Do
      If Source.Attribute[J].StoredName = Target.Attribute[I].StoredName Then
        Target.Attribute[I].Assign(Source.Attribute[J]);
End;

Procedure ApplyJSONScheme(HL: TLazEditCustomHighlighter);
Var
  Probe: TSynJScriptSyn;
Begin
  Probe := TSynJScriptSyn.Create(Nil);
  Try
    ApplyIDESettings(Probe);
    CopyAttributesByStoredName(HL, Probe);
  Finally
    Probe.Free;
  End;
End;

Function TryIDEHighlighter(Const Ext: String): TLazEditCustomHighlighter;
Var
  Id: TIdeSyntaxHighlighterID;
  Cls: TLazEditCustomHighlighterClass;
Begin
  Result := Nil;
  If Not Assigned(IdeSyntaxHighlighters) Then
    Exit;
  Id := IdeSyntaxHighlighters.GetIdForFileExtension(Ext);
  If (Id < IdeHighlighterStartId) Or (Id = IdeHighlighterUnknownId) Then
    Exit;
  Cls := IdeSyntaxHighlighters.SynHlClasses[Id];
  { TIDESyn* classes expect a source-editor host and have faulted when used only for tokens. }
  If Not Assigned(Cls) Or (Pos('IDE', Cls.ClassName) > 0) Then
    Exit;
  Result := Cls.Create(Nil);
End;

Function HighlighterForExt(Const Ext: String): TLazEditCustomHighlighter;
Begin
  Result := Nil;
  If Ext = '' Then
    Exit;
  If ExtIs(Ext, ['.pas', '.pp', '.inc', '.lpr', '.dpr', '.dpk', '.lpk', '.lrs', '.fpd']) Then
    Result := TSynPasSyn.Create(Nil)
  Else If ExtIs(Ext, ['.lfm', '.dfm', '.fmx']) Then
    Result := TSynLFMSyn.Create(Nil)
  Else If ExtIs(Ext, ['.xml', '.xsd', '.xsl', '.xslt', '.dtd', '.lpi', '.lps', '.xlf', '.wsdl', '.svg']) Then
    Result := TSynXMLSyn.Create(Nil)
  Else If Ext = '.sql' Then
    Result := TSynSQLSyn.Create(Nil)
  Else If ExtIs(Ext, ['.json', '.jsonc', '.jsonl', '.geojson', '.json5']) Then
    Begin
      Result := TryIDEHighlighter(Ext);
      If Not Assigned(Result) Then
        Result := TRepositoryJSONHighlighter.Create(Nil);
    End
  Else
    Result := TryIDEHighlighter(Ext);
End;

Function CreateRepositoryLanguageHighlighter(Const SourceFileName: String): TLazEditCustomHighlighter;
Var
  Ext: String;
  HL: TLazEditCustomHighlighter;
Begin
  Result := Nil;
  Ext := NormalizeExt(ExtractFileExt(SourceFileName));
  If Ext = '' Then
    Exit;
  HL := Nil;
  Try
    HL := HighlighterForExt(Ext);
    If Not Assigned(HL) Then
      Exit;
    If HL Is TRepositoryJSONHighlighter Then
      ApplyJSONScheme(HL)
    Else
      ApplyIDESettings(HL);
  Except
    FreeAndNil(HL);
  End;
  Result := HL;
End;

Constructor TRepositoryJSONHighlighter.Create(AOwner: TComponent);
Begin
  Inherited Create(AOwner);
  RangeState := jrNone;
  TokenID := jtNone;
  StringAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrString, SYNS_XML_AttrString);
  StringAttri.Foreground := clBlue;
  AddAttribute(StringAttri);
  KeyAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrReservedWord, SYNS_XML_AttrReservedWord);
  KeyAttri.Foreground := clNavy;
  KeyAttri.Style := [fsBold];
  AddAttribute(KeyAttri);
  LiteralAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrNonReservedKeyword, SYNS_XML_AttrNonReservedKeyword);
  LiteralAttri.Foreground := clNavy;
  AddAttribute(LiteralAttri);
  NumberAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrNumber, SYNS_XML_AttrNumber);
  NumberAttri.Foreground := clTeal;
  AddAttribute(NumberAttri);
  SymbolAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrSymbol, SYNS_XML_AttrSymbol);
  SymbolAttri.Foreground := clMaroon;
  AddAttribute(SymbolAttri);
  BracketAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrBrackets, SYNS_XML_AttrBrackets);
  BracketAttri.Style := [fsBold];
  AddAttribute(BracketAttri);
  CommentAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrComment, SYNS_XML_AttrComment);
  CommentAttri.Foreground := clGreen;
  CommentAttri.Style := [fsItalic];
  AddAttribute(CommentAttri);
  SpaceAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrSpace, SYNS_XML_AttrSpace);
  AddAttribute(SpaceAttri);
  UnknownAttri := TLazEditHighlighterAttributes.Create(@SYNS_AttrIdentifier, SYNS_XML_AttrIdentifier);
  AddAttribute(UnknownAttri);
  SetAttributesOnChange(@DefHighlightChange);
End;

Class Function TRepositoryJSONHighlighter.GetLanguageName: String;
Begin
  Result := 'JSON';
End;

Function TRepositoryJSONHighlighter.TokenEquals(Const Expected: String): Boolean;
Var
  I: Integer;
Begin
  Result := ScanPos - TokenPos = Length(Expected);
  If Not Result Then
    Exit;
  For I := 1 To Length(Expected) Do
    If LinePtr[TokenPos + I - 1] <> Expected[I] Then
      Exit(False);
End;

Function TRepositoryJSONHighlighter.PeekColon: Boolean;
Var
  I: Integer;
Begin
  I := ScanPos;
  While LinePtr[I] In [#9, ' '] Do
    Inc(I);
  Result := LinePtr[I] = ':';
End;

Procedure TRepositoryJSONHighlighter.ScanSpace;
Begin
  TokenID := jtSpace;
  Inc(ScanPos);
  While LinePtr[ScanPos] In [#1..#9, #11, #12, #14..#32] Do
    Inc(ScanPos);
End;

Procedure TRepositoryJSONHighlighter.ScanString(Const Opening: Boolean);
Begin
  If Opening Then
    Inc(ScanPos);
  While LinePtr[ScanPos] <> #0 Do
    Begin
      If LinePtr[ScanPos] = '\' Then
        Begin
          Inc(ScanPos);
          If LinePtr[ScanPos] <> #0 Then
            Inc(ScanPos);
        End
      Else If LinePtr[ScanPos] = '"' Then
        Begin
          Inc(ScanPos);
          RangeState := jrNone;
          If PeekColon Then
            TokenID := jtKey
          Else
            TokenID := jtString;
          Exit;
        End
      Else
        Inc(ScanPos);
    End;
  RangeState := jrString;
  TokenID := jtString;
End;

Procedure TRepositoryJSONHighlighter.ScanNumber;
Begin
  TokenID := jtNumber;
  If LinePtr[ScanPos] = '-' Then
    Begin
      If Not (LinePtr[ScanPos + 1] In ['0'..'9']) Then
        Begin
          TokenID := jtSymbol;
          Inc(ScanPos);
          Exit;
        End;
      Inc(ScanPos);
    End;
  While LinePtr[ScanPos] In ['0'..'9'] Do
    Inc(ScanPos);
  If (LinePtr[ScanPos] = '.') And (LinePtr[ScanPos + 1] In ['0'..'9']) Then
    Begin
      Inc(ScanPos);
      While LinePtr[ScanPos] In ['0'..'9'] Do
        Inc(ScanPos);
    End;
  If LinePtr[ScanPos] In ['e', 'E'] Then
    Begin
      Inc(ScanPos);
      If LinePtr[ScanPos] In ['+', '-'] Then
        Inc(ScanPos);
      While LinePtr[ScanPos] In ['0'..'9'] Do
        Inc(ScanPos);
    End;
End;

Procedure TRepositoryJSONHighlighter.ScanWord;
Begin
  While LinePtr[ScanPos] In ['A'..'Z', 'a'..'z', '0'..'9', '_'] Do
    Inc(ScanPos);
  If TokenEquals('true') Or TokenEquals('false') Or TokenEquals('null') Then
    TokenID := jtLiteral
  Else
    TokenID := jtUnknown;
End;

Procedure TRepositoryJSONHighlighter.ScanBlockComment(Const Opening: Boolean);
Begin
  TokenID := jtComment;
  If Opening Then
    Inc(ScanPos, 2);
  While LinePtr[ScanPos] <> #0 Do
    Begin
      If (LinePtr[ScanPos] = '*') And (LinePtr[ScanPos + 1] = '/') Then
        Begin
          Inc(ScanPos, 2);
          RangeState := jrNone;
          Exit;
        End;
      Inc(ScanPos);
    End;
  RangeState := jrBlockComment;
End;

Procedure TRepositoryJSONHighlighter.ScanSlash;
Begin
  If LinePtr[ScanPos + 1] = '/' Then
    Begin
      TokenID := jtComment;
      While LinePtr[ScanPos] <> #0 Do
        Inc(ScanPos);
      RangeState := jrNone;
    End
  Else If LinePtr[ScanPos + 1] = '*' Then
    ScanBlockComment(True)
  Else
    Begin
      TokenID := jtSymbol;
      Inc(ScanPos);
    End;
End;

Procedure TRepositoryJSONHighlighter.ScanUnknown;
Begin
  TokenID := jtUnknown;
  If Byte(LinePtr[ScanPos]) >= 128 Then
    Begin
      Inc(ScanPos);
      While (Byte(LinePtr[ScanPos]) And $C0) = $80 Do
        Inc(ScanPos);
    End
  Else
    Inc(ScanPos);
End;

Procedure TRepositoryJSONHighlighter.InitForScanningLine;
Begin
  Inherited InitForScanningLine;
  ScanPos := 0;
  Next;
End;

Procedure TRepositoryJSONHighlighter.Next;
Begin
  TokenPos := ScanPos;
  If LinePtr[ScanPos] = #0 Then
    Begin
      TokenID := jtNone;
      Exit;
    End;
  Case RangeState Of
    jrString: ScanString(False);
    jrBlockComment: ScanBlockComment(False);
  Else
    Case LinePtr[ScanPos] Of
      #1..#32: ScanSpace;
      '"': ScanString(True);
      '{', '}', '[', ']':
        Begin
          TokenID := jtBracket;
          Inc(ScanPos);
        End;
      ',', ':', '+':
        Begin
          TokenID := jtSymbol;
          Inc(ScanPos);
        End;
      '-', '0'..'9': ScanNumber;
      'A'..'Z', 'a'..'z', '_': ScanWord;
      '/': ScanSlash;
    Else
      ScanUnknown;
    End;
  End;
End;

Function TRepositoryJSONHighlighter.GetEol: Boolean;
Begin
  Result := TokenID = jtNone;
End;

Function TRepositoryJSONHighlighter.GetToken: String;
Begin
  SetString(Result, LinePtr + TokenPos, ScanPos - TokenPos);
End;

Function TRepositoryJSONHighlighter.GetTokenPos: Integer;
Begin
  Result := TokenPos;
End;

Function TRepositoryJSONHighlighter.GetTokenKind: Integer;
Begin
  Result := Ord(TokenID);
End;

Procedure TRepositoryJSONHighlighter.GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer);
Begin
  TokenLength := ScanPos - TokenPos;
  TokenStart := LinePtr + TokenPos;
End;

Function TRepositoryJSONHighlighter.GetTokenAttribute: TLazEditTextAttribute;
Begin
  Case TokenID Of
    jtString: Result := StringAttri;
    jtKey: Result := KeyAttri;
    jtNumber: Result := NumberAttri;
    jtLiteral: Result := LiteralAttri;
    jtSymbol: Result := SymbolAttri;
    jtBracket: Result := BracketAttri;
    jtComment: Result := CommentAttri;
    jtSpace: Result := SpaceAttri;
    jtUnknown: Result := UnknownAttri;
  Else
    Result := Nil;
  End;
End;

Function TRepositoryJSONHighlighter.GetTokenClass: TLazEditTokenClass;
Begin
  Case TokenID Of
    jtSpace: Result := tcWhiteSpace;
    jtString: Result := tcString;
    jtKey, jtLiteral: Result := tcKeyword;
    jtNumber: Result := tcNumber;
    jtSymbol, jtBracket: Result := tcSymbol;
    jtComment: Result := tcComment;
  Else
    Result := tcUnknown;
  End;
End;

{$PUSH}{$HINTS OFF}
Function TRepositoryJSONHighlighter.GetRange: Pointer;
Begin
  { SynEdit stores the scan range as an untyped pointer. The value is an enum, not an object. }
  Result := Pointer(PtrUInt(RangeState));
End;

Procedure TRepositoryJSONHighlighter.SetRange(Value: Pointer);
Begin
  RangeState := TJSONRange(PtrUInt(Value));
End;
{$POP}

Procedure TRepositoryJSONHighlighter.ResetRange;
Begin
  RangeState := jrNone;
End;

End.
