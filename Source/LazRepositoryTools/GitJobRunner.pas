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
    gjkSuggestMessage,
    gjkIndexHistory,
    gjkFetchDetails,
    gjkCommitPaths,
    gjkFilePreview,
    gjkRepositoryFiles,
    gjkPathCommits,
    gjkCommitFile,
    gjkPrepareAmend,
    gjkRemoveLastCommit
  );

  TGitJob = Class;

  TGitJobFinishedEvent = Procedure(Job: TGitJob) Of Object;

  TGitJob = Class
  Private
    FPreviewPath, FPreviewSha, FPreviewText: String;
    FPreviewStaged, FPreviewPlain, FPreviewReadBytes, FPreviewBinary: Boolean;
    FPreviewBytes: TMemoryStream;
    FKind: TGitJobKind;
    FId: Integer;
    FRepoPath: String;
    FCaption: String;
    FCommitMessage: String;
    FBranchName: String;
    FRefName: String;
    FUrl: String;
    FTargetDir: String;
    FPaths: TStringList;
    FTimeoutMs: Integer;
    FTag: PtrInt;
    FRepoGeneration: QWord;
    FPushAfterCommit: Boolean;
    FOnFinished: TGitJobFinishedEvent;
    FOk: Boolean;
    FCancelled: Boolean;
    FErrorText: String;
    FResultSha: String;
    FTransfer: TGitTransferSummary;
    FStatusEntries: TGitStatusEntryArray;
    FTrackedFiles: TStringList;
    FIncludeClean: Boolean;
    FGitDir, FRefsDigest: String;
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
    FAmendCommit: Boolean;
    FHeadPushed: Boolean;
    FHeadPushedKnown: Boolean;
  Public
    Constructor Create(AKind: TGitJobKind);
    Destructor Destroy; Override;
    Function MatchesRepository(Const Path: String; Generation: QWord): Boolean;
    { A follow-up copies its originating repository and callback context. }
    Function CreatePushFollowup: TGitJob;
    Procedure TakePaths(Paths: TStringList);
    Procedure CopyPathsFrom(Paths: TStrings);
    Property PreviewPath: String Read FPreviewPath Write FPreviewPath;
    Property PreviewSha: String Read FPreviewSha Write FPreviewSha;
    Property PreviewStaged: Boolean Read FPreviewStaged Write FPreviewStaged;
    Property PreviewReadBytes: Boolean Read FPreviewReadBytes Write FPreviewReadBytes;
    Property PreviewPlain: Boolean Read FPreviewPlain;
    Property PreviewBinary: Boolean Read FPreviewBinary;
    Property PreviewText: String Read FPreviewText;
    Property PreviewBytes: TMemoryStream Read FPreviewBytes;
    Property Kind: TGitJobKind Read FKind;
    Property Id: Integer Read FId Write FId;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
    Property Caption: String Read FCaption Write FCaption;
    Property CommitMessage: String Read FCommitMessage Write FCommitMessage;
    Property BranchName: String Read FBranchName Write FBranchName;
    Property RefName: String Read FRefName Write FRefName;
    Property Url: String Read FUrl Write FUrl;
    Property TargetDir: String Read FTargetDir Write FTargetDir;
    Property Paths: TStringList Read FPaths;
    Property TimeoutMs: Integer Read FTimeoutMs Write FTimeoutMs;
    Property Tag: PtrInt Read FTag Write FTag;
    Property RepoGeneration: QWord Read FRepoGeneration Write FRepoGeneration;
    Property PushAfterCommit: Boolean Read FPushAfterCommit Write FPushAfterCommit;
    Property OnFinished: TGitJobFinishedEvent Read FOnFinished Write FOnFinished;
    Property Ok: Boolean Read FOk;
    Property Cancelled: Boolean Read FCancelled;
    Property ErrorText: String Read FErrorText;
    Property ResultSha: String Read FResultSha;
    Property Transfer: TGitTransferSummary Read FTransfer;
    Property StatusEntries: TGitStatusEntryArray Read FStatusEntries;
    Property TrackedFiles: TStringList Read FTrackedFiles;
    Property IncludeClean: Boolean Read FIncludeClean Write FIncludeClean;
    Property RefsDigest: String Read FRefsDigest;
    Property GitDir: String Read FGitDir;
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
    Property AmendCommit: Boolean Read FAmendCommit Write FAmendCommit;
    Property HeadPushed: Boolean Read FHeadPushed Write FHeadPushed;
    Property HeadPushedKnown: Boolean Read FHeadPushedKnown Write FHeadPushedKnown;
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
    Procedure EnterLock;
    Procedure LeaveLock;
    Procedure WakeWorker;
    Procedure QueueBusyNotify(IsBusy: Boolean; Const Caption: String);
    Procedure QueueBusyCallback;
    Procedure DoBusyNotify;
    Procedure QueueFinished(Job: TGitJob);
    Procedure DoFinishedNotify;
    Function DequeueJob(Git: TGitService): TGitJob;
    Procedure ExecuteJob(Job: TGitJob; Git: TGitService);
    Function NonQuietQueuedLocked: Boolean;
    Function FirstNonQuietCaptionLocked: String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Enqueue a job. Ownership transfers to the runner; Job is freed after OnFinished. }
    Function Submit(Job: TGitJob): Boolean;
    Procedure CancelCurrent;
    { Call on the main thread, like completion callbacks and UI destruction.
      Nil OnFinished on queued/current/delivered jobs that point at Handler. }
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
  WorkflowLog, WorkflowEvents, GitGraphModel, LazFileUtils;

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
    gjkListStatus: Result := 'Refreshing changes…';
    gjkRepoProbe: Result := 'Checking repository…';
    gjkSuggestMessage: Result := 'Suggesting commit message…';
    gjkIndexHistory: Result := 'Indexing…';
    gjkFetchDetails: Result := 'Loading commit details…';
    gjkRepositoryFiles: Result := 'Listing files…';
    gjkPathCommits: Result := 'Listing commits…';
    gjkCommitFile: Result := 'Loading file…';
    gjkPrepareAmend: Result := 'Preparing amend…';
    gjkRemoveLastCommit: Result := 'Removing commit…';
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
  FCommitMessage := '';
  FBranchName := '';
  FRefName := '';
  FUrl := '';
  FTargetDir := '';
  FPaths := Nil;
  FTimeoutMs := GitJobDefaultTimeoutMs;
  FTag := 0;
  FRepoGeneration := 0;
  FPushAfterCommit := False;
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
  FAmendCommit := False;
  FHeadPushed := True;
  FHeadPushedKnown := False;
  FPreviewBinary := False;
End;

Destructor TGitJob.Destroy;
Begin
  FreeAndNil(FPaths);
  FreeAndNil(FTrackedFiles);
  FreeAndNil(FPreviewBytes);
  Inherited Destroy;
End;

Function TGitJob.MatchesRepository(Const Path: String; Generation: QWord): Boolean;
Begin
  Result := (FRepoGeneration = Generation) And (FRepoPath <> '') And (Path <> '') And
    (CompareFilenames(ExcludeTrailingPathDelimiter(ExpandFileName(FRepoPath)),
      ExcludeTrailingPathDelimiter(ExpandFileName(Path))) = 0);
End;

Function TGitJob.CreatePushFollowup: TGitJob;
Begin
  Result := Nil;
  If (FKind <> gjkCommit) Or Not FOk Or FCancelled Or Not FPushAfterCommit Then
    Exit;
  FPushAfterCommit := False;
  Result := TGitJob.Create(gjkPush);
  Result.RepoPath := FRepoPath;
  Result.RepoGeneration := FRepoGeneration;
  Result.OnFinished := FOnFinished;
End;

Procedure TGitJob.TakePaths(Paths: TStringList);
Begin
  If FPaths <> Paths Then
    Begin
      FreeAndNil(FPaths);
      FPaths := Paths;
    End;
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
Begin
  Git := TGitService.Create;
  { Never publish WorkflowEventBus from a worker — listeners update LCL UI. }
  Git.PublishEvents := False;
  Try
    While Not Terminated Do
      Begin
        Job := FRunner.DequeueJob(Git);
        If Not Assigned(Job) Then
          Begin
            If Terminated Then
              Break;
            RTLeventWaitFor(FRunner.FWake, 500);
            Continue;
          End;

        If Not Job.Quiet Then
          FRunner.QueueBusyNotify(True, Job.Caption);
        Job.FOk := False;
        Job.FErrorText := '';
        If Job.FCancelled Or FRunner.FStopping Or Terminated Then
          Begin
            Job.FCancelled := True;
            Job.FOk := False;
            Job.FErrorText := 'Cancelled';
          End
        Else
          Begin
            Git.TimeoutMs := Job.TimeoutMs;
            Git.RepoPath := Job.RepoPath;
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
          End;

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
  EnterLock;
  Try
    FStopping := True;
    FOnBusyChanged := Nil;
  Finally
    LeaveLock;
  End;
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

Function TGitJobRunner.NonQuietQueuedLocked: Boolean;
Var
  I: Integer;
  Job: TGitJob;
Begin
  Result := False;
  For I := 0 To FQueue.Count - 1 Do
    Begin
      Job := TGitJob(FQueue[I]);
      If Assigned(Job) And (Not Job.Quiet) Then
        Begin
          Result := True;
          Exit;
        End;
    End;
End;

Function TGitJobRunner.FirstNonQuietCaptionLocked: String;
Var
  I: Integer;
  Job: TGitJob;
Begin
  Result := '';
  For I := 0 To FQueue.Count - 1 Do
    Begin
      Job := TGitJob(FQueue[I]);
      If Assigned(Job) And (Not Job.Quiet) Then
        Begin
          Result := Job.Caption;
          Exit;
        End;
    End;
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
  Finally
    LeaveLock;
  End;
  QueueBusyCallback;
End;

Procedure TGitJobRunner.QueueBusyCallback;
Begin
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
    IsBusy := FBusy;
    Caption := FCurrentCaption;
    Handler := FOnBusyChanged;
  Finally
    LeaveLock;
  End;
  If Assigned(Handler) And Not FStopping Then
    Try
      Handler(Self, IsBusy, Caption);
    Except
      On E: Exception Do
        WorkflowLogger.Error('GitJobRunner', 'OnBusyChanged: ' + E.Message);
    End;
End;

Procedure TGitJobRunner.QueueFinished(Job: TGitJob);
Var
  NeedNotify: Boolean;
Begin
  EnterLock;
  Try
    FDeliverQueue.Add(Job);
    FCurrent := Nil;
    FActiveGit := Nil;
    If NonQuietQueuedLocked Then
      Begin
        FBusy := True;
        FCurrentCaption := FirstNonQuietCaptionLocked;
        NeedNotify := True;
      End
    Else If FBusy Or (Not Job.Quiet) Then
      Begin
        FBusy := False;
        FCurrentCaption := '';
        NeedNotify := True;
      End
    Else
      NeedNotify := False;
  Finally
    LeaveLock;
  End;

  If NeedNotify Then
    QueueBusyCallback;
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
      If Not FStopping And Assigned(Job.OnFinished) Then
        Job.OnFinished(Job);
    Except
      On E: Exception Do
        WorkflowLogger.Error('GitJobRunner', 'OnFinished: ' + E.Message);
    End;
    FreeAndNil(Job);
  Until False;
End;

Function TGitJobRunner.DequeueJob(Git: TGitService): TGitJob;
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
        { Publish ownership and reset cancellation atomically before a caller
          can cancel this job. Resetting later could lose a cancellation. }
        Git.ResetCancel;
        FCurrent := Result;
        FActiveGit := Git;
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
  Pushed: Boolean;
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
        If Job.FOk Then
          Job.FIndexOk := Git.FetchHistoryPreview(Job.RepoPath, GitGraphDetailBatch, Job.FIndexText,
            Job.FDetailsText, Job.FDetailsOk);
      End;
    gjkCommit:
      Begin
        Job.FOk := Git.Commit(Job.CommitMessage, NewSha, Job.AmendCommit);
        Job.FResultSha := NewSha;
        If Job.FOk Then Job.FOk := Git.RefDigest(Job.FRefsDigest);
        If Job.FOk Then Git.GetGitDir(Job.FGitDir);
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
        Job.FOk := Git.CreateBranch(Job.BranchName, Job.RefName);
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
    gjkCommitPaths:
      Begin
        Job.FOk := Git.ListCommitPaths(Job.PreviewSha, Job.FPaths);
        If Not Job.FOk Then Job.FErrorText := Git.LastError;
      End;
    gjkFilePreview:
      Begin
        If Job.PreviewReadBytes Then
          Begin
            Job.FPreviewBytes := TMemoryStream.Create;
            Job.FOk := Git.ReadBlobBytes(Job.PreviewSha, Job.PreviewPath, Job.PreviewStaged, Job.FPreviewBytes);
          End
        Else
          Begin
            If Job.PreviewSha <> '' Then
              Job.FOk := Git.ShowCommitPathDiff(Job.PreviewSha, Job.PreviewPath, Job.FPreviewText)
            Else Job.FOk := Git.DiffPath(Job.PreviewPath, Job.PreviewStaged, Job.FPreviewText);
            If Job.FOk And (Job.PreviewSha = '') And Not Job.PreviewStaged And (Job.FPreviewText = '') Then
              Begin
                Job.FPreviewPlain := True;
                Job.FOk := Git.ReadWorkingTreeFile(Job.PreviewPath, Job.FPreviewText);
              End;
          End;
        If Not Job.FOk Then Job.FErrorText := Git.LastError;
      End;
    gjkRepositoryFiles:
      Begin
        FreeAndNil(Job.FTrackedFiles);
        Job.FOk := Git.ListRepositoryFiles(Job.FTrackedFiles);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkPathCommits:
      Begin
        Job.FOk := Git.ListPathCommits(Job.PreviewPath, Job.FIndexText);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkCommitFile:
      Begin
        Job.FPreviewBinary := False;
        If Job.PreviewReadBytes Then
          Begin
            Job.FPreviewBytes := TMemoryStream.Create;
            Job.FOk := Git.ReadBlobBytes(Job.PreviewSha, Job.PreviewPath, False, Job.FPreviewBytes);
          End
        Else
          Job.FOk := Git.ReadCommitFileText(Job.PreviewSha, Job.PreviewPath, Job.FPreviewText, Job.FPreviewBinary);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkListStatus:
      Begin
        Job.FOk := Git.ListStatus(Entries, Job.IncludeUntracked, Job.IncludeIgnored);
        If Job.FOk Then
          Begin
            Job.FStatusEntries := Entries;
            If Job.IncludeClean Then Job.FOk := Git.ListTrackedFiles(Job.FTrackedFiles);
          End;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkRepoProbe:
      Begin
        Job.FOk := Git.ProbeRepository(NewSha, Job.FProbeBranch, Job.FProbeDigest);
        Job.FResultSha := NewSha;
        If Job.FOk Then Job.FOk := Git.RefDigest(Job.FRefsDigest);
        If Job.FOk Then Git.GetGitDir(Job.FGitDir);
        Job.FHeadPushedKnown := False;
        Job.FHeadPushed := True;
        If Job.FOk Then
          Begin
            If NewSha = '' Then
              Job.FHeadPushedKnown := True
            Else If Git.IsCommitPushed(NewSha, Pushed) Then
              Begin
                Job.FHeadPushedKnown := True;
                Job.FHeadPushed := Pushed;
              End;
          End;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkSuggestMessage:
      Begin
        Job.FOk := False;
        If Not SuggestCommitMessageAvailable Then
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
              Job.FCommitMessage := Suggested
            Else If ErrorText <> '' Then
              Job.FErrorText := ErrorText
            Else
              Job.FErrorText := 'Could not generate a commit message.';
          End;
      End;
    gjkIndexHistory:
      Begin
        Job.FIndexOk := Git.FetchRevListParents(Job.RepoPath, Job.FIndexText);
        Job.FOk := Job.FIndexOk;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkFetchDetails:
      Begin
        Job.FDetailsOk := Assigned(Job.Paths) And (Job.Paths.Count > 0) And
          Git.FetchCommitDetails(Job.RepoPath, Job.Paths, Job.FDetailsText);
        Job.FOk := Job.FDetailsOk;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkPrepareAmend:
      Begin
        Job.FAmendCommit := False;
        Job.FOk := Git.GetCommitMessage('HEAD', Job.FCommitMessage);
        If Job.FOk Then
          If Git.HeadHasParent Then
            Job.FOk := Git.ResetLastCommit(True)
          Else
            Job.FAmendCommit := True;
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
      End;
    gjkRemoveLastCommit:
      Begin
        Job.FOk := Git.ResetLastCommit(False);
        If Not Job.FOk Then
          Job.FErrorText := Git.LastError;
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
  NeedNotify: Boolean;
Begin
  Result := False;
  Reject := Nil;
  NeedNotify := False;
  If Not Assigned(Job) Then
    Exit;
  If FStopping Then
    Begin
      FreeAndNil(Job);
      Exit;
    End;
  EnterLock;
  Try
    If FStopping Or (FQueue.Count >= GitJobMaxQueue) Then
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
        If Not Job.Quiet Then
          Begin
            FBusy := True;
            FCurrentCaption := Job.Caption;
            NeedNotify := True;
          End;
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
  If NeedNotify Then
    QueueBusyCallback;
  If Result Then
    WakeWorker;
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
Begin
  EnterLock;
  Try
    If Assigned(FCurrent) And SameFinishedHandler(FCurrent.OnFinished, Handler) Then
      Begin
        FCurrent.FCancelled := True;
        If Assigned(FActiveGit) Then
          FActiveGit.Cancel;
      End;
  Finally
    LeaveLock;
  End;
End;

Procedure TGitJobRunner.CancelCurrent;
Begin
  EnterLock;
  Try
    If Assigned(FCurrent) Then
      FCurrent.FCancelled := True;
    { Keep the worker from advancing to another job or freeing Git mid-cancel. }
    If Assigned(FActiveGit) Then
      FActiveGit.Cancel;
  Finally
    LeaveLock;
  End;
End;

Function TGitJobRunner.Busy: Boolean;
Begin
  EnterLock;
  Try
    { Matches the footer/cursor flag: quiet probe/index/detail jobs are not busy. }
    Result := FBusy;
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
