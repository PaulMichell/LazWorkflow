Program AssistantConversationStressTest;
{$mode objfpc}{$H+}{$codepage utf8}
Uses cthreads, Interfaces, Forms, Controls, SysUtils, Math, StyledTextTypes,
  AssistantTrace, AssistantConversationSurface;
Var Host:TForm; View:TAssistantConversationSurface; Trace:TAssistantTrace;
  MaxPump,MaxPaint:QWord;
Procedure Check(Const Name:String; Passed:Boolean);
Begin
  If Not Passed Then Begin WriteLn('FAIL ',Name); Halt(1); End;
  WriteLn('ok ',Name); Flush(Output);
End;
Function CurrentFragment:Boolean;
Begin
  Result:=Assigned(View.Layout[0].Full) And
    (View.Layout[0].FullVersion=View.Layout[0].Version) And
    (View.Layout[0].Full.Generation=View.Renderer.Generation) And
    (View.Layout[0].Full.Width=View.Layout[0].OuterWidth-2*View.Layout[0].Padding);
End;
Procedure AwaitLayout(Complete:Boolean=True);
Var Deadline,Pump:QWord;
Begin
  Deadline:=GetTickCount64+45000;
  Repeat
    Pump:=GetTickCount64; Application.ProcessMessages; Pump:=GetTickCount64-Pump;
    MaxPump:=Max(MaxPump,Pump); MaxPaint:=Max(MaxPaint,View.LastPaintMilliseconds);
    If CurrentFragment And (Not Complete Or
      ((View.Layout[0].Full.NextMeasure=View.Layout[0].Full.Document.Count) And Not View.Layout.PendingWork)) Then Exit;
    Sleep(2);
  Until GetTickCount64>=Deadline;
  Check('layout completes without forced synchronous measurement',False);
End;
Procedure TestAnchor;
Var Before,After:TConversationViewState; Line:Integer;
Begin
  Before:=View.SaveViewState;
  Try
    Before.FollowTail:=False; Before.Anchor.Key:=Trace[0].ID;
    Before.Anchor.TextAnchor:=True; Before.Anchor.Text:=StyledPosition(1,Length(View.Layout[0].Full.Document[1]^.Text) Div 2);
    Before.Anchor.Offset:=0; View.RestoreViewState(Before);
  Finally Before.Free; End;
  Before:=View.SaveViewState;
  Try
    Check('reading starts halfway through a long paragraph',Before.Anchor.Text.Offset>250000);
    Host.Width:=640; AwaitLayout;
    After:=View.SaveViewState;
    Try
      Line:=View.Layout[0].Full.Layout.Paragraphs[1].LineAtOffset(Before.Anchor.Text.Offset);
      Check('resize preserves the line containing the original text position',
        After.Anchor.TextAnchor And (After.Anchor.Key=Before.Anchor.Key) And
        (After.Anchor.Text.Paragraph=1) And
        (After.Anchor.Text.Offset=View.Layout[0].Full.Layout.Paragraphs[1].Lines[Line].Start));
    Finally After.Free; End;
    View.Font.Size:=14; AwaitLayout(False);
    Check('font reflow is still incremental',View.Layout[0].Full.NextMeasure<View.Layout[0].Full.Document.Count);
    View.RestoreViewState(Before);
    View.JumpToStart; AwaitLayout;
    Check('explicit navigation cancels pending restoration',View.ScrollTop=0);
    Host.Width:=720; View.JumpToEnd; AwaitLayout;
    Check('tail follows incremental measurement to the exact end',View.FollowTail And
      (View.ScrollTop=View.ContentHeight-View.ViewRect.Height));
    View.Font.Size:=12; AwaitLayout(False); View.RestoreViewState(Before);
    View.Clear; Trace.Clear; Trace.EnsureAnswer.Body:='Replacement conversation';
    View.BeginDocument; View.AddBlock(Trace[0].ID,Trace[0]); View.EndDocument; AwaitLayout;
    After:=View.SaveViewState;
    Try Check('clearing discards the pending anchor',
      (After.Anchor.Key=Trace[0].ID) And (View.ScrollTop=0));
    Finally After.Free; End;
  Finally Before.Free; End;
End;
Procedure RunCase(N:Integer);
Var Body,Kind:String; Started,HeapBefore:QWord;
Begin
  Trace.Clear; Host.Width:=800;
  View:=TAssistantConversationSurface.Create(Host); View.Parent:=Host; View.Align:=alClient;
  Application.ProcessMessages;
  Try
    Case N Of
      0: Begin Kind:='prose'; Body:=UTF8String('Words with **bold**, café and code. ');
           While Length(Body)<512*1024 Do Body+=Body; End;
      1: Begin Kind:='token'; Body:=StringOfChar('x',512*1024); End;
      2: Begin Kind:='code'; Body:='```pascal'+#10+StringOfChar('x',512*1024)+#10+'```'; End;
      3: Begin Kind:='code spaces'; Body:='```'+#10+'word'+StringOfChar(' ',512*1024)+'last'+#10+'```'; End;
    End;
    HeapBefore:=GetFPCHeapStatus.CurrHeapUsed;
    Trace.EnsureAnswer.Body:=Body; Started:=GetTickCount64; MaxPump:=0; MaxPaint:=0;
    View.BeginDocument; View.AddBlock(Trace[0].ID,Trace[0]); View.EndDocument; View.JumpToStart;
    AwaitLayout;
    Check(Kind+' retains its source',View.Layout[0].Body=Body);
    Check(Kind+' publishes a coherent extent',View.ContentHeight=View.Layout.TotalHeight);
    Check(Kind+' has constant native control count',View.ControlCount=2);
    WriteLn(Kind,': bytes=',Length(Body),', elapsed_ms=',GetTickCount64-Started,
      ', max_pump_ms=',MaxPump,', max_paint_ms=',MaxPaint,', max_update_ms=',View.MaxUpdateMilliseconds,
      ', heap_before=',HeapBefore,', heap_after=',GetFPCHeapStatus.CurrHeapUsed,
      ', process_heap_peak=',GetFPCHeapStatus.MaxHeapUsed); Flush(Output);
    If N=1 Then TestAnchor;
  Finally View.Free; View:=Nil; End;
End;
Var N:Integer;
Begin
  Application.Initialize; Host:=TForm.CreateNew(Nil); Trace:=TAssistantTrace.Create;
  Try
    Host.SetBounds(0,0,800,600); Host.Show; Application.ProcessMessages;
    For N:=0 To 3 Do RunCase(N);
  Finally Trace.Free; Host.Free; End;
End.
