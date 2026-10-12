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
  Classes, SysUtils, Contnrs, AssistantConversation;

Const
  AssistantOpenRouterApiBase = 'https://openrouter.ai/api/v1';
  AssistantWireChatCompletions = 'chat-completions';
  AssistantOpenRouterKeyEnv = 'OPENROUTER_API_KEY';
  { Kept for the response parser map. The profile no longer stores a delivery mode. }
  AssistantImageDeliveryResponsePart = 'response-part';
  AssistantImageDeliveryToolPrompt = 'tool-prompt';

Type
  TAssistantConnection = Class
    Id, Name, Backend, Runtime, Model, ReasoningEffort, ApprovalMode: String;
    SearchMode, AnswerVerbosity, Preset, ApiBase: String;
    KeySource, KeyEnv, KeyValue, WireApi: String;
    CachedModelsJson: String;
    SearchCitations: Boolean;
    { False until the user marks this profile. Does not select a different model. }
    ImageOutput: Boolean;
    MaxOutputTokens: Integer;
    Constructor Create;
    /// True for grok and openai-compatible. Derived from Backend, not a stored flag.
    Function CanCompactContext: Boolean;
  End;
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

/// ImageOutput on the active saved profile. False when no profile is selected.
Function ActiveProfileImageOutput: Boolean;
/// True only for a Build turn whose active profile can generate images.
/// Plan and Document never offer write_image; they do not write project files.
Function AssistantTurnOffersImageOutput(Mode: TAssistantMode): Boolean;

Type
  { Fields needed to call this profile's own image endpoint. Do not log KeyValue. }
  TAssistantProfileCall = Record
    Backend, Model, ApiBase, Preset, KeySource, KeyEnv, KeyValue: String;
    ImageOutput: Boolean;
  End;

/// Reads the saved active profile. Does not rewrite the live config.
Function ReadActiveProfileCall(Out Profile: TAssistantProfileCall): Boolean;

Implementation

Uses
  AssistantConfig, WorkflowSettings, fpjson;

Constructor TAssistantConnection.Create;
Begin
  Inherited Create;
  ApprovalMode := 'ask';
  SearchMode := 'off';
  SearchCitations := False;
  ImageOutput := False;
  AnswerVerbosity := 'medium';
  MaxOutputTokens := 0;
  Preset := '';
  ApiBase := '';
  KeySource := 'env';
  KeyEnv := '';
  KeyValue := '';
  WireApi := '';
End;

Function TAssistantConnection.CanCompactContext: Boolean;
Begin
  Result := (Backend = 'grok') Or (Backend = 'openai-compatible');
End;

Procedure ClearProfileCall(Out Profile: TAssistantProfileCall);
Begin
  Profile.Backend := '';
  Profile.Model := '';
  Profile.ApiBase := '';
  Profile.Preset := '';
  Profile.KeySource := '';
  Profile.KeyEnv := '';
  Profile.KeyValue := '';
  Profile.ImageOutput := False;
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
        Profile.Model := Obj.Get('model', '');
        Profile.ApiBase := Obj.Get('api_base', '');
        Profile.Preset := Obj.Get('preset', '');
        Profile.KeySource := Obj.Get('key_source', '');
        Profile.KeyEnv := Obj.Get('key_env', '');
        Profile.KeyValue := Obj.Get('key_value', '');
        If Obj.Find('image_output') <> Nil Then
          Profile.ImageOutput := Obj.Get('image_output', False);
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
    Result := Profile.ImageOutput
  Else
    Result := False;
End;

Function AssistantTurnOffersImageOutput(Mode: TAssistantMode): Boolean;
Begin
  { Read the saved profile on each call. A model switch applies on the next turn. }
  Result := (Mode = amBuild) And ActiveProfileImageOutput;
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
