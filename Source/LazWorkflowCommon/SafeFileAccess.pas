Unit SafeFileAccess;

{ Opens and publishes files without following a final symlink or replacing an existing entry.

  The LCL has no call for that. Unix and Darwin share the POSIX arm. Windows uses
  CreateFile and MoveFileEx. A host that cannot meet a contract returns false and
  the existing error text. This unit does not fall back to TFileStream. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, Classes;

/// True only where the atomic no-follow publish is implemented.
Function CanCreateNewText: Boolean;
/// Rejects absolute paths, '..', and symlinks. Publishes with linkat so an existing entry is not replaced.
Function CreateNewText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
/// Reads exactly ExpectedSize bytes without following a final symlink. Image-store errors are preserved.
Function ReadAllNoFollow(Const Path: String; ExpectedSize: Int64; Out Data: TBytes; Out ErrorText: String): Boolean;
/// Creates a new file and writes Data. An existing entry, including a symlink, is not replaced.
Function CreateExclusiveNoFollow(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
/// Unix mode 0600. Windows has no mode bits and returns true.
Function ProtectOwnerOnlyFile(Const Path: String): Boolean;
/// Unix mode 0700. Windows has no mode bits and returns true.
Function ProtectOwnerOnlyDirectory(Const Path: String): Boolean;
/// True when the path is a regular file of at most MaxBytes. MaxBytes below zero skips the size test.
/// fpStat follows a symlink to a regular file; this function does the same.
Function IsRegularFile(Const Path: String; MaxBytes: Int64): Boolean;
/// Safe-file existence test. True for any entry, including a dangling symlink. The final component is not followed.
Function PathEntryExists(Const Path: String): Boolean;
/// Exclusive create for the Git config lock. ErrorText is the OS message. Caller closes Handle with FileClose.
Function TryExclusiveCreate(Const Path: String; Out Handle: THandle; Out ErrorText: String): Boolean;
/// Replaces DestinationPath with the exclusive file. Caller closes any handle on SourcePath first.
Function ReplaceWithExclusiveFile(Const SourcePath, DestinationPath: String; Out ErrorText: String): Boolean;
/// Git null-device argument: NUL on Windows, /dev/null elsewhere. Not a file to open.
Function NullDevicePath: String;

Implementation

{$IFDEF UNIX}
Uses
  BaseUnix, Unix{$IFDEF LINUX}, Linux{$ENDIF};
{$ENDIF}
{$IFDEF WINDOWS}
Uses
  Windows;
{$ENDIF}

Const
  ImageStoreMaxBytes = 8 * 1024 * 1024;
  NewTextMaxBytes = 1048576;
  NewTextMaxPathBytes = 4096;
  NewTextMaxDepth = 64;
  ImageReadError = 'Stored image could not be read.';
  ImageReadSymlinkError = 'Refusing to read a symbolic link.';
  ImageWriteError = 'Could not store the image.';
  ImageWriteSymlinkError = 'Refusing to store an image through a symbolic link.';
  NewTextUnsupportedError = 'New project file creation is currently supported on Linux only.';
  RestoreConfigError = 'Could not restore repository config';

{$IFDEF UNIX}
Function OpenAt(Dir: LongInt; Name: PChar; Flags: LongInt; Mode: Cardinal): LongInt; Cdecl; External 'c' Name 'openat';
Function MkdirAt(Dir: LongInt; Name: PChar; Mode: Cardinal): LongInt; Cdecl; External 'c' Name 'mkdirat';
Function LinkAt(OldDir: LongInt; OldName: PChar; NewDir: LongInt; NewName: PChar; Flags: LongInt): LongInt; Cdecl; External 'c' Name 'linkat';
Function UnlinkAt(Dir: LongInt; Name: PChar; Flags: LongInt): LongInt; Cdecl; External 'c' Name 'unlinkat';

Function DirectoryOpenFlag: cint;
Begin
  {$IF DECLARED(O_DIRECTORY)}
  Result := O_DIRECTORY;
  {$ELSE}
    {$IFDEF DARWIN}
    Result := $100000;
    {$ELSE}
    Result := 0;
    {$ENDIF}
  {$ENDIF}
End;

Function NoFollowOpenFlag: cint;
Begin
  {$IF DECLARED(O_NOFOLLOW)}
  Result := O_NOFOLLOW;
  {$ELSE}
  Result := 0;
  {$ENDIF}
End;

Function CloExecFlag: cint;
Begin
  {$IF DECLARED(O_CLOEXEC)}
  Result := O_CLOEXEC;
  {$ELSE}
    {$IFDEF LINUX}
    Result := $80000;
    {$ELSE}
      {$IFDEF DARWIN}
      Result := $1000000;
      {$ELSE}
      Result := 0;
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
End;

Function EntryIsSymlink(Const Path: String): Boolean;
Var
  Info: Stat;
Begin
  Info := Default(Stat);
  Result := (fpLStat(Path, Info) = 0) And FPS_ISLNK(Info.st_mode);
End;

Function PublishNewText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
Var
  Parts: TStringList;
  Dir, NextDir, Handle, I: cint;
  Written, Offset: SizeInt;
  TempName: String;
  Id: TGuid;
Begin
  Result := False;
  ErrorText := '';
  { Empty is rejected before indexing. Pascal Or does not short-circuit. }
  If (RelativePath = '') Or (Length(RelativePath) > NewTextMaxPathBytes) Or (Length(Text) > NewTextMaxBytes) Or
    (Pos(#0, RelativePath) > 0) Or (Pos(#0, Text) > 0) Then
    Begin
      ErrorText := 'A relative project path and at most 1 MiB of text are required.';
      Exit;
    End;
  If RelativePath[1] = '/' Then
    Begin
      ErrorText := 'A relative project path and at most 1 MiB of text are required.';
      Exit;
    End;
  Parts := TStringList.Create;
  Dir := -1;
  Handle := -1;
  TempName := '';
  Try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := '/';
    Parts.QuoteChar := #0;
    Parts.DelimitedText := RelativePath;
    If Parts.Count > NewTextMaxDepth Then
      Begin
        ErrorText := 'Too many directory levels.';
        Exit;
      End;
    For I := 0 To Parts.Count - 1 Do
      If (Parts[I] = '') Or (Parts[I] = '.') Or (Parts[I] = '..') Then
        Begin
          ErrorText := 'Empty and relative traversal components are not supported.';
          Exit;
        End;
    Dir := fpOpen(Root, O_RDONLY Or DirectoryOpenFlag Or CloExecFlag);
    If Dir < 0 Then
      Begin
        ErrorText := 'Cannot open the project directory.';
        Exit;
      End;
    For I := 0 To Parts.Count - 2 Do
      Begin
        NextDir := OpenAt(Dir, PChar(Parts[I]), O_RDONLY Or DirectoryOpenFlag Or NoFollowOpenFlag Or CloExecFlag, 0);
        If NextDir < 0 Then
          Begin
            { Existing symlinks, files and inaccessible directories cannot be
              replaced. Only a genuinely missing directory can be created. }
            If MkdirAt(Dir, PChar(Parts[I]), &755) <> 0 Then
              Begin
                ErrorText := 'Cannot create or traverse the project directory; symlinks are not followed.';
                Exit;
              End;
            NextDir := OpenAt(Dir, PChar(Parts[I]), O_RDONLY Or DirectoryOpenFlag Or NoFollowOpenFlag Or CloExecFlag, 0);
          End;
        If NextDir < 0 Then
          Begin
            ErrorText := 'Cannot open the new project directory.';
            Exit;
          End;
        fpClose(Dir);
        Dir := NextDir;
      End;
    If CreateGUID(Id) <> 0 Then
      Begin
        ErrorText := 'Cannot allocate a temporary file name.';
        Exit;
      End;
    TempName := '.laz-assistant-' + Copy(GUIDToString(Id), 2, 36) + '.tmp';
    Handle := OpenAt(Dir, PChar(TempName), O_WRONLY Or O_CREAT Or O_EXCL Or NoFollowOpenFlag Or CloExecFlag, &644);
    If Handle < 0 Then
      Begin
        { Do not unlink a name this call did not create. }
        TempName := '';
        ErrorText := 'Cannot create a temporary project file.';
        Exit;
      End;
    Offset := 1;
    While Offset <= Length(Text) Do
      Begin
        Written := fpWrite(Handle, Text[Offset], Length(Text) - Offset + 1);
        If (Written < 0) And (fpGetErrno = ESysEINTR) Then Continue;
        If Written <= 0 Then
          Begin
            ErrorText := 'Could not write the complete file; destination was not created.';
            Exit;
          End;
        Inc(Offset, Written);
      End;
    If fpFsync(Handle) <> 0 Then
      Begin
        ErrorText := 'Could not flush the new file; destination was not created.';
        Exit;
      End;
    fpClose(Handle);
    Handle := -1;
    { A hard-link publication is atomic and fails if any destination entry
      already exists, including a dangling symlink or concurrently created file. }
    If LinkAt(Dir, PChar(TempName), Dir, PChar(Parts[Parts.Count - 1]), 0) <> 0 Then
      Begin
        ErrorText := 'Destination already exists or cannot be created; nothing was overwritten.';
        Exit;
      End;
    Result := True;
  Finally
    If Handle >= 0 Then fpClose(Handle);
    If (Dir >= 0) And (TempName <> '') Then UnlinkAt(Dir, PChar(TempName), 0);
    If Dir >= 0 Then fpClose(Dir);
    Parts.Free;
  End;
End;

Function ReadAllNoFollowUnix(Const Path: String; ExpectedSize: Int64; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Handle: cint;
  Offset, Chunk, Got: SizeInt;
Begin
  Result := False;
  Data := Nil;
  ErrorText := '';
  Handle := fpOpen(PChar(Path), O_RDONLY Or NoFollowOpenFlag);
  If Handle < 0 Then
    Begin
      If EntryIsSymlink(Path) Then
        ErrorText := ImageReadSymlinkError
      Else
        ErrorText := ImageReadError;
      Exit;
    End;
  Try
    SetLength(Data, SizeInt(ExpectedSize));
    Offset := 0;
    While Offset < ExpectedSize Do
      Begin
        Chunk := SizeInt(ExpectedSize) - Offset;
        If Chunk > 65536 Then Chunk := 65536;
        Got := fpRead(Handle, Data[Offset], Chunk);
        If Got < 0 Then
          Begin
            SetLength(Data, 0);
            ErrorText := ImageReadError;
            Exit;
          End;
        If Got = 0 Then Break;
        Offset := Offset + Got;
      End;
    If Offset <> ExpectedSize Then
      Begin
        SetLength(Data, 0);
        ErrorText := ImageReadError;
        Exit;
      End;
    Result := True;
  Finally
    fpClose(Handle);
  End;
End;

Function CreateExclusiveNoFollowUnix(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
Var
  Handle: cint;
  Offset, Chunk, Wrote: SizeInt;
Begin
  Result := False;
  Handle := fpOpen(PChar(Path), O_WRONLY Or O_CREAT Or O_EXCL Or NoFollowOpenFlag, &644);
  If Handle < 0 Then
    Begin
      If EntryIsSymlink(Path) Then
        ErrorText := ImageWriteSymlinkError
      Else
        ErrorText := ImageWriteError;
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
            ErrorText := ImageWriteError;
            Exit;
          End;
        Offset := Offset + Wrote;
      End;
    Result := True;
  Finally
    fpClose(Handle);
  End;
End;
{$ENDIF}

{$IFDEF WINDOWS}
Function WindowsEntryIsReparse(Const Path: String): Boolean;
Var
  Attr: DWORD;
Begin
  Attr := GetFileAttributes(PChar(Path));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) And ((Attr And FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
End;

Function ReadAllNoFollowWindows(Const Path: String; ExpectedSize: Int64; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Handle: THandle;
  Info: TByHandleFileInformation;
  Offset, Chunk: SizeInt;
  ReadCount: DWORD;
Begin
  Result := False;
  Handle := Windows.CreateFile(PChar(Path), GENERIC_READ, FILE_SHARE_READ Or FILE_SHARE_WRITE Or FILE_SHARE_DELETE,
    Nil, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
  If Handle = INVALID_HANDLE_VALUE Then
    Begin
      If WindowsEntryIsReparse(Path) Then
        ErrorText := ImageReadSymlinkError
      Else
        ErrorText := ImageReadError;
      Exit;
    End;
  Try
    If Not GetFileInformationByHandle(Handle, Info) Or
      ((Info.dwFileAttributes And FILE_ATTRIBUTE_DIRECTORY) <> 0) Then
      Begin
        ErrorText := ImageReadError;
        Exit;
      End;
    If (Info.dwFileAttributes And FILE_ATTRIBUTE_REPARSE_POINT) <> 0 Then
      Begin
        ErrorText := ImageReadSymlinkError;
        Exit;
      End;
    SetLength(Data, SizeInt(ExpectedSize));
    Offset := 0;
    While Offset < ExpectedSize Do
      Begin
        Chunk := SizeInt(ExpectedSize) - Offset;
        If Chunk > 65536 Then Chunk := 65536;
        ReadCount := 0;
        If Not ReadFile(Handle, Data[Offset], DWORD(Chunk), ReadCount, Nil) Then
          Begin
            SetLength(Data, 0);
            ErrorText := ImageReadError;
            Exit;
          End;
        If ReadCount = 0 Then Break;
        Offset := Offset + ReadCount;
      End;
    If Offset <> ExpectedSize Then
      Begin
        SetLength(Data, 0);
        ErrorText := ImageReadError;
        Exit;
      End;
    Result := True;
  Finally
    CloseHandle(Handle);
  End;
End;

Function CreateExclusiveNoFollowWindows(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
Var
  Handle: THandle;
  Offset, Chunk: SizeInt;
  Wrote: DWORD;
Begin
  Result := False;
  If WindowsEntryIsReparse(Path) Then
    Begin
      ErrorText := ImageWriteSymlinkError;
      Exit;
    End;
  Handle := Windows.CreateFile(PChar(Path), GENERIC_WRITE, 0, Nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  If Handle = INVALID_HANDLE_VALUE Then
    Begin
      If WindowsEntryIsReparse(Path) Then
        ErrorText := ImageWriteSymlinkError
      Else
        ErrorText := ImageWriteError;
      Exit;
    End;
  Try
    Offset := 0;
    While Offset < Length(Data) Do
      Begin
        Chunk := Length(Data) - Offset;
        If Chunk > 65536 Then Chunk := 65536;
        Wrote := 0;
        If (Not WriteFile(Handle, Data[Offset], DWORD(Chunk), Wrote, Nil)) Or (Wrote < 1) Then
          Begin
            ErrorText := ImageWriteError;
            Exit;
          End;
        Offset := Offset + Wrote;
      End;
    Result := True;
  Finally
    CloseHandle(Handle);
  End;
End;
{$ENDIF}

Function CanCreateNewText: Boolean;
Begin
  {$IFDEF UNIX}
  Result := (DirectoryOpenFlag <> 0) And (NoFollowOpenFlag <> 0);
  {$ELSE}
  Result := False;
  {$ENDIF}
End;

Function CreateNewText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  {$IFDEF UNIX}
  If Not CanCreateNewText Then
    Begin
      ErrorText := NewTextUnsupportedError;
      Exit;
    End;
  Result := PublishNewText(Root, RelativePath, Text, ErrorText);
  {$ELSE}
  ErrorText := NewTextUnsupportedError;
  {$ENDIF}
End;

Function ReadAllNoFollow(Const Path: String; ExpectedSize: Int64; Out Data: TBytes; Out ErrorText: String): Boolean;
Begin
  Result := False;
  Data := Nil;
  ErrorText := '';
  If (ExpectedSize < 1) Or (ExpectedSize > ImageStoreMaxBytes) Then
    Begin
      ErrorText := ImageReadError;
      Exit;
    End;
  {$IFDEF UNIX}
  Result := ReadAllNoFollowUnix(Path, ExpectedSize, Data, ErrorText);
  {$ELSE}
    {$IFDEF WINDOWS}
    Result := ReadAllNoFollowWindows(Path, ExpectedSize, Data, ErrorText);
    {$ELSE}
    ErrorText := ImageReadError;
    {$ENDIF}
  {$ENDIF}
End;

Function CreateExclusiveNoFollow(Const Path: String; Const Data: TBytes; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Length(Data) < 1 Then
    Begin
      ErrorText := ImageWriteError;
      Exit;
    End;
  {$IFDEF UNIX}
  Result := CreateExclusiveNoFollowUnix(Path, Data, ErrorText);
  {$ELSE}
    {$IFDEF WINDOWS}
    Result := CreateExclusiveNoFollowWindows(Path, Data, ErrorText);
    {$ELSE}
    ErrorText := ImageWriteError;
    {$ENDIF}
  {$ENDIF}
End;

Function ProtectOwnerOnly(Const Path: String; Mode: Integer): Boolean;
Begin
  {$IFDEF UNIX}
  Result := fpChmod(Path, TMode(Mode)) = 0;
  {$ELSE}
  Result := True;
  {$ENDIF}
End;

Function ProtectOwnerOnlyFile(Const Path: String): Boolean;
Begin
  Result := ProtectOwnerOnly(Path, &600);
End;

Function ProtectOwnerOnlyDirectory(Const Path: String): Boolean;
Begin
  Result := ProtectOwnerOnly(Path, &700);
End;

Function IsRegularFile(Const Path: String; MaxBytes: Int64): Boolean;
{$IFDEF UNIX}
Var
  Info: Stat;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  Handle: THandle;
  Info: TByHandleFileInformation;
  Size: Int64;
{$ENDIF}
Begin
  Result := False;
  {$IFDEF UNIX}
  Info := Default(Stat);
  If fpStat(Path, Info) <> 0 Then Exit;
  If Not FPS_ISREG(Info.st_mode) Then Exit;
  Result := (MaxBytes < 0) Or (Info.st_size <= MaxBytes);
  {$ELSE}
    {$IFDEF WINDOWS}
    { OPEN_EXISTING follows the final symlink, matching fpStat. }
    Handle := Windows.CreateFile(PChar(Path), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ Or FILE_SHARE_WRITE Or FILE_SHARE_DELETE, Nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    If Handle = INVALID_HANDLE_VALUE Then Exit;
    Try
      If GetFileType(Handle) <> FILE_TYPE_DISK Then Exit;
      If Not GetFileInformationByHandle(Handle, Info) Then Exit;
      If (Info.dwFileAttributes And (FILE_ATTRIBUTE_DIRECTORY Or FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 Then Exit;
      Size := Int64(Info.nFileSizeHigh) Shl 32 Or Info.nFileSizeLow;
      Result := (MaxBytes < 0) Or (Size <= MaxBytes);
    Finally
      CloseHandle(Handle);
    End;
    {$ENDIF}
  {$ENDIF}
End;

Function PathEntryExists(Const Path: String): Boolean;
{$IFDEF UNIX}
Var
  Info: Stat;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  Attr: DWORD;
{$ENDIF}
Begin
  {$IFDEF UNIX}
  Info := Default(Stat);
  Result := fpLStat(Path, Info) = 0;
  {$ELSE}
    {$IFDEF WINDOWS}
    Attr := GetFileAttributes(PChar(Path));
    Result := Attr <> INVALID_FILE_ATTRIBUTES;
    {$ELSE}
    Result := False;
    {$ENDIF}
  {$ENDIF}
End;

Function TryExclusiveCreate(Const Path: String; Out Handle: THandle; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Opened: cint;
{$ENDIF}
Begin
  Result := False;
  Handle := THandle(-1);
  ErrorText := '';
  {$IFDEF UNIX}
  Opened := fpOpen(PChar(Path), O_WRONLY Or O_CREAT Or O_EXCL, &600);
  If Opened < 0 Then
    Begin
      ErrorText := SysErrorMessage(fpGetErrno);
      Exit;
    End;
  Handle := THandle(Opened);
  Result := True;
  {$ELSE}
    {$IFDEF WINDOWS}
    Handle := Windows.CreateFile(PChar(Path), GENERIC_WRITE, 0, Nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    If Handle = INVALID_HANDLE_VALUE Then
      Begin
        Handle := THandle(-1);
        ErrorText := SysErrorMessage(GetLastOSError);
        Exit;
      End;
    Result := True;
    {$ELSE}
    ErrorText := 'Exclusive create is not available on this host.';
    {$ENDIF}
  {$ENDIF}
End;

Function ReplaceWithExclusiveFile(Const SourcePath, DestinationPath: String; Out ErrorText: String): Boolean;
{$IFDEF UNIX}
Var
  Info: Stat;
{$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  {$IFDEF UNIX}
  Info := Default(Stat);
  If fpStat(DestinationPath, Info) = 0 Then fpChmod(SourcePath, Info.st_mode And &777);
  If Not RenameFile(SourcePath, DestinationPath) Then
    Begin
      ErrorText := RestoreConfigError;
      Exit;
    End;
  Result := True;
  {$ELSE}
    {$IFDEF WINDOWS}
    If Not MoveFileEx(PChar(SourcePath), PChar(DestinationPath), MOVEFILE_REPLACE_EXISTING Or MOVEFILE_WRITE_THROUGH) Then
      Begin
        ErrorText := RestoreConfigError;
        Exit;
      End;
    Result := True;
    {$ELSE}
    ErrorText := RestoreConfigError;
    {$ENDIF}
  {$ENDIF}
End;

Function NullDevicePath: String;
Begin
  {$IFDEF WINDOWS}
  Result := 'NUL';
  {$ELSE}
  Result := '/dev/null';
  {$ENDIF}
End;

End.
