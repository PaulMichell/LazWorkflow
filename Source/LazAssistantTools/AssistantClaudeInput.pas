Unit AssistantClaudeInput;

{ Pictures sent with a Claude Code turn (c) 2026 Michell Computing.

  A turn with attached pictures goes to claude -p --input-format stream-json as one user message: the text block,
  then one base64 image block per picture. That is the shape recorded in Tests/Fixtures/Claude/image-input.jsonl.
  The pictures are the store's upload copies, already within its 2048-pixel and 4 MiB ceilings. A turn without
  pictures keeps the plain-text prompt. Picture data is never logged. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Type
  { One picture for a user message: an API media type and its base64 data. }
  TClaudeImage = Record
    MediaType: String;
    Data: String;
  End;
  TClaudeImageArray = Array Of TClaudeImage;

Const
  { The media types the Claude API accepts in an image block. }
  ClaudeImageMediaTypes = 'image/jpeg,image/png,image/gif,image/webp';

/// One stream-json user message line, ending in a line feed: a text block, then one image block per picture.
Function ClaudeUserMessageLine(Const Text: String; Const Images: TClaudeImageArray): String;
/// The upload copy of each stored ref in RefsJson, at most AssistantImageMaxAttachments. An empty list gives no
/// pictures. False, with ErrorText starting AssistantImageSendFailedPrefix, when the list is invalid or a picture
/// cannot be read or has a type the API does not accept.
Function ClaudeImagesFromRefs(Const ProjectRoot, RefsJson: String; Out Images: TClaudeImageArray;
  Out ErrorText: String): Boolean;

Implementation

Uses
  SysUtils, fpjson, AssistantImages;

Function ClaudeUserMessageLine(Const Text: String; Const Images: TClaudeImageArray): String;
Var
  Root: TJSONObject;
  Content: TJSONArray;
  I: Integer;
Begin
  Content := TJSONArray.Create;
  Try
    Content.Add(TJSONObject.Create(['type', 'text', 'text', Text]));
    For I := 0 To High(Images) Do
      Content.Add(TJSONObject.Create(['type', 'image', 'source',
        TJSONObject.Create(['type', 'base64', 'media_type', Images[I].MediaType, 'data', Images[I].Data])]));
  Except
    Content.Free;
    Raise;
  End;
  { Root owns Content from here. }
  Root := TJSONObject.Create(['type', 'user', 'message', TJSONObject.Create(['role', 'user', 'content', Content])]);
  Try
    Result := Root.AsJSON + #10;
  Finally
    Root.Free;
  End;
End;

Function ClaudeImagesFromRefs(Const ProjectRoot, RefsJson: String; Out Images: TClaudeImageArray;
  Out ErrorText: String): Boolean;
Var
  Refs: TAssistantImageRefArray;
  I, Comma, Semicolon: Integer;
  DataUri, MediaType: String;
Begin
  Result := False;
  SetLength(Images, 0);
  ErrorText := '';
  SetLength(Refs, 0);
  If (Trim(RefsJson) = '') Or (Trim(RefsJson) = '[]') Then
    Exit(True);
  If Not ParseAssistantImageRefs(RefsJson, Refs) Then
    Begin
      ErrorText := AssistantImageSendFailedPrefix + ' Attachment list is invalid.';
      Exit;
    End;
  Refs := LimitAssistantImageRefs(Refs);
  SetLength(Images, Length(Refs));
  For I := 0 To High(Refs) Do
    Begin
      { data:<media type>;base64,<data> }
      If AssistantImageDataUri(ProjectRoot, Refs[I], DataUri, ErrorText) Then
        Begin
          Comma := Pos(',', DataUri);
          Semicolon := Pos(';', DataUri);
          MediaType := LowerCase(Copy(DataUri, 6, Semicolon - 6));
          If (Semicolon < 7) Or (Comma < Semicolon) Then
            ErrorText := 'Image could not be prepared for upload.'
          Else If Pos(',' + MediaType + ',', ',' + ClaudeImageMediaTypes + ',') = 0 Then
            ErrorText := 'Claude does not accept ' + MediaType + ' pictures.'
          Else
            Begin
              Images[I].MediaType := MediaType;
              Images[I].Data := Copy(DataUri, Comma + 1, MaxInt);
            End;
        End
      Else If ErrorText = '' Then
        ErrorText := 'Stored image is missing.';
      DataUri := '';
      If ErrorText <> '' Then
        Begin
          SetLength(Images, 0);
          ErrorText := AssistantImageSendFailedPrefix + ' ' + ErrorText;
          Exit;
        End;
    End;
  Result := True;
End;

End.
