Unit GrokConfig;

{ Persistent LazGrokChat settings (OAuth tokens, model) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, GrokOAuth;

Const
  GrokConfigFileName = 'LazGrokChat.xml';
  GrokConfigDefaultApiBase = 'https://api.x.ai/v1';
  GrokConfigDefaultModel = 'grok-4.5';

Type
  TGrokConfig = Class
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
    Procedure Assign(Source: TGrokConfig);
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
  GrokChatConfig: TGrokConfig;

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

Constructor TGrokConfig.Create;
Begin
  Inherited Create;
  FApiBase := GrokConfigDefaultApiBase;
  FModel := GrokConfigDefaultModel;
  FActiveSkill := '';
  FIncludeIDEContext := True;
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Function TGrokConfig.IsSignedIn: Boolean;
Begin
  Result := (Trim(FAccessToken) <> '') Or (Trim(FRefreshToken) <> '');
End;

Procedure TGrokConfig.Assign(Source: TGrokConfig);
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

Procedure TGrokConfig.ApplyOAuthTokens(Const Tokens: TGrokOAuthTokens);
Begin
  FAccessToken := Tokens.AccessToken;
  FRefreshToken := Tokens.RefreshToken;
  FTokenType := Tokens.TokenType;
  If FTokenType = '' Then
    FTokenType := 'Bearer';
  FScope := Tokens.Scope;
  FExpiresAt := Tokens.ExpiresAt;
End;

Procedure TGrokConfig.ClearOAuthTokens;
Begin
  FAccessToken := '';
  FRefreshToken := '';
  FTokenType := 'Bearer';
  FScope := '';
  FExpiresAt := 0;
End;

Function TGrokConfig.ToOAuthTokens: TGrokOAuthTokens;
Begin
  Result.AccessToken := FAccessToken;
  Result.RefreshToken := FRefreshToken;
  Result.TokenType := FTokenType;
  Result.Scope := FScope;
  Result.ExpiresAt := FExpiresAt;
End;

Procedure TGrokConfig.Load;
Var
  Cfg: TConfigStorage;
  LegacyKey: String;
Begin
  Cfg := GetIDEConfigStorage(GrokConfigFileName, True);
  Try
    FApiBase := Cfg.GetValue('API/Base', GrokConfigDefaultApiBase);
    FModel := Cfg.GetValue('API/Model', GrokConfigDefaultModel);
    FActiveSkill := Cfg.GetValue('Chat/ActiveSkill', '');
    FIncludeIDEContext := Cfg.GetValue('Chat/IncludeIDEContext', True);
    FAccessToken := Cfg.GetValue('OAuth/AccessToken', '');
    FRefreshToken := Cfg.GetValue('OAuth/RefreshToken', '');
    FTokenType := Cfg.GetValue('OAuth/TokenType', 'Bearer');
    FScope := Cfg.GetValue('OAuth/Scope', '');
    FExpiresAt := ConfigToDateTime(Cfg.GetValue('OAuth/ExpiresAt', ''));
    { One-time migration: older builds stored a console API key. Prefer OAuth. }
    If (FAccessToken = '') And (FRefreshToken = '') Then
      Begin
        LegacyKey := Cfg.GetValue('API/Key', '');
        If LegacyKey <> '' Then
          Begin
            { Leave legacy key unused for chat; OAuth is the supported path. }
            FAccessToken := '';
          End;
      End;
    If Trim(FApiBase) = '' Then
      FApiBase := GrokConfigDefaultApiBase;
    If Trim(FModel) = '' Then
      FModel := GrokConfigDefaultModel
    Else If SameText(FModel, 'grok-4') Or SameText(FModel, 'grok-4-latest') Then
      { Upgrade legacy default to current flagship. }
      FModel := GrokConfigDefaultModel;
    If Trim(FTokenType) = '' Then
      FTokenType := 'Bearer';
  Finally
    Cfg.Free;
  End;
End;

Procedure TGrokConfig.Save;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(GrokConfigFileName, False);
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

GrokChatConfig := TGrokConfig.Create;
GrokChatConfig.Load;
If Assigned(GrokOAuthClient) And GrokChatConfig.IsSignedIn Then
  GrokOAuthClient.SetTokens(GrokChatConfig.ToOAuthTokens);

Finalization

FreeAndNil(GrokChatConfig);

End.
