Unit ManageRepositoryHistory;

{ History-tab graph metrics and painting for Manage Repository (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Graphics, Controls, ExtCtrls, StdCtrls, Forms, GitGraphModel, CanvasUtils;

Type
  TManageHistoryGraph = Class
  Private
    FHost: TCustomForm;
    FPaintBox: TPaintBox;
    FScrollBar: TScrollBar;
    FModel: TGitGraphModel;
    FSelectedIndex: Integer;
    FIndexing: Boolean;
    FRepoPath: String;
    FHeadSha: String;
    FLaneColors: Array[0..9] Of TColor;
    Procedure InitLaneColors;
    Function GraphScale(DesignPx: Integer): Integer;
    Function GraphCanMeasureFont: Boolean;
    Function GraphLaneWidth: Integer;
    Function GraphLeftMargin: Integer;
    Function GraphNodeRadius: Integer;
    Function GraphTextGap: Integer;
    Function GraphDateColumnWidth: Integer;
    Function GraphContentWidth: Integer;
    Procedure PrepareGraphTextFont(ACanvas: TCanvas; IsDate: Boolean);
    Function LaneX(Lane: Integer): Integer;
    Function RowMidY(Row: Integer): Integer;
    Function FormatCommitDate(Const CommitTime: Int64): String;
    Procedure DrawRefCards(Const Refs: String; Var TextX: Integer; RowTop: Integer; RowColor: TColor);
    Function CommitIsCheckedOut(Const CommitRec: TGitCommitRec): Boolean;
    Function StrokesNear(NodeX, NodeY, Reach: Single; Const Visible: TGitEdgeIndices; HalfWidth: Single): TSmoothStrokeArray;
  Public
    Constructor Create(Host: TCustomForm);
    Procedure Bind(PaintBox: TPaintBox; ScrollBar: TScrollBar; Model: TGitGraphModel);
    Function RowHeight: Integer;
    Function ContentHeight: Integer;
    Function ScrollOffset: Integer;
    Function RowAtY(Y: Integer): Integer;
    Procedure GetVisibleRange(Out FirstRow, LastRow: Integer);
    Procedure UpdateScrollRange;
    Procedure Paint;
    Property SelectedIndex: Integer Read FSelectedIndex Write FSelectedIndex;
    Property Indexing: Boolean Read FIndexing Write FIndexing;
    Property RepoPath: String Read FRepoPath Write FRepoPath;
    Property HeadSha: String Read FHeadSha Write FHeadSha;
  End;

Implementation

Uses
  Types, Math, DateUtils, GitConfig;

Constructor TManageHistoryGraph.Create(Host: TCustomForm);
Begin
  Inherited Create;
  FHost := Host;
  FSelectedIndex := -1;
  FIndexing := False;
  FRepoPath := '';
  FHeadSha := '';
  InitLaneColors;
End;

Procedure TManageHistoryGraph.Bind(PaintBox: TPaintBox; ScrollBar: TScrollBar; Model: TGitGraphModel);
Begin
  FPaintBox := PaintBox;
  FScrollBar := ScrollBar;
  FModel := Model;
End;

Procedure TManageHistoryGraph.InitLaneColors;
Begin
  FLaneColors[0] := RGBToColor(33, 150, 243);
  FLaneColors[1] := RGBToColor(76, 175, 80);
  FLaneColors[2] := RGBToColor(255, 152, 0);
  FLaneColors[3] := RGBToColor(156, 39, 176);
  FLaneColors[4] := RGBToColor(244, 67, 54);
  FLaneColors[5] := RGBToColor(0, 150, 136);
  FLaneColors[6] := RGBToColor(63, 81, 181);
  FLaneColors[7] := RGBToColor(233, 30, 99);
  FLaneColors[8] := RGBToColor(121, 85, 72);
  FLaneColors[9] := RGBToColor(96, 125, 139);
End;

Function TManageHistoryGraph.GraphScale(DesignPx: Integer): Integer;
Var
  PPI: Integer;
Begin
  PPI := 96;
  If Assigned(FHost) Then
    PPI := FHost.PixelsPerInch;
  If PPI <= 0 Then
    PPI := Screen.PixelsPerInch;
  If PPI <= 0 Then
    PPI := 96;
  Result := Integer((Int64(DesignPx) * PPI) Div 96);
  If (DesignPx > 0) And (Result < 1) Then
    Result := 1;
End;

Function TManageHistoryGraph.GraphCanMeasureFont: Boolean;
Begin
  Result := Assigned(FPaintBox) And Assigned(FPaintBox.Parent) And FPaintBox.Parent.HandleAllocated;
End;

Function TManageHistoryGraph.RowHeight: Integer;
Var
  TextH, Base, Pad: Integer;
Begin
  Base := GraphScale(GitGraphRowHeight);
  Pad := GraphScale(6);
  Result := Base;
  If GraphCanMeasureFont Then
    Begin
      Try
        PrepareGraphTextFont(FPaintBox.Canvas, False);
        TextH := FPaintBox.Canvas.TextHeight('Ag');
        Result := Max(Base, TextH + Pad);
      Except
        Result := Base;
      End;
    End;
End;

Function TManageHistoryGraph.GraphLaneWidth: Integer;
Begin
  Result := GraphScale(GitGraphLaneWidth);
End;

Function TManageHistoryGraph.GraphLeftMargin: Integer;
Begin
  Result := GraphScale(GitGraphLeftMargin);
End;

Function TManageHistoryGraph.GraphNodeRadius: Integer;
Begin
  Result := GraphScale(GitGraphNodeRadius);
End;

Function TManageHistoryGraph.GraphTextGap: Integer;
Begin
  Result := GraphScale(GitGraphTextGap);
End;

Function TManageHistoryGraph.GraphDateColumnWidth: Integer;
Var
  SampleW: Integer;
Begin
  SampleW := GraphScale(110);
  If GraphCanMeasureFont Then
    Begin
      Try
        PrepareGraphTextFont(FPaintBox.Canvas, True);
        SampleW := FPaintBox.Canvas.TextWidth('0000-00-00 00:00');
      Except
        SampleW := GraphScale(110);
      End;
    End;
  Result := SampleW + GraphScale(GitGraphDateGap);
End;

Function TManageHistoryGraph.GraphContentWidth: Integer;
Begin
  If Assigned(FModel) Then
    Result := FModel.GraphWidth(GraphLeftMargin, GraphLaneWidth)
  Else
    Result := GraphLeftMargin;
End;

Function TManageHistoryGraph.ContentHeight: Integer;
Begin
  If Assigned(FModel) Then
    Result := FModel.TotalHeight(RowHeight)
  Else
    Result := 0;
End;

Procedure TManageHistoryGraph.PrepareGraphTextFont(ACanvas: TCanvas; IsDate: Boolean);
Var
  FontName: String;
  FontSize: Integer;
Begin
  If Not Assigned(ACanvas) Then
    Exit;
  FontName := 'default';
  If Assigned(FHost) Then
    FontName := FHost.Font.Name;
  FontSize := GitConfigDefaultGraphFontSize;
  If Assigned(GitManagerConfig) Then
    Begin
      If Trim(GitManagerConfig.GraphFontName) <> '' Then
        FontName := GitManagerConfig.GraphFontName;
      FontSize := GitManagerConfig.GraphFontSize;
    End;
  ACanvas.Font.Name := FontName;
  ACanvas.Font.Style := [];
  ACanvas.Font.Quality := fqCleartypeNatural;
  ACanvas.Font.Size := FontSize;
  If IsDate Then
    ACanvas.Font.Color := clGrayText
  Else
    ACanvas.Font.Color := clWindowText;
End;

Function TManageHistoryGraph.LaneX(Lane: Integer): Integer;
Var
  LW: Integer;
Begin
  LW := GraphLaneWidth;
  Result := GraphLeftMargin + Lane * LW + LW Div 2;
End;

Function TManageHistoryGraph.RowMidY(Row: Integer): Integer;
Var
  RH: Integer;
Begin
  RH := RowHeight;
  Result := Row * RH + RH Div 2 - ScrollOffset;
End;

Function TManageHistoryGraph.ScrollOffset: Integer;
Begin
  If Assigned(FScrollBar) Then
    Result := FScrollBar.Position
  Else
    Result := 0;
End;

Function TManageHistoryGraph.RowAtY(Y: Integer): Integer;
Var
  RH: Integer;
Begin
  Result := -1;
  If (Not Assigned(FModel)) Or (FModel.Count = 0) Then
    Exit;
  RH := RowHeight;
  If RH < 1 Then
    RH := 1;
  Result := (Y + ScrollOffset) Div RH;
  If (Result < 0) Or (Result >= FModel.Count) Then
    Result := -1;
End;

Function TManageHistoryGraph.FormatCommitDate(Const CommitTime: Int64): String;
Begin
  If CommitTime <= 0 Then
    Result := '…'
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(CommitTime));
End;

Procedure TManageHistoryGraph.GetVisibleRange(Out FirstRow, LastRow: Integer);
Var
  ViewH, RH: Integer;
Begin
  FirstRow := 0;
  LastRow := -1;
  If (Not Assigned(FModel)) Or (FModel.Count = 0) Or (Not Assigned(FPaintBox)) Then
    Exit;
  RH := RowHeight;
  If RH < 1 Then
    RH := 1;
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  FirstRow := ScrollOffset Div RH;
  LastRow := (ScrollOffset + ViewH) Div RH;
  If FirstRow < 0 Then
    FirstRow := 0;
  If LastRow >= FModel.Count Then
    LastRow := FModel.Count - 1;
End;

Procedure TManageHistoryGraph.UpdateScrollRange;
Var
  ViewH, MaxPos, RH: Integer;
Begin
  If (Not Assigned(FPaintBox)) Or (Not Assigned(FScrollBar)) Or (Not Assigned(FModel)) Then
    Exit;
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  RH := RowHeight;
  MaxPos := ContentHeight - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  FScrollBar.Min := 0;
  FScrollBar.SmallChange := RH;
  FScrollBar.LargeChange := ViewH;
  FScrollBar.PageSize := 0;
  FScrollBar.Max := MaxPos;
  If FScrollBar.Position > MaxPos Then
    FScrollBar.Position := MaxPos;
  FScrollBar.Enabled := MaxPos > 0;
End;

Function RefsIncludeHead(Const Refs: String): Boolean;
Var
  Token: String;
  Cursor, CommaAt, ArrowPos: Integer;
Begin
  Result := False;
  Cursor := 1;
  While Cursor <= Length(Refs) Do
    Begin
      CommaAt := Pos(',', Copy(Refs, Cursor, MaxInt));
      If CommaAt = 0 Then
        Begin
          Token := Trim(Copy(Refs, Cursor, MaxInt));
          Cursor := Length(Refs) + 1;
        End
      Else
        Begin
          Token := Trim(Copy(Refs, Cursor, CommaAt - 1));
          Cursor := Cursor + CommaAt;
        End;
      If Token = '' Then
        Continue;
      If SameText(Token, 'HEAD') Then
        Exit(True);
      ArrowPos := Pos(' -> ', Token);
      If (ArrowPos > 1) And SameText(Copy(Token, 1, ArrowPos - 1), 'HEAD') Then
        Exit(True);
    End;
End;

Function TManageHistoryGraph.CommitIsCheckedOut(Const CommitRec: TGitCommitRec): Boolean;
Begin
  If RefsIncludeHead(CommitRec.Refs) Then
    Exit(True);
  { Details that omit HEAD are authoritative. Until they arrive, trust the probe SHA. }
  If CommitRec.DetailsLoaded Then
    Exit(False);
  Result := (FHeadSha <> '') And SameText(CommitRec.Sha, FHeadSha);
End;

Function TManageHistoryGraph.StrokesNear(NodeX, NodeY, Reach: Single; Const Visible: TGitEdgeIndices; HalfWidth: Single): TSmoothStrokeArray;

  Function NearSegment(AX1, AY1, AX2, AY2: Single): Boolean;
  Var
    Dx, Dy, Len2, T, Px, Py: Single;
  Begin
    Dx := AX2 - AX1;
    Dy := AY2 - AY1;
    Len2 := Dx * Dx + Dy * Dy;
    If Len2 <= 0 Then
      Begin
        Px := NodeX - AX1;
        Py := NodeY - AY1;
        Result := Px * Px + Py * Py <= Reach * Reach;
        Exit;
      End;
    T := ((NodeX - AX1) * Dx + (NodeY - AY1) * Dy) / Len2;
    If T < 0 Then
      T := 0
    Else If T > 1 Then
      T := 1;
    Px := NodeX - (AX1 + T * Dx);
    Py := NodeY - (AY1 + T * Dy);
    Result := Px * Px + Py * Py <= Reach * Reach;
  End;

  Procedure AddStroke(AX1, AY1, AX2, AY2: Single; AColor: TColor);
  Var
    N: Integer;
  Begin
    If Not NearSegment(AX1, AY1, AX2, AY2) Then
      Exit;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].X1 := AX1;
    Result[N].Y1 := AY1;
    Result[N].X2 := AX2;
    Result[N].Y2 := AY2;
    Result[N].HalfWidth := HalfWidth;
    Result[N].Color := AColor;
  End;

Var
  I: Integer;
  E: TGitGraphEdge;
  X1, Y1, X2, Y2: Single;
  Col: TColor;
Begin
  Result := Nil;
  For I := 0 To High(Visible) Do
    Begin
      E := FModel.Edge(Visible[I]);
      X1 := LaneX(E.ChildLane);
      Y1 := RowMidY(E.ChildIndex);
      X2 := LaneX(E.ParentLane);
      Y2 := RowMidY(E.ParentIndex);
      Col := FLaneColors[FModel.LaneColorIndex(E.ChildLane)];
      If E.ChildLane = E.ParentLane Then
        AddStroke(X1, Y1, X2, Y2, Col)
      Else
        Begin
          AddStroke(X1, Y1, X1, Y2, Col);
          AddStroke(X1, Y2, X2, Y2, Col);
        End;
    End;
End;

Function HistoryRowFill(Selected: Boolean): TColor;
Begin
  If Selected Then
    Result := RGBToColor(227, 242, 253)
  Else
    Result := clWindow;
End;

Procedure TManageHistoryGraph.DrawRefCards(Const Refs: String; Var TextX: Integer; RowTop: Integer; RowColor: TColor);
Type
  TRefKind = (rkLocal, rkRemote, rkTag, rkCheckedOut, rkHead, rkOther);
Var
  Parts: TStringList;
  I, ArrowPos, CardW, CardH, CardY, PadX, Gap, MinW, RH, TextH: Integer;
  Token, RefName, HostFontName: String;
  Kind: TRefKind;
  Bg, Fg, Border: TColor;
Begin
  If (Trim(Refs) = '') Or (Not Assigned(FPaintBox)) Then
    Exit;
  HostFontName := 'default';
  If Assigned(FHost) Then
    HostFontName := FHost.Font.Name;

  Parts := TStringList.Create;
  Try
    Token := Refs;
    While Token <> '' Do
      Begin
        I := Pos(',', Token);
        If I = 0 Then
          Begin
            Parts.Add(Trim(Token));
            Break;
          End;
        Parts.Add(Trim(Copy(Token, 1, I - 1)));
        Token := Copy(Token, I + 1, MaxInt);
      End;

    RH := RowHeight;
    CardH := GraphScale(16);
    PadX := GraphScale(6);
    Gap := GraphScale(5);
    MinW := GraphScale(28);
    With FPaintBox.Canvas Do
      Begin
        Font.Name := HostFontName;
        Font.Size := 8;
        Font.Style := [];
        Font.Quality := fqCleartypeNatural;
        TextH := TextHeight('Ag');
      End;
    If CardH < TextH + GraphScale(4) Then
      CardH := TextH + GraphScale(4);
    If CardH > RH - GraphScale(2) Then
      CardH := Max(TextH, RH - GraphScale(2));
    CardY := RowTop + (RH - CardH) Div 2;

    For I := 0 To Parts.Count - 1 Do
      Begin
        Token := Trim(Parts[I]);
        If Token = '' Then
          Continue;
        ArrowPos := Pos(' -> ', Token);
        If ArrowPos > 0 Then
          Begin
            RefName := Trim(Copy(Token, ArrowPos + 4, MaxInt));
            If SameText(Copy(Token, 1, ArrowPos - 1), 'HEAD') Then
              Kind := rkCheckedOut
            Else
              Kind := rkLocal;
          End
        Else If SameText(Copy(Token, 1, 5), 'tag: ') Then
          Begin
            RefName := Trim(Copy(Token, 6, MaxInt));
            Kind := rkTag;
          End
        Else If SameText(Token, 'HEAD') Then
          Begin
            RefName := 'HEAD';
            Kind := rkHead;
          End
        Else
          Begin
            RefName := Token;
            If Pos('/', RefName) > 0 Then
              Kind := rkRemote
            Else
              Kind := rkLocal;
          End;
        If RefName = '' Then
          Continue;
        Case Kind Of
          rkLocal:
            Begin
              Bg := RGBToColor(227, 242, 253);
              Fg := RGBToColor(13, 71, 161);
              Border := RGBToColor(66, 165, 245);
            End;
          rkRemote:
            Begin
              Bg := RGBToColor(255, 243, 224);
              Fg := RGBToColor(230, 81, 0);
              Border := RGBToColor(255, 167, 38);
            End;
          rkTag:
            Begin
              Bg := RGBToColor(243, 229, 245);
              Fg := RGBToColor(106, 27, 154);
              Border := RGBToColor(186, 104, 200);
            End;
          rkCheckedOut:
            Begin
              Bg := RGBToColor(187, 222, 251);
              Fg := RGBToColor(13, 71, 161);
              Border := RGBToColor(21, 101, 192);
            End;
          rkHead:
            Begin
              Bg := RGBToColor(255, 236, 179);
              Fg := RGBToColor(93, 64, 55);
              Border := RGBToColor(245, 124, 0);
            End;
        Else
          Begin
            Bg := RGBToColor(245, 245, 245);
            Fg := RGBToColor(66, 66, 66);
            Border := RGBToColor(189, 189, 189);
          End;
        End;
        With FPaintBox.Canvas Do
          Begin
            Font.Name := HostFontName;
            Font.Size := 8;
            Font.Style := [];
            Font.Quality := fqCleartypeNatural;
            Font.Color := Fg;
            If (Kind = rkCheckedOut) Or (Kind = rkHead) Then
              Font.Style := [fsBold]
            Else
              Font.Style := [];
            CardW := TextWidth(RefName) + PadX * 2;
            If CardW < MinW Then
              CardW := MinW;
            DrawSmoothRoundRect(FPaintBox.Canvas, Rect(TextX, CardY, TextX + CardW, CardY + CardH), GraphScale(4), Bg, Border, RowColor);
            Brush.Style := bsClear;
            TextOut(TextX + PadX, CardY + (CardH - TextHeight(RefName)) Div 2, RefName);
            Brush.Style := bsSolid;
          End;
        TextX := TextX + CardW + Gap;
      End;
  Finally
    Parts.Free;
  End;
End;

Procedure TManageHistoryGraph.Paint;
Var
  FirstRow, LastRow, I, TextX, Y, X, Off, SubjectW, RH, DateColW, NodeR, Ring: Integer;
  TextH, TextY, EdgePenW, MsgPad, RingPenW, NodeY: Integer;
  MarkerRadius, RingInner, HalfStroke: Single;
  C: TGitCommitRec;
  E: TGitGraphEdge;
  Visible: TGitEdgeIndices;
  Strokes: TSmoothStrokeArray;
  Col: TColor;
  LabelText, DateText: String;
Begin
  If Not Assigned(FPaintBox) Then
    Exit;
  Off := ScrollOffset;
  RH := RowHeight;
  DateColW := GraphDateColumnWidth;
  NodeR := GraphNodeRadius;
  Ring := Max(2, GraphScale(2));
  RingPenW := Max(1, GraphScale(2));
  EdgePenW := Max(1, GraphScale(2));
  { One extra device pixel keeps the ring ramp off the marker and leaves the lane
    line visible between them. Coverage ramps are half a pixel, not DPI-scaled. }
  RingInner := NodeR + Ring + 1 - RingPenW / 2;
  MarkerRadius := NodeR;
  If MarkerRadius > RingInner - 1 Then
    MarkerRadius := RingInner - 1;
  If MarkerRadius < 1 Then
    MarkerRadius := 1;
  { Match the painted pen. A wider underlay bulges the circle where the line meets it. }
  HalfStroke := EdgePenW / 2;
  MsgPad := GraphScale(16);
  With FPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(FPaintBox.ClientRect);

      If FIndexing And ((Not Assigned(FModel)) Or (FModel.Count = 0)) Then
        Begin
          PrepareGraphTextFont(FPaintBox.Canvas, False);
          Font.Color := clGrayText;
          Font.Size := 11;
          TextOut(MsgPad, MsgPad, 'Indexing commit history…');
          Exit;
        End;

      If (Not Assigned(FModel)) Or (FModel.Count = 0) Then
        Begin
          PrepareGraphTextFont(FPaintBox.Canvas, False);
          Font.Color := clGrayText;
          Font.Size := 11;
          If FRepoPath = '' Then
            TextOut(MsgPad, MsgPad, 'No Git repository detected for the active project')
          Else
            TextOut(MsgPad, MsgPad, 'No commits to display');
          Exit;
        End;

      GetVisibleRange(FirstRow, LastRow);
      If LastRow < FirstRow Then
        Exit;

      If (FSelectedIndex >= FirstRow) And (FSelectedIndex <= LastRow) Then
        Begin
          Y := FSelectedIndex * RH - Off;
          Brush.Color := HistoryRowFill(True);
          FillRect(Bounds(0, Y, FPaintBox.ClientWidth, RH));
        End;

      Pen.Width := EdgePenW;
      Visible := FModel.VisibleEdges(FirstRow, LastRow);
      For I := 0 To High(Visible) Do
        Begin
          E := FModel.Edge(Visible[I]);
          If (E.ChildIndex > LastRow) Or (E.ParentIndex < FirstRow) Then
            Continue;
          Col := FLaneColors[FModel.LaneColorIndex(E.ChildLane)];
          Pen.Color := Col;
          X := LaneX(E.ChildLane);
          If E.ChildLane = E.ParentLane Then
            Line(X, RowMidY(E.ChildIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex))
          Else
            Begin
              Line(X, RowMidY(E.ChildIndex), X, RowMidY(E.ParentIndex));
              Line(X, RowMidY(E.ParentIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex));
            End;
        End;

      For I := FirstRow To LastRow Do
        Begin
          C := FModel.Commit(I);
          Y := I * RH - Off;
          Col := FLaneColors[FModel.LaneColorIndex(C.Lane)];
          X := LaneX(C.Lane);
          NodeY := RowMidY(I);
          Strokes := StrokesNear(X, NodeY, MarkerRadius + HalfStroke, Visible, HalfStroke);
          { Ring first, then the same disk as every other row, so the ring mask cannot clip this marker. }
          If CommitIsCheckedOut(C) Then
            DrawSmoothRing(FPaintBox.Canvas, X, NodeY, NodeR + Ring + 1, RingPenW, clWindowText,
              HistoryRowFill(I = FSelectedIndex), Strokes);
          DrawSmoothDisk(FPaintBox.Canvas, X, NodeY, MarkerRadius, Col, HistoryRowFill(I = FSelectedIndex), Strokes);

          TextX := GraphContentWidth + GraphTextGap;
          Brush.Style := bsClear;
          PrepareGraphTextFont(FPaintBox.Canvas, True);
          DateText := FormatCommitDate(C.CommitTime);
          TextH := TextHeight(DateText);
          TextY := Y + (RH - TextH) Div 2;
          TextOut(TextX, TextY, DateText);

          TextX := TextX + DateColW;
          PrepareGraphTextFont(FPaintBox.Canvas, False);
          If CommitIsCheckedOut(C) Then
            Font.Style := [fsBold];
          If C.DetailsLoaded Then
            LabelText := C.Subject
          Else
            LabelText := '…';
          TextH := TextHeight(LabelText);
          TextY := Y + (RH - TextH) Div 2;
          TextOut(TextX, TextY, LabelText);
          SubjectW := TextWidth(LabelText);
          TextX := TextX + SubjectW + GraphScale(8);
          Brush.Style := bsSolid;
          If C.DetailsLoaded And (C.Refs <> '') Then
            DrawRefCards(C.Refs, TextX, Y, HistoryRowFill(I = FSelectedIndex));
        End;
    End;
End;

End.
