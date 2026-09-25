Program AssistantSettingsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, StdCtrls, Graphics, ComCtrls,
  LazIDEIntf, ProjectIntf, BaseIDEIntf, LazConfigStorage, SpellCheckerConfig, WorkflowSettings, AssistantTestIDEHost, AssistantSettingsForm, AssistantConnections, AssistantCodexSettings, AssistantCodexProfile, AssistantConfig, AssistantTestSettings, AssistantTestSettingsFrame;
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
  TestFrame: TAssistantTestSettingsFrame; TestSettings: TAssistantTestSettings; Note, StoreDir: String;
  Pages: TPageControl; Store: TAssistantConnections; Guid: TGuid; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
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
    Check('built-in Grok connection shown without a migrated account', List.Items.Count = 1);
    TButton(Dialog.FindComponent('AddConnectionButton')).Click;
    Check('additional connection can be added', List.Items.Count = 2);
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
    TestFrame := TAssistantTestSettingsFrame(Dialog.FindComponent('ProjectTestSettings'));
    Check('project test controls disabled without a saved project', Not TestFrame.Enabled);
    TestFrame.Load(StoreDir, ConfigRoot + '/fixture.lpi'); TestFrame.EnabledCheck.Checked := True;
    TestFrame.ExecutableEdit.Text := ParamStr(0); TestFrame.ArgumentMemo.Lines.Add('--all');
    TestFrame.ArgumentMemo.Lines.Add('two words'); TestFrame.TimeoutEdit.Value := 15;
    TestFrame.ReportCombo.ItemIndex := 1; TestFrame.MinimumEdit.Value := 3;
    Check('test settings validate without launching a process', TestFrame.Validate(Note));
    If GetEnvironmentVariable('LAZ_SETTINGS_CAPTURE') <> '' Then
      Begin
        Pages.ActivePageIndex := 2; Application.ProcessMessages;
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
      Store.Load; Check('settings save preserves the added connection', (Store.Count = 2) And (Store[1].Name = 'Another ChatGPT account'));
      Check('settings save wrote the IDE document and the target document',
        FileExists(WorkflowSettingsPath) And FileExists(StoreDir + 'config.json') And
        Not FileExists(ConfigRoot + '/assistant-connections.ini') And Not FileExists(ConfigRoot + '/spell.xml'));
      OriginalContext := AssistantChatConfig.IncludeIDEContext;
      CancelledDialog := TAssistantSettingsForm.Create(Nil);
      Try
        CancelledDialog.LoadFromConfig;
        TButton(CancelledDialog.FindComponent('AddConnectionButton')).Click;
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
        (Store.Count = 2) And (AssistantChatConfig.IncludeIDEContext = OriginalContext));
    Finally Store.Free; End;
  Finally Dialog.Free; LazarusIDE := Nil; IDE.Free; DeleteFile(WorkflowSettingsPath); DeleteFile(StoreDir + 'config.json');
    RemoveDir(ExcludeTrailingPathDelimiter(StoreDir)); SetWorkflowSettingsDirectory(''); RemoveDir(ConfigRoot); End;
End.
