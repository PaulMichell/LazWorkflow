Unit StyledTableLayout;

{ Tab-separated table rows built from styled cell boxes (c) 2026 Michell Computing.
  Equal-width columns keep rows aligned without measuring the whole document. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Graphics, Types, StyledTextTypes, StyledCanvas;

Procedure PrepareStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout; Const Paragraph: TStyledParagraph);
Function ContinueStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout;
    Const Paragraph: TStyledParagraph; Milliseconds: Integer): Boolean;
Procedure DrawStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout; X: Integer; Y: Int64;
    Const Clip: TRect; SelectionStart, SelectionEnd: Integer; Foreground: TColor);

Implementation

Uses
  Math, StrUtils, SysUtils;

Procedure PrepareStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout; Const Paragraph: TStyledParagraph);
Var
  Cell: TStyledParagraph;
  Range: TStyledRange;
  Geometry: TStyledBoxGeometry;
  Index, Count, Start, Finish, Left, Right: Integer;
  Child: TStyledLayout;
Begin
  Count := 1;
  For Index := 1 To Length(Paragraph.Text) Do
    If Paragraph.Text[Index] = #9 Then Inc(Count);
  { Structural edits never discard text. A row with changed separators falls
    back to ordinary text until its number of cells matches the column schema. }
  If Count <> Length(Paragraph.Box.Columns) Then Exit;
  SetLength(Layout.Cells, Count);
  SetLength(Layout.CellParagraphs, Count);
  SetLength(Layout.CellStarts, Count);
  SetLength(Layout.CellLefts, Count);
  SetLength(Layout.CellWidths, Count);
  Layout.CellStyle := Paragraph.Box.Style;
  Layout.CellStyle.Margin := StyledInsets(0);
  Layout.CellStyle.CornerRadius := 0;
  Start := 0;

  For Index := 0 To Count - 1 Do
    Begin
      Finish := PosEx(#9, Paragraph.Text, Start + 1) - 1;
      If Finish < 0 Then Finish := Length(Paragraph.Text);
      Cell := Default(TStyledParagraph);
      Cell.Text := Copy(Paragraph.Text, Start + 1, Finish - Start);
      For Range In Paragraph.Ranges Do
        Begin
          Left := Max(Start, Range.Start);
          Right := Min(Finish, Range.Start + Range.Count);
          AddStyledRange(Cell.Ranges, Left - Start, Right - Left, Range.Style);
        End;
      Layout.CellStarts[Index] := Start;
      Layout.CellLefts[Index] := Int64(Index) * Max(0, Layout.AvailableWidth) Div Count;
      Layout.CellWidths[Index] := Int64(Index + 1) * Max(0, Layout.AvailableWidth) Div Count - Layout.CellLefts[Index];
      Geometry := GetStyledBoxGeometry(0, 0, Layout.CellWidths[Index], 0, Layout.CellStyle);
      Child := TStyledLayout.Create;
      Layout.Cells[Index] := Child;
      Layout.CellParagraphs[Index] := Cell;
      Renderer.BeginLayout(Child, Cell, Max(1, Geometry.Content.Right - Geometry.Content.Left), swWord);
      Start := Finish + 1;
    End;
  Layout.Width := Max(0, Layout.AvailableWidth);
End;

Function ContinueStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout;
    Const Paragraph: TStyledParagraph; Milliseconds: Integer): Boolean;
Var
  Started: QWord;
  Remaining, Index, LineIndex, FirstLine, RunIndex, Shift, TotalLines: Integer;
  Child: TStyledLayout;
Begin
  If Layout.Complete Then Exit(True);
  Started := GetTickCount64;
  While Layout.NextCell < Length(Layout.Cells) Do
    Begin
      Index := Layout.NextCell;
      Child := Layout.Cells[Index];
      FirstLine := Child.LineCount;
      Remaining := 0;
      If Milliseconds > 0 Then
        Remaining := Max(1, Int64(Milliseconds) - Int64(GetTickCount64 - Started));
      Renderer.ContinueLayout(Child, Layout.CellParagraphs[Index], Remaining);
      { Align each new line once, including lines published by a partial cell. }
      For LineIndex := FirstLine To Child.LineCount - 1 Do
        Begin
          Shift := Max(0, Child.AvailableWidth - Child.Lines[LineIndex].Width);
          Case Paragraph.Box.Columns[Index] Of
            scaLeft: Shift := 0;
            scaCenter: Shift := Shift Div 2;
            scaRight:;
          End;
          For RunIndex := Child.Lines[LineIndex].FirstRun To
            Child.Lines[LineIndex].FirstRun + Child.Lines[LineIndex].RunCount - 1 Do
              Inc(Child.Runs[RunIndex].X, Shift);
          Inc(Child.Lines[LineIndex].Width, Shift);
        End;
      Layout.Height := Max(Layout.Height, Child.Height + Max(0, Layout.CellStyle.BorderWidth) * 2 +
        Layout.CellStyle.Padding.Top + Layout.CellStyle.Padding.Bottom);
      If Child.Complete Then Inc(Layout.NextCell);
      If (Milliseconds > 0) And (GetTickCount64 - Started >= QWord(Milliseconds)) Then Break;
    End;
  { Publish geometry for selection and scroll extents while cells are pending. }
  TotalLines := 0;
  For Child In Layout.Cells Do Inc(TotalLines, Child.LineCount);
  SetLength(Layout.Lines, TotalLines);
  Layout.LineCount := 0;
  For Index := 0 To High(Layout.Cells) Do
    For LineIndex := 0 To Layout.Cells[Index].LineCount - 1 Do
      Begin
        Layout.Lines[Layout.LineCount] := Layout.Cells[Index].Lines[LineIndex];
        Inc(Layout.Lines[Layout.LineCount].Start, Layout.CellStarts[Index]);
        Inc(Layout.Lines[Layout.LineCount].Finish, Layout.CellStarts[Index]);
        Inc(Layout.Lines[Layout.LineCount].Top, Max(0, Layout.CellStyle.BorderWidth) + Layout.CellStyle.Padding.Top);
        Inc(Layout.LineCount);
      End;
  Layout.Complete := Layout.NextCell = Length(Layout.Cells);
  If Layout.Complete Then
    Begin
      Layout.NextOffset := Length(Paragraph.Text);
      Layout.CellParagraphs := Nil;
    End
  Else Layout.NextOffset := Layout.CellStarts[Layout.NextCell] + Layout.Cells[Layout.NextCell].NextOffset;
  Result := Layout.Complete;
End;

Procedure DrawStyledTable(Renderer: TStyledCanvas; Layout: TStyledLayout; X: Integer; Y: Int64;
    Const Clip: TRect; SelectionStart, SelectionEnd: Integer; Foreground: TColor);
Var
  Index, First, Last: Integer;
  Geometry: TStyledBoxGeometry;
  CellClip: TRect;
Begin
  For Index := 0 To High(Layout.Cells) Do
    Begin
      Geometry := GetStyledBoxGeometry(X + Layout.CellLefts[Index], Y,
        Layout.CellWidths[Index], Layout.Height, Layout.CellStyle);
      Renderer.DrawBoxFrame(Geometry, Layout.CellStyle, Clip);
      CellClip := Rect(Max(Int64(Clip.Left), Geometry.Content.Left), Max(Int64(Clip.Top), Geometry.Content.Top),
        Min(Int64(Clip.Right), Geometry.Content.Right), Min(Int64(Clip.Bottom), Geometry.Content.Bottom));
      If (CellClip.Left >= CellClip.Right) Or (CellClip.Top >= CellClip.Bottom) Then Continue;
      First := -1;
      Last := -1;
      If (SelectionStart >= 0) And (SelectionStart <= Layout.CellStarts[Index] + Length(Layout.Cells[Index].Source)) And
        (SelectionEnd > Layout.CellStarts[Index]) Then
          Begin
            First := Max(0, SelectionStart - Layout.CellStarts[Index]);
            Last := Min(Length(Layout.Cells[Index].Source) + 1, SelectionEnd - Layout.CellStarts[Index]);
          End;
      Renderer.Draw(Layout.Cells[Index], Geometry.Content.Left, Geometry.Content.Top, CellClip, First, Last, Foreground);
    End;
End;

End.
