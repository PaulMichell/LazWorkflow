Program AssistantConversationSurfaceTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Math, Graphics, StyledTextTypes,
  AssistantTrace, AssistantConversationSurface;
Procedure Check(Const Name:String; OK:Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ',Name); Halt(1); End; WriteLn('ok ',Name); End;
Var Host:TForm; View:TAssistantConversationSurface; Trace:TAssistantTrace; I,J,ControlsBefore:Integer; Body,Key:String;
  BeforeHeight,BeforeTop:Int64; Parses,Started,ParsedAt:QWord; Bitmap:TBitmap; PNG:TPortableNetworkGraphic; A,B:TConversationPosition;
Procedure Sync;
Var N:Integer;
Begin
 View.BeginDocument; For N:=0 To Trace.Count-1 Do View.AddBlock(Trace[N].ID,Trace[N]); View.EndDocument;
 View.CompleteLayout; Application.ProcessMessages;
 Check('extent equals the height index',View.ContentHeight=View.Layout.TotalHeight);
 Check('scroll position in range',(View.ScrollTop>=0) And (View.ScrollTop<=Max(Int64(0),View.ContentHeight-View.ViewRect.Height)));
End;
Begin
 Application.Initialize; Host:=TForm.CreateNew(nil); Trace:=TAssistantTrace.Create;
 Try
 Host.SetBounds(0,0,800,600); View:=TAssistantConversationSurface.Create(Host); View.Parent:=Host; View.Align:=alClient;
 Host.Show; Application.ProcessMessages; ControlsBefore:=View.ControlCount;
 Trace.AddTool('failure','read_file','{}').Body:='Failed output';
 Trace.FindTool('failure').OK:=False; Trace.FindTool('failure').Collapsed:=False;
 Sync; Check('failed tool defaults closed',View.Layout[0].Collapsed);
 View.Toggle(0); Sync; Check('user can open failed tool',Not View.Layout[0].Collapsed);
 Trace.FindTool('failure').Body:='Later output'; Trace.FindTool('failure').Collapsed:=True;
 Sync; Check('updates preserve user expansion',Not View.Layout[0].Collapsed);
 View.Toggle(0); Trace.FindTool('failure').Collapsed:=False;
 Sync; Check('updates preserve user collapse',View.Layout[0].Collapsed);
 Trace.Clear; View.Clear;
 Trace.AddUser('A short user message'); Trace.EnsureAnswer.Body:='A short **assistant** reply'; Sync;
 Check('user bubble aligns right',View.Layout[0].Left>View.Layout[1].Left);
 Check('bubble padding is included in extent',View.Layout.Heights.Values[0]=View.Layout[0].FullHeight+2*View.Layout[0].Padding+10);
 Check('bubble text fits its measured width',View.Layout[0].Full.Width=View.Layout[0].OuterWidth-2*View.Layout[0].Padding);
 Check('body font has readable default size',View.Font.Size>=10);
 Trace.Clear; View.Clear;
 Trace.StartThinking(0); Sync; Check('empty thinking takes no height',View.ContentHeight=0);
 Trace.CurrentThinking.Body:='Actual reasoning summary'; Sync; Check('received thinking appears',View.ContentHeight>0);
 Body:=''; For J:=1 To 600 Do Body+='Paragraph '+IntToStr(J)+': **bold** words and café text.'+#10+#10;
 For I:=1 To 10 Do Begin Trace.EnsureAnswer.Body:=Body; Trace.AddTool(IntToStr(I),'read_file','{}').Body:='Tool result'; End;
 Sync; Check('long conversation exceeds old coordinate cap',View.ContentHeight>30000);
 Check('first full answer exceeds old card-height cap',View.Layout[1].FullHeight>4000);
 Check('native child-control count is constant',View.ControlCount=ControlsBefore);
 Check('all answers remain visible',View.Layout[View.Layout.Count-2].Visible);
 View.JumpToEnd; Check('end reaches exact last content pixel',View.ScrollTop=View.ContentHeight-View.ViewRect.Height);
 View.ScrollTop:=1000; BeforeTop:=View.ScrollTop; Check('user scroll disables following',Not View.FollowTail);
 Trace.EnsureAnswer.Body:='New appended answer'; Sync;
 Check('append preserves earlier reading position',Abs(View.ScrollTop-BeforeTop)<=1);
 Parses:=View.Layout.ParseCount; Sync; Check('unchanged sync does not reparse Markdown',View.Layout.ParseCount=Parses);
 Trace[1].Title:='Assistant — updated metadata'; Sync; Check('header-only changes do not reparse body',View.Layout.ParseCount=Parses);
 BeforeHeight:=View.ContentHeight; View.ShowToolUse:=False;
 Check('hiding tools shrinks the extent',View.ContentHeight<BeforeHeight);
 Check('hidden tools keep source',Trace.FindTool('1').Body='Tool result');
 View.ShowToolUse:=True; View.CompleteLayout; Check('show restores measured extent',View.ContentHeight=BeforeHeight);
 Key:=Trace[1].ID; View.NavigateTo(Key); View.ScrollTop:=View.ScrollTop+80;
 Host.Width:=620; Application.ProcessMessages; View.CompleteLayout;
 Check('width change keeps anchor in same block',View.Layout[View.Layout.AtY(View.ScrollTop)].Key=Key);
 A.Key:=Trace[1].ID; A.Text:=StyledPosition(1,0); B.Key:=Trace[3].ID; B.Text:=StyledPosition(1,10);
 View.SelectRange(A,B); Check('cross-message selection copies text',(Pos('Paragraph',View.SelectedText)>0) And (Pos('read_file',View.SelectedText)>0));
 View.ShowToolUse:=False; Check('filter clears potentially hidden selection',View.SelectedText='');
 Check('Markdown export preserves hidden tools',Pos('Tool result',View.MarkdownText)>0);
 View.JumpToEnd; Trace.EnsureAnswer.Body:=Trace.EnsureAnswer.Body+' after end'; Sync;
 Check('tail remains at end after update',View.FollowTail And (View.ScrollTop=View.ContentHeight-View.ViewRect.Height));
 View.Clear; Check('clear resets extent and offset',(View.ContentHeight=0) And (View.ScrollTop=0));
 Trace.Clear; View.ShowToolUse:=True;
 For I:=1 To 10000 Do Trace.AddTool(IntToStr(I),'read_file','{}');
 Started:=GetTickCount64; Sync;
 WriteLn('benchmark 10000 sections: ',GetTickCount64-Started,' ms, height=',View.ContentHeight,', child controls=',View.ControlCount);
 Check('10000 sections remain addressable',(View.Layout.Count=10000) And (View.ContentHeight>30000) And (View.ControlCount=ControlsBefore));
 Check('painting uses the published layout revision',View.PaintRevision=View.LayoutRevision);
 If GetEnvironmentVariable('LAZ_CONVERSATION_BENCHMARK')<>'' Then
   Begin
     Trace.Clear; View.Clear; Body:='';
     While Length(Body)<2*1024*1024 Do Body+='A **formatted** paragraph with `code` and UTF-8 café. '+StringOfChar('x',160)+#10+#10+
       '| Column | Value |'+#10+'| --- | --- |'+#10+'| One | Two |'+#10+#10+
       '```pascal'+#10+'Result := Length(Text);'+#10+'```'+#10+#10;
     Trace.EnsureAnswer.Body:=Body; Trace.AddTool('middle','read_file','{}'); Trace.EnsureAnswer.Body:=Body;
     Started:=GetTickCount64; View.BeginDocument;
     For I:=0 To Trace.Count-1 Do View.AddBlock(Trace[I].ID,Trace[I]);
     View.EndDocument; ParsedAt:=GetTickCount64;
     View.CompleteLayout; Application.ProcessMessages;
     WriteLn('benchmark two large answers: bytes=',Length(Body)*2,', initial sync=',ParsedAt-Started,
       ' ms, complete layout=',GetTickCount64-ParsedAt,' ms, height=',View.ContentHeight);
     Check('large answers retain all content',View.Layout[0].Body=Body);
     Check('large answer extent stays coherent',View.ContentHeight=View.Layout.TotalHeight);
     View.JumpToEnd; Check('large answer end reachable',View.ScrollTop=View.ContentHeight-View.ViewRect.Height);
   End;
 If GetEnvironmentVariable('LAZ_CONVERSATION_CAPTURE')<>'' Then
   Begin
     Trace.Clear; Trace.AddUser('Please review the output renderer.');
     Trace.StartThinking(0).Body:='Check that the conversation and scrollbar use the same measured geometry.'; Trace.FinishCurrentThinking;
     Trace.EnsureAnswer.Body:='The conversation now uses **one StyledText canvas**.'+#10+#10+
       '| Check | Result |'+#10+'| --- | --- |'+#10+'| Long messages | Fully reachable |'+#10+'| Hidden tools | No blank gaps |'+#10+#10+
       '1. Preserve the reading position.'+#10+'2. Keep **bold** text and `code` readable.'+#10+#10+
       '```pascal'+#10+'ScrollTop := Max(0, ContentHeight - ViewHeight);'+#10+'```';
     Trace.AddTool('capture','read_file','{"path":"Source/Main.pas"}').Body:='Tool result retained for expansion';
     Trace.FindTool('capture').Running:=False;
     Trace.EnsureAnswer.Body:='Ready for your next message.'; Trace.ApplyWorkedFooter(1200);
     View.ShowToolUse:=True; Sync; View.JumpToStart; Application.ProcessMessages;
     Bitmap:=Host.GetFormImage; PNG:=TPortableNetworkGraphic.Create;
     Try PNG.Assign(Bitmap); PNG.SaveToFile('/tmp/laz-conversation-canvas.png'); Finally PNG.Free; Bitmap.Free; End;
   End;
 Finally Host.Free; Trace.Free; End;
End.
