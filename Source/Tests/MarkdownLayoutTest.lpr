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
  Interfaces, Graphics, Classes, SysUtils, StyledTextTypes, StyledCanvas, StyledMarkdown;

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

Begin
  FailCount := 0;
  Renderer := TStyledCanvas.Create;
  Try
    TestSoftAndHardBreaks;
    TestInlineCodeAndPunctuation;
    TestEmphasisAndHeading;
    TestLiteralUnsupported;
    TestListsAndCodeFence;
    TestTables;
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
