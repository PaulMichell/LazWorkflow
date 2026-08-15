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
  GitConfigDefaultGraphFontSize = 9;
  GitConfigMinGraphFontSize = 6;
  GitConfigMaxGraphFontSize = 24;
  GitConfigMigrationVersion = 1;

Type
  TGitConfig = Class
  Private
    FAutoRefresh: Boolean;
    FAutoRefreshSeconds: Integer;
    FGraphFontName: String;
    FGraphFontSize: Integer;
    Procedure SetAutoRefreshSeconds(Value: Integer);
    Procedure SetGraphFontSize(Value: Integer);
    Procedure SetGraphFontName(Const Value: String);
  Public
    Constructor Create;
    Procedure Load;
    Procedure Save;
    Procedure Assign(Source: TGitConfig);
    Property AutoRefresh: Boolean Read FAutoRefresh Write FAutoRefresh;
    Property AutoRefreshSeconds: Integer Read FAutoRefreshSeconds Write SetAutoRefreshSeconds;
    { Empty GraphFontName means use the form font name at draw time. }
    Property GraphFontName: String Read FGraphFontName Write SetGraphFontName;
    Property GraphFontSize: Integer Read FGraphFontSize Write SetGraphFontSize;
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
  FGraphFontName := '';
  FGraphFontSize := GitConfigDefaultGraphFontSize;
End;

Procedure TGitConfig.SetAutoRefreshSeconds(Value: Integer);
Begin
  If Value < GitConfigMinIntervalSec Then
    Value := GitConfigMinIntervalSec;
  If Value > GitConfigMaxIntervalSec Then
    Value := GitConfigMaxIntervalSec;
  FAutoRefreshSeconds := Value;
End;

Procedure TGitConfig.SetGraphFontSize(Value: Integer);
Begin
  If Value < GitConfigMinGraphFontSize Then
    Value := GitConfigMinGraphFontSize;
  If Value > GitConfigMaxGraphFontSize Then
    Value := GitConfigMaxGraphFontSize;
  FGraphFontSize := Value;
End;

Procedure TGitConfig.SetGraphFontName(Const Value: String);
Begin
  FGraphFontName := Trim(Value);
End;

Procedure TGitConfig.Assign(Source: TGitConfig);
Begin
  If Not Assigned(Source) Then
    Exit;
  FAutoRefresh := Source.AutoRefresh;
  AutoRefreshSeconds := Source.AutoRefreshSeconds;
  GraphFontName := Source.GraphFontName;
  GraphFontSize := Source.GraphFontSize;
End;

Procedure TGitConfig.Load;
Var
  Cfg: TConfigStorage;
  LoadedInterval, Version: Integer;
  NeedSave: Boolean;
Begin
  NeedSave := False;
  Cfg := GetIDEConfigStorage(GitConfigFileName, True);
  Try
    FAutoRefresh := Cfg.GetValue('AutoRefresh/Enabled', GitConfigDefaultAutoRefresh);
    LoadedInterval := Cfg.GetValue('AutoRefresh/IntervalSec', GitConfigDefaultIntervalSec);
    AutoRefreshSeconds := LoadedInterval;
    GraphFontName := Cfg.GetValue('Graph/FontName', '');
    GraphFontSize := Cfg.GetValue('Graph/FontSize', GitConfigDefaultGraphFontSize);
    Version := Cfg.GetValue('Migration/Version', 0);
    { One-time move from LazGitManager.xml. Version 0 means this store has never
      finished migration, so default-looking values may still be a first open. }
    If Version < GitConfigMigrationVersion Then
      Begin
        If (FAutoRefresh = GitConfigDefaultAutoRefresh) And
          (LoadedInterval = GitConfigDefaultIntervalSec) And (FGraphFontName = '') And
          (FGraphFontSize = GitConfigDefaultGraphFontSize) Then
          Begin
            Cfg.Free;
            Cfg := Nil;
            Cfg := GetIDEConfigStorage(GitConfigLegacyFileName, True);
            FAutoRefresh := Cfg.GetValue('AutoRefresh/Enabled', GitConfigDefaultAutoRefresh);
            AutoRefreshSeconds := Cfg.GetValue('AutoRefresh/IntervalSec', GitConfigDefaultIntervalSec);
          End;
        NeedSave := True;
      End;
  Finally
    Cfg.Free;
  End;
  If NeedSave Then
    Save;
End;

Procedure TGitConfig.Save;
Var
  Cfg: TConfigStorage;
Begin
  Cfg := GetIDEConfigStorage(GitConfigFileName, False);
  Try
    Cfg.SetValue('AutoRefresh/Enabled', FAutoRefresh);
    Cfg.SetValue('AutoRefresh/IntervalSec', FAutoRefreshSeconds);
    Cfg.SetValue('Graph/FontName', FGraphFontName);
    Cfg.SetValue('Graph/FontSize', FGraphFontSize);
    Cfg.SetValue('Migration/Version', GitConfigMigrationVersion);
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
