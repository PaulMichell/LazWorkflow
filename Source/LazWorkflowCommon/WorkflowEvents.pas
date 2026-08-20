Unit WorkflowEvents;

{ Central event bus and observer interfaces for LazWorkflow packages (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
  {$MODESWITCH NESTEDPROCVARS}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  { Git-related events }
  TGitRepositoryState = (grsUnknown, grsClean, grsDirty, grsConflict, grsDetached);
  
  TGitCommitInfo = Record
    Sha: String;
    ShortSha: String;
    Summary: String;
    AuthorName: String;
    AuthorEmail: String;
    CommitDate: TDateTime;
    ParentCount: Integer;
  End;

  IGitRepositoryChanged = Interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    Procedure RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure WorkingTreeChanged(Const RepoPath: String);
    Procedure HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
  End;

  IGitCommitCreated = Interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    Procedure CommitCreated(Const RepoPath: String; Const Commit: TGitCommitInfo);
  End;

  { Compiler / build events }
  TCompilerResult = (crSuccess, crFailed, crCancelled);

  ICompilerFinished = Interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
  End;

  { Markdown / document events }
  IMarkdownDocumentChanged = Interface
    ['{D4E5F6A7-B8C9-0123-DEF0-234567890123}']
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  End;

  { Assistant / LLM tool call bridge }
  IAssistantToolCallRequested = Interface
    ['{E5F6A7B8-C9D0-1234-EF01-345678901234}']
    Function HandleToolCall(Const ToolName: String; Const ArgumentsJson: String;
      Out ResultJson: String; Out ErrorMessage: String): Boolean;
  End;

  { Optional one-shot completion for Git commit messages (registered by LazAssistantTools).
    Returns True when MessageText is filled; ErrorText set on failure. Does not require
    LazRepositoryTools to depend on the Assistant package. }
  TSuggestCommitMessageFunc = Function(Const DiffText, StatusSummary: String;
    Out MessageText, ErrorText: String): Boolean;

  { Nested so notify helpers can close over their arguments. Stops when it returns True. }
  TWorkflowEachFunc = Function(Const Listener: IInterface): Boolean Is Nested;

  { Simple thread-safe observer list }
  TWorkflowEventBus = Class
  Private
    FListeners: TInterfaceList;
    FLock: TRTLCriticalSection;
    { Snapshot so notify callbacks can add/remove listeners and do UI without holding FLock. }
    Function CopyListeners: TInterfaceList;
    Function ForEach(Each: TWorkflowEachFunc): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;

    Procedure AddListener(Listener: IInterface);
    Procedure RemoveListener(Listener: IInterface);

    { Notification helpers }
    Procedure NotifyRepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure NotifyWorkingTreeChanged(Const RepoPath: String);
    Procedure NotifyHeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure NotifyRemoteUpdated(Const RepoPath: String; Const RemoteName: String);
    Procedure NotifyCommitCreated(Const RepoPath: String; Const Commit: TGitCommitInfo);
    Procedure NotifyCompilerFinished(Const ProjectFile: String; CompileResult: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    Procedure NotifyDocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure NotifyDocumentSaved(Const FileName: String);

    { Tool call routing – first listener that handles it wins }
    Function RequestToolCall(Const ToolName: String; Const ArgumentsJson: String;
      Out ResultJson: String; Out ErrorMessage: String): Boolean;
  End;

Var
  WorkflowEventBus: TWorkflowEventBus;
  { Nil until LazAssistantTools registers a handler (signed-in OAuth complete-once). }
  SuggestCommitMessageFunc: TSuggestCommitMessageFunc;

Implementation

Uses
  WorkflowLog;

Constructor TWorkflowEventBus.Create;
Begin
  Inherited Create;
  FListeners := TInterfaceList.Create;
  InitCriticalSection(FLock);
End;

Destructor TWorkflowEventBus.Destroy;
Begin
  EnterCriticalSection(FLock);
  Try
    FListeners.Clear;
  Finally
    LeaveCriticalSection(FLock);
  End;
  FreeAndNil(FListeners);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Function TWorkflowEventBus.ForEach(Each: TWorkflowEachFunc): Boolean;
Var
  I: Integer;
  Snapshot: TInterfaceList;
Begin
  Result := False;
  If Not Assigned(Each) Then
    Exit;
  Snapshot := CopyListeners;
  Try
    For I := 0 To Snapshot.Count - 1 Do
      Try
        If Each(Snapshot[I]) Then
          Begin
            Result := True;
            Exit;
          End;
      Except
        On E: Exception Do
          If Assigned(WorkflowLogger) Then
            WorkflowLogger.Error('WorkflowEvents', E.Message);
      End;
  Finally
    Snapshot.Free;
  End;
End;

Procedure TWorkflowEventBus.AddListener(Listener: IInterface);
Begin
  If Not Assigned(Listener) Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    If FListeners.IndexOf(Listener) < 0 Then
      FListeners.Add(Listener);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.RemoveListener(Listener: IInterface);
Begin
  If Not Assigned(Listener) Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    FListeners.Remove(Listener);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TWorkflowEventBus.CopyListeners: TInterfaceList;
Var
  I: Integer;
Begin
  Result := TInterfaceList.Create;
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      Result.Add(FListeners[I]);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyRepositoryStateChanged(Const RepoPath: String;
  NewState: TGitRepositoryState);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    GitListener: IGitRepositoryChanged;
  Begin
    Result := False;
    If Supports(Listener, IGitRepositoryChanged, GitListener) Then
      GitListener.RepositoryStateChanged(RepoPath, NewState);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyWorkingTreeChanged(Const RepoPath: String);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    GitListener: IGitRepositoryChanged;
  Begin
    Result := False;
    If Supports(Listener, IGitRepositoryChanged, GitListener) Then
      GitListener.WorkingTreeChanged(RepoPath);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyHeadChanged(Const RepoPath: String; Const NewHeadSha: String);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    GitListener: IGitRepositoryChanged;
  Begin
    Result := False;
    If Supports(Listener, IGitRepositoryChanged, GitListener) Then
      GitListener.HeadChanged(RepoPath, NewHeadSha);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyRemoteUpdated(Const RepoPath: String; Const RemoteName: String);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    GitListener: IGitRepositoryChanged;
  Begin
    Result := False;
    If Supports(Listener, IGitRepositoryChanged, GitListener) Then
      GitListener.RemoteUpdated(RepoPath, RemoteName);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyCommitCreated(Const RepoPath: String; Const Commit: TGitCommitInfo);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    CommitListener: IGitCommitCreated;
  Begin
    Result := False;
    If Supports(Listener, IGitCommitCreated, CommitListener) Then
      CommitListener.CommitCreated(RepoPath, Commit);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyCompilerFinished(Const ProjectFile: String;
  CompileResult: TCompilerResult; Const OutputText: String; ErrorCount, WarningCount: Integer);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    CompilerListener: ICompilerFinished;
  Begin
    Result := False;
    If Supports(Listener, ICompilerFinished, CompilerListener) Then
      CompilerListener.CompilerFinished(ProjectFile, CompileResult, OutputText, ErrorCount, WarningCount);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyDocumentChanged(Const FileName: String; Const NewContent: String);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    DocListener: IMarkdownDocumentChanged;
  Begin
    Result := False;
    If Supports(Listener, IMarkdownDocumentChanged, DocListener) Then
      DocListener.DocumentChanged(FileName, NewContent);
  End;

Begin
  ForEach(@CallOne);
End;

Procedure TWorkflowEventBus.NotifyDocumentSaved(Const FileName: String);

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    DocListener: IMarkdownDocumentChanged;
  Begin
    Result := False;
    If Supports(Listener, IMarkdownDocumentChanged, DocListener) Then
      DocListener.DocumentSaved(FileName);
  End;

Begin
  ForEach(@CallOne);
End;

Function TWorkflowEventBus.RequestToolCall(Const ToolName: String; Const ArgumentsJson: String;
  Out ResultJson: String; Out ErrorMessage: String): Boolean;

  Function CallOne(Const Listener: IInterface): Boolean;
  Var
    ToolListener: IAssistantToolCallRequested;
  Begin
    Result := False;
    If Supports(Listener, IAssistantToolCallRequested, ToolListener) Then
      Result := ToolListener.HandleToolCall(ToolName, ArgumentsJson, ResultJson, ErrorMessage);
  End;

Begin
  ResultJson := '';
  ErrorMessage := '';
  Result := ForEach(@CallOne);
End;

Initialization

WorkflowEventBus := TWorkflowEventBus.Create;
SuggestCommitMessageFunc := Nil;

Finalization

FreeAndNil(WorkflowEventBus);

End.
