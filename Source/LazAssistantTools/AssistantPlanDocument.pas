Unit AssistantPlanDocument;

{ Plan file reads and the monitor's full-file revision (c) 2026 Michell Computing.

  ReadAssistantPlanDocument keeps the 4 MiB model cap. The monitor revision is
  FNV-1a 64 of the whole file. A file over 256 KiB is hashed off the caller. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  { Model context cap. The phone review path does not use this. }
  AssistantPlanDocumentMaxBytes = 4 * 1024 * 1024;
  { At or under this size the IDE thread may hash the file. Larger files use the worker. }
  AssistantPlanInlineHashBytes = 256 * 1024;
  AssistantPlanHashBasis = UInt64(14695981039346656037);
  AssistantPlanHashPrime = UInt64(1099511628211);

/// Whole plan Markdown for the model. An empty path does not fall back to the default plan.
Function ReadAssistantPlanDocument(Const RelativeOrAbsolute: String; Out Truncated: Boolean): String;
{ FNV-1a 64 of the capped preview. Not the monitor revision. }
Function AssistantPlanDocumentRevision(Const RelativeOrAbsolute: String): String;
{ FNV-1a 64 of every byte. Empty when the path is empty or the file is missing. No size cap. }
Function AssistantPlanFileRevision(Const RelativeOrAbsolute: String): String;
{ Same hash of an absolute path. Does not resolve against the project. }
Function AssistantPlanHashFile(Const AbsolutePath: String): String;
Function AssistantPlanHashStart: UInt64;
Procedure AssistantPlanHashFold(Var Hash: UInt64; Const Data; Count: Integer);
Function AssistantPlanHashHex(Hash: UInt64): String;
{ Last published full-file revision. A file over 256 KiB is hashed off this thread. }
Function AssistantPlanCachedRevision(Const RelativeOrAbsolute: String; Age: LongInt; Bytes: Int64): String;
{ Age and size for the desktop save timer. False when the file is missing. }
Function AssistantPlanFileStamp(Const RelativeOrAbsolute: String; Out Age: LongInt; Out Bytes: Int64): Boolean;

Implementation

Uses
  Classes, SyncObjs, LazFileUtils, AssistantPlan;

Function TrimPartialUtf8(Const Text: String): String;
Var
  Last: Integer;
Begin
  Result := Text;
  While Result <> '' Do
    Begin
      Last := Ord(Result[Length(Result)]);
      If (Last And $C0) = $80 Then
        Delete(Result, Length(Result), 1)
      Else
        Break;
    End;
  If (Result <> '') And ((Ord(Result[Length(Result)]) And $C0) = $C0) Then
    Delete(Result, Length(Result), 1);
End;

Function ReadCappedUtf8File(Const FileName: String; MaxBytes: Integer; Out Truncated: Boolean): String;
Var
  Stream: TFileStream;
  Count, Size: Integer;
Begin
  Result := '';
  Truncated := False;
  If MaxBytes < 1 Then
    Exit;
  Try
    Stream := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Size := Stream.Size;
    If Size < 1 Then
      Exit;
    Truncated := Size > MaxBytes;
    Count := Size;
    If Count > MaxBytes Then
      Count := MaxBytes;
    SetLength(Result, Count);
    Count := Stream.Read(Result[1], Count);
    If Count < 0 Then
      Count := 0;
    SetLength(Result, Count);
    If (Length(Result) >= 3) And (Result[1] = #$EF) And (Result[2] = #$BB) And (Result[3] = #$BF) Then
      Delete(Result, 1, 3);
    If Truncated Then
      Result := TrimPartialUtf8(Result);
  Finally
    Stream.Free;
  End;
End;

Function AssistantPlanHashStart: UInt64;
Begin
  Result := AssistantPlanHashBasis;
End;

Procedure AssistantPlanHashFold(Var Hash: UInt64; Const Data; Count: Integer);
Var
  Bytes: PByte;
  Index: Integer;
Begin
  If Count < 1 Then
    Exit;
  Bytes := @Data;
  {$PUSH}{$Q-}{$R-}
  For Index := 0 To Count - 1 Do
    Begin
      Hash := Hash Xor Bytes[Index];
      Hash := Hash * AssistantPlanHashPrime;
    End;
  {$POP}
End;

Function AssistantPlanHashHex(Hash: UInt64): String;
Begin
  Result := LowerCase(IntToHex(Hash, 16));
End;

Function PlanFileRevision(Const Text: String): String;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If Text <> '' Then
    AssistantPlanHashFold(Hash, Text[1], Length(Text));
  Result := AssistantPlanHashHex(Hash);
End;

Function HashAbsoluteFile(Const FileName: String): String;
Var
  Stream: TFileStream;
  Buffer: Array[0..8191] Of Byte;
  Count: Integer;
  Hash: UInt64;
Begin
  Result := '';
  FillChar(Buffer, SizeOf(Buffer), 0);
  If FileName = '' Then
    Exit;
  Try
    Stream := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Hash := AssistantPlanHashStart;
    Repeat
      Count := Stream.Read(Buffer, SizeOf(Buffer));
      If Count < 0 Then
        Exit;
      If Count > 0 Then
        AssistantPlanHashFold(Hash, Buffer, Count);
    Until Count = 0;
    Result := AssistantPlanHashHex(Hash);
  Finally
    Stream.Free;
  End;
End;

Function ReadAssistantPlanDocument(Const RelativeOrAbsolute: String; Out Truncated: Boolean): String;
Var
  Resolved, ErrorText: String;
Begin
  Result := '';
  Truncated := False;
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Result := ReadCappedUtf8File(Resolved, AssistantPlanDocumentMaxBytes, Truncated);
End;

Function AssistantPlanDocumentRevision(Const RelativeOrAbsolute: String): String;
Var
  Resolved, ErrorText, Body: String;
  Truncated: Boolean;
Begin
  Result := '';
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Exit;
  Body := ReadCappedUtf8File(Resolved, AssistantPlanDocumentMaxBytes, Truncated);
  Result := PlanFileRevision(Body);
End;

Function AssistantPlanHashFile(Const AbsolutePath: String): String;
Begin
  Result := '';
  If Trim(AbsolutePath) = '' Then
    Exit;
  If Not FileExistsUTF8(AbsolutePath) Then
    Exit;
  Result := HashAbsoluteFile(AbsolutePath);
End;

Function AssistantPlanFileRevision(Const RelativeOrAbsolute: String): String;
Var
  Resolved, ErrorText: String;
Begin
  Result := '';
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  Result := AssistantPlanHashFile(Resolved);
End;

Type
  TPlanHashJob = Record
    Path: String;
    Resolved: String;
    Age: LongInt;
    Bytes: Int64;
    Generation: Integer;
  End;

  TPlanHashThread = Class(TThread)
  Private
    Lock: TCriticalSection;
    Wake: TEvent;
    Job: TPlanHashJob;
    HasJob: Boolean;
    Generation: Integer;
    DonePath: String;
    DoneAge: LongInt;
    DoneBytes: Int64;
    DoneRevision: String;
    DoneTick: QWord;
    Procedure Serve(Const One: TPlanHashJob);
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Request(Const RelativePath, Resolved: String; Age: LongInt; Bytes: Int64);
    Function PublishedRevision(Const RelativePath: String): String;
  End;

Var
  PlanHashThread: TPlanHashThread;

Constructor TPlanHashThread.Create;
Begin
  Lock := TCriticalSection.Create;
  Wake := TEvent.Create(Nil, False, False, '');
  HasJob := False;
  Generation := 0;
  DoneAge := -1;
  DoneBytes := -1;
  DoneTick := 0;
  Inherited Create(False);
End;

Destructor TPlanHashThread.Destroy;
Begin
  Terminate;
  Wake.SetEvent;
  WaitFor;
  Wake.Free;
  Lock.Free;
  Inherited Destroy;
End;

Procedure TPlanHashThread.Request(Const RelativePath, Resolved: String; Age: LongInt; Bytes: Int64);
Begin
  Lock.Acquire;
  Try
    If (Not HasJob) And (DonePath = RelativePath) And (DoneAge = Age) And (DoneBytes = Bytes) And
      (DoneTick <> 0) And (GetTickCount64 - DoneTick < 1000) Then
      Exit;
    If HasJob And (Job.Path = RelativePath) And (Job.Age = Age) And (Job.Bytes = Bytes) Then
      Exit;
    Inc(Generation);
    Job.Path := RelativePath;
    Job.Resolved := Resolved;
    Job.Age := Age;
    Job.Bytes := Bytes;
    Job.Generation := Generation;
    HasJob := True;
    Wake.SetEvent;
  Finally
    Lock.Release;
  End;
End;

Function TPlanHashThread.PublishedRevision(Const RelativePath: String): String;
Begin
  Lock.Acquire;
  Try
    If DonePath = RelativePath Then
      Result := DoneRevision
    Else
      Result := '';
  Finally
    Lock.Release;
  End;
End;

Procedure TPlanHashThread.Serve(Const One: TPlanHashJob);
Var
  Revision: String;
Begin
  Revision := HashAbsoluteFile(One.Resolved);
  Lock.Acquire;
  Try
    If One.Generation <> Generation Then
      Exit;
    DonePath := One.Path;
    DoneAge := One.Age;
    DoneBytes := One.Bytes;
    DoneRevision := Revision;
    DoneTick := GetTickCount64;
    HasJob := False;
  Finally
    Lock.Release;
  End;
End;

Procedure TPlanHashThread.Execute;
Var
  One: TPlanHashJob;
  Have: Boolean;
Begin
  While Not Terminated Do
    Begin
      Have := False;
      Lock.Acquire;
      Try
        If HasJob Then
          Begin
            One := Job;
            HasJob := False;
            Have := True;
          End;
      Finally
        Lock.Release;
      End;
      If Have Then
        Begin
          Try
            Serve(One);
          Except
            On Exception Do
              ;
          End;
        End
      Else
        Wake.WaitFor(500);
    End;
End;

Function AssistantPlanCachedRevision(Const RelativeOrAbsolute: String; Age: LongInt; Bytes: Int64): String;
Var
  Resolved, ErrorText: String;
Begin
  Result := '';
  If (Trim(RelativeOrAbsolute) = '') Or (Bytes < 0) Then
    Exit;
  If Bytes <= AssistantPlanInlineHashBytes Then
    Begin
      Result := AssistantPlanFileRevision(RelativeOrAbsolute);
      Exit;
    End;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not Assigned(PlanHashThread) Then
    PlanHashThread := TPlanHashThread.Create;
  PlanHashThread.Request(RelativeOrAbsolute, Resolved, Age, Bytes);
  Result := PlanHashThread.PublishedRevision(RelativeOrAbsolute);
End;

Function AssistantPlanFileStamp(Const RelativeOrAbsolute: String; Out Age: LongInt; Out Bytes: Int64): Boolean;
Var
  Resolved, ErrorText: String;
  Stream: TFileStream;
Begin
  Result := False;
  Age := -1;
  Bytes := -1;
  If Trim(RelativeOrAbsolute) = '' Then
    Exit;
  If Not ResolvePlanPath(RelativeOrAbsolute, Resolved, ErrorText) Then
    Exit;
  If Not FileExistsUTF8(Resolved) Then
    Exit;
  Age := FileAge(Resolved);
  Try
    Stream := TFileStream.Create(Resolved, fmOpenRead Or fmShareDenyNone);
  Except
    Exit;
  End;
  Try
    Bytes := Stream.Size;
    Result := True;
  Finally
    Stream.Free;
  End;
End;

Finalization

If Assigned(PlanHashThread) Then
  FreeAndNil(PlanHashThread);

End.
