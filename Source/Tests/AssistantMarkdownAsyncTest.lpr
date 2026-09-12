Program AssistantMarkdownAsyncTest;
{$mode objfpc}{$H+}{$codepage utf8}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, Graphics,
  StyledTextTypes, StyledTextDocument, StyledMarkdown, AssistantTrace, AssistantConversationSurface;
Procedure Check(Const Name: String; Passed: Boolean);
Begin
  If Not Passed Then Begin WriteLn('FAIL ',Name); Halt(1); End;
  WriteLn('ok ',Name); Flush(Output);
End;
Var Host: TForm; View: TAssistantConversationSurface; Trace: TAssistantTrace;
  Block: TTraceBlock; Body, Latest, OldKey: String; I,J: Integer;
  BeforeTop: Int64; Started, Deadline, CountBefore, MaxPumpMs: QWord;
  Expected: TStyledContent; Parsed: TParsedStyledMarkdown;
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
    Block.Body:=Latest+#10+'## A larger heading'; Sync;
    View.Font.Size:=14; Host.Width:=650;
    AwaitLatest;
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
