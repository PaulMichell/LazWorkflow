Unit AssistantMarkdownWorker;

{ A single value-only parse job. No canvas, controls, queued UI callbacks or
  section pointers cross the thread boundary. The caller polls completed jobs. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, SyncObjs, StyledMarkdown;
Type
  TAssistantMarkdownJob = Class
  Public
    Key, Source, ErrorText: String;
    Epoch, Identity, Version: QWord;
    BaseSize: Integer;
    Parsed: TParsedStyledMarkdown;
    Cancelled: Boolean;
    Destructor Destroy; Override;
  End;
  TAssistantMarkdownWorker = Class(TThread)
  Private
    Lock: TCriticalSection;
    Wake: TEvent;
    Job: TAssistantMarkdownJob;
    Ready: Boolean;
    CancelGeneration, RunningGeneration: LongInt;
    Function IsCancelled: Boolean;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { Takes ownership only on success. At most one snapshot is retained. }
    Function Submit(Value: TAssistantMarkdownJob): Boolean;
    Function Take: TAssistantMarkdownJob;
    Function Busy: Boolean;
    Procedure Cancel;
  End;
Implementation
Destructor TAssistantMarkdownJob.Destroy;
Begin Parsed.Free; Inherited Destroy; End;
Constructor TAssistantMarkdownWorker.Create;
Begin
  Inherited Create(True);
  FreeOnTerminate:=False;
  Lock:=TCriticalSection.Create;
  Wake:=TEvent.Create(Nil,False,False,'');
  Start;
End;
Destructor TAssistantMarkdownWorker.Destroy;
Begin
  Terminate;
  Cancel;
  Wake.SetEvent;
  WaitFor;
  Job.Free;
  Wake.Free;
  Lock.Free;
  Inherited Destroy;
End;
Procedure TAssistantMarkdownWorker.Cancel;
Begin InterlockedIncrement(CancelGeneration); End;
Function TAssistantMarkdownWorker.IsCancelled: Boolean;
Begin Result:=Terminated Or (InterlockedCompareExchange(CancelGeneration,0,0)<>RunningGeneration); End;
Function TAssistantMarkdownWorker.Submit(Value: TAssistantMarkdownJob): Boolean;
Begin
  Lock.Acquire;
  Try
    Result:=Not Assigned(Job);
    If Result Then
      Begin
        Job:=Value;
        RunningGeneration:=InterlockedCompareExchange(CancelGeneration,0,0);
        Ready:=False;
        Wake.SetEvent;
      End;
  Finally Lock.Release; End;
End;
Function TAssistantMarkdownWorker.Take: TAssistantMarkdownJob;
Begin
  Result:=Nil;
  Lock.Acquire;
  Try
    If Ready Then Begin Result:=Job; Job:=Nil; Ready:=False; End;
  Finally Lock.Release; End;
End;
Function TAssistantMarkdownWorker.Busy: Boolean;
Begin
  Lock.Acquire;
  Try Result:=Assigned(Job); Finally Lock.Release; End;
End;
Procedure TAssistantMarkdownWorker.Execute;
Var WorkItem: TAssistantMarkdownJob;
Begin
  While Not Terminated Do
    Begin
      Wake.WaitFor(INFINITE);
      If Terminated Then Break;
      Lock.Acquire;
      Try WorkItem:=Job; Finally Lock.Release; End;
      If Not Assigned(WorkItem) Then Continue;
      Try
        WorkItem.Parsed:=ParseStyledMarkdown(WorkItem.Source,WorkItem.BaseSize,@IsCancelled);
      Except
        On E: EAbort Do WorkItem.Cancelled:=True;
        On E: Exception Do WorkItem.ErrorText:=E.Message;
      End;
      Lock.Acquire;
      Try Ready:=True; Finally Lock.Release; End;
    End;
End;
End.
