Unit AssistantMonitorPlanFetch;

{ Streams a plan file for plan_get (c) 2026 Michell Computing.

  The link thread polls ready frames. A worker reads the file, off the IDE
  thread, and releases its lock before each read. Pieces are at most 24 KiB of
  UTF-8 and never split a code point. A replacement is revision_changed with no
  mixed bytes. This path does not call ReadAssistantPlanDocument or
  ReadMonitorPlanPreview, and it does not stop at 4 MiB. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, AssistantMonitorCodec;

Type
  TMonitorPlanFetchReady = Procedure Of Object;

  TMonitorPlanFetch = Class
  Private
    Lock: TCriticalSection;
    Wake: TEvent;
    Space: TEvent;
    FWorker: TThread;
    FOnReady: TMonitorPlanFetchReady;
    FGeneration: Integer;
    FHasJob: Boolean;
    FRequestId: String;
    FPayload: TMonitorPayload;
    FRoot: String;
    FCachePath: String;
    FCacheRevision: String;
    FSlot: String;
    FSlotFull: Boolean;
    { True when the stored frame is plan_data. An error frame stays on control. }
    FSlotBulk: Boolean;
    Procedure EnsureWorker;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Stores the request. Does not read the file. }
    Procedure BeginGet(Const RequestId: String; Const PayloadJson: TMonitorPayload; Const ProjectRoot: String);
    { IDE timer published this full-file revision. Does not read the file. }
    Procedure NoteCachedRevision(Const Path, Revision: String);
    Procedure Cancel;
    Function Ready: Boolean;
    { Bulk is true for plan_data. Error frames are not bulk. The session queues with that lane and does not parse. }
    Function Take(Out Json: String; Out Bulk: Boolean): Boolean;
    Property OnReady: TMonitorPlanFetchReady Read FOnReady Write FOnReady;
  End;

Implementation

Uses
  fpjson, jsonparser, LazFileUtils, AssistantPlan, AssistantPlanDocument, AssistantMonitorFrames,
  AssistantMonitorOutbox, AssistantMonitorText;

Const
  PlanSliceBytes = 24 * 1024;
  PlanBlockBytes = 4096;
  PlanChangedMessage = 'The plan changed. Start the fetch again.';

Type
  TPlanFetchWorker = Class(TThread)
  Private
    Owner: TMonitorPlanFetch;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AOwner: TMonitorPlanFetch);
  End;

  TPlanBlockHash = UInt64;
  TPlanBlockHashes = Array Of TPlanBlockHash;

Function JsonBudget: Integer;
Begin
  Result := MonitorOutboxChunkBytes - MonitorFrameHeaderSize;
  If Result < 1024 Then
    Result := 1024;
End;

Function ErrorFrame(Const FrameId, Reason, MessageText, RefId: String): String;
Var
  Root, Payload: TJSONObject;
Begin
  Result := '';
  Root := TJSONObject.Create;
  Payload := TJSONObject.Create;
  Try
    Payload.Add('reason', Reason);
    Payload.Add('message', MessageText);
    Payload.Add('ref', RefId);
    Root.Add('v', 3);
    Root.Add('id', FrameId);
    Root.Add('type', 'error');
    Root.Add('payload', Payload);
    Payload := Nil;
    Result := Root.AsJSON;
  Finally
    Payload.Free;
    Root.Free;
  End;
End;

Function DataFrame(Const FrameId, Path, Revision, Text, RefId: String; Offset, Total: Int64; Last: Boolean): String;
Var
  Root, Payload: TJSONObject;
  Body: RawByteString;
Begin
  Result := '';
  Root := TJSONObject.Create;
  Payload := TJSONObject.Create;
  Body := Text;
  SetCodePage(Body, CP_UTF8, False);
  Try
    Payload.Add('path', Path);
    Payload.Add('revision', Revision);
    Payload.Add('offset', Offset);
    Payload.Add('text', String(Body));
    Payload.Add('total_bytes', Total);
    Payload.Add('last', Last);
    Payload.Add('ref', RefId);
    Root.Add('v', 3);
    Root.Add('id', FrameId);
    Root.Add('type', 'plan_data');
    Root.Add('payload', Payload);
    Payload := Nil;
    Result := Root.AsJSON;
  Finally
    Payload.Free;
    Root.Free;
  End;
End;

Function AcceptUtf8(Var Carry: RawByteString; Const Chunk: RawByteString; FinalBlock: Boolean): Boolean;
Var
  Combined: RawByteString;
  Index, Need: Integer;
Begin
  Result := False;
  Combined := Carry + Chunk;
  Carry := '';
  Index := 1;
  While Index <= Length(Combined) Do
    Begin
      Need := Utf8Need(Ord(Combined[Index]));
      If Need = 0 Then
        Exit;
      If Index + Need - 1 > Length(Combined) Then
        Begin
          If FinalBlock Then
            Exit;
          Carry := Copy(Combined, Index, MaxInt);
          Exit(True);
        End;
      If Not SequenceOk(Combined, Index, Need) Then
        Exit;
      Inc(Index, Need);
    End;
  Result := True;
End;

Function Utf8PrefixLen(Const Bytes: RawByteString; MaxLen: Integer): Integer;
Var
  Index, Need: Integer;
Begin
  Result := 0;
  If MaxLen > Length(Bytes) Then
    MaxLen := Length(Bytes);
  If MaxLen < 1 Then
    Exit;
  Index := 1;
  While Index <= MaxLen Do
    Begin
      Need := Utf8Need(Ord(Bytes[Index]));
      If Need = 0 Then
        Exit(Index);
      If Index + Need - 1 > MaxLen Then
        Exit;
      If Not SequenceOk(Bytes, Index, Need) Then
        Exit(Index);
      Result := Index + Need - 1;
      Index := Result + 1;
    End;
End;

Function SamePlanPath(Const Left, Right: String): Boolean;
Begin
  Result := CompareFilenames(StringReplace(Left, '\', '/', [rfReplaceAll]),
    StringReplace(Right, '\', '/', [rfReplaceAll])) = 0;
End;

Function BlockHash(Const Bytes: RawByteString): TPlanBlockHash;
Var
  Hash: UInt64;
Begin
  Hash := AssistantPlanHashStart;
  If Bytes <> '' Then
    AssistantPlanHashFold(Hash, Bytes[1], Length(Bytes));
  Result := Hash;
End;

Constructor TPlanFetchWorker.Create(AOwner: TMonitorPlanFetch);
Begin
  Owner := AOwner;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TPlanFetchWorker.Execute;
Var
  RequestId, Root: String;
  Payload: TMonitorPayload;
  Generation: Integer;
  Have: Boolean;

  Function StillCurrent: Boolean;
  Begin
    Owner.Lock.Acquire;
    Try
      Result := (Not Terminated) And (Generation = Owner.FGeneration);
    Finally
      Owner.Lock.Release;
    End;
  End;

  Function StoreFrame(Const Json: String; Bulk: Boolean): Boolean;
  Var
    Callback: TMonitorPlanFetchReady;
  Begin
    Result := False;
    Callback := Nil;
    While Not Terminated Do
      Begin
        Owner.Lock.Acquire;
        Try
          If Generation <> Owner.FGeneration Then
            Exit;
          If Not Owner.FSlotFull Then
            Begin
              Owner.FSlot := Json;
              Owner.FSlotBulk := Bulk;
              Owner.FSlotFull := True;
              Callback := Owner.FOnReady;
              Result := True;
            End;
        Finally
          Owner.Lock.Release;
        End;
        If Result Then
          Begin
            If Assigned(Callback) Then
              Callback;
            Exit;
          End;
        Owner.Space.WaitFor(200);
      End;
  End;

  Procedure ServeJob;
  Var
    Data: TJSONData;
    Obj: TJSONObject;
    AskedPath, AskedRevision, Resolved, ErrorText, BoundRevision, FrameId, Piece, Json: String;
    AskedOffset, Total, At: Int64;
    Stream: TFileStream;
    Buffer: Array[0..PlanBlockBytes - 1] Of Byte;
    Count, Taken, Part, BlockCount, BlockIndex: Integer;
    Hashes: TPlanBlockHashes;
    Carry, Block: RawByteString;
    Hash: UInt64;
    Age, NowAge: LongInt;
    Utf8Ok, Last: Boolean;
    SeenCache, NowCache, RequestPath: String;

    Function Fail(Const Reason, MessageText: String): Boolean;
    Begin
      Result := False;
      If Not StillCurrent Then
        Exit;
      FrameId := 'pf' + IntToStr(Generation) + 'e';
      StoreFrame(ErrorFrame(FrameId, Reason, MessageText, RequestId), False);
    End;

    Function IdentityMoved: Boolean;
    Begin
      NowAge := FileAge(Resolved);
      Result := (NowAge <> Age) Or (Stream.Size <> Total);
    End;

    Function CacheChanged: Boolean;
    Begin
      Result := False;
      Owner.Lock.Acquire;
      Try
        If Not SamePlanPath(Owner.FCachePath, RequestPath) Then
          Exit;
        NowCache := Owner.FCacheRevision;
      Finally
        Owner.Lock.Release;
      End;
      If NowCache = SeenCache Then
        Exit;
      If (NowCache <> '') And (NowCache = BoundRevision) Then
        Begin
          SeenCache := NowCache;
          Exit;
        End;
      Result := True;
    End;

    Function ReadBlock(Index: Integer; Out Bytes: RawByteString): Boolean;
    Var
      Need, Got: Integer;
      { All reads use the job's stream, including verification after backpressure. }
    Begin
      Result := False;
      Bytes := '';
      Need := PlanBlockBytes;
      If Int64(Index + 1) * PlanBlockBytes > Total Then
        Need := Total - Int64(Index) * PlanBlockBytes;
      If Need < 1 Then
        Exit;
      Stream.Position := Int64(Index) * PlanBlockBytes;
      SetLength(Bytes, Need);
      Got := Stream.Read(Bytes[1], Need);
      If Got <> Need Then
        Begin
          Bytes := '';
          Exit;
        End;
      Result := BlockHash(Bytes) = Hashes[Index];
      If Not Result Then
        Bytes := '';
    End;

    Function VerifiedSlice(ByteOffset: Int64; Out Bytes: RawByteString): Boolean;
    Var
      First, LastIndex, Index, Into, Want, CopyFrom, CopyCount: Integer;
      One: RawByteString;
    Begin
      Result := False;
      Bytes := '';
      If ByteOffset >= Total Then
        Exit(True);
      Want := PlanSliceBytes;
      If ByteOffset + Want > Total Then
        Want := Total - ByteOffset;
      First := ByteOffset Div PlanBlockBytes;
      LastIndex := (ByteOffset + Want - 1) Div PlanBlockBytes;
      SetLength(Bytes, Want);
      Into := 1;
      For Index := First To LastIndex Do
        Begin
          If Not ReadBlock(Index, One) Then
            Begin
              Bytes := '';
              Exit;
            End;
          CopyFrom := 1;
          CopyCount := Length(One);
          If Index = First Then
            Begin
              CopyFrom := (ByteOffset Mod PlanBlockBytes) + 1;
              CopyCount := Length(One) - CopyFrom + 1;
            End;
          If Into + CopyCount - 1 > Want Then
            CopyCount := Want - Into + 1;
          If CopyCount > 0 Then
            Move(One[CopyFrom], Bytes[Into], CopyCount);
          Inc(Into, CopyCount);
        End;
      If Into - 1 <> Want Then
        Begin
          Bytes := '';
          Exit;
        End;
      Result := True;
    End;

    Function WaitForSpace: Boolean;
    Begin
      Result := False;
      While Not Terminated Do
        Begin
          If Not StillCurrent Then
            Exit;
          Owner.Lock.Acquire;
          Try
            Result := Not Owner.FSlotFull;
          Finally
            Owner.Lock.Release;
          End;
          If Result Then
            Exit;
          Owner.Space.WaitFor(200);
        End;
    End;

    Function OfferData(Const Json: String): Boolean;
    Var
      Callback: TMonitorPlanFetchReady;
    Begin
      Result := False;
      If Terminated Or Not StillCurrent Then
        Exit;
      { The sole producer waited for the slot before verifying this slice. }
      If IdentityMoved Or CacheChanged Then
        Begin
          Fail('revision_changed', PlanChangedMessage);
          Exit;
        End;
      Callback := Nil;
      Owner.Lock.Acquire;
      Try
        If Generation <> Owner.FGeneration Then
          Exit;
        Owner.FSlot := Json;
        Owner.FSlotBulk := True;
        Owner.FSlotFull := True;
        Callback := Owner.FOnReady;
        Result := True;
      Finally
        Owner.Lock.Release;
      End;
      If Assigned(Callback) Then
        Callback;
    End;

  Begin
    Hashes := Nil;
    Data := Nil;
    AskedPath := '';
    AskedRevision := '';
    AskedOffset := 0;
    RequestPath := '';
    If Not ParseMonitorObject(Payload, Data, Obj) Then
      Begin
        Data.Free;
        Fail('protocol', 'Plan fetch payload is not valid.');
        Exit;
      End;
    Try
      If (Obj.Find('path') = Nil) Or (Obj.Find('path').JSONType <> jtString) Or (Obj.Find('offset') = Nil) Or
        (Obj.Find('offset').JSONType <> jtNumber) Or (Obj.Find('revision') = Nil) Or
        (Obj.Find('revision').JSONType <> jtString) Then
        Begin
          Fail('protocol', 'Plan fetch payload is not valid.');
          Exit;
        End;
      AskedPath := Obj.Get('path', '');
      AskedRevision := Obj.Get('revision', '');
      AskedOffset := Obj.Find('offset').AsInt64;
    Finally
      Data.Free;
    End;
    RequestPath := AskedPath;
    If Not StillCurrent Then
      Exit;
    If AskedOffset < 0 Then
      Begin
        Fail('protocol', 'Plan fetch payload is not valid.');
        Exit;
      End;
    If Not ResolvePlanPathUnder(Root, AskedPath, Resolved, ErrorText) Or (Not FileExistsUTF8(Resolved)) Then
      Begin
        Fail('not_found', 'The plan file was not found.');
        Exit;
      End;
    Age := FileAge(Resolved);
    Try
      Stream := TFileStream.Create(Resolved, fmOpenRead Or fmShareDenyNone);
    Except
      Fail('failed', 'The plan file could not be read.');
      Exit;
    End;
    Try
      Total := Stream.Size;
      If (Total < 0) Or (Total > High(Int64) - PlanBlockBytes) Then
        Begin
          Fail('failed', 'The plan file could not be read.');
          Exit;
        End;
      BlockCount := (Total + PlanBlockBytes - 1) Div PlanBlockBytes;
      SetLength(Hashes, BlockCount);
      Hash := AssistantPlanHashStart;
      Carry := '';
      Block := '';
      FillChar(Buffer, SizeOf(Buffer), 0);
      Utf8Ok := True;
      BlockIndex := 0;
      At := 0;
      While At < Total Do
        Begin
          Count := PlanBlockBytes;
          If At + Count > Total Then
            Count := Total - At;
          Count := Stream.Read(Buffer, Count);
          If Count < 1 Then
            Begin
              Utf8Ok := False;
              Break;
            End;
          SetLength(Block, Count);
          Move(Buffer[0], Block[1], Count);
          AssistantPlanHashFold(Hash, Block[1], Count);
          Hashes[BlockIndex] := BlockHash(Block);
          Inc(BlockIndex);
          Inc(At, Count);
          If Not AcceptUtf8(Carry, Block, At >= Total) Then
            Utf8Ok := False;
        End;
      If (At <> Total) Or (Carry <> '') Then
        Utf8Ok := False;
      BoundRevision := AssistantPlanHashHex(Hash);
      If Not StillCurrent Then
        Exit;
      If Not Utf8Ok Then
        Begin
          Fail('failed', 'The plan file is not valid UTF-8.');
          Exit;
        End;
      If IdentityMoved Then
        Begin
          Fail('revision_changed', PlanChangedMessage);
          Exit;
        End;
      Owner.Lock.Acquire;
      Try
        If SamePlanPath(Owner.FCachePath, RequestPath) Then
          SeenCache := Owner.FCacheRevision
        Else
          SeenCache := '';
      Finally
        Owner.Lock.Release;
      End;
      If (AskedOffset > 0) And ((AskedRevision = '') Or (AskedRevision <> BoundRevision)) Then
        Begin
          Fail('revision_changed', PlanChangedMessage);
          Exit;
        End;
      If AskedOffset > Total Then
        Begin
          Fail('protocol', 'Plan fetch offset is past the end of the file.');
          Exit;
        End;
      Part := 0;
      At := AskedOffset;
      Repeat
        { Only this worker fills the slot. Verify once after the consumer makes room. }
        If Not WaitForSpace Then
          Exit;
        If IdentityMoved Or CacheChanged Then
          Begin
            Fail('revision_changed', PlanChangedMessage);
            Exit;
          End;
        If At < Total Then
          Begin
            If Not VerifiedSlice(At, Block) Then
              Begin
                Fail('revision_changed', PlanChangedMessage);
                Exit;
              End;
            Taken := Utf8PrefixLen(Block, Length(Block));
            Json := '';
            While Taken > 0 Do
              Begin
                Piece := String(Copy(Block, 1, Taken));
                SetCodePage(RawByteString(Piece), CP_UTF8, False);
                Last := At + Taken = Total;
                FrameId := 'pf' + IntToStr(Generation) + 's' + IntToStr(Part);
                Json := DataFrame(FrameId, AskedPath, BoundRevision, Piece, RequestId, At, Total, Last);
                If (Json <> '') And (Length(Json) <= JsonBudget) Then
                  Break;
                Taken := Utf8PrefixLen(Block, Taken Div 2);
                Json := '';
              End;
            If (Taken < 1) Or (Json = '') Then
              Begin
                Fail('failed', 'The plan file could not be read.');
                Exit;
              End;
          End
        Else
          Begin
            Taken := 0;
            Last := True;
            FrameId := 'pf' + IntToStr(Generation) + 's' + IntToStr(Part);
            Json := DataFrame(FrameId, AskedPath, BoundRevision, '', RequestId, At, Total, True);
          End;
        If Not OfferData(Json) Then
          Exit;
        Inc(Part);
        Inc(At, Taken);
      Until Last;
    Finally
      Stream.Free;
    End;
  End;

Begin
  While Not Terminated Do
    Begin
      Have := False;
      RequestId := '';
      Payload := '';
      Root := '';
      Generation := 0;
      Owner.Lock.Acquire;
      Try
        If Owner.FHasJob Then
          Begin
            RequestId := Owner.FRequestId;
            Payload := Owner.FPayload;
            Owner.FPayload := '';
            Root := Owner.FRoot;
            Generation := Owner.FGeneration;
            Owner.FHasJob := False;
            Have := True;
          End;
      Finally
        Owner.Lock.Release;
      End;
      If Have Then
        Begin
          Try
            ServeJob;
          Except
            On Exception Do
              If StillCurrent Then
                StoreFrame(ErrorFrame('pf' + IntToStr(Generation) + 'e', 'failed', 'The plan file could not be read.',
                  RequestId), False);
          End;
        End
      Else
        Owner.Wake.WaitFor(500);
    End;
End;

Constructor TMonitorPlanFetch.Create;
Begin
  Inherited Create;
  Lock := TCriticalSection.Create;
  Wake := TEvent.Create(Nil, False, False, '');
  Space := TEvent.Create(Nil, False, False, '');
  FWorker := Nil;
  FOnReady := Nil;
  FGeneration := 0;
  FHasJob := False;
  FSlotFull := False;
  FSlotBulk := False;
End;

Destructor TMonitorPlanFetch.Destroy;
Begin
  FOnReady := Nil;
  Cancel;
  If Assigned(FWorker) Then
    Begin
      FWorker.Terminate;
      Wake.SetEvent;
      Space.SetEvent;
      FWorker.WaitFor;
      FreeAndNil(FWorker);
    End;
  Space.Free;
  Wake.Free;
  Lock.Free;
  Inherited Destroy;
End;

Procedure TMonitorPlanFetch.EnsureWorker;
Begin
  If Assigned(FWorker) Then
    Exit;
  FWorker := TPlanFetchWorker.Create(Self);
End;

Procedure TMonitorPlanFetch.BeginGet(Const RequestId: String; Const PayloadJson: TMonitorPayload; Const ProjectRoot: String);
Begin
  EnsureWorker;
  Lock.Acquire;
  Try
    Inc(FGeneration);
    FRequestId := RequestId;
    FPayload := PayloadJson;
    FRoot := ProjectRoot;
    FHasJob := True;
    FSlot := '';
    FSlotFull := False;
    FSlotBulk := False;
  Finally
    Lock.Release;
  End;
  Space.SetEvent;
  Wake.SetEvent;
End;

Procedure TMonitorPlanFetch.NoteCachedRevision(Const Path, Revision: String);
Begin
  Lock.Acquire;
  Try
    FCachePath := Path;
    FCacheRevision := Revision;
  Finally
    Lock.Release;
  End;
End;

Procedure TMonitorPlanFetch.Cancel;
Begin
  Lock.Acquire;
  Try
    Inc(FGeneration);
    FHasJob := False;
    FSlot := '';
    FSlotFull := False;
    FSlotBulk := False;
  Finally
    Lock.Release;
  End;
  If Assigned(Wake) Then
    Wake.SetEvent;
  If Assigned(Space) Then
    Space.SetEvent;
End;

Function TMonitorPlanFetch.Ready: Boolean;
Begin
  Lock.Acquire;
  Try
    Result := FSlotFull;
  Finally
    Lock.Release;
  End;
End;

Function TMonitorPlanFetch.Take(Out Json: String; Out Bulk: Boolean): Boolean;
Begin
  Json := '';
  Bulk := False;
  Lock.Acquire;
  Try
    Result := FSlotFull;
    If Not Result Then
      Exit;
    Json := FSlot;
    Bulk := FSlotBulk;
    FSlot := '';
    FSlotBulk := False;
    FSlotFull := False;
  Finally
    Lock.Release;
  End;
  Space.SetEvent;
End;

End.
