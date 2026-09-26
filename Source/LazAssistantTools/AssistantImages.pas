Unit AssistantImages;

{ Still-image store for the project assistant.

  Size note: exceeds the 1000 line preference. Decode, GIF first-frame
  extraction, header sizing, the ICO reader, upload scaling, and store path
  checks are one policy surface; the image plan requires them in this unit
  rather than in the form or service. Reviewed 2026-09-23: header sizing stays
  here so a registered reader cannot bypass the side and pixel ceilings.
  Archive copies stay in this unit with the other path checks. Reviewed 2026-09-23.

  Readers come from the FPImage registry, so a test can register one before
  calling the store. ImageSize is not virtual. A positive size from the concrete
  reader is used; otherwise the still-image header is read. Oversized
  dimensions are refused before LoadFromStream.
  WebP is not linked; it is accepted only when a reader is already registered.
  Pixel bytes and data URIs are never logged. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpimage;

Const
  { Same ceilings as TGitDiffView.TryShowImageFromStream. }
  AssistantImageMaxFileBytes = 8 * 1024 * 1024;
  AssistantImageMaxSide = 16384;
  AssistantImageMaxPixels = 16000000;
  AssistantImageUploadMaxSide = 2048;
  AssistantImageUploadMaxBytes = 4 * 1024 * 1024;
  AssistantImageMaxAttachments = 8;
  AssistantImageContextTokens = 1100;
  AssistantImagesFolderName = 'images';
  AssistantImageLookText = 'Look at the attached image(s).';
  AssistantImageOmittedPrefix = '[Image omitted from model context:';
  AssistantImageSystemSentence =
    'User messages may include images; describe only what is visible; do not invent image contents; do not fetch URLs.';
  { ChatGPT in this client does not send pictures. Not a guessed image field, and not a text note standing in for one. }
  AssistantCodexImageAttachReason =
    'Images are sent on the Grok connection. This ChatGPT runtime cannot see pictures, so Attach is disabled.';
  { Extensions FileExtensionIsImage already names. Acceptance is by stream sniff, not by this list. }
  AssistantStillImageExtensions = '.png,.jpg,.jpeg,.gif,.bmp,.ico,.xpm,.tif,.tiff,.pbm,.pgm,.ppm';

Type
  TAssistantStoredImage = Record
    Id: String;
    OriginalName: String;
    Mime: String;
    Width: Integer;
    Height: Integer;
    DisplayRelativePath: String;
    UploadRelativePath: String;
    UploadMime: String;
    AnimationDiscarded: Boolean;
  End;

  { Reference only. No pixel bytes and no data URI. }
  TAssistantImageRef = Record
    Id: String;
    Name: String;
    Mime: String;
    Width: Integer;
    Height: Integer;
    DisplayPath: String;
    UploadPath: String;
    UploadMime: String;
    AnimationDiscarded: Boolean;
  End;
  TAssistantImageRefArray = Array Of TAssistantImageRef;

Function ImageRefFromStored(Const Stored: TAssistantStoredImage): TAssistantImageRef;
/// JSON array of refs. Empty when there are none. Drops any data URI or oversized string.
Function AssistantImageRefsToJson(Const Refs: TAssistantImageRefArray): String;
/// Missing or empty text is no images. Invalid JSON returns False and an empty list.
Function ParseAssistantImageRefs(Const JsonText: String; Out Refs: TAssistantImageRefArray): Boolean;
/// First file name, or Image when the attachments have no name. Empty when there are no attachments.
Function AssistantImageHistoryPreview(Const AttachmentsJson: String): String;
/// One plain file name per line. Does not emit Markdown image syntax.
Procedure AppendAssistantImageFileNames(Const AttachmentsJson: String; Lines: TStrings);
/// Copy referenced store files beside an archived conversation. A missing source is not an error.
Function PreserveAssistantImages(Const StoreDirectory, ArchiveId, ConversationFile: String; Out ErrorText: String;
  Const FallbackDirectory: String = ''): Boolean;
/// Copy archived files back into the live image directory when Activate finds them missing.
Function RestoreAssistantImages(Const StoreDirectory, ArchiveId, ConversationFile: String; Out ErrorText: String): Boolean;
/// True when every archived copy is present in the live directory, or was never archived.
Function AssistantArchiveImagesRecovered(Const StoreDirectory, ArchiveId, ConversationFile: String): Boolean;
/// Delete one archive image directory. Does not follow a symbolic link.
Function DeleteAssistantImageArchive(Const StoreDirectory, ArchiveId: String; Out ErrorText: String): Boolean;
/// Delete live image files that none of ConversationFiles still names. The list is current plus archives.
Function ReleaseUnreferencedAssistantImages(Const StoreDirectory: String; ConversationFiles: TStrings;
  Out ErrorText: String): Boolean;
/// Delete images-<id> directories whose archive is no longer on disk. Activate leaves those copies behind.
Function ReleaseOrphanAssistantImageArchives(Const StoreDirectory: String; ConversationFiles: TStrings;
  Out ErrorText: String): Boolean;
/// True when the display file is a regular file in the live image directory.
Function AssistantImageDisplayPresent(Const StoreDirectory, ImageId, DisplayPath: String): Boolean;

/// Directory that receives stored images. ProjectRoot is the directory that contains .assistant/conversation.jsonl.
Function AssistantImagesDirectory(Const ProjectRoot: String): String;
/// Copy a still image into the store. The file is not opened when it is over 8 MiB.
Function StoreAssistantImageFromFile(Const ProjectRoot, SourcePath: String; Out Stored: TAssistantStoredImage;
  Out ErrorText: String): Boolean;
/// Copy a still image from a stream. The stream is not read when its remaining size is over 8 MiB.
Function StoreAssistantImageFromStream(Const ProjectRoot, OriginalName: String; Stream: TStream;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
/// Resolve a stored project-relative path. Refuses a symbolic link and any path outside the image directory.
Function ResolveStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out FullPath, ErrorText: String): Boolean;
/// Read a stored image back. Symbolic links are refused before the file is opened.
Function ReadStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out Data: TBytes; Out ErrorText: String): Boolean;
/// Decode a stored display file. The caller frees Img. Symbolic links are refused.
Function LoadStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out Img: TFPMemoryImage;
  Out ErrorText: String): Boolean;
/// data: URI of the upload derivative. Never logged.
Function AssistantImageDataUri(Const ProjectRoot: String; Const Ref: TAssistantImageRef;
  Out DataUri, ErrorText: String): Boolean;
/// [Image omitted from model context: name, WxH]
Function AssistantImageOmittedNote(Const Ref: TAssistantImageRef): String;
/// Model text part. Empty user words with images become the look sentence, which is not the user's words.
Function AssistantImageModelText(Const UserText: String; ImageCount: Integer): String;
/// True when an API error refused the image, not when a local store check failed.
Function AssistantRequestRejectedImage(Const ErrorText: String): Boolean;
/// Delete display and upload files for an unsent attachment. Does not follow a symbolic link.
Function DeleteStoredAssistantImage(Const ProjectRoot: String; Const Ref: TAssistantImageRef;
  Out ErrorText: String): Boolean;
/// Store beside conversation.jsonl. StoreDirectory is that file's directory. Paths stay project-root relative.
Function StoreAssistantImageInStore(Const ProjectRoot, StoreDirectory, SourcePath: String;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
Function StoreAssistantImageStreamInStore(Const ProjectRoot, StoreDirectory, OriginalName: String; Stream: TStream;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
/// Cap a submission. Extra refs are dropped, not stored again.
Function LimitAssistantImageRefs(Const Refs: TAssistantImageRefArray): TAssistantImageRefArray;
/// Same-thread handoff from a tool to the actor. Not for subagents.
Procedure NoteThreadToolImages(Const Refs: TAssistantImageRefArray);
Function TakeThreadToolImages(Out Refs: TAssistantImageRefArray): Boolean;

Implementation

Uses
  Math, LazFileUtils, fpjson, jsonparser, fpreadpng, fpwritepng, fpreadjpeg, fpwritejpeg, fpreadbmp,
  fpreadgif, fpreadtiff, fpreadxpm, fpreadpnm, AssistantProjectPaths{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

Function PathInside(Const Root, Path: String): Boolean; Forward;
Function ImagePathPrefix(Const ProjectRoot, ImageDirectory: String): String; Forward;
Function EnsureStoreImages(Const ProjectRoot, StoreDirectory: String; Out Directory, ErrorText: String): Boolean; Forward;

Type
  TAssistantImageKind = (ikUnknown, ikPng, ikJpeg, ikGif, ikBmp, ikIco, ikXpm, ikTiff, ikPbm, ikPgm, ikPpm, ikWebp,
    ikCustom);
  TIcoEntry = Record
    Offset: Int64;
    BytesInRes: Int64;
    Width: Integer;
    Height: Integer;
    IsPng: Boolean;
    Valid: Boolean;
  End;
  TIcoEntryArray = Array Of TIcoEntry;

  TAssistantIcoReader = Class(TFPCustomImageReader)
  Protected
    Procedure InternalRead(Str: TStream; Img: TFPCustomImage); Override;
    Function InternalCheck(Str: TStream): Boolean; Override;
  Public
    Class Function ImageSize(Str: TStream): TPoint; Reintroduce;
  End;

Const
  JpegQualities: Array[0..5] Of Integer = (85, 70, 55, 40, 25, 12);

Procedure ClearStored(Out Stored: TAssistantStoredImage);
Begin
  Stored.Id := '';
  Stored.OriginalName := '';
  Stored.Mime := '';
  Stored.Width := 0;
  Stored.Height := 0;
  Stored.DisplayRelativePath := '';
  Stored.UploadRelativePath := '';
  Stored.UploadMime := '';
  Stored.AnimationDiscarded := False;
End;

Function ProjectRootDir(Const ProjectRoot: String): String;
Begin
  Result := Trim(ProjectRoot);
  If Result = '' Then Exit;
  Result := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(Result));
End;

Function AssistantImagesDirectory(Const ProjectRoot: String): String;
Var
  Root: String;
Begin
  Root := ProjectRootDir(ProjectRoot);
  If Root = '' Then
    Result := ''
  Else
    Result := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName + PathDelim + AssistantImagesFolderName + PathDelim;
End;

Function DimensionsFit(Width, Height: Integer): Boolean;
Begin
  Result := (Width >= 1) And (Height >= 1) And (Width <= AssistantImageMaxSide) And (Height <= AssistantImageMaxSide) And
    (Int64(Width) * Height <= AssistantImageMaxPixels);
End;

Function DimensionsAllowed(Width, Height: Integer; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
  If (Width < 1) Or (Height < 1) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If (Width > AssistantImageMaxSide) Or (Height > AssistantImageMaxSide) Then
    Begin
      ErrorText := 'Image is larger than 16384 pixels on a side.';
      Exit;
    End;
  If Int64(Width) * Height > AssistantImageMaxPixels Then
    Begin
      ErrorText := 'Image has more than 16 million pixels.';
      Exit;
    End;
  Result := True;
End;

Function Le16(Const Data: TBytes; Index: Integer): Integer;
Begin
  Result := 0;
  If (Index < 0) Or (Index + 1 >= Length(Data)) Then Exit;
  Result := Data[Index] Or (Data[Index + 1] Shl 8);
End;

Function Le32u(Const Data: TBytes; Index: Integer): Int64;
Begin
  Result := 0;
  If (Index < 0) Or (Index + 3 >= Length(Data)) Then Exit;
  Result := Data[Index] + Data[Index + 1] * 256 + Data[Index + 2] * 65536 + Int64(Data[Index + 3]) * 16777216;
End;

Function Be16(Const Data: TBytes; Index: Integer): Integer;
Begin
  Result := 0;
  If (Index < 0) Or (Index + 1 >= Length(Data)) Then Exit;
  Result := (Data[Index] Shl 8) Or Data[Index + 1];
End;

Function Be32u(Const Data: TBytes; Index: Integer): Int64;
Begin
  Result := 0;
  If (Index < 0) Or (Index + 3 >= Length(Data)) Then Exit;
  Result := Int64(Data[Index]) * 16777216 + Data[Index + 1] * 65536 + Data[Index + 2] * 256 + Data[Index + 3];
End;

Function SetLimitedDim(Value: Int64; Out Dim: Integer): Boolean;
Begin
  Result := Value >= 1;
  If Not Result Then Exit;
  If Value > AssistantImageMaxSide Then
    Dim := AssistantImageMaxSide + 1
  Else
    Dim := Integer(Value);
End;

Procedure PutLe32(Var Data: TBytes; Index, Value: Integer);
Begin
  Data[Index] := Byte(Value And $FF);
  Data[Index + 1] := Byte((Value Shr 8) And $FF);
  Data[Index + 2] := Byte((Value Shr 16) And $FF);
  Data[Index + 3] := Byte((Value Shr 24) And $FF);
End;

Function ReadAt(Stream: TStream; Offset, Count: Int64; Out Data: TBytes): Boolean;
Begin
  Result := False;
  SetLength(Data, 0);
  If (Not Assigned(Stream)) Or (Offset < 0) Or (Count < 1) Or (Offset > Stream.Size) Or (Count > Stream.Size - Offset) Then
    Exit;
  SetLength(Data, Count);
  Try
    Stream.Position := Offset;
    Stream.ReadBuffer(Data[0], Count);
    Result := True;
  Except
    SetLength(Data, 0);
    Result := False;
  End;
End;

Function StartsWithPng(Const Data: TBytes): Boolean;
Const
  Signature: Array[0..7] Of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
Var
  I: Integer;
Begin
  Result := Length(Data) >= 8;
  If Not Result Then Exit;
  For I := 0 To 7 Do
    If Data[I] <> Signature[I] Then Exit(False);
End;

Function HasAsciiAt(Const Data: TBytes; Index: Integer; Const Text: String): Boolean;
Var
  I: Integer;
Begin
  Result := (Index >= 0) And (Text <> '') And (Index + Length(Text) <= Length(Data));
  If Not Result Then Exit;
  For I := 1 To Length(Text) Do
    If Data[Index + I - 1] <> Ord(Text[I]) Then Exit(False);
End;

Function SniffImageKind(Const Data: TBytes): TAssistantImageKind;
Var
  Marker: Byte;
Begin
  Result := ikUnknown;
  If Length(Data) < 2 Then Exit;
  If StartsWithPng(Data) Then Exit(ikPng);
  If (Length(Data) >= 3) And (Data[0] = $FF) And (Data[1] = $D8) And (Data[2] = $FF) Then Exit(ikJpeg);
  If (Length(Data) >= 6) And (Data[0] = Ord('G')) And (Data[1] = Ord('I')) And (Data[2] = Ord('F')) And (Data[3] = Ord('8')) And
    ((Data[4] = Ord('7')) Or (Data[4] = Ord('9'))) And (Data[5] = Ord('a')) Then Exit(ikGif);
  If (Data[0] = Ord('B')) And (Data[1] = Ord('M')) Then Exit(ikBmp);
  If (Length(Data) >= 6) And (Data[0] = 0) And (Data[1] = 0) And (Data[2] = 1) And (Data[3] = 0) And
    ((Data[4] <> 0) Or (Data[5] <> 0)) Then Exit(ikIco);
  If (Length(Data) >= 4) And (((Data[0] = Ord('I')) And (Data[1] = Ord('I')) And (Data[2] = 42) And (Data[3] = 0)) Or
    ((Data[0] = Ord('M')) And (Data[1] = Ord('M')) And (Data[2] = 0) And (Data[3] = 42))) Then Exit(ikTiff);
  If (Length(Data) >= 12) And (Data[0] = Ord('R')) And (Data[1] = Ord('I')) And (Data[2] = Ord('F')) And (Data[3] = Ord('F')) And
    (Data[8] = Ord('W')) And (Data[9] = Ord('E')) And (Data[10] = Ord('B')) And (Data[11] = Ord('P')) Then Exit(ikWebp);
  If HasAsciiAt(Data, 0, '/* XPM */') Or HasAsciiAt(Data, 3, '/* XPM */') Or HasAsciiAt(Data, 0, '! XPM2') Or
    HasAsciiAt(Data, 3, '! XPM2') Then Exit(ikXpm);
  If (Data[0] = Ord('P')) And (Data[1] >= Ord('1')) And (Data[1] <= Ord('6')) Then
    Begin
      Marker := Data[1];
      If (Length(Data) = 2) Or (Data[2] In [9, 10, 13, 32]) Then
        Case Marker Of
          Ord('1'), Ord('4'): Exit(ikPbm);
          Ord('2'), Ord('5'): Exit(ikPgm);
          Ord('3'), Ord('6'): Exit(ikPpm);
        Else
          Result := ikUnknown;
        End;
    End;
End;

Procedure KindFileInfo(Kind: TAssistantImageKind; Out Extension, Mime: String);
Begin
  Case Kind Of
    ikPng:
      Begin
        Extension := '.png';
        Mime := 'image/png';
      End;
    ikJpeg:
      Begin
        Extension := '.jpg';
        Mime := 'image/jpeg';
      End;
    ikGif:
      Begin
        Extension := '.gif';
        Mime := 'image/gif';
      End;
    ikBmp:
      Begin
        Extension := '.bmp';
        Mime := 'image/bmp';
      End;
    ikIco:
      Begin
        Extension := '.ico';
        Mime := 'image/x-icon';
      End;
    ikXpm:
      Begin
        Extension := '.xpm';
        Mime := 'image/x-xpixmap';
      End;
    ikTiff:
      Begin
        Extension := '.tif';
        Mime := 'image/tiff';
      End;
    ikPbm:
      Begin
        Extension := '.pbm';
        Mime := 'image/x-portable-bitmap';
      End;
    ikPgm:
      Begin
        Extension := '.pgm';
        Mime := 'image/x-portable-graymap';
      End;
    ikPpm:
      Begin
        Extension := '.ppm';
        Mime := 'image/x-portable-pixmap';
      End;
    ikWebp:
      Begin
        Extension := '.webp';
        Mime := 'image/webp';
      End;
  Else
    Extension := '.img';
    Mime := 'image/x-registered';
  End;
End;

Function KindOfReader(Reader: TFPCustomImageReaderClass; Const Data: TBytes): TAssistantImageKind;
Begin
  If Reader = TFPReaderPNG Then Exit(ikPng);
  If Reader = TFPReaderJPEG Then Exit(ikJpeg);
  If Reader = TFPReaderGIF Then Exit(ikGif);
  If Reader = TFPReaderBMP Then Exit(ikBmp);
  If Reader = TAssistantIcoReader Then Exit(ikIco);
  If Reader = TFPReaderXPM Then Exit(ikXpm);
  If Reader = TFPReaderTIFF Then Exit(ikTiff);
  If Reader = TFPReaderPNM Then
    Begin
      Result := SniffImageKind(Data);
      If Result In [ikPbm, ikPgm, ikPpm] Then Exit;
      Exit(ikPpm);
    End;
  Result := SniffImageKind(Data);
  If Result = ikUnknown Then Result := ikCustom;
End;

Function NoReaderError(Const Data: TBytes): String;
Begin
  If SniffImageKind(Data) = ikWebp Then
    Result := 'WebP is not supported.'
  Else If SniffImageKind(Data) = ikUnknown Then
    Result := 'Unsupported image format.'
  Else
    Result := 'Image could not be decoded.';
End;

Function DisplayNameOnly(Const Name: String): String;
Var
  I, Start: Integer;
  C: Char;
Begin
  Result := StringReplace(Trim(Name), '\', '/', [rfReplaceAll]);
  Start := 1;
  For I := 1 To Length(Result) Do
    If Result[I] = '/' Then Start := I + 1;
  Result := Copy(Result, Start, MaxInt);
  If (Result = '.') Or (Result = '..') Then Exit('');
  I := 1;
  While I <= Length(Result) Do
    Begin
      C := Result[I];
      If (C < #32) Or (C = #127) Or (C = '/') Or (C = '\') Or (C = ':') Then
        Delete(Result, I, 1)
      Else
        Inc(I);
    End;
  If Length(Result) > 240 Then Result := Copy(Result, 1, 240);
End;

Function NewImageId: String;
Var
  Guid: TGuid;
Begin
  Result := '';
  If CreateGUID(Guid) <> 0 Then Exit;
  Result := LowerCase(Copy(GUIDToString(Guid), 2, 36));
End;

Function RelativeImagePath(Const FileName: String): String;
Begin
  Result := AssistantStoreFolderName + '/' + AssistantImagesFolderName + '/' + FileName;
End;

Function ImageFileNameSafe(Const FileName: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := (FileName <> '') And (FileName <> '.') And (FileName <> '..') And (Length(FileName) <= 80) And
    (Pos('/', FileName) = 0) And (Pos('\', FileName) = 0);
  If Not Result Then Exit;
  For I := 1 To Length(FileName) Do
    Begin
      C := FileName[I];
      If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_']) Then Exit(False);
    End;
End;

Function StoreSegmentSafe(Const Segment: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := (Segment <> '') And (Length(Segment) <= 80) And (Segment <> '.') And (Segment <> '..');
  If Not Result Then Exit;
  For I := 1 To Length(Segment) Do
    Begin
      C := Segment[I];
      If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) Then Exit(False);
    End;
End;

Function StoredImageFileName(Const RelativePath: String; Out FileName, ErrorText: String): Boolean;
Var
  Normal, Head, Segment: String;
  Marker: Integer;
Begin
  Result := False;
  FileName := '';
  ErrorText := 'Stored image path is outside the image store.';
  Normal := StringReplace(Trim(RelativePath), '\', '/', [rfReplaceAll]);
  While (Length(Normal) > 0) And (Normal[1] = '/') Do Delete(Normal, 1, 1);
  If (Normal = '') Or (Pos('..', Normal) > 0) Then Exit;
  If Not SameText(Copy(Normal, 1, Length(AssistantStoreFolderName + '/')), AssistantStoreFolderName + '/') Then Exit;
  Marker := Pos('/' + AssistantImagesFolderName + '/', LowerCase(Normal));
  If Marker < 1 Then Exit;
  If Pos('/' + AssistantImagesFolderName + '/', LowerCase(Copy(Normal, Marker + 1, MaxInt))) > 0 Then Exit;
  Head := Copy(Normal, 1, Marker - 1);
  FileName := Copy(Normal, Marker + Length('/' + AssistantImagesFolderName + '/'), MaxInt);
  If Not ImageFileNameSafe(FileName) Then
    Begin
      FileName := '';
      Exit;
    End;
  If SameText(Head, AssistantStoreFolderName) Then
    Exit(True);
  If Not SameText(Copy(Head, 1, Length(AssistantStoreFolderName + '/targets/')), AssistantStoreFolderName + '/targets/') Then
    Begin
      FileName := '';
      Exit;
    End;
  Segment := Copy(Head, Length(AssistantStoreFolderName + '/targets/') + 1, MaxInt);
  If (Pos('/', Segment) > 0) Or (Not StoreSegmentSafe(Segment)) Then
    Begin
      FileName := '';
      Exit;
    End;
  Result := True;
End;

Function RefuseSymlinkChain(Const Root, FullPath: String; Out ErrorText: String): Boolean;
Var
  Current, Rest, Segment: String;
  Slash: Integer;
Begin
  Result := False;
  ErrorText := '';
  Current := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName;
  If FileIsSymlink(Current) Then
    Begin
      ErrorText := 'Refusing to read a symbolic link.';
      Exit;
    End;
  Rest := Copy(FullPath, Length(IncludeTrailingPathDelimiter(Current)) + 1, MaxInt);
  While Rest <> '' Do
    Begin
      Slash := Pos(PathDelim, Rest);
      If Slash < 1 Then
        Segment := Rest
      Else
        Segment := Copy(Rest, 1, Slash - 1);
      If (Segment = '') Or (Segment = '.') Or (Segment = '..') Then
        Begin
          ErrorText := 'Stored image path is outside the image store.';
          Exit;
        End;
      Current := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Current)) + Segment;
      If FileIsSymlink(Current) Then
        Begin
          ErrorText := 'Refusing to read a symbolic link.';
          Exit;
        End;
      If Slash < 1 Then Break;
      Delete(Rest, 1, Slash);
    End;
  Result := True;
End;

Function ResolveStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out FullPath, ErrorText: String): Boolean;
Var
  Root, FileName, Normal: String;
Begin
  Result := False;
  FullPath := '';
  ErrorText := '';
  Root := ProjectRootDir(ProjectRoot);
  If (Root = '') Or (Not DirectoryExistsUTF8(Root)) Then
    Begin
      ErrorText := 'No project root for the image store.';
      Exit;
    End;
  If Not StoredImageFileName(RelativePath, FileName, ErrorText) Then Exit;
  Normal := StringReplace(Trim(RelativePath), '\', '/', [rfReplaceAll]);
  While (Length(Normal) > 0) And (Normal[1] = '/') Do Delete(Normal, 1, 1);
  FullPath := Root + PathDelim + StringReplace(Normal, '/', PathDelim, [rfReplaceAll]);
  If (ExtractFileName(FullPath) <> FileName) Or
    (Not PathInside(Root + PathDelim + AssistantStoreFolderName, FullPath)) Then
    Begin
      FullPath := '';
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  If Not RefuseSymlinkChain(Root, FullPath, ErrorText) Then
    Begin
      FullPath := '';
      Exit;
    End;
  Result := True;
End;

Function ReadOpenNoFollow(Const Path: String; Expected: Int64; Out Data: TBytes; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Handle: Integer;
  Offset, Chunk, Got: SizeInt;
{$ELSE}
Var
  Stream: TFileStream;
{$ENDIF}
Begin
  Result := False;
  SetLength(Data, 0);
  ErrorText := '';
  If (Expected < 1) Or (Expected > AssistantImageMaxFileBytes) Then
    Begin
      ErrorText := 'Stored image could not be read.';
      Exit;
    End;
  {$IFDEF UNIX}
  Handle := fpOpen(PChar(Path), O_RDONLY Or O_NOFOLLOW);
  If Handle < 0 Then
    Begin
      If FileIsSymlink(Path) Then
        ErrorText := 'Refusing to read a symbolic link.'
      Else
        ErrorText := 'Stored image could not be read.';
      Exit;
    End;
  Try
    SetLength(Data, SizeInt(Expected));
    Offset := 0;
    While Offset < Expected Do
      Begin
        Chunk := SizeInt(Expected) - Offset;
        If Chunk > 65536 Then Chunk := 65536;
        Got := fpRead(Handle, Data[Offset], Chunk);
        If Got < 0 Then
          Begin
            SetLength(Data, 0);
            ErrorText := 'Stored image could not be read.';
            Exit;
          End;
        If Got = 0 Then Break;
        Offset := Offset + Got;
      End;
    If Offset <> Expected Then
      Begin
        SetLength(Data, 0);
        ErrorText := 'Stored image could not be read.';
        Exit;
      End;
    Result := True;
  Finally
    fpClose(Handle);
  End;
  {$ELSE}
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Except
    ErrorText := 'Stored image could not be read.';
    Exit;
  End;
  Try
    Try
      If Stream.Size <> Expected Then
        Begin
          ErrorText := 'Stored image could not be read.';
          Exit;
        End;
      SetLength(Data, SizeInt(Expected));
      Stream.ReadBuffer(Data[0], LongInt(Expected));
      Result := True;
    Except
      SetLength(Data, 0);
      ErrorText := 'Stored image could not be read.';
      Result := False;
    End;
  Finally
    Stream.Free;
  End;
  {$ENDIF}
End;

Function ReadStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  FullPath: String;
  Size: Int64;
Begin
  Result := False;
  SetLength(Data, 0);
  ErrorText := '';
  Try
    If Not ResolveStoredAssistantImage(ProjectRoot, RelativePath, FullPath, ErrorText) Then Exit;
    If Not FileExistsUTF8(FullPath) Or DirectoryExistsUTF8(FullPath) Then
      Begin
        ErrorText := 'Stored image is missing.';
        Exit;
      End;
    Size := FileSizeUTF8(FullPath);
    If (Size < 1) Or (Size > AssistantImageMaxFileBytes) Then
      Begin
        If Size > AssistantImageMaxFileBytes Then
          ErrorText := 'Image is larger than 8 MiB.'
        Else
          ErrorText := 'Stored image could not be read.';
        Exit;
      End;
    Result := ReadOpenNoFollow(FullPath, Size, Data, ErrorText);
  Except
    SetLength(Data, 0);
    Result := False;
    If ErrorText = '' Then ErrorText := 'Stored image could not be read.';
  End;
End;

Function EnsureRealDirectory(Const Path: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  If FileIsSymlink(Path) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  If DirectoryExistsUTF8(Path) Then Exit(True);
  If FileExistsUTF8(Path) Then
    Begin
      ErrorText := 'Could not create the image store.';
      Exit;
    End;
  If Not ForceDirectoriesUTF8(Path) Then
    Begin
      ErrorText := 'Could not create the image store.';
      Exit;
    End;
  If FileIsSymlink(Path) Or (Not DirectoryExistsUTF8(Path)) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  Result := True;
End;

Function EnsureImageStore(Const ProjectRoot: String; Out Directory, ErrorText: String): Boolean;
Var
  Root, AssistantDir: String;
Begin
  Result := False;
  Directory := '';
  ErrorText := '';
  Root := ProjectRootDir(ProjectRoot);
  If (Root = '') Or (Not DirectoryExistsUTF8(Root)) Then
    Begin
      ErrorText := 'No project root for the image store.';
      Exit;
    End;
  AssistantDir := Root + PathDelim + AssistantStoreFolderName;
  If Not EnsureRealDirectory(AssistantDir, ErrorText) Then Exit;
  Directory := AssistantDir + PathDelim + AssistantImagesFolderName;
  If Not EnsureRealDirectory(Directory, ErrorText) Then Exit;
  Directory := IncludeTrailingPathDelimiter(Directory);
  Result := True;
End;

Function WriteExclusive(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Handle: Integer;
  Offset, Chunk, Wrote: SizeInt;
{$ELSE}
Var
  Stream: TFileStream;
{$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  If Length(Data) < 1 Then
    Begin
      ErrorText := 'Could not store the image.';
      Exit;
    End;
  {$IFDEF UNIX}
  Handle := fpOpen(PChar(Path), O_WRONLY Or O_CREAT Or O_EXCL Or O_NOFOLLOW, &644);
  If Handle < 0 Then
    Begin
      If FileIsSymlink(Path) Then
        ErrorText := 'Refusing to store an image through a symbolic link.'
      Else
        ErrorText := 'Could not store the image.';
      Exit;
    End;
  Try
    Offset := 0;
    While Offset < Length(Data) Do
      Begin
        Chunk := Length(Data) - Offset;
        If Chunk > 65536 Then Chunk := 65536;
        Wrote := fpWrite(Handle, Data[Offset], Chunk);
        If Wrote < 1 Then
          Begin
            ErrorText := 'Could not store the image.';
            Exit;
          End;
        Offset := Offset + Wrote;
      End;
    Result := True;
  Finally
    fpClose(Handle);
  End;
  {$ELSE}
  If FileIsSymlink(Path) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(Path, fmCreate);
  Except
    ErrorText := 'Could not store the image.';
    Exit;
  End;
  Try
    Try
      Stream.WriteBuffer(Data[0], LongInt(Length(Data)));
      Result := True;
    Except
      ErrorText := 'Could not store the image.';
      Result := False;
    End;
  Finally
    Stream.Free;
  End;
  {$ENDIF}
End;

Function WriteNewFile(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
Var
  Temp: String;
Begin
  Result := False;
  ErrorText := '';
  If FileIsSymlink(Path) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  If FileExistsUTF8(Path) Then
    Begin
      ErrorText := 'Could not store the image.';
      Exit;
    End;
  Temp := Path + '.tmp';
  If FileIsSymlink(Temp) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  If FileExistsUTF8(Temp) And (Not FileIsSymlink(Temp)) Then DeleteFileUTF8(Temp);
  If Not WriteExclusive(Temp, Data, ErrorText) Then
    Begin
      If Not FileIsSymlink(Temp) Then DeleteFileUTF8(Temp);
      Exit;
    End;
  If Not RenameFileUTF8(Temp, Path) Then
    Begin
      DeleteFileUTF8(Temp);
      ErrorText := 'Could not store the image.';
      Exit;
    End;
  Result := True;
End;

Function GifFirstFrame(Const Data: TBytes; Out Frame: TBytes; Out Animated: Boolean; Out ErrorText: String): Boolean;
Var
  Pos, FirstEnd, TableBytes, FrameCount: Integer;
  PackedByte: Byte;
  Function SkipSubBlocks: Boolean;
  Var
    BlockLen: Integer;
  Begin
    Result := False;
    Repeat
      If Pos >= Length(Data) Then Exit;
      BlockLen := Data[Pos];
      Inc(Pos);
      If BlockLen = 0 Then Exit(True);
      If BlockLen > Length(Data) - Pos Then Exit;
      Inc(Pos, BlockLen);
    Until False;
  End;
  Function SkipExtension: Boolean;
  Begin
    Result := False;
    If Pos + 2 > Length(Data) Then Exit;
    Inc(Pos, 2);
    Result := SkipSubBlocks;
  End;
  Function SkipImage: Boolean;
  Begin
    Result := False;
    If Pos + 10 > Length(Data) Then Exit;
    PackedByte := Data[Pos + 9];
    Inc(Pos, 10);
    If (PackedByte And $80) <> 0 Then
      Begin
        TableBytes := 3 * (1 Shl ((PackedByte And 7) + 1));
        If (TableBytes < 1) Or (TableBytes > Length(Data) - Pos) Then Exit;
        Inc(Pos, TableBytes);
      End;
    If Pos >= Length(Data) Then Exit;
    Inc(Pos);
    Result := SkipSubBlocks;
  End;
Begin
  Result := False;
  SetLength(Frame, 0);
  Animated := False;
  ErrorText := '';
  If (Length(Data) < 13) Or (SniffImageKind(Data) <> ikGif) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If Not DimensionsAllowed(Le16(Data, 6), Le16(Data, 8), ErrorText) Then Exit;
  PackedByte := Data[10];
  Pos := 13;
  If (PackedByte And $80) <> 0 Then
    Begin
      TableBytes := 3 * (1 Shl ((PackedByte And 7) + 1));
      If (TableBytes < 1) Or (Pos + TableBytes > Length(Data)) Then
        Begin
          ErrorText := 'Image could not be decoded.';
          Exit;
        End;
      Inc(Pos, TableBytes);
    End;
  FrameCount := 0;
  FirstEnd := -1;
  While Pos < Length(Data) Do
    Begin
      If Data[Pos] = $3B Then Break;
      If Data[Pos] = $21 Then
        Begin
          If Not SkipExtension Then
            Begin
              ErrorText := 'Image could not be decoded.';
              Exit;
            End;
          Continue;
        End;
      If Data[Pos] = $2C Then
        Begin
          If Pos + 9 >= Length(Data) Then
            Begin
              ErrorText := 'Image could not be decoded.';
              Exit;
            End;
          If Not DimensionsAllowed(Le16(Data, Pos + 5), Le16(Data, Pos + 7), ErrorText) Then Exit;
          Inc(FrameCount);
          If FrameCount = 1 Then
            Begin
              If Not SkipImage Then
                Begin
                  ErrorText := 'Image could not be decoded.';
                  Exit;
                End;
              FirstEnd := Pos;
            End
          Else
            Begin
              Animated := True;
              Break;
            End;
          Continue;
        End;
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If (FrameCount < 1) Or (FirstEnd < 1) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If Not Animated Then
    Frame := Data
  Else
    Begin
      SetLength(Frame, FirstEnd + 1);
      Move(Data[0], Frame[0], FirstEnd);
      Frame[FirstEnd] := $3B;
    End;
  Result := True;
End;

Function LongSideOf(Img: TFPCustomImage): Integer;
Begin
  Result := 0;
  If Not Assigned(Img) Then Exit;
  Result := Img.Width;
  If Img.Height > Result Then Result := Img.Height;
End;

Function Downscale(Src: TFPCustomImage; MaxSide: Integer): TFPMemoryImage;
Var
  DstW, DstH, X, Y, SrcX, SrcY, X0, X1, Y0, Y1: Integer;
  AccR, AccG, AccB, AccA, AccW, Premul: Int64;
  Color: TFPColor;
Begin
  Result := Nil;
  If (Not Assigned(Src)) Or (Src.Width < 1) Or (Src.Height < 1) Or (MaxSide < 1) Then Exit;
  If Src.Width >= Src.Height Then
    Begin
      DstW := MaxSide;
      DstH := Max(1, Integer((Int64(Src.Height) * MaxSide) Div Src.Width));
    End
  Else
    Begin
      DstH := MaxSide;
      DstW := Max(1, Integer((Int64(Src.Width) * MaxSide) Div Src.Height));
    End;
  Result := TFPMemoryImage.Create(DstW, DstH);
  For Y := 0 To DstH - 1 Do
    Begin
      Y0 := Integer((Int64(Y) * Src.Height) Div DstH);
      Y1 := Integer(((Int64(Y) + 1) * Src.Height) Div DstH) - 1;
      If Y1 < Y0 Then Y1 := Y0;
      If Y1 >= Src.Height Then Y1 := Src.Height - 1;
      For X := 0 To DstW - 1 Do
        Begin
          X0 := Integer((Int64(X) * Src.Width) Div DstW);
          X1 := Integer(((Int64(X) + 1) * Src.Width) Div DstW) - 1;
          If X1 < X0 Then X1 := X0;
          If X1 >= Src.Width Then X1 := Src.Width - 1;
          AccR := 0;
          AccG := 0;
          AccB := 0;
          AccA := 0;
          AccW := 0;
          For SrcY := Y0 To Y1 Do
            For SrcX := X0 To X1 Do
              Begin
                Color := Src.Colors[SrcX, SrcY];
                AccA := AccA + Color.Alpha;
                AccR := AccR + (Int64(Color.Red) * Color.Alpha) Div 65535;
                AccG := AccG + (Int64(Color.Green) * Color.Alpha) Div 65535;
                AccB := AccB + (Int64(Color.Blue) * Color.Alpha) Div 65535;
                Inc(AccW);
              End;
          If AccW < 1 Then
            AccW := 1;
          Color.Alpha := Word(AccA Div AccW);
          If Color.Alpha = 0 Then
            Begin
              Color.Red := 0;
              Color.Green := 0;
              Color.Blue := 0;
            End
          Else
            Begin
              Premul := AccR Div AccW;
              If Premul >= Color.Alpha Then
                Color.Red := 65535
              Else
                Color.Red := Word((Premul * 65535) Div Color.Alpha);
              Premul := AccG Div AccW;
              If Premul >= Color.Alpha Then
                Color.Green := 65535
              Else
                Color.Green := Word((Premul * 65535) Div Color.Alpha);
              Premul := AccB Div AccW;
              If Premul >= Color.Alpha Then
                Color.Blue := 65535
              Else
                Color.Blue := Word((Premul * 65535) Div Color.Alpha);
            End;
          Result.Colors[X, Y] := Color;
        End;
    End;
End;

Function ImageForSide(Src: TFPCustomImage; MaxSide: Integer; Out Owned: TFPMemoryImage): TFPCustomImage;
Begin
  Owned := Nil;
  Result := Src;
  If LongSideOf(Src) > MaxSide Then
    Begin
      Owned := Downscale(Src, MaxSide);
      Result := Owned;
    End;
End;

Function ImageHasAlpha(Img: TFPCustomImage): Boolean;
Var
  X, Y: Integer;
Begin
  Result := False;
  If Not Assigned(Img) Then Exit;
  For Y := 0 To Img.Height - 1 Do
    For X := 0 To Img.Width - 1 Do
      If Img.Colors[X, Y].Alpha < 65535 Then Exit(True);
End;

Function FlattenOnWhite(Src: TFPCustomImage): TFPMemoryImage;
Var
  X, Y: Integer;
  Color: TFPColor;
  Inverse: Int64;
Begin
  Result := TFPMemoryImage.Create(Src.Width, Src.Height);
  For Y := 0 To Src.Height - 1 Do
    For X := 0 To Src.Width - 1 Do
      Begin
        Color := Src.Colors[X, Y];
        Inverse := 65535 - Color.Alpha;
        Color.Red := Word((Int64(Color.Red) * Color.Alpha + 65535 * Inverse) Div 65535);
        Color.Green := Word((Int64(Color.Green) * Color.Alpha + 65535 * Inverse) Div 65535);
        Color.Blue := Word((Int64(Color.Blue) * Color.Alpha + 65535 * Inverse) Div 65535);
        Color.Alpha := 65535;
        Result.Colors[X, Y] := Color;
      End;
End;

Function StreamBytes(Stream: TMemoryStream): TBytes;
Begin
  Result := Nil;
  If (Not Assigned(Stream)) Or (Stream.Size < 1) Then Exit;
  SetLength(Result, SizeInt(Stream.Size));
  Move(Stream.Memory^, Result[0], SizeInt(Stream.Size));
End;

Function EncodePng(Img: TFPCustomImage; Out Data: TBytes): Boolean;
Var
  Writer: TFPWriterPNG;
  Stream: TMemoryStream;
Begin
  Result := False;
  SetLength(Data, 0);
  If Not Assigned(Img) Then Exit;
  Writer := TFPWriterPNG.Create;
  Stream := TMemoryStream.Create;
  Try
    Try
      Writer.UseAlpha := ImageHasAlpha(Img);
      Writer.Indexed := False;
      Writer.WordSized := False;
      Img.SaveToStream(Stream, Writer);
      Data := StreamBytes(Stream);
      Result := Length(Data) > 0;
    Except
      SetLength(Data, 0);
      Result := False;
    End;
  Finally
    Stream.Free;
    Writer.Free;
  End;
End;

Function EncodeJpeg(Img: TFPCustomImage; Quality: Integer; Out Data: TBytes): Boolean;
Var
  Flat: TFPMemoryImage;
  Writer: TFPWriterJPEG;
  Stream: TMemoryStream;
Begin
  Result := False;
  SetLength(Data, 0);
  If Not Assigned(Img) Or (Quality < 1) Or (Quality > 100) Then Exit;
  Flat := FlattenOnWhite(Img);
  Writer := TFPWriterJPEG.Create;
  Stream := TMemoryStream.Create;
  Try
    Try
      Writer.CompressionQuality := Quality;
      Flat.SaveToStream(Stream, Writer);
      Data := StreamBytes(Stream);
      Result := Length(Data) > 0;
    Except
      SetLength(Data, 0);
      Result := False;
    End;
  Finally
    Stream.Free;
    Writer.Free;
    Flat.Free;
  End;
End;

Function PrepareUpload(Img: TFPMemoryImage; Out Data: TBytes; Out Mime, ErrorText: String): Boolean;
Var
  Side, Quality: Integer;
  Owned: TFPMemoryImage;
  Working: TFPCustomImage;
  Produced: Boolean;
Begin
  Result := False;
  SetLength(Data, 0);
  Mime := '';
  ErrorText := '';
  Produced := False;
  If Not Assigned(Img) Then
    Begin
      ErrorText := 'Image could not be prepared for upload.';
      Exit;
    End;
  Side := AssistantImageUploadMaxSide;
  While Side >= 32 Do
    Begin
      Working := ImageForSide(Img, Side, Owned);
      Try
        If Not Assigned(Working) Then Break;
        If EncodePng(Working, Data) Then
          Begin
            Produced := True;
            If Length(Data) <= AssistantImageUploadMaxBytes Then
              Begin
                Mime := 'image/png';
                Exit(True);
              End;
          End;
        For Quality In JpegQualities Do
          If EncodeJpeg(Working, Quality, Data) Then
            Begin
              Produced := True;
              If Length(Data) <= AssistantImageUploadMaxBytes Then
                Begin
                  Mime := 'image/jpeg';
                  Exit(True);
                End;
            End;
      Finally
        FreeAndNil(Owned);
      End;
      Side := (Side * 3) Div 4;
    End;
  SetLength(Data, 0);
  If Produced Then
    ErrorText := 'Image could not be reduced below 4 MiB for upload.'
  Else
    ErrorText := 'Image could not be prepared for upload.';
End;

Function PngSliceSize(Stream: TStream; Offset: Int64; Out Width, Height: Integer): Boolean;
Var
  Saved: Int64;
  Size: TPoint;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  Saved := Stream.Position;
  Try
    Try
      Stream.Position := Offset;
      Size := TFPReaderPNG.ImageSize(Stream);
      Width := Size.X;
      Height := Size.Y;
      Result := (Width > 0) And (Height > 0);
    Except
      Result := False;
    End;
  Finally
    Stream.Position := Saved;
  End;
End;

Function DibIconSize(Const Header: TBytes; DirW, DirH: Integer; Out Width, Height: Integer): Boolean;
Var
  BiWidth, BiHeight, XorHeight: Integer;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If Length(Header) < 16 Then Exit;
  If Le32u(Header, 0) < 40 Then Exit;
  If Header[7] <> 0 Then
    Begin
      Width := AssistantImageMaxSide + 1;
      Height := 1;
      Exit(True);
    End;
  BiWidth := Integer(Le32u(Header, 4));
  If Header[11] <> 0 Then
    Begin
      Width := BiWidth;
      Height := AssistantImageMaxSide + 1;
      Exit(True);
    End;
  BiHeight := Integer(Le32u(Header, 8));
  If (BiWidth < 1) Or (BiHeight < 1) Then Exit;
  If (DirH > 0) And (BiHeight = DirH * 2) Then
    XorHeight := DirH
  Else If (DirH > 0) And (BiHeight = DirH) Then
    XorHeight := DirH
  Else If (BiHeight Mod 2) = 0 Then
    XorHeight := BiHeight Div 2
  Else
    XorHeight := BiHeight;
  If (XorHeight < 1) Or (DirW < 1) Then Exit;
  Width := BiWidth;
  Height := XorHeight;
  Result := True;
End;

Function ReadIcoEntries(Stream: TStream; Out Entries: TIcoEntryArray): Boolean;
Var
  Header, Entry, Peek: TBytes;
  Count, Index, DirW, DirH: Integer;
  Offset, BytesInRes: Int64;
Begin
  Result := False;
  SetLength(Entries, 0);
  If Not Assigned(Stream) Then Exit;
  If Not ReadAt(Stream, 0, 6, Header) Then Exit;
  If (Header[0] <> 0) Or (Header[1] <> 0) Or (Header[2] <> 1) Or (Header[3] <> 0) Then Exit;
  Count := Le16(Header, 4);
  If (Count < 1) Or (Count > 256) Then Exit;
  If Stream.Size < 6 + Int64(Count) * 16 Then Exit;
  SetLength(Entries, Count);
  For Index := 0 To Count - 1 Do
    Begin
      Entries[Index].Valid := False;
      If Not ReadAt(Stream, 6 + Int64(Index) * 16, 16, Entry) Then Exit;
      DirW := Entry[0];
      DirH := Entry[1];
      If DirW = 0 Then DirW := 256;
      If DirH = 0 Then DirH := 256;
      BytesInRes := Le32u(Entry, 8);
      Offset := Le32u(Entry, 12);
      Entries[Index].Offset := Offset;
      Entries[Index].BytesInRes := BytesInRes;
      If (Offset < 0) Or (BytesInRes < 8) Or (Offset >= Stream.Size) Or (BytesInRes > Stream.Size - Offset) Then
        Continue;
      If Not ReadAt(Stream, Offset, 8, Peek) Then Continue;
      If StartsWithPng(Peek) Then
        Begin
          Entries[Index].IsPng := True;
          Entries[Index].Valid := PngSliceSize(Stream, Offset, Entries[Index].Width, Entries[Index].Height);
        End
      Else If ReadAt(Stream, Offset, 16, Peek) Then
        Begin
          Entries[Index].IsPng := False;
          Entries[Index].Valid := DibIconSize(Peek, DirW, DirH, Entries[Index].Width, Entries[Index].Height);
        End;
    End;
  Result := True;
End;

Function SelectIcoEntry(Const Entries: TIcoEntryArray): Integer;
Var
  Index, Best: Integer;
  Area, BestArea: Int64;
  HaveFit: Boolean;
Begin
  Result := -1;
  Best := -1;
  BestArea := -1;
  HaveFit := False;
  For Index := 0 To High(Entries) Do
    Begin
      If Not Entries[Index].Valid Then Continue;
      Area := Int64(Entries[Index].Width) * Entries[Index].Height;
      If DimensionsFit(Entries[Index].Width, Entries[Index].Height) Then
        Begin
          If (Not HaveFit) Or (Area > BestArea) Then
            Begin
              HaveFit := True;
              Best := Index;
              BestArea := Area;
            End;
        End
      Else If (Not HaveFit) And ((Best < 0) Or (Area > BestArea)) Then
        Begin
          Best := Index;
          BestArea := Area;
        End;
    End;
  Result := Best;
End;

Function DibPixelOffset(Const Dib: TBytes): Integer;
Var
  BiSize, BitCount, ClrUsed, Compression: Integer;
Begin
  Result := 0;
  If Length(Dib) < 40 Then Exit;
  BiSize := Integer(Le32u(Dib, 0));
  If (BiSize < 40) Or (BiSize > Length(Dib)) Then Exit;
  BitCount := Le16(Dib, 14);
  Compression := Integer(Le32u(Dib, 16));
  ClrUsed := 0;
  If Length(Dib) >= 36 Then ClrUsed := Integer(Le32u(Dib, 32));
  If BitCount <= 8 Then
    Begin
      If ClrUsed = 0 Then ClrUsed := 1 Shl BitCount;
    End
  Else
    ClrUsed := 0;
  Result := BiSize + ClrUsed * 4;
  If (Compression = 3) And (BiSize = 40) Then Result := Result + 12;
End;

Procedure LoadIcoEntry(Stream: TStream; Const Entry: TIcoEntry; Img: TFPCustomImage);
Var
  Payload, Wrapped: TBytes;
  Reader: TFPCustomImageReader;
  Slice: TBytesStream;
  PixelOffset: Integer;
Begin
  If (Not Entry.Valid) Or (Not DimensionsFit(Entry.Width, Entry.Height)) Then
    Raise Exception.Create('Image could not be decoded.');
  If (Entry.BytesInRes < 8) Or (Entry.BytesInRes > AssistantImageMaxFileBytes) Then
    Raise Exception.Create('Image could not be decoded.');
  If Not ReadAt(Stream, Entry.Offset, Entry.BytesInRes, Payload) Then
    Raise Exception.Create('Image could not be decoded.');
  Reader := Nil;
  Slice := Nil;
  Try
    If Entry.IsPng Then
      Begin
        Slice := TBytesStream.Create(Payload);
        Reader := TFPReaderPNG.Create;
        Img.LoadFromStream(Slice, Reader);
      End
    Else
      Begin
        If Length(Payload) < 40 Then Raise Exception.Create('Image could not be decoded.');
        PutLe32(Payload, 8, Entry.Height);
        PutLe32(Payload, 20, 0);
        PixelOffset := DibPixelOffset(Payload);
        If (PixelOffset < 40) Or (PixelOffset > Length(Payload)) Then
          Raise Exception.Create('Image could not be decoded.');
        SetLength(Wrapped, 14 + Length(Payload));
        Wrapped[0] := Ord('B');
        Wrapped[1] := Ord('M');
        PutLe32(Wrapped, 2, Length(Wrapped));
        PutLe32(Wrapped, 6, 0);
        PutLe32(Wrapped, 10, 14 + PixelOffset);
        Move(Payload[0], Wrapped[14], Length(Payload));
        Slice := TBytesStream.Create(Wrapped);
        Reader := TFPReaderBMP.Create;
        Img.LoadFromStream(Slice, Reader);
      End;
  Finally
    Reader.Free;
    Slice.Free;
  End;
End;

Function TAssistantIcoReader.InternalCheck(Str: TStream): Boolean;
Var
  Header: Array[0..5] Of Byte;
  Saved: Int64;
Begin
  Result := False;
  If Not Assigned(Str) Then Exit;
  Saved := Str.Position;
  Try
    If Str.Size - Str.Position < 6 Then Exit;
    If Str.Read(Header, 6) <> 6 Then Exit;
    Result := (Header[0] = 0) And (Header[1] = 0) And (Header[2] = 1) And (Header[3] = 0) And
      ((Header[4] <> 0) Or (Header[5] <> 0));
  Finally
    Str.Position := Saved;
  End;
End;

Class Function TAssistantIcoReader.ImageSize(Str: TStream): TPoint;
Var
  Entries: TIcoEntryArray;
  Index: Integer;
  Saved: Int64;
Begin
  Result.X := -1;
  Result.Y := -1;
  If Not Assigned(Str) Then Exit;
  Saved := Str.Position;
  Try
    Try
      If Not ReadIcoEntries(Str, Entries) Then Exit;
      For Index := 0 To High(Entries) Do
        If Entries[Index].Valid And (Not DimensionsFit(Entries[Index].Width, Entries[Index].Height)) Then
          Begin
            Result.X := Entries[Index].Width;
            Result.Y := Entries[Index].Height;
            Exit;
          End;
      Index := SelectIcoEntry(Entries);
      If Index < 0 Then Exit;
      Result.X := Entries[Index].Width;
      Result.Y := Entries[Index].Height;
    Except
      Result.X := -1;
      Result.Y := -1;
    End;
  Finally
    Str.Position := Saved;
  End;
End;

Procedure TAssistantIcoReader.InternalRead(Str: TStream; Img: TFPCustomImage);
Var
  Entries: TIcoEntryArray;
  Index: Integer;
  ErrorText: String;
Begin
  If Not ReadIcoEntries(Str, Entries) Then
    Raise Exception.Create('Image could not be decoded.');
  For Index := 0 To High(Entries) Do
    If Entries[Index].Valid And (Not DimensionsAllowed(Entries[Index].Width, Entries[Index].Height, ErrorText)) Then
      Raise Exception.Create(ErrorText);
  Index := SelectIcoEntry(Entries);
  If Index < 0 Then
    Raise Exception.Create('Image could not be decoded.');
  LoadIcoEntry(Str, Entries[Index], Img);
End;

Function ReaderImageSize(ReaderClass: TFPCustomImageReaderClass; Stream: TStream): TPoint;
Begin
  Result.X := -1;
  Result.Y := -1;
  If (ReaderClass = Nil) Or (Not Assigned(Stream)) Then Exit;
  If ReaderClass = TAssistantIcoReader Then
    Result := TAssistantIcoReader.ImageSize(Stream)
  Else If ReaderClass = TFPReaderPNG Then
    Result := TFPReaderPNG.ImageSize(Stream)
  Else If ReaderClass = TFPReaderJPEG Then
    Result := TFPReaderJPEG.ImageSize(Stream)
  Else If ReaderClass = TFPReaderGIF Then
    Result := TFPReaderGIF.ImageSize(Stream)
  Else If ReaderClass = TFPReaderBMP Then
    Result := TFPReaderBMP.ImageSize(Stream)
  Else If ReaderClass = TFPReaderXPM Then
    Result := TFPReaderXPM.ImageSize(Stream)
  Else If ReaderClass = TFPReaderTIFF Then
    Result := TFPReaderTIFF.ImageSize(Stream)
  Else If ReaderClass = TFPReaderPNM Then
    Result := TFPReaderPNM.ImageSize(Stream);
End;

Function PngHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  RawW, RawH: Int64;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 24) Or (Not StartsWithPng(Data)) Then Exit;
  If Not HasAsciiAt(Data, 12, 'IHDR') Then Exit;
  RawW := Be32u(Data, 16);
  RawH := Be32u(Data, 20);
  If Not SetLimitedDim(RawW, Width) Then Exit;
  Result := SetLimitedDim(RawH, Height);
End;

Function JpegHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Pos, Marker, SegLen: Integer;
  RawW, RawH: Int64;
  Function IsStartOfFrame(MarkerByte: Integer): Boolean;
  Begin
    Result := (MarkerByte >= $C0) And (MarkerByte <= $CF) And (MarkerByte <> $C4) And (MarkerByte <> $C8) And
      (MarkerByte <> $CC);
  End;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 4) Or (Data[0] <> $FF) Or (Data[1] <> $D8) Then Exit;
  Pos := 2;
  While Pos < Length(Data) Do
    Begin
      If Data[Pos] <> $FF Then Exit;
      While (Pos < Length(Data)) And (Data[Pos] = $FF) Do Inc(Pos);
      If Pos >= Length(Data) Then Exit;
      Marker := Data[Pos];
      Inc(Pos);
      If (Marker = $01) Or (Marker = $D8) Or (Marker = $D9) Or ((Marker >= $D0) And (Marker <= $D7)) Then Continue;
      If Pos + 1 >= Length(Data) Then Exit;
      SegLen := Be16(Data, Pos);
      If (SegLen < 2) Or (Pos + SegLen > Length(Data)) Then Exit;
      If IsStartOfFrame(Marker) Then
        Begin
          If SegLen < 7 Then Exit;
          RawH := Be16(Data, Pos + 3);
          RawW := Be16(Data, Pos + 5);
          If Not SetLimitedDim(RawW, Width) Then Exit;
          Exit(SetLimitedDim(RawH, Height));
        End;
      If Marker = $DA Then Exit;
      Inc(Pos, SegLen);
    End;
End;

Function GifHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 10) Or (SniffImageKind(Data) <> ikGif) Then Exit;
  If Not SetLimitedDim(Le16(Data, 6), Width) Then Exit;
  Result := SetLimitedDim(Le16(Data, 8), Height);
End;

Function BmpHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  HeaderBytes, RawW, RawH: Int64;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 26) Or (Data[0] <> Ord('B')) Or (Data[1] <> Ord('M')) Then Exit;
  HeaderBytes := Le32u(Data, 14);
  If HeaderBytes = 12 Then
    Begin
      If Length(Data) < 22 Then Exit;
      RawW := Le16(Data, 18);
      RawH := Le16(Data, 20);
    End
  Else If HeaderBytes >= 16 Then
    Begin
      RawW := Le32u(Data, 18);
      RawH := Le32u(Data, 22);
      If RawW > 2147483647 Then Exit;
      If RawH > 2147483647 Then RawH := 4294967296 - RawH;
    End
  Else
    Exit;
  If Not SetLimitedDim(RawW, Width) Then Exit;
  Result := SetLimitedDim(RawH, Height);
End;

Function TiffHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Little: Boolean;
  Ifd, Count, Entry, Seen, Page: Integer;
  RawW, RawH, NextIfd: Int64;
  HaveW, HaveH: Boolean;
  Function E16(Index: Integer): Integer;
  Begin
    If Little Then Result := Le16(Data, Index) Else Result := Be16(Data, Index);
  End;
  Function E32(Index: Integer): Int64;
  Begin
    If Little Then Result := Le32u(Data, Index) Else Result := Be32u(Data, Index);
  End;
  Function InlineValue(EntryIndex, TypeCode: Integer): Int64;
  Begin
    Result := 0;
    If TypeCode = 3 Then
      Result := E16(EntryIndex + 8)
    Else If TypeCode = 4 Then
      Result := E32(EntryIndex + 8);
  End;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If Length(Data) < 8 Then Exit;
  Little := (Data[0] = Ord('I')) And (Data[1] = Ord('I')) And (Data[2] = 42) And (Data[3] = 0);
  If Not Little And ((Data[0] <> Ord('M')) Or (Data[1] <> Ord('M')) Or (Data[2] <> 0) Or (Data[3] <> 42)) Then Exit;
  NextIfd := E32(4);
  RawW := 0;
  RawH := 0;
  For Page := 1 To 16 Do
    Begin
      If (NextIfd < 8) Or (NextIfd + 2 > Length(Data)) Then Break;
      Ifd := Integer(NextIfd);
      Count := E16(Ifd);
      If (Count < 1) Or (Count > 4096) Or (Ifd + 2 + Int64(Count) * 12 + 4 > Length(Data)) Then
        Begin
          Result := False;
          Exit;
        End;
      HaveW := False;
      HaveH := False;
      For Entry := 0 To Count - 1 Do
        Begin
          Seen := Ifd + 2 + Entry * 12;
          If E32(Seen + 4) <> 1 Then Continue;
          If E16(Seen) = 256 Then
            Begin
              RawW := InlineValue(Seen, E16(Seen + 2));
              HaveW := RawW >= 1;
            End
          Else If E16(Seen) = 257 Then
            Begin
              RawH := InlineValue(Seen, E16(Seen + 2));
              HaveH := RawH >= 1;
            End;
        End;
      If HaveW And HaveH And ((RawW > Width) Or (RawH > Height)) Then
        Begin
          If Not SetLimitedDim(RawW, Width) Then Exit;
          If Not SetLimitedDim(RawH, Height) Then Exit;
          Result := True;
        End;
      NextIfd := E32(Ifd + 2 + Count * 12);
      If NextIfd = 0 Then Break;
    End;
End;

Function ReadHeaderDecimal(Const Data: TBytes; Var Pos: Integer; Limit: Integer; Out Value: Int64): Boolean;
Begin
  Result := False;
  Value := 0;
  If (Pos < 0) Or (Pos >= Length(Data)) Or (Pos >= Limit) Then Exit;
  If (Data[Pos] < Ord('0')) Or (Data[Pos] > Ord('9')) Then Exit;
  While (Pos < Length(Data)) And (Pos < Limit) And (Data[Pos] >= Ord('0')) And (Data[Pos] <= Ord('9')) Do
    Begin
      Value := Value * 10 + (Data[Pos] - Ord('0'));
      If Value > AssistantImageMaxSide + 1 Then Value := AssistantImageMaxSide + 1;
      Inc(Pos);
      Result := True;
    End;
End;

Function XpmHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Pos, Limit, Line: Integer;
  RawW, RawH: Int64;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  Limit := Length(Data);
  If Limit > 8192 Then Limit := 8192;
  If HasAsciiAt(Data, 0, '! XPM2') Or HasAsciiAt(Data, 3, '! XPM2') Then
    Begin
      Pos := 0;
      While (Pos < Limit) And (Data[Pos] <> 10) And (Data[Pos] <> 13) Do Inc(Pos);
      While (Pos < Limit) And ((Data[Pos] = 10) Or (Data[Pos] = 13)) Do Inc(Pos);
      If Not ReadHeaderDecimal(Data, Pos, Limit, RawW) Then Exit;
      While (Pos < Limit) And ((Data[Pos] = 32) Or (Data[Pos] = 9)) Do Inc(Pos);
      If Not ReadHeaderDecimal(Data, Pos, Limit, RawH) Then Exit;
    End
  Else
    Begin
      Pos := 0;
      While (Pos < Limit) And (Data[Pos] <> Ord('"')) Do Inc(Pos);
      If Pos >= Limit Then Exit;
      Inc(Pos);
      If Not ReadHeaderDecimal(Data, Pos, Limit, RawW) Then Exit;
      While (Pos < Limit) And ((Data[Pos] = 32) Or (Data[Pos] = 9)) Do Inc(Pos);
      If Not ReadHeaderDecimal(Data, Pos, Limit, RawH) Then Exit;
      Line := Pos;
      While (Line < Limit) And (Data[Line] <> Ord('"')) And (Data[Line] <> 10) Do Inc(Line);
      If (Line >= Limit) Or (Data[Line] <> Ord('"')) Then Exit;
    End;
  If Not SetLimitedDim(RawW, Width) Then Exit;
  Result := SetLimitedDim(RawH, Height);
End;

Function PnmHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Pos, Limit: Integer;
  RawW, RawH: Int64;
  Procedure SkipGap;
  Begin
    While Pos < Limit Do
      If Data[Pos] = Ord('#') Then
        While (Pos < Limit) And (Data[Pos] <> 10) And (Data[Pos] <> 13) Do Inc(Pos)
      Else If (Data[Pos] = 9) Or (Data[Pos] = 10) Or (Data[Pos] = 13) Or (Data[Pos] = 32) Then
        Inc(Pos)
      Else
        Exit;
  End;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 3) Or (SniffImageKind(Data) = ikUnknown) Then Exit;
  If Not (SniffImageKind(Data) In [ikPbm, ikPgm, ikPpm]) Then Exit;
  Limit := Length(Data);
  If Limit > 65536 Then Limit := 65536;
  Pos := 2;
  SkipGap;
  If Not ReadHeaderDecimal(Data, Pos, Limit, RawW) Then Exit;
  SkipGap;
  If Not ReadHeaderDecimal(Data, Pos, Limit, RawH) Then Exit;
  If Not SetLimitedDim(RawW, Width) Then Exit;
  Result := SetLimitedDim(RawH, Height);
End;

Function WebpHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Bits, RawW, RawH: Int64;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If (Length(Data) < 30) Or (SniffImageKind(Data) <> ikWebp) Then Exit;
  If HasAsciiAt(Data, 12, 'VP8X') Then
    Begin
      RawW := 1 + Data[24] + Data[25] * 256 + Int64(Data[26]) * 65536;
      RawH := 1 + Data[27] + Data[28] * 256 + Int64(Data[29]) * 65536;
    End
  Else If HasAsciiAt(Data, 12, 'VP8L') Then
    Begin
      If Data[20] <> $2F Then Exit;
      Bits := Le32u(Data, 21);
      RawW := (Bits And $3FFF) + 1;
      RawH := ((Bits Shr 14) And $3FFF) + 1;
    End
  Else If HasAsciiAt(Data, 12, 'VP8 ') Then
    Begin
      If (Data[20] And 1) <> 0 Then Exit;
      If (Data[23] <> $9D) Or (Data[24] <> $01) Or (Data[25] <> $2A) Then Exit;
      RawW := Le16(Data, 26) And $3FFF;
      RawH := Le16(Data, 28) And $3FFF;
    End
  Else
    Exit;
  If Not SetLimitedDim(RawW, Width) Then Exit;
  Result := SetLimitedDim(RawH, Height);
End;

Function IcoHeaderSize(Const Data: TBytes; Out Width, Height: Integer): Boolean;
Var
  Stream: TBytesStream;
  Dimensions: TPoint;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  If SniffImageKind(Data) <> ikIco Then Exit;
  Stream := TBytesStream.Create(Data);
  Try
    Dimensions := TAssistantIcoReader.ImageSize(Stream);
    Width := Dimensions.X;
    Height := Dimensions.Y;
    Result := (Width >= 1) And (Height >= 1);
  Finally
    Stream.Free;
  End;
End;

Function HeaderImageSize(Const Data: TBytes; Kind: TAssistantImageKind; Out Width, Height: Integer): Boolean;
Begin
  Width := 0;
  Height := 0;
  Case Kind Of
    ikPng: Result := PngHeaderSize(Data, Width, Height);
    ikJpeg: Result := JpegHeaderSize(Data, Width, Height);
    ikGif: Result := GifHeaderSize(Data, Width, Height);
    ikBmp: Result := BmpHeaderSize(Data, Width, Height);
    ikIco: Result := IcoHeaderSize(Data, Width, Height);
    ikXpm: Result := XpmHeaderSize(Data, Width, Height);
    ikTiff: Result := TiffHeaderSize(Data, Width, Height);
    ikPbm, ikPgm, ikPpm: Result := PnmHeaderSize(Data, Width, Height);
    ikWebp: Result := WebpHeaderSize(Data, Width, Height);
  Else
    Result := False;
  End;
End;

Function MeasuredImageSize(Const Data: TBytes; ReaderClass: TFPCustomImageReaderClass; Out Width, Height: Integer): Boolean;
Var
  Stream: TBytesStream;
  Dimensions: TPoint;
  Kind: TAssistantImageKind;
Begin
  Result := False;
  Width := 0;
  Height := 0;
  Dimensions.X := -1;
  Dimensions.Y := -1;
  If ReaderClass <> Nil Then
    Begin
      Stream := TBytesStream.Create(Data);
      Try
        Try
          Dimensions := ReaderImageSize(ReaderClass, Stream);
        Except
          Dimensions.X := -1;
          Dimensions.Y := -1;
        End;
      Finally
        Stream.Free;
      End;
    End;
  If (Dimensions.X >= 1) And (Dimensions.Y >= 1) Then
    Begin
      Width := Dimensions.X;
      Height := Dimensions.Y;
      Exit(True);
    End;
  Kind := ikUnknown;
  If ReaderClass <> Nil Then Kind := KindOfReader(ReaderClass, Data);
  If (Kind = ikUnknown) Or (Kind = ikCustom) Then Kind := SniffImageKind(Data);
  Result := HeaderImageSize(Data, Kind, Width, Height);
End;

Function ProbeImageSize(Const Data: TBytes; ReaderClass: TFPCustomImageReaderClass; Out ErrorText: String): Boolean;
Var
  Width, Height: Integer;
Begin
  Result := False;
  ErrorText := '';
  If ReaderClass = Nil Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If Not MeasuredImageSize(Data, ReaderClass, Width, Height) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  Result := DimensionsAllowed(Width, Height, ErrorText);
End;

Function FindReader(Const Data: TBytes; Out Reader: TFPCustomImageReaderClass; Out ErrorText: String): Boolean;
Var
  Stream: TBytesStream;
Begin
  Result := False;
  Reader := Nil;
  ErrorText := '';
  Stream := TBytesStream.Create(Data);
  Try
    Try
      Reader := TFPCustomImage.FindReaderFromStream(Stream);
    Except
      Reader := Nil;
    End;
  Finally
    Stream.Free;
  End;
  If Reader = Nil Then
    Begin
      ErrorText := NoReaderError(Data);
      Exit;
    End;
  Result := True;
End;

Function DecodeStillImage(Const Data: TBytes; ReaderClass: TFPCustomImageReaderClass; Out Img: TFPMemoryImage;
  Out ErrorText: String): Boolean;
Var
  Stream: TBytesStream;
  Reader: TFPCustomImageReader;
  Width, Height: Integer;
Begin
  Result := False;
  Img := Nil;
  ErrorText := '';
  If (Length(Data) < 1) Or (ReaderClass = Nil) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If Not MeasuredImageSize(Data, ReaderClass, Width, Height) Then
    Begin
      ErrorText := 'Image could not be decoded.';
      Exit;
    End;
  If Not DimensionsAllowed(Width, Height, ErrorText) Then Exit;
  Stream := TBytesStream.Create(Data);
  Reader := Nil;
  Try
    Try
      Img := TFPMemoryImage.Create(0, 0);
      Reader := ReaderClass.Create;
      Stream.Position := 0;
      Img.LoadFromStream(Stream, Reader);
      If Not DimensionsAllowed(Img.Width, Img.Height, ErrorText) Then
        Begin
          FreeAndNil(Img);
          Exit;
        End;
      Result := True;
    Except
      FreeAndNil(Img);
      If ErrorText = '' Then ErrorText := 'Image could not be decoded.';
      Result := False;
    End;
  Finally
    Reader.Free;
    Stream.Free;
  End;
End;

Function CopyLimitedStream(Stream: TStream; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Remaining: Int64;
Begin
  Result := False;
  SetLength(Data, 0);
  ErrorText := '';
  If Not Assigned(Stream) Then
    Begin
      ErrorText := 'Image is empty.';
      Exit;
    End;
  Try
    Remaining := Stream.Size - Stream.Position;
  Except
    ErrorText := 'Image could not be read.';
    Exit;
  End;
  If Remaining <= 0 Then
    Begin
      ErrorText := 'Image is empty.';
      Exit;
    End;
  If Remaining > AssistantImageMaxFileBytes Then
    Begin
      ErrorText := 'Image is larger than 8 MiB.';
      Exit;
    End;
  SetLength(Data, Remaining);
  Try
    Stream.ReadBuffer(Data[0], LongInt(Remaining));
    Result := True;
  Except
    SetLength(Data, 0);
    ErrorText := 'Image could not be read.';
  End;
End;

Function ReadAcceptedFile(Const SourcePath: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Path: String;
  Size: Int64;
  Stream: TFileStream;
Begin
  Result := False;
  SetLength(Data, 0);
  ErrorText := '';
  Path := Trim(SourcePath);
  If Path = '' Then
    Begin
      ErrorText := 'Image file was not found.';
      Exit;
    End;
  If (Not FileExistsUTF8(Path)) Or DirectoryExistsUTF8(Path) Then
    Begin
      ErrorText := 'Image file was not found.';
      Exit;
    End;
  { Stat the size before opening. An oversize file is not read. }
  Size := FileSizeUTF8(Path);
  If Size < 0 Then
    Begin
      ErrorText := 'Image file could not be read.';
      Exit;
    End;
  If Size = 0 Then
    Begin
      ErrorText := 'Image is empty.';
      Exit;
    End;
  If Size > AssistantImageMaxFileBytes Then
    Begin
      ErrorText := 'Image is larger than 8 MiB.';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Except
    ErrorText := 'Image file could not be read.';
    Exit;
  End;
  Try
    Try
      If Stream.Size > AssistantImageMaxFileBytes Then
        Begin
          ErrorText := 'Image is larger than 8 MiB.';
          Exit;
        End;
      If Stream.Size < 1 Then
        Begin
          ErrorText := 'Image is empty.';
          Exit;
        End;
      SetLength(Data, SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[0], LongInt(Stream.Size));
      Result := True;
    Except
      SetLength(Data, 0);
      ErrorText := 'Image file could not be read.';
      Result := False;
    End;
  Finally
    Stream.Free;
  End;
End;

Function StorePrepared(Const ProjectRoot, StoreDirectory, OriginalName: String; Const Source: TBytes;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
Var
  ReaderClass: TFPCustomImageReaderClass;
  Kind: TAssistantImageKind;
  Display, Upload: TBytes;
  Img: TFPMemoryImage;
  Directory, Id, DisplayExt, DisplayMime, UploadExt, UploadMime, DisplayFile, UploadFile: String;
  Attempt: Integer;
  Animated: Boolean;
Begin
  Result := False;
  ClearStored(Stored);
  ErrorText := '';
  SetLength(Display, 0);
  SetLength(Upload, 0);
  Img := Nil;
  If Not FindReader(Source, ReaderClass, ErrorText) Then Exit;
  { Refuse an oversized header before GIF splitting or pixel decode. }
  If Not ProbeImageSize(Source, ReaderClass, ErrorText) Then Exit;
  Kind := KindOfReader(ReaderClass, Source);
  If Kind = ikGif Then
    Begin
      If Not GifFirstFrame(Source, Display, Animated, ErrorText) Then Exit;
    End
  Else
    Begin
      Display := Source;
      Animated := False;
    End;
  If Not DecodeStillImage(Display, ReaderClass, Img, ErrorText) Then Exit;
  Try
    If Not PrepareUpload(Img, Upload, UploadMime, ErrorText) Then Exit;
    KindFileInfo(Kind, DisplayExt, DisplayMime);
    If UploadMime = 'image/jpeg' Then
      UploadExt := '.jpg'
    Else
      Begin
        UploadExt := '.png';
        UploadMime := 'image/png';
      End;
    If Trim(StoreDirectory) = '' Then
      Begin
        If Not EnsureImageStore(ProjectRoot, Directory, ErrorText) Then Exit;
      End
    Else If Not EnsureStoreImages(ProjectRoot, StoreDirectory, Directory, ErrorText) Then Exit;
    DisplayFile := '';
    UploadFile := '';
    Id := '';
    For Attempt := 1 To 4 Do
      Begin
        Id := NewImageId;
        If Id = '' Then
          Begin
            ErrorText := 'Could not store the image.';
            Exit;
          End;
        DisplayFile := Id + DisplayExt;
        UploadFile := Id + '-upload' + UploadExt;
        If FileExistsUTF8(Directory + DisplayFile) Or FileExistsUTF8(Directory + UploadFile) Or
          FileIsSymlink(Directory + DisplayFile) Or FileIsSymlink(Directory + UploadFile) Then
          Begin
            Id := '';
            Continue;
          End;
        Break;
      End;
    If Id = '' Then
      Begin
        ErrorText := 'Could not store the image.';
        Exit;
      End;
    If Not WriteNewFile(Directory + DisplayFile, Display, ErrorText) Then Exit;
    If Not WriteNewFile(Directory + UploadFile, Upload, ErrorText) Then
      Begin
        DeleteFileUTF8(Directory + DisplayFile);
        Exit;
      End;
    Stored.Id := Id;
    Stored.OriginalName := DisplayNameOnly(OriginalName);
    Stored.Mime := DisplayMime;
    Stored.Width := Img.Width;
    Stored.Height := Img.Height;
    Stored.DisplayRelativePath := ImagePathPrefix(ProjectRoot, Directory) + DisplayFile;
    Stored.UploadRelativePath := ImagePathPrefix(ProjectRoot, Directory) + UploadFile;
    Stored.UploadMime := UploadMime;
    Stored.AnimationDiscarded := Animated;
    Result := True;
  Finally
    FreeAndNil(Img);
  End;
End;

Function StoreAssistantImageFromStream(Const ProjectRoot, OriginalName: String; Stream: TStream;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
Var
  Data: TBytes;
Begin
  ClearStored(Stored);
  Result := False;
  ErrorText := '';
  Try
    If Not CopyLimitedStream(Stream, Data, ErrorText) Then Exit;
    Result := StorePrepared(ProjectRoot, '', OriginalName, Data, Stored, ErrorText);
    If Not Result Then ClearStored(Stored);
  Except
    ClearStored(Stored);
    Result := False;
    If ErrorText = '' Then ErrorText := 'Image could not be stored.';
  End;
End;

Function StoreAssistantImageFromFile(Const ProjectRoot, SourcePath: String; Out Stored: TAssistantStoredImage;
  Out ErrorText: String): Boolean;
Var
  Data: TBytes;
Begin
  ClearStored(Stored);
  Result := False;
  ErrorText := '';
  Try
    If Not ReadAcceptedFile(SourcePath, Data, ErrorText) Then Exit;
    Result := StorePrepared(ProjectRoot, '', SourcePath, Data, Stored, ErrorText);
    If Not Result Then ClearStored(Stored);
  Except
    ClearStored(Stored);
    Result := False;
    If ErrorText = '' Then ErrorText := 'Image could not be stored.';
  End;
End;

Function CleanRefText(Const Value: String): String;
Var
  Lower: String;
Begin
  Result := Trim(Value);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Lower := LowerCase(Result);
  If (Length(Result) > 500) Or (Pos('data:', Lower) > 0) Or (Pos('base64', Lower) > 0) Then
    Result := '';
End;

Function ImageRefFromStored(Const Stored: TAssistantStoredImage): TAssistantImageRef;
Begin
  Result.Id := CleanRefText(Stored.Id);
  Result.Name := CleanRefText(Stored.OriginalName);
  Result.Mime := CleanRefText(Stored.Mime);
  Result.Width := Stored.Width;
  Result.Height := Stored.Height;
  If (Result.Width < 0) Or (Result.Width > AssistantImageMaxSide) Then Result.Width := 0;
  If (Result.Height < 0) Or (Result.Height > AssistantImageMaxSide) Then Result.Height := 0;
  Result.DisplayPath := CleanRefText(Stored.DisplayRelativePath);
  Result.UploadPath := CleanRefText(Stored.UploadRelativePath);
  Result.UploadMime := CleanRefText(Stored.UploadMime);
  Result.AnimationDiscarded := Stored.AnimationDiscarded;
End;

Function RefFromJson(Obj: TJSONObject): TAssistantImageRef;
Begin
  Result.Id := '';
  Result.Name := '';
  Result.Mime := '';
  Result.Width := 0;
  Result.Height := 0;
  Result.DisplayPath := '';
  Result.UploadPath := '';
  Result.UploadMime := '';
  Result.AnimationDiscarded := False;
  If Not Assigned(Obj) Then Exit;
  Result.Id := CleanRefText(Obj.Get('id', ''));
  Result.Name := CleanRefText(Obj.Get('name', ''));
  Result.Mime := CleanRefText(Obj.Get('mime', ''));
  Result.Width := Obj.Get('width', 0);
  Result.Height := Obj.Get('height', 0);
  If (Result.Width < 0) Or (Result.Width > AssistantImageMaxSide) Then Result.Width := 0;
  If (Result.Height < 0) Or (Result.Height > AssistantImageMaxSide) Then Result.Height := 0;
  Result.DisplayPath := CleanRefText(Obj.Get('display', ''));
  Result.UploadPath := CleanRefText(Obj.Get('upload', ''));
  Result.UploadMime := CleanRefText(Obj.Get('upload_mime', ''));
  Result.AnimationDiscarded := Obj.Get('animation_discarded', False);
End;

Function AssistantImageRefsToJson(Const Refs: TAssistantImageRefArray): String;
Var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Ref: TAssistantImageRef;
Begin
  Result := '';
  If Length(Refs) = 0 Then Exit;
  Arr := TJSONArray.Create;
  Try
    For I := 0 To High(Refs) Do
      Begin
        Ref := Refs[I];
        Ref.Id := CleanRefText(Ref.Id);
        Ref.Name := CleanRefText(Ref.Name);
        Ref.Mime := CleanRefText(Ref.Mime);
        Ref.DisplayPath := CleanRefText(Ref.DisplayPath);
        Ref.UploadPath := CleanRefText(Ref.UploadPath);
        Ref.UploadMime := CleanRefText(Ref.UploadMime);
        If (Ref.Id = '') And (Ref.Name = '') And (Ref.DisplayPath = '') And (Ref.UploadPath = '') Then Continue;
        Obj := TJSONObject.Create;
        Obj.Add('id', Ref.Id);
        Obj.Add('name', Ref.Name);
        Obj.Add('mime', Ref.Mime);
        Obj.Add('width', Ref.Width);
        Obj.Add('height', Ref.Height);
        Obj.Add('display', Ref.DisplayPath);
        Obj.Add('upload', Ref.UploadPath);
        Obj.Add('upload_mime', Ref.UploadMime);
        Obj.Add('animation_discarded', Ref.AnimationDiscarded);
        Arr.Add(Obj);
      End;
    If Arr.Count > 0 Then
      Result := Arr.AsJSON;
  Finally
    Arr.Free;
  End;
End;

Function ParseAssistantImageRefs(Const JsonText: String; Out Refs: TAssistantImageRefArray): Boolean;
Var
  Data: TJSONData;
  Arr: TJSONArray;
  I, N: Integer;
Begin
  Result := False;
  SetLength(Refs, 0);
  If Trim(JsonText) = '' Then Exit(True);
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonText);
    Except
      Exit;
    End;
    If Not (Data Is TJSONArray) Then Exit;
    Arr := TJSONArray(Data);
    SetLength(Refs, Arr.Count);
    N := 0;
    For I := 0 To Arr.Count - 1 Do
      If Arr.Items[I] Is TJSONObject Then
        Begin
          Refs[N] := RefFromJson(TJSONObject(Arr.Items[I]));
          If (Refs[N].Id <> '') Or (Refs[N].Name <> '') Or (Refs[N].DisplayPath <> '') Or (Refs[N].UploadPath <> '') Then
            Inc(N);
        End;
    SetLength(Refs, N);
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function AssistantImageFileLabel(Const Ref: TAssistantImageRef): String;
Begin
  Result := Trim(Ref.Name);
  If Result = '' Then Result := Trim(Ref.Id);
  If Result = '' Then Result := 'Image';
End;

Function AssistantImageHistoryPreview(Const AttachmentsJson: String): String;
Var
  Refs: TAssistantImageRefArray;
  I: Integer;
Begin
  Result := '';
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Then Exit;
  If Length(Refs) = 0 Then Exit;
  For I := 0 To High(Refs) Do
    If Trim(Refs[I].Name) <> '' Then Exit(Refs[I].Name);
  Result := 'Image';
End;

Procedure AppendAssistantImageFileNames(Const AttachmentsJson: String; Lines: TStrings);
Var
  Refs: TAssistantImageRefArray;
  I: Integer;
Begin
  If Not Assigned(Lines) Then Exit;
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Then Exit;
  For I := 0 To High(Refs) Do
    Lines.Add(AssistantImageFileLabel(Refs[I]));
End;

Function ArchiveIdAllowed(Const ArchiveId: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := False;
  If (ArchiveId = '') Or (Length(ArchiveId) > 24) Then Exit;
  For I := 1 To Length(ArchiveId) Do
    Begin
      C := ArchiveId[I];
      If Not (((C >= '0') And (C <= '9')) Or (C = 'T') Or (C = 't') Or (C = 'x') Or (C = 'X')) Then Exit;
    End;
  Result := True;
End;

Function StoreImagesDirectory(Const StoreDirectory: String): String;
Begin
  Result := '';
  If Trim(StoreDirectory) = '' Then Exit;
  Result := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Trim(StoreDirectory))) + AssistantImagesFolderName + PathDelim;
End;

Function ArchiveImagesDirectory(Const StoreDirectory, ArchiveId: String): String;
Begin
  Result := '';
  If Not ArchiveIdAllowed(ArchiveId) Then Exit;
  Result := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Trim(StoreDirectory))) + 'images-' + ArchiveId + PathDelim;
End;

Function PathInside(Const Root, Path: String): Boolean;
Var
  RootPath, Full: String;
Begin
  RootPath := IncludeTrailingPathDelimiter(ExpandFileNameUTF8(ExcludeTrailingPathDelimiter(Root)));
  Full := ExpandFileNameUTF8(Path);
  Result := (RootPath <> '') And (Length(Full) >= Length(RootPath)) And
    (CompareFilenames(Copy(Full, 1, Length(RootPath)), RootPath) = 0);
End;

Function ImageNameAllowed(Const FileName: String): Boolean;
Var
  Parsed, ErrorText: String;
Begin
  Result := StoredImageFileName(RelativeImagePath(FileName), Parsed, ErrorText) And (Parsed = FileName);
End;

Procedure AddImageName(Const RelativePath: String; Names: TStrings);
Var
  FileName, ErrorText: String;
Begin
  If Not Assigned(Names) Then Exit;
  If StoredImageFileName(RelativePath, FileName, ErrorText) And ImageNameAllowed(FileName) Then
    Names.Add(FileName);
End;

Procedure CollectAttachmentNames(Data: TJSONData; Names: TStrings);
Var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
Begin
  If Not (Data Is TJSONArray) Then Exit;
  Arr := TJSONArray(Data);
  For I := 0 To Arr.Count - 1 Do
    If Arr.Items[I] Is TJSONObject Then
      Begin
        Obj := TJSONObject(Arr.Items[I]);
        AddImageName(Obj.Get('display', ''), Names);
        AddImageName(Obj.Get('upload', ''), Names);
      End;
End;

Procedure CollectMessageAttachmentNames(Messages: TJSONArray; Names: TStrings);
Var
  I: Integer;
  Obj: TJSONObject;
Begin
  If Not Assigned(Messages) Then Exit;
  For I := 0 To Messages.Count - 1 Do
    If Messages.Items[I] Is TJSONObject Then
      Begin
        Obj := TJSONObject(Messages.Items[I]);
        CollectAttachmentNames(Obj.Find('attachments'), Names);
      End;
End;

Procedure CollectConversationImageNames(Const ConversationFile: String; Names: TStrings);
Var
  Lines: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  I: Integer;
Begin
  If Not Assigned(Names) Then Exit;
  If (ConversationFile = '') Or FileIsSymlink(ConversationFile) Or Not FileExistsUTF8(ConversationFile) Then Exit;
  Lines := TStringList.Create;
  Try
    Try
      Lines.LoadFromFile(ConversationFile);
    Except
      Exit;
    End;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Data := Nil;
        Try
          Try
            Data := GetJSON(Lines[I]);
          Except
            Data := Nil;
          End;
          If Data Is TJSONObject Then
            Begin
              Obj := TJSONObject(Data);
              CollectAttachmentNames(Obj.Find('attachments'), Names);
              If Obj.Find('messages') Is TJSONArray Then
                CollectMessageAttachmentNames(TJSONArray(Obj.Find('messages')), Names);
            End;
        Finally
          Data.Free;
        End;
      End;
  Finally
    Lines.Free;
  End;
End;

Function NewImageNameList: TStringList;
Begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.CaseSensitive := True;
End;

Function CopyStoreImage(Const SourceDir, DestDir, FileName: String; Out ErrorText: String): Boolean;
Var
  SourcePath, DestPath: String;
  Size: Int64;
  Data: TBytes;
Begin
  Result := False;
  ErrorText := '';
  If Not ImageNameAllowed(FileName) Then
    Begin
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  SourcePath := IncludeTrailingPathDelimiter(SourceDir) + FileName;
  DestPath := IncludeTrailingPathDelimiter(DestDir) + FileName;
  If Not PathInside(SourceDir, SourcePath) Or Not PathInside(DestDir, DestPath) Then
    Begin
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  If FileIsSymlink(DestPath) Then
    Begin
      ErrorText := 'Refusing to copy an image through a symbolic link.';
      Exit;
    End;
  If FileIsSymlink(SourcePath) Then
    Begin
      Result := True;
      Exit;
    End;
  If Not FileExistsUTF8(SourcePath) Or DirectoryExistsUTF8(SourcePath) Then
    Begin
      Result := True;
      Exit;
    End;
  If FileExistsUTF8(DestPath) Then
    Begin
      Result := True;
      Exit;
    End;
  Size := FileSizeUTF8(SourcePath);
  If Not ReadOpenNoFollow(SourcePath, Size, Data, ErrorText) Then Exit;
  Result := WriteNewFile(DestPath, Data, ErrorText);
End;

Function EnsureImageDirectory(Const Directory: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  If Trim(Directory) = '' Then
    Begin
      ErrorText := 'Could not create the image store.';
      Exit;
    End;
  Result := EnsureRealDirectory(ExcludeTrailingPathDelimiter(Directory), ErrorText);
End;

Function PreserveAssistantImages(Const StoreDirectory, ArchiveId, ConversationFile: String; Out ErrorText: String;
  Const FallbackDirectory: String): Boolean;
Var
  Names: TStringList;
  DestDir, SourceDir, LiveDir, FallbackDir, SourcePath: String;
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  DestDir := ArchiveImagesDirectory(StoreDirectory, ArchiveId);
  If DestDir = '' Then
    Begin
      ErrorText := 'Invalid archive id.';
      Exit;
    End;
  If Not PathInside(StoreDirectory, ExcludeTrailingPathDelimiter(DestDir)) Then
    Begin
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  Names := NewImageNameList;
  Try
    CollectConversationImageNames(ConversationFile, Names);
    If Names.Count = 0 Then Exit(True);
    If Not EnsureImageDirectory(DestDir, ErrorText) Then Exit;
    LiveDir := StoreImagesDirectory(StoreDirectory);
    FallbackDir := StoreImagesDirectory(FallbackDirectory);
    For I := 0 To Names.Count - 1 Do
      Begin
        SourceDir := LiveDir;
        SourcePath := IncludeTrailingPathDelimiter(LiveDir) + Names[I];
        If (Not FileExistsUTF8(SourcePath) Or FileIsSymlink(SourcePath)) And (FallbackDir <> '') And
          (CompareFilenames(ExcludeTrailingPathDelimiter(FallbackDir), ExcludeTrailingPathDelimiter(LiveDir)) <> 0) Then
          SourceDir := FallbackDir;
        If Not CopyStoreImage(SourceDir, DestDir, Names[I], ErrorText) Then Exit;
      End;
    Result := True;
  Finally
    Names.Free;
  End;
End;

Function RestoreAssistantImages(Const StoreDirectory, ArchiveId, ConversationFile: String; Out ErrorText: String): Boolean;
Var
  Names: TStringList;
  SourceDir, LiveDir: String;
  I: Integer;
Begin
  Result := False;
  ErrorText := '';
  SourceDir := ArchiveImagesDirectory(StoreDirectory, ArchiveId);
  LiveDir := StoreImagesDirectory(StoreDirectory);
  If SourceDir = '' Then
    Begin
      ErrorText := 'Invalid archive id.';
      Exit;
    End;
  If Not DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(SourceDir)) Then Exit(True);
  If FileIsSymlink(ExcludeTrailingPathDelimiter(SourceDir)) Then
    Begin
      ErrorText := 'Refusing to read a symbolic link.';
      Exit;
    End;
  Names := NewImageNameList;
  Try
    CollectConversationImageNames(ConversationFile, Names);
    If Names.Count = 0 Then Exit(True);
    If Not EnsureImageDirectory(LiveDir, ErrorText) Then Exit;
    For I := 0 To Names.Count - 1 Do
      If Not CopyStoreImage(SourceDir, LiveDir, Names[I], ErrorText) Then Exit;
    Result := True;
  Finally
    Names.Free;
  End;
End;

Function AssistantArchiveImagesRecovered(Const StoreDirectory, ArchiveId, ConversationFile: String): Boolean;
Var
  Names: TStringList;
  SourceDir, LiveDir, SourcePath, LivePath: String;
  I: Integer;
Begin
  Result := False;
  SourceDir := ArchiveImagesDirectory(StoreDirectory, ArchiveId);
  LiveDir := StoreImagesDirectory(StoreDirectory);
  If SourceDir = '' Then Exit;
  If Not DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(SourceDir)) Then Exit(True);
  If FileIsSymlink(ExcludeTrailingPathDelimiter(SourceDir)) Then Exit;
  Names := NewImageNameList;
  Try
    CollectConversationImageNames(ConversationFile, Names);
    For I := 0 To Names.Count - 1 Do
      Begin
        SourcePath := IncludeTrailingPathDelimiter(SourceDir) + Names[I];
        LivePath := IncludeTrailingPathDelimiter(LiveDir) + Names[I];
        If FileIsSymlink(SourcePath) Or FileIsSymlink(LivePath) Then Exit;
        If FileExistsUTF8(SourcePath) And Not DirectoryExistsUTF8(SourcePath) Then
          If Not FileExistsUTF8(LivePath) Or DirectoryExistsUTF8(LivePath) Then Exit;
      End;
    Result := True;
  Finally
    Names.Free;
  End;
End;

Function DeleteAssistantImageArchive(Const StoreDirectory, ArchiveId: String; Out ErrorText: String): Boolean;
Var
  Directory, Path: String;
  Rec: TSearchRec;
  Code: Integer;
Begin
  Result := False;
  ErrorText := '';
  Directory := ExcludeTrailingPathDelimiter(ArchiveImagesDirectory(StoreDirectory, ArchiveId));
  If Directory = '' Then
    Begin
      ErrorText := 'Invalid archive id.';
      Exit;
    End;
  If Not PathInside(StoreDirectory, Directory) Then
    Begin
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  If Not DirectoryExistsUTF8(Directory) Then Exit(True);
  If FileIsSymlink(Directory) Then
    Begin
      ErrorText := 'Refusing to delete a symbolic link.';
      Exit;
    End;
  Code := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        If (Rec.Name <> '.') And (Rec.Name <> '..') Then
          Begin
            Path := IncludeTrailingPathDelimiter(Directory) + Rec.Name;
            If Not PathInside(Directory, Path) Then
              Begin
                ErrorText := 'Stored image path is outside the image store.';
                Exit;
              End;
            If (Rec.Attr And faDirectory) <> 0 Then
              Begin
                ErrorText := 'Could not delete the archived images.';
                Exit;
              End;
            If Not DeleteFileUTF8(Path) Then
              Begin
                ErrorText := 'Could not delete the archived images.';
                Exit;
              End;
          End;
        Code := FindNextUTF8(Rec);
      End;
  Finally
    FindCloseUTF8(Rec);
  End;
  If Not RemoveDir(Directory) Then
    Begin
      ErrorText := 'Could not delete the archived images.';
      Exit;
    End;
  Result := True;
End;

Function ReleaseUnreferencedAssistantImages(Const StoreDirectory: String; ConversationFiles: TStrings;
  Out ErrorText: String): Boolean;
Var
  Names: TStringList;
  Directory, Path: String;
  Rec: TSearchRec;
  Code, I: Integer;
Begin
  Result := False;
  ErrorText := '';
  Directory := ExcludeTrailingPathDelimiter(StoreImagesDirectory(StoreDirectory));
  If Directory = '' Then
    Begin
      ErrorText := 'No project root for the image store.';
      Exit;
    End;
  If Not DirectoryExistsUTF8(Directory) Then Exit(True);
  If FileIsSymlink(Directory) Then
    Begin
      ErrorText := 'Refusing to delete a symbolic link.';
      Exit;
    End;
  Names := NewImageNameList;
  Try
    If Assigned(ConversationFiles) Then
      For I := 0 To ConversationFiles.Count - 1 Do
        CollectConversationImageNames(ConversationFiles[I], Names);
    Code := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Rec);
    Try
      While Code = 0 Do
        Begin
          If (Rec.Name <> '.') And (Rec.Name <> '..') And ((Rec.Attr And faDirectory) = 0) And
            ImageNameAllowed(Rec.Name) And (Names.IndexOf(Rec.Name) < 0) Then
            Begin
              Path := IncludeTrailingPathDelimiter(Directory) + Rec.Name;
              If FileIsSymlink(Path) Then
                Begin
                  ErrorText := 'Refusing to delete a symbolic link.';
                  Exit;
                End;
              If Not DeleteFileUTF8(Path) Then
                Begin
                  ErrorText := 'Could not delete an unreferenced image.';
                  Exit;
                End;
            End;
          Code := FindNextUTF8(Rec);
        End;
    Finally
      FindCloseUTF8(Rec);
    End;
    Result := True;
  Finally
    Names.Free;
  End;
End;

Function ReleaseOrphanAssistantImageArchives(Const StoreDirectory: String; ConversationFiles: TStrings;
  Out ErrorText: String): Boolean;
Var
  Kept: TStringList;
  I, Code: Integer;
  Name, Id, Directory: String;
  Rec: TSearchRec;
Begin
  Result := False;
  ErrorText := '';
  Kept := TStringList.Create;
  Try
    Kept.Sorted := True;
    Kept.Duplicates := dupIgnore;
    If Assigned(ConversationFiles) Then
      For I := 0 To ConversationFiles.Count - 1 Do
        Begin
          Name := ExtractFileName(ConversationFiles[I]);
          If (Pos('.index.', LowerCase(Name)) > 0) Or Not SameText(ExtractFileExt(Name), '.jsonl') Then Continue;
          If Not SameText(Copy(Name, 1, Length('conversation-')), 'conversation-') Then Continue;
          Id := ChangeFileExt(Name, '');
          Delete(Id, 1, Length('conversation-'));
          If ArchiveIdAllowed(Id) Then Kept.Add(Id);
        End;
    Directory := ExcludeTrailingPathDelimiter(Trim(StoreDirectory));
    If (Directory = '') Or FileIsSymlink(Directory) Or Not DirectoryExistsUTF8(Directory) Then Exit(True);
    If Not PathInside(Directory, Directory) Then Exit(True);
    Code := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + 'images-*', faAnyFile, Rec);
    Try
      While Code = 0 Do
        Begin
          Id := '';
          If (Copy(Rec.Name, 1, Length('images-')) = 'images-') And ((Rec.Attr And faDirectory) <> 0) Then
            Id := Copy(Rec.Name, Length('images-') + 1, MaxInt);
          If ArchiveIdAllowed(Id) And (Kept.IndexOf(Id) < 0) Then
            If Not DeleteAssistantImageArchive(StoreDirectory, Id, ErrorText) Then Exit;
          Code := FindNextUTF8(Rec);
        End;
    Finally
      FindCloseUTF8(Rec);
    End;
    Result := True;
  Finally
    Kept.Free;
  End;
End;

Function AssistantImageDisplayPresent(Const StoreDirectory, ImageId, DisplayPath: String): Boolean;
Var
  Directory, FileName, ErrorText, Path, Id: String;
  Rec: TSearchRec;
  Code: Integer;
Begin
  Result := False;
  Directory := ExcludeTrailingPathDelimiter(StoreImagesDirectory(StoreDirectory));
  If (Directory = '') Or FileIsSymlink(Directory) Or Not DirectoryExistsUTF8(Directory) Then Exit;
  FileName := '';
  If StoredImageFileName(DisplayPath, FileName, ErrorText) And ImageNameAllowed(FileName) Then
    Begin
      Path := IncludeTrailingPathDelimiter(Directory) + FileName;
      If FileIsSymlink(Path) Or DirectoryExistsUTF8(Path) Then Exit;
      Exit(FileExistsUTF8(Path));
    End;
  Id := Trim(ImageId);
  If (Id = '') Or (Pos('/', Id) > 0) Or (Pos('\', Id) > 0) Then Exit;
  Code := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + Id + '.*', faAnyFile, Rec);
  Try
    While Code = 0 Do
      Begin
        Path := IncludeTrailingPathDelimiter(Directory) + Rec.Name;
        If Not FileIsSymlink(Path) And Not DirectoryExistsUTF8(Path) And FileExistsUTF8(Path) Then Exit(True);
        Code := FindNextUTF8(Rec);
      End;
  Finally
    FindCloseUTF8(Rec);
  End;
End;

Function ImagePathPrefix(Const ProjectRoot, ImageDirectory: String): String;
Var
  Root, Dir, Rel: String;
Begin
  Root := IncludeTrailingPathDelimiter(ProjectRootDir(ProjectRoot));
  Dir := IncludeTrailingPathDelimiter(ExpandFileNameUTF8(ExcludeTrailingPathDelimiter(ImageDirectory)));
  If (Root = '') Or (Length(Dir) < Length(Root)) Or (CompareFilenames(Copy(Dir, 1, Length(Root)), Root) <> 0) Then
    Result := AssistantStoreFolderName + '/' + AssistantImagesFolderName + '/'
  Else
    Begin
      Rel := Copy(Dir, Length(Root) + 1, MaxInt);
      Result := StringReplace(Rel, '\', '/', [rfReplaceAll]);
    End;
End;

Function EnsureStoreImages(Const ProjectRoot, StoreDirectory: String; Out Directory, ErrorText: String): Boolean;
Var
  Root, Store, Probe, Prefix, FileName: String;
Begin
  Result := False;
  Directory := '';
  ErrorText := '';
  Root := ProjectRootDir(ProjectRoot);
  Store := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(Trim(StoreDirectory)));
  If (Root = '') Or (Not DirectoryExistsUTF8(Root)) Or (Store = '') Or (Not DirectoryExistsUTF8(Store)) Then
    Begin
      ErrorText := 'No project root for the image store.';
      Exit;
    End;
  If Not PathInside(Root, Store) Then
    Begin
      ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  Probe := Root + PathDelim + AssistantStoreFolderName;
  If FileIsSymlink(Probe) Or FileIsSymlink(Store) Then
    Begin
      ErrorText := 'Refusing to store an image through a symbolic link.';
      Exit;
    End;
  Directory := IncludeTrailingPathDelimiter(Store) + AssistantImagesFolderName;
  If Not EnsureRealDirectory(ExcludeTrailingPathDelimiter(Directory), ErrorText) Then Exit;
  Directory := IncludeTrailingPathDelimiter(Directory);
  Prefix := ImagePathPrefix(Root, Directory);
  If Not StoredImageFileName(Prefix + 'a.png', FileName, ErrorText) Then
    Begin
      Directory := '';
      If ErrorText = '' Then ErrorText := 'Stored image path is outside the image store.';
      Exit;
    End;
  Result := True;
End;

Function EncodeBase64(Const Data: TBytes): String;
Const
  Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
Var
  I, N, OutPos, Value: Integer;
Begin
  N := Length(Data);
  SetLength(Result, ((N + 2) Div 3) * 4);
  OutPos := 1;
  I := 0;
  While I + 2 < N Do
    Begin
      Value := (Data[I] Shl 16) Or (Data[I + 1] Shl 8) Or Data[I + 2];
      Result[OutPos] := Alphabet[(Value Shr 18) And 63 + 1];
      Result[OutPos + 1] := Alphabet[(Value Shr 12) And 63 + 1];
      Result[OutPos + 2] := Alphabet[(Value Shr 6) And 63 + 1];
      Result[OutPos + 3] := Alphabet[Value And 63 + 1];
      Inc(OutPos, 4);
      Inc(I, 3);
    End;
  If I < N Then
    Begin
      Value := Data[I] Shl 16;
      If I + 1 < N Then Value := Value Or (Data[I + 1] Shl 8);
      Result[OutPos] := Alphabet[(Value Shr 18) And 63 + 1];
      Result[OutPos + 1] := Alphabet[(Value Shr 12) And 63 + 1];
      If I + 1 < N Then
        Result[OutPos + 2] := Alphabet[(Value Shr 6) And 63 + 1]
      Else
        Result[OutPos + 2] := '=';
      Result[OutPos + 3] := '=';
    End;
End;

Function LoadStoredAssistantImage(Const ProjectRoot, RelativePath: String; Out Img: TFPMemoryImage;
  Out ErrorText: String): Boolean;
Var
  Data: TBytes;
  Reader: TFPCustomImageReaderClass;
Begin
  Result := False;
  Img := Nil;
  ErrorText := '';
  If Not ReadStoredAssistantImage(ProjectRoot, RelativePath, Data, ErrorText) Then Exit;
  If Not FindReader(Data, Reader, ErrorText) Then Exit;
  Result := DecodeStillImage(Data, Reader, Img, ErrorText);
End;

Function AssistantImageDataUri(Const ProjectRoot: String; Const Ref: TAssistantImageRef; Out DataUri, ErrorText: String): Boolean;
Var
  Data: TBytes;
  Mime: String;
Begin
  Result := False;
  DataUri := '';
  ErrorText := '';
  SetLength(Data, 0);
  If Trim(Ref.UploadPath) = '' Then
    Begin
      ErrorText := 'Stored image is missing.';
      Exit;
    End;
  If Not ReadStoredAssistantImage(ProjectRoot, Ref.UploadPath, Data, ErrorText) Then Exit;
  If Length(Data) > AssistantImageUploadMaxBytes Then
    Begin
      SetLength(Data, 0);
      ErrorText := 'Image could not be reduced below 4 MiB for upload.';
      Exit;
    End;
  Mime := Trim(Ref.UploadMime);
  If Mime = '' Then Mime := 'image/png';
  If (Pos('data:', LowerCase(Mime)) > 0) Or (Pos('base64', LowerCase(Mime)) > 0) Or (Pos(#10, Mime) > 0) Then
    Begin
      SetLength(Data, 0);
      ErrorText := 'Image could not be prepared for upload.';
      Exit;
    End;
  DataUri := 'data:' + Mime + ';base64,' + EncodeBase64(Data);
  SetLength(Data, 0);
  Result := DataUri <> '';
End;

Function AssistantImageOmittedNote(Const Ref: TAssistantImageRef): String;
Begin
  Result := AssistantImageOmittedPrefix + ' ' + AssistantImageFileLabel(Ref);
  If (Ref.Width > 0) And (Ref.Height > 0) Then
    Result := Result + ', ' + IntToStr(Ref.Width) + 'x' + IntToStr(Ref.Height);
  Result := Result + ']';
End;

Function AssistantImageModelText(Const UserText: String; ImageCount: Integer): String;
Begin
  If (Trim(UserText) = '') And (ImageCount > 0) Then
    Result := AssistantImageLookText
  Else
    Result := UserText;
End;

Function AssistantRequestRejectedImage(Const ErrorText: String): Boolean;
Var
  S: String;
Begin
  S := LowerCase(ErrorText);
  Result := (Pos('does not support image', S) > 0) Or (Pos('do not support image', S) > 0) Or
    (Pos('doesn''t support image', S) > 0) Or (Pos('images are not supported', S) > 0) Or
    (Pos('image input is not', S) > 0) Or (Pos('image_url is not supported', S) > 0) Or
    (Pos('unsupported image', S) > 0) Or (Pos('invalid image', S) > 0) Or (Pos('rejected the image', S) > 0) Or
    (Pos('rejected image', S) > 0) Or ((Pos('image content', S) > 0) And (Pos('not supported', S) > 0)) Or
    ((Pos('input_image', S) > 0) And ((Pos('invalid', S) > 0) Or (Pos('unsupported', S) > 0) Or (Pos('reject', S) > 0))) Or
    ((Pos('modalit', S) > 0) And (Pos('image', S) > 0));
End;

Function DeleteOneStoredFile(Const ProjectRoot, RelativePath: String; Out ErrorText: String): Boolean;
Var
  FullPath: String;
Begin
  Result := True;
  ErrorText := '';
  If Trim(RelativePath) = '' Then Exit;
  If Not ResolveStoredAssistantImage(ProjectRoot, RelativePath, FullPath, ErrorText) Then Exit(False);
  If Not FileExistsUTF8(FullPath) Then Exit;
  If FileIsSymlink(FullPath) Or DirectoryExistsUTF8(FullPath) Then
    Begin
      ErrorText := 'Refusing to delete a symbolic link.';
      Exit(False);
    End;
  Result := DeleteFileUTF8(FullPath);
  If Not Result Then ErrorText := 'Could not delete the image.';
End;

Function DeleteStoredAssistantImage(Const ProjectRoot: String; Const Ref: TAssistantImageRef; Out ErrorText: String): Boolean;
Begin
  Result := DeleteOneStoredFile(ProjectRoot, Ref.DisplayPath, ErrorText);
  If Result Then Result := DeleteOneStoredFile(ProjectRoot, Ref.UploadPath, ErrorText);
End;

Function StoreAssistantImageStreamInStore(Const ProjectRoot, StoreDirectory, OriginalName: String; Stream: TStream;
  Out Stored: TAssistantStoredImage; Out ErrorText: String): Boolean;
Var
  Data: TBytes;
Begin
  ClearStored(Stored);
  Result := False;
  ErrorText := '';
  Try
    If Not CopyLimitedStream(Stream, Data, ErrorText) Then Exit;
    Result := StorePrepared(ProjectRoot, StoreDirectory, OriginalName, Data, Stored, ErrorText);
    If Not Result Then ClearStored(Stored);
  Except
    ClearStored(Stored);
    Result := False;
    If ErrorText = '' Then ErrorText := 'Image could not be stored.';
  End;
End;

Function StoreAssistantImageInStore(Const ProjectRoot, StoreDirectory, SourcePath: String; Out Stored: TAssistantStoredImage;
  Out ErrorText: String): Boolean;
Var
  Data: TBytes;
Begin
  ClearStored(Stored);
  Result := False;
  ErrorText := '';
  Try
    If Not ReadAcceptedFile(SourcePath, Data, ErrorText) Then Exit;
    Result := StorePrepared(ProjectRoot, StoreDirectory, SourcePath, Data, Stored, ErrorText);
    If Not Result Then ClearStored(Stored);
  Except
    ClearStored(Stored);
    Result := False;
    If ErrorText = '' Then ErrorText := 'Image could not be stored.';
  End;
End;

Function LimitAssistantImageRefs(Const Refs: TAssistantImageRefArray): TAssistantImageRefArray;
Var
  Count, I: Integer;
Begin
  Result := Nil;
  Count := Length(Refs);
  If Count > AssistantImageMaxAttachments Then Count := AssistantImageMaxAttachments;
  SetLength(Result, Count);
  For I := 0 To Count - 1 Do Result[I] := Refs[I];
End;

ThreadVar
  ToolImageRefs: TAssistantImageRefArray;

Procedure NoteThreadToolImages(Const Refs: TAssistantImageRefArray);
Var
  I: Integer;
Begin
  SetLength(ToolImageRefs, Length(Refs));
  For I := 0 To High(Refs) Do ToolImageRefs[I] := Refs[I];
End;

Function TakeThreadToolImages(Out Refs: TAssistantImageRefArray): Boolean;
Var
  I: Integer;
Begin
  SetLength(Refs, Length(ToolImageRefs));
  For I := 0 To High(ToolImageRefs) Do Refs[I] := ToolImageRefs[I];
  SetLength(ToolImageRefs, 0);
  Result := Length(Refs) > 0;
End;

Initialization
  ImageHandlers.RegisterImageReader('Icon', 'ico', TAssistantIcoReader);

End.
