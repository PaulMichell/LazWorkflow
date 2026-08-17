Unit SpellCheckerSettingsForm;

{ Standalone spell-checker settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, ButtonPanel, SpellCheckerSettingsFrame;

Type
  TSpellCheckerSettingsForm = Class(TForm)
    SpellFrame: TSpellCheckerSettingsFrame;
    ButtonPanel: TButtonPanel;
    Procedure FormCreate(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  End;

Function ShowSpellCheckerSettingsDialog: Boolean;

Implementation

{$R *.lfm}

Function ShowSpellCheckerSettingsDialog: Boolean;
Var
  Form: TSpellCheckerSettingsForm;
Begin
  Result := False;
  Form := TSpellCheckerSettingsForm.Create(Nil);
  Try
    Form.SpellFrame.LoadFromConfig;
    Result := Form.ShowModal = mrOk;
  Finally
    Form.Free;
  End;
End;

Procedure TSpellCheckerSettingsForm.FormCreate(Sender: TObject);
Begin
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
End;

Procedure TSpellCheckerSettingsForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := True;
  If ModalResult = mrOk Then
    SpellFrame.SaveToConfig;
End;

Initialization

RegisterClass(TSpellCheckerSettingsForm);

End.
