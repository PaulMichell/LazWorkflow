Unit StyledMarkdown;

{ Compact Markdown-to-styled-text reader (c) 2026 Michell Computing.
  Converts directly to TStyledContent; no external Markdown parser or AST.
  This is a deliberate subset, not a CommonMark/GFM conformance implementation.

  Unsupported features (retain source text; add only when needed):
  - Links/autolinks, images, reference definitions and footnotes.
  - Merged/nested tables, multiline cells and custom column widths.
  - Task checkboxes, HTML and entity decoding, math and diagrams.
  - Frontmatter, Setext headings and thematic rules.
  - Indented code, nested block containers and list continuation paragraphs.
  - Full delimiter/flanking rules, multiline inline spans, closing heading #s,
    code-span whitespace normalization and code-fence indentation removal.
  - Syntax highlighting, incremental parsing and Markdown round-trip editing.

  Simple list indentation is visual only. Unsupported block lines retain line
  breaks; ordinary prose joins soft breaks. Unclosed fences retain their source
  through EOF. Inline nesting beyond 16 levels is emitted literally. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
  {$CODEPAGE UTF8}
{$ENDIF}

Interface

Uses
  Classes, StyledTextTypes, StyledCanvas, StyledControls;

{ Style IDs belong to Renderer. The returned content is owned by the caller;
  box group IDs are local to this result. BaseSize is in points. }
Function BuildStyledMarkdown(Renderer: TStyledCanvas; Const MarkdownText: UTF8String;
  BaseSize: Integer = 10): TStyledContent;

Type
  TStyledMarkdown = Class
  Private
    FTarget: TCustomStyledText;
  Public
    { Borrows Target, which must outlive this loader. Call on the UI thread. }
    Constructor Create(Target: TCustomStyledText);
    { Replaces content, clears undo through document notification, resets caret
      and scroll. ReadOnly does not prevent programmatic loading. }
    Procedure LoadFromString(Const MarkdownText: UTF8String);
    Procedure LoadFromStrings(Source: TStrings);
    { Reads UTF-8 from the current position to EOF; does not close or rewind. }
    Procedure LoadFromStream(Source: TStream);
    Procedure LoadFromFile(Const FileName: String);
  End;

Implementation

Uses
  SysUtils, Math, Graphics;

Type
  { Emits paragraphs and style ranges directly; no intermediate syntax tree. }
  TMarkdownReader = Class
  Private
    FRenderer: TStyledCanvas;
    FContent: TStyledContent;
    FCount: Integer;
    Procedure NewParagraph(Indent: Integer; Background: TColor = clNone;
      Group: QWord = 0);
    Procedure Append(Const Value: UTF8String; Const Style: TStyledStyle);
    Function Table(Lines: TStrings; Var Index: Integer): Boolean;
    Procedure Inline(Const Value: UTF8String; Const Style: TStyledStyle;
      Depth: Integer = 0);
  Public
    Function Parse(Renderer: TStyledCanvas; Const Value: UTF8String;
      BaseSize: Integer): TStyledContent;
  End;

Procedure TMarkdownReader.NewParagraph(Indent: Integer; Background: TColor; Group: QWord);
Begin
  If FCount = Length(FContent) Then SetLength(FContent, Max(16, FCount * 2));
  FContent[FCount] := Default(TStyledParagraph);
  If Group = 0 Then Group := FCount + 1;
  FContent[FCount].Box.Group := Group;
  FContent[FCount].Box.Style := DefaultStyledBoxStyle;
  FContent[FCount].Box.Style.Margin := StyledInsets(0, 0, 6, Indent);
  FContent[FCount].Box.Style.Background := Background;
  If Background <> clNone Then
    FContent[FCount].Box.Style.Padding := StyledInsets(6, 8);
  Inc(FCount);
End;

Procedure TMarkdownReader.Append(Const Value: UTF8String; Const Style: TStyledStyle);
Begin
  If Value <> '' Then
    AppendStyledText(FContent[FCount - 1], Value, FRenderer.AddStyle(Style));
End;

Function RunLength(Const Value: UTF8String; Start: Integer): Integer;
Begin
  Result := 0;
  While (Start + Result <= Length(Value)) And
    (Value[Start + Result] = Value[Start]) Do Inc(Result);
End;

Function WordByte(Value: AnsiChar): Boolean;
Begin
  Result := Value In ['a'..'z', 'A'..'Z', '0'..'9', #128..#255];
End;

Function BracketEnd(Const Value: UTF8String; Start: Integer): Integer;
Var
  Level: Integer;
  OpenChar, CloseChar: AnsiChar;
Begin
  Result := Start;
  Repeat
    OpenChar := Value[Result];
    If OpenChar = '[' Then CloseChar := ']' Else CloseChar := ')';
    Level := 1;
    Inc(Result);
    While (Result <= Length(Value)) And (Level > 0) Do
      Begin
        If Value[Result] = '\' Then Inc(Result)
        Else If Value[Result] = OpenChar Then Inc(Level)
        Else If Value[Result] = CloseChar Then Dec(Level);
        Inc(Result);
      End;
  Until (Result > Length(Value)) Or Not (Value[Result] In ['[', '(']);
End;

Procedure TMarkdownReader.Inline(Const Value: UTF8String; Const Style: TStyledStyle; Depth: Integer);
Var
  Index, Start, Finish, Count, Closing, Level: Integer;
  Chunk: UTF8String;
  Styled: TStyledStyle;
Begin
  { Limit recursion for deliberately or accidentally deeply nested input. }
  If Depth >= 16 Then
    Begin
      Append(Value, Style);
      Exit;
    End;
  Index := 1;
  Start := 1;
  While Index <= Length(Value) Do
    Begin
      { Keep unsupported link/image/reference syntax intact, including emphasis
        in labels and destinations. An incomplete construct retains its tail. }
      If Value[Index] = '[' Then
        Begin
          Finish := BracketEnd(Value, Index);
          Append(Copy(Value, Start, Finish - Start), Style);
          Index := Finish;
          Start := Index;
          Continue;
        End;
      If (Value[Index] = '\') And (Index < Length(Value)) And
        (Value[Index + 1] In ['!', '"', '#', '$', '%', '&', '''', '(', ')', '*', '+',
          ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\', ']', '^', '_', '`', '{', '|', '}', '~']) Then
        Begin
          Append(Copy(Value, Start, Index - Start), Style);
          Append(Value[Index + 1], Style);
          Inc(Index, 2);
          Start := Index;
          Continue;
        End;
      If Value[Index] In ['*', '_', '~', '`'] Then
        Begin
          Count := RunLength(Value, Index);
          Closing := 0;
          If (Value[Index] = '`') Or
            (((Value[Index] In ['*', '_']) And (Count <= 3)) Or
             ((Value[Index] = '~') And (Count = 2))) Then
            Begin
              Finish := Index + Count;
              While Finish <= Length(Value) Do
                Begin
                  If (Value[Finish] = '[') And (Value[Index] <> '`') Then Finish := BracketEnd(Value, Finish)
                  Else If (Value[Finish] = '\') And (Value[Index] <> '`') Then Inc(Finish, 2)
                  Else If Value[Finish] = Value[Index] Then
                    Begin
                      Level := RunLength(Value, Finish);
                      If (Level = Count) And (Finish > Index + Count) And
                        ((Value[Index] = '`') Or
                         ((Value[Index + Count] > ' ') And (Value[Finish - 1] > ' '))) Then
                        Begin
                          Closing := Finish;
                          Break;
                        End;
                      Inc(Finish, Level);
                    End
                  Else Inc(Finish);
                End;
            End;
          { Underscores inside identifiers are ordinary text. }
          If (Value[Index] = '_') And
            (((Index > 1) And WordByte(Value[Index - 1])) Or
             ((Closing > 0) And (Closing + Count <= Length(Value)) And
              WordByte(Value[Closing + Count]))) Then Closing := 0;
          If Closing > 0 Then
            Begin
              Append(Copy(Value, Start, Index - Start), Style);
              Chunk := Copy(Value, Index + Count, Closing - Index - Count);
              Styled := Style;
              Case Value[Index] Of
                '`': Begin Styled.FontName := 'Monospace'; Styled.Background := clInfoBk; End;
                '~': Include(Styled.Styles, fsStrikeOut);
                '*', '_':
                  Begin
                    If Count >= 2 Then Include(Styled.Styles, fsBold);
                    If Count <> 2 Then Include(Styled.Styles, fsItalic);
                  End;
              End;
              If Value[Index] = '`' Then Append(Chunk, Styled)
              Else Inline(Chunk, Styled, Depth + 1);
              Index := Closing + Count;
              Start := Index;
              Continue;
            End;
          Inc(Index, Count);
        End
      Else Inc(Index);
    End;
  Append(Copy(Value, Start, Length(Value)), Style);
End;

Function SplitTableRow(Const Value: String; Cells: TStrings): Boolean;
Var
  Line: String;
  Index, Start, Count, Finish: Integer;
Begin
  Cells.Clear;
  Result := False;
  Line := Trim(Value);
  Index := 1;
  Start := 1;
  While Index <= Length(Line) Do
    Begin
      If Line[Index] = '\' Then Inc(Index, 2)
      Else If Line[Index] = '`' Then
        Begin
          Count := RunLength(Line, Index);
          Finish := Index + Count;
          While Finish <= Length(Line) Do
            Begin
              If (Line[Finish] = '`') And (RunLength(Line, Finish) = Count) Then Break;
              If Line[Finish] = '`' Then Inc(Finish, RunLength(Line, Finish)) Else Inc(Finish);
            End;
          If Finish <= Length(Line) Then Index := Finish + Count Else Inc(Index, Count);
        End
      Else If Line[Index] = '|' Then
        Begin
          Result := True;
          If Index > 1 Then Cells.Add(Trim(Copy(Line, Start, Index - Start)));
          Start := Index + 1;
          Inc(Index);
        End
      Else Inc(Index);
    End;
  If Start <= Length(Line) Then Cells.Add(Trim(Copy(Line, Start, Length(Line))))
  Else If Cells.Count = 0 Then Cells.Add('');
End;

Function TMarkdownReader.Table(Lines: TStrings; Var Index: Integer): Boolean;
Var
  Cells, Separator: TStringList;
  Columns: TStyledColumns;
  Marker: String;
  CellIndex, Position, Count: Integer;
  Header: Boolean;
  Style: TStyledStyle;
Begin
  Result := False;
  If Index + 1 >= Lines.Count Then Exit;
  Cells := TStringList.Create;
  Separator := TStringList.Create;
  Try
    If Not SplitTableRow(Lines[Index], Cells) Or Not SplitTableRow(Lines[Index + 1], Separator) Or
      (Cells.Count <> Separator.Count) Then Exit;
    SetLength(Columns, Cells.Count);
    For CellIndex := 0 To Separator.Count - 1 Do
      Begin
        Marker := Separator[CellIndex];
        If Marker = '' Then Exit;
        Columns[CellIndex] := scaLeft;
        If Marker[1] = ':' Then
          Begin
            Columns[CellIndex] := scaCenter;
            Delete(Marker, 1, 1);
          End;
        If (Marker <> '') And (Marker[Length(Marker)] = ':') Then
          Begin
            If Columns[CellIndex] = scaLeft Then Columns[CellIndex] := scaRight;
            Delete(Marker, Length(Marker), 1);
          End
        Else Columns[CellIndex] := scaLeft;
        If Length(Marker) < 3 Then Exit;
        For Position := 1 To Length(Marker) Do If Marker[Position] <> '-' Then Exit;
      End;
    Result := True;
    Header := True;
    Repeat
      NewParagraph(0);
      FContent[FCount - 1].Box.Columns := Copy(Columns);
      With FContent[FCount - 1].Box.Style Do
        Begin
          Margin := StyledInsets(0);
          Padding := StyledInsets(5, 8);
          BorderWidth := 1;
          BorderColor := clBtnShadow;
          If Header Then Background := clBtnFace;
        End;
      Style := DefaultStyledStyle;
      If Header Then Include(Style.Styles, fsBold);
      For CellIndex := 0 To High(Columns) Do
        Begin
          If CellIndex > 0 Then Append(#9, DefaultStyledStyle);
          If CellIndex < Cells.Count Then Inline(Cells[CellIndex], Style);
        End;
      If Header Then Inc(Index, 2) Else Inc(Index);
      Header := False;
      If Index >= Lines.Count Then Break;
      Count := Length(Lines[Index]) - Length(TrimLeft(Lines[Index]));
      If (Count >= 4) Or Not SplitTableRow(Lines[Index], Cells) Or (Cells.Count > Length(Columns)) Then Break;
      { Missing trailing cells are empty; surplus cells end the table and the
        original line is processed literally, so no content is discarded. }
    Until False;
  Finally
    Separator.Free;
    Cells.Free;
  End;
End;

Function TMarkdownReader.Parse(Renderer: TStyledCanvas; Const Value: UTF8String;
  BaseSize: Integer): TStyledContent;
Const
  HeadingScale: Array[1..6] Of Integer = (180, 155, 135, 120, 110, 100);
Var
  Lines: TStringList;
  Line, Body, Fence: UTF8String;
  Index, Finish, Count, Indent, Level, MarkerEnd, ListContentIndent: Integer;
  Style: TStyledStyle;
  Background: TColor;
  Group: QWord;
  ParagraphOpen, HardBreak, BlockLine, Literal, ListContinuation: Boolean;
Begin
  FRenderer := Renderer;
  Lines := TStringList.Create;
  Try
    Lines.Text := Value;
    Index := 0;
    ParagraphOpen := False; ListContentIndent := -1;
    While Index < Lines.Count Do
      Begin
        Line := Lines[Index];
        Body := TrimLeft(Line);
        Indent := Length(Line) - Length(Body);
        If Body = '' Then
          Begin
            ParagraphOpen := False;
            Inc(Index);
            Continue;
          End;
        Style := DefaultStyledStyle;
        Background := clNone;
        { Frontmatter is unsupported: preserve the entire opening block. }
        If (Index = 0) And (Line = '---') Then
          Begin
            Finish := Index + 1;
            While (Finish < Lines.Count) And (Lines[Finish] <> '---') Do Inc(Finish);
            If Finish = Lines.Count Then Finish := Index;
            While Index <= Finish Do
              Begin
                NewParagraph(0);
                Append(Lines[Index], Style);
                Inc(Index);
              End;
            Continue;
          End;
        If (Indent <= 3) And (Body[1] In ['`', '~']) And (RunLength(Body, 1) >= 3) Then
          Begin
            Count := RunLength(Body, 1);
            Fence := Copy(Body, 1, Count);
            Finish := Index + 1;
            While Finish < Lines.Count Do
              Begin
                Line := Trim(Lines[Finish]);
                If (Copy(Line, 1, Count) = Fence) And
                  (RunLength(Line, 1) = Length(Line)) And
                  (Length(Lines[Finish]) - Length(TrimLeft(Lines[Finish])) <= 3) Then Break;
                Inc(Finish);
              End;
            Literal := Finish = Lines.Count;
            Group := FCount + 1;
            If Not Literal Then
              Begin
                Inc(Index);
                Style.FontName := 'Monospace';
                Background := clInfoBk;
              End;
            While Index < Finish Do
              Begin
                NewParagraph(0, Background, Group);
                Append(Lines[Index], Style);
                Inc(Index);
              End;
            Inc(Index);
            ParagraphOpen := False;
            Continue;
          End;
        If (Indent <= 3) And (Pos('|', Body) > 0) And Table(Lines, Index) Then
          Begin
            ParagraphOpen := False;
            Continue;
          End;
        { Unsupported block forms stay verbatim, including their line breaks.
          Four-space indentation is not interpreted as code in this subset. }
        ListContinuation := (ListContentIndent >= 0) And
          (Indent >= ListContentIndent) And (Indent < ListContentIndent + 4);
        If (ListContentIndent >= 0) And (Indent < ListContentIndent) Then ListContentIndent := -1;
        Literal := ((Indent >= 4) And Not ListContinuation) Or (Pos('|', Body) > 0) Or
          (Body[1] In ['<', '$', '[', '!']) Or
          ((Body[1] In ['-', '=', '*', '_']) And
           (RunLength(Body, 1) = Length(Body)) And (Length(Body) >= 3));
        If Literal Then
          Begin
            NewParagraph(0);
            Append(Line, Style);
            ParagraphOpen := False;
            Inc(Index);
            Continue;
          End;
        Level := 0;
        If Body[1] = '#' Then
          Begin
            Count := RunLength(Body, 1);
            If (Count <= 6) And ((Count = Length(Body)) Or (Body[Count + 1] = ' ')) Then
              Begin
                Level := Count;
                Body := Trim(Copy(Body, Count + 1, Length(Body)));
              End;
          End;
        BlockLine := Level > 0;
        MarkerEnd := 0;
        If (Level = 0) And (Length(Body) >= 2) Then
          Begin
            If (Body[1] In ['-', '+', '*']) And (Body[2] = ' ') Then MarkerEnd := 1
            Else If Body[1] In ['0'..'9'] Then
              Begin
                Count := 1;
                While (Count <= Length(Body)) And (Body[Count] In ['0'..'9']) Do Inc(Count);
                If (Count < Length(Body)) And (Body[Count] = '.') And (Body[Count + 1] = ' ') Then MarkerEnd := Count;
              End;
            If MarkerEnd > 0 Then
              Begin
                BlockLine := True;
                ListContentIndent := Indent + MarkerEnd + 1;
                Indent := 20 + Indent * 6;
                If MarkerEnd = 1 Then Body := UTF8String('• ') + Copy(Body, 3, Length(Body));
              End
            Else If (Body[1] = '>') And (Body[2] = ' ') Then
              Begin
                BlockLine := True;
                Inc(Indent, 20);
                Background := clBtnFace;
                Style.Foreground := clGrayText;
                Delete(Body, 1, 2);
              End;
          End;
        If Level > 0 Then
          Begin
            Include(Style.Styles, fsBold);
            Style.Size := Max(1, BaseSize * HeadingScale[Level] Div 100);
          End;
        Count := Length(Body);
        While (Count > 0) And (Body[Count] = '\') Do Dec(Count);
        HardBreak := (Copy(Body, Length(Body) - 1, 2) = '  ') Or
          Odd(Length(Body) - Count);
        If HardBreak Then
          Begin
            If Body[Length(Body)] = '\' Then Delete(Body, Length(Body), 1);
            Body := TrimRight(Body);
          End;
        If Not ParagraphOpen Or BlockLine Then NewParagraph(Indent, Background)
        Else Append(' ', Style);
        Inline(Body, Style);
        ParagraphOpen := Not BlockLine And Not HardBreak;
        Inc(Index);
      End;
    If FCount = 0 Then NewParagraph(0);
    SetLength(FContent, FCount);
    Result := FContent;
  Finally
    Lines.Free;
  End;
End;

Function BuildStyledMarkdown(Renderer: TStyledCanvas; Const MarkdownText: UTF8String;
  BaseSize: Integer): TStyledContent;
Var
  Reader: TMarkdownReader;
  Value: UTF8String;
Begin
  If Not Assigned(Renderer) Then Raise EArgumentException.Create('Styled Markdown requires a renderer');
  Value := MarkdownText;
  If Copy(Value, 1, 3) = #$EF#$BB#$BF Then Delete(Value, 1, 3);
  Reader := TMarkdownReader.Create;
  Try
    Result := Reader.Parse(Renderer, NormaliseStyledText(Value), Max(1, BaseSize));
  Finally
    Reader.Free;
  End;
End;

Constructor TStyledMarkdown.Create(Target: TCustomStyledText);
Begin
  Inherited Create;
  If Not Assigned(Target) Then Raise EArgumentException.Create('Styled Markdown requires a target control');
  FTarget := Target;
End;

Procedure TStyledMarkdown.LoadFromString(Const MarkdownText: UTF8String);
Var
  Content: TStyledContent;
  Flat: TStyledParagraph;
  Index, Offset: Integer;
  Range: TStyledRange;
  Groups: Array Of QWord;
Begin
  Content := BuildStyledMarkdown(FTarget.Renderer, MarkdownText, Max(1, Abs(FTarget.Font.Size)));
  If FTarget Is TStyledEdit Then
    Begin
      Flat := Default(TStyledParagraph);
      For Index := 0 To High(Content) Do
        Begin
          If Index > 0 Then AppendStyledText(Flat, ' ');
          Offset := Length(Flat.Text);
          Flat.Text += Content[Index].Text;
          For Range In Content[Index].Ranges Do
            AddStyledRange(Flat.Ranges, Offset + Range.Start, Range.Count, Range.Style);
        End;
      SetLength(Content, 1);
      Content[0] := Flat;
    End
  Else
    Begin
      { Each allocated group has at least one paragraph; remap to document IDs. }
      Groups := Nil;
      SetLength(Groups, Length(Content) + 1);
      For Index := 0 To High(Content) Do
        If Content[Index].Box.Group <> 0 Then
          Begin
            If Groups[Content[Index].Box.Group] = 0 Then
              Groups[Content[Index].Box.Group] := FTarget.Document.NewBoxGroup;
            Content[Index].Box.Group := Groups[Content[Index].Box.Group];
          End;
    End;
  FTarget.Document.Replace(StyledPosition(0, 0), FTarget.Document.EndPosition, Content);
  FTarget.InsertionStyle := 0;
  FTarget.SelectRange(StyledPosition(0, 0), StyledPosition(0, 0));
  FTarget.ScrollToStart;
End;

Procedure TStyledMarkdown.LoadFromStrings(Source: TStrings);
Begin
  If Not Assigned(Source) Then Raise EArgumentException.Create('Cannot load Markdown from nil strings');
  LoadFromString(Source.Text);
End;

Procedure TStyledMarkdown.LoadFromStream(Source: TStream);
Var
  Buffer: TMemoryStream;
  Data: UTF8String;
  BytesRead: LongInt;
  Chunk: Array[0..16383] Of Byte;
Begin
  If Not Assigned(Source) Then Raise EArgumentException.Create('Cannot load Markdown from a nil stream');
  Buffer := TMemoryStream.Create;
  Try
    Repeat
      BytesRead := Source.Read(Chunk, SizeOf(Chunk));
      If BytesRead < 0 Then Raise EReadError.Create('Cannot read Markdown stream');
      If BytesRead > 0 Then Buffer.WriteBuffer(Chunk, BytesRead);
    Until BytesRead = 0;
    SetString(Data, PAnsiChar(Buffer.Memory), Buffer.Size);
    LoadFromString(Data);
  Finally
    Buffer.Free;
  End;
End;

Procedure TStyledMarkdown.LoadFromFile(Const FileName: String);
Var
  Source: TFileStream;
Begin
  Source := TFileStream.Create(FileName, fmOpenRead Or fmShareDenyWrite);
  Try
    LoadFromStream(Source);
  Finally
    Source.Free;
  End;
End;

End.
