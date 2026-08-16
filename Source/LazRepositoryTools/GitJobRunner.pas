Unit GitJobRunner;

{ Shared cancellable background Git job queue (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, GitService;

Const
  GitJobDefaultTimeoutMs = 0; { 0 = no timeout }
  GitJobMaxQueue = 32;

Type
  TGitJobKind = (
    gjkNone,
    gjkFetch,
    gjkPull,
    gjkPush,
    gjkCommit,
    gjkCheckout,
    gjkCreateBranch,
    gjkClone,
    gjkInit,
    gjkStagePaths,
    gjkUnstagePaths,
    gjkRevertPaths,
    gjkAppendIgnore,
    gjkApplyPatch,
    gjkListStatus,
    gjkRepoProbe,
    gjkSuggestMessage
  );

  TGitJob = Class;

  TGitJobFinishedEvent = Procedure(Job: TGitJob) Of Object;

  TGitJob = Class
  Private
    FKind: TGitJobKind;
    FId: Integer;
    FRepoPath: String;
    FCaption: String;
    FMessageText: String;
    FRefName: String;
    FUrl: String;
    FTargetDir: String;
    FPaths: TStringList;
    FOwnsPaths: Boolean;
    FTimeoutMs: Integer;
    FTag: PtrInt;
    FOnFinished: TGitJobFinishedEvent;
    FOk: Boolean;
    FCancelled: Boolean;
    FErrorText: String;
    FResultSha: String;
    FTransfer: TGitTransferSummary;
    FStatusEntries: TGitStatusEntryArray;
    FIncludeUntracked: Boolean;
    FIncludeIgnored: Boolean;
    FQuiet: Boolean;
    FProbeBranch: String;
    FProbeDigest: String;
    FIndexText: String;
    FDetailsText: String;
    FIndexOk: Boolean;
    FDetailsOk: Boolean;
    FPatchText: String;
    FReversePatch: Boolean;
  Public
    Constructor Create(AKind: TGitJobKind);
    Destructor Destroy; Override;
    Procedure TakePaths(Paths: TStringList);
    Procedure CopyPathsFrom(Paths: TStrings);
    Property Kind: TGitJobKind Read FKind;
    Property Id: Integer Read FId Write FId;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
    Property Caption: String Read FCaption Write FCaption;
    Property MessageText: String Read FMessageText Write FMessageText;
    Property RefName: String Read FRefName Write FRefName;
    Property Url: String Read FUrl Write FUrl;
    Property TargetDir: String Read FTargetDir Write FTargetDir;
    Property Paths: TStringList Read FPaths;
    Property TimeoutMs: Integer Read FTimeoutMs Write FTimeoutMs;
    Property Tag: PtrInt Read FTag Write FTag;
    Property OnFinished: TGitJobFinishedEvent Read FOnFinished Write FOnFinished;
    Property Ok: Boolean Read FOk;
    Property Cancelled: Boolean Read FCancelled;
    Property ErrorText: String Read FErrorText;
    Property ResultSha: String Read FResultSha;
    Property Transfer: TGitTransferSummary Read FTransfer;
    Property StatusEntries: TGitStatusEntryArray Read FStatusEntries;
    Property IncludeUntracked: Boolean Read FIncludeUntracked Write FIncludeUntracked;
    Property IncludeIgnored: Boolean Read FIncludeIgnored Write FIncludeIgnored;
    { Quiet jobs skip the busy cursor / footer so auto-refresh does not steal the UI. }
    Property Quiet: Boolean Read FQuiet Write FQuiet;
    Property ProbeBranch: String Read FProbeBranch;
    Property ProbeDigest: String Read FProbeDigest;
    Property IndexText: String Read FIndexText;
    Property DetailsText: String Read FDetailsText;
    Property IndexOk: Boolean Read FIndexOk;
    Property DetailsOk: Boolean Read FDetailsOk;
    Property PatchText: String Read FPatchText Write FPatchText;
    Property ReversePatch: Boolean Read FReversePatch Write FReversePatch;
  End;

  TGitJobBusyEvent = Procedure(Sender: TObject; IsBusy: Boolean; Const Caption: String) Of Object;

  TGitJobRunner = Class
  Private
    FLock: TRTLCriticalSection;
    FQueue: TFPList;
    FCurrent: TGitJob;
    FWorker: TThread;
    FWake: PRTLEvent;
    FStopping: Boolean;
    FNextId: Integer;
    FBusy: Boolean;
    FCurrentCaption: String;
    FActiveGit: TGitService;
    FOnBusyChanged: TGitJobBusyEvent;
    FDeliverQueue: TFPList;
    FNotifyBusy: Boolean;
    FNotifyCaption: String;
    Procedure EnterLock;
    Procedure LeaveLock;
    Procedure WakeWorker;
    Procedure QueueBusyNotify(IsBusy: Boolean; Const Caption: String);
    Procedure DoBusyNotify;
    Procedure QueueFinished(Job: TGitJob);
    Procedure DoFinishedNotify;
    Function DequeueJob: TGitJob;
    Procedure ExecuteJob(Job: TGitJob; Git: TGitService);
    Function QueueCountLocked: Integer;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Enqueue a job. Ownership transfers to the runner; Job is freed after OnFinished. }
    Function Submit(Job: TGitJob): Boolean;
    Procedure CancelCurrent;
    { Nil OnFinished on queued/current/delivered jobs that still point at Handler. }
    Procedure DetachFinishedHandler(Handler: TGitJobFinishedEvent);
    { Cancel only if the running job's OnFinished is Handler. }
    Procedure CancelIfHandler(Handler: TGitJobFinishedEvent);
    Function Busy: Boolean;
    Function CurrentCaption: String;
    Function QueueLength: Integer;
    Property OnBusyChanged: TGitJobBusyEvent Read FOnBusyChanged Write FOnBusyChanged;
  End;

Function GitJobs: TGitJobRunner;
Function GitJobKindCaption(Kind: TGitJobKind): String;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GitGraphModel;

Type
  TGitJobWorker = Class(TThread)
  Private
    FRunner: TGitJobRunner;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(ARunner: TGitJobRunner);
  End;

Var
  GlobalGitJobs: TGitJobRunner = Nil;

Function GitJobKindCaption(Kind: TGitJobKind): String;
Begin
  Case Kind Of
    gjkFetch: Result := 'Fetching…';
    gjkPull: Result := 'Pulling…';
    gjkPush: Result := 'Pushing…';
    gjkCommit: Result := 'Committing…';
    gjkCheckout: Result := 'Checking out…';
    gjkCreateBranch: Result := 'Creating branch…';
    gjkClone: Result := 'Cloning…';
    gjkInit: Result := 'Initialising repository…';
    gjkStagePaths: Result := 'Staging…';
    gjkUnstagePaths: Result := 'Unstaging…';
    gjkRevertPaths: Result := 'Reverting…';
    gjkAppendIgnore: Result := 'Updating ignore list…';
    gjkApplyPatch: Result := 'Applying selection…';
    gjkListStatus: Result := 'Refreshing files…';
    gjkRepoProbe: Result := 'Checking repository…';
    gjkSuggestMessage: Result := 'Suggesting commit message…';
  Else
    Result := 'Working…';
  End;
End;

Constructor TGitJob.Create(AKind: TGitJobKind);
Begin
  Inherited Create;
  FKind := AKind;
  FId := 0;
  FRepoPath := '';
  FCaption := GitJobKindCaption(AKind);
  FMessageText := '';
  FRefName := '';
  FUrl := '';
  FTargetDir := '';
  FPaths := Nil;
  FOwnsPaths := False;
  FTimeoutMs := GitJobDefaultTimeoutMs;
  FTag := 0;
  FOnFinished := Nil;
  FOk := False;
  FCancelled := False;
  FErrorText := '';
  FResultSha := '';
  FillChar(FTransfer, SizeOf(FTransfer), 0);
  SetLength(FStatusEntries, 0);
  FIncludeUntracked := False;
  FIncludeIgnored := False;
  FQuiet := False;
  FProbeBranch := '';
  FProbeDigest := '';
  FIndexText := '';
  FDetailsText := '';
  FIndexOk := False;
  FDetailsOk := False;
  FPatchText := '';
  FReversePatch := False;
End;

Destructor TGitJob.Destroy;
Begin
  If FOwnsPaths Then
    FreeAndNil(FPaths)
  Else
    FPaths := Nil;
  Inherited Destroy;
End;

Procedure TGitJob.TakePaths(Paths: TStringList);
Begin
  If FOwnsPaths Then
    FreeAndNil(FPaths);
  FPaths := Paths;
  FOwnsPaths := Assigned(Paths);
End;

Procedure TGitJob.CopyPathsFrom(Paths: TStrings);
Var
  List: TStringList;
  I: Integer;
Begin
  List := TStringList.Create;
  If Assigned(Paths) Then
    For I := 0 To Paths.Count - 1 Do
      List.Add(Paths[I]);
  TakePaths(List);
End;

Constructor TGitJobWorker.Create(ARunner: TGitJobRunner);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FRunner := ARunner;
End;

Procedure TGitJobWorker.Execute;
Var
  Job: TGitJob;
  Git: TGitService;
  StartTick: QWord;
  TimedOut: Boolean;
  StillQueued: Boolean;
Begin
  Git := TGitService.Create;
  { Never publish WorkflowEventBus from a worker — listeners update LCL UI. }
  Git.PublishEvents := False;
  Try
    While Not Terminated Do
      Begin
        Job := FRunner.DequeueJob;
        If Not Assigned(Job) Then
          Begin
            If Terminated Then
              Break;
            RTLeventWaitFor(FRunner.FWake, 500);
            Continue;
          End;

        FRunner.EnterLock;
        Try
          FRunner.FCurrent := Job;
          FRunner.FActiveGit := Git;
        Finally
          FRunner.LeaveLock;
        End;

        If Not Job.Quiet Then
          FRunner.QueueBusyNotify(True, Job.Caption);
        Git.ResetCancel;
        Git.TimeoutMs := Job.TimeoutMs;
        Git.RepoPath := Job.RepoPath;
        Job.FOk := False;
        Job.FCancelled := False;
        Job.FErrorText := '';
        StartTick := GetTickCount64;
        TimedOut := False;

        Try
          FRunner.ExecuteJob(Job, Git);
          If (Job.TimeoutMs > 0) And ((GetTickCount64 - StartTick) >= QWord(Job.TimeoutMs)) Then
            TimedOut := True;
          If Git.Cancelled Or TimedOut Or Job.FCancelled Then
            Begin
              Job.FCancelled := True;
              Job.FOk := False;
              If TimedOut And (Job.FErrorText = '') Then
                Job.FErrorText := 'Timed out'
              Else If Job.FErrorText = '' Then
                Job.FErrorText := 'Cancelled';
            End
          Else If Not Job.FOk And (Job.FErrorText = '') Then
            Job.FErrorText := Git.LastError;
        Except
          On E: Exception Do
            Begin
              Job.FOk := False;
              Job.FErrorText := E.Message;
              WorkflowLogger.Error('GitJobRunner', Job.Caption + ': ' + E.Message);
            End;
        End;

        FRunner.EnterLock;
        Try
          FRunner.FCurrent := Nil;
          FRunner.FActiveGit := Nil;
          StillQueued := FRunner.QueueCountLocked > 0;
        Finally
          FRunner.LeaveLock;
        End;

        If Not Job.Quiet Then
          If StillQueued Then
            FRunner.QueueBusyNotify(True, Job.Caption)
          Else
            FRunner.QueueBusyNotify(False, '');
        FRunner.QueueFinished(Job);
      End;
  Finally
    Git.Free;
  End;
End;

Constructor TGitJobRunner.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FQueue := TFPList.Create;
  FCurrent := Nil;
  FActiveGit := Nil;
  FWake := RTLEventCreate;
  FStopping := False;
  FNextId := 1;
  FBusy := False;
  FCurrentCaption := '';
  FOnBusyChanged := Nil;
  FDeliverQueue := TFPList.Create;
  FWorker := TGitJobWorker.Create(Self);
  FWorker.Start;
End;

Destructor TGitJobRunner.Destroy;
Var
  I: Integer;
  Job: TGitJob;
Begin
  FStopping := True;
  CancelCurrent;
  If Assigned(FWorker) Then
    Begin
      FWorker.Terminate;
      RTLeventSetEvent(FWake);
      FWorker.WaitFor;
      TThread.RemoveQueuedEvents(FWorker);
      FreeAndNil(FWorker);
    End;
  EnterLock;
  Try
    For I := 0 To FQueue.Count - 1 Do
      Begin
        Job := TGitJob(FQueue[I]);
        FreeAndNil(Job);
      End;
    FQueue.Clear;
    For I := 0 To FDeliverQueue.Count - 1 Do
      Begin
        Job := TGitJob(FDeliverQueue[I]);
        FreeAndNil(Job);
      End;
    FDeliverQueue.Clear;
  Finally
    LeaveLock;
  End;
  FreeAndNil(FQueue);
  FreeAndNil(FDeliverQueue);
  RTLeventDestroy(FWake);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TGitJobRunner.EnterLock;
Begin
  EnterCriticalSection(FLock);
End;

Procedure TGitJobRunner.LeaveLock;
Begin
  LeaveCriticalSection(FLock);
End;

Procedure TGitJobRunner.WakeWorker;
Begin
  RTLeventSetEvent(FWake);
End;

Function TGitJobRunner.QueueCountLocked: Integer;
Begin
  Result := FQueue.Count;
End;

Procedure TGitJobRunner.QueueBusyNotify(IsBusy: Boolean; Const Caption: String);
Begin
  EnterLock;
  Try
    FBusy := IsBusy;
    If IsBusy Then
      FCurrentCaption := Caption
    Else
      FCurrentCaption := '';
    FNotifyBusy := IsBusy;
    FNotifyCaption := Caption;
  Finally
    LeaveLock;
  End;
  If Assigned(FWorker) Then
    TThread.Queue(FWorker, @DoBusyNotify);
End;

Procedure TGitJobRunner.DoBusyNotify;
Var
  IsBusy: Boolean;
  Caption: String;
  Handler: TGitJobBusyEvent;
Begin
  EnterLock;
  Try
    IsBusy := FNotifyBusy;
    Caption := FNotifyCaption;
    Handler := FOnBusyChanged;
  Finally
    LeaveLock;
  End;
  If Assigned(Handler) Then
    Handler(Self, IsBusy, Caption);
End;

Procedure TGitJobRunner.QueueFinished(Job: TGitJob);
Begin
  EnterLock;
  Try
    FDeliverQueue.Add(Job);
  Finally
    LeaveLock;
  End;
  If Assigned(FWorker) Then
    TThread.Queue(FWorker, @DoFinishedNotify);
End;

Procedure TGitJobRunner.DoFinishedNotify;
Var
  Job: TGitJob;
Begin
  Repeat
    Job := Nil;
    EnterLock;
    Try
      If FDeliverQueue.Count > 0 Then
        Begin
          Job := TGitJob(FDeliverQueue[0]);
          FDeliverQueue.Delete(0);
        End;
    Finally
      LeaveLock;
    End;
    If Not Assigned(Job) Then
      Break;
    Try
      If Assigned(Job.OnFinished) Then
        Job.OnFinished(Job);
    Except
      On E: Exception Do
        WorkflowLogger.Error('GitJobRunner', 'OnFinished: ' + E.Message);
    End;
    FreeAndNil(Job);
  Until False;
End;

Function TGitJobRunner.DequeueJob: TGitJob;
Begin
  Result := Nil;
  EnterLock;
  Try
    If FStopping Then
      Exit;
    If FQueue.Count > 0 Then
      Begin
        Result := TGitJob(FQueue[0]);
        FQueue.Delete(0);
      End;
  Finally
    LeaveLock;
  End;
End;

Procedure TGitJobRunner.ExecuteJob(Job: TGitJob; Git: TGitService);
Var
  Summary: TGitTransferSummary;
  NewSha, DiffText, StatusText, Suggested, ErrorText: String;
  Entries: TGitStatusEntryArray;
Begin
  Case Job.Kind Of
    gjkFetch:
      Begin
        Job.FOk := Git.Fetch(Summary);
        Job.FTransfer := Summary;
        Job.FErrorText := Summary.Message;
        If Job.FOk Then
          Job.FIndexOk := Git.FetchHistoryPreview(Job.RepoPath, GitGraphDetailBatch, Job.FIndexText,
            Job.FDetailsText, Job.FDetailsOk);
      End;
    gjkPull:
      Begin
        Job.FOk := Git.Pull(Summary);
        Job.FTransfer := Summary;
        Job.FErrorText := Summary.Message;
        If Job.FOk Then
          Job.FIndexOk := Git.FetchHistoryPreview(Job.RepoPath, GitGraphDetailBatch, Job.FIndexText,
            Job.FDetailsText, Job.FDetailsOk);
      End;
    gjkPush:
      Begin
        Job.FOk := Git.Push(Summary);
        Job.FTransfer := Summary;
        Job.FErrorText := Summary.Message;
      End;
    gjkCommit:
      Begin
        Job.FOk := Git.Commit(Job.MessageText, NewSha);
        Job.FResultSha := NewSha;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkCheckout:
      Begin
        Job.FOk := Git.Checkout(Job.RefName);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkCreateBranch:
      Begin
        Job.FOk := Git.CreateBranch(Job.MessageText, Job.RefName);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkClone:
      Begin
        Job.FOk := Git.CloneRepository(Job.Url, Job.TargetDir);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkInit:
      Begin
        Job.FOk := Git.InitRepository(Job.TargetDir);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkStagePaths:
      Begin
        Job.FOk := Assigned(Job.Paths) And (Job.Paths.Count > 0) And Git.StagePaths(Job.Paths);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkUnstagePaths:
      Begin
        Job.FOk := Assigned(Job.Paths) And (Job.Paths.Count > 0) And Git.UnstagePaths(Job.Paths);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkRevertPaths:
      Begin
        Job.FOk := Assigned(Job.Paths) And (Job.Paths.Count > 0) And Git.RevertPaths(Job.Paths);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkAppendIgnore:
      Begin
        Job.FOk := Assigned(Job.Paths) And (Job.Paths.Count > 0) And Git.AppendIgnorePatterns(Job.Paths);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkApplyPatch:
      Begin
        Job.FOk := Git.ApplyPatchToIndex(Job.PatchText, Job.ReversePatch);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkListStatus:
      Begin
        Job.FOk := Git.ListStatus(Entries, Job.IncludeUntracked, Job.IncludeIgnored);
        If Job.FOk Then
          Job.FStatusEntries := Entries
        Else
          Job.FErrorText := Git.LastError;
      End;
    gjkRepoProbe:
      Begin
        Job.FOk := Git.ProbeRepository(NewSha, Job.FProbeBranch, Job.FProbeDigest);
        Job.FResultSha := NewSha;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkSuggestMessage:
      Begin
        Job.FOk := False;
        If Not Assigned(SuggestCommitMessageFunc) Then
          Job.FErrorText := 'Commit message suggestion is not available.'
        Else If Not Git.DiffStaged(DiffText) Then
          Job.FErrorText := Git.LastError
        Else If Trim(DiffText) = '' Then
          Job.FErrorText := 'Staged diff is empty. Stage file contents (not only renames without content) and try again.'
        Else
          Begin
            Git.StatusSummaryForCommit(StatusText);
            Job.FOk := SuggestCommitMessageFunc(DiffText, StatusText, Suggested, ErrorText);
            If Job.FOk Then
              Job.FMessageText := Suggested
            Else If ErrorText <> '' Then
              Job.FErrorText := ErrorText
            Else
              Job.FErrorText := 'Could not generate a commit message.';
          End;
      End;
  Else
    Begin
      Job.FOk := False;
      Job.FErrorText := 'Unknown job kind';
    End;
  End;
End;

Function TGitJobRunner.Submit(Job: TGitJob): Boolean;
Var
  Reject: TGitJob;
Begin
  Result := False;
  Reject := Nil;
  If Not Assigned(Job) Then
    Exit;
  If FStopping Then
    Begin
      FreeAndNil(Job);
      Exit;
    End;
  EnterLock;
  Try
    If FQueue.Count >= GitJobMaxQueue Then
      Begin
        Reject := Job;
        Job := Nil;
      End
    Else
      Begin
        Job.FId := FNextId;
        Inc(FNextId);
        If Job.FCaption = '' Then
          Job.FCaption := GitJobKindCaption(Job.Kind);
        FQueue.Add(Job);
        Result := True;
      End;
  Finally
    LeaveLock;
  End;
  If Assigned(Reject) Then
    Begin
      Reject.Free;
      Exit;
    End;
  If Result Then
    Begin
      If Not Job.Quiet Then
        QueueBusyNotify(True, Job.Caption);
      WakeWorker;
    End;
End;

Function SameFinishedHandler(Const Left, Right: TGitJobFinishedEvent): Boolean;
Begin
  Result := (TMethod(Left).Code = TMethod(Right).Code) And (TMethod(Left).Data = TMethod(Right).Data);
End;

Procedure TGitJobRunner.DetachFinishedHandler(Handler: TGitJobFinishedEvent);
Var
  I: Integer;
  Job: TGitJob;
Begin
  EnterLock;
  Try
    If Assigned(FCurrent) And SameFinishedHandler(FCurrent.OnFinished, Handler) Then
      FCurrent.OnFinished := Nil;
    For I := 0 To FQueue.Count - 1 Do
      Begin
        Job := TGitJob(FQueue[I]);
        If Assigned(Job) And SameFinishedHandler(Job.OnFinished, Handler) Then
          Job.OnFinished := Nil;
      End;
    For I := 0 To FDeliverQueue.Count - 1 Do
      Begin
        Job := TGitJob(FDeliverQueue[I]);
        If Assigned(Job) And SameFinishedHandler(Job.OnFinished, Handler) Then
          Job.OnFinished := Nil;
      End;
  Finally
    LeaveLock;
  End;
End;

Procedure TGitJobRunner.CancelIfHandler(Handler: TGitJobFinishedEvent);
Var
  Job: TGitJob;
Begin
  Job := Nil;
  EnterLock;
  Try
    Job := FCurrent;
  Finally
    LeaveLock;
  End;
  If Assigned(Job) And SameFinishedHandler(Job.OnFinished, Handler) Then
    CancelCurrent;
End;

Procedure TGitJobRunner.CancelCurrent;
Var
  Git: TGitService;
  Job: TGitJob;
Begin
  EnterLock;
  Try
    Job := FCurrent;
    Git := FActiveGit;
    If Assigned(Job) Then
      Job.FCancelled := True;
  Finally
    LeaveLock;
  End;
  If Assigned(Git) Then
    Git.Cancel;
End;

Function TGitJobRunner.Busy: Boolean;
Begin
  EnterLock;
  Try
    Result := FBusy Or (FQueue.Count > 0) Or Assigned(FCurrent);
  Finally
    LeaveLock;
  End;
End;

Function TGitJobRunner.CurrentCaption: String;
Begin
  EnterLock;
  Try
    Result := FCurrentCaption;
  Finally
    LeaveLock;
  End;
End;

Function TGitJobRunner.QueueLength: Integer;
Begin
  EnterLock;
  Try
    Result := FQueue.Count;
  Finally
    LeaveLock;
  End;
End;

Function GitJobs: TGitJobRunner;
Begin
  Result := GlobalGitJobs;
End;

Initialization

GlobalGitJobs := TGitJobRunner.Create;

Finalization

FreeAndNil(GlobalGitJobs);

End.
