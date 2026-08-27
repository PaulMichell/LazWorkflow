Program MarkdownLayoutTest;

{ Console checks for mixed-style markdown run spacing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Graphics, Classes, SysUtils, Contnrs, MarkDown.CanvasRender, Markdown.Processors, Markdown.Utils;

Var
  FailCount: Integer;

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

Function LayoutOf(Const Markdown: String; Out Renderer: TMarkDownCanvasRenderer): Integer;
Var
  Bmp: TBitmap;
  SL: TStringList;
  W, H: Integer;
Begin
  Renderer := TMarkDownCanvasRenderer.Create(Nil);
  Bmp := TBitmap.Create;
  SL := TStringList.Create;
  Try
    Bmp.SetSize(800, 200);
    Bmp.Canvas.Font.Name := 'DejaVu Sans';
    Bmp.Canvas.Font.Size := 10;
    Renderer.FontName := 'DejaVu Sans';
    Renderer.MonoFontName := 'DejaVu Sans Mono';
    Renderer.BaseFontSize := 10;
    SL.Text := Markdown;
    Renderer.ParseMarkdown(SL);
    Renderer.CalculateLayout(Bmp.Canvas, 700, W, H);
    Result := Renderer.LayoutItemCount;
  Finally
    SL.Free;
    Bmp.Free;
  End;
End;

Procedure TestRunsAbutAcrossStyleChange;
Var
  R: TMarkDownCanvasRenderer;
  A, B: TLayoutItem;
  I, N: Integer;
Begin
  N := LayoutOf('- `Card.SetBounds` is called, then `LockControlWidth(Card, InnerW);` again.', R);
  Try
    Check('mixed-style has several runs', N >= 3);
    For I := 0 To N - 2 Do
      Begin
        A := R.LayoutItem(I);
        B := R.LayoutItem(I + 1);
        If (Not Assigned(A)) Or (Not Assigned(B)) Then
          Continue;
        If A.Y <> B.Y Then
          Continue;
        Check('same-line runs abut', B.X = A.X + A.Width);
      End;
  Finally
    R.Free;
  End;
End;

Function JoinedLineText(Renderer: TMarkDownCanvasRenderer): String;
Var
  I: Integer;
  Item: TLayoutItem;
Begin
  Result := '';
  For I := 0 To Renderer.LayoutItemCount - 1 Do
    Begin
      Item := Renderer.LayoutItem(I);
      If Assigned(Item) And (Item.Kind = likText) And (Item.Y = 0) Then
        Result := Result + Item.Text;
    End;
End;

Procedure TestNoSpaceBeforePunctuationAfterCode;
Var
  Tight, Loose: TMarkDownCanvasRenderer;
  TightText, LooseText: String;
Begin
  LayoutOf('No `.lpi`. Files: `a.pas`, `b.lfm` / `c.lpr`.', Tight);
  LayoutOf('No `.lpi` . Files: `a.pas` , `b.lfm` / `c.lpr` .', Loose);
  Try
    TightText := JoinedLineText(Tight);
    LooseText := JoinedLineText(Loose);
    Check('tight has no space before period', Pos('.lpi.', TightText) > 0);
    Check('tight has no space before comma', Pos('.pas,', TightText) > 0);
    Check('loose glue period after code', Pos('.lpi.', LooseText) > 0);
    Check('loose glue comma after code', Pos('.pas,', LooseText) > 0);
    Check('loose does not keep "lpi ."', Pos('lpi .', LooseText) = 0);
    Check('loose does not keep "pas ,"', Pos('pas ,', LooseText) = 0);
  Finally
    Tight.Free;
    Loose.Free;
  End;
End;

Procedure TestCodeWidthMatchesGlyphs;
Var
  R: TMarkDownCanvasRenderer;
  Bmp: TBitmap;
  I, CodeRuns: Integer;
  Item: TLayoutItem;
  Measured: Integer;
Begin
  Bmp := TBitmap.Create;
  CodeRuns := 0;
  Try
    Bmp.SetSize(800, 80);
    Bmp.Canvas.Font.Name := 'DejaVu Sans Mono';
    Bmp.Canvas.Font.Size := 10;
    Bmp.Canvas.Font.Pitch := fpDefault;
    LayoutOf('- `FilterAllocatedOnly` only changes the project SQL.', R);
    Try
      For I := 0 To R.LayoutItemCount - 1 Do
        Begin
          Item := R.LayoutItem(I);
          If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
            Continue;
          If Not (fcCode In Item.Context) Then
            Continue;
          Inc(CodeRuns);
          Measured := Bmp.Canvas.TextWidth(Item.Text);
          Check('code run width matches glyphs for "' + Item.Text + '"', Abs(Item.Width - Measured) <= 2);
        End;
      Check('layout produced an inline code run', CodeRuns > 0);
    Finally
      R.Free;
    End;
  Finally
    Bmp.Free;
  End;
End;

Function JoinedAllText(Renderer: TMarkDownCanvasRenderer): String;
Var
  I: Integer;
  Item: TLayoutItem;
Begin
  Result := '';
  For I := 0 To Renderer.LayoutItemCount - 1 Do
    Begin
      Item := Renderer.LayoutItem(I);
      If Assigned(Item) And (Item.Kind = likText) Then
        Result := Result + Item.Text;
    End;
End;

Procedure TestHardBreakIsNewlineNotTag;
Var
  R: TMarkDownCanvasRenderer;
  All: String;
  HasTwoLines: Boolean;
  I: Integer;
  Item: TLayoutItem;
  FirstY, OtherY: Integer;
Begin
  LayoutOf('alpha  ' + LineEnding + 'bravo', R);
  Try
    All := JoinedAllText(R);
    Check('two-space break does not paint <br', Pos('<br', LowerCase(All)) = 0);
    Check('two-space break keeps both words', (Pos('alpha', All) > 0) And (Pos('bravo', All) > 0));
    HasTwoLines := False;
    FirstY := -1;
    For I := 0 To R.LayoutItemCount - 1 Do
      Begin
        Item := R.LayoutItem(I);
        If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
          Continue;
        If FirstY < 0 Then
          FirstY := Item.Y
        Else If Item.Y <> FirstY Then
          Begin
            OtherY := Item.Y;
            HasTwoLines := OtherY > FirstY;
          End;
      End;
    Check('two-space break makes a new line', HasTwoLines);
  Finally
    R.Free;
  End;
End;

Procedure TestPlainPunctuationKeepsSourceSpace;
Var
  R: TMarkDownCanvasRenderer;
  All: String;
Begin
  LayoutOf('hello , world', R);
  Try
    All := JoinedAllText(R);
    Check('plain comma keeps source space', Pos('hello ,', All) > 0);
    Check('plain comma does not glue hello,', Pos('hello,', All) = 0);
  Finally
    R.Free;
  End;
End;

Procedure TestNumericEntitiesHexAndSupplementary;
Var
  R: TMarkDownCanvasRenderer;
  All, Grin: String;
  Table: TFPStringHashTable;
Begin
  Grin := DecodeNumericEntityBody('#x1F600');
  Check('hex smile is four UTF-8 bytes', Length(Grin) = 4);
  Check('decimal smile matches hex', DecodeNumericEntityBody('#128512') = Grin);
  Check('hex A is A', DecodeNumericEntityBody('#x41') = 'A');
  Table := TFPStringHashTable.Create;
  Try
    Table.Add('amp', '&');
    Table.Add('Aacute', DecodeNumericEntityBody('#193'));
    Check('ParseEntityString named amp', ParseEntityString(Table, '&amp;') = '&');
    Check('ParseEntityString keeps Aacute case', ParseEntityString(Table, '&Aacute;') = DecodeNumericEntityBody('#193'));
    Check('ParseEntityString hex A', ParseEntityString(Table, '&#x41;') = 'A');
    Check('ParseEntityString unknown is empty', ParseEntityString(Table, '&nope;') = '');
  Finally
    Table.Free;
  End;
  LayoutOf('hi &#x1F600; there', R);
  Try
    All := JoinedAllText(R);
    Check('layout decodes hex smile', Pos(Grin, All) > 0);
  Finally
    R.Free;
  End;
End;

Procedure TestCopyDoesNotInsertSpacesBetweenAbuttingRuns;
Var
  R: TMarkDownCanvasRenderer;
  Copied: String;
Begin
  LayoutOf('see `name`.', R);
  Try
    Check('select all for copy', R.SelectAll);
    Copied := R.GetSelectedText;
    Check('copy keeps name.', Pos('name.', Copied) > 0);
    Check('copy does not insert name .', Pos('name .', Copied) = 0);
  Finally
    R.Free;
  End;
End;

Procedure TestSoftBreakIsSpaceNotNewline;
Var
  R: TMarkDownCanvasRenderer;
  All: String;
  HasTwoLines: Boolean;
  I, FirstY: Integer;
  Item: TLayoutItem;
Begin
  LayoutOf('hello' + LineEnding + 'world', R);
  Try
    All := JoinedAllText(R);
    Check('soft break keeps both words', (Pos('hello', All) > 0) And (Pos('world', All) > 0));
    Check('soft break does not glue hello-world', Pos('helloworld', All) = 0);
    HasTwoLines := False;
    FirstY := -1;
    For I := 0 To R.LayoutItemCount - 1 Do
      Begin
        Item := R.LayoutItem(I);
        If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
          Continue;
        If FirstY < 0 Then
          FirstY := Item.Y
        Else If Item.Y > FirstY Then
          HasTwoLines := True;
      End;
    Check('soft break stays on one line', Not HasTwoLines);
  Finally
    R.Free;
  End;
End;

Procedure TestHtmlBrIsNewlineNotTag;
Var
  R: TMarkDownCanvasRenderer;
  All: String;
  HasTwoLines: Boolean;
  I, FirstY: Integer;
  Item: TLayoutItem;
Begin
  LayoutOf('alpha<br/>bravo', R);
  Try
    All := JoinedAllText(R);
    Check('html br does not paint <br', Pos('<br', LowerCase(All)) = 0);
    Check('html br keeps both words', (Pos('alpha', All) > 0) And (Pos('bravo', All) > 0));
    HasTwoLines := False;
    FirstY := -1;
    For I := 0 To R.LayoutItemCount - 1 Do
      Begin
        Item := R.LayoutItem(I);
        If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
          Continue;
        If FirstY < 0 Then
          FirstY := Item.Y
        Else If Item.Y > FirstY Then
          HasTwoLines := True;
      End;
    Check('html br makes a new line', HasTwoLines);
  Finally
    R.Free;
  End;
End;

Procedure TestCodeSpanUsesMonoAndTightGap;
Var
  R: TMarkDownCanvasRenderer;
  Bmp: TBitmap;
  I: Integer;
  Item, Prev: TLayoutItem;
  CodeCount, Gap, SpaceW: Integer;
Begin
  Bmp := TBitmap.Create;
  Try
    Bmp.SetSize(800, 80);
    Bmp.Canvas.Font.Name := 'DejaVu Sans';
    Bmp.Canvas.Font.Size := 10;
    SpaceW := Bmp.Canvas.TextWidth(' ');
    LayoutOf('before `FilterAllocatedOnly` after.', R);
    Try
      CodeCount := 0;
      Prev := Nil;
      For I := 0 To R.LayoutItemCount - 1 Do
        Begin
          Item := R.LayoutItem(I);
          If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
            Continue;
          If fcMono In Item.Context Then
            Begin
              Inc(CodeCount);
              Check('code run is not a bare backtick', Pos('`', Item.Text) = 0);
              If Assigned(Prev) And (Prev.Y = Item.Y) Then
                Begin
                  Gap := Item.X - (Prev.X + Prev.Width);
                  Check('gap before code is a body space, not a mono hole', Gap <= SpaceW + 4);
                End;
            End;
          Prev := Item;
        End;
      Check('inline code produced a mono run', CodeCount > 0);
    Finally
      R.Free;
    End;
  Finally
    Bmp.Free;
  End;
End;

Procedure TestGenericMonoAliasUsesFixedPitch;
Var
  R: TMarkDownCanvasRenderer;
  Bmp: TBitmap;
  SL: TStringList;
  W, H, I, CodeCount: Integer;
  IItem, MItem, Item: TLayoutItem;
  BodyIWidth: Integer;
Begin
  R := TMarkDownCanvasRenderer.Create(Nil);
  Bmp := TBitmap.Create;
  SL := TStringList.Create;
  IItem := Nil;
  MItem := Nil;
  Try
    Bmp.SetSize(800, 120);
    Bmp.Canvas.Font.Name := 'DejaVu Sans';
    Bmp.Canvas.Font.Size := 10;
    R.FontName := 'DejaVu Sans';
    R.MonoFontName := 'Monospace';
    R.BaseFontSize := 10;
    SL.Text := '`iiiiiiii` `MMMMMMMM`';
    R.ParseMarkdown(SL);
    R.CalculateLayout(Bmp.Canvas, 700, W, H);
    CodeCount := 0;
    For I := 0 To R.LayoutItemCount - 1 Do
      Begin
        Item := R.LayoutItem(I);
        If (Not Assigned(Item)) Or (Item.Kind <> likText) Then
          Continue;
        If Not (fcMono In Item.Context) Then
          Continue;
        Inc(CodeCount);
        If Item.Text = 'iiiiiiii' Then
          IItem := Item
        Else If Item.Text = 'MMMMMMMM' Then
          MItem := Item;
      End;
    Check('generic Monospace produced two code runs', CodeCount >= 2);
    Check('found iiii code run', Assigned(IItem));
    Check('found MMMM code run', Assigned(MItem));
    If Assigned(IItem) And Assigned(MItem) Then
      Check('iiii and MMMM share a mono advance', Abs(IItem.Width - MItem.Width) <= 2);
    Bmp.Canvas.Font.BeginUpdate;
    Try
      Bmp.Canvas.Font.Name := 'DejaVu Sans';
      Bmp.Canvas.Font.Size := 10;
      Bmp.Canvas.Font.Style := [];
    Finally
      Bmp.Canvas.Font.EndUpdate;
    End;
    BodyIWidth := Bmp.Canvas.TextWidth('iiiiiiii');
    If Assigned(IItem) Then
      Check('code iiii is wider than body sans', IItem.Width > BodyIWidth + 2);
  Finally
    SL.Free;
    Bmp.Free;
    R.Free;
  End;
End;

Procedure TestCollapsedSpacesAroundCode;
Var
  Tight, Padded: TMarkDownCanvasRenderer;
  TightW, PadW: Integer;
  I: Integer;
  Item: TLayoutItem;
Begin
  TightW := 0;
  PadW := 0;
  LayoutOf('- `Foo` bar `Baz` end.', Tight);
  LayoutOf('- `Foo`          bar          `Baz`          end.', Padded);
  Try
    For I := 0 To Tight.LayoutItemCount - 1 Do
      Begin
        Item := Tight.LayoutItem(I);
        If Assigned(Item) And (Item.Y = 0) Then
          If Item.X + Item.Width > TightW Then
            TightW := Item.X + Item.Width;
      End;
    For I := 0 To Padded.LayoutItemCount - 1 Do
      Begin
        Item := Padded.LayoutItem(I);
        If Assigned(Item) And (Item.Y = 0) Then
          If Item.X + Item.Width > PadW Then
            PadW := Item.X + Item.Width;
      End;
    Check('padded spaces do not explode width', Abs(PadW - TightW) <= 8);
  Finally
    Tight.Free;
    Padded.Free;
  End;
End;

Begin
  FailCount := 0;
  TestRunsAbutAcrossStyleChange;
  TestNoSpaceBeforePunctuationAfterCode;
  TestPlainPunctuationKeepsSourceSpace;
  TestCodeWidthMatchesGlyphs;
  TestCollapsedSpacesAroundCode;
  TestHardBreakIsNewlineNotTag;
  TestNumericEntitiesHexAndSupplementary;
  TestCopyDoesNotInsertSpacesBetweenAbuttingRuns;
  TestSoftBreakIsSpaceNotNewline;
  TestHtmlBrIsNewlineNotTag;
  TestCodeSpanUsesMonoAndTightGap;
  TestGenericMonoAliasUsesFixedPitch;
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
