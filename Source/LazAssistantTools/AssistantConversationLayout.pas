Unit AssistantConversationLayout;
{ Data-only Markdown fragments and a single index of effective block heights. }
{$mode objfpc}{$H+}{$codepage utf8}
Interface
Uses Classes, SysUtils, Contnrs, Types, StyledTextTypes, StyledTextDocument,
  StyledCanvas, StyledMemoLayout, AssistantTrace, AssistantMarkdownWorker;
Type
  TConversationFragment = Class
  Public
    Document: TStyledDocument;
    Layout: TStyledMemoLayout;
    Width, NextMeasure: Integer;
    Generation: QWord;
    Constructor Create(Renderer: TStyledCanvas; Const Content: TStyledContent; AWidth: Integer);
    Destructor Destroy; Override;
    Function Height: Int64;
    Function Prepare(Top, Bottom: Int64; Finish: Boolean): Boolean;
    Procedure EvictDrawings;
    Procedure RetainDrawings(First, Last: Integer);
  End;
  TConversationSection = Class
  Public
    Key, Title, Body, Footer: String;
    Kind: TTraceBlockKind;
    Collapsed, UserCollapsed, Running, OK, Visible: Boolean;
    Full, Short: TConversationFragment;
    FullHeight, ShortHeight: Int64;
    Left, OuterWidth, Padding: Integer;
    Seen, Identity, Version, ParsedVersion, FullVersion: QWord;
    ParsedBaseSize: Integer;
    BodyContent: TStyledContent;
    Destructor Destroy; Override;
    Procedure Invalidate;
    Function Fragment: TConversationFragment;
  End;
  TConversationLayout = Class
  Private
    FSections: TFPList;
    Lookup: TStringList;
    Renderer: TStyledCanvas;
    FWidth, FBaseSize: Integer;
    FGeneration, SyncGeneration: QWord;
    FShowThinking, FShowTools: Boolean;
    FParseCount, Epoch, NextIdentity: QWord;
    Worker: TAssistantMarkdownWorker;
    Procedure PollParser;
    Procedure RequestParse(Section: TConversationSection);
    Function GetPendingWork: Boolean;
    Function GetSection(Index: Integer): TConversationSection;
    Function BuildContent(Section: TConversationSection; Short: Boolean; BodyReady: Boolean = True): TStyledContent;
  Public
    Heights: TStyledHeightIndex;
    Constructor Create(ARenderer: TStyledCanvas);
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure BeginSync;
    Procedure Add(Const Key: String; Block: TTraceBlock);
    Procedure EndSync;
    Procedure Configure(Width, BaseSize: Integer; ShowThinking, ShowTools: Boolean);
    Procedure Reindex;
    Function PrepareSection(Index: Integer; Top, Bottom: Int64; Finish: Boolean = False): Boolean;
    Procedure TrimDrawings(FirstVisible, LastVisible: Integer; ViewTop, ViewBottom: Int64);
    Function IndexOf(Const Key: String): Integer;
    Function Count: Integer;
    Function TotalHeight: Int64;
    Function Top(Index: Integer): Int64;
    Function AtY(Y: Int64): Integer;
    Property Sections[Index: Integer]: TConversationSection Read GetSection; Default;
    Property PendingWork: Boolean Read GetPendingWork;
    Property ParseCount: QWord Read FParseCount;
  End;
Implementation
Uses Math, Graphics, StyledMarkdown;
Constructor TConversationFragment.Create(Renderer: TStyledCanvas; Const Content: TStyledContent; AWidth: Integer);
Begin
  Inherited Create; Document := TStyledDocument.Create;
  Document.Replace(StyledPosition(0,0), Document.EndPosition, Content);
  Layout := TStyledMemoLayout.Create(Document, Renderer); Width := AWidth;
  Generation := Renderer.Generation; Layout.Reset(Width, True, 24);
End;
Destructor TConversationFragment.Destroy;
Begin Layout.Free; Document.Free; Inherited Destroy; End;
Function TConversationFragment.Height: Int64;
Begin Result := HeightBefore(Layout.Heights, Document.Count); End;
Procedure TConversationFragment.EvictDrawings;
Begin RetainDrawings(-1,-1); End;
Procedure TConversationFragment.RetainDrawings(First, Last: Integer);
Var I: Integer;
Begin
  For I:=0 To High(Layout.Paragraphs) Do
    If ((I<First) Or (I>Last)) And (I<>NextMeasure) Then FreeAndNil(Layout.Paragraphs[I]);
End;
Function TConversationFragment.Prepare(Top, Bottom: Int64; Finish: Boolean): Boolean;
Var I: Integer; Deadline: QWord;
Begin
  Deadline := GetTickCount64 + 8;
  I := ItemAtHeight(Layout.Heights, Max(Int64(0), Top));
  While I < Document.Count Do
    Begin
      If (HeightBefore(Layout.Heights, I) > Bottom) And Not Finish Then Break;
      Layout.Ensure(I, Finish);
      If Not Finish And (GetTickCount64 >= Deadline) Then Break;
      Inc(I);
    End;
  { Measure remaining paragraphs incrementally, including offscreen text in a
    tall block. Preserve measurements separately from disposable drawing runs. }
  While (NextMeasure < Document.Count) And (Finish Or (GetTickCount64 < Deadline)) Do
    Begin
      Layout.Ensure(NextMeasure, Finish);
      If Not Layout.Paragraphs[NextMeasure].Complete Then Break;
      Inc(NextMeasure);
    End;
  Result := NextMeasure >= Document.Count;
End;
Destructor TConversationSection.Destroy;
Begin Full.Free; Short.Free; Inherited Destroy; End;
Procedure TConversationSection.Invalidate;
Begin FreeAndNil(Full); FreeAndNil(Short); FullHeight := 28; ShortHeight := 28; End;
Function TConversationSection.Fragment: TConversationFragment;
Begin If Collapsed Then Result := Short Else Result := Full; End;
Constructor TConversationLayout.Create(ARenderer: TStyledCanvas);
Begin
  Inherited Create; Renderer := ARenderer; FSections := TFPList.Create;
  Lookup := TStringList.Create; Lookup.Sorted := True; Lookup.CaseSensitive := True;
  FWidth := 1; FBaseSize := 10; FShowThinking := True; FShowTools := True;
End;
Destructor TConversationLayout.Destroy;
Begin Worker.Free; Worker:=Nil; Clear; Lookup.Free; FSections.Free; Inherited Destroy; End;
Procedure TConversationLayout.Clear;
Var I: Integer;
Begin
  Inc(Epoch);
  If Assigned(Worker) Then Worker.Cancel;
  For I := 0 To Lookup.Count - 1 Do Lookup.Objects[I].Free;
  Lookup.Clear; FSections.Clear; ResetHeights(Heights, 0, 0);
End;
Procedure TConversationLayout.BeginSync;
Begin Inc(SyncGeneration); FSections.Clear; End;
Procedure TConversationLayout.Add(Const Key: String; Block: TTraceBlock);
Var I: Integer; Section: TConversationSection; DisplayTitle: String;
  Procedure UpdateTitle(Fragment: TConversationFragment; IsShort: Boolean);
  Var Value: String; Style: Integer;
  Begin
    If Not Assigned(Fragment) Then Exit;
    Value := DisplayTitle;
    If Block.Kind In [tbkThinking,tbkTool,tbkSubagent] Then
      Begin If IsShort Then Value := UTF8String('▸ ') + Value Else Value := UTF8String('▾ ') + Value; End;
    Style := 0; If Length(Fragment.Document[0]^.Ranges)>0 Then Style := Fragment.Document[0]^.Ranges[0].Style;
    Fragment.Document.ReplaceText(StyledPosition(0,0), StyledPosition(0,Length(Fragment.Document[0]^.Text)), Value, Style);
    Fragment.Layout.DocumentChanged(0,1,1); Fragment.NextMeasure := 0;
  End;
Begin
  DisplayTitle := Block.Title;
  If Block.Kind In [tbkTool,tbkSubagent] Then
    Begin
      If Block.Running Then DisplayTitle += UTF8String(' …');
      If Block.DurationMs>0 Then DisplayTitle += '  '+FormatThoughtElapsed(Block.DurationMs);
      If Not Block.OK Then DisplayTitle += UTF8String(' — failed');
    End;
  I := Lookup.IndexOf(Key);
  If I < 0 Then
    Begin
      Section := TConversationSection.Create; Section.Key := Key; Section.Invalidate;
      Inc(NextIdentity); Section.Identity:=NextIdentity; Section.Version:=1;
      Section.Collapsed := Block.Collapsed; Lookup.AddObject(Key, Section);
    End
  Else Section := TConversationSection(Lookup.Objects[I]);
  If Section.Seen = SyncGeneration Then Exit;
  Section.Seen := SyncGeneration;
  If Section.Body<>Block.Body Then Inc(Section.Version);
  If (Section.Kind<>Block.Kind) Or (Section.Footer<>Block.Footer) Or
    ((Section.Title='')<>(DisplayTitle='')) Then Section.Invalidate
  Else If Section.Body<>Block.Body Then
    Begin
      { Keep the last completed full document while a large replacement parses.
        Short thinking remains cheap and is rebuilt from the latest source. }
      If (Length(Block.Body)>=65536) And Not (Block.Kind In [tbkTool,tbkSteer]) Then
        Begin FreeAndNil(Section.Short); Section.ShortHeight:=28; End
      Else Section.Invalidate;
    End;
  If Section.Title<>DisplayTitle Then
    Begin UpdateTitle(Section.Full,False); UpdateTitle(Section.Short,True); End;
  Section.Kind := Block.Kind; Section.Title := DisplayTitle; Section.Body := Block.Body; Section.Footer := Block.Footer;
  Section.Running := Block.Running; Section.OK := Block.OK;
  If Not Section.UserCollapsed Then
    Section.Collapsed := (Block.Kind In [tbkTool,tbkSubagent]) Or Block.Collapsed;
  FSections.Add(Section);
End;
Procedure TConversationLayout.EndSync;
Var I: Integer;
Begin
  For I := Lookup.Count - 1 DownTo 0 Do
    If TConversationSection(Lookup.Objects[I]).Seen <> SyncGeneration Then
      Begin Lookup.Objects[I].Free; Lookup.Delete(I); End;
  Reindex;
End;
Procedure TConversationLayout.Configure(Width, BaseSize: Integer; ShowThinking, ShowTools: Boolean);
Var I: Integer;
Begin
  Width := Max(1, Width);
  If (FWidth <> Width) Or (FBaseSize <> BaseSize) Or (FGeneration <> Renderer.Generation) Then
    Begin
      FWidth := Width; FBaseSize := BaseSize; FGeneration := Renderer.Generation;
      For I := 0 To Count - 1 Do Sections[I].Invalidate;
    End;
  FShowThinking := ShowThinking; FShowTools := ShowTools; Reindex;
End;
Procedure TConversationLayout.Reindex;
Var I, LastVisible: Integer; Section: TConversationSection; H: Int64;
Begin
  ResetHeights(Heights, Count, 0); LastVisible := -1;
  For I := 0 To Count - 1 Do
    Begin
      Section := Sections[I];
      Section.Left := 0; Section.OuterWidth := FWidth; Section.Padding := 0;
      If Section.Kind In [tbkUser,tbkAnswer] Then
        Begin
          Section.Padding := Min(12, Max(0, (FWidth-1) Div 4));
          If Section.Kind=tbkUser Then Section.OuterWidth := Max(1, FWidth*85 Div 100)
          Else Section.OuterWidth := Max(1, FWidth*95 Div 100);
          If Section.Kind=tbkUser Then Section.Left := FWidth-Section.OuterWidth;
        End;
      Section.Visible := Not ((Section.Kind = tbkThinking) And ((Not FShowThinking) Or (Trim(Section.Body) = ''))) And
        Not ((Section.Kind In [tbkTool, tbkSubagent]) And Not FShowTools) And
        Not ((Section.Kind = tbkAnswer) And (Trim(Section.Body) = '') And (Section.Footer = ''));
      If Not Section.Visible Then Continue;
      If Section.Collapsed Then H := Section.ShortHeight Else H := Section.FullHeight;
      SetHeight(Heights, I, Max(Int64(1), H) + Section.Padding*2 + 10); LastVisible := I;
    End;
  If LastVisible >= 0 Then SetHeight(Heights, LastVisible, Heights.Values[LastVisible] - 10);
End;
Function TConversationLayout.BuildContent(Section: TConversationSection; Short: Boolean; BodyReady: Boolean): TStyledContent;
Var Part: TStyledContent; Style: TStyledStyle; N,I: Integer; Text: String;
  Procedure Append(Const Content: TStyledContent);
  Var J,Offset: Integer;
  Begin
    Offset := Length(Result); SetLength(Result, Offset + Length(Content));
    For J := 0 To High(Content) Do Result[Offset + J] := Content[J];
  End;
Begin
  Result := Nil; Style := DefaultStyledStyle; Style.Size := FBaseSize;
  If Section.Kind In [tbkThinking, tbkWorked] Then Style.Foreground := clGrayText;
  If Section.Title <> '' Then
    Begin
      Style.Styles := [fsBold]; If Not Section.OK Then Style.Foreground := clMaroon; Text := Section.Title;
      If Section.Kind In [tbkThinking, tbkTool, tbkSubagent] Then
        Begin If Section.Collapsed Then Text := UTF8String('▸ ') + Text Else Text := UTF8String('▾ ') + Text; End;
      Part := StyledContentFromText(Text, Renderer.AddStyle(Style)); Part[0].Box.Group:=1; Part[0].Box.Style:=DefaultStyledBoxStyle; Part[0].Box.Style.Margin.Bottom:=6;
      If Section.Kind In [tbkTool,tbkSubagent] Then Part[0].Box.Style.Background:=$F4F4F4;
      Append(Part); Style.Styles := []; Style.Foreground:=clDefault;
    End;
  Text := Section.Body;
  If Not BodyReady Then Text:='';
  If Short And (Section.Kind In [tbkTool, tbkSubagent]) Then Text := ''
  Else If Short And (Section.Kind = tbkThinking) And (Length(Text) > 2000) Then Text := Copy(Text, Length(Text)-1999, 2000);
  If Text <> '' Then
    Begin
      If Section.Kind In [tbkTool, tbkSteer] Then Part := StyledContentFromText(Text, Renderer.AddStyle(Style))
      Else If Not Short And (Section.ParsedVersion>0) And (Section.ParsedBaseSize=FBaseSize) Then
        Part:=Copy(Section.BodyContent)
      Else Begin Part := BuildStyledMarkdown(Renderer, Text, FBaseSize); Inc(FParseCount); End;
      { Parser box groups are fragment-local. Shift them past the title. }
      For I := 0 To High(Part) Do If Part[I].Box.Group <> 0 Then Inc(Part[I].Box.Group);
      Append(Part);
    End;
  If (Section.Footer <> '') And Not Short Then
    Begin Style.Styles := [fsItalic]; Style.Foreground := clGrayText; Append(StyledContentFromText(Section.Footer, Renderer.AddStyle(Style))); End;
  If Length(Result) = 0 Then Result := StyledContentFromText('');
  For N := 0 To High(Result) Do
    If Result[N].Box.Group = 0 Then Result[N].Box.Style.Margin.Bottom := 6;
End;
Function TConversationLayout.GetPendingWork: Boolean;
Begin Result:=Assigned(Worker) And Worker.Busy; End;

Procedure TConversationLayout.RequestParse(Section: TConversationSection);
Var Job: TAssistantMarkdownJob;
Begin
  If Not Assigned(Worker) Then Worker:=TAssistantMarkdownWorker.Create;
  If Worker.Busy Then Exit;
  Job:=TAssistantMarkdownJob.Create;
  Job.Key:=Section.Key; Job.Source:=Section.Body;
  Job.Epoch:=Epoch; Job.Identity:=Section.Identity; Job.Version:=Section.Version;
  Job.BaseSize:=FBaseSize;
  If Not Worker.Submit(Job) Then Job.Free;
End;

Procedure TConversationLayout.PollParser;
Var Job: TAssistantMarkdownJob; I: Integer; Section: TConversationSection;
Begin
  If Not Assigned(Worker) Then Exit;
  Job:=Worker.Take;
  If Not Assigned(Job) Then Exit;
  Try
    If Job.Cancelled Or (Job.Epoch<>Epoch) Or (Job.BaseSize<>FBaseSize) Then Exit;
    I:=Lookup.IndexOf(Job.Key);
    If I<0 Then Exit;
    Section:=TConversationSection(Lookup.Objects[I]);
    If (Section.Identity<>Job.Identity) Or ((Job.Version<=Section.ParsedVersion) And (Job.BaseSize=Section.ParsedBaseSize)) Or
      ((Job.Version<>Section.Version) And (Length(Section.Body)<65536)) Then Exit;
    { A completed snapshot may be displayed while a newer streaming snapshot is
      pending. Identity and epoch checks prevent cross-conversation reuse. }
    If Assigned(Job.Parsed) Then Section.BodyContent:=Job.Parsed.Bind(Renderer)
    Else Section.BodyContent:=StyledContentFromText(Job.Source);
    Section.ParsedVersion:=Job.Version; Section.ParsedBaseSize:=Job.BaseSize;
    Inc(FParseCount);
  Finally Job.Free; End;
End;

Function TConversationLayout.PrepareSection(Index: Integer; Top, Bottom: Int64; Finish: Boolean): Boolean;
Var Section: TConversationSection; Fragment: TConversationFragment;
  MarkdownBody, LargeBody, BodyReady, Pending: Boolean;
Begin
  PollParser;
  Result:=True;
  If (Index<0) Or (Index>=Count) Then Exit;
  Section:=Sections[Index];
  If Not Section.Visible Then Exit;
  MarkdownBody:=Not Section.Collapsed And Not (Section.Kind In [tbkTool,tbkSteer]);
  LargeBody:=MarkdownBody And (Length(Section.Body)>=65536);
  Pending:=False;
  If MarkdownBody And ((Section.ParsedVersion<>Section.Version) Or (Section.ParsedBaseSize<>FBaseSize)) Then
    Begin
      If LargeBody And Not Finish Then
        Begin RequestParse(Section); Pending:=True; End
      Else
        Begin
          Section.BodyContent:=BuildStyledMarkdown(Renderer,Section.Body,FBaseSize);
          Section.ParsedVersion:=Section.Version; Section.ParsedBaseSize:=FBaseSize;
          Inc(FParseCount);
        End;
    End;
  BodyReady:=Not MarkdownBody Or ((Section.ParsedVersion>0) And (Section.ParsedBaseSize=FBaseSize));
  If MarkdownBody And Assigned(Section.Full) And BodyReady And
    (Section.FullVersion<>Section.ParsedVersion) Then FreeAndNil(Section.Full);
  Fragment:=Section.Fragment;
  If Not Assigned(Fragment) Then
    Begin
      Fragment:=TConversationFragment.Create(Renderer,BuildContent(Section,Section.Collapsed,BodyReady),
        Max(1,Section.OuterWidth-Section.Padding*2));
      If Section.Collapsed Then Section.Short:=Fragment
      Else Begin Section.Full:=Fragment; If BodyReady Then Section.FullVersion:=Section.ParsedVersion Else Section.FullVersion:=0; End;
    End;
  Result:=Fragment.Prepare(Top-Section.Padding,Bottom-Section.Padding,Finish) And Not Pending;
  If Section.Collapsed Then Section.ShortHeight:=Fragment.Height Else Section.FullHeight:=Fragment.Height;
End;
Procedure TConversationLayout.TrimDrawings(FirstVisible, LastVisible: Integer; ViewTop, ViewBottom: Int64);
Var I,A,B: Integer; Fragment:TConversationFragment;
Begin
  For I:=0 To Count-1 Do
    Begin
      Fragment:=Sections[I].Fragment;
      If Assigned(Sections[I].Full) And (Sections[I].Full<>Fragment) Then Sections[I].Full.EvictDrawings;
      If Assigned(Sections[I].Short) And (Sections[I].Short<>Fragment) Then Sections[I].Short.EvictDrawings;
      If Not Assigned(Fragment) Then Continue;
      If Not Sections[I].Visible Or (I<FirstVisible) Or (I>LastVisible) Then Fragment.EvictDrawings
      Else
        Begin
          A:=ItemAtHeight(Fragment.Layout.Heights,Max(Int64(0),ViewTop-Top(I)-Sections[I].Padding-200));
          B:=ItemAtHeight(Fragment.Layout.Heights,Max(Int64(0),ViewBottom-Top(I)-Sections[I].Padding+200));
          Fragment.RetainDrawings(Max(0,A-2),Min(Fragment.Document.Count-1,B+2));
        End;
    End;
End;
Function TConversationLayout.IndexOf(Const Key: String): Integer;
Var I: Integer;
Begin Result := -1; For I := 0 To Count - 1 Do If Sections[I].Key = Key Then Exit(I); End;
Function TConversationLayout.GetSection(Index: Integer): TConversationSection;
Begin Result := TConversationSection(FSections[Index]); End;
Function TConversationLayout.Count: Integer;
Begin Result := FSections.Count; End;
Function TConversationLayout.TotalHeight: Int64;
Begin Result := HeightBefore(Heights, Count); End;
Function TConversationLayout.Top(Index: Integer): Int64;
Begin Result := HeightBefore(Heights, Index); End;
Function TConversationLayout.AtY(Y: Int64): Integer;
Begin
  Result := ItemAtHeight(Heights, Max(Int64(0), Y));
  While (Result < Count) And Not Sections[Result].Visible Do Inc(Result);
  If Result >= Count Then Result := -1;
End;
End.
