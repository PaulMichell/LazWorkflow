Unit AssistantGeneratedImage;

{ Provider-neutral generated image. Adapters fill this record. The writer,
  path checks, and tool result use only these fields.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  AssistantImageAdapterResponses = 'responses';
  AssistantImageAdapterImages = 'images';
  AssistantImageAdapterChat = 'chat-completions';

Type
  { Pixels from one provider response. No vendor field and no file path. }
  TAssistantGeneratedImage = Record
    Id: String;
    Mime: String;
    Width: Integer;
    Height: Integer;
    Bytes: TBytes;
  End;
  TAssistantGeneratedImageArray = Array Of TAssistantGeneratedImage;

  IAssistantGeneratedImageAdapter = Interface
    ['{8F4C2A91-6B17-4E5D-A3C8-1D9E7B04C6A2}']
    Function AdapterId: String;
    /// Fill images from this adapter's response body. Does not write a file.
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

Procedure ClearGeneratedImage(Out Image: TAssistantGeneratedImage);
Procedure RegisterGeneratedImageAdapter(Const Adapter: IAssistantGeneratedImageAdapter);
Function FindGeneratedImageAdapter(Const AdapterId: String): IAssistantGeneratedImageAdapter;
/// Adapter id for a profile. Delivery chooses the response shape, not a model id.
Function ProfileImageAdapterId(Const Backend, Delivery: String): String;
Function CollectGeneratedImages(Const AdapterId, ResponseJson: String;
  Out Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
/// True when the record has an id, sniffed still-image bytes, and matching size.
Function GeneratedImageBytesAccepted(Const Image: TAssistantGeneratedImage; Out ErrorText: String): Boolean;
/// Tool result. Path is the writer's project-relative path. No provider field is read.
Function GeneratedImageResultText(Const RelativePath: String; Const Image: TAssistantGeneratedImage): String;
Implementation

Uses
  AssistantConnections, AssistantImages;

Var
  RegisteredAdapters: Array Of IAssistantGeneratedImageAdapter;

Procedure ClearGeneratedImage(Out Image: TAssistantGeneratedImage);
Begin
  Image.Id := '';
  Image.Mime := '';
  Image.Width := 0;
  Image.Height := 0;
  SetLength(Image.Bytes, 0);
End;

Procedure RegisterGeneratedImageAdapter(Const Adapter: IAssistantGeneratedImageAdapter);
Var
  Count: Integer;
Begin
  If Not Assigned(Adapter) Or (Adapter.AdapterId = '') Then
    Exit;
  If Assigned(FindGeneratedImageAdapter(Adapter.AdapterId)) Then
    Exit;
  Count := Length(RegisteredAdapters);
  SetLength(RegisteredAdapters, Count + 1);
  RegisteredAdapters[Count] := Adapter;
End;

Function FindGeneratedImageAdapter(Const AdapterId: String): IAssistantGeneratedImageAdapter;
Var
  I: Integer;
Begin
  Result := Nil;
  For I := 0 To High(RegisteredAdapters) Do
    If SameText(RegisteredAdapters[I].AdapterId, AdapterId) Then
      Exit(RegisteredAdapters[I]);
End;

Function ProfileImageAdapterId(Const Backend, Delivery: String): String;
Begin
  If Delivery = AssistantImageDeliveryToolPrompt Then
    Begin
      If (Backend = 'grok') Or (Backend = 'openai-compatible') Then
        Result := AssistantImageAdapterImages
      Else If Backend = '' Then
        Result := ''
      Else
        Result := Backend + '-images';
    End
  Else If Backend = 'openai-compatible' Then
    Result := AssistantImageAdapterChat
  Else If Backend = 'grok' Then
    Result := AssistantImageAdapterResponses
  Else
    Result := Backend;
End;

Function CollectGeneratedImages(Const AdapterId, ResponseJson: String;
  Out Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
Var
  Adapter: IAssistantGeneratedImageAdapter;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Adapter := FindGeneratedImageAdapter(AdapterId);
  If Not Assigned(Adapter) Then
    Begin
      ErrorText := 'No generated-image adapter is registered for this profile.';
      Exit(False);
    End;
  Result := Adapter.Collect(ResponseJson, Images, ErrorText);
End;

Function GeneratedImageBytesAccepted(Const Image: TAssistantGeneratedImage; Out ErrorText: String): Boolean;
Var
  Mime: String;
  Width, Height: Integer;
Begin
  ErrorText := '';
  Result := False;
  If Image.Id = '' Then
    Begin
      ErrorText := 'Generated image has no turn-local id.';
      Exit;
    End;
  If Length(Image.Bytes) = 0 Then
    Begin
      ErrorText := 'Generated image has no bytes.';
      Exit;
    End;
  If Length(Image.Bytes) > AssistantImageMaxFileBytes Then
    Begin
      ErrorText := 'Generated image is over the size ceiling.';
      Exit;
    End;
  If Not MeasureStillImage(Image.Bytes, Mime, Width, Height) Then
    Begin
      ErrorText := 'Generated image bytes are not a still image.';
      Exit;
    End;
  If (Image.Mime <> Mime) Or (Image.Width <> Width) Or (Image.Height <> Height) Then
    Begin
      ErrorText := 'Generated image record does not match its bytes.';
      Exit;
    End;
  Result := True;
End;

Function GeneratedImageResultText(Const RelativePath: String; Const Image: TAssistantGeneratedImage): String;
Begin
  { The Wrote line is the success signal, same role as write_file's Wrote line. }
  Result := 'Wrote ' + RelativePath + ' (' + IntToStr(Length(Image.Bytes)) + ' bytes).' + LineEnding +
    'path=' + RelativePath + LineEnding +
    'bytes=' + IntToStr(Length(Image.Bytes)) + LineEnding +
    'width=' + IntToStr(Image.Width) + LineEnding +
    'height=' + IntToStr(Image.Height) + LineEnding +
    'mime=' + Image.Mime + LineEnding +
    'id=' + Image.Id;
End;

Finalization

  SetLength(RegisteredAdapters, 0);

End.
