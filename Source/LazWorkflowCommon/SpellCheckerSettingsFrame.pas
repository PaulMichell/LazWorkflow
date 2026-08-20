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
    Procedure EngineComboChange(Sender: TObject);
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
  SpellEngine, SpellCheckerConfig;

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
    If (Preview.EngineKind In [sekHunspell, sekAuto]) And WorkflowSpellConfig.HunspellAvailable Then
      StatusLabel.Caption := 'Hunspell library found'
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

Initialization

RegisterClass(TSpellCheckerSettingsFrame);

End.
