Unit AssistantGrokSettings;

{ Grok connection settings page. The settings form asks the registry for this page.
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
  SysUtils, StdCtrls, Spin, AssistantConnections, AssistantConfig, AssistantSettingsForm;

Type
  TGrokSettingsPage = Class(TAssistantSettingsPage)
    Function BackendId: String; Override;
    Function KindCaption: String; Override;
    Function PanelName: String; Override;
    Procedure Load(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure Store(Host: TComponent; Item: TAssistantConnection); Override;
    Procedure ApplyNew(Host: TComponent; Item: TAssistantConnection); Override;
    Function ModelText(Host: TComponent): String; Override;
    Procedure RestoreModelText(Host: TComponent; Const Text: String; Index: Integer); Override;
  End;

Function TGrokSettingsPage.BackendId: String;
Begin
  Result := 'grok';
End;

Function TGrokSettingsPage.KindCaption: String;
Begin
  Result := 'Grok account';
End;

Function TGrokSettingsPage.PanelName: String;
Begin
  Result := 'GrokPanel';
End;

Procedure TGrokSettingsPage.Load(Host: TComponent; Item: TAssistantConnection);
Begin
  TAssistantSettingsForm(Host).LoadGrokConnection(Item);
End;

Procedure TGrokSettingsPage.Store(Host: TComponent; Item: TAssistantConnection);
Begin
  TAssistantSettingsForm(Host).StoreGrokConnection(Item);
End;

Procedure TGrokSettingsPage.ApplyNew(Host: TComponent; Item: TAssistantConnection);
Begin
  If Not Assigned(Item) Then
    Exit;
  Item.ApiBase := AssistantConfigDefaultApiBase;
  If Assigned(AssistantChatConfig) And (AssistantChatConfig.ApiBase <> '') Then
    Item.ApiBase := AssistantChatConfig.ApiBase;
  Item.Model := AssistantConfigDefaultModel;
  Item.ReasoningEffort := 'high';
  Item.SearchMode := 'off';
  Item.AnswerVerbosity := 'medium';
End;

Function TGrokSettingsPage.ModelText(Host: TComponent): String;
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm(Host);
  If (Form.ModelList.ItemIndex >= 0) And (Form.ModelList.ItemIndex < Form.ModelList.Items.Count) Then
    Result := Form.ModelList.Items[Form.ModelList.ItemIndex]
  Else
    Result := '';
End;

Procedure TGrokSettingsPage.RestoreModelText(Host: TComponent; Const Text: String; Index: Integer);
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm(Host);
  If Form.ModelList.ItemIndex <> Index Then
    Form.ModelList.ItemIndex := Index;
End;

Initialization

RegisterAssistantSettingsPage(TGrokSettingsPage.Create);

End.
