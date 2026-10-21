Unit AssistantCodexSchema;

{ Bounded draft-07 contract checks for the app-server wire adapter. References
  stay in the generated document; unknown constraints fail closed. This is not
  a general schema service and never fetches a remote reference.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson;

  /// Outgoing values require declared properties and all required fields.
  /// Incoming samples check only the fields this adapter reads; extra fields are allowed.
Function CodexSchemaAccepts(Document, Schema, Value: TJSONData; Outgoing: Boolean; Out ErrorText: String): Boolean;
/// Exact split-file or named bundle lookup. Caller owns Document; Schema belongs to it.
Function ReadCodexSchema(Const Directory, RelativeName: String; Out Document, Schema: TJSONData;
    Out ErrorText: String): Boolean;

Implementation

Uses
  jsonparser, LazFileUtils, LazUTF8, RegExpr;

Const
  CompositionNames: Array[0..2] Of String = ('allOf', 'anyOf', 'oneOf');

Function PointerNode(Document: TJSONData; Const Reference: String): TJSONData;
Var
  Rest, Part: String;
  At: Integer;
Begin
  Result := Nil;
  If Reference = '#' Then Exit(Document);
  If Copy(Reference, 1, 2) <> '#/' Then Exit;
  Result := Document;
  Rest := Copy(Reference, 3, MaxInt);
  While Rest <> '' Do
    Begin
      At := Pos('/', Rest);
      If At = 0 Then At := Length(Rest) + 1;
      Part := Copy(Rest, 1, At - 1);
      Delete(Rest, 1, At);
      Part := StringReplace(Part, '~1', '/', [rfReplaceAll]);
      Part := StringReplace(Part, '~0', '~', [rfReplaceAll]);
      If Not (Result Is TJSONObject) Then Exit(Nil);
      Result := TJSONObject(Result).Find(Part);
    End;
End;

Function TypeMatches(Value: TJSONData; Const Name: String): Boolean;
Begin
  Case Name Of
    'null': Result := Value.JSONType = jtNull;
    'boolean': Result := Value.JSONType = jtBoolean;
    'string': Result := Value.JSONType = jtString;
    'object': Result := Value Is TJSONObject;
    'array': Result := Value Is TJSONArray;
    'number': Result := Value.JSONType = jtNumber;
    'integer': Result := (Value.JSONType = jtNumber) And (Frac(Value.AsFloat) = 0);
  Else
    Result := False;
  End;
End;

Function CodexSchemaAccepts(Document, Schema, Value: TJSONData; Outgoing: Boolean; Out ErrorText: String): Boolean;
Var
  Visits: Integer;
  Function Check(Node, Data: TJSONData; Depth: Integer; Const Path: String): Boolean;
  Var
    Obj, Props: TJSONObject;
    Part, Child, Types, Required: TJSONData;
    I, J, Matches: Integer;
    Name, SavedError: String;
    Matched: Boolean;
    Expression: TRegExpr;
    Function Reject(Const Reason: String): Boolean;
    Begin
      ErrorText := Path + ': ' + Reason;
      Result := False;
    End;
  Begin
    Result := False;
    Inc(Visits);
    If (Depth > 64) Or (Visits > 50000) Then Exit(Reject('schema complexity limit'));
    If Not Assigned(Node) Or Not Assigned(Data) Then Exit(Reject('missing schema or value'));
    If Node.JSONType = jtBoolean Then
      Begin
        If Node.AsBoolean Then Exit(True);
        Exit(Reject('value is forbidden'));
      End;
    If Not (Node Is TJSONObject) Then Exit(Reject('invalid schema object'));
    Obj := TJSONObject(Node);
    For I := 0 To Obj.Count - 1 Do
      Begin
        Name := Obj.Names[I];
        Case Name Of
          '$schema', '$id', '$ref', '$defs', 'definitions', 'title', 'description',
          'default', 'examples', 'deprecated', 'readOnly', 'writeOnly', 'format', 'type', 'enum', 'const',
          'properties', 'required', 'additionalProperties', 'items', 'allOf', 'anyOf', 'oneOf',
          'minimum', 'maximum', 'minLength', 'maxLength', 'minItems', 'maxItems', 'pattern':;
        Else
          Exit(Reject('unsupported constraint ' + Name));
        End;
      End;
    Part := Obj.Find('$ref');
    If Assigned(Part) Then
      Begin
        If Part.JSONType <> jtString Then Exit(Reject('invalid reference'));
        Child := PointerNode(Document, Part.AsString);
        If Not Assigned(Child) Then Exit(Reject('unresolved local reference'));
        { Draft-07 ignores siblings of $ref. }
        Exit(Check(Child, Data, Depth + 1, Path));
      End;
    For Name In CompositionNames Do
      Begin
        Part := Obj.Find(Name);
        If Not Assigned(Part) Then Continue;
        If Not (Part Is TJSONArray) Or (Part.Count = 0) Then Exit(Reject('invalid ' + Name));
        Matches := 0;
        SavedError := ErrorText;
        For I := 0 To Part.Count - 1 Do
          If Check(Part.Items[I], Data, Depth + 1, Path) Then Inc(Matches);
        If ((Name = 'allOf') And (Matches <> Part.Count)) Or
          ((Name = 'anyOf') And (Matches = 0)) Or ((Name = 'oneOf') And (Matches <> 1)) Then
            Exit(Reject('no matching ' + Name + ' contract'));
        ErrorText := SavedError;
      End;
    Types := Obj.Find('type');
    If Assigned(Types) Then
      Begin
        Matched := False;
        If Types.JSONType = jtString Then Matched := TypeMatches(Data, Types.AsString)
        Else If Types Is TJSONArray Then
          For I := 0 To Types.Count - 1 Do
            If (Types.Items[I].JSONType = jtString) And TypeMatches(Data, Types.Items[I].AsString) Then Matched := True;
          If Not Matched Then Exit(Reject('wrong type'));
      End;
    Part := Obj.Find('enum');
    If Assigned(Part) Then
      Begin
        If Not (Part Is TJSONArray) Then Exit(Reject('invalid enum'));
        Matched := False;
        For I := 0 To Part.Count - 1 Do
          If Part.Items[I].AsJSON = Data.AsJSON Then Matched := True;
        If Not Matched Then Exit(Reject('unsupported enum value'));
      End;
    Part := Obj.Find('const');
    If Assigned(Part) And (Part.AsJSON <> Data.AsJSON) Then Exit(Reject('wrong constant'));
    If Data Is TJSONObject Then
      Begin
        Props := Nil;
        Part := Obj.Find('properties');
        If Assigned(Part) Then
          Begin
            If Not (Part Is TJSONObject) Then Exit(Reject('invalid properties'));
            Props := TJSONObject(Part);
          End;
        If (Path = '$') And Not Assigned(Props) And Not Assigned(Obj.Find('oneOf')) And
          Not Assigned(Obj.Find('anyOf')) And Not Assigned(Obj.Find('allOf')) Then
            Exit(Reject('message properties are not described'));
        Required := Obj.Find('required');
        If Assigned(Required) And Outgoing Then
          Begin
            If Not (Required Is TJSONArray) Then Exit(Reject('invalid required fields'));
            For I := 0 To Required.Count - 1 Do
              If Not Assigned(TJSONObject(Data).Find(Required.Items[I].AsString)) Then
                Exit(Reject('missing required field ' + Required.Items[I].AsString));
          End;
        For I := 0 To Data.Count - 1 Do
          Begin
            Name := TJSONObject(Data).Names[I];
            Child := Nil;
            If Assigned(Props) Then Child := Props.Find(Name);
            If Assigned(Child) Then
              Begin
                If Not Check(Child, Data.Items[I], Depth + 1, Path + '.' + Name) Then Exit;
              End
                Else
                  Begin
                    Part := Obj.Find('additionalProperties');
                    If Assigned(Part) Then
                      Begin
                        If Not Check(Part, Data.Items[I], Depth + 1, Path + '.' + Name) Then Exit;
                      End
                        Else If Assigned(Props) Then Exit(Reject('undeclared field ' + Name));
                  End;
          End;
      End;
    If Data Is TJSONArray Then
      Begin
        Part := Obj.Find('items');
        If Assigned(Part) Then
          For I := 0 To Data.Count - 1 Do
            If Not Check(Part, Data.Items[I], Depth + 1, Path + '[' + IntToStr(I) + ']') Then Exit;
          Part := Obj.Find('minItems');
        If Assigned(Part) And (Data.Count < Part.AsInteger) Then Exit(Reject('too few items'));
        Part := Obj.Find('maxItems');
        If Assigned(Part) And (Data.Count > Part.AsInteger) Then Exit(Reject('too many items'));
      End;
    If Data.JSONType = jtString Then
      Begin
        J := UTF8Length(Data.AsString);
        Part := Obj.Find('minLength');
        If Assigned(Part) And (J < Part.AsInteger) Then Exit(Reject('string too short'));
        Part := Obj.Find('maxLength');
        If Assigned(Part) And (J > Part.AsInteger) Then Exit(Reject('string too long'));
        Part := Obj.Find('pattern');
        If Assigned(Part) Then
          Begin
            Expression := TRegExpr.Create;
            Try
              Expression.Expression := Part.AsString;
              If Not Expression.Exec(Data.AsString) Then Exit(Reject('string pattern mismatch'));
            Finally
              Expression.Free;
            End;
          End;
      End;
    If Data.JSONType = jtNumber Then
      Begin
        Part := Obj.Find('minimum');
        If Assigned(Part) And (Data.AsFloat < Part.AsFloat) Then Exit(Reject('below minimum'));
        Part := Obj.Find('maximum');
        If Assigned(Part) And (Data.AsFloat > Part.AsFloat) Then Exit(Reject('above maximum'));
      End;
    Result := True;
  End;
Begin
  Visits := 0;
  ErrorText := '';
  Try
    Result := Check(Schema, Value, 0, '$');
  Except
    Result := False;
    ErrorText := 'Invalid or unsupported schema constraint.';
  End;
End;

Function ReadCodexSchema(Const Directory, RelativeName: String; Out Document, Schema: TJSONData;
    Out ErrorText: String): Boolean;
Var
  Path, Name: String;
  Stream: TFileStream;
  Body: String;
Begin
  Result := False;
  Document := Nil;
  Schema := Nil;
  ErrorText := 'Missing schema ' + RelativeName + '.';
  Path := IncludeTrailingPathDelimiter(Directory) + RelativeName;
  Name := '';
  If Not FileExists(Path) Then
    Begin
      Name := ChangeFileExt(ExtractFileName(RelativeName), '');
      If Copy(RelativeName, 1, 3) = 'v2/' Then
        Path := IncludeTrailingPathDelimiter(Directory) + 'codex_app_server_protocol.v2.schemas.json'
      Else Path := IncludeTrailingPathDelimiter(Directory) + 'codex_app_server_protocol.schemas.json';
    End;
  If Not FileExists(Path) Or FileIsSymlink(Path) Then Exit;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
    Try
      If Stream.Size > 8 * 1024 * 1024 Then Exit;
      SetLength(Body, Stream.Size);
      If Body <> '' Then Stream.ReadBuffer(Body[1], Length(Body));
    Finally
      Stream.Free;
    End;
    Document := GetJSON(Body);
    If Name = '' Then Schema := Document
    Else Schema := PointerNode(Document, '#/definitions/' + Name);
    Result := Assigned(Schema);
    If Result Then ErrorText := '';
  Except
    ErrorText := 'Invalid schema ' + RelativeName + '.';
  End;
  If Not Result Then FreeAndNil(Document);
End;

End.
