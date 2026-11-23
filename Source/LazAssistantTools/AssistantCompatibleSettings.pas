Unit AssistantCompatibleSettings;

{ OpenAI-compatible connection settings page. The settings form asks the registry.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, AssistantSettingsPages;

Implementation

Uses
  SysUtils, AssistantConnections, AssistantSettingsForm;

Type
  TCompatibleSettingsPage = Class(TAssistantSettingsPage)
    Function BackendId: String; Override;
    Function KindCaption: String; Override;
    Function PanelName: String; Override;
    Procedure Load(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure Store(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure ApplyNew(Host: TComponent; Item: TAssistantConnection); Override;
    Function ModelText(Host: TComponent): String; Override;
    Procedure RestoreModelText(Host: TComponent; Const Text: String; Index: Integer); Override;
  End;

Function TCompatibleSettingsPage.BackendId: String;
Begin
  Result := 'openai-compatible';
End;

Function TCompatibleSettingsPage.KindCaption: String;
Begin
  Result := 'OpenAI-compatible endpoint';
End;

Function TCompatibleSettingsPage.PanelName: String;
Begin
  Result := 'CompatiblePanel';
End;

Procedure TCompatibleSettingsPage.Load(Host: TComponent; Item: TAssistantConnection);
Begin
  TAssistantSettingsForm(Host).LoadCompatibleConnection(Item);
End;

Procedure TCompatibleSettingsPage.Store(Host: TComponent; Item: TAssistantConnection);
Begin
  TAssistantSettingsForm(Host).StoreCompatibleConnection(Item);
End;

Procedure TCompatibleSettingsPage.ApplyNew(Host: TComponent; Item: TAssistantConnection);
Begin
  If Not Assigned(Item) Then
    Exit;
  Item.Preset := 'custom';
  Item.KeySource := 'env';
  Item.WireApi := AssistantWireChatCompletions;
End;

Function TCompatibleSettingsPage.ModelText(Host: TComponent): String;
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm(Host);
  Result := Form.CompatibleModelCombo.Text;
End;

Procedure TCompatibleSettingsPage.RestoreModelText(Host: TComponent; Const Text: String; Index: Integer);
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm(Host);
  If Form.CompatibleModelCombo.Text <> Text Then
    Begin
      Form.CompatibleModelCombo.ItemIndex := Index;
      If Form.CompatibleModelCombo.Text <> Text Then
        Form.CompatibleModelCombo.Text := Text;
    End;
End;

Initialization

RegisterAssistantSettingsPage(TCompatibleSettingsPage.Create);

End.
