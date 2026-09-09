Unit AssistantConnections;
{ Named connection definitions. Credentials remain with each backend's account
  owner; selecting a connection never disconnects another account. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, Contnrs;
Type
  TAssistantConnection = Class
    Id, Name, Backend, Runtime, Model, ReasoningEffort, ApprovalMode: String;
    Constructor Create;
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
    Procedure Save;
    Function AddChatGPT: TAssistantConnection;
    Function Active: TAssistantConnection;
    Function ProfileDir(Connection: TAssistantConnection): String;
    Procedure Remove(Index: Integer);
    Property Count: Integer Read GetCount;
    Property Items[Index: Integer]: TAssistantConnection Read GetItem; Default;
  End;
Implementation
Uses IniFiles;
Constructor TAssistantConnection.Create;
Begin Inherited Create; ApprovalMode := 'ask'; End;
Constructor TAssistantConnections.Create(Const ConfigRoot: String);
Begin Inherited Create; FRoot := IncludeTrailingPathDelimiter(ConfigRoot); FItems := TObjectList.Create(True); End;
Destructor TAssistantConnections.Destroy;
Begin FItems.Free; Inherited Destroy; End;
Function TAssistantConnections.GetCount: Integer;
Begin Result := FItems.Count; End;
Function TAssistantConnections.GetItem(Index: Integer): TAssistantConnection;
Begin Result := TAssistantConnection(FItems[Index]); End;
Function SafeId(Const Value: String): Boolean;
Var C: Char;
Begin
  Result := (Value <> '') And (Length(Value) <= 80);
  For C In Value Do If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) Then Exit(False);
End;
Procedure TAssistantConnections.Load;
Var Config: TIniFile; Sections: TStringList; I, J: Integer; Item: TAssistantConnection; Id: String; Duplicate: Boolean;
Begin
  FItems.Clear; ActiveId := 'grok';
  Config := TIniFile.Create(FRoot + 'assistant-connections.ini'); Sections := TStringList.Create;
  Try
    Config.ReadSections(Sections);
    For I := 0 To Sections.Count - 1 Do
      If Copy(Sections[I], 1, 11) = 'connection:' Then
        Begin
          Id := Copy(Sections[I], 12, MaxInt); If Not SafeId(Id) Then Continue;
          Duplicate := False;
          For J := 0 To Count - 1 Do If Items[J].Id = Id Then Duplicate := True;
          If Duplicate Then Continue;
          Item := TAssistantConnection.Create; Item.Id := Id;
          Item.Name := Config.ReadString(Sections[I], 'name', Id);
          Item.Backend := Config.ReadString(Sections[I], 'backend', '');
          Item.Runtime := Config.ReadString(Sections[I], 'runtime', '');
          Item.Model := Config.ReadString(Sections[I], 'model', '');
          Item.ReasoningEffort := Config.ReadString(Sections[I], 'reasoning_effort', '');
          Item.ApprovalMode := Config.ReadString(Sections[I], 'approval_mode', 'ask');
          If Not ((Item.ApprovalMode = 'auto') Or (Item.ApprovalMode = 'always')) Then Item.ApprovalMode := 'ask';
          FItems.Add(Item);
        End;
    ActiveId := Config.ReadString('settings', 'active', 'grok');
  Finally Sections.Free; Config.Free; End;
  If Count = 0 Then
    Begin
      Item := TAssistantConnection.Create; Item.Id := 'grok'; Item.Name := 'Grok'; Item.Backend := 'grok'; FItems.Add(Item);
      Item := TAssistantConnection.Create; Item.Id := 'chatgpt'; Item.Name := 'ChatGPT'; Item.Backend := 'codex'; FItems.Add(Item);
      Config := TIniFile.Create(FRoot + 'assistant-backend.ini');
      Try
        Item.Runtime := Config.ReadString('ChatGPT', 'Runtime', '');
        Item.Model := Config.ReadString('ChatGPT', 'Model', '');
        If Config.ReadBool('ChatGPT', 'Selected', False) Then ActiveId := Item.Id;
      Finally Config.Free; End;
    End;
  If Active = Nil Then ActiveId := Items[0].Id;
End;
Procedure TAssistantConnections.Save;
Var Config: TMemIniFile; I: Integer; Section, Temp: String;
Begin
  ForceDirectories(FRoot); Temp := FRoot + 'assistant-connections.ini.tmp';
  Config := TMemIniFile.Create(Temp);
  Try
    Config.Clear; Config.WriteInteger('settings', 'version', 1);
    Config.WriteString('settings', 'active', ActiveId);
    For I := 0 To Count - 1 Do
      Begin
        If Not SafeId(Items[I].Id) Then Raise Exception.Create('Invalid connection identifier');
        Section := 'connection:' + Items[I].Id;
        Config.WriteString(Section, 'name', Items[I].Name);
        Config.WriteString(Section, 'backend', Items[I].Backend);
        Config.WriteString(Section, 'runtime', Items[I].Runtime);
        Config.WriteString(Section, 'model', Items[I].Model);
        Config.WriteString(Section, 'reasoning_effort', Items[I].ReasoningEffort);
        Config.WriteString(Section, 'approval_mode', Items[I].ApprovalMode);
      End;
    Config.UpdateFile;
  Finally Config.Free; End;
  If Not RenameFile(Temp, FRoot + 'assistant-connections.ini') Then Raise Exception.Create('Could not save connection settings');
End;
Function TAssistantConnections.AddChatGPT: TAssistantConnection;
Var Id: TGuid;
Begin
  If CreateGUID(Id) <> 0 Then Raise Exception.Create('Cannot create connection identifier');
  Result := TAssistantConnection.Create; Result.Id := Copy(GUIDToString(Id), 2, 36);
  Result.Name := 'ChatGPT ' + IntToStr(Count); Result.Backend := 'codex'; FItems.Add(Result);
End;
Function TAssistantConnections.Active: TAssistantConnection;
Var I: Integer;
Begin Result := Nil; For I := 0 To Count - 1 Do If Items[I].Id = ActiveId Then Exit(Items[I]); End;
Function TAssistantConnections.ProfileDir(Connection: TAssistantConnection): String;
Begin
  If Not SafeId(Connection.Id) Then Raise Exception.Create('Invalid connection identifier');
  If Connection.Id = 'chatgpt' Then Result := FRoot + 'assistant-codex-preview'
  Else Result := FRoot + 'assistant-codex-connections' + PathDelim + Connection.Id;
End;
Procedure TAssistantConnections.Remove(Index: Integer);
Begin
  If (Index < 0) Or (Index >= Count) Or (Items[Index].Backend = 'grok') Then Exit;
  If ActiveId = Items[Index].Id Then ActiveId := 'grok';
  FItems.Delete(Index);
End;
End.
