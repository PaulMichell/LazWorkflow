Program AssistantMonitorCommandIdTest;

{ A phone command id stays with the turn it started, and an older line has none.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, LazFileUtils, AssistantConversation;

Var
  FailCount: Integer;
  TempSerial: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Function MakeTempRoot: String;
Begin
  Inc(TempSerial);
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-command-id-' +
    FormatDateTime('hhnnsszzz', Now) + '-' + IntToStr(TempSerial);
  ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(Result));
End;

Function AppendSample(Store: TAssistantConversationStore; Const Prompt, CommandId: String): Boolean;
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
Begin
  Turn := Default(TConversationTurn);
  Turn.Id := 'turn-' + CommandId;
  If Turn.Id = 'turn-' Then
    Turn.Id := 'turn-plain';
  Turn.Mode := 'build';
  Turn.Prompt := Prompt;
  Turn.Response := 'answer';
  Turn.CreatedAt := '2026-01-01T00:00:00Z';
  Turn.ClientCommandId := CommandId;
  Result := Store.AppendTurn(Turn, Entry);
End;

Procedure TestCommandIdSurvivesReload;
Var
  Root: String;
  Store, Reloaded: TAssistantConversationStore;
  Found: TConversationTurn;
  Lines: TStringList;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('command turn appended', AppendSample(Store, 'from the phone', 'cmd-42'));
    Check('plain turn appended', AppendSample(Store, 'from the desktop', ''));
    Check('open store finds the command', Store.TurnForClientCommand('cmd-42', Found) And (Found.Prompt = 'from the phone'));
    Check('empty id matches nothing', Not Store.TurnForClientCommand('', Found));
    Check('unknown id matches nothing', Not Store.TurnForClientCommand('missing', Found));
  Finally
    Store.Free;
  End;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(IncludeTrailingPathDelimiter(Root) + '.assistant' + PathDelim + 'conversation.jsonl');
    Check('two lines stored', Lines.Count = 2);
    Check('command id is stored', Pos('"client_command_id":"cmd-42"', Lines[0]) > 0);
    Check('empty id is omitted', Pos('client_command_id', Lines[1]) = 0);
  Finally
    Lines.Free;
  End;
  Reloaded := TAssistantConversationStore.Create;
  Try
    Reloaded.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Check('reload loads the file', Reloaded.Load);
    Check('reloaded store finds the command', Reloaded.TurnForClientCommand('cmd-42', Found) And
      (Found.Id = 'turn-cmd-42') And (Found.ClientCommandId = 'cmd-42') And (Found.Prompt = 'from the phone'));
    Check('older line has an empty id', Reloaded.GetTurn(1, Found) And (Found.ClientCommandId = '') And
      (Found.Prompt = 'from the desktop'));
  Finally
    Reloaded.Free;
  End;
End;

Begin
  FailCount := 0;
  TempSerial := 0;
  TestCommandIdSurvivesReload;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorCommandIdTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
