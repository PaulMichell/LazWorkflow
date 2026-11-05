Program MarkdownLayoutTest;

{ Console checks for the compact StyledMarkdown reader (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Graphics, Classes, SysUtils, StyledTextTypes, StyledTextDocument, StyledCanvas, StyledMemoLayout, StyledMarkdown,
  AssistantProtocol, AssistantSampler;

Var
  FailCount: Integer;
  Renderer: TStyledCanvas;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Function Plain(Const Content: TStyledContent): UTF8String;
Var
  Index: Integer;
Begin
  Result := '';
  For Index := 0 To High(Content) Do
    Begin
      If Index > 0 Then
        Result += #10;
      Result += Content[Index].Text;
    End;
End;

Function Parse(Const MarkdownText: UTF8String): TStyledContent;
Begin
  Result := BuildStyledMarkdown(Renderer, MarkdownText, 10);
End;

Function StyleFor(Const Content: TStyledContent; Const WordText: UTF8String): TStyledStyle;
Var
  Paragraph: TStyledParagraph;
  Range: TStyledRange;
  Offset: Integer;
Begin
  For Paragraph In Content Do
    Begin
      Offset := Pos(WordText, Paragraph.Text) - 1;
      If Offset < 0 Then
        Continue;
      For Range In Paragraph.Ranges Do
        If (Offset >= Range.Start) And (Offset < Range.Start + Range.Count) Then
          Exit(Renderer.StyleInfo[Range.Style]);
    End;
  Result := DefaultStyledStyle;
End;

Procedure TestRendererDPI;
Const Resolutions: Array[0..3] Of Integer = (96,144,192,96);
Var Bitmap: TBitmap; Font: TFont; Layout: TStyledLayout;
  Content: TStyledContent; Generation: QWord; NormalHeight: Int64; PPI,I: Integer;
Begin
  Bitmap:=TBitmap.Create; Font:=TFont.Create; Layout:=TStyledLayout.Create;
  Try
    Bitmap.SetSize(400,200); Font.Name:='DejaVu Sans';
    Content:=StyledContentFromText('DPI measurement'); NormalHeight:=0;
    For I:=0 To High(Resolutions) Do
      Begin
        PPI:=Resolutions[I];
        Font.PixelsPerInch:=PPI; Font.Size:=12;
        Renderer.Configure(Bitmap.Canvas,Font); Generation:=Renderer.Generation;
        Renderer.Prepare(Layout,Content[0],1000,swNone);
        If NormalHeight=0 Then NormalHeight:=Layout.Height
        Else If PPI=96 Then Check('returning to 96 DPI restores text height',Layout.Height=NormalHeight)
        Else Check('higher DPI increases text height',Layout.Height>NormalHeight);
        Renderer.Configure(Bitmap.Canvas,Font);
        Check('repeated configure preserves the DPI generation',Renderer.Generation=Generation);
      End;
  Finally Layout.Free; Font.Free; Bitmap.Free; End;
End;

Procedure TestSoftAndHardBreaks;
Var
  Content: TStyledContent;
Begin
  Content := Parse('hello' + LineEnding + 'world');
  Check('soft break joins with a space', Plain(Content) = 'hello world');
  Content := Parse('alpha  ' + LineEnding + 'bravo');
  Check('two-space break is a new paragraph', Plain(Content) = 'alpha' + #10 + 'bravo');
  Check('two-space break does not paint <br', Pos('<br', LowerCase(Plain(Content))) = 0);
End;

Procedure TestInlineCodeAndPunctuation;
Var
  Content: TStyledContent;
Begin
  Content := Parse('see `name`.');
  Check('copy keeps name. without an extra space', Pos('name.', Plain(Content)) > 0);
  Check('copy does not insert name .', Pos('name .', Plain(Content)) = 0);
  Check('code run is not a bare backtick', Pos('`', Plain(Content)) = 0);
  Check('inline code uses monospace', StyleFor(Content, 'name').FontName = 'Monospace');
  Content := Parse('hello , world');
  Check('plain comma keeps source space', Pos('hello ,', Plain(Content)) > 0);
  Check('plain comma does not glue hello,', Pos('hello,', Plain(Content)) = 0);
  Content := Parse('No `.lpi`. Files: `a.pas`, `b.lfm`.');
  Check('tight has no space before period', Pos('.lpi.', Plain(Content)) > 0);
  Check('tight has no space before comma', Pos('.pas,', Plain(Content)) > 0);
End;

Procedure TestEmphasisAndHeading;
Var
  Content: TStyledContent;
  Heading: TStyledStyle;
Begin
  Content := Parse('# Title' + LineEnding + LineEnding + 'café **bold** *italic* ~~gone~~');
  Heading := StyleFor(Content, 'Title');
  Check('heading is bold', fsBold In Heading.Styles);
  Check('heading is larger than body', Heading.Size > 10);
  Check('strong', fsBold In StyleFor(Content, 'bold').Styles);
  Check('emphasis', fsItalic In StyleFor(Content, 'italic').Styles);
  Check('strikeout', fsStrikeOut In StyleFor(Content, 'gone').Styles);
  Check('utf-8 prose is kept', Pos('café', Plain(Content)) > 0);
End;

Procedure TestLiteralUnsupported;
Var
  Content: TStyledContent;
Begin
  Content := Parse('hi &#x1F600; there');
  Check('numeric entities stay literal', Pos('&#x1F600;', Plain(Content)) > 0);
  Content := Parse('alpha<br/>bravo');
  Check('html br stays visible as source', Pos('<br', LowerCase(Plain(Content))) > 0);
  Content := Parse('[guide](docs/guide.md)');
  Check('links stay visible as source', Pos('[guide](docs/guide.md)', Plain(Content)) > 0);
  Content := Parse('---' + LineEnding + 'title: Hidden' + LineEnding + '---' + LineEnding + LineEnding + 'Visible');
  Check('frontmatter remains visible', Pos('title: Hidden', Plain(Content)) > 0);
  Check('body after frontmatter is kept', Pos('Visible', Plain(Content)) > 0);
End;

Procedure TestListsAndCodeFence;
Var
  Content: TStyledContent;
Begin
  Content := Parse('- `Card.SetBounds` is called.');
  Check('list item has a bullet', Pos('• ', Plain(Content)) = 1);
  Check('list item keeps inline code', Pos('Card.SetBounds', Plain(Content)) > 0);
  Check('mixed-style list has several ranges', Length(Content[0].Ranges) >= 2);
  Content := Parse('```' + LineEnding + '  a &amp; b' + LineEnding + LineEnding + 'c' + LineEnding + '```');
  Check('fenced code preserves whitespace', Plain(Content) = '  a &amp; b' + #10#10 + 'c');
  Check('fenced lines share a box group', (Length(Content) = 3) And (Content[0].Box.Group = Content[2].Box.Group));
End;

Procedure TestTables;
Var
  Content: TStyledContent;
Begin
  Content := Parse('| A | B |' + LineEnding + '| --- | --- |' + LineEnding + '| one | **two** |');
  Check('tables become tab-separated rows', Plain(Content) = 'A' + #9 + 'B' + #10 + 'one' + #9 + 'two');
  Check('table header is bold', fsBold In StyleFor(Content, 'A').Styles);
  Check('cell inline formatting', fsBold In StyleFor(Content, 'two').Styles);
  Check('column metadata is kept', (Length(Content[0].Box.Columns) = 2) And (Length(Content[1].Box.Columns) = 2));
End;

Procedure TestStreamedTables;
Const Markdown = '| Unit | Interface | Implementation |' + #10 +
  '|---|---|---|' + #10 + '| **First** | `Classes` | `SysUtils` |' + #10#10 +
  'Another table:' + #10#10 + '| Unit | Interface | Implementation |' + #10 +
  '|---|---|---|' + #10 + '| **Second** | `Classes` | `SysUtils` |';
Var
  Parser: TAssistantSseParser;
  Content: TStyledContent;
  I, Rows: Integer;
Begin
  Parser := TAssistantSseParser.Create;
  Try
    { Single-character tokens exercise repeated pipes, dashes, stars and LF. }
    For I := 1 To Length(Markdown) Do
      Parser.Feed('data: {"type":"response.output_text.delta","item_id":"m","delta":"' +
        JsonEscapeText(Markdown[I]) + '"}' + #10);
    Content := Parse(Parser.Content);
    Rows := 0;
    For I := 0 To High(Content) Do
      If Length(Content[I].Box.Columns) = 3 Then Inc(Rows);
    Check('both streamed tables render three columns', Rows = 4);
    Check('first streamed table retains bold', fsBold In StyleFor(Content, 'First').Styles);
    Check('second streamed table retains bold', fsBold In StyleFor(Content, 'Second').Styles);
  Finally Parser.Free; End;
End;

Type
  TCancelProbe = Class
    Function Cancelled: Boolean;
  End;
Function TCancelProbe.Cancelled: Boolean;
Begin Result:=True; End;
Procedure TestDetachedParsing;
Var Parsed: TParsedStyledMarkdown; Content, Again: TStyledContent;
  Other: TStyledCanvas; Style: TStyledStyle; Probe: TCancelProbe; Aborted: Boolean;
Begin
  Parsed:=ParseStyledMarkdown('**bold** and `code`');
  Other:=TStyledCanvas.Create;
  Try
    Style:=DefaultStyledStyle; Style.Size:=42; Other.AddStyle(Style);
    Content:=Parsed.Bind(Renderer); Again:=Parsed.Bind(Other);
    Check('detached Markdown binds to different registries',Plain(Content)=Plain(Again));
    Check('binding preserves bold values',fsBold In Other.StyleInfo[Again[0].Ranges[0].Style].Styles);
    Check('binding leaves local style IDs intact',Parsed.Content[0].Ranges[0].Style=0);
    Again:=Parsed.Bind(Renderer);
    Check('repeat binding preserves styles',Again[0].Ranges[0].Style=Content[0].Ranges[0].Style);
  Finally Other.Free; Parsed.Free; End;
  Probe:=TCancelProbe.Create; Aborted:=False;
  Try
    Try Parsed:=ParseStyledMarkdown('cancelled',10,@Probe.Cancelled); Parsed.Free;
    Except On E: EAbort Do Aborted:=True; End;
    Check('cancelled parse aborts without a renderer',Aborted);
  Finally Probe.Free; End;
End;

Procedure TestOversizedCluster;
Var Bitmap:TBitmap; Canvas:TStyledCanvas; Layout:TStyledLayout;
  Content:TStyledContent; Text:UTF8String; I:Integer;
Begin
  Text:='x'; For I:=1 To 4096 Do Text+=UTF8String('́');
  Bitmap:=TBitmap.Create; Canvas:=TStyledCanvas.Create; Layout:=TStyledLayout.Create;
  Try
    Bitmap.SetSize(400,100); Canvas.Configure(Bitmap.Canvas,Bitmap.Canvas.Font);
    Content:=StyledContentFromText(Text);
    Canvas.Prepare(Layout,Content[0],300,swWord);
    Check('oversized combining cluster stays in one drawing run',
      (Layout.RunCount=1) And (Layout.Runs[0].Start=0) And (Layout.Runs[0].Count=Length(Text)));
    Check('oversized cluster preserves complete source',Layout.Source=Text);
  Finally Layout.Free; Canvas.Free; Bitmap.Free; End;
End;

Procedure TestIncrementalTable;
Var Bitmap: TBitmap; Canvas: TStyledCanvas; Partial, Whole: TStyledLayout;
  Content: TStyledContent; I, J, Steps: Integer; Deadline: QWord;
Begin
  Bitmap:=TBitmap.Create; Canvas:=TStyledCanvas.Create;
  Partial:=TStyledLayout.Create; Whole:=TStyledLayout.Create;
  Try
    Bitmap.SetSize(600,300); Canvas.Configure(Bitmap.Canvas,Bitmap.Canvas.Font);
    Content:=BuildStyledMarkdown(Canvas,'| First | Second |'+#10+'| :---: | ---: |'+#10+
      '| '+StringOfChar('x',262144)+' | right aligned |',10);
    I:=High(Content);
    Check('large table fixture parsed',Length(Content[I].Box.Columns)=2);
    Canvas.BeginLayout(Partial,Content[I],400,swWord);
    Check('table initialisation defers cell measurement',
      Not Partial.Complete And (Partial.Cells[0].LineCount=0));
    Canvas.ContinueLayout(Partial,Content[I],1);
    Check('large table yields with usable partial geometry',
      Not Partial.Complete And (Partial.LineCount>0) And (Partial.Height>0));
    Steps:=0; Deadline:=GetTickCount64+10000;
    While Not Partial.Complete And (GetTickCount64<Deadline) Do
      Begin Canvas.ContinueLayout(Partial,Content[I],1); Inc(Steps); End;
    Check('incremental table completes',Partial.Complete And (Steps>0));
    Canvas.Prepare(Whole,Content[I],400,swWord);
    Check('incremental table matches synchronous extent',
      (Partial.Height=Whole.Height) And (Partial.LineCount=Whole.LineCount) And
      (Partial.NextOffset=Length(Content[I].Text)));
    For I:=0 To High(Whole.Cells) Do
      Begin
        Check('cell source preserved',Partial.Cells[I].Source=Whole.Cells[I].Source);
        For J:=0 To Whole.Cells[I].RunCount-1 Do
          Check('cell alignment independent of measurement slices',
            Partial.Cells[I].Runs[J].X=Whole.Cells[I].Runs[J].X);
      End;
    Check('temporary cell paragraphs released',Length(Partial.CellParagraphs)=0);
    I:=High(Content);
    Canvas.Prepare(Partial,Content[I],200,swWord);
    Check('resizing rebuilds table geometry',Partial.Complete And (Partial.Height>Whole.Height));
  Finally Whole.Free; Partial.Free; Canvas.Free; Bitmap.Free; End;
End;

Procedure TestReflowKeepsMeasuredHeight;
Var
  Bitmap: TBitmap;
  Font: TFont;
  Document: TStyledDocument;
  Memo: TStyledMemoLayout;
  Content: TStyledContent;
  Before, After: Int64;
Begin
  Bitmap := TBitmap.Create;
  Font := TFont.Create;
  Document := TStyledDocument.Create;
  Memo := Nil;
  Try
    Bitmap.SetSize(400, 200);
    Font.Name := 'DejaVu Sans';
    Font.Size := 12;
    Renderer.Configure(Bitmap.Canvas, Font, Bitmap.Width, Bitmap.Height);
    Content := StyledContentFromText('One two three four five six seven eight nine ten eleven twelve thirteen fourteen ' +
      'fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two.');
    Document.Replace(StyledPosition(0, 0), Document.EndPosition, Content);
    Memo := TStyledMemoLayout.Create(Document, Renderer);
    Memo.Reset(80, True, 24);
    Memo.Ensure(0, True);
    Before := HeightBefore(Memo.Heights, 1);
    Check('narrow wrap is taller than two lines', Before > Int64(Renderer.LineHeight) * 2);
    Memo.Reflow(220, Renderer.LineHeight);
    After := HeightBefore(Memo.Heights, 1);
    Check('reflow does not collapse to the initial line height', After > Int64(Renderer.LineHeight) * 2);
    Check('reflow keeps the measured block', After = Before);
  Finally
    Memo.Free;
    Document.Free;
    Font.Free;
    Bitmap.Free;
  End;
End;

Procedure TestLineHeightFollowsSurface;
Var
  Bitmap: TBitmap;
  Font: TFont;
  FirstGeneration, SecondGeneration: QWord;
  FirstHeight, SecondHeight: Integer;
Begin
  Bitmap := TBitmap.Create;
  Font := TFont.Create;
  Try
    Font.Name := 'DejaVu Sans';
    Font.Size := 12;
    Bitmap.SetSize(8, 8);
    Renderer.Configure(Bitmap.Canvas, Font, 8, 8);
    FirstHeight := Renderer.LineHeight;
    FirstGeneration := Renderer.Generation;
    Bitmap.SetSize(400, 200);
    Renderer.Configure(Bitmap.Canvas, Font, 400, 200);
    SecondHeight := Renderer.LineHeight;
    SecondGeneration := Renderer.Generation;
    Check('resized surface still has a line height', SecondHeight > 1);
    If SecondHeight <> FirstHeight Then
      Check('a changed line height drops the cached metrics', SecondGeneration <> FirstGeneration)
    Else
      Check('an unchanged line height keeps the generation', SecondGeneration = FirstGeneration);
    Renderer.Configure(Bitmap.Canvas, Font, 400, 200);
    Check('repeated surface configure does not invalidate again', Renderer.Generation = SecondGeneration);
  Finally
    Font.Free;
    Bitmap.Free;
  End;
End;

Procedure TestListContinuation;
Var Content: TStyledContent;
Begin
  Content := Parse('9. **Previous**' + #10#10 + '   **Fix:** previous' + #10#10 +
    '10. **Last item**' + #10#10 + '    **Location:** [file.pas:7](/project/file.pas:7)' +
    #10#10 + '    **Fix:** Handle empty streams.' );
  Check('two-digit list continuation renders bold labels',
    (Pos('**Fix:**', Plain(Content)) = 0) And (Pos('**Location:**', Plain(Content)) = 0) And
    (fsBold In StyleFor(Content, 'Location:').Styles));
  Content := Parse('    **standalone indentation**');
  Check('standalone indented literal retained', Pos('**standalone indentation**', Plain(Content)) > 0);
End;

Begin
  FailCount := 0;
  Renderer := TStyledCanvas.Create;
  Try
    TestRendererDPI;
    TestSoftAndHardBreaks;
    TestInlineCodeAndPunctuation;
    TestEmphasisAndHeading;
    TestLiteralUnsupported;
    TestListsAndCodeFence;
    TestTables;
    TestStreamedTables;
    TestListContinuation;
    TestDetachedParsing;
    TestOversizedCluster;
    TestIncrementalTable;
    TestReflowKeepsMeasuredHeight;
    TestLineHeightFollowsSurface;
  Finally
    Renderer.Free;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All MarkdownLayout tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' MarkdownLayout test(s) failed.');
      Halt(1);
    End;
End.
