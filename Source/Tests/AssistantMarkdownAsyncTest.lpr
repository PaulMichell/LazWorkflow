Program AssistantMarkdownAsyncTest;
{$mode objfpc}{$H+}{$codepage utf8}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Graphics,
  StyledTextTypes, StyledTextDocument, StyledMarkdown, AssistantTrace, AssistantConversationSurface, AssistantMarkdownWorker;
Procedure Check(Const Name: String; Passed: Boolean);
Begin
  If Not Passed Then Begin WriteLn('FAIL ',Name); Halt(1); End;
  WriteLn('ok ',Name); Flush(Output);
End;
Var Host: TForm; View: TAssistantConversationSurface; Trace: TAssistantTrace;
  Block: TTraceBlock; Body, Latest, OldKey: String; I,J: Integer;
  BeforeTop: Int64; Started, Deadline, CountBefore, MaxPumpMs: QWord;
  Expected: TStyledContent; Parsed: TParsedStyledMarkdown;
Var DisposalThread: TThreadID;
Type TDisposalProbe = Class
  Destructor Destroy; Override;
End;
Destructor TDisposalProbe.Destroy;
Begin DisposalThread:=GetCurrentThreadID; Inherited Destroy; End;
Procedure TestPreparedJob;
Var Worker: TAssistantMarkdownWorker; Job: TAssistantMarkdownJob;
  StopAt: QWord; N: Integer; Rejected: Boolean;
  Procedure AwaitJob;
  Begin
    StopAt:=GetTickCount64+5000;
    Repeat
      Job:=Worker.Take;
      If Assigned(Job) Then Exit;
      Sleep(1);
    Until GetTickCount64>=StopAt;
    Check('worker stage finishes',False);
  End;
Begin
  Worker:=TAssistantMarkdownWorker.Create; Job:=Nil;
  Try
    Job:=TAssistantMarkdownJob.Create;
    Job.Source:='## Heading'+#10+#10+'| A | B |'+#10+'| --- | --- |'+#10+'| **one** | two |';
    Job.BaseSize:=10;
    Check('submit parse stage',Worker.Submit(Job)); Job:=Nil; AwaitJob;
    Check('parse has no prepared document yet',Assigned(Job.Parsed) And Not Assigned(Job.PreparedDocument));
    SetLength(Job.Mapping,Length(Job.Parsed.Styles));
    For N:=0 To High(Job.Mapping) Do Job.Mapping[N]:=View.Renderer.AddStyle(Job.Parsed.Styles[N]);
    Job.Prefix:=StyledContentFromText('Assistant'); Job.Prefix[0].Box.Group:=1;
    Job.Suffix:=StyledContentFromText('Worked for 0:01');
    Job.Width:=320; Job.Stage:=amsPrepare;
    Check('submit preparation stage',Worker.Submit(Job)); Job:=Nil; AwaitJob;
    Check('worker built a valid document',Assigned(Job.PreparedDocument) And Job.PreparedDocument.Validate);
    Check('worker kept header and footer',(Job.PreparedDocument[0]^.Text='Assistant') And
      (Job.PreparedDocument[Job.PreparedDocument.Count-1]^.Text='Worked for 0:01'));
    Check('worker shifted body groups past header',Job.PreparedDocument[1]^.Box.Group<>Job.PreparedDocument[0]^.Box.Group);
    Check('worker retained table columns',Length(Job.PreparedDocument[2]^.Box.Columns)=2);
    Check('worker prepared all estimated heights',Length(Job.PreparedLayout.Heights.Values)=Job.PreparedDocument.Count);
    Job.PreparedLayout.AttachRenderer(View.Renderer);
    Job.PreparedLayout.Ensure(1,True);
    Check('prepared layout measures after UI attachment',Assigned(Job.PreparedLayout.Paragraphs[1]));
    Rejected:=False;
    Try Job.PreparedLayout.AttachRenderer(View.Renderer); Except On E: EArgumentException Do Rejected:=True; End;
    Check('layout cannot attach a second renderer',Rejected);
    Job.RetiredObject:=TDisposalProbe.Create; Job.Stage:=amsRetire;
    Check('submit disposal stage',Worker.Submit(Job)); Job:=Nil;
    StopAt:=GetTickCount64+5000;
    While Worker.Busy And (GetTickCount64<StopAt) Do Sleep(1);
    Check('retired snapshot freed on worker',(Not Worker.Busy) And (DisposalThread<>0) And (DisposalThread<>GetCurrentThreadID));
  Finally Job.Free; Worker.Free; End;
End;

Procedure Sync;
Var N: Integer;
Begin
  View.BeginDocument;
  For N:=0 To Trace.Count-1 Do View.AddBlock(Trace[N].ID,Trace[N]);
  View.EndDocument;
End;
Procedure AwaitLatest;
Var StopAt, PumpStart, Elapsed: QWord;
Begin
  StopAt:=GetTickCount64+15000;
  Repeat
    PumpStart:=GetTickCount64;
    Application.ProcessMessages;
    Elapsed:=GetTickCount64-PumpStart;
    If Elapsed>MaxPumpMs Then MaxPumpMs:=Elapsed;
    If (View.Layout[1].ParsedVersion=View.Layout[1].Version) And
      (View.Layout[1].FullVersion=View.Layout[1].Version) And Not View.Layout.PendingWork Then Exit;
    Sleep(2);
  Until GetTickCount64>StopAt;
  Check('asynchronous parse completed',False);
End;
Begin
  Application.Initialize;
  Host:=TForm.CreateNew(Nil); Trace:=TAssistantTrace.Create;
  Try
    Host.SetBounds(0,0,800,600);
    View:=TAssistantConversationSurface.Create(Host); View.Parent:=Host; View.Align:=alClient;
    Host.Show; Application.ProcessMessages;
    TestPreparedJob;
    Body:=UTF8String('Paragraph **bold** with café and `code`.')+#10+#10;
    While Length(Body)<2*1024*1024 Do Body+=Body;
    Trace.AddUser('Keep this question visible.');
    Block:=Trace.EnsureAnswer; Block.Body:='Previous completed reply.';
    Sync; View.CompleteLayout; View.JumpToStart; BeforeTop:=View.ScrollTop;
    Block.Body:=Body+'| Key | Value |'+#10+'| --- | --- |'+#10+'| One | Two |'+#10+#10+'```pascal'+#10+'Result := 1;';
    Started:=GetTickCount64; Sync;
    WriteLn('large update initial sync: ',GetTickCount64-Started,' ms');
    Check('previous reply remains available during replacement',Assigned(View.Layout[1].Full));
    Latest:=Block.Body+#10+'```'+#10+#10+'**Final marker**';
    Block.Body:=Latest; Sync;
    AwaitLatest;
    WriteLn('largest event pump while replacing ',Length(Latest),' bytes: ',MaxPumpMs,' ms');
    WriteLn('largest layout timer update: ',View.MaxUpdateMilliseconds,' ms');
    Check('source tracks newest snapshot',View.Layout[1].Body=Latest);
    Check('publication preserves earlier reading anchor',Abs(View.ScrollTop-BeforeTop)<=1);
    Expected:=BuildStyledMarkdown(View.Renderer,Latest,10);
    Check('async paragraphs match complete Markdown',Length(Expected)=Length(View.Layout[1].BodyContent));
    For I:=0 To High(Expected) Do
      Begin
        If Expected[I].Text<>View.Layout[1].BodyContent[I].Text Then Check('paragraph text matches',False);
        If Length(Expected[I].Ranges)<>Length(View.Layout[1].BodyContent[I].Ranges) Then Check('style range count',False);
        For J:=0 To High(Expected[I].Ranges) Do
          If (Expected[I].Ranges[J].Start<>View.Layout[1].BodyContent[I].Ranges[J].Start) Or
            (Expected[I].Ranges[J].Count<>View.Layout[1].BodyContent[I].Ranges[J].Count) Or
            (Expected[I].Ranges[J].Style<>View.Layout[1].BodyContent[I].Ranges[J].Style) Then Check('style ranges match',False);
      End;
    Check('partial fence converges to code',Pos('```',StyledContentText(View.Layout[1].BodyContent))=0);
    CountBefore:=View.Layout.ParseCount; Sync;
    Check('unchanged source is not reparsed',View.Layout.ParseCount=CountBefore);
    Host.Width:=720; Application.ProcessMessages; AwaitLatest;
    Check('width-only reflow keeps parsed content',View.Layout.ParseCount=CountBefore);
    Check('width-only preparation uses current width',View.Layout[1].Full.Width=View.Layout[1].OuterWidth-2*View.Layout[1].Padding);
    Block.Body:=Latest+#10+'## A larger heading'; Sync;
    Block.Title:='Assistant updated'; Block.Footer:='Latest footer'; Sync;
    View.Font.Size:=14; Host.Width:=650;
    AwaitLatest;
    Check('prepared header tracks metadata changes',View.Layout[1].Full.Document[0]^.Text='Assistant updated');
    Check('prepared footer tracks metadata changes',View.Layout[1].Full.Document[View.Layout[1].Full.Document.Count-1]^.Text='Latest footer');
    Check('prepared width tracks resize',View.Layout[1].Full.Width=View.Layout[1].OuterWidth-2*View.Layout[1].Padding);
    Check('pending parse respects font changes',View.Layout[1].ParsedBaseSize=14);
    Check('extent published after async update',View.ContentHeight=View.Layout.TotalHeight);
    OldKey:=Block.ID; Block.Body:=Latest+#10+'OLD CONVERSATION'; Sync;
    View.Clear; Trace.Clear;
    Trace.AddUser('Replacement question'); Block:=Trace.EnsureAnswer; Block.ID:=OldKey;
    Block.Body:='Replacement reply'; Sync;
    Deadline:=GetTickCount64+15000;
    While View.Layout.PendingWork And (GetTickCount64<Deadline) Do
      Begin Application.ProcessMessages; View.Layout.PrepareSection(1,0,0); Sleep(2); End;
    Check('cancelled worker drains',Not View.Layout.PendingWork);
    Check('cleared document rejects old parse',StyledContentText(View.Layout[1].BodyContent)='Replacement reply');
    Block.Body:=Latest; Sync;
    Started:=GetTickCount64;
    FreeAndNil(Host);
    WriteLn('close while parsing: ',GetTickCount64-Started,' ms');
    Check('worker shutdown joins without UI callbacks',True);
    { Detached parsed values can bind repeatedly without mutating local IDs. }
    Host:=TForm.CreateNew(Nil); View:=TAssistantConversationSurface.Create(Host);
    Parsed:=ParseStyledMarkdown('**Bold** and plain text');
    Try
      Expected:=Parsed.Bind(View.Renderer);
      Check('detached parse retains local style IDs',Parsed.Content[0].Ranges[0].Style=0);
      Check('detached parse can bind again',StyledContentText(Parsed.Bind(View.Renderer))=StyledContentText(Expected));
    Finally Parsed.Free; End;
  Finally Host.Free; Trace.Free; End;
End.
