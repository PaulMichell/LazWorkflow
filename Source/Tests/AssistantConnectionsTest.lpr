Program AssistantConnectionsTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads, {$ENDIF}Interfaces, Classes, SysUtils, AssistantConnections, AssistantCodexProfile, WorkflowSettings{$IFDEF UNIX}, BaseUnix{$ENDIF};
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
    Check('missing IDE document uses the built-in Grok connection', (Store.Count = 1) And (Store.Active.Backend = 'grok'));
    Check('legacy backend file is not read', (Store.Active.Model <> 'migrated-model-must-not-load') And (Store.Count = 1));
    Check('built-in connection asks with no model effort', (Store.Active.ApprovalMode = 'ask') And (Store.Active.ReasoningEffort = ''));
    Check('load does not write LazWorkflow.json or create a profile',
      Not FileExists(WorkflowSettingsPath) And Not DirectoryExists(Root + '/codex') And Not DirectoryExists(Root + '/assistant-codex-preview'));
    Raised := False;
    Try
      For I := 0 To Store.Count - 1 Do If Store[I].Backend = 'grok' Then Store.ProfileDir(Store[I]);
    Except On E: Exception Do Raised := True; End;
    Check('Grok has no Codex profile', Raised);
    Item := Store.AddChatGPT; Item.Name := 'First account'; Item.Model := 'model-one'; Item.Runtime := '/installed/codex'; Id := Item.Id;
    Profile := Store.ProfileDir(Item);
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
    Check('roundtrip preserves all connections', Store.Count = 3);
    Check('reasoning and permissions belong to each connection', (Store.Active.ReasoningEffort = 'high') And (Store.Active.ApprovalMode = 'auto') And (Store[1].ApprovalMode = 'ask'));
    Check('roundtrip preserves current connection', (Store.Active.Name = 'Second account') And (Store.Active.Model = 'model-two') And (Store.Active.Runtime = '/other/codex'));
    Store.ActiveId := 'grok'; Store.Save; Store.Load;
    Check('switching connection retains ChatGPT connections', (Store.Count = 3) And (Store[2].Model = 'model-two'));
    Store.Remove(0); Check('Grok credential owner retained', Store.Count = 3);
    Store.ActiveId := Store[2].Id; Store.Remove(2); Check('removing active connection selects Grok', Store.Active.Backend = 'grok');
    Store.Load; Check('discarding draft removal restores definitions', Store.Count = 3);
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
    Check('unsaved removal leaves the profile directory', DirectoryExists(Profile) And (Store.Count = 3));
    Check('explicit delete removes only the profile directory', DeleteCodexProfileDirectory(Profile, ErrorText) And Not DirectoryExists(Profile));
    Store.Save;
    Check('save does not recreate a deleted profile', Not DirectoryExists(Profile) And Not FileExists(Profile + PathDelim + 'auth.json'));
    Store.Load; Check('deleted profile is not part of the connection definition', Store.Count = 3);
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
