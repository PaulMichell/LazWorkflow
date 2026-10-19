Unit SpellCheckerSettingsFrame;

{ Shared spell-checker settings frame (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, SpellCheckerOptions, SpellEngine;

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
    EnginesFilled: Boolean;
    Procedure FillLanguageCombo(Const Selected: String);
    Procedure UpdatePreviewStatus;
    Procedure EnsureEngineItems;
    Procedure SelectEngineKind(Kind: TSpellEngineKind);
    Function SelectedEngineKind: TSpellEngineKind;
  Public
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
    Procedure OptionsFromControls(Dest: TSpellCheckerOptions);
    Procedure OptionsToControls(Source: TSpellCheckerOptions);
  End;

Implementation

{$R *.lfm}

Uses
  LazFileUtils, LazUTF8, SpellCheckerConfig, SpellEngineHunspell, SpellEngineAspell;

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

Function EngineKindCaption(Kind: TSpellEngineKind): String;
Begin
  Case Kind Of
    sekHunspell: Result := 'Hunspell (OpenOffice)';
    sekAspell: Result := 'ASpell';
    sekWindows: Result := 'Windows';
  Else
    Result := SpellEngineKindToText(Kind);
  End;
End;

Function EngineKindShortName(Kind: TSpellEngineKind): String;
Begin
  Case Kind Of
    sekHunspell: Result := 'Hunspell';
    sekAspell: Result := 'ASpell';
    sekWindows: Result := 'Windows';
  Else
    Result := SpellEngineKindToText(Kind);
  End;
End;

Function AutoEngineCaption(Const Kinds: TSpellEngineKindArray): String;
Var
  Index, Count: Integer;
  Names: Array Of String;
Begin
  Names := Nil;
  Count := 0;
  For Index := 0 To High(Kinds) Do
    Begin
      SetLength(Names, Count + 1);
      Names[Count] := EngineKindShortName(Kinds[Index]);
      Inc(Count);
    End;
  If Count = 0 Then
    Result := 'Auto'
  Else If Count = 1 Then
    Result := 'Auto (' + Names[0] + ')'
  Else
    Begin
      Result := 'Auto (';
      For Index := 0 To Count - 2 Do
        Begin
          If Index > 0 Then
            Result := Result + ', ';
          Result := Result + Names[Index];
        End;
      Result := Result + ', then ' + Names[Count - 1] + ')';
    End;
End;

Procedure TSpellCheckerSettingsFrame.SelectEngineKind(Kind: TSpellEngineKind);
Var
  Index: Integer;
Begin
  If Not Assigned(EngineCombo) Then
    Exit;
  For Index := 0 To EngineCombo.Items.Count - 1 Do
    If TSpellEngineKind(PtrInt(EngineCombo.Items.Objects[Index])) = Kind Then
      Begin
        EngineCombo.ItemIndex := Index;
        Exit;
      End;
  If EngineCombo.Items.Count > 1 Then
    EngineCombo.ItemIndex := 1
  Else
    EngineCombo.ItemIndex := 0;
End;

Function TSpellCheckerSettingsFrame.SelectedEngineKind: TSpellEngineKind;
Begin
  Result := sekAuto;
  If Not Assigned(EngineCombo) Then
    Exit;
  If (EngineCombo.ItemIndex < 0) Or (EngineCombo.ItemIndex >= EngineCombo.Items.Count) Then
    Exit;
  Result := TSpellEngineKind(PtrInt(EngineCombo.Items.Objects[EngineCombo.ItemIndex]));
End;

Procedure TSpellCheckerSettingsFrame.EnsureEngineItems;
Var
  Selected: TSpellEngineKind;
  Kinds: TSpellEngineKindArray;
  Index: Integer;
Begin
  If Not Assigned(EngineCombo) Then
    Exit;
  If EnginesFilled Then
    Selected := SelectedEngineKind
  Else
    Selected := sekAuto;
  Kinds := AvailableEngineKinds;
  EngineCombo.Items.BeginUpdate;
  Try
    EngineCombo.Items.Clear;
    EngineCombo.Items.AddObject('None', TObject(PtrInt(sekNone)));
    EngineCombo.Items.AddObject(AutoEngineCaption(Kinds), TObject(PtrInt(sekAuto)));
    For Index := 0 To High(Kinds) Do
      EngineCombo.Items.AddObject(EngineKindCaption(Kinds[Index]), TObject(PtrInt(Kinds[Index])));
  Finally
    EngineCombo.Items.EndUpdate;
  End;
  EnginesFilled := True;
  SelectEngineKind(Selected);
End;

Procedure TSpellCheckerSettingsFrame.OptionsToControls(Source: TSpellCheckerOptions);
Begin
  If Not Assigned(Source) Then
    Exit;
  EnsureEngineItems;
  SelectEngineKind(Source.EngineKind);
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
  EnsureEngineItems;
  Dest.EngineKind := SelectedEngineKind;
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
    If (Preview.EngineKind In [sekWindows, sekAuto]) And SpellEngineKindAvailable(sekWindows) Then
      Begin
        StatusLabel.Caption := 'Windows spell checker found';
        If Preview.Language <> '' Then
          StatusLabel.Caption := StatusLabel.Caption + ' · ' + Preview.Language;
        Exit;
      End;
    If Preview.EngineKind = sekWindows Then
      Begin
        StatusLabel.Caption := 'Windows spell checker is not available';
        Exit;
      End;
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
  ResetHunspellDiscovery;
  ConfigureWindowsHunspell(LibraryFile, Dirs);
  If LibraryFile = '' Then
    FindHunspellLibrary(LibraryFile);
  If Length(Dirs) = 0 Then
    Dirs := HunspellDictionaryDirectories;
  DictDir := ChooseDictionaryDirectory(Dirs);
  Result := (LibraryFile <> '') And (DictDir <> '');
End;

Function LocateAspellInstallation(Out LibraryFile, DictDir: String): Boolean;
Var
  Candidate: String;
Begin
  LibraryFile := '';
  DictDir := '';
  Result := FindAspellLibrary(LibraryFile);
  If Not Result Then
    Result := FindProgramAspellLibrary(LibraryFile);
  If Result And (ExtractFileDir(LibraryFile) <> '') Then
    Begin
      Candidate := IncludeTrailingPathDelimiter(ExtractFileDir(ExtractFileDir(LibraryFile))) + 'dict';
      If DirectoryExistsUTF8(Candidate) Then
        DictDir := Candidate;
    End;
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
    EnsureEngineItems;
    If Preview.EngineKind = sekNone Then
      Begin
        StatusLabel.Caption := 'Select a spell checker first';
        Exit;
      End;
    FoundKind := sekNone;
    LibraryFile := '';
    DictDir := '';
    If Preview.EngineKind In [sekWindows, sekAuto] Then
      If SpellEngineKindAvailable(sekWindows) Then
        Begin
          FoundKind := sekWindows;
          If Preview.EngineKind = sekWindows Then
            Begin
              SelectEngineKind(sekWindows);
              LibraryEdit.Text := '';
              DictDirEdit.Text := '';
            End;
          SaveToConfig;
          If Assigned(WorkflowSpellConfig) Then
            WorkflowSpellConfig.Apply;
          FillLanguageCombo(Preview.Language);
          If SelectedLanguage <> '' Then
            StatusLabel.Caption := 'Configured windows (' + SelectedLanguage + ')'
          Else
            StatusLabel.Caption := 'Configured windows';
          If Preview.EngineKind = sekAuto Then
            StatusLabel.Caption := StatusLabel.Caption + '. Auto uses it first on Windows.';
          Exit;
        End
      Else If Preview.EngineKind = sekWindows Then
        Begin
          StatusLabel.Caption := 'Windows spell checker is not available. Add a language in Windows settings.';
          Exit;
        End;
    If Preview.EngineKind In [sekHunspell, sekAuto] Then
      Begin
        If LocateHunspellInstallation(LibraryFile, DictDir) Then
          FoundKind := sekHunspell
        Else If (LibraryFile <> '') Or (DictDir <> '') Then
          Begin
            If LibraryFile <> '' Then
              LibraryEdit.Text := LibraryFile;
            If DictDir <> '' Then
              DictDirEdit.Text := DictDir;
            StatusLabel.Caption := HunspellDiscoveryNote;
            If StatusLabel.Caption = '' Then
              StatusLabel.Caption := 'Hunspell was only partly found';
            Exit;
          End;
      End;
    If (FoundKind = sekNone) And (Preview.EngineKind In [sekAspell, sekAuto]) And
       LocateAspellInstallation(LibraryFile, DictDir) Then
      FoundKind := sekAspell;
    If FoundKind = sekNone Then
      Begin
        StatusLabel.Caption := HunspellDiscoveryNote;
        If StatusLabel.Caption = '' Then
          StatusLabel.Caption := 'No installation found for the selected spell checker';
        Exit;
      End;
    If (Preview.EngineKind = sekAuto) And (FoundKind = sekAspell) Then
      SelectEngineKind(sekAspell);
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
