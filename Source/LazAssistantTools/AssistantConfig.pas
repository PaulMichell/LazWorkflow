Unit AssistantConfig;

{ Persistent LazAssistantTools settings (OAuth tokens, model, thinking, approval) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, GrokOAuth, AssistantConnections;

Const
  AssistantConfigFileName = 'LazAssistantTools.xml';
  AssistantConfigLegacyFileName = 'LazGrokChat.xml';
  AssistantConfigDefaultApiBase = 'https://api.x.ai/v1';
  AssistantConfigDefaultModel = 'grok-4.5';
  AssistantConfigDefaultThinking = 'high';
  AssistantConfigDefaultApproval = 'ask';

Type
  { Reasoning effort sent as reasoning_effort (xAI / Grok Build "thinking level").
    xhigh is grok-4.6+; older models treat it as high. }
  TAssistantThinkingLevel = (atlLow, atlMedium, atlHigh, atlXHigh);

  { Tool approval policy (Grok Build permission mode analogue). }
  TAssistantApprovalMode = (
    aamAsk,     { Prompt before write/compile tools }
    aamAuto,    { Auto-allow project tools (like acceptEdits / auto) }
    aamAlways   { Never prompt (like always-approve) }
  );

  TAssistantConfig = Class
  Private
    FApiBase: String;
    FModel: String;
    FActiveSkill: String;
    FIncludeIDEContext: Boolean;
    FThinkingLevel: String;
    FApprovalMode: String;
    FAutoNewChatAtContextLimit: Boolean;
    FAccessToken: String;
    FRefreshToken: String;
    FTokenType: String;
    FScope: String;
    FExpiresAt: TDateTime;
  Public
    Constructor Create;
    Procedure Load;
    Procedure Save;
    { Nil connections keeps the saved connection list and updates the Grok account from this config. }
    Procedure LoadWithConnections(Connections: TAssistantConnections);
    Procedure SaveWithConnections(Connections: TAssistantConnections);
    Procedure Assign(Source: TAssistantConfig);
    Procedure ApplyOAuthTokens(Const Tokens: TGrokOAuthTokens);
    Procedure ClearOAuthTokens;
    Function ToOAuthTokens: TGrokOAuthTokens;
    Function IsSignedIn: Boolean;
    Function GetThinkingLevel: TAssistantThinkingLevel;
    Procedure SetThinkingLevelEnum(Value: TAssistantThinkingLevel);
    Function GetApprovalMode: TAssistantApprovalMode;
    Procedure SetApprovalModeEnum(Value: TAssistantApprovalMode);
    Property ApiBase: String Read FApiBase Write FApiBase;
    Property Model: String Read FModel Write FModel;
    { Directory name under ~/.grok/skills, or empty for no skill. }
    Property ActiveSkill: String Read FActiveSkill Write FActiveSkill;
    { Attach active editor + project file list to each outgoing user message. }
    Property IncludeIDEContext: Boolean Read FIncludeIDEContext Write FIncludeIDEContext;
    { low | medium | high | xhigh — API reasoning_effort. }
    Property ThinkingLevel: String Read FThinkingLevel Write FThinkingLevel;
    { ask | auto | always — tool approval policy. }
    Property ApprovalMode: String Read FApprovalMode Write FApprovalMode;
    { When context ≥ 95%, start a new conversation automatically. }
    Property AutoNewChatAtContextLimit: Boolean Read FAutoNewChatAtContextLimit
      Write FAutoNewChatAtContextLimit;
    Property AccessToken: String Read FAccessToken Write FAccessToken;
    Property RefreshToken: String Read FRefreshToken Write FRefreshToken;
    Property TokenType: String Read FTokenType Write FTokenType;
    Property Scope: String Read FScope Write FScope;
    Property ExpiresAt: TDateTime Read FExpiresAt Write FExpiresAt;
  End;

Function ThinkingLevelToStr(Level: TAssistantThinkingLevel): String;
Function StrToThinkingLevel(Const Value: String): TAssistantThinkingLevel;
Function ThinkingLevelCaption(Level: TAssistantThinkingLevel): String;
Function ApprovalModeToStr(Mode: TAssistantApprovalMode): String;
Function StrToApprovalMode(Const Value: String): TAssistantApprovalMode;
Function ApprovalModeCaption(Mode: TAssistantApprovalMode): String;

Var
  AssistantChatConfig: TAssistantConfig;

Implementation

Uses
  fpjson, WorkflowSettings;

Function ThinkingLevelToStr(Level: TAssistantThinkingLevel): String;
Begin
  Case Level Of
    atlLow: Result := 'low';
    atlMedium: Result := 'medium';
    atlXHigh: Result := 'xhigh';
  Else
    Result := 'high';
  End;
End;

Function StrToThinkingLevel(Const Value: String): TAssistantThinkingLevel;
Var
  V: String;
Begin
  V := LowerCase(Trim(Value));
  V := StringReplace(V, '_', '', [rfReplaceAll]);
  V := StringReplace(V, '-', '', [rfReplaceAll]);
  V := StringReplace(V, ' ', '', [rfReplaceAll]);
  If (V = 'low') Or (V = 'minimal') Or (V = 'none') Then
    Result := atlLow
  Else If (V = 'medium') Or (V = 'med') Then
    Result := atlMedium
  Else If (V = 'xhigh') Or (V = 'extrahigh') Or (V = 'max') Then
    Result := atlXHigh
  Else
    Result := atlHigh;
End;

Function ThinkingLevelCaption(Level: TAssistantThinkingLevel): String;
Begin
  Case Level Of
    atlLow: Result := 'Low';
    atlMedium: Result := 'Medium';
    atlXHigh: Result := 'XHigh';
  Else
    Result := 'High';
  End;
End;

Function ApprovalModeToStr(Mode: TAssistantApprovalMode): String;
Begin
  Case Mode Of
    aamAsk: Result := 'ask';
    aamAuto: Result := 'auto';
  Else
    Result := 'always';
  End;
End;

Function StrToApprovalMode(Const Value: String): TAssistantApprovalMode;
Var
  V: String;
Begin
  V := LowerCase(Trim(Value));
  If (V = 'ask') Or (V = 'default') Then
    Result := aamAsk
  Else If (V = 'auto') Or (V = 'acceptedits') Then
    Result := aamAuto
  Else If (V = 'always') Then
    Result := aamAlways
  Else
    Result := aamAsk;
End;

Function ApprovalModeCaption(Mode: TAssistantApprovalMode): String;
Begin
  Case Mode Of
    aamAsk: Result := 'Ask';
    aamAuto: Result := 'Auto';
  Else
    Result := 'Always';
  End;
End;

Function DateTimeToConfig(Value: TDateTime): String;
Begin
  If Value <= 0 Then
    Result := ''
  Else
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Value);
End;

Function ConfigToDateTime(Const Value: String): TDateTime;
Var
  Y, M, D, H, N, S: Integer;
Begin
  Result := 0;
  If Trim(Value) = '' Then
    Exit;
  If Length(Value) < 19 Then
    Exit;
  Y := StrToIntDef(Copy(Value, 1, 4), 0);
  M := StrToIntDef(Copy(Value, 6, 2), 0);
  D := StrToIntDef(Copy(Value, 9, 2), 0);
  H := StrToIntDef(Copy(Value, 12, 2), 0);
  N := StrToIntDef(Copy(Value, 15, 2), 0);
  S := StrToIntDef(Copy(Value, 18, 2), 0);
  If (Y < 2000) Or (M < 1) Or (D < 1) Then
    Exit;
  Try
    Result := EncodeDate(Y, M, D) + EncodeTime(H, N, S, 0);
  Except
    Result := 0;
  End;
End;

Constructor TAssistantConfig.Create;
Begin
  Inherited Create;
  FApiBase := AssistantConfigDefaultApiBase;
  FModel := AssistantConfigDefaultModel;
  FActiveSkill := '';
  FIncludeIDEContext := False;
  FThinkingLevel := AssistantConfigDefaultThinking;
  FApprovalMode := AssistantConfigDefaultApproval;
  FAutoNewChatAtContextLimit := False;
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Function TAssistantConfig.IsSignedIn: Boolean;
Begin
  Result := (Trim(FAccessToken) <> '') Or (Trim(FRefreshToken) <> '');
End;

Function TAssistantConfig.GetThinkingLevel: TAssistantThinkingLevel;
Begin
  Result := StrToThinkingLevel(FThinkingLevel);
End;

Procedure TAssistantConfig.SetThinkingLevelEnum(Value: TAssistantThinkingLevel);
Begin
  FThinkingLevel := ThinkingLevelToStr(Value);
End;

Function TAssistantConfig.GetApprovalMode: TAssistantApprovalMode;
Begin
  Result := StrToApprovalMode(FApprovalMode);
End;

Procedure TAssistantConfig.SetApprovalModeEnum(Value: TAssistantApprovalMode);
Begin
  FApprovalMode := ApprovalModeToStr(Value);
End;

Procedure TAssistantConfig.Assign(Source: TAssistantConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FApiBase := Source.ApiBase;
  FModel := Source.Model;
  FActiveSkill := Source.ActiveSkill;
  FIncludeIDEContext := Source.IncludeIDEContext;
  FThinkingLevel := Source.ThinkingLevel;
  FApprovalMode := Source.ApprovalMode;
  FAutoNewChatAtContextLimit := Source.AutoNewChatAtContextLimit;
  FAccessToken := Source.AccessToken;
  FRefreshToken := Source.RefreshToken;
  FTokenType := Source.TokenType;
  FScope := Source.Scope;
  FExpiresAt := Source.ExpiresAt;
End;

Procedure TAssistantConfig.ApplyOAuthTokens(Const Tokens: TGrokOAuthTokens);
Begin
  FAccessToken := Tokens.AccessToken;
  FRefreshToken := Tokens.RefreshToken;
  FTokenType := Tokens.TokenType;
  If FTokenType = '' Then
    FTokenType := 'Bearer';
  FScope := Tokens.Scope;
  FExpiresAt := Tokens.ExpiresAt;
End;

Procedure TAssistantConfig.ClearOAuthTokens;
Begin
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Function TAssistantConfig.ToOAuthTokens: TGrokOAuthTokens;
Begin
  Result.AccessToken := FAccessToken;
  Result.RefreshToken := FRefreshToken;
  Result.TokenType := FTokenType;
  Result.Scope := FScope;
  Result.ExpiresAt := FExpiresAt;
End;

Procedure NormalizeAssistantConfig(Config: TAssistantConfig);
Begin
  If Not Assigned(Config) Then
    Exit;
  If Trim(Config.FApiBase) = '' Then
    Config.FApiBase := AssistantConfigDefaultApiBase;
  If Trim(Config.FModel) = '' Then
    Config.FModel := AssistantConfigDefaultModel;
  If Trim(Config.FTokenType) = '' Then
    Config.FTokenType := 'Bearer';
  Config.FThinkingLevel := ThinkingLevelToStr(StrToThinkingLevel(Config.FThinkingLevel));
  Config.FApprovalMode := ApprovalModeToStr(StrToApprovalMode(Config.FApprovalMode));
End;

Procedure ApplyOAuthObject(Config: TAssistantConfig; Auth: TJSONObject);
Begin
  If (Not Assigned(Config)) Or (Not Assigned(Auth)) Then
    Exit;
  Config.FAccessToken := Auth.Get('access_token', '');
  Config.FRefreshToken := Auth.Get('refresh_token', '');
  Config.FTokenType := Auth.Get('token_type', 'Bearer');
  Config.FScope := Auth.Get('scope', '');
  Config.FExpiresAt := ConfigToDateTime(Auth.Get('expiry', ''));
End;

Function OAuthObject(Config: TAssistantConfig): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('access_token', Config.FAccessToken);
  Result.Add('refresh_token', Config.FRefreshToken);
  Result.Add('token_type', Config.FTokenType);
  Result.Add('scope', Config.FScope);
  Result.Add('expiry', DateTimeToConfig(Config.FExpiresAt));
End;

Procedure ApplyGrokObject(Config: TAssistantConfig; Obj: TJSONObject);
Var
  Auth: TJSONData;
Begin
  If (Not Assigned(Config)) Or (Not Assigned(Obj)) Then
    Exit;
  Config.FApiBase := Obj.Get('api_base', AssistantConfigDefaultApiBase);
  Config.FActiveSkill := Obj.Get('skill', '');
  Config.FModel := Obj.Get('model', AssistantConfigDefaultModel);
  Config.FThinkingLevel := Obj.Get('thinking', AssistantConfigDefaultThinking);
  Config.FApprovalMode := Obj.Get('approval', AssistantConfigDefaultApproval);
  Auth := Obj.Find('oauth');
  If Auth Is TJSONObject Then
    ApplyOAuthObject(Config, TJSONObject(Auth))
  Else
    Config.ClearOAuthTokens;
  NormalizeAssistantConfig(Config);
End;

Function ConnectionObject(Item: TAssistantConnection; Config: TAssistantConfig): TJSONObject;
Var
  Thinking, Approval, Model: String;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Item.Id);
  Result.Add('name', Item.Name);
  Result.Add('backend', Item.Backend);
  Model := Item.Model;
  Thinking := Item.ReasoningEffort;
  Approval := Item.ApprovalMode;
  If (Item.Backend = 'grok') And Assigned(Config) Then
    Begin
      Model := Config.Model;
      Thinking := Config.ThinkingLevel;
      Approval := Config.ApprovalMode;
      Result.Add('api_base', Config.ApiBase);
      Result.Add('skill', Config.ActiveSkill);
      Result.Add('oauth', OAuthObject(Config));
    End;
  Result.Add('model', Model);
  Result.Add('thinking', Thinking);
  Result.Add('approval', Approval);
  If Item.Backend = 'codex' Then
    Result.Add('runtime', Item.Runtime);
End;

Procedure ReadConnection(Obj: TJSONObject; Item: TAssistantConnection);
Begin
  Item.Id := Obj.Get('id', Item.Id);
  Item.Name := Obj.Get('name', Item.Name);
  Item.Backend := Obj.Get('backend', Item.Backend);
  Item.Model := Obj.Get('model', '');
  Item.ReasoningEffort := Obj.Get('thinking', '');
  Item.ApprovalMode := Obj.Get('approval', 'ask');
  If Not ((Item.ApprovalMode = 'auto') Or (Item.ApprovalMode = 'always')) Then
    Item.ApprovalMode := 'ask';
  Item.Runtime := Obj.Get('runtime', '');
End;

Procedure TAssistantConfig.LoadWithConnections(Connections: TAssistantConnections);
Var
  Section, Obj: TJSONObject;
  Node, ItemNode: TJSONData;
  Item: TAssistantConnection;
  I: Integer;
  SeenGrok: Boolean;
Begin
  Section := ReadWorkflowSection('assistant');
  Try
    FIncludeIDEContext := False;
    FAutoNewChatAtContextLimit := False;
    If Assigned(Connections) Then
      Connections.ClearStored;
    If Not Assigned(Section) Then
      Begin
        If Assigned(Connections) Then
          Connections.EnsureBuiltinGrok;
        Exit;
      End;
    FIncludeIDEContext := Section.Get('include_ide_context', False);
    FAutoNewChatAtContextLimit := Section.Get('auto_new_chat_at_limit', False);
    SeenGrok := False;
    Node := Section.Find('connections');
    If Node Is TJSONArray Then
      For I := 0 To TJSONArray(Node).Count - 1 Do
        Begin
          ItemNode := TJSONArray(Node).Items[I];
          If Not (ItemNode Is TJSONObject) Then
            Continue;
          Obj := TJSONObject(ItemNode);
          If Assigned(Connections) Then
            Begin
              Item := Connections.AddStored(Obj.Get('id', ''), Obj.Get('name', ''), Obj.Get('backend', ''));
              If Assigned(Item) Then
                Begin
                  ReadConnection(Obj, Item);
                  If Item.Backend = 'grok' Then
                    Begin
                      SeenGrok := True;
                      ApplyGrokObject(Self, Obj);
                    End;
                End;
            End
          Else If Obj.Get('backend', '') = 'grok' Then
            Begin
              SeenGrok := True;
              ApplyGrokObject(Self, Obj);
            End;
        End;
    If Assigned(Connections) Then
      Begin
        If Not SeenGrok Then
          Connections.EnsureBuiltinGrok;
        Connections.ActiveId := Section.Get('active_connection', 'grok');
        If Connections.Active = Nil Then
          Connections.ActiveId := 'grok';
      End;
  Finally
    Section.Free;
  End;
  NormalizeAssistantConfig(Self);
End;

Procedure TAssistantConfig.SaveWithConnections(Connections: TAssistantConnections);
Var
  Section, Existing, Obj: TJSONObject;
  Node, ItemNode: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  ErrorText: String;
  Item: TAssistantConnection;
  HasGrok: Boolean;
Begin
  Section := TJSONObject.Create;
  Try
    Section.Add('include_ide_context', FIncludeIDEContext);
    Section.Add('auto_new_chat_at_limit', FAutoNewChatAtContextLimit);
    Arr := TJSONArray.Create;
    Section.Add('connections', Arr);
    If Assigned(Connections) Then
      Begin
        If Connections.Count = 0 Then
          Connections.EnsureBuiltinGrok;
        Section.Add('active_connection', Connections.ActiveId);
        For I := 0 To Connections.Count - 1 Do
          Arr.Add(ConnectionObject(Connections[I], Self));
      End
    Else
      Begin
        Existing := ReadWorkflowSection('assistant');
        Try
          If Assigned(Existing) Then
            Section.Add('active_connection', Existing.Get('active_connection', 'grok'))
          Else
            Section.Add('active_connection', 'grok');
          Node := Nil;
          If Assigned(Existing) Then
            Node := Existing.Find('connections');
          If Node Is TJSONArray Then
            For I := 0 To TJSONArray(Node).Count - 1 Do
              Begin
                ItemNode := TJSONArray(Node).Items[I];
                If Not (ItemNode Is TJSONObject) Then
                  Continue;
                Obj := TJSONObject(ItemNode);
                If Obj.Get('backend', '') = 'grok' Then
                  Begin
                    Item := TAssistantConnection.Create;
                    Try
                      Item.Id := Obj.Get('id', 'grok');
                      Item.Name := Obj.Get('name', 'Grok');
                      Item.Backend := 'grok';
                      Arr.Add(ConnectionObject(Item, Self));
                    Finally
                      Item.Free;
                    End;
                  End
                Else
                  Arr.Add(Obj.Clone);
              End;
        Finally
          Existing.Free;
        End;
        HasGrok := False;
        For I := 0 To Arr.Count - 1 Do
          If (Arr.Items[I] Is TJSONObject) And (TJSONObject(Arr.Items[I]).Get('backend', '') = 'grok') Then
            HasGrok := True;
        If Not HasGrok Then
          Begin
            Item := TAssistantConnection.Create;
            Try
              Item.Id := 'grok';
              Item.Name := 'Grok';
              Item.Backend := 'grok';
              Arr.Add(ConnectionObject(Item, Self));
            Finally
              Item.Free;
            End;
          End;
      End;
    Existing := ReadWorkflowSection('assistant');
    Try
      If Assigned(Existing) Then
        Begin
          If Assigned(Existing.Find('target_directory')) And (Section.Find('target_directory') = Nil) Then
            Section.Add('target_directory', Existing.Get('target_directory', ''));
          If (Existing.Find('recent_targets') Is TJSONArray) And (Section.Find('recent_targets') = Nil) Then
            Section.Add('recent_targets', Existing.Find('recent_targets').Clone);
        End;
    Finally
      Existing.Free;
    End;
    WriteWorkflowSection('assistant', Section, ErrorText);
  Finally
    Section.Free;
  End;
End;

Procedure TAssistantConfig.Load;
Begin
  LoadWithConnections(Nil);
End;

Procedure TAssistantConfig.Save;
Begin
  SaveWithConnections(Nil);
End;

Initialization

AssistantChatConfig := TAssistantConfig.Create;
AssistantChatConfig.Load;
If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
  GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);

Finalization

FreeAndNil(AssistantChatConfig);

End.
