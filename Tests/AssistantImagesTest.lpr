Program AssistantImagesTest;

{ Store limits, symlink refusal, and turn JSON without image bytes (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  BaseUnix,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpimage, fpwritepng, AssistantImages, AssistantConversation, AssistantProjectPaths,
  AssistantRecap;

Type
  { Reports a size over 8 MiB. A read means the size gate did not run first. }
  TOversizeStream = Class(TStream)
    PositionAt: Int64;
    Reads: Integer;
    Function Read(Var Buffer; Count: LongInt): LongInt; Override;
    Function Write(Const Buffer; Count: LongInt): LongInt; Override;
    Function Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64; Override;
  End;

Var
  FailCount: Integer;
  Root: String;
  Stored: TAssistantStoredImage;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Function TOversizeStream.Read(Var Buffer; Count: LongInt): LongInt;
Begin
  Inc(Reads);
  Result := 0;
End;

Function TOversizeStream.Write(Const Buffer; Count: LongInt): LongInt;
Begin
  Result := 0;
End;

Function TOversizeStream.Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64;
Begin
  Case Origin Of
    soBeginning: PositionAt := Offset;
    soCurrent: PositionAt := PositionAt + Offset;
    soEnd: PositionAt := Int64(AssistantImageMaxFileBytes) + 1 + Offset;
  Else
    PositionAt := 0;
  End;
  Result := PositionAt;
End;

Procedure PutBe32(Var Data: TBytes; Index: Integer; Value: Cardinal);
Begin
  Data[Index] := Byte((Value Shr 24) And $FF);
  Data[Index + 1] := Byte((Value Shr 16) And $FF);
  Data[Index + 2] := Byte((Value Shr 8) And $FF);
  Data[Index + 3] := Byte(Value And $FF);
End;

Function PngCrc(Const Data: TBytes; StartAt, Count: Integer): Cardinal;
Var
  Table: Array[0..255] Of Cardinal;
  I, J, N: Integer;
  C: Cardinal;
Begin
  For I := 0 To 255 Do
    Begin
      C := Cardinal(I);
      For J := 0 To 7 Do
        If (C And 1) <> 0 Then
          C := Cardinal($EDB88320) Xor (C Shr 1)
        Else
          C := C Shr 1;
      Table[I] := C;
    End;
  Result := $FFFFFFFF;
  For N := 0 To Count - 1 Do
    Result := Table[(Result Xor Data[StartAt + N]) And $FF] Xor (Result Shr 8);
  Result := Result Xor $FFFFFFFF;
End;

{ Signature plus an IHDR whose width is over 16384. No pixel data, so a decode would fail differently. }
Function OversizedHeaderPng: TBytes;
Var
  Crc: Cardinal;
Begin
  SetLength(Result, 33);
  Result[0] := 137;
  Result[1] := 80;
  Result[2] := 78;
  Result[3] := 71;
  Result[4] := 13;
  Result[5] := 10;
  Result[6] := 26;
  Result[7] := 10;
  PutBe32(Result, 8, 13);
  Result[12] := Ord('I');
  Result[13] := Ord('H');
  Result[14] := Ord('D');
  Result[15] := Ord('R');
  PutBe32(Result, 16, 20000);
  PutBe32(Result, 20, 1);
  Result[24] := 8;
  Result[25] := 2;
  Result[26] := 0;
  Result[27] := 0;
  Result[28] := 0;
  Crc := PngCrc(Result, 12, 17);
  PutBe32(Result, 29, Crc);
End;

Procedure WritePng(Const FileName: String; Width, Height: Integer);
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Stream: TFileStream;
  X, Y: Integer;
  Pixel: TFPColor;
Begin
  Img := TFPMemoryImage.Create(Width, Height);
  Writer := TFPWriterPNG.Create;
  Stream := TFileStream.Create(FileName, fmCreate);
  Try
    Pixel.Red := $FFFF;
    Pixel.Green := 0;
    Pixel.Blue := 0;
    Pixel.Alpha := $FFFF;
    For Y := 0 To Height - 1 Do
      For X := 0 To Width - 1 Do
        Img.Colors[X, Y] := Pixel;
    Img.SaveToStream(Stream, Writer);
  Finally
    Stream.Free;
    Writer.Free;
    Img.Free;
  End;
End;

Procedure DeleteTree(Const Path: String);
Var
  Search: TSearchRec;
  Child: String;
Begin
  If FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, Search) = 0 Then
    Begin
      Repeat
        If (Search.Name = '.') Or (Search.Name = '..') Then Continue;
        Child := IncludeTrailingPathDelimiter(Path) + Search.Name;
        If (Search.Attr And faDirectory) <> 0 Then
          DeleteTree(Child)
        Else
          DeleteFile(Child);
      Until FindNext(Search) <> 0;
      FindClose(Search);
    End;
  RemoveDir(Path);
End;

Procedure TestOversizeBeforeRead(Const Root: String);
Var
  Stream: TOversizeStream;
  FileStream: TFileStream;
  Stored: TAssistantStoredImage;
  ErrorText, HugePath: String;
Begin
  Stream := TOversizeStream.Create;
  Try
    Check('oversize stream rejected', Not StoreAssistantImageFromStream(Root, 'huge.png', Stream, Stored, ErrorText));
    Check('oversize stream names the limit', Pos('8 MiB', ErrorText) > 0);
    Check('oversize stream is not read', Stream.Reads = 0);
    Check('oversize stream stores nothing', Stored.Id = '');
  Finally
    Stream.Free;
  End;
  HugePath := IncludeTrailingPathDelimiter(Root) + 'huge.bin';
  FileStream := TFileStream.Create(HugePath, fmCreate);
  Try
    FileStream.Size := Int64(AssistantImageMaxFileBytes) + 1;
  Finally
    FileStream.Free;
  End;
  Check('oversize file rejected before a full read',
    Not StoreAssistantImageFromFile(Root, HugePath, Stored, ErrorText) And (Pos('8 MiB', ErrorText) > 0) And
    (Stored.Id = ''));
  DeleteFile(HugePath);
End;

Procedure TestDimensionBeforeDecode(Const Root: String);
Var
  Bytes: TBytes;
  Stream: TBytesStream;
  Stored: TAssistantStoredImage;
  ErrorText: String;
Begin
  Bytes := OversizedHeaderPng;
  Stream := TBytesStream.Create(Bytes);
  Try
    Check('oversized header is tiny', Length(Bytes) < 64);
    Check('dimension reject before decode', Not StoreAssistantImageFromStream(Root, 'wide.png', Stream, Stored, ErrorText));
    Check('dimension reject names the side limit', Pos('16384', ErrorText) > 0);
    Check('dimension reject is not a decode failure', Pos('could not be decoded', ErrorText) = 0);
    Check('dimension reject stores nothing', Stored.Id = '');
  Finally
    Stream.Free;
  End;
End;

Procedure TestPngRoundTrip(Const Root: String; Out Stored: TAssistantStoredImage);
Var
  SourcePath, ErrorText, JsonText: String;
  Loaded: TFPMemoryImage;
  Data: TBytes;
  Ref: TAssistantImageRef;
  Refs: TAssistantImageRefArray;
Begin
  SourcePath := IncludeTrailingPathDelimiter(Root) + 'sample.png';
  WritePng(SourcePath, 4, 3);
  Check('png stored', StoreAssistantImageFromFile(Root, SourcePath, Stored, ErrorText) And (Stored.Id <> '') And
    (Stored.Width = 4) And (Stored.Height = 3));
  Check('png read back', ReadStoredAssistantImage(Root, Stored.DisplayRelativePath, Data, ErrorText) And (Length(Data) > 8));
  Check('png reloads the same size', LoadStoredAssistantImage(Root, Stored.DisplayRelativePath, Loaded, ErrorText));
  If Assigned(Loaded) Then
    Begin
      Check('png reload width', Loaded.Width = 4);
      Check('png reload height', Loaded.Height = 3);
      Loaded.Free;
    End
  Else
    Begin
      Check('png reload width', False);
      Check('png reload height', False);
    End;
  Ref := ImageRefFromStored(Stored);
  SetLength(Refs, 1);
  Refs[0] := Ref;
  JsonText := AssistantImageRefsToJson(Refs);
  Check('stored ref keeps the id', Pos(Stored.Id, JsonText) > 0);
  Check('stored ref has no base64', (Pos('base64', JsonText) = 0) And (Pos('data:', JsonText) = 0));
End;

Procedure TestStoredPaths(Const Root: String);
Const
  Ordinary = '.assistant/images/a.png';
  Target = '.assistant/targets/demo/images/a.png';

  Procedure CheckPath(Const Input, Expected: String);
  Var
    FullPath, ErrorText: String;
    Accepted: Boolean;
  Begin
    Accepted := ResolveStoredAssistantImage(Root, Input, FullPath, ErrorText);
    If Expected = '' Then
      Check('reject invalid stored path', (Not Accepted) And (FullPath = '') And (ErrorText <> ''))
    Else
      Check('resolve ' + Expected, Accepted And (FullPath = IncludeTrailingPathDelimiter(Root) +
        StringReplace(Expected, '/', PathDelim, [rfReplaceAll])));
  End;

Begin
  CheckPath(Ordinary, Ordinary);
  CheckPath('.assistant/images/../a.png', '');
  CheckPath(Target, Target);
  CheckPath('.assistant/targets/demo/sub/images/a.png', '');
  CheckPath('  \.assistant/targets\demo/images\a.png  ', Target);
  CheckPath('.assistant\images/a.png\extra', '');
  CheckPath(StringOfChar('/', 8192) + Ordinary, Ordinary);
  CheckPath(StringOfChar('/', 8192), '');
End;

Procedure TestSymlinkRefusal(Const Root: String; Const Stored: TAssistantStoredImage);
Var
  FullPath, ErrorText, Decoy: String;
  Data: TBytes;
{$IFDEF UNIX}
  Linked: Boolean;
{$ENDIF}
Begin
  Check('resolve stored display', ResolveStoredAssistantImage(Root, Stored.DisplayRelativePath, FullPath, ErrorText));
  If FullPath = '' Then
    Begin
      Check('symlink read refused', False);
      Exit;
    End;
  Decoy := IncludeTrailingPathDelimiter(Root) + 'decoy.txt';
  With TStringList.Create Do
    Try
      Add('not an image');
      SaveToFile(Decoy);
    Finally
      Free;
    End;
  DeleteFile(FullPath);
  {$IFDEF UNIX}
  Linked := fpSymlink(PChar(Decoy), PChar(FullPath)) = 0;
  Check('symlink planted', Linked);
  If Not Linked Then Exit;
  Check('symlink read refused', Not ReadStoredAssistantImage(Root, Stored.DisplayRelativePath, Data, ErrorText) And
    (Pos('symbolic link', ErrorText) > 0));
  Check('symlink was not followed into bytes', Length(Data) = 0);
  {$ELSE}
  WriteLn('skip symlink refusal (not Unix)');
  {$ENDIF}
End;

Procedure TestTurnJsonRoundTrip(Const Root: String; Const Stored: TAssistantStoredImage);
Var
  Store: TAssistantConversationStore;
  Turn, Loaded: TConversationTurn;
  Entry: TConversationIndexEntry;
  Refs: TAssistantImageRefArray;
  Parsed: TAssistantImageRefArray;
  Lines: TStringList;
  ConvPath: String;
Begin
  SetLength(Refs, 1);
  Refs[0] := ImageRefFromStored(Stored);
  Turn := Default(TConversationTurn);
  Turn.Id := 'turn-image-1';
  Turn.Mode := 'inspect';
  Turn.Prompt := 'See the diagram';
  Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(Root);
    Check('image turn appended', Store.AppendTurn(Turn, Entry) And Assigned(Entry));
  Finally
    Store.Free;
  End;
  ConvPath := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName + PathDelim + AssistantConversationFileName;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(ConvPath);
    Check('turn file contains the id', (Stored.Id <> '') And (Pos(Stored.Id, Lines.Text) > 0));
    Check('turn file has no base64', Pos('base64', Lines.Text) = 0);
  Finally
    Lines.Free;
  End;
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(Root);
    Check('turn reloads', Store.Load And Store.GetTurn(0, Loaded));
    Check('reloaded turn keeps the id', ParseAssistantImageRefs(Loaded.AttachmentsJson, Parsed) And (Length(Parsed) = 1) And
      (Parsed[0].Id = Stored.Id));
    Check('reloaded attachments have no base64', Pos('base64', Loaded.AttachmentsJson) = 0);
  Finally
    Store.Free;
  End;
End;

Function Filled(Ch: Char; Count: Integer): String;
Begin
  SetLength(Result, Count);
  If Count > 0 Then
    FillChar(Result[1], Count, Ch);
End;

Procedure TestRecapBuilder(Const Root: String; Const Stored: TAssistantStoredImage);
Var
  Store: TAssistantConversationStore;
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Current, Refs: TAssistantImageRefArray;
  Recap: String;
  OneTurn: String;
Begin
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(Root);
    Turn := Default(TConversationTurn);
    Turn.Model := 'recap-model';
    Turn.Prompt := 'OLD-MARKER' + Filled('O', AssistantRecapUserChars);
    Turn.Response := Filled('X', AssistantRecapAnswerChars);
    Turn.AttachmentsJson := '[{"id":"missing-old","name":"gone.png"}]';
    Check('old recap turn stored', Store.AppendTurn(Turn, Entry));
    Turn := Default(TConversationTurn);
    Turn.Model := 'recap-model';
    Turn.Prompt := Filled('A', AssistantRecapUserChars);
    Turn.Response := Filled('B', AssistantRecapAnswerChars);
    SetLength(Refs, 1);
    Refs[0] := ImageRefFromStored(Stored);
    Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
    Check('included recap turn stored', Store.AppendTurn(Turn, Entry));
    Turn := Default(TConversationTurn);
    Turn.Model := 'recap-model';
    Turn.Prompt := 'NEW-MARKER' + Filled('C', AssistantRecapUserChars);
    Turn.Response := Filled('D', AssistantRecapAnswerChars);
    Turn.AttachmentsJson := '[{"id":"missing-new","name":"gone.png"}]';
    Check('newest recap turn stored', Store.AppendTurn(Turn, Entry));
    Turn := Default(TConversationTurn);
    Turn.Model := 'other-model';
    Turn.Prompt := 'OTHER-MODEL';
    Turn.Response := 'no';
    Check('other model stored', Store.AppendTurn(Turn, Entry));
    SetLength(Current, 0);
    AssistantBuildRecap(Store, Root, 'recap-model', Current, True, AssistantImageMaxAttachments, Recap, Refs);
    OneTurn := 'User: ' + Filled('A', AssistantRecapUserChars) + LineEnding +
      'Assistant: ' + Filled('B', AssistantRecapAnswerChars) + LineEnding;
    Check('recap keeps the two newest turns', (Pos('NEW-MARKER', Recap) > 0) And (Pos(OneTurn, Recap) > 0));
    Check('recap drops the turn past the cap', Pos('OLD-MARKER', Recap) = 0);
    Check('recap drops another model', Pos('OTHER-MODEL', Recap) = 0);
    Check('recap re-attaches the included picture', (Length(Refs) = 1) And (Refs[0].Id = Stored.Id));
    Check('recap skips a missing picture', Pos('missing-old', AssistantImageRefsToJson(Refs)) = 0);
    SetLength(Current, 1);
    Current[0] := ImageRefFromStored(Stored);
    AssistantBuildRecap(Store, Root, 'recap-model', Current, False, 1, Recap, Refs);
    Check('a session does not re-attach older pictures', (Length(Refs) = 1) And (Refs[0].Id = Stored.Id));
    Check('empty recap leaves the submit text', AssistantRecapPrompt('', 'now') = 'now');
    Check('recap heading is shared', Pos('Previous conversation (bounded recap):', AssistantRecapPrompt(Recap, 'now')) = 1);
  Finally
    Store.Free;
  End;
End;

Procedure TestArchiveCopy(Const Root: String; Const Stored: TAssistantStoredImage);
Const
  ArchiveId = '20261119T120000';
Var
  StoreDir, Conversation, SourcePath, CopyPath, ErrorText: String;
  SourceBytes, ArchivedBytes: TMemoryStream;
Begin
  StoreDir := IncludeTrailingPathDelimiter(Root) + AssistantStoreFolderName;
  Conversation := StoreDir + PathDelim + AssistantConversationFileName;
  SourcePath := IncludeTrailingPathDelimiter(Root) + Stored.DisplayRelativePath;
  CopyPath := StoreDir + PathDelim + 'images-' + ArchiveId + PathDelim + ExtractFileName(SourcePath);
  Check('archive copies stored images', PreserveAssistantImages(StoreDir, ArchiveId, Conversation, ErrorText));
  Check('archived image exists', FileExists(CopyPath));
  If Not FileExists(CopyPath) Then Exit;
  SourceBytes := TMemoryStream.Create;
  ArchivedBytes := TMemoryStream.Create;
  Try
    SourceBytes.LoadFromFile(SourcePath);
    ArchivedBytes.LoadFromFile(CopyPath);
    Check('archive preserves image bytes', (SourceBytes.Size > 0) And (SourceBytes.Size = ArchivedBytes.Size) And
      CompareMem(SourceBytes.Memory, ArchivedBytes.Memory, SourceBytes.Size));
  Finally
    ArchivedBytes.Free;
    SourceBytes.Free;
  End;
  {$IFDEF UNIX}
  Check('replace archived copy with symlink', DeleteFile(CopyPath) And (fpSymlink(PChar(SourcePath), PChar(CopyPath)) = 0));
  Check('archive refuses destination symlink', Not PreserveAssistantImages(StoreDir, ArchiveId, Conversation, ErrorText) And
    (Pos('symbolic link', ErrorText) > 0));
  {$ENDIF}
End;

Begin
  FailCount := 0;
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-images-test-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Root);
  Try
    TestOversizeBeforeRead(Root);
    TestDimensionBeforeDecode(Root);
    TestPngRoundTrip(Root, Stored);
    TestTurnJsonRoundTrip(Root, Stored);
    TestRecapBuilder(Root, Stored);
    TestArchiveCopy(Root, Stored);
    TestStoredPaths(Root);
    TestSymlinkRefusal(Root, Stored);
  Finally
    DeleteTree(Root);
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantImages tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantImages test(s) failed.');
      Halt(1);
    End;
End.
