Program AssistantSettingsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, StdCtrls, Graphics, ComCtrls, Menus,
  LazIDEIntf, ProjectIntf, BaseIDEIntf, LazConfigStorage, SpellCheckerConfig, WorkflowSettings, AssistantTestIDEHost, AssistantSettingsForm, AssistantConnections, AssistantCodexSettings, AssistantCodexProfile, AssistantConfig, AssistantTestSettings, AssistantTestSettingsFrame;
Const ModelList = '{"data":[{"model":"model-one","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"},{"reasoningEffort":"xhigh"}]},{"model":"model-two","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]}';
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
Procedure RejectModels(Frame: TCodexConnectionFrame; Const Value: String);
Var
  Cached, Models, Efforts, Model, Effort: String;
  Raised: Boolean;
Begin
  Cached := Frame.CachedModelsJson;
  Models := Frame.ModelCombo.Items.Text;
  Efforts := Frame.EffortCombo.Items.Text;
  Model := Frame.ModelCombo.Text;
  Effort := Frame.ReasoningEffort;
  Raised := False;
  Try Frame.LoadModels(Value); Except On E: Exception Do Raised := True; End;
  Check('invalid discovery keeps the last valid lists and selections',
    Raised And (Frame.CachedModelsJson = Cached) And (Frame.ModelCombo.Items.Text = Models)
    And (Frame.EffortCombo.Items.Text = Efforts) And (Frame.ModelCombo.Text = Model)
    And (Frame.ReasoningEffort = Effort));
End;
Function CodexSettings(Dialog: TAssistantSettingsForm): TCodexConnectionFrame;
Var I: Integer;
Begin
  For I := 0 To Dialog.ComponentCount - 1 Do
    If Dialog.Components[I] Is TCodexConnectionFrame Then
      Exit(TCodexConnectionFrame(Dialog.Components[I]));
  Raise Exception.Create('Missing Codex settings frame');
End;
Var Frame: TCodexConnectionFrame; IDE: TIDE; Dialog, CancelledDialog: TAssistantSettingsForm; OriginalContext: Boolean; List: TListBox; Names: TEdit;
  TestFrame: TAssistantTestSettingsFrame; TestSettings: TAssistantTestSettings; Note, StoreDir, KeptModel: String;
  Pages: TPageControl; Store: TAssistantConnections; Guid: TGuid; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
  ImageCheck: TCheckBox; DeliveryCombo: TComboBox; KeptIndex: Integer;
Begin
  Application.Initialize;
  CreateGUID(Guid); ConfigRoot := GetTempDir + 'laz-settings-' + GUIDToString(Guid); ForceDirectories(ConfigRoot);
  GetIDEConfigStorage := @MemoryConfig;
  SetWorkflowSettingsDirectory(ConfigRoot);
  WorkflowSpellConfig.SetStorageFileName(WorkflowSettingsPath);
  StoreDir := IncludeTrailingPathDelimiter(ConfigRoot) + '.assistant' + PathDelim;
  IDE := TIDE.Create(Nil); LazarusIDE := IDE;
  Frame := TCodexConnectionFrame.Create(Nil);
  Try
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-one', 'high', 'auto');
    Check('existing custom executable remains selected', Frame.RuntimeEdit.Text = ParamStr(0));
    Check('runtime Browse and Auto-detect controls available',
      Assigned(Frame.FindComponent('BrowseRuntimeButton')) And Assigned(Frame.FindComponent('DetectRuntimeButton')));
    If FindCodexExecutable <> '' Then
      Begin
        Frame.LoadConnection(ConfigRoot, ConfigRoot + '/removed-extension/codex', 'model-one', 'high', 'auto');
        Check('missing saved executable recovered without changing connection identity',
          (Frame.RuntimeEdit.Text = FindCodexExecutable) And (Frame.Profile = ConfigRoot)
          And (Frame.ModelCombo.Text = 'model-one') And (Frame.ReasoningEffort = 'high')
          And (Pos('no longer available', TLabel(Frame.FindComponent('ConnectionStatus')).Caption) > 0));
      End;
    Frame.LoadModels(ModelList);
    Check('model discovery preserves supported saved reasoning and approval',
      (Frame.ReasoningEffort = 'high') And (Frame.ApprovalMode = 'auto') And (Frame.EffortCombo.Items.Count = 4));
    RejectModels(Frame, '{');
    RejectModels(Frame, '[]');
    RejectModels(Frame, '{"data":[]}');
    RejectModels(Frame, '{"data":{}}');
    RejectModels(Frame, '{"data":[null]}');
    RejectModels(Frame, '{"data":[{"model":42,"supportedReasoningEfforts":[]}]}');
    RejectModels(Frame, '{"data":[{"model":"model-one","supportedReasoningEfforts":"high"}]}');
    RejectModels(Frame, '{"data":[{"model":"model-one","supportedReasoningEfforts":[{"reasoningEffort":false}]}]}');
    RejectModels(Frame, '{"data":[{"model":"valid","supportedReasoningEfforts":[]},{"model":"broken"}]}');
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-one', 'xhigh', 'auto', Frame.CachedModelsJson);
    Check('cached discovery restores model and reasoning choices without a query',
      (Frame.ModelCombo.Items.Count = 2) And (Frame.ModelCombo.Text = 'model-one')
      And (Frame.EffortCombo.Items.Count = 4) And (Frame.ReasoningEffort = 'xhigh')
      And (Frame.CachedModelsJson = ModelList) And Not Frame.Busy);
    Frame.ModelCombo.ItemIndex := 1; Frame.ModelCombo.OnChange(Frame.ModelCombo);
    Check('switching model removes unsupported reasoning values',
      (Frame.ReasoningEffort = '') And (Frame.EffortCombo.Items.Count = 2) And (Frame.EffortCombo.Items[1] = 'medium'));
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'new-model', 'future-effort', 'auto', ModelList);
    Check('older cached models retain the saved model and effort',
      (Frame.ModelCombo.Text = 'new-model') And (Frame.ReasoningEffort = 'future-effort')
      And (Frame.ModelCombo.Items.Count = 3) And (Frame.CachedModelsJson = ModelList));
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-one', 'future-effort', 'auto', ModelList);
    Check('older cached reasoning levels retain a newer saved effort',
      (Frame.ReasoningEffort = 'future-effort') And (Frame.EffortCombo.Items.Count = 5));
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-one', '', 'ask', ModelList);
    Check('cached discovery retains Model default', Frame.ReasoningEffort = '');
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-one', 'high', 'auto', '{"data":[]}');
    Check('invalid stored cache falls back to saved choices',
      (Frame.ModelCombo.Text = 'model-one') And (Frame.ReasoningEffort = 'high')
      And (Frame.CachedModelsJson = ''));
    Frame.LoadConnection(ConfigRoot, ParamStr(0), 'model-two', '', 'ask',
      '{"data":[{"id":"model-two","supportedReasoningEfforts":[]}]}');
    Check('id-only models and default-only reasoning are supported',
      (Frame.ModelCombo.Items.Count = 1) And (Frame.EffortCombo.Items.Count = 1));
    Frame.LoadConnection(ConfigRoot, '', 'model-one', '', 'invalid');
    Check('loading an uncached connection clears the previous lists',
      (Frame.CachedModelsJson = '') And (Frame.ModelCombo.Items.Count = 1)
      And (Frame.EffortCombo.Items.Count = 1));
    Check('unknown approval falls back to Ask', Frame.ApprovalMode = 'ask');
  Finally Frame.Free; End;
  Dialog := TAssistantSettingsForm.Create(Nil);
  Try
    Dialog.LoadFromConfig;
    Pages := TPageControl(Dialog.FindComponent('SettingsPages'));
    Check('settings pages are streamed', Assigned(Pages) And (Pages.PageCount = 4));
    Check('General page', Pages.Pages[0].Caption = 'General');
    Check('Connections page', Pages.Pages[1].Caption = 'Connections');
    Check('Spelling page', Pages.Pages[2].Caption = 'Spelling');
    Check('Tests page', Pages.Pages[3].Caption = 'Tests');
    Pages.ActivePageIndex := 0; Application.ProcessMessages;
    Pages.ActivePageIndex := 1; Application.ProcessMessages;
    Pages.ActivePageIndex := 2; Application.ProcessMessages;
    Pages.ActivePageIndex := 3; Application.ProcessMessages;
    List := TListBox(Dialog.FindComponent('ConnectionsList'));
    Names := TEdit(Dialog.FindComponent('ConnectionNameEdit'));
    Check('connection list is present without requiring a Grok row', Assigned(List) And (List.Items.Count = 0));
    Check('add menu items stay enabled when no row of that kind exists',
      TMenuItem(Dialog.FindComponent('GrokAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('ChatGptAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('CompatibleAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('ClaudeAccountItem')).Enabled);
    TMenuItem(Dialog.FindComponent('ChatGptAccountItem')).Click;
    Check('ChatGPT connection can be added', List.Items.Count = 1);
    Check('add menu items stay enabled after a row of that kind exists',
      TMenuItem(Dialog.FindComponent('GrokAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('ChatGptAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('CompatibleAccountItem')).Enabled And
      TMenuItem(Dialog.FindComponent('ClaudeAccountItem')).Enabled);
    Names.Text := 'Another ChatGPT account';
    Frame := CodexSettings(Dialog);
    Frame.RuntimeEdit.Text := ParamStr(0);
    Frame.LoadModels(ModelList);
    Frame.EffortCombo.ItemIndex := Frame.EffortCombo.Items.IndexOf('xhigh');
    ImageCheck := TCheckBox(Dialog.FindComponent('ImageOutputCheck'));
    DeliveryCombo := TComboBox(Dialog.FindComponent('ImageDeliveryCombo'));
    KeptModel := Frame.ModelCombo.Text;
    Check('selected profile shows Can generate images',
      Assigned(ImageCheck) And ImageCheck.Visible And (ImageCheck.Caption = 'Can generate images') And
      ImageCheck.Enabled And (Not ImageCheck.Checked) And Assigned(DeliveryCombo) And (DeliveryCombo.Items.Count = 2) And
      (DeliveryCombo.ItemIndex = 0) And (KeptModel = 'model-one'));
    ImageCheck.Checked := True;
    ImageCheck.OnClick(ImageCheck);
    DeliveryCombo.ItemIndex := 1;
    Check('turning on image output keeps the current model',
      (Frame.ModelCombo.Text = KeptModel) And (Frame.ModelCombo.Text = 'model-one') And ImageCheck.Checked And
      DeliveryCombo.Enabled And (DeliveryCombo.ItemIndex = 1));
    List.ItemIndex := 0; List.OnClick(List);
    TButton(Dialog.FindComponent('UseConnectionButton')).Click;
    Dialog.Show; Application.ProcessMessages;
    If GetEnvironmentVariable('LAZ_SETTINGS_CAPTURE') <> '' Then
      Begin
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-settings.png'); Finally PNG.Free; Bitmap.Free; End;
        Pages.ActivePageIndex := 0; Application.ProcessMessages;
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-general.png'); Finally PNG.Free; Bitmap.Free; End;
        Pages.ActivePageIndex := 2; Application.ProcessMessages;
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-spelling.png'); Finally PNG.Free; Bitmap.Free; End;
      End;
    Pages.ActivePageIndex := 2; Application.ProcessMessages;
    Check('spell settings fit inside the Spelling page',
      TControl(Dialog.FindComponent('GlobalSpellSettings')).Left +
      TControl(Dialog.FindComponent('GlobalSpellSettings')).Width <= Pages.ActivePage.ClientWidth);
    Pages.ActivePageIndex := 3; Application.ProcessMessages;
    TestFrame := TAssistantTestSettingsFrame(Dialog.FindComponent('ProjectTestSettings'));
    Check('project test controls disabled without a saved project', Not TestFrame.Enabled);
    TestFrame.Load(StoreDir, ConfigRoot + '/fixture.lpi'); TestFrame.EnabledCheck.Checked := True;
    TestFrame.ExecutableEdit.Text := ParamStr(0); TestFrame.ArgumentMemo.Lines.Add('--all');
    TestFrame.ArgumentMemo.Lines.Add('two words'); TestFrame.TimeoutEdit.Value := 15;
    TestFrame.ReportCombo.ItemIndex := 1; TestFrame.MinimumEdit.Value := 3;
    Check('test settings validate without launching a process', TestFrame.Validate(Note));
    If GetEnvironmentVariable('LAZ_SETTINGS_CAPTURE') <> '' Then
      Begin
        Pages.ActivePageIndex := 3; Application.ProcessMessages;
        Bitmap := Dialog.GetFormImage; PNG := TPortableNetworkGraphic.Create;
        Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-assistant-project-tests.png'); Finally PNG.Free; Bitmap.Free; End;
      End;
    Dialog.SaveToConfig;
    TestSettings := TAssistantTestSettings.Create(StoreDir, ConfigRoot + '/fixture.lpi');
    Try TestSettings.Load; Check('test settings UI saves exact project command', TestSettings.Enabled And
      (TestSettings.Arguments.Count = 2) And (TestSettings.Arguments[1] = 'two words') And (TestSettings.TimeoutSeconds = 15) And (TestSettings.ReportFormat = 'fpcunit-xml') And (TestSettings.MinimumTests = 3));
    Finally TestSettings.Free; End;
    Store := TAssistantConnections.Create(ConfigRoot);
    Try
      Store.Load; Check('settings save preserves the added connection', (Store.Count = 1) And (Store[0].Name = 'Another ChatGPT account'));
      Check('settings save wrote the IDE document and the target document',
        FileExists(WorkflowSettingsPath) And FileExists(StoreDir + 'config.json') And
        Not FileExists(ConfigRoot + '/assistant-connections.ini') And Not FileExists(ConfigRoot + '/spell.xml'));
      Check('saving settings persists the discovered lists', Store[0].CachedModelsJson = ModelList);
      Check('saving settings does not invent a Grok row', Store[0].Backend = 'codex');
      Check('settings save stores image output on that profile',
        Store[0].ImageOutput And (Store[0].ImageDelivery = aidToolPrompt) And (Store[0].Model = 'model-one'));
      OriginalContext := AssistantChatConfig.IncludeIDEContext;
      CancelledDialog := TAssistantSettingsForm.Create(Nil);
      Try
        CancelledDialog.LoadFromConfig;
        List := TListBox(CancelledDialog.FindComponent('ConnectionsList'));
        List.ItemIndex := 0; List.OnClick(List);
        Frame := CodexSettings(CancelledDialog);
        Check('reopening settings restores saved model and reasoning lists',
          (Frame.ModelCombo.Items.Count = 2) And (Frame.ModelCombo.Text = 'model-one')
          And (Frame.EffortCombo.Items.Count = 4) And (Frame.ReasoningEffort = 'xhigh')
          And Not Frame.Busy);
        ImageCheck := TCheckBox(CancelledDialog.FindComponent('ImageOutputCheck'));
        DeliveryCombo := TComboBox(CancelledDialog.FindComponent('ImageDeliveryCombo'));
        Check('reopened profile keeps image output and the same model',
          ImageCheck.Checked And ImageCheck.Enabled And (DeliveryCombo.ItemIndex = 1) And DeliveryCombo.Enabled And
          (Frame.ModelCombo.Text = 'model-one'));
        TMenuItem(CancelledDialog.FindComponent('ChatGptAccountItem')).Click;
        Check('new connections do not inherit discovered lists',
          (Frame.CachedModelsJson = '') And (Frame.ModelCombo.Items.Count = 0));
        Check('a new profile does not inherit image output',
          (Not TCheckBox(CancelledDialog.FindComponent('ImageOutputCheck')).Checked) And
          (TComboBox(CancelledDialog.FindComponent('ImageDeliveryCombo')).ItemIndex = 0) And
          (Frame.ModelCombo.Text = ''));
        Frame.LoadModels('{"data":[{"model":"other-account-model","supportedReasoningEfforts":[]}]}');
        List.ItemIndex := 0; List.OnClick(List);
        Check('switching connections restores their own discovery cache',
          (Frame.CachedModelsJson = ModelList) And (Frame.ModelCombo.Items.Count = 2)
          And (Frame.ReasoningEffort = 'xhigh'));
        Check('switching profiles restores image output without changing that model',
          TCheckBox(CancelledDialog.FindComponent('ImageOutputCheck')).Checked And
          (TComboBox(CancelledDialog.FindComponent('ImageDeliveryCombo')).ItemIndex = 1) And
          (Frame.ModelCombo.Text = 'model-one'));
        Frame.LoadModels('{"data":[{"model":"unsaved-model","supportedReasoningEfforts":[]}]}');
        TMenuItem(CancelledDialog.FindComponent('GrokAccountItem')).Click;
        Check('Grok detail does not show ChatGPT account fields',
          TControl(CancelledDialog.FindComponent('GrokPanel')).Visible And
          Not TControl(CancelledDialog.FindComponent('CodexPanel')).Visible);
        KeptIndex := TListBox(CancelledDialog.FindComponent('ModelList')).ItemIndex;
        KeptModel := '';
        If KeptIndex >= 0 Then
          KeptModel := TListBox(CancelledDialog.FindComponent('ModelList')).Items[KeptIndex];
        ImageCheck := TCheckBox(CancelledDialog.FindComponent('ImageOutputCheck'));
        ImageCheck.Checked := True;
        ImageCheck.OnClick(ImageCheck);
        Check('Grok image output does not select another model',
          (TListBox(CancelledDialog.FindComponent('ModelList')).ItemIndex = KeptIndex) And
          ((KeptIndex < 0) Or (TListBox(CancelledDialog.FindComponent('ModelList')).Items[KeptIndex] = KeptModel)));
        TButton(CancelledDialog.FindComponent('RemoveConnectionButton')).Click;
        Check('Remove deletes a Grok row', List.Items.Count = 2);
        TMenuItem(CancelledDialog.FindComponent('CompatibleAccountItem')).Click;
        TComboBox(CancelledDialog.FindComponent('PresetCombo')).ItemIndex := 0;
        TComboBox(CancelledDialog.FindComponent('PresetCombo')).OnChange(TComboBox(CancelledDialog.FindComponent('PresetCombo')));
        Check('OpenRouter fills the base URL and default env name',
          (TEdit(CancelledDialog.FindComponent('CompatibleBaseEdit')).Text = 'https://openrouter.ai/api/v1') And
          (TEdit(CancelledDialog.FindComponent('KeyEnvEdit')).Text = 'OPENROUTER_API_KEY') And
          TEdit(CancelledDialog.FindComponent('CompatibleBaseEdit')).ReadOnly);
        Check('OpenRouter preset does not select an image product',
          (TComboBox(CancelledDialog.FindComponent('CompatibleModelCombo')).Text = '') And
          (Not TCheckBox(CancelledDialog.FindComponent('ImageOutputCheck')).Checked));
        TComboBox(CancelledDialog.FindComponent('PresetCombo')).ItemIndex := 1;
        TComboBox(CancelledDialog.FindComponent('PresetCombo')).OnChange(TComboBox(CancelledDialog.FindComponent('PresetCombo')));
        Check('Custom leaves the base URL editable', Not TEdit(CancelledDialog.FindComponent('CompatibleBaseEdit')).ReadOnly);
        Check('stored key edit is a password edit', TEdit(CancelledDialog.FindComponent('KeyValueEdit')).PasswordChar = '*');
        Check('switching kind hides the other account fields',
          TControl(CancelledDialog.FindComponent('CompatiblePanel')).Visible And
          Not TControl(CancelledDialog.FindComponent('GrokPanel')).Visible And
          Not TControl(CancelledDialog.FindComponent('CodexPanel')).Visible And
          Not TControl(CancelledDialog.FindComponent('ClaudePanel')).Visible);
        CancelledDialog.IncludeContextCheck.Checked := Not OriginalContext;
        TestFrame := TAssistantTestSettingsFrame(CancelledDialog.FindComponent('ProjectTestSettings'));
        TestFrame.Load(StoreDir, ConfigRoot + '/fixture.lpi'); TestFrame.EnabledCheck.Checked := False;
        CancelledDialog.ModalResult := mrCancel;
      Finally CancelledDialog.Free; End;
      TestSettings := TAssistantTestSettings.Create(StoreDir, ConfigRoot + '/fixture.lpi');
      Try TestSettings.Load; Check('Cancel retains saved project test command', TestSettings.Enabled);
        DeleteFile(TestSettings.StorageFilename);
      Finally TestSettings.Free; End;
      Store.Load;
      Check('Cancel discards connection and general preference edits',
        (Store.Count = 1) And (AssistantChatConfig.IncludeIDEContext = OriginalContext));
      Check('Cancel retains the saved discovery cache', Store[0].CachedModelsJson = ModelList);
    Finally Store.Free; End;
  Finally Dialog.Free; LazarusIDE := Nil; IDE.Free; DeleteFile(WorkflowSettingsPath); DeleteFile(StoreDir + 'config.json');
    RemoveDir(ExcludeTrailingPathDelimiter(StoreDir)); SetWorkflowSettingsDirectory(''); RemoveDir(ConfigRoot); End;
End.
