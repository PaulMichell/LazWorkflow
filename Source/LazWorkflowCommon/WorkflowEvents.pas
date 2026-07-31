Unit WorkflowEvents;

{ Central event bus and observer interfaces for LazWorkflow packages (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  { Forward declarations }
  IWorkflowListener = Interface;

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

  { Generic listener that can implement any subset of the above }
  IWorkflowListener = Interface
    ['{F6A7B8C9-D0E1-2345-F012-456789012345}']
    { Empty marker; concrete listeners implement the specific interfaces they care about. }
  End;

  { Simple thread-safe observer list }
  TWorkflowEventBus = Class
  Private
    FListeners: TInterfaceList;
    FLock: TRTLCriticalSection;
  Public
    Constructor Create;
    Destructor Destroy; Override;

    Procedure AddListener(Listener: IWorkflowListener);
    Procedure RemoveListener(Listener: IWorkflowListener);

    { Notification helpers }
    Procedure NotifyRepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure NotifyWorkingTreeChanged(Const RepoPath: String);
    Procedure NotifyHeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure NotifyRemoteUpdated(Const RepoPath: String; Const RemoteName: String);
    Procedure NotifyCommitCreated(Const RepoPath: String; Const Commit: TGitCommitInfo);
    Procedure NotifyCompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
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

Procedure TWorkflowEventBus.AddListener(Listener: IWorkflowListener);
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

Procedure TWorkflowEventBus.RemoveListener(Listener: IWorkflowListener);
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

Procedure TWorkflowEventBus.NotifyRepositoryStateChanged(Const RepoPath: String;
  NewState: TGitRepositoryState);
Var
  I: Integer;
  Listener: IGitRepositoryChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IGitRepositoryChanged, Listener) Then
        Listener.RepositoryStateChanged(RepoPath, NewState);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyWorkingTreeChanged(Const RepoPath: String);
Var
  I: Integer;
  Listener: IGitRepositoryChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IGitRepositoryChanged, Listener) Then
        Listener.WorkingTreeChanged(RepoPath);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyHeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Var
  I: Integer;
  Listener: IGitRepositoryChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IGitRepositoryChanged, Listener) Then
        Listener.HeadChanged(RepoPath, NewHeadSha);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyRemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Var
  I: Integer;
  Listener: IGitRepositoryChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IGitRepositoryChanged, Listener) Then
        Listener.RemoteUpdated(RepoPath, RemoteName);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyCommitCreated(Const RepoPath: String; Const Commit: TGitCommitInfo);
Var
  I: Integer;
  Listener: IGitCommitCreated;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IGitCommitCreated, Listener) Then
        Listener.CommitCreated(RepoPath, Commit);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyCompilerFinished(Const ProjectFile: String;
  Result: TCompilerResult; Const OutputText: String; ErrorCount, WarningCount: Integer);
Var
  I: Integer;
  Listener: ICompilerFinished;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], ICompilerFinished, Listener) Then
        Listener.CompilerFinished(ProjectFile, Result, OutputText, ErrorCount, WarningCount);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyDocumentChanged(Const FileName: String; Const NewContent: String);
Var
  I: Integer;
  Listener: IMarkdownDocumentChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IMarkdownDocumentChanged, Listener) Then
        Listener.DocumentChanged(FileName, NewContent);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TWorkflowEventBus.NotifyDocumentSaved(Const FileName: String);
Var
  I: Integer;
  Listener: IMarkdownDocumentChanged;
Begin
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IMarkdownDocumentChanged, Listener) Then
        Listener.DocumentSaved(FileName);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TWorkflowEventBus.RequestToolCall(Const ToolName: String; Const ArgumentsJson: String;
  Out ResultJson: String; Out ErrorMessage: String): Boolean;
Var
  I: Integer;
  Listener: IAssistantToolCallRequested;
Begin
  Result := False;
  ResultJson := '';
  ErrorMessage := '';
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FListeners.Count - 1 Do
      If Supports(FListeners[I], IAssistantToolCallRequested, Listener) Then
        Begin
          If Listener.HandleToolCall(ToolName, ArgumentsJson, ResultJson, ErrorMessage) Then
            Begin
              Result := True;
              Exit;
            End;
        End;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Initialization

WorkflowEventBus := TWorkflowEventBus.Create;
SuggestCommitMessageFunc := Nil;

Finalization

FreeAndNil(WorkflowEventBus);

End.
