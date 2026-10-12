Unit AssistantImageAdapters;

{ Fills the generated-image record from each response shape. The writer does
  not use this unit. A new shape is a new adapter, not a new tool.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantGeneratedImage;

Procedure RegisterBuiltinImageAdapters;

Implementation

Uses
  base64, fpjson, jsonparser, AssistantImages;

Type
  TResponsesImageAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

  TImagesEndpointAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

  TChatCompletionsImageAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

Function StripWhitespace(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To Length(Value) Do
    If Not (Value[I] In [#9, #10, #13, ' ']) Then
      Result := Result + Value[I];
End;

Function PadBase64(Const Value: String): String;
Begin
  Result := StripWhitespace(Value);
  While (Result <> '') And (Length(Result) Mod 4 <> 0) Do
    Result := Result + '=';
End;

Function PayloadText(Const Encoded: String): String;
Var
  Marker, CommaAt: Integer;
  Lowered: String;
Begin
  Result := Trim(Encoded);
  Lowered := LowerCase(Result);
  Marker := Pos('base64,', Lowered);
  If Marker > 0 Then
    Result := Copy(Result, Marker + Length('base64,'), MaxInt)
  Else If Pos('data:', Lowered) = 1 Then
    Begin
      CommaAt := Pos(',', Result);
      If CommaAt > 0 Then
        Result := Copy(Result, CommaAt + 1, MaxInt);
    End;
End;

Function DecodeImagePayload(Const Encoded: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Raw: AnsiString;
  I: Integer;
Begin
  SetLength(Data, 0);
  ErrorText := '';
  Result := False;
  Raw := '';
  Try
    Raw := DecodeStringBase64(PadBase64(PayloadText(Encoded)));
  Except
    On E: Exception Do
      Begin
        ErrorText := 'Generated image bytes could not be decoded.';
        Exit;
      End;
  End;
  If Raw = '' Then
    Begin
      ErrorText := 'Generated image bytes could not be decoded.';
      Exit;
    End;
  If Length(Raw) > AssistantImageMaxFileBytes Then
    Begin
      ErrorText := 'Generated image is over the size ceiling.';
      Exit;
    End;
  SetLength(Data, Length(Raw));
  For I := 1 To Length(Raw) Do
    Data[I - 1] := Byte(Raw[I]);
  Result := True;
End;

Function TurnLocalId(Const Candidate: String; Index: Integer): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := Trim(Candidate);
  If (Result = '') Or (Length(Result) > 80) Then
    Exit('img-' + IntToStr(Index));
  For I := 1 To Length(Result) Do
    Begin
      C := Result[I];
      If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.']) Then
        Exit('img-' + IntToStr(Index));
    End;
End;

Function AppendDecoded(Const Id, Encoded: String; Index: Integer;
  Var Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
Var
  Image: TAssistantGeneratedImage;
  Data: TBytes;
Begin
  ClearGeneratedImage(Image);
  SetLength(Data, 0);
  Result := DecodeImagePayload(Encoded, Data, ErrorText);
  If Not Result Then
    Exit;
  If Not MeasureStillImage(Data, Image.Mime, Image.Width, Image.Height) Then
    Begin
      ErrorText := 'Generated image bytes are not a still image.';
      Exit(False);
    End;
  Image.Id := TurnLocalId(Id, Index);
  Image.Bytes := Data;
  SetLength(Images, Length(Images) + 1);
  Images[High(Images)] := Image;
  Result := True;
End;

Function OutputArray(Root: TJSONObject): TJSONArray;
Var
  Node: TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Root) Then
    Exit;
  Node := Root.Find('output');
  If Node Is TJSONArray Then
    Exit(TJSONArray(Node));
  If Root.Find('type') <> Nil Then
    Begin
      Result := TJSONArray.Create;
      Result.Add(Root.Clone);
    End;
End;

Function TResponsesImageAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterResponses;
End;

Function TResponsesImageAdapter.Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I, NextIndex: Integer;
  OwnedArray: Boolean;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Arr := Nil;
  OwnedArray := False;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    Arr := OutputArray(Root);
    OwnedArray := Assigned(Arr) And (Root.Find('output') = Nil);
    If Not Assigned(Arr) Then
      Exit(True);
    NextIndex := 1;
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(Arr.Items[I]);
        If Item.Get('type', '') <> 'image_generation_call' Then
          Continue;
        If Item.Get('result', '') = '' Then
          Begin
            ErrorText := 'Generated image response has no bytes.';
            SetLength(Images, 0);
            Exit(False);
          End;
        If Not AppendDecoded(Item.Get('id', ''), Item.Get('result', ''), NextIndex, Images, ErrorText) Then
          Begin
            SetLength(Images, 0);
            Exit(False);
          End;
        Inc(NextIndex);
      End;
    Result := True;
  Finally
    If OwnedArray Then
      Arr.Free;
    Data.Free;
  End;
End;

Function TImagesEndpointAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterImages;
End;

Function TImagesEndpointAdapter.Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Encoded: String;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('data') Is TJSONArray) Then
      Exit(True);
    Arr := TJSONArray(Root.Find('data'));
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(Arr.Items[I]);
        Encoded := Item.Get('b64_json', '');
        If Encoded = '' Then
          Begin
            If Item.Get('url', '') <> '' Then
              ErrorText := 'Generated image response has no bytes.'
            Else
              Continue;
            SetLength(Images, 0);
            Exit(False);
          End;
        If Not AppendDecoded(Item.Get('id', ''), Encoded, I + 1, Images, ErrorText) Then
          Begin
            SetLength(Images, 0);
            Exit(False);
          End;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function PartPayload(Part: TJSONObject; Out Encoded, PartId: String; Out NeedsBytes: Boolean): Boolean;
Var
  Source, UrlObj: TJSONObject;
  UrlNode: TJSONData;
Begin
  Encoded := '';
  PartId := Part.Get('id', '');
  NeedsBytes := False;
  Result := False;
  If Part.Get('type', '') = 'image_url' Then
    Begin
      UrlNode := Part.Find('image_url');
      If UrlNode Is TJSONObject Then
        Begin
          UrlObj := TJSONObject(UrlNode);
          Encoded := UrlObj.Get('url', '');
        End
      Else If Assigned(UrlNode) And (UrlNode.JSONType = jtString) Then
        Encoded := UrlNode.AsString;
      NeedsBytes := (Encoded <> '') And (Pos('base64', LowerCase(Encoded)) = 0);
      Result := Pos('base64', LowerCase(Encoded)) > 0;
      Exit;
    End;
  If Part.Get('type', '') <> 'image' Then
    Exit;
  If Not (Part.Find('source') Is TJSONObject) Then
    Exit;
  Source := TJSONObject(Part.Find('source'));
  If Source.Get('type', '') = 'url' Then
    Begin
      NeedsBytes := True;
      Exit;
    End;
  If Source.Get('type', '') <> 'base64' Then
    Exit;
  Encoded := Source.Get('data', '');
  NeedsBytes := Encoded = '';
  Result := Encoded <> '';
End;

Function TChatCompletionsImageAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterChat;
End;

Function TChatCompletionsImageAdapter.Collect(Const ResponseJson: String;
  Out Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Choice, MessageObj, Part: TJSONObject;
  Choices, Content: TJSONArray;
  I, J, NextIndex: Integer;
  Encoded, PartId: String;
  NeedsBytes: Boolean;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('choices') Is TJSONArray) Then
      Exit(True);
    Choices := TJSONArray(Root.Find('choices'));
    NextIndex := 1;
    For I := 0 To Choices.Count - 1 Do
      Begin
        If Not (Choices.Items[I] Is TJSONObject) Then
          Continue;
        Choice := TJSONObject(Choices.Items[I]);
        If Not (Choice.Find('message') Is TJSONObject) Then
          Continue;
        MessageObj := TJSONObject(Choice.Find('message'));
        If Not (MessageObj.Find('content') Is TJSONArray) Then
          Continue;
        Content := TJSONArray(MessageObj.Find('content'));
        For J := 0 To Content.Count - 1 Do
          Begin
            If Not (Content.Items[J] Is TJSONObject) Then
              Continue;
            Part := TJSONObject(Content.Items[J]);
            If Not PartPayload(Part, Encoded, PartId, NeedsBytes) Then
              Begin
                If NeedsBytes Then
                  Begin
                    ErrorText := 'Generated image response has no bytes.';
                    SetLength(Images, 0);
                    Exit(False);
                  End;
                Continue;
              End;
            If Not AppendDecoded(PartId, Encoded, NextIndex, Images, ErrorText) Then
              Begin
                SetLength(Images, 0);
                Exit(False);
              End;
            Inc(NextIndex);
          End;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Procedure RegisterBuiltinImageAdapters;
Begin
  RegisterGeneratedImageAdapter(TResponsesImageAdapter.Create);
  RegisterGeneratedImageAdapter(TImagesEndpointAdapter.Create);
  RegisterGeneratedImageAdapter(TChatCompletionsImageAdapter.Create);
End;

Initialization

RegisterBuiltinImageAdapters;

End.
