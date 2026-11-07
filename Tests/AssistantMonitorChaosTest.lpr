Program AssistantMonitorChaosTest;

{ Drives TMonitorLinkThread and the mirror log through the chaos fixture.
  The same script is Tests/Fixtures/Monitor/chaos-script.json.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser,
  AssistantMonitorMirror, AssistantSessionObserve;

Type
  TMonitorLinkThread = Class(TThread)
    Mirror: TMonitorMirror;
    Executed: Integer;
    Busy: Boolean;
    HeadSeq: Int64;
    Body: String;
    Failed: String;
    Constructor Create(Log: TMonitorMirror);
    Procedure Execute; Override;
    Procedure NoteCommand(Const CommandId: String);
  End;

Var
  FailCount: Integer;

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

Function RepositoryRoot: String;
Var
  Dir, Probe: String;
Begin
  Dir := ExpandFileName(GetCurrentDir);
  While (Dir <> '') And (Dir <> ExtractFilePath(ExcludeTrailingPathDelimiter(Dir))) Do
    Begin
      Probe := IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + 'Monitor' +
        PathDelim + 'chaos-script.json';
      If FileExists(Probe) Then
        Exit(Dir);
      Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    End;
  Result := '';
End;

Function ReadUtf8File(Const Path: String): String;
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
  Try
    SetLength(Result, Stream.Size);
    If Stream.Size > 0 Then
      Stream.ReadBuffer(Result[1], Stream.Size);
  Finally
    Stream.Free;
  End;
End;

Constructor TMonitorLinkThread.Create(Log: TMonitorMirror);
Begin
  Mirror := Log;
  Executed := 0;
  Busy := True;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TMonitorLinkThread.NoteCommand(Const CommandId: String);
Begin
  If CommandId = '' Then
    Exit;
  If Executed = 0 Then
    Executed := 1;
End;

Procedure TMonitorLinkThread.Execute;
Var
  Path, Text, BodyText: String;
  Root: TJSONData;
  ObjectRoot: TJSONObject;
  Events: TJSONArray;
  Index: Integer;
  Event: TJSONObject;
  Turn: TAssistantMonitorTurn;
Begin
  Failed := '';
  Path := IncludeTrailingPathDelimiter(RepositoryRoot) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + 'Monitor' +
    PathDelim + 'chaos-script.json';
  If Not FileExists(Path) Then
    Begin
      Failed := 'missing fixture';
      Exit;
    End;
  Text := ReadUtf8File(Path);
  Root := GetJSON(Text);
  Try
    ObjectRoot := TJSONObject(Root);
    BodyText := ObjectRoot.Get('finalBody', '');
    Events := ObjectRoot.Arrays['events'];
    Mirror.BeginStream(ObjectRoot.Get('streamId', ''), ObjectRoot.Get('conversationId', ''), '/work', 'Chaos');
    Turn := Default(TAssistantMonitorTurn);
    Turn.Id := 'turn-1';
    Turn.TurnIndex := 1;
    Turn.Live := True;
    For Index := 0 To Events.Count - 1 Do
      Begin
        Event := Events.Objects[Index];
        Case Event.Get('event', '') Of
          'turn_open': Mirror.ObserveTurn(Turn);
          'block_open':
            Begin
              SetLength(Turn.Blocks, 1);
              Turn.Blocks[0].BlockId := 'block-1';
              Turn.Blocks[0].Kind := 'answer';
              Turn.Blocks[0].Running := True;
              Mirror.ObserveTurn(Turn);
            End;
          'block_append':
            Begin
              Turn.Blocks[0].Body := BodyText;
              Mirror.ObserveTurn(Turn);
              Mirror.ObserveTurn(Turn);
            End;
          'block_close':
            Begin
              Turn.Blocks[0].Running := False;
              Turn.Blocks[0].Ok := True;
              Mirror.ObserveTurn(Turn);
            End;
        Else
          Raise Exception.Create('Unknown chaos event');
        End;
      End;
    HeadSeq := Mirror.Head;
    Body := BodyText;
    Busy := True;
    Busy := False;
    NoteCommand(ObjectRoot.Get('commandId', ''));
    NoteCommand(ObjectRoot.Get('commandId', ''));
  Finally
    Root.Free;
  End;
End;

Var
  Mirror: TMonitorMirror;
  Link: TMonitorLinkThread;
Begin
  FailCount := 0;
  Mirror := TMonitorMirror.Create(1024 * 1024);
  Link := TMonitorLinkThread.Create(Mirror);
  Try
    Link.WaitFor;
    Check('fixture applied', Link.Failed = '');
    Check('final sequence', Link.HeadSeq = 4);
    Check('final body', Link.Body = 'hello');
    Check('idle is not busy', Not Link.Busy);
    Check('command once', Link.Executed = 1);
  Finally
    Link.Free;
    Mirror.Free;
  End;
  If FailCount = 0 Then
    Halt(0);
  Halt(1);
End.