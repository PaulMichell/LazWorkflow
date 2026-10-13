Program AssistantMarkdownAsyncTest;
{$mode objfpc}{$H+}{$codepage utf8}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Graphics, StdCtrls,
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
      (View.Layout[1].FullVersion=View.Layout[1].Version) And
      (View.Layout[1].ParsedBaseSize=View.Font.Size) And
      (View.Layout[1].Full.Generation=View.Renderer.Generation) And
      (View.Layout[1].Full.Width=View.Layout[1].OuterWidth-2*View.Layout[1].Padding) And
      Not View.Layout.PendingWork Then Exit;
    Sleep(2);
  Until GetTickCount64>StopAt;
  WriteLn('pending=',View.Layout.PendingWork,' size=',View.Font.Size,
    ' parsed=',View.Layout[1].ParsedBaseSize,' gen=',View.Renderer.Generation,
    ' full=',View.Layout[1].Full.Generation,' width=',View.Layout[1].Full.Width,
    ' expected=',View.Layout[1].OuterWidth-2*View.Layout[1].Padding);
  Check('asynchronous parse completed',False);
End;
Procedure TestGrowingReply;
Var Source: String;
Begin
  Source:='Short **answer**.';
  Block.Body:=Source;
  Sync; View.CompleteLayout; AwaitLatest;
  Check('short answer has a fragment',Assigned(View.Layout[1].Full) And
    (View.Layout[1].ParsedVersion=View.Layout[1].Version));
  Source:=Source+#10+#10+'Appended paragraph.';
  Block.Body:=Source;
  Sync;
  Check('growing reply keeps its fragment',Assigned(View.Layout[1].Full));
  Check('growing reply defers the new parse',View.Layout[1].ParsedVersion<>View.Layout[1].Version);
  AwaitLatest;
  Expected:=BuildStyledMarkdown(View.Renderer,Source,View.Font.Size);
  Check('growing reply publishes the new source',
    StyledContentText(Expected)=StyledContentText(View.Layout[1].BodyContent));
End;
Procedure TestFontAnchor;
Var State, Actual: TConversationViewState; N,J: Integer; SavedParses, Generation: QWord;
  A,B: TConversationPosition;
Begin
  State:=View.SaveViewState;
  Try
    State.FollowTail:=False; State.Anchor.Key:=Block.ID;
    State.Anchor.Text:=StyledPosition(100,0); State.Anchor.TextAnchor:=True;
    State.Anchor.Offset:=0; View.RestoreViewState(State);
    Actual:=View.SaveViewState;
    Try Check('fixture starts inside a large reply',Actual.Anchor.TextAnchor And
      (Actual.Anchor.Text.Paragraph=100)); Finally Actual.Free; End;
    A.Key:=Block.ID; A.Text:=StyledPosition(101,0);
    B.Key:=Block.ID; B.Text:=StyledPosition(101,9); View.SelectRange(A,B);
    For N:=0 To 4 Do
      Begin
        SavedParses:=View.Layout.ParseCount;
        View.Font.BeginUpdate;
        Try
          Case N Of
            0: View.Font.Size:=14;
            1: View.Font.Name:='DejaVu Sans Mono';
            2: View.Font.PixelsPerInch:=144;
            3: View.Font.PixelsPerInch:=192;
            4: View.Font.PixelsPerInch:=96;
          End;
          If N>=2 Then View.Font.Size:=14;
        Finally View.Font.EndUpdate; End;
        AwaitLatest;
        Actual:=View.SaveViewState;
        Try
          Check('font/DPI change retains the reading paragraph '+IntToStr(N),
            (Actual.Anchor.Key=State.Anchor.Key) And Actual.Anchor.TextAnchor And
            (Actual.Anchor.Text.Paragraph=State.Anchor.Text.Paragraph));
        Finally Actual.Free; End;
        Check('selection survives font/DPI change',View.SelectedText='Paragraph');
        Check('bubble padding follows DPI',View.Layout[1].Padding=View.Scale96ToFont(12));
        Check('viewport gutter follows DPI',View.ViewRect.Left=View.Scale96ToFont(7));
        For J:=0 To View.ControlCount-1 Do
          If (View.Controls[J] Is TScrollBar) And
            (TScrollBar(View.Controls[J]).Kind=sbVertical) Then
            Check('viewport reserves the native scrollbar at each DPI',
              (View.Controls[J].Width>0) And
              (View.ViewRect.Right=View.ClientWidth-View.Scale96ToFont(7)-View.Controls[J].Width) And
              (View.Controls[J].Left>=View.ViewRect.Right) And
              (View.Controls[J].Left+View.Controls[J].Width<=View.ClientWidth));
        Generation:=View.Renderer.Generation; View.Repaint; View.Repaint;
        Check('unchanged paints keep the metric generation',View.Renderer.Generation=Generation);
        Check('font/DPI extent matches the index',View.ContentHeight=View.Layout.TotalHeight);
        If N>0 Then Check('face/DPI reflow reuses parsed Markdown',View.Layout.ParseCount=SavedParses);
      End;
    View.Font.Size:=10; AwaitLatest; View.JumpToStart;
  Finally State.Free; End;
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
    Sync; View.CompleteLayout;
    TestGrowingReply;
    MaxPumpMs:=0;
    View.JumpToStart; BeforeTop:=View.ScrollTop;
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
    TestFontAnchor;
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
