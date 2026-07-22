Unit GrokConfig;

{ Persistent LazGrokChat settings (API base, key, model) (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  GrokConfigFileName = 'LazGrokChat.xml';
  GrokConfigDefaultApiBase = 'https://api.x.ai/v1';
  GrokConfigDefaultModel = 'grok-4';

Type
  TGrokConfig = Class
  Private
    FApiBase: String;
    FApiKey: String;
    FModel: String;
  Public
    Constructor Create;
    Procedure Load;
    Procedure Save;
    Procedure Assign(Source: TGrokConfig);
    Function HasApiKey: Boolean;
    Property ApiBase: String Read FApiBase Write FApiBase;
    Property ApiKey: String Read FApiKey Write FApiKey;
    Property Model: String Read FModel Write FModel;
  End;

Var
  GrokChatConfig: TGrokConfig;

Implementation

Uses
  BaseIDEIntf, LazConfigStorage;

Constructor TGrokConfig.Create;
Begin
  Inherited Create;
  FApiBase := GrokConfigDefaultApiBase;
  FApiKey := '';
  FModel := GrokConfigDefaultModel;
End;

Function TGrokConfig.HasApiKey: Boolean;
Begin
  Result := Trim(FApiKey) <> '';
End;

Procedure TGrokConfig.Assign(Source: TGrokConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FApiBase := Source.ApiBase;
  FApiKey := Source.ApiKey;
  FModel := Source.Model;
End;

Procedure TGrokConfig.Load;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(GrokConfigFileName, True);
  Try
    FApiBase := Cfg.GetValue('API/Base', GrokConfigDefaultApiBase);
    FApiKey := Cfg.GetValue('API/Key', '');
    FModel := Cfg.GetValue('API/Model', GrokConfigDefaultModel);
    If Trim(FApiBase) = '' Then
      FApiBase := GrokConfigDefaultApiBase;
    If Trim(FModel) = '' Then
      FModel := GrokConfigDefaultModel;
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
    Cfg.SetValue('API/Key', FApiKey);
    Cfg.SetValue('API/Model', FModel);
    Cfg.WriteToDisk;
  Finally
    Cfg.Free;
  End;
End;

Initialization

GrokChatConfig := TGrokConfig.Create;
GrokChatConfig.Load;

Finalization

FreeAndNil(GrokChatConfig);

End.
