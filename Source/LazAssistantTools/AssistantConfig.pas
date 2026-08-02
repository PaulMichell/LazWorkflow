Unit AssistantConfig;

{ Persistent LazAssistantTools settings (OAuth tokens, model, thinking, approval) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, GrokOAuth;

Const
  AssistantConfigFileName = 'LazAssistantTools.xml';
  AssistantConfigLegacyFileName = 'LazGrokChat.xml';
  AssistantConfigDefaultApiBase = 'https://api.x.ai/v1';
  AssistantConfigDefaultModel = 'grok-4.5';
  AssistantConfigDefaultThinking = 'high';
  AssistantConfigDefaultApproval = 'always';

Type
  { Reasoning effort sent as reasoning_effort (xAI / Grok Build "thinking level"). }
  TAssistantThinkingLevel = (atlLow, atlMedium, atlHigh);

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
    FAccessToken: String;
    FRefreshToken: String;
    FTokenType: String;
    FScope: String;
    FExpiresAt: TDateTime;
  Public
    Constructor Create;
    Procedure Load;
    Procedure Save;
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
    { low | medium | high — API reasoning_effort. }
    Property ThinkingLevel: String Read FThinkingLevel Write FThinkingLevel;
    { ask | auto | always — tool approval policy. }
    Property ApprovalMode: String Read FApprovalMode Write FApprovalMode;
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
  BaseIDEIntf, LazConfigStorage;

Function ThinkingLevelToStr(Level: TAssistantThinkingLevel): String;
Begin
  Case Level Of
    atlLow: Result := 'low';
    atlMedium: Result := 'medium';
  Else
    Result := 'high';
  End;
End;

Function StrToThinkingLevel(Const Value: String): TAssistantThinkingLevel;
Var
  V: String;
Begin
  V := LowerCase(Trim(Value));
  If (V = 'low') Or (V = 'minimal') Or (V = 'none') Then
    Result := atlLow
  Else If (V = 'medium') Or (V = 'med') Then
    Result := atlMedium
  Else
    Result := atlHigh;
End;

Function ThinkingLevelCaption(Level: TAssistantThinkingLevel): String;
Begin
  Case Level Of
    atlLow: Result := 'Low';
    atlMedium: Result := 'Medium';
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
  Else
    Result := aamAlways;
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
  FIncludeIDEContext := True;
  FThinkingLevel := AssistantConfigDefaultThinking;
  FApprovalMode := AssistantConfigDefaultApproval;
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

Procedure ApplyConfigStorage(Cfg: TConfigStorage; Config: TAssistantConfig);
Var
  LegacyKey: String;
Begin
  If (Not Assigned(Cfg)) Or (Not Assigned(Config)) Then
    Exit;
  Config.FApiBase := Cfg.GetValue('API/Base', AssistantConfigDefaultApiBase);
  Config.FModel := Cfg.GetValue('API/Model', AssistantConfigDefaultModel);
  Config.FActiveSkill := Cfg.GetValue('Chat/ActiveSkill', '');
  Config.FIncludeIDEContext := Cfg.GetValue('Chat/IncludeIDEContext', True);
  Config.FThinkingLevel := Cfg.GetValue('Chat/ThinkingLevel', AssistantConfigDefaultThinking);
  Config.FApprovalMode := Cfg.GetValue('Chat/ApprovalMode', AssistantConfigDefaultApproval);
  Config.FAccessToken := Cfg.GetValue('OAuth/AccessToken', '');
  Config.FRefreshToken := Cfg.GetValue('OAuth/RefreshToken', '');
  Config.FTokenType := Cfg.GetValue('OAuth/TokenType', 'Bearer');
  Config.FScope := Cfg.GetValue('OAuth/Scope', '');
  Config.FExpiresAt := ConfigToDateTime(Cfg.GetValue('OAuth/ExpiresAt', ''));
  If (Config.FAccessToken = '') And (Config.FRefreshToken = '') Then
    Begin
      LegacyKey := Cfg.GetValue('API/Key', '');
      If LegacyKey <> '' Then
        Config.FAccessToken := '';
    End;
  If Trim(Config.FApiBase) = '' Then
    Config.FApiBase := AssistantConfigDefaultApiBase;
  If Trim(Config.FModel) = '' Then
    Config.FModel := AssistantConfigDefaultModel
  Else If SameText(Config.FModel, 'grok-4') Or SameText(Config.FModel, 'grok-4-latest') Then
    Config.FModel := AssistantConfigDefaultModel;
  If Trim(Config.FTokenType) = '' Then
    Config.FTokenType := 'Bearer';
  Config.FThinkingLevel := ThinkingLevelToStr(StrToThinkingLevel(Config.FThinkingLevel));
  Config.FApprovalMode := ApprovalModeToStr(StrToApprovalMode(Config.FApprovalMode));
End;

Procedure TAssistantConfig.Load;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(AssistantConfigFileName, True);
  Try
    ApplyConfigStorage(Cfg, Self);
    If (FAccessToken = '') And (FRefreshToken = '') Then
      Begin
        Cfg.Free;
        Cfg := Nil;
        Cfg := GetIDEConfigStorage(AssistantConfigLegacyFileName, True);
        ApplyConfigStorage(Cfg, Self);
      End;
  Finally
    Cfg.Free;
  End;
End;

Procedure TAssistantConfig.Save;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(AssistantConfigFileName, False);
  Try
    Cfg.SetValue('API/Base', FApiBase);
    Cfg.SetValue('API/Model', FModel);
    Cfg.SetValue('Chat/ActiveSkill', FActiveSkill);
    Cfg.SetValue('Chat/IncludeIDEContext', FIncludeIDEContext);
    Cfg.SetValue('Chat/ThinkingLevel', ThinkingLevelToStr(GetThinkingLevel));
    Cfg.SetValue('Chat/ApprovalMode', ApprovalModeToStr(GetApprovalMode));
    Cfg.SetValue('API/Key', '');
    Cfg.SetValue('OAuth/AccessToken', FAccessToken);
    Cfg.SetValue('OAuth/RefreshToken', FRefreshToken);
    Cfg.SetValue('OAuth/TokenType', FTokenType);
    Cfg.SetValue('OAuth/Scope', FScope);
    Cfg.SetValue('OAuth/ExpiresAt', DateTimeToConfig(FExpiresAt));
    Cfg.WriteToDisk;
  Finally
    Cfg.Free;
  End;
End;

Initialization

AssistantChatConfig := TAssistantConfig.Create;
AssistantChatConfig.Load;
If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
  GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);

Finalization

FreeAndNil(AssistantChatConfig);

End.
