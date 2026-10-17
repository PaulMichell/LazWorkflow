Unit AssistantWorkTarget;

{ IDE-thread work target. The target is the root folder for reads, writes, and
  Git. An empty folder means the current Lazarus project. A chosen folder does
  not widen to the Git root or to package membership. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, PackageIntf;

Type
  TAssistantTargetKind = (atkProject, atkPackage, atkFolder);
  TAssistantWorkTarget = Class
  Private
    FPackageFile: String;
    FFolder: String;
    FGeneration: QWord;
  Public
    Function Kind: TAssistantTargetKind;
    Function Package: TIDEPackage;
    Function Manifest: String;
    Function Identity: String;
    Function DisplayName: String;
    Function Available: Boolean;
    Function Modified: Boolean;
    Function BuildMode: String;
    Function ConfigurationStamp: String;
    Function Root: String;
    Function StoreKey: String;
    Function StoreDirectory: String;
    Procedure Members(Files: TStrings);
    Procedure Dependencies(Files: TStrings);
    Function ContainsFile(Const Filename: String): Boolean;
    Function AllowsWrite(Const Filename: String): Boolean;
    /// Refusal for a write, stage, or commit outside the selected target. Names that target.
    Function ScopeRefusal(Const Action, Path: String): String;
    Function Describe: String;
    Procedure SelectProject;
    Function SelectPackage(Const Filename: String; Out ErrorText: String): Boolean;
    /// Use Directory as the target root. Empty selects the current project.
    /// A chosen directory stays a folder even when it is the open project's directory.
    Function SelectFolder(Const Directory: String; Out ErrorText: String): Boolean;
  End;

Const
  AssistantRecentTargetLimit = 10;
  AssistantCurrentProjectCaption = 'Current Project';

Function AssistantTarget: TAssistantWorkTarget;
Function TargetPathWithin(Const Directory, Filename: String): Boolean;
Procedure LoadAssistantRecentTargets(Paths: TStrings);
Procedure RememberAssistantTarget(Const Directory: String);
Function SavedAssistantTarget: String;
Procedure SaveAssistantTarget(Const Directory: String);

Implementation

Uses
  LazIDEIntf, ProjectIntf, LazFileUtils, fpjson, AssistantProjectPaths, WorkflowSettings, sha1;

Var
  CurrentTarget: TAssistantWorkTarget;
  RecentTargets: TStringList;
  RecentTargetsLoaded: Boolean;

Function AssistantTarget: TAssistantWorkTarget;
Begin
  If Not Assigned(CurrentTarget) Then CurrentTarget := TAssistantWorkTarget.Create;
  Result := CurrentTarget;
End;

Function TargetPathWithin(Const Directory, Filename: String): Boolean;
Var
  Base, Candidate, PhysicalBase, Physical: String;
  Function PhysicalFuturePath(Const Path: String): String;
  Var
    Probe: String;
  Begin
    Probe := Path;
    While Not FileExistsUTF8(Probe) And Not DirectoryExistsUTF8(Probe) Do
      Begin
        If ExtractFileDir(Probe) = Probe Then Exit('');
        Probe := ExtractFileDir(Probe);
      End;
    Result := GetPhysicalFilename(Probe, pfeEmpty);
    If Result <> '' Then Result := ExpandFileName(Result + Copy(Path, Length(Probe) + 1, MaxInt));
  End;
Begin
  Result := False;
  If (Directory = '') Or (Filename = '') Then Exit;
  Base := IncludeTrailingPathDelimiter(ExpandFileName(Directory));
  Candidate := ExpandFileName(Filename);
  If (CompareFilenames(Copy(Candidate, 1, Length(Base)), Base) <> 0) And
    (CompareFilenames(Candidate, ExcludeTrailingPathDelimiter(Base)) <> 0) Then Exit;
  PhysicalBase := PhysicalFuturePath(ExcludeTrailingPathDelimiter(Base));
  Physical := PhysicalFuturePath(Candidate);
  If (PhysicalBase = '') Or (Physical = '') Then Exit;
  PhysicalBase := IncludeTrailingPathDelimiter(PhysicalBase);
  Result := (CompareFilenames(Copy(Physical, 1, Length(PhysicalBase)), PhysicalBase) = 0) Or
    (CompareFilenames(Physical, ExcludeTrailingPathDelimiter(PhysicalBase)) = 0);
End;

Function TAssistantWorkTarget.Kind: TAssistantTargetKind;
Begin
  If FFolder <> '' Then Result := atkFolder
  Else If FPackageFile = '' Then Result := atkProject
  Else Result := atkPackage;
End;

Function NormalizeTargetFolder(Const Directory: String): String;
Begin
  Result := Trim(Directory);
  If Result = '' Then Exit;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
End;

Procedure EnsureRecentTargets;
Var
  Section: TJSONObject;
  Node: TJSONData;
  Index: Integer;
  Path: String;
Begin
  If RecentTargetsLoaded Then Exit;
  RecentTargetsLoaded := True;
  If Not Assigned(RecentTargets) Then RecentTargets := TStringList.Create;
  RecentTargets.Clear;
  Section := ReadWorkflowSection('assistant');
  If Not Assigned(Section) Then Exit;
  Try
    Node := Section.Find('recent_targets');
    If Not (Node Is TJSONArray) Then Exit;
    For Index := 0 To TJSONArray(Node).Count - 1 Do
      Begin
        If RecentTargets.Count >= AssistantRecentTargetLimit Then Break;
        If TJSONArray(Node).Items[Index].JSONType <> jtString Then Continue;
        Path := NormalizeTargetFolder(TJSONArray(Node).Items[Index].AsString);
        If (Path = '') Or (Not DirectoryExistsUTF8(Path)) Then Continue;
        If RecentTargets.IndexOf(Path) >= 0 Then Continue;
        RecentTargets.Add(Path);
      End;
  Finally
    Section.Free;
  End;
End;

Procedure WriteTargetSettings(Const Selected: String);
Var
  Section: TJSONObject;
  Arr: TJSONArray;
  Index: Integer;
  ErrorText: String;
Begin
  EnsureRecentTargets;
  Section := ReadWorkflowSection('assistant');
  If Not Assigned(Section) Then Section := TJSONObject.Create;
  Try
    If Assigned(Section.Find('target_directory')) Then Section.Delete('target_directory');
    Section.Add('target_directory', Selected);
    If Assigned(Section.Find('recent_targets')) Then Section.Delete('recent_targets');
    Arr := TJSONArray.Create;
    Section.Add('recent_targets', Arr);
    For Index := 0 To RecentTargets.Count - 1 Do
      Arr.Add(RecentTargets[Index]);
    WriteWorkflowSection('assistant', Section, ErrorText);
  Finally
    Section.Free;
  End;
End;

Procedure LoadAssistantRecentTargets(Paths: TStrings);
Var
  Index: Integer;
Begin
  If Not Assigned(Paths) Then Exit;
  Paths.Clear;
  EnsureRecentTargets;
  For Index := 0 To RecentTargets.Count - 1 Do
    Paths.Add(RecentTargets[Index]);
End;

Procedure RememberAssistantTarget(Const Directory: String);
Var
  Path: String;
  Index: Integer;
Begin
  Path := NormalizeTargetFolder(Directory);
  If (Path = '') Or (Not DirectoryExistsUTF8(Path)) Then Exit;
  EnsureRecentTargets;
  Index := RecentTargets.IndexOf(Path);
  If Index >= 0 Then RecentTargets.Delete(Index);
  RecentTargets.Insert(0, Path);
  While RecentTargets.Count > AssistantRecentTargetLimit Do
    RecentTargets.Delete(RecentTargets.Count - 1);
  WriteTargetSettings(Path);
End;

Function SavedAssistantTarget: String;
Var
  Section: TJSONObject;
Begin
  Result := '';
  Section := ReadWorkflowSection('assistant');
  If Not Assigned(Section) Then Exit;
  Try
    Result := NormalizeTargetFolder(Section.Get('target_directory', ''));
    If (Result <> '') And (Not DirectoryExistsUTF8(Result)) Then Result := '';
  Finally
    Section.Free;
  End;
End;

Procedure SaveAssistantTarget(Const Directory: String);
Begin
  WriteTargetSettings(NormalizeTargetFolder(Directory));
End;

Function TAssistantWorkTarget.Package: TIDEPackage;
Var
  I: Integer;
  P: TIDEPackage;
Begin
  Result := Nil;
  If (FPackageFile = '') Or Not Assigned(PackageEditingInterface) Then Exit;
  For I := 0 To PackageEditingInterface.GetPackageCount - 1 Do
    Begin
      P := PackageEditingInterface.GetPackages(I);
      If Assigned(P) And (P.Filename <> '') And
        (CompareFilenames(ExpandFileName(P.Filename), FPackageFile) = 0) Then Exit(P);
    End;
End;

Function TAssistantWorkTarget.Manifest: String;
Begin
  If Kind = atkFolder Then Exit(FFolder);
  Result := FPackageFile;
  If (Kind = atkProject) And Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Result := LazarusIDE.ActiveProject.ProjectInfoFile;
End;

Function TAssistantWorkTarget.Available: Boolean;
Begin
  If Kind = atkFolder Then Result := DirectoryExistsUTF8(FFolder)
  Else If Kind = atkPackage Then Result := Assigned(Package)
  Else Result := Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject);
End;

Function TAssistantWorkTarget.Identity: String;
Var
  Owner: Pointer;
Begin
  Result := '';
  If Not Available Then Exit;
  If Kind = atkFolder Then
    Exit('2:' + IntToStr(FGeneration) + ':' + FFolder);
  If Kind = atkPackage Then Owner := Pointer(Package)
  Else Owner := Pointer(LazarusIDE.ActiveProject);
  Result := IntToStr(Ord(Kind)) + ':' + IntToStr(FGeneration) + ':' + IntToHex(PtrUInt(Owner), SizeOf(Pointer) * 2) + ':' + Manifest;
End;

Function TAssistantWorkTarget.DisplayName: String;
Begin
  If Kind = atkFolder Then Exit(FFolder);
  If Kind = atkPackage Then Result := 'Package — '
  Else Result := 'Project — ';
  If Manifest <> '' Then Result := Result + ExtractFileName(Manifest)
  Else If Available Then Result := Result + '(unsaved)'
  Else Result := Result + '(none)';
  If (Kind = atkPackage) And Not Available Then Result := Result + ' (closed)';
End;

Function TAssistantWorkTarget.Modified: Boolean;
Var
  List: TFPList;
  I: Integer;
Begin
  Result := True;
  If Not Available Then Exit;
  If Kind = atkFolder Then Exit(False);
  If Kind = atkPackage Then
    Begin
      Result := Package.Modified;
      If Result Then Exit;
      List := Nil;
      Try
        PackageEditingInterface.GetRequiredPackages(Package, List, []);
        If Assigned(List) Then For I := 0 To List.Count - 1 Do
          If TIDEPackage(List[I]).Modified Then Exit(True);
      Finally
        List.Free;
      End;
    End
          Else Result := LazarusIDE.ActiveProject.Modified;
End;

Function TAssistantWorkTarget.BuildMode: String;
Begin
  Result := '';
  If (Kind = atkProject) And Available Then Result := LazarusIDE.ActiveProject.ActiveBuildModeID;
End;

Function TAssistantWorkTarget.ConfigurationStamp: String;
Var
  List: TFPList;
  I: Integer;
  P: TIDEPackage;
  Stamps: TStringList;
Begin
  Result := BuildMode;
  If (Kind = atkPackage) And Available Then
    Begin
      Result := IntToStr(Package.ChangeStamp);
      List := Nil;
      Stamps := TStringList.Create;
      Try
        PackageEditingInterface.GetRequiredPackages(Package, List, []);
        If Assigned(List) Then For I := 0 To List.Count - 1 Do
          Begin
            P := TIDEPackage(List[I]);
            Stamps.Add(P.Filename + ':' + IntToStr(P.ChangeStamp) + ':' + BoolToStr(P.Modified, True));
          End;
        Stamps.Sort;
        Result := Result + ':' + Stamps.Text;
      Finally
        List.Free;
        Stamps.Free;
      End;
    End;
End;

Procedure TAssistantWorkTarget.Members(Files: TStrings);
Var
  I: Integer;
  Name: String;
  P: TIDEPackage;
  Proj: TLazProject;
Begin
  Files.Clear;
  If Not Available Then Exit;
  P := Package;
  Proj := Nil;
  If Kind = atkProject Then Proj := LazarusIDE.ActiveProject;
  If Assigned(P) Then
    For I := 0 To P.FileCount - 1 Do
      Begin
        If Not Assigned(P.Files[I]) Then Continue;
        Name := P.Files[I].Filename;
        If Name = '' Then Continue;
        If Not FilenameIsAbsolute(Name) Then Name := ExtractFilePath(Manifest) + Name;
        Files.Add(ExpandFileName(Name));
      End
        Else If Assigned(Proj) Then
          For I := 0 To Proj.FileCount - 1 Do
            Begin
              If Not Assigned(Proj.Files[I]) Then Continue;
              Name := Proj.Files[I].Filename;
              If Name = '' Then Continue;
              If Not FilenameIsAbsolute(Name) Then Name := ExtractFilePath(Manifest) + Name;
              Files.Add(ExpandFileName(Name));
            End;
End;

Procedure TAssistantWorkTarget.Dependencies(Files: TStrings);
Var
  List: TFPList;
  I: Integer;
Begin
  Files.Clear;
  If (Kind <> atkPackage) Or Not Available Then Exit;
  List := Nil;
  Try
    PackageEditingInterface.GetRequiredPackages(Package, List, []);
    If Assigned(List) Then For I := 0 To List.Count - 1 Do
      If TIDEPackage(List[I]).Filename <> '' Then Files.Add(ExpandFileName(TIDEPackage(List[I]).Filename));
  Finally
    List.Free;
  End;
End;

Function TAssistantWorkTarget.Root: String;
Var
  Proj: TLazProject;
  MainName, Base, Parent: String;
  Files: TStringList;
  I: Integer;
Begin
  Result := '';
  If Kind = atkFolder Then Exit(IncludeTrailingPathDelimiter(FFolder));
  If Kind = atkProject Then
    Begin
      If Not Available Then Exit;
      Proj := LazarusIDE.ActiveProject;
      MainName := '';
      If Assigned(Proj.MainFile) Then MainName := Proj.MainFile.Filename;
      Exit(ResolveAssistantProjectRoot(Proj.ProjectInfoFile, MainName));
    End;
  { Use the nearest repository when present. Otherwise use the common directory
    of the manifest and package members, never the active project's directory. }
  Base := ExtractFileDir(FPackageFile);
  Parent := Base;
  While (Parent <> '') And (Parent <> ExtractFileDir(Parent)) Do
    Begin
      If FileExistsUTF8(Parent + PathDelim + '.git' + PathDelim + 'HEAD') Or FileExistsUTF8(Parent + PathDelim + '.git') Then
        Exit(IncludeTrailingPathDelimiter(Parent));
      Parent := ExtractFileDir(Parent);
    End;
  Files := TStringList.Create;
  Try
    Members(Files);
    For I := 0 To Files.Count - 1 Do
      While Not TargetPathWithin(Base, Files[I]) And (Base <> ExtractFileDir(Base)) Do Base := ExtractFileDir(Base);
  Finally
    Files.Free;
  End;
  { Never turn filesystem/home roots into an implicit workspace. }
  If (Base = ExtractFileDir(Base)) Or (CompareFilenames(Base, ExcludeTrailingPathDelimiter(GetUserDir)) = 0) Then
    Base := ExtractFileDir(FPackageFile);
  Result := IncludeTrailingPathDelimiter(Base);
End;

Function TAssistantWorkTarget.StoreKey: String;
Begin
  Result := '';
  If Kind = atkPackage Then Result := 'package-' + SHA1Print(SHA1String(CreateRelativePath(Manifest, Root, False)));
End;

Function TAssistantWorkTarget.StoreDirectory: String;
Begin
  Result := Root;
  If Result = '' Then Exit;
  Result := Result + AssistantStoreFolderName + PathDelim;
  If StoreKey <> '' Then Result := Result + 'targets' + PathDelim + StoreKey + PathDelim;
End;

Function TAssistantWorkTarget.ContainsFile(Const Filename: String): Boolean;
Var
  Files: TStringList;
  I: Integer;
Begin
  If Kind <> atkPackage Then Exit(TargetPathWithin(Root, Filename));
  Result := False;
  If Filename = '' Then Exit;
  Files := TStringList.Create;
  Try
    Members(Files);
    For I := 0 To Files.Count - 1 Do If CompareFilenames(ExpandFileName(Filename), Files[I]) = 0 Then Exit(True);
  Finally
    Files.Free;
  End;
End;

Function TAssistantWorkTarget.AllowsWrite(Const Filename: String): Boolean;
Var
  Files: TStringList;
  I: Integer;
  Ext: String;
Begin
  Result := False;
  If Not Available Or Not TargetPathWithin(Root, Filename) Then Exit;
  If Kind <> atkPackage Then Exit(True);
  If Package.ReadOnly Then Exit;
  Ext := LowerCase(ExtractFileExt(Filename));
  If (Ext = '.lpk') Or (Ext = '.lpi') Then Exit;
  If TargetPathWithin(Root + 'Documents', Filename) Then Exit(True);
  Files := TStringList.Create;
  Try
    Members(Files);
    For I := 0 To Files.Count - 1 Do
      If TargetPathWithin(ExtractFileDir(Files[I]), Filename) Then Exit(True);
  Finally
    Files.Free;
  End;
End;

Function TAssistantWorkTarget.ScopeRefusal(Const Action, Path: String): String;
Begin
  If Kind = atkPackage Then
    Result := 'Cannot ' + Action + ' ' + Path + '. The selected target is ' + DisplayName +
      '. Writes, staging, and commits stay in that package''s member directories and in Documents/ under the working root. ' +
      'Choose the current project as the Assistant target to include the rest of the repository. The active plan stays with you.'
  Else
    Result := 'Cannot ' + Action + ' ' + Path + '. It is outside the selected target ' + DisplayName + '.';
End;

Function TAssistantWorkTarget.Describe: String;
Var
  Files: TStringList;
  I: Integer;
Begin
  Result := 'Target: ' + DisplayName + LineEnding + 'Manifest: ' + Manifest + LineEnding + 'Target root: ' + Root + LineEnding;
  Files := TStringList.Create;
  Try
    Members(Files);
    Result := Result + 'Target files:' + LineEnding;
    For I := 0 To Files.Count - 1 Do
      Begin
        If I >= 250 Then
          Begin
            Result := Result + '  (remaining files omitted)' + LineEnding;
            Break;
          End;
        Result := Result + '  ' + Files[I] + LineEnding;
      End;
    Dependencies(Files);
    Result := Result + 'Required packages (context, not added write roots):' + LineEnding;
    For I := 0 To Files.Count - 1 Do Result := Result + '  ' + Files[I] + LineEnding;
    If Kind = atkFolder Then
      Result := Result + 'Writes: any path inside the target.' + LineEnding
    Else If Kind = atkPackage Then
      Result := Result + 'Writes: member directories and Documents within the target; package metadata is managed separately in Lazarus.' + LineEnding;
  Finally
    Files.Free;
  End;
End;

Procedure TAssistantWorkTarget.SelectProject;
Begin
  FPackageFile := '';
  FFolder := '';
  Inc(FGeneration);
End;

Function TAssistantWorkTarget.SelectFolder(Const Directory: String; Out ErrorText: String): Boolean;
Var
  Path: String;
Begin
  Result := False;
  ErrorText := '';
  Path := NormalizeTargetFolder(Directory);
  If Path = '' Then
    Begin
      SelectProject;
      Result := True;
      Exit;
    End;
  If Not DirectoryExistsUTF8(Path) Then
    Begin
      ErrorText := 'Select an existing folder.';
      Exit;
    End;
  If Path = ExtractFileDir(Path) Then
    Begin
      ErrorText := 'The filesystem root cannot be the target.';
      Exit;
    End;
  FPackageFile := '';
  FFolder := Path;
  Inc(FGeneration);
  Result := True;
End;

Function TAssistantWorkTarget.SelectPackage(Const Filename: String; Out ErrorText: String): Boolean;
Var
  Previous, PreviousFolder: String;
Begin
  Result := False;
  ErrorText := '';
  If (Filename = '') Or Not SameText(ExtractFileExt(Filename), '.lpk') Then
    Begin
      ErrorText := 'Select a saved Lazarus package (.lpk).';
      Exit;
    End;
  Previous := FPackageFile;
  PreviousFolder := FFolder;
  FFolder := '';
  FPackageFile := ExpandFileName(Filename);
  If Not Available Then
    Begin
      FPackageFile := Previous;
      FFolder := PreviousFolder;
      ErrorText := 'Open the package in Lazarus before selecting it.';
      Exit;
    End;
  Inc(FGeneration);
  Result := True;
End;

Finalization
FreeAndNil(RecentTargets);
FreeAndNil(CurrentTarget);
End.
