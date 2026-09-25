Unit WorkflowSettings;

{ IDE-wide LazWorkflow.json. One section is replaced at a time; other keys are kept.
  Legacy settings filenames are not read. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, fpjson;

Const
  WorkflowSettingsFileName = 'LazWorkflow.json';

Function IsRejectedSettingsFileName(Const FileName: String): Boolean;
{ Deletes obsolete settings files in the current directory. Does not read them. }
Procedure RemoveObsoleteSettingsFiles;
Procedure SetWorkflowSettingsDirectory(Const ConfigDirectory: String);
Function WorkflowSettingsDirectory: String;
Function WorkflowSettingsPath: String;
{ Nil when the section is absent or the document is missing or invalid. Caller frees. }
Function ReadWorkflowSection(Const SectionName: String): TJSONObject;
Function WriteWorkflowSection(Const SectionName: String; Section: TJSONObject; Out ErrorText: String): Boolean;

Implementation

Uses
  Classes, LazFileUtils{$IFDEF UNIX}, BaseUnix{$ENDIF};

Var
  SettingsDirectory: String;

Function IsRejectedSettingsFileName(Const FileName: String): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(ExtractFileName(FileName));
  Result := (Name = 'lazassistanttools.xml') Or (Name = 'lazgrokchat.xml') Or
    (Name = 'lazrepositorytools.xml') Or (Name = 'lazgitmanager.xml') Or
    (Name = 'lazworkflowspell.xml') Or (Name = 'assistant-connections.ini') Or
    (Name = 'assistant-backend.ini');
End;

Procedure DeletePlainFile(Const Path: String);
Begin
  If (Path = '') Or FileIsSymlink(Path) Then Exit;
  If FileExistsUTF8(Path) Then
    DeleteFileUTF8(Path);
End;

Function RemovePlainDirectory(Const Directory: String): Boolean;
Var
  Info: TSearchRec;
  Child: String;
  Found: Integer;
Begin
  Result := False;
  If (Directory = '') Or FileIsSymlink(Directory) Or (Not DirectoryExistsUTF8(Directory)) Then Exit;
  Found := FindFirstUTF8(IncludeTrailingPathDelimiter(Directory) + '*', faAnyFile Or faSymLink, Info);
  If Found = 0 Then
    Begin
      Try
        Repeat
          If (Info.Name = '.') Or (Info.Name = '..') Then Continue;
          Child := IncludeTrailingPathDelimiter(Directory) + Info.Name;
          If FileIsSymlink(Child) Or ((Info.Attr And faSymLink) <> 0) Then
            Begin
              If Not DeleteFileUTF8(Child) Then Exit;
            End
          Else If (Info.Attr And faDirectory) <> 0 Then
            Begin
              If Not RemovePlainDirectory(Child) Then Exit;
            End
          Else If Not DeleteFileUTF8(Child) Then Exit;
        Until FindNextUTF8(Info) <> 0;
      Finally
        FindCloseUTF8(Info);
      End;
    End;
  Result := RemoveDir(Directory);
End;

Procedure RemoveObsoleteSettingsFiles;
Var
  Dir, Name, Tests, Child: String;
  Info: TSearchRec;
  Found: Integer;
Const
  ObsoleteNames: Array[0..20] Of String = (
    'LazAssistantTools.xml', 'LazAssistantTools.xml.bak', 'LazAssistantTools.xml~',
    'LazGrokChat.xml', 'LazGrokChat.xml.bak', 'LazGrokChat.xml~',
    'LazRepositoryTools.xml', 'LazRepositoryTools.xml.bak', 'LazRepositoryTools.xml~',
    'LazGitManager.xml', 'LazGitManager.xml.bak', 'LazGitManager.xml~',
    'LazWorkflowSpell.xml', 'LazWorkflowSpell.xml.bak', 'LazWorkflowSpell.xml~',
    'assistant-connections.ini', 'assistant-connections.ini.tmp', 'assistant-connections.ini.bak',
    'assistant-backend.ini', 'assistant-backend.ini.tmp', 'assistant-backend.ini.bak');
Begin
  Dir := SettingsDirectory;
  If Dir = '' Then Exit;
  For Name In ObsoleteNames Do
    DeletePlainFile(Dir + Name);
  DeletePlainFile(Dir + 'LazWorkflowPersonal.dic');
  DeletePlainFile(Dir + 'LazWorkflowPersonal.dic.bak');
  Tests := Dir + 'assistant-tests';
  If DirectoryExistsUTF8(Tests) And (Not FileIsSymlink(Tests)) Then
    Begin
      Found := FindFirstUTF8(IncludeTrailingPathDelimiter(Tests) + '*', faAnyFile, Info);
      If Found = 0 Then
        Begin
          Try
            Repeat
              If (Info.Name = '.') Or (Info.Name = '..') Then Continue;
              Child := IncludeTrailingPathDelimiter(Tests) + Info.Name;
              If FileIsSymlink(Child) Then Continue;
              Name := LowerCase(ExtractFileExt(Info.Name));
              If (Name = '.ini') Or (Name = '.tmp') Or (Name = '.bak') Then
                DeleteFileUTF8(Child);
            Until FindNextUTF8(Info) <> 0;
          Finally
            FindCloseUTF8(Info);
          End;
        End;
      RemoveDir(Tests);
    End;
  { Old Codex homes. The current profile is codex/<connection-id>/ and is not removed. }
  If Not FileIsSymlink(Dir + 'assistant-codex-preview') Then
    RemovePlainDirectory(Dir + 'assistant-codex-preview');
  If Not FileIsSymlink(Dir + 'assistant-codex-connections') Then
    RemovePlainDirectory(Dir + 'assistant-codex-connections');
End;

Procedure SetWorkflowSettingsDirectory(Const ConfigDirectory: String);
Begin
  SettingsDirectory := Trim(ConfigDirectory);
  If SettingsDirectory <> '' Then
    SettingsDirectory := IncludeTrailingPathDelimiter(SettingsDirectory);
  RemoveObsoleteSettingsFiles;
End;

Function WorkflowSettingsDirectory: String;
Begin
  Result := SettingsDirectory;
End;

Function WorkflowSettingsPath: String;
Begin
  If SettingsDirectory = '' Then
    Result := ''
  Else
    Result := SettingsDirectory + WorkflowSettingsFileName;
End;

Function LoadDocument: TJSONObject;
Var
  Path: String;
  Lines: TStringList;
  Data: TJSONData;
Begin
  Result := TJSONObject.Create;
  Path := WorkflowSettingsPath;
  If (Path = '') Or IsRejectedSettingsFileName(Path) Or (Not FileExistsUTF8(Path)) Then
    Exit;
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Try
      Lines.LoadFromFile(Path);
      Data := GetJSON(Lines.Text);
      If Data Is TJSONObject Then
        Begin
          Result.Free;
          Result := TJSONObject(Data);
          Data := Nil;
        End;
    Except
      { Invalid document: defaults, no legacy fallback. }
    End;
  Finally
    Data.Free;
    Lines.Free;
  End;
End;

Function SaveDocument(Document: TJSONObject; Out ErrorText: String): Boolean;
Var
  Path, Temp: String;
  Lines: TStringList;
Begin
  Result := False;
  ErrorText := '';
  Path := WorkflowSettingsPath;
  If (Path = '') Or IsRejectedSettingsFileName(Path) Or (Not Assigned(Document)) Then
    Begin
      ErrorText := 'Workflow settings directory is not set.';
      Exit;
    End;
  If Not ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(SettingsDirectory)) Then
    Begin
      ErrorText := 'Could not create the workflow settings directory.';
      Exit;
    End;
  Temp := Path + '.tmp';
  Lines := TStringList.Create;
  Try
    Try
      Lines.Text := Document.FormatJSON;
      Lines.SaveToFile(Temp);
      {$IFDEF UNIX}
      If fpChmod(Temp, &600) <> 0 Then
        Raise Exception.Create('Could not protect workflow settings.');
      {$ENDIF}
      If Not RenameFile(Temp, Path) Then
        Begin
          DeleteFileUTF8(Path);
          If Not RenameFile(Temp, Path) Then
            Raise Exception.Create('Could not replace workflow settings.');
        End;
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          DeleteFileUTF8(Temp);
        End;
    End;
  Finally
    Lines.Free;
  End;
End;

Function ReadWorkflowSection(Const SectionName: String): TJSONObject;
Var
  Document: TJSONObject;
  Node: TJSONData;
Begin
  Result := Nil;
  If Trim(SectionName) = '' Then
    Exit;
  Document := LoadDocument;
  Try
    Node := Document.Find(SectionName);
    If Node Is TJSONObject Then
      Result := TJSONObject(Node.Clone);
  Finally
    Document.Free;
  End;
End;

Function WriteWorkflowSection(Const SectionName: String; Section: TJSONObject; Out ErrorText: String): Boolean;
Var
  Document: TJSONObject;
Begin
  Result := False;
  ErrorText := '';
  If (Trim(SectionName) = '') Or (Not Assigned(Section)) Then
    Begin
      ErrorText := 'A settings section is required.';
      Exit;
    End;
  Document := LoadDocument;
  Try
    If Assigned(Document.Find(SectionName)) Then
      Document.Delete(SectionName);
    Document.Add(SectionName, TJSONObject(Section.Clone));
    Result := SaveDocument(Document, ErrorText);
  Finally
    Document.Free;
  End;
End;

End.
