Unit AssistantConfig;

{ Persistent LazAssistantTools settings (OAuth tokens, model, thinking, approval) (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Sampling migration, skill modes, and
  the assistant section load/save are one store. Splitting them would leave the
  private config fields behind. Reviewed 2026-10-05: no separate consumer identified. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, GrokOAuth, AssistantConnections;

Const
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
    FShowThinking: Boolean;
    FShowToolCalls: Boolean;
    FSearchMode: String;
    FSearchCitations: Boolean;
    FAnswerVerbosity: String;
    FMaxOutputTokens: Integer;
    FEnterInsertsNewline: Boolean;
    FAutoCompactContext: Boolean;
    FSkillModes: TJSONObject;
    FAccessToken: String;
    FRefreshToken: String;
    FTokenType: String;
    FScope: String;
    FExpiresAt: TDateTime;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Load;
    Procedure Save;
    { Nil connections keeps the saved list, including an empty list, and updates an existing Grok row from this config. }
    Procedure LoadWithConnections(Connections: TAssistantConnections);
    Function SaveWithConnections(Connections: TAssistantConnections): Boolean;
    Procedure Assign(Source: TAssistantConfig);
    Procedure ApplyOAuthTokens(Const Tokens: TGrokOAuthTokens);
    Procedure ClearOAuthTokens;
    Function ToOAuthTokens: TGrokOAuthTokens;
    Function IsSignedIn: Boolean;
    Function GetThinkingLevel: TAssistantThinkingLevel;
    Procedure SetThinkingLevelEnum(Value: TAssistantThinkingLevel);
    Function GetApprovalMode: TAssistantApprovalMode;
    Procedure SetApprovalModeEnum(Value: TAssistantApprovalMode);
    /// True when the skill is tagged for that mode. Modes are inspect, document, plan, build, and chat.
    Function SkillHasMode(Const SkillName, ModeName: String): Boolean;
    /// Replaces one skill's mode list. An empty list removes the skill. Chat is stored only when named.
    Procedure SetSkillModes(Const SkillName: String; Modes: TStrings);
    /// Fills Names with skills tagged for ModeName. Clears Names first.
    Procedure CollectSkillsForMode(Const ModeName: String; Names: TStrings);
    /// Fills Modes with the tags for SkillName. Clears Modes first.
    Procedure CollectModesForSkill(Const SkillName: String; Modes: TStrings);
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
    { Show thinking blocks in the conversation trace. }
    Property ShowThinking: Boolean Read FShowThinking Write FShowThinking;
    { Show tool-call blocks in the conversation trace. }
    Property ShowToolCalls: Boolean Read FShowToolCalls Write FShowToolCalls;
    { off | auto | on — Grok live search. Off matches the previous request. }
    Property SearchMode: String Read FSearchMode Write FSearchMode;
    { Ask the completions fallback to return citations. Responses search tools return sources. }
    Property SearchCitations: Boolean Read FSearchCitations Write FSearchCitations;
    { low | medium | high — Responses text.verbosity. }
    Property AnswerVerbosity: String Read FAnswerVerbosity Write FAnswerVerbosity;
    { 0 omits the cap and uses the provider default. }
    Property MaxOutputTokens: Integer Read FMaxOutputTokens Write FMaxOutputTokens;
    { Enter key inserts a newline in the prompt. Default true. }
    Property EnterInsertsNewline: Boolean Read FEnterInsertsNewline Write FEnterInsertsNewline;
    { Compact older history near the context limit. Default false. }
    Property AutoCompactContext: Boolean Read FAutoCompactContext Write FAutoCompactContext;
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
  WorkflowSettings;

Function NormalizeGrokSearchMode(Const Value: String): String;
Begin
  Result := LowerCase(Trim(Value));
  If (Result = 'auto') Or (Result = 'on') Then
    Exit;
  Result := 'off';
End;

Function NormalizeGrokVerbosity(Const Value: String): String;
Begin
  Result := LowerCase(Trim(Value));
  If (Result = 'low') Or (Result = 'high') Then
    Exit;
  Result := 'medium';
End;

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
  FShowThinking := True;
  FShowToolCalls := True;
  FSearchMode := 'off';
  FSearchCitations := False;
  FAnswerVerbosity := 'medium';
  FMaxOutputTokens := 0;
  FEnterInsertsNewline := True;
  FAutoCompactContext := False;
  FSkillModes := TJSONObject.Create;
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Destructor TAssistantConfig.Destroy;
Begin
  FSkillModes.Free;
  Inherited Destroy;
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
  FShowThinking := Source.ShowThinking;
  FShowToolCalls := Source.ShowToolCalls;
  FSearchMode := Source.SearchMode;
  FSearchCitations := Source.SearchCitations;
  FAnswerVerbosity := Source.AnswerVerbosity;
  FMaxOutputTokens := Source.MaxOutputTokens;
  FEnterInsertsNewline := Source.EnterInsertsNewline;
  FAutoCompactContext := Source.AutoCompactContext;
  If Source = Self Then
    Exit;
  If Assigned(Source.FSkillModes) Then
    Begin
      FSkillModes.Free;
      FSkillModes := TJSONObject(Source.FSkillModes.Clone);
    End
  Else
    FSkillModes.Clear;
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

Function IsSkillMode(Const ModeName: String): Boolean;
Begin
  Result := (ModeName = 'inspect') Or (ModeName = 'document') Or (ModeName = 'plan') Or
    (ModeName = 'build') Or (ModeName = 'chat');
End;

Procedure AddSkillMode(Modes: TJSONObject; Const SkillName, ModeName: String);
Var
  Node: TJSONData;
  Arr: TJSONArray;
  I, Index: Integer;
  Mode, Name: String;
Begin
  Name := Trim(SkillName);
  Mode := LowerCase(Trim(ModeName));
  If (Not Assigned(Modes)) Or (Name = '') Or (Not IsSkillMode(Mode)) Then
    Exit;
  Node := Modes.Find(Name);
  If Node Is TJSONArray Then
    Arr := TJSONArray(Node)
  Else
    Begin
      Index := Modes.IndexOfName(Name);
      If Index >= 0 Then
        Modes.Delete(Index);
      Arr := TJSONArray.Create;
      Modes.Add(Name, Arr);
    End;
  For I := 0 To Arr.Count - 1 Do
    If (Arr.Items[I].JSONType = jtString) And (Arr.Items[I].AsString = Mode) Then
      Exit;
  Arr.Add(Mode);
End;

Procedure SeedSkillModes(Modes: TJSONObject; Const ActiveSkill: String);
Var
  SkillName: String;
Begin
  { Historical Plan/Build attachment, plus the saved pin on the four work modes. Never chat. }
  AddSkillMode(Modes, 'free-pascal-engineer', 'plan');
  AddSkillMode(Modes, 'free-pascal-engineer', 'build');
  SkillName := Trim(ActiveSkill);
  If (SkillName = '') Or (Pos('/', SkillName) > 0) Or (Pos('\', SkillName) > 0) Then
    Exit;
  AddSkillMode(Modes, SkillName, 'inspect');
  AddSkillMode(Modes, SkillName, 'document');
  AddSkillMode(Modes, SkillName, 'plan');
  AddSkillMode(Modes, SkillName, 'build');
End;

Function SkillModeListed(Modes: TJSONObject; Const SkillName, ModeName: String): Boolean;
Var
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := False;
  If (Not Assigned(Modes)) Or (SkillName = '') Or (ModeName = '') Then
    Exit;
  Node := Modes.Find(SkillName);
  If Not (Node Is TJSONArray) Then
    Exit;
  Arr := TJSONArray(Node);
  For I := 0 To Arr.Count - 1 Do
    If (Arr.Items[I].JSONType = jtString) And (Arr.Items[I].AsString = ModeName) Then
      Exit(True);
End;

Procedure ReadSkillModes(Config: TAssistantConfig; Section: TJSONObject);
Var
  Node, ItemNode: TJSONData;
  Obj: TJSONObject;
  Arr: TJSONArray;
  I, J: Integer;
  SkillName: String;
Begin
  Config.FSkillModes.Clear;
  Node := Nil;
  If Assigned(Section) Then
    Node := Section.Find('skill_modes');
  If Not (Node Is TJSONObject) Then
    Begin
      SeedSkillModes(Config.FSkillModes, Config.FActiveSkill);
      Exit;
    End;
  Obj := TJSONObject(Node);
  For I := 0 To Obj.Count - 1 Do
    Begin
      SkillName := Obj.Names[I];
      ItemNode := Obj.Items[I];
      If Not (ItemNode Is TJSONArray) Then
        Continue;
      Arr := TJSONArray(ItemNode);
      For J := 0 To Arr.Count - 1 Do
        If Arr.Items[J].JSONType = jtString Then
          AddSkillMode(Config.FSkillModes, SkillName, Arr.Items[J].AsString);
    End;
End;

Procedure WriteSkillModes(Section, Modes: TJSONObject);
Const
  ModeOrder: Array[0..4] Of String = ('inspect', 'document', 'plan', 'build', 'chat');
Var
  OutModes: TJSONObject;
  Arr: TJSONArray;
  I, J: Integer;
  SkillName: String;
Begin
  OutModes := TJSONObject.Create;
  Section.Add('skill_modes', OutModes);
  If Not Assigned(Modes) Then
    Exit;
  For I := 0 To Modes.Count - 1 Do
    Begin
      SkillName := Modes.Names[I];
      If SkillName = '' Then
        Continue;
      Arr := TJSONArray.Create;
      For J := Low(ModeOrder) To High(ModeOrder) Do
        If SkillModeListed(Modes, SkillName, ModeOrder[J]) Then
          Arr.Add(ModeOrder[J]);
      If Arr.Count = 0 Then
        Arr.Free
      Else
        OutModes.Add(SkillName, Arr);
    End;
End;

Procedure ClampOutputTokens(Var Tokens: Integer);
Begin
  If Tokens < 0 Then
    Tokens := 0;
  If Tokens > 1000000 Then
    Tokens := 1000000;
End;

Procedure NormalizeConnection(Item: TAssistantConnection);
Begin
  If Not Assigned(Item) Then
    Exit;
  Item.SearchMode := NormalizeGrokSearchMode(Item.SearchMode);
  Item.AnswerVerbosity := NormalizeGrokVerbosity(Item.AnswerVerbosity);
  ClampOutputTokens(Item.MaxOutputTokens);
  If Item.KeySource <> 'stored' Then
    Item.KeySource := 'env';
  If Item.Backend <> 'openai-compatible' Then
    Exit;
  If Item.Preset <> 'openrouter' Then
    Item.Preset := 'custom';
  Item.WireApi := AssistantWireChatCompletions;
  If Item.Preset = 'openrouter' Then
    Begin
      Item.ApiBase := AssistantOpenRouterApiBase;
      If Item.KeyEnv = '' Then
        Item.KeyEnv := AssistantOpenRouterKeyEnv;
    End;
End;

Procedure CopyGlobalGrokOntoRow(Config: TAssistantConfig; Item: TAssistantConnection);
Begin
  { The settings form still edits Grok sampling on the config. Stamp it onto the row at save
    so the stored row matches the edited values and a later load does not prefer a stale row. }
  If (Not Assigned(Config)) Or (Not Assigned(Item)) Or (Item.Backend <> 'grok') Then
    Exit;
  Item.Model := Config.Model;
  Item.ReasoningEffort := Config.ThinkingLevel;
  Item.ApprovalMode := Config.ApprovalMode;
  Item.SearchMode := Config.SearchMode;
  Item.SearchCitations := Config.SearchCitations;
  Item.AnswerVerbosity := Config.AnswerVerbosity;
  Item.MaxOutputTokens := Config.MaxOutputTokens;
  Item.ApiBase := Config.ApiBase;
  NormalizeConnection(Item);
End;

Procedure MigrateGrokRowFromGlobals(Config: TAssistantConfig; Obj: TJSONObject; Item: TAssistantConnection);
Begin
  If (Not Assigned(Config)) Or (Not Assigned(Item)) Or (Item.Backend <> 'grok') Then
    Exit;
  If Item.Model = '' Then
    Begin
      Item.Model := Config.Model;
      Item.ReasoningEffort := Config.ThinkingLevel;
      Item.ApprovalMode := Config.ApprovalMode;
      Item.ApiBase := Config.ApiBase;
      Item.SearchMode := Config.SearchMode;
      Item.SearchCitations := Config.SearchCitations;
      Item.AnswerVerbosity := Config.AnswerVerbosity;
      Item.MaxOutputTokens := Config.MaxOutputTokens;
    End
  Else If Assigned(Obj) Then
    Begin
      If Obj.Find('search_mode') = Nil Then
        Item.SearchMode := Config.SearchMode;
      If Obj.Find('search_citations') = Nil Then
        Item.SearchCitations := Config.SearchCitations;
      If Obj.Find('answer_verbosity') = Nil Then
        Item.AnswerVerbosity := Config.AnswerVerbosity;
      If Obj.Find('max_output_tokens') = Nil Then
        Item.MaxOutputTokens := Config.MaxOutputTokens;
    End;
  NormalizeConnection(Item);
End;

Procedure SyncConfigFromGrokRow(Config: TAssistantConfig; Obj: TJSONObject; Item: TAssistantConnection);
Var
  Auth: TJSONData;
Begin
  If (Not Assigned(Config)) Or (Not Assigned(Item)) Then
    Exit;
  If Item.Model <> '' Then
    Config.FModel := Item.Model;
  If Item.ReasoningEffort <> '' Then
    Config.FThinkingLevel := Item.ReasoningEffort;
  If Item.ApprovalMode <> '' Then
    Config.FApprovalMode := Item.ApprovalMode;
  If Item.ApiBase <> '' Then
    Config.FApiBase := Item.ApiBase;
  Config.FSearchMode := NormalizeGrokSearchMode(Item.SearchMode);
  Config.FSearchCitations := Item.SearchCitations;
  Config.FAnswerVerbosity := NormalizeGrokVerbosity(Item.AnswerVerbosity);
  Config.FMaxOutputTokens := Item.MaxOutputTokens;
  If Assigned(Obj) Then
    Begin
      Config.FActiveSkill := Obj.Get('skill', Config.FActiveSkill);
      Auth := Obj.Find('oauth');
      If Auth Is TJSONObject Then
        ApplyOAuthObject(Config, TJSONObject(Auth))
      Else
        Config.ClearOAuthTokens;
    End;
  NormalizeAssistantConfig(Config);
End;

Procedure AddSamplingFields(Target: TJSONObject; Item: TAssistantConnection);
Begin
  Target.Add('search_mode', NormalizeGrokSearchMode(Item.SearchMode));
  Target.Add('search_citations', Item.SearchCitations);
  Target.Add('answer_verbosity', NormalizeGrokVerbosity(Item.AnswerVerbosity));
  Target.Add('max_output_tokens', Item.MaxOutputTokens);
End;

Function ConnectionObject(Item: TAssistantConnection; Config: TAssistantConfig): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Item.Id);
  Result.Add('name', Item.Name);
  Result.Add('backend', Item.Backend);
  Result.Add('model', Item.Model);
  Result.Add('thinking', Item.ReasoningEffort);
  Result.Add('approval', Item.ApprovalMode);
  If (Item.Backend = 'grok') Or (Item.Backend = 'openai-compatible') Then
    AddSamplingFields(Result, Item);
  If Item.Backend = 'grok' Then
    Begin
      If Item.ApiBase <> '' Then
        Result.Add('api_base', Item.ApiBase)
      Else If Assigned(Config) Then
        Result.Add('api_base', Config.ApiBase)
      Else
        Result.Add('api_base', AssistantConfigDefaultApiBase);
      If Assigned(Config) Then
        Begin
          Result.Add('skill', Config.ActiveSkill);
          Result.Add('oauth', OAuthObject(Config));
        End;
    End;
  If Item.Backend = 'openai-compatible' Then
    Begin
      NormalizeConnection(Item);
      Result.Add('preset', Item.Preset);
      Result.Add('api_base', Item.ApiBase);
      Result.Add('key_source', Item.KeySource);
      Result.Add('key_env', Item.KeyEnv);
      { Stored key stays in this assistant section. Do not log KeyValue. }
      Result.Add('key_value', Item.KeyValue);
      Result.Add('wire_api', Item.WireApi);
    End;
  If (Item.Backend = 'codex') Or (Item.Backend = 'claude') Then
    Result.Add('runtime', Item.Runtime);
  If Item.Backend = 'codex' Then
    Result.Add('models_json', Item.CachedModelsJson);
End;

Procedure ReadConnection(Obj: TJSONObject; Item: TAssistantConnection);
Var
  Cache: TJSONData;
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
  Item.CachedModelsJson := '';
  Cache := Obj.Find('models_json');
  If (Item.Backend = 'codex') And Assigned(Cache) Then
    If Cache.JSONType = jtString Then
      Item.CachedModelsJson := Cache.AsString;
  If Obj.Find('search_mode') <> Nil Then
    Item.SearchMode := Obj.Get('search_mode', Item.SearchMode);
  If Obj.Find('search_citations') <> Nil Then
    Item.SearchCitations := Obj.Get('search_citations', False);
  If Obj.Find('answer_verbosity') <> Nil Then
    Item.AnswerVerbosity := Obj.Get('answer_verbosity', Item.AnswerVerbosity);
  If Obj.Find('max_output_tokens') <> Nil Then
    Item.MaxOutputTokens := Obj.Get('max_output_tokens', 0);
  Item.Preset := Obj.Get('preset', Item.Preset);
  Item.ApiBase := Obj.Get('api_base', Item.ApiBase);
  Item.KeySource := Obj.Get('key_source', Item.KeySource);
  Item.KeyEnv := Obj.Get('key_env', Item.KeyEnv);
  Item.KeyValue := Obj.Get('key_value', Item.KeyValue);
  Item.WireApi := Obj.Get('wire_api', Item.WireApi);
  NormalizeConnection(Item);
End;

Procedure TAssistantConfig.LoadWithConnections(Connections: TAssistantConnections);
Var
  Section, Obj: TJSONObject;
  Node, ItemNode: TJSONData;
  Item: TAssistantConnection;
  I: Integer;
Begin
  Section := ReadWorkflowSection('assistant');
  Try
    FIncludeIDEContext := False;
    FAutoNewChatAtContextLimit := False;
    FShowThinking := True;
    FShowToolCalls := True;
    FSearchMode := 'off';
    FSearchCitations := False;
    FAnswerVerbosity := 'medium';
    FMaxOutputTokens := 0;
    FEnterInsertsNewline := True;
    FAutoCompactContext := False;
    FApiBase := AssistantConfigDefaultApiBase;
    FModel := AssistantConfigDefaultModel;
    FActiveSkill := '';
    FThinkingLevel := AssistantConfigDefaultThinking;
    FApprovalMode := AssistantConfigDefaultApproval;
    ClearOAuthTokens;
    FSkillModes.Clear;
    If Assigned(Connections) Then
      Connections.ClearStored;
    If Not Assigned(Section) Then
      Begin
        SeedSkillModes(FSkillModes, '');
        Exit;
      End;
    FIncludeIDEContext := Section.Get('include_ide_context', False);
    FAutoNewChatAtContextLimit := Section.Get('auto_new_chat_at_limit', False);
    FShowThinking := Section.Get('show_thinking', True);
    FShowToolCalls := Section.Get('show_tool_calls', True);
    FSearchMode := NormalizeGrokSearchMode(Section.Get('search_mode', 'off'));
    FSearchCitations := Section.Get('search_citations', False);
    FAnswerVerbosity := NormalizeGrokVerbosity(Section.Get('answer_verbosity', 'medium'));
    FMaxOutputTokens := Section.Get('max_output_tokens', 0);
    ClampOutputTokens(FMaxOutputTokens);
    If Section.Find('auto_compact_context') = Nil Then
      FAutoCompactContext := FAutoNewChatAtContextLimit
    Else
      FAutoCompactContext := Section.Get('auto_compact_context', False);
    FEnterInsertsNewline := Section.Get('enter_inserts_newline', True);
    If Section.Find('model') <> Nil Then
      FModel := Section.Get('model', FModel);
    If Section.Find('thinking') <> Nil Then
      FThinkingLevel := Section.Get('thinking', FThinkingLevel);
    If Section.Find('approval') <> Nil Then
      FApprovalMode := Section.Get('approval', FApprovalMode);
    If Section.Find('api_base') <> Nil Then
      FApiBase := Section.Get('api_base', FApiBase);
    If Section.Find('active_skill') <> Nil Then
      FActiveSkill := Section.Get('active_skill', '');
    If (FActiveSkill = '') And (Section.Find('skill') <> Nil) Then
      FActiveSkill := Section.Get('skill', '');
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
                      MigrateGrokRowFromGlobals(Self, Obj, Item);
                      SyncConfigFromGrokRow(Self, Obj, Item);
                    End;
                End;
            End
          Else If Obj.Get('backend', '') = 'grok' Then
            ApplyGrokObject(Self, Obj);
        End;
    If Assigned(Connections) Then
      Begin
        Connections.ActiveId := Section.Get('active_connection', '');
        If Connections.Active = Nil Then
          Begin
            If Connections.Count > 0 Then
              Connections.ActiveId := Connections[0].Id
            Else
              Connections.ActiveId := '';
          End;
      End;
    ReadSkillModes(Self, Section);
  Finally
    Section.Free;
  End;
  NormalizeAssistantConfig(Self);
End;

Function ActiveIdInArray(Arr: TJSONArray; Const ActiveId: String): String;
Var
  I: Integer;
Begin
  Result := '';
  If (ActiveId = '') Or (Not Assigned(Arr)) Then
    Exit;
  For I := 0 To Arr.Count - 1 Do
    If (Arr.Items[I] Is TJSONObject) And (TJSONObject(Arr.Items[I]).Get('id', '') = ActiveId) Then
      Exit(ActiveId);
End;

Function ResolvedActiveId(Connections: TAssistantConnections): String;
Begin
  Result := '';
  If Assigned(Connections) And Assigned(Connections.Active) Then
    Result := Connections.ActiveId;
End;

Function TAssistantConfig.SaveWithConnections(Connections: TAssistantConnections): Boolean;
Var
  Section, Existing, Obj: TJSONObject;
  Node, ItemNode: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  ErrorText, SavedActive: String;
  Item: TAssistantConnection;
Begin
  Result := False;
  Section := TJSONObject.Create;
  Try
    Section.Add('include_ide_context', FIncludeIDEContext);
    Section.Add('auto_new_chat_at_limit', FAutoNewChatAtContextLimit);
    Section.Add('show_thinking', FShowThinking);
    Section.Add('show_tool_calls', FShowToolCalls);
    Section.Add('search_mode', NormalizeGrokSearchMode(FSearchMode));
    Section.Add('search_citations', FSearchCitations);
    Section.Add('answer_verbosity', NormalizeGrokVerbosity(FAnswerVerbosity));
    Section.Add('max_output_tokens', FMaxOutputTokens);
    Section.Add('auto_compact_context', FAutoCompactContext);
    Section.Add('enter_inserts_newline', FEnterInsertsNewline);
    WriteSkillModes(Section, FSkillModes);
    Arr := TJSONArray.Create;
    Section.Add('connections', Arr);
    If Assigned(Connections) Then
      Begin
        For I := 0 To Connections.Count - 1 Do
          Begin
            If Connections[I].Backend = 'grok' Then
              CopyGlobalGrokOntoRow(Self, Connections[I]);
            Arr.Add(ConnectionObject(Connections[I], Self));
          End;
        Section.Add('active_connection', ResolvedActiveId(Connections));
      End
    Else
      Begin
        Existing := ReadWorkflowSection('assistant');
        Try
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
                      ReadConnection(Obj, Item);
                      CopyGlobalGrokOntoRow(Self, Item);
                      Arr.Add(ConnectionObject(Item, Self));
                    Finally
                      Item.Free;
                    End;
                  End
                Else
                  Arr.Add(Obj.Clone);
              End;
          SavedActive := '';
          If Assigned(Existing) Then
            SavedActive := Existing.Get('active_connection', '');
          Section.Add('active_connection', ActiveIdInArray(Arr, SavedActive));
        Finally
          Existing.Free;
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
    Result := WriteWorkflowSection('assistant', Section, ErrorText);
  Finally
    Section.Free;
  End;
End;

Function TAssistantConfig.SkillHasMode(Const SkillName, ModeName: String): Boolean;
Begin
  Result := SkillModeListed(FSkillModes, SkillName, LowerCase(Trim(ModeName)));
End;

Procedure TAssistantConfig.SetSkillModes(Const SkillName: String; Modes: TStrings);
Var
  Index, I: Integer;
Begin
  If Trim(SkillName) = '' Then
    Exit;
  Index := FSkillModes.IndexOfName(SkillName);
  If Index >= 0 Then
    FSkillModes.Delete(Index);
  If Not Assigned(Modes) Then
    Exit;
  For I := 0 To Modes.Count - 1 Do
    AddSkillMode(FSkillModes, SkillName, Modes[I]);
End;

Procedure TAssistantConfig.CollectSkillsForMode(Const ModeName: String; Names: TStrings);
Var
  I: Integer;
  Mode: String;
Begin
  If Not Assigned(Names) Then
    Exit;
  Names.Clear;
  Mode := LowerCase(Trim(ModeName));
  If Not Assigned(FSkillModes) Then
    Exit;
  For I := 0 To FSkillModes.Count - 1 Do
    If SkillModeListed(FSkillModes, FSkillModes.Names[I], Mode) Then
      Names.Add(FSkillModes.Names[I]);
End;

Procedure TAssistantConfig.CollectModesForSkill(Const SkillName: String; Modes: TStrings);
Const
  ModeOrder: Array[0..4] Of String = ('inspect', 'document', 'plan', 'build', 'chat');
Var
  I: Integer;
Begin
  If Not Assigned(Modes) Then
    Exit;
  Modes.Clear;
  For I := Low(ModeOrder) To High(ModeOrder) Do
    If SkillModeListed(FSkillModes, SkillName, ModeOrder[I]) Then
      Modes.Add(ModeOrder[I]);
End;

Procedure TAssistantConfig.Load;
Begin
  LoadWithConnections(Nil);
End;

Procedure TAssistantConfig.Save;
Begin
  If Not SaveWithConnections(Nil) Then
    Exit;
End;

Initialization

AssistantChatConfig := TAssistantConfig.Create;
AssistantChatConfig.Load;
If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
  GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);

Finalization

FreeAndNil(AssistantChatConfig);

End.
