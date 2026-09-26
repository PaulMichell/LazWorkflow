Program AssistantTraceViewTest;

{$MODE OBJFPC}{$H+}

Uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Controls, SysUtils, FileUtil, Classes, FPImage, FPWritePNG,
  AssistantTrace, AssistantTraceView, AssistantConversation, AssistantImages;

Procedure Check(Const Name: String; Passed: Boolean);
Begin
  If Not Passed Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Procedure TestVisibility;
Var Host: TForm; View: TAssistantTraceView; Trace: TAssistantTrace; Tool, Answer, Thought: TTraceBlock;
  Function Visible(Block: TTraceBlock): Boolean;
  Var I: Integer;
  Begin I := View.Surface.Layout.IndexOf(Block.ID); Result := (I >= 0) And View.Surface.Layout[I].Visible; End;
Begin
  Host := TForm.CreateNew(Nil); Trace := TAssistantTrace.Create;
  Try
    Host.SetBounds(0, 0, 800, 600); View := TAssistantTraceView.Create(Host); View.Parent := Host;
    Thought := Trace.StartThinking(0); View.Sync(Trace, False);
    Check('empty running thought has no visible extent', Not Visible(Thought));
    Check('empty thought omitted from history', Pos('thinking', Trace.SaveToJson) = 0);
    Thought.Body := 'Summary arrived'; View.Sync(Trace, False); Check('thought appears when text arrives', Visible(Thought));
    Thought.Body := ''; View.Sync(Trace, False); Check('empty thought removed from layout', Not Visible(Thought));
    Tool := Trace.AddTool('call_1', 'read_file', '{}'); Tool.Body := 'saved result';
    Answer := Trace.EnsureAnswer; Answer.Body := 'The answer stays visible.'; View.Sync(Trace, False);
    Check('tool use visible by default', Visible(Tool)); View.ShowToolUse := False; View.Sync(Trace, False);
    Check('tool row hidden', Not Visible(Tool)); Check('answer stays visible', Visible(Answer));
    View.RefreshElapsed(Trace); Check('elapsed refresh keeps tools hidden', Not Visible(Tool));
    Tool := Trace.AddTool('call_2', 'get_project_info', '{}'); View.Sync(Trace, False);
    Check('new tool row stays hidden', Not Visible(Tool)); View.ShowToolUse := True; View.Sync(Trace, False);
    Check('tool rows restored', Visible(Tool) And Visible(Trace.FindTool('call_1')));
    Check('tool result retained', Trace.FindTool('call_1').Body = 'saved result');
    Check('only one output surface is hosted', View.ControlCount = 1);
  Finally Host.Free; Trace.Free; End;
End;

Procedure TestPreference;
Var
  Store: TAssistantConversationStore;
  Root, Plan: String;
  Thinking, Tools: Boolean;
  Mode: TAssistantMode;
Begin
  Root := GetTempFileName(GetTempDir, 'trace-prefs-');
  DeleteFile(Root);
  ForceDirectories(Root);
  Store := TAssistantConversationStore.Create;
  Try
    Store.SetProjectRoot(Root);
    Tools := False;
    Store.LoadShellConfig(Thinking, Mode, Plan, @Tools);
    Check('missing configuration shows tools', Tools);
    Tools := False;
    Check('save hidden preference', Store.SaveShellConfig(True, amInspect, '', @Tools));
    Check('legacy plan update', Store.SaveShellConfig(False, amPlan, 'plan.md'));
    Tools := True;
    Check('load preferences', Store.LoadShellConfig(Thinking, Mode, Plan, @Tools));
    Check('plan updates preserve hidden preference', Not Tools);
    Check('other preferences retained', (Not Thinking) And (Mode = amPlan) And (Plan = 'plan.md'));
  Finally
    Store.Free;
    DeleteDirectory(Root, False);
  End;
End;

Procedure TestConversation;
Var Host:TForm; View:TAssistantTraceView; Store,Other:TAssistantConversationStore; Trace,Live:TAssistantTrace;
  Root,OtherRoot,TurnID,FirstID:String; Turn:TConversationTurn; Entry:TConversationIndexEntry; I,CountBefore:Integer; TopBefore:Int64;
Begin
  Root:=GetTempFileName(GetTempDir,'conversation-'); DeleteFile(Root); ForceDirectories(Root);
  OtherRoot:=Root+'-other'; ForceDirectories(OtherRoot);
  Host:=TForm.CreateNew(Nil); Store:=TAssistantConversationStore.Create; Other:=TAssistantConversationStore.Create;
  Trace:=TAssistantTrace.Create; Live:=TAssistantTrace.Create;
  Try
    Store.SetProjectRoot(Root); Store.Load; Other.SetProjectRoot(OtherRoot); Other.Load;
    Host.SetBounds(0,0,800,600); View:=TAssistantTraceView.Create(Host); View.Parent:=Host; Host.Show; Application.ProcessMessages;
    For I:=0 To 19 Do
      Begin
        Trace.Clear; Trace.AddUser('Saved question '+IntToStr(I)); Trace.EnsureAnswer.Body:='Saved **answer** '+IntToStr(I);
        Turn:=Default(TConversationTurn); Turn.Id:=NewConversationTurnId; Turn.Prompt:='Question'; Turn.Response:='Answer'; Turn.TraceJson:=Trace.SaveToJson;
        If I=0 Then FirstID:=Turn.Id; If I=10 Then TurnID:=Turn.Id;
        Check('append history fixture',Store.AppendTurn(Turn,Entry));
      End;
    View.SyncConversation(Store,Nil,False); View.Surface.CompleteLayout;
    Check('continuous conversation contains every saved turn',View.Surface.Layout.Count=40);
    View.NavigateTurn(TurnID); TopBefore:=View.Surface.ScrollTop;
    Check('turn navigation leaves tail-following',Not View.Surface.FollowTail);
    Live.AddUser('Live question'); Live.EnsureAnswer.Body:='Streaming answer';
    View.SyncConversation(Store,Live,True); View.Surface.CompleteLayout;
    Check('live append preserves history reading position',Abs(View.Surface.ScrollTop-TopBefore)<=1);
    CountBefore:=View.Surface.Layout.Count;
    Turn:=Default(TConversationTurn); Turn.Id:=NewConversationTurnId; Turn.TraceJson:=Live.SaveToJson;
    Check('save live turn',Store.AppendTurn(Turn,Entry));
    View.SyncConversation(Store,Live,False); View.Surface.CompleteLayout;
    Check('saving live turn does not duplicate its blocks',View.Surface.Layout.Count=CountBefore);
    Check('saving live turn preserves anchor',Abs(View.Surface.ScrollTop-TopBefore)<=1);
    Turn:=Default(TConversationTurn); Turn.Id:=NewConversationTurnId; Turn.Prompt:='Legacy prompt'; Turn.Thinking:=''; Turn.Response:='Legacy answer';
    Check('append legacy archive fixture',Other.AppendTurn(Turn,Entry));
    View.SyncConversation(Other,Nil,False); View.Surface.CompleteLayout;
    Check('legacy history adapter preserves text',Pos('Legacy answer',View.Surface.MarkdownText)>0);
    View.SyncConversation(Store,Nil,False); View.Surface.CompleteLayout;
    Check('switching back restores reading position',Abs(View.Surface.ScrollTop-TopBefore)<=1);
    View.ResetContent; View.SyncConversation(Store,Nil,False); View.Surface.CompleteLayout;
    Check('form context reset preserves saved reading position',Abs(View.Surface.ScrollTop-TopBefore)<=1);
  Finally Host.Free; Store.Free; Other.Free; Trace.Free; Live.Free; DeleteDirectory(Root,False); DeleteDirectory(OtherRoot,False); End;
End;

Procedure TestReloadImages;
Var
  Host: TForm;
  View: TAssistantTraceView;
  Store: TAssistantConversationStore;
  Trace: TAssistantTrace;
  Root: String;
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Ref: TAssistantImageRef;
  Refs: TAssistantImageRefArray;
  I, UserIndex: Integer;
  PPI: Integer;
Begin
  Root := GetTempFileName(GetTempDir, 'reload-images-');
  DeleteFile(Root);
  ForceDirectories(Root);
  Host := TForm.CreateNew(Nil);
  Store := TAssistantConversationStore.Create;
  Trace := TAssistantTrace.Create;
  Try
    Store.SetProjectRoot(Root);
    Store.Load;
    Host.SetBounds(0, 0, 800, 600);
    View := TAssistantTraceView.Create(Host);
    View.Parent := Host;
    Host.Show;
    Application.ProcessMessages;
    Trace.AddUser('stale trace body');
    Trace.SetUserImages(['old-id'], ['old.png']);
    Trace.EnsureAnswer.Body := 'Saved answer';
    Turn := Default(TConversationTurn);
    Turn.Id := NewConversationTurnId;
    Turn.Prompt := 'Look at the diagram';
    Turn.Response := 'Saved answer';
    Ref := Default(TAssistantImageRef);
    Ref.Id := 'pic1';
    Ref.Name := 'diagram.png';
    Ref.Width := 120;
    Ref.Height := 40;
    Ref.DisplayPath := '.assistant/images/pic1.png';
    SetLength(Refs, 1);
    Refs[0] := Ref;
    Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
    Turn.TraceJson := Trace.SaveToJson;
    Check('append image turn', Store.AppendTurn(Turn, Entry));
    Trace.Clear;
    Trace.EnsureAnswer.Body := 'Answer without a stored user block';
    Turn := Default(TConversationTurn);
    Turn.Id := NewConversationTurnId;
    Turn.Prompt := '';
    Turn.Response := 'Answer without a stored user block';
    Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
    Turn.TraceJson := Trace.SaveToJson;
    Check('append image-only turn', Store.AppendTurn(Turn, Entry));
    View.SyncConversation(Store, Nil, False);
    View.Surface.CompleteLayout;
    UserIndex := -1;
    For I := 0 To View.Surface.Layout.Count - 1 Do
      If (View.Surface.Layout[I].Kind = tbkUser) And (View.Surface.Layout[I].Body = 'Look at the diagram') Then
        UserIndex := I;
    Check('reload rebuilds the user words from the prompt', UserIndex >= 0);
    Check('reload replaces trace images with attachment ids',
      (UserIndex >= 0) And (Length(View.Surface.Layout[UserIndex].Images) = 1) And
      (View.Surface.Layout[UserIndex].Images[0].Id = 'pic1') And
      (View.Surface.Layout[UserIndex].Images[0].Name = 'diagram.png'));
    Check('missing reload file is marked unavailable',
      (UserIndex >= 0) And View.Surface.Layout[UserIndex].Images[0].Missing);
    PPI := View.Surface.Layout.PixelsPerInch;
    Check('missing reload tile is in the section height',
      (UserIndex >= 0) And (View.Surface.Layout.ImageRowHeight(UserIndex) = MissingImageTileHeight(PPI)) And
      (View.Surface.Layout.Heights.Values[UserIndex] = View.Surface.Layout[UserIndex].FullHeight +
        View.Surface.Layout.ImageRowHeight(UserIndex) + 2 * View.Surface.Layout[UserIndex].Padding +
        Round(10 * PPI / 96)));
    UserIndex := -1;
    For I := 0 To View.Surface.Layout.Count - 1 Do
      If (View.Surface.Layout[I].Kind = tbkUser) And (View.Surface.Layout[I].Body = '') And
        (Length(View.Surface.Layout[I].Images) = 1) Then
        UserIndex := I;
    Check('image-only reload builds a user block from the attachment id',
      (UserIndex >= 0) And (View.Surface.Layout[UserIndex].Images[0].Id = 'pic1'));
  Finally
    Host.Free;
    Store.Free;
    Trace.Free;
    DeleteDirectory(Root, False);
  End;
End;

Procedure TestReloadPresentImage;
Var
  Host: TForm;
  View: TAssistantTraceView;
  Store: TAssistantConversationStore;
  Trace: TAssistantTrace;
  Root, ErrorText: String;
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Ref: TAssistantImageRef;
  Refs: TAssistantImageRefArray;
  Stored: TAssistantStoredImage;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Stream: TMemoryStream;
  X, Y, UserIndex, PPI, ContentW, DisplayW, DisplayH: Integer;
  Pixel: TFPColor;
Begin
  Root := GetTempFileName(GetTempDir, 'reload-present-');
  DeleteFile(Root);
  ForceDirectories(Root);
  Host := TForm.CreateNew(Nil);
  Store := TAssistantConversationStore.Create;
  Trace := TAssistantTrace.Create;
  Img := TFPMemoryImage.Create(100, 50);
  Stream := TMemoryStream.Create;
  Writer := TFPWriterPNG.Create;
  Try
    Pixel.Red := $FFFF;
    Pixel.Green := 0;
    Pixel.Blue := 0;
    Pixel.Alpha := $FFFF;
    For Y := 0 To Img.Height - 1 Do
      For X := 0 To Img.Width - 1 Do
        Img.Colors[X, Y] := Pixel;
    Img.SaveToStream(Stream, Writer);
    Stream.Position := 0;
    Check('store reload picture', StoreAssistantImageFromStream(Root, 'diagram.png', Stream, Stored, ErrorText));
    Store.SetProjectRoot(Root);
    Store.Load;
    Host.SetBounds(0, 0, 800, 600);
    View := TAssistantTraceView.Create(Host);
    View.Parent := Host;
    Host.Show;
    Application.ProcessMessages;
    Trace.EnsureAnswer.Body := 'Saved answer';
    Turn := Default(TConversationTurn);
    Turn.Id := NewConversationTurnId;
    Turn.Prompt := 'Look at the diagram';
    Turn.Response := 'Saved answer';
    Ref := Default(TAssistantImageRef);
    Ref.Id := Stored.Id;
    Ref.Name := Stored.OriginalName;
    Ref.Width := Stored.Width;
    Ref.Height := Stored.Height;
    Ref.DisplayPath := Stored.DisplayRelativePath;
    SetLength(Refs, 1);
    Refs[0] := Ref;
    Turn.AttachmentsJson := AssistantImageRefsToJson(Refs);
    Turn.TraceJson := Trace.SaveToJson;
    Check('append present image turn', Store.AppendTurn(Turn, Entry));
    View.SyncConversation(Store, Nil, False);
    View.Surface.CompleteLayout;
    UserIndex := -1;
    For X := 0 To View.Surface.Layout.Count - 1 Do
      If (View.Surface.Layout[X].Kind = tbkUser) And (View.Surface.Layout[X].Body = 'Look at the diagram') Then
        UserIndex := X;
    PPI := View.Surface.Layout.PixelsPerInch;
    ContentW := 1;
    DisplayW := 0;
    DisplayH := 0;
    If UserIndex >= 0 Then ContentW := View.Surface.Layout.ImageContentWidth(UserIndex);
    Check('reload keeps a present file',
      (UserIndex >= 0) And (Length(View.Surface.Layout[UserIndex].Images) = 1) And
      (View.Surface.Layout[UserIndex].Images[0].Id = Stored.Id) And
      (Not View.Surface.Layout[UserIndex].Images[0].Missing) And
      (View.Surface.Layout[UserIndex].Images[0].DisplayPath = Stored.DisplayRelativePath));
    Check('present reload height follows the known image size',
      (UserIndex >= 0) And ScaledImageExtent(Stored.Width, Stored.Height, ContentW, PPI, DisplayW, DisplayH) And
      (View.Surface.Layout.ImageRowHeight(UserIndex) = UserImageSlotHeight(View.Surface.Layout[UserIndex].Images[0], ContentW, PPI)) And
      (View.Surface.Layout.ImageRowHeight(UserIndex) <> MissingImageTileHeight(PPI)));
  Finally
    Writer.Free;
    Stream.Free;
    Img.Free;
    Host.Free;
    Store.Free;
    Trace.Free;
    DeleteDirectory(Root, False);
  End;
End;

Begin
  Application.Initialize;
  TestVisibility;
  TestPreference;
  TestConversation;
  TestReloadImages;
  TestReloadPresentImage;
  WriteLn('All AssistantTraceView tests passed.');
End.
