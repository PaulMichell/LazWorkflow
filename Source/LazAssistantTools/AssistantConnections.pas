Unit AssistantConnections;

{ Named connection definitions. Credentials remain with each backend's account
  owner; selecting a connection never disconnects another account.
  Codex homes are derived paths only. This unit does not create or delete them. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs;

Const
  AssistantOpenRouterApiBase = 'https://openrouter.ai/api/v1';
  AssistantWireChatCompletions = 'chat-completions';
  AssistantOpenRouterKeyEnv = 'OPENROUTER_API_KEY';

Type
  TAssistantConnection = Class
    Id, Name, Backend, Runtime, Model, ReasoningEffort, ApprovalMode: String;
    SearchMode, AnswerVerbosity, Preset, ApiBase: String;
    KeySource, KeyEnv, KeyValue, WireApi: String;
    CachedModelsJson: String;
    SearchCitations: Boolean;
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

Implementation

Uses
  AssistantConfig;

Constructor TAssistantConnection.Create;
Begin
  Inherited Create;
  ApprovalMode := 'ask';
  SearchMode := 'off';
  SearchCitations := False;
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
