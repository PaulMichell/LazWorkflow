Unit SpellHunspellWindows;

{ Windows Hunspell/LibreOffice discovery (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

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
  , Windows, Registry, Zipper
  {$ENDIF}
  ;

{$IFDEF WINDOWS}
Var
  WindowsHunspellLock: TRTLCriticalSection;
  WindowsConfigReady: Boolean = False;
  WindowsLibraryFiles: TStringArray = Nil;
  WindowsDictionaryDirs: TStringArray = Nil;
  WindowsDiscoveryNote: String = '';

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
  Info: TSearchRec;
  DicResult: Integer;
Begin
  Result := False;
  If (Dir = '') Or (Not DirectoryExistsUTF8(Dir)) Then
    Exit;
  DicResult := FindFirstUTF8(IncludeTrailingPathDelimiter(Dir) + '*.dic', faAnyFile, Info);
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
        DicResult := FindNextUTF8(Info);
      End;
  Finally
    FindCloseUTF8(Info);
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
  Info: TSearchRec;
  Target, LowerTarget: String;
Begin
  If (Folder = '') Or (Depth < 0) Or (Not DirectoryExistsUTF8(Folder)) Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Folder) + '*.lnk', faAnyFile, Info) = 0 Then
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
      Until FindNextUTF8(Info) <> 0;
    Finally
      FindCloseUTF8(Info);
    End;
  If Depth = 0 Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Folder) + '*', faDirectory, Info) = 0 Then
    Try
      Repeat
        If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
          AddShortcutsIn(Roots, IncludeTrailingPathDelimiter(Folder) + Info.Name, Depth - 1);
      Until FindNextUTF8(Info) <> 0;
    Finally
      FindCloseUTF8(Info);
    End;
End;

Procedure AddInstallCandidates(Var Roots: TStringArray; Const Parent: String; Depth: Integer);
Var
  Info: TSearchRec;
  Child, LowerName: String;
Begin
  If (Parent = '') Or (Depth < 0) Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  AddLibreOfficeRoot(Roots, Parent);
  If Depth = 0 Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
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
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
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
  Info: TSearchRec;
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Parent);
  If (Clean = '') Or (Not DirectoryExistsUTF8(Clean)) Then
    Exit;
  AddLibreOfficeRoot(Roots, Clean + '\LibreOffice');
  If FindFirstUTF8(Clean + '\LibreOffice*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        AddLibreOfficeRoot(Roots, Clean + '\' + Info.Name);
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
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

Procedure AppendProgramLibraries(Var Libraries: TStringArray; Const Root: String);
Const
  Preferred: Array[0..6] Of String = (
    'hunspell.dll', 'libhunspell-1.7.dll', 'libhunspell-1.7-0.dll', 'libhunspell.dll',
    'libhunspell-1.6.dll', 'libhunspell-1.6-0.dll', 'hunspelllo.dll');
Var
  ProgramDir, LowerName: String;
  Index: Integer;
  Info: TSearchRec;
  Masks: Array[0..1] Of String;
Begin
  ProgramDir := IncludeTrailingPathDelimiter(Root) + 'program';
  If Not DirectoryExistsUTF8(ProgramDir) Then
    Exit;
  For Index := 0 To High(Preferred) Do
    AppendUniqueFile(Libraries, IncludeTrailingPathDelimiter(ProgramDir) + Preferred[Index]);
  Masks[0] := 'hunspell*.dll';
  Masks[1] := 'libhunspell*.dll';
  For Index := 0 To High(Masks) Do
    If FindFirstUTF8(IncludeTrailingPathDelimiter(ProgramDir) + Masks[Index], faAnyFile, Info) = 0 Then
      Try
        Repeat
          LowerName := LowerCase(Info.Name);
          If ((Info.Attr And faDirectory) = 0) And (Pos('hunspell', LowerName) > 0) Then
            AppendUniqueFile(Libraries, IncludeTrailingPathDelimiter(ProgramDir) + Info.Name);
        Until FindNextUTF8(Info) <> 0;
      Finally
        FindCloseUTF8(Info);
      End;
End;

Procedure AddDictionariesUnder(Var Dirs: TStringArray; Const Parent: String; Levels: Integer);
Var
  Info: TSearchRec;
  Child: String;
Begin
  If (Parent = '') Or (Levels < 0) Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  If DirectoryHasAffDicPair(Parent) Then
    AppendUniqueDirectory(Dirs, Parent);
  If Levels = 0 Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        Begin
          Child := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          AddDictionariesUnder(Dirs, Child, Levels - 1);
        End;
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
  End;
End;

Procedure ExtractPackedDictionaries(Var Dirs: TStringArray; Const Folder: String);
Var
  Info: TSearchRec;
  PackedFile, DestDir: String;
  UnZip: TUnZipper;
Begin
  If (Folder = '') Or (Not DirectoryExistsUTF8(Folder)) Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Folder) + '*.oxt', faAnyFile, Info) <> 0 Then
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
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
  End;
End;

Procedure AddInstallDictionaries(Var Dirs: TStringArray; Const Root: String);
Var
  Extensions: String;
  Info: TSearchRec;
Begin
  AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(Root) + 'share', 4);
  Extensions := IncludeTrailingPathDelimiter(Root) + 'share\extensions';
  ExtractPackedDictionaries(Dirs, Extensions);
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Extensions) + '*', faDirectory, Info) = 0 Then
    Try
      Repeat
        If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
          ExtractPackedDictionaries(Dirs, IncludeTrailingPathDelimiter(Extensions) + Info.Name);
      Until FindNextUTF8(Info) <> 0;
    Finally
      FindCloseUTF8(Info);
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
    WindowsDiscoveryNote := 'Found LibreOffice at ' + Roots[0] + ' but program has no hunspell DLL'
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
  Finally
    LeaveCriticalSection(WindowsHunspellLock);
  End;
End;

Procedure AppendWindowsChildDictionaries(Var Dirs: TStringArray; Const Parent: String);
Var
  Info: TSearchRec;
  Child: String;
Begin
  If (Parent = '') Or (Not DirectoryExistsUTF8(Parent)) Then
    Exit;
  If FindFirstUTF8(IncludeTrailingPathDelimiter(Parent) + '*', faDirectory, Info) <> 0 Then
    Exit;
  Try
    Repeat
      If ((Info.Attr And faDirectory) <> 0) And (Info.Name <> '.') And (Info.Name <> '..') Then
        Begin
          Child := IncludeTrailingPathDelimiter(Parent) + Info.Name;
          If DirectoryHasAffDicPair(Child) Then
            AppendUniqueDirectory(Dirs, Child);
        End;
    Until FindNextUTF8(Info) <> 0;
  Finally
    FindCloseUTF8(Info);
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

{$IFDEF WINDOWS}
Initialization
  InitCriticalSection(WindowsHunspellLock);
Finalization
  DoneCriticalSection(WindowsHunspellLock);
{$ENDIF}

End.
