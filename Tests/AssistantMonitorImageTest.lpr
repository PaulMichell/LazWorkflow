Program AssistantMonitorImageTest;

{ Image bytes are the display file, and a slow read does not hold the pulse or a command.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, SyncObjs, fpjson, jsonparser, AssistantSessionObserve, AssistantMonitorSnapshot,
  AssistantMonitorPulse, AssistantMonitorStore, AssistantMonitorImages;

Var
  FailCount: Integer;
  TempSerial: Integer;
  CommandTick: QWord;

Type
  TFakeSource = Class(TMonitorSnapshotSource)
    Text: String;
    Function Fill(Snap: TMonitorSnapshot): Boolean; Override;
  End;

  TPulseThread = Class(TThread)
    AfterRev: Int64;
    Status: Integer;
    Body: String;
    FinishedTick: QWord;
    Procedure Execute; Override;
  End;

  TImageThread = Class(TThread)
    ImageId: String;
    Status: Integer;
    Data: TBytes;
    Procedure Execute; Override;
  End;

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

Function TFakeSource.Fill(Snap: TMonitorSnapshot): Boolean;
Begin
  Snap.Available := True;
  Snap.StatusText := Text;
  Result := True;
End;

Procedure TPulseThread.Execute;
Begin
  ServeMonitorPulse('image', 'epoch-a', AfterRev, 150, Status, Body);
  FinishedTick := GetTickCount64;
End;

Procedure TImageThread.Execute;
Var
  Mime, ErrorBody: String;
Begin
  ReadMonitorDisplayImage(ImageId, Status, Mime, Data, ErrorBody);
End;

Procedure PostedCommand;
Begin
  CommandTick := GetTickCount64;
End;

Function MakeRoot: String;
Begin
  Inc(TempSerial);
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-image-' +
    FormatDateTime('hhnnsszzz', Now) + '-' + IntToStr(TempSerial);
  ForceDirectories(Result + PathDelim + '.assistant' + PathDelim + 'images');
  SetMonitorStoreRoot(ExcludeTrailingPathDelimiter(Result));
End;

Procedure WriteBytes(Const Path: String; Const Data: TBytes);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Length(Data) > 0 Then
      Stream.WriteBuffer(Data[0], Length(Data));
  Finally
    Stream.Free;
  End;
End;

Function Publish(Source: TFakeSource; Const Text: String; Previous: Int64): Int64;
Var
  Start: QWord;
Begin
  Source.Text := Text;
  TouchAssistantMirror;
  Start := GetTickCount64;
  Result := Previous;
  While (Result = Previous) And (GetTickCount64 - Start < 2000) Do
    Begin
      CheckSynchronize(10);
      Result := MonitorSnapshotRev;
    End;
End;

Procedure TestBytesAndMissing;
Var
  Root, ErrorBody, Mime: String;
  Status: Integer;
  Data, ReadBack: TBytes;
  Index: Integer;
Begin
  Root := MakeRoot;
  SetLength(Data, 8);
  For Index := 0 To 7 Do
    Data[Index] := Index + 1;
  WriteBytes(Root + PathDelim + '.assistant' + PathDelim + 'images' + PathDelim + '11111111-1111-1111-1111-111111111111.png', Data);
  Check('display file is served', ReadMonitorDisplayImage('11111111-1111-1111-1111-111111111111', Status, Mime, ReadBack,
    ErrorBody) And (Status = 200));
  Check('response bytes equal the display file', (Length(ReadBack) = Length(Data)) And CompareMem(@ReadBack[0], @Data[0],
    Length(Data)));
  Check('mime comes from the display file', Mime = 'image/png');
  Check('missing image is 404', (Not ReadMonitorDisplayImage('22222222-2222-2222-2222-222222222222', Status, Mime, ReadBack,
    ErrorBody)) And (Status = 404) And (Pos('not_found', ErrorBody) > 0));
  SetLength(Data, MonitorImageMaxBytes + 1);
  FillChar(Data[0], Length(Data), 9);
  WriteBytes(Root + PathDelim + '.assistant' + PathDelim + 'images' + PathDelim + '33333333-3333-3333-3333-333333333333.png', Data);
  Check('oversized image is 413', (Not ReadMonitorDisplayImage('33333333-3333-3333-3333-333333333333', Status, Mime, ReadBack,
    ErrorBody)) And (Status = 413) And (Pos('too_large', ErrorBody) > 0));
End;

Procedure TestDoesNotBlockPulseOrCommand;
Var
  Source: TFakeSource;
  Pulse: TPulseThread;
  Image: TImageThread;
  Entered, ReleaseGate: PRTLEvent;
  Rev: Int64;
  Root, NoticedTick: QWord;
  Data: TBytes;
Begin
  Root := 0;
  Source := TFakeSource.Create;
  Source.Text := 'ready';
  SetMonitorStoreRoot(ExcludeTrailingPathDelimiter(MakeRoot));
  SetLength(Data, 4);
  Data[0] := 1;
  Data[1] := 2;
  Data[2] := 3;
  Data[3] := 4;
  WriteBytes(MonitorAssistantDirectory + 'images' + PathDelim + '44444444-4444-4444-4444-444444444444.png', Data);
  StartMonitorSnapshot(Source);
  SetMonitorPulseEpoch('epoch-a');
  Rev := Publish(Source, 'ready', 0);
  Pulse := TPulseThread.Create(True);
  Pulse.FreeOnTerminate := False;
  Pulse.AfterRev := Rev;
  Pulse.Start;
  While (MonitorPulseWaiting('image') < 1) And (Root < 200) Do
    Begin
      CheckSynchronize(10);
      Inc(Root);
    End;
  Check('pulse is waiting', MonitorPulseWaiting('image') = 1);
  Entered := RTLEventCreate;
  ReleaseGate := RTLEventCreate;
  SetMonitorImageReadGate(Entered, ReleaseGate);
  Image := TImageThread.Create(True);
  Image.FreeOnTerminate := False;
  Image.ImageId := '44444444-4444-4444-4444-444444444444';
  Image.Start;
  RTLEventWaitFor(Entered, 2000);
  Rev := Publish(Source, 'changed', Rev);
  NoticedTick := GetTickCount64;
  While (Pulse.FinishedTick = 0) And (GetTickCount64 - NoticedTick < 50) Do
    CheckSynchronize(1);
  Check('pulse answered without waiting for the image', (Pulse.FinishedTick <> 0) And (Pulse.FinishedTick <= NoticedTick + 50));
  CommandTick := 0;
  TThread.Queue(Nil, @PostedCommand);
  Root := GetTickCount64;
  While (CommandTick = 0) And (GetTickCount64 - Root < 50) Do
    CheckSynchronize(1);
  Check('command posted without waiting for the image', CommandTick <> 0);
  RTLEventSetEvent(ReleaseGate);
  Image.WaitFor;
  Check('slow image still returns the display bytes', (Image.Status = 200) And (Length(Image.Data) = 4));
  Pulse.WaitFor;
  Pulse.Free;
  Image.Free;
  SetMonitorImageReadGate(Nil, Nil);
  RTLEventDestroy(Entered);
  RTLEventDestroy(ReleaseGate);
  StopMonitorSnapshot;
  ResetMonitorPulseClients;
End;

Begin
  FailCount := 0;
  TempSerial := 0;
  TestBytesAndMissing;
  TestDoesNotBlockPulseOrCommand;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorImageTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
