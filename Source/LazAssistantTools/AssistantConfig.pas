Unit AssistantConfig;

{ Persistent LazAssistantTools settings (OAuth tokens, model) (c) 2026 Michell Computing. }

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

Type
  TAssistantConfig = Class
  Private
    FApiBase: String;
    FModel: String;
    FActiveSkill: String;
    FIncludeIDEContext: Boolean;
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
    Property ApiBase: String Read FApiBase Write FApiBase;
    Property Model: String Read FModel Write FModel;
    { Directory name under ~/.grok/skills, or empty for no skill. }
    Property ActiveSkill: String Read FActiveSkill Write FActiveSkill;
    { Attach active editor + project file list to each outgoing user message. }
    Property IncludeIDEContext: Boolean Read FIncludeIDEContext Write FIncludeIDEContext;
    Property AccessToken: String Read FAccessToken Write FAccessToken;
    Property RefreshToken: String Read FRefreshToken Write FRefreshToken;
    Property TokenType: String Read FTokenType Write FTokenType;
    Property Scope: String Read FScope Write FScope;
    Property ExpiresAt: TDateTime Read FExpiresAt Write FExpiresAt;
  End;

Var
  AssistantChatConfig: TAssistantConfig;

Implementation

Uses
  BaseIDEIntf, LazConfigStorage;

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
  { yyyy-mm-ddThh:nn:ss }
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

Procedure TAssistantConfig.Assign(Source: TAssistantConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FApiBase := Source.ApiBase;
  FModel := Source.Model;
  FActiveSkill := Source.ActiveSkill;
  FIncludeIDEContext := Source.IncludeIDEContext;
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
End;

Procedure TAssistantConfig.Load;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(AssistantConfigFileName, True);
  Try
    ApplyConfigStorage(Cfg, Self);
    { Migrate settings from the previous package name when the new store is empty. }
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
    { Clear legacy API key slot so settings cannot silently re-use console keys. }
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
