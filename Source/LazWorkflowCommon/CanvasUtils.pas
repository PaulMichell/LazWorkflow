Unit CanvasUtils;

{ Anti-aliased canvas drawing (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Graphics, IntfGraphics, Types;

Type
  { A straight stroke already painted under a smooth shape. The fringe blends with Color
    where a sample lies inside the stroke, so the shape does not erase the line. }
  TSmoothStroke = Record
    X1, Y1, X2, Y2: Single;
    HalfWidth: Single;
    Color: TColor;
  End;
  TSmoothStrokeArray = Array Of TSmoothStroke;

/// Draws a symmetric rounded rectangle. Blend against Background, the colour just painted under Bounds.
/// The first paint cannot read those pixels: a canvas read comes back black and darkens the edge.
/// Rasterised into an opaque RGB bitmap and copied once (Cocoa-safe; no mask, no alpha channel needed).
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor;
  PixelScale: Single = 1);

/// Draws an antialiased disk over what is already painted. Radius is the 50% edge.
/// Uses the same coverage grid as DrawSmoothRing. Uncovered pixels use alpha 0 so paths remain.
/// Partial pixels blend against Background, or against a stroke when the sample lies on one.
/// Do not read the canvas: a read comes back black and darkens the edge.
/// Drawn via an 8-bit alpha bitmap (not a 1-bit mask): Cocoa ignores masks on plain Draw.
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill, Background: TColor;
  Const Strokes: TSmoothStrokeArray = Nil; PixelScale: Single = 1);

/// Draws an antialiased ring over what is already painted. Radius is the stroke centreline.
/// StrokeWidth is the full thickness. Uncovered pixels use alpha 0 so lane dots and paths remain.
/// Partial pixels blend against Background, or against a stroke when the sample lies on one.
/// Do not read the canvas: a read comes back black and darkens the edge.
/// Drawn via an 8-bit alpha bitmap (not a 1-bit mask): Cocoa ignores masks on plain Draw.
/// PixelScale is the control canvas scale (Retina 2). Values <= 1 keep a 1x buffer.
Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke, Background: TColor;
  Const Strokes: TSmoothStrokeArray = Nil; PixelScale: Single = 1);

/// Rasterises the image DrawSmoothRoundRect copies for a LogicalW x LogicalH rectangle. Image is resized to the
/// backing size. Returns False, leaving Image unchanged, when the rectangle is too small to draw.
/// SkipUniform False supersamples every pixel; tests compare it with the default, which must match exactly.
Function RenderSmoothRoundRect(Image: TLazIntfImage; LogicalW, LogicalH: Integer; Radius: Single;
  Fill, Border, Background: TColor; PixelScale: Single; SkipUniform: Boolean = True): Boolean;

/// Rasterises the image DrawSmoothDisk (InnerRadius < 0) or DrawSmoothRing (the band between the radii) copies.
/// Image needs an alpha channel and is resized to the backing size; Dest receives the logical rectangle it covers.
/// Returns False when nothing is drawn. SkipUniform False supersamples every pixel, as for RenderSmoothRoundRect.
Function RenderCoverageCircle(Image: TLazIntfImage; CentreX, CentreY, OuterRadius, InnerRadius: Single;
  Edge, Background: TColor; Const Strokes: TSmoothStrokeArray; PixelScale: Single; Out Dest: TRect;
  SkipUniform: Boolean = True): Boolean;

Implementation

Uses
  fpimage, GraphType, Math;

Const
  { Full width of the coverage ramp of a disk or ring, in physical pixels. }
  SmoothCoverageWidth = 0.5;
  { Half a pixel diagonal, rounded up. No supersample lies farther than this from its pixel centre. }
  PixelReach = 0.7072;
  { An uncovered disk or ring pixel. }
  ClearPixel: TFPColor = (Red: 0; Green: 0; Blue: 0; Alpha: 0);

Function ClampSmoothScale(Scale: Single): Single;
Begin
  If Scale < 1 Then
    Result := 1
  Else If Scale > 4 Then
    Result := 4
  Else
    Result := Scale;
End;

{ Distance is a pixel centre's signed distance from a coverage edge, positive outside, and HalfRamp is half the width
  of that edge's coverage ramp. The distance must change no faster than position does, as a true distance does.
  True when every sample in the pixel then has the same coverage, 0 or 1, returned in Coverage. }
Function UniformCoverage(Distance, HalfRamp: Single; Out Coverage: Single): Boolean;
Begin
  Result := True;
  If Distance > HalfRamp + PixelReach Then
    Coverage := 0
  Else If Distance < -(HalfRamp + PixelReach) Then
    Coverage := 1
  Else
    Begin
      Coverage := 0;
      Result := False;
    End;
End;

Procedure BlitSmoothImage(Target: TCanvas; Const Dest: TRect; Image: TLazIntfImage; Scale: Single);
Var
  Bitmap: TBitmap;
Begin
  Bitmap := TBitmap.Create;
  Try
    Bitmap.LoadFromIntfImage(Image);
    Bitmap.Transparent := False;
    If Abs(Scale - 1) <= 1E-3 Then
      Target.Draw(Dest.Left, Dest.Top, Bitmap)
    Else
      Target.StretchDraw(Dest, Bitmap);
  Finally
    Bitmap.Free;
  End;
End;

Function RenderSmoothRoundRect(Image: TLazIntfImage; LogicalW, LogicalH: Integer; Radius: Single;
  Fill, Border, Background: TColor; PixelScale: Single; SkipUniform: Boolean): Boolean;

  Function Clamp01(Value: Single): Single;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 1 Then
      Result := 1
    Else
      Result := Value;
  End;

  Function ClampChannel(Value: Single): Word;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 65535 Then
      Result := 65535
    Else
      Result := Round(Value);
  End;

  Function MaxSingle(A, B: Single): Single;
  Begin
    If A > B Then
      Result := A
    Else
      Result := B;
  End;

  Function MinSingle(A, B: Single): Single;
  Begin
    If A < B Then
      Result := A
    Else
      Result := B;
  End;

  { The exact signed distance from a rounded box, so it changes no faster than position does. }
  Function RoundRectDistance(PX, PY, HalfW, HalfH, CornerRadius: Single): Single;
  Var
    QX, QY, AX, AY: Single;
  Begin
    QX := Abs(PX) - HalfW + CornerRadius;
    QY := Abs(PY) - HalfH + CornerRadius;
    AX := MaxSingle(QX, 0);
    AY := MaxSingle(QY, 0);
    Result := MinSingle(MaxSingle(QX, QY), 0) + Sqrt(AX * AX + AY * AY) - CornerRadius;
  End;

  Function ColorToFP(C: TColor): TFPColor;
  Var
    RGB: TColor;
  Begin
    RGB := ColorToRGB(C);
    Result.Red := Word(RGB And $FF) * 257;
    Result.Green := Word((RGB Shr 8) And $FF) * 257;
    Result.Blue := Word((RGB Shr 16) And $FF) * 257;
    Result.Alpha := 65535;
  End;

  Function MixCoverage(Const Back, Edge, Inside: TFPColor; Outer, Inner: Single): TFPColor;
  Var
    BackWeight, EdgeWeight: Single;
  Begin
    BackWeight := 1 - Outer;
    EdgeWeight := Outer - Inner;
    Result.Red := ClampChannel(Back.Red * BackWeight + Edge.Red * EdgeWeight + Inside.Red * Inner);
    Result.Green := ClampChannel(Back.Green * BackWeight + Edge.Green * EdgeWeight + Inside.Green * Inner);
    Result.Blue := ClampChannel(Back.Blue * BackWeight + Edge.Blue * EdgeWeight + Inside.Blue * Inner);
    Result.Alpha := 65535;
  End;

Var
  PhysW, PhysH, X, Y, SampleX, SampleY: Integer;
  Scale, CX, CY, HalfW, HalfH, UsedRadius, BorderWidth, SD, Outer, Inner, OuterSum, InnerSum: Single;
  FillColor, BorderColor, BackColor: TFPColor;
Begin
  Result := False;
  If (Not Assigned(Image)) Or (LogicalW < 2) Or (LogicalH < 2) Then
    Exit;
  Scale := ClampSmoothScale(PixelScale);
  PhysW := Max(2, Ceil(LogicalW * Scale - 1E-6));
  PhysH := Max(2, Ceil(LogicalH * Scale - 1E-6));
  HalfW := PhysW / 2;
  HalfH := PhysH / 2;
  UsedRadius := Radius * Scale;
  If UsedRadius > MinSingle(HalfW, HalfH) - Scale Then
    UsedRadius := MinSingle(HalfW, HalfH) - Scale;
  If UsedRadius < Scale Then
    UsedRadius := Scale;
  { One logical pixel of border, in physical samples. }
  BorderWidth := Scale;
  CX := PhysW / 2;
  CY := PhysH / 2;
  FillColor := ColorToFP(Fill);
  BorderColor := ColorToFP(Border);
  BackColor := ColorToFP(Background);
  { Rasterise at backing resolution so Retina does not upscale a soft 1x fringe. }
  Image.SetSize(PhysW, PhysH);
  For Y := 0 To PhysH - 1 Do
    For X := 0 To PhysW - 1 Do
      Begin
        { A pixel well clear of both edges has one coverage throughout; its 16 samples would all agree. }
        SD := RoundRectDistance(X + 0.5 - CX, Y + 0.5 - CY, HalfW, HalfH, UsedRadius);
        If Not (SkipUniform And UniformCoverage(SD, 0.5, Outer) And UniformCoverage(SD + BorderWidth, 0.5, Inner)) Then
          Begin
            OuterSum := 0;
            InnerSum := 0;
            For SampleY := 0 To 3 Do
              For SampleX := 0 To 3 Do
                Begin
                  SD := RoundRectDistance(
                    (X + (SampleX + 0.5) / 4) - CX,
                    (Y + (SampleY + 0.5) / 4) - CY,
                    HalfW, HalfH, UsedRadius);
                  OuterSum := OuterSum + Clamp01(0.5 - SD);
                  InnerSum := InnerSum + Clamp01(0.5 - (SD + BorderWidth));
                End;
            Outer := OuterSum / 16;
            Inner := InnerSum / 16;
          End;
        Image.Colors[X, Y] := MixCoverage(BackColor, BorderColor, FillColor, Outer, Inner);
      End;
  Result := True;
End;

Procedure DrawSmoothRoundRect(Target: TCanvas; Const Bounds: TRect; Radius: Single; Fill, Border, Background: TColor;
  PixelScale: Single);
Var
  Image: TLazIntfImage;
Begin
  If Not Assigned(Target) Then
    Exit;
  { Every pixel is opaque, so the image needs no alpha channel and draws on any widgetset. }
  Image := TLazIntfImage.Create(0, 0, [riqfRGB]);
  Try
    If RenderSmoothRoundRect(Image, Bounds.Right - Bounds.Left, Bounds.Bottom - Bounds.Top, Radius, Fill, Border,
      Background, PixelScale) Then
      BlitSmoothImage(Target, Bounds, Image, ClampSmoothScale(PixelScale));
  Finally
    Image.Free;
  End;
End;

{ InnerRadius < 0 fills a disk of OuterRadius. Otherwise the stroke is the band between the two radii.
  Both shapes use one 8x8 coverage grid so a lane dot cannot be softer or harder than the checkout ring.
  Strokes supply the colour already painted under the shape. A canvas read cannot: it comes back black.
  Geometry is logical; PixelScale rasterises at backing resolution. }
Function RenderCoverageCircle(Image: TLazIntfImage; CentreX, CentreY, OuterRadius, InnerRadius: Single;
  Edge, Background: TColor; Const Strokes: TSmoothStrokeArray; PixelScale: Single; Out Dest: TRect;
  SkipUniform: Boolean): Boolean;

  Function Clamp01(Value: Single): Single;
  Begin
    If Value <= 0 Then
      Result := 0
    Else If Value >= 1 Then
      Result := 1
    Else
      Result := Value;
  End;

  Function MixChannel(Base, Over, Coverage: Single): Single;
  Begin
    Result := Base + (Over - Base) * Coverage;
  End;

  Function AverageChannel(Sum: Single; Count: Integer): Word;
  Var
    Value: Single;
  Begin
    Value := Sum / Count;
    If Value <= 0 Then
      Result := 0
    Else If Value >= 65535 Then
      Result := 65535
    Else
      Result := Round(Value);
  End;

  Function SampleCoverage(Dist, OuterR, InnerR: Single): Single;

    Function EdgeCoverage(Edge: Single): Single;
    Begin
      Result := Clamp01((Edge + SmoothCoverageWidth / 2 - Dist) / SmoothCoverageWidth);
    End;

  Begin
    If InnerR < 0 Then
      Result := EdgeCoverage(OuterR)
    Else
      Begin
        Result := EdgeCoverage(OuterR) - EdgeCoverage(InnerR);
        If Result < 0 Then
          Result := 0;
      End;
  End;

  Function UnderColor(SampleX, SampleY: Single; Const Base: TFPColor): TFPColor;
  Var
    S: Integer;
    SegX, SegY, Len2, T, Px, Py, Limit: Single;
  Begin
    Result := Base;
    For S := 0 To High(Strokes) Do
      Begin
        Limit := Strokes[S].HalfWidth * PixelScale;
        If Limit <= 0 Then
          Continue;
        SegX := (Strokes[S].X2 - Strokes[S].X1) * PixelScale;
        SegY := (Strokes[S].Y2 - Strokes[S].Y1) * PixelScale;
        Len2 := SegX * SegX + SegY * SegY;
        If Len2 <= 0 Then
          Begin
            Px := SampleX - Strokes[S].X1 * PixelScale;
            Py := SampleY - Strokes[S].Y1 * PixelScale;
          End
        Else
          Begin
            T := ((SampleX - Strokes[S].X1 * PixelScale) * SegX +
              (SampleY - Strokes[S].Y1 * PixelScale) * SegY) / Len2;
            If T < 0 Then
              T := 0
            Else If T > 1 Then
              T := 1;
            Px := SampleX - (Strokes[S].X1 * PixelScale + T * SegX);
            Py := SampleY - (Strokes[S].Y1 * PixelScale + T * SegY);
          End;
        If Px * Px + Py * Py <= Limit * Limit Then
          Exit(TColorToFPColor(ColorToRGB(Strokes[S].Color)));
      End;
  End;

Var
  Scale: Single;
  Left, Top, Right, Bottom, PhysW, PhysH, X, Y, SampleX, SampleY, SampleGrid, Samples, MaxExtent: Integer;
  SampleScale, Dx, Dy, Dist, Coverage, CoverageSum, SampleXPos, SampleYPos: Single;
  PhysCentreX, PhysCentreY, PhysOuter, PhysInner, Pad, OuterCoverage, InnerCoverage: Single;
  SumR, SumG, SumB: Single;
  EdgeColor, BackColor, Under, Pixel: TFPColor;
Begin
  Result := False;
  Dest := Rect(0, 0, 0, 0);
  If (Not Assigned(Image)) Or (OuterRadius <= 0) Then
    Exit;
  If Image.DataDescription.AlphaPrec < 1 Then
    Exit;
  { Nested stroke tests read PixelScale; keep it clamped for the whole body. }
  PixelScale := ClampSmoothScale(PixelScale);
  Scale := PixelScale;
  Pad := SmoothCoverageWidth / 2;
  Left := Floor(CentreX - OuterRadius - Pad);
  Top := Floor(CentreY - OuterRadius - Pad);
  Right := Ceil(CentreX + OuterRadius + Pad);
  Bottom := Ceil(CentreY + OuterRadius + Pad);
  PhysW := Max(2, Ceil((Right - Left) * Scale - 1E-6));
  PhysH := Max(2, Ceil((Bottom - Top) * Scale - 1E-6));
  MaxExtent := Max(256, Ceil(256 * Scale));
  If (PhysW > MaxExtent) Or (PhysH > MaxExtent) Then
    Exit;
  Dest := Rect(Left, Top, Right, Bottom);
  PhysCentreX := (CentreX - Left) * Scale;
  PhysCentreY := (CentreY - Top) * Scale;
  PhysOuter := OuterRadius * Scale;
  If InnerRadius < 0 Then
    PhysInner := -1
  Else
    PhysInner := InnerRadius * Scale;
  EdgeColor := TColorToFPColor(ColorToRGB(Edge));
  BackColor := TColorToFPColor(ColorToRGB(Background));
  SampleGrid := 8;
  Samples := SampleGrid * SampleGrid;
  SampleScale := 1 / SampleGrid;
  Image.SetSize(PhysW, PhysH);
  For Y := 0 To PhysH - 1 Do
    For X := 0 To PhysW - 1 Do
      Begin
        { A pixel well clear of every edge has one coverage throughout. Fully covered samples all take the edge
          colour, whatever lies under them, and uncovered ones leave the pixel transparent. }
        Dx := X + 0.5 - PhysCentreX;
        Dy := Y + 0.5 - PhysCentreY;
        Dist := Sqrt(Dx * Dx + Dy * Dy);
        If SkipUniform And UniformCoverage(Dist - PhysOuter, Pad, OuterCoverage) And
          ((PhysInner < 0) Or UniformCoverage(Dist - PhysInner, Pad, InnerCoverage)) Then
          Begin
            If PhysInner < 0 Then
              InnerCoverage := 0;
            If OuterCoverage > InnerCoverage Then
              Begin
                Pixel := EdgeColor;
                Pixel.Alpha := 65535;
              End
            Else
              Pixel := ClearPixel;
            Image.Colors[X, Y] := Pixel;
            Continue;
          End;
        SumR := 0;
        SumG := 0;
        SumB := 0;
        CoverageSum := 0;
        For SampleY := 0 To SampleGrid - 1 Do
          For SampleX := 0 To SampleGrid - 1 Do
            Begin
              SampleXPos := X + (SampleX + 0.5) * SampleScale;
              SampleYPos := Y + (SampleY + 0.5) * SampleScale;
              Dx := SampleXPos - PhysCentreX;
              Dy := SampleYPos - PhysCentreY;
              Dist := Sqrt(Dx * Dx + Dy * Dy);
              Coverage := SampleCoverage(Dist, PhysOuter, PhysInner);
              CoverageSum := CoverageSum + Coverage;
              { Stroke tests use physical space with origin at the logical (0,0) scaled. }
              Under := UnderColor(SampleXPos + Left * Scale, SampleYPos + Top * Scale, BackColor);
              SumR := SumR + MixChannel(Under.Red, EdgeColor.Red, Coverage);
              SumG := SumG + MixChannel(Under.Green, EdgeColor.Green, Coverage);
              SumB := SumB + MixChannel(Under.Blue, EdgeColor.Blue, Coverage);
            End;
        If CoverageSum <= 0 Then
          Pixel := ClearPixel
        Else
          Begin
            Pixel.Red := AverageChannel(SumR, Samples);
            Pixel.Green := AverageChannel(SumG, Samples);
            Pixel.Blue := AverageChannel(SumB, Samples);
            Pixel.Alpha := 65535;
          End;
        Image.Colors[X, Y] := Pixel;
      End;
  Result := True;
End;

Procedure DrawCoverageCircle(Target: TCanvas; CentreX, CentreY, OuterRadius, InnerRadius: Single; Edge, Background: TColor;
  Const Strokes: TSmoothStrokeArray; PixelScale: Single);
Var
  Image: TLazIntfImage;
  Dest: TRect;
Begin
  If Not Assigned(Target) Then
    Exit;
  Image := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
  Try
    If RenderCoverageCircle(Image, CentreX, CentreY, OuterRadius, InnerRadius, Edge, Background, Strokes, PixelScale,
      Dest) Then
      BlitSmoothImage(Target, Dest, Image, ClampSmoothScale(PixelScale));
  Finally
    Image.Free;
  End;
End;

Procedure DrawSmoothDisk(Target: TCanvas; CentreX, CentreY, Radius: Single; Fill, Background: TColor;
  Const Strokes: TSmoothStrokeArray; PixelScale: Single);
Begin
  If Radius <= 0 Then
    Exit;
  DrawCoverageCircle(Target, CentreX, CentreY, Radius, -1, Fill, Background, Strokes, PixelScale);
End;

Procedure DrawSmoothRing(Target: TCanvas; CentreX, CentreY, Radius, StrokeWidth: Single; Stroke, Background: TColor;
  Const Strokes: TSmoothStrokeArray; PixelScale: Single);
Var
  OuterRadius, InnerRadius: Single;
Begin
  If (StrokeWidth <= 0) Or (Radius <= 0) Then
    Exit;
  OuterRadius := Radius + StrokeWidth / 2;
  InnerRadius := Radius - StrokeWidth / 2;
  If InnerRadius < 0 Then
    InnerRadius := 0;
  DrawCoverageCircle(Target, CentreX, CentreY, OuterRadius, InnerRadius, Stroke, Background, Strokes, PixelScale);
End;

End.
