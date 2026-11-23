Unit AssistantClaudeSettings;

{ Claude connection settings page. Backend = 'claude' stays in this unit.
  The settings form asks the registry and does not name Claude. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, AssistantSettingsPages;

Implementation

Uses
  SysUtils, AssistantConnections, AssistantClaudeClient, AssistantSettingsForm;

Type
  TClaudeSettingsPage = Class(TAssistantSettingsPage)
    Function BackendId: String; Override;
    Function KindCaption: String; Override;
    Function PanelName: String; Override;
    Procedure Load(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure Store(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure ApplyNew(Host: TComponent; Item: TAssistantConnection); Override;
    Function ModelText(Host: TComponent): String; Override;
    Procedure RestoreModelText(Host: TComponent; Const Text: String; Index: Integer); Override;
  End;

Function TClaudeSettingsPage.BackendId: String;
Begin
  Result := 'claude';
End;

Function TClaudeSettingsPage.KindCaption: String;
Begin
  Result := 'Claude account';
End;

Function TClaudeSettingsPage.PanelName: String;
Begin
  Result := 'ClaudePanel';
End;

Procedure TClaudeSettingsPage.Load(Host: TComponent; Item: TAssistantConnection);
Begin
  If Item.Backend = 'claude' Then
    TAssistantSettingsForm(Host).LoadClaudeConnection(Item);
End;

Procedure TClaudeSettingsPage.Store(Host: TComponent; Item: TAssistantConnection);
Begin
  If Item.Backend = 'claude' Then
    TAssistantSettingsForm(Host).StoreClaudeConnection(Item);
End;

Procedure TClaudeSettingsPage.ApplyNew(Host: TComponent; Item: TAssistantConnection);
Begin
  If Assigned(Item) And (Item.Backend = 'claude') Then
    Item.Runtime := DetectClaudeExecutable;
End;

Function TClaudeSettingsPage.ModelText(Host: TComponent): String;
Begin
  Result := TAssistantSettingsForm(Host).ClaudeModelCombo.Text;
End;

Procedure TClaudeSettingsPage.RestoreModelText(Host: TComponent; Const Text: String; Index: Integer);
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm(Host);
  If Form.ClaudeModelCombo.Text <> Text Then
    Form.ClaudeModelCombo.Text := Text;
End;

Initialization

RegisterAssistantSettingsPage(TClaudeSettingsPage.Create);

End.
