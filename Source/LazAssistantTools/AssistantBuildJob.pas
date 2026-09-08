Unit AssistantBuildJob;

{ Asynchronous saved-input build pilot. A detached worker owns the process;
  an interface snapshot keeps its state alive without IDE callbacks or joins.
  Diagnostics describe observed inputs, not proof of an immutable full build. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils;
Type
  TBuildInput = Record Path, Text: String; End;
  TBuildInputs = Array Of TBuildInput;
  TBuildJobSnapshot = Record
    Done, Cancelled, InputsUnchanged: Boolean;
    ExitCode: Integer;
    OutputText, ErrorText, Manifest: String;
  End;
  IAssistantBuildJob = Interface
    ['{60D8C4B7-37B3-4B1C-89A5-F62B824BF6C8}']
    Procedure Cancel;
    Function Snapshot: TBuildJobSnapshot;
  End;
Function StartAssistantBuild(Const Executable, ProjectFile, BuildMode: String;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal = 600000): IAssistantBuildJob;
Implementation
Uses Process, Pipes, sha1, AssistantProtocol {$IFDEF LINUX}, BaseUnix{$ENDIF};
Type
  TBuildState = Class(TInterfacedObject, IAssistantBuildJob)
  Public
    Lock: TRTLCriticalSection;
    Cancelled: LongInt;
    Value: TBuildJobSnapshot;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Snapshot: TBuildJobSnapshot;
  End;
  TBuildWorker = Class(TThread)
  Private
    FState: TBuildState;
    FKeepAlive: IAssistantBuildJob;
    FExecutable, FProject, FMode: String;
    FInputs: TBuildInputs;
    FTimeout: Cardinal;
    Procedure ChildFork(Sender: TObject);
    Function InputsMatch: Boolean;
  Protected
    Procedure Execute; Override;
  End;
Constructor TBuildState.Create;
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  Value.ExitCode := -1;
End;
Destructor TBuildState.Destroy;
Begin DoneCriticalSection(Lock); Inherited Destroy; End;
Procedure TBuildState.Cancel;
Begin InterlockedExchange(Cancelled, 1); End;
Function TBuildState.Snapshot: TBuildJobSnapshot;
Begin
  EnterCriticalSection(Lock);
  Try Result := Value; Finally LeaveCriticalSection(Lock); End;
End;
Procedure TBuildWorker.ChildFork(Sender: TObject);
Begin {$IFDEF LINUX}If fpSetsid < 0 Then fpExit(126);{$ENDIF} End;
Function TBuildWorker.InputsMatch: Boolean;
Var I: Integer; Stream: TFileStream; Text: String;
Begin
  Result := False;
  For I := 0 To High(FInputs) Do
    Begin
      If InterlockedCompareExchange(FState.Cancelled, 0, 0) <> 0 Then Exit;
      Stream := TFileStream.Create(FInputs[I].Path, fmOpenRead Or fmShareDenyNone);
      Try
        If Stream.Size <> Length(FInputs[I].Text) Then Exit;
        SetLength(Text, Stream.Size);
        If Text <> '' Then Stream.ReadBuffer(Text[1], Length(Text));
        If Text <> FInputs[I].Text Then Exit;
      Finally Stream.Free; End;
    End;
  Result := True;
End;
Procedure TBuildWorker.Execute;
Var P: TProcess; Value: TBuildJobSnapshot; Deadline: QWord;
  I, N, Budget: Integer; Buf: Array[0..8191] Of Char; Part: String;
  Procedure Drain(Pipe: TInputPipeStream);
  Begin
    Budget := 65536;
    While (Pipe.NumBytesAvailable > 0) And (Budget > 0) Do
      Begin
        N := Pipe.NumBytesAvailable; If N > SizeOf(Buf) Then N := SizeOf(Buf);
        N := Pipe.Read(Buf, N); If N <= 0 Then Break;
        Dec(Budget, N);
        If Length(Value.OutputText) < 1048576 Then
          Begin
            SetString(Part, PChar(@Buf[0]), N);
            Value.OutputText := Value.OutputText + Copy(Part, 1, 1048576 - Length(Value.OutputText));
          End;
      End;
  End;
Begin
  P := Nil; Value := Default(TBuildJobSnapshot); Value.ExitCode := -1;
  Try
    Try
      {$IFNDEF LINUX}
      Raise Exception.Create('Asynchronous build pilot currently supports Linux only.');
      {$ENDIF}
      Value.Manifest := '[';
      For I := 0 To High(FInputs) Do
        Begin
          If I > 0 Then Value.Manifest := Value.Manifest + ',';
          Value.Manifest := Value.Manifest + '{"path":"' + JsonEscapeText(FInputs[I].Path) +
            '","sha1":"' + SHA1Print(SHA1String(FInputs[I].Text)) + '"}';
        End;
      Value.Manifest := Value.Manifest + ']';
      If Not InputsMatch Then Raise Exception.Create('Build inputs changed or are not saved; build not started.');
      P := TProcess.Create(Nil);
      P.Executable := FExecutable; P.CurrentDirectory := ExtractFilePath(FProject);
      P.Parameters.Add('--build-mode=' + FMode); P.Parameters.Add(FProject);
      P.Options := [poUsePipes]; P.OnForkEvent := @ChildFork;
      P.Execute;
      Deadline := GetTickCount64 + FTimeout;
      Repeat
        Drain(P.Output); Drain(P.Stderr);
        Value.Cancelled := InterlockedCompareExchange(FState.Cancelled, 0, 0) <> 0;
        If Value.Cancelled Then Break;
        If GetTickCount64 >= Deadline Then
          Begin Value.ErrorText := 'Build timed out.'; Break; End;
        If Not P.Running And (P.Output.NumBytesAvailable = 0) And (P.Stderr.NumBytesAvailable = 0) Then Break;
        Sleep(5);
      Until False;
      If Not P.Running Then Value.ExitCode := P.ExitCode;
      Value.InputsUnchanged := InputsMatch;
      If Not Value.InputsUnchanged And (Value.ErrorText = '') And Not Value.Cancelled Then
        Value.ErrorText := 'Observed source inputs changed during the build; diagnostics are stale.';
    Except
      On E: Exception Do Value.ErrorText := E.Message;
    End;
  Finally
    If Assigned(P) Then
      Begin
        {$IFDEF LINUX}
        { Kill the owned group even if the compiler parent has already exited. }
        If P.ProcessID > 0 Then
          Begin
            fpKill(-P.ProcessID, SIGKILL);
            If P.Running Then Begin fpKill(P.ProcessID, SIGKILL); P.WaitOnExit(500); End;
          End;
        {$ENDIF}
        P.Free;
      End;
    Value.Cancelled := InterlockedCompareExchange(FState.Cancelled, 0, 0) <> 0;
    Value.Done := True;
    EnterCriticalSection(FState.Lock);
    Try FState.Value := Value; Finally LeaveCriticalSection(FState.Lock); End;
    FKeepAlive := Nil;
  End;
End;
Function StartAssistantBuild(Const Executable, ProjectFile, BuildMode: String;
  Const Inputs: TBuildInputs; TimeoutMs: Cardinal): IAssistantBuildJob;
Var State: TBuildState; Worker: TBuildWorker;
Begin
  State := TBuildState.Create;
  Result := State;
  Worker := TBuildWorker.Create(True);
  Worker.FreeOnTerminate := True;
  Worker.FState := State; Worker.FKeepAlive := Result;
  Worker.FExecutable := Executable; Worker.FProject := ProjectFile; Worker.FMode := BuildMode;
  Worker.FInputs := Copy(Inputs); Worker.FTimeout := TimeoutMs;
  Worker.Start;
End;
End.
