Unit AssistantMonitorSnapshot;

{ Immutable host snapshot for the remote monitor (c) 2026 Michell Computing.

  The IDE thread builds it 100 ms after a mirror wake or an observe notice, and
  at least every second while changes keep arriving. A build that is already
  running sets a dirty flag and builds again when it finishes. It does not drop
  the tick. HTTP threads only read a published snapshot. No JSON is built here. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantSessionObserve;

Const
  MonitorSnapshotDelayMs = 100;
  MonitorSnapshotBackstopMs = 1000;

Type
  TMonitorSnapshotItem = Record
    Id: AnsiString;
    Kind: AnsiString;
    State: AnsiString;
    Revision: QWord;
    Body: AnsiString;
  End;

  TMonitorSnapshot = Class
  Private
    FRef: Integer;
  Public
    Rev: Int64;
    Available, Busy, Sending, PlanRunning, SignedIn: Boolean;
    CanSend, CanSteer, CanStop, CanChangeMode, RemoteApproval, StopPending: Boolean;
    Mode, Phase, StatusText, Activity, ActivitySince, TurnStartedAt: AnsiString;
    ErrorText, UsageCaption, UsageHint: AnsiString;
    ElapsedMs: Integer;
    ConversationId, ConversationTitle, ConversationEtag: AnsiString;
    TurnCount: Integer;
    HasLive: Boolean;
    LiveTurnId: AnsiString;
    LiveTurnIndex: Integer;
    LiveRev: QWord;
    Items: Array Of TMonitorSnapshotItem;
    PlanPath, PlanEtag, PlanItem: AnsiString;
    PlanItemRunning: Boolean;
    ListConversations, ListPlans, ListTasks: AnsiString;
    ApprovalActive: Boolean;
    ApprovalId, ApprovalTool: AnsiString;
    Constructor Create;
    Procedure Retain;
    Procedure Release;
  End;

  TMonitorSnapshotSource = Class
  Public
    Function Fill(Snap: TMonitorSnapshot): Boolean; Virtual; Abstract;
  End;

Procedure CopyMonitorTurn(Const Turn: TAssistantMonitorTurn; Snap: TMonitorSnapshot);
Procedure StartMonitorSnapshot(Source: TMonitorSnapshotSource);
Procedure StopMonitorSnapshot;
Function MonitorSnapshotRunning: Boolean;
{ Caller must Release the result. Nil when nothing has been published. }
Function PublishedMonitorSnapshot: TMonitorSnapshot;
Function MonitorSnapshotRev: Int64;
{ Called after a snapshot is published, outside the publisher lock. }
Procedure SetMonitorPublishWake(Wake: TProcedure);

Implementation

Uses
  Classes, SyncObjs, WorkflowLog;

Type
  TSnapshotScheduler = Class(TThread)
  Protected
    Procedure Execute; Override;
  End;

  TMonitorSnapshotPublisher = Class
    Source: TMonitorSnapshotSource;
    Lock: TRTLCriticalSection;
    WakeEvent: PRTLEvent;
    Scheduler: TSnapshotScheduler;
    PublishedSnap: TMonitorSnapshot;
    Dirty: Boolean;
    CoalesceOpen: Boolean;
    FirstDirty, DueAt: QWord;
    Building: Boolean;
    Stopping: Boolean;
    Procedure NoteChange;
    Procedure Hear(Kind: TAssistantSessionNoticeKind);
    Procedure Wake;
    Function DueNow: Boolean;
    Function NextWaitMs: Integer;
    Procedure Build;
    Procedure Publish(Snap: TMonitorSnapshot);
  End;

Var
  Publisher: TMonitorSnapshotPublisher;
  PublishWake: TProcedure;

Constructor TMonitorSnapshot.Create;
Begin
  Inherited Create;
  FRef := 1;
End;

Procedure TMonitorSnapshot.Retain;
Begin
  InterlockedIncrement(FRef);
End;

Procedure TMonitorSnapshot.Release;
Begin
  If InterlockedDecrement(FRef) = 0 Then
    Destroy;
End;

Function ItemState(Const Block: TAssistantMonitorBlock): String;
Begin
  If Block.Running Then
    Result := 'running'
  Else If Not Block.Ok Then
    Result := 'failed'
  Else
    Result := 'done';
End;

Procedure CopyMonitorTurn(Const Turn: TAssistantMonitorTurn; Snap: TMonitorSnapshot);
Var
  Index: Integer;
Begin
  SetLength(Snap.Items, Length(Turn.Blocks));
  Snap.LiveRev := 0;
  For Index := 0 To High(Turn.Blocks) Do
    Begin
      Snap.Items[Index].Id := Turn.Blocks[Index].BlockId;
      Snap.Items[Index].Kind := Turn.Blocks[Index].Kind;
      Snap.Items[Index].State := ItemState(Turn.Blocks[Index]);
      Snap.Items[Index].Revision := Turn.Blocks[Index].Revision;
      Snap.Items[Index].Body := Turn.Blocks[Index].Body;
      If Turn.Blocks[Index].Revision > Snap.LiveRev Then
        Snap.LiveRev := Turn.Blocks[Index].Revision;
    End;
End;

Function SameItems(Const Left, Right: Array Of TMonitorSnapshotItem): Boolean;
Var
  Index: Integer;
Begin
  Result := Length(Left) = Length(Right);
  If Not Result Then
    Exit;
  For Index := 0 To High(Left) Do
    If (Left[Index].Id <> Right[Index].Id) Or (Left[Index].Kind <> Right[Index].Kind) Or
      (Left[Index].State <> Right[Index].State) Or (Left[Index].Revision <> Right[Index].Revision) Or
      (Left[Index].Body <> Right[Index].Body) Then
      Exit(False);
End;

Function SameSnapshot(Left, Right: TMonitorSnapshot): Boolean;
Begin
  Result := Assigned(Left) And Assigned(Right) And
    (Left.Available = Right.Available) And (Left.Busy = Right.Busy) And (Left.Sending = Right.Sending) And
    (Left.PlanRunning = Right.PlanRunning) And (Left.SignedIn = Right.SignedIn) And
    (Left.CanSend = Right.CanSend) And (Left.CanSteer = Right.CanSteer) And (Left.CanStop = Right.CanStop) And
    (Left.CanChangeMode = Right.CanChangeMode) And (Left.RemoteApproval = Right.RemoteApproval) And
    (Left.StopPending = Right.StopPending) And (Left.Mode = Right.Mode) And (Left.Phase = Right.Phase) And
    (Left.StatusText = Right.StatusText) And (Left.Activity = Right.Activity) And
    (Left.ActivitySince = Right.ActivitySince) And (Left.TurnStartedAt = Right.TurnStartedAt) And
    (Left.ErrorText = Right.ErrorText) And (Left.UsageCaption = Right.UsageCaption) And
    (Left.UsageHint = Right.UsageHint) And (Left.ConversationId = Right.ConversationId) And
    (Left.ConversationTitle = Right.ConversationTitle) And (Left.ConversationEtag = Right.ConversationEtag) And
    (Left.TurnCount = Right.TurnCount) And (Left.HasLive = Right.HasLive) And (Left.LiveTurnId = Right.LiveTurnId) And
    (Left.LiveTurnIndex = Right.LiveTurnIndex) And (Left.LiveRev = Right.LiveRev) And
    (Left.PlanPath = Right.PlanPath) And (Left.PlanEtag = Right.PlanEtag) And (Left.PlanItem = Right.PlanItem) And
    (Left.PlanItemRunning = Right.PlanItemRunning) And (Left.ListConversations = Right.ListConversations) And
    (Left.ListPlans = Right.ListPlans) And (Left.ListTasks = Right.ListTasks) And
    (Left.ApprovalActive = Right.ApprovalActive) And (Left.ApprovalId = Right.ApprovalId) And
    (Left.ApprovalTool = Right.ApprovalTool) And SameItems(Left.Items, Right.Items);
End;

Procedure ApplyApproval(Snap: TMonitorSnapshot);
Var
  Notice: TAssistantApprovalNotice;
Begin
  Notice := CurrentAssistantApproval;
  Snap.ApprovalActive := Notice.Active;
  Snap.ApprovalId := Notice.ToolId;
  Snap.ApprovalTool := Notice.ToolName;
End;

Procedure TMonitorSnapshotPublisher.NoteChange;
Var
  NowTick, Soon, Backstop: QWord;
Begin
  NowTick := GetTickCount64;
  EnterCriticalSection(Lock);
  Try
    Dirty := True;
    If Not CoalesceOpen Then
      Begin
        CoalesceOpen := True;
        FirstDirty := NowTick;
      End;
    Soon := NowTick + MonitorSnapshotDelayMs;
    Backstop := FirstDirty + MonitorSnapshotBackstopMs;
    If Soon < Backstop Then
      DueAt := Soon
    Else
      DueAt := Backstop;
  Finally
    LeaveCriticalSection(Lock);
  End;
  RTLEventSetEvent(WakeEvent);
End;

Procedure TMonitorSnapshotPublisher.Hear(Kind: TAssistantSessionNoticeKind);
Begin
  NoteChange;
End;

Procedure TMonitorSnapshotPublisher.Wake;
Begin
  NoteChange;
End;

Function TMonitorSnapshotPublisher.DueNow: Boolean;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := Dirty And (GetTickCount64 >= DueAt);
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TMonitorSnapshotPublisher.NextWaitMs: Integer;
Var
  NowTick: QWord;
Begin
  EnterCriticalSection(Lock);
  Try
    If Not Dirty Then
      Result := 200
    Else
      Begin
        NowTick := GetTickCount64;
        If NowTick >= DueAt Then
          Result := 0
        Else If DueAt - NowTick > 1000 Then
          Result := 1000
        Else
          Result := Integer(DueAt - NowTick);
      End;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Procedure TMonitorSnapshotPublisher.Publish(Snap: TMonitorSnapshot);
Var
  Previous: TMonitorSnapshot;
Begin
  Previous := Nil;
  EnterCriticalSection(Lock);
  Try
    Previous := PublishedSnap;
    PublishedSnap := Snap;
  Finally
    LeaveCriticalSection(Lock);
  End;
  If Assigned(Previous) Then
    Previous.Release;
  If Assigned(PublishWake) Then
    PublishWake;
End;

Procedure SetMonitorPublishWake(Wake: TProcedure);
Begin
  PublishWake := Wake;
End;

Procedure TMonitorSnapshotPublisher.Build;
Var
  Again: Boolean;
  Next, Current: TMonitorSnapshot;
  NextRev: Int64;
Begin
  If Not Assigned(Source) Then
    Exit;
  Repeat
    EnterCriticalSection(Lock);
    Try
      Dirty := False;
      CoalesceOpen := False;
      Building := True;
    Finally
      LeaveCriticalSection(Lock);
    End;
    Next := TMonitorSnapshot.Create;
    Try
      Source.Fill(Next);
      ApplyApproval(Next);
    Except
      On E: Exception Do
        Begin
          WorkflowLogger.Warning('AssistantMonitor', 'snapshot build failed: ' + E.Message);
          Next.Release;
          Next := Nil;
        End;
    End;
    If Assigned(Next) Then
      Current := PublishedMonitorSnapshot
    Else
      Current := Nil;
    Try
      If Assigned(Next) And SameSnapshot(Current, Next) Then
        Next.Release
      Else If Assigned(Next) Then
        Begin
          EnterCriticalSection(Lock);
          Try
            If Assigned(PublishedSnap) Then
              NextRev := PublishedSnap.Rev + 1
            Else
              NextRev := 1;
          Finally
            LeaveCriticalSection(Lock);
          End;
          Next.Rev := NextRev;
          Publish(Next);
        End;
    Finally
      If Assigned(Current) Then
        Current.Release;
    End;
    EnterCriticalSection(Lock);
    Try
      Again := Dirty;
      If Not Again Then
        Building := False;
    Finally
      LeaveCriticalSection(Lock);
    End;
  Until Not Again;
End;

Procedure TSnapshotScheduler.Execute;
Begin
  While Not Terminated Do
    Begin
      RTLEventWaitFor(Publisher.WakeEvent, Publisher.NextWaitMs);
      RTLEventResetEvent(Publisher.WakeEvent);
      If Terminated Then
        Exit;
      If Publisher.DueNow Then
        Synchronize(@Publisher.Build);
    End;
End;

Function MonitorSnapshotRunning: Boolean;
Begin
  Result := Assigned(Publisher);
End;

Function PublishedMonitorSnapshot: TMonitorSnapshot;
Begin
  Result := Nil;
  If Not Assigned(Publisher) Then
    Exit;
  EnterCriticalSection(Publisher.Lock);
  Try
    Result := Publisher.PublishedSnap;
    If Assigned(Result) Then
      Result.Retain;
  Finally
    LeaveCriticalSection(Publisher.Lock);
  End;
End;

Function MonitorSnapshotRev: Int64;
Var
  Snap: TMonitorSnapshot;
Begin
  Snap := PublishedMonitorSnapshot;
  If Assigned(Snap) Then
    Begin
      Result := Snap.Rev;
      Snap.Release;
    End
  Else
    Result := 0;
End;

Procedure StartMonitorSnapshot(Source: TMonitorSnapshotSource);
Begin
  If Assigned(Publisher) Then
    Begin
      Source.Free;
      Exit;
    End;
  { AnsiString reference counts are atomic only when this is set. }
  IsMultiThread := True;
  Publisher := TMonitorSnapshotPublisher.Create;
  InitCriticalSection(Publisher.Lock);
  Publisher.WakeEvent := RTLEventCreate;
  Publisher.Source := Source;
  SetAssistantMirrorWake(@Publisher.Wake);
  SetAssistantSessionListener(@Publisher.Hear);
  Publisher.Scheduler := TSnapshotScheduler.Create(False);
End;

Procedure StopMonitorSnapshot;
Var
  Snap: TMonitorSnapshot;
  Scheduler: TSnapshotScheduler;
Begin
  If Not Assigned(Publisher) Then
    Exit;
  If Publisher.Stopping Then
    Exit;
  Publisher.Stopping := True;
  SetAssistantMirrorWake(Nil);
  SetAssistantSessionListener(Nil);
  Publisher.Scheduler.Terminate;
  RTLEventSetEvent(Publisher.WakeEvent);
  Scheduler := Publisher.Scheduler;
  While Not Scheduler.Finished Do
    CheckSynchronize(10);
  Scheduler.WaitFor;
  Scheduler.Free;
  EnterCriticalSection(Publisher.Lock);
  Try
    Snap := Publisher.PublishedSnap;
    Publisher.PublishedSnap := Nil;
  Finally
    LeaveCriticalSection(Publisher.Lock);
  End;
  If Assigned(Snap) Then
    Snap.Release;
  RTLEventDestroy(Publisher.WakeEvent);
  DoneCriticalSection(Publisher.Lock);
  Publisher.Source.Free;
  Publisher.Free;
  Publisher := Nil;
End;

End.
