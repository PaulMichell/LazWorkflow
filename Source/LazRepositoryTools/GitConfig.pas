Unit GitConfig;

{ Persistent LazRepositoryTools settings (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  GitConfigFileName = 'LazRepositoryTools.xml';
  GitConfigLegacyFileName = 'LazGitManager.xml';
  GitConfigDefaultAutoRefresh = True;
  GitConfigDefaultIntervalSec = 5;
  GitConfigMinIntervalSec = 2;
  GitConfigMaxIntervalSec = 3600;

Type
  TGitConfig = Class
  Private
    FAutoRefresh: Boolean;
    FAutoRefreshSeconds: Integer;
    Procedure SetAutoRefreshSeconds(Value: Integer);
  Public
    Constructor Create;
    Procedure Load;
    Procedure Save;
    Procedure Assign(Source: TGitConfig);
    Property AutoRefresh: Boolean Read FAutoRefresh Write FAutoRefresh;
    Property AutoRefreshSeconds: Integer Read FAutoRefreshSeconds Write SetAutoRefreshSeconds;
  End;

Var
  GitManagerConfig: TGitConfig;

Implementation

Uses
  BaseIDEIntf, LazConfigStorage;

Constructor TGitConfig.Create;
Begin
  Inherited Create;
  FAutoRefresh := GitConfigDefaultAutoRefresh;
  FAutoRefreshSeconds := GitConfigDefaultIntervalSec;
End;

Procedure TGitConfig.SetAutoRefreshSeconds(Value: Integer);
Begin
  If Value < GitConfigMinIntervalSec Then
    Value := GitConfigMinIntervalSec;
  If Value > GitConfigMaxIntervalSec Then
    Value := GitConfigMaxIntervalSec;
  FAutoRefreshSeconds := Value;
End;

Procedure TGitConfig.Assign(Source: TGitConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FAutoRefresh := Source.AutoRefresh;
  AutoRefreshSeconds := Source.AutoRefreshSeconds;
End;

Procedure TGitConfig.Load;
Var
  Cfg: TConfigStorage;
  LoadedInterval: Integer;
Begin
  Cfg := GetIDEConfigStorage(GitConfigFileName, True);
  Try
    FAutoRefresh := Cfg.GetValue('AutoRefresh/Enabled', GitConfigDefaultAutoRefresh);
    LoadedInterval := Cfg.GetValue('AutoRefresh/IntervalSec', GitConfigDefaultIntervalSec);
    AutoRefreshSeconds := LoadedInterval;
    { Migrate from LazGitManager.xml when the new store still looks empty/default. }
    If (FAutoRefresh = GitConfigDefaultAutoRefresh) And
      (LoadedInterval = GitConfigDefaultIntervalSec) Then
      Begin
        Cfg.Free;
        Cfg := Nil;
        Cfg := GetIDEConfigStorage(GitConfigLegacyFileName, True);
        FAutoRefresh := Cfg.GetValue('AutoRefresh/Enabled', GitConfigDefaultAutoRefresh);
        AutoRefreshSeconds := Cfg.GetValue('AutoRefresh/IntervalSec', GitConfigDefaultIntervalSec);
      End;
  Finally
    Cfg.Free;
  End;
End;

Procedure TGitConfig.Save;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(GitConfigFileName, False);
  Try
    Cfg.SetValue('AutoRefresh/Enabled', FAutoRefresh);
    Cfg.SetValue('AutoRefresh/IntervalSec', FAutoRefreshSeconds);
    Cfg.WriteToDisk;
  Finally
    Cfg.Free;
  End;
End;

Initialization

{ Create only — Load is deferred to RegisterGitManager so GetIDEConfigStorage
  is not called during unit initialization while the IDE is still starting. }
GitManagerConfig := TGitConfig.Create;

Finalization

FreeAndNil(GitManagerConfig);

End.
