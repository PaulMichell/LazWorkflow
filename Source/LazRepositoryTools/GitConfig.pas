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
  fpjson, WorkflowSettings;

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
  Section: TJSONObject;
Begin
  FAutoRefresh := GitConfigDefaultAutoRefresh;
  AutoRefreshSeconds := GitConfigDefaultIntervalSec;
  GraphFontName := '';
  GraphFontSize := GitConfigDefaultGraphFontSize;
  Section := ReadWorkflowSection('repository');
  If Not Assigned(Section) Then
    Exit;
  Try
    FAutoRefresh := Section.Get('auto_refresh', GitConfigDefaultAutoRefresh);
    AutoRefreshSeconds := Section.Get('interval_sec', GitConfigDefaultIntervalSec);
    GraphFontName := Section.Get('graph_font_name', '');
    GraphFontSize := Section.Get('graph_font_size', GitConfigDefaultGraphFontSize);
  Finally
    Section.Free;
  End;
End;

Procedure TGitConfig.Save;
Var
  Section: TJSONObject;
  ErrorText: String;
Begin
  Section := TJSONObject.Create;
  Try
    Section.Add('auto_refresh', FAutoRefresh);
    Section.Add('interval_sec', FAutoRefreshSeconds);
    Section.Add('graph_font_name', FGraphFontName);
    Section.Add('graph_font_size', FGraphFontSize);
    WriteWorkflowSection('repository', Section, ErrorText);
  Finally
    Section.Free;
  End;
End;

Initialization

{ Create only. RegisterGitManager loads the repository section after the settings directory is known. }
GitManagerConfig := TGitConfig.Create;

Finalization

FreeAndNil(GitManagerConfig);

End.
