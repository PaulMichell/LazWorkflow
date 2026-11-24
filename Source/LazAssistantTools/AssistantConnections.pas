Unit AssistantConnections;

{ Named connection definitions. Each row is the selected model profile.
  Image output is a stored capability on that profile, not a model id.
  A stored image_delivery value is ignored so an old connection still opens.
  Credentials remain with each backend's account owner; selecting a connection
  never disconnects another account. Codex homes are derived paths only.
  This unit does not create or delete them. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, fpjson, AssistantConversation;

Const
  AssistantOpenRouterApiBase = 'https://openrouter.ai/api/v1';
  AssistantWireChatCompletions = 'chat-completions';
  AssistantOpenRouterKeyEnv = 'OPENROUTER_API_KEY';
  { Kept for the response parser map. The profile no longer stores a delivery mode. }
  AssistantImageDeliveryResponsePart = 'response-part';
  AssistantImageDeliveryToolPrompt = 'tool-prompt';
  { Grok default when image output is turned on and no image model is stored. }
  AssistantGrokImageModel = 'grok-imagine-image-2.0';

Type
  { Common identity plus the fields callers already read. Backend-specific values are owned by
    BackendConfig. Load migrates a flat file into that object. }
  TAssistantConnection = Class
    Id, Name, Backend, Model, ReasoningEffort, ApprovalMode: String;
    Runtime, SearchMode, AnswerVerbosity, Preset, ApiBase: String;
    KeySource, KeyEnv, KeyValue, WireApi: String;
    CachedModelsJson: String;
    SearchCitations: Boolean;
    { False until the user marks this profile. Does not select a different model. }
    ImageOutput: Boolean;
    { Image endpoint id. Not copied from Model, and not limited to the chat picker. }
    ImageModel: String;
    MaxOutputTokens: Integer;
    { Backend-owned object. Not the OAuth token store. }
    BackendConfig: TJSONObject;
    Constructor Create;
    Destructor Destroy; Override;
    /// True when the registry delivers context compaction. OpenAI-compatible is false: it has no history to compact.
    Function CanCompactContext: Boolean;
  End;

  TConnectionConfigProc = Procedure(Item: TAssistantConnection; Config: TJSONObject);

  TAssistantConnections = Class
  Private
    FItems: TObjectList;
    FRoot: String;
    Function GetCount: Integer;
    Function GetItem(Index: Integer): TAssistantConnection;
  Public
    ActiveId: String;
    Constructor Create(Const ConfigRoot: String);
    Destructor Destroy; Override;
    Procedure Load;
    Function Save: Boolean;
    Function AddChatGPT: TAssistantConnection;
    Function Active: TAssistantConnection;
    Function ProfileDir(Connection: TAssistantConnection): String;
    Procedure Remove(Index: Integer);
    Procedure ClearStored;
    Function AddStored(Const Id, Name, Backend: String): TAssistantConnection;
    /// Inserts the historical Grok row when a caller asks for it. Load and save do not call this.
    Procedure EnsureBuiltinGrok;
    Property Count: Integer Read GetCount;
    Property Items[Index: Integer]: TAssistantConnection Read GetItem; Default;
  End;

/// Checks the qualified runtime for subscription profiles.
Function AssistantBackendCanDraw(Const Backend: String; Const Runtime: String = ''): Boolean;
/// Sets the Grok image model when drawing is turned on and none is stored.
/// Does not copy the chat model. Other backends are left unchanged.
Procedure ApplyImageOutputTurnedOn(Item: TAssistantConnection);
/// ImageOutput on the active saved profile, for a backend that can draw. False when no profile is selected.
Function ActiveProfileImageOutput: Boolean;
/// True for a Plan, Document, or Build turn whose active profile can generate images.
/// Inspect and Chat never offer write_image.
Function AssistantTurnOffersImageOutput(Mode: TAssistantMode): Boolean;

Type
  { Fields needed to call this profile's own image endpoint. Do not log KeyValue. }
  TAssistantProfileCall = Record
    Backend, Runtime, Model, ApiBase, Preset, KeySource, KeyEnv, KeyValue: String;
    ImageOutput: Boolean;
    ImageModel: String;
  End;

/// Reads the saved active profile. Does not rewrite the live config.
Function ReadActiveProfileCall(Out Profile: TAssistantProfileCall): Boolean;
Procedure RegisterConnectionConfig(Const BackendId: String; Apply, Collect: TConnectionConfigProc);
Procedure ApplyRegisteredConnectionConfig(Item: TAssistantConnection; Config: TJSONObject);
Procedure CollectRegisteredConnectionConfig(Item: TAssistantConnection; Config: TJSONObject);
/// Copies a flat connection object into BackendConfig when the file has no config object.
Procedure MigrateConnectionConfig(Source: TJSONObject; Item: TAssistantConnection);
/// Applies BackendConfig onto the typed fields. A missing key leaves the field unchanged.
Procedure ApplyConnectionConfig(Item: TAssistantConnection);
/// Writes the typed backend fields into BackendConfig. Common identity stays off this object.
Procedure CollectConnectionConfig(Item: TAssistantConnection);
Function CloneConnectionConfig(Item: TAssistantConnection): TJSONObject;

Implementation

Uses
  AssistantConfig, WorkflowSettings, AssistantCapabilities, AssistantGrokBackend, AssistantChatGPTBackend,
  AssistantClaudeBackend, AssistantCompatibleBackend, AssistantCodexQualification, AssistantCodexProfile;

Type
  TConnectionConfigHook = Record
    BackendId: String;
    Apply, Collect: TConnectionConfigProc;
  End;

Var
  ConfigHooks: Array Of TConnectionConfigHook;

Procedure RegisterConnectionConfig(Const BackendId: String; Apply, Collect: TConnectionConfigProc);
Var
  N: Integer;
Begin
  N := Length(ConfigHooks);
  SetLength(ConfigHooks, N + 1);
  ConfigHooks[N].BackendId := BackendId;
  ConfigHooks[N].Apply := Apply;
  ConfigHooks[N].Collect := Collect;
End;

Function HookFor(Const BackendId: String): Integer;
Var
  I: Integer;
Begin
  Result := -1;
  For I := 0 To High(ConfigHooks) Do
    If ConfigHooks[I].BackendId = BackendId Then
      Exit(I);
End;

Procedure ApplyRegisteredConnectionConfig(Item: TAssistantConnection; Config: TJSONObject);
Var
  Index: Integer;
Begin
  If Not Assigned(Item) Then
    Exit;
  Index := HookFor(Item.Backend);
  If (Index >= 0) And Assigned(ConfigHooks[Index].Apply) Then
    ConfigHooks[Index].Apply(Item, Config);
End;

Procedure CollectRegisteredConnectionConfig(Item: TAssistantConnection; Config: TJSONObject);
Var
  Index: Integer;
Begin
  If Not Assigned(Item) Then
    Exit;
  Index := HookFor(Item.Backend);
  If (Index >= 0) And Assigned(ConfigHooks[Index].Collect) Then
    ConfigHooks[Index].Collect(Item, Config);
End;

Function ConfigText(Config: TJSONObject; Const Name, Fallback: String): String;
Begin
  If Assigned(Config) And Assigned(Config.Find(Name)) Then
    Result := Config.Get(Name, Fallback)
  Else
    Result := Fallback;
End;

Procedure PutValue(Config: TJSONObject; Const Name: String; Value: TJSONData);
Var
  Index: Integer;
Begin
  If Not Assigned(Config) Or Not Assigned(Value) Then
    Exit;
  Index := Config.IndexOfName(Name);
  If Index >= 0 Then
    Config.Delete(Index);
  Config.Add(Name, Value);
End;

Procedure PutText(Config: TJSONObject; Const Name, Value: String);
Begin
  PutValue(Config, Name, TJSONString.Create(Value));
End;

Procedure PutBool(Config: TJSONObject; Const Name: String; Value: Boolean);
Begin
  PutValue(Config, Name, TJSONBoolean.Create(Value));
End;

Procedure PutInt(Config: TJSONObject; Const Name: String; Value: Integer);
Begin
  PutValue(Config, Name, TJSONIntegerNumber.Create(Value));
End;

Procedure MigrateConnectionConfig(Source: TJSONObject; Item: TAssistantConnection);
Var
  Node: TJSONData;
Begin
  If Not Assigned(Item) Then
    Exit;
  If Not Assigned(Item.BackendConfig) Then
    Item.BackendConfig := TJSONObject.Create;
  If Not Assigned(Source) Then
    Exit;
  Node := Source.Find('config');
  If Node Is TJSONObject Then
    Begin
      Item.BackendConfig.Free;
      Item.BackendConfig := TJSONObject(TJSONObject(Node).Clone);
      Exit;
    End;
  { Old file: the flat keys become the backend object. A later config object wins. }
  If Source.Find('runtime') <> Nil Then
    PutText(Item.BackendConfig, 'runtime', Source.Get('runtime', ''));
  If Source.Find('models_json') <> Nil Then
    PutText(Item.BackendConfig, 'models_json', Source.Get('models_json', ''));
  If Source.Find('search_mode') <> Nil Then
    PutText(Item.BackendConfig, 'search_mode', Source.Get('search_mode', ''));
  If Source.Find('search_citations') <> Nil Then
    PutBool(Item.BackendConfig, 'search_citations', Source.Get('search_citations', False));
  If Source.Find('answer_verbosity') <> Nil Then
    PutText(Item.BackendConfig, 'answer_verbosity', Source.Get('answer_verbosity', ''));
  If Source.Find('max_output_tokens') <> Nil Then
    PutInt(Item.BackendConfig, 'max_output_tokens', Source.Get('max_output_tokens', 0));
  If Source.Find('preset') <> Nil Then
    PutText(Item.BackendConfig, 'preset', Source.Get('preset', ''));
  If Source.Find('api_base') <> Nil Then
    PutText(Item.BackendConfig, 'api_base', Source.Get('api_base', ''));
  If Source.Find('key_source') <> Nil Then
    PutText(Item.BackendConfig, 'key_source', Source.Get('key_source', ''));
  If Source.Find('key_env') <> Nil Then
    PutText(Item.BackendConfig, 'key_env', Source.Get('key_env', ''));
  If Source.Find('key_value') <> Nil Then
    PutText(Item.BackendConfig, 'key_value', Source.Get('key_value', ''));
  If Source.Find('wire_api') <> Nil Then
    PutText(Item.BackendConfig, 'wire_api', Source.Get('wire_api', ''));
  If Source.Find('image_output') <> Nil Then
    PutBool(Item.BackendConfig, 'image_output', Source.Get('image_output', False));
  If Source.Find('image_model') <> Nil Then
    PutText(Item.BackendConfig, 'image_model', Source.Get('image_model', ''));
End;

Procedure ApplyConnectionConfig(Item: TAssistantConnection);
Var
  Config: TJSONObject;
Begin
  If Not Assigned(Item) Or Not Assigned(Item.BackendConfig) Then
    Exit;
  Config := Item.BackendConfig;
  If Config.Find('runtime') <> Nil Then
    Item.Runtime := ConfigText(Config, 'runtime', Item.Runtime);
  If Config.Find('models_json') <> Nil Then
    Item.CachedModelsJson := ConfigText(Config, 'models_json', Item.CachedModelsJson);
  If Config.Find('search_mode') <> Nil Then
    Item.SearchMode := ConfigText(Config, 'search_mode', Item.SearchMode);
  If Config.Find('search_citations') <> Nil Then
    Item.SearchCitations := Config.Get('search_citations', Item.SearchCitations);
  If Config.Find('answer_verbosity') <> Nil Then
    Item.AnswerVerbosity := ConfigText(Config, 'answer_verbosity', Item.AnswerVerbosity);
  If Config.Find('max_output_tokens') <> Nil Then
    Item.MaxOutputTokens := Config.Get('max_output_tokens', Item.MaxOutputTokens);
  If Config.Find('preset') <> Nil Then
    Item.Preset := ConfigText(Config, 'preset', Item.Preset);
  If Config.Find('api_base') <> Nil Then
    Item.ApiBase := ConfigText(Config, 'api_base', Item.ApiBase);
  If Config.Find('key_source') <> Nil Then
    Item.KeySource := ConfigText(Config, 'key_source', Item.KeySource);
  If Config.Find('key_env') <> Nil Then
    Item.KeyEnv := ConfigText(Config, 'key_env', Item.KeyEnv);
  If Config.Find('key_value') <> Nil Then
    Item.KeyValue := ConfigText(Config, 'key_value', Item.KeyValue);
  If Config.Find('wire_api') <> Nil Then
    Item.WireApi := ConfigText(Config, 'wire_api', Item.WireApi);
  If Config.Find('image_output') <> Nil Then
    Item.ImageOutput := Config.Get('image_output', Item.ImageOutput);
  If Config.Find('image_model') <> Nil Then
    Item.ImageModel := ConfigText(Config, 'image_model', Item.ImageModel);
  ApplyRegisteredConnectionConfig(Item, Config);
End;

Procedure CollectConnectionConfig(Item: TAssistantConnection);
Begin
  If Not Assigned(Item) Then
    Exit;
  If Not Assigned(Item.BackendConfig) Then
    Item.BackendConfig := TJSONObject.Create;
  PutText(Item.BackendConfig, 'runtime', Item.Runtime);
  PutText(Item.BackendConfig, 'models_json', Item.CachedModelsJson);
  PutText(Item.BackendConfig, 'search_mode', Item.SearchMode);
  PutBool(Item.BackendConfig, 'search_citations', Item.SearchCitations);
  PutText(Item.BackendConfig, 'answer_verbosity', Item.AnswerVerbosity);
  PutInt(Item.BackendConfig, 'max_output_tokens', Item.MaxOutputTokens);
  PutText(Item.BackendConfig, 'preset', Item.Preset);
  PutText(Item.BackendConfig, 'api_base', Item.ApiBase);
  PutText(Item.BackendConfig, 'key_source', Item.KeySource);
  PutText(Item.BackendConfig, 'key_env', Item.KeyEnv);
  PutText(Item.BackendConfig, 'key_value', Item.KeyValue);
  PutText(Item.BackendConfig, 'wire_api', Item.WireApi);
  PutBool(Item.BackendConfig, 'image_output', Item.ImageOutput);
  PutText(Item.BackendConfig, 'image_model', Item.ImageModel);
  CollectRegisteredConnectionConfig(Item, Item.BackendConfig);
End;

Function CloneConnectionConfig(Item: TAssistantConnection): TJSONObject;
Begin
  CollectConnectionConfig(Item);
  If Assigned(Item) And Assigned(Item.BackendConfig) Then
    Result := TJSONObject(Item.BackendConfig.Clone)
  Else
    Result := TJSONObject.Create;
End;

Constructor TAssistantConnection.Create;
Begin
  Inherited Create;
  BackendConfig := TJSONObject.Create;
  ApprovalMode := 'ask';
  SearchMode := 'off';
  SearchCitations := False;
  ImageOutput := False;
  ImageModel := '';
  AnswerVerbosity := 'medium';
  MaxOutputTokens := 0;
  Preset := '';
  ApiBase := '';
  KeySource := 'env';
  KeyEnv := '';
  KeyValue := '';
  WireApi := '';
End;

Destructor TAssistantConnection.Destroy;
Begin
  FreeAndNil(BackendConfig);
  Inherited Destroy;
End;

Function TAssistantConnection.CanCompactContext: Boolean;
Begin
  Result := AssistantCapabilityDelivered(Backend, acContextCompaction);
End;

Function AssistantBackendCanDraw(Const Backend: String; Const Runtime: String): Boolean;
Var
  VersionLine, ErrorText: String;
Begin
  If Backend = 'codex' Then
    Exit((Runtime <> '') And ReadCodexVersion(ResolveCodexExecutable(Runtime), Nil, VersionLine, ErrorText) And
      CodexVersionOffersImageGeneration(VersionLine));
  Result := AssistantCapabilityDelivered(Backend, acImageOutput);
End;

Procedure ApplyImageOutputTurnedOn(Item: TAssistantConnection);
Begin
  If Not Assigned(Item) Then
    Exit;
  { Only a Grok row with no stored image model receives the default.
    OpenAI-compatible keeps an empty id until the user sets one. }
  If (Item.Backend = 'grok') And (Trim(Item.ImageModel) = '') Then
    Item.ImageModel := AssistantGrokImageModel;
End;

Procedure ClearProfileCall(Out Profile: TAssistantProfileCall);
Begin
  Profile.Backend := '';
  Profile.Runtime := '';
  Profile.Model := '';
  Profile.ApiBase := '';
  Profile.Preset := '';
  Profile.KeySource := '';
  Profile.KeyEnv := '';
  Profile.KeyValue := '';
  Profile.ImageOutput := False;
  Profile.ImageModel := '';
End;

Function ReadActiveProfileCall(Out Profile: TAssistantProfileCall): Boolean;
Var
  Section: TJSONObject;
  Node: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  ActiveId: String;
  I: Integer;
Begin
  { Read the saved section only. Do not call Load: that rewrites the live config. }
  ClearProfileCall(Profile);
  Result := False;
  Section := ReadWorkflowSection('assistant');
  If Not Assigned(Section) Then
    Exit;
  Try
    ActiveId := Section.Get('active_connection', '');
    If ActiveId = '' Then
      Exit;
    Node := Section.Find('connections');
    If Not (Node Is TJSONArray) Then
      Exit;
    Arr := TJSONArray(Node);
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Obj := TJSONObject(Arr.Items[I]);
        If Obj.Get('id', '') <> ActiveId Then
          Continue;
        Profile.Backend := Obj.Get('backend', '');
        Profile.Runtime := Obj.Get('runtime', '');
        Profile.Model := Obj.Get('model', '');
        Profile.ApiBase := Obj.Get('api_base', '');
        Profile.Preset := Obj.Get('preset', '');
        Profile.KeySource := Obj.Get('key_source', '');
        Profile.KeyEnv := Obj.Get('key_env', '');
        Profile.KeyValue := Obj.Get('key_value', '');
        If Obj.Find('image_output') <> Nil Then
          Profile.ImageOutput := Obj.Get('image_output', False);
        Profile.ImageModel := Obj.Get('image_model', '');
        { A migrated file keeps those keys on the backend object. Flat keys still win when config is absent. }
        If Obj.Find('config') Is TJSONObject Then
          Begin
            Profile.Runtime := TJSONObject(Obj.Find('config')).Get('runtime', Profile.Runtime);
            If TJSONObject(Obj.Find('config')).Find('api_base') <> Nil Then
              Profile.ApiBase := TJSONObject(Obj.Find('config')).Get('api_base', Profile.ApiBase);
            If TJSONObject(Obj.Find('config')).Find('preset') <> Nil Then
              Profile.Preset := TJSONObject(Obj.Find('config')).Get('preset', Profile.Preset);
            If TJSONObject(Obj.Find('config')).Find('key_source') <> Nil Then
              Profile.KeySource := TJSONObject(Obj.Find('config')).Get('key_source', Profile.KeySource);
            If TJSONObject(Obj.Find('config')).Find('key_env') <> Nil Then
              Profile.KeyEnv := TJSONObject(Obj.Find('config')).Get('key_env', Profile.KeyEnv);
            If TJSONObject(Obj.Find('config')).Find('key_value') <> Nil Then
              Profile.KeyValue := TJSONObject(Obj.Find('config')).Get('key_value', Profile.KeyValue);
            If TJSONObject(Obj.Find('config')).Find('image_output') <> Nil Then
              Profile.ImageOutput := TJSONObject(Obj.Find('config')).Get('image_output', Profile.ImageOutput);
            If TJSONObject(Obj.Find('config')).Find('image_model') <> Nil Then
              Profile.ImageModel := TJSONObject(Obj.Find('config')).Get('image_model', Profile.ImageModel);
          End;
        { image_delivery is not applied. An old file still opens. }
        Exit(True);
      End;
  Finally
    Section.Free;
  End;
End;

Function ActiveProfileImageOutput: Boolean;
Var
  Profile: TAssistantProfileCall;
Begin
  If ReadActiveProfileCall(Profile) Then
    Result := Profile.ImageOutput And AssistantBackendCanDraw(Profile.Backend, Profile.Runtime)
  Else
    Result := False;
End;

Function AssistantTurnOffersImageOutput(Mode: TAssistantMode): Boolean;
Begin
  { Read the saved profile on each call. A model switch applies on the next turn. }
  Result := (Mode In [amPlan, amDocument, amBuild]) And ActiveProfileImageOutput;
End;

Constructor TAssistantConnections.Create(Const ConfigRoot: String);
Begin
  Inherited Create;
  FRoot := IncludeTrailingPathDelimiter(ConfigRoot);
  FItems := TObjectList.Create(True);
End;

Destructor TAssistantConnections.Destroy;
Begin
  FItems.Free;
  Inherited Destroy;
End;

Function TAssistantConnections.GetCount: Integer;
Begin
  Result := FItems.Count;
End;

Function TAssistantConnections.GetItem(Index: Integer): TAssistantConnection;
Begin
  Result := TAssistantConnection(FItems[Index]);
End;

Function SafeId(Const Value: String): Boolean;
Var
  C: Char;
Begin
  Result := (Value <> '') And (Length(Value) <= 80);
  For C In Value Do If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) Then Exit(False);
End;

Procedure TAssistantConnections.ClearStored;
Begin
  FItems.Clear;
  ActiveId := '';
End;

Function TAssistantConnections.AddStored(Const Id, Name, Backend: String): TAssistantConnection;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not SafeId(Id) Then
    Exit;
  For I := 0 To Count - 1 Do
    If Items[I].Id = Id Then
      Exit;
  Result := TAssistantConnection.Create;
  Result.Id := Id;
  Result.Name := Name;
  If Result.Name = '' Then
    Result.Name := Id;
  Result.Backend := Backend;
  FItems.Add(Result);
End;

Procedure TAssistantConnections.EnsureBuiltinGrok;
Begin
  { Explicit opt-in. Load and save keep whatever list was stored, including none. }
  If AddStored('grok', 'Grok', 'grok') = Nil Then
    Exit;
End;

Procedure TAssistantConnections.Load;
Begin
  ClearStored;
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.LoadWithConnections(Self);
  If Active <> Nil Then
    Exit;
  If Count > 0 Then
    ActiveId := Items[0].Id
  Else
    ActiveId := '';
End;

Function TAssistantConnections.Save: Boolean;
Begin
  { Definitions only. Do not create or delete Codex profile directories, and do
    not copy runtime credential files into this store. }
  Result := False;
  If Assigned(AssistantChatConfig) Then
    Result := AssistantChatConfig.SaveWithConnections(Self);
End;

Function TAssistantConnections.AddChatGPT: TAssistantConnection;
Var
  Id: TGuid;
Begin
  If CreateGUID(Id) <> 0 Then Raise Exception.Create('Cannot create connection identifier');
  Result := TAssistantConnection.Create;
  Result.Id := Copy(GUIDToString(Id), 2, 36);
  Result.Name := 'ChatGPT ' + IntToStr(Count);
  Result.Backend := 'codex';
  FItems.Add(Result);
End;

Function TAssistantConnections.Active: TAssistantConnection;
Var
  I: Integer;
Begin
  Result := Nil;
  For I := 0 To Count - 1 Do If Items[I].Id = ActiveId Then Exit(Items[I]);
End;

Function TAssistantConnections.ProfileDir(Connection: TAssistantConnection): String;
Begin
  If Not Assigned(Connection) Or Not SafeId(Connection.Id) Then Raise Exception.Create('Invalid connection identifier');
  If Connection.Backend <> 'codex' Then Raise Exception.Create('A Codex profile exists only for a Codex connection');
  { Path only. PrepareCodexProfile is the only creator. assistant-codex-preview is not used. }
  Result := FRoot + 'codex' + PathDelim + Connection.Id;
End;

Procedure TAssistantConnections.Remove(Index: Integer);
Var
  RemovedId: String;
Begin
  { Definition only. Deleting the profile directory is a separate explicit action.
    Any row can be removed, including a saved Grok row. }
  If (Index < 0) Or (Index >= Count) Then
    Exit;
  RemovedId := Items[Index].Id;
  If ActiveId = RemovedId Then
    Begin
      If Count = 1 Then
        ActiveId := ''
      Else If Index < Count - 1 Then
        ActiveId := Items[Index + 1].Id
      Else
        ActiveId := Items[Index - 1].Id;
    End;
  FItems.Delete(Index);
End;
End.
