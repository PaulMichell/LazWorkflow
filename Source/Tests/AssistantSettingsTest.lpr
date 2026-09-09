Program AssistantSettingsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, StdCtrls, Graphics, ComCtrls,
  LazIDEIntf, ProjectIntf, BaseIDEIntf, LazConfigStorage, SpellCheckerConfig, AssistantTestIDEHost, AssistantSettingsForm, AssistantConnections, AssistantCodexSettings, AssistantConfig;
Var ConfigRoot: String;
Type
  TMemoryConfig = Class(TConfigMemStorage)
    Procedure WriteToDisk; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Function GetActiveProject: TLazProject; Override;
    Class Function GetPrimaryConfigPath: String; Override;
  End;
Procedure TMemoryConfig.WriteToDisk;
Begin End;
Function MemoryConfig(Const Filename: String; LoadFromDisk: Boolean): TConfigStorage;
Begin Result := TMemoryConfig.Create('', False); End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Nil; End;
Class Function TIDE.GetPrimaryConfigPath: String;
Begin Result := ConfigRoot; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Var Frame: TCodexConnectionFrame; IDE: TIDE; Dialog, CancelledDialog: TAssistantSettingsForm; OriginalContext: Boolean; List: TListBox; Names: TEdit;
  Pages: TPageControl; Store: TAssistantConnections; Guid: TGuid; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
Begin
  Application.Initialize;
  CreateGUID(Guid); ConfigRoot := GetTempDir + 'laz-settings-' + GUIDToString(Guid); ForceDirectories(ConfigRoot);
  GetIDEConfigStorage := @MemoryConfig;
  WorkflowSpellConfig.SetStorageFileName(ConfigRoot + '/spell.xml');
  IDE := TIDE.Create(Nil); LazarusIDE := IDE;
  Frame := TCodexConnectionFrame.Create(Nil);
  Try
    Frame.LoadConnection(ConfigRoot, '', 'model-one', 'high', 'auto');
    Frame.LoadModels('{"data":[{"model":"model-one","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"}]},{"model":"model-two","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]}');
    Check('model discovery preserves supported saved reasoning and approval',
      (Frame.ReasoningEffort = 'high') And (Frame.ApprovalMode = 'auto') And (Frame.EffortCombo.Items.Count = 3));
    Frame.ModelCombo.ItemIndex := 1; Frame.ModelCombo.OnChange(Frame.ModelCombo);
    Check('switching model removes unsupported reasoning values',
      (Frame.ReasoningEffort = '') And (Frame.EffortCombo.Items.Count = 2) And (Frame.EffortCombo.Items[1] = 'medium'));
    Frame.LoadConnection(ConfigRoot, '', 'model-one', '', 'invalid');
    Check('unknown approval falls back to Ask', Frame.ApprovalMode = 'ask');
  Finally Frame.Free; End;
  Dialog := TAssistantSettingsForm.Create(Nil);
  Try
    Dialog.LoadFromConfig;
    List := TListBox(Dialog.FindComponent('ConnectionsList'));
    Names := TEdit(Dialog.FindComponent('ConnectionNameEdit'));
    Check('two independent default connections shown', List.Items.Count = 2);
    TButton(Dialog.FindComponent('AddConnectionButton')).Click;
    Check('additional connection can be added', List.Items.Count = 3);
    Names.Text := 'Another ChatGPT account';
    List.ItemIndex := 0; List.OnClick(List);
    TButton(Dialog.FindComponent('UseConnectionButton')).Click;
    Dialog.Show; Application.ProcessMessages;
    If GetEnvironmentVariable('LAZ_SETTINGS_CAPTURE') <> '' Then
      Begin
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-settings.png'); Finally PNG.Free; Bitmap.Free; End;
      End;
    If GetEnvironmentVariable('LAZ_SETTINGS_CAPTURE') <> '' Then
      Begin
        List.ItemIndex := 1; List.OnClick(List); Application.ProcessMessages;
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-connections.png'); Finally PNG.Free; Bitmap.Free; End;
        Pages := TPageControl(Dialog.FindComponent('SettingsPages')); Pages.ActivePageIndex := 1; Application.ProcessMessages;
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-general.png'); Finally PNG.Free; Bitmap.Free; End;
      End;
    Pages := TPageControl(Dialog.FindComponent('SettingsPages')); Pages.ActivePageIndex := 1; Application.ProcessMessages;
    Check('spell settings fit inside the General page',
      TControl(Dialog.FindComponent('GlobalSpellSettings')).Left +
      TControl(Dialog.FindComponent('GlobalSpellSettings')).Width <= Pages.ActivePage.ClientWidth);
    Dialog.SaveToConfig;
    Store := TAssistantConnections.Create(ConfigRoot);
    Try
      Store.Load; Check('settings save preserves multiple connection details', (Store.Count = 3) And (Store[2].Name = 'Another ChatGPT account'));
      OriginalContext := AssistantChatConfig.IncludeIDEContext;
      CancelledDialog := TAssistantSettingsForm.Create(Nil);
      Try
        CancelledDialog.LoadFromConfig;
        TButton(CancelledDialog.FindComponent('AddConnectionButton')).Click;
        CancelledDialog.IncludeContextCheck.Checked := Not OriginalContext;
        CancelledDialog.ModalResult := mrCancel;
      Finally CancelledDialog.Free; End;
      Store.Load;
      Check('Cancel discards connection and general preference edits',
        (Store.Count = 3) And (AssistantChatConfig.IncludeIDEContext = OriginalContext));
    Finally Store.Free; End;
  Finally Dialog.Free; LazarusIDE := Nil; IDE.Free; DeleteFile(ConfigRoot + '/spell.xml'); DeleteFile(ConfigRoot + '/assistant-connections.ini'); RemoveDir(ConfigRoot); End;
End.
