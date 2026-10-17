Unit AssistantConfig;

{ Persistent LazAssistantTools settings (OAuth tokens, model, thinking, approval) (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Sampling migration, skill modes,
  added guidance files, and the assistant section load/save are one store.
  Splitting them would leave the private config fields behind.
  Reviewed 2026-10-16: recovery intervals and caps sit beside auto_compact_context.
  A missing key keeps the default. The actor copies them when a turn starts. }

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
  { Recovery edits. Missing JSON keys keep these. The same numbers are the spin defaults. }
  AssistantReconnectIntervalDefault = 30;
  AssistantReconnectIntervalMax = 3600;
  AssistantCreditRetryDefault = 60;
  AssistantCreditRetryMax = 10080;
  AssistantContinuationDefault = 3;
  AssistantContinuationMax = 20;
  AssistantFaultRetryDefault = 1;
  AssistantFaultRetryMax = 10;
  { Same bounds as AssistantPlanRun. Stored here so settings load without that unit. }
  AssistantNewChatContextDefault = 95;
  AssistantNewChatContextMin = 50;
  AssistantNewChatContextMax = 99;

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
    FNewChatContextPercent: Integer;
    FShowThinking: Boolean;
    FShowToolCalls: Boolean;
    FSearchMode: String;
    FSearchCitations: Boolean;
    FAnswerVerbosity: String;
    FMaxOutputTokens: Integer;
    FEnterInsertsNewline: Boolean;
    FAutoCompactContext: Boolean;
    FReconnectIntervalSeconds: Integer;
    FCreditRetryMinutes: Integer;
    FAutomaticContinuations: Integer;
    FFaultRetries: Integer;
    FSkillModes: TJSONObject;
    FSkillFiles: TJSONObject;
    FSkillHidden: TStringList;
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
    /// Fills Names with skills tagged for ModeName. Clears Names first. Hidden skills are omitted.
    Procedure CollectSkillsForMode(Const ModeName: String; Names: TStrings);
    /// Adds skills whose SKILL.md declares ModeName, unless the user already saved a mode list.
    Procedure ApplyDeclaredSkillModes(Const ModeName, ProjectRoot: String; Names: TStrings);
    /// Copies declared modes into memory for skills that have no saved list. Does not write the settings file.
    Procedure RememberDeclaredModes(Const ProjectRoot: String; Names: TStrings);
    /// Fills Modes with the tags for SkillName. Clears Modes first.
    Procedure CollectModesForSkill(Const SkillName: String; Modes: TStrings);
    /// Fills Names with every skill that has a saved mode list. Clears Names first.
    Procedure CollectSkillModeNames(Names: TStrings);
    /// Absolute path for an added guidance file, or empty when the name is a catalog skill.
    Function SkillFilePath(Const SkillName: String): String;
    /// Stores or clears the file behind a skill name. An empty path removes the entry.
    Procedure SetSkillFile(Const SkillName, FilePath: String);
    /// True when the user removed this catalog skill from the settings grid.
    Function SkillIsHidden(Const SkillName: String): Boolean;
    Procedure SetSkillHidden(Const SkillName: String; Hidden: Boolean);
    /// Drops mode tags whose names are not in Keep. Keep may be nil.
    Procedure RetainSkillModes(Keep: TStrings);
    /// Drops file entries whose names are not in Keep. Keep may be nil.
    Procedure RetainSkillFiles(Keep: TStrings);
    /// Drops hidden names that are no longer discovered catalog skills.
    Procedure PruneHiddenSkills(Discovered: TStrings);
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
    { A plan run at NewChatContextPercent starts a new chat and continues. Key plan_continue_new_chat. Missing key is on. }
    Property AutoNewChatAtContextLimit: Boolean Read FAutoNewChatAtContextLimit
      Write FAutoNewChatAtContextLimit;
    { Percent of the context budget. Key new_chat_context_percent. Default 95. }
    Property NewChatContextPercent: Integer Read FNewChatContextPercent Write FNewChatContextPercent;
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
    { Seconds to wait after a lost connection. Key reconnect_interval_seconds. Default 30. }
    Property ReconnectIntervalSeconds: Integer Read FReconnectIntervalSeconds Write FReconnectIntervalSeconds;
    { Minutes to wait for credits when the reset time is unknown. Key credit_retry_minutes. Default 60. }
    Property CreditRetryMinutes: Integer Read FCreditRetryMinutes Write FCreditRetryMinutes;
    { Automatic continuations per task. Key automatic_continuations. Default 3. }
    Property AutomaticContinuations: Integer Read FAutomaticContinuations Write FAutomaticContinuations;
    { Fault retries per action. Key fault_retries. Default 1. A lost connection is not this cap. }
    Property FaultRetries: Integer Read FFaultRetries Write FFaultRetries;
    Property AccessToken: String Read FAccessToken Write FAccessToken;
    Property RefreshToken: String Read FRefreshToken Write FRefreshToken;
    Property TokenType: String Read FTokenType Write FTokenType;
    Property Scope: String Read FScope Write FScope;
    Property ExpiresAt: TDateTime Read FExpiresAt Write FExpiresAt;
  End;

Function ThinkingLevelToStr(Level: TAssistantThinkingLevel): String;
Function StrToThinkingLevel(Const Value: String): TAssistantThinkingLevel;
Function ApprovalModeToStr(Mode: TAssistantApprovalMode): String;
Function StrToApprovalMode(Const Value: String): TAssistantApprovalMode;
Function ApprovalModeCaption(Mode: TAssistantApprovalMode): String;

Var
  AssistantChatConfig: TAssistantConfig;

Implementation

Uses
  AssistantSkills, WorkflowSettings;

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
  FAutoNewChatAtContextLimit := True;
  FNewChatContextPercent := AssistantNewChatContextDefault;
  FShowThinking := True;
  FShowToolCalls := True;
  FSearchMode := 'off';
  FSearchCitations := False;
  FAnswerVerbosity := 'medium';
  FMaxOutputTokens := 0;
  FEnterInsertsNewline := True;
  FAutoCompactContext := False;
  FReconnectIntervalSeconds := AssistantReconnectIntervalDefault;
  FCreditRetryMinutes := AssistantCreditRetryDefault;
  FAutomaticContinuations := AssistantContinuationDefault;
  FFaultRetries := AssistantFaultRetryDefault;
  FSkillModes := TJSONObject.Create;
  FSkillFiles := TJSONObject.Create;
  FSkillHidden := TStringList.Create;
  FSkillHidden.CaseSensitive := False;
  FSkillHidden.Sorted := True;
  FSkillHidden.Duplicates := dupIgnore;
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Destructor TAssistantConfig.Destroy;
Begin
  FSkillHidden.Free;
  FSkillFiles.Free;
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
  FNewChatContextPercent := Source.NewChatContextPercent;
  FShowThinking := Source.ShowThinking;
  FShowToolCalls := Source.ShowToolCalls;
  FSearchMode := Source.SearchMode;
  FSearchCitations := Source.SearchCitations;
  FAnswerVerbosity := Source.AnswerVerbosity;
  FMaxOutputTokens := Source.MaxOutputTokens;
  FEnterInsertsNewline := Source.EnterInsertsNewline;
  FAutoCompactContext := Source.AutoCompactContext;
  FReconnectIntervalSeconds := Source.ReconnectIntervalSeconds;
  FCreditRetryMinutes := Source.CreditRetryMinutes;
  FAutomaticContinuations := Source.AutomaticContinuations;
  FFaultRetries := Source.FaultRetries;
  If Source = Self Then
    Exit;
  If Assigned(Source.FSkillModes) Then
    Begin
      FSkillModes.Free;
      FSkillModes := TJSONObject(Source.FSkillModes.Clone);
    End
  Else
    FSkillModes.Clear;
  If Assigned(Source.FSkillFiles) Then
    Begin
      FSkillFiles.Free;
      FSkillFiles := TJSONObject(Source.FSkillFiles.Clone);
    End
  Else
    FSkillFiles.Clear;
  If Assigned(Source.FSkillHidden) Then
    FSkillHidden.Assign(Source.FSkillHidden)
  Else
    FSkillHidden.Clear;
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

Function BoundRecoveryInt(Value, MinValue, MaxValue: Integer): Integer;
Begin
  If Value < MinValue Then
    Result := MinValue
  Else If Value > MaxValue Then
    Result := MaxValue
  Else
    Result := Value;
End;

Function ReadRecoveryInt(Section: TJSONObject; Const Key: String; DefaultValue, MinValue, MaxValue: Integer): Integer;
Var
  Node: TJSONData;
Begin
  Result := DefaultValue;
  If Not Assigned(Section) Then
    Exit;
  Node := Section.Find(Key);
  If Not Assigned(Node) Then
    Exit;
  If Node Is TJSONNumber Then
    Result := Node.AsInteger
  Else
    Result := StrToIntDef(Trim(Node.AsString), DefaultValue);
  Result := BoundRecoveryInt(Result, MinValue, MaxValue);
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
  Config.FReconnectIntervalSeconds := BoundRecoveryInt(Config.FReconnectIntervalSeconds, 0, AssistantReconnectIntervalMax);
  Config.FCreditRetryMinutes := BoundRecoveryInt(Config.FCreditRetryMinutes, 0, AssistantCreditRetryMax);
  Config.FAutomaticContinuations := BoundRecoveryInt(Config.FAutomaticContinuations, 0, AssistantContinuationMax);
  Config.FFaultRetries := BoundRecoveryInt(Config.FFaultRetries, 0, AssistantFaultRetryMax);
  If Config.FNewChatContextPercent <= 0 Then
    Config.FNewChatContextPercent := AssistantNewChatContextDefault;
  Config.FNewChatContextPercent := BoundRecoveryInt(Config.FNewChatContextPercent,
    AssistantNewChatContextMin, AssistantNewChatContextMax);
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

Procedure ReadSkillFiles(Config: TAssistantConfig; Section: TJSONObject);
Var
  Node: TJSONData;
  Obj: TJSONObject;
  I: Integer;
Begin
  Config.FSkillFiles.Clear;
  If Not Assigned(Section) Then
    Exit;
  Node := Section.Find('skill_files');
  If Not (Node Is TJSONObject) Then
    Exit;
  Obj := TJSONObject(Node);
  For I := 0 To Obj.Count - 1 Do
    If Obj.Items[I].JSONType = jtString Then
      Config.SetSkillFile(Obj.Names[I], Obj.Items[I].AsString);
End;

Procedure WriteSkillFiles(Section, Files: TJSONObject);
Var
  OutFiles: TJSONObject;
  I: Integer;
  Name, Path: String;
Begin
  OutFiles := TJSONObject.Create;
  Section.Add('skill_files', OutFiles);
  If Not Assigned(Files) Then
    Exit;
  For I := 0 To Files.Count - 1 Do
    Begin
      Name := Files.Names[I];
      If (Name = '') Or (Files.Items[I].JSONType <> jtString) Then
        Continue;
      Path := Trim(Files.Items[I].AsString);
      If Path <> '' Then
        OutFiles.Add(Name, Path);
    End;
End;

Procedure ReadSkillHidden(Config: TAssistantConfig; Section: TJSONObject);
Var
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
Begin
  Config.FSkillHidden.Clear;
  If Not Assigned(Section) Then
    Exit;
  Node := Section.Find('skill_hidden');
  If Not (Node Is TJSONArray) Then
    Exit;
  Arr := TJSONArray(Node);
  For I := 0 To Arr.Count - 1 Do
    If Arr.Items[I].JSONType = jtString Then
      Config.SetSkillHidden(Arr.Items[I].AsString, True);
End;

Procedure WriteSkillHidden(Section: TJSONObject; Hidden: TStrings);
Var
  Arr: TJSONArray;
  I: Integer;
Begin
  Arr := TJSONArray.Create;
  Section.Add('skill_hidden', Arr);
  If Not Assigned(Hidden) Then
    Exit;
  For I := 0 To Hidden.Count - 1 Do
    If Trim(Hidden[I]) <> '' Then
      Arr.Add(Trim(Hidden[I]));
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
  Result.Add('image_output', Item.ImageOutput);
  Result.Add('image_model', Item.ImageModel);
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
      { A fixture key must round-trip. OAuth remains the normal Grok credential. }
      If Item.KeyValue <> '' Then
        Result.Add('key_value', Item.KeyValue);
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
  Item.ImageOutput := False;
  If Obj.Find('image_output') <> Nil Then
    Item.ImageOutput := Obj.Get('image_output', False);
  Item.ImageModel := Obj.Get('image_model', '');
  { image_delivery is ignored. An old connection still opens. }
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
    FAutoNewChatAtContextLimit := True;
    FNewChatContextPercent := AssistantNewChatContextDefault;
    FShowThinking := True;
    FShowToolCalls := True;
    FSearchMode := 'off';
    FSearchCitations := False;
    FAnswerVerbosity := 'medium';
    FMaxOutputTokens := 0;
    FEnterInsertsNewline := True;
    FAutoCompactContext := False;
    FReconnectIntervalSeconds := AssistantReconnectIntervalDefault;
    FCreditRetryMinutes := AssistantCreditRetryDefault;
    FAutomaticContinuations := AssistantContinuationDefault;
    FFaultRetries := AssistantFaultRetryDefault;
    FApiBase := AssistantConfigDefaultApiBase;
    FModel := AssistantConfigDefaultModel;
    FActiveSkill := '';
    FThinkingLevel := AssistantConfigDefaultThinking;
    FApprovalMode := AssistantConfigDefaultApproval;
    ClearOAuthTokens;
    FSkillModes.Clear;
    FSkillFiles.Clear;
    FSkillHidden.Clear;
    If Assigned(Connections) Then
      Connections.ClearStored;
    If Not Assigned(Section) Then
      Begin
        SeedSkillModes(FSkillModes, '');
        Exit;
      End;
    FIncludeIDEContext := Section.Get('include_ide_context', False);
    { auto_new_chat_at_limit was saved false before it had a checkbox. The shown key is plan_continue_new_chat. }
    If Section.Find('plan_continue_new_chat') <> Nil Then
      FAutoNewChatAtContextLimit := Section.Get('plan_continue_new_chat', True)
    Else
      FAutoNewChatAtContextLimit := True;
    FNewChatContextPercent := ReadRecoveryInt(Section, 'new_chat_context_percent',
      AssistantNewChatContextDefault, AssistantNewChatContextMin, AssistantNewChatContextMax);
    FShowThinking := Section.Get('show_thinking', True);
    FShowToolCalls := Section.Get('show_tool_calls', True);
    FSearchMode := NormalizeGrokSearchMode(Section.Get('search_mode', 'off'));
    FSearchCitations := Section.Get('search_citations', False);
    FAnswerVerbosity := NormalizeGrokVerbosity(Section.Get('answer_verbosity', 'medium'));
    FMaxOutputTokens := Section.Get('max_output_tokens', 0);
    ClampOutputTokens(FMaxOutputTokens);
    { Do not copy a missing new-chat key onto compact. That key now defaults on. }
    If Section.Find('auto_compact_context') = Nil Then
      Begin
        If Section.Find('auto_new_chat_at_limit') <> Nil Then
          FAutoCompactContext := Section.Get('auto_new_chat_at_limit', False)
        Else
          FAutoCompactContext := False;
      End
    Else
      FAutoCompactContext := Section.Get('auto_compact_context', False);
    FEnterInsertsNewline := Section.Get('enter_inserts_newline', True);
    FReconnectIntervalSeconds := ReadRecoveryInt(Section, 'reconnect_interval_seconds',
      AssistantReconnectIntervalDefault, 0, AssistantReconnectIntervalMax);
    FCreditRetryMinutes := ReadRecoveryInt(Section, 'credit_retry_minutes',
      AssistantCreditRetryDefault, 0, AssistantCreditRetryMax);
    FAutomaticContinuations := ReadRecoveryInt(Section, 'automatic_continuations',
      AssistantContinuationDefault, 0, AssistantContinuationMax);
    FFaultRetries := ReadRecoveryInt(Section, 'fault_retries', AssistantFaultRetryDefault, 0, AssistantFaultRetryMax);
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
    ReadSkillFiles(Self, Section);
    ReadSkillHidden(Self, Section);
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
  NormalizeAssistantConfig(Self);
  Section := TJSONObject.Create;
  Try
    Section.Add('include_ide_context', FIncludeIDEContext);
    Section.Add('auto_new_chat_at_limit', FAutoNewChatAtContextLimit);
    Section.Add('plan_continue_new_chat', FAutoNewChatAtContextLimit);
    Section.Add('new_chat_context_percent', FNewChatContextPercent);
    Section.Add('show_thinking', FShowThinking);
    Section.Add('show_tool_calls', FShowToolCalls);
    Section.Add('search_mode', NormalizeGrokSearchMode(FSearchMode));
    Section.Add('search_citations', FSearchCitations);
    Section.Add('answer_verbosity', NormalizeGrokVerbosity(FAnswerVerbosity));
    Section.Add('max_output_tokens', FMaxOutputTokens);
    Section.Add('auto_compact_context', FAutoCompactContext);
    Section.Add('reconnect_interval_seconds', FReconnectIntervalSeconds);
    Section.Add('credit_retry_minutes', FCreditRetryMinutes);
    Section.Add('automatic_continuations', FAutomaticContinuations);
    Section.Add('fault_retries', FFaultRetries);
    Section.Add('enter_inserts_newline', FEnterInsertsNewline);
    WriteSkillModes(Section, FSkillModes);
    WriteSkillFiles(Section, FSkillFiles);
    WriteSkillHidden(Section, FSkillHidden);
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
    If SkillModeListed(FSkillModes, FSkillModes.Names[I], Mode) And
      (Not SkillIsHidden(FSkillModes.Names[I])) Then
      Names.Add(FSkillModes.Names[I]);
End;

Procedure TAssistantConfig.ApplyDeclaredSkillModes(Const ModeName, ProjectRoot: String; Names: TStrings);
Var
  Skills: TAssistantSkillList;
  Declared, Saved: TStringList;
  I: Integer;
  Mode, Name: String;
Begin
  If Not Assigned(Names) Then
    Exit;
  Mode := LowerCase(Trim(ModeName));
  If Not IsSkillMode(Mode) Then
    Exit;
  For I := Names.Count - 1 DownTo 0 Do
    If SkillIsHidden(Trim(Names[I])) Then
      Names.Delete(I);
  Saved := TStringList.Create;
  Declared := TStringList.Create;
  Try
    Saved.CaseSensitive := False;
    Declared.CaseSensitive := False;
    CollectSkillModeNames(Saved);
    Skills := ListGuidanceDocuments(ProjectRoot);
    For I := 0 To High(Skills) Do
      Begin
        Name := Skills[I].Name;
        If (Name = '') Or (Names.IndexOf(Name) >= 0) Or (Saved.IndexOf(Name) >= 0) Or SkillIsHidden(Name) Then
          Continue;
        Declared.Clear;
        If SkillDeclaredModes(Name, ProjectRoot, Declared) And (Declared.IndexOf(Mode) >= 0) Then
          Names.Add(Name);
      End;
    OmitRetiredBehaviourGuide(Names);
  Finally
    Declared.Free;
    Saved.Free;
  End;
End;

Procedure TAssistantConfig.RememberDeclaredModes(Const ProjectRoot: String; Names: TStrings);
Var
  Saved, Declared: TStringList;
  I: Integer;
Begin
  If Not Assigned(Names) Then
    Exit;
  Saved := TStringList.Create;
  Declared := TStringList.Create;
  Try
    Saved.CaseSensitive := False;
    Declared.CaseSensitive := False;
    CollectSkillModeNames(Saved);
    For I := 0 To Names.Count - 1 Do
      Begin
        If (Trim(Names[I]) = '') Or (Saved.IndexOf(Names[I]) >= 0) Or SkillIsHidden(Names[I]) Then
          Continue;
        Declared.Clear;
        If SkillDeclaredModes(Names[I], ProjectRoot, Declared) And (Declared.Count > 0) Then
          SetSkillModes(Names[I], Declared);
      End;
  Finally
    Declared.Free;
    Saved.Free;
  End;
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

Procedure TAssistantConfig.CollectSkillModeNames(Names: TStrings);
Var
  I: Integer;
Begin
  If Not Assigned(Names) Then
    Exit;
  Names.Clear;
  If Not Assigned(FSkillModes) Then
    Exit;
  For I := 0 To FSkillModes.Count - 1 Do
    If FSkillModes.Names[I] <> '' Then
      Names.Add(FSkillModes.Names[I]);
End;

Function TAssistantConfig.SkillFilePath(Const SkillName: String): String;
Var
  Node: TJSONData;
Begin
  Result := '';
  If (Not Assigned(FSkillFiles)) Or (Trim(SkillName) = '') Then
    Exit;
  Node := FSkillFiles.Find(Trim(SkillName));
  If Node = Nil Then
    Exit;
  Result := Trim(Node.AsString);
End;

Procedure TAssistantConfig.SetSkillFile(Const SkillName, FilePath: String);
Var
  Name, Path: String;
  Index: Integer;
Begin
  Name := Trim(SkillName);
  If (Name = '') Or (Not Assigned(FSkillFiles)) Then
    Exit;
  Index := FSkillFiles.IndexOfName(Name);
  Path := Trim(FilePath);
  If Index >= 0 Then
    FSkillFiles.Delete(Index);
  If Path = '' Then
    Exit;
  FSkillFiles.Add(Name, ExpandFileName(Path));
End;

Function TAssistantConfig.SkillIsHidden(Const SkillName: String): Boolean;
Begin
  Result := Assigned(FSkillHidden) And (Trim(SkillName) <> '') And (FSkillHidden.IndexOf(Trim(SkillName)) >= 0);
End;

Procedure TAssistantConfig.SetSkillHidden(Const SkillName: String; Hidden: Boolean);
Var
  Name: String;
  Index: Integer;
Begin
  Name := Trim(SkillName);
  If (Name = '') Or (Not Assigned(FSkillHidden)) Then
    Exit;
  Index := FSkillHidden.IndexOf(Name);
  If Hidden Then
    Begin
      If Index < 0 Then
        FSkillHidden.Add(Name);
    End
  Else If Index >= 0 Then
    FSkillHidden.Delete(Index);
End;

Function NameKept(Keep: TStrings; Const Name: String): Boolean;
Begin
  Result := Assigned(Keep) And (Keep.IndexOf(Name) >= 0);
End;

Procedure TAssistantConfig.RetainSkillModes(Keep: TStrings);
Var
  I: Integer;
Begin
  If Not Assigned(FSkillModes) Then
    Exit;
  For I := FSkillModes.Count - 1 DownTo 0 Do
    If Not NameKept(Keep, FSkillModes.Names[I]) Then
      FSkillModes.Delete(I);
End;

Procedure TAssistantConfig.RetainSkillFiles(Keep: TStrings);
Var
  I: Integer;
Begin
  If Not Assigned(FSkillFiles) Then
    Exit;
  For I := FSkillFiles.Count - 1 DownTo 0 Do
    If Not NameKept(Keep, FSkillFiles.Names[I]) Then
      FSkillFiles.Delete(I);
End;

Procedure TAssistantConfig.PruneHiddenSkills(Discovered: TStrings);
Var
  I: Integer;
Begin
  If Not Assigned(FSkillHidden) Then
    Exit;
  For I := FSkillHidden.Count - 1 DownTo 0 Do
    If Not NameKept(Discovered, FSkillHidden[I]) Then
      FSkillHidden.Delete(I);
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

Function ResolveConfiguredSkillFile(Const SkillName: String): String;
Begin
  Result := '';
  If Assigned(AssistantChatConfig) Then
    Result := AssistantChatConfig.SkillFilePath(SkillName);
End;

Function QuerySkillHidden(Const SkillName: String): Boolean;
Begin
  Result := Assigned(AssistantChatConfig) And AssistantChatConfig.SkillIsHidden(SkillName);
End;

Procedure EnumerateSkillFiles(Names, Paths: TStrings);
Var
  I: Integer;
  Name: String;
Begin
  If (Not Assigned(Names)) Or (Not Assigned(Paths)) Or (Not Assigned(AssistantChatConfig)) Then
    Exit;
  For I := 0 To AssistantChatConfig.FSkillFiles.Count - 1 Do
    Begin
      Name := AssistantChatConfig.FSkillFiles.Names[I];
      If Name = '' Then
        Continue;
      Names.Add(Name);
      Paths.Add(AssistantChatConfig.SkillFilePath(Name));
    End;
End;

Initialization

AssistantChatConfig := TAssistantConfig.Create;
SkillFileResolver := @ResolveConfiguredSkillFile;
SkillHiddenQuery := @QuerySkillHidden;
SkillFileEnumerator := @EnumerateSkillFiles;
AssistantChatConfig.Load;
If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
  GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);

Finalization

SkillFileResolver := Nil;
SkillHiddenQuery := Nil;
SkillFileEnumerator := Nil;
FreeAndNil(AssistantChatConfig);

End.
