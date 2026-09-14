Program AssistantConversationProfileTest;
{$mode objfpc}{$H+}{$codepage utf8}
{ Extended, opt-in GUI profiling. Run each fixture in a fresh process so
  process RSS and allocator peaks can be attributed to that fixture. }
Uses cthreads, Interfaces, Forms, Controls, SysUtils, Math,
  AssistantTrace, AssistantConversationSurface, AssistantConversationLayout;
Var Host:TForm; View:TAssistantConversationSurface; Trace:TAssistantTrace;
  Kind:String; I,J,Size,Blocks:Integer; SourceBytes,Started,SyncMS,MaxPump,MaxPaint:QWord;
Procedure Check(Const Name:String; OK:Boolean);
Begin
  If Not OK Then Begin WriteLn('FAIL ',Name); Flush(Output); Halt(1); End;
End;
Procedure HeapStage(Const Stage:String);
Begin
  WriteLn('heap stage=',Stage,' bytes=',GetFPCHeapStatus.CurrHeapUsed,
    ' peak=',GetFPCHeapStatus.MaxHeapUsed); Flush(Output);
End;
Function Ready:Boolean;
Var N:Integer; F:TConversationFragment;
Begin
  Result:=False;
  If View.Layout.PendingWork Then Exit;
  For N:=0 To View.Layout.Count-1 Do
    If View.Layout[N].Visible Then
      Begin
        If View.Layout[N].Collapsed Then F:=View.Layout[N].Short Else F:=View.Layout[N].Full;
        If Not Assigned(F) Or (F.NextMeasure<F.Document.Count) Then Exit;
        If Not View.Layout[N].Collapsed And
          (View.Layout[N].FullVersion<>View.Layout[N].Version) Then Exit;
      End;
  Result:=True;
End;
Procedure AwaitLayout;
Var Deadline,Pump:QWord; N,Measured:Integer;
Begin
  Deadline:=GetTickCount64+180000;
  Repeat
    Pump:=GetTickCount64; Application.ProcessMessages;
    MaxPump:=Max(MaxPump,GetTickCount64-Pump);
    MaxPaint:=Max(MaxPaint,View.LastPaintMilliseconds);
    If Ready Then Exit;
    Sleep(2);
  Until GetTickCount64>=Deadline;
  Measured:=0;
  For N:=0 To View.Layout.Count-1 Do
    If Assigned(View.Layout[N].Fragment) And
      (View.Layout[N].Fragment.NextMeasure>=View.Layout[N].Fragment.Document.Count) Then Inc(Measured);
  WriteLn('timeout measured_blocks=',Measured,'/',View.Layout.Count,
    ' pending_parser=',View.Layout.PendingWork,' max_update_ms=',View.MaxUpdateMilliseconds);
  Check('asynchronous layout completes',False);
End;
Procedure PopulateTrace;
Var Body, Row: String;
Begin
    If Kind='history' Then
      Begin
        If Size=0 Then Size:=5000;
        Body:='A **formatted** history paragraph with `code`, café and source references. '+StringOfChar('x',512);
        For I:=1 To Size Do
          Begin
            Trace.AddUser('Question '+IntToStr(I));
            Trace.EnsureAnswer.Body:=IntToStr(I)+' '+Body;
            Trace.AddTool(IntToStr(I),'read_file','{}').Body:='Completed tool result';
          End;
      End
    Else
      Begin
        If Kind='large' Then
          Begin
            If Size=0 Then Size:=8*1024*1024;
            Row:='A **formatted** paragraph with `code` and café. '+StringOfChar('x',192)+#10+#10;
            Body:=Row;
            While Length(Body)<Size Do Body+=Body;
            Body:=Copy(Body,1,(Size Div Length(Row))*Length(Row));
          End
        Else If Kind='table-cell' Then
          Begin
            If Size=0 Then Size:=256*1024;
            Body:='| Source | Detail |'+#10+'| --- | --- |'+#10+'| unit.pas | '+StringOfChar('x',Size)+' |';
          End
        Else If Kind='wide-table' Then
          Begin
            If Size=0 Then Size:=64;
            Body:='|'; Row:='|';
            For I:=1 To Size Do Begin Body+=' Column '+IntToStr(I)+' |'; Row+=' --- |'; End;
            Body+=#10+Row;
            For J:=1 To 64 Do
              Begin
                Row:='|'; For I:=1 To Size Do Row+=' **cell** '+IntToStr(J)+':'+IntToStr(I)+' |';
                Body+=#10+Row;
              End;
          End
        Else If Kind='cluster' Then
          Begin
            If Size=0 Then Size:=16384;
            Body:='x'; For I:=1 To Size Do Body+=UTF8String('́');
          End
        Else Begin WriteLn('Use history, large, table-cell, wide-table or cluster [size]'); Halt(2); End;
        Trace.EnsureAnswer.Body:=Body;
      End;
End;
Procedure CheckSources;
Var N: Integer;
Begin
  For N:=0 To Trace.Count-1 Do Check('source retained',View.Layout[N].Body=Trace[N].Body);
End;
Begin
  Application.Initialize;
  Kind:=ParamStr(1); Size:=StrToIntDef(ParamStr(2),0);
  Host:=TForm.CreateNew(Nil); Trace:=TAssistantTrace.Create;
  Try
    Host.SetBounds(0,0,900,650); Host.Show; Application.ProcessMessages;
    HeapStage('baseline');
    PopulateTrace;
    SourceBytes:=0; For I:=0 To Trace.Count-1 Do Inc(SourceBytes,Length(Trace[I].Body));
    Blocks:=Trace.Count; HeapStage('source');
    View:=TAssistantConversationSurface.Create(Host); View.Parent:=Host; View.Align:=alClient;
    Application.ProcessMessages; Started:=GetTickCount64;
    View.BeginDocument;
    For I:=0 To Trace.Count-1 Do View.AddBlock(Trace[I].ID,Trace[I]);
    View.EndDocument; SyncMS:=GetTickCount64-Started; HeapStage('initial-sync');
    AwaitLayout; HeapStage('complete-layout');
    Check('height index agrees',View.ContentHeight=View.Layout.TotalHeight);
    Check('native control count stays constant',View.ControlCount=2);
    Check('every block retained',View.Layout.Count=Blocks);
    CheckSources;
    View.JumpToEnd; AwaitLayout;
    Check('last content reachable',View.ScrollTop=Max(Int64(0),View.ContentHeight-View.ViewRect.Height));
    View.JumpToStart; AwaitLayout; Check('first content reachable',View.ScrollTop=0);
    WriteLn('profile kind=',Kind,' source_bytes=',SourceBytes,' blocks=',Blocks,
      ' sync_ms=',SyncMS,' elapsed_ms=',GetTickCount64-Started,
      ' max_pump_ms=',MaxPump,' max_paint_ms=',MaxPaint,
      ' max_update_ms=',View.MaxUpdateMilliseconds,' height=',View.ContentHeight); Flush(Output);
    FreeAndNil(View); HeapStage('view-released');
    Trace.Clear; HeapStage('source-released');
    WriteLn('PASS ',Kind); Flush(Output);
  Finally Trace.Free; Host.Free; End;
End.
