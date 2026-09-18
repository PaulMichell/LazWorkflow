Unit AssistantWorkTarget;

{ IDE-thread work target. A selected package is pinned by manifest, never by an
  editor tab or a borrowed package pointer that may be destroyed by Lazarus. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, PackageIntf;

Type
  TAssistantTargetKind = (atkProject, atkPackage);
  TAssistantWorkTarget = Class
  Private
    FPackageFile: String;
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
    Function Describe: String;
    Procedure SelectProject;
    Function SelectPackage(Const Filename: String; Out ErrorText: String): Boolean;
  End;

Function AssistantTarget: TAssistantWorkTarget;
Function TargetPathWithin(Const Directory, Filename: String): Boolean;

Implementation

Uses
  LazIDEIntf, ProjectIntf, LazFileUtils, AssistantProjectPaths, sha1;

Var
  CurrentTarget: TAssistantWorkTarget;

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
  If FPackageFile = '' Then Result := atkProject
  Else Result := atkPackage;
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
  Result := FPackageFile;
  If (Kind = atkProject) And Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Result := LazarusIDE.ActiveProject.ProjectInfoFile;
End;

Function TAssistantWorkTarget.Available: Boolean;
Begin
  If Kind = atkPackage Then Result := Assigned(Package)
  Else Result := Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject);
End;

Function TAssistantWorkTarget.Identity: String;
Var
  Owner: Pointer;
Begin
  Result := '';
  If Not Available Then Exit;
  If Kind = atkPackage Then Owner := Pointer(Package)
  Else Owner := Pointer(LazarusIDE.ActiveProject);
  Result := IntToStr(Ord(Kind)) + ':' + IntToStr(FGeneration) + ':' + IntToHex(PtrUInt(Owner), SizeOf(Pointer) * 2) + ':' + Manifest;
End;

Function TAssistantWorkTarget.DisplayName: String;
Begin
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
  If Kind = atkProject Then Exit(TargetPathWithin(Root, Filename));
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
  If Kind = atkProject Then Exit(True);
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

Function TAssistantWorkTarget.Describe: String;
Var
  Files: TStringList;
  I: Integer;
Begin
  Result := 'Target: ' + DisplayName + LineEnding + 'Manifest: ' + Manifest + LineEnding + 'Working root: ' + Root + LineEnding;
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
    If Kind = atkPackage Then Result := Result + 'Writes: member directories and Documents within the working root; package metadata is managed separately in Lazarus.' + LineEnding;
  Finally
    Files.Free;
  End;
End;

Procedure TAssistantWorkTarget.SelectProject;
Begin
  FPackageFile := '';
  Inc(FGeneration);
End;

Function TAssistantWorkTarget.SelectPackage(Const Filename: String; Out ErrorText: String): Boolean;
Var
  Previous: String;
Begin
  Result := False;
  ErrorText := '';
  If (Filename = '') Or Not SameText(ExtractFileExt(Filename), '.lpk') Then
    Begin
      ErrorText := 'Select a saved Lazarus package (.lpk).';
      Exit;
    End;
  Previous := FPackageFile;
  FPackageFile := ExpandFileName(Filename);
  If Not Available Then
    Begin
      FPackageFile := Previous;
      ErrorText := 'Open the package in Lazarus before selecting it.';
      Exit;
    End;
  Inc(FGeneration);
  Result := True;
End;

Finalization
FreeAndNil(CurrentTarget);
End.
