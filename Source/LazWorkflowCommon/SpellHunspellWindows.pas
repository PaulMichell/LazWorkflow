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
Procedure AppendWindowsChildDictionaries(Var Dirs: TStringArray; Const Parent: String);

Implementation

Uses
  LazFileUtils, LazUTF8, WorkflowLog
  {$IFDEF WINDOWS}
  , Windows, Registry
  {$ENDIF}
  ;

{$IFDEF WINDOWS}
Var
  WindowsHunspellLock: TRTLCriticalSection;
  WindowsConfigReady: Boolean = False;
  WindowsLibraryFiles: TStringArray = Nil;
  WindowsDictionaryDirs: TStringArray = Nil;

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
    DirectoryExistsUTF8(IncludeTrailingPathDelimiter(Path) + 'share\extensions');
End;

Procedure AddLibreOfficeRoot(Var Roots: TStringArray; Const Path: String);
Var
  Index: Integer;
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Trim(Path));
  If (Length(Clean) >= 2) And (Clean[1] = '"') And (Clean[Length(Clean)] = '"') Then
    Clean := ExcludeTrailingPathDelimiter(Trim(Copy(Clean, 2, Length(Clean) - 2)));
  If (Clean = '') Or (Not IsLibreOfficeRoot(Clean)) Then
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
    If Reg.ValueExists(ValueName) Then
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

Procedure ScanAppPathRoot(RootKey: HKEY; Access: LongWord; Var Roots: TStringArray);
Var
  Reg: TRegistry;
Begin
  Reg := TRegistry.Create(Access);
  Try
    Reg.RootKey := RootKey;
    If Not OpenRegistryKey(Reg, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\soffice.exe') Then
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
        0: ScanAppPathRoot(RootKey, Access, Roots);
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
  AddLibreOfficeChildren(Roots, GetEnvironmentVariableUTF8('ProgramW6432'));
  AddLibreOfficeChildren(Roots, GetEnvironmentVariableUTF8('ProgramFiles'));
  AddLibreOfficeChildren(Roots, GetEnvironmentVariableUTF8('ProgramFiles(x86)'));
  AddLibreOfficeChildren(Roots, 'C:\Program Files');
  AddLibreOfficeChildren(Roots, 'C:\Program Files (x86)');
  LocalPrograms := GetEnvironmentVariableUTF8('LOCALAPPDATA');
  If LocalPrograms <> '' Then
    AddLibreOfficeChildren(Roots, IncludeTrailingPathDelimiter(LocalPrograms) + 'Programs');
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

Procedure AddInstallDictionaries(Var Dirs: TStringArray; Const Root: String);
Begin
  AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(Root) + 'share\extensions', 2);
  AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(Root) + 'share\dict\ooo', 1);
  AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(Root) + 'share\hunspell', 1);
End;

Procedure AddProfileDictionaries(Var Dirs: TStringArray);
Var
  AppData, LocalData: String;
Begin
  AppData := GetEnvironmentVariableUTF8('APPDATA');
  LocalData := GetEnvironmentVariableUTF8('LOCALAPPDATA');
  If AppData <> '' Then
    Begin
      AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(AppData) + 'LibreOffice\4\user\wordbook', 0);
      AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(AppData) +
        'LibreOffice\4\user\uno_packages\cache\uno_packages', 3);
    End;
  If LocalData <> '' Then
    AddDictionariesUnder(Dirs, IncludeTrailingPathDelimiter(LocalData) + 'LibreOffice\4\user\wordbook', 0);
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
  If Not Assigned(WorkflowLogger) Then
    Exit;
  If Length(Libraries) = 0 Then
    WorkflowLogger.Debug('Spell', 'Windows Hunspell library not found')
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
