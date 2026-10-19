Unit SpellHunspellWindows;

{ Windows Hunspell/LibreOffice discovery (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, DynLibs;

/// True when FileName is a path that must be loaded with LOAD_WITH_ALTERED_SEARCH_PATH.
/// Other hosts return false so the caller uses DynLibs.LoadLibrary.
Function TryLoadHunspellAlteredSearch(Const FileName: String; Out Handle: TLibHandle; Out ErrorText: String): Boolean;

/// Locate Hunspell DLLs and aff/dic directories. Other platforms return empty results.
Function WindowsHunspellLibraryFiles: TStringArray;
Function WindowsHunspellDictionaryDirectories: TStringArray;
Function WindowsDirectoryHasAffDicPair(Const Dir: String): Boolean;
Function WindowsHunspellDiscoveryNote: String;
Procedure ResetWindowsHunspellDiscovery;
Procedure AppendWindowsChildDictionaries(Var Dirs: TStringArray; Const Parent: String);

Implementation

Uses
  LazFileUtils, LazUTF8, WorkflowLog
  {$IFDEF WINDOWS}
  , Windows, Registry, Zipper, DirectoryListing
  {$ENDIF}
  ;

{$IFDEF WINDOWS}
Var
  WindowsHunspellLock: TRTLCriticalSection;
  WindowsConfigReady: Boolean = False;
  WindowsLibraryFiles: TStringArray = Nil;
  WindowsDictionaryDirs: TStringArray = Nil;
  WindowsDiscoveryNote: String = '';
  WindowsRelatedDlls: String = '';

Procedure AppendUniqueDirectory(Var Dirs: TStringArray; Const Dir: String);
Var
  Index: Integer;
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Dir);
  If (Clean = '') Or (Not DirectoryExistsUTF8(Clean)) Then
    Exit;
  For Index := 0 To High(Dirs) Do
    If CompareFilenames(Dirs[Index], Clean) = 0 Then
      Exit;
  SetLength(Dirs, Length(Dirs) + 1);
  Dirs[High(Dirs)] := Clean;
End;

Procedure AppendUniqueFile(Var Files: TStringArray; Const FileName: String);
Var
  Index: Integer;
Begin
  If (FileName = '') Or (Not FileExistsUTF8(FileName)) Then
    Exit;
  For Index := 0 To High(Files) Do
    If CompareFilenames(Files[Index], FileName) = 0 Then
      Exit;
  SetLength(Files, Length(Files) + 1);
  Files[High(Files)] := FileName;
End;

Function DirectoryHasAffDicPair(Const Dir: String): Boolean;
Var
  Info: TDirectoryScan;
  DicResult: Integer;
Begin
  Result := False;
  If (Dir = '') Or (Not DirectoryExistsUTF8(Dir)) Then
    Exit;
  DicResult := StartDirectoryScan(IncludeTrailingPathDelimiter(Dir) + '*.dic', faAnyFile, Info);
  If DicResult <> 0 Then
    Exit;
  Try
    While DicResult = 0 Do
      Begin
        If ((Info.Attr And faDirectory) = 0) And
           FileExistsUTF8(IncludeTrailingPathDelimiter(Dir) + ChangeFileExt(Info.Name, '.aff')) Then
          Begin
            Result := True;
            Exit;
          End;
        DicResult := AdvanceDirectoryScan(Info);
      End;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Function IsLibreOfficeRoot(Const Path: String): Boolean;
Var
  ProgramDir: String;
Begin
  ProgramDir := IncludeTrailingPathDelimiter(Path) + 'program\';
  Result := FileExistsUTF8(ProgramDir + 'soffice.exe') Or FileExistsUTF8(ProgramDir + 'soffice.bin') Or
    FileExistsUTF8(ProgramDir + 'swriter.exe') Or
    DirectoryExistsUTF8(IncludeTrailingPathDelimiter(Path) + 'share\extensions');
End;

Function NormalizeLibreOfficeRoot(Const Path: String): String;
Var
  Clean: String;
Begin
  Result := '';
  Clean := ExcludeTrailingPathDelimiter(Trim(Path));
  If (Length(Clean) >= 2) And (Clean[1] = '"') And (Clean[Length(Clean)] = '"') Then
    Clean := ExcludeTrailingPathDelimiter(Trim(Copy(Clean, 2, Length(Clean) - 2)));
  If Clean = '' Then
    Exit;
  If FileExistsUTF8(IncludeTrailingPathDelimiter(Clean) + 'soffice.exe') Or
     FileExistsUTF8(IncludeTrailingPathDelimiter(Clean) + 'soffice.bin') Or
     FileExistsUTF8(IncludeTrailingPathDelimiter(Clean) + 'swriter.exe') Then
    Clean := ExtractFileDir(Clean);
  If IsLibreOfficeRoot(Clean) Then
    Result := Clean;
End;

Procedure AddLibreOfficeRoot(Var Roots: TStringArray; Const Path: String);
Var
  Index: Integer;
  Clean: String;
Begin
  Clean := NormalizeLibreOfficeRoot(Path);
  If Clean = '' Then
    Exit;
  For Index := 0 To High(Roots) Do
    If CompareFilenames(Roots[Index], Clean) = 0 Then
      Exit;
  SetLength(Roots, Length(Roots) + 1);
  Roots[High(Roots)] := Clean;
End;

Function StripExecutableHint(Const Hint: String): String;
Var
  Text: String;
  Mark: Integer;
Begin
  Text := Trim(Hint);
  If Text = '' Then
    Begin
      Result := '';
      Exit;
    End;
  If Text[1] = '"' Then
    Begin
      Delete(Text, 1, 1);
      Mark := Pos('"', Text);
      If Mark > 0 Then
        Text := Copy(Text, 1, Mark - 1);
    End
  Else
    Begin
      Mark := Pos(',', Text);
      If Mark > 0 Then
        Text := Trim(Copy(Text, 1, Mark - 1));
    End;
  Result := Trim(Text);
End;

Function InstallRootFromExecutable(Const ExecutablePath: String): String;
Var
  Folder: String;
Begin
  Result := '';
  Folder := ExtractFileDir(ExecutablePath);
  If IsLibreOfficeRoot(Folder) Then
    Result := Folder
  Else If SameText(ExtractFileName(Folder), 'program') And IsLibreOfficeRoot(ExtractFileDir(Folder)) Then
    Result := ExtractFileDir(Folder);
End;

Procedure AddLocationHint(Var Roots: TStringArray; Const Hint: String);
Var
  Text: String;
Begin
  Text := StripExecutableHint(Hint);
  If Text = '' Then
    Exit;
  If DirectoryExistsUTF8(Text) Then
    AddLibreOfficeRoot(Roots, Text)
  Else If FileExistsUTF8(Text) Then
    AddLibreOfficeRoot(Roots, InstallRootFromExecutable(Text));
End;

Function RegistryText(Reg: TRegistry; Const ValueName: String): String;
Begin
  Result := '';
  If Not Assigned(Reg) Then
    Exit;
  Try
    { The App Paths default value is the executable. ValueExists('') misses it. }
    If (ValueName = '') Or Reg.ValueExists(ValueName) Then
      Result := Trim(Reg.ReadString(ValueName));
  Except
    On Exception Do
      Result := '';
  End;
End;

Function OpenRegistryKey(Reg: TRegistry; Const KeyPath: String): Boolean;
Begin
  Result := False;
  If Not Assigned(Reg) Then
    Exit;
  Try
    Result := Reg.OpenKey(KeyPath, False);
  Except
    On Exception Do
      Result := False;
  End;
End;

Procedure ScanUninstallRoots(RootKey: HKEY; Access: LongWord; Var Roots: TStringArray);
Var
  ListReg, KeyReg: TRegistry;
  Names: TStringList;
  Index: Integer;
  KeyPath, DisplayName, Location, IconHint: String;
Begin
  ListReg := TRegistry.Create(Access);
  KeyReg := TRegistry.Create(Access);
  Names := TStringList.Create;
  Try
    ListReg.RootKey := RootKey;
    KeyReg.RootKey := RootKey;
    If Not OpenRegistryKey(ListReg, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') Then
      Exit;
    Try
      ListReg.GetKeyNames(Names);
    Finally
      ListReg.CloseKey;
    End;
    For Index := 0 To Names.Count - 1 Do
      Begin
        KeyPath := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + Names[Index];
        If Not OpenRegistryKey(KeyReg, KeyPath) Then
          Continue;
        Try
          DisplayName := RegistryText(KeyReg, 'DisplayName');
          Location := RegistryText(KeyReg, 'InstallLocation');
          IconHint := RegistryText(KeyReg, 'DisplayIcon');
          If (Pos('libreoffice', LowerCase(DisplayName)) = 0) And (Pos('libreoffice', LowerCase(Location)) = 0) And
             (Pos('soffice', LowerCase(IconHint)) = 0) Then
            Continue;
          AddLocationHint(Roots, Location);
          AddLocationHint(Roots, IconHint);
          AddLocationHint(Roots, RegistryText(KeyReg, 'UninstallString'));
        Finally
          KeyReg.CloseKey;
        End;
      End;
  Finally
    Names.Free;
    KeyReg.Free;
    ListReg.Free;
  End;
End;

Procedure ScanProductRoots(RootKey: HKEY; Access: LongWord; Var Roots: TStringArray);
Var
  ListReg, KeyReg: TRegistry;
  Names: TStringList;
  Index: Integer;
Begin
  ListReg := TRegistry.Create(Access);
  KeyReg := TRegistry.Create(Access);
  Names := TStringList.Create;
  Try
    ListReg.RootKey := RootKey;
    KeyReg.RootKey := RootKey;
    If Not OpenRegistryKey(ListReg, 'SOFTWARE\LibreOffice\LibreOffice') Then
      Exit;
    Try
      ListReg.GetKeyNames(Names);
    Finally
      ListReg.CloseKey;
    End;
    For Index := 0 To Names.Count - 1 Do
      Begin
        If Not OpenRegistryKey(KeyReg, 'SOFTWARE\LibreOffice\LibreOffice\' + Names[Index]) Then
          Continue;
        Try
          AddLocationHint(Roots, RegistryText(KeyReg, ''));
          AddLocationHint(Roots, RegistryText(KeyReg, 'Path'));
          AddLocationHint(Roots, RegistryText(KeyReg, 'InstallPath'));
          AddLocationHint(Roots, RegistryText(KeyReg, 'InstallLocation'));
        Finally
          KeyReg.CloseKey;
        End;
      End;
  Finally
    Names.Free;
    KeyReg.Free;
    ListReg.Free;
  End;
End;

Procedure ScanAppPathRoot(RootKey: HKEY; Access: LongWord; Const ExecutableName: String; Var Roots: TStringArray);
Var
  Reg: TRegistry;
Begin
  Reg := TRegistry.Create(Access);
  Try
    Reg.RootKey := RootKey;
    If Not OpenRegistryKey(Reg, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\' + ExecutableName) Then
      Exit;
    Try
      AddLocationHint(Roots, RegistryText(Reg, ''));
      AddLocationHint(Roots, RegistryText(Reg, 'Path'));
    Finally
      Reg.CloseKey;
    End;
  Finally
    Reg.Free;
  End;
End;

Procedure ScanLibreOfficeValues(RootKey: HKEY; Access: LongWord; Const KeyPath: String; Depth: Integer;
  Var Roots: TStringArray);
Var
  Reg: TRegistry;
  Names: TStringList;
  Index: Integer;
  Value: String;
Begin
  If (Depth < 0) Or (KeyPath = '') Then
    Exit;
  Reg := TRegistry.Create(Access);
  Names := TStringList.Create;
  Try
    Reg.RootKey := RootKey;
    If Not OpenRegistryKey(Reg, KeyPath) Then
      Exit;
    Try
      Reg.GetValueNames(Names);
      For Index := 0 To Names.Count - 1 Do
        Begin
          Value := RegistryText(Reg, Names[Index]);
          If (Pos(':\', Value) > 0) Or (Pos('soffice', LowerCase(Value)) > 0) Or (Pos('swriter', LowerCase(Value)) > 0) Then
            AddLocationHint(Roots, Value);
        End;
      Names.Clear;
      Reg.GetKeyNames(Names);
    Finally
      Reg.CloseKey;
    End;
    For Index := 0 To Names.Count - 1 Do
      ScanLibreOfficeValues(RootKey, Access, KeyPath + '\' + Names[Index], Depth - 1, Roots);
  Finally
    Names.Free;
    Reg.Free;
  End;
End;

Function ShortcutTarget(Const LinkFile: String): String;
Var
  Stream: TFileStream;
  Header: Array[0..75] Of Byte;
  Flags, InfoSize, InfoHeaderSize, LocalOffset, UnicodeOffset: DWORD;
  IdListSize: Word;
  InfoStart: Int64;
  WidePath: UnicodeString;
  AnsiPath: RawByteString;
  Index, ReadCount: Integer;
Begin
  Result := '';
  FillChar(Header, SizeOf(Header), 0);
  IdListSize := 0;
  InfoSize := 0;
  InfoHeaderSize := 0;
  LocalOffset := 0;
  UnicodeOffset := 0;
  WidePath := '';
  AnsiPath := '';
  Try
    Stream := TFileStream.Create(LinkFile, fmOpenRead Or fmShareDenyNone);
  Except
    On Exception Do
      Exit;
  End;
  Try
    If Stream.Read(Header, 76) <> 76 Then
      Exit;
    Flags := PDWORD(@Header[20])^;
    If (Flags And 1) <> 0 Then
      Begin
        If Stream.Read(IdListSize, 2) <> 2 Then
          Exit;
        Stream.Seek(IdListSize, soCurrent);
      End;
    If (Flags And 2) = 0 Then
      Exit;
    InfoStart := Stream.Position;
    If Stream.Read(InfoSize, 4) <> 4 Then
      Exit;
    If Stream.Read(InfoHeaderSize, 4) <> 4 Then
      Exit;
    Stream.Seek(8, soCurrent);
    If Stream.Read(LocalOffset, 4) <> 4 Then
      Exit;
    Stream.Seek(8, soCurrent);
    UnicodeOffset := 0;
    If InfoHeaderSize >= $24 Then
      Stream.Read(UnicodeOffset, 4);
    If (UnicodeOffset > 0) And (UnicodeOffset < InfoSize) Then
      Begin
        Stream.Seek(InfoStart + UnicodeOffset, soBeginning);
        SetLength(WidePath, 1024);
        Index := 0;
        While Index < 1024 Do
          Begin
            ReadCount := Stream.Read(WidePath[Index + 1], 2);
            If (ReadCount <> 2) Or (WidePath[Index + 1] = #0) Then
              Break;
            Inc(Index);
          End;
        SetLength(WidePath, Index);
        Result := UTF8Encode(WidePath);
      End
    Else If (LocalOffset > 0) And (LocalOffset < InfoSize) Then
      Begin
        Stream.Seek(InfoStart + LocalOffset, soBeginning);
        SetLength(AnsiPath, 1024);
        Index := 0;
        While Index < 1024 Do
          Begin
            ReadCount := Stream.Read(AnsiPath[Index + 1], 1);
            If (ReadCount <> 1) Or (AnsiPath[Index + 1] = #0) Then
              Break;
            Inc(Index);
          End;
        SetLength(AnsiPath, Index);
        Result := String(AnsiPath);
      End;
  Finally
    Stream.Free;
  End;
End;

Procedure AddShortcutsIn(Var Roots: TStringArray; Const Folder: String; Depth: Integer);
Var
  Info: TDirectoryScan;
  Target, LowerTarget: String;
Begin
  If (Folder = '') Or (Depth < 0) Or (Not DirectoryExistsUTF8(Folder)) Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Folder) + '*.lnk', faAnyFile, Info) = 0 Then
    Try
      Repeat
        If (Info.Attr And faDirectory) = 0 Then
          Begin
            Target := ShortcutTarget(IncludeTrailingPathDelimiter(Folder) + Info.Name);
            LowerTarget := LowerCase(Target);
            If (Pos('soffice.exe', LowerTarget) > 0) Or (Pos('swriter.exe', LowerTarget) > 0) Or
               (Pos('soffice.bin', LowerTarget) > 0) Then
              AddLocationHint(Roots, Target);
          End;
      Until AdvanceDirectoryScan(Info) <> 0;
    Finally
      CloseDirectoryScan(Info);
    End;
  If Depth = 0 Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Folder) + '*', faDirectory, Info) = 0 Then
    Try
      Repeat
        If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
          AddShortcutsIn(Roots, IncludeTrailingPathDelimiter(Folder) + Info.Name, Depth - 1);
      Until AdvanceDirectoryScan(Info) <> 0;
    Finally
      CloseDirectoryScan(Info);
    End;
End;

Procedure AddInstallCandidates(Var Roots: TStringArray; Const Parent: String; Depth: Integer);
Var
  Info: TDirectoryScan;
  Child, LowerName: String;
Begin
  If (Parent = '') Or (Depth < 0) Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  AddLibreOfficeRoot(Roots, Parent);
  If Depth = 0 Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        Begin
          Child := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          AddLibreOfficeRoot(Roots, Child);
          LowerName := LowerCase(Info.Name);
          If (Depth > 1) And ((Pos('libre', LowerName) > 0) Or (Pos('office', LowerName) > 0) Or
             (Pos('document', LowerName) > 0)) Then
            AddInstallCandidates(Roots, Child, Depth - 1);
        End;
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Procedure AddPathExecutables(Var Roots: TStringArray);
Var
  PathText, Item: String;
  Separator: Integer;
Begin
  PathText := GetEnvironmentVariableUTF8('PATH');
  While PathText <> '' Do
    Begin
      Separator := Pos(';', PathText);
      If Separator = 0 Then
        Begin
          Item := PathText;
          PathText := '';
        End
      Else
        Begin
          Item := Copy(PathText, 1, Separator - 1);
          Delete(PathText, 1, Separator);
        End;
      Item := ExcludeTrailingPathDelimiter(Trim(Item));
      If Item = '' Then
        Continue;
      If FileExistsUTF8(IncludeTrailingPathDelimiter(Item) + 'soffice.exe') Or
         FileExistsUTF8(IncludeTrailingPathDelimiter(Item) + 'swriter.exe') Then
        AddLibreOfficeRoot(Roots, Item);
    End;
End;

Procedure AddLibreOfficeChildren(Var Roots: TStringArray; Const Parent: String);
Var
  Info: TDirectoryScan;
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Parent);
  If (Clean = '') Or (Not DirectoryExistsUTF8(Clean)) Then
    Exit;
  AddLibreOfficeRoot(Roots, Clean + '\LibreOffice');
  If StartDirectoryScan(Clean + '\LibreOffice*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        AddLibreOfficeRoot(Roots, Clean + '\' + Info.Name);
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Procedure CollectLibreOfficeRoots(Var Roots: TStringArray);
Var
  LocalPrograms: String;
  View: Integer;
  Access: LongWord;
  Procedure ScanView(RootKey: HKEY; Kind: Integer);
  Begin
    Try
      Case Kind Of
        0:
          Begin
            ScanAppPathRoot(RootKey, Access, 'soffice.exe', Roots);
            ScanAppPathRoot(RootKey, Access, 'swriter.exe', Roots);
            ScanLibreOfficeValues(RootKey, Access, 'SOFTWARE\LibreOffice', 4, Roots);
          End;
        1: ScanProductRoots(RootKey, Access, Roots);
      Else
        ScanUninstallRoots(RootKey, Access, Roots);
      End;
    Except
      On E: Exception Do
        If Assigned(WorkflowLogger) Then
          WorkflowLogger.Debug('Spell', 'Windows registry scan skipped: ' + E.Message);
    End;
  End;
Begin
  Roots := Nil;
  For View := 0 To 1 Do
    Begin
      If View = 0 Then
        Access := KEY_READ Or KEY_WOW64_64KEY
      Else
        Access := KEY_READ Or KEY_WOW64_32KEY;
      ScanView(HKEY_LOCAL_MACHINE, 0);
      ScanView(HKEY_CURRENT_USER, 0);
      ScanView(HKEY_LOCAL_MACHINE, 1);
      ScanView(HKEY_CURRENT_USER, 1);
      ScanView(HKEY_LOCAL_MACHINE, 2);
      ScanView(HKEY_CURRENT_USER, 2);
    End;
  AddInstallCandidates(Roots, GetEnvironmentVariableUTF8('ProgramW6432'), 2);
  AddInstallCandidates(Roots, GetEnvironmentVariableUTF8('ProgramFiles'), 2);
  AddInstallCandidates(Roots, GetEnvironmentVariableUTF8('ProgramFiles(x86)'), 2);
  AddInstallCandidates(Roots, 'C:\Program Files', 2);
  AddInstallCandidates(Roots, 'C:\Program Files (x86)', 2);
  AddInstallCandidates(Roots, 'C:\Program Files\WindowsApps', 1);
  LocalPrograms := GetEnvironmentVariableUTF8('LOCALAPPDATA');
  If LocalPrograms <> '' Then
    Begin
      AddInstallCandidates(Roots, IncludeTrailingPathDelimiter(LocalPrograms) + 'Programs', 2);
      AddLibreOfficeChildren(Roots, IncludeTrailingPathDelimiter(LocalPrograms) + 'Programs');
    End;
  AddPathExecutables(Roots);
  AddShortcutsIn(Roots, GetEnvironmentVariableUTF8('ProgramData') + '\Microsoft\Windows\Start Menu\Programs', 3);
  AddShortcutsIn(Roots, GetEnvironmentVariableUTF8('APPDATA') + '\Microsoft\Windows\Start Menu\Programs', 3);
  AddShortcutsIn(Roots, GetEnvironmentVariableUTF8('USERPROFILE') + '\Desktop', 1);
  AddShortcutsIn(Roots, GetEnvironmentVariableUTF8('PUBLIC') + '\Desktop', 1);
End;

Function ReadCString(Stream: TStream; Offset: Int64): String;
Var
  Buffer: Array[0..255] Of AnsiChar;
  Count: Integer;
Begin
  Result := '';
  If (Offset < 0) Or (Offset >= Stream.Size) Then
    Exit;
  Stream.Seek(Offset, soBeginning);
  Count := Stream.Read(Buffer, SizeOf(Buffer) - 1);
  If Count <= 0 Then
    Exit;
  Buffer[Count] := #0;
  Result := String(PAnsiChar(@Buffer[0]));
End;

Function RvaToOffset(Const Sections: Array Of DWORD; Count: Integer; RVA: DWORD): Int64;
Var
  Index: Integer;
  VirtualAddress, VirtualSize, RawPointer: DWORD;
Begin
  Result := -1;
  Index := 0;
  While Index + 2 < Count Do
    Begin
      VirtualAddress := Sections[Index];
      VirtualSize := Sections[Index + 1];
      RawPointer := Sections[Index + 2];
      If (RVA >= VirtualAddress) And (RVA < VirtualAddress + VirtualSize) Then
        Begin
          Result := Int64(RawPointer) + (RVA - VirtualAddress);
          Exit;
        End;
      Inc(Index, 3);
    End;
End;

{ Returns DLL names imported by a PE file. Used to find LibreOffice's renamed Hunspell library. }
Function PeImportedDllNames(Const FileName: String): TStringArray;
Var
  Stream: TFileStream;
  Dos: Array[0..63] Of Byte;
  HeaderOffset, ImportRVA, NameRVA, RawSize: DWORD;
  CoffSections: Word;
  OptionalSize: Word;
  Magic: Word;
  SectionStart, Index, Descriptor, ImportOffset: Int64;
  SectionVA, SectionSize, SectionRaw: DWORD;
  Sections: Array Of DWORD;
  NameText: String;
Begin
  Result := Nil;
  Try
    Stream := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyNone);
  Except
    On Exception Do
      Exit;
  End;
  Try
    If Stream.Size < 256 Then
      Exit;
    If Stream.Read(Dos, 64) <> 64 Then
      Exit;
    If (Dos[0] <> Ord('M')) Or (Dos[1] <> Ord('Z')) Then
      Exit;
    HeaderOffset := PDWORD(@Dos[60])^;
    If (HeaderOffset = 0) Or (HeaderOffset + 160 >= Stream.Size) Then
      Exit;
    Stream.Seek(HeaderOffset + 4, soBeginning);
    Stream.Seek(2, soCurrent);
    If Stream.Read(CoffSections, 2) <> 2 Then
      Exit;
    Stream.Seek(12, soCurrent);
    If Stream.Read(OptionalSize, 2) <> 2 Then
      Exit;
    Stream.Seek(2, soCurrent);
    If Stream.Read(Magic, 2) <> 2 Then
      Exit;
    If Magic = $20B Then
      Stream.Seek(118, soCurrent)
    Else If Magic = $10B Then
      Stream.Seek(102, soCurrent)
    Else
      Exit;
    Stream.Read(ImportRVA, 4);
    If ImportRVA = 0 Then
      Exit;
    SectionStart := HeaderOffset + 24 + OptionalSize;
    SetLength(Sections, CoffSections * 3);
    For Index := 0 To CoffSections - 1 Do
      Begin
        Stream.Seek(SectionStart + Index * 40 + 8, soBeginning);
        Stream.Read(SectionSize, 4);
        Stream.Read(SectionVA, 4);
        Stream.Read(RawSize, 4);
        Stream.Read(SectionRaw, 4);
        If RawSize > SectionSize Then
          SectionSize := RawSize;
        Sections[Index * 3] := SectionVA;
        Sections[Index * 3 + 1] := SectionSize;
        Sections[Index * 3 + 2] := SectionRaw;
      End;
    ImportOffset := RvaToOffset(Sections, Length(Sections), ImportRVA);
    If ImportOffset < 0 Then
      Exit;
    Descriptor := ImportOffset;
    While Descriptor + 20 < Stream.Size Do
      Begin
        Stream.Seek(Descriptor + 12, soBeginning);
        If Stream.Read(NameRVA, 4) <> 4 Then
          Exit;
        If NameRVA = 0 Then
          Exit;
        NameText := ReadCString(Stream, RvaToOffset(Sections, Length(Sections), NameRVA));
        If NameText <> '' Then
          Begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := NameText;
          End;
        Inc(Descriptor, 20);
        If Length(Result) > 64 Then
          Exit;
      End;
  Finally
    Stream.Free;
  End;
End;

Function DllExportsHunspell(Const FileName: String): Boolean;
Var
  WideName: UnicodeString;
  Handle: THandle;
  OldMode: UINT;
Begin
  Result := False;
  If FileName = '' Then
    Exit;
  OldMode := SetErrorMode(SEM_FAILCRITICALERRORS Or SEM_NOOPENFILEERRORBOX);
  Try
    WideName := UTF8Decode(FileName);
    Handle := LoadLibraryExW(PWideChar(WideName), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
    If Handle = 0 Then
      Exit;
    Try
      Result := GetProcAddress(Handle, 'Hunspell_create') <> Nil;
      If Not Result Then
        Result := GetProcAddress(Handle, 'Hunspell_create@8') <> Nil;
    Finally
      FreeLibrary(Handle);
    End;
  Finally
    SetErrorMode(OldMode);
  End;
End;

Procedure RememberRelatedDll(Const Name: String);
Begin
  If Name = '' Then
    Exit;
  If WindowsRelatedDlls = '' Then
    WindowsRelatedDlls := Name
  Else If (Pos(Name, WindowsRelatedDlls) = 0) And (Length(WindowsRelatedDlls) < 240) Then
    WindowsRelatedDlls := WindowsRelatedDlls + ', ' + Name;
End;

Procedure AppendProgramLibraries(Var Libraries: TStringArray; Const Root: String);
Const
  Preferred: Array[0..10] Of String = (
    'hunspell.dll', 'hunspelllo.dll', 'libhunspelllo.dll', 'libhunspell.dll',
    'libhunspell-1.7.dll', 'libhunspell-1.7-0.dll', 'libhunspell-1.6.dll',
    'lnglo.dll', 'lng.dll', 'spell.dll', 'spelllo.dll');
Var
  ProgramDir, FileName, LowerName, Imported: String;
  Index, ImportIndex: Integer;
  Info: TDirectoryScan;
  Imports: TStringArray;
Begin
  ProgramDir := IncludeTrailingPathDelimiter(Root) + 'program';
  If Not DirectoryExistsUTF8(ProgramDir) Then
    Begin
      RememberRelatedDll('no program folder');
      Exit;
    End;
  For Index := 0 To High(Preferred) Do
    If FileExistsUTF8(IncludeTrailingPathDelimiter(ProgramDir) + Preferred[Index]) Then
      RememberRelatedDll(Preferred[Index]);
  If StartDirectoryScan(IncludeTrailingPathDelimiter(ProgramDir) + '*.dll', faAnyFile, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If (Info.Attr And faDirectory) <> 0 Then
        Continue;
      LowerName := LowerCase(Info.Name);
      FileName := IncludeTrailingPathDelimiter(ProgramDir) + Info.Name;
      If (Pos('huns', LowerName) > 0) Or (Pos('spell', LowerName) > 0) Or (Pos('lng', LowerName) > 0) Then
        RememberRelatedDll(Info.Name);
      If (Pos('huns', LowerName) > 0) Or (Pos('spell', LowerName) > 0) Then
        AppendUniqueFile(Libraries, FileName);
      Imports := PeImportedDllNames(FileName);
      For ImportIndex := 0 To High(Imports) Do
        If (Pos('huns', LowerCase(Imports[ImportIndex])) > 0) Or (Pos('spell', LowerCase(Imports[ImportIndex])) > 0) Then
          Begin
            RememberRelatedDll(Info.Name + ' imports ' + Imports[ImportIndex]);
            Imported := IncludeTrailingPathDelimiter(ProgramDir) + ExtractFileName(Imports[ImportIndex]);
            If FileExistsUTF8(Imported) Then
              AppendUniqueFile(Libraries, Imported);
          End;
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
  Index := 0;
  While Index <= High(Libraries) Do
    Begin
      If DllExportsHunspell(Libraries[Index]) Then
        Inc(Index)
      Else
        Begin
          { Keep only DLLs that export the Hunspell C API. }
          If Index < High(Libraries) Then
            Libraries[Index] := Libraries[High(Libraries)];
          SetLength(Libraries, Length(Libraries) - 1);
        End;
    End;
End;

Procedure AddDictionariesUnder(Var Dirs: TStringArray; Const Parent: String; Levels: Integer);
Var
  Info: TDirectoryScan;
  Child: String;
Begin
  If (Parent = '') Or (Levels < 0) Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  If DirectoryHasAffDicPair(Parent) Then
    AppendUniqueDirectory(Dirs, Parent);
  If Levels = 0 Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        Begin
          Child := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          AddDictionariesUnder(Dirs, Child, Levels - 1);
        End;
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Procedure ExtractPackedDictionaries(Var Dirs: TStringArray; Const Folder: String);
Var
  Info: TDirectoryScan;
  PackedFile, DestDir: String;
  UnZip: TUnZipper;
Begin
  If (Folder = '') Or (Not DirectoryExistsUTF8(Folder)) Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Folder) + '*.oxt', faAnyFile, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If (Info.Attr And faDirectory) <> 0 Then
        Continue;
      PackedFile := IncludeTrailingPathDelimiter(Folder) + Info.Name;
      DestDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'LazWorkflowSpell\' + ChangeFileExt(Info.Name, '');
      If Not DirectoryHasAffDicPair(DestDir) Then
        Try
          If Not ForceDirectoriesUTF8(DestDir) Then
            Continue;
          UnZip := TUnZipper.Create;
          Try
            UnZip.FileName := PackedFile;
            UnZip.OutputPath := DestDir;
            UnZip.Examine;
            UnZip.UnZipAllFiles;
          Finally
            UnZip.Free;
          End;
        Except
          On Exception Do
            Continue;
        End;
      AddDictionariesUnder(Dirs, DestDir, 3);
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
End;

Procedure AddInstallDictionaries(Var Dirs: TStringArray; Const Root: String);
Var
  Extensions: String;
  Info: TDirectoryScan;
Begin
  AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(Root) + 'share', 4);
  Extensions := IncludeTrailingPathDelimiter(Root) + 'share\extensions';
  ExtractPackedDictionaries(Dirs, Extensions);
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Extensions) + '*', faDirectory, Info) = 0 Then
    Try
      Repeat
        If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
          ExtractPackedDictionaries(Dirs, IncludeTrailingPathDelimiter(Extensions) + Info.Name);
      Until AdvanceDirectoryScan(Info) <> 0;
    Finally
      CloseDirectoryScan(Info);
    End;
End;

Procedure AddProfileDictionaries(Var Dirs: TStringArray);
Var
  AppData, LocalData: String;
Begin
  AppData := GetEnvironmentVariableUTF8('APPDATA');
  LocalData := GetEnvironmentVariableUTF8('LOCALAPPDATA');
  If AppData <> '' Then
    AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(AppData) + 'LibreOffice', 8);
  If LocalData <> '' Then
    AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(LocalData) + 'LibreOffice', 6);
End;

Procedure DiscoverWindowsHunspell(Var Libraries, Dictionaries: TStringArray);
Var
  Roots: TStringArray;
  Index: Integer;
  FoundText: String;
Begin
  Libraries := Nil;
  Dictionaries := Nil;
  Roots := Nil;
  WindowsRelatedDlls := '';
  Try
    CollectLibreOfficeRoots(Roots);
  Except
    On E: Exception Do
      If Assigned(WorkflowLogger) Then
        WorkflowLogger.Debug('Spell', 'Windows Hunspell install scan failed: ' + E.Message);
  End;
  For Index := 0 To High(Roots) Do
    Begin
      AppendProgramLibraries(Libraries, Roots[Index]);
      AddInstallDictionaries(Dictionaries, Roots[Index]);
    End;
  AddProfileDictionaries(Dictionaries);
  If Length(Roots) = 0 Then
    WindowsDiscoveryNote := 'LibreOffice was not found. No soffice.exe in Program Files, App Paths, PATH, or the Start Menu.'
  Else If Length(Libraries) = 0 Then
    Begin
      WindowsDiscoveryNote := 'Found LibreOffice at ' + Roots[0] + ' but no loadable Hunspell library';
      If WindowsRelatedDlls <> '' Then
        WindowsDiscoveryNote := WindowsDiscoveryNote + '. Saw ' + WindowsRelatedDlls;
    End
  Else If Length(Dictionaries) = 0 Then
    WindowsDiscoveryNote := 'Found ' + Libraries[0] + ' but no .aff/.dic dictionary'
  Else
    WindowsDiscoveryNote := '';
  If Not Assigned(WorkflowLogger) Then
    Exit;
  If Length(Libraries) = 0 Then
    WorkflowLogger.Info('Spell', WindowsDiscoveryNote)
  Else
    WorkflowLogger.Info('Spell', 'Windows Hunspell library ' + Libraries[0]);
  If Length(Dictionaries) = 0 Then
    WorkflowLogger.Debug('Spell', 'Windows Hunspell dictionaries not found')
  Else
    Begin
      FoundText := Dictionaries[0];
      For Index := 1 To High(Dictionaries) Do
        FoundText := FoundText + '; ' + Dictionaries[Index];
      WorkflowLogger.Info('Spell', 'Windows Hunspell dictionaries ' + FoundText);
    End;
End;

Procedure EnsureWindowsHunspellConfig;
Begin
  EnterCriticalSection(WindowsHunspellLock);
  Try
    If WindowsConfigReady Then
      Exit;
    DiscoverWindowsHunspell(WindowsLibraryFiles, WindowsDictionaryDirs);
    WindowsConfigReady := True;
  Finally
    LeaveCriticalSection(WindowsHunspellLock);
  End;
End;

Function WindowsHunspellLibraryFiles: TStringArray;
Begin
  EnsureWindowsHunspellConfig;
  Result := WindowsLibraryFiles;
End;

Function WindowsHunspellDictionaryDirectories: TStringArray;
Begin
  EnsureWindowsHunspellConfig;
  Result := WindowsDictionaryDirs;
End;

Function WindowsDirectoryHasAffDicPair(Const Dir: String): Boolean;
Begin
  Result := DirectoryHasAffDicPair(Dir);
End;

Function WindowsHunspellDiscoveryNote: String;
Begin
  EnsureWindowsHunspellConfig;
  Result := WindowsDiscoveryNote;
End;

Procedure ResetWindowsHunspellDiscovery;
Begin
  EnterCriticalSection(WindowsHunspellLock);
  Try
    WindowsConfigReady := False;
    WindowsLibraryFiles := Nil;
    WindowsDictionaryDirs := Nil;
    WindowsDiscoveryNote := '';
    WindowsRelatedDlls := '';
  Finally
    LeaveCriticalSection(WindowsHunspellLock);
  End;
End;

Procedure AppendWindowsChildDictionaries(Var Dirs: TStringArray; Const Parent: String);
Var
  Info: TDirectoryScan;
  Child: String;
Begin
  If (Parent = '') Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  If StartDirectoryScan(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        Begin
          Child := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          If DirectoryHasAffDicPair(Child) Then
            AppendUniqueDirectory(Dirs, Child);
        End;
    Until AdvanceDirectoryScan(Info) <> 0;
  Finally
    CloseDirectoryScan(Info);
  End;
End;
{$ELSE}
Function WindowsHunspellLibraryFiles: TStringArray;
Begin
  Result := Nil;
End;

Function WindowsHunspellDictionaryDirectories: TStringArray;
Begin
  Result := Nil;
End;

Function WindowsDirectoryHasAffDicPair(Const Dir: String): Boolean;
Begin
  Result := False;
  If Dir = '' Then
    Result := False;
End;

Function WindowsHunspellDiscoveryNote: String;
Begin
  Result := '';
End;

Procedure ResetWindowsHunspellDiscovery;
Begin
End;

Procedure AppendWindowsChildDictionaries(Var Dirs: TStringArray; Const Parent: String);
Begin
  If (Parent = '') Or (Length(Dirs) < 0) Then
    Exit;
End;
{$ENDIF}

Function TryLoadHunspellAlteredSearch(Const FileName: String; Out Handle: TLibHandle; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  WideName: UnicodeString;
  ErrorCode: DWORD;
{$ENDIF}
Begin
  Handle := NilHandle;
  ErrorText := '';
  Result := False;
  If FileName = '' Then
    Exit;
  {$IFDEF WINDOWS}
  Result := (Pos('\', FileName) > 0) Or (Pos('/', FileName) > 0);
  If Not Result Then
    Exit;
  WideName := UTF8Decode(FileName);
  Handle := TLibHandle(LoadLibraryExW(PWideChar(WideName), 0, LOAD_WITH_ALTERED_SEARCH_PATH));
  If Handle = NilHandle Then
    Begin
      ErrorCode := GetLastError;
      ErrorText := 'Could not load ' + FileName + ' (Windows error ' + IntToStr(ErrorCode) + ')';
    End;
  {$ELSE}
  Result := False;
  {$ENDIF}
End;

{$IFDEF WINDOWS}
Initialization
  InitCriticalSection(WindowsHunspellLock);
Finalization
  DoneCriticalSection(WindowsHunspellLock);
{$ENDIF}

End.
