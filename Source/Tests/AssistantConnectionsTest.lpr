Program AssistantConnectionsTest;
{$mode objfpc}{$H+}
Uses Classes, SysUtils, IniFiles, AssistantConnections;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Var Root, Profile, Id: String; Guid: TGuid; Config: TIniFile;
  Store: TAssistantConnections; Item: TAssistantConnection;
Begin
  CreateGUID(Guid); Root := GetTempDir + 'laz-connections-' + GUIDToString(Guid); ForceDirectories(Root);
  Config := TIniFile.Create(Root + '/assistant-backend.ini');
  Try Config.WriteString('ChatGPT', 'Runtime', '/installed/codex'); Config.WriteString('ChatGPT', 'Model', 'model-one'); Config.WriteBool('ChatGPT', 'Selected', True); Finally Config.Free; End;
  Store := TAssistantConnections.Create(Root);
  Try
    Store.Load;
    Check('migrates both backend definitions', Store.Count = 2);
    Check('new and migrated connections default to asking with model effort', (Store.Active.ApprovalMode = 'ask') And (Store.Active.ReasoningEffort = ''));
    Check('preserves selected model and runtime', (Store.Active.Model = 'model-one') And (Store.Active.Runtime = '/installed/codex'));
    Check('preserves existing credential profile path', Store.ProfileDir(Store.Active) = Root + '/assistant-codex-preview');
    Check('opening settings does not persist changes', Not FileExists(Root + '/assistant-connections.ini'));
    Item := Store.AddChatGPT; Item.Name := 'Second account'; Item.Model := 'model-two'; Item.Runtime := '/other/codex'; Id := Item.Id;
    Item.ReasoningEffort := 'high'; Item.ApprovalMode := 'auto';
    Profile := Store.ProfileDir(Item);
    Check('additional account gets distinct profile', Profile <> Store.ProfileDir(Store.Active));
    Store.ActiveId := Id; Store.Save; Store.Load;
    Check('roundtrip preserves all connections', Store.Count = 3);
    Check('reasoning and permissions belong to each connection', (Store.Active.ReasoningEffort = 'high') And (Store.Active.ApprovalMode = 'auto') And (Store[1].ApprovalMode = 'ask'));
    Check('roundtrip preserves current connection', (Store.Active.Name = 'Second account') And (Store.Active.Model = 'model-two'));
    Store.ActiveId := 'grok'; Store.Save; Store.Load;
    Check('switching backend retains ChatGPT connections', (Store.Count = 3) And (Store[2].Model = 'model-two'));
    Store.Remove(0); Check('Grok credential owner retained', Store.Count = 3);
    Store.ActiveId := Store[2].Id; Store.Remove(2); Check('removing active connection selects Grok', Store.Active.Backend = 'grok');
    Store.Load; Check('discarding draft removal restores definitions', Store.Count = 3);
  Finally Store.Free; DeleteFile(Root + '/assistant-connections.ini'); DeleteFile(Root + '/assistant-backend.ini'); RemoveDir(Root); End;
End.
