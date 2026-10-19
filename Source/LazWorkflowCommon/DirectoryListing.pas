Unit DirectoryListing;

{ Directory listing that reports symlink entries FindFirstUTF8 does not (c) 2026 Michell Computing.

  Checked 2026-10-19 against FindFirstUTF8 on LCL 5.99.0.0 / FPC 3.3.1.
  A regular file was attr 32 size 3 versus attr 0 size 3. A directory was
  attr 48 size 40 versus attr 16 size 40. faAnyFile followed a directory
  symlink (attr 48 size 40) and omitted a dangling symlink; this scanner
  reported attr 1040 size 6 and attr 1024 size 7. Even with faSymLink in the
  mask, FindFirst still added faArchive. Callers test faSymLink without
  passing that bit, so the Unix scanner stays. Do not add another FpOpenDir. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TDirectoryScan = Record
    Name: String;
    Attr: LongInt;
    Size: Int64;
    Active: Boolean;
    Index: Integer;
    Count: Integer;
    Names: Array Of String;
    Attrs: Array Of LongInt;
    Sizes: Array Of Int64;
    {$IFNDEF UNIX}
    Search: TSearchRec;
    {$ENDIF}
  End;

{ Same contract as FindFirst/FindNext/FindClose: 0 means an entry is in Scan.
  Close is safe when Start did not find a directory. Attr is honoured on Windows
  and recorded on every platform; Unix does not ask the C library to filter. }
Function StartDirectoryScan(Const Pattern: String; Attr: LongInt; Out Scan: TDirectoryScan): Integer;
Function AdvanceDirectoryScan(Var Scan: TDirectoryScan): Integer;
Procedure CloseDirectoryScan(Var Scan: TDirectoryScan);
{ Immediate child directories, full paths. "." and ".." are omitted. }
Procedure CollectChildDirectories(Const Directory: String; Names: TStrings);
{ Files whose names match Mask (one star). Directory links are listed but not entered. }
Procedure CollectMatchingFiles(Const Directory, Mask: String; Recursive: Boolean; Names: TStrings);

Implementation

Uses
  LazFileUtils, LazUTF8{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

Procedure ClearScan(Var Scan: TDirectoryScan);
Begin
  Scan.Name := '';
  Scan.Attr := 0;
  Scan.Size := 0;
  Scan.Active := False;
  Scan.Index := 0;
  Scan.Count := 0;
  SetLength(Scan.Names, 0);
  SetLength(Scan.Attrs, 0);
  SetLength(Scan.Sizes, 0);
End;

Procedure PublishEntry(Var Scan: TDirectoryScan);
Begin
  Scan.Name := Scan.Names[Scan.Index];
  Scan.Attr := Scan.Attrs[Scan.Index];
  Scan.Size := Scan.Sizes[Scan.Index];
End;

Function NameMatchesMask(Const Name, Mask: String): Boolean;
Var
  Star, SuffixStart: Integer;
  Prefix, Suffix: String;
Begin
  If (Mask = '') Or (Mask = '*') Then
    Exit(True);
  Star := Pos('*', Mask);
  If Star < 1 Then
    Exit(Name = Mask);
  { One star is every pattern this project builds. A second star does not match. }
  If Pos('*', Copy(Mask, Star + 1, MaxInt)) > 0 Then
    Exit(False);
  Prefix := Copy(Mask, 1, Star - 1);
  Suffix := Copy(Mask, Star + 1, MaxInt);
  If Copy(Name, 1, Length(Prefix)) <> Prefix Then
    Exit(False);
  SuffixStart := Length(Name) - Length(Suffix) + 1;
  If SuffixStart < Length(Prefix) + 1 Then
    Exit(False);
  Result := Copy(Name, SuffixStart, Length(Suffix)) = Suffix;
End;

Procedure SplitPattern(Const Pattern: String; Out Directory, Mask: String);
Var
  Slash: Integer;
Begin
  Slash := Length(Pattern);
  While (Slash > 0) And (Pattern[Slash] <> '/') And (Pattern[Slash] <> '\') Do
    Dec(Slash);
  If Slash < 1 Then
    Begin
      Directory := '.';
      Mask := Pattern;
    End
  Else
    Begin
      Directory := ExcludeTrailingPathDelimiter(Copy(Pattern, 1, Slash));
      Mask := Copy(Pattern, Slash + 1, MaxInt);
    End;
  If Mask = '' Then
    Mask := '*';
  If Directory = '' Then
    Directory := '.';
End;

{$IFDEF UNIX}
Procedure AddEntry(Var Scan: TDirectoryScan; Const Name: String; Attr: LongInt; Size: Int64);
Begin
  If Scan.Count >= Length(Scan.Names) Then
    Begin
      SetLength(Scan.Names, Scan.Count + 32);
      SetLength(Scan.Attrs, Scan.Count + 32);
      SetLength(Scan.Sizes, Scan.Count + 32);
    End;
  Scan.Names[Scan.Count] := Name;
  Scan.Attrs[Scan.Count] := Attr;
  Scan.Sizes[Scan.Count] := Size;
  Inc(Scan.Count);
End;

Function StartDirectoryScan(Const Pattern: String; Attr: LongInt; Out Scan: TDirectoryScan): Integer;
Var
  Directory, Mask, Full, RawName: String;
  Dir: PDir;
  Ent: PDirent;
  LinkInfo, FileInfo: Stat;
  EntryAttr: LongInt;
  EntrySize: Int64;
Begin
  Scan := Default(TDirectoryScan);
  ClearScan(Scan);
  If Attr = 0 Then
    Attr := faAnyFile;
  SplitPattern(Pattern, Directory, Mask);
  Dir := FpOpenDir(Directory);
  If Dir = Nil Then
    Exit(2);
  Try
    Repeat
      Ent := FpReadDir(Dir^);
      If Ent = Nil Then
        Break;
      RawName := SysToUTF8(PAnsiChar(@Ent^.d_name[0]));
      If Not NameMatchesMask(RawName, Mask) Then
        Continue;
      Full := IncludeTrailingPathDelimiter(Directory) + RawName;
      EntryAttr := 0;
      EntrySize := 0;
      LinkInfo := Default(Stat);
      FileInfo := Default(Stat);
      If FpLStat(Full, LinkInfo) = 0 Then
        Begin
          If fpS_ISLNK(LinkInfo.st_mode) Then
            Begin
              { faSymLink is $400. The old DOS bit $40 is not this flag. }
              {$PUSH}{$WARN 5044 OFF}
              EntryAttr := faSymLink;
              {$POP}
            End;
          If fpS_ISDIR(LinkInfo.st_mode) Then
            EntryAttr := EntryAttr Or faDirectory;
          EntrySize := LinkInfo.st_size;
          If fpS_ISLNK(LinkInfo.st_mode) Then
            Begin
              If (FpStat(Full, FileInfo) = 0) And fpS_ISDIR(FileInfo.st_mode) Then
                EntryAttr := EntryAttr Or faDirectory;
            End
          Else If FpStat(Full, FileInfo) = 0 Then
            EntrySize := FileInfo.st_size;
        End;
      { faDirectory alone means directories. faAnyFile and mixed masks keep every name. }
      If (Attr = faDirectory) And ((EntryAttr And faDirectory) = 0) Then
        Continue;
      AddEntry(Scan, RawName, EntryAttr, EntrySize);
    Until False;
  Finally
    FpCloseDir(Dir^);
  End;
  SetLength(Scan.Names, Scan.Count);
  SetLength(Scan.Attrs, Scan.Count);
  SetLength(Scan.Sizes, Scan.Count);
  If Scan.Count < 1 Then
    Exit(18);
  Scan.Active := True;
  Scan.Index := 0;
  PublishEntry(Scan);
  Result := 0;
End;
{$ELSE}
Function StartDirectoryScan(Const Pattern: String; Attr: LongInt; Out Scan: TDirectoryScan): Integer;
Begin
  Scan := Default(TDirectoryScan);
  ClearScan(Scan);
  If Attr = 0 Then
    Attr := faAnyFile;
  Result := FindFirstUTF8(Pattern, Attr, Scan.Search);
  If Result <> 0 Then
    Exit;
  Scan.Active := True;
  Scan.Name := Scan.Search.Name;
  Scan.Attr := Scan.Search.Attr;
  Scan.Size := Scan.Search.Size;
End;
{$ENDIF}

Function AdvanceDirectoryScan(Var Scan: TDirectoryScan): Integer;
Begin
  Result := 18;
  If Not Scan.Active Then
    Exit;
  {$IFDEF UNIX}
  Inc(Scan.Index);
  If Scan.Index >= Scan.Count Then
    Begin
      Scan.Active := False;
      Scan.Name := '';
      Exit;
    End;
  PublishEntry(Scan);
  Result := 0;
  {$ELSE}
  Result := FindNextUTF8(Scan.Search);
  If Result <> 0 Then
    Begin
      Scan.Active := False;
      Scan.Name := '';
      Exit;
    End;
  Scan.Name := Scan.Search.Name;
  Scan.Attr := Scan.Search.Attr;
  Scan.Size := Scan.Search.Size;
  {$ENDIF}
End;

Procedure CloseDirectoryScan(Var Scan: TDirectoryScan);
Begin
  {$IFNDEF UNIX}
  If Scan.Active Then
    FindCloseUTF8(Scan.Search);
  {$ENDIF}
  ClearScan(Scan);
End;

Procedure CollectChildDirectories(Const Directory: String; Names: TStrings);
Var
  Scan: TDirectoryScan;
  Code: Integer;
  Child: String;
Begin
  If (Not Assigned(Names)) Or (Directory = '') Or (Not DirectoryExistsUTF8(Directory)) Then
    Exit;
  Code := StartDirectoryScan(IncludeTrailingPathDelimiter(Directory) + '*', faDirectory, Scan);
  If Code <> 0 Then
    Exit;
  Try
    While Code = 0 Do
      Begin
        If (Scan.Name <> '.') And (Scan.Name <> '..') And ((Scan.Attr And faDirectory) <> 0) Then
          Begin
            Child := IncludeTrailingPathDelimiter(Directory) + Scan.Name;
            Names.Add(Child);
          End;
        Code := AdvanceDirectoryScan(Scan);
      End;
  Finally
    CloseDirectoryScan(Scan);
  End;
End;

Procedure CollectMatchingFiles(Const Directory, Mask: String; Recursive: Boolean; Names: TStrings);
Var
  Scan: TDirectoryScan;
  Code: Integer;
  Child: String;
Begin
  If (Not Assigned(Names)) Or (Directory = '') Or (Not DirectoryExistsUTF8(Directory)) Then
    Exit;
  Code := StartDirectoryScan(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile, Scan);
  If Code <> 0 Then
    Exit;
  Try
    While Code = 0 Do
      Begin
        If (Scan.Name <> '.') And (Scan.Name <> '..') Then
          Begin
            Child := IncludeTrailingPathDelimiter(Directory) + Scan.Name;
            If (Scan.Attr And faDirectory) <> 0 Then
              Begin
                {$PUSH}{$WARN 5044 OFF}
                If Recursive And ((Scan.Attr And faSymLink) = 0) Then
                  CollectMatchingFiles(Child, Mask, True, Names);
                {$POP}
              End
            Else If NameMatchesMask(Scan.Name, Mask) Then
              Names.Add(Child);
          End;
        Code := AdvanceDirectoryScan(Scan);
      End;
  Finally
    CloseDirectoryScan(Scan);
  End;
End;

End.
