Unit StyledCanvas;

{ Shared measured wrapping, painting and caret geometry (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, Graphics, Types, StyledTextTypes;

Type
  TStyledMetrics = Record
    Ascent, Descent, Leading, Shift, Size, SpaceWidth, AverageWidth: Integer;
  End;
  TStyledDrawingRun = Record
    Start, Count, Style, X, Width: Integer;
    Metrics: TStyledMetrics;
    Stops, Advances: TStyledIntegers;
    IsTab: Boolean;
  End;
  TStyledVisualLine = Record
    Start, Finish, FirstRun, RunCount, Width, Height, Baseline: Integer;
    Top: Int64;
  End;
  TStyledLayout = Class
  Public
    Source: UTF8String;
    Cells: Array Of TStyledLayout;
    CellParagraphs: TStyledContent;
    NextCell: Integer;
    CellStarts, CellLefts, CellWidths: TStyledIntegers;
    CellStyle: TStyledBoxStyle;
    Lines: Array Of TStyledVisualLine;
    Runs: Array Of TStyledDrawingRun;
    LineCount, RunCount, Width, AvailableWidth, NextOffset: Integer;
    Height: Int64;
    Revision, Generation: QWord;
    Wrap: TStyledWrap;
    Complete: Boolean;
    Destructor Destroy; Override;
    Function CellAtOffset(Offset: Integer): Integer;
    Function AtVerticalEdge(Offset: Integer; Trailing, Up: Boolean): Boolean;
    Procedure Clear;
    Function LineAtY(Y: Int64): Integer;
    Function LineAtOffset(Offset: Integer; Trailing: Boolean = False): Integer;
  End;
  TStyledBoxLayout = Class
  Public
    Paragraphs: Array Of TStyledLayout;
    ParagraphTops: Array Of Int64;
    Style: TStyledBoxStyle;
    Width, ContentWidth: Integer;
    Height, TextHeight: Int64;
    Destructor Destroy; Override;
  End;
  TStyledCanvasStats = Record
    Measurements, LayoutLines, DrawCalls, PaintedLines: QWord;
  End;
  TStyledCanvas = Class
  Private
    Styles: Array Of TStyledStyle;
    Metrics: Array Of TStyledMetrics;
    MetricValid: Array Of Boolean;
    Target: TCanvas;
    BaseFont: TFont;
    FGeneration: QWord;
    FStats: TStyledCanvasStats;
    FSurfaceWidth, FSurfaceHeight: Integer;
    ActiveStyle: Integer;
    Function GetStyle(Index: Integer): TStyledStyle;
    Function StyleAt(Const Paragraph: TStyledParagraph; Offset: Integer; Var Hint: Integer): Integer;
    Function Measure(Const Value: UTF8String; Style: Integer): Integer;
    Function GetMetrics(Style: Integer): TStyledMetrics;
    Function FitLine(Const Paragraph: TStyledParagraph; Start, Width: Integer; Wrap: TStyledWrap): Integer;
    Procedure AddLine(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Start, Finish: Integer);
    Procedure EnsureStops(Layout: TStyledLayout; RunIndex: Integer);
    Procedure ApplyStyle(Style: Integer);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Configure(Canvas: TCanvas; Font: TFont; SurfaceWidth: Integer = -1; SurfaceHeight: Integer = -1);
    Function LineHeight: Integer;
    Function AddStyle(Const Style: TStyledStyle): Integer;
    Procedure BeginLayout(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Width: Integer; Wrap: TStyledWrap;
      RestartOffset: Integer = 0);
    Function ContinueLayout(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Milliseconds: Integer = 8): Boolean;
    Procedure Prepare(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Width: Integer; Wrap: TStyledWrap);
    Procedure Draw(Layout: TStyledLayout; X: Integer; Y: Int64; Const Clip: TRect; SelectionStart: Integer = -1;
      SelectionEnd: Integer = -1; Foreground: TColor = clDefault);
    Procedure DrawBoxFrame(Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect);
    Procedure DrawBoxText(Layout: TStyledLayout; X: Integer; Y: Int64; Const Geometry: TStyledBoxGeometry;
      Const Style: TStyledBoxStyle; Const Clip: TRect; SelectionStart: Integer = -1; SelectionEnd: Integer = -1);
    Procedure PrepareBox(Layout: TStyledBoxLayout; Const Content: TStyledContent; OuterWidth: Integer;
      Const BoxStyle: TStyledBoxStyle; Wrap: TStyledWrap = swWord);
    Procedure DrawBox(Layout: TStyledBoxLayout; X: Integer; Y: Int64; Const Clip: TRect; OuterHeight: Int64 = -1); Overload;
    Procedure DrawBox(Layout: TStyledBoxLayout; Const OuterRect, Clip: TRect); Overload;
    Function PositionX(Layout: TStyledLayout; LineIndex, Offset: Integer): Integer;
    Function HitTest(Layout: TStyledLayout; X: Integer; Y: Int64; Out Trailing: Boolean): Integer;
    Function CaretRect(Layout: TStyledLayout; Offset: Integer; Trailing: Boolean = False): TRect;
    Property Generation: QWord Read FGeneration;
    Property StyleInfo[Index: Integer]: TStyledStyle Read GetStyle;
    Property Stats: TStyledCanvasStats Read FStats;
  End;

Implementation

Uses
  SysUtils, Math, LazUTF8, LCLIntf, LCLType, StyledBoxPainter, StyledTableLayout;

Destructor TStyledBoxLayout.Destroy;
Var
  Paragraph: TStyledLayout;
Begin
  For Paragraph In Paragraphs Do Paragraph.Free;
  Inherited Destroy;
End;

Destructor TStyledLayout.Destroy;
Begin
  Clear;
  Inherited Destroy;
End;

Function TStyledLayout.CellAtOffset(Offset: Integer): Integer;
Begin
  Result := 0;
  While (Result < High(Cells)) And (Offset >= CellStarts[Result + 1]) Do Inc(Result);
End;

Function TStyledLayout.AtVerticalEdge(Offset: Integer; Trailing, Up: Boolean): Boolean;
Var
  Index: Integer;
Begin
  If Length(Cells) > 0 Then
    Begin
      Index := CellAtOffset(Offset);
      Exit(Cells[Index].AtVerticalEdge(Offset - CellStarts[Index], Trailing, Up));
    End;
  Index := LineAtOffset(Offset, Trailing);
  If Up Then Result := Index = 0 Else Result := Index = LineCount - 1;
End;

Procedure TStyledLayout.Clear;
Var
  Index: Integer;
Begin
  For Index := 0 To High(Cells) Do Cells[Index].Free;
  Cells := Nil;
  CellParagraphs := Nil;
  NextCell := 0;
  CellStarts := Nil;
  CellLefts := Nil;
  CellWidths := Nil;
  For Index := 0 To RunCount - 1 Do
    Begin
      Runs[Index].Stops := Nil;
      Runs[Index].Advances := Nil;
    End;
  LineCount := 0;
  RunCount := 0;
  Height := 0;
  Width := 0;
  NextOffset := 0;
  Complete := False;
End;

Function TStyledLayout.LineAtY(Y: Int64): Integer;
Var
  Left, Right, Middle: Integer;
Begin
  Left := 0;
  Right := LineCount;
  While Left < Right Do
    Begin
      Middle := (Left + Right) Div 2;
      If Lines[Middle].Top + Lines[Middle].Height <= Y Then Left := Middle + 1 Else Right := Middle;
    End;
  Result := Min(Left, Max(0, LineCount - 1));
End;

Function TStyledLayout.LineAtOffset(Offset: Integer; Trailing: Boolean): Integer;
Var
  Left, Right, Middle: Integer;
Begin
  If Length(Cells) > 0 Then
    Begin
      Middle := CellAtOffset(Offset);
      Result := Cells[Middle].LineAtOffset(Offset - CellStarts[Middle], Trailing);
      For Left := 0 To Middle - 1 Do Inc(Result, Cells[Left].LineCount);
      Exit;
    End;
  Left := 0;
  Right := LineCount;
  While Left < Right Do
    Begin
      Middle := (Left + Right) Div 2;
      If (Lines[Middle].Finish < Offset) Or ((Lines[Middle].Finish = Offset) And Not Trailing) Then Left := Middle + 1
      Else Right := Middle;
    End;
  Result := Min(Left, Max(0, LineCount - 1));
End;

Constructor TStyledCanvas.Create;
Begin
  Inherited Create;
  BaseFont := TFont.Create;
  ActiveStyle := -1;
  FSurfaceWidth := -1;
  FSurfaceHeight := -1;
  AddStyle(DefaultStyledStyle);
End;

Destructor TStyledCanvas.Destroy;
Begin
  FreeAndNil(BaseFont);
  Inherited Destroy;
End;

Function MetricsDiffer(Const First, Second: TStyledMetrics): Boolean;
Begin
  Result := (First.Ascent <> Second.Ascent) Or (First.Descent <> Second.Descent) Or (First.Leading <> Second.Leading) Or
    (First.SpaceWidth <> Second.SpaceWidth) Or (First.AverageWidth <> Second.AverageWidth);
End;

Procedure TStyledCanvas.Configure(Canvas: TCanvas; Font: TFont; SurfaceWidth: Integer; SurfaceHeight: Integer);
Var
  Index: Integer;
  FontChanged, SurfaceChanged, HadMetrics: Boolean;
  Previous: TStyledMetrics;
Begin
  FontChanged := (BaseFont.Name <> Font.Name) Or (BaseFont.Size <> Font.Size) Or (BaseFont.Style <> Font.Style) Or
    (BaseFont.PixelsPerInch <> Font.PixelsPerInch) Or (BaseFont.Quality <> Font.Quality);
  SurfaceChanged := (SurfaceWidth >= 0) And (SurfaceHeight >= 0) And
    ((FSurfaceWidth <> SurfaceWidth) Or (FSurfaceHeight <> SurfaceHeight));
  HadMetrics := (Length(MetricValid) > 0) And MetricValid[0];
  If HadMetrics Then Previous := Metrics[0];
  If FontChanged Or SurfaceChanged Then
    For Index := 0 To High(MetricValid) Do MetricValid[Index] := False;
  If FontChanged Then Inc(FGeneration);
  { LCL TFont.Assign preserves the destination DPI. Copy it explicitly so
    subsequent paints compare the same metrics and do not invalidate forever. }
  BaseFont.PixelsPerInch := Font.PixelsPerInch;
  BaseFont.Assign(Font);
  Target := Canvas;
  ActiveStyle := -1;
  If SurfaceWidth >= 0 Then FSurfaceWidth := SurfaceWidth;
  If SurfaceHeight >= 0 Then FSurfaceHeight := SurfaceHeight;
  { A resize changes the measurement surface. Keep the first canvas's line
    height only when the new surface measures the same. }
  If SurfaceChanged And Not FontChanged And HadMetrics And Assigned(Target) Then
    If MetricsDiffer(Previous, GetMetrics(0)) Then Inc(FGeneration);
End;

Function TStyledCanvas.LineHeight: Integer;
Var
  Body: TStyledMetrics;
Begin
  If Not Assigned(Target) Then
    Begin
      Result := Abs(BaseFont.Height);
      If Result < 1 Then Result := 24;
      Exit;
    End;
  Body := GetMetrics(0);
  Result := Max(1, Body.Ascent + Body.Descent + Body.Leading + 1);
End;

Function TStyledCanvas.GetStyle(Index: Integer): TStyledStyle;
Begin
  If (Index < 0) Or (Index >= Length(Styles)) Then Index := 0;
  Result := Styles[Index];
End;

Function TStyledCanvas.AddStyle(Const Style: TStyledStyle): Integer;
Var
  Existing: TStyledStyle;
  Index: Integer;
Begin
  For Index := 0 To High(Styles) Do
    Begin
      Existing := Styles[Index];
      If (Existing.FontName = Style.FontName) And (Existing.Size = Style.Size) And (Existing.Styles = Style.Styles) And
        (Existing.Foreground = Style.Foreground) And (Existing.Background = Style.Background) And (Existing.Script = Style.Script) Then
        Exit(Index);
    End;
  Result := Length(Styles);
  SetLength(Styles, Result + 1);
  SetLength(Metrics, Result + 1);
  SetLength(MetricValid, Result + 1);
  Styles[Result] := Style;
End;

Procedure TStyledCanvas.ApplyStyle(Style: Integer);
Var
  Value: TStyledStyle;
  Size: Integer;
Begin
  If ActiveStyle = Style Then Exit;
  Value := GetStyle(Style);
  If Value.FontName = '' Then Target.Font.Name := BaseFont.Name Else Target.Font.Name := Value.FontName;
  Size := Value.Size;
  If Size = 0 Then Size := Max(1, BaseFont.Size);
  If Value.Script <> ssNormal Then Size := Max(1, Round(Size * 0.75));
  Target.Font.PixelsPerInch := BaseFont.PixelsPerInch;
  Target.Font.Size := Size;
  Target.Font.Style := (BaseFont.Style + Value.Styles) - [fsUnderline, fsStrikeOut];
  Target.Font.Quality := BaseFont.Quality;
  If Value.Foreground = clDefault Then Target.Font.Color := BaseFont.Color Else Target.Font.Color := Value.Foreground;
  ActiveStyle := Style;
End;

Function TStyledCanvas.GetMetrics(Style: Integer): TStyledMetrics;
Var
  Native: TLCLTextMetric;
  ParentSize: Integer;
Begin
  If (Style < 0) Or (Style >= Length(Styles)) Then Style := 0;
  If MetricValid[Style] Then Exit(Metrics[Style]);
  ApplyStyle(Style);
  If Target.GetTextMetrics(Native) Then
    Begin
      Result.Ascent := Max(1, Native.Ascender);
      Result.Descent := Max(1, Native.Descender);
      Result.Leading := Max(1, Native.Height - Result.Ascent - Result.Descent);
    End
  Else
    Begin
      Result.Ascent := Max(1, Target.TextHeight('Mg') * 4 Div 5);
      Result.Descent := Max(1, Target.TextHeight('Mg') - Result.Ascent);
      Result.Leading := 1;
    End;
  Result.SpaceWidth := Max(1, Target.TextWidth(' '));
  Result.AverageWidth := Max(1, Target.TextWidth('abcdefghijklmnopqrstuvwxyz') Div 26);
  Result.Size := Target.Font.Size;
  Result.Shift := 0;
  ParentSize := Styles[Style].Size;
  If ParentSize = 0 Then ParentSize := Max(1, BaseFont.Size);
  ParentSize := ParentSize * Max(96, BaseFont.PixelsPerInch) Div 72;
  Case Styles[Style].Script Of
    ssSubscript: Result.Shift := -Max(1, ParentSize Div 5);
    ssSuperscript: Result.Shift := Max(1, ParentSize Div 3);
  Else
  End;
  Metrics[Style] := Result;
  MetricValid[Style] := True;
End;

Function TStyledCanvas.Measure(Const Value: UTF8String; Style: Integer): Integer;
Begin
  ApplyStyle(Style);
  Result := Target.TextWidth(Value);
  Inc(FStats.Measurements);
End;

Function TStyledCanvas.StyleAt(Const Paragraph: TStyledParagraph; Offset: Integer; Var Hint: Integer): Integer;
Var
  Left, Right, Middle: Integer;
Begin
  If Length(Paragraph.Ranges) = 0 Then Exit(0);
  If (Hint < 0) Or (Hint >= Length(Paragraph.Ranges)) Or (Paragraph.Ranges[Hint].Start > Offset) Or
    (Paragraph.Ranges[Hint].Start + Paragraph.Ranges[Hint].Count <= Offset) Then
    Begin
      Left := 0;
      Right := Length(Paragraph.Ranges);
      While Left < Right Do
        Begin
          Middle := (Left + Right) Div 2;
          If Paragraph.Ranges[Middle].Start + Paragraph.Ranges[Middle].Count <= Offset Then Left := Middle + 1 Else Right := Middle;
        End;
      Hint := Min(Left, High(Paragraph.Ranges));
    End;
  Result := Paragraph.Ranges[Hint].Style;
End;

Function TStyledCanvas.FitLine(Const Paragraph: TStyledParagraph; Start, Width: Integer; Wrap: TStyledWrap): Integer;
Var
  Hint, Style, Finish, ChunkEnd, X, Advance, FitChars, FitBytes, Boundary, LastBreak, Scan, TabWidth: Integer;
  Chunk: UTF8String;
Begin
  If Wrap = swNone Then Exit(Length(Paragraph.Text));
  Result := Start;
  X := 0;
  Hint := -1;
  TabWidth := 4 * GetMetrics(0).SpaceWidth;
  While Result < Length(Paragraph.Text) Do
    Begin
      Style := StyleAt(Paragraph, Result, Hint);
      If Paragraph.Text[Result + 1] = #9 Then
        Begin
          Advance := TabWidth - X Mod TabWidth;
          If (X + Advance > Width) And (Result > Start) Then Break;
          Inc(X, Advance);
          Inc(Result);
          Continue;
        End;
      Finish := Paragraph.Ranges[Hint].Start + Paragraph.Ranges[Hint].Count;
      ChunkEnd := Min(Finish, Result + Max(32, Min(2048, (Width - X) Div GetMetrics(Style).AverageWidth * 2 + 8)));
      If ChunkEnd < Finish Then ChunkEnd := PreviousCluster(Paragraph.Text, ChunkEnd);
      If ChunkEnd <= Result Then ChunkEnd := NextCluster(Paragraph.Text, Result);
      Scan := Result;
      While Scan < ChunkEnd Do
        Begin
          If Paragraph.Text[Scan + 1] = #9 Then
            Begin
              ChunkEnd := Scan;
              Break;
            End;
          Inc(Scan);
        End;
      Chunk := Copy(Paragraph.Text, Result + 1, ChunkEnd - Result);
      Advance := Measure(Chunk, Style);
      If X + Advance <= Width Then
        Begin
          Inc(X, Advance);
          Result := ChunkEnd;
          Continue;
        End;
      FitChars := Target.TextFitInfo(Chunk, Max(0, Width - X));
      FitBytes := UTF8CodepointToByteIndex(PChar(Chunk), Length(Chunk), FitChars);
      FitBytes := EnsureRange(FitBytes, 0, Length(Chunk));
      Boundary := Result;
      While NextCluster(Paragraph.Text, Boundary) <= Result + FitBytes Do
        Begin
          Scan := NextCluster(Paragraph.Text, Boundary);
          If Scan <= Boundary Then Break;
          Boundary := Scan;
        End;
      Result := Boundary;
      Break;
    End;
  If Result <= Start Then Exit(NextCluster(Paragraph.Text, Start));
  If (Wrap = swWord) And (Result < Length(Paragraph.Text)) Then
    Begin
      LastBreak := Start;
      Scan := Start;
      While Scan < Result Do
        Begin
          If Paragraph.Text[Scan + 1] In [' ', #9, '-'] Then LastBreak := Scan + 1;
          Scan := NextCluster(Paragraph.Text, Scan);
        End;
      { A following separator means the complete word already fits. }
      If (LastBreak > Start) And Not (Paragraph.Text[Result + 1] In [' ', #9]) Then Result := LastBreak;
      { Carry wrap separators on the preceding line without changing the source. }
      While (Result < Length(Paragraph.Text)) And (Paragraph.Text[Result + 1] In [' ', #9]) Do Inc(Result);
    End;
End;

Procedure TStyledCanvas.AddLine(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Start, Finish: Integer);
Var
  Line: TStyledVisualLine;
  Run: TStyledDrawingRun;
  Position, Hint, EndRun, RunLimit, Above, Below, Leading, TabWidth, Scan: Integer;
  Body: TStyledMetrics;
Begin
  Line := Default(TStyledVisualLine);
  Line.Start := Start;
  Line.Finish := Finish;
  Line.Top := Layout.Height;
  Line.FirstRun := Layout.RunCount;
  Position := Start;
  Above := 0;
  Below := 0;
  Leading := 1;
  Hint := -1;
  TabWidth := 0;
  While Position < Finish Do
    Begin
      Run := Default(TStyledDrawingRun);
      Run.Style := StyleAt(Paragraph, Position, Hint);
      RunLimit := Min(Finish, Paragraph.Ranges[Hint].Start + Paragraph.Ranges[Hint].Count);
      EndRun := Min(RunLimit, Position + 2048);
      If EndRun < Finish Then
        Begin
          Scan := PreviousCluster(Paragraph.Text, EndRun + 1);
          If Scan > Position Then EndRun := Scan
          Else EndRun := Min(RunLimit, NextCluster(Paragraph.Text, Position));
        End;
      Run.IsTab := Paragraph.Text[Position + 1] = #9;
      If Run.IsTab Then EndRun := Position + 1
      Else
        For Scan := Position To EndRun - 1 Do
          If Paragraph.Text[Scan + 1] = #9 Then
            Begin
              EndRun := Scan;
              Break;
            End;
      Run.Start := Position;
      Run.Count := EndRun - Position;
      Run.X := Line.Width;
      Run.Metrics := GetMetrics(Run.Style);
      If Run.IsTab Then
        Begin
          If TabWidth = 0 Then TabWidth := 4 * GetMetrics(0).SpaceWidth;
          Run.Width := TabWidth - Line.Width Mod TabWidth;
        End
      Else Run.Width := Measure(Copy(Paragraph.Text, Position + 1, Run.Count), Run.Style);
      Above := Max(Above, Run.Metrics.Ascent + Run.Metrics.Shift);
      Below := Max(Below, Run.Metrics.Descent - Run.Metrics.Shift);
      Leading := Max(Leading, Run.Metrics.Leading);
      If Layout.RunCount = Length(Layout.Runs) Then SetLength(Layout.Runs, Max(16, Layout.RunCount * 2));
      Layout.Runs[Layout.RunCount] := Run;
      Inc(Layout.RunCount);
      Inc(Line.Width, Run.Width);
      Position := EndRun;
    End;
  If Position = Start Then
    Begin
      Body := GetMetrics(0);
      Above := Body.Ascent;
      Below := Body.Descent;
      Leading := Body.Leading;
    End;
  Line.Baseline := Above;
  Line.Height := Max(1, Above + Below + Leading + 1);
  Line.RunCount := Layout.RunCount - Line.FirstRun;
  If Layout.LineCount = Length(Layout.Lines) Then SetLength(Layout.Lines, Max(8, Layout.LineCount * 2));
  Layout.Lines[Layout.LineCount] := Line;
  Inc(Layout.LineCount);
  Inc(Layout.Height, Line.Height);
  Layout.Width := Max(Layout.Width, Line.Width);
  Inc(FStats.LayoutLines);
End;

Procedure TStyledCanvas.BeginLayout(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Width: Integer; Wrap: TStyledWrap;
  RestartOffset: Integer);
Var
  LineIndex, Index: Integer;
Begin
  If (Layout.Revision = Paragraph.Revision) And (Layout.Source = Paragraph.Text) And (Layout.Generation = FGeneration) And
    (Layout.AvailableWidth = Width) And (Layout.Wrap = Wrap) And
    ((Length(Layout.Cells) > 0) = (Length(Paragraph.Box.Columns) > 0)) Then Exit;
  If (Length(Layout.Cells) = 0) And (Length(Paragraph.Box.Columns) = 0) And
    (RestartOffset > 0) And (Layout.Generation = FGeneration) And (Layout.AvailableWidth = Width) And (Layout.Wrap = Wrap) And
    (Layout.LineCount > 0) Then
    Begin
      LineIndex := Max(0, Layout.LineAtOffset(RestartOffset) - 1);
      Layout.NextOffset := Layout.Lines[LineIndex].Start;
      Layout.Height := Layout.Lines[LineIndex].Top;
      For Index := Layout.Lines[LineIndex].FirstRun To Layout.RunCount - 1 Do
        Begin
          Layout.Runs[Index].Stops := Nil;
          Layout.Runs[Index].Advances := Nil;
        End;
      Layout.RunCount := Layout.Lines[LineIndex].FirstRun;
      Layout.LineCount := LineIndex;
      Layout.Complete := False;
    End
  Else Layout.Clear;
  Layout.Source := Paragraph.Text;
  Layout.Revision := Paragraph.Revision;
  Layout.Generation := FGeneration;
  Layout.AvailableWidth := Width;
  Layout.Wrap := Wrap;
  If Length(Paragraph.Box.Columns) > 0 Then PrepareStyledTable(Self, Layout, Paragraph);
End;

Function TStyledCanvas.ContinueLayout(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Milliseconds: Integer): Boolean;
Var
  Started: QWord;
  Finish: Integer;
Begin
  If Length(Layout.Cells) > 0 Then
    Exit(ContinueStyledTable(Self, Layout, Paragraph, Milliseconds));
  Started := GetTickCount64;
  While Not Layout.Complete Do
    Begin
      Finish := FitLine(Paragraph, Layout.NextOffset, Max(1, Layout.AvailableWidth), Layout.Wrap);
      AddLine(Layout, Paragraph, Layout.NextOffset, Finish);
      Layout.NextOffset := Finish;
      Layout.Complete := Finish >= Length(Paragraph.Text);
      If (Milliseconds > 0) And (GetTickCount64 - Started >= QWord(Milliseconds)) Then Break;
    End;
  Result := Layout.Complete;
End;

Procedure TStyledCanvas.Prepare(Layout: TStyledLayout; Const Paragraph: TStyledParagraph; Width: Integer; Wrap: TStyledWrap);
Begin
  BeginLayout(Layout, Paragraph, Width, Wrap);
  ContinueLayout(Layout, Paragraph, 0);
End;

Procedure TStyledCanvas.EnsureStops(Layout: TStyledLayout; RunIndex: Integer);
Var
  Run: ^TStyledDrawingRun;
  Partial: TStyledIntegers;
  Value: UTF8String;
  Extent: TSize;
  Offset, CharacterIndex, ClusterEnd, Count, Index: Integer;
Begin
  Run := @Layout.Runs[RunIndex];
  If Length(Run^.Stops) > 0 Then Exit;
  Value := Copy(Layout.Source, Run^.Start + 1, Run^.Count);
  SetLength(Partial, Length(Value) + 1);
  ApplyStyle(Run^.Style);
  { TextExtent selects the effective font before the lower-level advance query. }
  Target.TextExtent(Value);
  If Not Run^.IsTab Then
    Begin
      If Not GetTextExtentExPoint(Target.Handle, PChar(Value), Length(Value), High(Integer), Nil, @Partial[0], Extent) Then
        Raise Exception.Create('The canvas cannot return text advances');
      Inc(FStats.Measurements);
    End;
  Count := 1;
  Offset := 0;
  While Offset < Length(Value) Do
    Begin
      Offset := NextCluster(Value, Offset);
      Inc(Count);
    End;
  SetLength(Run^.Stops, Count);
  SetLength(Run^.Advances, Count);
  Offset := 0;
  CharacterIndex := 0;
  Index := 1;
  While Offset < Length(Value) Do
    Begin
      ClusterEnd := NextCluster(Value, Offset);
      While Offset < ClusterEnd Do
        Begin
          Offset := NextCodepoint(Value, Offset);
          Inc(CharacterIndex);
        End;
      Run^.Stops[Index] := Offset;
      If Run^.IsTab Then Run^.Advances[Index] := Run^.Width Else Run^.Advances[Index] := Partial[CharacterIndex - 1];
      Inc(Index);
    End;
  Run^.Advances[Count - 1] := Run^.Width;
End;

Function TStyledCanvas.PositionX(Layout: TStyledLayout; LineIndex, Offset: Integer): Integer;
Var
  Line: TStyledVisualLine;
  Index, Left, Right, Middle: Integer;
  Run: ^TStyledDrawingRun;
Begin
  If Length(Layout.Cells) > 0 Then
    Begin
      Index := Layout.CellAtOffset(Offset);
      Exit(Layout.CellLefts[Index] + Max(0, Layout.CellStyle.BorderWidth) + Layout.CellStyle.Padding.Left +
        PositionX(Layout.Cells[Index], Layout.Cells[Index].LineAtOffset(Offset - Layout.CellStarts[Index],
          Layout.Lines[LineIndex].Finish = Offset), Offset - Layout.CellStarts[Index]));
    End;
  Result := 0;
  If Layout.LineCount = 0 Then Exit;
  Line := Layout.Lines[EnsureRange(LineIndex, 0, Layout.LineCount - 1)];
  For Index := Line.FirstRun To Line.FirstRun + Line.RunCount - 1 Do
    Begin
      Run := @Layout.Runs[Index];
      If Offset > Run^.Start + Run^.Count Then Continue;
      EnsureStops(Layout, Index);
      Left := 0;
      Right := Length(Run^.Stops) - 1;
      While Left < Right Do
        Begin
          Middle := (Left + Right + 1) Div 2;
          If Run^.Start + Run^.Stops[Middle] <= Offset Then Left := Middle Else Right := Middle - 1;
        End;
      Exit(Run^.X + Run^.Advances[Left]);
    End;
  Result := Line.Width;
End;

Function TStyledCanvas.HitTest(Layout: TStyledLayout; X: Integer; Y: Int64; Out Trailing: Boolean): Integer;
Var
  Line: TStyledVisualLine;
  LineIndex, Index, Stop: Integer;
  Run: ^TStyledDrawingRun;
Begin
  If Length(Layout.Cells) > 0 Then
    Begin
      Index := 0;
      While (Index < High(Layout.Cells)) And (X >= Layout.CellLefts[Index + 1]) Do Inc(Index);
      Exit(Layout.CellStarts[Index] + HitTest(Layout.Cells[Index],
        X - Layout.CellLefts[Index] - Max(0, Layout.CellStyle.BorderWidth) - Layout.CellStyle.Padding.Left,
        Y - Max(0, Layout.CellStyle.BorderWidth) - Layout.CellStyle.Padding.Top, Trailing));
    End;
  Result := 0;
  Trailing := False;
  If Layout.LineCount = 0 Then Exit;
  LineIndex := Layout.LineAtY(Y);
  Line := Layout.Lines[LineIndex];
  If X <= 0 Then Exit(Line.Start);
  For Index := Line.FirstRun To Line.FirstRun + Line.RunCount - 1 Do
    Begin
      Run := @Layout.Runs[Index];
      If X > Run^.X + Run^.Width Then Continue;
      EnsureStops(Layout, Index);
      For Stop := 1 To High(Run^.Stops) Do
        If X - Run^.X < (Run^.Advances[Stop - 1] + Run^.Advances[Stop]) / 2 Then
          Exit(Run^.Start + Run^.Stops[Stop - 1]);
      Result := Run^.Start + Run^.Count;
      Trailing := (Result = Line.Finish) And (LineIndex < Layout.LineCount - 1);
      Exit;
    End;
  Result := Line.Finish;
  Trailing := LineIndex < Layout.LineCount - 1;
End;

Function TStyledCanvas.CaretRect(Layout: TStyledLayout; Offset: Integer; Trailing: Boolean): TRect;
Var
  Index, X: Integer;
Begin
  Result := Rect(0, 0, 1, 1);
  If Layout.LineCount = 0 Then Exit;
  Index := Layout.LineAtOffset(Offset, Trailing);
  X := PositionX(Layout, Index, Offset);
  Result := Rect(X, Layout.Lines[Index].Top, X + 1, Layout.Lines[Index].Top + Layout.Lines[Index].Height);
End;

Procedure TStyledCanvas.Draw(Layout: TStyledLayout; X: Integer; Y: Int64; Const Clip: TRect; SelectionStart: Integer;
  SelectionEnd: Integer; Foreground: TColor);
Var
  Line: TStyledVisualLine;
  Run: TStyledDrawingRun;
  Value: TStyledStyle;
  LineIndex, RunIndex, LineY, Left, Right: Integer;
  SelectionRect, RunRect, ActualClip: TRect;
  HasSelection: Boolean;

  Procedure DrawRuns(TextColor: TColor);
  Var
    Index, TextY: Integer;
    TextRun: TStyledDrawingRun;
    RunStyle: TStyledStyle;
    TextValue: UTF8String;
  Begin
    For Index := Line.FirstRun To Line.FirstRun + Line.RunCount - 1 Do
      Begin
        TextRun := Layout.Runs[Index];
        If (X + TextRun.X > Clip.Right) Or (X + TextRun.X + TextRun.Width < Clip.Left) Then Continue;
        ApplyStyle(TextRun.Style);
        RunStyle := GetStyle(TextRun.Style);
        If TextColor <> clDefault Then Target.Font.Color := TextColor
        Else If RunStyle.Foreground = clDefault Then Target.Font.Color := BaseFont.Color
        Else Target.Font.Color := RunStyle.Foreground;
        Target.Brush.Style := bsClear;
        TextY := LineY + Line.Baseline - TextRun.Metrics.Ascent - TextRun.Metrics.Shift;
        If Not TextRun.IsTab Then
          Begin
            TextValue := Copy(Layout.Source, TextRun.Start + 1, TextRun.Count);
            Target.TextOut(X + TextRun.X, TextY, TextValue);
            Inc(FStats.DrawCalls);
          End;
        Target.Pen.Color := Target.Font.Color;
        Target.Pen.Width := Max(1, BaseFont.PixelsPerInch Div 96);
        If fsUnderline In RunStyle.Styles Then
          Target.Line(X + TextRun.X, TextY + TextRun.Metrics.Ascent + 1,
            X + TextRun.X + TextRun.Width, TextY + TextRun.Metrics.Ascent + 1);
        If fsStrikeOut In RunStyle.Styles Then
          Target.Line(X + TextRun.X, TextY + TextRun.Metrics.Ascent * 2 Div 3,
            X + TextRun.X + TextRun.Width, TextY + TextRun.Metrics.Ascent * 2 Div 3);
      End;
  End;

Begin
  If Length(Layout.Cells) > 0 Then
    Begin
      DrawStyledTable(Self, Layout, X, Y, Clip, SelectionStart, SelectionEnd, Foreground);
      Exit;
    End;
  If Layout.LineCount = 0 Then Exit;
  Target.SaveHandleState;
  Try
    IntersectClipRect(Target.Handle, Clip.Left, Clip.Top, Clip.Right, Clip.Bottom);
    ActiveStyle := -1;
    LineIndex := Layout.LineAtY(Clip.Top - Y);
    While LineIndex < Layout.LineCount Do
      Begin
        Line := Layout.Lines[LineIndex];
        If Y + Line.Top >= Clip.Bottom Then Break;
        LineY := Y + Line.Top;
        Inc(FStats.PaintedLines);
        HasSelection := (SelectionStart >= 0) And (SelectionEnd > SelectionStart) And
          (SelectionEnd > Line.Start) And (SelectionStart <= Line.Finish);
        SelectionRect := Rect(0, 0, 0, 0);
        If HasSelection Then
          Begin
            Left := X + PositionX(Layout, LineIndex, Max(Line.Start, SelectionStart));
            Right := X + PositionX(Layout, LineIndex, Min(Line.Finish, SelectionEnd));
            If SelectionEnd > Line.Finish Then Right := Max(Right, X + Line.Width + 5);
            SelectionRect := Rect(Left, LineY, Right, LineY + Line.Height);
          End;
        For RunIndex := Line.FirstRun To Line.FirstRun + Line.RunCount - 1 Do
          Begin
            Run := Layout.Runs[RunIndex];
            If (X + Run.X > Clip.Right) Or (X + Run.X + Run.Width < Clip.Left) Then Continue;
            Value := GetStyle(Run.Style);
            RunRect := Rect(X + Run.X, LineY, X + Run.X + Run.Width, LineY + Line.Height);
            If Value.Background <> clNone Then
              Begin
                Target.Brush.Style := bsSolid;
                Target.Brush.Color := Value.Background;
                Target.FillRect(RunRect);
              End;
          End;
        If HasSelection Then
          Begin
            Target.Brush.Style := bsSolid;
            Target.Brush.Color := clHighlight;
            Target.FillRect(SelectionRect);
          End;
        If HasSelection And IntersectRect(ActualClip, SelectionRect, Clip) Then
          Begin
            { Keep the complete shaped runs, but paint disjoint regions. Drawing
              white over normal glyphs leaves dark antialiased edges underneath. }
            Target.SaveHandleState;
            Try
              ExcludeClipRect(Target.Handle, ActualClip.Left, ActualClip.Top, ActualClip.Right, ActualClip.Bottom);
              DrawRuns(Foreground);
            Finally
              Target.RestoreHandleState;
              ActiveStyle := -1;
            End;
            Target.SaveHandleState;
            Try
              IntersectClipRect(Target.Handle, ActualClip.Left, ActualClip.Top, ActualClip.Right, ActualClip.Bottom);
              DrawRuns(clHighlightText);
            Finally
              Target.RestoreHandleState;
              ActiveStyle := -1;
            End;
          End
        Else DrawRuns(Foreground);
        Inc(LineIndex);
      End;
  Finally
    Target.RestoreHandleState;
    ActiveStyle := -1;
  End;
End;

Procedure TStyledCanvas.DrawBoxFrame(Const Geometry: TStyledBoxGeometry; Const Style: TStyledBoxStyle; Const Clip: TRect);
Begin
  PaintStyledBox(Target, Geometry, Style, Clip);
  ActiveStyle := -1;
End;

Procedure TStyledCanvas.DrawBoxText(Layout: TStyledLayout; X: Integer; Y: Int64; Const Geometry: TStyledBoxGeometry;
  Const Style: TStyledBoxStyle; Const Clip: TRect; SelectionStart: Integer; SelectionEnd: Integer);
Begin
  Target.SaveHandleState;
  Try
    If ClipStyledBoxText(Target, Geometry, Style, Clip) Then Draw(Layout, X, Y, Clip, SelectionStart, SelectionEnd);
  Finally
    Target.RestoreHandleState;
    ActiveStyle := -1;
  End;
End;

Procedure TStyledCanvas.PrepareBox(Layout: TStyledBoxLayout; Const Content: TStyledContent; OuterWidth: Integer;
  Const BoxStyle: TStyledBoxStyle; Wrap: TStyledWrap);
Var
  Index: Integer;
  Geometry: TStyledBoxGeometry;
Begin
  Layout.Style := BoxStyle;
  Layout.Width := Max(0, OuterWidth);
  Geometry := GetStyledBoxGeometry(0, 0, Layout.Width, 0, BoxStyle);
  Layout.ContentWidth := Geometry.Content.Right - Geometry.Content.Left;
  For Index := Length(Content) To High(Layout.Paragraphs) Do Layout.Paragraphs[Index].Free;
  SetLength(Layout.Paragraphs, Length(Content));
  SetLength(Layout.ParagraphTops, Length(Content));
  Layout.TextHeight := 0;
  For Index := 0 To High(Content) Do
    Begin
      If Not Assigned(Layout.Paragraphs[Index]) Then Layout.Paragraphs[Index] := TStyledLayout.Create;
      Layout.ParagraphTops[Index] := Layout.TextHeight;
      If Layout.ContentWidth > 0 Then
        Begin
          Prepare(Layout.Paragraphs[Index], Content[Index], Layout.ContentWidth, Wrap);
          Inc(Layout.TextHeight, Layout.Paragraphs[Index].Height);
        End;
    End;
  Layout.Height := Int64(Max(0, BoxStyle.Margin.Top)) + Max(0, BoxStyle.Margin.Bottom) +
    Int64(Max(0, BoxStyle.BorderWidth)) * 2 + Max(0, BoxStyle.Padding.Top) + Max(0, BoxStyle.Padding.Bottom) + Layout.TextHeight;
End;

Procedure TStyledCanvas.DrawBox(Layout: TStyledBoxLayout; Const OuterRect, Clip: TRect);
Begin
  If Max(Int64(0), Int64(OuterRect.Right) - OuterRect.Left) <> Layout.Width Then
    Raise EArgumentException.Create('PrepareBox must use the drawing rectangle width');
  DrawBox(Layout, OuterRect.Left, OuterRect.Top, Clip, Max(Int64(0), Int64(OuterRect.Bottom) - OuterRect.Top));
End;

Procedure TStyledCanvas.DrawBox(Layout: TStyledBoxLayout; X: Integer; Y: Int64; Const Clip: TRect; OuterHeight: Int64);
Var
  Geometry: TStyledBoxGeometry;
  ContentClip: TRect;
  Left, Right, Middle, Index: Integer;
  TextTop: Int64;


Begin
  If OuterHeight < 0 Then OuterHeight := Layout.Height;
  Geometry := GetStyledBoxGeometry(X, Y, Layout.Width, OuterHeight, Layout.Style);
  If (Geometry.Border.Right <= Clip.Left) Or (Geometry.Border.Left >= Clip.Right) Or
    (Geometry.Border.Bottom <= Clip.Top) Or (Geometry.Border.Top >= Clip.Bottom) Then Exit;
  Target.SaveHandleState;
  Try
    IntersectClipRect(Target.Handle, Clip.Left, Clip.Top, Clip.Right, Clip.Bottom);
    DrawBoxFrame(Geometry, Layout.Style, Clip);
    If (Geometry.Content.Right <= Clip.Left) Or (Geometry.Content.Left >= Clip.Right) Or
      (Geometry.Content.Bottom <= Clip.Top) Or (Geometry.Content.Top >= Clip.Bottom) Or
      (Geometry.Content.Right <= Geometry.Content.Left) Or (Geometry.Content.Bottom <= Geometry.Content.Top) Then Exit;
    ContentClip := Rect(Max(Int64(Clip.Left), Geometry.Content.Left), Max(Int64(Clip.Top), Geometry.Content.Top),
      Min(Int64(Clip.Right), Geometry.Content.Right), Min(Int64(Clip.Bottom), Geometry.Content.Bottom));
    Left := 0;
    Right := Length(Layout.Paragraphs);
    While Left < Right Do
      Begin
        Middle := (Left + Right) Div 2;
        If Geometry.Content.Top + Layout.ParagraphTops[Middle] + Layout.Paragraphs[Middle].Height <= ContentClip.Top Then
          Left := Middle + 1 Else Right := Middle;
      End;
    Index := Left;
    While Index < Length(Layout.Paragraphs) Do
      Begin
        TextTop := Geometry.Content.Top + Layout.ParagraphTops[Index];
        If TextTop >= ContentClip.Bottom Then Break;
        DrawBoxText(Layout.Paragraphs[Index], Geometry.Content.Left, TextTop, Geometry, Layout.Style, ContentClip);
        Inc(Index);
      End;
  Finally
    Target.RestoreHandleState;
    ActiveStyle := -1;
  End;
End;

End.
