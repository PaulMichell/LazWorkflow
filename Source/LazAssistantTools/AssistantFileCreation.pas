Unit AssistantFileCreation;
{ Publish complete new text files without replacing existing directory entries.
  Linux directory handles keep all child operations relative to the project root. }
{$mode objfpc}{$H+}
Interface
Function CreateNewProjectText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
Implementation
Uses Classes, SysUtils
  {$IFDEF LINUX}, BaseUnix, Unix, Linux{$ENDIF};
{$IFDEF LINUX}
Function OpenAt(Dir: LongInt; Name: PChar; Flags: LongInt; Mode: Cardinal): LongInt; cdecl; external 'c' name 'openat';
Function MkdirAt(Dir: LongInt; Name: PChar; Mode: Cardinal): LongInt; cdecl; external 'c' name 'mkdirat';
Function LinkAt(OldDir: LongInt; OldName: PChar; NewDir: LongInt; NewName: PChar; Flags: LongInt): LongInt; cdecl; external 'c' name 'linkat';
Function UnlinkAt(Dir: LongInt; Name: PChar; Flags: LongInt): LongInt; cdecl; external 'c' name 'unlinkat';
{$ENDIF}
Function CreateNewProjectText(Const Root, RelativePath, Text: String; Out ErrorText: String): Boolean;
{$IFDEF LINUX}
Var Parts: TStringList; Dir, NextDir, Handle, I: Integer; Written, Offset: SizeInt;
  TempName: String; Id: TGuid;
{$ENDIF}
Begin
  Result := False; ErrorText := '';
  {$IFDEF LINUX}
  If (RelativePath = '') Or (RelativePath[1] = '/') Or (Pos(#0, RelativePath) > 0) Or
    (Length(RelativePath) > 4096) Or (Length(Text) > 1048576) Or (Pos(#0, Text) > 0) Then
    Begin ErrorText := 'A relative project path and at most 1 MiB of text are required.'; Exit; End;
  Parts := TStringList.Create; Dir := -1; Handle := -1; TempName := '';
  Try
    Parts.StrictDelimiter := True; Parts.Delimiter := '/'; Parts.QuoteChar := #0; Parts.DelimitedText := RelativePath;
    If Parts.Count > 64 Then Begin ErrorText := 'Too many directory levels.'; Exit; End;
    For I := 0 To Parts.Count - 1 Do
      If (Parts[I] = '') Or (Parts[I] = '.') Or (Parts[I] = '..') Then
        Begin ErrorText := 'Empty and relative traversal components are not supported.'; Exit; End;
    Dir := fpOpen(Root, O_RDONLY Or O_DIRECTORY Or O_CLOEXEC);
    If Dir < 0 Then Begin ErrorText := 'Cannot open the project directory.'; Exit; End;
    For I := 0 To Parts.Count - 2 Do
      Begin
        NextDir := OpenAt(Dir, PChar(Parts[I]), O_RDONLY Or O_DIRECTORY Or O_NOFOLLOW Or O_CLOEXEC, 0);
        If NextDir < 0 Then
          Begin
            { Existing symlinks, files and inaccessible directories cannot be
              replaced. Only a genuinely missing directory can be created. }
            If MkdirAt(Dir, PChar(Parts[I]), &755) <> 0 Then
              Begin ErrorText := 'Cannot create or traverse the project directory; symlinks are not followed.'; Exit; End;
            NextDir := OpenAt(Dir, PChar(Parts[I]), O_RDONLY Or O_DIRECTORY Or O_NOFOLLOW Or O_CLOEXEC, 0);
          End;
        If NextDir < 0 Then Begin ErrorText := 'Cannot open the new project directory.'; Exit; End;
        fpClose(Dir); Dir := NextDir;
      End;
    If CreateGUID(Id) <> 0 Then Begin ErrorText := 'Cannot allocate a temporary file name.'; Exit; End;
    TempName := '.laz-assistant-' + Copy(GUIDToString(Id), 2, 36) + '.tmp';
    Handle := OpenAt(Dir, PChar(TempName), O_WRONLY Or O_CREAT Or O_EXCL Or O_NOFOLLOW Or O_CLOEXEC, &644);
    If Handle < 0 Then Begin TempName := ''; ErrorText := 'Cannot create a temporary project file.'; Exit; End;
    Offset := 1;
    While Offset <= Length(Text) Do
      Begin
        Written := fpWrite(Handle, Text[Offset], Length(Text) - Offset + 1);
        If (Written < 0) And (fpGetErrno = ESysEINTR) Then Continue;
        If Written <= 0 Then Begin ErrorText := 'Could not write the complete file; destination was not created.'; Exit; End;
        Inc(Offset, Written);
      End;
    If fpFsync(Handle) <> 0 Then Begin ErrorText := 'Could not flush the new file; destination was not created.'; Exit; End;
    fpClose(Handle); Handle := -1;
    { A hard-link publication is atomic and fails if any destination entry
      already exists, including a dangling symlink or concurrently created file. }
    If LinkAt(Dir, PChar(TempName), Dir, PChar(Parts[Parts.Count - 1]), 0) <> 0 Then
      Begin ErrorText := 'Destination already exists or cannot be created; nothing was overwritten.'; Exit; End;
    Result := True;
  Finally
    If Handle >= 0 Then fpClose(Handle);
    If (Dir >= 0) And (TempName <> '') Then UnlinkAt(Dir, PChar(TempName), 0);
    If Dir >= 0 Then fpClose(Dir);
    Parts.Free;
  End;
  {$ELSE}
  ErrorText := 'New project file creation is currently supported on Linux only.';
  {$ENDIF}
End;
End.
