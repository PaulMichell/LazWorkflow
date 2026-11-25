Unit AssistantMonitorImages;

{ Display-file responses for GET /v4/images/id (c) 2026 Michell Computing.

  The file is found the way AssistantImageDisplayPresent finds an id, which is
  the display file RemoteImage reads. The bytes are streamed. This unit does not
  take the pulse lock or the conversation cache lock while the file is open. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs;

Const
  MonitorImageMaxBytes = 1048576;

Procedure SetMonitorImageReadGate(Entered, ReleaseGate: PRTLEvent);
Function ReadMonitorDisplayImage(Const ImageId: String; Out Status: Integer; Out Mime: String; Out Data: TBytes;
  Out ErrorBody: String): Boolean;
Function OpenMonitorDisplayImage(Const ImageId: String; Out ImageStream: TStream; Out Mime: String; Out Status: Integer;
  Out ErrorBody: String): Boolean;

Implementation

Uses
  LazFileUtils, AssistantProjectPaths, AssistantImages, AssistantMonitorStore;

Var
  ReadEntered, ReadRelease: PRTLEvent;

Function ErrorJson(Const Reason, MessageText: String): String;
Begin
  Result := '{"reason":"' + Reason + '","message":"' + MessageText + '"}';
End;

Function MimeForName(Const FileName: String): String;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(FileName));
  If Ext = '.png' Then
    Result := 'image/png'
  Else If (Ext = '.jpg') Or (Ext = '.jpeg') Then
    Result := 'image/jpeg'
  Else If Ext = '.gif' Then
    Result := 'image/gif'
  Else If Ext = '.bmp' Then
    Result := 'image/bmp'
  Else If Ext = '.webp' Then
    Result := 'image/webp'
  Else
    Result := 'application/octet-stream';
End;

Function ImageIdAllowed(Const ImageId: String): Boolean;
Var
  Index: Integer;
  C: Char;
Begin
  Result := (ImageId <> '') And (Pos('/', ImageId) = 0) And (Pos('\', ImageId) = 0) And (Pos('..', ImageId) = 0);
  If Not Result Then
    Exit;
  For Index := 1 To Length(ImageId) Do
    Begin
      C := ImageId[Index];
      Result := ((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'z')) Or ((C >= 'A') And (C <= 'Z')) Or (C = '-');
      If Not Result Then
        Exit;
    End;
End;

Function FindDisplayFile(Const ImagesDir, ImageId: String; Out FullPath: String): Boolean;
Const
  DisplayExtensions: Array[0..4] Of String = ('.png', '.jpg', '.jpeg', '.gif', '.bmp');
Var
  Index: Integer;
  Info: TSearchRec;
  Path: String;
Begin
  Result := False;
  FullPath := '';
  For Index := 0 To High(DisplayExtensions) Do
    Begin
      Path := IncludeTrailingPathDelimiter(ImagesDir) + ImageId + DisplayExtensions[Index];
      If FileExistsUTF8(Path) And (Not FileIsSymlink(Path)) And (Not DirectoryExistsUTF8(Path)) Then
        Begin
          FullPath := Path;
          Exit(True);
        End;
    End;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(ImagesDir) + ImageId + '.*', faAnyFile, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If (Info.Name = '.') Or (Info.Name = '..') Then
        Continue;
      If Pos('-upload.', LowerCase(Info.Name)) > 0 Then
        Continue;
      Path := IncludeTrailingPathDelimiter(ImagesDir) + Info.Name;
      If FileIsSymlink(Path) Or DirectoryExistsUTF8(Path) Or (Not FileExistsUTF8(Path)) Then
        Continue;
      FullPath := Path;
      Result := True;
      Exit;
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
  End;
End;

Function LocateDisplayFile(Const ImageId: String; Out FullPath, Mime: String; Out Status: Integer;
  Out ErrorBody: String): Boolean;
Var
  Directory, ImagesDir: String;
  Size: Int64;
Begin
  Result := False;
  FullPath := '';
  Mime := '';
  Status := 404;
  ErrorBody := ErrorJson('not_found', 'That image is not in the store.');
  If Not ImageIdAllowed(ImageId) Then
    Exit;
  Directory := MonitorAssistantDirectory;
  If Directory = '' Then
    Exit;
  ImagesDir := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Directory)) + AssistantImagesFolderName + PathDelim;
  If (ImagesDir = '') Or FileIsSymlink(ExcludeTrailingPathDelimiter(ImagesDir)) Or (Not DirectoryExistsUTF8(ImagesDir)) Then
    Exit;
  If Not FindDisplayFile(ImagesDir, ImageId, FullPath) Then
    Exit;
  If Not AssistantImageDisplayPresent(Directory, ImageId,
    AssistantStoreFolderName + '/' + AssistantImagesFolderName + '/' + ExtractFileName(FullPath)) Then
    Begin
      FullPath := '';
      Exit;
    End;
  Size := FileSizeUTF8(FullPath);
  If Size > MonitorImageMaxBytes Then
    Begin
      Status := 413;
      ErrorBody := ErrorJson('too_large', 'That image is larger than 1 MiB.');
      FullPath := '';
      Exit;
    End;
  Mime := MimeForName(FullPath);
  Status := 200;
  ErrorBody := '';
  Result := True;
End;

Procedure WaitReadGate;
Begin
  If Assigned(ReadEntered) Then
    RTLEventSetEvent(ReadEntered);
  If Assigned(ReadRelease) Then
    RTLEventWaitFor(ReadRelease, 10000);
End;

Function OpenMonitorDisplayImage(Const ImageId: String; Out ImageStream: TStream; Out Mime: String; Out Status: Integer;
  Out ErrorBody: String): Boolean;
Var
  FullPath: String;
Begin
  ImageStream := Nil;
  Result := LocateDisplayFile(ImageId, FullPath, Mime, Status, ErrorBody);
  If Not Result Then
    Exit;
  WaitReadGate;
  Try
    ImageStream := TFileStream.Create(FullPath, fmOpenRead Or fmShareDenyNone);
  Except
    Status := 404;
    ErrorBody := ErrorJson('not_found', 'That image is not in the store.');
    Mime := '';
    Result := False;
  End;
End;

Function ReadMonitorDisplayImage(Const ImageId: String; Out Status: Integer; Out Mime: String; Out Data: TBytes;
  Out ErrorBody: String): Boolean;
Var
  ImageStream: TStream;
Begin
  Data := Nil;
  SetLength(Data, 0);
  Result := OpenMonitorDisplayImage(ImageId, ImageStream, Mime, Status, ErrorBody);
  If Not Result Then
    Exit;
  Try
    SetLength(Data, ImageStream.Size);
    If Length(Data) > 0 Then
      ImageStream.ReadBuffer(Data[0], Length(Data));
  Finally
    ImageStream.Free;
  End;
End;

Procedure SetMonitorImageReadGate(Entered, ReleaseGate: PRTLEvent);
Begin
  ReadEntered := Entered;
  ReadRelease := ReleaseGate;
End;

End.
