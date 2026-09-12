Unit AssistantMarkdownWorker;

{ A single value-only parse job. No canvas, controls, queued UI callbacks or
  section pointers cross the thread boundary. The caller polls completed jobs. }
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, SyncObjs, StyledMarkdown, StyledTextTypes, StyledTextDocument, StyledMemoLayout;
Type
  TAssistantMarkdownStage = (amsParse, amsPrepare, amsRetire);
  TAssistantMarkdownJob = Class
  Public
    Key, Source, ErrorText: String;
    Epoch, Identity, Version: QWord;
    BaseSize, Width, Kind: Integer;
    OK, CountParse: Boolean;
    Stage: TAssistantMarkdownStage;
    Title, Footer: String;
    Mapping: TStyledIntegers;
    Prefix, Suffix, BoundBody, RetiredContent: TStyledContent;
    PreparedDocument: TStyledDocument;
    PreparedLayout: TStyledMemoLayout;
    RetiredObject: TObject;
    Parsed: TParsedStyledMarkdown;
    Cancelled: Boolean;
    Procedure PrepareDocument;
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
Begin
  PreparedLayout.Free; PreparedDocument.Free; RetiredObject.Free; Parsed.Free;
  Inherited Destroy;
End;
Procedure TAssistantMarkdownJob.PrepareDocument;
Var Content: TStyledContent; I,Offset: Integer;
Begin
  FreeAndNil(PreparedLayout); FreeAndNil(PreparedDocument);
  If Assigned(Parsed) Then
    Begin BoundBody:=Parsed.BindStyles(Mapping); FreeAndNil(Parsed); End
  Else If Length(BoundBody)=0 Then BoundBody:=StyledContentFromText(Source);
  SetLength(Content,Length(Prefix)+Length(BoundBody)+Length(Suffix));
  Offset:=0;
  For I:=0 To High(Prefix) Do Begin Content[Offset]:=Prefix[I]; Inc(Offset); End;
  For I:=0 To High(BoundBody) Do
    Begin
      Content[Offset]:=BoundBody[I];
      If Content[Offset].Box.Group<>0 Then Inc(Content[Offset].Box.Group);
      Inc(Offset);
    End;
  For I:=0 To High(Suffix) Do Begin Content[Offset]:=Suffix[I]; Inc(Offset); End;
  If Length(Content)=0 Then Content:=StyledContentFromText('');
  For I:=0 To High(Content) Do
    If Content[I].Box.Group=0 Then Content[I].Box.Style.Margin.Bottom:=6;
  PreparedDocument:=TStyledDocument.Create;
  PreparedDocument.Replace(StyledPosition(0,0),PreparedDocument.EndPosition,Content);
  PreparedLayout:=TStyledMemoLayout.Create(PreparedDocument,Nil);
  PreparedLayout.Reset(Width,True,24);
End;
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
      If WorkItem.Stage=amsRetire Then
        Begin
          WorkItem.Free;
          Lock.Acquire;
          Try Job:=Nil; Finally Lock.Release; End;
          Continue;
        End;
      Try
        If IsCancelled Then Raise EAbort.Create('Markdown preparation cancelled');
        Case WorkItem.Stage Of
          amsParse: WorkItem.Parsed:=ParseStyledMarkdown(WorkItem.Source,WorkItem.BaseSize,@IsCancelled);
          amsPrepare: WorkItem.PrepareDocument;
        End;
        If IsCancelled Then WorkItem.Cancelled:=True;
      Except
        On E: EAbort Do WorkItem.Cancelled:=True;
        On E: Exception Do WorkItem.ErrorText:=E.Message;
      End;
      Lock.Acquire;
      Try Ready:=True; Finally Lock.Release; End;
    End;
End;
End.
