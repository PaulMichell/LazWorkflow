Program AssistantConnectionsTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads, {$ENDIF}Interfaces, Classes, SysUtils, AssistantConnections, AssistantCodexProfile, AssistantConfig, WorkflowSettings{$IFDEF UNIX}, BaseUnix{$ENDIF};
Const ModelList = '{"data":[{"model":"model-one","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"},{"reasoningEffort":"xhigh"}]},{"model":"model-two","supportedReasoningEfforts":[{"reasoningEffort":"medium"}]}]}';
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Function Derived(Const ConfigRoot, ConnectionId: String): String;
Begin Result := IncludeTrailingPathDelimiter(ConfigRoot) + 'codex' + PathDelim + ConnectionId; End;
Var Root, Profile, Id, ErrorText, PolicyText: String; Guid: TGuid;
  Store: TAssistantConnections; Item: TAssistantConnection; Raised: Boolean; I: Integer; Policy: TStringList;
Begin
  CreateGUID(Guid); Root := GetTempDir + 'laz-connections-' + GUIDToString(Guid); ForceDirectories(Root);
  SetWorkflowSettingsDirectory(Root);
  Policy := TStringList.Create;
  Try
    Policy.Text := 'Model=migrated-model-must-not-load';
    Policy.SaveToFile(Root + '/assistant-backend.ini');
    Policy.Text := 'legacy-marker-must-not-load';
    Policy.SaveToFile(Root + '/assistant-connections.ini');
  Finally Policy.Free; End;
  Store := TAssistantConnections.Create(Root);
  Try
    Store.Load;
    Check('missing document has no connections', (Store.Count = 0) And (Store.Active = Nil) And (Store.ActiveId = ''));
    Check('legacy backend file is not read', Store.Count = 0);
    Check('load does not write LazWorkflow.json or create a profile',
      Not FileExists(WorkflowSettingsPath) And Not DirectoryExists(Root + '/codex') And Not DirectoryExists(Root + '/assistant-codex-preview'));
    Policy := TStringList.Create;
    Try
      Policy.Text := '{"assistant":{"active_connection":"desk-grok","connections":[' +
        '{"id":"desk-grok","name":"Desk Grok","backend":"grok","model":"grok-kept","thinking":"low","approval":"ask"}]}}';
      Policy.SaveToFile(WorkflowSettingsPath);
    Finally Policy.Free; End;
    Store.Load;
    Check('a saved Grok row is loaded with its id', Assigned(Store.Active) And (Store.Count = 1) And (Store.Active.Id = 'desk-grok') And
      (Store.Active.Name = 'Desk Grok') And (Store.Active.Backend = 'grok') And (Store.Active.Model = 'grok-kept'));
    Raised := False;
    Try Store.ProfileDir(Store.Active); Except On E: Exception Do Raised := True; End;
    Check('Grok has no Codex profile', Raised);
    Store.Remove(0);
    Check('removing the active row does not recreate Grok', (Store.Count = 0) And (Store.Active = Nil) And (Store.ActiveId = ''));
    Store.Save; Store.Load;
    Check('saving a removed Grok row leaves the list empty', (Store.Count = 0) And (Store.ActiveId = ''));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('empty save does not write a Grok row', Pos('grok', LowerCase(Policy.Text)) = 0);
    Finally Policy.Free; End;
    Item := Store.AddChatGPT; Item.Name := 'Only Codex'; Item.Model := 'codex-only'; Item.Runtime := '/installed/codex'; Id := Item.Id;
    Store.ActiveId := Id; Store.Save; Store.Load;
    Check('codex-only roundtrip keeps one row', (Store.Count = 1) And (Store[0].Id = Id) And (Store[0].Backend = 'codex') And
      (Store[0].Model = 'codex-only'));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('codex-only file has no Grok row', Pos('grok', LowerCase(Policy.Text)) = 0);
    Finally Policy.Free; End;
    Check('loaded Codex row asks with no effort until set', (Store[0].ApprovalMode = 'ask') And (Store[0].ReasoningEffort = ''));
    Store[0].Name := 'First account'; Store[0].Model := 'model-one'; Store[0].CachedModelsJson := ModelList;
    Profile := Store.ProfileDir(Store[0]);
    Check('connection uses a derived Codex profile', Profile = Derived(Root, Id));
    Check('profile is not created until launch', Not DirectoryExists(Profile));
    Item := Store.AddChatGPT; Item.Name := 'Second account'; Item.Model := 'model-two'; Item.Runtime := '/other/codex';
    Item.ReasoningEffort := 'high'; Item.ApprovalMode := 'auto';
    Check('additional account gets a distinct profile', Store.ProfileDir(Item) = Derived(Root, Item.Id));
    Check('additional profile is not created until launch', Not DirectoryExists(Store.ProfileDir(Item)));
    Store.ActiveId := Item.Id; Store.Save; Store.Load;
    Check('save writes the IDE document and leaves legacy files in place',
      FileExists(WorkflowSettingsPath) And FileExists(Root + '/assistant-connections.ini') And FileExists(Root + '/assistant-backend.ini'));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(Root + '/assistant-connections.ini');
      Check('save does not replace the legacy connections file', Pos('legacy-marker-must-not-load', Policy.Text) > 0);
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('IDE document contains the saved connection', Pos('Second account', Policy.Text) > 0);
    Finally Policy.Free; End;
    Check('save does not create Codex profile directories', Not DirectoryExists(IncludeTrailingPathDelimiter(Root) + 'codex'));
    Check('roundtrip preserves all connections', Store.Count = 2);
    Check('model and reasoning cache belongs to its connection',
      (Store[0].CachedModelsJson = ModelList) And (Store[1].CachedModelsJson = ''));
    AssistantChatConfig.Save;
    Store.Load;
    Check('saving general preferences preserves the model cache', Store[0].CachedModelsJson = ModelList);
    Check('reasoning and permissions belong to each connection', (Store.Active.ReasoningEffort = 'high') And (Store.Active.ApprovalMode = 'auto') And (Store[0].ApprovalMode = 'ask'));
    Check('roundtrip preserves current connection', (Store.Active.Name = 'Second account') And (Store.Active.Model = 'model-two') And (Store.Active.Runtime = '/other/codex'));
    Store.ActiveId := 'grok'; Store.Save; Store.Load;
    Check('an unresolved Grok id does not create a row', (Store.Count = 2) And (Store.Active.Backend = 'codex') And (Store[1].Model = 'model-two'));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('save does not write active_connection grok', Pos('grok', LowerCase(Policy.Text)) = 0);
    Finally Policy.Free; End;
    Store.ActiveId := Store[1].Id; Store.Remove(1);
    Check('removing the active row selects another remaining row', (Store.Count = 1) And Assigned(Store.Active) And (Store.Active.Id = Id));
    Store.Load; Check('discarding draft removal restores definitions', Store.Count = 2);
    Check('launch creates the derived profile', PrepareCodexProfile(Profile, ErrorText) And DirectoryExists(Profile) And FileExists(Profile + PathDelim + 'config.toml'));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(Profile + PathDelim + 'config.toml');
      Policy.Add('model = "should-not-persist"');
      Policy.Add('approval = "always"');
      Policy.Add('token = "session-token-must-not-leak"');
      Policy.SaveToFile(Profile + PathDelim + 'config.toml');
      Check('relaunch rewrites the fixed profile policy', PrepareCodexProfile(Profile, ErrorText));
      Policy.LoadFromFile(Profile + PathDelim + 'config.toml');
      PolicyText := Policy.Text;
      Check('profile keeps ChatGPT login', Pos('forced_login_method = "chatgpt"', PolicyText) > 0);
      Check('profile keeps on-request approval', Pos('approval_policy = "on-request"', PolicyText) > 0);
      Check('profile keeps read-only sandbox', Pos('sandbox_mode = "read-only"', PolicyText) > 0);
      Check('profile keeps web search off', Pos('web_search = "disabled"', PolicyText) > 0);
      Check('profile keeps shell tools off', (Pos('shell_tool = false', PolicyText) > 0) And (Pos('unified_exec = false', PolicyText) > 0));
      Check('profile does not keep turn model effort or approval', (Pos('should-not-persist', PolicyText) = 0) And (Pos('always', PolicyText) = 0) And (Pos('token = ', PolicyText) = 0));
      Policy.Clear; Policy.Add('session-token-must-not-leak'); Policy.SaveToFile(Profile + PathDelim + 'auth.json');
    Finally Policy.Free; End;
    Store.Save;
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('IDE document does not copy runtime credentials', Pos('session-token-must-not-leak', Policy.Text) = 0);
    Finally Policy.Free; End;
    Check('save does not delete the profile directory', FileExists(Profile + PathDelim + 'auth.json'));
    For I := Store.Count - 1 DownTo 0 Do If Store[I].Id = Id Then Store.Remove(I);
    Check('removing a definition keeps the profile directory', DirectoryExists(Profile));
    Store.Load;
    Check('unsaved removal leaves the profile directory', DirectoryExists(Profile) And (Store.Count = 2));
    Check('explicit delete removes only the profile directory', DeleteCodexProfileDirectory(Profile, ErrorText) And Not DirectoryExists(Profile));
    Store.Save;
    Check('save does not recreate a deleted profile', Not DirectoryExists(Profile) And Not FileExists(Profile + PathDelim + 'auth.json'));
    Store.Load; Check('deleted profile is not part of the connection definition', Store.Count = 2);
    Check('old preview path is not a derived profile', Not CodexProfilePathIsDerived(Root + '/assistant-codex-preview'));
    Check('refuses to delete a non-derived path', Not DeleteCodexProfileDirectory(Root + '/assistant-codex-preview', ErrorText));
    Check('refusal does not create the old preview path', Not DirectoryExists(Root + '/assistant-codex-preview'));
    {$IFDEF UNIX}
    ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'codex');
    ForceDirectories(Root + '/outside-profile');
    Policy := TStringList.Create;
    Try Policy.Add('keep'); Policy.SaveToFile(Root + '/outside-profile/marker.txt'); Finally Policy.Free; End;
    Check('symlink setup', FpSymlink(PChar(Root + '/outside-profile'), PChar(Profile)) = 0);
    Check('explicit delete refuses a symlink profile', Not DeleteCodexProfileDirectory(Profile, ErrorText));
    Check('symlink target was not deleted', FileExists(Root + '/outside-profile/marker.txt'));
    DeleteFile(Profile);
    {$ENDIF}
    Item := Store.AddStored('desk-grok', 'Desk Grok', 'grok');
    Check('a Grok row can be stored beside Codex rows', Assigned(Item) And (Item.Id = 'desk-grok'));
    Store.ActiveId := Item.Id; Store.Save; Store.Load;
    Check('reloaded Grok row keeps its id beside Codex rows', (Store.Count = 3) And Assigned(Store.Active) And (Store.Active.Id = 'desk-grok'));
    Store.Remove(Store.Count - 1);
    Check('removing the active Grok row selects another row', (Store.Count = 2) And Assigned(Store.Active) And (Store.Active.Backend = 'codex'));
    Store.Save; Store.Load;
    Check('saved removal of Grok does not recreate it', (Store.Count = 2) And Assigned(Store.Active) And (Store.Active.Backend = 'codex'));
    Policy := TStringList.Create;
    Try
      Policy.LoadFromFile(WorkflowSettingsPath);
      Check('saved removal leaves no Grok row', Pos('grok', LowerCase(Policy.Text)) = 0);
    Finally Policy.Free; End;
  Finally
    Store.Free;
    DeleteCodexProfileDirectory(Derived(Root, Id), ErrorText);
    DeleteFile(Derived(Root, Id));
    DeleteFile(Root + '/outside-profile/marker.txt');
    RemoveDir(Root + '/outside-profile');
    RemoveDir(IncludeTrailingPathDelimiter(Root) + 'codex');
    DeleteFile(WorkflowSettingsPath);
    DeleteFile(WorkflowSettingsPath + '.tmp');
    DeleteFile(Root + '/assistant-connections.ini');
    DeleteFile(Root + '/assistant-backend.ini');
    SetWorkflowSettingsDirectory('');
    RemoveDir(Root);
  End;
End.
