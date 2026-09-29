Unit SpellCheckerSettingsFrame;

{ Shared spell-checker settings frame (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, SpellCheckerOptions;

Type
  TSpellCheckerSettingsFrame = Class(TFrame)
    SpellGroup: TGroupBox;
    EngineLabel: TLabel;
    EngineCombo: TComboBox;
    LanguageLabel: TLabel;
    LanguageCombo: TComboBox;
    LibraryLabel: TLabel;
    LibraryEdit: TEdit;
    DictDirLabel: TLabel;
    DictDirEdit: TEdit;
    StatusLabel: TLabel;
    LocateButton: TButton;
    Procedure EngineComboChange(Sender: TObject);
    Procedure LocateButtonClick(Sender: TObject);
  Private
    Procedure FillLanguageCombo(Const Selected: String);
    Procedure UpdatePreviewStatus;
  Public
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
    Procedure OptionsFromControls(Dest: TSpellCheckerOptions);
    Procedure OptionsToControls(Source: TSpellCheckerOptions);
  End;

Implementation

{$R *.lfm}

Uses
  LazFileUtils, LazUTF8, SpellEngine, SpellCheckerConfig, SpellEngineHunspell, SpellEngineAspell;

Procedure TSpellCheckerSettingsFrame.FillLanguageCombo(Const Selected: String);
Var
  Languages: TSpellDiscoveredLanguageArray;
  Index: Integer;
  LabelText: String;
Begin
  LanguageCombo.Items.BeginUpdate;
  Try
    LanguageCombo.Items.Clear;
    LanguageCombo.Items.Add('(default)');
    If Assigned(WorkflowSpellConfig) Then
      Begin
        WorkflowSpellConfig.DiscoverLanguages(Languages);
        For Index := 0 To High(Languages) Do
          Begin
            LabelText := Languages[Index].Code + ' (' + SpellEngineKindToText(Languages[Index].SourceKind) + ')';
            LanguageCombo.Items.Add(LabelText);
            LanguageCombo.Items.Objects[LanguageCombo.Items.Count - 1] := TObject(PtrInt(Index + 1));
          End;
      End;
    If Trim(Selected) = '' Then
      LanguageCombo.ItemIndex := 0
    Else
      Begin
        LanguageCombo.ItemIndex := 0;
        For Index := 1 To LanguageCombo.Items.Count - 1 Do
          If Pos(LowerCase(Selected), LowerCase(LanguageCombo.Items[Index])) = 1 Then
            Begin
              LanguageCombo.ItemIndex := Index;
              Break;
            End;
        If LanguageCombo.ItemIndex = 0 Then
          Begin
            LanguageCombo.Items.Insert(1, Selected);
            LanguageCombo.ItemIndex := 1;
          End;
      End;
  Finally
    LanguageCombo.Items.EndUpdate;
  End;
End;

Procedure TSpellCheckerSettingsFrame.OptionsToControls(Source: TSpellCheckerOptions);
Begin
  If Not Assigned(Source) Then
    Exit;
  Case Source.EngineKind Of
    sekNone: EngineCombo.ItemIndex := 0;
    sekAuto: EngineCombo.ItemIndex := 1;
    sekHunspell: EngineCombo.ItemIndex := 2;
    sekAspell: EngineCombo.ItemIndex := 3;
  Else
    EngineCombo.ItemIndex := 1;
  End;
  LibraryEdit.Text := Source.LibraryFileName;
  DictDirEdit.Text := Source.DictionaryDirectory;
  FillLanguageCombo(Source.Language);
  UpdatePreviewStatus;
End;

Procedure TSpellCheckerSettingsFrame.OptionsFromControls(Dest: TSpellCheckerOptions);
Var
  LangItem: String;
  SpacePos: Integer;
Begin
  If Not Assigned(Dest) Then
    Exit;
  Case EngineCombo.ItemIndex Of
    0: Dest.EngineKind := sekNone;
    2: Dest.EngineKind := sekHunspell;
    3: Dest.EngineKind := sekAspell;
  Else
    Dest.EngineKind := sekAuto;
  End;
  LangItem := Trim(LanguageCombo.Text);
  If (LangItem = '') Or (LangItem = '(default)') Then
    Dest.Language := ''
  Else
    Begin
      SpacePos := Pos(' ', LangItem);
      If SpacePos > 0 Then
        Dest.Language := Copy(LangItem, 1, SpacePos - 1)
      Else
        Dest.Language := LangItem;
    End;
  Dest.LibraryFileName := Trim(LibraryEdit.Text);
  Dest.DictionaryDirectory := Trim(DictDirEdit.Text);
End;

Procedure TSpellCheckerSettingsFrame.UpdatePreviewStatus;
Var
  Preview: TSpellCheckerOptions;
  FoundLibrary: String;
Begin
  If Not Assigned(StatusLabel) Then
    Exit;
  Preview := TSpellCheckerOptions.Create;
  Try
    OptionsFromControls(Preview);
    If Preview.EngineKind = sekNone Then
      Begin
        StatusLabel.Caption := 'No engine loaded — memo only';
        Exit;
      End;
    FoundLibrary := '';
    If (Preview.EngineKind In [sekHunspell, sekAuto]) And FindHunspellLibrary(FoundLibrary) Then
      Begin
        If Pos('libreoffice', LowerCase(FoundLibrary)) > 0 Then
          StatusLabel.Caption := 'Hunspell library found in LibreOffice'
        Else
          StatusLabel.Caption := 'Hunspell library found';
      End
    Else If (Preview.EngineKind In [sekAspell, sekAuto]) And WorkflowSpellConfig.AspellAvailable Then
      StatusLabel.Caption := 'ASpell library found'
    Else
      StatusLabel.Caption := 'No spell library found — memo only';
    If Preview.Language <> '' Then
      StatusLabel.Caption := StatusLabel.Caption + ' · ' + Preview.Language;
  Finally
    Preview.Free;
  End;
End;

Procedure TSpellCheckerSettingsFrame.EngineComboChange(Sender: TObject);
Begin
  UpdatePreviewStatus;
End;

Procedure TSpellCheckerSettingsFrame.LoadFromConfig;
Begin
  If Assigned(WorkflowSpellConfig) Then
    OptionsToControls(WorkflowSpellConfig.Options);
End;

Procedure TSpellCheckerSettingsFrame.SaveToConfig;
Var
  NewOptions: TSpellCheckerOptions;
Begin
  If Not Assigned(WorkflowSpellConfig) Then
    Exit;
  NewOptions := TSpellCheckerOptions.Create;
  Try
    NewOptions.Assign(WorkflowSpellConfig.Options);
    OptionsFromControls(NewOptions);
    WorkflowSpellConfig.AssignOptions(NewOptions);
    WorkflowSpellConfig.Save;
    StatusLabel.Caption := WorkflowSpellConfig.LastStatus;
  Finally
    NewOptions.Free;
  End;
End;

Function ChooseDictionaryDirectory(Const Dirs: TStringArray): String;
Var
  Index: Integer;
  Parent, Candidate: String;
  SharedParent: Boolean;
Begin
  Result := '';
  If Length(Dirs) = 0 Then
    Exit;
  Parent := ExtractFileDir(Dirs[0]);
  SharedParent := (Parent <> '') And (Length(Dirs) > 1);
  If SharedParent Then
    For Index := 1 To High(Dirs) Do
      If Not SameText(ExtractFileDir(Dirs[Index]), Parent) Then
        SharedParent := False;
  If SharedParent And SameText(ExtractFileName(Parent), 'extensions') Then
    Begin
      Result := Parent;
      Exit;
    End;
  Result := Dirs[0];
  For Index := 0 To High(Dirs) Do
    Begin
      Candidate := IncludeTrailingPathDelimiter(Dirs[Index]);
      If FileExistsUTF8(Candidate + 'en_GB.dic') Or FileExistsUTF8(Candidate + 'en_US.dic') Then
        Begin
          Result := Dirs[Index];
          Exit;
        End;
    End;
End;

Function LocateHunspellInstallation(Out LibraryFile, DictDir: String): Boolean;
Var
  Dirs: TStringArray;
Begin
  LibraryFile := '';
  DictDir := '';
  Dirs := Nil;
  ConfigureWindowsHunspell(LibraryFile, Dirs);
  If LibraryFile = '' Then
    FindHunspellLibrary(LibraryFile);
  If Length(Dirs) = 0 Then
    Dirs := HunspellDictionaryDirectories;
  DictDir := ChooseDictionaryDirectory(Dirs);
  Result := (LibraryFile <> '') And (DictDir <> '');
End;

Function LocateAspellInstallation(Out LibraryFile, DictDir: String): Boolean;
{$IFDEF WINDOWS}
Var
  Roots: Array[0..2] Of String;
  Index: Integer;
  Root, Candidate: String;
{$ENDIF}
Begin
  LibraryFile := '';
  DictDir := '';
  Result := FindAspellLibrary(LibraryFile);
  {$IFDEF WINDOWS}
  If Not Result Then
    Begin
      Roots[0] := GetEnvironmentVariableUTF8('ProgramW6432');
      Roots[1] := GetEnvironmentVariableUTF8('ProgramFiles');
      Roots[2] := GetEnvironmentVariableUTF8('ProgramFiles(x86)');
      For Index := 0 To High(Roots) Do
        Begin
          Root := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Roots[Index])) + 'Aspell\';
          Candidate := Root + 'bin\aspell-15.dll';
          If Not FileExistsUTF8(Candidate) Then
            Candidate := Root + 'bin\libaspell-15.dll';
          If FileExistsUTF8(Candidate) Then
            Begin
              LibraryFile := Candidate;
              Result := True;
              Break;
            End;
        End;
    End;
  If Result And (ExtractFileDir(LibraryFile) <> '') Then
    Begin
      Candidate := IncludeTrailingPathDelimiter(ExtractFileDir(ExtractFileDir(LibraryFile))) + 'dict';
      If DirectoryExistsUTF8(Candidate) Then
        DictDir := Candidate;
    End;
  {$ENDIF}
  Result := LibraryFile <> '';
End;

Procedure TSpellCheckerSettingsFrame.LocateButtonClick(Sender: TObject);
Var
  Preview: TSpellCheckerOptions;
  LibraryFile, DictDir, SelectedLanguage: String;
  FoundKind: TSpellEngineKind;
Begin
  If Not Assigned(StatusLabel) Then
    Exit;
  Preview := TSpellCheckerOptions.Create;
  Try
    OptionsFromControls(Preview);
    SelectedLanguage := Preview.Language;
    If Preview.EngineKind = sekNone Then
      Begin
        StatusLabel.Caption := 'Select Hunspell or ASpell first';
        Exit;
      End;
    FoundKind := sekNone;
    LibraryFile := '';
    DictDir := '';
    If (Preview.EngineKind In [sekHunspell, sekAuto]) And LocateHunspellInstallation(LibraryFile, DictDir) Then
      FoundKind := sekHunspell;
    If (FoundKind = sekNone) And (Preview.EngineKind In [sekAspell, sekAuto]) And
       LocateAspellInstallation(LibraryFile, DictDir) Then
      FoundKind := sekAspell;
    If FoundKind = sekNone Then
      Begin
        StatusLabel.Caption := 'No installation found for the selected spell checker';
        Exit;
      End;
    If (Preview.EngineKind = sekAuto) And (FoundKind = sekAspell) Then
      EngineCombo.ItemIndex := 3;
    If LibraryFile <> '' Then
      LibraryEdit.Text := LibraryFile;
    If DictDir <> '' Then
      DictDirEdit.Text := DictDir;
    SaveToConfig;
    FillLanguageCombo(SelectedLanguage);
    If Assigned(WorkflowSpellConfig) And (WorkflowSpellConfig.LastStatus <> '') Then
      StatusLabel.Caption := WorkflowSpellConfig.LastStatus
    Else
      Begin
        StatusLabel.Caption := 'Configured ' + SpellEngineKindToText(FoundKind) + '. Library ' + LibraryFile;
        If DictDir <> '' Then
          StatusLabel.Caption := StatusLabel.Caption + '. Dictionaries ' + DictDir;
      End;
  Finally
    Preview.Free;
  End;
End;

Initialization

RegisterClass(TSpellCheckerSettingsFrame);

End.
